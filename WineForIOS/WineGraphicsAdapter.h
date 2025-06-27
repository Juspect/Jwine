#import <UIKit/UIKit.h>
#import <Metal/Metal.h>

NS_ASSUME_NONNULL_BEGIN

@interface WineGraphicsAdapter : NSObject

@property (nonatomic, weak) UIView *displayView;
@property (nonatomic, readonly) CGSize virtualScreenSize;

- (instancetype)initWithDisplayView:(UIView *)displayView;
- (BOOL)initializeGraphicsContext;
- (void)handleWineGraphicsOutput:(NSData *)frameData size:(CGSize)size;
- (void)forwardTouchEvent:(UITouch *)touch withType:(UITouchPhase)phase;
- (void)forwardKeyboardInput:(NSString *)text;
- (void)setVirtualScreenSize:(CGSize)size;

@end

NS_ASSUME_NONNULL_END
