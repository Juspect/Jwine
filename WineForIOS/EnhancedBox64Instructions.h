// EnhancedBox64Instructions.h - 扩展的x86指令集支持
#import <Foundation/Foundation.h>
#import "Box64Engine.h"

NS_ASSUME_NONNULL_BEGIN

// 扩展指令类型枚举
typedef NS_ENUM(NSUInteger, X86ExtendedInstructionType) {
    // 基础指令
    X86_INSTR_NOP = 0x90,
    X86_INSTR_RET = 0xC3,
    
    // 数据移动指令
    X86_INSTR_MOV_REG_IMM = 0xB8,  // MOV reg, imm32 (0xB8-0xBF)
    X86_INSTR_MOV_REG_REG = 0x89,  // MOV r/m32, r32
    X86_INSTR_MOV_MEM_REG = 0x8B,  // MOV r32, r/m32
    
    // 算术指令
    X86_INSTR_ADD_REG_IMM = 0x05,  // ADD EAX, imm32
    X86_INSTR_ADD_REG_REG = 0x01,  // ADD r/m32, r32
    X86_INSTR_SUB_REG_IMM = 0x2D,  // SUB EAX, imm32
    X86_INSTR_SUB_REG_REG = 0x29,  // SUB r/m32, r32
    X86_INSTR_MUL_REG = 0xF7,      // MUL r/m32 (需要ModR/M)
    X86_INSTR_DIV_REG = 0xF7,      // DIV r/m32 (需要ModR/M)
    
    // 比较和测试指令
    X86_INSTR_CMP_REG_IMM = 0x3D,  // CMP EAX, imm32
    X86_INSTR_CMP_REG_REG = 0x39,  // CMP r/m32, r32
    X86_INSTR_TEST_REG_REG = 0x85, // TEST r/m32, r32
    
    // 跳转指令
    X86_INSTR_JMP_REL8 = 0xEB,     // JMP rel8
    X86_INSTR_JMP_REL32 = 0xE9,    // JMP rel32
    X86_INSTR_JE_REL8 = 0x74,      // JE rel8
    X86_INSTR_JNE_REL8 = 0x75,     // JNE rel8
    X86_INSTR_JL_REL8 = 0x7C,      // JL rel8
    X86_INSTR_JG_REL8 = 0x7F,      // JG rel8
    
    // 调用和返回指令
    X86_INSTR_CALL_REL32 = 0xE8,   // CALL rel32
    X86_INSTR_PUSH_REG = 0x50,     // PUSH r32 (0x50-0x57)
    X86_INSTR_POP_REG = 0x58,      // POP r32 (0x58-0x5F)
    
    // 逻辑指令
    X86_INSTR_AND_REG_REG = 0x21,  // AND r/m32, r32
    X86_INSTR_OR_REG_REG = 0x09,   // OR r/m32, r32
    X86_INSTR_XOR_REG_REG = 0x31,  // XOR r/m32, r32
    
    // 内存操作指令
    X86_INSTR_LEA = 0x8D,          // LEA r32, m
    
    // 系统指令
    X86_INSTR_INT = 0xCD,          // INT imm8
    X86_INSTR_SYSCALL = 0x0F05     // SYSCALL (2字节指令)
};

// 扩展指令解码结果
typedef struct X86ExtendedInstruction {
    X86ExtendedInstructionType type;
    uint8_t opcode;
    uint8_t modrm;
    uint8_t sib;
    uint8_t rex;              // REX前缀 (x64)
    int32_t displacement;
    int64_t immediate;
    uint8_t length;
    
    // 操作数信息
    X86Register sourceReg;
    X86Register destReg;
    BOOL hasMemoryOperand;
    uint64_t memoryAddress;
    
    // 标志位
    BOOL hasModRM;
    BOOL hasSIB;
    BOOL hasDisplacement;
    BOOL hasImmediate;
    BOOL hasREXPrefix;
} X86ExtendedInstruction;

// ARM64扩展指令编码
typedef struct ARM64ExtendedInstruction {
    uint32_t encoding;
    NSString *mnemonic;
    NSString *operands;
} ARM64ExtendedInstruction;

@interface EnhancedBox64Instructions : NSObject

// 指令解码和分析
+ (X86ExtendedInstruction)decodeInstruction:(const uint8_t *)instruction maxLength:(size_t)maxLength;
+ (BOOL)isValidInstruction:(const uint8_t *)instruction;
+ (NSString *)disassembleInstruction:(const X86ExtendedInstruction)instruction;

// ARM64代码生成
+ (NSArray<NSNumber *> *)generateARM64Code:(const X86ExtendedInstruction)x86Instruction;
+ (NSArray<NSNumber *> *)generateARM64Arithmetic:(const X86ExtendedInstruction)instruction;
+ (NSArray<NSNumber *> *)generateARM64Logic:(const X86ExtendedInstruction)instruction;
+ (NSArray<NSNumber *> *)generateARM64Memory:(const X86ExtendedInstruction)instruction;
+ (NSArray<NSNumber *> *)generateARM64Control:(const X86ExtendedInstruction)instruction;

// 寄存器映射和状态管理
+ (ARM64Register)mapX86ToARM64Register:(X86Register)x86Register;
+ (void)updateFlags:(Box64Context *)context result:(uint64_t)result operation:(NSString *)operation;

// 内存操作辅助
+ (uint64_t)calculateEffectiveAddress:(const X86ExtendedInstruction)instruction context:(Box64Context *)context;
+ (BOOL)validateMemoryAccess:(uint64_t)address size:(size_t)size context:(Box64Context *)context;

@end

NS_ASSUME_NONNULL_END
