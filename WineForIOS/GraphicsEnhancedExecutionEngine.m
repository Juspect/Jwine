// GraphicsEnhancedExecutionEngine.m - 修复渲染循环崩溃版本
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
@property (nonatomic, strong) dispatch_queue_t renderQueue;  // 🔧 新增：专用渲染队列
@property (nonatomic, assign) BOOL shouldStopRendering;      // 🔧 新增：停止渲染标志
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
        _shouldStopRendering = NO;
        
        // 🔧 修复：创建专用的渲染队列，避免主线程阻塞
        _renderQueue = dispatch_queue_create("com.wineforios.graphics.render", DISPATCH_QUEUE_SERIAL);
        
        // 延迟初始化核心组件，避免启动时的潜在问题
        _coreEngine = nil;
        _graphicsBridge = nil;
        _wineAPI = nil;
        
        NSLog(@"[GraphicsEnhancedExecutionEngine] Initialized graphics-enhanced execution engine (components will be initialized on demand)");
    }
    return self;
}

- (void)dealloc {
    NSLog(@"[GraphicsEnhancedExecutionEngine] Deallocating execution engine...");
    [self cleanup];
}

#pragma mark - 安全的组件初始化

- (CompleteExecutionEngine *)coreEngine {
    if (!_coreEngine) {
        _coreEngine = [CompleteExecutionEngine sharedEngine];
        _coreEngine.delegate = self;
        NSLog(@"[GraphicsEnhancedExecutionEngine] Core engine initialized on demand");
    }
    return _coreEngine;
}

- (MoltenVKBridge *)graphicsBridge {
    if (!_graphicsBridge) {
        _graphicsBridge = [MoltenVKBridge sharedBridge];
        NSLog(@"[GraphicsEnhancedExecutionEngine] Graphics bridge initialized on demand");
    }
    return _graphicsBridge;
}

- (WineAPI *)wineAPI {
    if (!_wineAPI) {
        _wineAPI = [WineAPI sharedAPI];
        NSLog(@"[GraphicsEnhancedExecutionEngine] Wine API initialized on demand");
    }
    return _wineAPI;
}

#pragma mark - 初始化和清理

- (BOOL)initializeWithViewController:(UIViewController *)viewController
                    graphicsOutputView:(UIView *)graphicsView {
    if (_isInitialized) {
        NSLog(@"[GraphicsEnhancedExecutionEngine] Already initialized");
        return YES;
    }
    
    NSLog(@"[GraphicsEnhancedExecutionEngine] Initializing graphics-enhanced execution engine...");
    
    // 🔧 修复：添加输入验证
    if (!viewController) {
        NSLog(@"[GraphicsEnhancedExecutionEngine] ERROR: View controller is nil");
        return NO;
    }
    
    if (!graphicsView) {
        NSLog(@"[GraphicsEnhancedExecutionEngine] ERROR: Graphics view is nil");
        return NO;
    }
    
    _hostViewController = viewController;
    _graphicsOutputView = graphicsView;
    
    // 1. 初始化核心执行引擎
    if (![self.coreEngine initializeWithViewController:viewController]) {
        NSLog(@"[GraphicsEnhancedExecutionEngine] Failed to initialize core execution engine");
        return NO;
    }
    
    // 2. 初始化图形桥接 - 添加错误检查
    @try {
        if (![self.graphicsBridge initializeWithView:graphicsView]) {
            NSLog(@"[GraphicsEnhancedExecutionEngine] Failed to initialize graphics bridge");
            return NO;
        }
    } @catch (NSException *exception) {
        NSLog(@"[GraphicsEnhancedExecutionEngine] Exception during graphics bridge initialization: %@", exception);
        return NO;
    }
    
    // 3. 配置Wine API
    if (self.wineAPI) {
        self.wineAPI.rootViewController = viewController;
        NSLog(@"[GraphicsEnhancedExecutionEngine] Wine API configured successfully");
    } else {
        NSLog(@"[GraphicsEnhancedExecutionEngine] Warning: Failed to get Wine API instance");
        // 不要因为Wine API失败就退出，继续初始化
    }
    
    _isInitialized = YES;
    _graphicsEnabled = NO;  // 🔧 修复：默认关闭图形渲染，避免启动时崩溃
    _shouldStopRendering = NO;
    
    NSLog(@"[GraphicsEnhancedExecutionEngine] Graphics-enhanced execution engine initialized successfully");
    return YES;
}

- (void)cleanup {
    NSLog(@"[GraphicsEnhancedExecutionEngine] Starting cleanup...");
    
    // 🔧 修复：设置停止标志，防止新的渲染操作
    _shouldStopRendering = YES;
    _isExecuting = NO;
    
    // 停止渲染定时器
    ENSURE_MAIN_THREAD(^{
        if (self->_renderTimer) {
            [self->_renderTimer invalidate];
            self->_renderTimer = nil;
            NSLog(@"[GraphicsEnhancedExecutionEngine] Render timer invalidated");
        }
    });
    
    // 等待渲染队列中的任务完成
    if (_renderQueue) {
        dispatch_sync(_renderQueue, ^{
            NSLog(@"[GraphicsEnhancedExecutionEngine] Render queue drained");
        });
    }
    
    // 清理组件
    if (_coreEngine) {
        [_coreEngine cleanup];
        _coreEngine = nil;
    }
    
    if (_graphicsBridge) {
        [_graphicsBridge cleanup];
        _graphicsBridge = nil;
    }
    
    _graphicsEnabled = NO;
    _isInitialized = NO;
    
    NSLog(@"[GraphicsEnhancedExecutionEngine] Cleanup completed");
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
    _shouldStopRendering = NO;
    
    [self notifyStartExecution:exePath];
    [self notifyProgress:0.0 status:@"开始图形增强执行..."];
    
    // 🔧 修复：延迟启动渲染循环，让核心执行先稳定
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self->_graphicsEnabled && self->_isExecuting && !self->_shouldStopRendering) {
            [self startRenderLoop];
        }
    });
    
    // 使用核心引擎执行程序
    ExecutionResult coreResult = [self.coreEngine executeProgram:exePath arguments:arguments];
    
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
    
    // 🔧 修复：先设置停止标志
    _shouldStopRendering = YES;
    _isExecuting = NO;
    
    // 停止渲染循环
    ENSURE_MAIN_THREAD(^{
        if (self->_renderTimer) {
            [self->_renderTimer invalidate];
            self->_renderTimer = nil;
            NSLog(@"[GraphicsEnhancedExecutionEngine] Render timer stopped");
        }
    });
    
    // 停止核心引擎
    if (_coreEngine) {
        [_coreEngine stopExecution];
    }
    
    [self notifyOutput:@"程序执行已停止"];
}

#pragma mark - 图形功能

- (BOOL)enableGraphicsOutput:(BOOL)enabled {
    NSLog(@"[GraphicsEnhancedExecutionEngine] Graphics output %@", enabled ? @"enabling" : @"disabling");
    
    if (enabled && !_isInitialized) {
        NSLog(@"[GraphicsEnhancedExecutionEngine] Cannot enable graphics - engine not initialized");
        return NO;
    }
    
    _graphicsEnabled = enabled;
    
    if (enabled && _isExecuting && !_shouldStopRendering) {
        [self startRenderLoop];
    } else if (!enabled) {
        _shouldStopRendering = YES;
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
    if (!_isInitialized || !self.graphicsBridge) {
        NSLog(@"[GraphicsEnhancedExecutionEngine] Cannot set resolution - not initialized");
        return;
    }
    
    @try {
        [self.graphicsBridge resizeToWidth:resolution.width height:resolution.height];
        NSLog(@"[GraphicsEnhancedExecutionEngine] Graphics resolution set to %.0fx%.0f",
              resolution.width, resolution.height);
    } @catch (NSException *exception) {
        NSLog(@"[GraphicsEnhancedExecutionEngine] Exception setting resolution: %@", exception);
    }
}

- (UIImage *)captureCurrentFrame {
    // 临时返回nil，避免潜在的内存问题
    return nil;
}

#pragma mark - 渲染循环 - 完全重写，线程安全

- (void)startRenderLoop {
    if (_shouldStopRendering) {
        NSLog(@"[GraphicsEnhancedExecutionEngine] Render loop start cancelled - stopping flag set");
        return;
    }
    
    ENSURE_MAIN_THREAD(^{
        if (self->_renderTimer) {
            [self->_renderTimer invalidate];
            self->_renderTimer = nil;
        }
        
        // 🔧 修复：使用更低的频率开始，减少CPU负载
        self->_renderTimer = [NSTimer scheduledTimerWithTimeInterval:1.0/30.0  // 30 FPS instead of 60
                                                              target:self
                                                            selector:@selector(renderFrameSafely)
                                                            userInfo:nil
                                                             repeats:YES];
        
        NSLog(@"[GraphicsEnhancedExecutionEngine] Started render loop (30 FPS) on main thread");
    });
}

- (void)renderFrameSafely {
    // 🔧 修复：添加多重安全检查
    if (_shouldStopRendering || !_isExecuting || !_graphicsEnabled || !_isInitialized) {
        return;
    }
    
    // 在专用队列中执行渲染逻辑，避免阻塞主线程
    dispatch_async(_renderQueue, ^{
        @autoreleasepool {
            [self performRenderFrame];
        }
    });
}

- (void)performRenderFrame {
    // 🔧 修复：在渲染前再次检查状态
    if (_shouldStopRendering || !_isExecuting || !_graphicsEnabled) {
        return;
    }
    
    // 检查图形桥接器是否可用
    if (!self.graphicsBridge || !self.graphicsBridge.isInitialized) {
        return;
    }
    
    @try {
        // 🔧 修复：简化渲染调用，避免复杂操作
        // 暂时注释掉presentFrame调用，避免崩溃
        // [self.graphicsBridge presentFrame];
        
        // 简单的日志输出，确认渲染循环在运行
        static int frameCount = 0;
        frameCount++;
        if (frameCount % 180 == 0) {  // 每6秒输出一次 (30 FPS * 6s = 180 frames)
            NSLog(@"[GraphicsEnhancedExecutionEngine] Render loop active - frame %d", frameCount);
        }
        
    } @catch (NSException *exception) {
        NSLog(@"[GraphicsEnhancedExecutionEngine] Exception in render frame: %@", exception);
        _shouldStopRendering = YES;  // 发生异常时停止渲染
    }
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

#pragma mark - 调试和监控

- (NSDictionary *)getDetailedSystemInfo {
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    
    // 引擎状态
    info[@"engine_initialized"] = @(_isInitialized);
    info[@"engine_executing"] = @(_isExecuting);
    info[@"graphics_enabled"] = @(_graphicsEnabled);
    info[@"should_stop_rendering"] = @(_shouldStopRendering);
    info[@"current_program"] = _currentProgramPath ?: @"none";
    info[@"render_timer_active"] = @(_renderTimer != nil);
    
    // 核心引擎信息
    if (_coreEngine) {
        @try {
            info[@"core_engine"] = [_coreEngine getSystemInfo];
        } @catch (NSException *exception) {
            info[@"core_engine"] = @{@"error": exception.description};
        }
    }
    
    // 图形桥接信息
    if (_graphicsBridge) {
        @try {
            info[@"graphics_bridge"] = [_graphicsBridge getVulkanInfo];
            info[@"metal_info"] = [_graphicsBridge getMetalInfo];
        } @catch (NSException *exception) {
            info[@"graphics_bridge"] = @{@"error": exception.description};
        }
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
    [status appendFormat:@"  Should Stop Rendering: %@\n", _shouldStopRendering ? @"YES" : @"NO"];
    [status appendFormat:@"  Current Program: %@\n", _currentProgramPath ?: @"none"];
    [status appendFormat:@"  Render Timer: %@\n", _renderTimer ? @"ACTIVE" : @"INACTIVE"];
    
    if (_coreEngine) {
        @try {
            [status appendFormat:@"  Core Engine: Available\n"];
        } @catch (NSException *exception) {
            [status appendFormat:@"  Core Engine: Error - %@\n", exception.description];
        }
    } else {
        [status appendFormat:@"  Core Engine: Not initialized\n"];
    }
    
    return [status copy];
}

#pragma mark - CompleteExecutionEngineDelegate实现

- (void)executionEngine:(CompleteExecutionEngine *)engine didStartExecution:(NSString *)programPath {
    [self notifyStartExecution:programPath];
}

- (void)executionEngine:(CompleteExecutionEngine *)engine didFinishExecution:(NSString *)programPath result:(ExecutionResult)result {
    // 🔧 修复：执行完成时停止渲染
    _shouldStopRendering = YES;
    
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
    // 🔧 修复：发生错误时停止渲染
    _shouldStopRendering = YES;
    [self notifyError:error];
}

- (void)executionEngine:(CompleteExecutionEngine *)engine didUpdateProgress:(float)progress status:(NSString *)status {
    [self notifyProgress:progress status:status];
}

@end
