#import "CppJiebaTokenizerBridge.h"

#include <memory>
#include <string>
#include <vector>

#include "cppjieba/Jieba.hpp"

@implementation CppJiebaTokenizerBridge {
    std::unique_ptr<cppjieba::Jieba> _tokenizer;
}

- (nullable instancetype)initWithDictionaryDirectory:(NSString *)dictionaryDirectory
                                  userDictionaryPath:(nullable NSString *)userDictionaryPath {
    self = [super init];
    if (!self) { return nil; }

    NSString *dictPath = [dictionaryDirectory stringByAppendingPathComponent:@"jieba.dict.utf8"];
    NSString *hmmPath = [dictionaryDirectory stringByAppendingPathComponent:@"hmm_model.utf8"];
    NSString *idfPath = [dictionaryDirectory stringByAppendingPathComponent:@"idf.utf8"];
    NSString *stopWordsPath = [dictionaryDirectory stringByAppendingPathComponent:@"stop_words.utf8"];
    NSString *defaultUserPath = [dictionaryDirectory stringByAppendingPathComponent:@"user.dict.utf8"];
    NSString *userPath = userDictionaryPath.length > 0 ? userDictionaryPath : defaultUserPath;

    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSArray<NSString *> *required = @[dictPath, hmmPath, userPath, idfPath, stopWordsPath];
    for (NSString *path in required) {
        if (![fileManager fileExistsAtPath:path]) {
            return nil;
        }
    }

    _tokenizer = std::make_unique<cppjieba::Jieba>(
        dictPath.UTF8String,
        hmmPath.UTF8String,
        userPath.UTF8String,
        idfPath.UTF8String,
        stopWordsPath.UTF8String
    );

    return self;
}

- (NSArray<NSString *> *)cut:(NSString *)text hmm:(BOOL)hmm forSearch:(BOOL)forSearch {
    if (!_tokenizer || text.length == 0) { return @[]; }

    std::vector<std::string> words;
    std::string input(text.UTF8String ?: "");
    if (forSearch) {
        _tokenizer->CutForSearch(input, words, hmm);
    } else {
        _tokenizer->Cut(input, words, hmm);
    }

    NSMutableArray<NSString *> *result = [NSMutableArray arrayWithCapacity:words.size()];
    for (const auto &word : words) {
        NSString *string = [NSString stringWithUTF8String:word.c_str()];
        if (string.length > 0) {
            [result addObject:string];
        }
    }
    return result;
}

- (void)insertUserWords:(NSArray<NSString *> *)words {
    if (!_tokenizer) { return; }
    for (NSString *word in words) {
        NSString *trimmed = [word stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (trimmed.length == 0) { continue; }
        _tokenizer->InsertUserWord(std::string(trimmed.UTF8String ?: ""), 1000000);
    }
}

@end
