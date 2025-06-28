#import "UpdatedMainViewController.h"

@interface UpdatedMainViewController ()

// UI组件
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *mainStackView;

// 状态显示
@property (nonatomic, strong) UIView *statusCard;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *engineStatusLabel;
@property (nonatomic, strong) UIProgressView *progressView;

// 系统信息
@property (nonatomic, strong) UIView *systemInfoCard;
@property (nonatomic, strong) UILabel *jitStatusLabel;
@property (nonatomic, strong) UILabel *box64StatusLabel;
@property (nonatomic, strong) UILabel *wineStatusLabel;

// 控制按钮
@property (nonatomic, strong) UIButton *initializeButton;
@property (nonatomic, strong) UIButton *createTestFilesButton;
@property (nonatomic, strong) UIButton *selectFileButton;
@property (nonatomic, strong) UIButton *runButton;
@property (nonatomic, strong) UIButton *stopButton;

// 文件信息
@property (nonatomic, strong) UIView *fileInfoCard;
@property (nonatomic, strong) UILabel *selectedFileLabel;
@property (nonatomic, strong) UILabel *fileDetailsLabel;

// 执行区域
@property (nonatomic, strong) UIView *executionCard;
@property (nonatomic, strong) UIView *wineDisplayView;  // Wine程序的显示区域
@property (nonatomic, strong) UITextView *outputTextView;

// 调试控制
@property (nonatomic, strong) UIView *debugCard;
@property (nonatomic, strong) UIButton *dumpStatesButton;
@property (nonatomic, strong) UIButton *systemInfoButton;

// 数据
@property (nonatomic, strong) CompleteExecutionEngine *executionEngine;
@property (nonatomic, strong) TestBinaryCreator *testCreator;
@property (nonatomic, strong) NSString *selectedFilePath;
@property (nonatomic, assign) BOOL isEngineInitialized;

@end

@implementation UpdatedMainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"Wine for iOS - Complete";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    // 设置导航栏
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:@"设置"
        style:UIBarButtonItemStylePlain
        target:self
        action:@selector(showSettings)];
    
    [self setupEngines];
    [self setupUI];
    [self updateUI];
    
    NSLog(@"[UpdatedMainViewController] Complete Wine for iOS interface loaded");
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    // 检查是否需要自动初始化
    if (!self.isEngineInitialized) {
        [self showInitializationPrompt];
    }
}

#pragma mark - 引擎设置

- (void)setupEngines {
    self.executionEngine = [CompleteExecutionEngine sharedEngine];
    self.executionEngine.delegate = self;
    
    self.testCreator = [TestBinaryCreator sharedCreator];
    
    self.isEngineInitialized = NO;
}

#pragma mark - UI设置

- (void)setupUI {
    // 创建滚动视图
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.showsVerticalScrollIndicator = YES;
    [self.view addSubview:self.scrollView];
    
    // 创建主堆栈视图
    self.mainStackView = [[UIStackView alloc] init];
    self.mainStackView.axis = UILayoutConstraintAxisVertical;
    self.mainStackView.spacing = 16;
    self.mainStackView.alignment = UIStackViewAlignmentFill;
    self.mainStackView.distribution = UIStackViewDistributionFill;
    self.mainStackView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.mainStackView];
    
    // 设置各个区域
    [self setupStatusSection];
    [self setupSystemInfoSection];
    [self setupControlSection];
    [self setupFileInfoSection];
    [self setupExecutionSection];
    [self setupDebugSection];
    
    // 设置约束
    [self setupConstraints];
}

- (void)setupStatusSection {
    // 状态区域标题
    UILabel *statusTitle = [self createSectionTitle:@"🎮 引擎状态" emoji:@"🎮"];
    [self.mainStackView addArrangedSubview:statusTitle];
    
    // 状态卡片
    self.statusCard = [self createCardView];
    
    // 主状态标签
    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.text = @"等待初始化...";
    self.statusLabel.font = [UIFont boldSystemFontOfSize:18];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.statusCard addSubview:self.statusLabel];
    
    // 引擎状态标签
    self.engineStatusLabel = [[UILabel alloc] init];
    self.engineStatusLabel.text = @"Box64 + Wine + JIT 引擎";
    self.engineStatusLabel.font = [UIFont systemFontOfSize:14];
    self.engineStatusLabel.textColor = [UIColor secondaryLabelColor];
    self.engineStatusLabel.textAlignment = NSTextAlignmentCenter;
    self.engineStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.statusCard addSubview:self.engineStatusLabel];
    
    // 进度条
    self.progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.progressView.progress = 0.0;
    self.progressView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.statusCard addSubview:self.progressView];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.statusLabel.topAnchor constraintEqualToAnchor:self.statusCard.topAnchor constant:16],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.statusCard.leadingAnchor constant:16],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.statusCard.trailingAnchor constant:-16],
        
        [self.engineStatusLabel.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:8],
        [self.engineStatusLabel.leadingAnchor constraintEqualToAnchor:self.statusCard.leadingAnchor constant:16],
        [self.engineStatusLabel.trailingAnchor constraintEqualToAnchor:self.statusCard.trailingAnchor constant:-16],
        
        [self.progressView.topAnchor constraintEqualToAnchor:self.engineStatusLabel.bottomAnchor constant:12],
        [self.progressView.leadingAnchor constraintEqualToAnchor:self.statusCard.leadingAnchor constant:16],
        [self.progressView.trailingAnchor constraintEqualToAnchor:self.statusCard.trailingAnchor constant:-16],
        [self.progressView.bottomAnchor constraintEqualToAnchor:self.statusCard.bottomAnchor constant:-16]
    ]];
    
    [self.mainStackView addArrangedSubview:self.statusCard];
}

- (void)setupSystemInfoSection {
    // 系统信息标题
    UILabel *systemTitle = [self createSectionTitle:@"⚙️ 系统组件" emoji:@"⚙️"];
    [self.mainStackView addArrangedSubview:systemTitle];
    
    // 系统信息卡片
    self.systemInfoCard = [self createCardView];
    
    // JIT状态
    self.jitStatusLabel = [self createInfoLabel:@"JIT引擎: 未初始化"];
    [self.systemInfoCard addSubview:self.jitStatusLabel];
    
    // Box64状态
    self.box64StatusLabel = [self createInfoLabel:@"Box64引擎: 未初始化"];
    [self.systemInfoCard addSubview:self.box64StatusLabel];
    
    // Wine状态
    self.wineStatusLabel = [self createInfoLabel:@"Wine API: 未初始化"];
    [self.systemInfoCard addSubview:self.wineStatusLabel];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.jitStatusLabel.topAnchor constraintEqualToAnchor:self.systemInfoCard.topAnchor constant:16],
        [self.jitStatusLabel.leadingAnchor constraintEqualToAnchor:self.systemInfoCard.leadingAnchor constant:16],
        [self.jitStatusLabel.trailingAnchor constraintEqualToAnchor:self.systemInfoCard.trailingAnchor constant:-16],
        
        [self.box64StatusLabel.topAnchor constraintEqualToAnchor:self.jitStatusLabel.bottomAnchor constant:8],
        [self.box64StatusLabel.leadingAnchor constraintEqualToAnchor:self.systemInfoCard.leadingAnchor constant:16],
        [self.box64StatusLabel.trailingAnchor constraintEqualToAnchor:self.systemInfoCard.trailingAnchor constant:-16],
        
        [self.wineStatusLabel.topAnchor constraintEqualToAnchor:self.box64StatusLabel.bottomAnchor constant:8],
        [self.wineStatusLabel.leadingAnchor constraintEqualToAnchor:self.systemInfoCard.leadingAnchor constant:16],
        [self.wineStatusLabel.trailingAnchor constraintEqualToAnchor:self.systemInfoCard.trailingAnchor constant:-16],
        [self.wineStatusLabel.bottomAnchor constraintEqualToAnchor:self.systemInfoCard.bottomAnchor constant:-16]
    ]];
    
    [self.mainStackView addArrangedSubview:self.systemInfoCard];
}

- (void)setupControlSection {
    // 控制标题
    UILabel *controlTitle = [self createSectionTitle:@"🎯 操作控制" emoji:@"🎯"];
    [self.mainStackView addArrangedSubview:controlTitle];
    
    // 初始化按钮
    self.initializeButton = [self createPrimaryButton:@"🚀 初始化引擎" action:@selector(initializeEngine)];
    [self.mainStackView addArrangedSubview:self.initializeButton];
    
    // 创建测试文件按钮
    self.createTestFilesButton = [self createSecondaryButton:@"📁 创建测试文件" action:@selector(createTestFiles)];
    self.createTestFilesButton.enabled = NO;
    [self.mainStackView addArrangedSubview:self.createTestFilesButton];
    
    // 选择文件按钮
    self.selectFileButton = [self createSecondaryButton:@"📂 选择EXE文件" action:@selector(selectFile)];
    self.selectFileButton.enabled = NO;
    [self.mainStackView addArrangedSubview:self.selectFileButton];
    
    // 运行和停止按钮的容器
    UIStackView *runStopStack = [[UIStackView alloc] init];
    runStopStack.axis = UILayoutConstraintAxisHorizontal;
    runStopStack.distribution = UIStackViewDistributionFillEqually;
    runStopStack.spacing = 12;
    
    self.runButton = [self createPrimaryButton:@"▶️ 运行程序" action:@selector(runProgram)];
    self.runButton.enabled = NO;
    [runStopStack addArrangedSubview:self.runButton];
    
    self.stopButton = [self createDangerButton:@"⏹️ 停止执行" action:@selector(stopExecution)];
    self.stopButton.enabled = NO;
    [runStopStack addArrangedSubview:self.stopButton];
    
    [self.mainStackView addArrangedSubview:runStopStack];
}

- (void)setupFileInfoSection {
    // 文件信息标题
    UILabel *fileTitle = [self createSectionTitle:@"📄 文件信息" emoji:@"📄"];
    [self.mainStackView addArrangedSubview:fileTitle];
    
    // 文件信息卡片
    self.fileInfoCard = [self createCardView];
    
    self.selectedFileLabel = [[UILabel alloc] init];
    self.selectedFileLabel.text = @"未选择文件";
    self.selectedFileLabel.font = [UIFont systemFontOfSize:16];
    self.selectedFileLabel.textColor = [UIColor secondaryLabelColor];
    self.selectedFileLabel.numberOfLines = 0;
    self.selectedFileLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.fileInfoCard addSubview:self.selectedFileLabel];
    
    self.fileDetailsLabel = [[UILabel alloc] init];
    self.fileDetailsLabel.text = @"选择一个EXE文件以查看详细信息";
    self.fileDetailsLabel.font = [UIFont systemFontOfSize:14];
    self.fileDetailsLabel.textColor = [UIColor tertiaryLabelColor];
    self.fileDetailsLabel.numberOfLines = 0;
    self.fileDetailsLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.fileInfoCard addSubview:self.fileDetailsLabel];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.selectedFileLabel.topAnchor constraintEqualToAnchor:self.fileInfoCard.topAnchor constant:16],
        [self.selectedFileLabel.leadingAnchor constraintEqualToAnchor:self.fileInfoCard.leadingAnchor constant:16],
        [self.selectedFileLabel.trailingAnchor constraintEqualToAnchor:self.fileInfoCard.trailingAnchor constant:-16],
        
        [self.fileDetailsLabel.topAnchor constraintEqualToAnchor:self.selectedFileLabel.bottomAnchor constant:8],
        [self.fileDetailsLabel.leadingAnchor constraintEqualToAnchor:self.fileInfoCard.leadingAnchor constant:16],
        [self.fileDetailsLabel.trailingAnchor constraintEqualToAnchor:self.fileInfoCard.trailingAnchor constant:-16],
        [self.fileDetailsLabel.bottomAnchor constraintEqualToAnchor:self.fileInfoCard.bottomAnchor constant:-16]
    ]];
    
    [self.mainStackView addArrangedSubview:self.fileInfoCard];
}

- (void)setupExecutionSection {
    // 执行区域标题
    UILabel *executionTitle = [self createSectionTitle:@"🖥️ 程序执行" emoji:@"🖥️"];
    [self.mainStackView addArrangedSubview:executionTitle];
    
    // 执行卡片
    self.executionCard = [self createCardView];
    
    // Wine显示区域
    self.wineDisplayView = [[UIView alloc] init];
    self.wineDisplayView.backgroundColor = [UIColor blackColor];
    self.wineDisplayView.layer.borderWidth = 2;
    self.wineDisplayView.layer.borderColor = [UIColor systemBlueColor].CGColor;
    self.wineDisplayView.layer.cornerRadius = 8;
    self.wineDisplayView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.executionCard addSubview:self.wineDisplayView];
    
    // 添加占位符标签
    UILabel *placeholderLabel = [[UILabel alloc] init];
    placeholderLabel.text = @"Wine程序显示区域\n程序运行时将在此处显示GUI";
    placeholderLabel.textColor = [UIColor whiteColor];
    placeholderLabel.textAlignment = NSTextAlignmentCenter;
    placeholderLabel.numberOfLines = 0;
    placeholderLabel.font = [UIFont systemFontOfSize:14];
    placeholderLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.wineDisplayView addSubview:placeholderLabel];
    
    // 输出文本视图
    self.outputTextView = [[UITextView alloc] init];
    self.outputTextView.backgroundColor = [UIColor blackColor];
    self.outputTextView.textColor = [UIColor greenColor];
    self.outputTextView.font = [UIFont fontWithName:@"Courier" size:12];
    self.outputTextView.editable = NO;
    self.outputTextView.text = @"=== Wine for iOS 执行日志 ===\n";
    self.outputTextView.layer.cornerRadius = 8;
    self.outputTextView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.executionCard addSubview:self.outputTextView];
    
    [NSLayoutConstraint activateConstraints:@[
        // Wine显示区域
        [self.wineDisplayView.topAnchor constraintEqualToAnchor:self.executionCard.topAnchor constant:16],
        [self.wineDisplayView.leadingAnchor constraintEqualToAnchor:self.executionCard.leadingAnchor constant:16],
        [self.wineDisplayView.trailingAnchor constraintEqualToAnchor:self.executionCard.trailingAnchor constant:-16],
        [self.wineDisplayView.heightAnchor constraintEqualToConstant:200],
        
        // 占位符标签
        [placeholderLabel.centerXAnchor constraintEqualToAnchor:self.wineDisplayView.centerXAnchor],
        [placeholderLabel.centerYAnchor constraintEqualToAnchor:self.wineDisplayView.centerYAnchor],
        
        // 输出文本视图
        [self.outputTextView.topAnchor constraintEqualToAnchor:self.wineDisplayView.bottomAnchor constant:12],
        [self.outputTextView.leadingAnchor constraintEqualToAnchor:self.executionCard.leadingAnchor constant:16],
        [self.outputTextView.trailingAnchor constraintEqualToAnchor:self.executionCard.trailingAnchor constant:-16],
        [self.outputTextView.heightAnchor constraintEqualToConstant:150],
        [self.outputTextView.bottomAnchor constraintEqualToAnchor:self.executionCard.bottomAnchor constant:-16]
    ]];
    
    [self.mainStackView addArrangedSubview:self.executionCard];
}

- (void)setupDebugSection {
    // 调试区域标题
    UILabel *debugTitle = [self createSectionTitle:@"🔧 调试工具" emoji:@"🔧"];
    [self.mainStackView addArrangedSubview:debugTitle];
    
    // 调试卡片
    self.debugCard = [self createCardView];
    
    // 调试按钮容器
    UIStackView *debugStack = [[UIStackView alloc] init];
    debugStack.axis = UILayoutConstraintAxisHorizontal;
    debugStack.distribution = UIStackViewDistributionFillEqually;
    debugStack.spacing = 12;
    debugStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.debugCard addSubview:debugStack];
    
    self.dumpStatesButton = [self createSecondaryButton:@"📊 状态转储" action:@selector(dumpStates)];
    [debugStack addArrangedSubview:self.dumpStatesButton];
    
    self.systemInfoButton = [self createSecondaryButton:@"ℹ️ 系统信息" action:@selector(showSystemInfo)];
    [debugStack addArrangedSubview:self.systemInfoButton];
    
    [NSLayoutConstraint activateConstraints:@[
        [debugStack.topAnchor constraintEqualToAnchor:self.debugCard.topAnchor constant:16],
        [debugStack.leadingAnchor constraintEqualToAnchor:self.debugCard.leadingAnchor constant:16],
        [debugStack.trailingAnchor constraintEqualToAnchor:self.debugCard.trailingAnchor constant:-16],
        [debugStack.bottomAnchor constraintEqualToAnchor:self.debugCard.bottomAnchor constant:-16]
    ]];
    
    [self.mainStackView addArrangedSubview:self.debugCard];
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
        [self.mainStackView.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor constant:16],
        [self.mainStackView.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor constant:-16],
        [self.mainStackView.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor constant:-20],
        [self.mainStackView.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor constant:-32]
    ]];
}

#pragma mark - UI助手方法

- (UILabel *)createSectionTitle:(NSString *)title emoji:(NSString *)emoji {
    UILabel *label = [[UILabel alloc] init];
    label.text = title;
    label.font = [UIFont boldSystemFontOfSize:20];
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

- (UILabel *)createInfoLabel:(NSString *)text {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.font = [UIFont systemFontOfSize:14];
    label.textColor = [UIColor labelColor];
    label.numberOfLines = 0;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
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

- (UIButton *)createDangerButton:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.backgroundColor = [UIColor systemRedColor];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    button.layer.cornerRadius = 12;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [button.heightAnchor constraintEqualToConstant:50].active = YES;
    return button;
}

#pragma mark - 操作方法

- (void)initializeEngine {
    [self appendOutput:@"开始初始化Wine引擎..."];
    self.initializeButton.enabled = NO;
    [self.initializeButton setTitle:@"🔄 初始化中..." forState:UIControlStateNormal];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        BOOL success = [self.executionEngine initializeWithViewController:self];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success) {
                self.isEngineInitialized = YES;
                self.statusLabel.text = @"✅ 引擎已就绪";
                self.statusLabel.textColor = [UIColor systemGreenColor];
                [self.initializeButton setTitle:@"✅ 初始化完成" forState:UIControlStateNormal];
                self.initializeButton.backgroundColor = [UIColor systemGreenColor];
                
                // 启用其他按钮
                self.createTestFilesButton.enabled = YES;
                self.selectFileButton.enabled = YES;
                
                [self appendOutput:@"Wine引擎初始化成功！可以开始运行程序了。"];
                [self updateSystemInfo];
            } else {
                self.statusLabel.text = @"❌ 初始化失败";
                self.statusLabel.textColor = [UIColor systemRedColor];
                [self.initializeButton setTitle:@"🚀 重新初始化" forState:UIControlStateNormal];
                self.initializeButton.enabled = YES;
                [self appendOutput:@"Wine引擎初始化失败，请检查日志并重试。"];
            }
            
            [self updateUI];
        });
    });
}

- (void)createTestFiles {
    [self appendOutput:@"创建测试文件..."];
    self.createTestFilesButton.enabled = NO;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self.testCreator createAllTestFiles];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.createTestFilesButton.enabled = YES;
            [self.createTestFilesButton setTitle:@"✅ 测试文件已创建" forState:UIControlStateNormal];
            self.createTestFilesButton.backgroundColor = [UIColor systemGreenColor];
            [self.createTestFilesButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            
            [self appendOutput:@"测试文件创建完成！包括简单测试、计算器和Hello World程序。"];
            
            // 显示提示
            [self showTestFilesCreatedAlert];
        });
    });
}

- (void)selectFile {
    [self appendOutput:@"打开文件选择器..."];
    
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

- (void)runProgram {
    if (!self.selectedFilePath) {
        [self appendOutput:@"错误：未选择文件"];
        return;
    }
    
    if (!self.isEngineInitialized) {
        [self appendOutput:@"错误：引擎未初始化"];
        return;
    }
    
    [self appendOutput:[NSString stringWithFormat:@"开始执行程序: %@", [self.selectedFilePath lastPathComponent]]];
    
    self.runButton.enabled = NO;
    self.stopButton.enabled = YES;
    self.selectFileButton.enabled = NO;
    
    // 清空Wine显示区域
    for (UIView *subview in self.wineDisplayView.subviews) {
        if (![subview isKindOfClass:[UILabel class]]) { // 保留占位符标签
            [subview removeFromSuperview];
        }
    }
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        ExecutionResult result = [self.executionEngine executeProgram:self.selectedFilePath];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self handleExecutionResult:result];
        });
    });
}

- (void)stopExecution {
    [self appendOutput:@"停止程序执行..."];
    [self.executionEngine stopExecution];
    
    self.runButton.enabled = YES;
    self.stopButton.enabled = NO;
    self.selectFileButton.enabled = YES;
}

- (void)dumpStates {
    [self appendOutput:@"=== 系统状态转储 ==="];
    [self.executionEngine dumpAllStates];
    [self appendOutput:@"状态转储完成，请查看控制台日志"];
}

- (void)showSystemInfo {
    NSDictionary *systemInfo = [self.executionEngine getSystemInfo];
    
    NSMutableString *info = [NSMutableString stringWithString:@"系统信息:\n\n"];
    for (NSString *key in systemInfo.allKeys) {
        [info appendFormat:@"%@: %@\n", key, systemInfo[key]];
    }
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"系统信息"
                                                                   message:info
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定"
                                                       style:UIAlertActionStyleDefault
                                                     handler:nil];
    [alert addAction:okAction];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showSettings {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"设置"
                                                                   message:@"选择操作"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    UIAlertAction *clearOutputAction = [UIAlertAction actionWithTitle:@"清空输出"
                                                                style:UIAlertActionStyleDefault
                                                              handler:^(UIAlertAction * action) {
        [self clearOutput];
    }];
    
    UIAlertAction *resetEngineAction = [UIAlertAction actionWithTitle:@"重置引擎"
                                                                style:UIAlertActionStyleDestructive
                                                              handler:^(UIAlertAction * action) {
        [self resetEngine];
    }];
    
    UIAlertAction *aboutAction = [UIAlertAction actionWithTitle:@"关于"
                                                          style:UIAlertActionStyleDefault
                                                        handler:^(UIAlertAction * action) {
        [self showAbout];
    }];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消"
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];
    
    [alert addAction:clearOutputAction];
    [alert addAction:resetEngineAction];
    [alert addAction:aboutAction];
    [alert addAction:cancelAction];
    
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - 帮助方法

- (void)updateUI {
    if (self.isEngineInitialized) {
        [self updateSystemInfo];
    }
}

- (void)updateSystemInfo {
    // 更新系统组件状态
    IOSJITEngine *jitEngine = [IOSJITEngine sharedEngine];
    Box64Engine *box64Engine = [Box64Engine sharedEngine];
    WineAPI *wineAPI = [WineAPI sharedAPI];
    
    self.jitStatusLabel.text = [NSString stringWithFormat:@"JIT引擎: %@",
                                jitEngine.isJITEnabled ? @"✅ 已启用" : @"❌ 未启用"];
    
    self.box64StatusLabel.text = [NSString stringWithFormat:@"Box64引擎: %@",
                                  box64Engine.isInitialized ? @"✅ 已初始化" : @"❌ 未初始化"];
    
    self.wineStatusLabel.text = [NSString stringWithFormat:@"Wine API: ✅ 已加载 (%lu窗口)",
                                 (unsigned long)wineAPI.windows.count];
}

- (void)showInitializationPrompt {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"欢迎使用 Wine for iOS"
                                                                   message:@"这是一个完整的Windows程序执行环境，基于Box64+Wine+JIT技术。\n\n首次使用需要初始化引擎，这可能需要几秒钟时间。"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *initAction = [UIAlertAction actionWithTitle:@"立即初始化"
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction * action) {
        [self initializeEngine];
    }];
    
    UIAlertAction *laterAction = [UIAlertAction actionWithTitle:@"稍后初始化"
                                                          style:UIAlertActionStyleCancel
                                                        handler:nil];
    
    [alert addAction:initAction];
    [alert addAction:laterAction];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showTestFilesCreatedAlert {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"测试文件创建完成"
                                                                   message:@"已创建以下测试程序：\n\n• simple_test.exe - 消息框测试\n• calculator.exe - GUI计算器\n• hello_world.exe - 控制台程序\n\n现在可以通过'选择EXE文件'来运行这些程序。"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"开始测试"
                                                       style:UIAlertActionStyleDefault
                                                     handler:^(UIAlertAction * action) {
        [self selectFile];
    }];
    
    UIAlertAction *laterAction = [UIAlertAction actionWithTitle:@"稍后测试"
                                                          style:UIAlertActionStyleCancel
                                                        handler:nil];
    
    [alert addAction:okAction];
    [alert addAction:laterAction];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)handleExecutionResult:(ExecutionResult)result {
    self.runButton.enabled = YES;
    self.stopButton.enabled = NO;
    self.selectFileButton.enabled = YES;
    
    switch (result) {
        case ExecutionResultSuccess:
            [self appendOutput:@"✅ 程序执行成功完成"];
            break;
        case ExecutionResultFailure:
            [self appendOutput:@"❌ 程序执行失败"];
            break;
        case ExecutionResultInvalidFile:
            [self appendOutput:@"❌ 无效的PE文件"];
            break;
        case ExecutionResultMemoryError:
            [self appendOutput:@"❌ 内存分配失败"];
            break;
        case ExecutionResultInitError:
            [self appendOutput:@"❌ 引擎初始化错误"];
            break;
    }
}

- (void)clearOutput {
    self.outputTextView.text = @"=== Wine for iOS 执行日志 ===\n";
}

- (void)resetEngine {
    [self.executionEngine cleanup];
    self.isEngineInitialized = NO;
    
    self.statusLabel.text = @"等待初始化...";
    self.statusLabel.textColor = [UIColor labelColor];
    
    [self.initializeButton setTitle:@"🚀 初始化引擎" forState:UIControlStateNormal];
    self.initializeButton.backgroundColor = [UIColor systemBlueColor];
    self.initializeButton.enabled = YES;
    
    self.createTestFilesButton.enabled = NO;
    self.selectFileButton.enabled = NO;
    self.runButton.enabled = NO;
    
    [self appendOutput:@"引擎已重置，需要重新初始化"];
}

- (void)showAbout {
    NSString *message = @"Wine for iOS v2.0\n\n"
                       @"完整的Windows程序执行环境\n\n"
                       @"技术栈：\n"
                       @"• iOS JIT编译引擎\n"
                       @"• Box64 x86→ARM64转换\n"
                       @"• Wine Windows API兼容层\n"
                       @"• 完整GUI支持\n\n"
                       @"支持：\n"
                       @"• 控制台程序\n"
                       @"• GUI应用程序\n"
                       @"• 简单游戏\n\n"
                       @"架构: ARM64\n"
                       @"iOS版本: 16.0+";
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"关于 Wine for iOS"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定"
                                                       style:UIAlertActionStyleDefault
                                                     handler:nil];
    
    [alert addAction:okAction];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)appendOutput:(NSString *)message {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setTimeStyle:NSDateFormatterMediumStyle];
    NSString *timestamp = [formatter stringFromDate:[NSDate date]];
    
    NSString *logEntry = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];
    self.outputTextView.text = [self.outputTextView.text stringByAppendingString:logEntry];
    
    // 滚动到底部
    NSRange range = NSMakeRange(self.outputTextView.text.length - 1, 1);
    [self.outputTextView scrollRangeToVisible:range];
    
    NSLog(@"%@", logEntry);
}

#pragma mark - CompleteExecutionEngineDelegate

- (void)executionEngine:(CompleteExecutionEngine *)engine didStartExecution:(NSString *)programPath {
    [self appendOutput:[NSString stringWithFormat:@"开始执行: %@", [programPath lastPathComponent]]];
}

- (void)executionEngine:(CompleteExecutionEngine *)engine didFinishExecution:(NSString *)programPath result:(ExecutionResult)result {
    [self appendOutput:[NSString stringWithFormat:@"执行完成: %@ (结果: %ld)", [programPath lastPathComponent], (long)result]];
    [self handleExecutionResult:result];
}

- (void)executionEngine:(CompleteExecutionEngine *)engine didReceiveOutput:(NSString *)output {
    [self appendOutput:[NSString stringWithFormat:@"程序输出: %@", output]];
}

- (void)executionEngine:(CompleteExecutionEngine *)engine didEncounterError:(NSError *)error {
    [self appendOutput:[NSString stringWithFormat:@"执行错误: %@", error.localizedDescription]];
}

- (void)executionEngine:(CompleteExecutionEngine *)engine didUpdateProgress:(float)progress status:(NSString *)status {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.progressView.progress = progress;
        self.engineStatusLabel.text = status;
    });
}

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (urls.count > 0) {
        NSURL *selectedURL = urls.firstObject;
        
        // 获取安全访问权限
        BOOL startedAccessing = [selectedURL startAccessingSecurityScopedResource];
        
        if (startedAccessing) {
            NSString *fileName = selectedURL.lastPathComponent;
            NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
            
            // 修复：创建唯一的文件名避免冲突
            NSString *fileExtension = [fileName pathExtension];
            NSString *baseName = [fileName stringByDeletingPathExtension];
            NSString *uniqueFileName = fileName;
            NSString *destinationPath = [documentsPath stringByAppendingPathComponent:uniqueFileName];
            
            NSFileManager *fileManager = [NSFileManager defaultManager];
            int counter = 1;
            
            // 如果文件已存在，生成唯一名称
            while ([fileManager fileExistsAtPath:destinationPath]) {
                uniqueFileName = [NSString stringWithFormat:@"%@_%d.%@", baseName, counter, fileExtension];
                destinationPath = [documentsPath stringByAppendingPathComponent:uniqueFileName];
                counter++;
            }
            
            NSError *error;
            
            // 修复：使用copyItemAtURL而不是moveItemAtURL，保留原文件
            if ([fileManager copyItemAtURL:selectedURL toURL:[NSURL fileURLWithPath:destinationPath] error:&error]) {
                self.selectedFilePath = destinationPath;
                self.runButton.enabled = YES;
                
                // 更新文件信息
                self.selectedFileLabel.text = [NSString stringWithFormat:@"已选择: %@", uniqueFileName];
                self.selectedFileLabel.textColor = [UIColor systemGreenColor];
                
                // 获取文件详细信息
                [self analyzeSelectedFile:destinationPath];
                
                [self appendOutput:[NSString stringWithFormat:@"已复制文件到Documents: %@", uniqueFileName]];
                
                // 修复：添加文件大小和路径信息
                NSDictionary *attributes = [fileManager attributesOfItemAtPath:destinationPath error:nil];
                if (attributes) {
                    NSNumber *fileSize = attributes[NSFileSize];
                    [self appendOutput:[NSString stringWithFormat:@"文件大小: %@", [self formatFileSize:fileSize.longLongValue]]];
                    [self appendOutput:[NSString stringWithFormat:@"保存路径: %@", destinationPath]];
                }
                
            } else {
                [self appendOutput:[NSString stringWithFormat:@"文件复制失败: %@", error.localizedDescription]];
                
                // 如果复制失败，尝试直接使用原文件（仅限测试）
                if ([selectedURL.scheme isEqualToString:@"file"]) {
                    self.selectedFilePath = selectedURL.path;
                    self.runButton.enabled = YES;
                    self.selectedFileLabel.text = [NSString stringWithFormat:@"已选择（原位置）: %@", fileName];
                    self.selectedFileLabel.textColor = [UIColor systemOrangeColor];
                    [self appendOutput:@"警告: 使用原文件位置，可能在应用重启后丢失访问权限"];
                }
            }
            
            [selectedURL stopAccessingSecurityScopedResource];
        } else {
            [self appendOutput:@"无法获取文件访问权限"];
        }
    }
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    [self appendOutput:@"文件选择已取消"];
}

#pragma mark - 文件处理辅助方法

- (NSString *)formatFileSize:(long long)bytes {
    if (bytes < 1024) {
        return [NSString stringWithFormat:@"%lld B", bytes];
    } else if (bytes < 1024 * 1024) {
        return [NSString stringWithFormat:@"%.1f KB", bytes / 1024.0];
    } else if (bytes < 1024 * 1024 * 1024) {
        return [NSString stringWithFormat:@"%.1f MB", bytes / (1024.0 * 1024.0)];
    } else {
        return [NSString stringWithFormat:@"%.1f GB", bytes / (1024.0 * 1024.0 * 1024.0)];
    }
}

- (void)analyzeSelectedFile:(NSString *)filePath {
    NSError *error;
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:&error];
    
    if (attributes) {
        NSNumber *fileSize = attributes[NSFileSize];
        NSDate *modDate = attributes[NSFileModificationDate];
        
        NSString *sizeString = [self formatFileSize:fileSize.longLongValue];
        
        NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
        [dateFormatter setDateStyle:NSDateFormatterShortStyle];
        [dateFormatter setTimeStyle:NSDateFormatterShortStyle];
        
        self.fileDetailsLabel.text = [NSString stringWithFormat:@"文件大小: %@\n修改时间: %@\n文件路径: %@",
                                      sizeString, [dateFormatter stringFromDate:modDate], filePath];
        
        // 检查文件是否可读
        if ([[NSFileManager defaultManager] isReadableFileAtPath:filePath]) {
            [self appendOutput:@"文件权限检查: ✅ 可读"];
        } else {
            [self appendOutput:@"文件权限检查: ❌ 不可读"];
        }
        
        // 尝试读取PE头
        [self validatePEFile:filePath];
        
    } else {
        self.fileDetailsLabel.text = [NSString stringWithFormat:@"无法获取文件信息: %@", error.localizedDescription];
        [self appendOutput:[NSString stringWithFormat:@"文件分析失败: %@", error.localizedDescription]];
    }
}

- (void)validatePEFile:(NSString *)filePath {
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingAtPath:filePath];
    if (!fileHandle) {
        [self appendOutput:@"PE验证: ❌ 无法打开文件"];
        return;
    }
    
    @try {
        // 读取DOS头
        NSData *dosHeader = [fileHandle readDataOfLength:64];
        if (dosHeader.length >= 2) {
            const unsigned char *bytes = (const unsigned char *)[dosHeader bytes];
            if (bytes[0] == 'M' && bytes[1] == 'Z') {
                [self appendOutput:@"PE验证: ✅ 有效的PE文件 (MZ签名)"];
                
                // 读取PE头信息
                if (dosHeader.length >= 60) {
                    uint32_t peOffset = *(uint32_t *)(bytes + 60);
                    [fileHandle seekToFileOffset:peOffset];
                    NSData *peSignature = [fileHandle readDataOfLength:4];
                    
                    if (peSignature.length == 4) {
                        const unsigned char *peBytes = (const unsigned char *)[peSignature bytes];
                        if (peBytes[0] == 'P' && peBytes[1] == 'E') {
                            [self appendOutput:@"PE验证: ✅ PE签名确认"];
                            
                            // 读取机器类型
                            NSData *machineType = [fileHandle readDataOfLength:2];
                            if (machineType.length == 2) {
                                uint16_t machine = *(uint16_t *)[machineType bytes];
                                NSString *architecture = [self getArchitectureString:machine];
                                [self appendOutput:[NSString stringWithFormat:@"目标架构: %@", architecture]];
                            }
                        }
                    }
                }
            } else {
                [self appendOutput:@"PE验证: ❌ 不是有效的PE文件"];
            }
        }
    } @catch (NSException *exception) {
        [self appendOutput:[NSString stringWithFormat:@"PE验证异常: %@", exception.reason]];
    } @finally {
        [fileHandle closeFile];
    }
}

- (NSString *)getArchitectureString:(uint16_t)machine {
    switch (machine) {
        case 0x014c:
            return @"i386 (32位)";
        case 0x8664:
            return @"x86_64 (64位)";
        case 0x01c0:
            return @"ARM";
        case 0xaa64:
            return @"ARM64";
        default:
            return [NSString stringWithFormat:@"未知架构 (0x%04x)", machine];
    }
}

@end
