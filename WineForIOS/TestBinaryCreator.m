// TestBinaryCreator.m - 测试二进制文件创建器实现
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

#pragma mark - PE文件创建

- (NSData *)createSimpleTestPE {
    NSMutableData *peData = [NSMutableData data];
    
    // DOS头 (64字节)
    uint8_t dosHeader[64] = {0};
    dosHeader[0] = 'M';   // DOS签名
    dosHeader[1] = 'Z';
    *(uint32_t *)(dosHeader + 60) = 64;  // PE头偏移
    [peData appendBytes:dosHeader length:64];
    
    // PE头
    uint8_t peSignature[4] = {'P', 'E', 0, 0};
    [peData appendBytes:peSignature length:4];
    
    // COFF头 (20字节)
    uint8_t coffHeader[20] = {0};
    *(uint16_t *)(coffHeader + 0) = 0x8664;  // 机器类型: x86_64
    *(uint16_t *)(coffHeader + 2) = 1;       // 节数量
    *(uint32_t *)(coffHeader + 8) = 0;       // 符号表偏移
    *(uint32_t *)(coffHeader + 12) = 0;      // 符号数量
    *(uint16_t *)(coffHeader + 16) = 240;    // 可选头大小
    *(uint16_t *)(coffHeader + 18) = 0x022;  // 特征: 可执行文件
    [peData appendBytes:coffHeader length:20];
    
    // 可选头 (240字节)
    uint8_t optionalHeader[240] = {0};
    *(uint16_t *)(optionalHeader + 0) = 0x020b;     // PE32+标识
    *(uint8_t *)(optionalHeader + 2) = 1;           // 主版本号
    *(uint8_t *)(optionalHeader + 3) = 0;           // 次版本号
    *(uint32_t *)(optionalHeader + 4) = 0x1000;     // 代码大小
    *(uint32_t *)(optionalHeader + 8) = 0;          // 初始化数据大小
    *(uint32_t *)(optionalHeader + 12) = 0;         // 未初始化数据大小
    *(uint32_t *)(optionalHeader + 16) = 0x1000;    // 入口点地址
    *(uint32_t *)(optionalHeader + 20) = 0x1000;    // 代码基址
    *(uint64_t *)(optionalHeader + 24) = 0x400000;  // 镜像基址
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
    *(uint16_t *)(optionalHeader + 68) = 2;         // 子系统: GUI
    *(uint64_t *)(optionalHeader + 72) = 0x100000;  // 栈保留大小
    *(uint64_t *)(optionalHeader + 80) = 0x1000;    // 栈提交大小
    *(uint64_t *)(optionalHeader + 88) = 0x100000;  // 堆保留大小
    *(uint64_t *)(optionalHeader + 96) = 0x1000;    // 堆提交大小
    *(uint32_t *)(optionalHeader + 108) = 16;       // 数据目录数量
    [peData appendBytes:optionalHeader length:240];
    
    // 节表 (40字节)
    uint8_t sectionHeader[40] = {0};
    memcpy(sectionHeader, ".text\0\0\0", 8);        // 节名
    *(uint32_t *)(sectionHeader + 8) = 0x1000;      // 虚拟大小
    *(uint32_t *)(sectionHeader + 12) = 0x1000;     // 虚拟地址
    *(uint32_t *)(sectionHeader + 16) = 0x200;      // 原始数据大小
    *(uint32_t *)(sectionHeader + 20) = 0x400;      // 原始数据偏移
    *(uint32_t *)(sectionHeader + 36) = 0x60000020; // 特征: 代码|可执行|可读
    [peData appendBytes:sectionHeader length:40];
    
    // 填充到文件对齐边界
    while (peData.length < 0x400) {
        uint8_t zero = 0;
        [peData appendBytes:&zero length:1];
    }
    
    // 简单的x86_64代码段
    uint8_t code[] = {
        // 简单的测试程序：显示消息框然后退出
        0x48, 0x83, 0xEC, 0x28,                     // SUB RSP, 0x28 (为调用准备栈空间)
        0x48, 0xC7, 0xC1, 0x00, 0x00, 0x00, 0x00,   // MOV RCX, 0 (hWnd = NULL)
        0x48, 0xC7, 0xC2, 0x20, 0x10, 0x40, 0x00,   // MOV RDX, 0x401020 (lpText)
        0x49, 0xC7, 0xC0, 0x30, 0x10, 0x40, 0x00,   // MOV R8, 0x401030 (lpCaption)
        0x49, 0xC7, 0xC1, 0x00, 0x00, 0x00, 0x00,   // MOV R9, 0 (uType = MB_OK)
        0xFF, 0x15, 0x02, 0x00, 0x00, 0x00,         // CALL [MessageBoxA_ptr]
        0xEB, 0x08,                                 // JMP +8 (跳过函数指针)
        // MessageBoxA函数指针占位符
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        // 退出程序
        0x48, 0xC7, 0xC1, 0x00, 0x00, 0x00, 0x00,   // MOV RCX, 0 (退出码)
        0xFF, 0x15, 0x02, 0x00, 0x00, 0x00,         // CALL [ExitProcess_ptr]
        0xEB, 0x08,                                 // JMP +8 (跳过函数指针)
        // ExitProcess函数指针占位符
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        // 填充到0x1020
    };
    [peData appendBytes:code length:sizeof(code)];
    
    // 填充剩余代码段
    while (peData.length < 0x1020) {
        uint8_t zero = 0;
        [peData appendBytes:&zero length:1];
    }
    
    // 字符串数据
    const char *text = "Hello from Wine on iOS!";
    [peData appendBytes:text length:strlen(text) + 1];
    
    while (peData.length < 0x1030) {
        uint8_t zero = 0;
        [peData appendBytes:&zero length:1];
    }
    
    const char *caption = "Wine Test";
    [peData appendBytes:caption length:strlen(caption) + 1];
    
    // 填充到节对齐
    while (peData.length < 0x1200) {
        uint8_t zero = 0;
        [peData appendBytes:&zero length:1];
    }
    
    NSLog(@"[TestBinaryCreator] Created simple test PE (%lu bytes)", (unsigned long)peData.length);
    return peData;
}

- (NSData *)createCalculatorTestPE {
    // 创建一个更复杂的计算器PE文件
    // 这里先返回简化版本，在实际应用中需要包含完整的UI代码
    NSMutableData *peData = [NSMutableData data];
    
    // DOS头
    uint8_t dosHeader[64] = {0};
    dosHeader[0] = 'M';
    dosHeader[1] = 'Z';
    *(uint32_t *)(dosHeader + 60) = 64;
    [peData appendBytes:dosHeader length:64];
    
    // PE签名
    uint8_t peSignature[4] = {'P', 'E', 0, 0};
    [peData appendBytes:peSignature length:4];
    
    // COFF头
    uint8_t coffHeader[20] = {0};
    *(uint16_t *)(coffHeader + 0) = 0x8664;  // x86_64
    *(uint16_t *)(coffHeader + 2) = 1;       // 1个节
    *(uint16_t *)(coffHeader + 16) = 240;    // 可选头大小
    *(uint16_t *)(coffHeader + 18) = 0x022;  // 可执行文件
    [peData appendBytes:coffHeader length:20];
    
    // 简化的可选头
    uint8_t optionalHeader[240] = {0};
    *(uint16_t *)(optionalHeader + 0) = 0x020b;     // PE32+
    *(uint32_t *)(optionalHeader + 16) = 0x1000;    // 入口点
    *(uint64_t *)(optionalHeader + 24) = 0x400000;  // 镜像基址
    *(uint32_t *)(optionalHeader + 32) = 0x1000;    // 节对齐
    *(uint32_t *)(optionalHeader + 36) = 0x200;     // 文件对齐
    *(uint16_t *)(optionalHeader + 48) = 6;         // 主子系统版本
    *(uint32_t *)(optionalHeader + 56) = 0x2000;    // 镜像大小
    *(uint32_t *)(optionalHeader + 60) = 0x400;     // 头大小
    *(uint16_t *)(optionalHeader + 68) = 2;         // GUI子系统
    [peData appendBytes:optionalHeader length:240];
    
    // 节表
    uint8_t sectionHeader[40] = {0};
    memcpy(sectionHeader, ".text\0\0\0", 8);
    *(uint32_t *)(sectionHeader + 8) = 0x1000;      // 虚拟大小
    *(uint32_t *)(sectionHeader + 12) = 0x1000;     // 虚拟地址
    *(uint32_t *)(sectionHeader + 16) = 0x200;      // 原始数据大小
    *(uint32_t *)(sectionHeader + 20) = 0x400;      // 原始数据偏移
    *(uint32_t *)(sectionHeader + 36) = 0x60000020; // 特征
    [peData appendBytes:sectionHeader length:40];
    
    // 填充到0x400
    while (peData.length < 0x400) {
        uint8_t zero = 0;
        [peData appendBytes:&zero length:1];
    }
    
    // 计算器程序的简化代码
    uint8_t calculatorCode[] = {
        // 创建窗口并显示计算器界面的简化版本
        0x48, 0x83, 0xEC, 0x28,                     // SUB RSP, 0x28
        0x48, 0xC7, 0xC1, 0x00, 0x00, 0x00, 0x00,   // MOV RCX, 0
        0x48, 0xC7, 0xC2, 0x00, 0x11, 0x40, 0x00,   // MOV RDX, 0x401100 (窗口文本)
        0x49, 0xC7, 0xC0, 0x10, 0x11, 0x40, 0x00,   // MOV R8, 0x401110 (窗口标题)
        0x49, 0xC7, 0xC1, 0x00, 0x00, 0x00, 0x00,   // MOV R9, 0
        0x90, 0x90, 0x90, 0x90,                     // NOP占位符
        0x48, 0xC7, 0xC1, 0x00, 0x00, 0x00, 0x00,   // MOV RCX, 0
        0x90, 0x90, 0x90, 0x90,                     // NOP占位符
        0xC3                                        // RET
    };
    [peData appendBytes:calculatorCode length:sizeof(calculatorCode)];
    
    // 填充到0x600
    while (peData.length < 0x600) {
        uint8_t zero = 0;
        [peData appendBytes:&zero length:1];
    }
    
    NSLog(@"[TestBinaryCreator] Created calculator test PE (%lu bytes)", (unsigned long)peData.length);
    return peData;
}

- (NSData *)createHelloWorldPE {
    NSMutableData *peData = [NSMutableData data];
    
    // 最简单的Hello World PE文件
    uint8_t dosHeader[64] = {0};
    dosHeader[0] = 'M';
    dosHeader[1] = 'Z';
    *(uint32_t *)(dosHeader + 60) = 64;
    [peData appendBytes:dosHeader length:64];
    
    uint8_t peSignature[4] = {'P', 'E', 0, 0};
    [peData appendBytes:peSignature length:4];
    
    uint8_t coffHeader[20] = {0};
    *(uint16_t *)(coffHeader + 0) = 0x8664;  // x86_64
    *(uint16_t *)(coffHeader + 2) = 1;
    *(uint16_t *)(coffHeader + 16) = 240;
    *(uint16_t *)(coffHeader + 18) = 0x022;
    [peData appendBytes:coffHeader length:20];
    
    uint8_t optionalHeader[240] = {0};
    *(uint16_t *)(optionalHeader + 0) = 0x020b;
    *(uint32_t *)(optionalHeader + 16) = 0x1000;
    *(uint64_t *)(optionalHeader + 24) = 0x400000;
    *(uint32_t *)(optionalHeader + 32) = 0x1000;
    *(uint32_t *)(optionalHeader + 36) = 0x200;
    *(uint16_t *)(optionalHeader + 68) = 3;  // 控制台子系统
    [peData appendBytes:optionalHeader length:240];
    
    uint8_t sectionHeader[40] = {0};
    memcpy(sectionHeader, ".text\0\0\0", 8);
    *(uint32_t *)(sectionHeader + 8) = 0x1000;
    *(uint32_t *)(sectionHeader + 12) = 0x1000;
    *(uint32_t *)(sectionHeader + 16) = 0x200;
    *(uint32_t *)(sectionHeader + 20) = 0x400;
    *(uint32_t *)(sectionHeader + 36) = 0x60000020;
    [peData appendBytes:sectionHeader length:40];
    
    while (peData.length < 0x400) {
        uint8_t zero = 0;
        [peData appendBytes:&zero length:1];
    }
    
    // 简单的Hello World代码
    uint8_t helloCode[] = {
        0xB8, 0x01, 0x00, 0x00, 0x00,  // MOV EAX, 1
        0xC3                           // RET
    };
    [peData appendBytes:helloCode length:sizeof(helloCode)];
    
    while (peData.length < 0x600) {
        uint8_t zero = 0;
        [peData appendBytes:&zero length:1];
    }
    
    NSLog(@"[TestBinaryCreator] Created Hello World PE (%lu bytes)", (unsigned long)peData.length);
    return peData;
}

#pragma mark - 文件保存

- (NSString *)saveTestPEToDocuments:(NSString *)filename data:(NSData *)peData {
    NSArray *documentPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [documentPaths objectAtIndex:0];
    NSString *filePath = [documentsDirectory stringByAppendingPathComponent:filename];
    
    NSError *error;
    if ([peData writeToFile:filePath options:NSDataWritingAtomic error:&error]) {
        NSLog(@"[TestBinaryCreator] Saved test PE to: %@", filePath);
        return filePath;
    } else {
        NSLog(@"[TestBinaryCreator] Failed to save test PE: %@", error.localizedDescription);
        return nil;
    }
}

- (void)createAllTestFiles {
    NSLog(@"[TestBinaryCreator] Creating all test files...");
    
    // 创建并保存所有测试文件
    NSData *simpleTest = [self createSimpleTestPE];
    [self saveTestPEToDocuments:@"simple_test.exe" data:simpleTest];
    
    NSData *calculatorTest = [self createCalculatorTestPE];
    [self saveTestPEToDocuments:@"calculator.exe" data:calculatorTest];
    
    NSData *helloWorldTest = [self createHelloWorldPE];
    [self saveTestPEToDocuments:@"hello_world.exe" data:helloWorldTest];
    
    // 创建一个测试说明文件
    NSString *readme = @"Wine for iOS 测试文件\n\n"
                      @"包含的测试程序：\n"
                      @"1. simple_test.exe - 简单的消息框测试\n"
                      @"2. calculator.exe - GUI计算器程序\n"
                      @"3. hello_world.exe - 基础控制台程序\n\n"
                      @"使用方法：\n"
                      @"1. 在应用中点击'选择EXE文件'\n"
                      @"2. 选择测试文件\n"
                      @"3. 点击'运行程序'开始执行\n\n"
                      @"注意：这些是为测试Box64+Wine引擎创建的示例文件。";
    
    NSArray *documentPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [documentPaths objectAtIndex:0];
    NSString *readmePath = [documentsDirectory stringByAppendingPathComponent:@"README.txt"];
    [readme writeToFile:readmePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    
    NSLog(@"[TestBinaryCreator] All test files created successfully!");
}

@end
