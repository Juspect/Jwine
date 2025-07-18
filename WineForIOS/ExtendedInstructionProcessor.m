#import "ExtendedInstructionProcessor.h"

@implementation ExtendedInstructionProcessor

+ (instancetype)sharedProcessor {
    static ExtendedInstructionProcessor *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[ExtendedInstructionProcessor alloc] init];
    });
    return shared;
}

- (BOOL)processExtendedInstruction:(const uint8_t *)instruction
                            length:(size_t)length
                           context:(Box64Context *)context {
    
    X86ExtendedInstruction decoded = [EnhancedBox64Instructions decodeInstruction:instruction maxLength:length];
    
    if (decoded.length == 0) {
        NSLog(@"[ExtendedProcessor] Failed to decode instruction");
        return NO;
    }
    
    NSLog(@"[ExtendedProcessor] Processing instruction type: 0x%X", decoded.opcode);
    
    // 根据指令类型分发处理
    switch (decoded.type) {
        // 浮点指令
        case X86_INSTR_FADD:
        case X86_INSTR_FSUB:
        case X86_INSTR_FMUL:
        case X86_INSTR_FDIV:
        case X86_INSTR_FLD:
        case X86_INSTR_FST:
            return [self processFloatingPointInstruction:decoded context:context];
            
        // SIMD指令
        case X86_INSTR_MOVSS:
        case X86_INSTR_ADDSS:
        case X86_INSTR_MULSS:
        case X86_INSTR_MOVAPS:
        case X86_INSTR_PADDB:
            return [self processSIMDInstruction:decoded context:context];
            
        // 字符串操作
        case X86_INSTR_MOVSB:
        case X86_INSTR_MOVSW:
        case X86_INSTR_STOSB:
        case X86_INSTR_LODSB:
        case X86_INSTR_CMPSB:
        case X86_INSTR_SCASB:
            return [self processStringInstruction:decoded context:context];
            
        // 位操作
        case X86_INSTR_BSF:
        case X86_INSTR_BSR:
        case X86_INSTR_BT:
        case X86_INSTR_BTC:
        case X86_INSTR_BTR:
        case X86_INSTR_BTS:
            return [self processBitInstruction:decoded context:context];
            
        default:
            NSLog(@"[ExtendedProcessor] Unsupported instruction type: 0x%X", decoded.type);
            return NO;
    }
}

- (BOOL)processFloatingPointInstruction:(X86ExtendedInstruction)instr context:(Box64Context *)context {
    NSLog(@"[ExtendedProcessor] Processing floating point instruction");
    
    // 简化的浮点运算实现
    switch (instr.type) {
        case X86_INSTR_FADD: {
            // 浮点加法 - 使用ARM64 NEON指令
            NSArray *arm64Code = @[
                @(0x4E20D400), // FADD V0.4S, V0.4S, V0.4S
                @(0xD65F03C0)  // RET
            ];
            [self executeARM64Code:arm64Code context:context];
            return YES;
        }
        
        case X86_INSTR_FMUL: {
            // 浮点乘法
            NSArray *arm64Code = @[
                @(0x6E20DC00), // FMUL V0.4S, V0.4S, V0.4S
                @(0xD65F03C0)  // RET
            ];
            [self executeARM64Code:arm64Code context:context];
            return YES;
        }
        
        default:
            return NO;
    }
}

- (BOOL)processSIMDInstruction:(X86ExtendedInstruction)instr context:(Box64Context *)context {
    NSLog(@"[ExtendedProcessor] Processing SIMD instruction");
    
    switch (instr.type) {
        case X86_INSTR_MOVSS: {
            // 移动单精度浮点数
            NSArray *arm64Code = @[
                @(0x0E040400), // MOV V0.S[0], V0.S[0]
                @(0xD65F03C0)  // RET
            ];
            [self executeARM64Code:arm64Code context:context];
            return YES;
        }
        
        case X86_INSTR_ADDSS: {
            // 单精度浮点加法
            NSArray *arm64Code = @[
                @(0x7E22D400), // FADD S0, S0, S2
                @(0xD65F03C0)  // RET
            ];
            [self executeARM64Code:arm64Code context:context];
            return YES;
        }
        
        case X86_INSTR_PADDB: {
            // 字节并行加法
            NSArray *arm64Code = @[
                @(0x4E228400), // ADD V0.16B, V0.16B, V2.16B
                @(0xD65F03C0)  // RET
            ];
            [self executeARM64Code:arm64Code context:context];
            return YES;
        }
        
        default:
            return NO;
    }
}

- (BOOL)processStringInstruction:(X86ExtendedInstruction)instr context:(Box64Context *)context {
    NSLog(@"[ExtendedProcessor] Processing string instruction");
    
    switch (instr.type) {
        case X86_INSTR_MOVSB: {
            // 字节移动
            uint64_t srcAddr = context->x86_regs[X86_RSI];
            uint64_t dstAddr = context->x86_regs[X86_RDI];
            
            if ([self validateMemoryAccess:srcAddr size:1 context:context] &&
                [self validateMemoryAccess:dstAddr size:1 context:context]) {
                
                uint8_t *src = context->memory_base + srcAddr;
                uint8_t *dst = context->memory_base + dstAddr;
                *dst = *src;
                
                // 更新指针
                context->x86_regs[X86_RSI]++;
                context->x86_regs[X86_RDI]++;
                
                return YES;
            }
            return NO;
        }
        
        case X86_INSTR_STOSB: {
            // 存储字节
            uint64_t dstAddr = context->x86_regs[X86_RDI];
            uint8_t value = (uint8_t)context->x86_regs[X86_RAX];
            
            if ([self validateMemoryAccess:dstAddr size:1 context:context]) {
                uint8_t *dst = context->memory_base + dstAddr;
                *dst = value;
                context->x86_regs[X86_RDI]++;
                return YES;
            }
            return NO;
        }
        
        default:
            return NO;
    }
}

- (BOOL)processBitInstruction:(X86ExtendedInstruction)instr context:(Box64Context *)context {
    NSLog(@"[ExtendedProcessor] Processing bit instruction");
    
    uint64_t sourceValue = context->x86_regs[instr.sourceReg];
    
    switch (instr.type) {
        case X86_INSTR_BSF: {
            // 位扫描前向
            uint64_t result = 0;
            for (int i = 0; i < 64; i++) {
                if (sourceValue & (1ULL << i)) {
                    result = i;
                    break;
                }
            }
            context->x86_regs[instr.destReg] = result;
            return YES;
        }
        
        case X86_INSTR_BSR: {
            // 位扫描反向
            uint64_t result = 0;
            for (int i = 63; i >= 0; i--) {
                if (sourceValue & (1ULL << i)) {
                    result = i;
                    break;
                }
            }
            context->x86_regs[instr.destReg] = result;
            return YES;
        }
        
        case X86_INSTR_BT: {
            // 位测试
            int bitIndex = (int)(instr.immediate & 0x3F);
            uint64_t bitValue = (sourceValue >> bitIndex) & 1;
            
            // 设置进位标志
            if (bitValue) {
                context->rflags |= 0x01; // CF = 1
            } else {
                context->rflags &= ~0x01; // CF = 0
            }
            return YES;
        }
        
        default:
            return NO;
    }
}

- (BOOL)validateMemoryAccess:(uint64_t)address size:(size_t)size context:(Box64Context *)context {
    return (address + size) <= context->memory_size && context->memory_base != NULL;
}

- (void)executeARM64Code:(NSArray<NSNumber *> *)codeArray context:(Box64Context *)context {
    // 将生成的ARM64代码发送给JIT引擎执行
    NSMutableData *codeData = [NSMutableData data];
    
    for (NSNumber *instruction in codeArray) {
        uint32_t code = instruction.unsignedIntValue;
        [codeData appendBytes:&code length:sizeof(code)];
    }
    
    // 这里应该调用JIT引擎执行生成的代码
    NSLog(@"[ExtendedProcessor] Generated %lu bytes of ARM64 code", (unsigned long)codeData.length);
}

- (NSArray<NSNumber *> *)generateARM64ForExtendedInstruction:(X86ExtendedInstruction)instr {
    // 根据x86指令生成对应的ARM64代码
    NSMutableArray *arm64Code = [NSMutableArray array];
    
    // 添加基本的ARM64指令序列
    [arm64Code addObject:@(0xD503201F)]; // NOP
    [arm64Code addObject:@(0xD65F03C0)]; // RET
    
    return [arm64Code copy];
}

@end
