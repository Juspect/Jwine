#import "CompleteExecutionEngine.h"
#import "Box64Engine.h"
#import "IOSJITEngine.h"
#import "WineAPI.h"
#import "TestBinaryCreator.h"

// 线程安全宏 - 增强版
#define ENSURE_MAIN_THREAD_SYNC(block) do { \
    if ([NSThread isMainThread]) { \
        block(); \
    } else { \
        dispatch_sync(dispatch_get_main_queue(), block); \
    } \
} while(0)

#define ENSURE_MAIN_THREAD_ASYNC(block) do { \
    if ([NSThread isMainThread]) { \
        block(); \
    } else { \
        dispatch_async(dispatch_get_main_queue(), block); \
    } \
} while(0)

@interface CompleteExecutionEngine()
@property (nonatomic, strong) Box64Engine *box64Engine;
@property (nonatomic, strong) IOSJITEngine *jitEngine;
@property (nonatomic, strong) WineAPI *wineAPI;
@property (nonatomic, assign) BOOL isInitialized;
@property (nonatomic, assign) BOOL isExecuting;
@property (nonatomic, strong) NSString *currentProgramPath;
@property (nonatomic, strong) NSTimer *safetyTimer;
@property (nonatomic, strong) NSRecursiveLock *executionLock;
@property (nonatomic, strong) NSMutableArray<NSString *> *executionLog;
@property (nonatomic, assign) NSTimeInterval executionStartTime;
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
        _executionLock = [[NSRecursiveLock alloc] init];
        _executionLog = [NSMutableArray array];
        _isInitialized = NO;
        _isExecuting = NO;
        _currentProgramPath = nil;
        _executionStartTime = 0;
        
        NSLog(@"[CompleteExecutionEngine] Initializing complete execution engine with enhanced safety...");
    }
    return self;
}

- (void)dealloc {
    [self cleanup];
}

#pragma mark - 初始化 - 线程安全版本

- (BOOL)initializeEngines {
    [_executionLock lock];
    
    @try {
        if (_isInitialized) {
            NSLog(@"[CompleteExecutionEngine] Already initialized");
            return YES;
        }
        
        NSLog(@"[CompleteExecutionEngine] Starting enhanced initialization...");
        
        // 清空执行日志
        [_executionLog removeAllObjects];
        [_executionLog addObject:@"开始初始化执行引擎..."];
        
        [self notifyProgress:0.1 status:@"初始化JIT引擎..."];
        
        // 初始化JIT引擎
        _jitEngine = [IOSJITEngine sharedEngine];
        BOOL jitSuccess = [_jitEngine initializeJIT];
        if (!jitSuccess) {
            NSLog(@"[CompleteExecutionEngine] CRITICAL: Failed to initialize JIT engine");
            [self notifyErrorSync:[NSError errorWithDomain:@"ExecutionEngine" code:ExecutionResultInitError userInfo:@{NSLocalizedDescriptionKey: @"JIT引擎初始化失败"}]];
            return NO;
        }
        [_executionLog addObject:@"✓ JIT引擎初始化成功"];
        
        [self notifyProgress:0.3 status:@"初始化Box64引擎..."];
        
        // 初始化Box64引擎 - 使用安全模式
        _box64Engine = [Box64Engine sharedEngine];
        BOOL box64Success = [_box64Engine initializeWithMemorySize:64 * 1024 * 1024 safeMode:YES];
        if (!box64Success) {
            NSLog(@"[CompleteExecutionEngine] CRITICAL: Failed to initialize Box64 engine");
            [self notifyErrorSync:[NSError errorWithDomain:@"ExecutionEngine" code:ExecutionResultInitError userInfo:@{NSLocalizedDescriptionKey: @"Box64引擎初始化失败"}]];
            return NO;
        }
        [_executionLog addObject:@"✓ Box64引擎初始化成功（安全模式）"];
        
        [self notifyProgress:0.5 status:@"初始化Wine API..."];
        
        // 初始化Wine API
        _wineAPI = [[WineAPI alloc] init];
        if (!_wineAPI) {
            NSLog(@"[CompleteExecutionEngine] CRITICAL: Failed to initialize Wine API");
            [self notifyErrorSync:[NSError errorWithDomain:@"ExecutionEngine" code:ExecutionResultInitError userInfo:@{NSLocalizedDescriptionKey: @"Wine API初始化失败"}]];
            return NO;
        }
        [_executionLog addObject:@"✓ Wine API初始化成功"];
        
        [self notifyProgress:0.7 status:@"设置Wine环境..."];
        [self registerBasicWindowClasses];
        [_executionLog addObject:@"✓ 窗口类注册完成"];
        
        [self notifyProgress:0.8 status:@"创建虚拟Windows环境..."];
        [self createBasicWindowsEnvironment];
        [_executionLog addObject:@"✓ Windows环境创建完成"];
        
        [self notifyProgress:0.9 status:@"验证系统状态..."];
        
        // 执行初始化后的安全检查
        if (![self performInitializationSafetyCheck]) {
            NSLog(@"[CompleteExecutionEngine] CRITICAL: Initialization safety check failed");
            [self notifyErrorSync:[NSError errorWithDomain:@"ExecutionEngine" code:ExecutionResultInitError userInfo:@{NSLocalizedDescriptionKey: @"初始化安全检查失败"}]];
            return NO;
        }
        [_executionLog addObject:@"✓ 安全检查通过"];
        
        [self notifyProgress:1.0 status:@"初始化完成"];
        
        _isInitialized = YES;
        NSLog(@"[CompleteExecutionEngine] Complete execution engine initialized successfully with enhanced safety!");
        [_executionLog addObject:@"🎉 执行引擎初始化完成"];
        
        return YES;
        
    } @finally {
        [_executionLock unlock];
    }
}

- (BOOL)performInitializationSafetyCheck {
    // 检查JIT引擎状态
    if (!_jitEngine || !_jitEngine.isJITEnabled) {
        NSLog(@"[CompleteExecutionEngine] Safety check failed: JIT engine not ready");
        return NO;
    }
    
    // 检查Box64引擎状态
    if (!_box64Engine || !_box64Engine.isInitialized) {
        NSLog(@"[CompleteExecutionEngine] Safety check failed: Box64 engine not ready");
        return NO;
    }
    
    // 检查Box64安全状态
    if (![_box64Engine performSafetyCheck]) {
        NSLog(@"[CompleteExecutionEngine] Safety check failed: Box64 safety check failed");
        return NO;
    }
    
    // 检查Wine API状态
    if (!_wineAPI) {
        NSLog(@"[CompleteExecutionEngine] Safety check failed: Wine API not ready");
        return NO;
    }
    
    NSLog(@"[CompleteExecutionEngine] Initialization safety check passed");
    return YES;
}

- (void)registerBasicWindowClasses {
    // 这里应该实现基础窗口类注册
    // 由于这是模拟实现，我们只记录日志
    NSLog(@"[CompleteExecutionEngine] Registering basic window classes...");
    
    // 模拟注册常用窗口类
    NSArray *windowClasses = @[@"Button", @"Static", @"Edit", @"ListBox", @"ComboBox"];
    for (NSString *className in windowClasses) {
        NSLog(@"[CompleteExecutionEngine] Registered window class: %@", className);
    }
}

- (void)createBasicWindowsEnvironment {
    // 设置Windows环境变量
    setenv("WINEPREFIX", "/tmp/wine_prefix", 1);
    setenv("WINEDEBUG", "-all", 1);
    setenv("DISPLAY", ":0", 1);
    
    NSLog(@"[CompleteExecutionEngine] Basic Windows environment created");
}

#pragma mark - 程序执行 - 安全版本

- (void)executeProgram:(NSString *)programPath {
    [_executionLock lock];
    
    @try {
        if (!_isInitialized) {
            NSLog(@"[CompleteExecutionEngine] SECURITY: Cannot execute - engine not initialized");
            [self notifyErrorSync:[NSError errorWithDomain:@"ExecutionEngine" code:ExecutionResultNotInitialized userInfo:@{NSLocalizedDescriptionKey: @"执行引擎未初始化"}]];
            return;
        }
        
        if (_isExecuting) {
            NSLog(@"[CompleteExecutionEngine] SECURITY: Already executing a program");
            [self notifyErrorSync:[NSError errorWithDomain:@"ExecutionEngine" code:ExecutionResultAlreadyExecuting userInfo:@{NSLocalizedDescriptionKey: @"已有程序在执行中"}]];
            return;
        }
        
        if (!programPath || ![NSFileManager.defaultManager fileExistsAtPath:programPath]) {
            NSLog(@"[CompleteExecutionEngine] SECURITY: Invalid program path: %@", programPath);
            [self notifyErrorSync:[NSError errorWithDomain:@"ExecutionEngine" code:ExecutionResultInvalidFile userInfo:@{NSLocalizedDescriptionKey: @"程序文件不存在"}]];
            return;
        }
        
        NSLog(@"[CompleteExecutionEngine] Starting secure execution of: %@", programPath);
        
        _isExecuting = YES;
        _currentProgramPath = programPath;
        _executionStartTime = [NSDate timeIntervalSinceReferenceDate];
        
        // 清空执行日志
        [_executionLog removeAllObjects];
        [_executionLog addObject:[NSString stringWithFormat:@"开始执行程序: %@", [programPath lastPathComponent]]];
        
        // 通知开始执行
        [self notifyStartExecutionSync:programPath];
        
        // 设置安全定时器 - 10秒超时
        [self setupSafetyTimer:10.0];
        
        // 在后台线程执行程序
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            ExecutionResult result = [self executeFileAtPath:programPath];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [self finishExecution:result];
            });
        });
        
    } @finally {
        [_executionLock unlock];
    }
}

- (void)setupSafetyTimer:(NSTimeInterval)timeout {
    // 清除现有定时器
    if (_safetyTimer) {
        [_safetyTimer invalidate];
        _safetyTimer = nil;
    }
    
    // 在主线程创建定时器
    ENSURE_MAIN_THREAD_SYNC(^{
        self.safetyTimer = [NSTimer scheduledTimerWithTimeInterval:timeout
                                                          target:self
                                                        selector:@selector(safetyTimerFired:)
                                                        userInfo:nil
                                                         repeats:NO];
        NSLog(@"[CompleteExecutionEngine] Safety timer set for %.1f seconds", timeout);
    });
}

- (void)safetyTimerFired:(NSTimer *)timer {
    NSLog(@"[CompleteExecutionEngine] SAFETY: Execution timeout - forcing stop");
    
    [_executionLock lock];
    
    @try {
        if (_isExecuting) {
            [_executionLog addObject:@"⚠️ 执行超时，强制停止"];
            [self stopExecution];
            [self notifyErrorSync:[NSError errorWithDomain:@"ExecutionEngine" code:ExecutionResultTimeout userInfo:@{NSLocalizedDescriptionKey: @"程序执行超时"}]];
        }
    } @finally {
        [_executionLock unlock];
    }
}

- (ExecutionResult)executeFileAtPath:(NSString *)filePath {
    NSLog(@"[CompleteExecutionEngine] Executing file with enhanced safety: %@", filePath);
    
    @try {
        // 执行前安全检查
        if (![self performPreExecutionSafetyCheck]) {
            NSLog(@"[CompleteExecutionEngine] SECURITY: Pre-execution safety check failed");
            [_executionLog addObject:@"❌ 执行前安全检查失败"];
            return ExecutionResultSecurityError;
        }
        
        [self notifyProgress:0.1 status:@"读取程序文件..."];
        
        // 安全读取文件
        NSError *readError;
        NSData *programData = [NSData dataWithContentsOfFile:filePath options:NSDataReadingMappedIfSafe error:&readError];
        if (!programData) {
            NSLog(@"[CompleteExecutionEngine] SECURITY: Failed to read file: %@", readError.localizedDescription);
            [_executionLog addObject:[NSString stringWithFormat:@"❌ 文件读取失败: %@", readError.localizedDescription]];
            return ExecutionResultInvalidFile;
        }
        
        if (programData.length > 10 * 1024 * 1024) {  // 10MB限制
            NSLog(@"[CompleteExecutionEngine] SECURITY: File too large: %zu bytes", programData.length);
            [_executionLog addObject:@"❌ 文件过大，拒绝执行"];
            return ExecutionResultSecurityError;
        }
        
        [_executionLog addObject:[NSString stringWithFormat:@"✓ 文件读取成功 (%zu 字节)", programData.length]];
        
        [self notifyProgress:0.3 status:@"分析PE文件..."];
        
        // PE文件分析
        ExecutionResult analysisResult = [self analyzePEFile:programData];
        if (analysisResult != ExecutionResultSuccess) {
            return analysisResult;
        }
        
        [self notifyProgress:0.5 status:@"重置执行环境..."];
        
        // 重置执行环境到安全状态
        [_box64Engine resetToSafeState];
        [_executionLog addObject:@"✓ 执行环境重置"];
        
        [self notifyProgress:0.7 status:@"执行程序代码..."];
        
        // 执行程序代码 - 使用安全模式
        BOOL executionSuccess = [_box64Engine executeWithSafetyCheck:programData.bytes
                                                              length:programData.length
                                                      maxInstructions:1000];  // 限制最大指令数
        
        if (!executionSuccess) {
            NSLog(@"[CompleteExecutionEngine] SECURITY: Code execution failed");
            [_executionLog addObject:@"❌ 代码执行失败"];
            
            // 获取详细错误信息
            NSString *lastError = [_box64Engine getLastError];
            if (lastError) {
                [_executionLog addObject:[NSString stringWithFormat:@"错误详情: %@", lastError]];
            }
            
            // 获取安全警告
            NSArray<NSString *> *warnings = [_box64Engine getSafetyWarnings];
            for (NSString *warning in warnings) {
                [_executionLog addObject:[NSString stringWithFormat:@"⚠️ 安全警告: %@", warning]];
            }
            
            return ExecutionResultExecutionError;
        }
        
        [_executionLog addObject:@"✓ 程序执行完成"];
        
        [self notifyProgress:0.9 status:@"执行后安全检查..."];
        
        // 执行后安全检查
        if (![self performPostExecutionSafetyCheck]) {
            NSLog(@"[CompleteExecutionEngine] SECURITY: Post-execution safety check failed");
            [_executionLog addObject:@"⚠️ 执行后安全检查发现异常"];
            return ExecutionResultSecurityWarning;
        }
        
        [self notifyProgress:1.0 status:@"执行完成"];
        
        NSTimeInterval executionTime = [NSDate timeIntervalSinceReferenceDate] - _executionStartTime;
        [_executionLog addObject:[NSString stringWithFormat:@"🎉 执行成功 (耗时: %.2f秒)", executionTime]];
        
        NSLog(@"[CompleteExecutionEngine] Program execution completed successfully");
        return ExecutionResultSuccess;
        
    } @catch (NSException *exception) {
        NSLog(@"[CompleteExecutionEngine] CRITICAL: Exception during execution: %@", exception.reason);
        [_executionLog addObject:[NSString stringWithFormat:@"💥 执行异常: %@", exception.reason]];
        
        // 转储崩溃状态
        [self dumpCrashState];
        
        return ExecutionResultCrash;
    }
}

- (BOOL)performPreExecutionSafetyCheck {
    // 检查Box64引擎状态
    if (![_box64Engine performSafetyCheck]) {
        NSLog(@"[CompleteExecutionEngine] Pre-execution safety check: Box64 engine not safe");
        return NO;
    }
    
    // 检查JIT引擎状态
    if (!_jitEngine.isJITEnabled) {
        NSLog(@"[CompleteExecutionEngine] Pre-execution safety check: JIT engine not ready");
        return NO;
    }
    
    // 检查内存状态
    NSDictionary *systemState = [_box64Engine getSystemState];
    if (![systemState[@"safe_mode"] boolValue]) {
        NSLog(@"[CompleteExecutionEngine] Pre-execution safety check: Box64 not in safe mode");
        return NO;
    }
    
    NSLog(@"[CompleteExecutionEngine] Pre-execution safety check passed");
    return YES;
}

- (BOOL)performPostExecutionSafetyCheck {
    // 检查Box64引擎执行后状态
    if (![_box64Engine performSafetyCheck]) {
        NSLog(@"[CompleteExecutionEngine] Post-execution safety check: Box64 safety check failed");
        return NO;
    }
    
    // 检查是否有安全警告
    NSArray<NSString *> *warnings = [_box64Engine getSafetyWarnings];
    if (warnings.count > 0) {
        NSLog(@"[CompleteExecutionEngine] Post-execution safety check: %lu safety warnings", (unsigned long)warnings.count);
        for (NSString *warning in warnings) {
            NSLog(@"[CompleteExecutionEngine] Safety warning: %@", warning);
        }
        return NO;  // 有警告就认为不安全
    }
    
    NSLog(@"[CompleteExecutionEngine] Post-execution safety check passed");
    return YES;
}

- (ExecutionResult)analyzePEFile:(NSData *)fileData {
    if (!fileData || fileData.length < 64) {
        NSLog(@"[CompleteExecutionEngine] SECURITY: Invalid PE file - too small");
        [_executionLog addObject:@"❌ PE文件无效（文件过小）"];
        return ExecutionResultInvalidFile;
    }
    
    const uint8_t *bytes = fileData.bytes;
    
    // 检查DOS头
    if (bytes[0] != 'M' || bytes[1] != 'Z') {
        NSLog(@"[CompleteExecutionEngine] SECURITY: Invalid DOS signature");
        [_executionLog addObject:@"❌ DOS签名无效"];
        return ExecutionResultInvalidFile;
    }
    
    // 获取PE头偏移
    uint32_t peOffset = *(uint32_t *)(bytes + 60);
    if (peOffset >= fileData.length - 4) {
        NSLog(@"[CompleteExecutionEngine] SECURITY: Invalid PE offset");
        [_executionLog addObject:@"❌ PE头偏移无效"];
        return ExecutionResultInvalidFile;
    }
    
    // 检查PE签名
    if (*(uint32_t *)(bytes + peOffset) != 0x00004550) {  // "PE\0\0"
        NSLog(@"[CompleteExecutionEngine] SECURITY: Invalid PE signature");
        [_executionLog addObject:@"❌ PE签名无效"];
        return ExecutionResultInvalidFile;
    }
    
    // 检查架构
    uint16_t machine = *(uint16_t *)(bytes + peOffset + 4);
    NSString *architecture;
    
    switch (machine) {
        case 0x014c:  // IMAGE_FILE_MACHINE_I386
            architecture = @"x86 (32-bit)";
            break;
        case 0x8664:  // IMAGE_FILE_MACHINE_AMD64
            architecture = @"x64 (64-bit)";
            break;
        case 0x01c0:  // IMAGE_FILE_MACHINE_ARM
            architecture = @"ARM (32-bit)";
            break;
        case 0xaa64:  // IMAGE_FILE_MACHINE_ARM64
            architecture = @"ARM64 (64-bit)";
            break;
        default:
            NSLog(@"[CompleteExecutionEngine] SECURITY: Unsupported architecture: 0x%04x", machine);
            [_executionLog addObject:[NSString stringWithFormat:@"❌ 不支持的架构: 0x%04x", machine]];
            return ExecutionResultInvalidFile;
    }
    
    [self notifyOutputSync:[NSString stringWithFormat:@"PE文件分析完成: %@", architecture]];
    [_executionLog addObject:[NSString stringWithFormat:@"✓ PE文件分析完成: %@", architecture]];
    NSLog(@"[CompleteExecutionEngine] PE analysis successful: %@", architecture);
    
    return ExecutionResultSuccess;
}

- (void)finishExecution:(ExecutionResult)result {
    [_executionLock lock];
    
    @try {
        // 清除安全定时器
        if (_safetyTimer) {
            [_safetyTimer invalidate];
            _safetyTimer = nil;
        }
        
        NSString *resultString = [self executionResultToString:result];
        NSTimeInterval totalTime = [NSDate timeIntervalSinceReferenceDate] - _executionStartTime;
        
        [_executionLog addObject:[NSString stringWithFormat:@"执行结果: %@ (总耗时: %.2f秒)", resultString, totalTime]];
        
        NSLog(@"[CompleteExecutionEngine] Execution finished: %@ (%.2f seconds)", resultString, totalTime);
        
        // 通知执行完成
        [self notifyFinishExecutionSync:_currentProgramPath result:result];
        
        // 输出执行日志
        for (NSString *logEntry in _executionLog) {
            [self notifyOutputSync:logEntry];
        }
        
        // 如果执行失败，输出调试信息
        if (result != ExecutionResultSuccess) {
            [self outputDebugInformation];
        }
        
        // 重置状态
        _isExecuting = NO;
        _currentProgramPath = nil;
        _executionStartTime = 0;
        
    } @finally {
        [_executionLock unlock];
    }
}

- (void)outputDebugInformation {
    NSLog(@"[CompleteExecutionEngine] Outputting debug information...");
    
    // 输出Box64状态
    NSDictionary *box64State = [_box64Engine getSystemState];
    [self notifyOutputSync:@"=== Box64 引擎状态 ==="];
    for (NSString *key in box64State) {
        [self notifyOutputSync:[NSString stringWithFormat:@"%@: %@", key, box64State[key]]];
    }
    
    // 输出安全警告
    NSArray<NSString *> *warnings = [_box64Engine getSafetyWarnings];
    if (warnings.count > 0) {
        [self notifyOutputSync:@"=== 安全警告 ==="];
        for (NSString *warning in warnings) {
            [self notifyOutputSync:[NSString stringWithFormat:@"⚠️ %@", warning]];
        }
    }
    
    // 输出最后错误
    NSString *lastError = [_box64Engine getLastError];
    if (lastError) {
        [self notifyOutputSync:[NSString stringWithFormat:@"最后错误: %@", lastError]];
    }
}

- (void)dumpCrashState {
    NSLog(@"[CompleteExecutionEngine] ===== CRASH STATE DUMP =====");
    
    // 转储Box64状态
    [_box64Engine dumpRegisters];
    [_box64Engine dumpMemoryRegions];
    
    // 转储JIT状态
    [_jitEngine dumpJITStats];
    
    // 转储执行状态
    NSLog(@"[CompleteExecutionEngine] Current program: %@", _currentProgramPath);
    NSLog(@"[CompleteExecutionEngine] Execution time: %.2f seconds", [NSDate timeIntervalSinceReferenceDate] - _executionStartTime);
    NSLog(@"[CompleteExecutionEngine] Execution log:");
    for (NSString *logEntry in _executionLog) {
        NSLog(@"[CompleteExecutionEngine]   %@", logEntry);
    }
    
    NSLog(@"[CompleteExecutionEngine] ==============================");
}

- (NSString *)executionResultToString:(ExecutionResult)result {
    switch (result) {
        case ExecutionResultSuccess: return @"成功";
        case ExecutionResultInvalidFile: return @"无效文件";
        case ExecutionResultInitError: return @"初始化错误";
        case ExecutionResultExecutionError: return @"执行错误";
        case ExecutionResultTimeout: return @"执行超时";
        case ExecutionResultNotInitialized: return @"未初始化";
        case ExecutionResultAlreadyExecuting: return @"重复执行";
        case ExecutionResultSecurityError: return @"安全错误";
        case ExecutionResultSecurityWarning: return @"安全警告";
        case ExecutionResultCrash: return @"程序崩溃";
        default: return @"未知错误";
    }
}

- (void)stopExecution {
    [_executionLock lock];
    
    @try {
        if (!_isExecuting) return;
        
        NSLog(@"[CompleteExecutionEngine] Stopping execution...");
        
        // 停止定时器
        if (_safetyTimer) {
            [_safetyTimer invalidate];
            _safetyTimer = nil;
        }
        
        // 重置Box64引擎到安全状态
        [_box64Engine resetToSafeState];
        
        _isExecuting = NO;
        [_executionLog addObject:@"程序执行已停止"];
        [self notifyOutputSync:@"程序执行已停止"];
        
    } @finally {
        [_executionLock unlock];
    }
}

#pragma mark - 系统状态

- (NSDictionary *)getSystemInfo {
    [_executionLock lock];
    
    @try {
        NSMutableDictionary *info = [NSMutableDictionary dictionary];
        
        info[@"initialized"] = @(_isInitialized);
        info[@"executing"] = @(_isExecuting);
        info[@"current_program"] = _currentProgramPath ?: @"无";
        
        if (_jitEngine) {
            info[@"jit_enabled"] = @(_jitEngine.isJITEnabled);
            info[@"jit_memory"] = @(_jitEngine.totalJITMemory);
        }
        
        if (_box64Engine) {
            info[@"box64_initialized"] = @(_box64Engine.isInitialized);
            info[@"box64_safe_mode"] = @(_box64Engine.isSafeMode);
            NSDictionary *box64State = [_box64Engine getSystemState];
            [info addEntriesFromDictionary:box64State];
        }
        
        if (_wineAPI) {
            info[@"wine_windows"] = @(_wineAPI.windows.count);
        }
        
        return [info copy];
        
    } @finally {
        [_executionLock unlock];
    }
}

- (NSString *)getEngineStatus {
    [_executionLock lock];
    
    @try {
        if (!_isInitialized) {
            return @"未初始化";
        }
        
        if (_isExecuting) {
            NSTimeInterval elapsed = [NSDate timeIntervalSinceReferenceDate] - _executionStartTime;
            return [NSString stringWithFormat:@"正在执行: %@ (%.1f秒)", [_currentProgramPath lastPathComponent], elapsed];
        }
        
        return @"就绪";
        
    } @finally {
        [_executionLock unlock];
    }
}

- (NSArray<NSString *> *)getExecutionLog {
    [_executionLock lock];
    
    @try {
        return [_executionLog copy];
    } @finally {
        [_executionLock unlock];
    }
}

#pragma mark - 委托通知方法 - 线程安全版本

- (void)notifyStartExecutionSync:(NSString *)programPath {
    ENSURE_MAIN_THREAD_ASYNC(^{
        if ([self.delegate respondsToSelector:@selector(executionEngine:didStartExecution:)]) {
            [self.delegate executionEngine:self didStartExecution:programPath];
        }
    });
}

- (void)notifyFinishExecutionSync:(NSString *)programPath result:(ExecutionResult)result {
    ENSURE_MAIN_THREAD_ASYNC(^{
        if ([self.delegate respondsToSelector:@selector(executionEngine:didFinishExecution:result:)]) {
            [self.delegate executionEngine:self didFinishExecution:programPath result:result];
        }
    });
}

- (void)notifyOutputSync:(NSString *)output {
    ENSURE_MAIN_THREAD_ASYNC(^{
        if ([self.delegate respondsToSelector:@selector(executionEngine:didReceiveOutput:)]) {
            [self.delegate executionEngine:self didReceiveOutput:output];
        }
    });
}

- (void)notifyErrorSync:(NSError *)error {
    ENSURE_MAIN_THREAD_ASYNC(^{
        if ([self.delegate respondsToSelector:@selector(executionEngine:didEncounterError:)]) {
            [self.delegate executionEngine:self didEncounterError:error];
        }
    });
}

- (void)notifyProgress:(float)progress status:(NSString *)status {
    ENSURE_MAIN_THREAD_ASYNC(^{
        if ([self.delegate respondsToSelector:@selector(executionEngine:didUpdateProgress:status:)]) {
            [self.delegate executionEngine:self didUpdateProgress:progress status:status];
        }
    });
}

#pragma mark - 清理

- (void)cleanup {
    [_executionLock lock];
    
    @try {
        NSLog(@"[CompleteExecutionEngine] Cleaning up execution engine...");
        
        // 停止执行
        [self stopExecution];
        
        // 清理各个引擎
        if (_box64Engine) {
            [_box64Engine cleanup];
        }
        
        if (_jitEngine) {
            [_jitEngine cleanup];
        }
        
        // 清理状态
        [_executionLog removeAllObjects];
        _isInitialized = NO;
        _currentProgramPath = nil;
        _executionStartTime = 0;
        
        NSLog(@"[CompleteExecutionEngine] Cleanup completed");
        
    } @finally {
        [_executionLock unlock];
    }
}

@end
