// MoltenVKBridge.h - 修复版本
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
typedef uint32_t VkResult;
typedef uint32_t VkFormat;

// Vulkan常量
#define VK_SUCCESS 0
#define VK_ERROR_INITIALIZATION_FAILED -3
#define VK_ERROR_OUT_OF_DEVICE_MEMORY -6
#define VK_FORMAT_B8G8R8A8_UNORM 44

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

@end

// MoltenVK到Metal桥接主类
@interface MoltenVKBridge : NSObject

// 单例访问
+ (instancetype)sharedBridge;

// 初始化和清理
- (BOOL)initializeWithView:(UIView * _Nonnull)containerView;
- (void)cleanup;

// Vulkan实例和设备管理
- (VkResult)createVulkanInstance:(VkInstance * _Nonnull)instance;
- (VkResult)createVulkanDevice:(VkDevice * _Nonnull)device
                  fromInstance:(VkInstance _Nonnull)instance;

// Vulkan表面和交换链
- (VkResult)createVulkanSurface:(VkSurfaceKHR * _Nonnull)surface
                       instance:(VkInstance _Nonnull)instance
                           view:(UIView * _Nonnull)view;
- (VkResult)createSwapchain:(VkSwapchainKHR * _Nonnull)swapchain
                     device:(VkDevice _Nonnull)device
                    surface:(VkSurfaceKHR _Nonnull)surface
                      width:(uint32_t)width
                     height:(uint32_t)height;

// 图形管道
- (VkResult)createRenderPass:(VkRenderPass * _Nonnull)renderPass
                      device:(VkDevice _Nonnull)device
                      format:(VkFormat)format;
- (VkResult)createGraphicsPipeline:(VkPipeline * _Nonnull)pipeline
                            device:(VkDevice _Nonnull)device
                        renderPass:(VkRenderPass _Nonnull)renderPass;

// 命令缓冲区管理
- (VkResult)createCommandBuffer:(VkCommandBuffer * _Nonnull)commandBuffer
                         device:(VkDevice _Nonnull)device;
- (VkResult)beginCommandBuffer:(VkCommandBuffer _Nonnull)commandBuffer;
- (VkResult)endCommandBuffer:(VkCommandBuffer _Nonnull)commandBuffer;
- (VkResult)submitCommandBuffer:(VkCommandBuffer _Nonnull)commandBuffer
                         device:(VkDevice _Nonnull)device;

// 渲染操作
- (VkResult)beginRenderPass:(VkCommandBuffer _Nonnull)commandBuffer
                 renderPass:(VkRenderPass _Nonnull)renderPass
                      width:(uint32_t)width
                     height:(uint32_t)height;
- (void)endRenderPass:(VkCommandBuffer _Nonnull)commandBuffer;

// Wine DirectX桥接方法
- (BOOL)handleDirectXCall:(NSString * _Nonnull)functionName
               parameters:(NSArray * _Nonnull)parameters
            deviceContext:(void * _Nullable)deviceContext;

// Metal特定操作
- (void)presentFrame;
- (void)resizeToWidth:(CGFloat)width height:(CGFloat)height;

// 调试和监控
- (NSDictionary * _Nonnull)getVulkanInfo;
- (NSDictionary * _Nonnull)getMetalInfo;
- (void)dumpPipelineStates;

@end

NS_ASSUME_NONNULL_END
