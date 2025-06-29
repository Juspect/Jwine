// GraphicsEnhancedExecutionEngine.m - 图形增强执行引擎实现（线程安全修复版本）
#import "GraphicsEnhancedExecutionEngine.h"

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

@interface GraphicsEnhancedExecutionEngine() <CompleteExecutionEngineDelegate>
@property (nonatomic, strong) CompleteExecutionEngine *coreEngine;
@property (nonatomic, strong) MoltenVKBridge *graphicsBridge;
@property (nonatomic, strong) WineAPI *wineAPI;
@property (nonatomic, assign) BOOL isInitialized;
@property (nonatomic, assign) BOOL isExecuting;
@property (nonatomic, assign) BOOL graphicsEnabled;
@property (nonatomic, strong) NSTimer *renderTimer;
@property (nonatomic, strong) NSString *currentProgramPath;
@property (nonatomic, strong) UIImageView *frameImageView;
@end

@implementation GraphicsEnhancedExecutionEngine

+ (instancetype)sharedEngine {
    static GraphicsEnhancedExecutionEngine *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[GraphicsEnhancedExecutionEngine alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _isInitialized = NO;
        _isExecuting = NO;
        _graphicsEnabled = NO;
        _renderTimer = nil;
        _currentProgramPath = nil;
        
        // 初始化核心组件
        _coreEngine = [CompleteExecutionEngine sharedEngine];
        _coreEngine.delegate = self;
        
        _graphicsBridge = [MoltenVKBridge sharedBridge];
        _wineAPI = [WineAPI sharedAPI];
        
        NSLog(@"[GraphicsEnhancedExecutionEngine] Initialized graphics-enhanced execution engine");
    }
    return self;
}

- (void)dealloc {
    [self cleanup];
}

#pragma mark - 初始化和清理

- (BOOL)initializeWithViewController:(UIViewController *)viewController
                    graphicsOutputView:(UIView *)graphicsView {
    if (_isInitialized) {
        NSLog(@"[GraphicsEnhancedExecutionEngine] Already initialized");
        return YES;
    }
    
    NSLog(@"[GraphicsEnhancedExecutionEngine] Initializing graphics-enhanced execution engine...");
    
    _hostViewController = viewController;
    _graphicsOutputView = graphicsView;
    
    // 1. 初始化核心执行引擎
    if (![_coreEngine initializeWithViewController:viewController]) {
        NSLog(@"[GraphicsEnhancedExecutionEngine] Failed to initialize core execution engine");
        return NO;
    }
    
    // 2. 初始化图形桥接
    if (![_graphicsBridge initializeWithView:graphicsView]) {
        NSLog(@"[GraphicsEnhancedExecutionEngine] Failed to initialize graphics bridge");
        return NO;
    }
    
    // 3. 配置Wine API (WineAPI通过sharedAPI自动初始化，只需设置根视图控制器)
    if (_wineAPI) {
        _wineAPI.rootViewController = viewController;
        NSLog(@"[GraphicsEnhancedExecutionEngine] Wine API configured successfully");
    } else {
        NSLog(@"[GraphicsEnhancedExecutionEngine] Failed to get Wine API instance");
        return NO;
    }
    
    _isInitialized = YES;
    _graphicsEnabled = YES;
    
    NSLog(@"[GraphicsEnhancedExecutionEngine] Graphics-enhanced execution engine initialized successfully");
    return YES;
}

- (void)cleanup {
    ENSURE_MAIN_THREAD(^{
        if (!self->_isInitialized) {
            return;
        }
        
        NSLog(@"[GraphicsEnhancedExecutionEngine] Cleaning up graphics-enhanced execution engine...");
        
        // 停止渲染定时器
        if (self->_renderTimer) {
            [self->_renderTimer invalidate];
            self->_renderTimer = nil;
        }
        
        [self stopExecution];
        
        if (self->_graphicsBridge) {
            [self->_graphicsBridge cleanup];
        }
        
        if (self->_coreEngine) {
            [self->_coreEngine cleanup];
        }
        
        self->_graphicsEnabled = NO;
        self->_isInitialized = NO;
        
        NSLog(@"[GraphicsEnhancedExecutionEngine] Cleanup completed");
    });
}

#pragma mark - 程序执行

- (GraphicsExecutionResult)executeProgram:(NSString *)exePath {
    return [self executeProgram:exePath arguments:nil];
}

- (GraphicsExecutionResult)executeProgram:(NSString *)exePath arguments:(nullable NSArray<NSString *> *)arguments {
    if (!_isInitialized) {
        NSLog(@"[GraphicsEnhancedExecutionEngine] Engine not initialized");
        return GraphicsExecutionResultFailure;
    }
    
    if (_isExecuting) {
        NSLog(@"[GraphicsEnhancedExecutionEngine] Already executing a program");
        return GraphicsExecutionResultFailure;
    }
    
    NSLog(@"[GraphicsEnhancedExecutionEngine] Starting enhanced execution of: %@", exePath);
    _currentProgramPath = exePath;
    _isExecuting = YES;
    
    [self notifyStartExecution:exePath];
    [self notifyProgress:0.0 status:@"开始图形增强执行..."];
    
    // 启动渲染循环
    if (_graphicsEnabled) {
        [self startRenderLoop];
    }
    
    // 使用核心引擎执行程序
    ExecutionResult coreResult = [_coreEngine executeProgram:exePath arguments:arguments];
    
    // 转换结果类型
    GraphicsExecutionResult result;
    switch (coreResult) {
        case ExecutionResultSuccess:
            result = GraphicsExecutionResultSuccess;
            break;
        case ExecutionResultInvalidFile:
            result = GraphicsExecutionResultInvalidFile;
            break;
        default:
            result = GraphicsExecutionResultFailure;
            break;
    }
    
    [self notifyFinishExecution:exePath result:result];
    _isExecuting = NO;
    
    return result;
}

- (void)stopExecution {
    NSLog(@"[GraphicsEnhancedExecutionEngine] Stopping enhanced execution...");
    
    // 停止渲染循环
    ENSURE_MAIN_THREAD(^{
        if (self->_renderTimer) {
            [self->_renderTimer invalidate];
            self->_renderTimer = nil;
        }
    });
    
    [_coreEngine stopExecution];
    _isExecuting = NO;
    
    [self notifyOutput:@"程序执行已停止"];
}

#pragma mark - 图形功能

- (BOOL)enableGraphicsOutput:(BOOL)enabled {
    _graphicsEnabled = enabled;
    
    if (enabled && _isExecuting) {
        [self startRenderLoop];
    } else if (!enabled) {
        ENSURE_MAIN_THREAD(^{
            if (self->_renderTimer) {
                [self->_renderTimer invalidate];
                self->_renderTimer = nil;
            }
        });
    }
    
    NSLog(@"[GraphicsEnhancedExecutionEngine] Graphics output %@", enabled ? @"enabled" : @"disabled");
    return YES;
}

- (void)setGraphicsResolution:(CGSize)resolution {
    if (_graphicsBridge) {
        [_graphicsBridge resizeToWidth:resolution.width height:resolution.height];
    }
    
    NSLog(@"[GraphicsEnhancedExecutionEngine] Graphics resolution set to %.0fx%.0f",
          resolution.width, resolution.height);
}

- (UIImage *)captureCurrentFrame {
    // 从Metal层捕获当前帧
    if (!_graphicsBridge) {
        return nil;
    }
    
    // 这里应该从MoltenVK桥接器获取当前帧
    // 临时返回nil，实际实现需要从Metal层获取
    return nil;
}

#pragma mark - 渲染循环 - 线程安全修复

- (void)startRenderLoop {
    ENSURE_MAIN_THREAD(^{
        if (self->_renderTimer) {
            [self->_renderTimer invalidate];
        }
        
        // 60 FPS渲染循环 - 确保在主线程创建定时器
        self->_renderTimer = [NSTimer scheduledTimerWithTimeInterval:1.0/60.0
                                                              target:self
                                                            selector:@selector(renderFrame)
                                                            userInfo:nil
                                                             repeats:YES];
        
        NSLog(@"[GraphicsEnhancedExecutionEngine] Started render loop (60 FPS) on main thread");
    });
}

- (void)renderFrame {
    // 确保渲染操作在主线程执行
    ENSURE_MAIN_THREAD(^{
        if (!self->_isExecuting || !self->_graphicsEnabled) {
            return;
        }
        
        // 通知图形桥接器执行渲染（Metal操作必须在主线程）
        if (self->_graphicsBridge) {
            [self->_graphicsBridge presentFrame];
        }
        
        // 通知代理帧已渲染
        if ([self.delegate respondsToSelector:@selector(graphicsEngine:didRenderFrame:)]) {
            UIImage *frameImage = [self captureCurrentFrame];
            if (frameImage) {
                [self.delegate graphicsEngine:self didRenderFrame:frameImage];
            }
        }
    });
}

#pragma mark - 委托通知方法 - 线程安全修复

- (void)notifyProgress:(float)progress status:(NSString *)status {
    ENSURE_MAIN_THREAD(^{
        if ([self.delegate respondsToSelector:@selector(graphicsEngine:didUpdateProgress:status:)]) {
            [self.delegate graphicsEngine:self didUpdateProgress:progress status:status];
        }
    });
}

- (void)notifyStartExecution:(NSString *)programPath {
    ENSURE_MAIN_THREAD(^{
        if ([self.delegate respondsToSelector:@selector(graphicsEngine:didStartExecution:)]) {
            [self.delegate graphicsEngine:self didStartExecution:programPath];
        }
    });
}

- (void)notifyFinishExecution:(NSString *)programPath result:(GraphicsExecutionResult)result {
    ENSURE_MAIN_THREAD(^{
        if ([self.delegate respondsToSelector:@selector(graphicsEngine:didFinishExecution:result:)]) {
            [self.delegate graphicsEngine:self didFinishExecution:programPath result:result];
        }
    });
}

- (void)notifyOutput:(NSString *)output {
    ENSURE_MAIN_THREAD(^{
        if ([self.delegate respondsToSelector:@selector(graphicsEngine:didReceiveOutput:)]) {
            [self.delegate graphicsEngine:self didReceiveOutput:output];
        }
    });
}

- (void)notifyError:(NSError *)error {
    ENSURE_MAIN_THREAD(^{
        if ([self.delegate respondsToSelector:@selector(graphicsEngine:didEncounterError:)]) {
            [self.delegate graphicsEngine:self didEncounterError:error];
        }
    });
}

- (void)notifyCreateWindow:(NSString *)windowTitle size:(CGSize)size {
    ENSURE_MAIN_THREAD(^{
        if ([self.delegate respondsToSelector:@selector(graphicsEngine:didCreateWindow:size:)]) {
            [self.delegate graphicsEngine:self didCreateWindow:windowTitle size:size];
        }
    });
}

#pragma mark - 增强指令执行

- (BOOL)executeEnhancedInstructionSequence:(const uint8_t *)instructions length:(size_t)length {
    if (!_isInitialized) {
        NSLog(@"[GraphicsEnhancedExecutionEngine] Engine not initialized");
        return NO;
    }
    
    NSLog(@"[GraphicsEnhancedExecutionEngine] Executing enhanced instruction sequence (%zu bytes)", length);
    
    size_t offset = 0;
    int instructionCount = 0;
    
    while (offset < length && instructionCount < 1000) {  // 安全限制
        X86ExtendedInstruction instruction = [EnhancedBox64Instructions
            decodeInstruction:(instructions + offset)
                    maxLength:(length - offset)];
        
        if (instruction.length == 0) {
            NSLog(@"[GraphicsEnhancedExecutionEngine] Failed to decode instruction at offset %zu", offset);
            break;
        }
        
        // 生成对应的ARM64代码
        NSArray<NSNumber *> *arm64Code = [EnhancedBox64Instructions generateARM64Code:instruction];
        
        if (arm64Code.count > 0) {
            NSLog(@"[GraphicsEnhancedExecutionEngine] Instruction %d: processed successfully", instructionCount);
        }
        
        offset += instruction.length;
        instructionCount++;
    }
    
    NSLog(@"[GraphicsEnhancedExecutionEngine] Processed %d instructions", instructionCount);
    return YES;
}

- (NSArray<NSString *> *)disassembleInstructions:(const uint8_t *)instructions length:(size_t)length {
    NSMutableArray<NSString *> *disassembly = [NSMutableArray array];
    
    size_t offset = 0;
    int instructionCount = 0;
    
    while (offset < length && instructionCount < 100) {  // 限制反汇编数量
        X86ExtendedInstruction instruction = [EnhancedBox64Instructions
            decodeInstruction:(instructions + offset)
                    maxLength:(length - offset)];
        
        if (instruction.length == 0) {
            break;
        }
        
        NSString *disasm = [NSString stringWithFormat:@"0x%04zx: instruction_%d", offset, (int)instruction.type];
        [disassembly addObject:disasm];
        
        offset += instruction.length;
        instructionCount++;
    }
    
    return [disassembly copy];
}

#pragma mark - 调试和监控

- (NSDictionary *)getDetailedSystemInfo {
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    
    // 引擎状态
    info[@"engine_initialized"] = @(_isInitialized);
    info[@"engine_executing"] = @(_isExecuting);
    info[@"graphics_enabled"] = @(_graphicsEnabled);
    info[@"current_program"] = _currentProgramPath ?: @"none";
    
    // 核心引擎信息
    if (_coreEngine) {
        info[@"core_engine"] = [_coreEngine getSystemInfo];
    }
    
    // 图形桥接信息
    if (_graphicsBridge) {
        info[@"graphics_bridge"] = [_graphicsBridge getVulkanInfo];
        info[@"metal_info"] = [_graphicsBridge getMetalInfo];
    }
    
    // Wine API信息
    if (_wineAPI) {
        info[@"wine_api"] = @{@"initialized": @YES, @"status": @"basic_ready"};
    }
    
    return [info copy];
}

- (NSString *)getDetailedEngineStatus {
    NSMutableString *status = [NSMutableString string];
    
    [status appendFormat:@"Graphics Enhanced Execution Engine Status:\n"];
    [status appendFormat:@"  Initialized: %@\n", _isInitialized ? @"YES" : @"NO"];
    [status appendFormat:@"  Executing: %@\n", _isExecuting ? @"YES" : @"NO"];
    [status appendFormat:@"  Graphics Enabled: %@\n", _graphicsEnabled ? @"YES" : @"NO"];
    [status appendFormat:@"  Current Program: %@\n", _currentProgramPath ?: @"none"];
    [status appendFormat:@"  Render Timer: %@\n", _renderTimer ? @"ACTIVE" : @"INACTIVE"];
    
    if (_coreEngine) {
        [status appendFormat:@"  Core Engine: %@\n", [_coreEngine getEngineStatus]];
    }
    
    return [status copy];
}

- (void)dumpDetailedStates {
    NSLog(@"[GraphicsEnhancedExecutionEngine] ===== Detailed State Dump =====");
    NSLog(@"%@", [self getDetailedEngineStatus]);
    
    if (_coreEngine) {
        [_coreEngine dumpAllStates];
    }
    
    if (_graphicsBridge) {
        NSLog(@"[GraphicsEnhancedExecutionEngine] Vulkan Info: %@", [_graphicsBridge getVulkanInfo]);
        NSLog(@"[GraphicsEnhancedExecutionEngine] Metal Info: %@", [_graphicsBridge getMetalInfo]);
    }
    
    NSLog(@"[GraphicsEnhancedExecutionEngine] ===============================");
}

#pragma mark - CompleteExecutionEngineDelegate实现

- (void)executionEngine:(CompleteExecutionEngine *)engine didStartExecution:(NSString *)programPath {
    [self notifyStartExecution:programPath];
}

- (void)executionEngine:(CompleteExecutionEngine *)engine didFinishExecution:(NSString *)programPath result:(ExecutionResult)result {
    GraphicsExecutionResult graphicsResult;
    switch (result) {
        case ExecutionResultSuccess:
            graphicsResult = GraphicsExecutionResultSuccess;
            break;
        case ExecutionResultInvalidFile:
            graphicsResult = GraphicsExecutionResultInvalidFile;
            break;
        default:
            graphicsResult = GraphicsExecutionResultFailure;
            break;
    }
    [self notifyFinishExecution:programPath result:graphicsResult];
}

- (void)executionEngine:(CompleteExecutionEngine *)engine didReceiveOutput:(NSString *)output {
    [self notifyOutput:output];
}

- (void)executionEngine:(CompleteExecutionEngine *)engine didEncounterError:(NSError *)error {
    [self notifyError:error];
}

- (void)executionEngine:(CompleteExecutionEngine *)engine didUpdateProgress:(float)progress status:(NSString *)status {
    [self notifyProgress:progress status:status];
}

@end
