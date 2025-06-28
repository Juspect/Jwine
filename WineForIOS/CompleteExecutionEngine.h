#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "IOSJITEngine.h"
#import "Box64Engine.h"
#import "WineAPI.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ExecutionResult) {
    ExecutionResultSuccess = 0,
    ExecutionResultFailure = -1,
    ExecutionResultInvalidFile = -2,
    ExecutionResultMemoryError = -3,
    ExecutionResultInitError = -4
};

@class CompleteExecutionEngine;

@protocol CompleteExecutionEngineDelegate <NSObject>
@optional
- (void)executionEngine:(CompleteExecutionEngine *)engine didStartExecution:(NSString *)programPath;
- (void)executionEngine:(CompleteExecutionEngine *)engine didFinishExecution:(NSString *)programPath result:(ExecutionResult)result;
- (void)executionEngine:(CompleteExecutionEngine *)engine didReceiveOutput:(NSString *)output;
- (void)executionEngine:(CompleteExecutionEngine *)engine didEncounterError:(NSError *)error;
- (void)executionEngine:(CompleteExecutionEngine *)engine didUpdateProgress:(float)progress status:(NSString *)status;
@end

@interface CompleteExecutionEngine : NSObject

@property (nonatomic, weak) id<CompleteExecutionEngineDelegate> delegate;
@property (nonatomic, weak) UIViewController *hostViewController;
@property (nonatomic, readonly) BOOL isInitialized;
@property (nonatomic, readonly) BOOL isExecuting;

+ (instancetype)sharedEngine;

// 初始化和配置
- (BOOL)initializeWithViewController:(UIViewController *)viewController;
- (void)cleanup;

// 程序执行
- (ExecutionResult)executeProgram:(NSString *)exePath;
- (ExecutionResult)executeProgram:(NSString *)exePath arguments:(nullable NSArray<NSString *> *)arguments;
- (void)stopExecution;

// 系统状态
- (NSDictionary *)getSystemInfo;
- (NSString *)getEngineStatus;
- (void)dumpAllStates;

@end

NS_ASSUME_NONNULL_END
