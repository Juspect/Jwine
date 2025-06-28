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

// EnhancedBox64Instructions.m - 实现
@implementation EnhancedBox64Instructions

#pragma mark - 指令解码

+ (X86ExtendedInstruction)decodeInstruction:(const uint8_t *)instruction maxLength:(size_t)maxLength {
    X86ExtendedInstruction decoded = {0};
    if (!instruction || maxLength == 0) {
        return decoded;
    }
    
    size_t pos = 0;
    
    // 检查REX前缀 (x64)
    if (maxLength > pos && (instruction[pos] & 0xF0) == 0x40) {
        decoded.rex = instruction[pos];
        decoded.hasREXPrefix = YES;
        pos++;
    }
    
    if (pos >= maxLength) return decoded;
    
    decoded.opcode = instruction[pos];
    decoded.length = pos + 1;
    
    // 根据操作码确定指令类型
    switch (decoded.opcode) {
        case X86_INSTR_NOP:
            decoded.type = X86_INSTR_NOP;
            break;
            
        case X86_INSTR_RET:
            decoded.type = X86_INSTR_RET;
            break;
            
        case 0xB8 ... 0xBF:  // MOV reg, imm32
            decoded.type = X86_INSTR_MOV_REG_IMM;
            decoded.destReg = (X86Register)(decoded.opcode - 0xB8);
            if (maxLength >= pos + 5) {
                decoded.immediate = *(uint32_t *)(instruction + pos + 1);
                decoded.hasImmediate = YES;
                decoded.length = pos + 5;
            }
            break;
            
        case X86_INSTR_ADD_REG_IMM:  // ADD EAX, imm32
            decoded.type = X86_INSTR_ADD_REG_IMM;
            decoded.destReg = X86_RAX;
            if (maxLength >= pos + 5) {
                decoded.immediate = *(uint32_t *)(instruction + pos + 1);
                decoded.hasImmediate = YES;
                decoded.length = pos + 5;
            }
            break;
            
        case X86_INSTR_SUB_REG_IMM:  // SUB EAX, imm32
            decoded.type = X86_INSTR_SUB_REG_IMM;
            decoded.destReg = X86_RAX;
            if (maxLength >= pos + 5) {
                decoded.immediate = *(uint32_t *)(instruction + pos + 1);
                decoded.hasImmediate = YES;
                decoded.length = pos + 5;
            }
            break;
            
        case X86_INSTR_CMP_REG_IMM:  // CMP EAX, imm32
            decoded.type = X86_INSTR_CMP_REG_IMM;
            decoded.destReg = X86_RAX;
            if (maxLength >= pos + 5) {
                decoded.immediate = *(uint32_t *)(instruction + pos + 1);
                decoded.hasImmediate = YES;
                decoded.length = pos + 5;
            }
            break;
            
        case X86_INSTR_JMP_REL8:  // JMP rel8
            decoded.type = X86_INSTR_JMP_REL8;
            if (maxLength >= pos + 2) {
                decoded.immediate = (int8_t)instruction[pos + 1];
                decoded.hasImmediate = YES;
                decoded.length = pos + 2;
            }
            break;
            
        case X86_INSTR_JE_REL8:   // JE rel8
        case X86_INSTR_JNE_REL8:  // JNE rel8
        case X86_INSTR_JL_REL8:   // JL rel8
        case X86_INSTR_JG_REL8:   // JG rel8
            decoded.type = (X86ExtendedInstructionType)decoded.opcode;
            if (maxLength >= pos + 2) {
                decoded.immediate = (int8_t)instruction[pos + 1];
                decoded.hasImmediate = YES;
                decoded.length = pos + 2;
            }
            break;
            
        case 0x50 ... 0x57:  // PUSH reg
            decoded.type = X86_INSTR_PUSH_REG;
            decoded.sourceReg = (X86Register)(decoded.opcode - 0x50);
            break;
            
        case 0x58 ... 0x5F:  // POP reg
            decoded.type = X86_INSTR_POP_REG;
            decoded.destReg = (X86Register)(decoded.opcode - 0x58);
            break;
            
        case X86_INSTR_CALL_REL32:  // CALL rel32
            decoded.type = X86_INSTR_CALL_REL32;
            if (maxLength >= pos + 5) {
                decoded.immediate = *(int32_t *)(instruction + pos + 1);
                decoded.hasImmediate = YES;
                decoded.length = pos + 5;
            }
            break;
            
        case X86_INSTR_INT:  // INT imm8
            decoded.type = X86_INSTR_INT;
            if (maxLength >= pos + 2) {
                decoded.immediate = instruction[pos + 1];
                decoded.hasImmediate = YES;
                decoded.length = pos + 2;
            }
            break;
            
        default:
            // 需要ModR/M字节的指令
            if (maxLength > pos + 1) {
                decoded.modrm = instruction[pos + 1];
                decoded.hasModRM = YES;
                decoded.length = pos + 2;
                
                // 解析ModR/M字节
                uint8_t mod = (decoded.modrm >> 6) & 0x03;
                uint8_t reg = (decoded.modrm >> 3) & 0x07;
                uint8_t rm = decoded.modrm & 0x07;
                
                decoded.sourceReg = (X86Register)reg;
                decoded.destReg = (X86Register)rm;
                
                // 根据mod字段确定是否有位移
                if (mod == 0x01 && maxLength >= decoded.length + 1) {
                    decoded.displacement = (int8_t)instruction[decoded.length];
                    decoded.hasDisplacement = YES;
                    decoded.length++;
                } else if (mod == 0x02 && maxLength >= decoded.length + 4) {
                    decoded.displacement = *(int32_t *)(instruction + decoded.length);
                    decoded.hasDisplacement = YES;
                    decoded.length += 4;
                }
            }
            break;
    }
    
    return decoded;
}

+ (BOOL)isValidInstruction:(const uint8_t *)instruction {
    if (!instruction) return NO;
    
    uint8_t opcode = instruction[0];
    
    // 检查是否为已知指令
    switch (opcode) {
        case X86_INSTR_NOP:
        case X86_INSTR_RET:
        case 0xB8 ... 0xBF:  // MOV reg, imm
        case X86_INSTR_ADD_REG_IMM:
        case X86_INSTR_SUB_REG_IMM:
        case X86_INSTR_CMP_REG_IMM:
        case X86_INSTR_JMP_REL8:
        case X86_INSTR_JE_REL8:
        case X86_INSTR_JNE_REL8:
        case 0x50 ... 0x5F:  // PUSH/POP reg
        case X86_INSTR_CALL_REL32:
        case X86_INSTR_INT:
            return YES;
        default:
            return NO;
    }
}

+ (NSString *)disassembleInstruction:(const X86ExtendedInstruction)instruction {
    switch (instruction.type) {
        case X86_INSTR_NOP:
            return @"nop";
        case X86_INSTR_RET:
            return @"ret";
        case X86_INSTR_MOV_REG_IMM:
            return [NSString stringWithFormat:@"mov %@, 0x%llx",
                    [self registerName:instruction.destReg], instruction.immediate];
        case X86_INSTR_ADD_REG_IMM:
            return [NSString stringWithFormat:@"add eax, 0x%llx", instruction.immediate];
        case X86_INSTR_SUB_REG_IMM:
            return [NSString stringWithFormat:@"sub eax, 0x%llx", instruction.immediate];
        case X86_INSTR_CMP_REG_IMM:
            return [NSString stringWithFormat:@"cmp eax, 0x%llx", instruction.immediate];
        case X86_INSTR_JMP_REL8:
            return [NSString stringWithFormat:@"jmp +%lld", instruction.immediate];
        case X86_INSTR_JE_REL8:
            return [NSString stringWithFormat:@"je +%lld", instruction.immediate];
        case X86_INSTR_JNE_REL8:
            return [NSString stringWithFormat:@"jne +%lld", instruction.immediate];
        case X86_INSTR_PUSH_REG:
            return [NSString stringWithFormat:@"push %@", [self registerName:instruction.sourceReg]];
        case X86_INSTR_POP_REG:
            return [NSString stringWithFormat:@"pop %@", [self registerName:instruction.destReg]];
        case X86_INSTR_CALL_REL32:
            return [NSString stringWithFormat:@"call +%lld", instruction.immediate];
        case X86_INSTR_INT:
            return [NSString stringWithFormat:@"int 0x%llx", instruction.immediate];
        default:
            return [NSString stringWithFormat:@"unknown (0x%02x)", instruction.opcode];
    }
}

+ (NSString *)registerName:(X86Register)reg {
    switch (reg) {
        case X86_RAX: return @"eax";
        case X86_RCX: return @"ecx";
        case X86_RDX: return @"edx";
        case X86_RBX: return @"ebx";
        case X86_RSP: return @"esp";
        case X86_RBP: return @"ebp";
        case X86_RSI: return @"esi";
        case X86_RDI: return @"edi";
        default: return [NSString stringWithFormat:@"r%d", (int)reg];
    }
}

#pragma mark - ARM64代码生成

+ (NSArray<NSNumber *> *)generateARM64Code:(const X86ExtendedInstruction)x86Instruction {
    switch (x86Instruction.type) {
        case X86_INSTR_NOP:
            return @[@(0xD503201F)];  // NOP
            
        case X86_INSTR_RET:
            return @[@(0xD65F03C0)];  // RET
            
        case X86_INSTR_MOV_REG_IMM:
            return [self generateARM64MovImmediate:x86Instruction];
            
        case X86_INSTR_ADD_REG_IMM:
        case X86_INSTR_SUB_REG_IMM:
            return [self generateARM64Arithmetic:x86Instruction];
            
        case X86_INSTR_CMP_REG_IMM:
            return [self generateARM64Compare:x86Instruction];
            
        case X86_INSTR_JMP_REL8:
        case X86_INSTR_JE_REL8:
        case X86_INSTR_JNE_REL8:
        case X86_INSTR_JL_REL8:
        case X86_INSTR_JG_REL8:
            return [self generateARM64Branch:x86Instruction];
            
        case X86_INSTR_PUSH_REG:
        case X86_INSTR_POP_REG:
            return [self generateARM64Stack:x86Instruction];
            
        case X86_INSTR_CALL_REL32:
            return [self generateARM64Call:x86Instruction];
            
        case X86_INSTR_INT:
            return [self generateARM64Interrupt:x86Instruction];
            
        default:
            NSLog(@"[EnhancedBox64Instructions] Unsupported instruction type: %lu", (unsigned long)x86Instruction.type);
            return @[@(0xD503201F)];  // NOP as fallback
    }
}

+ (NSArray<NSNumber *> *)generateARM64MovImmediate:(const X86ExtendedInstruction)instruction {
    ARM64Register targetReg = [self mapX86ToARM64Register:instruction.destReg];
    uint64_t immediate = instruction.immediate;
    
    // MOVZ Xd, #imm16, LSL #shift
    uint32_t movz = 0xD2800000 | (targetReg & 0x1F) | ((immediate & 0xFFFF) << 5);
    
    if (immediate > 0xFFFF) {
        // 需要多条指令处理大立即数
        uint32_t movk = 0xF2A00000 | (targetReg & 0x1F) | (((immediate >> 16) & 0xFFFF) << 5);
        return @[@(movz), @(movk)];
    }
    
    return @[@(movz)];
}

+ (NSArray<NSNumber *> *)generateARM64Arithmetic:(const X86ExtendedInstruction)instruction {
    ARM64Register targetReg = [self mapX86ToARM64Register:X86_RAX];  // EAX对应
    uint64_t immediate = instruction.immediate;
    
    if (instruction.type == X86_INSTR_ADD_REG_IMM) {
        // ADD Xd, Xn, #imm12
        uint32_t add = 0x91000000 | (targetReg & 0x1F) | ((targetReg & 0x1F) << 5) | ((immediate & 0xFFF) << 10);
        return @[@(add)];
    } else if (instruction.type == X86_INSTR_SUB_REG_IMM) {
        // SUB Xd, Xn, #imm12
        uint32_t sub = 0xD1000000 | (targetReg & 0x1F) | ((targetReg & 0x1F) << 5) | ((immediate & 0xFFF) << 10);
        return @[@(sub)];
    }
    
    return @[@(0xD503201F)];  // NOP fallback
}

+ (NSArray<NSNumber *> *)generateARM64Compare:(const X86ExtendedInstruction)instruction {
    ARM64Register targetReg = [self mapX86ToARM64Register:X86_RAX];
    uint64_t immediate = instruction.immediate;
    
    // CMP Xn, #imm12 (实际上是SUBS XZR, Xn, #imm12)
    uint32_t cmp = 0xF1000000 | 0x1F | ((targetReg & 0x1F) << 5) | ((immediate & 0xFFF) << 10);
    return @[@(cmp)];
}

+ (NSArray<NSNumber *> *)generateARM64Branch:(const X86ExtendedInstruction)instruction {
    int64_t offset = instruction.immediate;
    
    switch (instruction.type) {
        case X86_INSTR_JMP_REL8:
            // B #imm26
            return @[@(0x14000000 | ((offset / 4) & 0x3FFFFFF))];
            
        case X86_INSTR_JE_REL8:
            // B.EQ #imm19
            return @[@(0x54000000 | ((offset / 4) & 0x7FFFF) << 5 | 0x0)];
            
        case X86_INSTR_JNE_REL8:
            // B.NE #imm19
            return @[@(0x54000000 | ((offset / 4) & 0x7FFFF) << 5 | 0x1)];
            
        case X86_INSTR_JL_REL8:
            // B.LT #imm19
            return @[@(0x54000000 | ((offset / 4) & 0x7FFFF) << 5 | 0xB)];
            
        case X86_INSTR_JG_REL8:
            // B.GT #imm19
            return @[@(0x54000000 | ((offset / 4) & 0x7FFFF) << 5 | 0xC)];
            
        default:
            return @[@(0xD503201F)];
    }
}

+ (NSArray<NSNumber *> *)generateARM64Stack:(const X86ExtendedInstruction)instruction {
    ARM64Register reg = [self mapX86ToARM64Register:instruction.sourceReg ?: instruction.destReg];
    
    if (instruction.type == X86_INSTR_PUSH_REG) {
        // STR Xt, [SP, #-16]!
        uint32_t str = 0xF81F0000 | (reg & 0x1F) | (ARM64_SP << 5);
        return @[@(str)];
    } else if (instruction.type == X86_INSTR_POP_REG) {
        // LDR Xt, [SP], #16
        uint32_t ldr = 0xF84003E0 | (reg & 0x1F);
        return @[@(ldr)];
    }
    
    return @[@(0xD503201F)];
}

+ (NSArray<NSNumber *> *)generateARM64Call:(const X86ExtendedInstruction)instruction {
    int64_t offset = instruction.immediate;
    
    // BL #imm26
    uint32_t bl = 0x94000000 | ((offset / 4) & 0x3FFFFFF);
    return @[@(bl)];
}

+ (NSArray<NSNumber *> *)generateARM64Interrupt:(const X86ExtendedInstruction)instruction {
    uint64_t intNum = instruction.immediate;
    
    // 模拟系统调用 - 使用SVC指令
    uint32_t svc = 0xD4000001 | ((intNum & 0xFFFF) << 5);
    return @[@(svc)];
}

#pragma mark - 寄存器映射

+ (ARM64Register)mapX86ToARM64Register:(X86Register)x86Register {
    // 扩展的寄存器映射表
    static const ARM64Register mapping[16] = {
        ARM64_X19, ARM64_X20, ARM64_X21, ARM64_X22,  // RAX, RCX, RDX, RBX
        ARM64_SP,  ARM64_X29, ARM64_X23, ARM64_X24,  // RSP, RBP, RSI, RDI
        ARM64_X8,  ARM64_X9,  ARM64_X10, ARM64_X11,  // R8-R11
        ARM64_X12, ARM64_X13, ARM64_X14, ARM64_X15   // R12-R15
    };
    
    if (x86Register < 16) {
        return mapping[x86Register];
    }
    
    return ARM64_X0;  // 默认值
}

+ (void)updateFlags:(Box64Context *)context result:(uint64_t)result operation:(NSString *)operation {
    if (!context) return;
    
    // 更新RFLAGS
    context->rflags &= ~0x8D5;  // 清除相关标志位
    
    // Zero Flag (ZF)
    if (result == 0) {
        context->rflags |= 0x40;
    }
    
    // Sign Flag (SF)
    if (result & 0x80000000) {
        context->rflags |= 0x80;
    }
    
    // Carry Flag (CF) - 简化实现
    if ([operation isEqualToString:@"add"] && result < context->x86_regs[X86_RAX]) {
        context->rflags |= 0x01;
    }
}

#pragma mark - 内存操作

+ (uint64_t)calculateEffectiveAddress:(const X86ExtendedInstruction)instruction context:(Box64Context *)context {
    // 简化的有效地址计算
    uint64_t baseAddr = 0;
    
    if (instruction.hasDisplacement) {
        baseAddr += instruction.displacement;
    }
    
    if (instruction.destReg != X86_RSP) {
        baseAddr += context->x86_regs[instruction.destReg];
    }
    
    return baseAddr;
}

+ (BOOL)validateMemoryAccess:(uint64_t)address size:(size_t)size context:(Box64Context *)context {
    if (!context || !context->memory_base) {
        return NO;
    }
    
    return (address + size) <= context->memory_size;
}

@end
