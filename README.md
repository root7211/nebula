# Nebula GUI Compiler

**Nebula** 是一个用编译期元编程把"声明意图"翻译成"等价手写代码"的 GUI 编译器。它的核心主张是**阶段封闭性**：

> 每个操作必须归属于其输入最早全部可知的阶段。后一阶段不得执行前一阶段的操作，前一阶段的输出是后一阶段的不可变输入。

Nebula 不是运行时框架，不是响应式引擎，也不是场景图。它是一个 **Nelua 宏驱动的代码生成器**——开发者声明组件的形状、交互原语和布局意图，Nebula 在编译期将这些声明翻译成零开销、零样板、零运行时分发的 WebGPU 渲染代码。

---

### 当前状态：Phase 4.2.1 (PAL 骨架) 进行中

**Phase 3.6.2 至 Phase 4.2.1 已全部合入主线**，全量回归测试（包含 Lua 冒烟测试和编译测试）**全部通过**。

Phase 4.2.1 交付了 **跨平台 PAL (Platform Abstraction Layer) 骨架**，为 Nebula 建立了跨 Linux X11 / Linux Wayland / Windows / Web 四端的编译期平台抽象：

- **平台检测**：`nebula_core.nelua` 引入 `NEBULA_TARGET`（linux/windows/wasm）和 `NEBULA_LINUX_DISPLAY`（x11/wayland）编译期变量，支持三级优先级（`-D` 传参 > 环境变量 > 自动检测），非法值触发 S1 阶段断言。
- **Surface 创建抽象**：`renderer.nelua` 将 Surface 创建从单一 X11 路径扩展为四路条件编译（X11 / Wayland / Windows HWND / Web Canvas），修正了 SType 值为 webgpu-headers 官方规范值，修正了 Windows `hinstance` 获取方式（改用 `GetModuleHandleA(nilptr)`）。
- **GLFW 绑定条件化**：`glfw_bindings.nelua` 将 native 函数绑定改为条件化导入，新增 Wayland / Win32 / Emscripten 函数绑定，移除硬编码的 `GLFW_EXPOSE_NATIVE_X11`。
- **主循环宏**：`app.nelua` 引入 `nebula_main_loop` 宏，封装 Native（阻塞式 while）与 Web（Emscripten 回调）的循环差异，公理 A 合规（所有分支在 S1 阶段消解）。
- **构建系统升级**：`build.sh` 支持 `--target=linux|windows|wasm` 和 `--display=x11|wayland` 参数，自动配置对应编译标志。

Phase 4.1 交付了 **Slug 文本渲染引擎 MVP**，将 Nebula 的文本渲染从 ASCII-only SDF 升级为基于贝塞尔曲线的纯数学矢量渲染。**作为 MVP，它有意识地引入了三项内核债务**（均匀 Band、跳过 Jacobian、Storage Buffer 路径），这些债务已登记于 [ARCHITECTURE_GRAND_PLAN.md §5.2](docs/ARCHITECTURE_GRAND_PLAN.md)，并计划在 Phase 4.2.2 / 4.2.3 清算。MVP 的核心实现如下：

- **S0 阶段（字体预处理器扩展）**：`font_preprocessor_slug.nelua` 在编译期提取 95 个字形的 2328 条贝塞尔曲线和 8811 条 Band 引用，生成 `liberation_sans_slug_metrics.nelua`。
- **S1 阶段（着色器与管线生成）**：`shader_compose.lua` 新增 `nebula_compose_slug_shader`，生成包含 Slug 覆盖率计算的 WGSL 着色器；`pipeline_factory.lua` 新增 `gen_pipeline_slug_text` 路径；`app_factory.lua` 支持 `text_mode=slug` 配置。
- **S2 阶段（运行时顶点装配）**：`text_runtime.nelua` 新增 `NebulaSlugVertex` 结构体和 `nebula_slug_text_build_vertices` 函数；`nebula_core.nelua` 新增 `nebula_derive_slug_text_visual` 派生路径。

---

## 愿景：30 行终态

当路线图全部完成后，一个完整的表单应用将是这样的：

```nelua
require "nebula"

##[[
  nebula_annotate("CardVisual",   { ... })
  nebula_annotate("InputVisual",  { primitives = {"hoverable","clickable","focusable","editable"}, max_text_len = 255 })
  nebula_annotate("TextVisual",   { text_mode = "ascii_sdf" })
  nebula_annotate("ButtonVisual", { ... })
]]
## nebula_derive("CardVisual"); nebula_derive("InputVisual"); nebula_derive("TextVisual"); nebula_derive("ButtonVisual")

##[[
  nebula_app_begin("FormApp")
    nebula_app_set_root_layout("FormApp", { direction = "column", padding = 32, gap = 16 })
    nebula_app_register_component("card",        "CardVisual",   { layout = { width = 480, height = 320 } })
    nebula_app_register_component("email_input", "InputVisual",  { component_id = 1, layout = { height = 40 } })
    nebula_app_register_text     ("email_label", { bound_to = "email_input", placeholder = "email" })
    nebula_app_register_component("login_btn",   "ButtonVisual", { layout = { height = 44 } })
  nebula_app_end()
]]
## nebula_derive_app("FormApp")

local function main()
  local renderer: NebulaRenderer
  local app:      FormApp
  if not nebula_init(&renderer, &app) then return 1 end
  while not nebula_should_close() do
    nebula_frame_render(&renderer, &app)
  end
  return 0
end
main()
```

**30 行，零样板，零 WGPU 调用，零 Pipeline 初始化代码，零 Arena 管理代码。**

---

## 三大哲学公理

Nebula 的全部设计决策由三条公理驱动，三者作用于正交维度（详见 [`docs/ARCHITECTURE_GRAND_PLAN.md`](docs/ARCHITECTURE_GRAND_PLAN.md)）：

**公理 A（阶段封闭性）**：Nebula 的生命周期被划分为三个严格有序的阶段——S0（预处理）、S1（编译）、S2（运行）。每个操作必须归属于其输入最早全部可知的阶段。后一阶段不得执行前一阶段的操作。

**公理 B（生命周期三层）**：运行时数据存在且仅存在三种生命周期——L0（永久层，应用全生命周期）、L1（持久层，跨帧存活）、L2（帧级层，单帧瞬时）。每个数据必须显式归属其一，层间依赖严格单向。

**公理 C（形即渲染）**：每一个 Visual 类型 V 在 S1 阶段必须确定性地映射到一个管线签名 Σ(V) = (VertexLayout, UniformsLayout, ShaderModule, BlendState)。

**元规则 Π（正交性）**：三条公理分别约束时间（A）、空间（B）、映射（C），不应产生冲突。如果出现表面冲突，应修订公理的形式化表述，而非裁决优先级。

---

## 架构路线图

| Phase | 名称 | 消除张力 | 状态 |
| :--- | :--- | :--- | :--- |
| 3.6.2 | 鼠标命中与栈上排版 | T2 | **已完成** |
| 3.6.3 | 多行文本与 Selection | T2 | **已完成** |
| 3.7 | 管线生成器收敛与死代码清理 | T1 | **已完成** |
| 3.8 | 渲染循环封装与 FrameArena 内嵌 | T5, T6 | **已完成** |
| 3.9 | 文本一等公民 + Slot Producer 重构 | T3, T4 | **已完成** |
| **3.10** | **原语注册中心** | **T7** | **已完成** |
| 3.10.5 | 独立文本标签 + 多 Pass 渲染 | — | 已完成 |
| 3.11 | Layout-App 统一注册 | T8 | **已完成** |
| 3.12 | 响应式重排 (Responsive Reflow) | 视口自适应 | 已完成 |
| **4.0** | **编译期公理校验器** | **防止回退** | **已完成** |
| **4.1** | **Slug 文本渲染引擎 (MVP)** | **Unicode 可行性验证** | **已完成**（引入内核债务 D-4.1-A/B/C） |
| **4.2.1** | **跨平台 PAL 骨架** | **Linux/Windows/Web 三端源码级对齐** | **进行中（当前）** |
| 4.2.2 | Slug 渲染内核生产级化 | 清算 D-4.1-A/B，评估 D-4.1-C | 规划中（可与 4.2.1 并行） |
| 4.2.3 | HarfBuzz + CJK 集成 | 端一致 + 7000 字规模 | 规划中 |
| 4.3 | 可编程原语注册表 | 引导 Era II | 规划中 |
| 4.4 | 高级宏观原语库 | multiline/scrollable/clipboard | 规划中 |
| 4.5 | 小型文本编辑器原型 | Era II 里程碑 | 规划中 |
| 5.0 | 自动化 CI/CD 与工业化发布 | 三端自动回归 | 规划中 |

**当前（Phase 4.1 已完成，进入 Phase 4.2.1）**：Slug 文本渲染引擎 MVP 已交付，47/47 项回归测试全部通过。MVP 限于 95 个 ASCII 字形、均匀 `BAND_COUNT=8`、跳过 Jacobian（详见 [ARCHITECTURE_GRAND_PLAN.md §5.2](docs/ARCHITECTURE_GRAND_PLAN.md) 技术债登记表）。

**下一步（Phase 4.2.1 + 4.2.2 并行 → 4.2.3）**：
- **4.2.1 PAL**：完成 `NEBULA_TARGET` 检测、`nebula_main_loop` 宏封装、三端 Surface 描述符分化，验收载体仍为 ASCII。
- **4.2.2 Slug 生产级化**：清算 D-4.1-A（自适应 band 分割）与 D-4.1-B（Jacobian + SlugDilate），完成 Storage Buffer vs 纹理 benchmark。
- **4.2.3 HarfBuzz + CJK**：在 4.2.1 + 4.2.2 完成后集成 HarfBuzz，按 charset 声明预计算 shaping 表，验证 7000 常用字在三端的一致性与性能。

---

## 各阶段演进

| 维度 | Phase 3.6.x | Phase 3.7/3.8 | Phase 3.9 | Phase 3.10.x | Phase 3.11/3.12 | **Phase 4.0** |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| 核心推导 | Gap Buffer + 选区 | 管线收敛 + 循环封装 | 文本一等公民 + Slot | 原语注册中心 + 独立文本 | Layout-App 统一注册 + 响应式重排 | **公理校验器（任务 A/B/C）** | **Slug 文本渲染引擎（S0/S1/S2）** |
| 渲染技术 | L1/L2 分层 + 栈上排版 | 3 着色器 + 1 行样板 | 文本管线自动注入 | 元数据驱动 + 多 Pass 阴影 | 编译期分段系数推导 + 运行时扁平插小 | **只读断言模式，不修改状态** | **Slug 算法：贝塞尔曲线 + Band 索引 + Storage Buffer** |
| 质量保障 | 260+ 项断言 | 专项测试 | 25/25 通过 | 27/27 通过，含注册表专项 | 全量回归通过，含 60 项响应式专项 | **28/28 通过，含任务 A/B/C 全覆盖** | **47/47 通过，含 S0/S1/S2 全阶段覆盖** |

---

## 项目结构

```text
nebula/
├── src/
│   ├── nebula_core.nelua           # 编译期推导引擎（含 nebula_derive_app 宏）
│   ├── nebula_arena.nelua          # Frame Arena（含 mark/rewind 局部回收）
│   ├── app.nelua                   # 统一输入收集 + nebula_frame_render 封装
│   ├── gap_buffer.nelua            # 编译期定容 Gap Buffer
│   ├── text_runtime.nelua          # 文本运行时，字形顶点装配与上传
│   ├── renderer.nelua              # WebGPU 渲染器封装
│   └── derive/
│       ├── app_factory.lua         # 编排工厂 v0.4（文本一等公民 + Slot Producer + 多 Pass）
│       ├── pipeline_factory.lua    # 管线工厂（3 条路径）
│       ├── shader_compose.lua      # 着色器组合器（3 个公开函数）
│       ├── interaction_factory.lua # NEBULA_PRIMITIVES 统一注册表
│       ├── layout_engine.lua       # ★ Phase 3.12: 编译期静态 Flexbox + 分段系数推导
│       ├── axiom_validator.lua     # ★ Phase 4.0: 编译期公理校验器（任务 A/B/C）
│       └── gap_buffer_factory.lua  # Gap Buffer 代码生成器
├── assets/
│   └── generated/
│       ├── liberation_sans_sdf_atlas.nelua        # SDF 字体图集
│       └── liberation_sans_slug_metrics.nelua    # ★ Phase 4.1: Slug 字形数据（95 字形、2328 曲线）
├── examples/
│   ├── form_demo.nelua             # 文本一等公民表单演示（主循环 2 行）
│   ├── dynamic_list_demo.nelua     # Slot Producer 动态列表（10,000 项，主循环 3 行）
│   ├── login_demo.nelua            # 登录框演示（密码掩码）
│   ├── button_demo.nelua           # 按钮演示（最简入门）
│   ├── layout_demo.nelua           # 编译期 Flexbox 布局演示（7 组件）
│   ├── shadow_demo.nelua           # 多 Pass 阴影
│   └── text_demo.nelua             # 文本渲染展示
├── tests/
│   ├── smoke_phase3_12.lua         # Phase 3.12: 响应式重排专项（60 项断言）
│   ├── smoke_phase4_1.lua          # ★ Phase 4.1: Slug 文本渲染引擎专项（47 项断言）
│   ├── smoke_phase4_0.lua          # ★ Phase 4.0: 公理校验器专项（28 项断言）
│   ├── smoke_phase3_11.lua         # Phase 3.11: 30 行愿景专项
│   ├── smoke_phase3_10_5.lua       # Phase 3.10.5: 独立文本 + 多 Pass 专项
│   └── ... (共 28 个测试，含编译回归)
├── docs/
│   ├── ARCHITECTURE_GRAND_PLAN.md  # ★ Nebula 架构总纲领 v2（三大公理、路线图）
│   ├── PHASE3_12_*.md              # ★ Phase 3.12: 方案评估、公理审查与实现指南
│   └── PLAN_PHASE*.md              # 各 Phase 历史计划文档
├── assets/
│   └── generated/                  # 自动生成的字体 SDF 图集与度量文件
├── build.sh                        # 一键构建脚本
└── tools/
    ├── run_all_tests.sh            # 全量回归测试运行器
    ├── font_preprocessor.nelua         # 字体预处理工具（TTF → SDF Atlas）
    └── font_preprocessor_slug.nelua    # ★ Phase 4.1: Slug 字体预处理工具（TTF → 贝塞尔曲线 + Band 索引）
```

---

## 构建与运行

### 环境要求

- Linux x86_64 / WSL2
- GCC 11+（`sudo apt-get install -y gcc build-essential`）
- Nelua 0.2.0-dev（含 `nelua-lua` Lua 5.4 解释器，源码编译安装）
- wgpu-native v29.0.0.0（解压至 `vendor/wgpu-native/`）
- GLFW 3（`sudo apt-get install -y libglfw3-dev`）

### 编译 Demo

```bash
chmod +x build.sh

# Linux X11（默认）
./build.sh form_demo
./build.sh form_demo --target=linux --display=x11

# Linux Wayland
./build.sh form_demo --target=linux --display=wayland

# Windows（需在 Windows 环境或交叉编译工具链下执行）
./build.sh form_demo --target=windows

# Web / Wasm（需安装 Emscripten）
./build.sh form_demo --target=wasm

# 其他可用 Demo
./build.sh dynamic_list_demo    # Slot Producer 动态列表（10,000 项）
./build.sh login_demo           # 登录框演示（密码掩码）
./build.sh button_demo          # 按钮演示（最简入门）
./build.sh layout_demo          # 编译期 Flexbox 布局演示（7 组件）
./build.sh shadow_demo          # 多 Pass 阴影
./build.sh text_demo            # 文本渲染展示
```

### 运行

```bash
# 有显示器
LD_LIBRARY_PATH=vendor/wgpu-native/lib ~/.cache/nelua/form_demo

# 无显示器（CI / 服务器）
Xvfb :99 -screen 0 1024x768x24 &
DISPLAY=:99 LD_LIBRARY_PATH=vendor/wgpu-native/lib ~/.cache/nelua/form_demo
```

### 运行测试

```bash
# Phase 4.2.1 PAL 骨架专项冒烟测试（无需 GPU，43 项断言）
nelua-lua tests/smoke_phase4_2_1.lua

# Phase 4.1 Slug 文本渲染专项（47 项）
nelua-lua tests/smoke_phase4_1.lua

# Phase 3.12 响应式重排专项（60 项）
nelua-lua tests/smoke_phase3_12.lua

# 全量回归测试（含编译回归）
bash tools/run_all_tests.sh
```

---

## 参考文档

| 文档 | 说明 |
| :--- | :--- |
| [`docs/ARCHITECTURE_GRAND_PLAN.md`](docs/ARCHITECTURE_GRAND_PLAN.md) | 架构总纲领 v3.1：三大公理、路线图、技术债登记表 |
| [`docs/IMPL_PHASE4_2_1_PAL.md`](docs/IMPL_PHASE4_2_1_PAL.md) | Phase 4.2.1 PAL 骨架实施方案（含研究结论与架构决策） |
| [`docs/REPORT_DEAD_CODE_AUDIT.md`](docs/REPORT_DEAD_CODE_AUDIT.md) | 死代码审查与清理报告（Phase 3.7） |
