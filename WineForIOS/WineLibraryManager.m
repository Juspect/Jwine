// WineLibraryManager.m - 修复版本
#import "WineLibraryManager.h"

@interface WineLibraryManager()
@property (nonatomic, assign, nullable) void *libwineHandle;
@property (nonatomic, assign, nullable) void *ntdllHandle;
@property (nonatomic, assign, nullable) void *kernel32Handle;
@property (nonatomic, assign, nullable) WineAPI *wineAPI;
@property (nonatomic, strong, nullable) NSString *wineLibsPath;
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
        _wineAPI = malloc(sizeof(WineAPI));
        memset(_wineAPI, 0, sizeof(WineAPI));
        
        // 获取Wine库路径
        NSBundle *mainBundle = [NSBundle mainBundle];
        _wineLibsPath = [mainBundle pathForResource:@"WineLibs" ofType:nil];
        
        if (!_wineLibsPath) {
            NSLog(@"[WineLibraryManager] Wine库文件夹未找到");
        }
    }
    return self;
}

- (void)dealloc {
    [self unloadWineLibraries];
    if (_wineAPI) {
        free(_wineAPI);
    }
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
    
    // 加载libwine.dylib
    NSString *libwinePath = [_wineLibsPath stringByAppendingPathComponent:@"libwine.dylib"];
    _libwineHandle = dlopen([libwinePath UTF8String], RTLD_LAZY | RTLD_LOCAL);
    if (!_libwineHandle) {
        NSLog(@"[WineLibraryManager] 加载libwine.dylib失败: %s", dlerror());
        return NO;
    }
    NSLog(@"[WineLibraryManager] libwine.dylib加载成功");
    
    // 加载ntdll.dll.so
    NSString *ntdllPath = [_wineLibsPath stringByAppendingPathComponent:@"ntdll.dll.so"];
    _ntdllHandle = dlopen([ntdllPath UTF8String], RTLD_LAZY | RTLD_LOCAL);
    if (!_ntdllHandle) {
        NSLog(@"[WineLibraryManager] 加载ntdll.dll.so失败: %s", dlerror());
        return NO;
    }
    NSLog(@"[WineLibraryManager] ntdll.dll.so加载成功");
    
    // 加载kernel32.dll.so
    NSString *kernel32Path = [_wineLibsPath stringByAppendingPathComponent:@"kernel32.dll.so"];
    _kernel32Handle = dlopen([kernel32Path UTF8String], RTLD_LAZY | RTLD_LOCAL);
    if (!_kernel32Handle) {
        NSLog(@"[WineLibraryManager] 加载kernel32.dll.so失败: %s", dlerror());
        return NO;
    }
    NSLog(@"[WineLibraryManager] kernel32.dll.so加载成功");
    
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

- (BOOL)loadWineFunctions {
    NSLog(@"[WineLibraryManager] 获取Wine函数指针...");
    
    // 从libwine获取核心函数
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
    if (!_isLoaded) {
        NSLog(@"[WineLibraryManager] Wine库未加载");
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
    if (!_isLoaded) {
        NSLog(@"[WineLibraryManager] Wine库未加载");
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
    NSDictionary *config = [NSDictionary dictionaryWithContentsOfFile:configPath];
    return config[@"WineVersion"] ?: @"Unknown";
}

@end
