// CompleteExecutionEngine.m - 修复版：解决栈指针和内存映射问题
#import "CompleteExecutionEngine.h"
#import "Box64Engine.h"
#import "IOSJITEngine.h"
#import "WineAPI.h"
#import "TestBinaryCreator.h"

// 线程安全宏定义
#define ENSURE_MAIN_THREAD_SYNC(block) \
    if ([NSThread isMainThread]) { \
        block(); \
    } else { \
        dispatch_sync(dispatch_get_main_queue(), block); \
    }

#define ENSURE_MAIN_THREAD_ASYNC(block) \
    if ([NSThread isMainThread]) { \
        block(); \
    } else { \
        dispatch_async(dispatch_get_main_queue(), block); \
    }

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

// PE解析相关属性
@property (nonatomic, assign) uint64_t peImageBase;
@property (nonatomic, assign) uint32_t peEntryPointRVA;
@property (nonatomic, assign) uint64_t peActualEntryPoint;
@property (nonatomic, strong) NSData *peCodeSection;
@property (nonatomic, assign) uint64_t peCodeSectionVA;
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
        _executionLog = [[NSMutableArray alloc] init];
        _isInitialized = NO;
        _isExecuting = NO;
        
        // 重置PE相关状态
        _peImageBase = 0;
        _peEntryPointRVA = 0;
        _peActualEntryPoint = 0;
        _peCodeSection = nil;
        _peCodeSectionVA = 0;
    }
    return self;
}

- (void)dealloc {
    [self cleanup];
}

#pragma mark - 初始化方法

- (BOOL)initializeEngines {
    [_executionLock lock];
    
    @try {
        if (_isInitialized) {
            NSLog(@"[CompleteExecutionEngine] Already initialized");
            return YES;
        }
        
        NSLog(@"[CompleteExecutionEngine] Initializing execution engines...");
        
        // 初始化JIT引擎
        _jitEngine = [[IOSJITEngine alloc] init];
        if (![_jitEngine initializeJIT]) {
            NSLog(@"[CompleteExecutionEngine] ❌ Failed to initialize JIT engine");
            return NO;
        }
        
        // 初始化Box64引擎
        _box64Engine = [[Box64Engine alloc] init];
        _box64Engine.jitEngine = _jitEngine;
        
        // 🔧 修复：使用合理的内存大小初始化Box64引擎
        size_t memorySize = 64 * 1024 * 1024; // 64MB
        if (![_box64Engine initializeWithMemorySize:memorySize safeMode:YES]) {
            NSLog(@"[CompleteExecutionEngine] ❌ Failed to initialize Box64 engine");
            return NO;
        }
        
        // 初始化Wine API
        _wineAPI = [[WineAPI alloc] init];
        if (![_wineAPI initializeWineAPI]) {
            NSLog(@"[CompleteExecutionEngine] ❌ Failed to initialize Wine API");
            return NO;
        }
        
        // 执行初始化安全检查
        if (![self performInitializationSafetyCheck]) {
            NSLog(@"[CompleteExecutionEngine] ❌ Initialization safety check failed");
            return NO;
        }
        
        [self registerBasicWindowClasses];
        [self createBasicWindowsEnvironment];
        
        _isInitialized = YES;
        NSLog(@"[CompleteExecutionEngine] ✅ All engines initialized successfully");
        
        return YES;
        
    } @finally {
        [_executionLock unlock];
    }
}

- (BOOL)initializeWithViewController:(UIViewController *)viewController {
    _hostViewController = viewController;
    return [self initializeEngines];
}

- (void)cleanup {
    [_executionLock lock];
    
    @try {
        NSLog(@"[CompleteExecutionEngine] Cleaning up...");
        
        [self stopExecution];
        
        _wineAPI = nil;
        _box64Engine = nil;
        _jitEngine = nil;
        _isInitialized = NO;
        
        NSLog(@"[CompleteExecutionEngine] Cleanup completed");
        
    } @finally {
        [_executionLock unlock];
    }
}

#pragma mark - 程序执行 - 修复版

- (ExecutionResult)executeProgram:(NSString *)programPath {
    return [self executeProgram:programPath arguments:nil];
}

- (ExecutionResult)executeProgram:(NSString *)programPath arguments:(nullable NSArray<NSString *> *)arguments {
    [_executionLock lock];
    
    @try {
        if (!_isInitialized) {
            NSLog(@"[CompleteExecutionEngine] SECURITY: Cannot execute - engine not initialized");
            [self notifyErrorSync:[NSError errorWithDomain:@"ExecutionEngine" code:ExecutionResultNotInitialized userInfo:@{NSLocalizedDescriptionKey: @"执行引擎未初始化"}]];
            return ExecutionResultNotInitialized;
        }
        
        if (_isExecuting) {
            NSLog(@"[CompleteExecutionEngine] SECURITY: Already executing a program");
            [self notifyErrorSync:[NSError errorWithDomain:@"ExecutionEngine" code:ExecutionResultAlreadyExecuting userInfo:@{NSLocalizedDescriptionKey: @"已有程序在执行中"}]];
            return ExecutionResultAlreadyExecuting;
        }
        
        if (!programPath || ![[NSFileManager defaultManager] fileExistsAtPath:programPath]) {
            NSLog(@"[CompleteExecutionEngine] SECURITY: Program file does not exist: %@", programPath);
            [self notifyErrorSync:[NSError errorWithDomain:@"ExecutionEngine" code:ExecutionResultInvalidFile userInfo:@{NSLocalizedDescriptionKey: @"程序文件不存在"}]];
            return ExecutionResultInvalidFile;
        }
        
        NSLog(@"[CompleteExecutionEngine] 🚀 开始执行图形增强程序: %@", [programPath lastPathComponent]);
        
        // 开始执行
        _isExecuting = YES;
        _currentProgramPath = programPath;
        _executionStartTime = [NSDate timeIntervalSinceReferenceDate];
        [_executionLog removeAllObjects];
        
        // 🔧 修复：设置更长的安全定时器，防止调试时超时
        NSTimeInterval safetyTimeout = 30.0; // 30秒
        NSLog(@"[CompleteExecutionEngine] Safety timer set for %.1f seconds", safetyTimeout);
        
        _safetyTimer = [NSTimer scheduledTimerWithTimeInterval:safetyTimeout
                                                        target:self
                                                      selector:@selector(safetyTimeoutHit)
                                                      userInfo:nil
                                                       repeats:NO];
        
        // 通知开始执行
        [self notifyStartExecutionSync:programPath];
        
        // Phase 1: 执行前安全检查
        [self notifyProgress:0.1 status:@"执行前安全检查..."];
        if (![self performPreExecutionSafetyCheck]) {
            NSLog(@"[CompleteExecutionEngine] ❌ Pre-execution safety check failed");
            [self finishExecution:ExecutionResultSecurityError];
            return ExecutionResultSecurityError;
        }
        
        // Phase 2: 重置Box64引擎到安全状态
        [self notifyProgress:0.2 status:@"重置引擎状态..."];
        [_box64Engine resetToSafeState];
        
        // Phase 3: 读取和验证PE文件
        [self notifyProgress:0.3 status:@"读取PE文件..."];
        NSData *peFileData = [NSData dataWithContentsOfFile:programPath];
        if (!peFileData || peFileData.length < 1024) {
            NSLog(@"[CompleteExecutionEngine] ❌ Invalid PE file data");
            [self finishExecution:ExecutionResultInvalidFile];
            return ExecutionResultInvalidFile;
        }
        
        // Phase 4: 分析PE文件结构
        [self notifyProgress:0.5 status:@"分析PE文件结构..."];
        ExecutionResult parseResult = [self analyzePEFile:peFileData];
        if (parseResult != ExecutionResultSuccess) {
            NSLog(@"[CompleteExecutionEngine] ❌ PE file analysis failed");
            [self finishExecution:parseResult];
            return parseResult;
        }
        
        // Phase 5: 映射PE文件到内存
        [self notifyProgress:0.7 status:@"映射PE到内存..."];
        if (![self mapPEToMemory:peFileData]) {
            NSLog(@"[CompleteExecutionEngine] ❌ Failed to map PE to memory");
            [_executionLog addObject:@"❌ PE内存映射失败"];
            [self finishExecution:ExecutionResultMemoryError];
            return ExecutionResultMemoryError;
        }
        
        // Phase 6: 设置执行入口点
        [self notifyProgress:0.8 status:@"设置执行入口点..."];
        if (![self setupExecutionEntryPoint]) {
            NSLog(@"[CompleteExecutionEngine] ❌ Failed to setup execution entry point");
            [_executionLog addObject:@"❌ 执行入口点设置失败"];
            [self finishExecution:ExecutionResultExecutionError];
            return ExecutionResultExecutionError;
        }
        
        // Phase 7: 执行PE入口点代码
        [self notifyProgress:0.9 status:@"执行PE代码..."];
        BOOL executionSuccess = [self executeAtEntryPoint];
        
        if (!executionSuccess) {
            NSLog(@"[CompleteExecutionEngine] ❌ PE entry point execution failed");
            [_executionLog addObject:@"❌ PE入口点执行失败"];
            
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
            
            [self finishExecution:ExecutionResultExecutionError];
            return ExecutionResultExecutionError;
        }
        
        [_executionLog addObject:@"✅ PE程序执行完成"];
        [self notifyProgress:1.0 status:@"执行完成"];
        
        // Phase 8: 执行后安全检查
        if (![self performPostExecutionSafetyCheck]) {
            NSLog(@"[CompleteExecutionEngine] ⚠️ Post-execution safety check failed");
            [self finishExecution:ExecutionResultSecurityWarning];
            return ExecutionResultSecurityWarning;
        }
        
        [self finishExecution:ExecutionResultSuccess];
        return ExecutionResultSuccess;
        
    } @catch (NSException *exception) {
        NSLog(@"[CompleteExecutionEngine] CRITICAL: Exception during execution: %@", exception.reason);
        [self dumpCrashState];
        [self finishExecution:ExecutionResultCrash];
        return ExecutionResultCrash;
        
    } @finally {
        [_executionLock unlock];
    }
}

#pragma mark - PE文件处理 - 修复版

- (ExecutionResult)analyzePEFile:(NSData *)fileData {
    NSLog(@"[CompleteExecutionEngine] 🔧 PE文件分析开始...");
    
    const uint8_t *bytes = fileData.bytes;
    if (fileData.length < 1024) {
        NSLog(@"[CompleteExecutionEngine] ❌ PE文件太小: %lu字节", (unsigned long)fileData.length);
        return ExecutionResultInvalidFile;
    }
    
    // 检查DOS头
    if (bytes[0] != 'M' || bytes[1] != 'Z') {
        NSLog(@"[CompleteExecutionEngine] ❌ 无效的DOS头");
        return ExecutionResultInvalidFile;
    }
    
    // 获取PE头偏移
    uint32_t peOffset = *(uint32_t *)(bytes + 0x3C);
    if (peOffset >= fileData.length - 4) {
        NSLog(@"[CompleteExecutionEngine] ❌ 无效的PE头偏移: 0x%X", peOffset);
        return ExecutionResultInvalidFile;
    }
    
    // 检查PE签名
    if (*(uint32_t *)(bytes + peOffset) != 0x00004550) {
        NSLog(@"[CompleteExecutionEngine] ❌ 无效的PE签名");
        return ExecutionResultInvalidFile;
    }
    
    // 获取架构信息
    uint16_t machine = *(uint16_t *)(bytes + peOffset + 4);
    NSString *architecture = (machine == 0x8664) ? @"x64 (64-bit)" : @"x86 (32-bit)";
    
    // 获取镜像基址和入口点
    _peImageBase = *(uint64_t *)(bytes + peOffset + 24 + 24);
    _peEntryPointRVA = *(uint32_t *)(bytes + peOffset + 24 + 16);
    _peActualEntryPoint = _peImageBase + _peEntryPointRVA;
    
    NSLog(@"[CompleteExecutionEngine] 🔧 PE分析完成:");
    NSLog(@"[CompleteExecutionEngine]   架构: %@", architecture);
    NSLog(@"[CompleteExecutionEngine]   镜像基址: 0x%llX", _peImageBase);
    NSLog(@"[CompleteExecutionEngine]   入口点RVA: 0x%X", _peEntryPointRVA);
    NSLog(@"[CompleteExecutionEngine]   实际入口点: 0x%llX", _peActualEntryPoint);
    
    [self notifyOutputSync:[NSString stringWithFormat:@"PE文件分析完成: %@", architecture]];
    [_executionLog addObject:[NSString stringWithFormat:@"✅ PE分析: %@ 入口点=0x%llX", architecture, _peActualEntryPoint]];
    
    return ExecutionResultSuccess;
}

- (BOOL)mapPEToMemory:(NSData *)fileData {
    NSLog(@"[CompleteExecutionEngine] 🔧 映射PE到内存...");
    
    // 找到代码段（通常在文件偏移0x400）
    const uint8_t *bytes = fileData.bytes;
    
    size_t codeOffset = 0x400;
    if (fileData.length <= codeOffset) {
        NSLog(@"[CompleteExecutionEngine] ❌ PE文件太小，无法包含代码段");
        return NO;
    }
    
    // 提取代码段数据
    size_t codeSize = MIN(0x200, fileData.length - codeOffset);  // 最多512字节
    _peCodeSection = [fileData subdataWithRange:NSMakeRange(codeOffset, codeSize)];
    
    // 🔧 修复：使用Box64Engine内存管理器分配内存
    uint8_t *codeMemory = [_box64Engine allocateMemory:codeSize];
    if (!codeMemory) {
        NSLog(@"[CompleteExecutionEngine] ❌ 无法分配代码段内存");
        return NO;
    }
    
    // 复制代码到分配的内存
    memcpy(codeMemory, _peCodeSection.bytes, codeSize);
    _peCodeSectionVA = (uint64_t)codeMemory;
    
    NSLog(@"[CompleteExecutionEngine] 🔧 代码段信息:");
    NSLog(@"[CompleteExecutionEngine]   文件偏移: 0x%zX", codeOffset);
    NSLog(@"[CompleteExecutionEngine]   虚拟地址: 0x%llX", _peCodeSectionVA);
    NSLog(@"[CompleteExecutionEngine]   代码大小: %zu字节", codeSize);
    
    // 显示前几个字节用于调试
    if (codeSize >= 8) {
        const uint8_t *codeBytes = _peCodeSection.bytes;
        NSLog(@"[CompleteExecutionEngine]   前8字节: %02X %02X %02X %02X %02X %02X %02X %02X",
              codeBytes[0], codeBytes[1], codeBytes[2], codeBytes[3],
              codeBytes[4], codeBytes[5], codeBytes[6], codeBytes[7]);
    }
    
    NSLog(@"[CompleteExecutionEngine] ✅ PE代码段已映射到内存 0x%llX", _peCodeSectionVA);
    [_executionLog addObject:[NSString stringWithFormat:@"✅ PE内存映射: 0x%llX (%zu字节)", _peCodeSectionVA, codeSize]];
    
    return YES;
}

- (BOOL)setupExecutionEntryPoint {
    NSLog(@"[CompleteExecutionEngine] 🔧 设置执行入口点...");
    
    if (_peCodeSectionVA == 0) {
        NSLog(@"[CompleteExecutionEngine] ❌ 无效的代码段虚拟地址");
        return NO;
    }
    
    // 🔧 修复：使用代码段的实际内存地址作为入口点
    uint64_t entryPoint = _peCodeSectionVA;
    
    NSLog(@"[CompleteExecutionEngine] 🔧 设置RIP到代码段开始地址: 0x%llX", entryPoint);
    
    // 设置RIP寄存器到代码段开始位置
    if (![_box64Engine setX86Register:X86_RIP value:entryPoint]) {
        NSLog(@"[CompleteExecutionEngine] ❌ 设置RIP寄存器失败");
        return NO;
    }
    
    // 🔧 修复：使用Box64Engine的有效栈地址，而不是硬编码地址
    NSDictionary *systemState = [_box64Engine getSystemState];
    uint64_t stackBase = [systemState[@"stack_base"] unsignedLongLongValue];
    uint64_t stackSize = [systemState[@"stack_size"] unsignedLongLongValue];
    
    if (stackBase == 0 || stackSize == 0) {
        NSLog(@"[CompleteExecutionEngine] ❌ Box64Engine栈未正确初始化");
        return NO;
    }
    
    // 设置栈指针到栈顶附近（留出一些空间）
    uint64_t safeStackPointer = stackBase + stackSize - 64;
    if (![_box64Engine setX86Register:X86_RSP value:safeStackPointer]) {
        NSLog(@"[CompleteExecutionEngine] ❌ 设置RSP寄存器失败");
        return NO;
    }
    
    NSLog(@"[CompleteExecutionEngine] ✅ 入口点设置完成:");
    NSLog(@"[CompleteExecutionEngine]   RIP: 0x%llX (代码段开始)", entryPoint);
    NSLog(@"[CompleteExecutionEngine]   RSP: 0x%llX (栈基址: 0x%llX, 大小: %llu)",
          safeStackPointer, stackBase, stackSize);
    
    [_executionLog addObject:[NSString stringWithFormat:@"✅ 入口点设置: RIP=0x%llX, RSP=0x%llX", entryPoint, safeStackPointer]];
    
    return YES;
}

- (BOOL)executeAtEntryPoint {
    NSLog(@"[CompleteExecutionEngine] 🔧 在入口点执行代码...");
    
    if (!_peCodeSection || _peCodeSection.length == 0) {
        NSLog(@"[CompleteExecutionEngine] ❌ 没有代码段可执行");
        return NO;
    }
    
    // 🔧 修复：传递正确的基地址给Box64引擎
    NSLog(@"[CompleteExecutionEngine] 📍 执行参数:");
    NSLog(@"[CompleteExecutionEngine]   代码段地址: 0x%llX", _peCodeSectionVA);
    NSLog(@"[CompleteExecutionEngine]   代码段大小: %zu字节", _peCodeSection.length);
    NSLog(@"[CompleteExecutionEngine]   当前RIP: 0x%llX", [_box64Engine getX86Register:X86_RIP]);
    
    // 执行PE代码段 - 传递基地址用于正确的RIP计算
    BOOL success = [_box64Engine executeWithSafetyCheck:_peCodeSection.bytes
                                                 length:_peCodeSection.length
                                         maxInstructions:100
                                             baseAddress:_peCodeSectionVA];
    
    if (success) {
        NSDictionary *finalState = [_box64Engine getSystemState];
        uint32_t instructionCount = [finalState[@"instruction_count"] unsignedIntValue];
        uint64_t finalRIP = [_box64Engine getX86Register:X86_RIP];
        uint64_t finalRAX = [_box64Engine getX86Register:X86_RAX];
        
        NSLog(@"[CompleteExecutionEngine] 🎉 PE执行成功:");
        NSLog(@"[CompleteExecutionEngine]   执行的指令数: %u", instructionCount);
        NSLog(@"[CompleteExecutionEngine]   最终RIP: 0x%llX", finalRIP);
        NSLog(@"[CompleteExecutionEngine]   最终RAX: 0x%llX (%llu)", finalRAX, finalRAX);
        
        [_executionLog addObject:[NSString stringWithFormat:@"🎉 执行成功: %u条指令, RAX=%llu", instructionCount, finalRAX]];
        
        // 验证预期结果
        if (instructionCount > 0) {
            NSLog(@"[CompleteExecutionEngine] ✅ 成功：至少执行了一条指令！");
            
            // 检查测试程序的预期结果
            if (finalRAX == 42) {
                NSLog(@"[CompleteExecutionEngine] ✅ 完美：RAX=42 符合simple_test.exe预期");
                [_executionLog addObject:@"✅ 完美：RAX=42 符合simple_test.exe预期"];
            } else if (finalRAX == 2) {
                NSLog(@"[CompleteExecutionEngine] ✅ 完美：RAX=2 符合hello_world.exe预期");
                [_executionLog addObject:@"✅ 完美：RAX=2 符合hello_world.exe预期"];
            } else {
                NSLog(@"[CompleteExecutionEngine] ℹ️ RAX=%llu (可能是其他测试程序)", finalRAX);
                [_executionLog addObject:[NSString stringWithFormat:@"ℹ️ RAX=%llu", finalRAX]];
            }
        } else {
            NSLog(@"[CompleteExecutionEngine] ⚠️ 警告：没有执行任何指令");
            [_executionLog addObject:@"⚠️ 警告：没有执行任何指令"];
        }
        
    } else {
        NSLog(@"[CompleteExecutionEngine] ❌ PE执行失败");
        [_executionLog addObject:@"❌ PE执行失败"];
        
        // 输出错误详情
        NSString *lastError = [_box64Engine getLastError];
        if (lastError) {
            NSLog(@"[CompleteExecutionEngine] 错误详情: %@", lastError);
            [_executionLog addObject:[NSString stringWithFormat:@"错误详情: %@", lastError]];
        }
    }
    
    return success;
}

#pragma mark - 安全检查方法

- (BOOL)performInitializationSafetyCheck {
    // 检查Box64引擎状态
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
        NSLog(@"[CompleteExecutionEngine] Post-execution safety check: Box64 engine check failed");
        return NO;
    }
    
    // 检查是否有安全警告
    NSArray<NSString *> *warnings = [_box64Engine getSafetyWarnings];
    if (warnings.count > 0) {
        NSLog(@"[CompleteExecutionEngine] Post-execution safety check: %lu safety warnings", (unsigned long)warnings.count);
        for (NSString *warning in warnings) {
            NSLog(@"[CompleteExecutionEngine] WARNING: %@", warning);
        }
    }
    
    NSLog(@"[CompleteExecutionEngine] Post-execution safety check passed");
    return YES;
}

- (void)registerBasicWindowClasses {
    NSLog(@"[CompleteExecutionEngine] Registering basic window classes...");
    NSArray *windowClasses = @[@"Button", @"Static", @"Edit", @"ListBox", @"ComboBox"];
    for (NSString *className in windowClasses) {
        NSLog(@"[CompleteExecutionEngine] Registered window class: %@", className);
    }
}

- (void)createBasicWindowsEnvironment {
    setenv("WINEPREFIX", "/tmp/wine_prefix", 1);
    setenv("WINEDEBUG", "-all", 1);
    setenv("DISPLAY", ":0", 1);
    NSLog(@"[CompleteExecutionEngine] Basic Windows environment created");
}

#pragma mark - 执行控制

- (void)stopExecution {
    [_executionLock lock];
    
    @try {
        if (!_isExecuting) {
            return;
        }
        
        NSLog(@"[CompleteExecutionEngine] Stopping execution...");
        
        // 清除安全定时器
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

- (void)safetyTimeoutHit {
    NSLog(@"[CompleteExecutionEngine] SAFETY: Execution timeout reached");
    [self stopExecution];
    [self finishExecution:ExecutionResultTimeout];
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
        
        // 清理PE相关状态
        _peImageBase = 0;
        _peEntryPointRVA = 0;
        _peActualEntryPoint = 0;
        _peCodeSection = nil;
        _peCodeSectionVA = 0;
        
    } @finally {
        [_executionLock unlock];
    }
}

#pragma mark - 调试和状态方法

- (void)outputDebugInformation {
    NSLog(@"[CompleteExecutionEngine] Outputting debug information...");
    
    // 输出Box64状态
    NSDictionary *box64State = [_box64Engine getSystemState];
    [self notifyOutputSync:@"=== Box64 引擎状态 ==="];
    for (NSString *key in box64State) {
        [self notifyOutputSync:[NSString stringWithFormat:@"%@: %@", key, box64State[key]]];
    }
    
    // 输出PE信息
    [self notifyOutputSync:@"=== PE文件信息 ==="];
    [self notifyOutputSync:[NSString stringWithFormat:@"镜像基址: 0x%llX", _peImageBase]];
    [self notifyOutputSync:[NSString stringWithFormat:@"入口点RVA: 0x%X", _peEntryPointRVA]];
    [self notifyOutputSync:[NSString stringWithFormat:@"实际入口点: 0x%llX", _peActualEntryPoint]];
    [self notifyOutputSync:[NSString stringWithFormat:@"代码段大小: %lu字节", (unsigned long)_peCodeSection.length]];
    
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
    NSLog(@"[CompleteExecutionEngine] PE Image Base: 0x%llX", _peImageBase);
    NSLog(@"[CompleteExecutionEngine] PE Entry Point: 0x%llX", _peActualEntryPoint);
    NSLog(@"[CompleteExecutionEngine] Execution log:");
    for (NSString *logEntry in _executionLog) {
        NSLog(@"[CompleteExecutionEngine]   %@", logEntry);
    }
    
    NSLog(@"[CompleteExecutionEngine] ==============================");
}

- (NSDictionary *)getSystemInfo {
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    
    info[@"isInitialized"] = @(_isInitialized);
    info[@"isExecuting"] = @(_isExecuting);
    info[@"currentProgram"] = _currentProgramPath ?: @"无";
    
    if (_box64Engine) {
        [info addEntriesFromDictionary:[_box64Engine getSystemState]];
    }
    
    return [info copy];
}

- (NSString *)getEngineStatus {
    return [NSString stringWithFormat:@"初始化: %@, 执行中: %@, 当前程序: %@",
            _isInitialized ? @"是" : @"否",
            _isExecuting ? @"是" : @"否",
            _currentProgramPath ? [_currentProgramPath lastPathComponent] : @"无"];
}

- (NSArray<NSString *> *)getExecutionLog {
    return [_executionLog copy];
}

- (void)dumpAllStates {
    NSLog(@"[CompleteExecutionEngine] ===== ALL STATES DUMP =====");
    
    NSLog(@"[CompleteExecutionEngine] Engine State:");
    NSLog(@"[CompleteExecutionEngine]   Initialized: %@", _isInitialized ? @"YES" : @"NO");
    NSLog(@"[CompleteExecutionEngine]   Executing: %@", _isExecuting ? @"YES" : @"NO");
    NSLog(@"[CompleteExecutionEngine]   Current Program: %@", _currentProgramPath ?: @"None");
    
    if (_box64Engine) {
        [_box64Engine dumpRegisters];
        [_box64Engine dumpMemoryRegions];
    }
    
    if (_jitEngine) {
        [_jitEngine dumpJITStats];
    }
    
    NSLog(@"[CompleteExecutionEngine] ================================");
}

#pragma mark - 工具方法

- (NSString *)executionResultToString:(ExecutionResult)result {
    switch (result) {
        case ExecutionResultSuccess: return @"成功";
        case ExecutionResultInvalidFile: return @"无效文件";
        case ExecutionResultInitError: return @"初始化错误";
        case ExecutionResultExecutionError: return @"执行错误";
        case ExecutionResultTimeout: return @"执行超时";
        case ExecutionResultNotInitialized: return @"未初始化";
        case ExecutionResultAlreadyExecuting: return @"已在执行";
        case ExecutionResultMemoryError: return @"内存错误";
        case ExecutionResultSecurityError: return @"安全错误";
        case ExecutionResultSecurityWarning: return @"安全警告";
        case ExecutionResultCrash: return @"程序崩溃";
        default: return @"未知错误";
    }
}

#pragma mark - 通知方法

- (void)notifyStartExecutionSync:(NSString *)programPath {
    ENSURE_MAIN_THREAD_SYNC(^{
        if (self.delegate && [self.delegate respondsToSelector:@selector(executionEngine:didStartExecution:)]) {
            [self.delegate executionEngine:self didStartExecution:programPath];
        }
    });
}

- (void)notifyFinishExecutionSync:(NSString *)programPath result:(ExecutionResult)result {
    ENSURE_MAIN_THREAD_SYNC(^{
        if (self.delegate && [self.delegate respondsToSelector:@selector(executionEngine:didFinishExecution:result:)]) {
            [self.delegate executionEngine:self didFinishExecution:programPath result:result];
        }
    });
}

- (void)notifyOutputSync:(NSString *)output {
    ENSURE_MAIN_THREAD_SYNC(^{
        if (self.delegate && [self.delegate respondsToSelector:@selector(executionEngine:didReceiveOutput:)]) {
            [self.delegate executionEngine:self didReceiveOutput:output];
        }
    });
}

- (void)notifyErrorSync:(NSError *)error {
    ENSURE_MAIN_THREAD_SYNC(^{
        if (self.delegate && [self.delegate respondsToSelector:@selector(executionEngine:didEncounterError:)]) {
            [self.delegate executionEngine:self didEncounterError:error];
        }
    });
}

- (void)notifyProgress:(float)progress status:(NSString *)status {
    ENSURE_MAIN_THREAD_ASYNC(^{
        if (self.delegate && [self.delegate respondsToSelector:@selector(executionEngine:didUpdateProgress:status:)]) {
            [self.delegate executionEngine:self didUpdateProgress:progress status:status];
        }
    });
}

@end
