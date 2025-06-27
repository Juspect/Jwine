#import "WineGraphicsAdapter.h"

@interface WineGraphicsAdapter()
@property (nonatomic, strong) CALayer *renderLayer;
@property (nonatomic, assign) CGSize virtualScreenSize;
@property (nonatomic, strong) id<MTLDevice> metalDevice;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@end

@implementation WineGraphicsAdapter

- (instancetype)initWithDisplayView:(UIView *)displayView {
    self = [super init];
    if (self) {
        _displayView = displayView;
        _virtualScreenSize = CGSizeMake(800, 600); // 默认分辨率
        [self setupMetal];
    }
    return self;
}

- (void)setupMetal {
    self.metalDevice = MTLCreateSystemDefaultDevice();
    if (self.metalDevice) {
        self.commandQueue = [self.metalDevice newCommandQueue];
        NSLog(@"Metal device initialized: %@", self.metalDevice.name);
    } else {
        NSLog(@"Failed to initialize Metal device");
    }
}

- (BOOL)initializeGraphicsContext {
    if (!self.displayView) {
        NSLog(@"Display view not set");
        return NO;
    }
    
    // 创建渲染层
    self.renderLayer = [CALayer layer];
    self.renderLayer.frame = self.displayView.bounds;
    self.renderLayer.backgroundColor = [UIColor blackColor].CGColor;
    [self.displayView.layer addSublayer:self.renderLayer];
    
    // 设置触摸处理
    self.displayView.userInteractionEnabled = YES;
    
    NSLog(@"Graphics context initialized with size: %.0fx%.0f",
          self.virtualScreenSize.width, self.virtualScreenSize.height);
    
    return YES;
}

- (void)handleWineGraphicsOutput:(NSData *)frameData size:(CGSize)size {
    // 这里处理来自Wine的图形输出
    // 暂时显示一个占位符
    dispatch_async(dispatch_get_main_queue(), ^{
        if (frameData && frameData.length > 0) {
            // TODO: 解析Wine的图形数据并渲染到Metal
            // 目前只是更新背景色表示有数据
            self.renderLayer.backgroundColor = [UIColor darkGrayColor].CGColor;
            
            // 模拟渲染内容
            [self renderPlaceholderContent];
        }
    });
}

- (void)renderPlaceholderContent {
    // 创建一个简单的渲染内容作为占位符
    CATextLayer *textLayer = [CATextLayer layer];
    textLayer.string = @"Wine Output\n(Graphics rendering in development)";
    textLayer.fontSize = 16;
    textLayer.foregroundColor = [UIColor whiteColor].CGColor;
    textLayer.backgroundColor = [UIColor clearColor].CGColor;
    textLayer.alignmentMode = kCAAlignmentCenter;
    textLayer.frame = CGRectMake(0, 0, self.renderLayer.bounds.size.width, 100);
    textLayer.position = CGPointMake(self.renderLayer.bounds.size.width/2,
                                   self.renderLayer.bounds.size.height/2);
    
    [self.renderLayer addSublayer:textLayer];
}

- (void)forwardTouchEvent:(UITouch *)touch withType:(UITouchPhase)phase {
    CGPoint location = [touch locationInView:self.displayView];
    
    // 将iOS触摸坐标转换为Wine坐标系
    CGFloat scaleX = self.virtualScreenSize.width / self.displayView.bounds.size.width;
    CGFloat scaleY = self.virtualScreenSize.height / self.displayView.bounds.size.height;
    
    CGPoint wineCoordinate = CGPointMake(location.x * scaleX, location.y * scaleY);
    
    NSLog(@"Touch event: phase=%ld, iOS=(%.1f,%.1f), Wine=(%.1f,%.1f)",
          (long)phase, location.x, location.y, wineCoordinate.x, wineCoordinate.y);
    
    // TODO: 将触摸事件发送给Wine
}

- (void)forwardKeyboardInput:(NSString *)text {
    NSLog(@"Keyboard input: %@", text);
    // TODO: 将键盘输入发送给Wine
}

- (void)setVirtualScreenSize:(CGSize)size {
    _virtualScreenSize = size;
    NSLog(@"Virtual screen size set to: %.0fx%.0f", size.width, size.height);
}

@end
