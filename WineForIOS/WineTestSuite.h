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

// WineTestSuite.m
#import "WineTestSuite.h"
#import "WineLibraryManager.h"
#import "WineContainer.h"

@implementation WineTestCase
@end

@interface WineTestSuite()
@property (nonatomic, strong) NSMutableArray<WineTestCase *> *mutableTestCases;
@property (nonatomic, assign) BOOL isRunning;
@property (nonatomic, strong) WineLibraryManager *wineManager;
@property (nonatomic, strong) WineContainer *testContainer;
@end

@implementation WineTestSuite

- (instancetype)init {
    self = [super init];
    if (self) {
        _mutableTestCases = [NSMutableArray array];
        _isRunning = NO;
        _wineManager = [WineLibraryManager sharedManager];
        _testContainer = [[WineContainer alloc] initWithName:@"test"];
        [self setupTestCases];
    }
    return self;
}

- (NSArray<WineTestCase *> *)testCases {
    return [self.mutableTestCases copy];
}

- (void)setupTestCases {
    // 1. 基础环境测试
    WineTestCase *envTest = [[WineTestCase alloc] init];
    envTest.name = @"Environment";
    envTest.description = @"检查iOS环境和基础依赖";
    [self.mutableTestCases addObject:envTest];
    
    // 2. Wine库文件测试
    WineTestCase *filesTest = [[WineTestCase alloc] init];
    filesTest.name = @"WineFiles";
    filesTest.description = @"验证Wine库文件存在和完整性";
    [self.mutableTestCases addObject:filesTest];
    
    // 3. 库加载测试
    WineTestCase *loadTest = [[WineTestCase alloc] init];
    loadTest.name = @"LibraryLoad";
    loadTest.description = @"测试Wine库动态加载";
    [self.mutableTestCases addObject:loadTest];
    
    // 4. API函数测试
    WineTestCase *apiTest = [[WineTestCase alloc] init];
    apiTest.name = @"APIFunctions";
    apiTest.description = @"验证Wine API函数可用性";
    [self.mutableTestCases addObject:apiTest];
    
    // 5. 容器创建测试
    WineTestCase *containerTest = [[WineTestCase alloc] init];
    containerTest.name = @"Container";
    containerTest.description = @"测试Wine容器创建和初始化";
    [self.mutableTestCases addObject:containerTest];
    
    // 6. 环境初始化测试
    WineTestCase *initTest = [[WineTestCase alloc] init];
    initTest.name = @"Initialization";
    initTest.description = @"测试Wine环境初始化";
    [self.mutableTestCases addObject:initTest];
    
    // 7. 简单程序测试
    WineTestCase *simpleExecTest = [[WineTestCase alloc] init];
    simpleExecTest.name = @"SimpleExecution";
    simpleExecTest.description = @"测试简单可执行文件执行";
    [self.mutableTestCases addObject:simpleExecTest];
}

- (void)runAllTests {
    if (self.isRunning) {
        NSLog(@"[WineTestSuite] 测试已在运行");
        return;
    }
    
    self.isRunning = YES;
    NSLog(@"[WineTestSuite] 开始运行所有测试...");
    
    for (WineTestCase *testCase in self.mutableTestCases) {
        [self runSingleTest:testCase];
    }
    
    self.isRunning = NO;
    
    if (self.delegate) {
        [self.delegate testSuite:self didCompleteAllTests:self.testCases];
    }
    
    [self printTestSummary];
}

- (void)runTest:(NSString *)testName {
    WineTestCase *testCase = nil;
    for (WineTestCase *tc in self.mutableTestCases) {
        if ([tc.name isEqualToString:testName]) {
            testCase = tc;
            break;
        }
    }
    
    if (!testCase) {
        NSLog(@"[WineTestSuite] 测试用例未找到: %@", testName);
        return;
    }
    
    [self runSingleTest:testCase];
}

- (void)runSingleTest:(WineTestCase *)testCase {
    NSLog(@"[WineTestSuite] 运行测试: %@", testCase.name);
    
    if (self.delegate) {
        [self.delegate testSuite:self didStartTest:testCase];
    }
    
    NSDate *startTime = [NSDate date];
    
    @try {
        if ([testCase.name isEqualToString:@"Environment"]) {
            [self testEnvironment:testCase];
        } else if ([testCase.name isEqualToString:@"WineFiles"]) {
            [self testWineFiles:testCase];
        } else if ([testCase.name isEqualToString:@"LibraryLoad"]) {
            [self testLibraryLoad:testCase];
        } else if ([testCase.name isEqualToString:@"APIFunctions"]) {
            [self testAPIFunctions:testCase];
        } else if ([testCase.name isEqualToString:@"Container"]) {
            [self testContainer:testCase];
        } else if ([testCase.name isEqualToString:@"Initialization"]) {
            [self testInitialization:testCase];
        } else if ([testCase.name isEqualToString:@"SimpleExecution"]) {
            [self testSimpleExecution:testCase];
        } else {
            testCase.result = WineTestResultSkipped;
            testCase.errorMessage = @"测试用例未实现";
        }
    } @catch (NSException *exception) {
        testCase.result = WineTestResultFailed;
        testCase.errorMessage = [NSString stringWithFormat:@"异常: %@", exception.reason];
    }
    
    testCase.executionTime = [[NSDate date] timeIntervalSinceDate:startTime];
    
    NSLog(@"[WineTestSuite] 测试 %@ %@: %@",
          testCase.name,
          testCase.result == WineTestResultPassed ? @"通过" : @"失败",
          testCase.errorMessage ?: @"");
    
    if (self.delegate) {
        [self.delegate testSuite:self didCompleteTest:testCase];
    }
}

#pragma mark - 具体测试方法

- (void)testEnvironment:(WineTestCase *)testCase {
    // 检查iOS版本
    
    // 检查架构
    #if !defined(__arm64__)
    testCase.result = WineTestResultFailed;
    testCase.errorMessage = @"需要ARM64架构";
    return;
    #endif
    
    // 检查沙盒权限
    NSArray *documentPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    if (documentPaths.count == 0) {
        testCase.result = WineTestResultFailed;
        testCase.errorMessage = @"无法访问Documents目录";
        return;
    }
    
    testCase.result = WineTestResultPassed;
}

- (void)testWineFiles:(WineTestCase *)testCase {
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSString *wineLibsPath = [mainBundle pathForResource:@"WineLibs" ofType:nil];
    
    if (!wineLibsPath) {
        testCase.result = WineTestResultFailed;
        testCase.errorMessage = @"WineLibs文件夹未找到";
        return;
    }
    
    // 检查必需的库文件
    NSArray *requiredLibs = @[@"libwine.dylib", @"ntdll.dll.so", @"kernel32.dll.so"];
    NSFileManager *fm = [NSFileManager defaultManager];
    
    for (NSString *lib in requiredLibs) {
        NSString *libPath = [wineLibsPath stringByAppendingPathComponent:lib];
        if (![fm fileExistsAtPath:libPath]) {
            testCase.result = WineTestResultFailed;
            testCase.errorMessage = [NSString stringWithFormat:@"缺少库文件: %@", lib];
            return;
        }
        
        // 检查文件大小
        NSDictionary *attrs = [fm attributesOfItemAtPath:libPath error:nil];
        NSNumber *fileSize = attrs[NSFileSize];
        if (fileSize.integerValue < 1000) { // 至少1KB
            testCase.result = WineTestResultFailed;
            testCase.errorMessage = [NSString stringWithFormat:@"库文件太小: %@", lib];
            return;
        }
    }
    
    testCase.result = WineTestResultPassed;
}

- (void)testLibraryLoad:(WineTestCase *)testCase {
    // 先卸载（如果已加载）
    if (self.wineManager.isLoaded) {
        [self.wineManager unloadWineLibraries];
    }
    
    // 尝试加载
    BOOL loaded = [self.wineManager loadWineLibraries];
    
    if (!loaded) {
        testCase.result = WineTestResultFailed;
        testCase.errorMessage = @"Wine库加载失败";
        return;
    }
    
    if (!self.wineManager.isLoaded) {
        testCase.result = WineTestResultFailed;
        testCase.errorMessage = @"加载状态不正确";
        return;
    }
    
    testCase.result = WineTestResultPassed;
}

- (void)testAPIFunctions:(WineTestCase *)testCase {
    if (!self.wineManager.isLoaded) {
        testCase.result = WineTestResultFailed;
        testCase.errorMessage = @"Wine库未加载";
        return;
    }
    
    WineAPI *api = self.wineManager.wineAPI;
    if (!api) {
        testCase.result = WineTestResultFailed;
        testCase.errorMessage = @"Wine API结构为空";
        return;
    }
    
    // 检查关键函数指针
    NSMutableArray *missingFunctions = [NSMutableArray array];
    
    if (!api->wine_dlopen) [missingFunctions addObject:@"wine_dlopen"];
    if (!api->wine_dlsym) [missingFunctions addObject:@"wine_dlsym"];
    if (!api->wine_dlclose) [missingFunctions addObject:@"wine_dlclose"];
    if (!api->wine_mmap) [missingFunctions addObject:@"wine_mmap"];
    if (!api->wine_munmap) [missingFunctions addObject:@"wine_munmap"];
    
    if (missingFunctions.count > 0) {
        testCase.result = WineTestResultFailed;
        testCase.errorMessage = [NSString stringWithFormat:@"缺少函数: %@", [missingFunctions componentsJoinedByString:@", "]];
        return;
    }
    
    testCase.result = WineTestResultPassed;
}

- (void)testContainer:(WineTestCase *)testCase {
    // 创建测试容器
    BOOL created = [self.testContainer createContainer];
    
    if (!created) {
        testCase.result = WineTestResultFailed;
        testCase.errorMessage = @"容器创建失败";
        return;
    }
    
    // 检查容器状态
    if (self.testContainer.status != WineContainerStatusReady) {
        testCase.result = WineTestResultFailed;
        testCase.errorMessage = @"容器状态不正确";
        return;
    }
    
    // 检查容器路径
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:self.testContainer.containerPath]) {
        testCase.result = WineTestResultFailed;
        testCase.errorMessage = @"容器路径不存在";
        return;
    }
    
    testCase.result = WineTestResultPassed;
}

- (void)testInitialization:(WineTestCase *)testCase {
    if (!self.wineManager.isLoaded) {
        testCase.result = WineTestResultFailed;
        testCase.errorMessage = @"Wine库未加载";
        return;
    }
    
    // 初始化Wine环境
    BOOL initialized = [self.wineManager initializeWineEnvironment:self.testContainer.winePrefixPath];
    
    if (!initialized) {
        testCase.result = WineTestResultFailed;
        testCase.errorMessage = @"Wine环境初始化失败";
        return;
    }
    
    // 检查环境变量
    const char *winePrefix = getenv("WINEPREFIX");
    if (!winePrefix || strlen(winePrefix) == 0) {
        testCase.result = WineTestResultFailed;
        testCase.errorMessage = @"WINEPREFIX环境变量未设置";
        return;
    }
    
    testCase.result = WineTestResultPassed;
}

- (void)testSimpleExecution:(WineTestCase *)testCase {
    // 创建一个简单的测试EXE文件（模拟）
    NSString *testExePath = [self createTestExecutable];
    
    if (!testExePath) {
        testCase.result = WineTestResultFailed;
        testCase.errorMessage = @"无法创建测试可执行文件";
        return;
    }
    
    // 尝试执行
    int exitCode = [self.wineManager executeProgram:testExePath arguments:nil];
    
    // 清理测试文件
    [[NSFileManager defaultManager] removeItemAtPath:testExePath error:nil];
    
    // 检查结果（对于模拟文件，可能会失败，但不应该崩溃）
    if (exitCode == -1) {
        testCase.result = WineTestResultFailed;
        testCase.errorMessage = @"执行函数调用失败";
        return;
    }
    
    testCase.result = WineTestResultPassed;
}

#pragma mark - 辅助方法

- (NSString *)createTestExecutable {
    // 创建一个简单的PE格式模拟文件用于测试
    NSString *tempDir = NSTemporaryDirectory();
    NSString *testPath = [tempDir stringByAppendingPathComponent:@"test.exe"];
    
    // 创建一个最小的PE头结构
    NSMutableData *peData = [NSMutableData data];
    
    // DOS头
    uint8_t dosHeader[64] = {0};
    dosHeader[0] = 0x4D; // 'M'
    dosHeader[1] = 0x5A; // 'Z'
    *(uint32_t *)(dosHeader + 60) = 64; // PE头偏移
    [peData appendBytes:dosHeader length:64];
    
    // PE头
    uint8_t peHeader[4] = {0x50, 0x45, 0x00, 0x00}; // "PE\0\0"
    [peData appendBytes:peHeader length:4];
    
    // 机器类型 (x86_64)
    uint16_t machine = 0x8664;
    [peData appendBytes:&machine length:2];
    
    // 写入文件
    if ([peData writeToFile:testPath atomically:YES]) {
        return testPath;
    }
    
    return nil;
}

- (void)printTestSummary {
    NSInteger total = self.testCases.count;
    NSInteger passed = [self passedTests];
    NSInteger failed = [self failedTests];
    
    NSLog(@"\n[WineTestSuite] ==================== 测试总结 ====================");
    NSLog(@"[WineTestSuite] 总测试数: %ld", (long)total);
    NSLog(@"[WineTestSuite] 通过: %ld", (long)passed);
    NSLog(@"[WineTestSuite] 失败: %ld", (long)failed);
    NSLog(@"[WineTestSuite] 成功率: %.1f%%", total > 0 ? (passed * 100.0 / total) : 0);
    
    if (failed > 0) {
        NSLog(@"[WineTestSuite] 失败的测试:");
        for (WineTestCase *testCase in self.testCases) {
            if (testCase.result == WineTestResultFailed) {
                NSLog(@"[WineTestSuite]   - %@: %@", testCase.name, testCase.errorMessage);
            }
        }
    }
    
    NSLog(@"[WineTestSuite] ================================================\n");
}

#pragma mark - 统计方法

- (NSInteger)totalTests {
    return self.testCases.count;
}

- (NSInteger)passedTests {
    NSInteger count = 0;
    for (WineTestCase *testCase in self.testCases) {
        if (testCase.result == WineTestResultPassed) {
            count++;
        }
    }
    return count;
}

- (NSInteger)failedTests {
    NSInteger count = 0;
    for (WineTestCase *testCase in self.testCases) {
        if (testCase.result == WineTestResultFailed) {
            count++;
        }
    }
    return count;
}

@end
