#import <Foundation/Foundation.h>
#import "WineContainer.h"

NS_ASSUME_NONNULL_BEGIN

@class ExecutionEngine;

@protocol ExecutionEngineDelegate <NSObject>
- (void)executionEngine:(ExecutionEngine *)engine didStartProgram:(NSString *)programPath;
- (void)executionEngine:(ExecutionEngine *)engine didFinishProgram:(NSString *)programPath withExitCode:(int)exitCode;
- (void)executionEngine:(ExecutionEngine *)engine didEncounterError:(NSError *)error;
- (void)executionEngine:(ExecutionEngine *)engine didReceiveOutput:(NSString *)output;
@end

@interface ExecutionEngine : NSObject

@property (nonatomic, weak) id<ExecutionEngineDelegate> delegate;
@property (nonatomic, strong, readonly) WineContainer *container;
@property (nonatomic, readonly) BOOL isRunning;

- (instancetype)initWithContainer:(WineContainer *)container;
- (void)loadExecutable:(NSString *)exePath;
- (void)startExecution;
- (void)stopExecution;

@end

NS_ASSUME_NONNULL_END
