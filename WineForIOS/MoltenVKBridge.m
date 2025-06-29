// MoltenVKBridge.m - 完整修复版本
#import "MoltenVKBridge.h"
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>

// 魔术数字常量 - 用于检测内存损坏
#define VULKAN_CMDBUFFER_MAGIC 0x12345678
#define VULKAN_SURFACE_MAGIC   0x87654321
#define VULKAN_SWAPCHAIN_MAGIC 0xABCDEF00
#define VULKAN_DEVICE_MAGIC    0x11223344
#define VULKAN_INSTANCE_MAGIC  0x55667788
#define VULKAN_RENDERPASS_MAGIC 0x99AABBCC
#define VULKAN_PIPELINE_MAGIC  0xDDEEFF00
#define VULKAN_BUFFER_MAGIC    0x12ABCD34
#define VULKAN_IMAGE_MAGIC     0x56EF7890

// Vulkan对象模拟结构体 - 添加内存对齐和魔术数字
typedef struct __attribute__((aligned(8))) {
    __unsafe_unretained id<MTLCommandBuffer> metalCommandBuffer;
    __unsafe_unretained id<MTLRenderCommandEncoder> currentEncoder;
    __unsafe_unretained id<MTLComputeCommandEncoder> computeEncoder;
    __unsafe_unretained id<MTLBlitCommandEncoder> blitEncoder;
    BOOL isRecording;
    BOOL isValid;
    uint64_t creationTime;
    uint32_t magic;
    uint32_t padding; // 确保8字节对齐
} VulkanCommandBufferMock;

typedef struct __attribute__((aligned(8))) {
    __unsafe_unretained CAMetalLayer *metalLayer;
    __unsafe_unretained UIView *targetView;
    CGSize surfaceSize;
    BOOL isValid;
    uint64_t creationTime;
    uint32_t magic;
    uint32_t padding;
} VulkanSurfaceMock;

typedef struct __attribute__((aligned(8))) {
    __unsafe_unretained CAMetalLayer *metalLayer;
    VkFormat format;
    uint32_t width;
    uint32_t height;
    uint32_t imageCount;
    BOOL isValid;
    uint64_t creationTime;
    uint32_t magic;
    uint32_t padding;
} VulkanSwapchainMock;

typedef struct __attribute__((aligned(8))) {
    __unsafe_unretained id<MTLDevice> metalDevice;
    VkInstance parentInstance;
    BOOL isValid;
    uint64_t creationTime;
    uint32_t magic;
    uint32_t padding;
} VulkanDeviceMock;

typedef struct __attribute__((aligned(8))) {
    NSString *name;
    BOOL isValid;
    uint64_t creationTime;
    uint32_t magic;
    uint32_t padding;
} VulkanInstanceMock;

typedef struct __attribute__((aligned(8))) {
    VkFormat format;
    uint32_t width;
    uint32_t height;
    BOOL hasDepthAttachment;
    BOOL isValid;
    uint64_t creationTime;
    uint32_t magic;
    uint32_t padding;
} VulkanRenderPassMock;

typedef struct __attribute__((aligned(8))) {
    __unsafe_unretained id<MTLRenderPipelineState> metalPipelineState;
    VkRenderPass renderPass;
    BOOL isValid;
    uint64_t creationTime;
    uint32_t magic;
    uint32_t padding;
} VulkanPipelineMock;

typedef struct __attribute__((aligned(8))) {
    __unsafe_unretained id<MTLBuffer> metalBuffer;
    uint64_t size;
    VkFlags usage;
    BOOL isValid;
    uint64_t creationTime;
    uint32_t magic;
    uint32_t padding;
} VulkanBufferMock;

typedef struct __attribute__((aligned(8))) {
    __unsafe_unretained id<MTLTexture> metalTexture;
    VkFormat format;
    uint32_t width;
    uint32_t height;
    VkFlags usage;
    BOOL isValid;
    uint64_t creationTime;
    uint32_t magic;
    uint32_t padding;
} VulkanImageMock;

// 性能监控结构
typedef struct {
    NSString *markerName;
    NSTimeInterval startTime;
    NSTimeInterval endTime;
    BOOL isActive;
} PerformanceMarker;

@interface MoltenVKBridge()
@property (nonatomic, strong) id<MTLDevice> metalDevice;
@property (nonatomic, strong) id<MTLCommandQueue> metalCommandQueue;
@property (nonatomic, strong) CAMetalLayer *metalLayer;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSValue *> *vulkanObjects;
@property (nonatomic, strong) DirectXToVulkanTranslator *dxTranslator;
@property (nonatomic, assign) uint64_t objectIdCounter;
@property (nonatomic, assign) BOOL isInitialized;
@property (nonatomic, assign) BOOL isReady;
@property (nonatomic, assign) NSUInteger totalObjectsCreated;
@property (nonatomic, assign) NSUInteger totalObjectsDestroyed;
@property (nonatomic, strong) NSString *lastError;
@property (nonatomic, strong) NSMutableArray<NSValue *> *performanceMarkers;
@property (nonatomic, strong) dispatch_queue_t bridgeQueue;
@property (nonatomic, strong) NSLock *objectsLock;
@end

@implementation MoltenVKBridge

#pragma mark - 单例和初始化

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
        _isReady = NO;
        _objectIdCounter = 1000; // 从较大数字开始，避免与小地址混淆
        _totalObjectsCreated = 0;
        _totalObjectsDestroyed = 0;
        _vulkanObjects = [NSMutableDictionary dictionary];
        _performanceMarkers = [NSMutableArray array];
        _lastError = @"";
        
        // 创建线程安全的队列和锁
        _bridgeQueue = dispatch_queue_create("com.wineforios.moltenvkbridge", DISPATCH_QUEUE_SERIAL);
        _objectsLock = [[NSLock alloc] init];
        
        // 延迟创建转换器
        _dxTranslator = nil;
        
        NSLog(@"[MoltenVKBridge] Initialized (not ready for use until initializeWithView is called)");
    }
    return self;
}

#pragma mark - 初始化和清理

- (BOOL)initializeWithView:(UIView *)containerView {
    if (_isInitialized) {
        NSLog(@"[MoltenVKBridge] Already initialized");
        return YES;
    }
    
    NSLog(@"[MoltenVKBridge] Initializing MoltenVK bridge...");
    
    // 输入验证
    if (!containerView) {
        _lastError = @"Container view is nil";
        NSLog(@"[MoltenVKBridge] ERROR: %@", _lastError);
        return NO;
    }
    
    // 1. 创建Metal设备
    _metalDevice = MTLCreateSystemDefaultDevice();
    if (!_metalDevice) {
        _lastError = @"Failed to create Metal device";
        NSLog(@"[MoltenVKBridge] ERROR: %@", _lastError);
        return NO;
    }
    
    NSLog(@"[MoltenVKBridge] Created Metal device: %@", _metalDevice.name);
    
    // 2. 创建命令队列
    _metalCommandQueue = [_metalDevice newCommandQueue];
    if (!_metalCommandQueue) {
        _lastError = @"Failed to create Metal command queue";
        NSLog(@"[MoltenVKBridge] ERROR: %@", _lastError);
        return NO;
    }
    
    _metalCommandQueue.label = @"WineForIOS-CommandQueue";
    NSLog(@"[MoltenVKBridge] Created Metal command queue");
    
    // 3. 设置Metal层
    _metalLayer = [CAMetalLayer layer];
    _metalLayer.device = _metalDevice;
    _metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    _metalLayer.framebufferOnly = YES;
    // displaySyncEnabled 不是CAMetalLayer的有效属性，移除
    
    // 确保在主线程设置UI
    if ([NSThread isMainThread]) {
        [self setupMetalLayerWithView:containerView];
    } else {
        dispatch_sync(dispatch_get_main_queue(), ^{
            [self setupMetalLayerWithView:containerView];
        });
    }
    
    // 4. 创建DirectX转换器
    _dxTranslator = [DirectXToVulkanTranslator translatorWithBridge:self];
    if (!_dxTranslator) {
        _lastError = @"Failed to create DirectX translator";
        NSLog(@"[MoltenVKBridge] ERROR: %@", _lastError);
        return NO;
    }
    
    _isInitialized = YES;
    _isReady = YES;
    _lastError = @"";
    
    NSLog(@"[MoltenVKBridge] MoltenVK bridge initialized successfully");
    NSLog(@"[MoltenVKBridge] Metal device: %@", _metalDevice.name);
    NSLog(@"[MoltenVKBridge] Layer size: %@", NSStringFromCGSize(_metalLayer.drawableSize));
    
    return YES;
}

- (void)setupMetalLayerWithView:(UIView *)containerView {
    _metalLayer.frame = containerView.bounds;
    _metalLayer.drawableSize = containerView.bounds.size;
    [containerView.layer addSublayer:_metalLayer];
    NSLog(@"[MoltenVKBridge] Metal layer added to view with size: %@", NSStringFromCGSize(containerView.bounds.size));
}

- (void)cleanup {
    NSLog(@"[MoltenVKBridge] Cleaning up MoltenVK bridge...");
    
    [self beginPerformanceMarker:@"Cleanup"];
    
    // 停止所有操作
    _isReady = NO;
    
    // 等待所有队列中的操作完成
    dispatch_sync(_bridgeQueue, ^{
        // 清理所有Vulkan对象
        [self cleanupVulkanObjects];
        
        // 清理Metal资源
        if (self->_metalLayer) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self->_metalLayer removeFromSuperlayer];
            });
            self->_metalLayer = nil;
        }
        
        self->_metalCommandQueue = nil;
        self->_metalDevice = nil;
        self->_dxTranslator = nil;
        
        [self->_vulkanObjects removeAllObjects];
        [self->_performanceMarkers removeAllObjects];
        
        self->_isInitialized = NO;
        self->_lastError = @"";
    });
    
    [self endPerformanceMarker];
    
    NSLog(@"[MoltenVKBridge] Cleanup completed. Stats - Created: %lu, Destroyed: %lu",
          (unsigned long)_totalObjectsCreated, (unsigned long)_totalObjectsDestroyed);
}

- (void)reset {
    NSLog(@"[MoltenVKBridge] Resetting bridge state...");
    
    [_objectsLock lock];
    
    // 清理所有对象但保持初始化状态
    [self cleanupVulkanObjects];
    [_vulkanObjects removeAllObjects];
    [_performanceMarkers removeAllObjects];
    
    _objectIdCounter = 1000;
    _totalObjectsDestroyed += _totalObjectsCreated;
    _totalObjectsCreated = 0;
    _lastError = @"";
    
    [_objectsLock unlock];
    
    NSLog(@"[MoltenVKBridge] Reset completed");
}

#pragma mark - 安全的内存管理

- (void)cleanupVulkanObjects {
    NSLog(@"[MoltenVKBridge] Cleaning up %lu Vulkan objects...", (unsigned long)_vulkanObjects.count);
    
    [_objectsLock lock];
    
    NSUInteger freedCount = 0;
    NSUInteger invalidCount = 0;
    
    for (NSNumber *objectId in [_vulkanObjects allKeys]) {
        NSValue *value = _vulkanObjects[objectId];
        if (value) {
            void *ptr = [value pointerValue];
            if (ptr) {
                if ([self isValidMockStructure:ptr]) {
                    free(ptr);
                    freedCount++;
                } else {
                    invalidCount++;
                    NSLog(@"[MoltenVKBridge] WARNING: Invalid magic number for object %@, skipping free", objectId);
                }
            }
        }
    }
    
    [_objectsLock unlock];
    
    NSLog(@"[MoltenVKBridge] Cleanup stats - Freed: %lu, Invalid: %lu",
          (unsigned long)freedCount, (unsigned long)invalidCount);
}

- (BOOL)isValidMockStructure:(void *)ptr {
    if (!ptr) {
        return NO;
    }
    
    // 检查各种可能的魔术数字
    uint32_t *magicPtr = (uint32_t *)((char *)ptr + sizeof(void *) * 4);
    uint32_t magic = *magicPtr;
    
    return (magic == VULKAN_CMDBUFFER_MAGIC ||
            magic == VULKAN_SURFACE_MAGIC ||
            magic == VULKAN_SWAPCHAIN_MAGIC ||
            magic == VULKAN_DEVICE_MAGIC ||
            magic == VULKAN_INSTANCE_MAGIC ||
            magic == VULKAN_RENDERPASS_MAGIC ||
            magic == VULKAN_PIPELINE_MAGIC ||
            magic == VULKAN_BUFFER_MAGIC ||
            magic == VULKAN_IMAGE_MAGIC);
}

#pragma mark - 安全性检查

- (BOOL)isValidCommandBuffer:(VkCommandBuffer)commandBuffer {
    if (!commandBuffer) {
        return NO;
    }
    
    VulkanCommandBufferMock *mockCmdBuffer = (VulkanCommandBufferMock *)commandBuffer;
    
    @try {
        return (mockCmdBuffer->magic == VULKAN_CMDBUFFER_MAGIC && mockCmdBuffer->isValid);
    } @catch (NSException *exception) {
        NSLog(@"[MoltenVKBridge] Exception checking command buffer validity: %@", exception);
        return NO;
    }
}

- (BOOL)isValidVulkanObject:(void *)vulkanObject {
    if (!vulkanObject) {
        return NO;
    }
    
    return [self isValidMockStructure:vulkanObject];
}

- (BOOL)canCreateObjects {
    return _isInitialized && _isReady && _metalDevice && _metalCommandQueue;
}

- (NSUInteger)activeObjectCount {
    [_objectsLock lock];
    NSUInteger count = _vulkanObjects.count;
    [_objectsLock unlock];
    return count;
}

#pragma mark - Vulkan实例和设备管理

- (VkResult)createVulkanInstance:(VkInstance *)instance {
    if (![self canCreateObjects]) {
        _lastError = @"Bridge not ready for object creation";
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    VulkanInstanceMock *mockInstance = calloc(1, sizeof(VulkanInstanceMock));
    if (!mockInstance) {
        _lastError = @"Failed to allocate memory for Vulkan instance";
        return VK_ERROR_OUT_OF_DEVICE_MEMORY;
    }
    
    mockInstance->name = @"WineForIOS-VulkanInstance";
    mockInstance->isValid = YES;
    mockInstance->creationTime = [[NSDate date] timeIntervalSince1970];
    mockInstance->magic = VULKAN_INSTANCE_MAGIC;
    
    *instance = (VkInstance)mockInstance;
    
    [_objectsLock lock];
    NSNumber *instanceId = @((uintptr_t)*instance);
    _vulkanObjects[instanceId] = [NSValue valueWithPointer:mockInstance];
    _totalObjectsCreated++;
    [_objectsLock unlock];
    
    NSLog(@"[MoltenVKBridge] Created Vulkan instance: %p", *instance);
    return VK_SUCCESS;
}

- (VkResult)createVulkanDevice:(VkDevice *)device fromInstance:(VkInstance)instance {
    if (![self canCreateObjects]) {
        _lastError = @"Bridge not ready for object creation";
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    if (!instance || ![self isValidVulkanObject:instance]) {
        _lastError = @"Invalid Vulkan instance";
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    VulkanDeviceMock *mockDevice = calloc(1, sizeof(VulkanDeviceMock));
    if (!mockDevice) {
        _lastError = @"Failed to allocate memory for Vulkan device";
        return VK_ERROR_OUT_OF_DEVICE_MEMORY;
    }
    
    mockDevice->metalDevice = _metalDevice;
    mockDevice->parentInstance = instance;
    mockDevice->isValid = YES;
    mockDevice->creationTime = [[NSDate date] timeIntervalSince1970];
    mockDevice->magic = VULKAN_DEVICE_MAGIC;
    
    *device = (VkDevice)mockDevice;
    
    [_objectsLock lock];
    NSNumber *deviceId = @((uintptr_t)*device);
    _vulkanObjects[deviceId] = [NSValue valueWithPointer:mockDevice];
    _totalObjectsCreated++;
    [_objectsLock unlock];
    
    NSLog(@"[MoltenVKBridge] Created Vulkan device: %p", *device);
    return VK_SUCCESS;
}

- (void)destroyVulkanInstance:(VkInstance)instance {
    if (!instance) return;
    
    [_objectsLock lock];
    NSNumber *instanceId = @((uintptr_t)instance);
    NSValue *value = _vulkanObjects[instanceId];
    if (value) {
        void *ptr = [value pointerValue];
        if (ptr && [self isValidMockStructure:ptr]) {
            free(ptr);
            _totalObjectsDestroyed++;
        }
        [_vulkanObjects removeObjectForKey:instanceId];
    }
    [_objectsLock unlock];
    
    NSLog(@"[MoltenVKBridge] Destroyed Vulkan instance: %p", instance);
}

- (void)destroyVulkanDevice:(VkDevice)device {
    if (!device) return;
    
    [_objectsLock lock];
    NSNumber *deviceId = @((uintptr_t)device);
    NSValue *value = _vulkanObjects[deviceId];
    if (value) {
        void *ptr = [value pointerValue];
        if (ptr && [self isValidMockStructure:ptr]) {
            free(ptr);
            _totalObjectsDestroyed++;
        }
        [_vulkanObjects removeObjectForKey:deviceId];
    }
    [_objectsLock unlock];
    
    NSLog(@"[MoltenVKBridge] Destroyed Vulkan device: %p", device);
}

#pragma mark - Vulkan表面和交换链

- (VkResult)createVulkanSurface:(VkSurfaceKHR *)surface
                       instance:(VkInstance)instance
                           view:(UIView *)view {
    if (![self canCreateObjects]) {
        _lastError = @"Bridge not ready for object creation";
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    if (!instance || ![self isValidVulkanObject:instance]) {
        _lastError = @"Invalid Vulkan instance";
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    if (!view) {
        _lastError = @"View is nil";
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    VulkanSurfaceMock *mockSurface = calloc(1, sizeof(VulkanSurfaceMock));
    if (!mockSurface) {
        _lastError = @"Failed to allocate memory for Vulkan surface";
        return VK_ERROR_OUT_OF_DEVICE_MEMORY;
    }
    
    mockSurface->metalLayer = _metalLayer;
    mockSurface->targetView = view;
    mockSurface->surfaceSize = view.bounds.size;
    mockSurface->isValid = YES;
    mockSurface->creationTime = [[NSDate date] timeIntervalSince1970];
    mockSurface->magic = VULKAN_SURFACE_MAGIC;
    
    *surface = (VkSurfaceKHR)mockSurface;
    
    [_objectsLock lock];
    NSNumber *surfaceId = @((uintptr_t)*surface);
    _vulkanObjects[surfaceId] = [NSValue valueWithPointer:mockSurface];
    _totalObjectsCreated++;
    [_objectsLock unlock];
    
    NSLog(@"[MoltenVKBridge] Created Vulkan surface: %p (%.0fx%.0f)",
          *surface, view.bounds.size.width, view.bounds.size.height);
    return VK_SUCCESS;
}

- (VkResult)createSwapchain:(VkSwapchainKHR *)swapchain
                     device:(VkDevice)device
                    surface:(VkSurfaceKHR)surface
                      width:(uint32_t)width
                     height:(uint32_t)height {
    if (![self canCreateObjects]) {
        _lastError = @"Bridge not ready for object creation";
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    if (!device || ![self isValidVulkanObject:device]) {
        _lastError = @"Invalid Vulkan device";
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    if (!surface || ![self isValidVulkanObject:surface]) {
        _lastError = @"Invalid Vulkan surface";
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    VulkanSwapchainMock *mockSwapchain = calloc(1, sizeof(VulkanSwapchainMock));
    if (!mockSwapchain) {
        _lastError = @"Failed to allocate memory for Vulkan swapchain";
        return VK_ERROR_OUT_OF_DEVICE_MEMORY;
    }
    
    mockSwapchain->metalLayer = _metalLayer;
    mockSwapchain->format = VK_FORMAT_B8G8R8A8_UNORM;
    mockSwapchain->width = width;
    mockSwapchain->height = height;
    mockSwapchain->imageCount = 3; // Triple buffering
    mockSwapchain->isValid = YES;
    mockSwapchain->creationTime = [[NSDate date] timeIntervalSince1970];
    mockSwapchain->magic = VULKAN_SWAPCHAIN_MAGIC;
    
    *swapchain = (VkSwapchainKHR)mockSwapchain;
    
    [_objectsLock lock];
    NSNumber *swapchainId = @((uintptr_t)*swapchain);
    _vulkanObjects[swapchainId] = [NSValue valueWithPointer:mockSwapchain];
    _totalObjectsCreated++;
    [_objectsLock unlock];
    
    NSLog(@"[MoltenVKBridge] Created swapchain: %p (%dx%d)", *swapchain, width, height);
    return VK_SUCCESS;
}

- (void)destroyVulkanSurface:(VkSurfaceKHR)surface {
    if (!surface) return;
    
    [_objectsLock lock];
    NSNumber *surfaceId = @((uintptr_t)surface);
    NSValue *value = _vulkanObjects[surfaceId];
    if (value) {
        void *ptr = [value pointerValue];
        if (ptr && [self isValidMockStructure:ptr]) {
            free(ptr);
            _totalObjectsDestroyed++;
        }
        [_vulkanObjects removeObjectForKey:surfaceId];
    }
    [_objectsLock unlock];
    
    NSLog(@"[MoltenVKBridge] Destroyed Vulkan surface: %p", surface);
}

- (void)destroySwapchain:(VkSwapchainKHR)swapchain {
    if (!swapchain) return;
    
    [_objectsLock lock];
    NSNumber *swapchainId = @((uintptr_t)swapchain);
    NSValue *value = _vulkanObjects[swapchainId];
    if (value) {
        void *ptr = [value pointerValue];
        if (ptr && [self isValidMockStructure:ptr]) {
            free(ptr);
            _totalObjectsDestroyed++;
        }
        [_vulkanObjects removeObjectForKey:swapchainId];
    }
    [_objectsLock unlock];
    
    NSLog(@"[MoltenVKBridge] Destroyed swapchain: %p", swapchain);
}

#pragma mark - 图形管道

- (VkResult)createRenderPass:(VkRenderPass *)renderPass
                      device:(VkDevice)device
                      format:(VkFormat)format {
    if (![self canCreateObjects]) {
        _lastError = @"Bridge not ready for object creation";
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    if (!device || ![self isValidVulkanObject:device]) {
        _lastError = @"Invalid Vulkan device";
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    VulkanRenderPassMock *mockRenderPass = calloc(1, sizeof(VulkanRenderPassMock));
    if (!mockRenderPass) {
        _lastError = @"Failed to allocate memory for render pass";
        return VK_ERROR_OUT_OF_DEVICE_MEMORY;
    }
    
    mockRenderPass->format = format;
    mockRenderPass->width = 0;  // Will be set during begin render pass
    mockRenderPass->height = 0;
    mockRenderPass->hasDepthAttachment = NO;
    mockRenderPass->isValid = YES;
    mockRenderPass->creationTime = [[NSDate date] timeIntervalSince1970];
    mockRenderPass->magic = VULKAN_RENDERPASS_MAGIC;
    
    *renderPass = (VkRenderPass)mockRenderPass;
    
    [_objectsLock lock];
    NSNumber *renderPassId = @((uintptr_t)*renderPass);
    _vulkanObjects[renderPassId] = [NSValue valueWithPointer:mockRenderPass];
    _totalObjectsCreated++;
    [_objectsLock unlock];
    
    NSLog(@"[MoltenVKBridge] Created render pass: %p", *renderPass);
    return VK_SUCCESS;
}

- (VkResult)createGraphicsPipeline:(VkPipeline *)pipeline
                            device:(VkDevice)device
                        renderPass:(VkRenderPass)renderPass {
    if (![self canCreateObjects]) {
        _lastError = @"Bridge not ready for object creation";
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    if (!device || ![self isValidVulkanObject:device]) {
        _lastError = @"Invalid Vulkan device";
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    if (!renderPass || ![self isValidVulkanObject:renderPass]) {
        _lastError = @"Invalid render pass";
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    VulkanPipelineMock *mockPipeline = calloc(1, sizeof(VulkanPipelineMock));
    if (!mockPipeline) {
        _lastError = @"Failed to allocate memory for graphics pipeline";
        return VK_ERROR_OUT_OF_DEVICE_MEMORY;
    }
    
    // 创建基础的Metal渲染管道状态
    MTLRenderPipelineDescriptor *pipelineDesc = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDesc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    
    NSError *error;
    id<MTLRenderPipelineState> metalPipelineState = [_metalDevice newRenderPipelineStateWithDescriptor:pipelineDesc error:&error];
    
    if (!metalPipelineState) {
        free(mockPipeline);
        _lastError = [NSString stringWithFormat:@"Failed to create Metal pipeline state: %@", error.localizedDescription];
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    mockPipeline->metalPipelineState = metalPipelineState;
    mockPipeline->renderPass = renderPass;
    mockPipeline->isValid = YES;
    mockPipeline->creationTime = [[NSDate date] timeIntervalSince1970];
    mockPipeline->magic = VULKAN_PIPELINE_MAGIC;
    
    *pipeline = (VkPipeline)mockPipeline;
    
    [_objectsLock lock];
    NSNumber *pipelineId = @((uintptr_t)*pipeline);
    _vulkanObjects[pipelineId] = [NSValue valueWithPointer:mockPipeline];
    _totalObjectsCreated++;
    [_objectsLock unlock];
    
    NSLog(@"[MoltenVKBridge] Created graphics pipeline: %p", *pipeline);
    return VK_SUCCESS;
}

- (VkResult)createFramebuffer:(VkFramebuffer *)framebuffer
                       device:(VkDevice)device
                   renderPass:(VkRenderPass)renderPass
                        width:(uint32_t)width
                       height:(uint32_t)height {
    if (![self canCreateObjects]) {
        _lastError = @"Bridge not ready for object creation";
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    // 简化的framebuffer创建 - 在Metal中framebuffer概念与Vulkan不同
    *framebuffer = (VkFramebuffer)(uintptr_t)_objectIdCounter++;
    
    [_objectsLock lock];
    NSNumber *framebufferId = @((uintptr_t)*framebuffer);
    _vulkanObjects[framebufferId] = @{
        @"type": @"framebuffer",
        @"renderpass": @((uintptr_t)renderPass),
        @"width": @(width),
        @"height": @(height)
    };
    _totalObjectsCreated++;
    [_objectsLock unlock];
    
    NSLog(@"[MoltenVKBridge] Created framebuffer: %p (%dx%d)", *framebuffer, width, height);
    return VK_SUCCESS;
}

- (void)destroyRenderPass:(VkRenderPass)renderPass {
    if (!renderPass) return;
    
    [_objectsLock lock];
    NSNumber *renderPassId = @((uintptr_t)renderPass);
    NSValue *value = _vulkanObjects[renderPassId];
    if (value) {
        void *ptr = [value pointerValue];
        if (ptr && [self isValidMockStructure:ptr]) {
            free(ptr);
            _totalObjectsDestroyed++;
        }
        [_vulkanObjects removeObjectForKey:renderPassId];
    }
    [_objectsLock unlock];
    
    NSLog(@"[MoltenVKBridge] Destroyed render pass: %p", renderPass);
}

- (void)destroyGraphicsPipeline:(VkPipeline)pipeline {
    if (!pipeline) return;
    
    [_objectsLock lock];
    NSNumber *pipelineId = @((uintptr_t)pipeline);
    NSValue *value = _vulkanObjects[pipelineId];
    if (value) {
        void *ptr = [value pointerValue];
        if (ptr && [self isValidMockStructure:ptr]) {
            free(ptr);
            _totalObjectsDestroyed++;
        }
        [_vulkanObjects removeObjectForKey:pipelineId];
    }
    [_objectsLock unlock];
    
    NSLog(@"[MoltenVKBridge] Destroyed graphics pipeline: %p", pipeline);
}

- (void)destroyFramebuffer:(VkFramebuffer)framebuffer {
    if (!framebuffer) return;
    
    [_objectsLock lock];
    NSNumber *framebufferId = @((uintptr_t)framebuffer);
    [_vulkanObjects removeObjectForKey:framebufferId];
    _totalObjectsDestroyed++;
    [_objectsLock unlock];
    
    NSLog(@"[MoltenVKBridge] Destroyed framebuffer: %p", framebuffer);
}

#pragma mark - 着色器管理

- (VkResult)createShaderModule:(VkShaderModule *)shaderModule
                        device:(VkDevice)device
                    spirvCode:(NSData *)spirvCode {
    if (![self canCreateObjects]) {
        _lastError = @"Bridge not ready for object creation";
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    if (!spirvCode || spirvCode.length == 0) {
        _lastError = @"Invalid SPIRV code";
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    // 简化的着色器模块创建
    *shaderModule = (VkShaderModule)(uintptr_t)_objectIdCounter++;
    
    [_objectsLock lock];
    NSNumber *shaderModuleId = @((uintptr_t)*shaderModule);
    _vulkanObjects[shaderModuleId] = @{
        @"type": @"shadermodule",
        @"spirv_size": @(spirvCode.length)
    };
    _totalObjectsCreated++;
    [_objectsLock unlock];
    
    NSLog(@"[MoltenVKBridge] Created shader module: %p (SPIRV size: %lu)",
          *shaderModule, (unsigned long)spirvCode.length);
    return VK_SUCCESS;
}

- (void)destroyShaderModule:(VkShaderModule)shaderModule {
    if (!shaderModule) return;
    
    [_objectsLock lock];
    NSNumber *shaderModuleId = @((uintptr_t)shaderModule);
    [_vulkanObjects removeObjectForKey:shaderModuleId];
    _totalObjectsDestroyed++;
    [_objectsLock unlock];
    
    NSLog(@"[MoltenVKBridge] Destroyed shader module: %p", shaderModule);
}

#pragma mark - 命令缓冲区操作

- (VkResult)createCommandBuffer:(VkCommandBuffer *)commandBuffer device:(VkDevice)device {
    if (![self canCreateObjects]) {
        _lastError = @"Bridge not ready for object creation";
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    if (!device || ![self isValidVulkanObject:device]) {
        _lastError = @"Invalid Vulkan device";
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    id<MTLCommandBuffer> metalCommandBuffer = [_metalCommandQueue commandBuffer];
    if (!metalCommandBuffer) {
        _lastError = @"Failed to create Metal command buffer";
        return VK_ERROR_OUT_OF_DEVICE_MEMORY;
    }
    
    VulkanCommandBufferMock *mockCmdBuffer = calloc(1, sizeof(VulkanCommandBufferMock));
    if (!mockCmdBuffer) {
        _lastError = @"Failed to allocate memory for command buffer mock";
        return VK_ERROR_OUT_OF_DEVICE_MEMORY;
    }
    
    mockCmdBuffer->metalCommandBuffer = metalCommandBuffer;
    mockCmdBuffer->currentEncoder = nil;
    mockCmdBuffer->computeEncoder = nil;
    mockCmdBuffer->blitEncoder = nil;
    mockCmdBuffer->isRecording = NO;
    mockCmdBuffer->isValid = YES;
    mockCmdBuffer->creationTime = [[NSDate date] timeIntervalSince1970];
    mockCmdBuffer->magic = VULKAN_CMDBUFFER_MAGIC;
    
    *commandBuffer = (VkCommandBuffer)mockCmdBuffer;
    
    [_objectsLock lock];
    NSNumber *cmdBufferId = @((uintptr_t)*commandBuffer);
    _vulkanObjects[cmdBufferId] = [NSValue valueWithPointer:mockCmdBuffer];
    _totalObjectsCreated++;
    [_objectsLock unlock];
    
    NSLog(@"[MoltenVKBridge] Created command buffer: %p (Metal: %p)",
          *commandBuffer, metalCommandBuffer);
    return VK_SUCCESS;
}

- (VkResult)beginCommandBuffer:(VkCommandBuffer)commandBuffer {
    if (![self isValidCommandBuffer:commandBuffer]) {
        _lastError = @"Invalid command buffer in beginCommandBuffer";
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    VulkanCommandBufferMock *mockCmdBuffer = (VulkanCommandBufferMock *)commandBuffer;
    
    if (mockCmdBuffer->isRecording) {
        _lastError = @"Command buffer is already recording";
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    mockCmdBuffer->isRecording = YES;
    
    NSLog(@"[MoltenVKBridge] Begin recording command buffer: %p", commandBuffer);
    return VK_SUCCESS;
}

- (VkResult)endCommandBuffer:(VkCommandBuffer)commandBuffer {
    if (![self isValidCommandBuffer:commandBuffer]) {
        _lastError = @"Invalid command buffer in endCommandBuffer";
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    VulkanCommandBufferMock *mockCmdBuffer = (VulkanCommandBufferMock *)commandBuffer;
    
    if (!mockCmdBuffer->isRecording) {
        _lastError = @"Command buffer is not recording";
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    mockCmdBuffer->isRecording = NO;
    
    // 结束任何活动的编码器
    if (mockCmdBuffer->currentEncoder) {
        [mockCmdBuffer->currentEncoder endEncoding];
        mockCmdBuffer->currentEncoder = nil;
    }
    if (mockCmdBuffer->computeEncoder) {
        [mockCmdBuffer->computeEncoder endEncoding];
        mockCmdBuffer->computeEncoder = nil;
    }
    if (mockCmdBuffer->blitEncoder) {
        [mockCmdBuffer->blitEncoder endEncoding];
        mockCmdBuffer->blitEncoder = nil;
    }
    
    NSLog(@"[MoltenVKBridge] End recording command buffer: %p", commandBuffer);
    return VK_SUCCESS;
}

- (VkResult)submitCommandBuffer:(VkCommandBuffer)commandBuffer device:(VkDevice)device {
    if (![self isValidCommandBuffer:commandBuffer]) {
        _lastError = @"Invalid command buffer in submitCommandBuffer";
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    VulkanCommandBufferMock *mockCmdBuffer = (VulkanCommandBufferMock *)commandBuffer;
    
    if (!mockCmdBuffer->metalCommandBuffer) {
        _lastError = @"Metal command buffer is nil";
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    if (mockCmdBuffer->isRecording) {
        _lastError = @"Cannot submit recording command buffer";
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    [mockCmdBuffer->metalCommandBuffer commit];
    
    NSLog(@"[MoltenVKBridge] Submitted command buffer: %p", commandBuffer);
    return VK_SUCCESS;
}

- (VkResult)resetCommandBuffer:(VkCommandBuffer)commandBuffer {
    if (![self isValidCommandBuffer:commandBuffer]) {
        _lastError = @"Invalid command buffer in resetCommandBuffer";
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    VulkanCommandBufferMock *mockCmdBuffer = (VulkanCommandBufferMock *)commandBuffer;
    
    // 结束记录状态
    mockCmdBuffer->isRecording = NO;
    
    // 清理编码器
    if (mockCmdBuffer->currentEncoder) {
        [mockCmdBuffer->currentEncoder endEncoding];
        mockCmdBuffer->currentEncoder = nil;
    }
    if (mockCmdBuffer->computeEncoder) {
        [mockCmdBuffer->computeEncoder endEncoding];
        mockCmdBuffer->computeEncoder = nil;
    }
    if (mockCmdBuffer->blitEncoder) {
        [mockCmdBuffer->blitEncoder endEncoding];
        mockCmdBuffer->blitEncoder = nil;
    }
    
    // 创建新的Metal命令缓冲区
    mockCmdBuffer->metalCommandBuffer = [_metalCommandQueue commandBuffer];
    
    NSLog(@"[MoltenVKBridge] Reset command buffer: %p", commandBuffer);
    return VK_SUCCESS;
}

- (void)destroyCommandBuffer:(VkCommandBuffer)commandBuffer {
    if (!commandBuffer) return;
    
    [_objectsLock lock];
    NSNumber *cmdBufferId = @((uintptr_t)commandBuffer);
    NSValue *value = _vulkanObjects[cmdBufferId];
    if (value) {
        void *ptr = [value pointerValue];
        if (ptr && [self isValidMockStructure:ptr]) {
            VulkanCommandBufferMock *mockCmdBuffer = (VulkanCommandBufferMock *)ptr;
            
            // 清理编码器
            if (mockCmdBuffer->currentEncoder) {
                [mockCmdBuffer->currentEncoder endEncoding];
            }
            if (mockCmdBuffer->computeEncoder) {
                [mockCmdBuffer->computeEncoder endEncoding];
            }
            if (mockCmdBuffer->blitEncoder) {
                [mockCmdBuffer->blitEncoder endEncoding];
            }
            
            free(ptr);
            _totalObjectsDestroyed++;
        }
        [_vulkanObjects removeObjectForKey:cmdBufferId];
    }
    [_objectsLock unlock];
    
    NSLog(@"[MoltenVKBridge] Destroyed command buffer: %p", commandBuffer);
}

#pragma mark - 渲染操作

- (VkResult)beginRenderPass:(VkCommandBuffer)commandBuffer
                 renderPass:(VkRenderPass)renderPass
                 framebuffer:(VkFramebuffer)framebuffer
                      width:(uint32_t)width
                     height:(uint32_t)height {
    
    if (![self isValidCommandBuffer:commandBuffer]) {
        _lastError = @"Invalid command buffer in beginRenderPass";
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    if (!renderPass || ![self isValidVulkanObject:renderPass]) {
        _lastError = @"Invalid render pass";
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    VulkanCommandBufferMock *mockCmdBuffer = (VulkanCommandBufferMock *)commandBuffer;
    
    if (!_metalLayer) {
        _lastError = @"Metal layer not available";
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    // 获取当前可绘制对象
    id<CAMetalDrawable> drawable = [_metalLayer nextDrawable];
    if (!drawable) {
        _lastError = @"Failed to get drawable from Metal layer";
        return VK_ERROR_OUT_OF_DEVICE_MEMORY;
    }
    
    // 创建渲染通道描述符
    MTLRenderPassDescriptor *renderPassDesc = [MTLRenderPassDescriptor renderPassDescriptor];
    renderPassDesc.colorAttachments[0].texture = drawable.texture;
    renderPassDesc.colorAttachments[0].loadAction = MTLLoadActionClear;
    renderPassDesc.colorAttachments[0].storeAction = MTLStoreActionStore;
    renderPassDesc.colorAttachments[0].clearColor = MTLClearColorMake(0.2, 0.2, 0.2, 1.0);
    
    // 创建渲染编码器
    mockCmdBuffer->currentEncoder = [mockCmdBuffer->metalCommandBuffer renderCommandEncoderWithDescriptor:renderPassDesc];
    
    if (!mockCmdBuffer->currentEncoder) {
        _lastError = @"Failed to create render command encoder";
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    NSLog(@"[MoltenVKBridge] Begin render pass: %p (%dx%d)", renderPass, width, height);
    return VK_SUCCESS;
}

- (void)endRenderPass:(VkCommandBuffer)commandBuffer {
    if (![self isValidCommandBuffer:commandBuffer]) {
        NSLog(@"[MoltenVKBridge] Invalid command buffer in endRenderPass");
        return;
    }
    
    VulkanCommandBufferMock *mockCmdBuffer = (VulkanCommandBufferMock *)commandBuffer;
    
    if (mockCmdBuffer->currentEncoder) {
        [mockCmdBuffer->currentEncoder endEncoding];
        mockCmdBuffer->currentEncoder = nil;
        NSLog(@"[MoltenVKBridge] End render pass");
    } else {
        NSLog(@"[MoltenVKBridge] No active render encoder to end");
    }
}

#pragma mark - 绘制命令

- (VkResult)cmdDraw:(VkCommandBuffer)commandBuffer
        vertexCount:(uint32_t)vertexCount
      instanceCount:(uint32_t)instanceCount
        firstVertex:(uint32_t)firstVertex
       firstInstance:(uint32_t)firstInstance {
    
    if (![self isValidCommandBuffer:commandBuffer]) {
        _lastError = @"Invalid command buffer in cmdDraw";
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    VulkanCommandBufferMock *mockCmdBuffer = (VulkanCommandBufferMock *)commandBuffer;
    
    if (!mockCmdBuffer->currentEncoder) {
        _lastError = @"No active render encoder for draw command";
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    // 执行Metal绘制命令
    [mockCmdBuffer->currentEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                                      vertexStart:firstVertex
                                      vertexCount:vertexCount
                                    instanceCount:instanceCount
                                     baseInstance:firstInstance];
    
    NSLog(@"[MoltenVKBridge] Draw command: %d vertices, %d instances", vertexCount, instanceCount);
    return VK_SUCCESS;
}

- (VkResult)cmdDrawIndexed:(VkCommandBuffer)commandBuffer
                indexCount:(uint32_t)indexCount
             instanceCount:(uint32_t)instanceCount
                firstIndex:(uint32_t)firstIndex
             vertexOffset:(int32_t)vertexOffset
              firstInstance:(uint32_t)firstInstance {
    
    if (![self isValidCommandBuffer:commandBuffer]) {
        _lastError = @"Invalid command buffer in cmdDrawIndexed";
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    VulkanCommandBufferMock *mockCmdBuffer = (VulkanCommandBufferMock *)commandBuffer;
    
    if (!mockCmdBuffer->currentEncoder) {
        _lastError = @"No active render encoder for indexed draw command";
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    NSLog(@"[MoltenVKBridge] Indexed draw command: %d indices, %d instances", indexCount, instanceCount);
    return VK_SUCCESS;
}

#pragma mark - 缓冲区和内存管理

- (VkResult)createBuffer:(VkBuffer *)buffer
                  device:(VkDevice)device
                    size:(uint64_t)size
                   usage:(VkFlags)usage {
    if (![self canCreateObjects]) {
        _lastError = @"Bridge not ready for object creation";
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    if (!device || ![self isValidVulkanObject:device]) {
        _lastError = @"Invalid Vulkan device";
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    // 创建Metal缓冲区
    id<MTLBuffer> metalBuffer = [_metalDevice newBufferWithLength:size options:MTLResourceStorageModeShared];
    if (!metalBuffer) {
        _lastError = @"Failed to create Metal buffer";
        return VK_ERROR_OUT_OF_DEVICE_MEMORY;
    }
    
    VulkanBufferMock *mockBuffer = calloc(1, sizeof(VulkanBufferMock));
    if (!mockBuffer) {
        _lastError = @"Failed to allocate memory for buffer mock";
        return VK_ERROR_OUT_OF_DEVICE_MEMORY;
    }
    
    mockBuffer->metalBuffer = metalBuffer;
    mockBuffer->size = size;
    mockBuffer->usage = usage;
    mockBuffer->isValid = YES;
    mockBuffer->creationTime = [[NSDate date] timeIntervalSince1970];
    mockBuffer->magic = VULKAN_BUFFER_MAGIC;
    
    *buffer = (VkBuffer)mockBuffer;
    
    [_objectsLock lock];
    NSNumber *bufferId = @((uintptr_t)*buffer);
    _vulkanObjects[bufferId] = [NSValue valueWithPointer:mockBuffer];
    _totalObjectsCreated++;
    [_objectsLock unlock];
    
    NSLog(@"[MoltenVKBridge] Created buffer: %p (size: %llu)", *buffer, size);
    return VK_SUCCESS;
}

- (VkResult)createImage:(VkImage *)image
                 device:(VkDevice)device
                  width:(uint32_t)width
                 height:(uint32_t)height
                 format:(VkFormat)format
                  usage:(VkFlags)usage {
    if (![self canCreateObjects]) {
        _lastError = @"Bridge not ready for object creation";
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    if (!device || ![self isValidVulkanObject:device]) {
        _lastError = @"Invalid Vulkan device";
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    // 创建Metal纹理描述符
    MTLTextureDescriptor *textureDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                           width:width
                                                                                          height:height
                                                                                       mipmapped:NO];
    textureDesc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    
    id<MTLTexture> metalTexture = [_metalDevice newTextureWithDescriptor:textureDesc];
    if (!metalTexture) {
        _lastError = @"Failed to create Metal texture";
        return VK_ERROR_OUT_OF_DEVICE_MEMORY;
    }
    
    VulkanImageMock *mockImage = calloc(1, sizeof(VulkanImageMock));
    if (!mockImage) {
        _lastError = @"Failed to allocate memory for image mock";
        return VK_ERROR_OUT_OF_DEVICE_MEMORY;
    }
    
    mockImage->metalTexture = metalTexture;
    mockImage->format = format;
    mockImage->width = width;
    mockImage->height = height;
    mockImage->usage = usage;
    mockImage->isValid = YES;
    mockImage->creationTime = [[NSDate date] timeIntervalSince1970];
    mockImage->magic = VULKAN_IMAGE_MAGIC;
    
    *image = (VkImage)mockImage;
    
    [_objectsLock lock];
    NSNumber *imageId = @((uintptr_t)*image);
    _vulkanObjects[imageId] = [NSValue valueWithPointer:mockImage];
    _totalObjectsCreated++;
    [_objectsLock unlock];
    
    NSLog(@"[MoltenVKBridge] Created image: %p (%dx%d)", *image, width, height);
    return VK_SUCCESS;
}

- (VkResult)createImageView:(VkImageView *)imageView
                     device:(VkDevice)device
                      image:(VkImage)image
                     format:(VkFormat)format {
    if (![self canCreateObjects]) {
        _lastError = @"Bridge not ready for object creation";
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    if (!image || ![self isValidVulkanObject:image]) {
        _lastError = @"Invalid Vulkan image";
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    // 简化的图像视图创建
    *imageView = (VkImageView)(uintptr_t)_objectIdCounter++;
    
    [_objectsLock lock];
    NSNumber *imageViewId = @((uintptr_t)*imageView);
    _vulkanObjects[imageViewId] = @{
        @"type": @"imageview",
        @"image": @((uintptr_t)image),
        @"format": @(format)
    };
    _totalObjectsCreated++;
    [_objectsLock unlock];
    
    NSLog(@"[MoltenVKBridge] Created image view: %p", *imageView);
    return VK_SUCCESS;
}

- (void)destroyBuffer:(VkBuffer)buffer {
    if (!buffer) return;
    
    [_objectsLock lock];
    NSNumber *bufferId = @((uintptr_t)buffer);
    NSValue *value = _vulkanObjects[bufferId];
    if (value) {
        void *ptr = [value pointerValue];
        if (ptr && [self isValidMockStructure:ptr]) {
            free(ptr);
            _totalObjectsDestroyed++;
        }
        [_vulkanObjects removeObjectForKey:bufferId];
    }
    [_objectsLock unlock];
    
    NSLog(@"[MoltenVKBridge] Destroyed buffer: %p", buffer);
}

- (void)destroyImage:(VkImage)image {
    if (!image) return;
    
    [_objectsLock lock];
    NSNumber *imageId = @((uintptr_t)image);
    NSValue *value = _vulkanObjects[imageId];
    if (value) {
        void *ptr = [value pointerValue];
        if (ptr && [self isValidMockStructure:ptr]) {
            free(ptr);
            _totalObjectsDestroyed++;
        }
        [_vulkanObjects removeObjectForKey:imageId];
    }
    [_objectsLock unlock];
    
    NSLog(@"[MoltenVKBridge] Destroyed image: %p", image);
}

- (void)destroyImageView:(VkImageView)imageView {
    if (!imageView) return;
    
    [_objectsLock lock];
    NSNumber *imageViewId = @((uintptr_t)imageView);
    [_vulkanObjects removeObjectForKey:imageViewId];
    _totalObjectsDestroyed++;
    [_objectsLock unlock];
    
    NSLog(@"[MoltenVKBridge] Destroyed image view: %p", imageView);
}

#pragma mark - 同步操作

- (VkResult)deviceWaitIdle:(VkDevice)device {
    if (!device || ![self isValidVulkanObject:device]) {
        _lastError = @"Invalid Vulkan device";
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    // 等待Metal设备完成所有操作
    if (_metalCommandQueue) {
        id<MTLCommandBuffer> syncBuffer = [_metalCommandQueue commandBuffer];
        [syncBuffer commit];
        [syncBuffer waitUntilCompleted];
    }
    
    NSLog(@"[MoltenVKBridge] Device wait idle completed");
    return VK_SUCCESS;
}

- (VkResult)queueWaitIdle {
    if (!_metalCommandQueue) {
        _lastError = @"Metal command queue not available";
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    // 等待队列中所有命令完成
    id<MTLCommandBuffer> syncBuffer = [_metalCommandQueue commandBuffer];
    [syncBuffer commit];
    [syncBuffer waitUntilCompleted];
    
    NSLog(@"[MoltenVKBridge] Queue wait idle completed");
    return VK_SUCCESS;
}

#pragma mark - Wine DirectX桥接

- (BOOL)handleDirectXCall:(NSString *)functionName
               parameters:(NSArray *)parameters
               deviceContext:(void *)deviceContext {
    
    NSLog(@"[MoltenVKBridge] DirectX call: %@ with %lu parameters",
          functionName, (unsigned long)parameters.count);
    
    if (!_dxTranslator) {
        _lastError = @"DirectX translator not available";
        NSLog(@"[MoltenVKBridge] ERROR: %@", _lastError);
        return NO;
    }
    
    [self beginPerformanceMarker:[NSString stringWithFormat:@"DirectX-%@", functionName]];
    
    BOOL result = [_dxTranslator translateDirectXCall:functionName parameters:parameters];
    
    [self endPerformanceMarker];
    
    if (!result) {
        _lastError = [NSString stringWithFormat:@"Failed to translate DirectX call: %@", functionName];
    }
    
    return result;
}

#pragma mark - Wine图形上下文管理

- (void *)createWineGraphicsContext:(CGSize)size {
    NSLog(@"[MoltenVKBridge] Creating Wine graphics context (%.0fx%.0f)", size.width, size.height);
    
    // 创建简化的上下文结构
    void *context = malloc(sizeof(CGSize) + sizeof(BOOL));
    if (context) {
        *((CGSize *)context) = size;
        *((BOOL *)((char *)context + sizeof(CGSize))) = YES; // valid flag
    }
    
    return context;
}

- (BOOL)updateWineGraphicsContext:(void *)context size:(CGSize)size {
    if (!context) {
        return NO;
    }
    
    *((CGSize *)context) = size;
    NSLog(@"[MoltenVKBridge] Updated Wine graphics context (%.0fx%.0f)", size.width, size.height);
    return YES;
}

- (void)destroyWineGraphicsContext:(void *)context {
    if (context) {
        free(context);
        NSLog(@"[MoltenVKBridge] Destroyed Wine graphics context");
    }
}

#pragma mark - 高级图形功能

- (VkResult)presentFrame:(VkSwapchainKHR)swapchain {
    if (!swapchain || ![self isValidVulkanObject:swapchain]) {
        _lastError = @"Invalid swapchain";
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    // 在Metal中，present是通过CAMetalDrawable自动处理的
    NSLog(@"[MoltenVKBridge] Present frame for swapchain: %p", swapchain);
    return VK_SUCCESS;
}

- (VkResult)acquireNextImage:(VkSwapchainKHR)swapchain imageIndex:(uint32_t *)imageIndex {
    if (!swapchain || ![self isValidVulkanObject:swapchain]) {
        _lastError = @"Invalid swapchain";
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    if (!imageIndex) {
        _lastError = @"Image index pointer is null";
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    // 返回下一个可用的图像索引
    *imageIndex = 0; // 简化实现
    
    NSLog(@"[MoltenVKBridge] Acquired next image: %d", *imageIndex);
    return VK_SUCCESS;
}

#pragma mark - Metal特定操作 - GraphicsEnhancedExecutionEngine需要的方法

- (void)presentFrame {
    if (!_isInitialized || !_metalLayer) {
        NSLog(@"[MoltenVKBridge] Cannot present frame - not initialized or no metal layer");
        return;
    }
    
    // 确保在主线程执行
    if ([NSThread isMainThread]) {
        [self performPresentFrame];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self performPresentFrame];
        });
    }
}

- (void)performPresentFrame {
    // 获取当前可绘制对象
    id<CAMetalDrawable> drawable = [_metalLayer nextDrawable];
    if (!drawable) {
        NSLog(@"[MoltenVKBridge] Failed to get drawable for present");
        return;
    }
    
    // 创建命令缓冲区
    id<MTLCommandBuffer> commandBuffer = [_metalCommandQueue commandBuffer];
    if (!commandBuffer) {
        NSLog(@"[MoltenVKBridge] Failed to create command buffer for present");
        return;
    }
    
    // 创建简单的清屏操作
    MTLRenderPassDescriptor *renderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
    renderPassDescriptor.colorAttachments[0].texture = drawable.texture;
    renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
    renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.2, 0.2, 0.3, 1.0);
    renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
    
    id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    if (renderEncoder) {
        [renderEncoder endEncoding];
        
        // 提交到GPU并呈现
        [commandBuffer presentDrawable:drawable];
        [commandBuffer commit];
        
        NSLog(@"[MoltenVKBridge] Frame presented successfully");
    } else {
        NSLog(@"[MoltenVKBridge] Failed to create render encoder for present");
    }
}

- (void)resizeToWidth:(CGFloat)width height:(CGFloat)height {
    if (!_isInitialized || !_metalLayer) {
        NSLog(@"[MoltenVKBridge] Cannot resize - not initialized");
        return;
    }
    
    // 确保在主线程执行
    if ([NSThread isMainThread]) {
        [self performResizeToWidth:width height:height];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self performResizeToWidth:width height:height];
        });
    }
}

- (void)performResizeToWidth:(CGFloat)width height:(CGFloat)height {
    CGSize newSize = CGSizeMake(width, height);
    _metalLayer.drawableSize = newSize;
    
    // 如果有父视图，也更新它的大小
    if (_metalLayer.superlayer) {
        _metalLayer.frame = CGRectMake(0, 0, width, height);
    }
    
    NSLog(@"[MoltenVKBridge] Resized to %.0fx%.0f", width, height);
}

#pragma mark - 调试和诊断 - GraphicsEnhancedExecutionEngine需要的方法

#pragma mark - 调试和诊断

- (NSDictionary *)getSystemInfo {
    return @{
        @"bridge_initialized": @(_isInitialized),
        @"bridge_ready": @(_isReady),
        @"metal_device_name": _metalDevice.name ?: @"Unknown",
        @"metal_device_supports_compute": @([_metalDevice supportsFamily:MTLGPUFamilyMac2]),
        @"command_queue_label": _metalCommandQueue.label ?: @"Default",
        @"metal_layer_frame": _metalLayer ? NSStringFromCGRect(_metalLayer.frame) : @"nil",
        @"metal_layer_drawable_size": _metalLayer ? NSStringFromCGSize(_metalLayer.drawableSize) : @"nil",
        @"pixel_format": _metalLayer ? @(_metalLayer.pixelFormat) : @"nil",
        @"active_objects": @(self.activeObjectCount),
        @"total_created": @(_totalObjectsCreated),
        @"total_destroyed": @(_totalObjectsDestroyed)
    };
}

- (NSDictionary *)getVulkanInfo {
    [_objectsLock lock];
    NSUInteger objectCount = _vulkanObjects.count;
    [_objectsLock unlock];
    
    return @{
        @"objects_count": @(objectCount),
        @"next_object_id": @(_objectIdCounter),
        @"is_initialized": @(_isInitialized),
        @"is_ready": @(_isReady),
        @"total_created": @(_totalObjectsCreated),
        @"total_destroyed": @(_totalObjectsDestroyed),
        @"active_objects": @(objectCount)
    };
}

- (NSDictionary *)getMetalInfo {
    if (!_metalDevice) {
        return @{
            @"device_name": @"Not Available",
            @"device_supports_compute": @NO,
            @"command_queue_label": @"Not Available",
            @"layer_size": @"Not Available",
            @"pixel_format": @"Not Available"
        };
    }
    
    return @{
        @"device_name": _metalDevice.name ?: @"Unknown",
        @"device_supports_compute": @([_metalDevice supportsFamily:MTLGPUFamilyMac2]),
        @"command_queue_label": _metalCommandQueue.label ?: @"Default",
        @"layer_size": _metalLayer ? NSStringFromCGSize(_metalLayer.drawableSize) : @"Not Available",
        @"pixel_format": _metalLayer ? @(_metalLayer.pixelFormat) : @0,
        @"layer_framebuffer_only": _metalLayer ? @(_metalLayer.framebufferOnly) : @NO
        // 移除 displaySyncEnabled - 不是CAMetalLayer的有效属性
    };
}

- (NSDictionary *)getStatistics {
    [_objectsLock lock];
    NSUInteger activeObjects = _vulkanObjects.count;
    [_objectsLock unlock];
    
    return @{
        @"active_vulkan_objects": @(activeObjects),
        @"total_objects_created": @(_totalObjectsCreated),
        @"total_objects_destroyed": @(_totalObjectsDestroyed),
        @"objects_leaked": @(_totalObjectsCreated - _totalObjectsDestroyed - activeObjects),
        @"performance_markers": @(_performanceMarkers.count),
        @"last_error": _lastError ?: @""
    };
}

- (void)dumpVulkanObjects {
    NSLog(@"[MoltenVKBridge] ===== Vulkan Objects Dump =====");
    
    [_objectsLock lock];
    
    for (NSNumber *objectId in _vulkanObjects) {
        NSValue *value = _vulkanObjects[objectId];
        if ([value isKindOfClass:[NSValue class]]) {
            void *ptr = [value pointerValue];
            if (ptr && [self isValidMockStructure:ptr]) {
                NSLog(@"[MoltenVKBridge] Object ID: %@ -> Valid Mock Structure", objectId);
            } else {
                NSLog(@"[MoltenVKBridge] Object ID: %@ -> Invalid/Dictionary: %@", objectId, value);
            }
        } else {
            NSLog(@"[MoltenVKBridge] Object ID: %@ -> Dictionary: %@", objectId, value);
        }
    }
    
    [_objectsLock unlock];
    
    NSLog(@"[MoltenVKBridge] Total objects: %lu", (unsigned long)self.activeObjectCount);
    NSLog(@"[MoltenVKBridge] Objects created: %lu", (unsigned long)_totalObjectsCreated);
    NSLog(@"[MoltenVKBridge] Objects destroyed: %lu", (unsigned long)_totalObjectsDestroyed);
    NSLog(@"[MoltenVKBridge] ==============================");
}

- (void)logMemoryUsage {
    NSLog(@"[MoltenVKBridge] ===== Memory Usage =====");
    NSLog(@"[MoltenVKBridge] Active Vulkan objects: %lu", (unsigned long)self.activeObjectCount);
    NSLog(@"[MoltenVKBridge] Estimated memory usage: %lu bytes",
          (unsigned long)(self.activeObjectCount * 64)); // 大概估算
    NSLog(@"[MoltenVKBridge] ========================");
}

- (NSString *)getLastError {
    return _lastError ?: @"";
}

#pragma mark - 性能监控

- (void)beginPerformanceMarker:(NSString *)markerName {
    PerformanceMarker marker;
    marker.markerName = markerName;
    marker.startTime = [[NSDate date] timeIntervalSince1970];
    marker.endTime = 0;
    marker.isActive = YES;
    
    NSValue *markerValue = [NSValue valueWithBytes:&marker objCType:@encode(PerformanceMarker)];
    [_performanceMarkers addObject:markerValue];
    
    NSLog(@"[MoltenVKBridge] Performance marker started: %@", markerName);
}

- (void)endPerformanceMarker {
    if (_performanceMarkers.count == 0) {
        return;
    }
    
    NSValue *lastMarkerValue = [_performanceMarkers lastObject];
    PerformanceMarker marker;
    [lastMarkerValue getValue:&marker];
    
    if (marker.isActive) {
        marker.endTime = [[NSDate date] timeIntervalSince1970];
        marker.isActive = NO;
        
        NSValue *updatedMarkerValue = [NSValue valueWithBytes:&marker objCType:@encode(PerformanceMarker)];
        [_performanceMarkers replaceObjectAtIndex:_performanceMarkers.count - 1 withObject:updatedMarkerValue];
        
        NSTimeInterval duration = marker.endTime - marker.startTime;
        NSLog(@"[MoltenVKBridge] Performance marker ended: %@ (%.3fs)", marker.markerName, duration);
    }
}

- (NSDictionary *)getPerformanceMetrics {
    NSMutableArray *metrics = [NSMutableArray array];
    NSTimeInterval totalTime = 0;
    
    for (NSValue *markerValue in _performanceMarkers) {
        PerformanceMarker marker;
        [markerValue getValue:&marker];
        
        if (!marker.isActive && marker.endTime > 0) {
            NSTimeInterval duration = marker.endTime - marker.startTime;
            totalTime += duration;
            
            [metrics addObject:@{
                @"name": marker.markerName,
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
}

#pragma mark - 内存管理

- (void)dealloc {
    NSLog(@"[MoltenVKBridge] Deallocating MoltenVK bridge...");
    [self cleanup];
}

@end

#pragma mark - DirectXToVulkanTranslator实现

@implementation DirectXToVulkanTranslator

+ (instancetype)translatorWithBridge:(MoltenVKBridge *)bridge {
    DirectXToVulkanTranslator *translator = [[DirectXToVulkanTranslator alloc] init];
    translator.bridge = bridge;
    return translator;
}

- (BOOL)translateDirectXCall:(NSString *)functionName parameters:(NSArray *)parameters {
    NSLog(@"[DirectXToVulkanTranslator] Translating DirectX call: %@ with %lu parameters",
          functionName, (unsigned long)parameters.count);
    
    // D3D11设备创建函数
    if ([functionName isEqualToString:@"D3D11CreateDevice"] ||
        [functionName isEqualToString:@"D3D11CreateDeviceAndSwapChain"]) {
        return [self handleDeviceCreation:functionName parameters:parameters];
    }
    
    // 绘制函数
    if ([functionName hasPrefix:@"Draw"] || [functionName hasSuffix:@"Draw"]) {
        return [self handleDrawCall:functionName parameters:parameters];
    }
    
    // 资源创建函数
    if ([functionName containsString:@"Create"]) {
        return [self handleResourceCreation:functionName parameters:parameters];
    }
    
    // 状态设置函数
    if ([functionName hasPrefix:@"Set"] || [functionName containsString:@"State"]) {
        return [self handleStateChange:functionName parameters:parameters];
    }
    
    // 通用D3D11函数
    if ([functionName hasPrefix:@"D3D11"]) {
        NSLog(@"[DirectXToVulkanTranslator] Generic D3D11 function: %@", functionName);
        return YES;
    }
    
    NSLog(@"[DirectXToVulkanTranslator] Unsupported DirectX function: %@", functionName);
    return NO;
}

- (BOOL)handleDeviceCreation:(NSString *)functionName parameters:(NSArray *)parameters {
    NSLog(@"[DirectXToVulkanTranslator] Handling device creation: %@", functionName);
    
    if (!self.bridge || !self.bridge.isReady) {
        NSLog(@"[DirectXToVulkanTranslator] Bridge not ready for device creation");
        return NO;
    }
    
    // 模拟D3D11设备创建成功
    return YES;
}

- (BOOL)handleDrawCall:(NSString *)functionName parameters:(NSArray *)parameters {
    NSLog(@"[DirectXToVulkanTranslator] Handling draw call: %@", functionName);
    
    // 转换绘制调用到Metal
    return YES;
}

- (BOOL)handleResourceCreation:(NSString *)functionName parameters:(NSArray *)parameters {
    NSLog(@"[DirectXToVulkanTranslator] Handling resource creation: %@", functionName);
    
    // 转换资源创建到Metal
    return YES;
}

- (BOOL)handleStateChange:(NSString *)functionName parameters:(NSArray *)parameters {
    NSLog(@"[DirectXToVulkanTranslator] Handling state change: %@", functionName);
    
    // 转换状态变更到Metal
    return YES;
}

- (VkResult)translateDrawCall:(NSString *)drawType
                   parameters:(NSDictionary *)params
                commandBuffer:(VkCommandBuffer)commandBuffer {
    NSLog(@"[DirectXToVulkanTranslator] Translating draw call: %@", drawType);
    
    if (!self.bridge || ![self.bridge isValidCommandBuffer:commandBuffer]) {
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    // 这里可以添加具体的绘制转换逻辑
    return VK_SUCCESS;
}

- (VkResult)translateResourceCreation:(NSString *)resourceType parameters:(NSDictionary *)params {
    NSLog(@"[DirectXToVulkanTranslator] Translating resource creation: %@", resourceType);
    
    if (!self.bridge || !self.bridge.isReady) {
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    // 这里可以添加具体的资源创建转换逻辑
    return VK_SUCCESS;
}

- (NSData *)translateShader:(NSString *)hlslCode shaderType:(NSString *)type {
    NSLog(@"[DirectXToVulkanTranslator] Translating shader: %@ (%lu chars)", type, (unsigned long)hlslCode.length);
    
    // 这里应该实现HLSL到SPIRV到MSL的转换
    // 目前返回空数据，表示需要实现
    return nil;
}

@end
