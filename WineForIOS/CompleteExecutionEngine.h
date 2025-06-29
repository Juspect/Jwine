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
    ExecutionResultInitError = -4,
    
    // 新增的枚举值
    ExecutionResultNotInitialized = -5,
    ExecutionResultAlreadyExecuting = -6,
    ExecutionResultTimeout = -7,
    ExecutionResultSecurityError = -8,
    ExecutionResultExecutionError = -9,
    ExecutionResultSecurityWarning = -10,
    ExecutionResultCrash = -11
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
- (BOOL)initializeEngines;  // 修改方法名以匹配实现
- (void)cleanup;

// 程序执行
- (void)executeProgram:(NSString *)programPath;  // 修改为异步执行
- (void)stopExecution;

// 系统状态
- (NSDictionary *)getSystemInfo;
- (NSString *)getEngineStatus;
- (NSArray<NSString *> *)getExecutionLog;  // 新增方法
- (void)dumpAllStates;

@end

NS_ASSUME_NONNULL_END
