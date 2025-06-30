// Box64Engine.h - 完整的头文件声明
#import <Foundation/Foundation.h>
#import "IOSJITEngine.h"

NS_ASSUME_NONNULL_BEGIN

// 内存安全常量
#define MEMORY_GUARD_SIZE 4096
#define MAX_INSTRUCTIONS_PER_EXECUTION 1000
#define MIN_VALID_ADDRESS 0x1000
#define MAX_MEMORY_SIZE (256 * 1024 * 1024)  // 256MB最大内存

// 🔧 修复：x86寄存器定义 - 确保 X86_RIP 正确定义
typedef NS_ENUM(NSUInteger, X86Register) {
    X86_RAX = 0, X86_RCX, X86_RDX, X86_RBX,
    X86_RSP, X86_RBP, X86_RSI, X86_RDI,
    X86_R8,  X86_R9,  X86_R10, X86_R11,
    X86_R12, X86_R13, X86_R14, X86_R15,
    X86_RIP = 16  // 🔧 明确指定 RIP 的值
};

// ARM64寄存器定义
typedef NS_ENUM(NSUInteger, ARM64Register) {
    ARM64_X0 = 0,  ARM64_X1,  ARM64_X2,  ARM64_X3,
    ARM64_X4,  ARM64_X5,  ARM64_X6,  ARM64_X7,
    ARM64_X8,  ARM64_X9,  ARM64_X10, ARM64_X11,
    ARM64_X12, ARM64_X13, ARM64_X14, ARM64_X15,
    ARM64_X16, ARM64_X17, ARM64_X18, ARM64_X19,
    ARM64_X20, ARM64_X21, ARM64_X22, ARM64_X23,
    ARM64_X24, ARM64_X25, ARM64_X26, ARM64_X27,
    ARM64_X28, ARM64_X29, ARM64_X30, ARM64_SP = 31
};

// 内存区域结构
typedef struct MemoryRegion {
    uint64_t start_address;
    uint64_t size;
    BOOL is_allocated;
    BOOL is_executable;
    BOOL is_writable;
    char name[64];
} MemoryRegion;

// CPU执行上下文 - 增强版
typedef struct Box64Context {
    uint64_t x86_regs[16];              // x86寄存器状态
    uint64_t arm64_regs[32];            // ARM64寄存器状态
    uint64_t rip;                       // 指令指针
    uint64_t rflags;                    // 标志寄存器
    uint8_t *memory_base;               // 内存基址
    size_t memory_size;                 // 内存大小
    void *jit_cache;                   // JIT缓存
    
    // 内存安全增强
    MemoryRegion memory_regions[32];    // 内存区域记录
    uint32_t region_count;              // 区域数量
    uint64_t stack_base;                // 栈基址
    uint64_t stack_size;                // 栈大小
    uint64_t heap_base;                 // 堆基址
    uint64_t heap_size;                 // 堆大小
    
    // 执行安全
    uint32_t instruction_count;         // 已执行指令数
    uint32_t max_instructions;          // 最大指令数限制
    BOOL is_in_safe_mode;              // 安全模式标志
    
    // 调试信息
    uint64_t last_valid_rip;           // 最后有效的RIP
    char last_instruction[16];          // 最后执行的指令
} Box64Context;

// 指令解码结果 - 增强版
typedef struct X86Instruction {
    uint8_t opcode;                    // 操作码
    uint8_t modrm;                     // ModR/M字节
    uint8_t sib;                       // SIB字节
    int32_t displacement;              // 位移
    int64_t immediate;                 // 立即数
    uint8_t length;                    // 指令长度
    BOOL has_modrm;                    // 是否有ModR/M
    BOOL has_sib;                      // 是否有SIB
    BOOL has_displacement;             // 是否有位移
    BOOL has_immediate;                // 是否有立即数
    
    // 安全检查
    BOOL is_valid;                     // 指令是否有效
    BOOL is_safe;                      // 指令是否安全
    char mnemonic[32];                 // 助记符
} X86Instruction;

@interface Box64Engine : NSObject

@property (nonatomic, readonly) Box64Context *context;
@property (nonatomic, readonly) BOOL isInitialized;
@property (nonatomic, readonly) BOOL isSafeMode;
@property (nonatomic, strong) IOSJITEngine *jitEngine;

+ (instancetype)sharedEngine;

// 初始化和清理
- (BOOL)initializeWithMemorySize:(size_t)memorySize;
- (BOOL)initializeWithMemorySize:(size_t)memorySize safeMode:(BOOL)safeMode;
- (void)cleanup;
- (void)resetToSafeState;

// 内存管理 - 安全版本
- (uint8_t *)allocateMemory:(size_t)size;
- (uint8_t *)allocateMemoryAt:(uint64_t)address size:(size_t)size;
- (void)freeMemory:(uint8_t *)memory;
- (BOOL)isValidMemoryAddress:(uint64_t)address size:(size_t)size;
- (BOOL)mapMemory:(uint64_t)address size:(size_t)size data:(nullable NSData *)data;
- (BOOL)unmapMemory:(uint64_t)address size:(size_t)size;
- (BOOL)protectMemory:(uint64_t)address size:(size_t)size executable:(BOOL)executable writable:(BOOL)writable;

// 🔧 修复：指令执行 - 完整的方法声明
- (BOOL)executeX86Code:(const uint8_t *)code length:(size_t)length;
- (BOOL)executeSingleInstruction:(const uint8_t *)instruction;
- (BOOL)executeWithSafetyCheck:(const uint8_t *)code length:(size_t)length maxInstructions:(uint32_t)maxInstructions;
- (BOOL)executeWithSafetyCheck:(const uint8_t *)code length:(size_t)length maxInstructions:(uint32_t)maxInstructions baseAddress:(uint64_t)baseAddress;

// 🔧 修复：新增的简化执行方法
- (BOOL)executeX86CodeSimplified:(const uint8_t *)code length:(size_t)length maxInstructions:(uint32_t)maxInstructions baseAddress:(uint64_t)baseAddress;
- (BOOL)simulateInstructionExecution:(const X86Instruction *)instruction;

// 寄存器操作 - 安全版本
- (uint64_t)getX86Register:(X86Register)reg;
- (BOOL)setX86Register:(X86Register)reg value:(uint64_t)value;
- (BOOL)validateRegisterValue:(X86Register)reg value:(uint64_t)value;
- (BOOL)setX86RegisterImmediate:(X86Register)reg value:(uint64_t)value;

// 指令解码 - 增强版本
- (X86Instruction)decodeInstruction:(const uint8_t *)instruction maxLength:(size_t)maxLength;
- (BOOL)validateInstruction:(const X86Instruction *)instruction;
- (NSString *)disassembleInstruction:(const X86Instruction *)instruction;

// 调试和状态
- (void)dumpRegisters;
- (void)dumpMemoryRegions;
- (void)dumpMemory:(uint64_t)address length:(size_t)length;
- (NSDictionary *)getSystemState;
- (NSString *)getLastError;

// 🔧 修复：安全检查 - 完整的方法声明
- (BOOL)performSafetyCheck;
- (BOOL)performSafetyCheckWithRIP:(uint64_t)rip;
- (void)enableSafeMode:(BOOL)enabled;
- (NSArray<NSString *> *)getSafetyWarnings;

@end

NS_ASSUME_NONNULL_END
