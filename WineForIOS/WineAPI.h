#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <pthread.h>  // 添加pthread头文件

NS_ASSUME_NONNULL_BEGIN

// Windows基础类型定义
typedef void* HWND;
typedef void* HDC;
typedef void* HBITMAP;
typedef void* HBRUSH;
typedef void* HPEN;
typedef void* HFONT;
typedef void* HICON;
typedef void* HCURSOR;
typedef void* HMENU;
typedef void* HINSTANCE;
typedef uint32_t DWORD;
typedef int32_t LONG;
typedef uint16_t WORD;
typedef uint8_t BYTE;
typedef char* LPSTR;
typedef const char* LPCSTR;
typedef wchar_t* LPWSTR;
typedef const wchar_t* LPCWSTR;
typedef void* LPVOID;
typedef LONG LRESULT;
typedef DWORD WPARAM;
typedef LONG LPARAM;

#define TRUE 1
#define FALSE 0
#define NULL ((void*)0)

// Windows消息定义
#define WM_CREATE       0x0001
#define WM_DESTROY      0x0002
#define WM_CLOSE        0x0010
#define WM_QUIT         0x0012
#define WM_PAINT        0x000F
#define WM_LBUTTONDOWN  0x0201
#define WM_LBUTTONUP    0x0202
#define WM_MOUSEMOVE    0x0200
#define WM_KEYDOWN      0x0100
#define WM_KEYUP        0x0101
#define WM_COMMAND      0x0111

// 窗口样式
#define WS_OVERLAPPED    0x00000000
#define WS_POPUP         0x80000000
#define WS_CHILD         0x40000000
#define WS_MINIMIZE      0x20000000
#define WS_VISIBLE       0x10000000
#define WS_DISABLED      0x08000000
#define WS_CLIPSIBLINGS  0x04000000
#define WS_CLIPCHILDREN  0x02000000
#define WS_MAXIMIZE      0x01000000
#define WS_CAPTION       0x00C00000
#define WS_BORDER        0x00800000
#define WS_DLGFRAME      0x00400000
#define WS_VSCROLL       0x00200000
#define WS_HSCROLL       0x00100000
#define WS_SYSMENU       0x00080000
#define WS_THICKFRAME    0x00040000
#define WS_GROUP         0x00020000
#define WS_TABSTOP       0x00010000
#define WS_MINIMIZEBOX   0x00020000
#define WS_MAXIMIZEBOX   0x00010000

#define WS_OVERLAPPEDWINDOW (WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX)

// 消息框类型
#define MB_OK            0x00000000
#define MB_OKCANCEL      0x00000001
#define MB_YESNO         0x00000004
#define MB_ICONERROR     0x00000010
#define MB_ICONWARNING   0x00000030
#define MB_ICONINFO      0x00000040

// 绘图常量
#define BLACK_BRUSH      4
#define WHITE_BRUSH      0
#define GRAY_BRUSH       2

// Windows结构体定义
typedef struct tagPOINT {
    LONG x;
    LONG y;
} POINT, *PPOINT, *LPPOINT;

typedef struct tagRECT {
    LONG left;
    LONG top;
    LONG right;
    LONG bottom;
} RECT, *PRECT, *LPRECT;

typedef struct tagMSG {
    HWND hwnd;
    DWORD message;
    WPARAM wParam;
    LPARAM lParam;
    DWORD time;
    POINT pt;
} MSG, *PMSG, *LPMSG;

typedef struct tagWNDCLASS {
    DWORD style;
    LRESULT (*lpfnWndProc)(HWND, DWORD, WPARAM, LPARAM);
    int cbClsExtra;
    int cbWndExtra;
    HINSTANCE hInstance;
    HICON hIcon;
    HCURSOR hCursor;
    HBRUSH hbrBackground;
    LPCSTR lpszMenuName;
    LPCSTR lpszClassName;
} WNDCLASS, *PWNDCLASS, *LPWNDCLASS;

typedef struct tagPAINTSTRUCT {
    HDC hdc;
    BOOL fErase;
    RECT rcPaint;
    BOOL fRestore;
    BOOL fIncUpdate;
    BYTE rgbReserved[32];
} PAINTSTRUCT, *PPAINTSTRUCT, *LPPAINTSTRUCT;

// Windows窗口数据
@interface WineWindow : NSObject
@property (nonatomic, strong) UIView *view;
@property (nonatomic, strong) UIViewController *viewController;
@property (nonatomic, assign) LRESULT (*wndProc)(HWND, DWORD, WPARAM, LPARAM);
@property (nonatomic, strong) NSString *className;
@property (nonatomic, strong) NSString *windowText;
@property (nonatomic, assign) RECT rect;
@property (nonatomic, assign) DWORD style;
@property (nonatomic, assign) BOOL isVisible;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *children;
@end

// Windows设备上下文
@interface WineDC : NSObject
@property (nonatomic, assign) CGContextRef cgContext;
@property (nonatomic, assign) HWND hwnd;
@property (nonatomic, strong) UIColor *currentColor;
@property (nonatomic, strong) UIFont *currentFont;
@property (nonatomic, assign) CGRect clipRect;
@end

// Wine API管理器
@interface WineAPI : NSObject

@property (nonatomic, strong) NSMutableDictionary<NSNumber *, WineWindow *> *windows;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, WineDC *> *deviceContexts;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *windowClasses;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *messageQueue;
@property (nonatomic, weak) UIViewController *rootViewController;

+ (instancetype)sharedAPI;

// 修复：添加线程安全的UI辅助方法
+ (void)showAlertWithTitle:(NSString *)title message:(NSString *)message type:(DWORD)uType;

// KERNEL32 API
DWORD GetLastError(void);
void SetLastError(DWORD error);
DWORD GetCurrentThreadId(void);
DWORD GetCurrentProcessId(void);

// USER32 API
BOOL RegisterClass(const WNDCLASS *lpWndClass);
HWND CreateWindow(LPCSTR lpClassName, LPCSTR lpWindowName, DWORD dwStyle,
                 int x, int y, int nWidth, int nHeight,
                 HWND hWndParent, HMENU hMenu, HINSTANCE hInstance, LPVOID lpParam);
BOOL ShowWindow(HWND hWnd, int nCmdShow);
BOOL UpdateWindow(HWND hWnd);
BOOL DestroyWindow(HWND hWnd);
LRESULT DefWindowProc(HWND hWnd, DWORD Msg, WPARAM wParam, LPARAM lParam);

// 消息循环
BOOL GetMessage(LPMSG lpMsg, HWND _Nullable hWnd, DWORD wMsgFilterMin, DWORD wMsgFilterMax);
BOOL PeekMessage(LPMSG lpMsg, HWND _Nullable hWnd, DWORD wMsgFilterMin, DWORD wMsgFilterMax, DWORD wRemoveMsg);
BOOL TranslateMessage(const MSG *lpMsg);
LRESULT DispatchMessage(const MSG *lpMsg);
void PostQuitMessage(int nExitCode);

// 绘图API
HDC BeginPaint(HWND hWnd, LPPAINTSTRUCT lpPaint);
BOOL EndPaint(HWND hWnd, const PAINTSTRUCT *lpPaint);
HDC GetDC(HWND hWnd);
int ReleaseDC(HWND hWnd, HDC hDC);

// GDI32 API
BOOL Rectangle(HDC hdc, int left, int top, int right, int bottom);
BOOL Ellipse(HDC hdc, int left, int top, int right, int bottom);
BOOL TextOut(HDC hdc, int x, int y, LPCSTR lpString, int c);
BOOL LineTo(HDC hdc, int x, int y);
BOOL MoveToEx(HDC hdc, int x, int y, LPPOINT lppt);
HBRUSH CreateSolidBrush(DWORD color);
HPEN CreatePen(int style, int width, DWORD color);
HBRUSH GetStockObject(int object);

// 消息框
int MessageBox(HWND hWnd, LPCSTR lpText, LPCSTR lpCaption, DWORD uType);

@end

NS_ASSUME_NONNULL_END
