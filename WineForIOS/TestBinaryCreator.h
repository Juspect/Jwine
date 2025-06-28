#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TestBinaryCreator : NSObject

+ (instancetype)sharedCreator;

// 创建简单的测试PE文件
- (NSData *)createSimpleTestPE;
- (NSData *)createCalculatorTestPE;
- (NSData *)createHelloWorldPE;

// 保存测试文件到Documents目录
- (NSString *)saveTestPEToDocuments:(NSString *)filename data:(NSData *)peData;

// 创建完整的测试环境
- (void)createAllTestFiles;

@end

NS_ASSUME_NONNULL_END

