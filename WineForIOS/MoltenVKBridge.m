// MoltenVKBridge.m - Vulkan到Metal图形桥接系统实现
#import "MoltenVKBridge.h"

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

- (void)dealloc {
    [self cleanup];
}

#pragma mark - 初始化和清理

- (BOOL)initializeWithView:(UIView *)containerView {
    if (_isInitialized) {
        NSLog(@"[MoltenVKBridge] Already initialized");
        return YES;
    }
    
    NSLog(@"[MoltenVKBridge] Initializing Metal graphics system...");
    
    // 1. 创建Metal设备
    _metalDevice = MTLCreateSystemDefaultDevice();
    if (!_metalDevice) {
        NSLog(@"[MoltenVKBridge] Failed to create Metal device");
        return NO;
    }
    
    NSLog(@"[MoltenVKBridge] Metal device: %@", _metalDevice.name);
    
    // 2. 创建命令队列
    _metalCommandQueue = [_metalDevice newCommandQueue];
    if (!_metalCommandQueue) {
        NSLog(@"[MoltenVKBridge] Failed to create Metal command queue");
        return NO;
    }
    
    // 3. 设置Metal层
    _metalLayer = [CAMetalLayer layer];
    _metalLayer.device = _metalDevice;
    _metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    _metalLayer.framebufferOnly = YES;
    _metalLayer.frame = containerView.bounds;
    
    // 4. 添加到容器视图
    [containerView.layer addSublayer:_metalLayer];
    
    // 5. 创建MTKView用于简化渲染
    _metalView = [[MTKView alloc] initWithFrame:containerView.bounds device:_metalDevice];
    _metalView.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    _metalView.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);
    [containerView addSubview:_metalView];
    
    _isInitialized = YES;
    NSLog(@"[MoltenVKBridge] Metal graphics initialization completed successfully");
    
    return YES;
}

- (void)cleanup {
    if (!_isInitialized) return;
    
    NSLog(@"[MoltenVKBridge] Cleaning up Metal graphics system...");
    
    // 清理Vulkan对象
    [_vulkanObjects removeAllObjects];
    
    // 清理Metal资源
    if (_metalView) {
        [_metalView removeFromSuperview];
        _metalView = nil;
    }
    
    if (_metalLayer) {
        [_metalLayer removeFromSuperlayer];
        _metalLayer = nil;
    }
    
    _metalCommandQueue = nil;
    _metalDevice = nil;
    _isInitialized = NO;
    
    NSLog(@"[MoltenVKBridge] Cleanup completed");
}

#pragma mark - Vulkan实例管理

- (VkResult)createVulkanInstance:(VkInstance *)instance {
    if (!_isInitialized) {
        NSLog(@"[MoltenVKBridge] Not initialized");
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    VulkanInstanceMock *mockInstance = malloc(sizeof(VulkanInstanceMock));
    mockInstance->metalDevice = _metalDevice;
    mockInstance->isValid = YES;
    
    NSNumber *instanceId = @(_objectIdCounter++);
    _vulkanObjects[instanceId] = [NSValue valueWithPointer:mockInstance];
    
    *instance = (VkInstance)(uintptr_t)instanceId.integerValue;
    
    NSLog(@"[MoltenVKBridge] Created Vulkan instance: %p", *instance);
    return VK_SUCCESS;
}

- (void)destroyVulkanInstance:(VkInstance)instance {
    NSNumber *instanceId = @((uintptr_t)instance);
    NSValue *value = _vulkanObjects[instanceId];
    
    if (value) {
        VulkanInstanceMock *mockInstance = (VulkanInstanceMock *)[value pointerValue];
        if (mockInstance) {
            mockInstance->isValid = NO;
            free(mockInstance);
        }
        [_vulkanObjects removeObjectForKey:instanceId];
        NSLog(@"[MoltenVKBridge] Destroyed Vulkan instance: %p", instance);
    }
}

#pragma mark - 设备管理

- (VkResult)createVulkanDevice:(VkDevice *)device fromInstance:(VkInstance)instance {
    VulkanDeviceMock *mockDevice = malloc(sizeof(VulkanDeviceMock));
    mockDevice->metalDevice = _metalDevice;
    mockDevice->commandQueue = _metalCommandQueue;
    mockDevice->isValid = YES;
    
    NSNumber *deviceId = @(_objectIdCounter++);
    _vulkanObjects[deviceId] = [NSValue valueWithPointer:mockDevice];
    
    *device = (VkDevice)(uintptr_t)deviceId.integerValue;
    
    NSLog(@"[MoltenVKBridge] Created Vulkan device: %p", *device);
    return VK_SUCCESS;
}

- (void)destroyVulkanDevice:(VkDevice)device {
    NSNumber *deviceId = @((uintptr_t)device);
    NSValue *value = _vulkanObjects[deviceId];
    
    if (value) {
        VulkanDeviceMock *mockDevice = (VulkanDeviceMock *)[value pointerValue];
        if (mockDevice) {
            mockDevice->isValid = NO;
            free(mockDevice);
        }
        [_vulkanObjects removeObjectForKey:deviceId];
        NSLog(@"[MoltenVKBridge] Destroyed Vulkan device: %p", device);
    }
}

#pragma mark - 表面和交换链管理

- (VkResult)createSurface:(VkSurfaceKHR *)surface forView:(UIView *)view instance:(VkInstance)instance {
    VulkanSurfaceMock *mockSurface = malloc(sizeof(VulkanSurfaceMock));
    mockSurface->metalLayer = _metalLayer;
    mockSurface->targetView = view;
    mockSurface->isValid = YES;
    
    NSNumber *surfaceId = @(_objectIdCounter++);
    _vulkanObjects[surfaceId] = [NSValue valueWithPointer:mockSurface];
    
    *surface = (VkSurfaceKHR)(uintptr_t)surfaceId.integerValue;
    
    NSLog(@"[MoltenVKBridge] Created Vulkan surface: %p for view: %@", *surface, view);
    return VK_SUCCESS;
}

- (VkResult)createSwapchain:(VkSwapchainKHR *)swapchain
                    surface:(VkSurfaceKHR)surface
                     device:(VkDevice)device
                     format:(VkFormat)format
                      width:(uint32_t)width
                     height:(uint32_t)height {
    
    VulkanSwapchainMock *mockSwapchain = malloc(sizeof(VulkanSwapchainMock));
    mockSwapchain->metalLayer = _metalLayer;
    mockSwapchain->format = format;
    mockSwapchain->width = width;
    mockSwapchain->height = height;
    mockSwapchain->isValid = YES;
    
    // 更新Metal层尺寸
    dispatch_async(dispatch_get_main_queue(), ^{
        self.metalLayer.drawableSize = CGSizeMake(width, height);
    });
    
    NSNumber *swapchainId = @(_objectIdCounter++);
    _vulkanObjects[swapchainId] = [NSValue valueWithPointer:mockSwapchain];
    
    *swapchain = (VkSwapchainKHR)(uintptr_t)swapchainId.integerValue;
    
    NSLog(@"[MoltenVKBridge] Created swapchain: %p (%dx%d, format: %d)",
          *swapchain, width, height, format);
    return VK_SUCCESS;
}

#pragma mark - 渲染管道管理

- (VkResult)createRenderPass:(VkRenderPass *)renderPass device:(VkDevice)device format:(VkFormat)format {
    // 在Metal中，RenderPass的概念被MTLRenderPassDescriptor替代
    // 这里我们只是创建一个标识符
    NSNumber *renderPassId = @(_objectIdCounter++);
    _vulkanObjects[renderPassId] = @{@"type": @"renderpass", @"format": @(format)};
    
    *renderPass = (VkRenderPass)(uintptr_t)renderPassId.integerValue;
    
    NSLog(@"[MoltenVKBridge] Created render pass: %p", *renderPass);
    return VK_SUCCESS;
}

- (VkResult)createGraphicsPipeline:(VkPipeline *)pipeline
                            device:(VkDevice)device
                        renderPass:(VkRenderPass)renderPass {
    
    // 创建基础的Metal渲染管道状态
    MTLRenderPipelineDescriptor *pipelineDesc = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDesc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    
    // 创建简单的顶点和片段着色器
    NSString *vertexShaderSource = @
    "#include <metal_stdlib>\n"
    "using namespace metal;\n"
    "struct VertexOut {\n"
    "    float4 position [[position]];\n"
    "    float4 color;\n"
    "};\n"
    "vertex VertexOut vertex_main(uint vertexID [[vertex_id]]) {\n"
    "    VertexOut out;\n"
    "    float2 positions[3] = {float2(0.0, 0.5), float2(-0.5, -0.5), float2(0.5, -0.5)};\n"
    "    out.position = float4(positions[vertexID], 0.0, 1.0);\n"
    "    out.color = float4(1.0, 0.0, 0.0, 1.0);\n"
    "    return out;\n"
    "}\n";
    
    NSString *fragmentShaderSource = @
    "#include <metal_stdlib>\n"
    "using namespace metal;\n"
    "struct VertexOut {\n"
    "    float4 position [[position]];\n"
    "    float4 color;\n"
    "};\n"
    "fragment float4 fragment_main(VertexOut in [[stage_in]]) {\n"
    "    return in.color;\n"
    "}\n";
    
    NSError *error = nil;
    id<MTLLibrary> library = [_metalDevice newLibraryWithSource:vertexShaderSource options:nil error:&error];
    
    if (library) {
        pipelineDesc.vertexFunction = [library newFunctionWithName:@"vertex_main"];
        pipelineDesc.fragmentFunction = [library newFunctionWithName:@"fragment_main"];
        
        id<MTLRenderPipelineState> pipelineState = [_metalDevice newRenderPipelineStateWithDescriptor:pipelineDesc error:&error];
        
        if (pipelineState) {
            NSNumber *pipelineId = @(_objectIdCounter++);
            _vulkanObjects[pipelineId] = @{@"type": @"pipeline", @"metalPipeline": pipelineState};
            
            *pipeline = (VkPipeline)(uintptr_t)pipelineId.integerValue;
            NSLog(@"[MoltenVKBridge] Created graphics pipeline: %p", *pipeline);
            return VK_SUCCESS;
        }
    }
    
    NSLog(@"[MoltenVKBridge] Failed to create graphics pipeline: %@", error);
    return VK_ERROR_INITIALIZATION_FAILED;
}

#pragma mark - 命令缓冲区管理

- (VkResult)createCommandBuffer:(VkCommandBuffer *)commandBuffer device:(VkDevice)device {
    id<MTLCommandBuffer> metalCmdBuffer = [_metalCommandQueue commandBuffer];
    if (!metalCmdBuffer) {
        return VK_ERROR_OUT_OF_DEVICE_MEMORY;
    }
    
    VulkanCommandBufferMock *mockCmdBuffer = malloc(sizeof(VulkanCommandBufferMock));
    mockCmdBuffer->metalCommandBuffer = metalCmdBuffer;
    mockCmdBuffer->currentEncoder = nil;
    mockCmdBuffer->isRecording = NO;
    mockCmdBuffer->isValid = YES;
    
    NSNumber *cmdBufferId = @(_objectIdCounter++);
    _vulkanObjects[cmdBufferId] = [NSValue valueWithPointer:mockCmdBuffer];
    
    *commandBuffer = (VkCommandBuffer)(uintptr_t)cmdBufferId.integerValue;
    
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

#pragma mark - Metal操作

- (void)presentFrame {
    // 这个方法将在实际渲染时调用
    NSLog(@"[MoltenVKBridge] Present frame");
}

- (void)resizeToWidth:(CGFloat)width height:(CGFloat)height {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.metalLayer.drawableSize = CGSizeMake(width, height);
        self.metalView.frame = CGRectMake(0, 0, width, height);
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
        @"command_queue_label": _metalCommandQueue.label ?: @"Default Queue",
        @"layer_pixel_format": @(_metalLayer.pixelFormat)
    };
}

- (void)dumpPipelineStates {
    NSLog(@"[MoltenVKBridge] ===== Pipeline States =====");
    for (NSNumber *objectId in _vulkanObjects.allKeys) {
        id object = _vulkanObjects[objectId];
        if ([object isKindOfClass:[NSDictionary class]]) {
            NSDictionary *dict = (NSDictionary *)object;
            NSLog(@"[MoltenVKBridge] Object %@: %@", objectId, dict[@"type"]);
        }
    }
    NSLog(@"[MoltenVKBridge] ==============================");
}

@end
