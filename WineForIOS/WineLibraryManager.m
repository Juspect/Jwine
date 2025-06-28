// WineLibraryManager.m - 修复版本（解决dyld加载问题）
#import "WineLibraryManager.h"

@interface WineLibraryManager()
@property (nonatomic, assign, nullable) void *libwineHandle;
@property (nonatomic, assign, nullable) void *ntdllHandle;
@property (nonatomic, assign, nullable) void *kernel32Handle;
@property (nonatomic, assign, nullable) void *user32Handle;    // 新增
@property (nonatomic, assign, nullable) void *gdi32Handle;     // 新增
@property (nonatomic, assign, nullable) WineAPI *wineAPI;
@property (nonatomic, strong, nullable) NSString *wineLibsPath;
@property (nonatomic, assign) BOOL librariesExist;            // 缓存检查结果
@end

@implementation WineLibraryManager

+ (instancetype)sharedManager {
    static WineLibraryManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _isLoaded = NO;
        _librariesExist = NO;
        _wineAPI = malloc(sizeof(WineAPI));
        memset(_wineAPI, 0, sizeof(WineAPI));
        
        // 获取Wine库路径
        NSBundle *mainBundle = [NSBundle mainBundle];
        _wineLibsPath = [mainBundle pathForResource:@"WineLibs" ofType:nil];
        
        if (!_wineLibsPath) {
            // 尝试其他可能的路径
            NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
            _wineLibsPath = [documentsPath stringByAppendingPathComponent:@"WineLibs"];
            
            if (![[NSFileManager defaultManager] fileExistsAtPath:_wineLibsPath]) {
                NSLog(@"[WineLibraryManager] Wine库文件夹未找到，将在首次加载时检查");
                _wineLibsPath = nil;
            }
        }
        
        // 不在初始化时加载库，避免启动时的dyld错误
        NSLog(@"[WineLibraryManager] 管理器已初始化，延迟加载策略");
    }
    return self;
}

- (void)dealloc {
    [self unloadWineLibraries];
    if (_wineAPI) {
        free(_wineAPI);
    }
}

#pragma mark - 库存在性检查

- (BOOL)checkWineLibrariesExist {
    if (!_wineLibsPath) {
        NSLog(@"[WineLibraryManager] Wine库路径未设置");
        return NO;
    }
    
    NSArray *requiredLibs = @[@"libwine.dylib", @"ntdll.dll.so", @"kernel32.dll.so", @"user32.dll.so", @"gdi32.dll.so"];
    NSFileManager *fm = [NSFileManager defaultManager];
    
    for (NSString *lib in requiredLibs) {
        NSString *libPath = [_wineLibsPath stringByAppendingPathComponent:lib];
        if (![fm fileExistsAtPath:libPath]) {
            NSLog(@"[WineLibraryManager] 缺少库文件: %@", lib);
            _librariesExist = NO;
            return NO;
        }
    }
    
    _librariesExist = YES;
    NSLog(@"[WineLibraryManager] 所有必需库文件已找到");
    return YES;
}

- (NSArray<NSString *> *)getMissingLibraries {
    if (!_wineLibsPath) {
        return @[@"WineLibs文件夹不存在"];
    }
    
    NSArray *requiredLibs = @[@"libwine.dylib", @"ntdll.dll.so", @"kernel32.dll.so", @"user32.dll.so", @"gdi32.dll.so"];
    NSMutableArray *missing = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    
    for (NSString *lib in requiredLibs) {
        NSString *libPath = [_wineLibsPath stringByAppendingPathComponent:lib];
        if (![fm fileExistsAtPath:libPath]) {
            [missing addObject:lib];
        }
    }
    
    return [missing copy];
}

#pragma mark - 延迟加载

- (BOOL)loadWineLibrariesIfNeeded {
    if (_isLoaded) {
        NSLog(@"[WineLibraryManager] Wine库已加载");
        return YES;
    }
    
    // 首先检查库文件是否存在
    if (![self checkWineLibrariesExist]) {
        NSArray *missing = [self getMissingLibraries];
        NSLog(@"[WineLibraryManager] 缺少库文件: %@", missing);
        return NO;
    }
    
    return [self loadWineLibraries];
}

- (BOOL)loadWineLibraries {
    if (_isLoaded) {
        NSLog(@"[WineLibraryManager] Wine库已加载");
        return YES;
    }
    
    if (!_wineLibsPath) {
        NSLog(@"[WineLibraryManager] Wine库路径未设置");
        return NO;
    }
    
    NSLog(@"[WineLibraryManager] 开始加载Wine库...");
    
    // 使用RTLD_LAZY | RTLD_LOCAL避免立即解析所有符号
    const int loadFlags = RTLD_LAZY | RTLD_LOCAL;
    
    // 按依赖顺序加载
    if (![self loadLibrary:@"libwine.dylib" handle:&_libwineHandle flags:loadFlags]) {
        return NO;
    }
    
    if (![self loadLibrary:@"ntdll.dll.so" handle:&_ntdllHandle flags:loadFlags]) {
        return NO;
    }
    
    if (![self loadLibrary:@"kernel32.dll.so" handle:&_kernel32Handle flags:loadFlags]) {
        return NO;
    }
    
    if (![self loadLibrary:@"user32.dll.so" handle:&_user32Handle flags:loadFlags]) {
        return NO;
    }
    
    if (![self loadLibrary:@"gdi32.dll.so" handle:&_gdi32Handle flags:loadFlags]) {
        return NO;
    }
    
    // 获取函数指针
    if (![self loadWineFunctions]) {
        NSLog(@"[WineLibraryManager] 获取Wine函数指针失败");
        [self unloadWineLibraries];
        return NO;
    }
    
    _isLoaded = YES;
    NSLog(@"[WineLibraryManager] Wine库加载完成");
    return YES;
}

- (BOOL)loadLibrary:(NSString *)libraryName handle:(void **)handle flags:(int)flags {
    NSString *libPath = [_wineLibsPath stringByAppendingPathComponent:libraryName];
    
    *handle = dlopen([libPath UTF8String], flags);
    if (!*handle) {
        const char *error = dlerror();
        NSLog(@"[WineLibraryManager] 加载%@失败: %s", libraryName, error ? error : "未知错误");
        return NO;
    }
    
    NSLog(@"[WineLibraryManager] %@加载成功", libraryName);
    return YES;
}

- (BOOL)loadWineFunctions {
    NSLog(@"[WineLibraryManager] 获取Wine函数指针...");
    
    // 从libwine获取核心函数（可能不存在，使用系统函数作为后备）
    _wineAPI->wine_init = dlsym(_libwineHandle, "wine_init");
    _wineAPI->wine_main = dlsym(_libwineHandle, "wine_main");
    _wineAPI->wine_cleanup = dlsym(_libwineHandle, "wine_cleanup");
    
    // 动态库函数
    _wineAPI->wine_dlopen = dlsym(_libwineHandle, "wine_dlopen");
    _wineAPI->wine_dlsym = dlsym(_libwineHandle, "wine_dlsym");
    _wineAPI->wine_dlclose = dlsym(_libwineHandle, "wine_dlclose");
    
    // 如果某些函数不存在，使用系统函数作为后备
    if (!_wineAPI->wine_dlopen) {
        _wineAPI->wine_dlopen = dlopen;
    }
    if (!_wineAPI->wine_dlsym) {
        _wineAPI->wine_dlsym = dlsym;
    }
    if (!_wineAPI->wine_dlclose) {
        _wineAPI->wine_dlclose = dlclose;
    }
    
    // 内存管理函数
    _wineAPI->wine_mmap = dlsym(_libwineHandle, "wine_mmap");
    _wineAPI->wine_munmap = dlsym(_libwineHandle, "wine_munmap");
    
    if (!_wineAPI->wine_mmap) {
        _wineAPI->wine_mmap = mmap;
    }
    if (!_wineAPI->wine_munmap) {
        _wineAPI->wine_munmap = munmap;
    }
    
    // 进程管理函数
    _wineAPI->wine_exec = dlsym(_libwineHandle, "wine_exec");
    _wineAPI->wine_exit = dlsym(_libwineHandle, "wine_exit");
    
    if (!_wineAPI->wine_exit) {
        _wineAPI->wine_exit = exit;
    }
    
    NSLog(@"[WineLibraryManager] Wine函数指针获取完成");
    return YES;
}

- (void)unloadWineLibraries {
    if (!_isLoaded) {
        return;
    }
    
    NSLog(@"[WineLibraryManager] 卸载Wine库...");
    
    if (_wineAPI->wine_cleanup) {
        _wineAPI->wine_cleanup();
    }
    
    if (_gdi32Handle) {
        dlclose(_gdi32Handle);
        _gdi32Handle = NULL;
    }
    
    if (_user32Handle) {
        dlclose(_user32Handle);
        _user32Handle = NULL;
    }
    
    if (_kernel32Handle) {
        dlclose(_kernel32Handle);
        _kernel32Handle = NULL;
    }
    
    if (_ntdllHandle) {
        dlclose(_ntdllHandle);
        _ntdllHandle = NULL;
    }
    
    if (_libwineHandle) {
        dlclose(_libwineHandle);
        _libwineHandle = NULL;
    }
    
    memset(_wineAPI, 0, sizeof(WineAPI));
    _isLoaded = NO;
    
    NSLog(@"[WineLibraryManager] Wine库卸载完成");
}

- (BOOL)initializeWineEnvironment:(NSString *)prefixPath {
    if (![self loadWineLibrariesIfNeeded]) {
        NSLog(@"[WineLibraryManager] Wine库加载失败");
        return NO;
    }
    
    NSLog(@"[WineLibraryManager] 初始化Wine环境...");
    
    // 设置环境变量
    setenv("WINEPREFIX", [prefixPath UTF8String], 1);
    setenv("WINEDEBUG", "-all", 1);
    setenv("WINE_CPU", "arm64", 1);
    
    // 初始化Wine
    if (_wineAPI->wine_init) {
        void *result = _wineAPI->wine_init();
        if (!result) {
            NSLog(@"[WineLibraryManager] Wine初始化失败");
            return NO;
        }
    }
    
    NSLog(@"[WineLibraryManager] Wine环境初始化完成");
    return YES;
}

- (int)executeProgram:(NSString *)exePath arguments:(NSArray<NSString *> *)arguments {
    if (![self loadWineLibrariesIfNeeded]) {
        NSLog(@"[WineLibraryManager] Wine库加载失败");
        return -1;
    }
    
    NSLog(@"[WineLibraryManager] 执行程序: %@", exePath);
    
    // 准备参数
    NSMutableArray *allArgs = [NSMutableArray arrayWithObject:@"wine"];
    [allArgs addObject:exePath];
    if (arguments) {
        [allArgs addObjectsFromArray:arguments];
    }
    
    // 转换为C字符串数组
    int argc = (int)[allArgs count];
    char **argv = malloc(sizeof(char*) * (argc + 1));
    
    for (int i = 0; i < argc; i++) {
        NSString *arg = allArgs[i];
        argv[i] = strdup([arg UTF8String]);
    }
    argv[argc] = NULL;
    
    int result = -1;
    
    // 执行程序
    if (_wineAPI->wine_main) {
        result = _wineAPI->wine_main(argc, argv);
    } else if (_wineAPI->wine_exec) {
        result = _wineAPI->wine_exec([exePath UTF8String], &argv[1]);
    } else {
        NSLog(@"[WineLibraryManager] 没有可用的执行函数");
    }
    
    // 清理内存
    for (int i = 0; i < argc; i++) {
        free(argv[i]);
    }
    free(argv);
    
    NSLog(@"[WineLibraryManager] 程序执行完成，退出码: %d", result);
    return result;
}

- (NSString *)wineVersion {
    // 读取配置文件获取版本信息
    NSString *configPath = [_wineLibsPath stringByAppendingPathComponent:@"wine_config.plist"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:configPath]) {
        NSDictionary *config = [NSDictionary dictionaryWithContentsOfFile:configPath];
        return config[@"WineVersion"] ?: @"Unknown";
    }
    return @"8.0-ios-stub";
}

@end
