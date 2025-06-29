// IntegrationTestSuite.h - 完整集成测试
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "GraphicsEnhancedExecutionEngine.h"
#import "EnhancedMoltenVKIntegration.h"
#import "ExtendedInstructionProcessor.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, IntegrationTestType) {
    IntegrationTestTypeBasicExecution,
    IntegrationTestTypeGraphicsRendering,
    IntegrationTestTypeFloatingPoint,
    IntegrationTestTypeSIMD,
    IntegrationTestTypeStringOperations,
    IntegrationTestTypeRealWorldApp
};

@interface IntegrationTestCase : NSObject
@property (nonatomic, assign) IntegrationTestType type;
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString *description;
@property (nonatomic, strong) NSData *testBinary;
@property (nonatomic, assign) BOOL passed;
@property (nonatomic, strong, nullable) NSString *errorMessage;
@property (nonatomic, assign) NSTimeInterval executionTime;
@end

@protocol IntegrationTestSuiteDelegate <NSObject>
- (void)integrationTestSuite:(id)suite didStartTest:(IntegrationTestCase *)testCase;
- (void)integrationTestSuite:(id)suite didCompleteTest:(IntegrationTestCase *)testCase;
- (void)integrationTestSuite:(id)suite didUpdateProgress:(float)progress;
@end

@interface IntegrationTestSuite : NSObject

@property (nonatomic, weak) id<IntegrationTestSuiteDelegate> delegate;
@property (nonatomic, weak) UIViewController *hostViewController;
@property (nonatomic, weak) UIView *graphicsOutputView;

- (instancetype)initWithViewController:(UIViewController *)viewController
                      graphicsOutputView:(UIView *)outputView;

- (void)runAllTests;
- (void)runTestType:(IntegrationTestType)type;
- (NSArray<IntegrationTestCase *> *)getAllTestCases;

@end

NS_ASSUME_NONNULL_END
