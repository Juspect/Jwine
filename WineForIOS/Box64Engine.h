#import <Foundation/Foundation.h>
#import "IOSJITEngine.h"

NS_ASSUME_NONNULL_BEGIN

// x86寄存器定义
typedef NS_ENUM(NSUInteger, X86Register) {
    X86_RAX = 0, X86_RCX, X86_RDX, X86_RBX,
    X86_RSP, X86_RBP, X86_RSI, X86_RDI,
    X86_R8,  X86_R9,  X86_R10, X86_R11,
    X86_R12, X86_R13, X86_R14, X86_R15
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

// CPU执行上下文
typedef struct Box64Context {
    uint64_t x86_regs[16];      // x86寄存器状态
    uint64_t arm64_regs[32];    // ARM64寄存器状态
    uint64_t rip;               // 指令指针
    uint64_t rflags;            // 标志寄存器
    uint8_t *memory_base;       // 内存基址
    size_t memory_size;         // 内存大小
    void *jit_cache;           // JIT缓存
} Box64Context;

// 指令解码结果
typedef struct X86Instruction {
    uint8_t opcode;            // 操作码
    uint8_t modrm;             // ModR/M字节
    uint8_t sib;               // SIB字节
    int32_t displacement;      // 位移
    int64_t immediate;         // 立即数
    uint8_t length;            // 指令长度
    BOOL has_modrm;            // 是否有ModR/M
    BOOL has_sib;              // 是否有SIB
    BOOL has_displacement;     // 是否有位移
    BOOL has_immediate;        // 是否有立即数
} X86Instruction;

@interface Box64Engine : NSObject

@property (nonatomic, readonly) Box64Context *context;
@property (nonatomic, readonly) BOOL isInitialized;
@property (nonatomic, strong) IOSJITEngine *jitEngine;

+ (instancetype)sharedEngine;

// 初始化和清理
- (BOOL)initializeWithMemorySize:(size_t)memorySize;
- (void)cleanup;

// 内存管理
- (uint8_t *)allocateMemory:(size_t)size;
- (void)freeMemory:(uint8_t *)memory;
- (BOOL)mapMemory:(uint64_t)address size:(size_t)size data:(nullable NSData *)data;

// 指令执行
- (BOOL)executeX86Code:(const uint8_t *)code length:(size_t)length;
- (BOOL)executeSingleInstruction:(const uint8_t *)instruction;

// 寄存器操作
- (uint64_t)getX86Register:(X86Register)reg;
- (void)setX86Register:(X86Register)reg value:(uint64_t)value;

// 调试和状态
- (void)dumpRegisters;
- (void)dumpMemory:(uint64_t)address length:(size_t)length;
- (NSString *)disassembleInstruction:(const uint8_t *)instruction;

@end

NS_ASSUME_NONNULL_END
