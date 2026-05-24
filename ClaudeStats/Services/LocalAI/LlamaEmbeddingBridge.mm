#import "LlamaEmbeddingBridge.h"

#import <llama/llama.h>

#include <algorithm>
#include <cmath>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

static NSString * const LlamaEmbeddingBridgeErrorDomain = @"com.claudestats.LlamaEmbeddingBridge";

static NSError * LlamaError(NSInteger code, NSString * message) {
    return [NSError errorWithDomain:LlamaEmbeddingBridgeErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static void EnsureLlamaBackend() {
    static std::once_flag once;
    std::call_once(once, [] {
        llama_backend_init();
    });
}

@interface LlamaEmbeddingBridge ()
@property(nonatomic, assign) struct llama_model * model;
@property(nonatomic, assign) struct llama_context * context;
@property(nonatomic, assign) NSInteger dimensions;
@property(nonatomic, assign) NSInteger maxTokens;
@end

@implementation LlamaEmbeddingBridge

- (nullable instancetype)initWithModelPath:(NSString *)modelPath
                                dimensions:(NSInteger)dimensions
                                 maxTokens:(NSInteger)maxTokens
                                   pooling:(NSString *)pooling
                                  useMetal:(BOOL)useMetal
                                     error:(NSError **)error {
    self = [super init];
    if (!self) { return nil; }

    EnsureLlamaBackend();
    _dimensions = dimensions;
    _maxTokens = std::max<NSInteger>(32, maxTokens);

    llama_model_params modelParams = llama_model_default_params();
    modelParams.n_gpu_layers = useMetal ? -1 : 0;
    modelParams.use_mmap = true;

    _model = llama_model_load_from_file(modelPath.fileSystemRepresentation, modelParams);
    if (_model == nullptr) {
        if (error) { *error = LlamaError(1, @"Unable to load GGUF model."); }
        return nil;
    }

    llama_context_params contextParams = llama_context_default_params();
    contextParams.n_ctx = (uint32_t)_maxTokens;
    contextParams.n_batch = (uint32_t)_maxTokens;
    contextParams.n_ubatch = (uint32_t)_maxTokens;
    contextParams.n_seq_max = 1;
    contextParams.n_threads = (int32_t)std::max(2u, std::thread::hardware_concurrency() / 2);
    contextParams.n_threads_batch = (int32_t)std::max(2u, std::thread::hardware_concurrency());
    contextParams.embeddings = true;
    contextParams.pooling_type = [pooling isEqualToString:@"last"] ? LLAMA_POOLING_TYPE_LAST : LLAMA_POOLING_TYPE_MEAN;
    contextParams.attention_type = [pooling isEqualToString:@"last"] ? LLAMA_ATTENTION_TYPE_UNSPECIFIED : LLAMA_ATTENTION_TYPE_NON_CAUSAL;

    _context = llama_init_from_model(_model, contextParams);
    if (_context == nullptr) {
        llama_model_free(_model);
        _model = nullptr;
        if (error) { *error = LlamaError(2, @"Unable to initialize llama context."); }
        return nil;
    }

    int32_t actualDimensions = llama_model_n_embd_out(_model);
    if (actualDimensions > 0) {
        _dimensions = actualDimensions;
    }
    return self;
}

- (void)dealloc {
    if (_context != nullptr) {
        llama_free(_context);
        _context = nullptr;
    }
    if (_model != nullptr) {
        llama_model_free(_model);
        _model = nullptr;
    }
}

- (nullable NSArray<NSArray<NSNumber *> *> *)embedTexts:(NSArray<NSString *> *)texts
                                                  error:(NSError **)error {
    if (_model == nullptr || _context == nullptr) {
        if (error) { *error = LlamaError(3, @"llama runtime is not initialized."); }
        return nil;
    }

    NSMutableArray<NSArray<NSNumber *> *> * output = [NSMutableArray arrayWithCapacity:texts.count];
    for (NSString * text in texts) {
        @autoreleasepool {
            NSArray<NSNumber *> * vector = [self embedText:text error:error];
            if (!vector) { return nil; }
            [output addObject:vector];
        }
    }
    return output;
}

- (nullable NSArray<NSNumber *> *)embedText:(NSString *)text error:(NSError **)error {
    const llama_vocab * vocab = llama_model_get_vocab(_model);
    std::string input(text.UTF8String ?: "");
    int32_t tokenCapacity = std::max<int32_t>((int32_t)input.size() + 8, 32);
    std::vector<llama_token> tokens(tokenCapacity);
    int32_t tokenCount = llama_tokenize(
        vocab,
        input.c_str(),
        (int32_t)input.size(),
        tokens.data(),
        (int32_t)tokens.size(),
        true,
        true
    );
    if (tokenCount < 0) {
        tokenCapacity = -tokenCount;
        tokens.assign(tokenCapacity, 0);
        tokenCount = llama_tokenize(
            vocab,
            input.c_str(),
            (int32_t)input.size(),
            tokens.data(),
            (int32_t)tokens.size(),
            true,
            true
        );
    }
    if (tokenCount <= 0) {
        if (error) { *error = LlamaError(4, @"Unable to tokenize text."); }
        return nil;
    }
    if (tokenCount > _maxTokens) {
        tokens.resize(_maxTokens);
        tokenCount = (int32_t)_maxTokens;
    } else {
        tokens.resize(tokenCount);
    }

    llama_batch batch = llama_batch_init(tokenCount, 0, 1);
    batch.n_tokens = tokenCount;
    for (int32_t i = 0; i < tokenCount; i++) {
        batch.token[i] = tokens[i];
        batch.pos[i] = i;
        batch.n_seq_id[i] = 1;
        batch.seq_id[i][0] = 0;
        batch.logits[i] = 1;
    }

    llama_memory_clear(llama_get_memory(_context), true);
    int32_t decodeResult = llama_decode(_context, batch);
    llama_batch_free(batch);
    if (decodeResult < 0) {
        if (error) { *error = LlamaError(5, @"llama_decode failed while embedding text."); }
        return nil;
    }

    const float * embedding = llama_get_embeddings_seq(_context, 0);
    if (embedding == nullptr) {
        embedding = llama_get_embeddings_ith(_context, -1);
    }
    if (embedding == nullptr) {
        if (error) { *error = LlamaError(6, @"llama did not return an embedding vector."); }
        return nil;
    }

    NSInteger count = _dimensions;
    double norm = 0;
    for (NSInteger i = 0; i < count; i++) {
        norm += (double)embedding[i] * (double)embedding[i];
    }
    norm = std::sqrt(norm);
    if (norm <= 0) { norm = 1; }

    NSMutableArray<NSNumber *> * values = [NSMutableArray arrayWithCapacity:count];
    for (NSInteger i = 0; i < count; i++) {
        [values addObject:@((float)(embedding[i] / norm))];
    }
    return values;
}

@end
