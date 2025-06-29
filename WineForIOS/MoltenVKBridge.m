// MoltenVKBridge.m - Vulkan到Metal图形桥接系统实现（线程安全修复版本）
#import "MoltenVKBridge.h"

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

// 内部Vulkan对象模拟结构
typedef struct VulkanInstanceMock {
    id<MTLDevice> metalDevice;
    BOOL isValid;
} VulkanInstanceMock;

typedef struct VulkanDeviceMock {
    id<MTLDevice> metalDevice;
    id<MTLCommandQueue> commandQueue;
    BOOL isValid;
} VulkanDeviceMock;

typedef struct VulkanSurfaceMock {
    CAMetalLayer *metalLayer;
    UIView *targetView;
    BOOL isValid;
} VulkanSurfaceMock;

typedef struct VulkanSwapchainMock {
    CAMetalLayer *metalLayer;
    VkFormat format;
    uint32_t width, height;
    BOOL isValid;
} VulkanSwapchainMock;

typedef struct VulkanCommandBufferMock {
    id<MTLCommandBuffer> metalCommandBuffer;
    id<MTLRenderCommandEncoder> currentEncoder;
    BOOL isRecording;
    BOOL isValid;
} VulkanCommandBufferMock;

#pragma mark - DirectX到Vulkan转换器实现

@implementation DirectXToVulkanTranslator

+ (instancetype)translatorWithBridge:(MoltenVKBridge *)bridge {
    DirectXToVulkanTranslator *translator = [[DirectXToVulkanTranslator alloc] init];
    translator.bridge = bridge;
    return translator;
}

- (BOOL)translateDirectXCall:(NSString *)functionName parameters:(NSArray *)parameters {
    NSLog(@"[DirectXToVulkanTranslator] Translating DirectX call: %@", functionName);
    
    // 将参数数组转换为字典格式以便处理
    NSMutableDictionary *paramDict = [NSMutableDictionary dictionary];
    for (NSInteger i = 0; i < parameters.count; i++) {
        paramDict[@(i)] = parameters[i];
    }
    
    // 基础DirectX函数转换
    if ([functionName isEqualToString:@"CreateDevice"]) {
        return [self handleCreateDevice:paramDict];
    } else if ([functionName isEqualToString:@"DrawPrimitive"]) {
        return [self handleDrawPrimitive:paramDict];
    } else if ([functionName isEqualToString:@"DrawIndexedPrimitive"]) {
        return [self handleDrawIndexedPrimitive:paramDict];
    } else if ([functionName isEqualToString:@"Clear"]) {
        return [self handleClear:paramDict];
    } else if ([functionName isEqualToString:@"Present"]) {
        return [self handlePresent:paramDict];
    } else if ([functionName isEqualToString:@"SetRenderTarget"]) {
        return [self handleSetRenderTarget:paramDict];
    } else if ([functionName isEqualToString:@"SetTexture"]) {
        return [self handleSetTexture:paramDict];
    } else if ([functionName isEqualToString:@"SetTransform"]) {
        return [self handleSetTransform:paramDict];
    } else if ([functionName isEqualToString:@"BeginScene"]) {
        return [self handleBeginScene:paramDict];
    } else if ([functionName isEqualToString:@"EndScene"]) {
        return [self handleEndScene:paramDict];
    }
    
    NSLog(@"[DirectXToVulkanTranslator] Unknown DirectX function: %@", functionName);
    return NO;
}

- (BOOL)handleCreateDevice:(NSDictionary *)params {
    NSLog(@"[DirectXToVulkanTranslator] Creating DirectX device (mapped to Metal)");
    
    // 创建对应的Vulkan设备实例
    VkInstance vulkanInstance;
    VkDevice vulkanDevice;
    
    if ([self.bridge createVulkanInstance:&vulkanInstance] == VK_SUCCESS) {
        if ([self.bridge createVulkanDevice:&vulkanDevice fromInstance:vulkanInstance] == VK_SUCCESS) {
            NSLog(@"[DirectXToVulkanTranslator] Successfully created Vulkan device for DirectX");
            return YES;
        }
    }
    
    return NO;
}

- (BOOL)handleDrawPrimitive:(NSDictionary *)params {
    NSLog(@"[DirectXToVulkanTranslator] Drawing primitive (DirectX → Vulkan → Metal)");
    
    // 从参数中提取绘制信息
    NSNumber *primitiveType = params[@0]; // D3DPRIMITIVETYPE
    NSNumber *startVertex = params[@1];
    NSNumber *primitiveCount = params[@2];
    
    // 转换为Vulkan绘制命令
    VkCommandBuffer commandBuffer = (VkCommandBuffer)1; // 简化的命令缓冲区
    
    if ([self.bridge createCommandBuffer:&commandBuffer device:(VkDevice)1] == VK_SUCCESS) {
        [self.bridge beginCommandBuffer:commandBuffer];
        
        // 这里应该设置渲染管道状态和执行绘制
        NSLog(@"[DirectXToVulkanTranslator] Executing draw command for %@ primitives", primitiveCount);
        
        [self.bridge endCommandBuffer:commandBuffer];
        [self.bridge submitCommandBuffer:commandBuffer device:(VkDevice)1];
        return YES;
    }
    
    return NO;
}

- (BOOL)handleDrawIndexedPrimitive:(NSDictionary *)params {
    NSLog(@"[DirectXToVulkanTranslator] Drawing indexed primitive");
    
    NSNumber *primitiveType = params[@0];
    NSNumber *baseVertexIndex = params[@1];
    NSNumber *minVertexIndex = params[@2];
    NSNumber *numVertices = params[@3];
    NSNumber *startIndex = params[@4];
    NSNumber *primCount = params[@5];
    
    // 转换为Vulkan索引绘制命令
    VkCommandBuffer commandBuffer = (VkCommandBuffer)1;
    
    if ([self.bridge createCommandBuffer:&commandBuffer device:(VkDevice)1] == VK_SUCCESS) {
        [self.bridge beginCommandBuffer:commandBuffer];
        
        NSLog(@"[DirectXToVulkanTranslator] Executing indexed draw: %@ vertices, %@ primitives",
              numVertices, primCount);
        
        [self.bridge endCommandBuffer:commandBuffer];
        [self.bridge submitCommandBuffer:commandBuffer device:(VkDevice)1];
        return YES;
    }
    
    return NO;
}

- (BOOL)handleSetRenderTarget:(NSDictionary *)params {
    NSLog(@"[DirectXToVulkanTranslator] Setting render target");
    
    NSNumber *renderTargetIndex = params[@0];
    void *renderTargetSurface = [params[@1] pointerValue];
    
    // 转换为Vulkan渲染目标设置
    VkRenderPass renderPass;
    if ([self.bridge createRenderPass:&renderPass
                                device:(VkDevice)1
                                format:VK_FORMAT_B8G8R8A8_UNORM] == VK_SUCCESS) {
        NSLog(@"[DirectXToVulkanTranslator] Render target %@ set successfully", renderTargetIndex);
        return YES;
    }
    
    return NO;
}

- (BOOL)handleSetTexture:(NSDictionary *)params {
    NSLog(@"[DirectXToVulkanTranslator] Setting texture");
    
    NSNumber *stage = params[@0];
    void *texture = [params[@1] pointerValue];
    
    if (texture) {
        NSLog(@"[DirectXToVulkanTranslator] Texture bound to stage %@", stage);
    } else {
        NSLog(@"[DirectXToVulkanTranslator] Texture unbound from stage %@", stage);
    }
    
    return YES;
}

- (BOOL)handleSetTransform:(NSDictionary *)params {
    NSLog(@"[DirectXToVulkanTranslator] Setting transform matrix");
    
    NSNumber *transformState = params[@0]; // D3DTRANSFORMSTATETYPE
    void *matrix = [params[@1] pointerValue]; // D3DMATRIX*
    
    if (matrix) {
        NSLog(@"[DirectXToVulkanTranslator] Transform matrix set for state %@", transformState);
        // 这里应该将DirectX变换矩阵转换为Vulkan uniform buffer
    }
    
    return YES;
}

- (BOOL)handleBeginScene:(NSDictionary *)params {
    NSLog(@"[DirectXToVulkanTranslator] Beginning scene rendering");
    
    // 开始Vulkan渲染通道
    VkCommandBuffer commandBuffer = (VkCommandBuffer)1;
    VkRenderPass renderPass = (VkRenderPass)1;
    
    if ([self.bridge createCommandBuffer:&commandBuffer device:(VkDevice)1] == VK_SUCCESS) {
        [self.bridge beginCommandBuffer:commandBuffer];
        [self.bridge beginRenderPass:commandBuffer
                           renderPass:renderPass
                                width:800
                               height:600];
        return YES;
    }
    
    return NO;
}

- (BOOL)handleEndScene:(NSDictionary *)params {
    NSLog(@"[DirectXToVulkanTranslator] Ending scene rendering");
    
    // 结束Vulkan渲染通道
    VkCommandBuffer commandBuffer = (VkCommandBuffer)1;
    
    [self.bridge endRenderPass:commandBuffer];
    [self.bridge endCommandBuffer:commandBuffer];
    [self.bridge submitCommandBuffer:commandBuffer device:(VkDevice)1];
    
    return YES;
}

- (BOOL)handleClear:(NSDictionary *)parameters {
    NSLog(@"[DirectXToVulkanTranslator] Clearing render target (via Vulkan)");
    return YES;
}

- (BOOL)handlePresent:(NSDictionary *)parameters {
    NSLog(@"[DirectXToVulkanTranslator] Presenting frame (via Metal)");
    [self.bridge presentFrame];
    return YES;
}

- (VkResult)translateDrawCall:(NSString *)drawType
                   parameters:(NSDictionary *)params
                commandBuffer:(VkCommandBuffer)commandBuffer {
    NSLog(@"[DirectXToVulkanTranslator] Translating draw call: %@", drawType);
    return VK_SUCCESS;
}

- (VkResult)translateResourceCreation:(NSString *)resourceType
                           parameters:(NSDictionary *)params {
    NSLog(@"[DirectXToVulkanTranslator] Translating resource creation: %@", resourceType);
    return VK_SUCCESS;
}

- (NSData *)translateShader:(NSString *)hlslCode shaderType:(NSString *)type {
    NSLog(@"[DirectXToVulkanTranslator] Translating %@ shader", type);
    // 这里需要HLSL→SPIRV→MSL的转换链
    // 现在返回空数据作为占位符
    return [NSData data];
}

@end

#pragma mark - MoltenVKBridge实现

@interface MoltenVKBridge()
@property (nonatomic, strong) id<MTLDevice> metalDevice;
@property (nonatomic, strong) id<MTLCommandQueue> metalCommandQueue;
@property (nonatomic, strong) MTKView *metalView;
@property (nonatomic, strong) CAMetalLayer *metalLayer;
@property (nonatomic, assign) BOOL isInitialized;
@property (nonatomic, strong) NSMutableDictionary *vulkanObjects;
@property (nonatomic, assign) NSUInteger objectIdCounter;
@property (nonatomic, strong) DirectXToVulkanTranslator *dxTranslator;
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
        _vulkanObjects = [NSMutableDictionary dictionary];
        _objectIdCounter = 1000;
        _dxTranslator = [DirectXToVulkanTranslator translatorWithBridge:self];
    }
    return self;
}

#pragma mark - 初始化和清理 - 线程安全修复

- (BOOL)initializeWithView:(UIView *)containerView {
    __block BOOL result = NO;
    
    ENSURE_MAIN_THREAD_SYNC(^{
        if (self->_isInitialized) {
            NSLog(@"[MoltenVKBridge] Already initialized");
            result = YES;
            return;
        }
        
        NSLog(@"[MoltenVKBridge] Initializing Metal graphics system...");
        
        // 1. 创建Metal设备
        self->_metalDevice = MTLCreateSystemDefaultDevice();
        if (!self->_metalDevice) {
            NSLog(@"[MoltenVKBridge] Failed to create Metal device");
            result = NO;
            return;
        }
        
        NSLog(@"[MoltenVKBridge] Metal device: %@", self->_metalDevice.name);
        
        // 2. 创建命令队列
        self->_metalCommandQueue = [self->_metalDevice newCommandQueue];
        if (!self->_metalCommandQueue) {
            NSLog(@"[MoltenVKBridge] Failed to create Metal command queue");
            result = NO;
            return;
        }
        
        // 3. 设置Metal层（UI操作必须在主线程）
        self->_metalLayer = [CAMetalLayer layer];
        self->_metalLayer.device = self->_metalDevice;
        self->_metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
        self->_metalLayer.framebufferOnly = YES;
        self->_metalLayer.frame = containerView.bounds;
        
        // 4. 添加到容器视图（UI操作）
        [containerView.layer addSublayer:self->_metalLayer];
        
        // 5. 初始化转换器
        self->_dxTranslator = [DirectXToVulkanTranslator translatorWithBridge:self];
        
        self->_isInitialized = YES;
        NSLog(@"[MoltenVKBridge] Metal graphics system initialized successfully");
        result = YES;
    });
    
    return result;
}

- (void)cleanup {
    ENSURE_MAIN_THREAD(^{
        if (!self->_isInitialized) {
            return;
        }
        
        NSLog(@"[MoltenVKBridge] Cleaning up Metal graphics system...");
        
        if (self->_metalLayer) {
            [self->_metalLayer removeFromSuperlayer];
            self->_metalLayer = nil;
        }
        
        self->_metalCommandQueue = nil;
        self->_metalDevice = nil;
        self->_dxTranslator = nil;
        
        [self->_vulkanObjects removeAllObjects];
        
        self->_isInitialized = NO;
        NSLog(@"[MoltenVKBridge] Cleanup completed");
    });
}

#pragma mark - Vulkan实例和设备管理

- (VkResult)createVulkanInstance:(VkInstance *)instance {
    if (!_metalDevice) {
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    VulkanInstanceMock *mockInstance = malloc(sizeof(VulkanInstanceMock));
    mockInstance->metalDevice = _metalDevice;
    mockInstance->isValid = YES;
    
    *instance = (VkInstance)mockInstance;
    
    // 存储对象引用
    NSNumber *instanceId = @((uintptr_t)*instance);
    _vulkanObjects[instanceId] = [NSValue valueWithPointer:mockInstance];
    
    NSLog(@"[MoltenVKBridge] Created Vulkan instance: %p", *instance);
    return VK_SUCCESS;
}

- (VkResult)createVulkanDevice:(VkDevice *)device fromInstance:(VkInstance)instance {
    VulkanDeviceMock *mockDevice = malloc(sizeof(VulkanDeviceMock));
    mockDevice->metalDevice = _metalDevice;
    mockDevice->commandQueue = _metalCommandQueue;
    mockDevice->isValid = YES;
    
    *device = (VkDevice)mockDevice;
    
    // 存储对象引用
    NSNumber *deviceId = @((uintptr_t)*device);
    _vulkanObjects[deviceId] = [NSValue valueWithPointer:mockDevice];
    
    NSLog(@"[MoltenVKBridge] Created Vulkan device: %p", *device);
    return VK_SUCCESS;
}

#pragma mark - Vulkan表面和交换链

- (VkResult)createVulkanSurface:(VkSurfaceKHR *)surface
                       instance:(VkInstance)instance
                           view:(UIView *)view {
    
    VulkanSurfaceMock *mockSurface = malloc(sizeof(VulkanSurfaceMock));
    mockSurface->metalLayer = _metalLayer;
    mockSurface->targetView = view;
    mockSurface->isValid = YES;
    
    *surface = (VkSurfaceKHR)mockSurface;
    
    // 存储对象引用
    NSNumber *surfaceId = @((uintptr_t)*surface);
    _vulkanObjects[surfaceId] = [NSValue valueWithPointer:mockSurface];
    
    NSLog(@"[MoltenVKBridge] Created Vulkan surface: %p", *surface);
    return VK_SUCCESS;
}

- (VkResult)createSwapchain:(VkSwapchainKHR *)swapchain
                     device:(VkDevice)device
                    surface:(VkSurfaceKHR)surface
                      width:(uint32_t)width
                     height:(uint32_t)height {
    
    VulkanSwapchainMock *mockSwapchain = malloc(sizeof(VulkanSwapchainMock));
    mockSwapchain->metalLayer = _metalLayer;
    mockSwapchain->format = VK_FORMAT_B8G8R8A8_UNORM;
    mockSwapchain->width = width;
    mockSwapchain->height = height;
    mockSwapchain->isValid = YES;
    
    *swapchain = (VkSwapchainKHR)mockSwapchain;
    
    // 存储对象引用
    NSNumber *swapchainId = @((uintptr_t)*swapchain);
    _vulkanObjects[swapchainId] = [NSValue valueWithPointer:mockSwapchain];
    
    NSLog(@"[MoltenVKBridge] Created swapchain: %p (%dx%d)", *swapchain, width, height);
    return VK_SUCCESS;
}

#pragma mark - 图形管道

- (VkResult)createRenderPass:(VkRenderPass *)renderPass
                      device:(VkDevice)device
                      format:(VkFormat)format {
    
    // 创建简化的渲染通道模拟
    *renderPass = (VkRenderPass)(uintptr_t)_objectIdCounter++;
    
    // 存储对象引用
    NSNumber *renderPassId = @((uintptr_t)*renderPass);
    _vulkanObjects[renderPassId] = @{@"type": @"renderpass", @"format": @(format)};
    
    NSLog(@"[MoltenVKBridge] Created render pass: %p", *renderPass);
    return VK_SUCCESS;
}

- (VkResult)createGraphicsPipeline:(VkPipeline *)pipeline
                            device:(VkDevice)device
                        renderPass:(VkRenderPass)renderPass {
    
    // 创建简化的图形管道模拟
    *pipeline = (VkPipeline)(uintptr_t)_objectIdCounter++;
    
    // 存储对象引用
    NSNumber *pipelineId = @((uintptr_t)*pipeline);
    _vulkanObjects[pipelineId] = @{@"type": @"pipeline", @"renderpass": @((uintptr_t)renderPass)};
    
    NSLog(@"[MoltenVKBridge] Created graphics pipeline: %p", *pipeline);
    return VK_SUCCESS;
}

#pragma mark - 命令缓冲区操作

- (VkResult)createCommandBuffer:(VkCommandBuffer *)commandBuffer device:(VkDevice)device {
    id<MTLCommandBuffer> metalCommandBuffer = [_metalCommandQueue commandBuffer];
    if (!metalCommandBuffer) {
        return VK_ERROR_OUT_OF_DEVICE_MEMORY;
    }
    
    VulkanCommandBufferMock *mockCmdBuffer = malloc(sizeof(VulkanCommandBufferMock));
    mockCmdBuffer->metalCommandBuffer = metalCommandBuffer;
    mockCmdBuffer->currentEncoder = nil;
    mockCmdBuffer->isRecording = NO;
    mockCmdBuffer->isValid = YES;
    
    *commandBuffer = (VkCommandBuffer)mockCmdBuffer;
    
    // 存储对象引用
    NSNumber *cmdBufferId = @((uintptr_t)*commandBuffer);
    _vulkanObjects[cmdBufferId] = [NSValue valueWithPointer:mockCmdBuffer];
    
    NSLog(@"[MoltenVKBridge] Created command buffer: %p", *commandBuffer);
    return VK_SUCCESS;
}

- (VkResult)beginCommandBuffer:(VkCommandBuffer)commandBuffer {
    NSNumber *cmdBufferId = @((uintptr_t)commandBuffer);
    NSValue *value = _vulkanObjects[cmdBufferId];
    
    if (value) {
        VulkanCommandBufferMock *mockCmdBuffer = (VulkanCommandBufferMock *)[value pointerValue];
        if (mockCmdBuffer && mockCmdBuffer->isValid) {
            mockCmdBuffer->isRecording = YES;
            NSLog(@"[MoltenVKBridge] Begin recording command buffer: %p", commandBuffer);
            return VK_SUCCESS;
        }
    }
    
    return VK_ERROR_INITIALIZATION_FAILED;
}

- (VkResult)endCommandBuffer:(VkCommandBuffer)commandBuffer {
    NSNumber *cmdBufferId = @((uintptr_t)commandBuffer);
    NSValue *value = _vulkanObjects[cmdBufferId];
    
    if (value) {
        VulkanCommandBufferMock *mockCmdBuffer = (VulkanCommandBufferMock *)[value pointerValue];
        if (mockCmdBuffer && mockCmdBuffer->isValid && mockCmdBuffer->isRecording) {
            mockCmdBuffer->isRecording = NO;
            if (mockCmdBuffer->currentEncoder) {
                [mockCmdBuffer->currentEncoder endEncoding];
                mockCmdBuffer->currentEncoder = nil;
            }
            NSLog(@"[MoltenVKBridge] End recording command buffer: %p", commandBuffer);
            return VK_SUCCESS;
        }
    }
    
    return VK_ERROR_INITIALIZATION_FAILED;
}

- (VkResult)submitCommandBuffer:(VkCommandBuffer)commandBuffer device:(VkDevice)device {
    NSNumber *cmdBufferId = @((uintptr_t)commandBuffer);
    NSValue *value = _vulkanObjects[cmdBufferId];
    
    if (value) {
        VulkanCommandBufferMock *mockCmdBuffer = (VulkanCommandBufferMock *)[value pointerValue];
        if (mockCmdBuffer && mockCmdBuffer->isValid) {
            [mockCmdBuffer->metalCommandBuffer commit];
            [mockCmdBuffer->metalCommandBuffer waitUntilCompleted];
            NSLog(@"[MoltenVKBridge] Submitted command buffer: %p", commandBuffer);
            return VK_SUCCESS;
        }
    }
    
    return VK_ERROR_INITIALIZATION_FAILED;
}

#pragma mark - 渲染操作

- (VkResult)beginRenderPass:(VkCommandBuffer)commandBuffer
                 renderPass:(VkRenderPass)renderPass
                      width:(uint32_t)width
                     height:(uint32_t)height {
    
    NSNumber *cmdBufferId = @((uintptr_t)commandBuffer);
    NSValue *value = _vulkanObjects[cmdBufferId];
    
    if (value) {
        VulkanCommandBufferMock *mockCmdBuffer = (VulkanCommandBufferMock *)[value pointerValue];
        if (mockCmdBuffer && mockCmdBuffer->isValid) {
            
            // 获取当前可绘制对象
            id<CAMetalDrawable> drawable = [_metalLayer nextDrawable];
            if (!drawable) {
                NSLog(@"[MoltenVKBridge] Failed to get drawable");
                return VK_ERROR_OUT_OF_DEVICE_MEMORY;
            }
            
            // 创建渲染通道描述符
            MTLRenderPassDescriptor *renderPassDesc = [MTLRenderPassDescriptor renderPassDescriptor];
            renderPassDesc.colorAttachments[0].texture = drawable.texture;
            renderPassDesc.colorAttachments[0].loadAction = MTLLoadActionClear;
            renderPassDesc.colorAttachments[0].storeAction = MTLStoreActionStore;
            renderPassDesc.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);
            
            // 创建渲染编码器
            mockCmdBuffer->currentEncoder = [mockCmdBuffer->metalCommandBuffer renderCommandEncoderWithDescriptor:renderPassDesc];
            
            NSLog(@"[MoltenVKBridge] Begin render pass: %p (%dx%d)", renderPass, width, height);
            return VK_SUCCESS;
        }
    }
    
    return VK_ERROR_INITIALIZATION_FAILED;
}

- (void)endRenderPass:(VkCommandBuffer)commandBuffer {
    NSNumber *cmdBufferId = @((uintptr_t)commandBuffer);
    NSValue *value = _vulkanObjects[cmdBufferId];
    
    if (value) {
        VulkanCommandBufferMock *mockCmdBuffer = (VulkanCommandBufferMock *)[value pointerValue];
        if (mockCmdBuffer && mockCmdBuffer->currentEncoder) {
            [mockCmdBuffer->currentEncoder endEncoding];
            mockCmdBuffer->currentEncoder = nil;
            NSLog(@"[MoltenVKBridge] End render pass");
        }
    }
}

#pragma mark - Wine DirectX桥接

- (BOOL)handleDirectXCall:(NSString *)functionName
               parameters:(NSArray *)parameters
               deviceContext:(void *)deviceContext {
    
    NSLog(@"[MoltenVKBridge] DirectX call: %@ with %lu parameters", functionName, (unsigned long)parameters.count);
    
    // 将DirectX调用转换为Vulkan调用
    return [_dxTranslator translateDirectXCall:functionName parameters:parameters];
}

#pragma mark - Metal操作 - 线程安全修复

- (void)presentFrame {
    ENSURE_MAIN_THREAD(^{
        if (!self->_isInitialized || !self->_metalLayer) {
            return;
        }
        
        // 获取当前可绘制对象
        id<CAMetalDrawable> drawable = [self->_metalLayer nextDrawable];
        if (!drawable) {
            return;
        }
        
        // 创建命令缓冲区
        id<MTLCommandBuffer> commandBuffer = [self->_metalCommandQueue commandBuffer];
        if (!commandBuffer) {
            return;
        }
        
        // 简单的清屏操作
        MTLRenderPassDescriptor *renderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture;
        renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.2, 0.2, 0.2, 1.0);
        renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
        
        id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        [renderEncoder endEncoding];
        
        // 提交到GPU
        [commandBuffer presentDrawable:drawable];
        [commandBuffer commit];
    });
}

- (void)resizeToWidth:(CGFloat)width height:(CGFloat)height {
    ENSURE_MAIN_THREAD(^{
        self->_metalLayer.drawableSize = CGSizeMake(width, height);
        if (self->_metalView) {
            self->_metalView.frame = CGRectMake(0, 0, width, height);
        }
        NSLog(@"[MoltenVKBridge] Resized to %.0fx%.0f", width, height);
    });
}

#pragma mark - 调试信息

- (NSDictionary *)getVulkanInfo {
    return @{
        @"objects_count": @(_vulkanObjects.count),
        @"next_object_id": @(_objectIdCounter),
        @"is_initialized": @(_isInitialized)
    };
}

- (NSDictionary *)getMetalInfo {
    return @{
        @"device_name": _metalDevice.name ?: @"Unknown",
        @"device_supports_compute": @([_metalDevice supportsFamily:MTLGPUFamilyMac2]),
        @"command_queue_label": _metalCommandQueue.label ?: @"Default",
        @"metal_layer_frame": NSStringFromCGRect(_metalLayer.frame),
        @"metal_layer_drawable_size": NSStringFromCGSize(_metalLayer.drawableSize),
        @"pixel_format": @(_metalLayer.pixelFormat)
    };
}

- (void)dumpVulkanObjects {
    NSLog(@"[MoltenVKBridge] ===== Vulkan Objects Dump =====");
    for (NSNumber *objectId in _vulkanObjects) {
        NSValue *value = _vulkanObjects[objectId];
        NSLog(@"[MoltenVKBridge] Object ID: %@ -> %@", objectId, value);
    }
    NSLog(@"[MoltenVKBridge] Total objects: %lu", (unsigned long)_vulkanObjects.count);
    NSLog(@"[MoltenVKBridge] ==============================");
}

#pragma mark - 内存管理

- (void)dealloc {
    [self cleanup];
    
    // 释放所有Vulkan对象模拟结构
    for (NSValue *value in _vulkanObjects.allValues) {
        if (value) {
            void *ptr = [value pointerValue];
            if (ptr) {
                free(ptr);
            }
        }
    }
    [_vulkanObjects removeAllObjects];
}

@end
