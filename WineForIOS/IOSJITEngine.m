#import "IOSJITEngine.h"
#import <unistd.h>
#import <dlfcn.h>

// 条件编译：只在真机上使用ptrace
#if TARGET_OS_IPHONE && !TARGET_IPHONE_SIMULATOR
#import <sys/ptrace.h>
#define PT_TRACE_ME 0
#define PTRACE_AVAILABLE 1
#else
#define PTRACE_AVAILABLE 0
// 模拟器上的ptrace函数声明
int ptrace(int request, pid_t pid, caddr_t addr, int data) {
    NSLog(@"[IOSJITEngine] ptrace not available on simulator");
    return 0;  // 模拟成功
}
#define PT_TRACE_ME 0
#endif

// 页面大小常量
#define JIT_PAGE_SIZE (16 * 1024)  // iOS上通常是16K页面
#define MAX_JIT_PAGES 64           // 最大JIT页面数

@interface IOSJITEngine()
@property (nonatomic, assign) JITContext *jitContext;
@property (nonatomic, assign) BOOL jitInitialized;
@end

@implementation IOSJITEngine

+ (instancetype)sharedEngine {
    static IOSJITEngine *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[IOSJITEngine alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _jitInitialized = NO;
        _jitContext = malloc(sizeof(JITContext));
        memset(_jitContext, 0, sizeof(JITContext));
        _jitContext->maxPages = MAX_JIT_PAGES;
        _jitContext->pages = malloc(sizeof(JITPage) * MAX_JIT_PAGES);
        memset(_jitContext->pages, 0, sizeof(JITPage) * MAX_JIT_PAGES);
    }
    return self;
}

- (void)dealloc {
    [self cleanupJIT];
    if (_jitContext) {
        if (_jitContext->pages) {
            free(_jitContext->pages);
        }
        free(_jitContext);
    }
}

#pragma mark - JIT初始化

- (BOOL)initializeJIT {
    if (_jitInitialized) {
        NSLog(@"[IOSJITEngine] JIT already initialized");
        return YES;
    }
    
    NSLog(@"[IOSJITEngine] Initializing iOS JIT engine...");
    
    // 第一步：启用ptrace自我跟踪
    if (![self enablePtraceDebugging]) {
        NSLog(@"[IOSJITEngine] Failed to enable ptrace debugging");
        return NO;
    }
    
    // 第二步：测试W^X权限切换
    if (![self testWXPermissions]) {
        NSLog(@"[IOSJITEngine] W^X permission test failed");
        return NO;
    }
    
    _jitContext->isEnabled = YES;
    _jitInitialized = YES;
    
    NSLog(@"[IOSJITEngine] JIT initialization successful!");
    return YES;
}

- (BOOL)enablePtraceDebugging {
    NSLog(@"[IOSJITEngine] Enabling ptrace debugging...");
    
#if PTRACE_AVAILABLE
    // 使用ptrace(PT_TRACE_ME)启用代码签名验证绕过 (仅真机)
    if (ptrace(PT_TRACE_ME, 0, NULL, 0) == -1) {
        NSLog(@"[IOSJITEngine] ptrace(PT_TRACE_ME) failed: %s", strerror(errno));
        return NO;
    }
    NSLog(@"[IOSJITEngine] ptrace debugging enabled successfully (device)");
#else
    // 模拟器模式：跳过ptrace，但继续执行
    NSLog(@"[IOSJITEngine] ptrace debugging skipped (simulator mode)");
#endif
    
    return YES;
}

- (BOOL)testWXPermissions {
    NSLog(@"[IOSJITEngine] Testing W^X permissions...");
    
    // 分配测试内存
    size_t testSize = JIT_PAGE_SIZE;
    void *testMemory = mmap(NULL, testSize, PROT_READ | PROT_WRITE,
                           MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    
    if (testMemory == MAP_FAILED) {
        NSLog(@"[IOSJITEngine] Failed to allocate test memory: %s", strerror(errno));
        return NO;
    }
    
    // 测试写入权限
    *(uint32_t *)testMemory = 0x12345678;
    
    // 切换到执行权限
    if (mprotect(testMemory, testSize, PROT_READ | PROT_EXEC) != 0) {
        NSLog(@"[IOSJITEngine] Failed to switch to execute permissions: %s", strerror(errno));
        munmap(testMemory, testSize);
        return NO;
    }
    
    // 验证数据完整性
    if (*(uint32_t *)testMemory != 0x12345678) {
        NSLog(@"[IOSJITEngine] Data corruption detected after permission switch");
        munmap(testMemory, testSize);
        return NO;
    }
    
    // 清理测试内存
    munmap(testMemory, testSize);
    
    NSLog(@"[IOSJITEngine] W^X permission test passed!");
    return YES;
}

#pragma mark - 内存管理

- (void *)allocateJITMemory:(size_t)size {
    if (!_jitInitialized) {
        NSLog(@"[IOSJITEngine] JIT not initialized");
        return NULL;
    }
    
    // 确保大小是页面对齐的
    size_t alignedSize = (size + JIT_PAGE_SIZE - 1) & ~(JIT_PAGE_SIZE - 1);
    
    // 分配内存 (初始为可写)
    void *memory = mmap(NULL, alignedSize, PROT_READ | PROT_WRITE,
                       MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    
    if (memory == MAP_FAILED) {
        NSLog(@"[IOSJITEngine] Failed to allocate JIT memory: %s", strerror(errno));
        return NULL;
    }
    
    // 记录页面信息
    if (_jitContext->pageCount < _jitContext->maxPages) {
        JITPage *page = &_jitContext->pages[_jitContext->pageCount++];
        page->memory = memory;
        page->size = alignedSize;
        page->isWritable = YES;
        page->isExecutable = NO;
    }
    
    NSLog(@"[IOSJITEngine] Allocated %zu bytes JIT memory at %p", alignedSize, memory);
    return memory;
}

- (void)freeJITMemory:(void *)memory {
    if (!memory) return;
    
    // 查找对应的页面
    for (int i = 0; i < _jitContext->pageCount; i++) {
        JITPage *page = &_jitContext->pages[i];
        if (page->memory == memory) {
            // 释放内存
            munmap(memory, page->size);
            
            // 移除页面记录
            for (int j = i; j < _jitContext->pageCount - 1; j++) {
                _jitContext->pages[j] = _jitContext->pages[j + 1];
            }
            _jitContext->pageCount--;
            
            NSLog(@"[IOSJITEngine] Freed JIT memory at %p", memory);
            return;
        }
    }
    
    NSLog(@"[IOSJITEngine] Warning: Attempted to free unknown JIT memory %p", memory);
}

#pragma mark - 权限管理 (W^X实现)

- (BOOL)makeMemoryWritable:(void *)memory size:(size_t)size {
    // 确保大小是页面对齐的
    size_t alignedSize = (size + JIT_PAGE_SIZE - 1) & ~(JIT_PAGE_SIZE - 1);
    
    if (mprotect(memory, alignedSize, PROT_READ | PROT_WRITE) != 0) {
        NSLog(@"[IOSJITEngine] Failed to make memory writable: %s", strerror(errno));
        return NO;
    }
    
    // 更新页面状态
    [self updatePagePermissions:memory writable:YES executable:NO];
    
    return YES;
}

- (BOOL)makeMemoryExecutable:(void *)memory size:(size_t)size {
    // 确保大小是页面对齐的
    size_t alignedSize = (size + JIT_PAGE_SIZE - 1) & ~(JIT_PAGE_SIZE - 1);
    
    if (mprotect(memory, alignedSize, PROT_READ | PROT_EXEC) != 0) {
        NSLog(@"[IOSJITEngine] Failed to make memory executable: %s", strerror(errno));
        return NO;
    }
    
    // 更新页面状态
    [self updatePagePermissions:memory writable:NO executable:YES];
    
    return YES;
}

- (void)updatePagePermissions:(void *)memory writable:(BOOL)writable executable:(BOOL)executable {
    for (int i = 0; i < _jitContext->pageCount; i++) {
        JITPage *page = &_jitContext->pages[i];
        if (page->memory == memory) {
            page->isWritable = writable;
            page->isExecutable = executable;
            break;
        }
    }
}

#pragma mark - 代码编译和执行

- (BOOL)writeCode:(const void *)code size:(size_t)size toMemory:(void *)memory {
    if (!code || !memory || size == 0) {
        NSLog(@"[IOSJITEngine] Invalid parameters for writeCode");
        return NO;
    }
    
    // 确保内存是可写的
    if (![self makeMemoryWritable:memory size:size]) {
        return NO;
    }
    
    // 复制代码到JIT内存
    memcpy(memory, code, size);
    
    NSLog(@"[IOSJITEngine] Wrote %zu bytes of code to %p", size, memory);
    return YES;
}

- (int)executeCode:(void *)memory withArgc:(int)argc argv:(char **)argv {
    if (!memory) {
        NSLog(@"[IOSJITEngine] Invalid memory for execution");
        return -1;
    }
    
    // 确保内存是可执行的
    if (![self makeMemoryExecutable:memory size:JIT_PAGE_SIZE]) {
        return -1;
    }
    
    NSLog(@"[IOSJITEngine] Executing JIT code at %p", memory);
    
    // 将内存转换为函数指针并执行
    int (*jitFunction)(int, char **) = (int (*)(int, char **))memory;
    
    @try {
        int result = jitFunction(argc, argv);
        NSLog(@"[IOSJITEngine] JIT execution completed with result: %d", result);
        return result;
    } @catch (NSException *exception) {
        NSLog(@"[IOSJITEngine] JIT execution failed: %@", exception.reason);
        return -1;
    }
}

#pragma mark - 清理和调试

- (void)cleanupJIT {
    if (!_jitInitialized) return;
    
    NSLog(@"[IOSJITEngine] Cleaning up JIT engine...");
    
    // 释放所有JIT页面
    for (int i = 0; i < _jitContext->pageCount; i++) {
        JITPage *page = &_jitContext->pages[i];
        if (page->memory) {
            munmap(page->memory, page->size);
        }
    }
    
    _jitContext->pageCount = 0;
    _jitContext->isEnabled = NO;
    _jitInitialized = NO;
    
    NSLog(@"[IOSJITEngine] JIT cleanup completed");
}

- (void)dumpJITStats {
    NSLog(@"[IOSJITEngine] ===== JIT Statistics =====");
    NSLog(@"[IOSJITEngine] Initialized: %@", _jitInitialized ? @"YES" : @"NO");
    NSLog(@"[IOSJITEngine] Enabled: %@", _jitContext->isEnabled ? @"YES" : @"NO");
    NSLog(@"[IOSJITEngine] Active pages: %d/%d", _jitContext->pageCount, _jitContext->maxPages);
    NSLog(@"[IOSJITEngine] Total memory: %zu KB", [self totalJITMemory] / 1024);
    
    for (int i = 0; i < _jitContext->pageCount; i++) {
        JITPage *page = &_jitContext->pages[i];
        NSLog(@"[IOSJITEngine] Page %d: %p (%zu bytes) W:%@ X:%@",
              i, page->memory, page->size,
              page->isWritable ? @"Y" : @"N",
              page->isExecutable ? @"Y" : @"N");
    }
    NSLog(@"[IOSJITEngine] ==========================");
}

- (NSString *)getJITStatus {
    if (!_jitInitialized) {
        return @"JIT未初始化";
    }
    
    return [NSString stringWithFormat:@"JIT已启用 (%d页面, %zu KB)",
            _jitContext->pageCount, [self totalJITMemory] / 1024];
}

#pragma mark - 属性实现

- (BOOL)isJITEnabled {
    return _jitInitialized && _jitContext->isEnabled;
}

- (size_t)totalJITMemory {
    size_t total = 0;
    for (int i = 0; i < _jitContext->pageCount; i++) {
        total += _jitContext->pages[i].size;
    }
    return total;
}

@end
