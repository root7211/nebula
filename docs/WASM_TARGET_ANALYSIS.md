# Nebula WebAssembly (Wasm) 编译目标可行性与演进分析

如果 Nebula 未来计划编译到 WebAssembly (Wasm) 并在浏览器中运行，这将是一个极具战略意义的跨越。Nebula 的核心语言 Nelua 本身就是为了编译到 C 并支持嵌入式/Web 环境而设计的，但 Nebula 作为一个图形框架，其依赖的渲染后端和窗口系统与 Wasm 生态之间存在复杂的交互。

本文基于 Nebula 当前的技术栈（Phase 3.2.5），详细分析将其移植到 Wasm 目标的兼容性、技术障碍及演进路径。

---

## 1. 核心语言层：Nelua 与 Wasm 的天然契合

**兼容性：极高**

Nelua 语言的官方设计目标之一就是支持 WebAssembly。Nelua 代码会被转译为纯净的 C 代码，这意味着它可以无缝接入 Emscripten 工具链（使用 `emcc` 替代 `gcc` 或 `clang`）[1]。

*   **零运行时优势**：由于 Nebula 在编译期（Lua 宏阶段）就完成了所有的布局推导、着色器组合和状态机生成，生成的 C 代码中不包含任何 Lua 虚拟机或庞大的运行时库。这使得 Nebula 编译出的 `.wasm` 二进制文件将极其小巧（可能在几百 KB 级别），远胜于携带完整虚拟机的传统脚本语言。
*   **内存模型匹配**：Nelua 默认的线性内存管理和手动分配（或 Arena 分配）与 Wasm 的线性内存模型（Linear Memory）完美契合。如前所述，Nebula 不需要依赖 Wasm GC 提案，这反而保证了其在所有支持基础 Wasm 的浏览器中的最高兼容性和可预测的极低延迟 [2]。

## 2. 渲染后端层：wgpu-native 与 WebGPU 的映射

**兼容性：中等，需调整构建链**

Nebula 目前硬依赖于 `wgpu-native`（基于 Rust 的 WebGPU C API 实现）。
*   **原生环境**：`wgpu-native` 将 WebGPU API 调用翻译为底层的 Vulkan、Metal 或 DX12 调用。
*   **Wasm 环境**：在浏览器中，底层图形 API 就是浏览器原生提供的 WebGPU（或通过 Emscripten 桥接的 WebGL）。

**演进路径**：
在编译为 Wasm 时，Nebula **不能也不应该**将 `wgpu-native` 库编译进去。相反，Emscripten 提供了一个特殊的链接标志 `-sUSE_WEBGPU=1` [3]。
1.  Nebula 的 C 绑定代码（`wgpu_bindings.nelua`）声明的 C 函数签名（如 `wgpuDeviceCreateBuffer`）与标准的 `webgpu.h` 是一致的。
2.  当使用 Emscripten 编译时，这些 C 函数调用会被 Emscripten 的 JavaScript 胶水代码拦截，并直接映射到浏览器全局的 `navigator.gpu` API [3]。
3.  **挑战**：Nebula 当前的 `renderer.nelua` 中包含了一些特定于 `wgpu-native` 的扩展（如 `WGPUInstanceExtras` 和 `WGPUInstanceBackend_All`），这些在标准的 Web 浏览器 WebGPU API 中是不存在的。必须通过条件编译（`## if not wasm then ...`）将这些原生扩展隔离。

## 3. 窗口与事件层：GLFW 的 Wasm 适配

**兼容性：低，需重构事件循环**

Nebula 当前的窗口创建和事件收集完全依赖于 GLFW 3（`glfw_bindings.nelua` 和 `app.nelua`），并使用了 X11 特定的原生句柄（`glfwGetX11Display`）。

**演进路径**：
1.  **Emscripten 内置 GLFW 端口**：Emscripten 提供了一个对 GLFW 3 的部分实现，它可以将 `glfwCreateWindow` 映射到 HTML5 的 `<canvas>` 元素，并将浏览器的鼠标/键盘事件转换为 GLFW 事件 [4]。
2.  **事件循环的倒置**：这是 Wasm 移植中最经典的痛点。在原生应用中，Nebula 使用 `while (true)` 死循环（阻塞式）。但在浏览器中，主线程不能被阻塞，否则页面会卡死。必须使用 Emscripten 的 `emscripten_set_main_loop` 将单帧更新逻辑（即目前 `while` 循环体内的代码）注册为回调函数 [5]。
3.  **Surface 创建的修改**：在 Wasm 中，不需要（也不能）通过 X11 或 Win32 句柄创建 WebGPU Surface。Emscripten 的 WebGPU 绑定提供了一种直接从 HTML Canvas 获取 Surface 的方法。`renderer.nelua` 中的 Surface 初始化代码必须为 Wasm 单独编写。

## 4. 资源与文件系统：字体与图像的加载

**兼容性：需异步化改造**

Nebula 目前在 `text_runtime.nelua` 中使用 C 标准库的 `fopen` 和 `fread` 同步读取本地文件系统中的字体 SDF 图集（如 `assets/generated/liberation_sans_ascii_48_sdf.pgm`）。

**演进路径**：
*   **虚拟文件系统**：最简单的方案是利用 Emscripten 的 `--preload-file` 功能，将 `assets` 目录打包进一个 `.data` 文件中。这样 Wasm 启动时会建立一个内存虚拟文件系统，原有的 `fopen` 代码可以无需修改直接运行 [5]。
*   **异步 Fetch**：如果资源较大，更现代的做法是使用浏览器的 `fetch` API 异步下载资源，但这需要对 Nebula 的初始化流程进行异步化改造，这在 C/Nelua 层面实现起来相对复杂。

## 5. 总结与路线图建议

如果 Nebula 决定将 Wasm 作为一等公民支持，其演进路线图建议如下：

1.  **构建系统改造**：在 `build.sh` 中引入 `emcc` 编译分支，添加 `-sUSE_WEBGPU=1` 和 `-sUSE_GLFW=3` 标志。
2.  **平台抽象层 (PAL)**：将 `renderer.nelua` 和 `app.nelua` 中的平台相关代码（Surface 创建、事件循环、扩展配置）抽象出来，使用 Nelua 的预处理器宏区分 `native` 和 `wasm` 目标。
3.  **主循环重构**：将现有的 `while` 循环重构为单帧 `tick()` 函数，以便原生环境和 `emscripten_set_main_loop` 都能调用。
4.  **资源打包**：配置 Emscripten 的文件预加载，确保 SDF 字体等资产能在浏览器中被正确读取。

**结论**：Nebula 编译到 Wasm 在技术上是完全可行的，且其“编译期元编程”的特性将使其在 Wasm 平台上展现出惊人的体积优势和启动速度。最大的障碍在于剥离特定于原生操作系统的窗口句柄，并适应浏览器的非阻塞事件循环模型。

---

### 参考文献
[1] Nelua Official Documentation. "Overview - Systems programming language for performance."
[2] WebAssembly Community. "WebAssembly GC Proposal and Linear Memory."
[3] Emscripten Documentation. "Targeting WebGPU from Wasm with wasm_webgpu bindings."
[4] Pongasoft. "emscripten-glfw: An emscripten port of GLFW written in C++ for the web/wasm platform."
[5] Emscripten Documentation. "Compiling and running WebAssembly code: Main Loop and File System."
