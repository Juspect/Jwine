// MoltenVKBridge.h - 完整修复版本
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <QuartzCore/QuartzCore.h>

NS_ASSUME_NONNULL_BEGIN

// Vulkan类型前向声明
typedef void* VkInstance;
typedef void* VkDevice;
typedef void* VkSurfaceKHR;
typedef void* VkSwapchainKHR;
typedef void* VkCommandBuffer;
typedef void* VkRenderPass;
typedef void* VkPipeline;
typedef void* VkFramebuffer;
typedef void* VkBuffer;
typedef void* VkImage;
typedef void* VkImageView;
typedef void* VkSampler;
typedef void* VkDescriptorSet;
typedef void* VkDescriptorSetLayout;
typedef void* VkPipelineLayout;
typedef void* VkShaderModule;
typedef uint32_t VkResult;
typedef uint32_t VkFormat;
typedef uint32_t VkFlags;
typedef uint32_t VkBool32;

// Vulkan常量
#define VK_SUCCESS 0
#define VK_ERROR_INITIALIZATION_FAILED -3
#define VK_ERROR_OUT_OF_DEVICE_MEMORY -6
#define VK_ERROR_DEVICE_LOST -4
#define VK_ERROR_MEMORY_MAP_FAILED -5
#define VK_FORMAT_B8G8R8A8_UNORM 44
#define VK_FORMAT_R8G8B8A8_UNORM 37
#define VK_TRUE 1
#define VK_FALSE 0

// 前向声明
@class MoltenVKBridge;

// Wine DirectX到Vulkan转换辅助类
@interface DirectXToVulkanTranslator : NSObject

@property (nonatomic, weak, nullable) MoltenVKBridge *bridge;

+ (instancetype)translatorWithBridge:(MoltenVKBridge * _Nonnull)bridge;

// 修复的方法签名 - 确保与调用代码匹配
- (BOOL)translateDirectXCall:(NSString * _Nonnull)functionName
                  parameters:(NSArray * _Nonnull)parameters;

// DirectX Draw调用转换
- (VkResult)translateDrawCall:(NSString * _Nonnull)drawType
                   parameters:(NSDictionary * _Nonnull)params
                commandBuffer:(VkCommandBuffer _Nonnull)commandBuffer;

// DirectX资源管理转换
- (VkResult)translateResourceCreation:(NSString * _Nonnull)resourceType
                           parameters:(NSDictionary * _Nonnull)params;

// 着色器转换 (HLSL → SPIRV → MSL)
- (NSData * _Nullable)translateShader:(NSString * _Nonnull)hlslCode
                           shaderType:(NSString * _Nonnull)type;

// DirectX状态管理
- (VkResult)translateRenderState:(NSString * _Nonnull)stateName
                           value:(id _Nonnull)value
                   commandBuffer:(VkCommandBuffer _Nonnull)commandBuffer;

// DirectX纹理和缓冲区转换
- (VkResult)translateTextureCreation:(NSDictionary * _Nonnull)textureParams
                            outImage:(VkImage * _Nullable)outImage
                         outImageView:(VkImageView * _Nullable)outImageView;

- (VkResult)translateBufferCreation:(NSDictionary * _Nonnull)bufferParams
                          outBuffer:(VkBuffer * _Nullable)outBuffer;

@end

// MoltenVK到Metal桥接主类
@interface MoltenVKBridge : NSObject

// 核心属性
@property (nonatomic, readonly) BOOL isInitialized;
@property (nonatomic, readonly) BOOL isReady;
@property (nonatomic, strong, readonly, nullable) id<MTLDevice> metalDevice;
@property (nonatomic, strong, readonly, nullable) id<MTLCommandQueue> metalCommandQueue;
@property (nonatomic, strong, readonly, nullable) CAMetalLayer *metalLayer;
@property (nonatomic, strong, readonly, nullable) DirectXToVulkanTranslator *dxTranslator;

// 统计信息
@property (nonatomic, readonly) NSUInteger activeObjectCount;
@property (nonatomic, readonly) NSUInteger totalObjectsCreated;
@property (nonatomic, readonly) NSUInteger totalObjectsDestroyed;

// 单例访问
+ (instancetype)sharedBridge;

// 初始化和清理
- (BOOL)initializeWithView:(UIView * _Nonnull)containerView;
- (void)cleanup;
- (void)reset;

// 安全性检查方法
- (BOOL)isValidCommandBuffer:(VkCommandBuffer _Nonnull)commandBuffer;
- (BOOL)isValidVulkanObject:(void * _Nonnull)vulkanObject;
- (BOOL)canCreateObjects;

// Vulkan实例和设备管理
- (VkResult)createVulkanInstance:(VkInstance * _Nonnull)instance;
- (VkResult)createVulkanDevice:(VkDevice * _Nonnull)device
                  fromInstance:(VkInstance _Nonnull)instance;
- (void)destroyVulkanInstance:(VkInstance _Nonnull)instance;
- (void)destroyVulkanDevice:(VkDevice _Nonnull)device;

// Vulkan表面和交换链
- (VkResult)createVulkanSurface:(VkSurfaceKHR * _Nonnull)surface
                       instance:(VkInstance _Nonnull)instance
                           view:(UIView * _Nonnull)view;
- (VkResult)createSwapchain:(VkSwapchainKHR * _Nonnull)swapchain
                     device:(VkDevice _Nonnull)device
                    surface:(VkSurfaceKHR _Nonnull)surface
                      width:(uint32_t)width
                     height:(uint32_t)height;
- (void)destroyVulkanSurface:(VkSurfaceKHR _Nonnull)surface;
- (void)destroySwapchain:(VkSwapchainKHR _Nonnull)swapchain;

// 图形管道
- (VkResult)createRenderPass:(VkRenderPass * _Nonnull)renderPass
                      device:(VkDevice _Nonnull)device
                      format:(VkFormat)format;
- (VkResult)createGraphicsPipeline:(VkPipeline * _Nonnull)pipeline
                            device:(VkDevice _Nonnull)device
                        renderPass:(VkRenderPass _Nonnull)renderPass;
- (VkResult)createFramebuffer:(VkFramebuffer * _Nonnull)framebuffer
                       device:(VkDevice _Nonnull)device
                   renderPass:(VkRenderPass _Nonnull)renderPass
                        width:(uint32_t)width
                       height:(uint32_t)height;
- (void)destroyRenderPass:(VkRenderPass _Nonnull)renderPass;
- (void)destroyGraphicsPipeline:(VkPipeline _Nonnull)pipeline;
- (void)destroyFramebuffer:(VkFramebuffer _Nonnull)framebuffer;

// 着色器管理
- (VkResult)createShaderModule:(VkShaderModule * _Nonnull)shaderModule
                        device:(VkDevice _Nonnull)device
                    spirvCode:(NSData * _Nonnull)spirvCode;
- (void)destroyShaderModule:(VkShaderModule _Nonnull)shaderModule;

// 命令缓冲区操作
- (VkResult)createCommandBuffer:(VkCommandBuffer * _Nonnull)commandBuffer
                         device:(VkDevice _Nonnull)device;
- (VkResult)beginCommandBuffer:(VkCommandBuffer _Nonnull)commandBuffer;
- (VkResult)endCommandBuffer:(VkCommandBuffer _Nonnull)commandBuffer;
- (VkResult)submitCommandBuffer:(VkCommandBuffer _Nonnull)commandBuffer
                         device:(VkDevice _Nonnull)device;
- (VkResult)resetCommandBuffer:(VkCommandBuffer _Nonnull)commandBuffer;
- (void)destroyCommandBuffer:(VkCommandBuffer _Nonnull)commandBuffer;

// 渲染操作
- (VkResult)beginRenderPass:(VkCommandBuffer _Nonnull)commandBuffer
                 renderPass:(VkRenderPass _Nonnull)renderPass
                 framebuffer:(VkFramebuffer _Nonnull)framebuffer
                      width:(uint32_t)width
                     height:(uint32_t)height;
- (void)endRenderPass:(VkCommandBuffer _Nonnull)commandBuffer;

// 绘制命令
- (VkResult)cmdDraw:(VkCommandBuffer _Nonnull)commandBuffer
        vertexCount:(uint32_t)vertexCount
      instanceCount:(uint32_t)instanceCount
        firstVertex:(uint32_t)firstVertex
       firstInstance:(uint32_t)firstInstance;
- (VkResult)cmdDrawIndexed:(VkCommandBuffer _Nonnull)commandBuffer
                indexCount:(uint32_t)indexCount
             instanceCount:(uint32_t)instanceCount
                firstIndex:(uint32_t)firstIndex
             vertexOffset:(int32_t)vertexOffset
              firstInstance:(uint32_t)firstInstance;

// 缓冲区和内存管理
- (VkResult)createBuffer:(VkBuffer * _Nonnull)buffer
                  device:(VkDevice _Nonnull)device
                    size:(uint64_t)size
                   usage:(VkFlags)usage;
- (VkResult)createImage:(VkImage * _Nonnull)image
                 device:(VkDevice _Nonnull)device
                  width:(uint32_t)width
                 height:(uint32_t)height
                 format:(VkFormat)format
                  usage:(VkFlags)usage;
- (VkResult)createImageView:(VkImageView * _Nonnull)imageView
                     device:(VkDevice _Nonnull)device
                      image:(VkImage _Nonnull)image
                     format:(VkFormat)format;
- (void)destroyBuffer:(VkBuffer _Nonnull)buffer;
- (void)destroyImage:(VkImage _Nonnull)image;
- (void)destroyImageView:(VkImageView _Nonnull)imageView;

// 同步操作
- (VkResult)deviceWaitIdle:(VkDevice _Nonnull)device;
- (VkResult)queueWaitIdle;

// Wine DirectX桥接
- (BOOL)handleDirectXCall:(NSString * _Nonnull)functionName
               parameters:(NSArray * _Nonnull)parameters
               deviceContext:(void * _Nullable)deviceContext;

// Wine图形上下文管理
- (void *)createWineGraphicsContext:(CGSize)size;
- (BOOL)updateWineGraphicsContext:(void * _Nonnull)context
                             size:(CGSize)size;
- (void)destroyWineGraphicsContext:(void * _Nonnull)context;

// 高级图形功能
- (VkResult)presentFrame:(VkSwapchainKHR _Nonnull)swapchain;
- (VkResult)acquireNextImage:(VkSwapchainKHR _Nonnull)swapchain
                  imageIndex:(uint32_t * _Nonnull)imageIndex;

// Metal特定操作 - 添加GraphicsEnhancedExecutionEngine需要的方法
- (void)presentFrame;  // 无参数版本，用于简单的帧呈现
- (void)resizeToWidth:(CGFloat)width height:(CGFloat)height;  // 调整大小

// 调试和诊断
- (NSDictionary * _Nonnull)getSystemInfo;
- (NSDictionary * _Nonnull)getStatistics;
- (NSDictionary * _Nonnull)getVulkanInfo;  // GraphicsEnhancedExecutionEngine需要
- (NSDictionary * _Nonnull)getMetalInfo;   // GraphicsEnhancedExecutionEngine需要
- (void)dumpVulkanObjects;
- (void)logMemoryUsage;
- (NSString * _Nonnull)getLastError;

// 性能监控
- (void)beginPerformanceMarker:(NSString * _Nonnull)markerName;
- (void)endPerformanceMarker;
- (NSDictionary * _Nonnull)getPerformanceMetrics;

@end

NS_ASSUME_NONNULL_END
