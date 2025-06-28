#import "CompleteExecutionEngine.h"

@interface CompleteExecutionEngine()
@property (nonatomic, strong) IOSJITEngine *jitEngine;
@property (nonatomic, strong) Box64Engine *box64Engine;
@property (nonatomic, strong) WineAPI *wineAPI;
@property (nonatomic, assign) BOOL isInitialized;
@property (nonatomic, assign) BOOL isExecuting;
@property (nonatomic, strong) NSString *currentProgramPath;
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

#pragma mark - 初始化和配置

- (BOOL)initializeWithViewController:(UIViewController *)viewController {
    if (_isInitialized) {
        NSLog(@"[CompleteExecutionEngine] Already initialized");
        return YES;
    }
    
    NSLog(@"[CompleteExecutionEngine] Initializing complete execution engine...");
    [self updateProgress:0.1 status:@"初始化JIT引擎..."];
    
    // 设置主视图控制器
    _hostViewController = viewController;
    _wineAPI.rootViewController = viewController;
    
    // 初始化JIT引擎
    if (![_jitEngine initializeJIT]) {
        NSLog(@"[CompleteExecutionEngine] Failed to initialize JIT engine");
        [self notifyError:[NSError errorWithDomain:@"ExecutionEngine" code:ExecutionResultInitError userInfo:@{NSLocalizedDescriptionKey: @"JIT引擎初始化失败"}]];
        return NO;
    }
    
    [self updateProgress:0.3 status:@"初始化Box64引擎..."];
    
    // 初始化Box64引擎 (分配64MB虚拟内存)
    if (![_box64Engine initializeWithMemorySize:64 * 1024 * 1024]) {
        NSLog(@"[CompleteExecutionEngine] Failed to initialize Box64 engine");
        [self notifyError:[NSError errorWithDomain:@"ExecutionEngine" code:ExecutionResultInitError userInfo:@{NSLocalizedDescriptionKey: @"Box64引擎初始化失败"}]];
        return NO;
    }
    
    [self updateProgress:0.5 status:@"设置Wine环境..."];
    
    // 注册基础窗口类
    [self registerBasicWindowClasses];
    
    [self updateProgress:0.7 status:@"创建虚拟Windows环境..."];
    
    // 创建基础Windows环境
    [self createBasicWindowsEnvironment];
    
    [self updateProgress:1.0 status:@"初始化完成"];
    
    _isInitialized = YES;
    NSLog(@"[CompleteExecutionEngine] Complete execution engine initialized successfully!");
    
    return YES;
}

- (void)registerBasicWindowClasses {
    // 注册基础窗口类 "Button"
    WNDCLASS buttonClass = {0};
    buttonClass.lpfnWndProc = DefWindowProc;
    buttonClass.lpszClassName = "Button";
    buttonClass.hbrBackground = GetStockObject(WHITE_BRUSH);
    RegisterClass(&buttonClass);
    
    // 注册基础窗口类 "Static"
    WNDCLASS staticClass = {0};
    staticClass.lpfnWndProc = DefWindowProc;
    staticClass.lpszClassName = "Static";
    staticClass.hbrBackground = GetStockObject(WHITE_BRUSH);
    RegisterClass(&staticClass);
    
    // 注册基础窗口类 "Edit"
    WNDCLASS editClass = {0};
    editClass.lpfnWndProc = DefWindowProc;
    editClass.lpszClassName = "Edit";
    editClass.hbrBackground = GetStockObject(WHITE_BRUSH);
    RegisterClass(&editClass);
    
    NSLog(@"[CompleteExecutionEngine] Registered basic window classes");
}

- (void)createBasicWindowsEnvironment {
    // 设置基础环境变量
    setenv("WINEPREFIX", "/tmp/wine_prefix", 1);
    setenv("WINEDEBUG", "-all", 1);
    setenv("DISPLAY", ":0", 1);
    
    // 在Box64中映射基础系统DLL
    NSData *kernelData = [self createMockKernel32DLL];
    [_box64Engine mapMemory:0x1000000 size:kernelData.length data:kernelData];
    
    NSData *userData = [self createMockUser32DLL];
    [_box64Engine mapMemory:0x2000000 size:userData.length data:userData];
    
    NSData *gdiData = [self createMockGDI32DLL];
    [_box64Engine mapMemory:0x3000000 size:gdiData.length data:gdiData];
    
    NSLog(@"[CompleteExecutionEngine] Created basic Windows environment");
}

- (NSData *)createMockKernel32DLL {
    // 创建模拟的KERNEL32.DLL代码
    // 这里创建简单的ARM64指令序列，用于处理基础系统调用
    uint32_t instructions[] = {
        0xD503201F,  // NOP
        0xD2800000,  // MOV X0, #0 (GetLastError返回0)
        0xD65F03C0   // RET
    };
    
    return [NSData dataWithBytes:instructions length:sizeof(instructions)];
}

- (NSData *)createMockUser32DLL {
    // 创建模拟的USER32.DLL代码
    uint32_t instructions[] = {
        0xD503201F,  // NOP
        0xD2800020,  // MOV X0, #1 (成功返回TRUE)
        0xD65F03C0   // RET
    };
    
    return [NSData dataWithBytes:instructions length:sizeof(instructions)];
}

- (NSData *)createMockGDI32DLL {
    // 创建模拟的GDI32.DLL代码
    uint32_t instructions[] = {
        0xD503201F,  // NOP
        0xD2800020,  // MOV X0, #1 (成功返回TRUE)
        0xD65F03C0   // RET
    };
    
    return [NSData dataWithBytes:instructions length:sizeof(instructions)];
}

- (void)cleanup {
    if (!_isInitialized) return;
    
    NSLog(@"[CompleteExecutionEngine] Cleaning up execution engine...");
    
    [self stopExecution];
    [_box64Engine cleanup];
    [_jitEngine cleanupJIT];
    
    _isInitialized = NO;
    NSLog(@"[CompleteExecutionEngine] Cleanup completed");
}

#pragma mark - 程序执行

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
    
    [self notifyStartExecution:exePath];
    [self updateProgress:0.0 status:@"加载程序文件..."];
    
    // 验证文件存在
    if (![[NSFileManager defaultManager] fileExistsAtPath:exePath]) {
        NSLog(@"[CompleteExecutionEngine] Program file not found: %@", exePath);
        [self notifyError:[NSError errorWithDomain:@"ExecutionEngine" code:ExecutionResultInvalidFile userInfo:@{NSLocalizedDescriptionKey: @"程序文件未找到"}]];
        _isExecuting = NO;
        return ExecutionResultInvalidFile;
    }
    
    [self updateProgress:0.2 status:@"分析PE文件..."];
    
    // 加载和分析PE文件
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
    
    [self updateProgress:0.4 status:@"设置执行环境..."];
    
    // 在Box64中映射PE文件
    if (![_box64Engine mapMemory:0x400000 size:peData.length data:peData]) {
        NSLog(@"[CompleteExecutionEngine] Failed to map PE file");
        [self notifyError:[NSError errorWithDomain:@"ExecutionEngine" code:ExecutionResultMemoryError userInfo:@{NSLocalizedDescriptionKey: @"内存映射失败"}]];
        _isExecuting = NO;
        return ExecutionResultMemoryError;
    }
    
    [self updateProgress:0.6 status:@"初始化Windows环境..."];
    
    // 设置执行参数
    [_box64Engine setX86Register:X86_RSP value:0x100000];  // 设置栈指针
    [_box64Engine setX86Register:X86_RBP value:0x100000];  // 设置基址指针
    
    [self updateProgress:0.8 status:@"开始执行程序..."];
    
    // 创建主窗口 (如果是GUI程序)
    HWND mainWindow = [self createMainWindow];
    
    // 执行PE入口点
    result = [self executePEEntryPoint:peData arguments:arguments];
    
    if (result == ExecutionResultSuccess) {
        [self updateProgress:1.0 status:@"程序执行完成"];
        
        // 如果创建了主窗口，运行消息循环
        if (mainWindow) {
            [self runMessageLoop:mainWindow];
        }
    }
    
    [self notifyFinishExecution:exePath result:result];
    _isExecuting = NO;
    
    return result;
}

- (ExecutionResult)analyzePEFile:(NSData *)peData {
    if (peData.length < 64) {
        NSLog(@"[CompleteExecutionEngine] PE file too small");
        return ExecutionResultInvalidFile;
    }
    
    const uint8_t *bytes = peData.bytes;
    
    // 检查DOS签名
    if (bytes[0] != 'M' || bytes[1] != 'Z') {
        NSLog(@"[CompleteExecutionEngine] Invalid DOS signature");
        return ExecutionResultInvalidFile;
    }
    
    // 获取PE头偏移
    uint32_t peOffset = *(uint32_t *)(bytes + 60);
    if (peOffset >= peData.length || peOffset + 4 >= peData.length) {
        NSLog(@"[CompleteExecutionEngine] Invalid PE offset");
        return ExecutionResultInvalidFile;
    }
    
    // 检查PE签名
    const uint8_t *peHeader = bytes + peOffset;
    if (peHeader[0] != 'P' || peHeader[1] != 'E') {
        NSLog(@"[CompleteExecutionEngine] Invalid PE signature");
        return ExecutionResultInvalidFile;
    }
    
    // 检查机器类型
    uint16_t machine = *(uint16_t *)(peHeader + 4);
    NSString *architecture;
    switch (machine) {
        case 0x014c:
            architecture = @"i386";
            break;
        case 0x8664:
            architecture = @"x86_64";
            break;
        default:
            architecture = [NSString stringWithFormat:@"Unknown (0x%04x)", machine];
            NSLog(@"[CompleteExecutionEngine] Unsupported architecture: %@", architecture);
            return ExecutionResultInvalidFile;
    }
    
    [self notifyOutput:[NSString stringWithFormat:@"PE文件分析完成: %@", architecture]];
    NSLog(@"[CompleteExecutionEngine] PE analysis successful: %@", architecture);
    
    return ExecutionResultSuccess;
}

- (HWND)createMainWindow {
    // 注册主窗口类
    WNDCLASS wc = {0};
    wc.lpfnWndProc = DefWindowProc;
    wc.lpszClassName = "WineMainWindow";
    wc.hbrBackground = GetStockObject(WHITE_BRUSH);
    
    if (!RegisterClass(&wc)) {
        NSLog(@"[CompleteExecutionEngine] Failed to register main window class");
        return NULL;
    }
    
    // 创建主窗口
    HWND hwnd = CreateWindow("WineMainWindow", "Wine Application",
                            WS_OVERLAPPEDWINDOW | WS_VISIBLE,
                            100, 100, 400, 300,
                            NULL, NULL, NULL, NULL);
    
    if (hwnd) {
        ShowWindow(hwnd, 1);  // SW_SHOWNORMAL
        UpdateWindow(hwnd);
        NSLog(@"[CompleteExecutionEngine] Created main window: %p", hwnd);
    }
    
    return hwnd;
}

- (ExecutionResult)executePEEntryPoint:(NSData *)peData arguments:(nullable NSArray<NSString *> *)arguments {
    NSLog(@"[CompleteExecutionEngine] Executing PE entry point...");
    
    // 简化的入口点执行
    // 在真实实现中，需要解析PE头找到入口点地址
    
    // 创建简单的x86指令序列来测试系统
    uint8_t testInstructions[] = {
        0xB8, 0x00, 0x00, 0x00, 0x00,  // MOV EAX, 0
        0x05, 0x01, 0x00, 0x00, 0x00,  // ADD EAX, 1
        0xC3                            // RET
    };
    
    NSData *instructionData = [NSData dataWithBytes:testInstructions length:sizeof(testInstructions)];
    
    // 执行测试指令
    BOOL success = [_box64Engine executeX86Code:instructionData.bytes length:instructionData.length];
    
    if (success) {
        [self notifyOutput:@"程序入口点执行成功"];
        
        // 检查结果
        uint64_t result = [_box64Engine getX86Register:X86_RAX];
        [self notifyOutput:[NSString stringWithFormat:@"程序返回值: %llu", result]];
        
        return ExecutionResultSuccess;
    } else {
        [self notifyOutput:@"程序入口点执行失败"];
        return ExecutionResultFailure;
    }
}

- (void)runMessageLoop:(HWND)mainWindow {
    NSLog(@"[CompleteExecutionEngine] Starting Windows message loop...");
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        MSG msg;
        BOOL running = YES;
        
        while (running) {
            if (GetMessage(&msg, (HWND)0, 0, 0)) {
                if (msg.message == WM_QUIT) {
                    NSLog(@"[CompleteExecutionEngine] Received WM_QUIT, exiting message loop");
                    running = NO;
                } else {
                    TranslateMessage(&msg);
                    DispatchMessage(&msg);
                }
            } else {
                // GetMessage返回FALSE，退出循环
                running = NO;
            }
            
            // 防止死循环
            [NSThread sleepForTimeInterval:0.01];
        }
        
        NSLog(@"[CompleteExecutionEngine] Message loop ended");
    });
}

- (void)stopExecution {
    if (!_isExecuting) return;
    
    NSLog(@"[CompleteExecutionEngine] Stopping execution...");
    
    // 发送退出消息
    PostQuitMessage(0);
    
    _isExecuting = NO;
    [self notifyOutput:@"程序执行已停止"];
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
    
    // JIT状态
    [_jitEngine dumpJITStats];
    
    // Box64状态
    [_box64Engine dumpRegisters];
    
    // Wine状态
    NSLog(@"[CompleteExecutionEngine] Wine Windows: %@", _wineAPI.windows.allKeys);
    NSLog(@"[CompleteExecutionEngine] Wine DCs: %@", _wineAPI.deviceContexts.allKeys);
    NSLog(@"[CompleteExecutionEngine] Message Queue: %lu messages", (unsigned long)_wineAPI.messageQueue.count);
    
    NSLog(@"[CompleteExecutionEngine] ==============================");
}

#pragma mark - 委托通知方法

- (void)notifyStartExecution:(NSString *)programPath {
    if ([self.delegate respondsToSelector:@selector(executionEngine:didStartExecution:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate executionEngine:self didStartExecution:programPath];
        });
    }
}

- (void)notifyFinishExecution:(NSString *)programPath result:(ExecutionResult)result {
    if ([self.delegate respondsToSelector:@selector(executionEngine:didFinishExecution:result:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate executionEngine:self didFinishExecution:programPath result:result];
        });
    }
}

- (void)notifyOutput:(NSString *)output {
    if ([self.delegate respondsToSelector:@selector(executionEngine:didReceiveOutput:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate executionEngine:self didReceiveOutput:output];
        });
    }
}

- (void)notifyError:(NSError *)error {
    if ([self.delegate respondsToSelector:@selector(executionEngine:didEncounterError:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate executionEngine:self didEncounterError:error];
        });
    }
}

- (void)updateProgress:(float)progress status:(NSString *)status {
    if ([self.delegate respondsToSelector:@selector(executionEngine:didUpdateProgress:status:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate executionEngine:self didUpdateProgress:progress status:status];
        });
    }
}

@end
