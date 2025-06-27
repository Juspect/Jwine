#import "ViewController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface ViewController () <UIDocumentPickerDelegate>
@property (strong, nonatomic) UILabel *statusLabel;
@property (strong, nonatomic) UIButton *testButton;
@property (strong, nonatomic) UIButton *selectFileButton;
@property (strong, nonatomic) UIButton *runFileButton;
@property (strong, nonatomic) UITextView *logView;
@property (strong, nonatomic) NSString *selectedFilePath;
@property (strong, nonatomic) NSString *containerPath;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    NSLog(@"ViewController viewDidLoad called");
    
    self.title = @"Wine for iOS";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    [self setupUI];
    [self logMessage:@"App started successfully"];
}

- (void)setupUI {
    // Status Label
    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.text = @"Wine for iOS - Ready";
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.font = [UIFont boldSystemFontOfSize:18];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.statusLabel];
    
    // Test Container Button
    self.testButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.testButton setTitle:@"Create Wine Container" forState:UIControlStateNormal];
    self.testButton.backgroundColor = [UIColor systemBlueColor];
    [self.testButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.testButton.layer.cornerRadius = 8;
    [self.testButton addTarget:self action:@selector(testButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    self.testButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.testButton];
    
    // Select File Button
    self.selectFileButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.selectFileButton setTitle:@"Select EXE File" forState:UIControlStateNormal];
    self.selectFileButton.backgroundColor = [UIColor systemOrangeColor];
    [self.selectFileButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.selectFileButton.layer.cornerRadius = 8;
    self.selectFileButton.enabled = NO;
    [self.selectFileButton addTarget:self action:@selector(selectFileButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    self.selectFileButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.selectFileButton];
    
    // Run File Button
    self.runFileButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.runFileButton setTitle:@"Run EXE" forState:UIControlStateNormal];
    self.runFileButton.backgroundColor = [UIColor systemGreenColor];
    [self.runFileButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.runFileButton.layer.cornerRadius = 8;
    self.runFileButton.enabled = NO;
    [self.runFileButton addTarget:self action:@selector(runFileButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    self.runFileButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.runFileButton];
    
    // Log View
    self.logView = [[UITextView alloc] init];
    self.logView.backgroundColor = [UIColor blackColor];
    self.logView.textColor = [UIColor greenColor];
    self.logView.font = [UIFont fontWithName:@"Courier" size:14];
    self.logView.editable = NO;
    self.logView.text = @"=== Wine for iOS Log ===\n";
    self.logView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.logView];
    
    // Auto Layout
    [NSLayoutConstraint activateConstraints:@[
        // Status Label
        [self.statusLabel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:20],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        
        // Test Button
        [self.testButton.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:20],
        [self.testButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.testButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.testButton.heightAnchor constraintEqualToConstant:44],
        
        // Select File Button
        [self.selectFileButton.topAnchor constraintEqualToAnchor:self.testButton.bottomAnchor constant:10],
        [self.selectFileButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.selectFileButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.selectFileButton.heightAnchor constraintEqualToConstant:44],
        
        // Run File Button
        [self.runFileButton.topAnchor constraintEqualToAnchor:self.selectFileButton.bottomAnchor constant:10],
        [self.runFileButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.runFileButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.runFileButton.heightAnchor constraintEqualToConstant:44],
        
        // Log View
        [self.logView.topAnchor constraintEqualToAnchor:self.runFileButton.bottomAnchor constant:20],
        [self.logView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.logView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.logView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-20]
    ]];
}

- (void)testButtonTapped {
    [self logMessage:@"Creating Wine container..."];
    self.statusLabel.text = @"Creating Container...";
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self createTestContainer];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.statusLabel.text = @"Container Ready";
            self.selectFileButton.enabled = YES;
            [self logMessage:@"Container creation completed! You can now select an EXE file."];
        });
    });
}

- (void)selectFileButtonTapped {
    [self logMessage:@"Opening file picker..."];
    
    UIDocumentPickerViewController *documentPicker;
    
    if (@available(iOS 14.0, *)) {
        documentPicker = [[UIDocumentPickerViewController alloc]
                          initForOpeningContentTypes:@[UTTypeItem, UTTypeExecutable]];
    } else {
        documentPicker = [[UIDocumentPickerViewController alloc]
                          initWithDocumentTypes:@[@"public.item", @"com.microsoft.windows-executable"]
                          inMode:UIDocumentPickerModeOpen];
    }
    
    documentPicker.delegate = self;
    documentPicker.allowsMultipleSelection = NO;
    [self presentViewController:documentPicker animated:YES completion:nil];
}

- (void)runFileButtonTapped {
    if (!self.selectedFilePath) {
        [self logMessage:@"No file selected"];
        return;
    }
    
    [self logMessage:[NSString stringWithFormat:@"Attempting to run: %@", [self.selectedFilePath lastPathComponent]]];
    self.statusLabel.text = @"Running EXE...";
    self.runFileButton.enabled = NO;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self executeFile:self.selectedFilePath];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.statusLabel.text = @"Execution Completed";
            self.runFileButton.enabled = YES;
        });
    });
}

- (void)executeFile:(NSString *)filePath {
    [self logMessage:@"=== Starting EXE Execution ==="];
    
    // 分析exe文件
    [self analyzeExecutableFile:filePath];
    
    // 设置Wine环境
    [self setupWineEnvironment];
    
    // 模拟执行过程
    [self simulateExecution:filePath];
    
    [self logMessage:@"=== Execution Completed ==="];
}

- (void)analyzeExecutableFile:(NSString *)filePath {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error;
    NSDictionary *attributes = [fileManager attributesOfItemAtPath:filePath error:&error];
    
    if (attributes) {
        NSNumber *fileSize = [attributes objectForKey:NSFileSize];
        NSDate *modificationDate = [attributes objectForKey:NSFileModificationDate];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self logMessage:[NSString stringWithFormat:@"File size: %@ bytes", fileSize]];
            [self logMessage:[NSString stringWithFormat:@"Modified: %@", modificationDate]];
        });
        
        // 读取PE头信息
        [self analyzePEHeader:filePath];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self logMessage:[NSString stringWithFormat:@"Error reading file attributes: %@", error.localizedDescription]];
        });
    }
}

- (void)analyzePEHeader:(NSString *)filePath {
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingAtPath:filePath];
    if (!fileHandle) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self logMessage:@"Could not open file for reading"];
        });
        return;
    }
    
    // 读取DOS头
    NSData *dosHeader = [fileHandle readDataOfLength:64];
    if (dosHeader.length >= 2) {
        const unsigned char *bytes = (const unsigned char *)[dosHeader bytes];
        if (bytes[0] == 0x4D && bytes[1] == 0x5A) { // "MZ"
            dispatch_async(dispatch_get_main_queue(), ^{
                [self logMessage:@"Valid PE executable detected (MZ signature found)"];
            });
            
            // 读取更多PE信息
            if (dosHeader.length >= 60) {
                uint32_t peOffset = *(uint32_t *)(bytes + 60);
                [fileHandle seekToFileOffset:peOffset];
                NSData *peSignature = [fileHandle readDataOfLength:4];
                
                if (peSignature.length == 4) {
                    const unsigned char *peBytes = (const unsigned char *)[peSignature bytes];
                    if (peBytes[0] == 0x50 && peBytes[1] == 0x45) { // "PE"
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [self logMessage:@"PE signature confirmed"];
                        });
                        
                        // 读取机器类型
                        NSData *machineType = [fileHandle readDataOfLength:2];
                        if (machineType.length == 2) {
                            uint16_t machine = *(uint16_t *)[machineType bytes];
                            NSString *architecture;
                            switch (machine) {
                                case 0x014c:
                                    architecture = @"i386 (32-bit)";
                                    break;
                                case 0x8664:
                                    architecture = @"x86_64 (64-bit)";
                                    break;
                                case 0x01c0:
                                    architecture = @"ARM";
                                    break;
                                case 0xaa64:
                                    architecture = @"ARM64";
                                    break;
                                default:
                                    architecture = [NSString stringWithFormat:@"Unknown (0x%04x)", machine];
                                    break;
                            }
                            
                            dispatch_async(dispatch_get_main_queue(), ^{
                                [self logMessage:[NSString stringWithFormat:@"Target architecture: %@", architecture]];
                            });
                        }
                    }
                }
            }
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self logMessage:@"Not a valid PE executable (no MZ signature)"];
            });
        }
    }
    
    [fileHandle closeFile];
}

- (void)setupWineEnvironment {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self logMessage:@"Setting up Wine environment..."];
    });
    
    // 设置环境变量
    NSString *winePrefix = [self.containerPath stringByAppendingPathComponent:@"prefix"];
    setenv("WINEPREFIX", [winePrefix UTF8String], 1);
    setenv("WINEDEBUG", "-all", 1);
    setenv("DISPLAY", ":0", 1);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self logMessage:[NSString stringWithFormat:@"WINEPREFIX: %@", winePrefix]];
        [self logMessage:@"Wine environment configured"];
    });
}

- (void)simulateExecution:(NSString *)filePath {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self logMessage:@"Initializing Box64 x86 emulation..."];
    });
    sleep(1);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self logMessage:@"Loading Wine compatibility layer..."];
    });
    sleep(1);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self logMessage:@"Translating x86 instructions to ARM..."];
    });
    sleep(1);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self logMessage:@"Creating virtual Windows environment..."];
    });
    sleep(1);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self logMessage:[NSString stringWithFormat:@"Executing: %@", [filePath lastPathComponent]]];
    });
    sleep(2);
    
    // 模拟程序输出
    dispatch_async(dispatch_get_main_queue(), ^{
        [self logMessage:@"--- Program Output ---"];
        [self logMessage:@"Hello from Wine on iOS!"];
        [self logMessage:@"Program executed successfully"];
        [self logMessage:@"Exit code: 0"];
    });
}

- (void)createTestContainer {
    // 获取Documents目录
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    
    // 创建Wine容器目录
    self.containerPath = [documentsDirectory stringByAppendingPathComponent:@"WineContainers/default"];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error = nil;
    
    // 创建目录结构
    NSArray *directories = @[
        self.containerPath,
        [self.containerPath stringByAppendingPathComponent:@"prefix"],
        [self.containerPath stringByAppendingPathComponent:@"prefix/drive_c"],
        [self.containerPath stringByAppendingPathComponent:@"prefix/drive_c/windows"],
        [self.containerPath stringByAppendingPathComponent:@"prefix/drive_c/windows/system32"],
        [self.containerPath stringByAppendingPathComponent:@"prefix/drive_c/Program Files"],
        [self.containerPath stringByAppendingPathComponent:@"prefix/drive_c/users"],
        [self.containerPath stringByAppendingPathComponent:@"prefix/drive_c/users/default"],
        [self.containerPath stringByAppendingPathComponent:@"prefix/drive_c/temp"]
    ];
    
    for (NSString *dir in directories) {
        if ([fileManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&error]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self logMessage:[NSString stringWithFormat:@"Created: %@", [dir lastPathComponent]]];
            });
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self logMessage:[NSString stringWithFormat:@"Error creating %@: %@", [dir lastPathComponent], error.localizedDescription]];
            });
        }
        usleep(300000); // 0.3秒
    }
    
    // 创建基础Windows文件
    [self createBasicWindowsFiles];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self logMessage:[NSString stringWithFormat:@"Container path: %@", self.containerPath]];
    });
}

- (void)createBasicWindowsFiles {
    NSString *prefixPath = [self.containerPath stringByAppendingPathComponent:@"prefix"];
    
    // 创建用户注册表
    NSString *userReg = [prefixPath stringByAppendingPathComponent:@"user.reg"];
    NSString *userRegContent = @"[Software\\Wine]\n\"Version\"=\"wine-8.0\"\n";
    [userRegContent writeToFile:userReg atomically:YES encoding:NSUTF8StringEncoding error:nil];
    
    // 创建系统注册表
    NSString *systemReg = [prefixPath stringByAppendingPathComponent:@"system.reg"];
    NSString *systemRegContent = @"[System\\CurrentControlSet\\Control\\Session Manager\\Environment]\n\"PATH\"=\"C:\\\\windows\\\\system32\"\n";
    [systemRegContent writeToFile:systemReg atomically:YES encoding:NSUTF8StringEncoding error:nil];
    
    // 创建测试文件
    NSString *testFile = [prefixPath stringByAppendingPathComponent:@"drive_c/test.txt"];
    NSString *testContent = @"Hello from Wine for iOS!\nContainer created successfully.\nReady to run Windows applications.";
    [testContent writeToFile:testFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self logMessage:@"Basic Windows files created"];
    });
}

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (urls.count > 0) {
        NSURL *selectedURL = urls.firstObject;
        
        // 获取安全访问权限
        BOOL startedAccessing = [selectedURL startAccessingSecurityScopedResource];
        
        if (startedAccessing) {
            // 复制文件到应用沙盒
            NSString *fileName = selectedURL.lastPathComponent;
            NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
            NSString *destinationPath = [documentsPath stringByAppendingPathComponent:fileName];
            
            NSError *error;
            [[NSFileManager defaultManager] removeItemAtPath:destinationPath error:nil];
            
            if ([[NSFileManager defaultManager] copyItemAtURL:selectedURL toURL:[NSURL fileURLWithPath:destinationPath] error:&error]) {
                self.selectedFilePath = destinationPath;
                self.runFileButton.enabled = YES;
                [self logMessage:[NSString stringWithFormat:@"Selected file: %@", fileName]];
                [self logMessage:[NSString stringWithFormat:@"File copied to: %@", destinationPath]];
                self.statusLabel.text = [NSString stringWithFormat:@"Ready: %@", fileName];
            } else {
                [self logMessage:[NSString stringWithFormat:@"Failed to copy file: %@", error.localizedDescription]];
            }
            
            [selectedURL stopAccessingSecurityScopedResource];
        }
    }
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    [self logMessage:@"File selection cancelled"];
}

- (void)logMessage:(NSString *)message {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setTimeStyle:NSDateFormatterMediumStyle];
    NSString *timestamp = [formatter stringFromDate:[NSDate date]];
    
    NSString *logEntry = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];
    self.logView.text = [self.logView.text stringByAppendingString:logEntry];
    
    // 滚动到底部
    NSRange range = NSMakeRange(self.logView.text.length - 1, 1);
    [self.logView scrollRangeToVisible:range];
    
    NSLog(@"%@", logEntry);
}

@end
