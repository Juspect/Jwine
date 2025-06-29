// ExtendedInstructionProcessor.h - 扩展指令处理器
#import <Foundation/Foundation.h>
#import "EnhancedBox64Instructions.h"

NS_ASSUME_NONNULL_BEGIN

// 新增指令类型
typedef NS_ENUM(NSUInteger, ExtendedX86InstructionType) {
    // 浮点指令
    X86_INSTR_FADD = 0xD8C0,
    X86_INSTR_FSUB = 0xD8E0,
    X86_INSTR_FMUL = 0xD8C8,
    X86_INSTR_FDIV = 0xD8F0,
    X86_INSTR_FLD = 0xD900,
    X86_INSTR_FST = 0xD910,
    
    // SIMD指令 (SSE/AVX)
    X86_INSTR_MOVSS = 0xF30F10,
    X86_INSTR_ADDSS = 0xF30F58,
    X86_INSTR_MULSS = 0xF30F59,
    X86_INSTR_MOVAPS = 0x0F28,
    X86_INSTR_PADDB = 0x660FFC,
    
    // 字符串操作指令
    X86_INSTR_MOVSB = 0xA4,
    X86_INSTR_MOVSW = 0xA5,
    X86_INSTR_STOSB = 0xAA,
    X86_INSTR_LODSB = 0xAC,
    X86_INSTR_CMPSB = 0xA6,
    X86_INSTR_SCASB = 0xAE,
    
    // 位操作指令
    X86_INSTR_BSF = 0x0FBC,
    X86_INSTR_BSR = 0x0FBD,
    X86_INSTR_BT = 0x0FA3,
    X86_INSTR_BTC = 0x0FBB,
    X86_INSTR_BTR = 0x0FB3,
    X86_INSTR_BTS = 0x0FAB,
    
    // 条件移动指令
    X86_INSTR_CMOVZ = 0x0F44,
    X86_INSTR_CMOVNZ = 0x0F45,
    X86_INSTR_CMOVS = 0x0F48,
    X86_INSTR_CMOVNS = 0x0F49,
    
    // 循环指令
    X86_INSTR_LOOP = 0xE2,
    X86_INSTR_LOOPE = 0xE1,
    X86_INSTR_LOOPNE = 0xE0,
    
    // 复杂运算指令
    X86_INSTR_IMUL = 0x0FAF,
    X86_INSTR_IDIV = 0xF7F8,
    X86_INSTR_SHL = 0xD3E0,
    X86_INSTR_SHR = 0xD3E8,
    X86_INSTR_SAR = 0xD3F8,
    X86_INSTR_ROL = 0xD3C0,
    X86_INSTR_ROR = 0xD3C8
};

@interface ExtendedInstructionProcessor : NSObject

+ (instancetype)sharedProcessor;

// 主要处理方法
- (BOOL)processExtendedInstruction:(const uint8_t *)instruction
                            length:(size_t)length
                           context:(Box64Context *)context;

// 浮点运算处理
- (BOOL)processFloatingPointInstruction:(X86ExtendedInstruction)instr context:(Box64Context *)context;

// SIMD指令处理
- (BOOL)processSIMDInstruction:(X86ExtendedInstruction)instr context:(Box64Context *)context;

// 字符串操作处理
- (BOOL)processStringInstruction:(X86ExtendedInstruction)instr context:(Box64Context *)context;

// 位操作处理
- (BOOL)processBitInstruction:(X86ExtendedInstruction)instr context:(Box64Context *)context;

// 生成对应的ARM64代码
- (NSArray<NSNumber *> *)generateARM64ForExtendedInstruction:(X86ExtendedInstruction)instr;

@end

NS_ASSUME_NONNULL_END
