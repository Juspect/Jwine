// ExecutionEngine.m - 修复版本，移除NSTask (iOS不支持)
#import "ExecutionEngine.h"
#import "WineLibraryManager.h"

@interface ExecutionEngine()
@property (nonatomic, strong) WineContainer *container;
@property (nonatomic, copy) NSString *currentExecutablePath;
@property (nonatomic, assign) BOOL isRunning;
@property (nonatomic, strong) WineLibraryManager *wineManager;
// 移除NSTask相关属性，iOS不支持
@end

@implementation ExecutionEngine

- (instancetype)initWithContainer:(WineContainer *)container {
    self = [super init];
    if (self) {
        _container = container;
        _isRunning = NO;
        _wineManager = [WineLibraryManager sharedManager];
    }
    return self;
}

- (void)loadExecutable:(NSString *)exePath {
    self.currentExecutablePath = [exePath copy];
    
    // 验证文件存在
    if (![[NSFileManager defaultManager] fileExistsAtPath:exePath]) {
        NSError *error = [NSError errorWithDomain:@"ExecutionEngine"
                                             code:404
                                         userInfo:@{NSLocalizedDescriptionKey: @"Executable file not found"}];
        if (self.delegate) {
            [self.delegate executionEngine:self didEncounterError:error];
        }
        return;
    }
    
    // 分析PE文件
    [self analyzePEFile:exePath];
    
    NSLog(@"[ExecutionEngine] Loaded executable: %@", exePath);
    if (self.delegate) {
        [self.delegate executionEngine:self didReceiveOutput:[NSString stringWithFormat:@"Loaded: %@", [exePath lastPathComponent]]];
    }
}

- (void)analyzePEFile:(NSString *)exePath {
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingAtPath:exePath];
    if (!fileHandle) {
        if (self.delegate) {
            [self.delegate executionEngine:self didReceiveOutput:@"Could not analyze PE file"];
        }
        return;
    }
    
    @try {
        // 读取DOS头
        NSData *dosHeader = [fileHandle readDataOfLength:64];
        if (dosHeader.length >= 2) {
            const unsigned char *bytes = (const unsigned char *)[dosHeader bytes];
            if (bytes[0] == 0x4D && bytes[1] == 0x5A) { // "MZ"
                if (self.delegate) {
                    [self.delegate executionEngine:self didReceiveOutput:@"Valid PE executable (MZ signature)"];
                }
                
                // 读取PE头信息
                if (dosHeader.length >= 60) {
                    uint32_t peOffset = *(uint32_t *)(bytes + 60);
                    [fileHandle seekToFileOffset:peOffset];
                    NSData *peSignature = [fileHandle readDataOfLength:4];
                    
                    if (peSignature.length == 4) {
                        const unsigned char *peBytes = (const unsigned char *)[peSignature bytes];
                        if (peBytes[0] == 0x50 && peBytes[1] == 0x45) { // "PE"
                            if (self.delegate) {
                                [self.delegate executionEngine:self didReceiveOutput:@"PE signature confirmed"];
                            }
                            
                            // 读取机器类型
                            NSData *machineType = [fileHandle readDataOfLength:2];
                            if (machineType.length == 2) {
                                uint16_t machine = *(uint16_t *)[machineType bytes];
                                NSString *architecture = [self getArchitectureString:machine];
                                
                                if (self.delegate) {
                                    [self.delegate executionEngine:self didReceiveOutput:[NSString stringWithFormat:@"Target: %@", architecture]];
                                }
                            }
                        }
                    }
                }
            } else {
                if (self.delegate) {
                    [self.delegate executionEngine:self didReceiveOutput:@"Not a valid PE executable"];
                }
            }
        }
    } @catch (NSException *exception) {
        if (self.delegate) {
            [self.delegate executionEngine:self didReceiveOutput:[NSString stringWithFormat:@"PE analysis error: %@", exception.reason]];
        }
    } @finally {
        [fileHandle closeFile];
    }
}

- (NSString *)getArchitectureString:(uint16_t)machine {
    switch (machine) {
        case 0x014c:
            return @"i386 (32-bit)";
        case 0x8664:
            return @"x86_64 (64-bit)";
        case 0x01c0:
            return @"ARM";
        case 0xaa64:
            return @"ARM64";
        default:
            return [NSString stringWithFormat:@"Unknown (0x%04x)", machine];
    }
}

- (void)startExecution {
    if (self.isRunning) {
        NSLog(@"[ExecutionEngine] Already running");
        return;
    }
    
    if (!self.currentExecutablePath) {
        NSError *error = [NSError errorWithDomain:@"ExecutionEngine"
                                             code:400
                                         userInfo:@{NSLocalizedDescriptionKey: @"No executable loaded"}];
        if (self.delegate) {
            [self.delegate executionEngine:self didEncounterError:error];
        }
        return;
    }
    
    // 检查Wine库是否加载
    if (!self.wineManager.isLoaded) {
        if (![self.wineManager loadWineLibraries]) {
            NSError *error = [NSError errorWithDomain:@"ExecutionEngine"
                                                 code:500
                                             userInfo:@{NSLocalizedDescriptionKey: @"Failed to load Wine libraries"}];
            if (self.delegate) {
                [self.delegate executionEngine:self didEncounterError:error];
            }
            return;
        }
    }
    
    [self executeWithWine];
}

- (void)executeWithWine {
    self.isRunning = YES;
    
    if (self.delegate) {
        [self.delegate executionEngine:self didStartProgram:self.currentExecutablePath];
        [self.delegate executionEngine:self didReceiveOutput:@"Starting Wine execution..."];
    }
    
    NSLog(@"[ExecutionEngine] Executing with Wine: %@", self.currentExecutablePath);
    
    // 在后台线程执行Wine程序
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @autoreleasepool {
            [self runWineExecution];
        }
    });
}

- (void)runWineExecution {
    // 设置Wine环境
    if (![self setupWineEnvironment]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.isRunning = NO;
            NSError *error = [NSError errorWithDomain:@"ExecutionEngine"
                                                 code:500
                                             userInfo:@{NSLocalizedDescriptionKey: @"Failed to setup Wine environment"}];
            if (self.delegate) {
                [self.delegate executionEngine:self didEncounterError:error];
            }
        });
        return;
    }
    
    // 执行程序 - 使用空数组而不是nil来避免警告
    NSArray<NSString *> *emptyArgs = @[];
    int exitCode = [self.wineManager executeProgram:self.currentExecutablePath arguments:emptyArgs];
    
    // 回到主线程报告结果
    dispatch_async(dispatch_get_main_queue(), ^{
        self.isRunning = NO;
        if (self.delegate) {
            [self.delegate executionEngine:self didFinishProgram:self.currentExecutablePath withExitCode:exitCode];
        }
    });
}

- (BOOL)setupWineEnvironment {
    // 初始化Wine环境
    if (![self.wineManager initializeWineEnvironment:self.container.winePrefixPath]) {
        return NO;
    }
    
    // 设置额外的环境变量
    setenv("WINEARCH", "win64", 1);
    setenv("WINELOADER", "/usr/bin/wine", 1);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.delegate) {
            [self.delegate executionEngine:self didReceiveOutput:@"Wine environment initialized"];
        }
    });
    
    return YES;
}

- (void)stopExecution {
    if (!self.isRunning) {
        return;
    }
    
    NSLog(@"[ExecutionEngine] Stopping execution...");
    
    // iOS上没有NSTask，直接设置状态
    self.isRunning = NO;
    
    if (self.delegate) {
        [self.delegate executionEngine:self didReceiveOutput:@"Execution stopped"];
    }
    
    NSLog(@"[ExecutionEngine] Execution stopped");
}

@end
