#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CppJiebaTokenizerBridge : NSObject

- (nullable instancetype)initWithDictionaryDirectory:(NSString *)dictionaryDirectory
                                  userDictionaryPath:(nullable NSString *)userDictionaryPath;
- (NSArray<NSString *> *)cut:(NSString *)text hmm:(BOOL)hmm forSearch:(BOOL)forSearch;
- (void)insertUserWords:(NSArray<NSString *> *)words;

@end

NS_ASSUME_NONNULL_END
