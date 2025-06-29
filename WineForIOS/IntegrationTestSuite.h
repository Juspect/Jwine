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

// IntegrationTestSuite.m - 实现
@implementation IntegrationTestCase
@end

@interface IntegrationTestSuite()
@property (nonatomic, strong) GraphicsEnhancedExecutionEngine *executionEngine;
@property (nonatomic, strong) EnhancedMoltenVKIntegration *graphicsIntegration;
@property (nonatomic, strong) ExtendedInstructionProcessor *instructionProcessor;
@property (nonatomic, strong) NSMutableArray<IntegrationTestCase *> *testCases;
@end

@implementation IntegrationTestSuite

- (instancetype)initWithViewController:(UIViewController *)viewController
                      graphicsOutputView:(UIView *)outputView {
    self = [super init];
    if (self) {
        _hostViewController = viewController;
        _graphicsOutputView = outputView;
        
        _executionEngine = [GraphicsEnhancedExecutionEngine sharedEngine];
        _graphicsIntegration = [EnhancedMoltenVKIntegration sharedIntegration];
        _instructionProcessor = [ExtendedInstructionProcessor sharedProcessor];
        
        [self setupTestCases];
    }
    return self;
}

- (void)setupTestCases {
    _testCases = [NSMutableArray array];
    
    // 1. 基础执行测试
    IntegrationTestCase *basicTest = [[IntegrationTestCase alloc] init];
    basicTest.type = IntegrationTestTypeBasicExecution;
    basicTest.name = @"Basic Execution";
    basicTest.description = @"测试基础的x86指令执行";
    basicTest.testBinary = [self createBasicExecutionTest];
    [_testCases addObject:basicTest];
    
    // 2. 图形渲染测试
    IntegrationTestCase *graphicsTest = [[IntegrationTestCase alloc] init];
    graphicsTest.type = IntegrationTestTypeGraphicsRendering;
    graphicsTest.name = @"Graphics Rendering";
    graphicsTest.description = @"测试DirectX→Vulkan→Metal图形管道";
    graphicsTest.testBinary = [self createGraphicsRenderingTest];
    [_testCases addObject:graphicsTest];
    
    // 3. 浮点运算测试
    IntegrationTestCase *floatTest = [[IntegrationTestCase alloc] init];
    floatTest.type = IntegrationTestTypeFloatingPoint;
    floatTest.name = @"Floating Point";
    floatTest.description = @"测试浮点运算指令";
    floatTest.testBinary = [self createFloatingPointTest];
    [_testCases addObject:floatTest];
    
    // 4. SIMD指令测试
    IntegrationTestCase *simdTest = [[IntegrationTestCase alloc] init];
    simdTest.type = IntegrationTestTypeSIMD;
    simdTest.name = @"SIMD Instructions";
    simdTest.description = @"测试SSE/AVX SIMD指令";
    simdTest.testBinary = [self createSIMDTest];
    [_testCases addObject:simdTest];
    
    // 5. 字符串操作测试
    IntegrationTestCase *stringTest = [[IntegrationTestCase alloc] init];
    stringTest.type = IntegrationTestTypeStringOperations;
    stringTest.name = @"String Operations";
    stringTest.description = @"测试字符串操作指令";
    stringTest.testBinary = [self createStringOperationsTest];
    [_testCases addObject:stringTest];
    
    // 6. 真实应用测试
    IntegrationTestCase *realAppTest = [[IntegrationTestCase alloc] init];
    realAppTest.type = IntegrationTestTypeRealWorldApp;
    realAppTest.name = @"Real World Application";
    realAppTest.description = @"测试真实的Windows应用程序";
    realAppTest.testBinary = [self createRealWorldAppTest];
    [_testCases addObject:realAppTest];
}

- (void)runAllTests {
    NSLog(@"[IntegrationTest] Starting comprehensive integration tests...");
    
    // 首先初始化所有系统
    if (![self initializeTestEnvironment]) {
        NSLog(@"[IntegrationTest] Failed to initialize test environment");
        return;
    }
    
    for (NSInteger i = 0; i < _testCases.count; i++) {
        IntegrationTestCase *testCase = _testCases[i];
        
        if (self.delegate) {
            [self.delegate integrationTestSuite:self didStartTest:testCase];
        }
        
        NSDate *startTime = [NSDate date];
        [self runSingleTest:testCase];
        testCase.executionTime = [[NSDate date] timeIntervalSinceDate:startTime];
        
        if (self.delegate) {
            [self.delegate integrationTestSuite:self didCompleteTest:testCase];
            [self.delegate integrationTestSuite:self didUpdateProgress:(float)(i + 1) / _testCases.count];
        }
        
        // 测试之间的短暂延迟
        [NSThread sleepForTimeInterval:0.5];
    }
    
    [self generateTestReport];
}

- (BOOL)initializeTestEnvironment {
    NSLog(@"[IntegrationTest] Initializing test environment...");
    
    // 1. 初始化执行引擎
    if (![_executionEngine initializeWithViewController:_hostViewController
                                       graphicsOutputView:_graphicsOutputView]) {
        NSLog(@"[IntegrationTest] Failed to initialize execution engine");
        return NO;
    }
    
    // 2. 初始化图形系统
    if (![_graphicsIntegration initializeWithOutputView:_graphicsOutputView]) {
        NSLog(@"[IntegrationTest] Failed to initialize graphics integration");
        return NO;
    }
    
    NSLog(@"[IntegrationTest] Test environment initialized successfully");
    return YES;
}

- (void)runSingleTest:(IntegrationTestCase *)testCase {
    NSLog(@"[IntegrationTest] Running test: %@", testCase.name);
    
    @try {
        switch (testCase.type) {
            case IntegrationTestTypeBasicExecution:
                testCase.passed = [self runBasicExecutionTest:testCase];
                break;
                
            case IntegrationTestTypeGraphicsRendering:
                testCase.passed = [self runGraphicsRenderingTest:testCase];
                break;
                
            case IntegrationTestTypeFloatingPoint:
                testCase.passed = [self runFloatingPointTest:testCase];
                break;
                
            case IntegrationTestTypeSIMD:
                testCase.passed = [self runSIMDTest:testCase];
                break;
                
            case IntegrationTestTypeStringOperations:
                testCase.passed = [self runStringOperationsTest:testCase];
                break;
                
            case IntegrationTestTypeRealWorldApp:
                testCase.passed = [self runRealWorldAppTest:testCase];
                break;
        }
    } @catch (NSException *exception) {
        testCase.passed = NO;
        testCase.errorMessage = [NSString stringWithFormat:@"Exception: %@", exception.reason];
    }
    
    NSLog(@"[IntegrationTest] Test %@ %@", testCase.name, testCase.passed ? @"PASSED" : @"FAILED");
}

- (BOOL)runBasicExecutionTest:(IntegrationTestCase *)testCase {
    // 测试基础指令执行
    uint8_t testInstructions[] = {
        0xB8, 0x0A, 0x00, 0x00, 0x00,  // MOV EAX, 10
        0x05, 0x05, 0x00, 0x00, 0x00,  // ADD EAX, 5
        0x2D, 0x03, 0x00, 0x00, 0x00,  // SUB EAX, 3
        0x90,                           // NOP
        0xC3                            // RET
    };
    
    BOOL success = [_instructionProcessor processExtendedInstruction:testInstructions
                                                              length:sizeof(testInstructions)
                                                             context:[[Box64Engine sharedEngine] context]];
    
    if (!success) {
        testCase.errorMessage = @"Failed to execute basic instructions";
        return NO;
    }
    
    // 验证结果 (EAX应该等于12)
    uint64_t result = [[Box64Engine sharedEngine] getX86Register:X86_RAX];
    if (result != 12) {
        testCase.errorMessage = [NSString stringWithFormat:@"Expected 12, got %llu", result];
        return NO;
    }
    
    return YES;
}

- (BOOL)runGraphicsRenderingTest:(IntegrationTestCase *)testCase {
    // 测试DirectX调用的拦截和转换
    NSDictionary *testParams = @{
        @"width": @800,
        @"height": @600,
        @"format": @"BGRA8"
    };
    
    void *deviceHandle = NULL;
    BOOL success = [_graphicsIntegration interceptDirectXCall:@"CreateDevice"
                                                   parameters:testParams
                                                  returnValue:&deviceHandle];
    
    if (!success || !deviceHandle) {
        testCase.errorMessage = @"Failed to create DirectX device";
        return NO;
    }
    
    // 测试清屏操作
    NSDictionary *clearParams = @{
        @"color": [UIColor blueColor]
    };
    
    success = [_graphicsIntegration interceptDirectXCall:@"Clear"
                                              parameters:clearParams
                                             returnValue:NULL];
    
    if (!success) {
        testCase.errorMessage = @"Failed to clear render target";
        return NO;
    }
    
    // 测试简单绘制
    success = [_graphicsIntegration interceptDirectXCall:@"DrawPrimitive"
                                              parameters:@{}
                                             returnValue:NULL];
    
    if (!success) {
        testCase.errorMessage = @"Failed to draw primitive";
        return NO;
    }
    
    return YES;
}

- (BOOL)runFloatingPointTest:(IntegrationTestCase *)testCase {
    // 测试浮点运算指令
    uint8_t floatInstructions[] = {
        0xD8, 0xC0,  // FADD ST(0), ST(0) - 简化的浮点加法
        0xD8, 0xC8,  // FMUL ST(0), ST(0) - 简化的浮点乘法
        0xC3         // RET
    };
    
    BOOL success = [_instructionProcessor processExtendedInstruction:floatInstructions
                                                              length:sizeof(floatInstructions)
                                                             context:[[Box64Engine sharedEngine] context]];
    
    if (!success) {
        testCase.errorMessage = @"Failed to execute floating point instructions";
        return NO;
    }
    
    return YES;
}

- (BOOL)runSIMDTest:(IntegrationTestCase *)testCase {
    // 测试SIMD指令
    uint8_t simdInstructions[] = {
        0xF3, 0x0F, 0x10, 0x00,  // MOVSS XMM0, [EAX] - 简化版本
        0xF3, 0x0F, 0x58, 0x08,  // ADDSS XMM1, [EAX] - 简化版本
        0xC3                      // RET
    };
    
    BOOL success = [_instructionProcessor processExtendedInstruction:simdInstructions
                                                              length:sizeof(simdInstructions)
                                                             context:[[Box64Engine sharedEngine] context]];
    
    if (!success) {
        testCase.errorMessage = @"Failed to execute SIMD instructions";
        return NO;
    }
    
    return YES;
}

- (BOOL)runStringOperationsTest:(IntegrationTestCase *)testCase {
    // 测试字符串操作指令
    uint8_t stringInstructions[] = {
        0xA4,  // MOVSB
        0xAA,  // STOSB
        0xAC,  // LODSB
        0xC3   // RET
    };
    
    BOOL success = [_instructionProcessor processExtendedInstruction:stringInstructions
                                                              length:sizeof(stringInstructions)
                                                             context:[[Box64Engine sharedEngine] context]];
    
    if (!success) {
        testCase.errorMessage = @"Failed to execute string instructions";
        return NO;
    }
    
    return YES;
}

- (BOOL)runRealWorldAppTest:(IntegrationTestCase *)testCase {
    // 使用创建的测试PE文件进行真实应用测试
    if (!testCase.testBinary) {
        testCase.errorMessage = @"No test binary available";
        return NO;
    }
    
    // 保存测试二进制文件
    NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"integration_test.exe"];
    if (![testCase.testBinary writeToFile:tempPath atomically:YES]) {
        testCase.errorMessage = @"Failed to write test binary";
        return NO;
    }
    
    // 执行测试程序
    GraphicsExecutionResult result = [_executionEngine executeProgram:tempPath];
    
    // 清理临时文件
    [[NSFileManager defaultManager] removeItemAtPath:tempPath error:nil];
    
    if (result != GraphicsExecutionResultSuccess) {
        testCase.errorMessage = [NSString stringWithFormat:@"Execution failed with result: %ld", (long)result];
        return NO;
    }
    
    return YES;
}

#pragma mark - 测试二进制文件创建

- (NSData *)createBasicExecutionTest {
    // 创建基础执行测试的PE文件
    return [[TestBinaryCreator sharedCreator] createSimpleTestPE];
}

- (NSData *)createGraphicsRenderingTest {
    // 创建包含DirectX调用的测试PE文件
    return [[TestBinaryCreator sharedCreator] createCalculatorTestPE];
}

- (NSData *)createFloatingPointTest {
    // 创建浮点运算测试PE文件
    NSMutableData *peData = [NSMutableData data];
    
    // 添加PE头结构（简化版本）
    uint8_t header[] = {0x4D, 0x5A}; // MZ signature
    [peData appendBytes:header length:sizeof(header)];
    
    // 添加浮点指令测试代码
    uint8_t floatCode[] = {
        0xD9, 0xE8,  // FLD1 - 加载1.0到FPU栈
        0xD8, 0xC0,  // FADD ST(0), ST(0) - 计算 1.0 + 1.0
        0xC3         // RET
    };
    [peData appendBytes:floatCode length:sizeof(floatCode)];
    
    return peData;
}

- (NSData *)createSIMDTest {
    // 创建SIMD指令测试PE文件
    return [[TestBinaryCreator sharedCreator] createHelloWorldPE];
}

- (NSData *)createStringOperationsTest {
    // 创建字符串操作测试PE文件
    return [[TestBinaryCreator sharedCreator] createSimpleTestPE];
}

- (NSData *)createRealWorldAppTest {
    // 创建一个更复杂的真实应用测试
    return [[TestBinaryCreator sharedCreator] createCalculatorTestPE];
}

- (NSArray<IntegrationTestCase *> *)getAllTestCases {
    return [_testCases copy];
}

- (void)generateTestReport {
    NSInteger passedCount = 0;
    NSInteger failedCount = 0;
    
    for (IntegrationTestCase *testCase in _testCases) {
        if (testCase.passed) {
            passedCount++;
        } else {
            failedCount++;
        }
    }
    
    NSLog(@"\n[IntegrationTest] ===================== TEST REPORT =====================");
    NSLog(@"[IntegrationTest] Total Tests: %ld", (long)_testCases.count);
    NSLog(@"[IntegrationTest] Passed: %ld", (long)passedCount);
    NSLog(@"[IntegrationTest] Failed: %ld", (long)failedCount);
    NSLog(@"[IntegrationTest] Success Rate: %.1f%%",
          _testCases.count > 0 ? (passedCount * 100.0 / _testCases.count) : 0);
    
    if (failedCount > 0) {
        NSLog(@"[IntegrationTest] Failed Tests:");
        for (IntegrationTestCase *testCase in _testCases) {
            if (!testCase.passed) {
                NSLog(@"[IntegrationTest]   - %@: %@", testCase.name, testCase.errorMessage ?: @"Unknown error");
            }
        }
    }
    
    NSLog(@"[IntegrationTest] =======================================================\n");
}

@end
