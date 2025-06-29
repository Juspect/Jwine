#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <QuartzCore/CAMetalLayer.h>

NS_ASSUME_NONNULL_BEGIN

// 前向声明
@class MoltenVKBridge;
@class DirectXToVulkanTranslator;

// Vulkan基础结构体模拟
typedef struct VkInstance_T* VkInstance;
typedef struct VkDevice_T* VkDevice;
typedef struct VkCommandBuffer_T* VkCommandBuffer;
typedef struct VkRenderPass_T* VkRenderPass;
typedef struct VkPipeline_T* VkPipeline;
typedef uint32_t VkBool32;
typedef uint64_t VkDeviceAddress;

// DirectX函数类型定义
typedef enum DirectXFunctionType {
    DirectXFunctionTypeDevice,
    DirectXFunctionTypeContext,
    DirectXFunctionTypeDraw,
    DirectXFunctionTypeResource,
    DirectXFunctionTypeShader,
    DirectXFunctionTypeState
} DirectXFunctionType;

// 性能标记结构
typedef struct PerformanceMarker {
    double startTime;
    double endTime;
    BOOL isActive;
    char name[64];
} PerformanceMarker;

// 错误回调类型
typedef void(^MoltenVKErrorHandler)(NSError *error);
typedef void(^MoltenVKWarningHandler)(NSString *warning);

#pragma mark - 委托协议

@protocol MoltenVKBridgeDelegate <NSObject>
@optional
- (void)moltenVKBridge:(MoltenVKBridge *)bridge didEncounterError:(NSError *)error;
- (void)moltenVKBridge:(MoltenVKBridge *)bridge didReceiveWarning:(NSString *)warning;
- (void)moltenVKBridge:(MoltenVKBridge *)bridge didCompleteFrame:(NSTimeInterval)frameTime;
- (void)moltenVKBridge:(MoltenVKBridge *)bridge didUpdatePerformanceMetrics:(NSDictionary *)metrics;
@end

#pragma mark - MoltenVKBridge主类

@interface MoltenVKBridge : NSObject

// 核心属性
@property (nonatomic, readonly) id<MTLDevice> metalDevice;
@property (nonatomic, readonly) id<MTLCommandQueue> commandQueue;
@property (nonatomic, readonly) CAMetalLayer *metalLayer;
@property (nonatomic, readonly) BOOL isInitialized;

// Vulkan模拟对象
@property (nonatomic, readonly) VkInstance vulkanInstance;
@property (nonatomic, readonly) VkDevice vulkanDevice;

// 回调处理
@property (nonatomic, copy, nullable) MoltenVKErrorHandler errorHandler;
@property (nonatomic, copy, nullable) MoltenVKWarningHandler warningHandler;

// 翻译器
@property (nonatomic, strong, readonly) DirectXToVulkanTranslator *translator;

// 委托
@property (nonatomic, weak, nullable) id<MoltenVKBridgeDelegate> delegate;

// 单例模式
+ (instancetype)sharedBridge;

// 初始化方法
- (BOOL)initializeBridge;
- (BOOL)initializeBridgeWithPreferredDevice:(nullable id<MTLDevice>)preferredDevice;
- (BOOL)initializeWithView:(UIView *)view;
- (void)cleanup;

// Metal层管理
- (BOOL)setupMetalLayerWithView:(UIView *)view;
- (void)resizeMetalLayer:(CGSize)newSize;
- (void)resizeToWidth:(CGFloat)width height:(CGFloat)height;

// Vulkan实例创建 (模拟)
- (VkInstance)createVulkanInstance;
- (VkDevice)createVulkanDevice;
- (void)destroyVulkanInstance:(VkInstance)instance;
- (void)destroyVulkanDevice:(VkDevice)device;

// 渲染管道
- (VkRenderPass)createRenderPass;
- (VkPipeline)createGraphicsPipeline;
- (VkCommandBuffer)createCommandBuffer;

// 渲染控制
- (BOOL)beginFrame;
- (BOOL)endFrame;
- (BOOL)presentFrame;

// DirectX转换支持
- (BOOL)interceptDirectXCall:(NSString *)functionName parameters:(NSArray *)parameters;
- (BOOL)translateAndExecuteDirectXCall:(NSString *)functionName parameters:(NSArray *)parameters;

// 性能监控
- (void)beginPerformanceMarker:(NSString *)name;
- (void)endPerformanceMarker:(NSString *)name;
- (NSDictionary *)getPerformanceMetrics;

// 调试支持
- (NSString *)getSystemInfo;
- (NSDictionary *)getVulkanInfo;
- (NSDictionary *)getMetalInfo;
- (void)dumpVulkanState;
- (void)enableDebugMode:(BOOL)enabled;

@end

#pragma mark - DirectXToVulkanTranslator类

@interface DirectXToVulkanTranslator : NSObject

@property (nonatomic, weak) MoltenVKBridge *bridge;

// 初始化方法
+ (instancetype)translatorWithBridge:(MoltenVKBridge *)bridge;

// 主要翻译方法 - 修复方法签名
- (BOOL)translateDirectXCall:(NSString *)functionName parameters:(NSArray *)parameters;

// 特定函数类型处理
- (BOOL)handleDeviceCreation:(NSString *)functionName parameters:(NSArray *)parameters;
- (BOOL)handleDrawCall:(NSString *)functionName parameters:(NSArray *)parameters;
- (BOOL)handleResourceCreation:(NSString *)functionName parameters:(NSArray *)parameters;
- (BOOL)handleShaderOperation:(NSString *)functionName parameters:(NSArray *)parameters;
- (BOOL)handleStateChange:(NSString *)functionName parameters:(NSArray *)parameters;

// 函数类型检测
- (DirectXFunctionType)detectFunctionType:(NSString *)functionName;

// 参数转换
- (NSArray *)convertDirectXParameters:(NSArray *)dxParameters toVulkanForFunction:(NSString *)functionName;

// 调试支持
- (NSString *)getTranslationLog;
- (void)clearTranslationLog;

@end

#pragma mark - 错误代码

// 错误域字符串常量
FOUNDATION_EXPORT NSString * const MoltenVKBridgeErrorDomainInitialization;
FOUNDATION_EXPORT NSString * const MoltenVKBridgeErrorDomainDeviceCreation;
FOUNDATION_EXPORT NSString * const MoltenVKBridgeErrorDomainCommandExecution;
FOUNDATION_EXPORT NSString * const MoltenVKBridgeErrorDomainTranslation;
FOUNDATION_EXPORT NSString * const MoltenVKBridgeErrorDomainRendering;

// 便利函数
FOUNDATION_EXPORT NSError *MoltenVKBridgeError(NSString *domain, NSInteger code, NSString *description);

NS_ASSUME_NONNULL_END
