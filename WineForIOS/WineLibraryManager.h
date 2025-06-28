// WineLibraryManager.h - 最终修复版本（解决dyld加载问题）
#import <Foundation/Foundation.h>
#import <dlfcn.h>

NS_ASSUME_NONNULL_BEGIN

typedef struct WineAPI {
    // Wine核心函数指针 - 使用懒加载，避免启动时加载
    void* _Nullable (*_Nullable wine_init)(void);
    int (*_Nullable wine_main)(int argc, char * _Nonnull argv[_Nonnull]);
    void (*_Nullable wine_cleanup)(void);
    
    // 动态库相关
    void* _Nullable (*_Nullable wine_dlopen)(const char * _Nonnull filename, int flag);
    void* _Nullable (*_Nullable wine_dlsym)(void * _Nullable handle, const char * _Nonnull symbol);
    int (*_Nullable wine_dlclose)(void * _Nullable handle);
    
    // 内存管理
    void* _Nullable (*_Nullable wine_mmap)(void * _Nullable addr, size_t length, int prot, int flags, int fd, off_t offset);
    int (*_Nullable wine_munmap)(void * _Nullable addr, size_t length);
    
    // 进程管理
    int (*_Nullable wine_exec)(const char * _Nonnull filename, char * const _Nonnull argv[_Nonnull]);
    void (*_Nullable wine_exit)(int status);
    
} WineAPI;

@interface WineLibraryManager : NSObject

@property (nonatomic, readonly) BOOL isLoaded;
@property (nonatomic, readonly, nullable) NSString *wineVersion;
@property (nonatomic, readonly, nullable) WineAPI *wineAPI;

+ (instancetype _Nonnull)sharedManager;

// 修改：延迟加载，避免启动时自动加载
- (BOOL)loadWineLibrariesIfNeeded;
- (void)unloadWineLibraries;
- (BOOL)initializeWineEnvironment:(NSString * _Nonnull)prefixPath;
- (int)executeProgram:(NSString * _Nonnull)exePath arguments:(NSArray<NSString *> * _Nullable)arguments;

// 新增：检查库文件是否存在，不实际加载
- (BOOL)checkWineLibrariesExist;
- (NSArray<NSString *> * _Nullable)getMissingLibraries;

@end

NS_ASSUME_NONNULL_END
