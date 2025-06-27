#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, WineContainerStatus) {
    WineContainerStatusNotCreated,
    WineContainerStatusCreating,
    WineContainerStatusReady,
    WineContainerStatusError
};

@interface WineContainer : NSObject

@property (nonatomic, readonly) NSString *containerName;
@property (nonatomic, readonly) NSString *containerPath;
@property (nonatomic, readonly) NSString *winePrefixPath;
@property (nonatomic, readonly) WineContainerStatus status;

- (instancetype)initWithName:(NSString *)name;
- (BOOL)createContainer;
- (BOOL)isWineInstalled;
- (BOOL)installWineLibraries;
- (NSString *)getVirtualCDrivePath;
- (NSString *)mapWindowsPathToReal:(NSString *)windowsPath;
- (BOOL)executeProgram:(NSString *)exePath withArguments:(nullable NSArray<NSString *> *)arguments;

@end

NS_ASSUME_NONNULL_END
