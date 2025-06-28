#import "WineAPI.h"

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

- (CGRect)rectToCGRect:(RECT)rect {
    return CGRectMake(rect.left, rect.top, rect.right - rect.left, rect.bottom - rect.top);
}

- (RECT)cgRectToRect:(CGRect)cgRect {
    return (RECT){
        .left = (LONG)cgRect.origin.x,
        .top = (LONG)cgRect.origin.y,
        .right = (LONG)(cgRect.origin.x + cgRect.size.width),
        .bottom = (LONG)(cgRect.origin.y + cgRect.size.height)
    };
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
    return (DWORD)pthread_self();
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
        return NULL;
    }
    
    WineAPI *api = [WineAPI sharedAPI];
    NSString *className = [NSString stringWithUTF8String:lpClassName];
    
    // 检查窗口类是否已注册
    NSDictionary *classInfo = api.windowClasses[className];
    if (!classInfo) {
        NSLog(@"[WineAPI] Window class not found: %@", className);
        SetLastError(1407); // ERROR_CLASS_DOES_NOT_EXIST
        return NULL;
    }
    
    // 创建Wine窗口对象
    WineWindow *window = [[WineWindow alloc] init];
    window.className = className;
    window.windowText = lpWindowName ? [NSString stringWithUTF8String:lpWindowName] : @"";
    window.style = dwStyle;
    window.rect = (RECT){x, y, x + nWidth, y + nHeight};
    window.wndProc = (LRESULT (*)(HWND, DWORD, WPARAM, LPARAM))[classInfo[@"wndProc"] pointerValue];
    
    // 创建iOS视图
    UIView *view = [[UIView alloc] initWithFrame:CGRectMake(x, y, nWidth, nHeight)];
    view.backgroundColor = [UIColor whiteColor];
    view.layer.borderWidth = 1.0;
    view.layer.borderColor = [UIColor blackColor].CGColor;
    
    // 添加标题标签
    if (window.windowText.length > 0) {
        UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(5, 5, nWidth - 10, 25)];
        titleLabel.text = window.windowText;
        titleLabel.font = [UIFont boldSystemFontOfSize:14];
        titleLabel.backgroundColor = [UIColor lightGrayColor];
        [view addSubview:titleLabel];
    }
    
    window.view = view;
    
    // 生成窗口句柄
    HWND hwnd = [api generateWindowHandle];
    api.windows[@((uintptr_t)hwnd)] = window;
    
    // 如果有父窗口，添加为子视图
    if (hWndParent) {
        WineWindow *parentWindow = [api getWindow:hWndParent];
        if (parentWindow) {
            [parentWindow.view addSubview:view];
            [parentWindow.children addObject:@{@"hwnd": @((uintptr_t)hwnd)}];
        }
    } else if (api.rootViewController) {
        // 作为根窗口添加到主视图控制器
        [api.rootViewController.view addSubview:view];
    }
    
    NSLog(@"[WineAPI] Created window %p (%@) size:%dx%d", hwnd, window.windowText, nWidth, nHeight);
    
    // 发送WM_CREATE消息
    if (window.wndProc) {
        window.wndProc(hwnd, WM_CREATE, 0, (LPARAM)lpParam);
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
    
    switch (nCmdShow) {
        case 0: // SW_HIDE
            window.view.hidden = YES;
            window.isVisible = NO;
            break;
        case 1: // SW_SHOWNORMAL
        case 5: // SW_SHOW
            window.view.hidden = NO;
            window.isVisible = YES;
            break;
        default:
            window.view.hidden = NO;
            window.isVisible = YES;
            break;
    }
    
    NSLog(@"[WineAPI] ShowWindow %p, cmdShow=%d", hWnd, nCmdShow);
    return wasVisible;
}

BOOL UpdateWindow(HWND hWnd) {
    WineAPI *api = [WineAPI sharedAPI];
    WineWindow *window = [api getWindow:hWnd];
    
    if (!window) {
        SetLastError(1400); // ERROR_INVALID_WINDOW_HANDLE
        return FALSE;
    }
    
    // 触发重绘
    dispatch_async(dispatch_get_main_queue(), ^{
        [window.view setNeedsDisplay];
    });
    
    // 发送WM_PAINT消息
    [api postMessage:hWnd message:WM_PAINT wParam:0 lParam:0];
    
    NSLog(@"[WineAPI] UpdateWindow %p", hWnd);
    return TRUE;
}

BOOL DestroyWindow(HWND hWnd) {
    WineAPI *api = [WineAPI sharedAPI];
    WineWindow *window = [api getWindow:hWnd];
    
    if (!window) {
        SetLastError(1400); // ERROR_INVALID_WINDOW_HANDLE
        return FALSE;
    }
    
    // 发送WM_DESTROY消息
    if (window.wndProc) {
        window.wndProc(hWnd, WM_DESTROY, 0, 0);
    }
    
    // 移除视图
    [window.view removeFromSuperview];
    
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
    
    // 等待消息
    while (api.messageQueue.count == 0 && !api.quitMessagePosted) {
        // 在实际实现中，这里应该是事件等待
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    
    if (api.quitMessagePosted) {
        return FALSE; // WM_QUIT收到
    }
    
    if (api.messageQueue.count > 0) {
        NSDictionary *msg = api.messageQueue.firstObject;
        [api.messageQueue removeObjectAtIndex:0];
        
        lpMsg->hwnd = (HWND)[msg[@"hwnd"] unsignedIntegerValue];
        lpMsg->message = [msg[@"message"] unsignedIntValue];
        lpMsg->wParam = [msg[@"wParam"] unsignedIntegerValue];
        lpMsg->lParam = [msg[@"lParam"] integerValue];
        lpMsg->time = [msg[@"time"] unsignedIntValue];
        lpMsg->pt = (POINT){0, 0};
        
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
    lpMsg->wParam = [msg[@"wParam"] unsignedIntegerValue];
    lpMsg->lParam = [msg[@"lParam"] integerValue];
    lpMsg->time = [msg[@"time"] unsignedIntValue];
    lpMsg->pt = (POINT){0, 0};
    
    if (wRemoveMsg) {
        [api.messageQueue removeObjectAtIndex:0];
    }
    
    return TRUE;
}

BOOL TranslateMessage(const MSG *lpMsg) {
    // 简单实现：不做键盘消息翻译
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
    NSLog(@"[WineAPI] Posted WM_QUIT message");
}

#pragma mark - 绘图API实现

HDC BeginPaint(HWND hWnd, LPPAINTSTRUCT lpPaint) {
    WineAPI *api = [WineAPI sharedAPI];
    WineWindow *window = [api getWindow:hWnd];
    
    if (!window) {
        SetLastError(1400);
        return NULL;
    }
    
    HDC hdc = [api generateDCHandle];
    WineDC *dc = [[WineDC alloc] init];
    dc.hwnd = hWnd;
    
    // 创建Core Graphics上下文
    CGSize size = window.view.bounds.size;
    UIGraphicsBeginImageContext(size);
    dc.cgContext = UIGraphicsGetCurrentContext();
    
    api.deviceContexts[@((uintptr_t)hdc)] = dc;
    
    if (lpPaint) {
        lpPaint->hdc = hdc;
        lpPaint->fErase = TRUE;
        lpPaint->rcPaint = window.rect;
    }
    
    NSLog(@"[WineAPI] BeginPaint for window %p, DC=%p", hWnd, hdc);
    return hdc;
}

BOOL EndPaint(HWND hWnd, const PAINTSTRUCT *lpPaint) {
    WineAPI *api = [WineAPI sharedAPI];
    WineWindow *window = [api getWindow:hWnd];
    WineDC *dc = [api getDC:lpPaint->hdc];
    
    if (!window || !dc) {
        return FALSE;
    }
    
    // 结束绘图上下文
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    // 更新视图
    dispatch_async(dispatch_get_main_queue(), ^{
        UIImageView *imageView = [[UIImageView alloc] initWithImage:image];
        imageView.frame = window.view.bounds;
        [window.view.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
        [window.view addSubview:imageView];
    });
    
    // 清理DC
    [api.deviceContexts removeObjectForKey:@((uintptr_t)lpPaint->hdc)];
    
    NSLog(@"[WineAPI] EndPaint for window %p", hWnd);
    return TRUE;
}

HDC GetDC(HWND hWnd) {
    WineAPI *api = [WineAPI sharedAPI];
    WineWindow *window = [api getWindow:hWnd];
    
    if (!window) {
        SetLastError(1400);
        return NULL;
    }
    
    HDC hdc = [api generateDCHandle];
    WineDC *dc = [[WineDC alloc] init];
    dc.hwnd = hWnd;
    
    // 为窗口创建图形上下文
    CGSize size = window.view.bounds.size;
    UIGraphicsBeginImageContext(size);
    dc.cgContext = UIGraphicsGetCurrentContext();
    
    api.deviceContexts[@((uintptr_t)hdc)] = dc;
    
    NSLog(@"[WineAPI] GetDC for window %p, DC=%p", hWnd, hdc);
    return hdc;
}

int ReleaseDC(HWND hWnd, HDC hDC) {
    WineAPI *api = [WineAPI sharedAPI];
    WineDC *dc = [api getDC:hDC];
    
    if (dc) {
        UIGraphicsEndImageContext();
        [api.deviceContexts removeObjectForKey:@((uintptr_t)hDC)];
        NSLog(@"[WineAPI] ReleaseDC %p", hDC);
        return 1;
    }
    
    return 0;
}

#pragma mark - GDI32 API实现

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
    
    NSLog(@"[WineAPI] Rectangle (%d,%d) to (%d,%d)", left, top, right, bottom);
    return TRUE;
}

BOOL Ellipse(HDC hdc, int left, int top, int right, int bottom) {
    WineAPI *api = [WineAPI sharedAPI];
    WineDC *dc = [api getDC:hdc];
    
    if (!dc || !dc.cgContext) {
        return FALSE;
    }
    
    CGRect rect = CGRectMake(left, top, right - left, bottom - top);
    CGContextSetStrokeColorWithColor(dc.cgContext, [UIColor blackColor].CGColor);
    CGContextSetLineWidth(dc.cgContext, 1.0);
    CGContextStrokeEllipseInRect(dc.cgContext, rect);
    
    NSLog(@"[WineAPI] Ellipse (%d,%d) to (%d,%d)", left, top, right, bottom);
    return TRUE;
}

BOOL TextOut(HDC hdc, int x, int y, LPCSTR lpString, int c) {
    WineAPI *api = [WineAPI sharedAPI];
    WineDC *dc = [api getDC:hdc];
    
    if (!dc || !dc.cgContext || !lpString) {
        return FALSE;
    }
    
    NSString *text = [[NSString alloc] initWithBytes:lpString length:c encoding:NSUTF8StringEncoding];
    if (!text) {
        text = [NSString stringWithCString:lpString encoding:NSASCIIStringEncoding];
    }
    
    if (text) {
        CGContextSetFillColorWithColor(dc.cgContext, [UIColor blackColor].CGColor);
        
        // 简单的文本绘制
        NSDictionary *attributes = @{
            NSFontAttributeName: dc.currentFont,
            NSForegroundColorAttributeName: dc.currentColor
        };
        
        [text drawAtPoint:CGPointMake(x, y) withAttributes:attributes];
        
        NSLog(@"[WineAPI] TextOut at (%d,%d): %@", x, y, text);
    }
    
    return TRUE;
}

BOOL LineTo(HDC hdc, int x, int y) {
    WineAPI *api = [WineAPI sharedAPI];
    WineDC *dc = [api getDC:hdc];
    
    if (!dc || !dc.cgContext) {
        return FALSE;
    }
    
    CGContextSetStrokeColorWithColor(dc.cgContext, [UIColor blackColor].CGColor);
    CGContextSetLineWidth(dc.cgContext, 1.0);
    CGContextAddLineToPoint(dc.cgContext, x, y);
    CGContextStrokePath(dc.cgContext);
    
    NSLog(@"[WineAPI] LineTo (%d,%d)", x, y);
    return TRUE;
}

BOOL MoveToEx(HDC hdc, int x, int y, LPPOINT lppt) {
    WineAPI *api = [WineAPI sharedAPI];
    WineDC *dc = [api getDC:hdc];
    
    if (!dc || !dc.cgContext) {
        return FALSE;
    }
    
    CGContextMoveToPoint(dc.cgContext, x, y);
    
    if (lppt) {
        // 返回前一个位置 (简化实现)
        lppt->x = x;
        lppt->y = y;
    }
    
    NSLog(@"[WineAPI] MoveToEx (%d,%d)", x, y);
    return TRUE;
}

HBRUSH CreateSolidBrush(DWORD color) {
    // 简化实现：返回一个唯一的画刷句柄
    static NSUInteger brushCounter = 3000;
    HBRUSH brush = (HBRUSH)(uintptr_t)brushCounter++;
    
    NSLog(@"[WineAPI] CreateSolidBrush color=0x%X, brush=%p", color, brush);
    return brush;
}

HPEN CreatePen(int style, int width, DWORD color) {
    // 简化实现：返回一个唯一的画笔句柄
    static NSUInteger penCounter = 4000;
    HPEN pen = (HPEN)(uintptr_t)penCounter++;
    
    NSLog(@"[WineAPI] CreatePen style=%d width=%d color=0x%X, pen=%p", style, width, color, pen);
    return pen;
}

HBRUSH GetStockObject(int object) {
    // 返回系统默认对象
    return (HBRUSH)(uintptr_t)(5000 + object);
}

#pragma mark - 消息框API

int MessageBox(HWND hWnd, LPCSTR lpText, LPCSTR lpCaption, DWORD uType) {
    NSString *text = lpText ? [NSString stringWithUTF8String:lpText] : @"";
    NSString *caption = lpCaption ? [NSString stringWithUTF8String:lpCaption] : @"";
    
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:caption
                                                                       message:text
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
        
        // 获取当前视图控制器来显示alert
        UIViewController *rootVC = [WineAPI sharedAPI].rootViewController;
        if (rootVC) {
            [rootVC presentViewController:alert animated:YES completion:nil];
        }
    });
    
    NSLog(@"[WineAPI] MessageBox: %@ - %@", caption, text);
    return 1; // IDOK
}
