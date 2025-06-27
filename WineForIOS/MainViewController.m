#import "MainViewController.h"
#import "WineContainer.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface MainViewController () <UIDocumentPickerDelegate>
@property (nonatomic, strong) UITextView *logTextView;
@property (nonatomic, strong) UIButton *selectFileButton;
@property (nonatomic, strong) UIButton *runButton;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) WineContainer *container;
@property (nonatomic, strong) ExecutionEngine *executionEngine;
@property (nonatomic, strong) NSString *selectedFilePath;
@end

@implementation MainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Wine for iOS";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    [self setupUI];
    [self setupWineContainer];
}

- (void)setupUI {
    // Status Label
    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.text = @"Ready";
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.statusLabel];
    
    // Select File Button
    self.selectFileButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.selectFileButton setTitle:@"Select EXE File" forState:UIControlStateNormal];
    [self.selectFileButton addTarget:self action:@selector(selectFileButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    self.selectFileButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.selectFileButton];
    
    // Run Button
    self.runButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.runButton setTitle:@"Run Program" forState:UIControlStateNormal];
    [self.runButton addTarget:self action:@selector(runButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    self.runButton.enabled = NO;
    self.runButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.runButton];
    
    // Log Text View
    self.logTextView = [[UITextView alloc] init];
    self.logTextView.editable = NO;
    self.logTextView.font = [UIFont fontWithName:@"Courier" size:12];
    self.logTextView.backgroundColor = [UIColor blackColor];
    self.logTextView.textColor = [UIColor greenColor];
    self.logTextView.text = @"Wine for iOS - Ready\n";
    self.logTextView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.logTextView];
    
    // Layout
    [NSLayoutConstraint activateConstraints:@[
        [self.statusLabel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:20],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        
        [self.selectFileButton.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:20],
        [self.selectFileButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.selectFileButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.selectFileButton.heightAnchor constraintEqualToConstant:44],
        
        [self.runButton.topAnchor constraintEqualToAnchor:self.selectFileButton.bottomAnchor constant:10],
        [self.runButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.runButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.runButton.heightAnchor constraintEqualToConstant:44],
        
        [self.logTextView.topAnchor constraintEqualToAnchor:self.runButton.bottomAnchor constant:20],
        [self.logTextView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.logTextView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.logTextView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-20]
    ]];
}

- (void)setupWineContainer {
    self.container = [[WineContainer alloc] initWithName:@"default"];
    self.executionEngine = [[ExecutionEngine alloc] initWithContainer:self.container];
    self.executionEngine.delegate = self;
    
    [self appendToLog:@"Setting up Wine container..."];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        BOOL success = [self.container createContainer];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success) {
                [self appendToLog:@"Wine container created successfully"];
                self.statusLabel.text = @"Container Ready";
            } else {
                [self appendToLog:@"Failed to create Wine container"];
                self.statusLabel.text = @"Container Error";
            }
        });
    });
}

- (void)selectFileButtonTapped {
    UIDocumentPickerViewController *documentPicker = [[UIDocumentPickerViewController alloc]
                                                      initForOpeningContentTypes:@[UTTypeExecutable, UTTypeItem]];
    documentPicker.delegate = self;
    documentPicker.allowsMultipleSelection = NO;
    [self presentViewController:documentPicker animated:YES completion:nil];
}

- (void)runButtonTapped {
    if (self.selectedFilePath) {
        [self.executionEngine loadExecutable:self.selectedFilePath];
        [self.executionEngine startExecution];
    }
}

- (void)appendToLog:(NSString *)message {
    NSString *timestamp = [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                         dateStyle:NSDateFormatterNoStyle
                                                         timeStyle:NSDateFormatterMediumStyle];
    NSString *logEntry = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];
    self.logTextView.text = [self.logTextView.text stringByAppendingString:logEntry];
    
    // 滚动到底部
    NSRange range = NSMakeRange(self.logTextView.text.length - 1, 1);
    [self.logTextView scrollRangeToVisible:range];
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
            [[NSFileManager defaultManager] removeItemAtPath:destinationPath error:nil]; // 删除已存在的文件
            
            if ([[NSFileManager defaultManager] copyItemAtURL:selectedURL toURL:[NSURL fileURLWithPath:destinationPath] error:&error]) {
                self.selectedFilePath = destinationPath;
                self.runButton.enabled = YES;
                [self appendToLog:[NSString stringWithFormat:@"Selected file: %@", fileName]];
                self.statusLabel.text = [NSString stringWithFormat:@"Ready: %@", fileName];
            } else {
                [self appendToLog:[NSString stringWithFormat:@"Failed to copy file: %@", error.localizedDescription]];
            }
            
            [selectedURL stopAccessingSecurityScopedResource];
        }
    }
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    [self appendToLog:@"File selection cancelled"];
}

#pragma mark - ExecutionEngineDelegate

- (void)executionEngine:(ExecutionEngine *)engine didStartProgram:(NSString *)programPath {
    [self appendToLog:[NSString stringWithFormat:@"Started: %@", [programPath lastPathComponent]]];
    self.statusLabel.text = @"Running...";
    self.runButton.enabled = NO;
}

- (void)executionEngine:(ExecutionEngine *)engine didFinishProgram:(NSString *)programPath withExitCode:(int)exitCode {
    [self appendToLog:[NSString stringWithFormat:@"Finished: %@ (exit code: %d)", [programPath lastPathComponent], exitCode]];
    self.statusLabel.text = @"Finished";
    self.runButton.enabled = YES;
}

- (void)executionEngine:(ExecutionEngine *)engine didEncounterError:(NSError *)error {
    [self appendToLog:[NSString stringWithFormat:@"Error: %@", error.localizedDescription]];
    self.statusLabel.text = @"Error";
    self.runButton.enabled = YES;
}

- (void)executionEngine:(ExecutionEngine *)engine didReceiveOutput:(NSString *)output {
    [self appendToLog:[NSString stringWithFormat:@"Output: %@", output]];
}

@end

// ==================== WineGraphicsAdapter.h ====================
#import <UIKit/UIKit.h>
#import <Metal/Metal.h>

NS_ASSUME_NONNULL_BEGIN

@interface WineGraphicsAdapter : NSObject

@property (nonatomic, weak) UIView *displayView;
@property (nonatomic, readonly) CGSize virtualScreenSize;

- (instancetype)initWithDisplayView:(UIView *)displayView;
- (BOOL)initializeGraphicsContext;
- (void)handleWineGraphicsOutput:(NSData *)frameData size:(CGSize)size;
- (void)forwardTouchEvent:(UITouch *)touch withType:(UITouchPhase)phase;
- (void)forwardKeyboardInput:(NSString *)text;
- (void)setVirtualScreenSize:(CGSize)size;

@end

NS_ASSUME_NONNULL_END
