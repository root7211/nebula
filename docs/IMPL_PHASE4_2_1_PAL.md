# Phase 4.2.1 实施方案：跨平台 PAL 骨架

**文档版本**：v1.0（基于 glfw3webgpu + webgpu-headers 官方规范研究）
**前置文档**：`PLAN_PHASE4_2_1_PAL.md`（需求与验收标准）、`ARCHITECTURE_GRAND_PLAN.md` v3.1
**当前代码基线**：Phase 4.1 完成，NEBULA_TARGET 检测已部分实现

---

## 0. 研究结论摘要

在动手编码前，我们对 WebGPU 跨平台 Surface 创建的工业最佳实践进行了调研。核心参考对象是 **glfw3webgpu**（eliemichel/glfw3webgpu，107 stars，MIT 协议），它是 WebGPU C++ 社区事实上的标准跨平台 Surface 创建库，被 "Learn WebGPU for C++" 教程系列采用。

调研发现了三个关键事实，直接影响本阶段的实施策略：

**事实一：官方 SType 值与我们的初始假设不同。** webgpu-headers 官方规范（webgpu-native.github.io）定义的 Surface Source SType 值如下表所示，其中 Windows HWND 和 Canvas HTML Selector 的值与我们最初编写的不一致，已在 `wgpu_bindings.nelua` 中修正。

| Surface Source | 官方 SType 值 | 初始错误值 |
| :--- | :--- | :--- |
| MetalLayer (macOS) | `0x00000004` | 未定义 |
| WindowsHWND | `0x00000005` | `0x00000008` |
| XlibWindow (X11) | `0x00000006` | 正确 |
| WaylandSurface | `0x00000007` | 未定义 |
| CanvasHTMLSelector (Web) | `0x0000000F` | `0x00000004` |

**事实二：Linux 必须区分 X11 和 Wayland。** GLFW 3.4 默认同时编译 X11 和 Wayland 支持，并在运行时通过 `glfwGetPlatform()` 选择。glfw3webgpu 为两者提供了完全不同的 Surface 创建路径（`WGPUSurfaceSourceXlibWindow` vs `WGPUSurfaceSourceWaylandSurface`）。Nebula 的原始计划仅考虑了 X11，这在现代 Linux 桌面（GNOME 46+ 默认 Wayland）上是不够的。

**事实三：Windows 的 hinstance 应使用 Win32 API 而非 GLFW。** glfw3webgpu 使用 `GetModuleHandle(NULL)` 获取 hinstance，而非任何 GLFW 函数。这是因为 GLFW 并未提供获取 HINSTANCE 的公开 API。

---

## 1. 架构决策：编译期 vs 运行时平台分支

glfw3webgpu 采用的是 **C 预处理器 + 运行时 switch** 的混合策略：预处理器控制哪些平台分支被编译进二进制，`glfwGetPlatform()` 在运行时选择实际执行的分支。这种方式的优势是单一二进制可以同时支持 X11 和 Wayland。

Nebula 的公理 A 要求 **零运行时分支**，因此我们不能照搬 glfw3webgpu 的运行时 switch 模式。但这引出了一个重要的设计抉择：

> **Linux 上的 X11/Wayland 选择应该在编译期还是运行时决定？**

### 决策：引入 NEBULA_LINUX_DISPLAY 编译期子变量

我们的方案是在 `NEBULA_TARGET == 'linux'` 时引入第二级编译期常量 `NEBULA_LINUX_DISPLAY`，合法值为 `"x11"`（默认）和 `"wayland"`。这样做的理由如下：

第一，**公理 A 合规性**。Nebula 的核心哲学是编译期消解所有平台差异，生成的二进制中不存在任何运行时 `if (platform == ...)` 分支。引入运行时检测会破坏这一根基。

第二，**实际影响可控**。与 glfw3webgpu 面向的通用库场景不同，Nebula 的用户是 GUI 应用开发者，他们在发布时明确知道目标环境。提供 `NEBULA_LINUX_DISPLAY=wayland` 编译选项比运行时自动检测更符合 Nebula 的"编译即部署"理念。

第三，**未来可扩展**。如果未来确实需要单一二进制同时支持 X11 和 Wayland，可以在 Era III 的运行时层中引入，而不是在 PAL 骨架阶段就破坏公理 A。

---

## 2. 变更清单与实施顺序

以下是按依赖关系排序的完整变更清单。每个变更标注了涉及的文件、变更性质（新增/修改/删除）和预估代码行数。

### 第一步：NEBULA_TARGET 检测逻辑（已完成）

**文件**：`src/nebula_core.nelua`（修改）

此步骤已在之前的工作中完成。在 `nebula_core.nelua` 的文件头部加入了 S1 阶段的平台检测逻辑，支持三级优先级（编译器 `-D` > 环境变量 > ccinfo 自动检测），合法值为 `linux`、`windows`、`wasm`。

**需要补充的变更**：在 `NEBULA_TARGET == 'linux'` 的分支中，增加 `NEBULA_LINUX_DISPLAY` 的检测逻辑。检测优先级同样为：编译器 `-D` > 环境变量 > 默认值 `"x11"`。代码如下：

```lua
##[[
  if NEBULA_TARGET == "linux" then
    if not NEBULA_LINUX_DISPLAY then
      local env_display = os.getenv("NEBULA_LINUX_DISPLAY")
      if env_display and env_display ~= "" then
        NEBULA_LINUX_DISPLAY = env_display
      else
        NEBULA_LINUX_DISPLAY = "x11"  -- 默认 X11
      end
    end
    local valid_displays = { x11 = true, wayland = true }
    assert(valid_displays[NEBULA_LINUX_DISPLAY],
      "[nebula] NEBULA_LINUX_DISPLAY must be 'x11' or 'wayland', got: '"
      .. tostring(NEBULA_LINUX_DISPLAY) .. "'")
    print("[nebula] S1: NEBULA_LINUX_DISPLAY = " .. NEBULA_LINUX_DISPLAY)
  end
]]
```

**预估行数**：+15 行

---

### 第二步：wgpu_bindings.nelua Surface 结构体（已完成）

**文件**：`src/wgpu_bindings.nelua`（修改）

此步骤已在之前的工作中完成。SType 值已修正为官方规范值，并新增了 `WGPUSurfaceSourceWaylandSurface` 和 `WGPUSurfaceSourceCanvasHTMLSelector` 结构体绑定。完整的 Surface Source 结构体清单如下：

| 结构体 | 平台 | 状态 |
| :--- | :--- | :--- |
| `WGPUSurfaceSourceXlibWindow` | Linux X11 | 已有（Phase 0） |
| `WGPUSurfaceSourceWaylandSurface` | Linux Wayland | 新增 |
| `WGPUSurfaceSourceWindowsHWND` | Windows | 新增 |
| `WGPUSurfaceSourceCanvasHTMLSelector` | Web | 新增（名称已修正） |

**无需额外变更。**

---

### 第三步：glfw_bindings.nelua 条件平台导入

**文件**：`src/glfw_bindings.nelua`（修改）
**预估行数**：+40 行（净增）

这是当前实施的关键瓶颈。现有的 `glfw_bindings.nelua` 在文件顶部硬编码了 `GLFW_EXPOSE_NATIVE_X11`，导致在非 X11 环境下编译会引入不存在的头文件。需要进行以下改造：

**3a. 条件化 native header 导入**

将文件顶部的无条件 X11 导入改为基于 `NEBULA_TARGET` 和 `NEBULA_LINUX_DISPLAY` 的条件编译：

```lua
## linklib "glfw"
## cinclude "<GLFW/glfw3.h>"

## if NEBULA_TARGET ~= 'wasm' then
  -- Native 端需要 glfw3native.h 获取平台原生句柄
  ## if NEBULA_TARGET == 'linux' then
    ## if NEBULA_LINUX_DISPLAY == 'wayland' then
      ## cdefine "GLFW_EXPOSE_NATIVE_WAYLAND"
    ## else
      ## cdefine "GLFW_EXPOSE_NATIVE_X11"
    ## end
  ## elseif NEBULA_TARGET == 'windows' then
    ## cdefine "GLFW_EXPOSE_NATIVE_WIN32"
  ## end
  ## cinclude "<GLFW/glfw3native.h>"
## end
```

**3b. 条件化 native 函数绑定**

将现有的 `glfwGetX11Display` / `glfwGetX11Window` 包裹在条件编译中，并新增 Wayland 和 Windows 的对应函数：

```lua
-- Linux X11 原生访问
## if NEBULA_TARGET == 'linux' and NEBULA_LINUX_DISPLAY == 'x11' then
global function glfwGetX11Display(): pointer <cimport, nodecl> end
global function glfwGetX11Window(window: GLFWwindow): uint64 <cimport, nodecl> end
## end

-- Linux Wayland 原生访问
## if NEBULA_TARGET == 'linux' and NEBULA_LINUX_DISPLAY == 'wayland' then
global function glfwGetWaylandDisplay(): pointer <cimport, nodecl> end
global function glfwGetWaylandWindow(window: GLFWwindow): pointer <cimport, nodecl> end
## end

-- Windows 原生访问
## if NEBULA_TARGET == 'windows' then
global function glfwGetWin32Window(window: GLFWwindow): pointer <cimport, nodecl> end
-- 注意：hinstance 通过 Win32 API GetModuleHandle 获取，非 GLFW 函数
## cinclude "<windows.h>"
global function GetModuleHandleA(lpModuleName: cstring): pointer <cimport, nodecl> end
## end
```

**3c. Web 端特殊处理**

Web 端不需要 `glfw3native.h`，但需要 Emscripten 的主循环 API（为第五步准备）：

```lua
## if NEBULA_TARGET == 'wasm' then
## cinclude "<emscripten.h>"
global function emscripten_set_main_loop(
  func: function(): void, fps: int32, simulate_infinite_loop: int32
): void <cimport, nodecl> end
## end
```

---

### 第四步：renderer.nelua Surface 创建重构

**文件**：`src/renderer.nelua`（修改）
**预估行数**：+15 行（净增，主要是 Wayland 路径）

当前 `renderer.nelua` 中的 Surface 创建已经有了三路条件编译的骨架（linux/windows/wasm），但存在以下问题需要修正：

**4a. Linux 路径拆分为 X11 和 Wayland**

将 `## if NEBULA_TARGET == 'linux'` 内部进一步细分：

```lua
## if NEBULA_TARGET == 'linux' then
  ## if NEBULA_LINUX_DISPLAY == 'wayland' then
  -- Linux (Wayland) 路径
  local wl_src = WGPUSurfaceSourceWaylandSurface{
    chain   = WGPUChainedStruct{
      next  = nilptr,
      sType = WGPUSType_SurfaceSourceWaylandSurface,
    },
    display = glfwGetWaylandDisplay(),
    surface = glfwGetWaylandWindow(window),
  }
  local surf_desc = WGPUSurfaceDescriptor{
    nextInChain = (@*WGPUChainedStruct)(&wl_src),
    label       = wgpu_str_null(),
  }
  ## else
  -- Linux (X11) 路径（保持现有代码不变）
  -- ...
  ## end
## end
```

**4b. Windows 路径修正 hinstance 获取方式**

将 `glfwGetWin32Module()` 替换为 `GetModuleHandleA(nilptr)`：

```lua
## elseif NEBULA_TARGET == 'windows' then
local hwnd_src = WGPUSurfaceSourceWindowsHWND{
  chain = WGPUChainedStruct{
    next  = nilptr,
    sType = WGPUSType_SurfaceSourceWindowsHWND,
  },
  hinstance = GetModuleHandleA(nilptr),  -- 修正：使用 Win32 API
  hwnd      = glfwGetWin32Window(window),
}
```

**4c. Web 路径修正结构体名称**

将 `WGPUSurfaceSourceCanvasHTMLSelector_Unpacked` 替换为 `WGPUSurfaceSourceCanvasHTMLSelector`，对应的 SType 也需要更新：

```lua
## elseif NEBULA_TARGET == 'wasm' then
local canvas_src = WGPUSurfaceSourceCanvasHTMLSelector{
  chain = WGPUChainedStruct{
    next  = nilptr,
    sType = WGPUSType_SurfaceSourceCanvasHTMLSelector,
  },
  selector = "#nebula-canvas",
}
```

---

### 第五步：app.nelua 主循环宏

**文件**：`src/app.nelua`（修改）
**预估行数**：+45 行

这是 PAL 骨架中最具架构意义的变更。当前的 `examples/*.nelua` 使用裸 `while` 循环，这在 Web 端无法工作（Emscripten 要求使用回调式主循环）。

**5a. 新增 `nebula_main_loop` 宏**

在 `nebula_shutdown` 之后新增：

```lua
-- ★ Phase 4.2.1: nebula_main_loop — 跨平台主循环宏
--
-- 公理 A 合规：Native 端展开为 while 阻塞循环，Web 端展开为
-- emscripten_set_main_loop 回调注册。生成代码中不存在运行时分支。
--
-- 使用方式（替代原来的 while not nebula_should_close() do ... end）：
--   nebula_main_loop(renderer, app, input, clear_r, clear_g, clear_b)
##[[
function nebula_main_loop(renderer_sym, app_sym, input_sym, cr, cg, cb)
  ]]
  ## if NEBULA_TARGET == 'wasm' then
  -- Web: 将帧逻辑封装为回调，交给浏览器调度
  local function _nebula_wasm_frame(): void
    glfwPollEvents()
    local now = glfwGetTime()
    -- dt 计算使用全局变量
    local dt = (@float32)(now - _nebula_last_time)
    _nebula_last_time = now
    nebula_collect_input(&## renderer_sym ##, &## input_sym ##)
    nebula_frame_render(&## renderer_sym ##, &## app_sym ##, &## input_sym ##, dt, ## cr ##, ## cg ##, ## cb ##)
  end
  emscripten_set_main_loop(_nebula_wasm_frame, 0, 1)
  ## else
  -- Native: 传统阻塞循环
  while not nebula_should_close() do
    glfwPollEvents()
    local now = glfwGetTime()
    local dt = (@float32)(now - _nebula_last_time)
    _nebula_last_time = now
    nebula_collect_input(&## renderer_sym ##, &## input_sym ##)
    nebula_frame_render(&## renderer_sym ##, &## app_sym ##, &## input_sym ##, dt, ## cr ##, ## cg ##, ## cb ##)
  end
  ## end
  ##[[
end
]]
```

> **注意**：上述伪代码展示的是设计意图。Nelua 宏的实际语法需要根据 Nelua 的元编程 API 进行调整，特别是符号引用（`## sym ##`）的具体写法。这是实施时需要验证的技术点。

**5b. 新增 Web 端全局时间变量**

```lua
## if NEBULA_TARGET == 'wasm' then
global _nebula_last_time: float64 = 0.0
## end
```

**5c. 对现有 API 的影响**

`nebula_main_loop` 是**新增** API，不会破坏现有的 `nebula_should_close` / `nebula_poll_events` 等函数。现有的 `examples/*.nelua` 可以逐步迁移，不需要一次性全部改写。迁移后的 example 代码将从约 15 行主循环缩减为 1 行宏调用。

---

### 第六步：build.sh 多端编译支持

**文件**：`build.sh`（修改）
**预估行数**：+60 行

**6a. 新增 `--target` 参数解析**

```bash
# 解析 --target 参数（默认 linux）
TARGET="linux"
DISPLAY_TYPE="x11"
for arg in "$@"; do
  case "$arg" in
    --target=*) TARGET="${arg#*=}" ;;
    --display=*) DISPLAY_TYPE="${arg#*=}" ;;
  esac
done
```

**6b. 根据 target 选择编译工具链**

```bash
case "$TARGET" in
  linux)
    NEBULA_FLAGS="-D NEBULA_TARGET=linux -D NEBULA_LINUX_DISPLAY=$DISPLAY_TYPE"
    LINK_FLAGS="-lwgpu_native -lglfw -lm -ldl"
    ;;
  windows)
    NEBULA_FLAGS="-D NEBULA_TARGET=windows"
    LINK_FLAGS="-lwgpu_native -lglfw3 -luser32 -lgdi32 -lshell32"
    ;;
  wasm)
    NEBULA_FLAGS="-D NEBULA_TARGET=wasm"
    CC_OVERRIDE="--cc emcc"
    LINK_FLAGS="-sUSE_WEBGPU=1 -sUSE_GLFW=3 -sALLOW_MEMORY_GROWTH=1"
    ;;
esac
```

**6c. 更新文件头注释**

将 "Phase 3.10.5" 更新为 "Phase 4.2.1"，并添加新的使用说明。

---

### 第七步：冒烟测试

**文件**：`tests/smoke_phase4_2_1_pal.sh`（新增）
**预估行数**：约 50 行

冒烟测试验证 PAL 骨架的编译期行为是否正确。由于我们无法在单一 CI 环境中同时拥有三个平台的完整工具链，测试策略分为两层：

**第一层：编译期断言测试（可在 Linux CI 上运行）**

```bash
# 测试 1: 默认 target 应为 linux
NEBULA_TARGET="" nelua -L src nebula_core.nelua 2>&1 | grep "NEBULA_TARGET = linux"

# 测试 2: 环境变量覆盖
NEBULA_TARGET=windows nelua -L src nebula_core.nelua 2>&1 | grep "NEBULA_TARGET = windows"

# 测试 3: 非法 target 应触发 assert
NEBULA_TARGET=macos nelua -L src nebula_core.nelua 2>&1 | grep "must be"

# 测试 4: Linux display 默认值
NEBULA_TARGET=linux nelua -L src nebula_core.nelua 2>&1 | grep "NEBULA_LINUX_DISPLAY = x11"

# 测试 5: Wayland display
NEBULA_TARGET=linux NEBULA_LINUX_DISPLAY=wayland nelua -L src nebula_core.nelua 2>&1 | grep "NEBULA_LINUX_DISPLAY = wayland"
```

**第二层：Linux X11 端到端测试（需要 GPU 或 Xvfb）**

```bash
# 测试 6: form_demo 在 linux/x11 下编译成功
./build.sh --target=linux --display=x11 form_demo

# 测试 7: 生成的二进制不包含运行时平台分支（nm 检查）
nm ~/.cache/nelua/form_demo | grep -v "glfwGetWayland"  # 不应包含 Wayland 符号
nm ~/.cache/nelua/form_demo | grep -v "GetModuleHandle"  # 不应包含 Win32 符号
```

---

### 第八步：文档更新

**文件**：`README.md`（修改）、`docs/ARCHITECTURE_GRAND_PLAN.md`（修改）

**8a. README.md**

在"快速开始"部分增加多平台编译说明：

```markdown
## 跨平台编译（Phase 4.2.1+）

# Linux (X11，默认)
./build.sh form_demo

# Linux (Wayland)
./build.sh --target=linux --display=wayland form_demo

# Windows（需要在 Windows 环境或交叉编译工具链下）
./build.sh --target=windows form_demo

# Web (Wasm，需要 Emscripten SDK)
./build.sh --target=wasm form_demo
```

**8b. ARCHITECTURE_GRAND_PLAN.md**

在 Phase 4.2.1 条目中标注"已完成"，并在技术债登记表中记录本阶段产生的新债务（若有）。

---

## 3. 风险评估与缓解

| 风险 | 严重程度 | 缓解策略 |
| :--- | :--- | :--- |
| Nelua 宏语法不支持预期的符号引用方式 | 高 | 第五步实施前先编写最小验证用例，确认 Nelua 宏的 AST 注入能力 |
| Windows 交叉编译在 Linux CI 上不可行 | 中 | 第七步的 Windows 测试仅验证编译期断言，不要求链接成功 |
| Wayland 下 GLFW 的 `glfwGetWaylandWindow` 返回 `wl_surface*` 而非窗口句柄 | 低 | 已在 glfw3webgpu 源码中确认，`WGPUSurfaceSourceWaylandSurface.surface` 接收的正是 `wl_surface*` |
| Emscripten 的 `emscripten_set_main_loop` 与 Nelua 的函数指针兼容性 | 中 | 第五步实施前先编写最小 Emscripten 编译测试 |
| `build.sh` 参数解析与现有 demo target 参数冲突 | 低 | 使用 `--target=` 长选项格式，与现有的位置参数（demo 名称）不冲突 |

---

## 4. 实施顺序总结

以下是推荐的实施顺序，按依赖关系排列。每一步完成后应立即提交，确保 git 历史的原子性。

| 步骤 | 文件 | 内容 | 依赖 |
| :--- | :--- | :--- | :--- |
| 1 | `nebula_core.nelua` | 补充 `NEBULA_LINUX_DISPLAY` 检测 | 无 |
| 2 | `wgpu_bindings.nelua` | 已完成（SType 修正 + Wayland 结构体） | 无 |
| 3 | `glfw_bindings.nelua` | 条件化 native header 导入 + 多平台函数绑定 | 步骤 1 |
| 4 | `renderer.nelua` | Surface 创建四路分支 + hinstance 修正 | 步骤 2, 3 |
| 5 | `app.nelua` | `nebula_main_loop` 宏 | 步骤 3（Emscripten 绑定） |
| 6 | `build.sh` | `--target` / `--display` 参数 + 多工具链 | 步骤 1 |
| 7 | `tests/smoke_phase4_2_1_pal.sh` | 编译期断言 + 符号检查 | 步骤 1-6 |
| 8 | `README.md` + `ARCHITECTURE_GRAND_PLAN.md` | 文档更新 | 步骤 7 |

---

## 5. 与原始计划的差异

本实施方案相对于 `PLAN_PHASE4_2_1_PAL.md` 的主要变化如下：

**新增 `NEBULA_LINUX_DISPLAY` 子变量。** 原计划提到"根据环境变量选择 X11 或 Wayland 描述符"，但未明确是编译期还是运行时选择。本方案明确为编译期，并引入了专用的子变量。

**新增 Wayland 完整路径。** 原计划仅在任务清单中简要提及 Wayland，本方案提供了完整的结构体绑定、GLFW 函数绑定和 Surface 创建代码。

**修正 Windows hinstance 获取方式。** 原计划未涉及此细节，本方案基于 glfw3webgpu 的实践明确使用 `GetModuleHandle(NULL)`。

**修正所有 SType 值。** 原计划使用了假设值，本方案使用 webgpu-headers 官方规范值。

**保留 macOS 为未来扩展。** 虽然 glfw3webgpu 支持 macOS (Metal)，但 Nebula 的原始计划范围为 Linux/Windows/Web 三端。macOS 支持需要 Objective-C 代码（`CAMetalLayer`），超出本阶段范围，但 `wgpu_bindings.nelua` 中已预留了 `WGPUSType_SurfaceSourceMetalLayer` 的 SType 值。
