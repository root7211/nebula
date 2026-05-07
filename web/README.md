# Nebula WASM Build

## Quick Start

```bash
# 安装前置条件
# 1. Nelua: https://nelua.io/installing/
# 2. Emscripten: https://emscripten.org/docs/getting_started/downloads.html

# 编译 demo
./build_wasm.sh button_v2_demo

# 本地预览（需要 HTTP server，WASM 不支持 file:// 协议）
cd build/wasm && python3 -m http.server 8000
# 打开 http://localhost:8000/button_v2_demo.html
```

## Requirements

- **Browser**: Chrome 113+ / Edge 113+ / Firefox Nightly (WebGPU flag)
- **GPU**: Hardware acceleration must be enabled
- **Emscripten**: 3.1.51+ (tested)
- **Nelua**: latest

## Architecture

```
web/
  shell.html        — HTML 模板（<canvas> + WebGPU 检测 + loading UI）
build_wasm.sh       — 一键 WASM 构建脚本
build/wasm/         — 输出目录（gitignored）
  *.html            — 入口页面
  *.js              — Emscripten JS 胶水
  *.wasm            — WebAssembly 二进制
  *.data            — 预加载资产（字体 atlas 等）
```

## How It Works

1. **Nelua → C**: Nelua 编译器将 `.nelua` 转译为纯 C 代码
2. **C → WASM**: Emscripten (`emcc`) 将 C 编译为 `.wasm`
3. **WebGPU binding**: `-sUSE_WEBGPU=1` 让 `wgpuXxx()` C 调用直接映射到浏览器的 `navigator.gpu` API
4. **GLFW emulation**: `-sUSE_GLFW=3` 将 GLFW 窗口/输入映射到 HTML Canvas
5. **Asset preloading**: `--preload-file` 将字体 atlas 打包到 `.data`，Emscripten VFS 模拟 `fopen/fread`
6. **Main loop**: `emscripten_set_main_loop` 替代原生的 `while` 阻塞循环

## Conditional Compilation

Nebula 使用 Nelua 预处理器 `## if NEBULA_TARGET == 'wasm'` 在编译期消解平台差异：

| 模块 | Native 路径 | WASM 路径 |
|------|-------------|-----------|
| Instance | `WGPUInstanceExtras` (wgpu-native) | 标准 `WGPUInstanceDescriptor` |
| Surface | X11/Wayland/HWND | `CanvasHTMLSelector("#nebula-canvas")` |
| Main loop | `while not should_close()` | `emscripten_set_main_loop` 回调 |
| 链接库 | `-lwgpu_native -lglfw` | `-sUSE_WEBGPU=1 -sUSE_GLFW=3` |

## Supported Demos

不是所有 demo 都支持 WASM：

| Demo | WASM | Notes |
|------|------|-------|
| button_v2_demo | YES | 推荐首选 |
| button_demo | YES | |
| layout_demo | YES | |
| form_demo | YES | |
| text_demo | YES | |
| term_demo | NO | 需要 PTY (forkpty) |
| term_demo_v2 | NO | 需要 PTY |
| slug_bench | NO | 性能基准，无意义 |

## GitHub Pages

每次 push 到 `main` 分支，CI 自动构建并部署到 GitHub Pages。
