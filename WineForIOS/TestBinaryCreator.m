// TestBinaryCreator.m - 修复版：生成最简单的可执行PE
#import "TestBinaryCreator.h"

@implementation TestBinaryCreator

+ (instancetype)sharedCreator {
    static TestBinaryCreator *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[TestBinaryCreator alloc] init];
    });
    return sharedInstance;
}

#pragma mark - PE文件创建 - 修复版

- (NSData *)createSimpleTestPE {
    NSMutableData *peData = [NSMutableData data];
    
    NSLog(@"[TestBinaryCreator] Creating ultra-simple PE for debugging...");
    
    // DOS头 (64字节) - 保持不变
    uint8_t dosHeader[64] = {0};
    dosHeader[0] = 'M';   // DOS签名
    dosHeader[1] = 'Z';
    *(uint32_t *)(dosHeader + 60) = 64;  // PE头偏移
    [peData appendBytes:dosHeader length:64];
    
    // PE头 - 保持不变
    uint8_t peSignature[4] = {'P', 'E', 0, 0};
    [peData appendBytes:peSignature length:4];
    
    // COFF头 (20字节) - 保持不变
    uint8_t coffHeader[20] = {0};
    *(uint16_t *)(coffHeader + 0) = 0x8664;  // 机器类型: x86_64
    *(uint16_t *)(coffHeader + 2) = 1;       // 节数量
    *(uint32_t *)(coffHeader + 8) = 0;       // 符号表偏移
    *(uint32_t *)(coffHeader + 12) = 0;      // 符号数量
    *(uint16_t *)(coffHeader + 16) = 240;    // 可选头大小
    *(uint16_t *)(coffHeader + 18) = 0x022;  // 特征: 可执行文件
    [peData appendBytes:coffHeader length:20];
    
    // 🔧 修复：简化的可选头 (240字节)
    uint8_t optionalHeader[240] = {0};
    *(uint16_t *)(optionalHeader + 0) = 0x020b;     // PE32+标识
    *(uint8_t *)(optionalHeader + 2) = 1;           // 主版本号
    *(uint8_t *)(optionalHeader + 3) = 0;           // 次版本号
    *(uint32_t *)(optionalHeader + 4) = 0x200;      // 🔧 修复：代码大小（512字节）
    *(uint32_t *)(optionalHeader + 8) = 0;          // 初始化数据大小
    *(uint32_t *)(optionalHeader + 12) = 0;         // 未初始化数据大小
    *(uint32_t *)(optionalHeader + 16) = 0x1000;    // 🔧 入口点RVA = 0x1000
    *(uint32_t *)(optionalHeader + 20) = 0x1000;    // 代码基址
    *(uint64_t *)(optionalHeader + 24) = 0x400000;  // 🔧 镜像基址 = 0x400000
    *(uint32_t *)(optionalHeader + 32) = 0x1000;    // 节对齐
    *(uint32_t *)(optionalHeader + 36) = 0x200;     // 文件对齐
    *(uint16_t *)(optionalHeader + 40) = 6;         // 主操作系统版本
    *(uint16_t *)(optionalHeader + 42) = 0;         // 次操作系统版本
    *(uint16_t *)(optionalHeader + 44) = 6;         // 主镜像版本
    *(uint16_t *)(optionalHeader + 46) = 0;         // 次镜像版本
    *(uint16_t *)(optionalHeader + 48) = 6;         // 主子系统版本
    *(uint16_t *)(optionalHeader + 50) = 0;         // 次子系统版本
    *(uint32_t *)(optionalHeader + 56) = 0x2000;    // 镜像大小
    *(uint32_t *)(optionalHeader + 60) = 0x400;     // 头大小
    *(uint16_t *)(optionalHeader + 68) = 3;         // 🔧 修复：子系统 = 3 (控制台)
    *(uint64_t *)(optionalHeader + 72) = 0x100000;  // 栈保留大小
    *(uint64_t *)(optionalHeader + 80) = 0x1000;    // 栈提交大小
    *(uint64_t *)(optionalHeader + 88) = 0x100000;  // 堆保留大小
    *(uint64_t *)(optionalHeader + 96) = 0x1000;    // 堆提交大小
    *(uint32_t *)(optionalHeader + 108) = 16;       // 数据目录数量
    [peData appendBytes:optionalHeader length:240];
    
    // 🔧 修复：节表 (40字节) - 确保地址映射正确
    uint8_t sectionHeader[40] = {0};
    memcpy(sectionHeader, ".text\0\0\0", 8);        // 节名
    *(uint32_t *)(sectionHeader + 8) = 0x200;       // 🔧 虚拟大小 = 512字节
    *(uint32_t *)(sectionHeader + 12) = 0x1000;     // 🔧 虚拟地址 = 0x1000 (入口点)
    *(uint32_t *)(sectionHeader + 16) = 0x200;      // 原始数据大小 = 512字节
    *(uint32_t *)(sectionHeader + 20) = 0x400;      // 🔧 原始数据偏移 = 0x400
    *(uint32_t *)(sectionHeader + 36) = 0x60000020; // 特征: 代码|可执行|可读
    [peData appendBytes:sectionHeader length:40];
    
    // 填充到文件对齐边界 (0x400)
    while (peData.length < 0x400) {
        uint8_t zero = 0;
        [peData appendBytes:&zero length:1];
    }
    
    NSLog(@"[TestBinaryCreator] PE header complete, adding ultra-simple code...");
    
    // 🔧 修复：最简单的x86_64代码（在文件偏移0x400，虚拟地址0x401000）
    uint8_t simpleCode[] = {
        // 最简单的程序：设置返回值然后退出
        0x48, 0xC7, 0xC0, 0x2A, 0x00, 0x00, 0x00,   // MOV RAX, 42 (7字节)
        0x90,                                         // NOP (1字节)
        0x90,                                         // NOP (1字节)
        0x90,                                         // NOP (1字节)
        0xC3                                          // RET (1字节) - 总共11字节
    };
    
    [peData appendBytes:simpleCode length:sizeof(simpleCode)];
    
    // 记录关键信息用于调试
    NSLog(@"[TestBinaryCreator] 🔧 调试信息:");
    NSLog(@"[TestBinaryCreator]   镜像基址: 0x400000");
    NSLog(@"[TestBinaryCreator]   入口点RVA: 0x1000");
    NSLog(@"[TestBinaryCreator]   实际入口点: 0x401000");
    NSLog(@"[TestBinaryCreator]   代码段虚拟地址: 0x401000");
    NSLog(@"[TestBinaryCreator]   代码段文件偏移: 0x400");
    NSLog(@"[TestBinaryCreator]   代码长度: %zu字节", sizeof(simpleCode));
    NSLog(@"[TestBinaryCreator]   第一条指令: MOV RAX, 42");
    
    // 填充到512字节的代码段
    while (peData.length < 0x400 + 0x200) {
        uint8_t zero = 0;
        [peData appendBytes:&zero length:1];
    }
    
    NSLog(@"[TestBinaryCreator] Ultra-simple PE created (%lu bytes)", (unsigned long)peData.length);
    NSLog(@"[TestBinaryCreator] Expected: instruction_count >= 1, RAX = 42");
    
    return peData;
}

- (NSData *)createCalculatorTestPE {
    // 重用简单版本，避免复杂性
    return [self createSimpleTestPE];
}

- (NSData *)createHelloWorldPE {
    // 创建另一个简单版本，使用不同的测试指令
    NSMutableData *peData = [NSMutableData data];
    
    // DOS头 + PE头 + COFF头 + 可选头 + 节表（复用上面的结构）
    NSData *simpleBase = [self createSimpleTestPE];
    [peData appendData:[simpleBase subdataWithRange:NSMakeRange(0, 0x400)]];
    
    // 不同的测试代码
    uint8_t testCode[] = {
        0x48, 0xC7, 0xC0, 0x01, 0x00, 0x00, 0x00,   // MOV RAX, 1
        0x48, 0x83, 0xC0, 0x01,                     // ADD RAX, 1 (结果应该是2)
        0x90,                                       // NOP
        0xC3                                        // RET
    };
    
    [peData appendBytes:testCode length:sizeof(testCode)];
    
    // 填充
    while (peData.length < 0x400 + 0x200) {
        uint8_t zero = 0;
        [peData appendBytes:&zero length:1];
    }
    
    NSLog(@"[TestBinaryCreator] Hello World PE: MOV RAX, 1; ADD RAX, 1 -> expect RAX=2");
    
    return peData;
}

// 🔧 新增：创建指令测试专用PE
- (NSData *)createInstructionTestPE {
    NSMutableData *peData = [NSMutableData data];
    
    // 复用基础结构
    NSData *simpleBase = [self createSimpleTestPE];
    [peData appendData:[simpleBase subdataWithRange:NSMakeRange(0, 0x400)]];
    
    // 专门用于测试指令解码的代码
    uint8_t instructionTest[] = {
        // 测试基础指令
        0xB8, 0x0A, 0x00, 0x00, 0x00,  // MOV EAX, 10    (5字节)
        0x05, 0x05, 0x00, 0x00, 0x00,  // ADD EAX, 5     (5字节) -> EAX = 15
        0x2D, 0x03, 0x00, 0x00, 0x00,  // SUB EAX, 3     (5字节) -> EAX = 12
        0x90,                          // NOP            (1字节)
        0xC3                           // RET            (1字节)
    };
    
    [peData appendBytes:instructionTest length:sizeof(instructionTest)];
    
    // 填充
    while (peData.length < 0x400 + 0x200) {
        uint8_t zero = 0;
        [peData appendBytes:&zero length:1];
    }
    
    NSLog(@"[TestBinaryCreator] Instruction Test PE: MOV->ADD->SUB sequence, expect EAX=12");
    
    return peData;
}

#pragma mark - 文件保存 - 增强调试

- (NSString *)saveTestPEToDocuments:(NSString *)filename data:(NSData *)peData {
    NSArray *documentPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [documentPaths objectAtIndex:0];
    NSString *filePath = [documentsDirectory stringByAppendingPathComponent:filename];
    
    NSError *error;
    if ([peData writeToFile:filePath options:NSDataWritingAtomic error:&error]) {
        NSLog(@"[TestBinaryCreator] ✅ Saved test PE to: %@", filePath);
        NSLog(@"[TestBinaryCreator] 📊 File size: %lu bytes", (unsigned long)peData.length);
        
        // 🔧 新增：验证保存的文件
        [self verifyPEFile:filePath];
        
        return filePath;
    } else {
        NSLog(@"[TestBinaryCreator] ❌ Failed to save test PE: %@", error.localizedDescription);
        return nil;
    }
}

// 🔧 新增：PE文件验证方法
- (void)verifyPEFile:(NSString *)filePath {
    NSData *fileData = [NSData dataWithContentsOfFile:filePath];
    if (!fileData || fileData.length < 64) {
        NSLog(@"[TestBinaryCreator] ❌ PE验证失败：文件无效");
        return;
    }
    
    const uint8_t *bytes = fileData.bytes;
    
    // 检查DOS签名
    if (bytes[0] != 'M' || bytes[1] != 'Z') {
        NSLog(@"[TestBinaryCreator] ❌ PE验证失败：DOS签名错误");
        return;
    }
    
    // 检查PE偏移
    uint32_t peOffset = *(uint32_t *)(bytes + 60);
    if (peOffset >= fileData.length - 4) {
        NSLog(@"[TestBinaryCreator] ❌ PE验证失败：PE偏移无效");
        return;
    }
    
    // 检查PE签名
    if (*(uint32_t *)(bytes + peOffset) != 0x00004550) {
        NSLog(@"[TestBinaryCreator] ❌ PE验证失败：PE签名错误");
        return;
    }
    
    // 读取入口点信息
    uint32_t entryPointRVA = *(uint32_t *)(bytes + peOffset + 24 + 16);
    uint64_t imageBase = *(uint64_t *)(bytes + peOffset + 24 + 24);
    
    NSLog(@"[TestBinaryCreator] ✅ PE文件验证通过");
    NSLog(@"[TestBinaryCreator] 📍 镜像基址: 0x%llX", imageBase);
    NSLog(@"[TestBinaryCreator] 📍 入口点RVA: 0x%X", entryPointRVA);
    NSLog(@"[TestBinaryCreator] 📍 实际入口点: 0x%llX", imageBase + entryPointRVA);
    
    // 检查代码段内容
    if (fileData.length >= 0x400 + 5) {
        const uint8_t *codeBytes = bytes + 0x400;
        NSLog(@"[TestBinaryCreator] 📝 前5字节代码: %02X %02X %02X %02X %02X",
              codeBytes[0], codeBytes[1], codeBytes[2], codeBytes[3], codeBytes[4]);
        
        // 验证第一条指令（MOV RAX, 42 = 48 C7 C0 2A 00 00 00）
        if (codeBytes[0] == 0x48 && codeBytes[1] == 0xC7 && codeBytes[2] == 0xC0 && codeBytes[3] == 0x2A) {
            NSLog(@"[TestBinaryCreator] ✅ 第一条指令验证通过：MOV RAX, 42");
        } else {
            NSLog(@"[TestBinaryCreator] ⚠️ 第一条指令不匹配预期");
        }
    }
}

- (void)createAllTestFiles {
    NSLog(@"[TestBinaryCreator] Creating all enhanced test files...");
    
    // 创建并保存增强的测试文件
    NSData *simpleTest = [self createSimpleTestPE];
    [self saveTestPEToDocuments:@"simple_test.exe" data:simpleTest];
    
    NSData *helloWorldTest = [self createHelloWorldPE];
    [self saveTestPEToDocuments:@"hello_world.exe" data:helloWorldTest];
    
    // 🔧 新增：指令测试文件
    NSData *instructionTest = [self createInstructionTestPE];
    [self saveTestPEToDocuments:@"instruction_test.exe" data:instructionTest];
    
    // 创建增强的说明文件
    NSString *readme = @"Wine for iOS 增强测试文件 (修复版)\n\n"
                      @"🔧 调试版本测试程序：\n"
                      @"1. simple_test.exe - 最简单测试：MOV RAX, 42\n"
                      @"   预期结果：instruction_count=1, RAX=42\n\n"
                      @"2. hello_world.exe - 算术测试：MOV RAX, 1; ADD RAX, 1\n"
                      @"   预期结果：instruction_count=2, RAX=2\n\n"
                      @"3. instruction_test.exe - 指令序列测试\n"
                      @"   预期结果：instruction_count=4, EAX=12\n\n"
                      @"📊 PE文件结构信息：\n"
                      @"• 镜像基址: 0x400000\n"
                      @"• 入口点RVA: 0x1000\n"
                      @"• 实际入口点: 0x401000\n"
                      @"• 代码段文件偏移: 0x400\n\n"
                      @"🔍 调试方法：\n"
                      @"1. 检查instruction_count > 0\n"
                      @"2. 检查rip值变化\n"
                      @"3. 检查寄存器值\n"
                      @"4. 如果仍然失败，问题在PE入口点定位或内存映射";
    
    NSArray *documentPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [documentPaths objectAtIndex:0];
    NSString *readmePath = [documentsDirectory stringByAppendingPathComponent:@"README_DEBUG.txt"];
    [readme writeToFile:readmePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    
    NSLog(@"[TestBinaryCreator] ✅ All enhanced test files created successfully!");
    NSLog(@"[TestBinaryCreator] 📝 Debug info saved to README_DEBUG.txt");
}

@end
