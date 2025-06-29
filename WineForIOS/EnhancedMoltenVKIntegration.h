// EnhancedMoltenVKIntegration.h - 完整MoltenVK集成
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import "MoltenVKBridge.h"

NS_ASSUME_NONNULL_BEGIN

// DirectX到Vulkan指令映射
typedef struct DXVKCommandMapping {
    NSString *dxFunction;
    NSString *vulkanFunction;
    NSArray *parameterMapping;
} DXVKCommandMapping;

@interface EnhancedMoltenVKIntegration : NSObject

@property (nonatomic, strong, readonly) MoltenVKBridge *bridge;
@property (nonatomic, strong, readonly) id<MTLDevice> metalDevice;
@property (nonatomic, strong, readonly) id<MTLCommandQueue> commandQueue;
@property (nonatomic, assign, readonly) BOOL isRenderingActive;

+ (instancetype)sharedIntegration;

// 初始化和配置
- (BOOL)initializeWithOutputView:(UIView *)outputView;
- (void)shutdown;

// DirectX API拦截和转换
- (BOOL)interceptDirectXCall:(NSString *)functionName
                  parameters:(NSDictionary *)params
                 returnValue:(void **)returnValue;

// 实时渲染管理
- (void)beginFrame;
- (void)endFrame;
- (void)presentFrame;

// 渲染状态管理
- (void)createRenderTarget:(CGSize)size format:(MTLPixelFormat)format;
- (void)setViewport:(CGRect)viewport;
- (void)clearRenderTarget:(UIColor *)color;

// 着色器管理
- (id<MTLRenderPipelineState>)createPipelineWithVertexShader:(NSString *)vertexSource
                                              fragmentShader:(NSString *)fragmentSource;


NS_ASSUME_NONNULL_END

@end

