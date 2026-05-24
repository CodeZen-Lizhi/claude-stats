#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LlamaEmbeddingBridge : NSObject

- (nullable instancetype)initWithModelPath:(NSString *)modelPath
                                dimensions:(NSInteger)dimensions
                                 maxTokens:(NSInteger)maxTokens
                                   pooling:(NSString *)pooling
                                  useMetal:(BOOL)useMetal
                                     error:(NSError **)error;

- (nullable NSArray<NSArray<NSNumber *> *> *)embedTexts:(NSArray<NSString *> *)texts
                                                  error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
