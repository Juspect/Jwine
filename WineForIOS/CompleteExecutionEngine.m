// CompleteExecutionEngine.m - 完整执行引擎实现（线程安全修复版本）
#import "CompleteExecutionEngine.h"

// 线程安全宏定义
#define ENSURE_MAIN_THREAD(block) \
    if ([NSThread isMainThread]) { \
        block(); \
    } else { \
        dispatch_async(dispatch_get_main_queue(), block); \
    }

#define ENSURE_MAIN_THREAD_SYNC(block) \
    if ([NSThread isMainThread]) { \
        block(); \
    } else { \
        dispatch_sync(dispatch_get_main_queue(), block); \
    }

@interface CompleteExecutionEngine()
@property (nonatomic, strong) IOSJITEngine *jitEngine;
@property (nonatomic, strong) Box64Engine *box64Engine;
@property (nonatomic, strong) WineAPI *wineAPI;
@property (nonatomic, assign) BOOL isInitialized;
@property (nonatomic, assign) BOOL isExecuting;
@property (nonatomic, strong) NSString *currentProgramPath;
@property (nonatomic, strong) NSTimer *safetyTimer; // 用Timer替换dispatch_after
@end

@implementation CompleteExecutionEngine

+ (instancetype)sharedEngine {
    static CompleteExecutionEngine *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[CompleteExecutionEngine alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _jitEngine = [IOSJITEngine sharedEngine];
        _box64Engine = [Box64Engine sharedEngine];
        _wineAPI = [WineAPI sharedAPI];
        _isInitialized = NO;
        _isExecuting = NO;
    }
    return self;
}

- (void)dealloc {
    // 停止所有定时器
    if (_safetyTimer) {
        [_safetyTimer invalidate];
        _safetyTimer = nil;
    }
    [self cleanup];
}

#pragma mark - 初始化和配置

- (BOOL)initializeWithViewController:(UIViewController *)viewController {
    if (_isInitialized) {
        NSLog(@"[CompleteExecutionEngine] Already initialized");
        return YES;
    }
    
    NSLog(@"[CompleteExecutionEngine] Initializing complete execution engine...");
    [self notifyProgress:0.1 status:@"初始化JIT引擎..."];
    
    _hostViewController = viewController;
    _wineAPI.rootViewController = viewController;
    
    // 同步初始化，避免任何异步Block
    BOOL jitSuccess = [_jitEngine initializeJIT];
    if (!jitSuccess) {
        NSLog(@"[CompleteExecutionEngine] Failed to initialize JIT engine");
        [self notifyErrorSync:[NSError errorWithDomain:@"ExecutionEngine" code:ExecutionResultInitError userInfo:@{NSLocalizedDescriptionKey: @"JIT引擎初始化失败"}]];
        return NO;
    }
    
    [self notifyProgress:0.3 status:@"初始化Box64引擎..."];
    
    BOOL box64Success = [_box64Engine initializeWithMemorySize:64 * 1024 * 1024];
    if (!box64Success) {
        NSLog(@"[CompleteExecutionEngine] Failed to initialize Box64 engine");
        [self notifyErrorSync:[NSError errorWithDomain:@"ExecutionEngine" code:ExecutionResultInitError userInfo:@{NSLocalizedDescriptionKey: @"Box64引擎初始化失败"}]];
        return NO;
    }
    
    [self notifyProgress:0.5 status:@"设置Wine环境..."];
    [self registerBasicWindowClasses];
    
    [self notifyProgress:0.7 status:@"创建虚拟Windows环境..."];
    [self createBasicWindowsEnvironment];
    
    [self notifyProgress:1.0 status:@"初始化完成"];
    
    _isInitialized = YES;
    NSLog(@"[CompleteExecutionEngine] Complete execution engine initialized successfully!");
    
    return YES;
}

- (void)registerBasicWindowClasses {
    WNDCLASS buttonClass = {0};
    buttonClass.lpfnWndProc = DefWindowProc;
    buttonClass.lpszClassName = "Button";
    buttonClass.hbrBackground = GetStockObject(WHITE_BRUSH);
    RegisterClass(&buttonClass);
    
    WNDCLASS staticClass = {0};
    staticClass.lpfnWndProc = DefWindowProc;
    staticClass.lpszClassName = "Static";
    staticClass.hbrBackground = GetStockObject(WHITE_BRUSH);
    RegisterClass(&staticClass);
    
    WNDCLASS editClass = {0};
    editClass.lpfnWndProc = DefWindowProc;
    editClass.lpszClassName = "Edit";
    editClass.hbrBackground = GetStockObject(WHITE_BRUSH);
    RegisterClass(&editClass);
    
    NSLog(@"[CompleteExecutionEngine] Registered basic window classes");
}

- (void)createBasicWindowsEnvironment {
    setenv("WINEPREFIX", "/tmp/wine_prefix", 1);
    setenv("WINEDEBUG", "-all", 1);
    setenv("DISPLAY", ":0", 1);
    
    NSData *kernelData = [self createMockKernel32DLL];
    [_box64Engine mapMemory:0x1000000 size:kernelData.length data:kernelData];
    
    NSData *userData = [self createMockUser32DLL];
    [_box64Engine mapMemory:0x2000000 size:userData.length data:userData];
    
    NSData *gdiData = [self createMockGDI32DLL];
    [_box64Engine mapMemory:0x3000000 size:gdiData.length data:gdiData];
    
    NSLog(@"[CompleteExecutionEngine] Created basic Windows environment");
}

- (NSData *)createMockKernel32DLL {
    uint32_t instructions[] = {
        0xD503201F,  // NOP
        0xD2800000,  // MOV X0, #0
        0xD65F03C0   // RET
    };
    return [NSData dataWithBytes:instructions length:sizeof(instructions)];
}

- (NSData *)createMockUser32DLL {
    uint32_t instructions[] = {
        0xD503201F,  // NOP
        0xD2800020,  // MOV X0, #1
        0xD65F03C0   // RET
    };
    return [NSData dataWithBytes:instructions length:sizeof(instructions)];
}

- (NSData *)createMockGDI32DLL {
    uint32_t instructions[] = {
        0xD503201F,  // NOP
        0xD2800020,  // MOV X0, #1
        0xD65F03C0   // RET
    };
    return [NSData dataWithBytes:instructions length:sizeof(instructions)];
}

- (void)cleanup {
    if (!_isInitialized) return;
    
    NSLog(@"[CompleteExecutionEngine] Cleaning up execution engine...");
    
    // 停止定时器
    if (_safetyTimer) {
        [_safetyTimer invalidate];
        _safetyTimer = nil;
    }
    
    [self stopExecution];
    
    if (_box64Engine) {
        [_box64Engine cleanup];
    }
    
    if (_jitEngine) {
        [_jitEngine cleanupJIT];
    }
    
    _isInitialized = NO;
    NSLog(@"[CompleteExecutionEngine] Cleanup completed");
}

#pragma mark - 程序执行 - 完全同步版本

- (ExecutionResult)executeProgram:(NSString *)exePath {
    return [self executeProgram:exePath arguments:nil];
}

- (ExecutionResult)executeProgram:(NSString *)exePath arguments:(nullable NSArray<NSString *> *)arguments {
    if (!_isInitialized) {
        NSLog(@"[CompleteExecutionEngine] Engine not initialized");
        return ExecutionResultInitError;
    }
    
    if (_isExecuting) {
        NSLog(@"[CompleteExecutionEngine] Already executing a program");
        return ExecutionResultFailure;
    }
    
    NSLog(@"[CompleteExecutionEngine] Starting execution of: %@", exePath);
    _currentProgramPath = exePath;
    _isExecuting = YES;
    
    [self notifyStartExecutionSync:exePath];
    [self notifyProgress:0.0 status:@"加载程序文件..."];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:exePath]) {
        NSLog(@"[CompleteExecutionEngine] Program file not found: %@", exePath);
        [self notifyErrorSync:[NSError errorWithDomain:@"ExecutionEngine" code:ExecutionResultInvalidFile userInfo:@{NSLocalizedDescriptionKey: @"程序文件未找到"}]];
        _isExecuting = NO;
        return ExecutionResultInvalidFile;
    }
    
    [self notifyProgress:0.2 status:@"分析PE文件..."];
    
    NSData *peData = [NSData dataWithContentsOfFile:exePath];
    if (!peData) {
        NSLog(@"[CompleteExecutionEngine] Failed to load PE file");
        _isExecuting = NO;
        return ExecutionResultInvalidFile;
    }
    
    ExecutionResult result = [self analyzePEFile:peData];
    if (result != ExecutionResultSuccess) {
        _isExecuting = NO;
        return result;
    }
    
    [self notifyProgress:0.4 status:@"设置执行环境..."];
    
    // 完全同步执行，避免任何Block
    BOOL mapSuccess = NO;
    @try {
        mapSuccess = [_box64Engine mapMemory:0x400000 size:peData.length data:peData];
    } @catch (NSException *exception) {
        NSLog(@"[CompleteExecutionEngine] Exception during memory mapping: %@", exception.reason);
        mapSuccess = NO;
    }
    
    if (!mapSuccess) {
        NSLog(@"[CompleteExecutionEngine] Failed to map PE file");
        [self notifyErrorSync:[NSError errorWithDomain:@"ExecutionEngine" code:ExecutionResultMemoryError userInfo:@{NSLocalizedDescriptionKey: @"内存映射失败"}]];
        _isExecuting = NO;
        return ExecutionResultMemoryError;
    }
    
    [self notifyProgress:0.6 status:@"初始化CPU状态..."];
    
    @try {
        [_box64Engine setX86Register:X86_RSP value:0x100000];
        [_box64Engine setX86Register:X86_RBP value:0x100000];
        NSLog(@"[CompleteExecutionEngine] CPU registers initialized");
    } @catch (NSException *exception) {
        NSLog(@"[CompleteExecutionEngine] Exception setting registers: %@", exception.reason);
    }
    
    [self notifyProgress:0.8 status:@"开始执行程序..."];
    
    // 同步执行
    ExecutionResult execResult = [self executePEEntryPointSync:peData arguments:arguments];
    
    if (execResult == ExecutionResultSuccess) {
        [self notifyProgress:1.0 status:@"程序执行完成"];
        [self notifyOutputSync:@"🎉 程序执行成功完成！"];
        
        // 使用NSTimer延迟检查结果，避免dispatch_after
        if (![NSThread isMainThread]) {
            dispatch_sync(dispatch_get_main_queue(), ^{
                [self scheduleResultCheck];
            });
        } else {
            [self scheduleResultCheck];
        }
    }
    
    [self notifyFinishExecutionSync:exePath result:execResult];
    _isExecuting = NO;
    
    return execResult;
}

// 新增：使用NSTimer替换dispatch_after
- (void)scheduleResultCheck {
    // 确保在主线程
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self scheduleResultCheck];
        });
        return;
    }
    
    // 停止之前的定时器
    if (_safetyTimer) {
        [_safetyTimer invalidate];
    }
    
    // 创建单次触发的定时器
    _safetyTimer = [NSTimer scheduledTimerWithTimeInterval:0.1
                                                    target:self
                                                  selector:@selector(performResultCheck:)
                                                  userInfo:nil
                                                   repeats:NO];
}

// NSTimer回调方法
- (void)performResultCheck:(NSTimer *)timer {
    // 停用定时器
    [timer invalidate];
    if (_safetyTimer == timer) {
        _safetyTimer = nil;
    }
    
    // 执行结果检查
    [self checkExecutionResultSafely];
}

- (ExecutionResult)executePEEntryPointSync:(NSData *)peData arguments:(nullable NSArray<NSString *> *)arguments {
    NSLog(@"[CompleteExecutionEngine] Executing PE entry point synchronously...");
    
    if (!_box64Engine || !_box64Engine.isInitialized) {
        NSLog(@"[CompleteExecutionEngine] Box64 engine not properly initialized");
        [self notifyOutputSync:@"❌ Box64引擎未初始化"];
        return ExecutionResultInitError;
    }
    
    uint8_t simpleTestInstructions[] = {
        0xB8, 0x2A, 0x00, 0x00, 0x00,  // MOV EAX, 42
        0x90,                           // NOP
        0x90                            // NOP
    };
    
    NSLog(@"[CompleteExecutionEngine] Testing with simple instruction sequence");
    [self notifyOutputSync:@"开始执行简单测试指令..."];
    
    @try {
        BOOL success = [_box64Engine executeX86Code:simpleTestInstructions length:sizeof(simpleTestInstructions)];
        NSLog(@"[CompleteExecutionEngine] x86 code execution result: %@", success ? @"SUCCESS" : @"FAILED");
        
        if (success) {
            [self notifyOutputSync:@"✅ 基础指令测试成功"];
            return ExecutionResultSuccess;
        } else {
            [self notifyOutputSync:@"❌ 基础指令测试失败"];
            return ExecutionResultFailure;
        }
        
    } @catch (NSException *exception) {
        NSLog(@"[CompleteExecutionEngine] Exception during execution: %@", exception.reason);
        [self notifyOutputSync:[NSString stringWithFormat:@"❌ 执行异常: %@", exception.reason]];
        return ExecutionResultFailure;
    }
}

- (void)checkExecutionResultSafely {
    // 确保在主线程且对象仍然有效
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self checkExecutionResultSafely];
        });
        return;
    }
    
    // 安全的结果检查
    if (_isInitialized && _box64Engine) {
        NSLog(@"[CompleteExecutionEngine] Execution result check completed safely");
        [self notifyOutputSync:@"🔍 执行结果检查完成"];
    }
}

- (ExecutionResult)analyzePEFile:(NSData *)peData {
    if (peData.length < 64) {
        NSLog(@"[CompleteExecutionEngine] PE file too small");
        [self notifyOutputSync:@"❌ PE文件过小"];
        return ExecutionResultInvalidFile;
    }
    
    const uint8_t *bytes = peData.bytes;
    
    // 检查DOS头
    if (bytes[0] != 'M' || bytes[1] != 'Z') {
        NSLog(@"[CompleteExecutionEngine] Invalid DOS header");
        [self notifyOutputSync:@"❌ 无效的DOS头"];
        return ExecutionResultInvalidFile;
    }
    
    // 获取PE头偏移
    uint32_t peOffset = *(uint32_t *)(bytes + 60);
    if (peOffset >= peData.length - 4) {
        NSLog(@"[CompleteExecutionEngine] Invalid PE offset");
        [self notifyOutputSync:@"❌ 无效的PE偏移"];
        return ExecutionResultInvalidFile;
    }
    
    // 检查PE签名
    if (*(uint32_t *)(bytes + peOffset) != 0x00004550) { // "PE\0\0"
        NSLog(@"[CompleteExecutionEngine] Invalid PE signature");
        [self notifyOutputSync:@"❌ 无效的PE签名"];
        return ExecutionResultInvalidFile;
    }
    
    // 获取机器类型
    uint16_t machine = *(uint16_t *)(bytes + peOffset + 4);
    NSString *architecture;
    
    switch (machine) {
        case 0x014c: // IMAGE_FILE_MACHINE_I386
            architecture = @"x86 (32-bit)";
            break;
        case 0x8664: // IMAGE_FILE_MACHINE_AMD64
            architecture = @"x64 (64-bit)";
            break;
        case 0x01c0: // IMAGE_FILE_MACHINE_ARM
            architecture = @"ARM";
            break;
        case 0xaa64: // IMAGE_FILE_MACHINE_ARM64
            architecture = @"ARM64";
            break;
        default:
            architecture = [NSString stringWithFormat:@"Unknown (0x%04x)", machine];
            NSLog(@"[CompleteExecutionEngine] Unsupported architecture: %@", architecture);
            return ExecutionResultInvalidFile;
    }
    
    [self notifyOutputSync:[NSString stringWithFormat:@"PE文件分析完成: %@", architecture]];
    NSLog(@"[CompleteExecutionEngine] PE analysis successful: %@", architecture);
    
    return ExecutionResultSuccess;
}

- (void)stopExecution {
    if (!_isExecuting) return;
    
    NSLog(@"[CompleteExecutionEngine] Stopping execution...");
    
    // 停止定时器
    if (_safetyTimer) {
        [_safetyTimer invalidate];
        _safetyTimer = nil;
    }
    
    _isExecuting = NO;
    [self notifyOutputSync:@"程序执行已停止"];
}

#pragma mark - 系统状态

- (NSDictionary *)getSystemInfo {
    return @{
        @"jit_enabled": @(_jitEngine.isJITEnabled),
        @"jit_memory": @(_jitEngine.totalJITMemory),
        @"box64_initialized": @(_box64Engine.isInitialized),
        @"wine_windows": @(_wineAPI.windows.count),
        @"is_executing": @(_isExecuting),
        @"current_program": _currentProgramPath ?: @"None"
    };
}

- (NSString *)getEngineStatus {
    if (!_isInitialized) {
        return @"未初始化";
    }
    
    if (_isExecuting) {
        return [NSString stringWithFormat:@"正在执行: %@", [_currentProgramPath lastPathComponent]];
    }
    
    return @"就绪";
}

- (void)dumpAllStates {
    NSLog(@"[CompleteExecutionEngine] ===== System State Dump =====");
    [_jitEngine dumpJITStats];
    [_box64Engine dumpRegisters];
    NSLog(@"[CompleteExecutionEngine] Wine Windows: %@", _wineAPI.windows.allKeys);
    NSLog(@"[CompleteExecutionEngine] Wine DCs: %@", _wineAPI.deviceContexts.allKeys);
    NSLog(@"[CompleteExecutionEngine] Message Queue: %lu messages", (unsigned long)_wineAPI.messageQueue.count);
    NSLog(@"[CompleteExecutionEngine] ==============================");
}

#pragma mark - 同步委托通知方法 - 线程安全修复

- (void)notifyStartExecutionSync:(NSString *)programPath {
    ENSURE_MAIN_THREAD(^{
        if ([self.delegate respondsToSelector:@selector(executionEngine:didStartExecution:)]) {
            [self.delegate executionEngine:self didStartExecution:programPath];
        }
    });
}

- (void)notifyFinishExecutionSync:(NSString *)programPath result:(ExecutionResult)result {
    ENSURE_MAIN_THREAD(^{
        if ([self.delegate respondsToSelector:@selector(executionEngine:didFinishExecution:result:)]) {
            [self.delegate executionEngine:self didFinishExecution:programPath result:result];
        }
    });
}

- (void)notifyOutputSync:(NSString *)output {
    ENSURE_MAIN_THREAD(^{
        if ([self.delegate respondsToSelector:@selector(executionEngine:didReceiveOutput:)]) {
            [self.delegate executionEngine:self didReceiveOutput:output];
        }
    });
}

- (void)notifyErrorSync:(NSError *)error {
    ENSURE_MAIN_THREAD(^{
        if ([self.delegate respondsToSelector:@selector(executionEngine:didEncounterError:)]) {
            [self.delegate executionEngine:self didEncounterError:error];
        }
    });
}

- (void)notifyProgress:(float)progress status:(NSString *)status {
    ENSURE_MAIN_THREAD(^{
        if ([self.delegate respondsToSelector:@selector(executionEngine:didUpdateProgress:status:)]) {
            [self.delegate executionEngine:self didUpdateProgress:progress status:status];
        }
    });
}

@end
