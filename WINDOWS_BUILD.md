# Nebula Windows 构建指南

本文档记录了为 Nebula GUI 编译器添加 Windows 支持的过程。

## 完成的工作

### 1. 安装 Nelua 编译器

```bash
cd ~
git clone https://github.com/edubart/nelua-lang.git
cd nelua-lang
gcc -O2 -DNDEBUG -D_CRT_SECURE_NO_WARNINGS -D_CRT_NONSTDC_NO_WARNINGS \
    -DMAXRECLEVEL=400 -Isrc/lua -o nelua-lua.exe src/*.c src/lpeglabel/*.c -static
```

创建 bash wrapper：`~/bin/nelua`

### 2. 下载 Windows 依赖库

#### wgpu-native v29.0.0.0 (MinGW GNU 版本)

```bash
cd ~/nebula
curl -L -o /tmp/wgpu-windows.zip \
  "https://github.com/gfx-rs/wgpu-native/releases/download/v29.0.0.0/wgpu-windows-x86_64-gnu-release.zip"
unzip -q /tmp/wgpu-windows.zip -d vendor/wgpu-native
```

包含：
- `include/webgpu/`: WebGPU 头文件
- `lib/libwgpu_native.a`: 静态库
- `lib/wgpu_native.dll`: 动态库 (14 MB)

#### GLFW 3.4 (MinGW 版本)

```bash
cd ~/nebula
curl -L -o /tmp/glfw.zip \
  "https://github.com/glfw/glfw/releases/download/3.4/glfw-3.4.bin.WIN64.zip"
unzip -q /tmp/glfw.zip -d /tmp/glfw-extract
mkdir -p vendor/glfw/include/GLFW
cp /tmp/glfw-extract/glfw-3.4.bin.WIN64/include/GLFW/* vendor/glfw/include/GLFW/
cp -r /tmp/glfw-extract/glfw-3.4.bin.WIN64/lib-mingw-w64 vendor/glfw/lib
```

包含：
- `include/GLFW/glfw3.h` 和 `glfw3native.h`
- `lib/libglfw3.a`: 静态库
- `lib/glfw3.dll`: 动态库 (299 KB)

### 3. 源码修改

#### 3.1 修复平台条件编译 (`src/renderer.nelua`)

**问题**: Linux X11/Wayland 代码路径没有被 `NEBULA_TARGET` 条件包裹，导致在 Windows 平台也会编译 Linux 特定代码。

**修复**: 重新组织条件编译结构，将 Windows 分支放在最前面：

```nelua
## if NEBULA_TARGET == 'windows' then
  -- Windows (HWND) 路径
  local hwnd_src = WGPUSurfaceSourceWindowsHWND{...}
## elseif NEBULA_LINUX_DISPLAY ~= 'wayland' then
  -- Linux (X11) 路径
## elseif NEBULA_LINUX_DISPLAY == 'wayland' then
  -- Linux (Wayland) 路径
## end
```

#### 3.2 修复 GLFW 库链接 (`src/glfw_bindings.nelua`)

**问题**: 在 Windows 上，GLFW 库名是 `glfw3` 而不是 `glfw`。

**修复**: 添加平台条件链接：

```nelua
## if NEBULA_TARGET ~= 'wasm' then
  ## if NEBULA_TARGET == 'windows' then
## linklib "glfw3"
  ## else
## linklib "glfw"
  ## end
## end
```

#### 3.3 更新构建脚本 (`build.sh`)

**问题**: 
1. 缺少 GLFW 库路径配置
2. MSYS 路径格式 (`/c/Users/...`) 与 GCC 不兼容
3. 缺少必要的 Windows 系统库

**修复**:

```bash
elif [ "$NEBULA_TARGET" == "windows" ]; then
  # 转换 MSYS 路径为 Windows 路径
  VENDOR_WIN=$(cygpath -w "$SCRIPT_DIR/vendor/wgpu-native" 2>/dev/null || echo "$SCRIPT_DIR/vendor/wgpu-native" | sed 's|^/c/|C:/|')
  GLFW_DIR_WIN=$(cygpath -w "$SCRIPT_DIR/vendor/glfw" 2>/dev/null || echo "$SCRIPT_DIR/vendor/glfw" | sed 's|^/c/|C:/|')
  
  CFLAGS="-I$VENDOR_WIN/include -I$GLFW_DIR_WIN/include"
  LDFLAGS="-L$VENDOR_WIN/lib -L$GLFW_DIR_WIN/lib -lwgpu_native -lglfw3 \
           -lopengl32 -lgdi32 -luser32 -lshell32 -ladvapi32 -lws2_32 \
           -luserenv -lbcrypt -lntdll"
fi
```

### 4. 构建测试

```bash
cd ~/nebula
./build.sh button_demo --target=windows
```

**输出**:
- 生成的 C 代码: `~/.cache/nelua/button_demo.c` (68 KB)
- 可执行文件: `~/.cache/nelua/button_demo.exe` (494 KB)

**运行时依赖**:
- `wgpu_native.dll` (14 MB)
- `glfw3.dll` (299 KB)

## 限制

### 不支持的 Demo

1. **term_demo / term_demo_v2**: 需要 POSIX PTY (伪终端)，Windows 不支持
2. **code_browser_demo**: 依赖 POSIX C FFI 的目录遍历功能

### 运行环境要求

- 需要支持 Vulkan 或 DirectX 12 的 GPU
- 无法在纯命令行/SSH 环境中测试 GUI（需要本地显示器）

## 使用方法

### 编译项目

```bash
cd ~/nebula
./build.sh <demo_name> --target=windows
```

支持的 demo:
- button_demo, button_v2_demo
- login_demo, login_v2_demo
- form_demo
- layout_demo
- text_demo
- slider_demo
- scrollable_demo
- dropdown_demo
- multiline_editable_demo
- text_editor_demo, text_editor_demo_v2, text_editor_demo_v3, text_editor_demo_v4
- minimal_editor_demo
- json_viewer_demo, json_viewer_demo_v2
- counter_demo, counter_binding_demo
- 等等

### 运行程序

```bash
# 复制 DLL 到可执行文件目录
cp ~/nebula/vendor/wgpu-native/lib/wgpu_native.dll ~/.cache/nelua/
cp ~/nebula/vendor/glfw/lib/glfw3.dll ~/.cache/nelua/

# 运行
~/.cache/nelua/<demo_name>.exe
```

或者将 DLL 所在目录添加到 PATH：

```bash
export PATH="$PATH:$HOME/nebula/vendor/wgpu-native/lib:$HOME/nebula/vendor/glfw/lib"
~/.cache/nelua/<demo_name>.exe
```

## 技术细节

### 编译器工具链

- **Nelua**: 0.2.0-dev (build 1635)
- **GCC**: x86_64-w64-mingw32-gcc 14.2.0 (MinGW)
- **Target**: x86_64-w64-mingw32

### 依赖架构

```
Nebula (.nelua)
    ↓ [Nelua Compiler]
Generated C Code (.c)
    ↓ [MinGW GCC]
Native Binary (.exe)
    ↓ [Runtime]
wgpu_native.dll + glfw3.dll
    ↓
Vulkan / DirectX 12
```

### 编译流程

1. Nelua 编译器读取 `.nelua` 源码
2. 执行编译期元编程（## 宏展开）
3. 根据 `NEBULA_TARGET=windows` 条件编译
4. 生成优化的 C 代码
5. 调用 MinGW GCC 编译 C 代码
6. 链接 wgpu-native 和 GLFW 库
7. 生成最终的 Windows 可执行文件

## 下一步改进

1. **创建 Windows 批处理脚本**: 提供 `build.bat` 以便在 cmd.exe 或 PowerShell 中使用
2. **自动 DLL 复制**: 修改构建脚本自动复制 DLL 到输出目录
3. **MSVC 支持**: 添加对 Visual Studio 编译器的支持（需要 `wgpu-windows-x86_64-msvc-release.zip`）
4. **代码浏览器 Windows 移植**: 使用 Windows API 替代 POSIX dirent
5. **安装脚本**: 创建自动化安装脚本，一键配置所有依赖

## 故障排查

### 编译错误: "cannot find -lglfw"

确保 `src/glfw_bindings.nelua` 中的平台条件链接已正确修改。

### 编译错误: "GLFW/glfw3.h: No such file or directory"

检查 GLFW 头文件是否在 `vendor/glfw/include/GLFW/` 目录下。

### 运行时错误: "无法启动此程序，因为计算机中丢失 xxx.dll"

将必要的 DLL 复制到可执行文件同目录，或添加到 PATH。

### 黑屏或程序立即退出

检查是否有支持 Vulkan/DirectX 12 的 GPU，以及是否在本地桌面环境中运行（不支持远程 SSH）。

## 贡献

本 Windows 支持由社区贡献者添加。如有问题或改进建议，请提交 Issue 或 Pull Request。

## 许可

遵循 Nebula 项目的原始许可证。
