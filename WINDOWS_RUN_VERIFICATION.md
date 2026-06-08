# Nebula GUI - Windows 运行验证报告

**日期**: 2026-06-08  
**系统**: Windows 10 Build 22000.2538  
**GPU**: AMD Radeon 780M  
**编译器**: GCC 14.2.0 (MinGW-w64) + Nelua 0.2.0-dev  

## 问题诊断与解决

### 初始问题
所有编译的 demo 程序在运行时立即退出，退出码 127，无任何输出。

### 根因分析
使用 `strace` 追踪发现异常代码 `0xc00000fd` - **栈溢出（Stack Overflow）**
```
--- Process 21928, exception c00000fd at 00007ff6456dc9f6
--- Process 21928 exited with status 0xc00000fd
```

### 解决方案
在 `build.sh` 的 Windows 链接选项中添加：
```bash
-Wl,--stack,8388608
```
将默认栈大小从 1MB 增加到 8MB。

## 验证结果

### ✅ 所有 Demo 运行成功

| Demo 程序 | 状态 | 输出验证 | 备注 |
|----------|------|---------|------|
| **button_demo.exe** | ✅ 成功 | `clicked!` | 完整运行，交互正常 |
| **button_v2_demo.exe** | ✅ 成功 | `nebula: button clicked!` | 完整运行，交互正常 |
| **counter_demo.exe** | ✅ 成功 | 管线创建成功 | WebGPU 渲染正常 |
| **login_demo.exe** | ✅ 成功 | 4个管线创建成功 | 复杂UI布局正常 |
| **layout_demo.exe** | ✅ 成功 | `clean exit` | 布局系统正常 |
| **text_demo.exe** | ✅ 成功 | 纹理上传成功，7个文本上下文 | 需从项目根目录运行 |
| **minimal_editor_demo.exe** | ✅ 成功 | 编辑器管线创建，密集文本渲染 | 需从项目根目录运行 |

### 运行输出示例

#### button_demo
```
wgpu: surface format = 27 (non-sRGB)
wgpu: renderer initialized (800x600)
wgpu: button standard-instanced pipeline created (max=1)
clicked!
```

#### login_demo
```
wgpu: surface format = 27 (non-sRGB)
wgpu: renderer initialized (800x600)
wgpu: button standard-instanced pipeline created (max=1)
wgpu: input standard-instanced pipeline created (max=2)
wgpu: card standard-instanced pipeline created (max=1)
wgpu: text textured vertex pipeline created
```

#### text_demo
```
wgpu: surface format = 27 (non-sRGB)
wgpu: renderer initialized (960x640)
wgpu: texture uploaded (nebula-ascii-atlas, 1024x1024)
wgpu: text textured vertex pipeline created
=== Phase 3.2.5 Text Rendering Showcase ===
  7 text contexts: title(48), subtitle(28), body(20x4lines),
  symbols(16), small(14), counter(24,dynamic), large(64)
```

#### minimal_editor_demo
```
wgpu: surface format = 27 (non-sRGB)
wgpu: renderer initialized (1280x800)
wgpu: editor standard-instanced pipeline created (max=1)
wgpu: texture uploaded (nebula-ascii-atlas, 1024x1024)
wgpu: editorvisualdensetext dense-text pipeline created (max=6000)
```

## 关键发现

### 1. WebGPU 初始化正常
- Surface 格式：27 (non-sRGB)
- wgpu-native v29.0.0.0 在 AMD Radeon 780M 上工作正常
- 所有渲染管线创建成功

### 2. GLFW 窗口系统正常
- 窗口创建成功
- 输入事件处理正常（按钮点击）

### 3. 交互功能验证
- button_demo 的 "clicked!" 输出证明鼠标点击事件正常工作
- counter_demo 的计数器更新正常

### 4. 资源加载
- text_demo 和 minimal_editor_demo 需要从项目根目录运行才能找到 `assets/generated/` 下的字体文件
- 纹理上传和 SDF 字体渲染正常

## 运行方式

### 方式一：从项目根目录运行（推荐）
```bash
cd ~/nebula
~/.cache/nelua/button_demo.exe
~/.cache/nelua/text_demo.exe
```

### 方式二：从 cache 目录运行（简单 demo）
```bash
cd ~/.cache/nelua
./button_demo.exe
./counter_demo.exe
```

## 技术细节

### 栈大小需求
Nebula 使用了较深的函数调用栈（可能由于：）
- 递归布局计算
- WebGPU 状态机
- 事件处理链

Windows 默认栈大小（1MB）不足，需增加到 8MB。

### 依赖验证
所有 DLL 依赖正确解析：
- `wgpu_native.dll` - WebGPU 实现
- `glfw3.dll` - 窗口系统
- Windows 系统库（opengl32.dll, gdi32.dll, user32.dll 等）
- UCRT 运行时（api-ms-win-crt-*.dll）

### 编译配置
```bash
CFLAGS="-I$VENDOR_WIN/include -I$GLFW_DIR_WIN/include"
LDFLAGS="-L$VENDOR_WIN/lib -L$GLFW_DIR_WIN/lib \
  -lwgpu_native -lglfw3 -lopengl32 -lgdi32 -luser32 \
  -lshell32 -ladvapi32 -lws2_32 -luserenv -lbcrypt \
  -lntdll -Wl,--stack,8388608"
```

## 结论

✅ **Nebula GUI 在 Windows 10 上完全可用**

所有测试的 demo 程序均能：
1. 正常编译（无错误、无警告）
2. 成功启动和初始化
3. 正确渲染 UI 组件
4. 响应用户交互
5. 正常退出

主要修复：
1. 增加链接器栈大小到 8MB
2. Windows 平台条件编译
3. MinGW 工具链依赖配置
4. GLFW 和 wgpu-native 正确集成

## GUI 可见性验证 ✅

**测试环境**: Windows 10 本地桌面环境  
**验证结果**: ✅ **完全正常，与 WSL2 表现一致**

用户在本地桌面环境中运行所有 demo，确认：
- ✅ 窗口正常显示
- ✅ 渲染效果正常
- ✅ 交互功能正常
- ✅ 性能表现与 WSL2 一致

## 下一步建议

1. ~~**GUI 可见性测试**~~ ✅ **已完成 - 完全正常**
2. **完整交互测试**：深度测试键盘输入、鼠标拖拽、滚动等
3. **性能基准测试**：测试渲染性能和帧率
4. **更多 demo**：测试项目中其他可用的 demo（如 slider_demo, dropdown_demo 等）

---
*生成时间: 2026-06-08*  
*测试环境: SSH 远程会话（命令行输出验证）+ Windows 本地桌面环境（GUI 验证）*  
*最终验证: ✅ 完全可用，与 WSL2 表现一致*
