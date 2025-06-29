#import "WineTestViewController.h"

@interface WineTestViewController ()
@property (nonatomic, strong) WineTestSuite *testSuite;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIButton *runAllButton;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UITextView *logTextView;
@property (nonatomic, strong) NSMutableArray<WineTestCase *> *testResults;
@end

@implementation WineTestViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"Wine 库测试";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    [self setupTestSuite];
    [self setupUI];
}

- (void)setupTestSuite {
    self.testSuite = [[WineTestSuite alloc] init];
    self.testSuite.delegate = self;
    self.testResults = [NSMutableArray array];
}

- (void)setupUI {
    // 状态标签
    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.text = @"准备测试Wine库";
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.font = [UIFont boldSystemFontOfSize:16];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.statusLabel];
    
    // 进度条
    self.progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.progressView.progress = 0.0;
    self.progressView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.progressView];
    
    // 运行所有测试按钮
    self.runAllButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.runAllButton setTitle:@"运行所有测试" forState:UIControlStateNormal];
    self.runAllButton.backgroundColor = [UIColor systemBlueColor];
    [self.runAllButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.runAllButton.layer.cornerRadius = 8;
    self.runAllButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [self.runAllButton addTarget:self action:@selector(runAllTests) forControlEvents:UIControlEventTouchUpInside];
    self.runAllButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.runAllButton];
    
    // 测试结果表格
    self.tableView = [[UITableView alloc] init];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"TestCell"];
    [self.view addSubview:self.tableView];
    
    // 日志文本视图
    self.logTextView = [[UITextView alloc] init];
    self.logTextView.backgroundColor = [UIColor blackColor];
    self.logTextView.textColor = [UIColor greenColor];
    self.logTextView.font = [UIFont fontWithName:@"Courier" size:12];
    self.logTextView.editable = NO;
    self.logTextView.text = @"=== Wine 测试日志 ===\n";
    self.logTextView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.logTextView];
    
    // 设置约束
    [NSLayoutConstraint activateConstraints:@[
        // 状态标签
        [self.statusLabel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:20],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        
        // 进度条
        [self.progressView.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:10],
        [self.progressView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.progressView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        
        // 运行按钮
        [self.runAllButton.topAnchor constraintEqualToAnchor:self.progressView.bottomAnchor constant:20],
        [self.runAllButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.runAllButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.runAllButton.heightAnchor constraintEqualToConstant:44],
        
        // 表格视图
        [self.tableView.topAnchor constraintEqualToAnchor:self.runAllButton.bottomAnchor constant:20],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.heightAnchor constraintEqualToConstant:250],
        
        // 日志视图
        [self.logTextView.topAnchor constraintEqualToAnchor:self.tableView.bottomAnchor constant:10],
        [self.logTextView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10],
        [self.logTextView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10],
        [self.logTextView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-10]
    ]];
}

#pragma mark - Actions

- (void)runAllTests {
    [self.testResults removeAllObjects];
    [self.tableView reloadData];
    
    self.runAllButton.enabled = NO;
    [self.runAllButton setTitle:@"测试中..." forState:UIControlStateNormal];
    self.progressView.progress = 0.0;
    
    [self appendLog:@"开始运行Wine库测试套件...\n"];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self.testSuite runAllTests];
    });
}

- (void)runSingleTest:(NSString *)testName {
    [self appendLog:[NSString stringWithFormat:@"运行单个测试: %@\n", testName]];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self.testSuite runTest:testName];
    });
}

#pragma mark - WineTestSuiteDelegate

- (void)testSuite:(id)suite didStartTest:(WineTestCase *)testCase {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.statusLabel.text = [NSString stringWithFormat:@"正在测试: %@", testCase.description];
        [self appendLog:[NSString stringWithFormat:@"[开始] %@\n", testCase.name]];
    });
}

- (void)testSuite:(id)suite didCompleteTest:(WineTestCase *)testCase {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.testResults addObject:testCase];
        
        // 更新进度
        float progress = (float)self.testResults.count / (float)self.testSuite.totalTests;
        self.progressView.progress = progress;
        
        // 更新表格
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:self.testResults.count - 1 inSection:0];
        [self.tableView insertRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
        
        // 添加日志
        NSString *resultStr = testCase.result == WineTestResultPassed ? @"通过" : @"失败";
        NSString *logMsg = [NSString stringWithFormat:@"[%@] %@ (%.2fs)", resultStr, testCase.name, testCase.executionTime];
        if (testCase.errorMessage) {
            logMsg = [logMsg stringByAppendingFormat:@" - %@", testCase.errorMessage];
        }
        [self appendLog:[logMsg stringByAppendingString:@"\n"]];
    });
}

- (void)testSuite:(id)suite didCompleteAllTests:(NSArray<WineTestCase *> *)results {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.runAllButton.enabled = YES;
        [self.runAllButton setTitle:@"重新运行测试" forState:UIControlStateNormal];
        
        NSInteger passed = 0;
        NSInteger failed = 0;
        for (WineTestCase *testCase in results) {
            if (testCase.result == WineTestResultPassed) {
                passed++;
            } else if (testCase.result == WineTestResultFailed) {
                failed++;
            }
        }
        
        NSString *summary = [NSString stringWithFormat:@"测试完成: %ld通过, %ld失败", (long)passed, (long)failed];
        self.statusLabel.text = summary;
        
        // 更新按钮颜色
        if (failed == 0) {
            self.runAllButton.backgroundColor = [UIColor systemGreenColor];
        } else {
            self.runAllButton.backgroundColor = [UIColor systemOrangeColor];
        }
        
        [self appendLog:[NSString stringWithFormat:@"\n=== 测试总结 ===\n%@\n", summary]];
        
        // 如果有失败，显示详细信息
        if (failed > 0) {
            [self appendLog:@"失败详情:\n"];
            for (WineTestCase *testCase in results) {
                if (testCase.result == WineTestResultFailed) {
                    [self appendLog:[NSString stringWithFormat:@"  %@: %@\n", testCase.name, testCase.errorMessage]];
                }
            }
        }
        
        [self showTestCompletionAlert:passed failed:failed];
    });
}

#pragma mark - UITableViewDataSource & Delegate

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.testResults.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"TestCell" forIndexPath:indexPath];
    
    WineTestCase *testCase = self.testResults[indexPath.row];
    
    cell.textLabel.text = [NSString stringWithFormat:@"%@ - %@", testCase.name, testCase.description];
    cell.textLabel.font = [UIFont systemFontOfSize:14];
    
    switch (testCase.result) {
        case WineTestResultPassed:
            cell.accessoryType = UITableViewCellAccessoryCheckmark;
            cell.textLabel.textColor = [UIColor systemGreenColor];
            break;
        case WineTestResultFailed:
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.textLabel.textColor = [UIColor systemRedColor];
            break;
        case WineTestResultSkipped:
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.textLabel.textColor = [UIColor systemOrangeColor];
            break;
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    WineTestCase *testCase = self.testResults[indexPath.row];
    
    NSString *message = [NSString stringWithFormat:@"测试: %@\n描述: %@\n结果: %@\n执行时间: %.2fs",
                        testCase.name,
                        testCase.description,
                        testCase.result == WineTestResultPassed ? @"通过" : @"失败",
                        testCase.executionTime];
    
    if (testCase.errorMessage) {
        message = [message stringByAppendingFormat:@"\n错误: %@", testCase.errorMessage];
    }
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"测试详情"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    // 重新运行单个测试
    UIAlertAction *retryAction = [UIAlertAction actionWithTitle:@"重新运行"
                                                          style:UIAlertActionStyleDefault
                                                        handler:^(UIAlertAction * _Nonnull action) {
        [self runSingleTest:testCase.name];
    }];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定"
                                                       style:UIAlertActionStyleCancel
                                                     handler:nil];
    
    [alert addAction:retryAction];
    [alert addAction:okAction];
    
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Helper Methods

- (void)appendLog:(NSString *)message {
    NSString *timestamp = [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                         dateStyle:NSDateFormatterNoStyle
                                                         timeStyle:NSDateFormatterMediumStyle];
    NSString *logEntry = [NSString stringWithFormat:@"[%@] %@", timestamp, message];
    
    self.logTextView.text = [self.logTextView.text stringByAppendingString:logEntry];
    
    // 滚动到底部
    NSRange range = NSMakeRange(self.logTextView.text.length - 1, 1);
    [self.logTextView scrollRangeToVisible:range];
}

- (void)showTestCompletionAlert:(NSInteger)passed failed:(NSInteger)failed {
    NSString *title;
    NSString *message;
    
    if (failed == 0) {
        title = @"🎉 测试全部通过！";
        message = @"Wine库已经成功集成，所有功能测试通过。现在可以继续进行Box64集成了。";
    } else {
        title = @"⚠️ 部分测试失败";
        message = [NSString stringWithFormat:@"有 %ld 个测试失败。请查看日志了解详细信息，并根据故障排除指南解决问题。", (long)failed];
    }
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定"
                                                       style:UIAlertActionStyleDefault
                                                     handler:nil];
    
    if (failed > 0) {
        UIAlertAction *troubleshootAction = [UIAlertAction actionWithTitle:@"故障排除"
                                                                     style:UIAlertActionStyleDefault
                                                                   handler:^(UIAlertAction * _Nonnull action) {
            [self showTroubleshootingGuide];
        }];
        [alert addAction:troubleshootAction];
    }
    
    [alert addAction:okAction];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showTroubleshootingGuide {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"故障排除指南"
                                                                   message:@"请选择对应的问题类型："
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    UIAlertAction *filesAction = [UIAlertAction actionWithTitle:@"库文件问题"
                                                          style:UIAlertActionStyleDefault
                                                        handler:^(UIAlertAction * _Nonnull action) {
        [self showFilesTroubleshooting];
    }];
    
    UIAlertAction *loadAction = [UIAlertAction actionWithTitle:@"加载问题"
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction * _Nonnull action) {
        [self showLoadTroubleshooting];
    }];
    
    UIAlertAction *execAction = [UIAlertAction actionWithTitle:@"执行问题"
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction * _Nonnull action) {
        [self showExecutionTroubleshooting];
    }];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消"
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];
    
    [alert addAction:filesAction];
    [alert addAction:loadAction];
    [alert addAction:execAction];
    [alert addAction:cancelAction];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showFilesTroubleshooting {
    NSString *message = @"库文件问题解决方案：\n\n"
                       @"1. 确认已运行wine_build_script.sh\n"
                       @"2. 检查WineLibs文件夹是否存在\n"
                       @"3. 重新运行xcode_integration_script.sh\n"
                       @"4. 清理项目并重新构建\n"
                       @"5. 检查Bundle是否正确添加到项目";
    
    [self showTroubleshootingAlert:@"库文件问题" message:message];
}

- (void)showLoadTroubleshooting {
    NSString *message = @"库加载问题解决方案：\n\n"
                       @"1. 检查库文件权限\n"
                       @"2. 确认iOS版本≥16.0\n"
                       @"3. 检查架构是否为ARM64\n"
                       @"4. 查看详细错误信息\n"
                       @"5. 重启应用重试";
    
    [self showTroubleshootingAlert:@"库加载问题" message:message];
}

- (void)showExecutionTroubleshooting {
    NSString *message = @"执行问题解决方案：\n\n"
                       @"1. 检查Wine环境变量\n"
                       @"2. 确认容器已正确创建\n"
                       @"3. 检查文件权限\n"
                       @"4. 查看执行日志\n"
                       @"5. 尝试简单的测试程序";
    
    [self showTroubleshootingAlert:@"执行问题" message:message];
}

- (void)showTroubleshootingAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定"
                                                       style:UIAlertActionStyleDefault
                                                     handler:nil];
    
    [alert addAction:okAction];
    
    [self presentViewController:alert animated:YES completion:nil];
}

@end
