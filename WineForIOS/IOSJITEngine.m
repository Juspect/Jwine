// IOSJITEngine.m - 修复iOS API兼容性版本
#import "IOSJITEngine.h"
#import <unistd.h>
#import <dlfcn.h>
// 🔧 修复：使用iOS可用的API
#import <libkern/OSCacheControl.h>  // 或者不导入，使用内建函数

// 条件编译：只在真机上使用ptrace
#if TARGET_OS_IPHONE && !TARGET_IPHONE_SIMULATOR
#import <sys/ptrace.h>
#define PT_TRACE_ME 0
#define PTRACE_AVAILABLE 1
#else
#define PTRACE_AVAILABLE 0
int ptrace(int request, pid_t pid, caddr_t addr, int data) {
    NSLog(@"[IOSJITEngine] ptrace not available on simulator");
    return 0;
}
#define PT_TRACE_ME 0
#endif

// 页面大小常量
#define JIT_PAGE_SIZE (16 * 1024)
#define MAX_JIT_PAGES 64

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
    if (ptrace(PT_TRACE_ME, 0, NULL, 0) == -1) {
        NSLog(@"[IOSJITEngine] ptrace(PT_TRACE_ME) failed: %s", strerror(errno));
        return NO;
    }
    NSLog(@"[IOSJITEngine] ptrace debugging enabled successfully (device)");
#else
    NSLog(@"[IOSJITEngine] ptrace debugging skipped (simulator mode)");
#endif
    
    return YES;
}

- (BOOL)testWXPermissions {
    NSLog(@"[IOSJITEngine] Testing W^X permissions...");
    
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
    
    size_t alignedSize = (size + JIT_PAGE_SIZE - 1) & ~(JIT_PAGE_SIZE - 1);
    
    void *memory = mmap(NULL, alignedSize, PROT_READ | PROT_WRITE,
                       MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    
    if (memory == MAP_FAILED) {
        NSLog(@"[IOSJITEngine] Failed to allocate JIT memory: %s", strerror(errno));
        return NULL;
    }
    
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
    
    for (int i = 0; i < _jitContext->pageCount; i++) {
        JITPage *page = &_jitContext->pages[i];
        if (page->memory == memory) {
            munmap(memory, page->size);
            
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

#pragma mark - 权限管理

- (BOOL)makeMemoryWritable:(void *)memory size:(size_t)size {
    size_t alignedSize = (size + JIT_PAGE_SIZE - 1) & ~(JIT_PAGE_SIZE - 1);
    
    if (mprotect(memory, alignedSize, PROT_READ | PROT_WRITE) != 0) {
        NSLog(@"[IOSJITEngine] Failed to make memory writable: %s", strerror(errno));
        return NO;
    }
    
    [self updatePagePermissions:memory writable:YES executable:NO];
    return YES;
}

- (BOOL)makeMemoryExecutable:(void *)memory size:(size_t)size {
    size_t alignedSize = (size + JIT_PAGE_SIZE - 1) & ~(JIT_PAGE_SIZE - 1);
    
    // 🔧 修复：使用iOS兼容的指令缓存清除方法
    [self clearInstructionCache:memory size:alignedSize];
    
    if (mprotect(memory, alignedSize, PROT_READ | PROT_EXEC) != 0) {
        NSLog(@"[IOSJITEngine] Failed to make memory executable: %s", strerror(errno));
        return NO;
    }
    
    [self updatePagePermissions:memory writable:NO executable:YES];
    return YES;
}

// 🔧 新增：iOS兼容的指令缓存清除方法
- (void)clearInstructionCache:(void *)memory size:(size_t)size {
    @try {
        // 方法1：使用GCC/Clang内建函数（最兼容）
        __builtin___clear_cache((char *)memory, (char *)memory + size);
        NSLog(@"[IOSJITEngine] Instruction cache cleared using builtin");
    } @catch (NSException *exception) {
        // 方法2：如果内建函数失败，尝试系统调用
        NSLog(@"[IOSJITEngine] Builtin cache clear failed, trying alternative");
        
        @try {
            // 在iOS上，这个函数可能可用
            void (*cache_invalidate)(void *, size_t) = dlsym(RTLD_DEFAULT, "sys_icache_invalidate");
            if (cache_invalidate) {
                cache_invalidate(memory, size);
                NSLog(@"[IOSJITEngine] Instruction cache cleared using dlsym");
            } else {
                NSLog(@"[IOSJITEngine] sys_icache_invalidate not available, continuing without cache clear");
            }
        } @catch (NSException *innerException) {
            NSLog(@"[IOSJITEngine] All cache clear methods failed, continuing without");
        }
    }
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
    
    if (![self makeMemoryWritable:memory size:size]) {
        return NO;
    }
    
    // 清零内存后再写入
    memset(memory, 0, ((size + JIT_PAGE_SIZE - 1) & ~(JIT_PAGE_SIZE - 1)));
    memcpy(memory, code, size);
    
    NSLog(@"[IOSJITEngine] Wrote %zu bytes of code to %p", size, memory);
    return YES;
}

- (int)executeCode:(void *)memory withArgc:(int)argc argv:(char **)argv {
    if (!memory) {
        NSLog(@"[IOSJITEngine] Invalid memory for execution");
        return -1;
    }
    
    if (![self makeMemoryExecutable:memory size:JIT_PAGE_SIZE]) {
        return -1;
    }
    
    NSLog(@"[IOSJITEngine] Executing JIT code at %p", memory);
    
    // 验证生成的代码
    uint32_t *instructions = (uint32_t *)memory;
    NSLog(@"[IOSJITEngine] First instruction: 0x%08X", instructions[0]);
    NSLog(@"[IOSJITEngine] Second instruction: 0x%08X", instructions[1]);
    
    @try {
        typedef int (*JITFunction)(void);
        JITFunction jitFunction = (JITFunction)memory;
        
        NSLog(@"[IOSJITEngine] About to call JIT function at %p", jitFunction);
        
        int result = jitFunction();
        
        NSLog(@"[IOSJITEngine] JIT execution completed with result: %d", result);
        return result;
        
    } @catch (NSException *exception) {
        NSLog(@"[IOSJITEngine] JIT execution failed: %@", exception.reason);
        NSLog(@"[IOSJITEngine] Exception name: %@", exception.name);
        NSLog(@"[IOSJITEngine] Exception userInfo: %@", exception.userInfo);
        return -1;
    }
}

#pragma mark - 清理和调试

- (void)cleanupJIT {
    if (!_jitInitialized) return;
    
    NSLog(@"[IOSJITEngine] Cleaning up JIT engine...");
    
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
