#import "Box64Engine.h"
#import <sys/mman.h>
#import <pthread.h>
#import <errno.h>
#import <string.h>

// ARM64指令编码宏 - 安全版本
#define ARM64_NOP()           0xD503201F
#define ARM64_RET()           0xD65F03C0
#define ARM64_MOVZ_X(rd, imm) (0xD2800000 | (((imm) & 0xFFFF) << 5) | ((rd) & 0x1F))
#define ARM64_ADD_IMM_X(rd, rn, imm) (0x91000000 | (((imm) & 0xFFF) << 10) | (((rn) & 0x1F) << 5) | ((rd) & 0x1F))

// x86到ARM64寄存器映射
static const ARM64Register x86_to_arm64_mapping[16] = {
    ARM64_X19, ARM64_X20, ARM64_X21, ARM64_X22, ARM64_SP, ARM64_X29,
    ARM64_X23, ARM64_X24, ARM64_X8, ARM64_X9, ARM64_X10, ARM64_X11,
    ARM64_X12, ARM64_X13, ARM64_X14, ARM64_X15
};

@interface Box64Engine()
@property (nonatomic, assign) Box64Context *context;
@property (nonatomic, assign) BOOL isInitialized;
@property (nonatomic, assign) BOOL isSafeMode;
@property (nonatomic, strong) NSMutableArray<NSString *> *safetyWarnings;
@property (nonatomic, strong) NSString *lastError;
@property (nonatomic, strong) NSRecursiveLock *contextLock;
@end

@implementation Box64Engine

+ (instancetype)sharedEngine {
    static Box64Engine *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[Box64Engine alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _isInitialized = NO;
        _isSafeMode = YES;  // 默认启用安全模式
        _jitEngine = [IOSJITEngine sharedEngine];
        _safetyWarnings = [NSMutableArray array];
        _contextLock = [[NSRecursiveLock alloc] init];
        
        // 安全的内存分配
        _context = calloc(1, sizeof(Box64Context));
        if (!_context) {
            NSLog(@"[Box64Engine] CRITICAL: Failed to allocate context");
            _lastError = @"无法分配执行上下文内存";
            return nil;
        }
        
        // 初始化安全参数
        _context->is_in_safe_mode = YES;
        _context->max_instructions = MAX_INSTRUCTIONS_PER_EXECUTION;
        _context->instruction_count = 0;
        
        NSLog(@"[Box64Engine] Initialized with enhanced memory safety");
    }
    return self;
}

- (void)dealloc {
    [self cleanup];
    if (_context) {
        free(_context);
        _context = NULL;
    }
}

#pragma mark - 初始化和清理 - 安全版本

- (BOOL)initializeWithMemorySize:(size_t)memorySize {
    return [self initializeWithMemorySize:memorySize safeMode:YES];
}

- (BOOL)initializeWithMemorySize:(size_t)memorySize safeMode:(BOOL)safeMode {
    [_contextLock lock];
    
    @try {
        if (_isInitialized) {
            NSLog(@"[Box64Engine] Already initialized");
            return YES;
        }
        
        // 内存大小安全检查
        if (memorySize < MEMORY_GUARD_SIZE * 4 || memorySize > MAX_MEMORY_SIZE) {
            NSLog(@"[Box64Engine] SECURITY: Invalid memory size: %zu bytes", memorySize);
            _lastError = [NSString stringWithFormat:@"无效的内存大小: %zu字节", memorySize];
            return NO;
        }
        
        // 确保context存在
        if (!_context) {
            NSLog(@"[Box64Engine] CRITICAL: Context is NULL");
            _lastError = @"执行上下文为空";
            return NO;
        }
        
        NSLog(@"[Box64Engine] Initializing with %zu MB memory (Safe Mode: %@)",
              memorySize / (1024 * 1024), safeMode ? @"ON" : @"OFF");
        
        // 初始化JIT引擎
        if (![_jitEngine initializeJIT]) {
            NSLog(@"[Box64Engine] CRITICAL: Failed to initialize JIT engine");
            _lastError = @"JIT引擎初始化失败";
            return NO;
        }
        
        // 分配虚拟内存空间 - 带保护页
        _context->memory_base = malloc(memorySize + MEMORY_GUARD_SIZE * 2);
        if (!_context->memory_base) {
            NSLog(@"[Box64Engine] CRITICAL: Failed to allocate memory");
            _lastError = @"内存分配失败";
            return NO;
        }
        
        _context->memory_size = memorySize;
        memset(_context->memory_base, 0, memorySize + MEMORY_GUARD_SIZE * 2);
        
        // 设置保护页 - 前后各一页
        if (mprotect(_context->memory_base, MEMORY_GUARD_SIZE, PROT_NONE) != 0) {
            NSLog(@"[Box64Engine] WARNING: Could not set front guard page: %s", strerror(errno));
        }
        
        uint8_t *end_guard = _context->memory_base + MEMORY_GUARD_SIZE + memorySize;
        if (mprotect(end_guard, MEMORY_GUARD_SIZE, PROT_NONE) != 0) {
            NSLog(@"[Box64Engine] WARNING: Could not set end guard page: %s", strerror(errno));
        }
        
        // 调整内存基址到可用区域
        _context->memory_base += MEMORY_GUARD_SIZE;
        
        // 分配JIT缓存
        _context->jit_cache = [_jitEngine allocateJITMemory:4096];
        if (!_context->jit_cache) {
            NSLog(@"[Box64Engine] CRITICAL: Failed to allocate JIT cache");
            _lastError = @"JIT缓存分配失败";
            free(_context->memory_base - MEMORY_GUARD_SIZE);
            _context->memory_base = NULL;
            return NO;
        }
        
        // 初始化内存区域管理
        [self initializeMemoryRegions];
        
        // 初始化CPU状态
        [self resetCPUState];
        
        // 设置安全模式
        _isSafeMode = safeMode;
        _context->is_in_safe_mode = safeMode;
        
        _isInitialized = YES;
        NSLog(@"[Box64Engine] Successfully initialized with enhanced security");
        return YES;
        
    } @finally {
        [_contextLock unlock];
    }
}

- (void)initializeMemoryRegions {
    if (!_context) return;
    
    // 清空区域记录
    memset(_context->memory_regions, 0, sizeof(_context->memory_regions));
    _context->region_count = 0;
    
    // 设置基础内存区域
    _context->stack_size = 1024 * 1024;  // 1MB栈
    _context->stack_base = (uint64_t)_context->memory_base + _context->memory_size - _context->stack_size;
    
    _context->heap_base = (uint64_t)_context->memory_base + 0x10000;  // 64KB后开始堆
    _context->heap_size = _context->memory_size / 2;  // 一半内存作为堆
    
    // 添加栈区域
    [self addMemoryRegion:_context->stack_base size:_context->stack_size
                     name:"Stack" executable:NO writable:YES];
    
    // 添加堆区域
    [self addMemoryRegion:_context->heap_base size:_context->heap_size
                     name:"Heap" executable:NO writable:YES];
    
    NSLog(@"[Box64Engine] Memory regions initialized: Stack=0x%llx-0x%llx, Heap=0x%llx-0x%llx",
          _context->stack_base, _context->stack_base + _context->stack_size,
          _context->heap_base, _context->heap_base + _context->heap_size);
}

- (BOOL)addMemoryRegion:(uint64_t)address size:(uint64_t)size name:(const char *)name executable:(BOOL)executable writable:(BOOL)writable {
    if (!_context || _context->region_count >= 32) {
        return NO;
    }
    
    MemoryRegion *region = &_context->memory_regions[_context->region_count];
    region->start_address = address;
    region->size = size;
    region->is_allocated = YES;
    region->is_executable = executable;
    region->is_writable = writable;
    strncpy(region->name, name, sizeof(region->name) - 1);
    region->name[sizeof(region->name) - 1] = '\0';
    
    _context->region_count++;
    return YES;
}

- (void)resetCPUState {
    [_contextLock lock];
    
    @try {
        if (!_context) {
            NSLog(@"[Box64Engine] CRITICAL: Cannot reset CPU state - context is NULL");
            return;
        }
        
        // 清零所有寄存器
        memset(_context->x86_regs, 0, sizeof(_context->x86_regs));
        memset(_context->arm64_regs, 0, sizeof(_context->arm64_regs));
        
        // 设置安全的栈指针
        if (_context->memory_base && _context->stack_base > 0) {
            _context->x86_regs[X86_RSP] = _context->stack_base + _context->stack_size - 16;
            _context->arm64_regs[ARM64_SP] = _context->x86_regs[X86_RSP];
        }
        
        // 设置默认标志和指令指针
        _context->rflags = 0x202;
        _context->rip = 0;
        _context->last_valid_rip = 0;
        _context->instruction_count = 0;
        
        // 清空最后指令记录
        memset(_context->last_instruction, 0, sizeof(_context->last_instruction));
        
        NSLog(@"[Box64Engine] CPU state reset safely - RSP: 0x%llx", _context->x86_regs[X86_RSP]);
        
    } @finally {
        [_contextLock unlock];
    }
}

- (void)resetToSafeState {
    [_contextLock lock];
    
    @try {
        NSLog(@"[Box64Engine] Resetting to safe state...");
        
        [self resetCPUState];
        [_safetyWarnings removeAllObjects];
        
        if (_context) {
            _context->is_in_safe_mode = YES;
            _context->instruction_count = 0;
        }
        
        _isSafeMode = YES;
        _lastError = nil;
        
        NSLog(@"[Box64Engine] Safe state reset completed");
        
    } @finally {
        [_contextLock unlock];
    }
}

#pragma mark - 内存管理 - 安全版本

- (BOOL)isValidMemoryAddress:(uint64_t)address size:(size_t)size {
    if (!_context || !_context->memory_base) {
        return NO;
    }
    
    // 检查地址范围
    uint64_t memory_start = (uint64_t)_context->memory_base;
    uint64_t memory_end = memory_start + _context->memory_size;
    
    // 防止地址溢出
    if (address < MIN_VALID_ADDRESS || address >= memory_end) {
        return NO;
    }
    
    if (size == 0 || size > _context->memory_size) {
        return NO;
    }
    
    // 检查地址+大小是否溢出
    if (address + size < address || address + size > memory_end) {
        return NO;
    }
    
    return YES;
}

- (uint8_t *)allocateMemory:(size_t)size {
    [_contextLock lock];
    
    @try {
        if (!_isInitialized || !_context) {
            NSLog(@"[Box64Engine] SECURITY: Cannot allocate - engine not initialized");
            return NULL;
        }
        
        if (size == 0 || size > _context->memory_size / 4) {
            NSLog(@"[Box64Engine] SECURITY: Invalid allocation size: %zu", size);
            return NULL;
        }
        
        // 简单的内存分配器 - 从堆基址分配
        static size_t allocated_offset = 0;
        
        // 16字节对齐
        size_t aligned_size = (size + 15) & ~15;
        
        if (allocated_offset + aligned_size > _context->heap_size) {
            NSLog(@"[Box64Engine] SECURITY: Out of heap memory");
            return NULL;
        }
        
        uint8_t *memory = (uint8_t *)_context->heap_base + allocated_offset;
        allocated_offset += aligned_size;
        
        // 清零内存
        memset(memory, 0, aligned_size);
        
        NSLog(@"[Box64Engine] Allocated %zu bytes at 0x%p", aligned_size, memory);
        return memory;
        
    } @finally {
        [_contextLock unlock];
    }
}

- (uint8_t *)allocateMemoryAt:(uint64_t)address size:(size_t)size {
    [_contextLock lock];
    
    @try {
        if (![self isValidMemoryAddress:address size:size]) {
            NSLog(@"[Box64Engine] SECURITY: Invalid memory allocation at 0x%llx size %zu", address, size);
            return NULL;
        }
        
        uint8_t *memory = (uint8_t *)address;
        memset(memory, 0, size);
        
        NSLog(@"[Box64Engine] Allocated %zu bytes at fixed address 0x%llx", size, address);
        return memory;
        
    } @finally {
        [_contextLock unlock];
    }
}

- (void)freeMemory:(uint8_t *)memory {
    [_contextLock lock];
    
    @try {
        if (!memory) {
            NSLog(@"[Box64Engine] WARNING: Attempting to free NULL pointer");
            return;
        }
        
        // 检查指针是否在有效范围内
        uint64_t addr = (uint64_t)memory;
        if (![self isValidMemoryAddress:addr size:1]) {
            NSLog(@"[Box64Engine] SECURITY: Attempting to free invalid pointer 0x%p", memory);
            return;
        }
        
        NSLog(@"[Box64Engine] Freed memory at 0x%p", memory);
        
    } @finally {
        [_contextLock unlock];
    }
}

- (BOOL)mapMemory:(uint64_t)address size:(size_t)size data:(nullable NSData *)data {
    [_contextLock lock];
    
    @try {
        if (![self isValidMemoryAddress:address size:size]) {
            NSLog(@"[Box64Engine] SECURITY: Invalid memory mapping at 0x%llx size %zu", address, size);
            return NO;
        }
        
        uint8_t *target = (uint8_t *)address;
        
        if (data) {
            size_t copy_size = MIN(size, data.length);
            memcpy(target, data.bytes, copy_size);
            NSLog(@"[Box64Engine] Mapped %zu bytes of data to 0x%llx", copy_size, address);
        } else {
            memset(target, 0, size);
            NSLog(@"[Box64Engine] Mapped %zu bytes of zeros to 0x%llx", size, address);
        }
        
        return YES;
        
    } @finally {
        [_contextLock unlock];
    }
}

#pragma mark - 寄存器操作 - 安全版本

- (uint64_t)getX86Register:(X86Register)reg {
    [_contextLock lock];
    
    @try {
        if (!_context) {
            NSLog(@"[Box64Engine] SECURITY: Cannot get register - context is NULL");
            return 0;
        }
        
        if (reg >= 16) {
            NSLog(@"[Box64Engine] SECURITY: Invalid register index %lu", (unsigned long)reg);
            return 0;
        }
        
        uint64_t value = _context->x86_regs[reg];
        
        // 检查可疑的寄存器值
        if (value > 0 && value < MIN_VALID_ADDRESS && _isSafeMode) {
            NSLog(@"[Box64Engine] WARNING: Register %lu contains suspicious low address: 0x%llx",
                  (unsigned long)reg, value);
            [_safetyWarnings addObject:[NSString stringWithFormat:@"寄存器%lu包含可疑地址0x%llx", (unsigned long)reg, value]];
        }
        
        return value;
        
    } @finally {
        [_contextLock unlock];
    }
}

- (BOOL)setX86Register:(X86Register)reg value:(uint64_t)value {
    [_contextLock lock];
    
    @try {
        if (!_context) {
            NSLog(@"[Box64Engine] SECURITY: Cannot set register - context is NULL");
            return NO;
        }
        
        if (reg >= 16) {
            NSLog(@"[Box64Engine] SECURITY: Invalid register index %lu", (unsigned long)reg);
            return NO;
        }
        
        // 验证寄存器值
        if (![self validateRegisterValue:reg value:value]) {
            NSLog(@"[Box64Engine] SECURITY: Register validation failed for %lu = 0x%llx", (unsigned long)reg, value);
            return NO;
        }
        
        _context->x86_regs[reg] = value;
        
        // 同步到ARM64寄存器
        if (reg < 16) {
            ARM64Register arm64reg = x86_to_arm64_mapping[reg];
            _context->arm64_regs[arm64reg] = value;
        }
        
        NSLog(@"[Box64Engine] Set register %lu = 0x%llx", (unsigned long)reg, value);
        return YES;
        
    } @finally {
        [_contextLock unlock];
    }
}

- (BOOL)validateRegisterValue:(X86Register)reg value:(uint64_t)value {
    if (!_isSafeMode) {
        return YES;  // 非安全模式下允许任何值
    }
    
    // 栈指针特殊检查
    if (reg == X86_RSP) {
        if (value < _context->stack_base || value >= _context->stack_base + _context->stack_size) {
            NSLog(@"[Box64Engine] SECURITY: Stack pointer 0x%llx out of stack range", value);
            return NO;
        }
    }
    
    // 检查指针类型寄存器
    if (value > 0 && value < MIN_VALID_ADDRESS) {
        NSLog(@"[Box64Engine] SECURITY: Register value 0x%llx is in dangerous low memory range", value);
        return NO;
    }
    
    // 检查是否在有效内存范围内
    if (value > MIN_VALID_ADDRESS && ![self isValidMemoryAddress:value size:1]) {
        NSLog(@"[Box64Engine] SECURITY: Register value 0x%llx points to invalid memory", value);
        return NO;
    }
    
    return YES;
}

#pragma mark - 指令执行 - 安全版本

- (BOOL)executeX86Code:(const uint8_t *)code length:(size_t)length {
    return [self executeWithSafetyCheck:code length:length maxInstructions:MAX_INSTRUCTIONS_PER_EXECUTION];
}

- (BOOL)executeWithSafetyCheck:(const uint8_t *)code length:(size_t)length maxInstructions:(uint32_t)maxInstructions {
    [_contextLock lock];
    
    @try {
        if (!_isInitialized || !_context) {
            NSLog(@"[Box64Engine] SECURITY: Engine not initialized or context is NULL");
            return NO;
        }
        
        if (!code || length == 0) {
            NSLog(@"[Box64Engine] SECURITY: Invalid code parameters");
            return NO;
        }
        
        if (length > 1024 * 1024) {  // 1MB代码限制
            NSLog(@"[Box64Engine] SECURITY: Code too large: %zu bytes", length);
            return NO;
        }
        
        NSLog(@"[Box64Engine] Executing %zu bytes of x86 code (max %u instructions)", length, maxInstructions);
        
        // 重置执行计数器
        _context->instruction_count = 0;
        _context->max_instructions = maxInstructions;
        _context->rip = 0;
        _context->last_valid_rip = 0;
        
        // 安全的执行循环
        size_t executed_bytes = 0;
        
        while (executed_bytes < length && _context->instruction_count < maxInstructions) {
            const uint8_t *current_instruction = code + executed_bytes;
            size_t remaining_bytes = length - executed_bytes;
            
            // 解码指令
            X86Instruction decoded = [self decodeInstruction:current_instruction maxLength:remaining_bytes];
            
            if (!decoded.is_valid) {
                NSLog(@"[Box64Engine] SECURITY: Invalid instruction at offset %zu", executed_bytes);
                return NO;
            }
            
            if (!decoded.is_safe && _isSafeMode) {
                NSLog(@"[Box64Engine] SECURITY: Unsafe instruction %s blocked in safe mode", decoded.mnemonic);
                return NO;
            }
            
            // 记录最后有效的RIP
            _context->last_valid_rip = _context->rip;
            memcpy(_context->last_instruction, current_instruction, MIN(decoded.length, sizeof(_context->last_instruction)));
            
            // 执行指令
            if (![self executeSingleInstruction:current_instruction]) {
                NSLog(@"[Box64Engine] SECURITY: Failed to execute instruction at offset %zu", executed_bytes);
                return NO;
            }
            
            executed_bytes += decoded.length;
            _context->instruction_count++;
            _context->rip = executed_bytes;
            
            // 执行后安全检查
            if (![self performSafetyCheck]) {
                NSLog(@"[Box64Engine] SECURITY: Safety check failed after instruction %u", _context->instruction_count);
                return NO;
            }
            
            NSLog(@"[Box64Engine] Executed instruction %u, offset %zu", _context->instruction_count, executed_bytes);
        }
        
        if (_context->instruction_count >= maxInstructions) {
            NSLog(@"[Box64Engine] INFO: Hit instruction limit %u, stopping execution", maxInstructions);
        }
        
        NSLog(@"[Box64Engine] x86 code execution completed successfully (%u instructions)", _context->instruction_count);
        return YES;
        
    } @finally {
        [_contextLock unlock];
    }
}

- (BOOL)executeSingleInstruction:(const uint8_t *)instruction {
    if (!instruction || !_context) {
        NSLog(@"[Box64Engine] SECURITY: executeSingleInstruction: invalid parameters");
        return NO;
    }
    
    X86Instruction decoded = [self decodeInstruction:instruction maxLength:16];
    
    if (!decoded.is_valid) {
        NSLog(@"[Box64Engine] SECURITY: Cannot execute invalid instruction");
        return NO;
    }
    
    NSLog(@"[Box64Engine] Executing instruction: %s (opcode 0x%02X)", decoded.mnemonic, decoded.opcode);
    
    // 生成对应的ARM64代码
    NSMutableData *arm64Code = [NSMutableData data];
    
    // 添加函数序言 - 安全版本
    uint32_t prologue[] = {
        0xA9BF7BFD,  // STP X29, X30, [SP, #-16]!
        0x910003FD   // MOV X29, SP
    };
    [arm64Code appendBytes:prologue length:sizeof(prologue)];
    
    // 根据指令类型生成ARM64代码
    switch (decoded.opcode) {
        case 0x90:  // NOP
            [self generateARM64NOP:arm64Code];
            break;
            
        case 0xB8: case 0xB9: case 0xBA: case 0xBB:  // MOV reg, imm32
        case 0xBC: case 0xBD: case 0xBE: case 0xBF:
            [self generateARM64MOVImm:arm64Code reg:(decoded.opcode & 7) immediate:decoded.immediate];
            break;
            
        case 0xC3:  // RET
            [self generateARM64Return:arm64Code];
            break;
            
        default:
            if (_isSafeMode) {
                NSLog(@"[Box64Engine] SECURITY: Unsupported opcode 0x%02X in safe mode", decoded.opcode);
                return NO;
            } else {
                NSLog(@"[Box64Engine] WARNING: Unsupported opcode 0x%02X, generating NOP", decoded.opcode);
                [self generateARM64NOP:arm64Code];
            }
            break;
    }
    
    // 添加函数尾声
    uint32_t epilogue[] = {
        0x52800000,  // MOV W0, #0
        0xA8C17BFD,  // LDP X29, X30, [SP], #16
        0xD65F03C0   // RET
    };
    [arm64Code appendBytes:epilogue length:sizeof(epilogue)];
    
    // 执行生成的ARM64代码
    return [self executeARM64Code:arm64Code];
}

#pragma mark - ARM64代码生成 - 安全版本

- (void)generateARM64NOP:(NSMutableData *)code {
    uint32_t nop = ARM64_NOP();
    [code appendBytes:&nop length:sizeof(nop)];
}

- (void)generateARM64MOVImm:(NSMutableData *)code reg:(X86Register)x86reg immediate:(int64_t)immediate {
    if (x86reg >= 16) {
        NSLog(@"[Box64Engine] SECURITY: Invalid x86 register: %lu", (unsigned long)x86reg);
        return;
    }
    
    // 安全检查立即数
    if (_isSafeMode && immediate > 0 && immediate < MIN_VALID_ADDRESS) {
        NSLog(@"[Box64Engine] SECURITY: Blocking dangerous immediate value 0x%llx", immediate);
        immediate = 0;  // 将危险值置零
    }
    
    ARM64Register arm64reg = x86_to_arm64_mapping[x86reg];
    
    uint32_t movz = ARM64_MOVZ_X(arm64reg, immediate & 0xFFFF);
    [code appendBytes:&movz length:sizeof(movz)];
    
    // 安全的寄存器状态更新
    if (_context && [self validateRegisterValue:x86reg value:(immediate & 0xFFFF)]) {
        _context->x86_regs[x86reg] = immediate & 0xFFFF;
        _context->arm64_regs[arm64reg] = immediate & 0xFFFF;
    }
    
    NSLog(@"[Box64Engine] Generated MOVZ X%d, #0x%04X", arm64reg, (uint16_t)(immediate & 0xFFFF));
}

- (void)generateARM64Return:(NSMutableData *)code {
    uint32_t ret = ARM64_RET();
    [code appendBytes:&ret length:sizeof(ret)];
}

- (BOOL)executeARM64Code:(NSData *)code {
    if (!code || code.length == 0) {
        return YES;
    }
    
    if (code.length > 4096 || !_context || !_context->jit_cache) {
        NSLog(@"[Box64Engine] SECURITY: Invalid ARM64 code execution parameters");
        return NO;
    }
    
    // 写入和执行JIT代码
    if (![_jitEngine writeCode:code.bytes size:code.length toMemory:_context->jit_cache]) {
        NSLog(@"[Box64Engine] SECURITY: Failed to write ARM64 code to JIT memory");
        return NO;
    }
    
    if (![_jitEngine makeMemoryExecutable:_context->jit_cache size:4096]) {
        NSLog(@"[Box64Engine] SECURITY: Failed to make JIT memory executable");
        return NO;
    }
    
    @try {
        NSLog(@"[Box64Engine] Executing %lu bytes of ARM64 code", (unsigned long)code.length);
        
        int result = [_jitEngine executeCode:_context->jit_cache withArgc:0 argv:NULL];
        
        NSLog(@"[Box64Engine] ARM64 execution completed with result: %d", result);
        return result >= 0;
        
    } @catch (NSException *exception) {
        NSLog(@"[Box64Engine] CRITICAL: Exception during ARM64 execution: %@", exception.reason);
        _lastError = [NSString stringWithFormat:@"ARM64执行异常: %@", exception.reason];
        
        // 记录崩溃状态用于调试
        [self dumpCrashState];
        
        return NO;
    }
}

#pragma mark - 指令解码 - 增强版本

- (X86Instruction)decodeInstruction:(const uint8_t *)instruction maxLength:(size_t)maxLength {
    X86Instruction decoded = {0};
    
    if (!instruction || maxLength == 0) {
        NSLog(@"[Box64Engine] SECURITY: decodeInstruction: invalid parameters");
        decoded.is_valid = NO;
        strcpy(decoded.mnemonic, "INVALID");
        return decoded;
    }
    
    decoded.opcode = instruction[0];
    decoded.length = 1;
    decoded.is_valid = YES;
    decoded.is_safe = YES;  // 默认安全
    
    switch (decoded.opcode) {
        case 0x90:  // NOP
            strcpy(decoded.mnemonic, "NOP");
            break;
            
        case 0xB8: case 0xB9: case 0xBA: case 0xBB:  // MOV reg, imm32
        case 0xBC: case 0xBD: case 0xBE: case 0xBF:
            if (maxLength < 5) {
                decoded.is_valid = NO;
                strcpy(decoded.mnemonic, "TRUNCATED");
                break;
            }
            decoded.has_immediate = YES;
            decoded.immediate = *(uint32_t *)(instruction + 1);
            decoded.length = 5;
            sprintf(decoded.mnemonic, "MOV r%d, 0x%X", decoded.opcode & 7, (uint32_t)decoded.immediate);
            
            // 安全检查 - 检查立即数是否是危险地址
            if (decoded.immediate > 0 && decoded.immediate < MIN_VALID_ADDRESS) {
                decoded.is_safe = NO;
            }
            break;
            
        case 0xC3:  // RET
            strcpy(decoded.mnemonic, "RET");
            break;
            
        default:
            sprintf(decoded.mnemonic, "UNK_0x%02X", decoded.opcode);
            decoded.is_safe = NO;  // 未知指令标记为不安全
            NSLog(@"[Box64Engine] WARNING: Unknown opcode: 0x%02X", decoded.opcode);
            break;
    }
    
    return decoded;
}

- (BOOL)validateInstruction:(const X86Instruction *)instruction {
    if (!instruction) {
        return NO;
    }
    
    if (!instruction->is_valid) {
        return NO;
    }
    
    if (_isSafeMode && !instruction->is_safe) {
        return NO;
    }
    
    return YES;
}

- (NSString *)disassembleInstruction:(const X86Instruction *)instruction {
    if (!instruction || !instruction->is_valid) {
        return @"INVALID";
    }
    
    return [NSString stringWithUTF8String:instruction->mnemonic];
}

#pragma mark - 安全检查

- (BOOL)performSafetyCheck {
    if (!_context) {
        return NO;
    }
    
    // 检查栈指针
    uint64_t rsp = _context->x86_regs[X86_RSP];
    if (rsp < _context->stack_base || rsp >= _context->stack_base + _context->stack_size) {
        NSLog(@"[Box64Engine] SECURITY: Stack pointer corruption detected: 0x%llx", rsp);
        [_safetyWarnings addObject:@"栈指针损坏"];
        return NO;
    }
    
    // 检查指令指针
    if (_context->rip > 0 && _context->rip < MIN_VALID_ADDRESS) {
        NSLog(@"[Box64Engine] SECURITY: Instruction pointer in dangerous range: 0x%llx", _context->rip);
        [_safetyWarnings addObject:@"指令指针在危险地址范围"];
        return NO;
    }
    
    // 检查其他重要寄存器
    for (int i = 0; i < 16; i++) {
        uint64_t value = _context->x86_regs[i];
        if (value > 0 && value < MIN_VALID_ADDRESS && value != 0x32) {  // 0x32是常见的错误地址
            NSLog(@"[Box64Engine] WARNING: Register %d contains suspicious value: 0x%llx", i, value);
            [_safetyWarnings addObject:[NSString stringWithFormat:@"寄存器%d包含可疑值0x%llx", i, value]];
        }
    }
    
    return YES;
}

- (void)enableSafeMode:(BOOL)enabled {
    [_contextLock lock];
    
    @try {
        _isSafeMode = enabled;
        if (_context) {
            _context->is_in_safe_mode = enabled;
        }
        
        NSLog(@"[Box64Engine] Safe mode %@", enabled ? @"ENABLED" : @"DISABLED");
        
    } @finally {
        [_contextLock unlock];
    }
}

- (NSArray<NSString *> *)getSafetyWarnings {
    [_contextLock lock];
    
    @try {
        return [_safetyWarnings copy];
    } @finally {
        [_contextLock unlock];
    }
}

#pragma mark - 调试和状态

- (void)dumpRegisters {
    [_contextLock lock];
    
    @try {
        if (!_context) {
            NSLog(@"[Box64Engine] Cannot dump registers: context is NULL");
            return;
        }
        
        NSLog(@"[Box64Engine] ===== CPU Registers =====");
        NSLog(@"[Box64Engine] RAX: 0x%016llX  RCX: 0x%016llX", _context->x86_regs[X86_RAX], _context->x86_regs[X86_RCX]);
        NSLog(@"[Box64Engine] RDX: 0x%016llX  RBX: 0x%016llX", _context->x86_regs[X86_RDX], _context->x86_regs[X86_RBX]);
        NSLog(@"[Box64Engine] RSP: 0x%016llX  RBP: 0x%016llX", _context->x86_regs[X86_RSP], _context->x86_regs[X86_RBP]);
        NSLog(@"[Box64Engine] RSI: 0x%016llX  RDI: 0x%016llX", _context->x86_regs[X86_RSI], _context->x86_regs[X86_RDI]);
        NSLog(@"[Box64Engine] RIP: 0x%016llX  RFLAGS: 0x%016llX", _context->rip, _context->rflags);
        NSLog(@"[Box64Engine] Instructions: %u/%u", _context->instruction_count, _context->max_instructions);
        NSLog(@"[Box64Engine] Safe Mode: %s", _context->is_in_safe_mode ? "ON" : "OFF");
        NSLog(@"[Box64Engine] ==========================");
        
    } @finally {
        [_contextLock unlock];
    }
}

- (void)dumpMemoryRegions {
    [_contextLock lock];
    
    @try {
        if (!_context) {
            NSLog(@"[Box64Engine] Cannot dump memory regions: context is NULL");
            return;
        }
        
        NSLog(@"[Box64Engine] ===== Memory Regions =====");
        NSLog(@"[Box64Engine] Memory Base: 0x%p, Size: %zu MB", _context->memory_base, _context->memory_size / (1024 * 1024));
        NSLog(@"[Box64Engine] Stack: 0x%llx-0x%llx (%llu KB)",
              _context->stack_base, _context->stack_base + _context->stack_size, _context->stack_size / 1024);
        NSLog(@"[Box64Engine] Heap: 0x%llx-0x%llx (%llu KB)",
              _context->heap_base, _context->heap_base + _context->heap_size, _context->heap_size / 1024);
        
        for (uint32_t i = 0; i < _context->region_count; i++) {
            MemoryRegion *region = &_context->memory_regions[i];
            NSLog(@"[Box64Engine] Region %u: %s at 0x%llx-0x%llx (%s%s%s)",
                  i, region->name, region->start_address, region->start_address + region->size,
                  region->is_executable ? "X" : "-",
                  region->is_writable ? "W" : "-",
                  "R");  // 总是可读
        }
        NSLog(@"[Box64Engine] ============================");
        
    } @finally {
        [_contextLock unlock];
    }
}

- (void)dumpMemory:(uint64_t)address length:(size_t)length {
    [_contextLock lock];
    
    @try {
        if (![self isValidMemoryAddress:address size:length]) {
            NSLog(@"[Box64Engine] SECURITY: Cannot dump invalid memory range 0x%llx-0x%llx", address, address + length);
            return;
        }
        
        NSLog(@"[Box64Engine] ===== Memory Dump 0x%llx =====", address);
        
        uint8_t *memory = (uint8_t *)address;
        size_t safe_length = MIN(length, 256);  // 最多显示256字节
        
        for (size_t i = 0; i < safe_length; i += 16) {
            NSMutableString *line = [NSMutableString stringWithFormat:@"[Box64Engine] %llx: ", address + i];
            
            // 十六进制
            for (size_t j = 0; j < 16 && (i + j) < safe_length; j++) {
                [line appendFormat:@"%02x ", memory[i + j]];
            }
            
            // 补齐空格
            for (size_t j = safe_length - i; j < 16; j++) {
                [line appendString:@"   "];
            }
            
            [line appendString:@" "];
            
            // ASCII
            for (size_t j = 0; j < 16 && (i + j) < safe_length; j++) {
                char c = memory[i + j];
                [line appendFormat:@"%c", (c >= 32 && c <= 126) ? c : '.'];
            }
            
            NSLog(@"%@", line);
        }
        
        NSLog(@"[Box64Engine] ================================");
        
    } @finally {
        [_contextLock unlock];
    }
}

- (void)dumpCrashState {
    NSLog(@"[Box64Engine] ===== CRASH STATE DUMP =====");
    NSLog(@"[Box64Engine] Last valid RIP: 0x%llx", _context ? _context->last_valid_rip : 0);
    NSLog(@"[Box64Engine] Current RIP: 0x%llx", _context ? _context->rip : 0);
    NSLog(@"[Box64Engine] Instruction count: %u", _context ? _context->instruction_count : 0);
    
    if (_context && _context->last_instruction[0] != 0) {
        NSLog(@"[Box64Engine] Last instruction bytes:");
        for (int i = 0; i < 8; i++) {
            NSLog(@"[Box64Engine]   [%d]: 0x%02x", i, _context->last_instruction[i]);
        }
    }
    
    [self dumpRegisters];
    [self dumpMemoryRegions];
    
    NSLog(@"[Box64Engine] Safety warnings: %@", _safetyWarnings);
    NSLog(@"[Box64Engine] Last error: %@", _lastError);
    NSLog(@"[Box64Engine] ==============================");
}

- (NSDictionary *)getSystemState {
    [_contextLock lock];
    
    @try {
        NSMutableDictionary *state = [NSMutableDictionary dictionary];
        
        state[@"initialized"] = @(_isInitialized);
        state[@"safe_mode"] = @(_isSafeMode);
        state[@"last_error"] = _lastError ?: @"无错误";
        state[@"safety_warnings"] = [_safetyWarnings copy];
        
        if (_context) {
            state[@"instruction_count"] = @(_context->instruction_count);
            state[@"max_instructions"] = @(_context->max_instructions);
            state[@"rip"] = @(_context->rip);
            state[@"rsp"] = @(_context->x86_regs[X86_RSP]);
            state[@"memory_size"] = @(_context->memory_size);
            state[@"region_count"] = @(_context->region_count);
        }
        
        return [state copy];
        
    } @finally {
        [_contextLock unlock];
    }
}

- (NSString *)getLastError {
    return _lastError;
}

#pragma mark - 清理

- (void)cleanup {
    [_contextLock lock];
    
    @try {
        if (!_isInitialized || !_context) return;
        
        NSLog(@"[Box64Engine] Cleaning up Box64 engine...");
        
        if (_context->memory_base) {
            // 恢复原始指针进行释放
            free(_context->memory_base - MEMORY_GUARD_SIZE);
            _context->memory_base = NULL;
        }
        
        if (_context->jit_cache) {
            [_jitEngine freeJITMemory:_context->jit_cache];
            _context->jit_cache = NULL;
        }
        
        [_safetyWarnings removeAllObjects];
        _lastError = nil;
        _isInitialized = NO;
        _isSafeMode = YES;
        
        NSLog(@"[Box64Engine] Box64 cleanup completed safely");
        
    } @finally {
        [_contextLock unlock];
    }
}

@end
