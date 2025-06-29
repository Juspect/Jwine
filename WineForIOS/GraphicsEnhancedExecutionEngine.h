// GraphicsEnhancedExecutionEngine.h - 图形增强执行引擎
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "CompleteExecutionEngine.h"
#import "MoltenVKBridge.h"
#import "EnhancedBox64Instructions.h"
#import "WineAPI.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, GraphicsExecutionResult) {
    GraphicsExecutionResultSuccess = 0,
    GraphicsExecutionResultFailure = -1,
    GraphicsExecutionResultInvalidFile = -2,
    GraphicsExecutionResultGraphicsError = -3,
    GraphicsExecutionResultInstructionError = -4
};

@class GraphicsEnhancedExecutionEngine;

@protocol GraphicsEnhancedExecutionEngineDelegate <NSObject>
@optional
- (void)graphicsEngine:(GraphicsEnhancedExecutionEngine * _Nonnull)engine
       didStartExecution:(NSString * _Nonnull)programPath;

- (void)graphicsEngine:(GraphicsEnhancedExecutionEngine * _Nonnull)engine
      didFinishExecution:(NSString * _Nonnull)programPath
                  result:(GraphicsExecutionResult)result;

- (void)graphicsEngine:(GraphicsEnhancedExecutionEngine * _Nonnull)engine
       didReceiveOutput:(NSString * _Nonnull)output;

- (void)graphicsEngine:(GraphicsEnhancedExecutionEngine * _Nonnull)engine
      didEncounterError:(NSError * _Nonnull)error;

- (void)graphicsEngine:(GraphicsEnhancedExecutionEngine * _Nonnull)engine
       didUpdateProgress:(float)progress
                  status:(NSString * _Nonnull)status;

- (void)graphicsEngine:(GraphicsEnhancedExecutionEngine * _Nonnull)engine
         didCreateWindow:(NSString * _Nonnull)windowTitle
                    size:(CGSize)size;

- (void)graphicsEngine:(GraphicsEnhancedExecutionEngine * _Nonnull)engine
          didRenderFrame:(UIImage * _Nonnull)frameImage;
@end

@interface GraphicsEnhancedExecutionEngine : NSObject

@property (nonatomic, weak, nullable) id<GraphicsEnhancedExecutionEngineDelegate> delegate;
@property (nonatomic, weak, nullable) UIViewController *hostViewController;
@property (nonatomic, weak, nullable) UIView *graphicsOutputView;
@property (nonatomic, readonly) BOOL isInitialized;
@property (nonatomic, readonly) BOOL isExecuting;
@property (nonatomic, readonly) BOOL graphicsEnabled;

// 核心引擎组件
@property (nonatomic, strong, readonly) CompleteExecutionEngine *coreEngine;
@property (nonatomic, strong, readonly) MoltenVKBridge *graphicsBridge;
@property (nonatomic, strong, readonly) WineAPI *wineAPI;

+ (instancetype)sharedEngine;

// 初始化方法
- (BOOL)initializeWithViewController:(UIViewController * _Nonnull)viewController
                    graphicsOutputView:(UIView * _Nonnull)graphicsView;
- (void)cleanup;

// 执行方法
- (GraphicsExecutionResult)executeProgram:(NSString * _Nonnull)exePath;
- (GraphicsExecutionResult)executeProgram:(NSString * _Nonnull)exePath
                                arguments:(nullable NSArray<NSString *> *)arguments;
- (void)stopExecution;

// 图形相关方法
- (BOOL)enableGraphicsOutput:(BOOL)enabled;
- (void)setGraphicsResolution:(CGSize)resolution;
- (UIImage * _Nullable)captureCurrentFrame;

// 高级指令执行
- (BOOL)executeEnhancedInstructionSequence:(const uint8_t * _Nonnull)instructions
                                    length:(size_t)length;
- (NSArray<NSString *> * _Nonnull)disassembleInstructions:(const uint8_t * _Nonnull)instructions
                                                   length:(size_t)length;

// 调试和监控
- (NSDictionary * _Nonnull)getDetailedSystemInfo;
- (NSString * _Nonnull)getDetailedEngineStatus;
- (void)dumpDetailedStates;

@end

// MARK: - CompleteExecutionEngineDelegate Implementation
@interface GraphicsEnhancedExecutionEngine() <CompleteExecutionEngineDelegate>

// 代理方法 - 修复空指针警告
- (void)executionEngine:(CompleteExecutionEngine * _Nonnull)engine
       didEncounterError:(NSError * _Nonnull)error;

- (void)executionEngine:(CompleteExecutionEngine * _Nonnull)engine
        didUpdateProgress:(float)progress
                   status:(NSString * _Nonnull)status;

- (void)executionEngine:(CompleteExecutionEngine * _Nonnull)engine
         didReceiveOutput:(NSString * _Nonnull)output;

@end

NS_ASSUME_NONNULL_END
