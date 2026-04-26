# Nebula GUI Compiler

**Nebula** 是一个用编译期元编程把"声明意图"翻译成"等价手写代码"的 GUI 编译器。它的核心主张是**阶段封闭性**：

> 每个操作必须归属于其输入最早全部可知的阶段。后一阶段不得执行前一阶段的操作，前一阶段的输出是后一阶段的不可变输入。

Nebula 不是运行时框架，不是响应式引擎，也不是场景图。它是一个 **Nelua 宏驱动的代码生成器**——开发者声明组件的形状、交互原语和布局意图，Nebula 在编译期将这些声明翻译成零开销、零样板、零运行时分发的 WebGPU 渲染代码。

---

## 当前状态：Phase 3.10.5

**Phase 3.6.2 至 Phase 3.10.5 已全部合入主线**，全量回归测试 **27/27 通过，零失败**。

Phase 3.10 完成了原语注册中心重构，Phase 3.10.5 扩展了文本和渲染能力：

- **原语注册中心（Phase 3.10）**：构建了 `NEBULA_PRIMITIVES` 统一注册表，五个交互原语（hoverable、clickable、focusable、editable、toggleable）全部迁移到元数据驱动模式，彻底删除了 Monkey-patch 和所有硬编码分支。
- **独立文本标签 + 多 Pass 渲染（Phase 3.10.5）**：`nebula_app_register_text` 支持 `static`/`dynamic` 模式；引入 `nebula_app_register_shadow` 和多 Pass 渲染架构。

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
| **3.10.5** | **独立文本标签 + 多 Pass 渲染** | **—** | **已完成（当前）** |
| 3.11 | Layout-App 统一注册 | T8 | 规划中 |
| 3.12 | 响应式重排 (Responsive Reflow) | 视口自适应 | 规划中 |
| 4.0 | 编译期公理校验器 | 防止回退 | 规划中 |
| 4.1 | Slug 文本渲染引擎 | Unicode 全量 | 规划中 |
| 4.2 | CJK 字体预处理 | CJK 支持 | 规划中 |
| 4.3 | 拓扑流渲染 (Indirect Drawing) | 降低 CPU 提交开销 | 规划中 |
| 5.0 | WASM 后端 | 跨平台 | 规划中 |

**下一步（Phase 3.11）**：将布局约束嵌入 `nebula_app_register_component` 的注册 API，消除独立的 `attach_layout` 调用；实现 `nebula_init` 和 `nebula_should_close` 便利性封装，兑现 30 行愿景。

**后续（Phase 3.12）**：在不违反公理 A 的前提下，通过编译期约束降维和运行时线性插值，实现窗口 Resize 时的 UI 响应式重排。

---

## 各阶段演进

| 维度 | Phase 0-2.5 | Phase 3.1-3.5 | Phase 3.6.x | Phase 3.7 | Phase 3.8 | Phase 3.9 | **Phase 3.10/3.10.5** |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| 核心推导 | 形状 → 状态机/管线 | 布局 + 文本 + 动态列表 | Gap Buffer + 选区 | 管线收敛 | 渲染循环封装 | 文本一等公民 + Slot Producer | **原语注册中心 + 独立文本 + 多 Pass** |
| 渲染技术 | SDF 形状 + 多 Pass 阴影 | SDF 文本 + Instanced | L1/L2 分层 + 栈上排版 | 3 着色器 + 3 路径 | 1 行 WGPU 样板 | 文本管线自动注入 | **NEBULA_PRIMITIVES 元数据驱动；register_shadow** |
| 质量保障 | 手动验证 | 150+ 项断言 | 260+ 项断言 | 专项测试 | 专项测试 | 25/25 通过 | **27/27 通过，含注册表专项 22 项** |

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
│       ├── interaction_factory.lua # ★ Phase 3.10: NEBULA_PRIMITIVES 统一注册表（v0.7）
│       ├── layout_engine.lua       # 编译期静态 Flexbox 布局引擎
│       └── gap_buffer_factory.lua  # Gap Buffer 代码生成器
├── examples/
│   ├── form_demo.nelua             # 文本一等公民表单演示（主循环 2 行）
│   ├── dynamic_list_demo.nelua     # Slot Producer 动态列表（10,000 项，主循环 3 行）
│   ├── login_demo.nelua            # 登录框演示（密码掩码）
│   ├── button_demo.nelua           # 按钮演示（最简入门）
│   ├── layout_demo.nelua           # 编译期 Flexbox 布局演示（7 组件）
│   ├── shadow_demo.nelua           # 多 Pass 阴影
│   └── text_demo.nelua             # 文本渲染展示
├── tests/
│   ├── smoke_phase3_10.lua         # ★ Phase 3.10: 注册表专项（22 项断言）
│   ├── smoke_phase3_10_5.lua       # Phase 3.10.5: 独立文本 + 多 Pass 专项
│   ├── smoke_phase3_9.lua          # Phase 3.9: 文本一等公民 & Slot Producer 专项
│   └── ... (共 27 个测试，含编译回归)
├── docs/
│   ├── ARCHITECTURE_GRAND_PLAN.md  # ★ Nebula 架构总纲领 v2（三大公理、路线图）
│   └── PLAN_PHASE*.md              # 各 Phase 历史计划文档
├── assets/
│   └── generated/                  # 自动生成的字体 SDF 图集与度量文件
├── build.sh                        # 一键构建脚本
└── tools/
    ├── run_all_tests.sh            # 全量回归测试运行器
    └── font_preprocessor.nelua     # 字体预处理工具（TTF → SDF Atlas）
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

# 核心 Demo
./build.sh form_demo            # 文本一等公民表单演示
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
# 单项冒烟测试（无需 GPU）
nelua-lua tests/smoke_phase3_10.lua   # Phase 3.10 注册表专项（22 项）
nelua-lua tests/smoke_phase3_9.lua    # Phase 3.9 专项（64 项）

# 全量回归测试（含编译回归）
bash tools/run_all_tests.sh           # 27/27 通过，零失败
```

---

## 参考文档

| 文档 | 说明 |
| :--- | :--- |
| [`docs/ARCHITECTURE_GRAND_PLAN.md`](docs/ARCHITECTURE_GRAND_PLAN.md) | 架构总纲领 v2：三大公理、路线图 |
| [`docs/REPORT_DEAD_CODE_AUDIT.md`](docs/REPORT_DEAD_CODE_AUDIT.md) | 死代码审查与清理报告（Phase 3.7） |
