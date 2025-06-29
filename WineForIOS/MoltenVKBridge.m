#import "MoltenVKBridge.h"

// 错误域常量定义
NSString * const MoltenVKBridgeErrorDomainInitialization = @"MoltenVKBridgeErrorInitialization";
NSString * const MoltenVKBridgeErrorDomainDeviceCreation = @"MoltenVKBridgeErrorDeviceCreation";
NSString * const MoltenVKBridgeErrorDomainCommandExecution = @"MoltenVKBridgeErrorCommandExecution";
NSString * const MoltenVKBridgeErrorDomainTranslation = @"MoltenVKBridgeErrorTranslation";
NSString * const MoltenVKBridgeErrorDomainRendering = @"MoltenVKBridgeErrorRendering";

// 便利函数实现
NSError *MoltenVKBridgeError(NSString *domain, NSInteger code, NSString *description) {
    return [NSError errorWithDomain:domain code:code userInfo:@{NSLocalizedDescriptionKey: description}];
}

@interface MoltenVKBridge()
@property (nonatomic, strong) id<MTLDevice> metalDevice;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) CAMetalLayer *metalLayer;
@property (nonatomic, assign) BOOL isInitialized;

// Vulkan模拟对象 - 内部实现
@property (nonatomic, assign) VkInstance vulkanInstance;
@property (nonatomic, assign) VkDevice vulkanDevice;

// 内部状态
@property (nonatomic, strong) DirectXToVulkanTranslator *translator;
@property (nonatomic, strong) NSMutableArray<NSValue *> *performanceMarkers;
@property (nonatomic, strong) NSMutableString *debugLog;
@property (nonatomic, assign) BOOL debugModeEnabled;
@property (nonatomic, strong) NSRecursiveLock *bridgeLock;

// 渲染状态
@property (nonatomic, strong) id<MTLRenderPipelineState> currentPipelineState;
@property (nonatomic, strong) id<MTLRenderCommandEncoder> currentRenderEncoder;
@property (nonatomic, strong) id<MTLCommandBuffer> currentCommandBuffer;
@property (nonatomic, assign) BOOL frameInProgress;
@end

@implementation MoltenVKBridge

+ (instancetype)sharedBridge {
    static MoltenVKBridge *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[MoltenVKBridge alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _isInitialized = NO;
        _debugModeEnabled = NO;
        _frameInProgress = NO;
        _bridgeLock = [[NSRecursiveLock alloc] init];
        _performanceMarkers = [NSMutableArray array];
        _debugLog = [NSMutableString string];
        
        // 创建翻译器
        _translator = [DirectXToVulkanTranslator translatorWithBridge:self];
        
        NSLog(@"[MoltenVKBridge] Initialized MoltenVK bridge");
    }
    return self;
}

- (void)dealloc {
    [self cleanup];
}

#pragma mark - 初始化方法

- (BOOL)initializeBridge {
    return [self initializeBridgeWithPreferredDevice:nil];
}

- (BOOL)initializeBridgeWithPreferredDevice:(nullable id<MTLDevice>)preferredDevice {
    [_bridgeLock lock];
    
    @try {
        if (_isInitialized) {
            NSLog(@"[MoltenVKBridge] Already initialized");
            return YES;
        }
        
        NSLog(@"[MoltenVKBridge] Initializing MoltenVK bridge...");
        
        // 1. 初始化Metal设备
        if (preferredDevice) {
            _metalDevice = preferredDevice;
        } else {
            _metalDevice = MTLCreateSystemDefaultDevice();
        }
        
        if (!_metalDevice) {
            NSLog(@"[MoltenVKBridge] CRITICAL: Failed to create Metal device");
            if (_errorHandler) {
                _errorHandler(MoltenVKBridgeError(MoltenVKBridgeErrorDomainDeviceCreation, 1, @"无法创建Metal设备"));
            }
            return NO;
        }
        
        NSLog(@"[MoltenVKBridge] Metal device created: %@", _metalDevice.name);
        
        // 2. 创建命令队列
        _commandQueue = [_metalDevice newCommandQueue];
        if (!_commandQueue) {
            NSLog(@"[MoltenVKBridge] CRITICAL: Failed to create command queue");
            if (_errorHandler) {
                _errorHandler(MoltenVKBridgeError(MoltenVKBridgeErrorDomainDeviceCreation, 2, @"无法创建命令队列"));
            }
            return NO;
        }
        
        _commandQueue.label = @"MoltenVKBridge Command Queue";
        NSLog(@"[MoltenVKBridge] Command queue created");
        
        // 3. 创建模拟的Vulkan实例和设备
        _vulkanInstance = [self createVulkanInstance];
        _vulkanDevice = [self createVulkanDevice];
        
        if (!_vulkanInstance || !_vulkanDevice) {
            NSLog(@"[MoltenVKBridge] CRITICAL: Failed to create Vulkan objects");
            if (_errorHandler) {
                _errorHandler(MoltenVKBridgeError(MoltenVKBridgeErrorDomainInitialization, 3, @"无法创建Vulkan对象"));
            }
            return NO;
        }
        
        NSLog(@"[MoltenVKBridge] Vulkan objects created");
        
        // 4. 初始化性能监控
        [_performanceMarkers removeAllObjects];
        [_debugLog setString:@""];
        
        _isInitialized = YES;
        NSLog(@"[MoltenVKBridge] MoltenVK bridge initialized successfully");
        
        return YES;
        
    } @finally {
        [_bridgeLock unlock];
    }
}

- (BOOL)initializeWithView:(UIView *)view {
    // 首先初始化桥接
    if (![self initializeBridge]) {
        NSLog(@"[MoltenVKBridge] Failed to initialize bridge");
        return NO;
    }
    
    // 然后设置Metal层
    if (![self setupMetalLayerWithView:view]) {
        NSLog(@"[MoltenVKBridge] Failed to setup Metal layer");
        return NO;
    }
    
    NSLog(@"[MoltenVKBridge] Successfully initialized with view: %@", view);
    return YES;
}

- (void)cleanup {
    [_bridgeLock lock];
    
    @try {
        if (!_isInitialized) return;
        
        NSLog(@"[MoltenVKBridge] Cleaning up MoltenVK bridge...");
        
        // 停止当前帧
        if (_frameInProgress) {
            [self endFrame];
        }
        
        // 清理Vulkan对象
        if (_vulkanDevice) {
            [self destroyVulkanDevice:_vulkanDevice];
            _vulkanDevice = NULL;
        }
        
        if (_vulkanInstance) {
            [self destroyVulkanInstance:_vulkanInstance];
            _vulkanInstance = NULL;
        }
        
        // 清理Metal对象
        _currentRenderEncoder = nil;
        _currentCommandBuffer = nil;
        _currentPipelineState = nil;
        _commandQueue = nil;
        _metalDevice = nil;
        _metalLayer = nil;
        
        // 清理状态
        [_performanceMarkers removeAllObjects];
        [_debugLog setString:@""];
        _frameInProgress = NO;
        _isInitialized = NO;
        
        NSLog(@"[MoltenVKBridge] Cleanup completed");
        
    } @finally {
        [_bridgeLock unlock];
    }
}

#pragma mark - Metal层管理

- (BOOL)setupMetalLayerWithView:(UIView *)view {
    [_bridgeLock lock];
    
    @try {
        if (!_isInitialized) {
            NSLog(@"[MoltenVKBridge] Cannot setup Metal layer - bridge not initialized");
            return NO;
        }
        
        if (!view) {
            NSLog(@"[MoltenVKBridge] Cannot setup Metal layer - view is nil");
            return NO;
        }
        
        NSLog(@"[MoltenVKBridge] Setting up Metal layer for view: %@", view);
        
        // 创建CAMetalLayer
        _metalLayer = [CAMetalLayer layer];
        _metalLayer.device = _metalDevice;
        _metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
        _metalLayer.framebufferOnly = YES;
        _metalLayer.frame = view.bounds;
        
        // 添加到视图
        [view.layer addSublayer:_metalLayer];
        
        NSLog(@"[MoltenVKBridge] Metal layer setup completed");
        return YES;
        
    } @finally {
        [_bridgeLock unlock];
    }
}

- (void)resizeMetalLayer:(CGSize)newSize {
    [_bridgeLock lock];
    
    @try {
        if (!_metalLayer) {
            NSLog(@"[MoltenVKBridge] Cannot resize - Metal layer not created");
            return;
        }
        
        _metalLayer.frame = CGRectMake(0, 0, newSize.width, newSize.height);
        _metalLayer.drawableSize = newSize;
        
        NSLog(@"[MoltenVKBridge] Metal layer resized to %.0fx%.0f", newSize.width, newSize.height);
        
    } @finally {
        [_bridgeLock unlock];
    }
}

- (void)resizeToWidth:(CGFloat)width height:(CGFloat)height {
    [self resizeMetalLayer:CGSizeMake(width, height)];
}

#pragma mark - Vulkan实例创建 (模拟)

- (VkInstance)createVulkanInstance {
    // 创建一个模拟的Vulkan实例
    // 在真实实现中，这里会调用实际的Vulkan API
    VkInstance instance = (VkInstance)CFBridgingRetain([[NSObject alloc] init]);
    NSLog(@"[MoltenVKBridge] Created Vulkan instance (simulated): %p", instance);
    return instance;
}

- (VkDevice)createVulkanDevice {
    // 创建一个模拟的Vulkan设备
    VkDevice device = (VkDevice)CFBridgingRetain([[NSObject alloc] init]);
    NSLog(@"[MoltenVKBridge] Created Vulkan device (simulated): %p", device);
    return device;
}

- (void)destroyVulkanInstance:(VkInstance)instance {
    if (instance) {
        CFBridgingRelease(instance);
        NSLog(@"[MoltenVKBridge] Destroyed Vulkan instance: %p", instance);
    }
}

- (void)destroyVulkanDevice:(VkDevice)device {
    if (device) {
        CFBridgingRelease(device);
        NSLog(@"[MoltenVKBridge] Destroyed Vulkan device: %p", device);
    }
}

#pragma mark - 渲染管道

- (VkRenderPass)createRenderPass {
    // 创建模拟的渲染通道
    VkRenderPass renderPass = (VkRenderPass)CFBridgingRetain([[NSObject alloc] init]);
    NSLog(@"[MoltenVKBridge] Created render pass (simulated): %p", renderPass);
    return renderPass;
}

- (VkPipeline)createGraphicsPipeline {
    // 创建模拟的图形管道
    VkPipeline pipeline = (VkPipeline)CFBridgingRetain([[NSObject alloc] init]);
    NSLog(@"[MoltenVKBridge] Created graphics pipeline (simulated): %p", pipeline);
    return pipeline;
}

- (VkCommandBuffer)createCommandBuffer {
    // 创建模拟的命令缓冲区
    VkCommandBuffer commandBuffer = (VkCommandBuffer)CFBridgingRetain([[NSObject alloc] init]);
    NSLog(@"[MoltenVKBridge] Created command buffer (simulated): %p", commandBuffer);
    return commandBuffer;
}

#pragma mark - 渲染控制

- (BOOL)beginFrame {
    [_bridgeLock lock];
    
    @try {
        if (!_isInitialized) {
            NSLog(@"[MoltenVKBridge] Cannot begin frame - bridge not initialized");
            return NO;
        }
        
        if (_frameInProgress) {
            NSLog(@"[MoltenVKBridge] Frame already in progress");
            return NO;
        }
        
        // 开始性能标记
        [self beginPerformanceMarker:@"Frame"];
        
        // 创建命令缓冲区
        _currentCommandBuffer = [_commandQueue commandBuffer];
        if (!_currentCommandBuffer) {
            NSLog(@"[MoltenVKBridge] Failed to create command buffer");
            [self endPerformanceMarker:@"Frame"];
            return NO;
        }
        
        _currentCommandBuffer.label = @"MoltenVKBridge Frame Command Buffer";
        
        // 如果有Metal层，获取drawable
        if (_metalLayer) {
            id<CAMetalDrawable> drawable = [_metalLayer nextDrawable];
            if (!drawable) {
                NSLog(@"[MoltenVKBridge] Failed to get drawable");
                [self endPerformanceMarker:@"Frame"];
                return NO;
            }
            
            // 创建渲染通道描述符
            MTLRenderPassDescriptor *renderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
            renderPassDescriptor.colorAttachments[0].texture = drawable.texture;
            renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
            renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
            renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);
            
            // 创建渲染编码器
            _currentRenderEncoder = [_currentCommandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
            if (!_currentRenderEncoder) {
                NSLog(@"[MoltenVKBridge] Failed to create render encoder");
                [self endPerformanceMarker:@"Frame"];
                return NO;
            }
            
            _currentRenderEncoder.label = @"MoltenVKBridge Render Encoder";
        }
        
        _frameInProgress = YES;
        NSLog(@"[MoltenVKBridge] Frame begun successfully");
        
        return YES;
        
    } @finally {
        [_bridgeLock unlock];
    }
}

- (BOOL)endFrame {
    [_bridgeLock lock];
    
    @try {
        if (!_frameInProgress) {
            NSLog(@"[MoltenVKBridge] No frame in progress");
            return NO;
        }
        
        // 结束渲染编码器
        if (_currentRenderEncoder) {
            [_currentRenderEncoder endEncoding];
            _currentRenderEncoder = nil;
        }
        
        _frameInProgress = NO;
        
        // 结束性能标记
        [self endPerformanceMarker:@"Frame"];
        
        NSLog(@"[MoltenVKBridge] Frame ended successfully");
        return YES;
        
    } @finally {
        [_bridgeLock unlock];
    }
}

- (BOOL)presentFrame {
    [_bridgeLock lock];
    
    @try {
        if (_frameInProgress) {
            NSLog(@"[MoltenVKBridge] Cannot present - frame still in progress");
            return NO;
        }
        
        if (!_currentCommandBuffer) {
            NSLog(@"[MoltenVKBridge] Cannot present - no command buffer");
            return NO;
        }
        
        // 如果有Metal层，呈现drawable
        if (_metalLayer) {
            id<CAMetalDrawable> drawable = _metalLayer.nextDrawable;
            if (drawable) {
                [_currentCommandBuffer presentDrawable:drawable];
            }
        }
        
        // 提交命令缓冲区
        [_currentCommandBuffer commit];
        [_currentCommandBuffer waitUntilCompleted];
        
        _currentCommandBuffer = nil;
        
        NSLog(@"[MoltenVKBridge] Frame presented successfully");
        
        // 通知委托
        if ([_delegate respondsToSelector:@selector(moltenVKBridge:didCompleteFrame:)]) {
            NSTimeInterval frameTime = [NSDate timeIntervalSinceReferenceDate];
            [_delegate moltenVKBridge:self didCompleteFrame:frameTime];
        }
        
        return YES;
        
    } @finally {
        [_bridgeLock unlock];
    }
}

#pragma mark - DirectX转换支持

- (BOOL)interceptDirectXCall:(NSString *)functionName parameters:(NSArray *)parameters {
    [_bridgeLock lock];
    
    @try {
        if (!_isInitialized) {
            NSLog(@"[MoltenVKBridge] Cannot intercept DirectX call - bridge not initialized");
            return NO;
        }
        
        NSLog(@"[MoltenVKBridge] Intercepting DirectX call: %@", functionName);
        
        // 记录调试信息
        if (_debugModeEnabled) {
            [_debugLog appendFormat:@"[%@] Intercepted: %@ with %lu parameters\n",
             [NSDate date], functionName, (unsigned long)parameters.count];
        }
        
        // 委托给翻译器处理
        return [_translator translateDirectXCall:functionName parameters:parameters];
        
    } @finally {
        [_bridgeLock unlock];
    }
}

- (BOOL)translateAndExecuteDirectXCall:(NSString *)functionName parameters:(NSArray *)parameters {
    // 这个方法是interceptDirectXCall的别名，保持兼容性
    return [self interceptDirectXCall:functionName parameters:parameters];
}

#pragma mark - 性能监控

- (void)beginPerformanceMarker:(NSString *)name {
    [_bridgeLock lock];
    
    @try {
        PerformanceMarker marker;
        marker.startTime = [NSDate timeIntervalSinceReferenceDate];
        marker.endTime = 0;
        marker.isActive = YES;
        strncpy(marker.name, name.UTF8String, sizeof(marker.name) - 1);
        marker.name[sizeof(marker.name) - 1] = '\0';
        
        NSValue *markerValue = [NSValue value:&marker withObjCType:@encode(PerformanceMarker)];
        [_performanceMarkers addObject:markerValue];
        
        if (_debugModeEnabled) {
            NSLog(@"[MoltenVKBridge] Performance marker started: %@", name);
        }
        
    } @finally {
        [_bridgeLock unlock];
    }
}

- (void)endPerformanceMarker:(NSString *)name {
    [_bridgeLock lock];
    
    @try {
        double endTime = [NSDate timeIntervalSinceReferenceDate];
        
        for (NSValue *markerValue in _performanceMarkers) {
            PerformanceMarker marker;
            [markerValue getValue:&marker];
            
            if (marker.isActive && strcmp(marker.name, name.UTF8String) == 0) {
                marker.endTime = endTime;
                marker.isActive = NO;
                
                // 更新数组中的值
                NSValue *updatedValue = [NSValue value:&marker withObjCType:@encode(PerformanceMarker)];
                NSUInteger index = [_performanceMarkers indexOfObject:markerValue];
                [_performanceMarkers replaceObjectAtIndex:index withObject:updatedValue];
                
                if (_debugModeEnabled) {
                    double duration = marker.endTime - marker.startTime;
                    NSLog(@"[MoltenVKBridge] Performance marker ended: %@ (%.3fms)", name, duration * 1000);
                }
                
                break;
            }
        }
        
    } @finally {
        [_bridgeLock unlock];
    }
}

- (NSDictionary *)getPerformanceMetrics {
    [_bridgeLock lock];
    
    @try {
        NSMutableArray *metrics = [NSMutableArray array];
        double totalTime = 0;
        
        for (NSValue *markerValue in _performanceMarkers) {
            PerformanceMarker marker;
            [markerValue getValue:&marker];
            
            if (!marker.isActive && marker.endTime > 0) {
                double duration = marker.endTime - marker.startTime;
                totalTime += duration;
                
                [metrics addObject:@{
                    @"name": [NSString stringWithUTF8String:marker.name],
                    @"duration": @(duration),
                    @"start_time": @(marker.startTime),
                    @"end_time": @(marker.endTime)
                }];
            }
        }
        
        return @{
            @"markers": metrics,
            @"total_time": @(totalTime),
            @"marker_count": @(metrics.count),
            @"active_markers": @([_performanceMarkers filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSValue *value, NSDictionary *bindings) {
                PerformanceMarker marker;
                [value getValue:&marker];
                return marker.isActive;
            }]].count)
        };
        
    } @finally {
        [_bridgeLock unlock];
    }
}

#pragma mark - 调试支持

- (NSString *)getSystemInfo {
    [_bridgeLock lock];
    
    @try {
        NSMutableString *info = [NSMutableString string];
        
        [info appendFormat:@"=== MoltenVK Bridge System Info ===\n"];
        [info appendFormat:@"Initialized: %@\n", _isInitialized ? @"YES" : @"NO"];
        [info appendFormat:@"Debug Mode: %@\n", _debugModeEnabled ? @"YES" : @"NO"];
        [info appendFormat:@"Frame In Progress: %@\n", _frameInProgress ? @"YES" : @"NO"];
        
        if (_metalDevice) {
            [info appendFormat:@"Metal Device: %@\n", _metalDevice.name];
            [info appendFormat:@"Metal Family: %@\n", [self getMetalFamilyString]];
        }
        
        if (_metalLayer) {
            [info appendFormat:@"Metal Layer Size: %.0fx%.0f\n", _metalLayer.frame.size.width, _metalLayer.frame.size.height];
            [info appendFormat:@"Metal Layer Pixel Format: %lu\n", (unsigned long)_metalLayer.pixelFormat];
        }
        
        [info appendFormat:@"Performance Markers: %lu\n", (unsigned long)_performanceMarkers.count];
        [info appendFormat:@"Vulkan Instance: %p\n", _vulkanInstance];
        [info appendFormat:@"Vulkan Device: %p\n", _vulkanDevice];
        
        return [info copy];
        
    } @finally {
        [_bridgeLock unlock];
    }
}

- (NSDictionary *)getVulkanInfo {
    [_bridgeLock lock];
    
    @try {
        NSMutableDictionary *info = [NSMutableDictionary dictionary];
        
        info[@"initialized"] = @(_isInitialized);
        info[@"instance"] = _vulkanInstance ? [NSString stringWithFormat:@"%p", _vulkanInstance] : @"NULL";
        info[@"device"] = _vulkanDevice ? [NSString stringWithFormat:@"%p", _vulkanDevice] : @"NULL";
        info[@"frame_in_progress"] = @(_frameInProgress);
        
        // 模拟Vulkan属性
        info[@"api_version"] = @"1.3.0";
        info[@"driver_version"] = @"1.0.0";
        info[@"vendor_id"] = @"0x106B"; // Apple
        info[@"device_id"] = @"0x0001";
        info[@"device_type"] = @"Integrated GPU";
        
        // 模拟扩展支持
        NSArray *extensions = @[
            @"VK_KHR_surface",
            @"VK_KHR_swapchain",
            @"VK_KHR_get_physical_device_properties2",
            @"VK_KHR_portability_subset",
            @"VK_EXT_metal_surface"
        ];
        info[@"extensions"] = extensions;
        
        // 模拟内存信息
        info[@"memory_types"] = @{
            @"device_local": @(256 * 1024 * 1024),  // 256MB
            @"host_visible": @(128 * 1024 * 1024),  // 128MB
            @"host_coherent": @(64 * 1024 * 1024)   // 64MB
        };
        
        return [info copy];
        
    } @finally {
        [_bridgeLock unlock];
    }
}

- (NSDictionary *)getMetalInfo {
    [_bridgeLock lock];
    
    @try {
        NSMutableDictionary *info = [NSMutableDictionary dictionary];
        
        if (_metalDevice) {
            info[@"device_name"] = _metalDevice.name ?: @"Unknown";
            
            // 修复：删除不存在的属性
            // info[@"location"] = @(_metalDevice.location);
            // info[@"location_number"] = @(_metalDevice.locationNumber);
            
            info[@"max_threads_per_threadgroup"] = @(_metalDevice.maxThreadsPerThreadgroup.width);
            info[@"has_unified_memory"] = @(_metalDevice.hasUnifiedMemory);
            info[@"supports_raytracing"] = @(_metalDevice.supportsRaytracing);
            info[@"supports_function_pointers"] = @(_metalDevice.supportsFunctionPointers);
            
            // GPU Family支持
            NSMutableArray *supportedFamilies = [NSMutableArray array];
            if ([_metalDevice supportsFamily:MTLGPUFamilyApple1]) [supportedFamilies addObject:@"Apple1"];
            if ([_metalDevice supportsFamily:MTLGPUFamilyApple2]) [supportedFamilies addObject:@"Apple2"];
            if ([_metalDevice supportsFamily:MTLGPUFamilyApple3]) [supportedFamilies addObject:@"Apple3"];
            if ([_metalDevice supportsFamily:MTLGPUFamilyApple4]) [supportedFamilies addObject:@"Apple4"];
            if ([_metalDevice supportsFamily:MTLGPUFamilyApple5]) [supportedFamilies addObject:@"Apple5"];
            if ([_metalDevice supportsFamily:MTLGPUFamilyApple6]) [supportedFamilies addObject:@"Apple6"];
            if ([_metalDevice supportsFamily:MTLGPUFamilyApple7]) [supportedFamilies addObject:@"Apple7"];
            info[@"supported_families"] = [supportedFamilies copy];
            
            // 推荐内存大小
            info[@"recommended_max_working_set_size"] = @(_metalDevice.recommendedMaxWorkingSetSize);
            
            // 当前分配的内存
            if (@available(iOS 13.0, *)) {
                info[@"current_allocated_size"] = @(_metalDevice.currentAllocatedSize);
            }
            
            // Registry ID
            info[@"registry_id"] = @(_metalDevice.registryID);
        } else {
            info[@"error"] = @"Metal device not available";
        }
        
        if (_commandQueue) {
            info[@"command_queue_label"] = _commandQueue.label ?: @"Unlabeled";
        }
        
        if (_metalLayer) {
            info[@"layer_info"] = @{
                @"pixel_format": @(_metalLayer.pixelFormat),
                @"frame_size": NSStringFromCGRect(_metalLayer.frame),
                @"drawable_size": NSStringFromCGSize(_metalLayer.drawableSize),
                @"framebuffer_only": @(_metalLayer.framebufferOnly),
                // 修复：删除不存在的属性
                // @"display_sync_enabled": @(_metalLayer.displaySyncEnabled)
            };
        }
        
        return [info copy];
        
    } @finally {
        [_bridgeLock unlock];
    }
}

- (NSString *)getMetalFamilyString {
    if (!_metalDevice) return @"Unknown";
    
    if ([_metalDevice supportsFamily:MTLGPUFamilyApple7]) return @"Apple 7";
    if ([_metalDevice supportsFamily:MTLGPUFamilyApple6]) return @"Apple 6";
    if ([_metalDevice supportsFamily:MTLGPUFamilyApple5]) return @"Apple 5";
    if ([_metalDevice supportsFamily:MTLGPUFamilyApple4]) return @"Apple 4";
    if ([_metalDevice supportsFamily:MTLGPUFamilyApple3]) return @"Apple 3";
    if ([_metalDevice supportsFamily:MTLGPUFamilyApple2]) return @"Apple 2";
    if ([_metalDevice supportsFamily:MTLGPUFamilyApple1]) return @"Apple 1";
    
    return @"Unknown Apple GPU";
}

- (void)dumpVulkanState {
    [_bridgeLock lock];
    
    @try {
        NSLog(@"[MoltenVKBridge] ===== Vulkan State Dump =====");
        NSLog(@"[MoltenVKBridge] Vulkan Instance: %p", _vulkanInstance);
        NSLog(@"[MoltenVKBridge] Vulkan Device: %p", _vulkanDevice);
        NSLog(@"[MoltenVKBridge] Frame In Progress: %@", _frameInProgress ? @"YES" : @"NO");
        NSLog(@"[MoltenVKBridge] Current Command Buffer: %@", _currentCommandBuffer);
        NSLog(@"[MoltenVKBridge] Current Render Encoder: %@", _currentRenderEncoder);
        NSLog(@"[MoltenVKBridge] Current Pipeline State: %@", _currentPipelineState);
        NSLog(@"[MoltenVKBridge] =============================");
        
    } @finally {
        [_bridgeLock unlock];
    }
}

- (void)enableDebugMode:(BOOL)enabled {
    [_bridgeLock lock];
    
    @try {
        _debugModeEnabled = enabled;
        
        if (enabled) {
            [_debugLog appendFormat:@"[%@] Debug mode enabled\n", [NSDate date]];
        }
        
        NSLog(@"[MoltenVKBridge] Debug mode %@", enabled ? @"ENABLED" : @"DISABLED");
        
    } @finally {
        [_bridgeLock unlock];
    }
}

@end

#pragma mark - DirectXToVulkanTranslator实现

@implementation DirectXToVulkanTranslator {
    NSMutableString *_translationLog;
    NSRecursiveLock *_translatorLock;
}

+ (instancetype)translatorWithBridge:(MoltenVKBridge *)bridge {
    DirectXToVulkanTranslator *translator = [[DirectXToVulkanTranslator alloc] init];
    translator.bridge = bridge;
    return translator;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _translationLog = [NSMutableString string];
        _translatorLock = [[NSRecursiveLock alloc] init];
        NSLog(@"[DirectXToVulkanTranslator] Translator initialized");
    }
    return self;
}

#pragma mark - 主要翻译方法

- (BOOL)translateDirectXCall:(NSString *)functionName parameters:(NSArray *)parameters {
    [_translatorLock lock];
    
    @try {
        NSLog(@"[DirectXToVulkanTranslator] Translating DirectX call: %@ with %lu parameters",
              functionName, (unsigned long)parameters.count);
        
        // 记录翻译日志
        [_translationLog appendFormat:@"[%@] Translating: %@(%@)\n",
         [NSDate date], functionName, [parameters componentsJoinedByString:@", "]];
        
        // 检测函数类型并分发处理
        DirectXFunctionType functionType = [self detectFunctionType:functionName];
        
        BOOL result = NO;
        
        switch (functionType) {
            case DirectXFunctionTypeDevice:
                result = [self handleDeviceCreation:functionName parameters:parameters];
                break;
                
            case DirectXFunctionTypeDraw:
                result = [self handleDrawCall:functionName parameters:parameters];
                break;
                
            case DirectXFunctionTypeResource:
                result = [self handleResourceCreation:functionName parameters:parameters];
                break;
                
            case DirectXFunctionTypeShader:
                result = [self handleShaderOperation:functionName parameters:parameters];
                break;
                
            case DirectXFunctionTypeState:
                result = [self handleStateChange:functionName parameters:parameters];
                break;
                
            case DirectXFunctionTypeContext:
            default:
                NSLog(@"[DirectXToVulkanTranslator] Unsupported function type for: %@", functionName);
                result = [self handleGenericFunction:functionName parameters:parameters];
                break;
        }
        
        // 记录结果
        [_translationLog appendFormat:@"[%@] Result: %@\n", [NSDate date], result ? @"SUCCESS" : @"FAILED"];
        
        return result;
        
    } @finally {
        [_translatorLock unlock];
    }
}

#pragma mark - 特定函数类型处理

- (BOOL)handleDeviceCreation:(NSString *)functionName parameters:(NSArray *)parameters {
    NSLog(@"[DirectXToVulkanTranslator] Handling device creation: %@", functionName);
    
    if ([functionName isEqualToString:@"D3D11CreateDevice"] ||
        [functionName isEqualToString:@"D3D11CreateDeviceAndSwapChain"]) {
        
        // 模拟设备创建
        NSLog(@"[DirectXToVulkanTranslator] Creating D3D11 device -> Vulkan device mapping");
        
        // 确保MoltenVK桥接已初始化
        if (!_bridge.isInitialized) {
            NSLog(@"[DirectXToVulkanTranslator] Bridge not initialized, initializing now...");
            if (![_bridge initializeBridge]) {
                NSLog(@"[DirectXToVulkanTranslator] Failed to initialize bridge");
                return NO;
            }
        }
        
        return YES;
    }
    
    NSLog(@"[DirectXToVulkanTranslator] Unknown device function: %@", functionName);
    return NO;
}

- (BOOL)handleDrawCall:(NSString *)functionName parameters:(NSArray *)parameters {
    NSLog(@"[DirectXToVulkanTranslator] Handling draw call: %@", functionName);
    
    // 确保帧在进行中
    if (!_bridge.frameInProgress) {
        NSLog(@"[DirectXToVulkanTranslator] Starting frame for draw call");
        if (![_bridge beginFrame]) {
            NSLog(@"[DirectXToVulkanTranslator] Failed to begin frame");
            return NO;
        }
    }
    
    if ([functionName hasPrefix:@"Draw"]) {
        // 处理各种绘制调用
        if ([functionName isEqualToString:@"DrawIndexed"]) {
            return [self handleDrawIndexed:parameters];
        } else if ([functionName isEqualToString:@"Draw"]) {
            return [self handleDraw:parameters];
        } else if ([functionName isEqualToString:@"DrawInstanced"]) {
            return [self handleDrawInstanced:parameters];
        }
    }
    
    NSLog(@"[DirectXToVulkanTranslator] Unknown draw function: %@", functionName);
    return NO;
}

- (BOOL)handleDrawIndexed:(NSArray *)parameters {
    NSLog(@"[DirectXToVulkanTranslator] Translating DrawIndexed");
    
    // 在真实实现中，这里会：
    // 1. 转换索引缓冲区
    // 2. 设置渲染状态
    // 3. 执行Metal绘制调用
    
    // 模拟实现
    if (_bridge.currentRenderEncoder) {
        // 这里应该执行实际的Metal绘制调用
        NSLog(@"[DirectXToVulkanTranslator] Executing Metal draw call");
        return YES;
    }
    
    return NO;
}

- (BOOL)handleDraw:(NSArray *)parameters {
    NSLog(@"[DirectXToVulkanTranslator] Translating Draw");
    
    // 模拟简单绘制
    if (_bridge.currentRenderEncoder) {
        NSLog(@"[DirectXToVulkanTranslator] Executing Metal draw primitives");
        return YES;
    }
    
    return NO;
}

- (BOOL)handleDrawInstanced:(NSArray *)parameters {
    NSLog(@"[DirectXToVulkanTranslator] Translating DrawInstanced");
    
    // 模拟实例化绘制
    if (_bridge.currentRenderEncoder) {
        NSLog(@"[DirectXToVulkanTranslator] Executing Metal instanced draw");
        return YES;
    }
    
    return NO;
}

- (BOOL)handleResourceCreation:(NSString *)functionName parameters:(NSArray *)parameters {
    NSLog(@"[DirectXToVulkanTranslator] Handling resource creation: %@", functionName);
    
    if ([functionName containsString:@"CreateBuffer"]) {
        return [self handleCreateBuffer:parameters];
    } else if ([functionName containsString:@"CreateTexture"]) {
        return [self handleCreateTexture:parameters];
    } else if ([functionName containsString:@"CreateShader"]) {
        return [self handleCreateShader:parameters];
    }
    
    NSLog(@"[DirectXToVulkanTranslator] Unknown resource function: %@", functionName);
    return NO;
}

- (BOOL)handleCreateBuffer:(NSArray *)parameters {
    NSLog(@"[DirectXToVulkanTranslator] Creating buffer resource");
    // 模拟缓冲区创建
    return YES;
}

- (BOOL)handleCreateTexture:(NSArray *)parameters {
    NSLog(@"[DirectXToVulkanTranslator] Creating texture resource");
    // 模拟纹理创建
    return YES;
}

- (BOOL)handleCreateShader:(NSArray *)parameters {
    NSLog(@"[DirectXToVulkanTranslator] Creating shader resource");
    // 模拟着色器创建
    return YES;
}

- (BOOL)handleShaderOperation:(NSString *)functionName parameters:(NSArray *)parameters {
    NSLog(@"[DirectXToVulkanTranslator] Handling shader operation: %@", functionName);
    
    // 处理着色器相关操作
    if ([functionName containsString:@"SetVertexShader"]) {
        NSLog(@"[DirectXToVulkanTranslator] Setting vertex shader");
        return YES;
    } else if ([functionName containsString:@"SetPixelShader"]) {
        NSLog(@"[DirectXToVulkanTranslator] Setting pixel shader");
        return YES;
    }
    
    return NO;
}

- (BOOL)handleStateChange:(NSString *)functionName parameters:(NSArray *)parameters {
    NSLog(@"[DirectXToVulkanTranslator] Handling state change: %@", functionName);
    
    // 处理状态变更
    if ([functionName containsString:@"SetRenderState"]) {
        NSLog(@"[DirectXToVulkanTranslator] Setting render state");
        return YES;
    } else if ([functionName containsString:@"SetSamplerState"]) {
        NSLog(@"[DirectXToVulkanTranslator] Setting sampler state");
        return YES;
    }
    
    return NO;
}

- (BOOL)handleGenericFunction:(NSString *)functionName parameters:(NSArray *)parameters {
    NSLog(@"[DirectXToVulkanTranslator] Handling generic function: %@", functionName);
    
    // 对于未知函数，记录警告但继续执行
    if (_bridge.warningHandler) {
        _bridge.warningHandler([NSString stringWithFormat:@"未支持的DirectX函数: %@", functionName]);
    }
    
    return YES;  // 假设成功以避免阻断执行
}

#pragma mark - 函数类型检测

- (DirectXFunctionType)detectFunctionType:(NSString *)functionName {
    if ([functionName containsString:@"CreateDevice"] ||
        [functionName containsString:@"GetDevice"]) {
        return DirectXFunctionTypeDevice;
    }
    
    if ([functionName hasPrefix:@"Draw"] || [functionName hasSuffix:@"Draw"]) {
        return DirectXFunctionTypeDraw;
    }
    
    if ([functionName containsString:@"Create"] &&
        ([functionName containsString:@"Buffer"] ||
         [functionName containsString:@"Texture"] ||
         [functionName containsString:@"Shader"])) {
        return DirectXFunctionTypeResource;
    }
    
    if ([functionName containsString:@"Shader"] ||
        [functionName containsString:@"SetVertexShader"] ||
        [functionName containsString:@"SetPixelShader"]) {
        return DirectXFunctionTypeShader;
    }
    
    if ([functionName containsString:@"SetState"] ||
        [functionName containsString:@"State"]) {
        return DirectXFunctionTypeState;
    }
    
    return DirectXFunctionTypeContext;
}

#pragma mark - 参数转换

- (NSArray *)convertDirectXParameters:(NSArray *)dxParameters toVulkanForFunction:(NSString *)functionName {
    NSMutableArray *vulkanParameters = [NSMutableArray array];
    
    // 简单的参数转换示例
    for (id parameter in dxParameters) {
        // 在真实实现中，这里会根据函数名和参数类型进行复杂的转换
        [vulkanParameters addObject:parameter];
    }
    
    NSLog(@"[DirectXToVulkanTranslator] Converted %lu parameters for %@",
          (unsigned long)dxParameters.count, functionName);
    
    return [vulkanParameters copy];
}

#pragma mark - 调试支持

- (NSString *)getTranslationLog {
    [_translatorLock lock];
    
    @try {
        return [_translationLog copy];
    } @finally {
        [_translatorLock unlock];
    }
}

- (void)clearTranslationLog {
    [_translatorLock lock];
    
    @try {
        [_translationLog setString:@""];
        NSLog(@"[DirectXToVulkanTranslator] Translation log cleared");
    } @finally {
        [_translatorLock unlock];
    }
}

@end
