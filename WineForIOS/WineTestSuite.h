// WineTestSuite.h
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, WineTestResult) {
    WineTestResultPassed,
    WineTestResultFailed,
    WineTestResultSkipped
};

@interface WineTestCase : NSObject
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString *description;
@property (nonatomic, assign) WineTestResult result;
@property (nonatomic, strong, nullable) NSString *errorMessage;
@property (nonatomic, assign) NSTimeInterval executionTime;
@end

@protocol WineTestSuiteDelegate <NSObject>
- (void)testSuite:(id)suite didStartTest:(WineTestCase *)testCase;
- (void)testSuite:(id)suite didCompleteTest:(WineTestCase *)testCase;
- (void)testSuite:(id)suite didCompleteAllTests:(NSArray<WineTestCase *> *)results;
@end

@interface WineTestSuite : NSObject

@property (nonatomic, weak) id<WineTestSuiteDelegate> delegate;
@property (nonatomic, readonly) NSArray<WineTestCase *> *testCases;
@property (nonatomic, readonly) BOOL isRunning;

- (void)runAllTests;
- (void)runTest:(NSString *)testName;
- (NSInteger)totalTests;
- (NSInteger)passedTests;
- (NSInteger)failedTests;

@end

NS_ASSUME_NONNULL_END
