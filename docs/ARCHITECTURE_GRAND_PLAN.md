# Nebula 架构总纲领 v3.6

**修订日期**：2026-05-17（v3.6 修订）  
**修订历史**：  
- **v3.6 (2026-05-17)**：Phase 5.0 完成同步。全知图编译期端到端路径五个梯队（S1a→S1b→S2/S2.5→S3→S4→S5）全部完成。Phase 4.5-4.9 编号与实际实施对齐（语法糖→Builtin Producer→编辑器原型→嵌套布局→Terminal/WASM）。原 5.0"生态与 CI/CD"重编号为 5.1。
- **v3.5 (2026-05-01)**：全面同步。Phase 4.2.2 标记完成（D-4.1-A/B/C 全通过）。Phase 4.2.3 描述更新为 v3 分级查表方案（废弃 HarfBuzz/DFA）。记录代码质量改进：renderer 管线重构（-196 行）、pipeline_factory 互斥校验、axiom_validator 笛卡尔上限、interaction_factory 函数拆分。Era II 路线图与 `PLAN_ERA2_MASTER.md` 四梯队对齐。
- **v3.4 (2026-04-30)**：深度审计。Phase 4.3/4.4 标记为"S1-S3 核心已完成，存在结构性缺口"。
- **v3.3 (2026-04-30)**：同步 Era II 路线图至实际完成状态。Phase 4.3（可编程原语注册表 S1-S3）和 Phase 4.4（高级组件库 S1-S3）已全部合入主线。清理过时规划文档。  
- **v3.2 (2026-04-28)**：重置项目愿景。废弃 Era III "计算统一"的极客路线，转向构建工业级 GUI 框架。目标是对标 Qt、ImGui 和 SwiftUI，提供兼具高性能渲染、极高开发效率和声明式编程体验的"GUI 编译器"。

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

### 1.2 公理 B：生命周期三层原则

Nebula 的运行时数据存在且仅存在三种生命周期，每个运行时数据必须显式归属其一。层间依赖严格单向。

| 层 | 名称 | 生命周期 | 创建时机 | 销毁时机 | 合法存储 | 典型数据 |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **L0** | 永久层 | 应用全生命周期 | `init()` | `deinit()` | 静态全局 / App Record | GPU 管线、纹理、Bind Group Layout、Sampler |
| **L1** | 持久层 | 跨帧存活 | `init()` 或状态转移 | 显式重置 | App Record 内的状态字段 | 焦点 ID、Gap Buffer 内容、Toggle 状态、状态机当前态 |
| **L2** | 帧级层 | 单帧瞬时 | 每帧 `update`/`draw` | `arena.reset()` | Frame Arena | 排版结果、Slot Producer 输出、临时 cstring |

### 1.3 公理 C：形即渲染原则

每一个 Visual 类型 V 在编译期（S1）必须确定性地映射到一个**管线签名**：

> Σ(V) = (VertexLayout, UniformsLayout, ShaderModule, BlendState)

---

## 2. 核心定位：编译期消解的 GUI 编译器

Nebula 不是又一个 GUI 框架——它是一个**编译器**。传统框架在运行时解释 UI 描述（虚表分发、事件总线、反射系统），Nebula 把这一切前移到编译期：

- **编译期消解**：声明式 UI 描述在 S1 阶段由 Nelua 宏系统完整展开为确定性的原生代码。运行时不存在间接层，不存在 “框架税”。
- **公理驱动设计**：三大公理（阶段封闭性 / 生命周期三层 / 形即渲染）不是指导原则，而是**可执行约束**——`axiom_validator` 在编译期强制执行，违规即编译失败。
- **极限代码压缩**：19 行声明 → 886 行等价手写代码（46.6x），开发者写意图，编译器生成实现。

---

## 3. Nebula 发展路线图：两大纪元

我们将整个发展路线图划分为两大纪元（Era），聚焦于从“渲染引擎”向“全功能框架”的进化。

### Era I：形即渲染 (Shape-Is Rendering) — Phase 0 至 Phase 4.1（已完成）

**核心命题**：开发者声明 Visual 的**外观**规格，编译器推导渲染代码。

| Phase | 名称 | 状态 | 重要度 |
| :--- | :--- | :--- | :--- |
| Phase 1 | `nebula_derive()` 编译期生成器 | 已完成 | **91/100** |
| Phase 2 | 形即渲染（WGSL 管线生成） | 已完成 | **89/100** |
| Phase 3（3.1–3.4） | 多组件布局、文本、键盘输入 | 已完成 | 87/100 |
| Phase 3.5 | App 编排与全面 Instancing | 已完成 | **91/100** |
| Phase 3.6 | Gap Buffer 文本编辑 | 已完成 | 75/100 |
| Phase 3.7 | 管线生成器收敛 | 已完成 | 75/100 |
| Phase 3.8 | 渲染循环封装 + FrameArena | 已完成 | 76/100 |
| Phase 3.9 | 文本一等公民 + Slot Producer | 已完成 | 85/100 |
| Phase 3.10 | 原语注册中心 | 已完成 | 68/100 |
| Phase 3.11 | Layout-App 统一注册 | 已完成 | 77/100 |
| Phase 3.12 | 响应式重排 | 已完成 | 71/100 |
| Phase 4.0 | 编译期公理校验器 | 已完成 | 75/100 |
| Phase 4.1 | Slug 文本渲染引擎 | 已完成 | **89/100** |
| Phase 4.2.1 | 跨平台 PAL 骨架 | 已完成 | 83/100 |

### Era II：全功能框架 (Full-Featured Framework) — Phase 4.2.1 至今（进行中）

**核心命题**：将"形即"范式扩展到**行为**与**生态**。将 Nebula 打造为一个能够承载复杂应用（如文本编辑器、专业工具软件）的成熟框架。

| Phase | 名称 | 目标 | 状态 | 重要度 |
| :--- | :--- | :--- | :--- | :--- |
| **4.2.1** | 跨平台 PAL 骨架 | 源码级支持 Linux/Windows/Web，实现多端对齐。 | **已完成** | 83/100 |
| **4.2.2** | Slug 渲染内核生产级化 | 清算 MVP 债务，支持任意仿射变换与 Latin 全量字符。 | **已完成**（D-4.1-A/B/C 全部通过） | 79/100 |
| **4.3** | **可编程原语注册表** | 允许开发者安全注入自定义交互逻辑，框架从工具库升维为开放元系统。 | **已完成**（含 Task D process_body 公理校验，已接入编译流程） | **90/100** |
| **4.4** | **高级组件库** | 实现 scrollable、dropdown、multiline_editable 标准组件。 | **已完成**（三个原语已内置注册表，契约校验已接入编译流程） | **81/100** |
| **4.2.3** | **分级文本 Shaping + CJK** | 分级查表架构（Tier 1 cmap+metrics 已完成）；零运行时 HarfBuzz 依赖。Tier 2 连字→Phase 5+，UAX#14 换行→Phase 4.X。详见 `PLAN_PHASE4_2_3_CJK.md` v3。 | **✅ 已完成**（S0+S1+S2，47/47 回归全绿） | 82/100 |
| **4.X** | **高密度文本渲染通道** | 8192 字符 per-char 颜色等宽文本网格（Instanced + SDF Atlas + Storage Buffer）。着色器 + 管线 + Record + 派生入口 + 辅助函数 + dense_text_demo（120×50）+ 65 条冒烟测试。UAX#14 换行待后续 Phase。 | **✅ 已完成**（Step 1-5，49/49 回归全绿） | 85/100 |
| 4.5 | 注册原语语法糖 | 基于 4.4 真实用例提炼重复模式，简化 DX | **✅ 已完成**（nebula_app/nebula_visual sugar） | 85/100 |
| 4.6 | DenseText Builtin Producer | 内置行号/编辑区/搜索栏/状态栏 Producer 生成器 | **✅ 已完成**（4 个 builtin + term_grid） | 80/100 |
| 4.7 | 文本编辑器原型 | 验证 Era II 工业级能力（完整编辑器 v1-v3） | **✅ 已完成**（搜索替换/语法高亮/选区/Undo） | 88/100 |
| 4.8 | 嵌套布局 + Flexbox | 容器嵌套、flex_basis/flex_grow、row/column 方向 | **✅ 已完成** | 82/100 |
| 4.9 | Terminal + WASM 支持 | 终端模拟器 builtin、emscripten 主循环 | **✅ 已完成** | 78/100 |
| **5.0** | **全知图：编译期端到端路径** | 全知图构建 + AST 分析 + 代码生成 + 动态内容 + 编辑器迁移。消除运行时事件系统，编译期消解范式的理论极限。 | **✅ 已完成**（S1a-S5 五个梯队，6 套测试共 440+ 断言全绿） | **92/100** |
| 5.1 | 生态与 CI/CD | 完善文档、包管理支持与多端自动化测试。 | 规划中 | 待评分 |

> 重要度评分基于五个维度（架构奠基性、公理合规性、开发者体验、工业化就绪度、下游解锁度）加权综合评分，详见 [`docs/PHASE_IMPORTANCE_SCORECARD.md`](PHASE_IMPORTANCE_SCORECARD.md)。

---

## 4. 代码质量改进记录（2026-05-01）

| 提交 | 文件 | 改进 |
|:-----|:-----|:-----|
| `1046e33` | `src/renderer.nelua` | 提取 `_nebula_build_render_pipeline` + `_nebula_make_textured_bgl_entries` 共享辅助函数，消除三处管线初始化的 ~400 行重复代码，净减 196 行 |
| `dc300b8` | `src/derive/pipeline_factory.lua` | `nebula_gen_pipeline_source` 入口添加四条管线路径（`has_shadow`/`standard_instanced`/`textured`/`slug_text`）互斥校验，防止无效标志组合静默生成垃圾代码 |
| `a854546` | `src/derive/axiom_validator.lua` | `cartesian_booleans` 添加 `MAX_BOOLEAN_COMBOS = 256` 上限，超限退化为确定性随机采样（固定种子 42），防止编译期 2^n 指数爆炸 |
| `5f034b7` | `src/derive/interaction_factory.lua` | 269 行 `nebula_gen_text_buffer` 拆分为 `_gen_cursor_helpers` / `_gen_process_text_input` / `_gen_selection_helpers` / `_gen_text_accessors` 四个职责单一的子生成器 |

所有改进零行为变更，47/47 回归测试全绿。

---

## 5. 愿景：50 行终态（文本编辑器）

当 Era II 的路线图全部完成后，一个功能完备的小型文本编辑器将是这样的：

```nelua
require "nebula"

##[[
  nebula_annotate("EditorVisual", {
    primitives = {"multiline_editable", "scrollable_y", "clipboard_aware"},
    font_size = 14,
    line_height = 1.5
  })
]]
## nebula_derive("EditorVisual")

##[[
  nebula_app_begin("TextEditorApp")
    nebula_app_set_root_layout("TextEditorApp", { direction = "column", padding = 0 })
    nebula_app_register_component("editor", "EditorVisual", {
      layout = { flex_grow = 1 }
    })
  nebula_app_end()
]]
## nebula_derive_app("TextEditorApp")

local function main()
  local renderer: NebulaRenderer
  local app:      TextEditorApp
  if not nebula_init(&renderer, &app) then return 1 end
  while not nebula_should_close() do
    nebula_frame_render(&renderer, &app)
  end
  return 0
end
main()
```

**50 行，零样板，零 WGPU 调用。** 布局在编译期解算，交互逻辑由编译器自动编织。这是 Nebula 作为工业级 GUI 编译器的终态。
