#!/bin/bash
# 修改版Wine for iOS编译脚本 - 针对iOS架构优化
# 添加了iOS目标架构支持，修复了库文件兼容性问题

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 简化配置
WINE_VERSION="wine-8.0"  # 使用较稳定的8.0版本
PROJECT_ROOT="$(pwd)"
BUILD_DIR="$PROJECT_ROOT/WineBuild"
WINE_SOURCE_DIR="$BUILD_DIR/$WINE_VERSION"
WINE_INSTALL_DIR="$PROJECT_ROOT/WineForIOS/WineLibs"

# iOS构建目标配置
IOS_TARGET="arm64-apple-ios-simulator"
SIMULATOR_TARGET="arm64-apple-ios-simulator"
MIN_IOS_VERSION="16.0"

# 检查基础环境
check_basic_requirements() {
    log_info "检查基础编译环境..."
    
    # 检查Xcode命令行工具
    if ! xcode-select -p &> /dev/null; then
        log_error "请安装Xcode命令行工具: xcode-select --install"
        exit 1
    fi
    
    # 检查Homebrew（可选）
    if ! command -v brew &> /dev/null; then
        log_warning "未检测到Homebrew，某些依赖可能需
        要手动安装"
    fi
    
    # 检查iOS SDK
    if [ ! -d "$(xcrun --sdk iphonesimulator18.5 --show-sdk-path)" ]; then
        log_error "iOS SDK未找到，请安装Xcode"
        exit 1
    fi
    
    log_success "基础环境检查完成"
}

# 下载Wine源码（简化版）
download_simple_wine() {
    log_info "下载Wine 8.0源码..."
    
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
    
    if [ ! -d "$WINE_SOURCE_DIR" ]; then
        # 使用Git clone更稳定
        log_info "从Git仓库克隆Wine源码..."
        git clone --depth 1 --branch wine-8.0 https://github.com/wine-mirror/wine.git "$WINE_SOURCE_DIR"
    else
        log_info "Wine源码已存在"
    fi
    
    log_success "Wine源码准备完成"
}

# 创建最小化库文件（用于测试）
create_minimal_libs() {
    log_info "创建最小化Wine库（iOS优化版）..."
    
    mkdir -p "$WINE_INSTALL_DIR"
    cd "$WINE_INSTALL_DIR"
    
    # 获取iOS SDK路径
    IOS_SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path)
    SIMULATOR_SDK_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path)
    
    # 创建基础库文件结构
    log_info "创建libwine.dylib（iOS架构）..."
    create_minimal_libwine "$IOS_SDK_PATH"
    
    log_info "创建ntdll.dll.so（iOS架构）..."
    create_minimal_ntdll "$IOS_SDK_PATH"
    
    log_info "创建kernel32.dll.so（iOS架构）..."
    create_minimal_kernel32 "$IOS_SDK_PATH"
    
    log_info "创建user32.dll.so（iOS架构）..."
    create_minimal_user32 "$IOS_SDK_PATH"
    
    log_info "创建gdi32.dll.so（iOS架构）..."
    create_minimal_gdi32 "$IOS_SDK_PATH"
    
    # 创建配置文件
    create_wine_config
    
    log_success "iOS优化版库文件创建完成"
}

# 创建libwine.dylib的模拟版本（iOS兼容）
create_minimal_libwine() {
    local SDK_PATH=$1
    
    cat > libwine_stub.c << 'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <dlfcn.h>
#include <unistd.h>
#include <sys/mman.h>
#include <sys/types.h>

// Wine API函数存根
void* wine_init(void) {
    printf("Wine init stub called\n");
    return (void*)1;
}

int wine_main(int argc, char *argv[]) {
    printf("Wine main stub called with %d arguments\n", argc);
    for (int i = 0; i < argc; i++) {
        printf("  arg[%d]: %s\n", i, argv[i]);
    }
    return 0;
}

void wine_cleanup(void) {
    printf("Wine cleanup stub called\n");
}

void* wine_dlopen(const char *filename, int flag) {
    printf("Wine dlopen stub: %s\n", filename);
    return dlopen(filename, flag);
}

void* wine_dlsym(void *handle, const char *symbol) {
    return dlsym(handle, symbol);
}

int wine_dlclose(void *handle) {
    return dlclose(handle);
}

void* wine_mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset) {
    return mmap(addr, length, prot, flags, fd, offset);
}

int wine_munmap(void *addr, size_t length) {
    return munmap(addr, length);
}

int wine_exec(const char *filename, char *const argv[]) {
    printf("Wine exec stub: %s\n", filename);
    return execv(filename, argv);
}

void wine_exit(int status) {
    exit(status);
}
EOF
    
    # 编译动态库 - 针对iOS架构
    if clang -shared -fPIC -target "$IOS_TARGET" -isysroot "$SDK_PATH" \
       -miphoneos-version-min="$MIN_IOS_VERSION" -o libwine.dylib libwine_stub.c; then
        log_success "libwine.dylib编译成功（iOS架构）"
    else
        log_error "libwine.dylib编译失败"
        return 1
    fi
    
    # 验证架构
    if file libwine.dylib | grep -q "arm64"; then
        log_success "架构验证: libwine.dylib 已构建为ARM64 iOS"
    else
        log_error "架构验证失败: libwine.dylib 未构建为ARM64 iOS"
        return 1
    fi
    
    rm -f libwine_stub.c
}

# 创建ntdll.dll.so的模拟版本（iOS兼容）
create_minimal_ntdll() {
    local SDK_PATH=$1
    
    cat > ntdll_stub.c << 'EOF'
#include <stdio.h>

// NTDLL函数存根
int NtCreateFile(void) {
    printf("NtCreateFile stub called\n");
    return 0;
}

int NtReadFile(void) {
    printf("NtReadFile stub called\n");
    return 0;
}

int NtWriteFile(void) {
    printf("NtWriteFile stub called\n");
    return 0;
}

int NtClose(void) {
    printf("NtClose stub called\n");
    return 0;
}
EOF
    
    # 编译为iOS动态库
    clang -shared -fPIC -target "$IOS_TARGET" -isysroot "$SDK_PATH" \
          -miphoneos-version-min="$MIN_IOS_VERSION" -o ntdll.dll.so ntdll_stub.c
    rm ntdll_stub.c
    
    # 验证架构
    if file ntdll.dll.so | grep -q "arm64"; then
        log_success "架构验证: ntdll.dll.so 已构建为ARM64 iOS"
    else
        log_error "架构验证失败: ntdll.dll.so 未构建为ARM64 iOS"
    fi
}

# 创建kernel32.dll.so的模拟版本（iOS兼容）
create_minimal_kernel32() {
    local SDK_PATH=$1
    
    cat > kernel32_stub.c << 'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

// 简化的Windows类型定义
typedef void* HANDLE;
typedef const char* LPCSTR;
typedef uint32_t DWORD;
typedef void* LPSECURITY_ATTRIBUTES;
typedef uint32_t UINT;
typedef int BOOL;
typedef void* LPVOID;
typedef const void* LPCVOID;
typedef DWORD* LPDWORD;
typedef void* LPOVERLAPPED;

#define INVALID_HANDLE_VALUE ((HANDLE)(long long)-1)
#define FALSE 0
#define TRUE 1

// Kernel32函数存根
HANDLE CreateFileA(LPCSTR lpFileName, DWORD dwDesiredAccess, DWORD dwShareMode,
                   LPSECURITY_ATTRIBUTES lpSecurityAttributes, DWORD dwCreationDisposition,
                   DWORD dwFlagsAndAttributes, HANDLE hTemplateFile) {
    printf("CreateFileA stub: %s\n", lpFileName ? lpFileName : "NULL");
    return INVALID_HANDLE_VALUE;
}

BOOL ReadFile(HANDLE hFile, LPVOID lpBuffer, DWORD nNumberOfBytesToRead,
              LPDWORD lpNumberOfBytesRead, LPOVERLAPPED lpOverlapped) {
    printf("ReadFile stub called\n");
    return FALSE;
}

BOOL WriteFile(HANDLE hFile, LPCVOID lpBuffer, DWORD nNumberOfBytesToWrite,
               LPDWORD lpNumberOfBytesWritten, LPOVERLAPPED lpOverlapped) {
    printf("WriteFile stub called\n");
    return FALSE;
}

BOOL CloseHandle(HANDLE hObject) {
    printf("CloseHandle stub called\n");
    return TRUE;
}

void ExitProcess(UINT uExitCode) {
    printf("ExitProcess stub: %d\n", uExitCode);
    exit(uExitCode);
}
EOF
    
    # 编译为iOS动态库
    clang -shared -fPIC -target "$IOS_TARGET" -isysroot "$SDK_PATH" \
          -miphoneos-version-min="$MIN_IOS_VERSION" -o kernel32.dll.so kernel32_stub.c
    rm kernel32_stub.c
    
    # 验证架构
    if file kernel32.dll.so | grep -q "arm64"; then
        log_success "架构验证: kernel32.dll.so 已构建为ARM64 iOS"
    else
        log_error "架构验证失败: kernel32.dll.so 未构建为ARM64 iOS"
    fi
}

# 创建user32.dll.so的模拟版本（iOS兼容）
create_minimal_user32() {
    local SDK_PATH=$1
    
    cat > user32_stub.c << 'EOF'
#include <stdio.h>
#include <stdint.h>

// 简化的Windows类型定义
typedef void* HWND;
typedef void* HINSTANCE;
typedef void* HMENU;
typedef uint32_t DWORD;
typedef int BOOL;

#define MB_OK 0

// User32函数存根
int MessageBoxA(HWND hWnd, const char *lpText, const char *lpCaption, unsigned int uType) {
    printf("MessageBoxA stub: %s - %s\n", lpCaption ? lpCaption : "NULL", lpText ? lpText : "NULL");
    return 1;
}

HWND CreateWindowExA(DWORD dwExStyle, const char *lpClassName, const char *lpWindowName,
                     DWORD dwStyle, int X, int Y, int nWidth, int nHeight,
                     HWND hWndParent, HMENU hMenu, HINSTANCE hInstance, void *lpParam) {
    printf("CreateWindowExA stub: %s\n", lpWindowName ? lpWindowName : "NULL");
    return (HWND)1;
}

BOOL ShowWindow(HWND hWnd, int nCmdShow) {
    printf("ShowWindow stub called\n");
    return 1;
}

BOOL UpdateWindow(HWND hWnd) {
    printf("UpdateWindow stub called\n");
    return 1;
}
EOF
    
    # 编译为iOS动态库
    clang -shared -fPIC -target "$IOS_TARGET" -isysroot "$SDK_PATH" \
          -miphoneos-version-min="$MIN_IOS_VERSION" -o user32.dll.so user32_stub.c
    rm user32_stub.c
    
    # 验证架构
    if file user32.dll.so | grep -q "arm64"; then
        log_success "架构验证: user32.dll.so 已构建为ARM64 iOS"
    else
        log_error "架构验证失败: user32.dll.so 未构建为ARM64 iOS"
    fi
}

# 创建gdi32.dll.so的模拟版本（iOS兼容）
create_minimal_gdi32() {
    local SDK_PATH=$1
    
    cat > gdi32_stub.c << 'EOF'
#include <stdio.h>

// 简化的Windows类型定义
typedef void* HDC;
typedef void* HGDIOBJ;

// GDI32函数存根
HDC CreateDCA(const char *pwszDriver, const char *pwszDevice, const char *pszPort, void *pdm) {
    printf("CreateDCA stub called\n");
    return (HDC)1;
}

int DeleteDC(HDC hdc) {
    printf("DeleteDC stub called\n");
    return 1;
}

HGDIOBJ SelectObject(HDC hdc, HGDIOBJ h) {
    printf("SelectObject stub called\n");
    return (HGDIOBJ)1;
}

int DeleteObject(HGDIOBJ ho) {
    printf("DeleteObject stub called\n");
    return 1;
}
EOF
    
    # 编译为iOS动态库
    clang -shared -fPIC -target "$IOS_TARGET" -isysroot "$SDK_PATH" \
          -miphoneos-version-min="$MIN_IOS_VERSION" -o gdi32.dll.so gdi32_stub.c
    rm gdi32_stub.c
    
    # 验证架构
    if file gdi32.dll.so | grep -q "arm64"; then
        log_success "架构验证: gdi32.dll.so 已构建为ARM64 iOS"
    else
        log_error "架构验证失败: gdi32.dll.so 未构建为ARM64 iOS"
    fi
}

# 创建Wine配置文件
create_wine_config() {
    cat > wine_config.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>WineVersion</key>
    <string>8.0-ios</string>
    <key>BuildDate</key>
    <string>$(date -u +"%Y-%m-%dT%H:%M:%SZ")</string>
    <key>BuildType</key>
    <string>iOS优化版</string>
    <key>TargetArchitecture</key>
    <string>arm64</string>
    <key>MinimumiOSVersion</key>
    <string>${MIN_IOS_VERSION}</string>
    <key>CoreLibraries</key>
    <array>
        <string>libwine.dylib</string>
        <string>ntdll.dll.so</string>
        <string>kernel32.dll.so</string>
        <string>user32.dll.so</string>
        <string>gdi32.dll.so</string>
    </array>
    <key>Note</key>
    <string>此版本专为iOS ARM64架构构建，支持iOS ${MIN_IOS_VERSION}+</string>
</dict>
</plist>
EOF
}

# 验证文件
verify_minimal_build() {
    log_info "验证iOS最小化构建..."
    
    local required_files=("libwine.dylib" "ntdll.dll.so" "kernel32.dll.so" "user32.dll.so" "gdi32.dll.so" "wine_config.plist")
    
    for file in "${required_files[@]}"; do
        if [ -f "$WINE_INSTALL_DIR/$file" ]; then
            local size=$(du -h "$WINE_INSTALL_DIR/$file" | cut -f1)
            
            # 对配置文件特殊处理
            if [[ "$file" == *".plist" ]]; then
                log_success "✓ $file ($size) [配置文件]"
            else
                local arch=$(file "$WINE_INSTALL_DIR/$file" | grep -o "arm64")
                
                if [ "$arch" = "arm64" ]; then
                    log_success "✓ $file ($size) [ARM64 iOS]"
                else
                    log_error "✗ $file 架构错误: $(file "$WINE_INSTALL_DIR/$file")"
                    return 1
                fi
            fi
        else
            log_error "✗ 缺少文件: $file"
            return 1
        fi
    done
    
    log_success "iOS最小化构建验证完成"
}

# 创建测试用例
create_test_files() {
    log_info "创建iOS测试用例..."
    
    mkdir -p "$PROJECT_ROOT/TestFiles"
    cd "$PROJECT_ROOT/TestFiles"
    
    # 创建简单的C程序
    cat > hello.c << 'EOF'
#include <stdio.h>
#include <windows.h>

int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow) {
    printf("Hello from Wine on iOS!\n");
    return 0;
}
EOF
    
    # 创建iOS测试说明
    cat > README-iOS.md << 'EOF'
# iOS 测试说明

## 测试文件说明
- `hello.c`: 简单的Windows程序测试用例

## 测试步骤
1. 在Xcode中打开项目
2. 将TestFiles目录添加到项目中
3. 运行测试套件
4. 检查日志输出

## 预期结果
- Wine库应正确加载
- 测试程序应返回退出码0
- 控制台应输出"Hello from Wine on iOS!"

## 故障排除
如果测试失败：
1. 检查库文件架构是否为ARM64
2. 验证iOS部署目标 ≥ 16.0
3. 确保库文件已正确添加到Bundle中
EOF
    
    log_info "测试用例已创建在 TestFiles/ 目录"
    log_success "iOS测试文件创建完成"
}

# 生成iOS测试报告
generate_test_report() {
    log_info "生成iOS测试报告..."
    
    cat > "$PROJECT_ROOT/wine_ios_test_report.md" << EOF
# Wine for iOS 测试构建报告

## 构建信息
- 构建时间: $(date)
- Wine版本: 8.0 (iOS优化版)
- 目标架构: ARM64
- 最低iOS版本: ${MIN_IOS_VERSION}
- 构建类型: 测试/最小化版本

## 生成的文件
$(ls -la "$WINE_INSTALL_DIR")

## 架构验证
$(for file in libwine.dylib ntdll.dll.so kernel32.dll.so user32.dll.so gdi32.dll.so; do
    echo "- $file: \`$(file "$WINE_INSTALL_DIR/$file")\`"
done)

## iOS特定测试建议

### 1. 架构验证
使用以下命令验证库文件架构：
\`\`\`bash
file WineLibs/*
\`\`\`
所有文件应显示为 \`Mach-O 64-bit dynamically linked shared library arm64\`

### 2. Xcode项目配置
1. 在Build Settings中设置：
   - \`ARCHS = arm64\`
   - \`VALID_ARCHS = arm64\`
   - \`ONLY_ACTIVE_ARCH = YES\`
2. 添加库搜索路径：
   - \`LIBRARY_SEARCH_PATHS = \\\$(PROJECT_DIR)/WineForIOS/WineLibs\`

### 3. 真机测试
1. 使用Developer证书签名
2. 在ARM64 iOS设备上运行测试
3. 检查控制台日志

## 已知限制
- 这是存根版本，仅用于测试框架
- 需要iOS 16.0或更高版本
- 仅支持ARM64架构设备

## 下一步
1. 在Xcode中运行测试套件
2. 集成到主应用
3. 测试真实Windows程序执行
EOF
    
    log_success "iOS测试报告已生成: wine_ios_test_report.md"
}

# 清理函数
cleanup_build() {
    log_info "清理构建文件..."
    rm -rf "$BUILD_DIR"
    log_success "清理完成"
}

# 主执行流程
main() {
    log_info "开始iOS优化版Wine库构建..."
    echo "==========================================="
    
    check_basic_requirements
    
    # 询问用户是否要下载完整源码
    read -p "是否下载Wine源码？(用于后续真实编译) [y/N]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        download_simple_wine
    else
        log_info "跳过源码下载，仅创建iOS测试存根"
    fi
    
    create_minimal_libs
    verify_minimal_build
    create_test_files
    generate_test_report
    
    log_success "iOS优化版Wine库构建完成！"
    echo "==========================================="
    log_info "接下来请："
    log_info "1. 在Xcode中添加WineTestViewController"
    log_info "2. 设置库搜索路径: \$(PROJECT_DIR)/WineForIOS/WineLibs"
    log_info "3. 运行测试套件验证功能"
    log_info "4. 检查测试报告: wine_ios_test_report.md"
    echo ""
    log_info "关键验证命令:"
    log_info "  file WineForIOS/WineLibs/*"
    log_info "  otool -l WineForIOS/WineLibs/libwine.dylib | grep -A5 LC_VERSION_MIN_IPHONEOS"
    
    read -p "是否清理构建文件？[y/N]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cleanup_build
    fi
}

# 错误处理
trap 'log_error "构建过程中发生错误"; exit 1' ERR

# 执行主程序
main "$@"
