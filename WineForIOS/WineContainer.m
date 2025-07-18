// WineContainer.m - 修复版本
#import "WineContainer.h"
#import "WineLibraryManager.h"

@interface WineContainer()
@property (nonatomic, strong) NSString *containerName;
@property (nonatomic, strong) NSString *containerPath;
@property (nonatomic, strong) NSString *winePrefixPath;
@property (nonatomic, assign) WineContainerStatus status;
@property (nonatomic, strong) WineLibraryManager *wineManager;
@end

@implementation WineContainer

- (instancetype)initWithName:(NSString *)name {
    self = [super init];
    if (self) {
        _containerName = [name copy];
        _status = WineContainerStatusNotCreated;
        _wineManager = [WineLibraryManager sharedManager];
        [self setupPaths];
    }
    return self;
}

- (void)setupPaths {
    NSArray *documentPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [documentPaths objectAtIndex:0];
    
    self.containerPath = [documentsDirectory stringByAppendingPathComponent:@"WineContainers"];
    self.containerPath = [self.containerPath stringByAppendingPathComponent:self.containerName];
    self.winePrefixPath = [self.containerPath stringByAppendingPathComponent:@"prefix"];
}

- (BOOL)createContainer {
    self.status = WineContainerStatusCreating;
    
    // 先加载Wine库
    if (![self.wineManager loadWineLibrariesIfNeeded]) {
        NSLog(@"Failed to load Wine libraries");
        self.status = WineContainerStatusError;
        return NO;
    }
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error = nil;
    
    // 创建容器目录结构
    NSArray *directories = @[
        self.containerPath,
        self.winePrefixPath,
        [self.winePrefixPath stringByAppendingPathComponent:@"drive_c"],
        [self.winePrefixPath stringByAppendingPathComponent:@"drive_c/windows"],
        [self.winePrefixPath stringByAppendingPathComponent:@"drive_c/windows/system32"],
        [self.winePrefixPath stringByAppendingPathComponent:@"drive_c/Program Files"],
        [self.winePrefixPath stringByAppendingPathComponent:@"drive_c/users"],
        [self.winePrefixPath stringByAppendingPathComponent:@"drive_c/users/default"]
    ];
    
    for (NSString *dir in directories) {
        if (![fileManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&error]) {
            NSLog(@"Failed to create directory %@: %@", dir, error.localizedDescription);
            self.status = WineContainerStatusError;
            return NO;
        }
    }
    
    // 创建基础配置文件
    [self createBasicWineConfiguration];
    
    // 初始化Wine环境
    if (![self.wineManager initializeWineEnvironment:self.winePrefixPath]) {
        NSLog(@"Failed to initialize Wine environment");
        self.status = WineContainerStatusError;
        return NO;
    }
    
    self.status = WineContainerStatusReady;
    return YES;
}

- (void)createBasicWineConfiguration {
    NSString *configPath = [self.winePrefixPath stringByAppendingPathComponent:@"user.reg"];
    NSString *basicConfig = @"[Software\\\\Wine]\n\"Version\"=\"wine-8.0\"\n";
    [basicConfig writeToFile:configPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

- (BOOL)isWineInstalled {
    NSString *winePath = [self.containerPath stringByAppendingPathComponent:@"wine"];
    return [[NSFileManager defaultManager] fileExistsAtPath:winePath];
}

- (BOOL)installWineLibraries {
    // 这里会复制预编译的Wine库文件到容器中
    NSString *bundlePath = [[NSBundle mainBundle] pathForResource:@"WineLibs" ofType:nil];
    if (!bundlePath) {
        NSLog(@"Wine libraries not found in bundle");
        return NO;
    }
    
    NSString *targetPath = [self.containerPath stringByAppendingPathComponent:@"wine"];
    NSError *error = nil;
    
    if (![[NSFileManager defaultManager] copyItemAtPath:bundlePath toPath:targetPath error:&error]) {
        NSLog(@"Failed to install Wine libraries: %@", error.localizedDescription);
        return NO;
    }
    
    return YES;
}

- (NSString *)getVirtualCDrivePath {
    return [self.winePrefixPath stringByAppendingPathComponent:@"drive_c"];
}

- (NSString *)mapWindowsPathToReal:(NSString *)windowsPath {
    // 将Windows路径映射到实际iOS文件系统路径
    if ([windowsPath hasPrefix:@"C:\\"]) {
        NSString *relativePath = [windowsPath substringFromIndex:3];
        relativePath = [relativePath stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
        return [[self getVirtualCDrivePath] stringByAppendingPathComponent:relativePath];
    }
    return windowsPath;
}

- (BOOL)executeProgram:(NSString *)exePath withArguments:(nullable NSArray<NSString *> *)arguments {
    if (self.status != WineContainerStatusReady) {
        NSLog(@"Container not ready");
        return NO;
    }
    
    if (!self.wineManager.isLoaded) {
        NSLog(@"Wine libraries not loaded");
        return NO;
    }
    
    NSLog(@"Executing: %@ with arguments: %@", exePath, arguments);
    
    // 使用真正的Wine执行程序
    int exitCode = [self.wineManager executeProgram:exePath arguments:arguments];
    
    return exitCode == 0;
}

@end
