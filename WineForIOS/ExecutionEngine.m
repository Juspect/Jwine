#import "ExecutionEngine.h"

@interface ExecutionEngine()
@property (nonatomic, strong) WineContainer *container;
@property (nonatomic, copy) NSString *currentExecutablePath;
@property (nonatomic, assign) BOOL isRunning;
@end

@implementation ExecutionEngine

- (instancetype)initWithContainer:(WineContainer *)container {
    self = [super init];
    if (self) {
        _container = container;
        _isRunning = NO;
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
    
    NSLog(@"Loaded executable: %@", exePath);
}

- (void)startExecution {
    if (self.isRunning) {
        NSLog(@"Already running");
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
    
    [self executeWithWine];
}

- (void)executeWithWine {
    // 暂时模拟执行，后续集成真正的Wine + Box64
    self.isRunning = YES;
    if (self.delegate) {
        [self.delegate executionEngine:self didStartProgram:self.currentExecutablePath];
    }
    
    NSLog(@"Executing: %@", self.currentExecutablePath);
    
    // 模拟程序执行
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        sleep(2); // 模拟执行时间
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.isRunning = NO;
            if (self.delegate) {
                [self.delegate executionEngine:self didFinishProgram:self.currentExecutablePath withExitCode:0];
            }
        });
    });
}

- (void)stopExecution {
    self.isRunning = NO;
    NSLog(@"Execution stopped");
}

@end
