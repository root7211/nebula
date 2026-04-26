# Nebula 架构总纲领 v2

**修订日期**：2026-04-26
**修订动因**：Phase 3.10 完成后的哲学审计发现原始公理体系存在形式化缺陷。本版本对三大公理进行了精确化重构，引入三阶段模型和三层生命周期模型，消除了所有已知的哲学不可达点。
**适用范围**：所有未来 Phase 规划、所有 PR 评审、所有架构决策

---

## 1. 公理体系

Nebula 的全部设计决策由三条公理驱动。三条公理分别约束**时间**（操作归属哪个阶段）、**空间**（数据归属哪个生命周期层）和**映射**（Visual 如何确定性地对应管线），三者作用于正交维度。

### 1.1 公理 A：阶段封闭性原则

Nebula 的生命周期被划分为三个严格有序的阶段，每个阶段有且仅有一类合法操作。后一阶段不得执行前一阶段的操作，前一阶段的输出是后一阶段的不可变输入。

| 阶段 | 名称 | 合法操作 | 输出 | 执行者 |
| :--- | :--- | :--- | :--- | :--- |
| **S0** | 预处理阶段 | 字体解析、atlas/curve-data 生成、资源序列化 | 静态资产文件（`.nelua`、`.pgm`、`.bin`） | 离线工具（`font_preprocessor`） |
| **S1** | 编译阶段 | 类型派生、管线生成、布局解算、状态机构建、着色器组合 | Nelua 源码 → C 源码 → 机器码 | Nelua 宏（`##`） |
| **S2** | 运行阶段 | GPU 资源创建、输入处理、状态转移、渲染提交 | 帧画面 | 编译后的二进制 |

**判定准则**：给定一个操作 O，其合法阶段由输入来源决定——

1. 如果 O 的所有输入在 S0 时刻已知（如 TTF 文件路径、目标字符集），则 O 属于 S0。
2. 如果 O 的所有输入在 S1 时刻已知（如 Visual 的字段列表、原语声明），则 O 属于 S1。
3. 仅当 O 的输入依赖用户交互或外部事件（如鼠标位置、键盘输入、窗口 resize）时，O 属于 S2。

这是一个可机械判定的分类规则：只需检查操作的输入来源，即可确定其合法阶段。

### 1.2 公理 B：生命周期三层原则

Nebula 的运行时数据存在且仅存在三种生命周期，每个运行时数据必须显式归属其一。层间依赖严格单向。

| 层 | 名称 | 生命周期 | 创建时机 | 销毁时机 | 合法存储 | 典型数据 |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **L0** | 永久层 | 应用全生命周期 | `init()` | `deinit()` | 静态全局 / App Record | GPU 管线、纹理、Bind Group Layout、Sampler |
| **L1** | 持久层 | 跨帧存活 | `init()` 或状态转移 | 显式重置 | App Record 内的状态字段 | 焦点 ID、Gap Buffer 内容、Toggle 状态、状态机当前态 |
| **L2** | 帧级层 | 单帧瞬时 | 每帧 `update`/`draw` | `arena.reset()` | Frame Arena | 排版结果、Slot Producer 输出、临时 cstring |

**不变量**（形式化表述）：

```
∀ data ∈ L1: valid(data) ⟹ valid(data) after arena.reset()
∀ data ∈ L0: valid(data) ⟹ valid(data) after any L1 state transition
```

L2 的 reset 不得影响 L1 的有效性；L1 的任何状态变化不得影响 L0 的有效性。

### 1.3 公理 C：形即渲染原则

每一个 Visual 类型 V 在编译期（S1）必须确定性地映射到一个**管线签名**：

> Σ(V) = (VertexLayout, UniformsLayout, ShaderModule, BlendState)

两个 Visual 类型 V₁ ≠ V₂ 当且仅当 Σ(V₁) ≠ Σ(V₂) 时允许共享管线对象。对于多 Pass 渲染，签名扩展为有序序列 Σ(V) = [Σ₁, Σ₂, ..., Σₙ]，其中每个 Σᵢ 对应一个 Pass。

### 1.4 元规则 Π：正交性原则

公理 A 约束操作的**时间归属**（S0/S1/S2），公理 B 约束数据的**生命周期归属**（L0/L1/L2），公理 C 约束 Visual 的**管线映射**。三者作用于正交维度，不应产生冲突。如果出现表面冲突，应修订公理的形式化表述，而非裁决优先级。

---

## 2. 架构张力与原语映射

总纲领识别了八大架构张力，每个张力对应一个需要实现的"原语"。原语是消除张力的最小架构单元。

| 张力 | 描述 | 对应原语 | 解决方案 |
| :--- | :--- | :--- | :--- |
| T1 | 管线路径爆炸 | 原语 1：管线收敛 | `pipeline_factory.lua` 收敛为 3 条路径（standard_instanced、text_vertex、shadow_multipass） |
| T2 | 命中测试与排版分离 | 原语 2：栈上排版 + 命中测试 | `text_runtime.nelua` 中 L2 排版 + 编译期命中区域注入 |
| T3 | 文本渲染手动管理 | 原语 3：文本一等公民 | `nebula_app_register_text` 自动编排文本管线 |
| T4 | 动态列表外部依赖 | 原语 4：Slot Producer | `producer` 纯函数 + Arena mark/rewind |
| T5 | 渲染循环样板代码 | 原语 5：渲染循环封装 | `nebula_frame_render` 一行调用 |
| T6 | FrameArena 外置 | 原语 8：Arena 内嵌 | Arena 作为 App Record 的 L0 成员 |
| T7 | 交互原语硬编码 | 原语 6：原语注册中心 | `NEBULA_PRIMITIVES` 元数据驱动注册表 |
| T8 | 布局与 App 分离 | 原语 7：Layout-App 桥接 | 布局约束嵌入注册 API，编译期解算坐标 |

---

## 3. 已完成的 Phase 历史

以下 Phase 已全部合入主线，全量回归测试通过。

| Phase | 名称 | 消除张力 | 关键成果 | 完成日期 |
| :--- | :--- | :--- | :--- | :--- |
| 3.6.2 | 鼠标命中与栈上排版 | T2 | L2 栈上排版替代 L1 缓存 | 2026-04-24 |
| 3.6.3 | 多行文本与 Selection | T2 | Gap Buffer 选区支持 | 2026-04-24 |
| 3.7 | 管线生成器收敛与死代码清理 | T1 | 5 条路径 → 3 条路径，删除 600+ 行死代码 | 2026-04-24 |
| 3.8 | 渲染循环封装与 FrameArena 内嵌 | T5, T6 | `nebula_frame_render` 一行调用；Arena 内嵌 App Record | 2026-04-24 |
| 3.9 | 文本一等公民 + Slot Producer 重构 | T3, T4 | `nebula_app_register_text`；Producer 纯函数模式 | 2026-04-25 |
| 3.10 | 原语注册中心 | T7 | `NEBULA_PRIMITIVES` 统一注册表；Monkey-patch 彻底删除 | 2026-04-26 |
| 3.10.5 | 独立文本标签 + 多 Pass 渲染架构 | — | `register_text` static/dynamic 模式；`register_shadow`；多 Pass 渲染 | 2026-04-26 |

**当前状态**：Phase 3.10.5 已完成，全量回归测试 **27/27 通过**（含 Phase 3.10 注册表专项 22 项断言）。

---

## 4. 未来路线图

### 4.1 Phase 3.11：Layout-App 统一注册

**目标**：消除张力 T8，兑现 30 行愿景。

将布局约束嵌入 `nebula_app_register_component` 的注册 API 中，消除独立的 `nebula_app_attach_layout` 调用（消除 DRY 违反）。`app_factory.lua` 在 S1 阶段自动从所有注册组件的 `layout` 字段构建布局树，调用 `layout_engine.lua` 解算坐标，将结果嵌入 `<App>:init()` 的编译期常量中。同时实现 `nebula_init` 和 `nebula_should_close` 便利性封装。

**目标 API**：

```lua
nebula_app_register_component("email_input", "InputVisual", {
  component_id = 1,
  layout = { height = 40, flex_grow = 1, margin = {top = 8} }
})

nebula_app_set_root_layout("FormApp", {
  direction = "column", padding = 32, gap = 16
})
```

### 4.2 Phase 4.0：编译期公理校验器

**目标**：将公理从"文档约束"升级为"编译期强制"。

在 `nebula_derive` 和 `app_factory` 内嵌公理 B/C 的编译期断言。利用 Nelua 宏的元编程能力，在 S1 阶段直接校验：公理 B 校验 L2 数据不得出现在 Visual Record 中；公理 C 校验管线签名唯一性。这比外部 grep 工具强大得多，因为它在 S1 阶段拥有完整的类型信息和注册元数据，可以做真正的语义校验。

### 4.3 Phase 4.1：Slug 文本渲染引擎

**目标**：不违反公理 A 的 Unicode 全量支持。

**技术选型**：采用 2026 年 3 月进入公共领域的 **Slug 算法**（Eric Lengyel）。Slug 直接在 GPU 上从贝塞尔曲线控制点计算像素覆盖率，不需要光栅化的 SDF atlas。

**与三阶段模型的对齐**：

| 阶段 | Slug 操作 | 输入来源 | 公理 A 合法性 |
| :--- | :--- | :--- | :--- |
| S0 | 从 TTF 提取贝塞尔曲线控制点，生成 band-data 和 curve-data | TTF 文件（S0 已知） | 合法 |
| S1 | 将 curve/band 数据嵌入编译期常量，生成 WGSL Slug 着色器 | S0 输出（S1 已知） | 合法 |
| S2 | GPU 从 curve/band 纹理计算像素覆盖率 | 要渲染的文字（依赖用户交互） | 合法 |

Slug 将"字形渲染"分解为"数据提取"（S0）和"像素计算"（S2），运行时没有任何光栅化或 atlas 管理。20,000+ CJK 字形的 curve-data 远小于等效的 SDF atlas（几 MB vs 数百 MB），且渲染质量在任意缩放下都是数学精确的。

**实施路径**：详见 `docs/PLAN_PHASE4_1.md`。

### 4.4 Phase 4.2：CJK 字体预处理与 HarfBuzz 集成

**目标**：S0 阶段完成所有字形数据提取和 shaping 规则预处理。

扩展 `font_preprocessor` 支持 CJK 字体子集化（按应用声明的字符集提取），集成 HarfBuzz 进行编译期 shaping（字距调整、连字替换）。shaping 规则表在 S0 阶段生成，S2 阶段仅做查表。

### 4.5 Phase 4.3：拓扑流渲染 (Indirect Drawing)

**目标**：引入 GPU 驱动的间接绘制，大幅降低 CPU 提交开销。

**技术选型**：将 CPU 端的显式 Draw Call 替换为 GPU 端维护的 Indirect Buffer。利用 Compute Shader 执行视锥体剔除和状态检查，实现真正的动态拓扑变化。

**实施路径**：详见 `docs/PLAN_PHASE4_3.md`。

### 4.6 Phase 5.0：WASM 后端

**目标**：零运行时分支的跨平台。

平台差异通过 S1 阶段的编译期条件处理。`NEBULA_TARGET` 在 S1 阶段确定（编译时传入），S2 阶段的二进制中只有一条路径——native 生成 GLFW while 循环，wasm 生成 Emscripten 回调。不存在运行时的平台分支。

---

## 5. 不变量与红线

以下不变量在任何 Phase 中都不得被打破：

**I1（零运行时分发）**：S2 阶段不存在虚函数表、字符串查表或 `if typeof(x)` 式的类型分支。所有分发在 S1 阶段由宏展开为直接调用。

**I2（Arena 唯一性）**：每个 App 实例有且仅有一个 Frame Arena（L2 层），所有帧级临时数据必须从该 Arena 分配。不得在 S2 阶段调用系统 `malloc` 分配帧级数据。

**I3（管线确定性）**：每个 Visual 的管线签名 Σ(V) 在 S1 阶段完全确定。S2 阶段不得动态创建或切换管线。

**I4（注册表完备性）**：所有交互原语必须通过 `NEBULA_PRIMITIVES` 注册表声明。`nebula_core.nelua` 中不得出现针对特定原语名称的硬编码分支。

**I5（层间隔离）**：L0 数据的有效性不依赖 L1 的状态；L1 数据的有效性不依赖 L2 的内容。`arena.reset()` 不得使任何 L1 数据失效。

**I6（永不引入 GC）**：Lua 仅作为 S1 阶段的编译期元代码语言存在，S2 阶段不应有任何 Lua 运行时或垃圾回收器。

**I7（永不引入运行时反射）**：所有类型信息必须在 S1 阶段被消解为静态字段访问。S2 阶段不存在类型元数据查询。

---

## 6. 与 v1 总纲领的差异摘要

本版本（v2）相对于原始总纲领（v1）的核心变更如下：

| 维度 | v1 | v2 | 变更理由 |
| :--- | :--- | :--- | :--- |
| 公理 A | "编译期最大化"（模糊谓词） | 阶段封闭性（S0/S1/S2，可机械判定） | 消除"能不能在编译期确定"的争论 |
| 公理 B | 二层模型（L1/L2） | 三层模型（L0/L1/L2） | 覆盖 GPU 资源的应用级生命周期 |
| 公理 C | "专属管线"（自然语言） | 管线签名四元组 Σ(V)（数学定义） | 精确定义"专属"的等价判定 |
| 元规则 Π | 优先级裁决（B > C > A） | 正交性要求（不应冲突） | 更高的数学标准 |
| CJK 方案 | 未明确 | Slug 算法（S0 数据提取 + S2 GPU 计算） | 不违反公理 A 的 Unicode 全量支持 |
| Phase 4.0 | grep 校验器 | 编译期内嵌断言 | 利用 S1 阶段的完整类型信息做语义校验 |
| 行数目标 | 具体行数承诺（如 450 行） | 结构性约束（路径数、注册表完备性） | 行数不是公理约束的对象 |

---

## 7. 愿景：30 行终态

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

**30 行，零样板，零 WGPU 调用，零 Pipeline 初始化代码，零 Arena 管理代码。** 布局约束内嵌于注册 API，坐标在 S1 阶段解算并嵌入编译期常量。这是公理 A（阶段封闭性）、公理 B（三层生命周期）和公理 C（形即渲染）协同时应有的形态。

---

## 8. 参考资料

| 资料 | 说明 |
| :--- | :--- |
| [Slug Algorithm (GitHub)](https://github.com/EricLengyel/Slug) | Eric Lengyel 的 Slug 算法参考着色器实现，2026 年 3 月进入公共领域 |
| [Sluggish (GitHub)](https://github.com/mightycow/Sluggish) | Slug 的 band-data / curve-data 纹理生成工具 |
| [HarfBuzz (GitHub)](https://github.com/harfbuzz/harfbuzz) | 文本 shaping 引擎，用于字距调整和连字替换 |
| [Slug JCGT Paper](https://jcgt.org/published/0006/02/02/) | Slug 算法的原始学术论文（2017） |
