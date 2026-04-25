# Nebula GUI Compiler

**Nebula** 是一个用编译期元编程把"声明意图"翻译成"等价手写代码"的 GUI 编译器。它的核心主张只有一句话：

> 任何能在编译期确定的事实，必须在编译期确定。

Nebula 不是运行时框架，不是响应式引擎，也不是场景图。它是一个 **Nelua 宏驱动的代码生成器**——开发者声明组件的形状、交互原语和布局意图，Nebula 在编译期将这些声明翻译成零开销、零样板、零运行时分发的 WebGPU 渲染代码。

---

## 当前状态：Phase 3.9

**Phase 3.6.2 至 Phase 3.9 已全部合入主线**，全量回归测试 **25/25 通过，零失败**。

Phase 3.9 完成了两项关键原语：

- **原语 3（文本一等公民）**：引入 `nebula_app_register_text`，将文本组件的输入处理、状态同步和渲染管线全部纳入编译期自动编排，消除了 `form_demo` 中原本 40 行的手动文本渲染 Pass。
- **原语 4（Slot Producer 重构）**：以 `producer` 纯函数模式重构动态插槽，动态列表的实例数据完全由 App 内部 FrameArena 托管，消除了对外部全局变量的依赖，`dynamic_list_demo` 的主循环从 80 行 WGPU 样板收缩到 3 行。

---

## 愿景：Nebula 该有的样子

当总纲领描述的全部八大原语落地之后，一个完整的表单应用将是这样的：

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
    nebula_app_register_component("card",        "CardVisual")
    nebula_app_register_component("email_input", "InputVisual",  { component_id = 1 })
    nebula_app_register_text     ("email_label", { bound_to = "email_input", placeholder = "email" })
    nebula_app_register_component("login_btn",   "ButtonVisual")
  nebula_app_end()

  nebula_app_attach_layout("FormApp", function()
    return nebula_layout_node({
      direction = "column", padding = 32, gap = 16,
      children = {
        { name = "card",        width = 480, height = 320 },
        { name = "email_input", height = 40 },
        { name = "login_btn",   height = 44 },
      }
    })
  end)
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

**30 行，零样板，零 WGPU 调用，零 Pipeline 初始化代码，零 Arena 管理代码。** 这是 Nebula 的终态。

---

## 三大哲学公理

Nebula 的全部设计决策由三条公理驱动，外加一条冲突裁决元规则：

**公理 A（编译期最大化）**：任何能在编译期确定的事实，必须在编译期确定。Nelua 宏（`##`）是唯一合法的编译期推导通道；运行时不应出现可由编译期消除的虚函数分发、字符串查表或特性开关。

**公理 B（生命周期严格分层）**：Nebula 中只存在两种内存生命周期——L1 持久层（跨帧存活，栈分配）和 L2 帧级层（单帧瞬时，Frame Arena）。任何数据必须显式归属其一，不得混用。

**公理 C（形即渲染）**：每一个 `Visual` 类型必须拥有一条专属的、按字段精确组合而成的渲染管线。运行时不存在"通用渲染器"，也不存在通过运行时分支选择字段集合的着色器。

**元规则 Π（冲突裁决）**：当公理出现冲突时，按 **B > C > A** 的优先级裁决——宁可放弃部分编译期推导，也要保住生命周期的严格分层。

---

## 架构路线图

| Phase | 名称 | 对应原语 | 状态 |
| :--- | :--- | :--- | :--- |
| 3.6.2 | 鼠标命中与栈上排版 | 原语 2 | **已完成** |
| 3.6.3 | 多行文本与 Selection | 原语 2、8 | **已完成** |
| 3.7 | 管线生成器收敛与死代码清理 | 原语 1 | **已完成** |
| 3.8 | 渲染循环封装与 FrameArena 内嵌 | 原语 5、8 | **已完成** |
| **3.9** | **文本一等公民 + Slot Producer 重构** | **原语 3、4** | **已完成（当前）** |
| 3.10 | 原语注册中心与 primitives.nelua 瘦身 | 原语 6 | 规划中 |
| 3.11 | Layout-App 桥接 | 原语 7 | 规划中 |
| 4.0 | 哲学公理校验器（编译期 lint） | 公理 A/B/C 自动校验 | 规划中 |
| 4.1 | 中文 / Unicode 全量支持 | 扩展原语 3 | 规划中 |
| 5.0 | WASM 后端与端到端冒烟 | 跨原语整合 | 规划中 |

**下一步（Phase 3.10）**：将 `interaction_factory.lua` 中五个交互原语（hoverable、clickable、focusable、editable、toggleable）收敛到统一的 `NEBULA_PRIMITIVES` 注册表，消除 toggleable 的字符串后处理 hack，为 Phase 3.11 的 Layout-App 桥接铺路。

---

## 各阶段演进

| 维度 | Phase 0–2.5 | Phase 3.1–3.5 | Phase 3.6.x | Phase 3.7 | Phase 3.8 | **Phase 3.9** |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| 核心推导 | 形状 → 状态机 / 管线 | 布局 + 文本 + 动态列表 + 显式编排 | Gap Buffer + 选区支持 | 管线收敛：3 着色器 + 3 路径 | 渲染循环封装 + FrameArena 内嵌 | **文本一等公民（原语 3）+ Slot Producer（原语 4）** |
| 渲染技术 | SDF 形状 + 多 Pass 阴影 | SDF 文本 + Instanced 渲染 | L1/L2 分层 + 栈上即时排版 | standard_instanced 默认路径 | 20 行 WGPU 样板 → 1 行 | **文本管线自动注入；Producer 驱动动态插槽，Arena mark/rewind 局部回收** |
| 质量保障 | 手动验证 | 150+ 项断言 | 260+ 项断言 | smoke_phase3_7 专项 | smoke_phase3_8 专项 | **25/25 套件，259 项断言，零失败** |

---

## 项目结构

```text
nebula/
├── src/
│   ├── nebula_core.nelua           # 编译期推导引擎（含 nebula_derive_app 宏）
│   ├── nebula_arena.nelua          # ★ Phase 3.9: Frame Arena（含 mark/rewind 局部回收）
│   ├── app.nelua                   # ★ Phase 3.8: 统一输入收集 + nebula_frame_render 封装
│   ├── gap_buffer.nelua            # Phase 3.6.1: 编译期定容 Gap Buffer
│   ├── text_runtime.nelua          # Phase 3.2.4: 文本运行时，字形顶点装配与上传
│   ├── renderer.nelua              # WebGPU 渲染器封装
│   └── derive/
│       ├── app_factory.lua         # ★ Phase 3.9: 编排工厂 v0.3（文本一等公民 + Slot Producer）
│       ├── pipeline_factory.lua    # Phase 3.7: 收敛为 3 条路径（v0.7_phase3.7）
│       ├── shader_compose.lua      # Phase 3.7: 收敛为 3 个公开函数（v0.6_phase3.7）
│       ├── interaction_factory.lua # Phase 3.6.3: 交互原语工厂（含选区支持）
│       ├── layout_engine.lua       # Phase 3.1: 编译期静态 Flexbox 布局引擎
│       └── gap_buffer_factory.lua  # Phase 3.6.1: Gap Buffer 代码生成器
├── examples/
│   ├── form_demo.nelua             # ★ Phase 3.9: 文本一等公民（主循环 2 行）
│   ├── dynamic_list_demo.nelua     # ★ Phase 3.9: Slot Producer（10,000 项实例渲染，主循环 3 行）
│   ├── login_demo.nelua            # ★ Phase 3.9: 登录框（nebula_app_register_text 密码掩码）
│   ├── button_demo.nelua           # ★ Phase 3.9: 按钮演示（最简入门）
│   ├── layout_demo.nelua           # ★ Phase 3.9: 编译期 Flexbox 布局演示（7 组件）
│   ├── shadow_demo.nelua           # Phase 2.5: 多 Pass 阴影（暂缓升级，等待 Phase 4.x 多 Pass 框架）
│   └── text_demo.nelua             # Phase 3.2.5: 文本渲染展示（暂缓升级，等待 Phase 3.10 独立标签支持）
├── tests/
│   ├── smoke_phase3_9.lua          # ★ Phase 3.9: 文本一等公民 & Slot Producer 专项（64 项）
│   ├── smoke_phase3_8.lua          # Phase 3.8: nebula_frame_render & FrameArena 内嵌验证（30 项）
│   ├── smoke_phase3_7.lua          # Phase 3.7: 管线收敛 & 死代码清理专项
│   └── ... (共 18 个测试套件，259 项断言)
├── docs/
│   ├── ARCHITECTURE_GRAND_PLAN.md  # ★ Nebula 架构总纲领（三大公理、八大原语、完整路线图）
│   ├── AUDIT_PHASE3_9_PHILOSOPHY.md # ★ Phase 3.9 设计哲学合规性审计报告
│   ├── PLAN_PHASE3_9.md            # Phase 3.9 详细任务计划
│   ├── REPORT_PHASE3_9_COMPLIANCE.md # Phase 3.9 架构合规性审查报告
│   └── ...
├── assets/
│   └── generated/                  # 自动生成的字体 SDF 图集与度量文件
├── build.sh                        # 一键构建脚本
└── tools/
    ├── run_all_tests.sh            # ★ 全量回归测试运行器（25 项，259 项断言）
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

# Phase 3.9 核心 Demo（最新 API）
./build.sh form_demo            # 文本一等公民表单演示
./build.sh dynamic_list_demo    # Slot Producer 动态列表（10,000 项）
./build.sh login_demo           # 登录框演示（密码掩码）
./build.sh button_demo          # 按钮演示（最简入门）
./build.sh layout_demo          # 编译期 Flexbox 布局演示（7 组件）

# 暂缓升级的 Demo
./build.sh shadow_demo          # Phase 2.5 多 Pass 阴影
./build.sh text_demo            # Phase 3.2.5 文本渲染展示
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
nelua-lua tests/smoke_phase3_9.lua   # Phase 3.9 专项（64 项）
nelua-lua tests/smoke_phase3_8.lua   # Phase 3.8 专项（30 项）

# 全量回归测试（含编译回归）
bash tools/run_all_tests.sh          # 25/25 通过，零失败
```

---

## 参考文档

| 文档 | 说明 |
| :--- | :--- |
| [`docs/ARCHITECTURE_GRAND_PLAN.md`](docs/ARCHITECTURE_GRAND_PLAN.md) | 架构总纲领：三大公理、八大原语、完整路线图 |
| [`docs/AUDIT_PHASE3_9_PHILOSOPHY.md`](docs/AUDIT_PHASE3_9_PHILOSOPHY.md) | Phase 3.9 设计哲学合规性审计报告 |
| [`docs/PLAN_PHASE3_9.md`](docs/PLAN_PHASE3_9.md) | Phase 3.9 详细任务计划 |
| [`docs/REPORT_PHASE3_9_COMPLIANCE.md`](docs/REPORT_PHASE3_9_COMPLIANCE.md) | Phase 3.9 架构合规性审查报告 |
| [`docs/REPORT_DEAD_CODE_AUDIT.md`](docs/REPORT_DEAD_CODE_AUDIT.md) | 死代码审查与清理报告（Phase 3.7） |
