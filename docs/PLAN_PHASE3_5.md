# Phase 3.5 详细规划：高层组件编排与渲染管线共享

**作者**：Manus AI
**日期**：2026-04-23

基于对 Nebula 核心代码（截至 Phase 3.4.4）的全面审视，我们发现框架的底层渲染与推导引擎已足够强悍，但**应用组装层的样板代码（Boilerplate）极其冗长**。在 `login_demo.nelua` 等示例中，开发者必须手动初始化每一个 Pipeline，手动调用每个 Context 的 `update` 和 `draw`，并手动编写重复的 WebGPU 渲染循环 [1] [2]。

为了将 Nebula 从一个“图形学库”提升为真正的“GUI 框架”，同时坚守“零运行时开销”的核心哲学，Phase 3.5 将聚焦于**高层组件编排（App Orchestration）**与**管线共享（Pipeline Sharing）**，而非急于进行跨平台移植或开发复杂的业务组件 [3]。

---

## 1. 设计哲学与演进方向

### 1.1 坚持内部 DSL，拒绝外部语法
正如前期的架构决策分析所指出，Nebula 绝不应该引入 XML 或 YAML 等外部 DSL。我们将继续深耕 Nelua 的编译期元编程（`##` 语法），通过 Lua 宏来声明组件树，并在编译期将其展开为高效的、静态类型的运行时代码 [4]。

### 1.2 消除“Pipeline 与 Context 的 1:1 绑定”
目前，每个 `Context` 实例都需要一个独立的 `Pipeline` 实例（例如 `pipe_email` 和 `pipe_password`）。这不仅导致代码冗长，还浪费了大量的 WebGPU BindGroup 资源。Phase 3.5 将重构派生引擎，使**同一种 Visual 类型的所有实例共享同一个 Pipeline**，通过动态更新 Uniform Buffer 或使用动态偏移（Dynamic Offset）来渲染不同实例。

### 1.3 自动化生命周期管理
开发者不应再手动编写包含 50 行样板代码的 `while` 循环。我们将引入 `NebulaApp` 概念，接管事件收集、组件更新（Update）和绘制分发（Draw Dispatch）。

---

## 2. 核心目标与技术方案

### 2.1 渲染循环模板化（Render Loop Encapsulation）
提取所有 Demo 中重复的 WebGPU 渲染循环代码，封装为高层次的 API。

**技术方案：**
*   在 `renderer.nelua` 中新增 `nebula_frame_begin()` 和 `nebula_frame_end()`。
*   `nebula_frame_begin()`：负责获取 Surface Texture、创建 TextureView 和 CommandEncoder，并开启 RenderPass。
*   `nebula_frame_end()`：负责结束 RenderPass、提交 CommandBuffer 并调用 Present。

### 2.2 同类型管线共享（Pipeline Sharing via Dynamic Uniforms）
修改 `nebula_derive` 生成的 `<T>Pipeline`，使其能够渲染多个同类型的 `Context` 实例。

**技术方案：**
*   **方案 A（单 Buffer 多偏移）**：创建一个足够大的 Uniform Buffer，使用 `wgpuRenderPassEncoderSetBindGroup` 的 `dynamicOffset` 参数。每次绘制前设置偏移量，指向当前实例的数据。
*   **方案 B（每实例更新）**：在调用 `pipe:draw(pass, &context)` 时，内部调用 `wgpuQueueWriteBuffer` 更新唯一的 Uniform Buffer，然后执行绘制。由于 UI 组件数量通常不大（非动态列表场景），这种简单的更新策略在性能上是可接受的，且实现更简单。
*   **决策**：考虑到代码生成的简易性，优先采用**方案 B**。如果后续发现性能瓶颈，再无缝切换到方案 A。

### 2.3 编译期组件树注册与自动编排（App Derivation）
这是 Phase 3.5 的核心挑战。我们需要一个机制，在编译期收集应用中所有的组件实例，并自动生成它们的 `update` 和 `draw` 调用序列。

**技术方案（概念设计）：**
```nelua
-- 1. 在编译期声明应用结构（内部 eDSL）
##[[
  nebula_app_begin("LoginApp")
    nebula_app_register_component("card", "CardVisual")
    nebula_app_register_component("email", "InputVisual")
    nebula_app_register_component("password", "InputVisual")
    nebula_app_register_component("login_btn", "ButtonVisual")
  nebula_app_end()
]]

-- 2. 自动派生 App 结构体与方法
## nebula_derive_app("LoginApp")

-- 3. 运行时使用
local app: LoginApp
app:init(&renderer)
-- 配置初始视觉属性
app.card.visual.radius = 16.0
-- 运行主循环（内部自动处理事件、更新和渲染）
app:run()
```
*   `nebula_derive_app` 将在编译期生成一个包含所有注册组件 `Context` 和所需共享 `Pipeline` 的 `LoginApp` 记录。
*   自动生成 `app:update(input, dt)`，内部按注册顺序调用 `self.card:update(...)`、`self.email:update(...)` 等。
*   自动生成 `app:draw(pass)`，内部按注册顺序调用 `self.pipe_card:draw(pass, &self.card)` 等。

### 2.4 新增交互原语：Toggleable
为了支持复选框（Checkbox）和开关（Switch），在 `interaction_factory.lua` 中新增 `toggleable` 原语。

**技术方案：**
*   生成 `toggle: ToggleableState`（包含 `is_on` 布尔值）。
*   在 `process_input` 中，如果检测到 `click.just_clicked`，则翻转 `is_on` 的值。
*   允许在状态机中定义 `on` 和 `off` 相关的状态分支。

---

## 3. 子阶段实施计划

| 子阶段 | 标题 | 核心交付物 |
| :--- | :--- | :--- |
| **3.5.1** | 渲染循环与管线共享重构 | 封装 `nebula_frame_begin/end`；修改 `<T>Pipeline:draw` 以接受 Context 指针并内部更新 Uniform。 |
| **3.5.2** | `nebula_derive_app` 编译期编排 | 实现 Lua 宏以注册组件树；自动生成 `App` 记录及其生命周期方法。 |
| **3.5.3** | `Toggleable` 原语与 Checkbox 组件 | 扩展交互工厂；实现一个基础的复选框组件演示。 |
| **3.5.4** | `form_demo` 综合演示与重构验证 | 使用新的 App 编排机制重写 `login_demo`（更名为 `form_demo` 并加入复选框），验证代码量缩减目标（预期缩减 50% 以上的样板代码）。 |

---

## 4. 预期收益与风险评估

### 4.1 预期收益
*   **极简的开发者体验**：应用组装代码将从数百行锐减至几十行。
*   **资源优化**：消除冗余的 Pipeline 和 BindGroup 实例。
*   **架构闭环**：真正确立 Nebula 基于内部 eDSL 的声明式 UI 范式。

### 4.2 风险评估
*   **编译期状态管理复杂性**：`nebula_derive_app` 需要在 Lua 环境中维护复杂的组件树状态，并正确生成强类型的 Nelua 字段。这要求对现有的推导引擎进行小心翼翼的扩展，以避免破坏现有的向后兼容性。
*   **动态列表的兼容性**：Phase 3.3 的动态列表（Instancing）由于其特殊的数据供给方式，可能暂时无法完美融入这种静态的组件树编排。Phase 3.5 的首要目标是解决常规静态 UI（如表单）的编排，动态列表的统一编排将留至 Phase 3.6 探索。

## 参考文献
[1] `examples/login_demo.nelua` - 当前最复杂的静态组件演示，暴露了应用组装层的冗长痛点。
[2] `examples/layout_demo.nelua` - 展示了编译期 Flexbox 的潜力，但同样受困于手动的生命周期管理。
[3] `docs/PLAN_PHASE3_5_PROPOSAL.md` - 早期的 Phase 3.5 提案，现已被本规划的“高层组件编排”方向所取代。
[4] `docs/NEBULA_ABSTRACTION_DSL_ANALYSIS.md` - 关于 Nebula 架构决策的深度分析，确立了拒绝外部 DSL、拥抱内部 eDSL 的基调。
