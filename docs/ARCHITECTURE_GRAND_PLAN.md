# Nebula 架构总纲领 v3.4

**修订日期**：2026-04-30（v3.4 修订）  
**修订历史**：  
- **v3.4 (2026-04-30)**：深度审计。Phase 4.3/4.4 标记为"S1-S3 核心已完成，存在结构性缺口"：沙箱隔离未实现、契约校验未接入编译流程、高级原语未内置。Phase 4.2.2 D-4.1-C benchmark 已通过（2026-05-01 补执行）。
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

## 2. 核心定位：工业级 GUI 编译器

Nebula 的目标不是做一个小众的研究项目，而是成为一个能与工业界主流框架竞争的 GUI 基础设施：

- **对标 Qt**：提供完备的跨平台抽象（PAL）和工业级的渲染质量（Slug 引擎）。
- **对标 ImGui**：通过“编译期消解”实现比 ImGui 更低的运行时开销，同时保持极其简单的 API。
- **对标 SwiftUI**：利用 Nelua 的元编程能力实现纯声明式的 UI 描述，但无需 SwiftUI 那样庞大的运行时支持。

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
| **4.3** | **可编程原语注册表** | 允许开发者安全注入自定义交互逻辑，框架从工具库升维为开放元系统。 | **S1+S2+S3 核心已完成**；沙箱隔离未实现，契约校验未接入编译流程 | **90/100** |
| **4.4** | **高级组件库** | 实现 scrollable、dropdown、multiline_editable 标准组件。 | **S1+S2+S3 核心已完成**；三个高级原语未内置到框架注册表 | **81/100** |
| 4.2.3 | HarfBuzz + CJK 集成 | 7000 常用 CJK 字形 shaping 预处理。 | 规划中 | 82/100 |
| 4.X | 高密度文本 + 输入补全 | Atlas 文本通道 + Unicode char callback + clipboard | 规划中 | 待评分 |
| 4.5 | 注册原语语法糖 | 基于 4.4 真实用例提炼重复模式，简化 DX | 规划中 | 待评分 |
| 4.6 | Indirect Drawing | GPU 端实例剔除与间接绘制 | 规划中 | 78/100 |
| 4.7 | 文本编辑器原型 | 验证 Era II 工业级能力 | 规划中 | 待评分 |
| 5.0 | 生态与 CI/CD | 完善文档、包管理支持与多端自动化测试。 | 规划中 | 待评分 |

> 重要度评分基于五个维度（架构奠基性、公理合规性、开发者体验、工业化就绪度、下游解锁度）加权综合评分，详见 [`docs/PHASE_IMPORTANCE_SCORECARD.md`](PHASE_IMPORTANCE_SCORECARD.md)。

---

## 4. 愿景：50 行终态（文本编辑器）

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
