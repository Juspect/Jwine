#import "WineAPI.h"
#import <pthread.h>
#import <unistd.h>

// 线程安全宏定义
#define ENSURE_MAIN_THREAD(block) \
    if ([NSThread isMainThread]) { \
        block(); \
    } else { \
        dispatch_async(dispatch_get_main_queue(), block); \
    }

#define ENSURE_MAIN_THREAD_SYNC(block) \
    if ([NSThread isMainThread]) { \
        block(); \
    } else { \
        dispatch_sync(dispatch_get_main_queue(), block); \
    }

@implementation WineWindow
- (instancetype)init {
    self = [super init];
    if (self) {
        _children = [NSMutableArray array];
        _isVisible = NO;
        _rect = (RECT){0, 0, 0, 0};
    }
    return self;
}
@end

@implementation WineDC
- (instancetype)init {
    self = [super init];
    if (self) {
        _currentColor = [UIColor blackColor];
        _currentFont = [UIFont systemFontOfSize:12];
        _clipRect = CGRectZero;
    }
    return self;
}
@end

@interface WineAPI()
@property (nonatomic, assign) DWORD lastError;
@property (nonatomic, assign) NSUInteger nextWindowHandle;
@property (nonatomic, assign) NSUInteger nextDCHandle;
@property (nonatomic, assign) BOOL quitMessagePosted;
@end

@implementation WineAPI

- (BOOL)initializeWineAPI {
    NSLog(@"[WineAPI] Initializing Wine API system...");
    
    // 重置错误状态
    _lastError = 0;
    
    // 确保集合已初始化
    if (!_windows) {
        _windows = [NSMutableDictionary dictionary];
    }
    if (!_deviceContexts) {
        _deviceContexts = [NSMutableDictionary dictionary];
    }
    if (!_windowClasses) {
        _windowClasses = [NSMutableDictionary dictionary];
    }
    if (!_messageQueue) {
        _messageQueue = [NSMutableArray array];
    }
    
    // 重置句柄生成器
    _nextWindowHandle = 1000;
    _nextDCHandle = 2000;
    _quitMessagePosted = NO;
    
    // 注册基础窗口类
    [self registerBasicWindowClasses];
    
    NSLog(@"[WineAPI] Wine API initialization completed successfully");
    return YES;
}

// 🔧 新增：注册基础窗口类
- (void)registerBasicWindowClasses {
    NSLog(@"[WineAPI] Registering basic window classes...");
    
    // 注册一些基础的窗口类，避免运行时找不到
    NSArray *basicClasses = @[@"Button", @"Static", @"Edit", @"ListBox", @"ComboBox", @"#32770"]; // #32770 是对话框类
    
    for (NSString *className in basicClasses) {
        NSDictionary *classInfo = @{
            @"style": @(0),
            @"wndProc": [NSValue valueWithPointer:NULL],
            @"cbClsExtra": @(0),
            @"cbWndExtra": @(0),
            @"hInstance": [NSValue valueWithPointer:NULL],
            @"hIcon": [NSValue valueWithPointer:NULL],
            @"hCursor": [NSValue valueWithPointer:NULL],
            @"hbrBackground": [NSValue valueWithPointer:NULL]
        };
        
        _windowClasses[className] = classInfo;
        NSLog(@"[WineAPI] Registered basic window class: %@", className);
    }
}

+ (instancetype)sharedAPI {
    static WineAPI *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[WineAPI alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _windows = [NSMutableDictionary dictionary];
        _deviceContexts = [NSMutableDictionary dictionary];
        _windowClasses = [NSMutableDictionary dictionary];
        _messageQueue = [NSMutableArray array];
        _nextWindowHandle = 1000;
        _nextDCHandle = 2000;
        _lastError = 0;
        _quitMessagePosted = NO;
    }
    return self;
}

#pragma mark - 线程安全辅助方法

+ (void)showAlertWithTitle:(NSString *)title message:(NSString *)message type:(DWORD)uType {
    ENSURE_MAIN_THREAD(^{
        UIViewController *rootVC = [WineAPI sharedAPI].rootViewController;
        if (!rootVC) {
            NSLog(@"[WineAPI] No root view controller available for alert");
            return;
        }
        
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        
        if (uType & MB_YESNO) {
            [alert addAction:[UIAlertAction actionWithTitle:@"Yes" style:UIAlertActionStyleDefault handler:nil]];
            [alert addAction:[UIAlertAction actionWithTitle:@"No" style:UIAlertActionStyleCancel handler:nil]];
        } else if (uType & MB_OKCANCEL) {
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        } else {
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        }
        
        [rootVC presentViewController:alert animated:YES completion:nil];
    });
}

#pragma mark - 内部辅助方法

- (HWND)generateWindowHandle {
    return (HWND)(uintptr_t)_nextWindowHandle++;
}

- (HDC)generateDCHandle {
    return (HDC)(uintptr_t)_nextDCHandle++;
}

- (WineWindow *)getWindow:(HWND)hwnd {
    return _windows[@((uintptr_t)hwnd)];
}

- (WineDC *)getDC:(HDC)hdc {
    return _deviceContexts[@((uintptr_t)hdc)];
}

- (void)postMessage:(HWND)hwnd message:(DWORD)message wParam:(WPARAM)wParam lParam:(LPARAM)lParam {
    NSDictionary *msg = @{
        @"hwnd": @((uintptr_t)hwnd),
        @"message": @(message),
        @"wParam": @(wParam),
        @"lParam": @(lParam),
        @"time": @([[NSDate date] timeIntervalSince1970] * 1000)
    };
    
    [_messageQueue addObject:msg];
    NSLog(@"[WineAPI] Posted message 0x%X to window %p", message, hwnd);
}

@end

#pragma mark - KERNEL32 API实现

DWORD GetLastError(void) {
    return [WineAPI sharedAPI].lastError;
}

void SetLastError(DWORD error) {
    [WineAPI sharedAPI].lastError = error;
}

DWORD GetCurrentThreadId(void) {
    pthread_t thread = pthread_self();
    return (DWORD)((uintptr_t)thread & 0xFFFFFFFF);
}

DWORD GetCurrentProcessId(void) {
    return (DWORD)getpid();
}

#pragma mark - USER32 API实现

BOOL RegisterClass(const WNDCLASS *lpWndClass) {
    if (!lpWndClass || !lpWndClass->lpszClassName) {
        SetLastError(87); // ERROR_INVALID_PARAMETER
        return FALSE;
    }
    
    WineAPI *api = [WineAPI sharedAPI];
    NSString *className = [NSString stringWithUTF8String:lpWndClass->lpszClassName];
    
    NSDictionary *classInfo = @{
        @"style": @(lpWndClass->style),
        @"wndProc": [NSValue valueWithPointer:lpWndClass->lpfnWndProc],
        @"cbClsExtra": @(lpWndClass->cbClsExtra),
        @"cbWndExtra": @(lpWndClass->cbWndExtra),
        @"hInstance": [NSValue valueWithPointer:lpWndClass->hInstance],
        @"hIcon": [NSValue valueWithPointer:lpWndClass->hIcon],
        @"hCursor": [NSValue valueWithPointer:lpWndClass->hCursor],
        @"hbrBackground": [NSValue valueWithPointer:lpWndClass->hbrBackground]
    };
    
    api.windowClasses[className] = classInfo;
    
    NSLog(@"[WineAPI] Registered window class: %@", className);
    return TRUE;
}

HWND CreateWindow(LPCSTR lpClassName, LPCSTR lpWindowName, DWORD dwStyle,
                 int x, int y, int nWidth, int nHeight,
                 HWND hWndParent, HMENU hMenu, HINSTANCE hInstance, LPVOID lpParam) {
    
    if (!lpClassName) {
        SetLastError(87); // ERROR_INVALID_PARAMETER
        return (HWND)0;
    }
    
    WineAPI *api = [WineAPI sharedAPI];
    NSString *className = [NSString stringWithUTF8String:lpClassName];
    
    // 检查窗口类是否已注册
    NSDictionary *classInfo = api.windowClasses[className];
    if (!classInfo) {
        NSLog(@"[WineAPI] Window class not found: %@", className);
        SetLastError(1407); // ERROR_CLASS_DOES_NOT_EXIST
        return (HWND)0;
    }
    
    // 创建Wine窗口对象（只创建数据结构，不创建UI）
    WineWindow *window = [[WineWindow alloc] init];
    window.className = className;
    window.windowText = lpWindowName ? [NSString stringWithUTF8String:lpWindowName] : @"";
    window.style = dwStyle;
    window.rect = (RECT){x, y, x + nWidth, y + nHeight};
    window.wndProc = (LRESULT (*)(HWND, DWORD, WPARAM, LPARAM))[classInfo[@"wndProc"] pointerValue];
    
    // 生成窗口句柄
    HWND hwnd = [api generateWindowHandle];
    api.windows[@((uintptr_t)hwnd)] = window;
    
    NSLog(@"[WineAPI] Created window %p (%@) - UI creation skipped for testing", hwnd, window.windowText);
    
    // 🔧 修复：暂时跳过UI创建，避免线程问题
    // 发送WM_CREATE消息
    if (window.wndProc) {
        window.wndProc(hwnd, WM_CREATE, 0, (LPARAM)(intptr_t)lpParam);
    }
    
    return hwnd;
}

BOOL ShowWindow(HWND hWnd, int nCmdShow) {
    WineAPI *api = [WineAPI sharedAPI];
    WineWindow *window = [api getWindow:hWnd];
    
    if (!window) {
        SetLastError(1400); // ERROR_INVALID_WINDOW_HANDLE
        return FALSE;
    }
    
    BOOL wasVisible = window.isVisible;
    
    // 🔧 修复：只更新状态，不操作UI
    switch (nCmdShow) {
        case 0: // SW_HIDE
            window.isVisible = NO;
            break;
        case 1: // SW_SHOWNORMAL
        case 5: // SW_SHOW
        default:
            window.isVisible = YES;
            break;
    }
    
    NSLog(@"[WineAPI] ShowWindow %p, cmdShow=%d (UI update skipped)", hWnd, nCmdShow);
    return wasVisible;
}

BOOL UpdateWindow(HWND hWnd) {
    WineAPI *api = [WineAPI sharedAPI];
    WineWindow *window = [api getWindow:hWnd];
    
    if (!window) {
        SetLastError(1400); // ERROR_INVALID_WINDOW_HANDLE
        return FALSE;
    }
    
    // 🔧 修复：不发送WM_PAINT消息，避免消息循环
    NSLog(@"[WineAPI] UpdateWindow %p (paint message skipped)", hWnd);
    return TRUE;
}

BOOL DestroyWindow(HWND hWnd) {
    WineAPI *api = [WineAPI sharedAPI];
    WineWindow *window = [api getWindow:hWnd];
    
    if (!window) {
        SetLastError(1400); // ERROR_INVALID_WINDOW_HANDLE
        return FALSE;
    }
    
    // 发送WM_DESTROY消息 (非UI操作)
    if (window.wndProc) {
        window.wndProc(hWnd, WM_DESTROY, 0, 0);
    }
    
    // 🔧 修复：UI操作在主线程执行
    ENSURE_MAIN_THREAD(^{
        // 移除视图
        if (window.view) {
            [window.view removeFromSuperview];
        }
    });
    
    // 清理子窗口
    for (NSDictionary *child in window.children) {
        HWND childHwnd = (HWND)[child[@"hwnd"] unsignedIntegerValue];
        DestroyWindow(childHwnd);
    }
    
    // 从窗口列表中移除
    [api.windows removeObjectForKey:@((uintptr_t)hWnd)];
    
    NSLog(@"[WineAPI] Destroyed window %p", hWnd);
    return TRUE;
}

LRESULT DefWindowProc(HWND hWnd, DWORD Msg, WPARAM wParam, LPARAM lParam) {
    switch (Msg) {
        case WM_CLOSE:
            DestroyWindow(hWnd);
            return 0;
        case WM_DESTROY:
            PostQuitMessage(0);
            return 0;
        default:
            return 0;
    }
}

#pragma mark - 消息循环API

BOOL GetMessage(LPMSG lpMsg, HWND hWnd, DWORD wMsgFilterMin, DWORD wMsgFilterMax) {
    WineAPI *api = [WineAPI sharedAPI];
    
    // 🔧 修复：添加超时机制，避免无限等待
    NSDate *timeoutDate = [NSDate dateWithTimeIntervalSinceNow:0.1]; // 100ms超时
    
    while (api.messageQueue.count == 0 && !api.quitMessagePosted) {
        // 运行运行循环一小段时间
        BOOL hasRunLoop = [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:timeoutDate];
        
        if (!hasRunLoop || [timeoutDate timeIntervalSinceNow] < 0) {
            // 超时或没有运行循环，返回FALSE表示没有消息
            NSLog(@"[WineAPI] GetMessage timeout, no messages available");
            return FALSE;
        }
    }
    
    if (api.quitMessagePosted) {
        NSLog(@"[WineAPI] WM_QUIT received, exiting message loop");
        return FALSE; // WM_QUIT收到
    }
    
    if (api.messageQueue.count > 0) {
        NSDictionary *msg = api.messageQueue.firstObject;
        [api.messageQueue removeObjectAtIndex:0];
        
        lpMsg->hwnd = (HWND)[msg[@"hwnd"] unsignedIntegerValue];
        lpMsg->message = [msg[@"message"] unsignedIntValue];
        lpMsg->wParam = (WPARAM)[msg[@"wParam"] unsignedIntValue];
        lpMsg->lParam = (LPARAM)[msg[@"lParam"] intValue];
        lpMsg->time = [msg[@"time"] unsignedIntValue];
        lpMsg->pt = (POINT){0, 0};
        
        NSLog(@"[WineAPI] GetMessage returning message 0x%X", lpMsg->message);
        return TRUE;
    }
    
    return FALSE;
}

BOOL PeekMessage(LPMSG lpMsg, HWND hWnd, DWORD wMsgFilterMin, DWORD wMsgFilterMax, DWORD wRemoveMsg) {
    WineAPI *api = [WineAPI sharedAPI];
    
    if (api.messageQueue.count == 0) {
        return FALSE;
    }
    
    NSDictionary *msg = api.messageQueue.firstObject;
    
    lpMsg->hwnd = (HWND)[msg[@"hwnd"] unsignedIntegerValue];
    lpMsg->message = [msg[@"message"] unsignedIntValue];
    lpMsg->wParam = (WPARAM)[msg[@"wParam"] unsignedIntValue];
    lpMsg->lParam = (LPARAM)[msg[@"lParam"] intValue];
    lpMsg->time = [msg[@"time"] unsignedIntValue];
    lpMsg->pt = (POINT){0, 0};
    
    if (wRemoveMsg) {
        [api.messageQueue removeObjectAtIndex:0];
    }
    
    return TRUE;
}

BOOL TranslateMessage(const MSG *lpMsg) {
    return TRUE;
}

LRESULT DispatchMessage(const MSG *lpMsg) {
    WineAPI *api = [WineAPI sharedAPI];
    WineWindow *window = [api getWindow:lpMsg->hwnd];
    
    if (window && window.wndProc) {
        return window.wndProc(lpMsg->hwnd, lpMsg->message, lpMsg->wParam, lpMsg->lParam);
    }
    
    return DefWindowProc(lpMsg->hwnd, lpMsg->message, lpMsg->wParam, lpMsg->lParam);
}

void PostQuitMessage(int nExitCode) {
    WineAPI *api = [WineAPI sharedAPI];
    api.quitMessagePosted = YES;
    
    NSDictionary *msg = @{
        @"hwnd": @0,
        @"message": @(WM_QUIT),
        @"wParam": @(nExitCode),
        @"lParam": @0,
        @"time": @([[NSDate date] timeIntervalSince1970] * 1000)
    };
    
    [api.messageQueue addObject:msg];
    NSLog(@"[WineAPI] Posted WM_QUIT message with exit code %d", nExitCode);
}

#pragma mark - 绘图API实现

HDC BeginPaint(HWND hWnd, LPPAINTSTRUCT lpPaint) {
    WineAPI *api = [WineAPI sharedAPI];
    WineWindow *window = [api getWindow:hWnd];
    
    if (!window) {
        SetLastError(1400);
        return (HDC)0;
    }
    
    HDC hdc = [api generateDCHandle];
    WineDC *dc = [[WineDC alloc] init];
    dc.hwnd = hWnd;
    
    // 🔧 修复：图形上下文创建在主线程
    ENSURE_MAIN_THREAD_SYNC(^{
        if (window.view) {
            CGSize size = window.view.bounds.size;
            UIGraphicsBeginImageContext(size);
            dc.cgContext = UIGraphicsGetCurrentContext();
        }
    });
    
    api.deviceContexts[@((uintptr_t)hdc)] = dc;
    
    if (lpPaint) {
        lpPaint->hdc = hdc;
        lpPaint->fErase = TRUE;
        lpPaint->rcPaint = window.rect;
    }
    
    NSLog(@"[WineAPI] BeginPaint for window %p, DC=%p", hWnd, hdc);
    return hdc;
}

HDC GetDC(HWND hWnd) {
    WineAPI *api = [WineAPI sharedAPI];
    WineWindow *window = [api getWindow:hWnd];
    
    if (!window) {
        SetLastError(1400);
        return (HDC)0;
    }
    
    HDC hdc = [api generateDCHandle];
    WineDC *dc = [[WineDC alloc] init];
    dc.hwnd = hWnd;
    
    // 🔧 修复：图形上下文创建在主线程
    ENSURE_MAIN_THREAD_SYNC(^{
        if (window.view) {
            CGSize size = window.view.bounds.size;
            UIGraphicsBeginImageContext(size);
            dc.cgContext = UIGraphicsGetCurrentContext();
        }
    });
    
    api.deviceContexts[@((uintptr_t)hdc)] = dc;
    
    NSLog(@"[WineAPI] GetDC for window %p, DC=%p", hWnd, hdc);
    return hdc;
}

// 其他绘图函数保持不变，已经是线程安全的
BOOL Rectangle(HDC hdc, int left, int top, int right, int bottom) {
    WineAPI *api = [WineAPI sharedAPI];
    WineDC *dc = [api getDC:hdc];
    
    if (!dc || !dc.cgContext) {
        return FALSE;
    }
    
    CGRect rect = CGRectMake(left, top, right - left, bottom - top);
    CGContextSetStrokeColorWithColor(dc.cgContext, [UIColor blackColor].CGColor);
    CGContextSetLineWidth(dc.cgContext, 1.0);
    CGContextStrokeRect(dc.cgContext, rect);
    
    return TRUE;
}

HBRUSH CreateSolidBrush(DWORD color) {
    static NSUInteger brushCounter = 3000;
    return (HBRUSH)(uintptr_t)brushCounter++;
}

HBRUSH GetStockObject(int object) {
    return (HBRUSH)(uintptr_t)(5000 + object);
}

#pragma mark - 消息框API

int MessageBox(HWND hWnd, LPCSTR lpText, LPCSTR lpCaption, DWORD uType) {
    NSString *text = lpText ? [NSString stringWithUTF8String:lpText] : @"";
    NSString *caption = lpCaption ? [NSString stringWithUTF8String:lpCaption] : @"";
    
    // 🔧 修复：使用新的线程安全方法
    [WineAPI showAlertWithTitle:caption message:text type:uType];
    
    NSLog(@"[WineAPI] MessageBox: %@ - %@", caption, text);
    return 1; // IDOK
}
