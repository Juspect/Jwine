#import "Box64Engine.h"
#import <sys/mman.h>
#import <pthread.h>
#import <errno.h>
#import <string.h>

// 添加必要的包含和错误处理

// x86到ARM64寄存器映射
static const ARM64Register x86_to_arm64_mapping[16] = {
    ARM64_X19, // RAX -> X19
    ARM64_X20, // RCX -> X20
    ARM64_X21, // RDX -> X21
    ARM64_X22, // RBX -> X22
    ARM64_SP,  // RSP -> SP
    ARM64_X29, // RBP -> X29 (FP)
    ARM64_X23, // RSI -> X23
    ARM64_X24, // RDI -> X24
    ARM64_X25, // R8  -> X25
    ARM64_X26, // R9  -> X26
    ARM64_X27, // R10 -> X27
    ARM64_X28, // R11 -> X28
    ARM64_X12, // R12 -> X12
    ARM64_X13, // R13 -> X13
    ARM64_X14, // R14 -> X14
    ARM64_X15  // R15 -> X15
};

// ARM64指令编码辅助宏
#define ARM64_INSTR(op, rn, rt) (((op) << 16) | ((rn) << 5) | (rt))
#define ARM64_MOV_REG(rd, rn) (0xAA000000 | ((rn) << 16) | (rd))
#define ARM64_ADD_IMM(rd, rn, imm) (0x91000000 | ((imm) << 10) | ((rn) << 5) | (rd))
#define ARM64_RET() (0xD65F03C0)

@interface Box64Engine()
@property (nonatomic, assign) Box64Context *context;
@property (nonatomic, assign) BOOL isInitialized;
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
        _jitEngine = [IOSJITEngine sharedEngine];
        _context = malloc(sizeof(Box64Context));
        memset(_context, 0, sizeof(Box64Context));
    }
    return self;
}

- (void)dealloc {
    [self cleanup];
    if (_context) {
        free(_context);
    }
}

#pragma mark - 初始化和清理

- (BOOL)initializeWithMemorySize:(size_t)memorySize {
    if (_isInitialized) {
        NSLog(@"[Box64Engine] Already initialized");
        return YES;
    }
    
    NSLog(@"[Box64Engine] Initializing Box64 engine with %zu MB memory", memorySize / (1024 * 1024));
    
    // 初始化JIT引擎
    if (![_jitEngine initializeJIT]) {
        NSLog(@"[Box64Engine] Failed to initialize JIT engine");
        return NO;
    }
    
    // 分配虚拟内存空间
    _context->memory_base = malloc(memorySize);
    if (!_context->memory_base) {
        NSLog(@"[Box64Engine] Failed to allocate memory");
        return NO;
    }
    _context->memory_size = memorySize;
    memset(_context->memory_base, 0, memorySize);
    
    // 分配JIT缓存
    _context->jit_cache = [_jitEngine allocateJITMemory:1024 * 1024]; // 1MB JIT缓存
    if (!_context->jit_cache) {
        NSLog(@"[Box64Engine] Failed to allocate JIT cache");
        free(_context->memory_base);
        return NO;
    }
    
    // 初始化寄存器状态
    [self resetCPUState];
    
    _isInitialized = YES;
    NSLog(@"[Box64Engine] Box64 engine initialized successfully");
    return YES;
}

- (void)cleanup {
    if (!_isInitialized) return;
    
    NSLog(@"[Box64Engine] Cleaning up Box64 engine...");
    
    if (_context->memory_base) {
        free(_context->memory_base);
        _context->memory_base = NULL;
    }
    
    if (_context->jit_cache) {
        [_jitEngine freeJITMemory:_context->jit_cache];
        _context->jit_cache = NULL;
    }
    
    _isInitialized = NO;
    NSLog(@"[Box64Engine] Box64 cleanup completed");
}

- (void)resetCPUState {
    // 清零所有寄存器
    memset(_context->x86_regs, 0, sizeof(_context->x86_regs));
    memset(_context->arm64_regs, 0, sizeof(_context->arm64_regs));
    
    // 设置栈指针 (假设栈在内存顶部)
    _context->x86_regs[X86_RSP] = (uint64_t)_context->memory_base + _context->memory_size - 4096;
    _context->arm64_regs[ARM64_SP] = _context->x86_regs[X86_RSP];
    
    // 设置默认标志
    _context->rflags = 0x202;  // IF (中断使能) + 保留位
    
    NSLog(@"[Box64Engine] CPU state reset, stack at 0x%llx", _context->x86_regs[X86_RSP]);
}

#pragma mark - 内存管理

- (uint8_t *)allocateMemory:(size_t)size {
    if (!_isInitialized) {
        NSLog(@"[Box64Engine] Engine not initialized");
        return NULL;
    }
    
    // 简单的内存分配器 (在实际实现中需要更复杂的管理)
    static size_t allocated_offset = 0;
    
    if (allocated_offset + size > _context->memory_size) {
        NSLog(@"[Box64Engine] Out of memory");
        return NULL;
    }
    
    uint8_t *memory = _context->memory_base + allocated_offset;
    allocated_offset += (size + 15) & ~15;  // 16字节对齐
    
    NSLog(@"[Box64Engine] Allocated %zu bytes at offset 0x%zx", size, (size_t)(memory - _context->memory_base));
    return memory;
}

- (void)freeMemory:(uint8_t *)memory {
    // 简单实现：标记为已释放 (实际实现需要内存管理器)
    NSLog(@"[Box64Engine] Memory freed at %p", memory);
}

- (BOOL)mapMemory:(uint64_t)address size:(size_t)size data:(nullable NSData *)data {
    if (address >= _context->memory_size || address + size > _context->memory_size) {
        NSLog(@"[Box64Engine] Invalid memory mapping range");
        return NO;
    }
    
    uint8_t *target = _context->memory_base + address;
    
    if (data) {
        memcpy(target, data.bytes, MIN(size, data.length));
        NSLog(@"[Box64Engine] Mapped %zu bytes to 0x%llx", data.length, address);
    } else {
        memset(target, 0, size);
        NSLog(@"[Box64Engine] Zeroed %zu bytes at 0x%llx", size, address);
    }
    
    return YES;
}

#pragma mark - 指令解码

- (X86Instruction)decodeInstruction:(const uint8_t *)instruction {
    X86Instruction decoded = {0};
    const uint8_t *ptr = instruction;
    
    // 简化的x86指令解码器
    // 在实际实现中需要完整的x86解码表
    
    // 跳过前缀
    while (*ptr == 0x66 || *ptr == 0x67 || *ptr == 0xF2 || *ptr == 0xF3) {
        ptr++;
    }
    
    // REX前缀 (64位模式)
    if ((*ptr & 0xF0) == 0x40) {
        ptr++;
    }
    
    // 操作码
    decoded.opcode = *ptr++;
    decoded.length = ptr - instruction;
    
    // 检查是否需要ModR/M字节
    if ([self opcodeNeedsModRM:decoded.opcode]) {
        decoded.has_modrm = YES;
        decoded.modrm = *ptr++;
        decoded.length++;
        
        // 检查是否需要SIB字节
        uint8_t mod = (decoded.modrm >> 6) & 3;
        uint8_t rm = decoded.modrm & 7;
        
        if (mod != 3 && rm == 4) {
            decoded.has_sib = YES;
            decoded.sib = *ptr++;
            decoded.length++;
        }
        
        // 检查位移
        if (mod == 1) {
            decoded.has_displacement = YES;
            decoded.displacement = (int8_t)*ptr++;
            decoded.length++;
        } else if (mod == 2 || (mod == 0 && rm == 5)) {
            decoded.has_displacement = YES;
            decoded.displacement = *(int32_t *)ptr;
            ptr += 4;
            decoded.length += 4;
        }
    }
    
    // 检查立即数 (简化处理)
    if ([self opcodeHasImmediate:decoded.opcode]) {
        decoded.has_immediate = YES;
        // 根据操作码确定立即数大小 (这里简化为32位)
        decoded.immediate = *(int32_t *)ptr;
        ptr += 4;
        decoded.length += 4;
    }
    
    return decoded;
}

- (BOOL)opcodeNeedsModRM:(uint8_t)opcode {
    // 简化的ModR/M需求检查
    static uint8_t modrm_opcodes[] = {
        0x01, 0x03, 0x05, 0x07, 0x09, 0x0B, 0x0D, 0x0F,
        0x11, 0x13, 0x15, 0x17, 0x19, 0x1B, 0x1D, 0x1F,
        0x21, 0x23, 0x25, 0x27, 0x29, 0x2B, 0x2D, 0x2F,
        0x31, 0x33, 0x35, 0x37, 0x39, 0x3B, 0x3D, 0x3F,
        0x63, 0x69, 0x6B, 0x8B, 0x89, 0xFF
    };
    
    for (size_t i = 0; i < sizeof(modrm_opcodes); i++) {
        if (opcode == modrm_opcodes[i]) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)opcodeHasImmediate:(uint8_t)opcode {
    // 简化的立即数检查
    switch (opcode) {
        case 0xB8: case 0xB9: case 0xBA: case 0xBB:  // MOV reg, imm32
        case 0xBC: case 0xBD: case 0xBE: case 0xBF:
        case 0xC7:  // MOV r/m32, imm32
        case 0x68:  // PUSH imm32
        case 0x05:  // ADD EAX, imm32
            return YES;
        default:
            return NO;
    }
}

#pragma mark - 指令翻译和执行

- (BOOL)executeX86Code:(const uint8_t *)code length:(size_t)length {
    if (!_isInitialized) {
        NSLog(@"[Box64Engine] Engine not initialized");
        return NO;
    }
    
    NSLog(@"[Box64Engine] Executing %zu bytes of x86 code", length);
    
    // 将x86代码复制到虚拟内存
    uint8_t *vmem = [self allocateMemory:length];
    if (!vmem) {
        return NO;
    }
    memcpy(vmem, code, length);
    
    // 设置执行起始点
    _context->rip = (uint64_t)(vmem - _context->memory_base);
    
    // 执行指令循环
    size_t executed_bytes = 0;
    while (executed_bytes < length) {
        const uint8_t *current_instruction = _context->memory_base + _context->rip;
        
        if (![self executeSingleInstruction:current_instruction]) {
            NSLog(@"[Box64Engine] Failed to execute instruction at RIP=0x%llx", _context->rip);
            return NO;
        }
        
        executed_bytes = _context->rip - (uint64_t)(vmem - _context->memory_base);
        
        // 防止无限循环
        if (executed_bytes > length * 2) {
            NSLog(@"[Box64Engine] Execution exceeded expected length, breaking");
            break;
        }
    }
    
    NSLog(@"[Box64Engine] x86 code execution completed");
    return YES;
}

- (BOOL)executeSingleInstruction:(const uint8_t *)instruction {
    X86Instruction decoded = [self decodeInstruction:instruction];
    
    NSLog(@"[Box64Engine] Executing opcode 0x%02X", decoded.opcode);
    
    // 生成对应的ARM64代码
    NSMutableData *arm64Code = [NSMutableData data];
    
    switch (decoded.opcode) {
        case 0x90:  // NOP
            [self generateARM64NOP:arm64Code];
            break;
            
        case 0xB8: case 0xB9: case 0xBA: case 0xBB:  // MOV reg, imm32
        case 0xBC: case 0xBD: case 0xBE: case 0xBF:
            [self generateARM64MOVImm:arm64Code reg:(decoded.opcode & 7) immediate:decoded.immediate];
            break;
            
        case 0x05:  // ADD EAX, imm32
            [self generateARM64ADDImm:arm64Code reg:X86_RAX immediate:decoded.immediate];
            break;
            
        case 0xC3:  // RET
            [self generateARM64RET:arm64Code];
            break;
            
        default:
            NSLog(@"[Box64Engine] Unsupported opcode: 0x%02X", decoded.opcode);
            return NO;
    }
    
    // 执行生成的ARM64代码
    if (![self executeARM64Code:arm64Code]) {
        return NO;
    }
    
    // 更新指令指针
    _context->rip += decoded.length;
    
    return YES;
}

#pragma mark - ARM64代码生成

- (void)generateARM64NOP:(NSMutableData *)code {
    uint32_t nop = 0xD503201F;  // ARM64 NOP
    [code appendBytes:&nop length:sizeof(nop)];
}

- (void)generateARM64MOVImm:(NSMutableData *)code reg:(X86Register)x86reg immediate:(int64_t)immediate {
    ARM64Register arm64reg = x86_to_arm64_mapping[x86reg];
    
    // MOV Xd, #immediate (使用MOVZ指令)
    uint32_t movz = 0xD2800000 | ((immediate & 0xFFFF) << 5) | arm64reg;
    [code appendBytes:&movz length:sizeof(movz)];
    
    // 更新x86寄存器状态
    _context->x86_regs[x86reg] = immediate;
    _context->arm64_regs[arm64reg] = immediate;
}

- (void)generateARM64ADDImm:(NSMutableData *)code reg:(X86Register)x86reg immediate:(int64_t)immediate {
    ARM64Register arm64reg = x86_to_arm64_mapping[x86reg];
    
    // ADD Xd, Xd, #immediate
    uint32_t add = 0x91000000 | ((immediate & 0xFFF) << 10) | (arm64reg << 5) | arm64reg;
    [code appendBytes:&add length:sizeof(add)];
    
    // 更新x86寄存器状态
    _context->x86_regs[x86reg] += immediate;
    _context->arm64_regs[arm64reg] = _context->x86_regs[x86reg];
}

- (void)generateARM64RET:(NSMutableData *)code {
    uint32_t ret = ARM64_RET();
    [code appendBytes:&ret length:sizeof(ret)];
}

- (BOOL)executeARM64Code:(NSData *)code {
    if (!code || code.length == 0) {
        return YES;  // 空代码认为成功
    }
    
    // 写入JIT内存
    if (![_jitEngine writeCode:code.bytes size:code.length toMemory:_context->jit_cache]) {
        NSLog(@"[Box64Engine] Failed to write ARM64 code to JIT memory");
        return NO;
    }
    
    // 执行JIT代码
    int result = [_jitEngine executeCode:_context->jit_cache withArgc:0 argv:NULL];
    
    return result >= 0;
}

#pragma mark - 寄存器操作

- (uint64_t)getX86Register:(X86Register)reg {
    if (reg >= 16) return 0;
    return _context->x86_regs[reg];
}

- (void)setX86Register:(X86Register)reg value:(uint64_t)value {
    if (reg >= 16) return;
    _context->x86_regs[reg] = value;
    
    // 同步到ARM64寄存器
    ARM64Register arm64reg = x86_to_arm64_mapping[reg];
    _context->arm64_regs[arm64reg] = value;
}

#pragma mark - 调试和状态

- (void)dumpRegisters {
    NSLog(@"[Box64Engine] ===== CPU Registers =====");
    NSLog(@"[Box64Engine] RAX: 0x%016llX  RCX: 0x%016llX", _context->x86_regs[X86_RAX], _context->x86_regs[X86_RCX]);
    NSLog(@"[Box64Engine] RDX: 0x%016llX  RBX: 0x%016llX", _context->x86_regs[X86_RDX], _context->x86_regs[X86_RBX]);
    NSLog(@"[Box64Engine] RSP: 0x%016llX  RBP: 0x%016llX", _context->x86_regs[X86_RSP], _context->x86_regs[X86_RBP]);
    NSLog(@"[Box64Engine] RSI: 0x%016llX  RDI: 0x%016llX", _context->x86_regs[X86_RSI], _context->x86_regs[X86_RDI]);
    NSLog(@"[Box64Engine] RIP: 0x%016llX  RFLAGS: 0x%016llX", _context->rip, _context->rflags);
    NSLog(@"[Box64Engine] ==========================");
}

- (void)dumpMemory:(uint64_t)address length:(size_t)length {
    if (address >= _context->memory_size) {
        NSLog(@"[Box64Engine] Invalid memory address: 0x%llx", address);
        return;
    }
    
    NSLog(@"[Box64Engine] Memory dump at 0x%llx (%zu bytes):", address, length);
    
    uint8_t *memory = _context->memory_base + address;
    for (size_t i = 0; i < length && (address + i) < _context->memory_size; i += 16) {
        NSMutableString *hex = [NSMutableString string];
        NSMutableString *ascii = [NSMutableString string];
        
        for (size_t j = 0; j < 16 && (i + j) < length; j++) {
            uint8_t byte = memory[i + j];
            [hex appendFormat:@"%02X ", byte];
            [ascii appendFormat:@"%c", (byte >= 32 && byte < 127) ? byte : '.'];
        }
        
        NSLog(@"[Box64Engine] %016llX: %-48s %@", address + i, hex.UTF8String, ascii);
    }
}

- (NSString *)disassembleInstruction:(const uint8_t *)instruction {
    X86Instruction decoded = [self decodeInstruction:instruction];
    
    NSMutableString *result = [NSMutableString string];
    
    switch (decoded.opcode) {
        case 0x90:
            [result appendString:@"nop"];
            break;
        case 0xB8: case 0xB9: case 0xBA: case 0xBB:
        case 0xBC: case 0xBD: case 0xBE: case 0xBF:
            [result appendFormat:@"mov r%d, 0x%llx", decoded.opcode & 7, decoded.immediate];
            break;
        case 0x05:
            [result appendFormat:@"add eax, 0x%llx", decoded.immediate];
            break;
        case 0xC3:
            [result appendString:@"ret"];
            break;
        default:
            [result appendFormat:@"unknown (0x%02X)", decoded.opcode];
            break;
    }
    
    return result;
}

@end
