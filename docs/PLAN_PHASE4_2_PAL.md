# Phase 4.2 实施计划：跨平台 PAL (Platform Abstraction Layer)

**目标**：通过编译期元编程（S1 阶段），实现 Nebula 在 Linux、Windows 和 Web (Wasm) 平台上的源码级一致性，消除平台相关的硬编码。

---

## 1. 核心张力：阻塞 vs 回调

跨平台重构面临的最大挑战是主循环结构的根本差异：
- **Native (Linux/Win)**：控制权在应用手中，使用 `while` 阻塞循环。
- **Web (Wasm)**：控制权在浏览器手中，必须使用 `emscripten_set_main_loop` 注册回调。

### 解决方案：`nebula_main_loop` 宏
在 `app.nelua` 中引入一个高级宏，封装循环逻辑：

```nelua
## macro nebula_main_loop(app, frame_func)
  ## if NEBULA_TARGET == 'wasm' then
    emscripten_set_main_loop(function()
      frame_func(renderer, app)
    end, 0, 1)
  ## else
    while not glfwWindowShouldClose(window) do
      frame_func(renderer, app)
    end
  ## end
## end
```

---

## 2. 渲染后端抽象：Surface 创建

不同平台创建 WebGPU Surface 的参数完全不同。

### 任务清单：
1. **重构 `renderer.nelua`**：
   - 移除 `glfwGetX11Display` 等硬编码调用。
   - 引入 `nebula_create_surface(instance, window)` 宏。
   - **Windows 路径**：使用 `WGPUSurfaceDescriptorFromWindowsHWND`。
   - **Linux 路径**：根据环境变量选择 X11 或 Wayland 描述符。
   - **Web 路径**：使用 `WGPUSurfaceDescriptorFromCanvasHTML5`。

2. **条件链接 `wgpu-native` 扩展**：
   - 仅在 Native 目标下包含 `WGPUInstanceExtras`。
   - Web 目标下直接使用标准 WebGPU C API。

---

## 3. 构建系统升维：`build.sh`

重构 `build.sh` 使其具备多端编译能力：

```bash
# 用法示例: ./build.sh --target=wasm examples/text_demo.nelua

if [ "$TARGET" == "wasm" ]; then
    nelua --cc emcc --cflags="-sUSE_WEBGPU=1 -sUSE_GLFW=3" ...
elif [ "$TARGET" == "windows" ]; then
    # 交叉编译或在 Windows 环境下使用 cl.exe
    nelua --cc cl --cflags="/I vendor/wgpu/include user32.lib gdi32.lib" ...
fi
```

---

## 4. 进度安排

### 第一阶段：PAL 骨架 (S1 宏定义)
- 在 `nebula_core.nelua` 中定义 `NEBULA_TARGET` 检测逻辑。
- 在 `app.nelua` 中实现 `nebula_main_loop`。

### 第二阶段：Surface 兼容性适配
- 修复 Windows 下的 `HWND` 获取与 Surface 创建。
- 修复 Web 下的 Canvas 关联。

### 第三阶段：CJK 与 HarfBuzz 集成
- 在 PAL 稳固后，集成 HarfBuzz 预处理器。
- 验证 CJK 在三端的渲染一致性。

---

## 5. 验收标准
1. **源码一致性**：同一个 `examples/form_demo.nelua` 无需修改即可在三端编译运行。
2. **性能无损**：Native 端的阻塞循环效率不因宏封装而下降。
3. **零运行时分支**：最终生成的二进制中不包含任何运行时的 `if (platform == ...)` 判断。
