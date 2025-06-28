// MainViewController.m - 更新版本，集成Wine测试功能
#import "MainViewController.h"
#import "WineContainer.h"
#import "WineTestViewController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface MainViewController () <UIDocumentPickerDelegate>
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *mainStackView;

// 状态显示
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *wineVersionLabel;

// 测试相关
@property (nonatomic, strong) UIButton *testWineButton;
@property (nonatomic, strong) UIButton *createContainerButton;

// 文件操作
@property (nonatomic, strong) UIButton *selectFileButton;
@property (nonatomic, strong) UIButton *runButton;
@property (nonatomic, strong) UILabel *selectedFileLabel;

// 日志显示
@property (nonatomic, strong) UITextView *logTextView;

// Wine相关
@property (nonatomic, strong) WineContainer *container;
@property (nonatomic, strong) ExecutionEngine *executionEngine;
@property (nonatomic, strong) NSString *selectedFilePath;
@end

@implementation MainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Wine for iOS";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    // 添加设置按钮
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:@"设置"
        style:UIBarButtonItemStylePlain
        target:self
        action:@selector(showSettings)];
    
    [self setupUI];
    [self setupWineContainer];
    [self checkWineLibraries];
}

- (void)setupUI {
    // 创建滚动视图
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.scrollView];
    
    // 创建主堆栈视图
    self.mainStackView = [[UIStackView alloc] init];
    self.mainStackView.axis = UILayoutConstraintAxisVertical;
    self.mainStackView.spacing = 16;
    self.mainStackView.alignment = UIStackViewAlignmentFill;
    self.mainStackView.distribution = UIStackViewDistributionFill;
    self.mainStackView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.mainStackView];
    
    // 状态区域
    [self setupStatusSection];
    
    // 测试区域
    [self setupTestSection];
    
    // 容器管理区域
    [self setupContainerSection];
    
    // 文件操作区域
    [self setupFileSection];
    
    // 日志区域
    [self setupLogSection];
    
    // 设置约束
    [self setupConstraints];
}

- (void)setupStatusSection {
    // 状态标题
    UILabel *statusTitle = [self createSectionTitle:@"📊 状态信息"];
    [self.mainStackView addArrangedSubview:statusTitle];
    
    // 状态卡片
    UIView *statusCard = [self createCardView];
    
    // 主状态标签
    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.text = @"正在检查Wine库...";
    self.statusLabel.font = [UIFont boldSystemFontOfSize:16];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [statusCard addSubview:self.statusLabel];
    
    // Wine版本标签
    self.wineVersionLabel = [[UILabel alloc] init];
    self.wineVersionLabel.text = @"Wine版本: 检查中...";
    self.wineVersionLabel.font = [UIFont systemFontOfSize:14];
    self.wineVersionLabel.textColor = [UIColor secondaryLabelColor];
    self.wineVersionLabel.textAlignment = NSTextAlignmentCenter;
    self.wineVersionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [statusCard addSubview:self.wineVersionLabel];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.statusLabel.topAnchor constraintEqualToAnchor:statusCard.topAnchor constant:16],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:statusCard.leadingAnchor constant:16],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:statusCard.trailingAnchor constant:-16],
        
        [self.wineVersionLabel.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:8],
        [self.wineVersionLabel.leadingAnchor constraintEqualToAnchor:statusCard.leadingAnchor constant:16],
        [self.wineVersionLabel.trailingAnchor constraintEqualToAnchor:statusCard.trailingAnchor constant:-16],
        [self.wineVersionLabel.bottomAnchor constraintEqualToAnchor:statusCard.bottomAnchor constant:-16]
    ]];
    
    [self.mainStackView addArrangedSubview:statusCard];
}

- (void)setupTestSection {
    // 测试标题
    UILabel *testTitle = [self createSectionTitle:@"🧪 Wine库测试"];
    [self.mainStackView addArrangedSubview:testTitle];
    
    // 测试按钮
    self.testWineButton = [self createPrimaryButton:@"运行Wine库测试" action:@selector(runWineTests)];
    [self.mainStackView addArrangedSubview:self.testWineButton];
}

- (void)setupContainerSection {
    // 容器标题
    UILabel *containerTitle = [self createSectionTitle:@"🗂️ Wine容器"];
    [self.mainStackView addArrangedSubview:containerTitle];
    
    // 创建容器按钮
    self.createContainerButton = [self createSecondaryButton:@"创建Wine容器" action:@selector(createContainerButtonTapped)];
    [self.mainStackView addArrangedSubview:self.createContainerButton];
}

- (void)setupFileSection {
    // 文件标题
    UILabel *fileTitle = [self createSectionTitle:@"📁 文件执行"];
    [self.mainStackView addArrangedSubview:fileTitle];
    
    // 选择文件按钮
    self.selectFileButton = [self createSecondaryButton:@"选择EXE文件" action:@selector(selectFileButtonTapped)];
    self.selectFileButton.enabled = NO;
    [self.mainStackView addArrangedSubview:self.selectFileButton];
    
    // 选中文件标签
    self.selectedFileLabel = [[UILabel alloc] init];
    self.selectedFileLabel.text = @"未选择文件";
    self.selectedFileLabel.font = [UIFont systemFontOfSize:14];
    self.selectedFileLabel.textColor = [UIColor secondaryLabelColor];
    self.selectedFileLabel.textAlignment = NSTextAlignmentCenter;
    self.selectedFileLabel.numberOfLines = 0;
    [self.mainStackView addArrangedSubview:self.selectedFileLabel];
    
    // 运行按钮
    self.runButton = [self createPrimaryButton:@"运行程序" action:@selector(runButtonTapped)];
    self.runButton.enabled = NO;
    [self.mainStackView addArrangedSubview:self.runButton];
}

- (void)setupLogSection {
    // 日志标题
    UILabel *logTitle = [self createSectionTitle:@"📝 执行日志"];
    [self.mainStackView addArrangedSubview:logTitle];
    
    // 日志文本视图
    self.logTextView = [[UITextView alloc] init];
    self.logTextView.backgroundColor = [UIColor blackColor];
    self.logTextView.textColor = [UIColor greenColor];
    self.logTextView.font = [UIFont fontWithName:@"Courier" size:12];
    self.logTextView.editable = NO;
    self.logTextView.text = @"=== Wine for iOS 执行日志 ===\n";
    self.logTextView.layer.cornerRadius = 8;
    self.logTextView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.logTextView.heightAnchor constraintEqualToConstant:200].active = YES;
    [self.mainStackView addArrangedSubview:self.logTextView];
}

- (void)setupConstraints {
    [NSLayoutConstraint activateConstraints:@[
        // 滚动视图
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        
        // 主堆栈视图
        [self.mainStackView.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor constant:20],
        [self.mainStackView.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor constant:20],
        [self.mainStackView.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor constant:-20],
        [self.mainStackView.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor constant:-20],
        [self.mainStackView.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor constant:-40]
    ]];
}

#pragma mark - UI Helper Methods

- (UILabel *)createSectionTitle:(NSString *)title {
    UILabel *label = [[UILabel alloc] init];
    label.text = title;
    label.font = [UIFont boldSystemFontOfSize:18];
    label.textColor = [UIColor labelColor];
    return label;
}

- (UIView *)createCardView {
    UIView *cardView = [[UIView alloc] init];
    cardView.backgroundColor = [UIColor secondarySystemBackgroundColor];
    cardView.layer.cornerRadius = 12;
    cardView.layer.shadowColor = [UIColor blackColor].CGColor;
    cardView.layer.shadowOffset = CGSizeMake(0, 2);
    cardView.layer.shadowRadius = 4;
    cardView.layer.shadowOpacity = 0.1;
    return cardView;
}

- (UIButton *)createPrimaryButton:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.backgroundColor = [UIColor systemBlueColor];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    button.layer.cornerRadius = 12;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [button.heightAnchor constraintEqualToConstant:50].active = YES;
    return button;
}

- (UIButton *)createSecondaryButton:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.backgroundColor = [UIColor systemGray5Color];
    [button setTitleColor:[UIColor systemBlueColor] forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:16];
    button.layer.cornerRadius = 12;
    button.layer.borderWidth = 1;
    button.layer.borderColor = [UIColor systemBlueColor].CGColor;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [button.heightAnchor constraintEqualToConstant:50].active = YES;
    return button;
}

#pragma mark - Wine Setup

- (void)setupWineContainer {
    self.container = [[WineContainer alloc] initWithName:@"default"];
    self.executionEngine = [[ExecutionEngine alloc] initWithContainer:self.container];
    self.executionEngine.delegate = self;
}

- (void)checkWineLibraries {
    [self appendToLog:@"检查Wine库..."];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        WineLibraryManager *manager = [WineLibraryManager sharedManager];
        BOOL loaded = [manager loadWineLibraries];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (loaded) {
                self.statusLabel.text = @"✅ Wine库已就绪";
                self.statusLabel.textColor = [UIColor systemGreenColor];
                self.wineVersionLabel.text = [NSString stringWithFormat:@"Wine版本: %@", manager.wineVersion];
                self.testWineButton.enabled = YES;
                [self appendToLog:@"Wine库检查完成 - 状态正常"];
            } else {
                self.statusLabel.text = @"❌ Wine库未找到";
                self.statusLabel.textColor = [UIColor systemRedColor];
                self.wineVersionLabel.text = @"请先编译Wine库";
                [self appendToLog:@"Wine库检查失败 - 请运行编译脚本"];
            }
        });
    });
}

#pragma mark - Actions

- (void)runWineTests {
    [self appendToLog:@"启动Wine库测试..."];
    
    WineTestViewController *testVC = [[WineTestViewController alloc] init];
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:testVC];
    navController.modalPresentationStyle = UIModalPresentationFullScreen;
    
    [self presentViewController:navController animated:YES completion:^{
        [self appendToLog:@"已打开测试界面"];
    }];
}

- (void)createContainerButtonTapped {
    [self appendToLog:@"创建Wine容器..."];
    self.createContainerButton.enabled = NO;
    [self.createContainerButton setTitle:@"创建中..." forState:UIControlStateNormal];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        BOOL success = [self.container createContainer];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.createContainerButton.enabled = YES;
            
            if (success) {
                [self.createContainerButton setTitle:@"✅ 容器已创建" forState:UIControlStateNormal];
                self.createContainerButton.backgroundColor = [UIColor systemGreenColor];
                [self.createContainerButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
                self.selectFileButton.enabled = YES;
                [self appendToLog:@"Wine容器创建成功"];
            } else {
                [self.createContainerButton setTitle:@"❌ 创建失败" forState:UIControlStateNormal];
                self.createContainerButton.backgroundColor = [UIColor systemRedColor];
                [self appendToLog:@"Wine容器创建失败"];
            }
        });
    });
}

- (void)selectFileButtonTapped {
    [self appendToLog:@"打开文件选择器..."];
    
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

- (void)runButtonTapped {
    if (!self.selectedFilePath) {
        [self appendToLog:@"未选择文件"];
        return;
    }
    
    [self.executionEngine loadExecutable:self.selectedFilePath];
    [self.executionEngine startExecution];
}

- (void)showSettings {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"设置"
                                                                   message:@"选择操作"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    UIAlertAction *clearLogsAction = [UIAlertAction actionWithTitle:@"清空日志"
                                                              style:UIAlertActionStyleDefault
                                                            handler:^(UIAlertAction * _Nonnull action) {
        [self clearLogs];
    }];
    
    UIAlertAction *aboutAction = [UIAlertAction actionWithTitle:@"关于"
                                                          style:UIAlertActionStyleDefault
                                                        handler:^(UIAlertAction * _Nonnull action) {
        [self showAbout];
    }];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消"
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];
    
    [alert addAction:clearLogsAction];
    [alert addAction:aboutAction];
    [alert addAction:cancelAction];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)clearLogs {
    self.logTextView.text = @"=== Wine for iOS 执行日志 ===\n";
    [self appendToLog:@"日志已清空"];
}

- (void)showAbout {
    NSString *message = @"Wine for iOS v1.0\n\n"
                       @"这是一个运行Windows程序的iOS应用\n"
                       @"基于Wine和Box64技术\n\n"
                       @"当前状态: 测试阶段\n"
                       @"支持架构: ARM64\n"
                       @"最低iOS版本: 16.0";
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"关于 Wine for iOS"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定"
                                                       style:UIAlertActionStyleDefault
                                                     handler:nil];
    
    [alert addAction:okAction];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (urls.count > 0) {
        NSURL *selectedURL = urls.firstObject;
        
        BOOL startedAccessing = [selectedURL startAccessingSecurityScopedResource];
        
        if (startedAccessing) {
            NSString *fileName = selectedURL.lastPathComponent;
            NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
            NSString *destinationPath = [documentsPath stringByAppendingPathComponent:fileName];
            
            NSError *error;
            [[NSFileManager defaultManager] removeItemAtPath:destinationPath error:nil];
            
            if ([[NSFileManager defaultManager] copyItemAtURL:selectedURL toURL:[NSURL fileURLWithPath:destinationPath] error:&error]) {
                self.selectedFilePath = destinationPath;
                self.runButton.enabled = YES;
                self.selectedFileLabel.text = [NSString stringWithFormat:@"已选择: %@", fileName];
                self.selectedFileLabel.textColor = [UIColor systemGreenColor];
                [self appendToLog:[NSString stringWithFormat:@"已选择文件: %@", fileName]];
            } else {
                [self appendToLog:[NSString stringWithFormat:@"文件复制失败: %@", error.localizedDescription]];
            }
            
            [selectedURL stopAccessingSecurityScopedResource];
        }
    }
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    [self appendToLog:@"文件选择已取消"];
}

#pragma mark - ExecutionEngineDelegate

- (void)executionEngine:(ExecutionEngine *)engine didStartProgram:(NSString *)programPath {
    [self appendToLog:[NSString stringWithFormat:@"开始执行: %@", [programPath lastPathComponent]]];
    self.runButton.enabled = NO;
    [self.runButton setTitle:@"运行中..." forState:UIControlStateNormal];
}

- (void)executionEngine:(ExecutionEngine *)engine didFinishProgram:(NSString *)programPath withExitCode:(int)exitCode {
    [self appendToLog:[NSString stringWithFormat:@"执行完成: %@ (退出码: %d)", [programPath lastPathComponent], exitCode]];
    self.runButton.enabled = YES;
    [self.runButton setTitle:@"运行程序" forState:UIControlStateNormal];
}

- (void)executionEngine:(ExecutionEngine *)engine didEncounterError:(NSError *)error {
    [self appendToLog:[NSString stringWithFormat:@"执行错误: %@", error.localizedDescription]];
    self.runButton.enabled = YES;
    [self.runButton setTitle:@"运行程序" forState:UIControlStateNormal];
}

- (void)executionEngine:(ExecutionEngine *)engine didReceiveOutput:(NSString *)output {
    [self appendToLog:[NSString stringWithFormat:@"输出: %@", output]];
}

#pragma mark - Helper Methods

- (void)appendToLog:(NSString *)message {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setTimeStyle:NSDateFormatterMediumStyle];
    NSString *timestamp = [formatter stringFromDate:[NSDate date]];
    
    NSString *logEntry = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];
    self.logTextView.text = [self.logTextView.text stringByAppendingString:logEntry];
    
    // 滚动到底部
    NSRange range = NSMakeRange(self.logTextView.text.length - 1, 1);
    [self.logTextView scrollRangeToVisible:range];
    
    NSLog(@"%@", logEntry);
}

@end
