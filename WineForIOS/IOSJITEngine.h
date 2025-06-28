#import <Foundation/Foundation.h>
#import <sys/mman.h>
#import <sys/types.h>

NS_ASSUME_NONNULL_BEGIN

// JIT页面管理结构
typedef struct JITPage {
    void *memory;           // 内存地址
    size_t size;           // 页面大小
    BOOL isExecutable;     // 当前是否可执行
    BOOL isWritable;       // 当前是否可写
} JITPage;

// JIT编译上下文
typedef struct JITContext {
    JITPage *pages;        // 页面数组
    int pageCount;         // 页面数量
    int maxPages;          // 最大页面数
    BOOL isEnabled;        // JIT是否启用
} JITContext;

@interface IOSJITEngine : NSObject

@property (nonatomic, readonly) BOOL isJITEnabled;
@property (nonatomic, readonly) size_t totalJITMemory;

+ (instancetype)sharedEngine;

// JIT初始化和清理
- (BOOL)initializeJIT;
- (void)cleanupJIT;

// 内存管理
- (void *)allocateJITMemory:(size_t)size;
- (void)freeJITMemory:(void *)memory;

// 权限切换 (W^X实现)
- (BOOL)makeMemoryWritable:(void *)memory size:(size_t)size;
- (BOOL)makeMemoryExecutable:(void *)memory size:(size_t)size;

// 代码编译和执行
- (BOOL)writeCode:(const void *)code size:(size_t)size toMemory:(void *)memory;
- (int)executeCode:(void *)memory withArgc:(int)argc argv:(char **)argv;

// 调试支持
- (void)dumpJITStats;
- (NSString *)getJITStatus;

@end

NS_ASSUME_NONNULL_END
