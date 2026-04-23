# Phase 3.5 详细规划：哲学驱动的高层组件编排与全面 Instancing 化

**作者**：Manus AI
**日期**：2026-04-24

基于对 Nebula 核心代码（截至 Phase 3.4.4）的全面审视，我们发现框架的底层渲染与推导引擎已足够强悍，但**应用组装层的样板代码（Boilerplate）极其冗长**。在 `login_demo.nelua` 等示例中，开发者必须手动初始化每一个 Pipeline，手动调用每个 Context 的 `update` 和 `draw`，并手动编写重复的 WebGPU 渲染循环 [1]。

为了将 Nebula 从一个“图形学库”提升为真正的“GUI 框架”，同时坚守“零运行时开销”与“形状即渲染”的核心哲学，Phase 3.5 将聚焦于**高层组件编排（App Orchestration）**与**全面 Instancing 化（Universal Instancing）**。

---

## 1. 设计哲学与演进方向

在重新审视了 Phase 0 到 Phase 3.4 的演进历程后，我们决定摒弃原计划中基于 `wgpuQueueWriteBuffer` 的“运行时管线共享”和纯静态的“黑盒运行时编排”，回归 Nebula 的第一性原理 [2] [3]：

### 1.1 摒弃“运行时管线共享”，坚持“编译期专属 Instancing”
原计划通过频繁更新单一 Uniform Buffer 来实现管线共享，这是一种典型的“运行时通用化”妥协，违背了“形状即渲染”的专属生成原则。
我们将坚持为每种 Visual 生成专属管线，并将 Phase 3.3 的 Storage Buffer Instancing 提升为所有派生管线的默认标准。`pipeline_factory.lua` 将不再生成单实例的 `draw` 方法，而是生成 `draw_instanced(pass, context_array, count)`。这既保留了编译期专属优化的优雅，又通过 Instancing 彻底解决了 WebGPU 绑定瓶颈，实现了极致性能。

### 1.2 摒弃“黑盒运行时编排”，坚持“编译期显式代码生成”
原计划的 `nebula_derive_app` 试图在运行时接管生命周期，这容易退化为不透明的框架，且难以与动态列表（Arena 分配）融合。
我们将让 `nebula_derive_app` 直接生成包含所有组件显式调用序列的 `app:update()` 和 `app:draw()` 源码。对于声明的动态插槽（Slots），生成器会直接插入遍历 Arena 并收集数据的内联代码。生成的代码就像是开发者手写的一样清晰、直接，没有任何运行时的虚假抽象。

---

## 2. 核心目标与技术方案

### 2.1 渲染循环模板化（Render Loop Encapsulation）
提取所有 Demo 中重复的 WebGPU 渲染循环代码，封装为高层次的 API。

**技术方案：**
*   在 `renderer.nelua` 中新增 `nebula_frame_begin()` 和 `nebula_frame_end()`。
*   `nebula_frame_begin()`：负责获取 Surface Texture、创建 TextureView 和 CommandEncoder，并开启 RenderPass。
*   `nebula_frame_end()`：负责结束 RenderPass、提交 CommandBuffer 并调用 Present。
*   **注意**：必须提供健壮的错误处理和资源清理机制，防止在缺乏 RAII 机制的 Nelua 中发生 WGPU 资源泄漏。

### 2.2 全面 Instancing 化（Universal Instancing via Storage Buffers）
修改 `nebula_derive` 生成的 `<T>Pipeline`，使其默认采用基于 Storage Buffer 的 Instanced 渲染路径。

**技术方案：**
*   **废弃单 Uniform 绑定**：修改 `nebula_pipeline_base_init`，不再为每个 Pipeline 创建独立的 Uniform Buffer（仅保留一个全局的 Viewport Uniform）。
*   **统一使用 Storage Buffer**：所有派生的 `<T>Pipeline` 默认采用 `gen_pipeline_instanced` 的生成逻辑。每个 Pipeline 维护一个 `Storage Buffer`，其大小为 `max_instances * sizeof(<T>Uniforms)`。
*   **着色器统一**：修改 `shader_compose.lua`，使所有生成的 WGSL 着色器默认通过 `@builtin(instance_index)` 从 Storage Buffer 中读取组件属性。
*   **批量绘制**：生成 `upload(renderer, data_array, count)` 和 `draw_instanced(pass, count)` 方法。

### 2.3 编译期显式编排与动态插槽（Explicit App Derivation & Dynamic Slots）
引入 `nebula_derive_app` 宏，在编译期声明组件树，并生成显式的生命周期方法。

**技术方案（概念设计）：**
```nelua
-- 1. 在编译期声明应用结构（内部 eDSL）
##[[
  nebula_app_begin("LoginApp")
    nebula_app_register_component("card", "CardVisual")
    nebula_app_register_component("email", "InputVisual")
    nebula_app_register_component("password", "InputVisual")
    nebula_app_register_slot("list_container", "ListItemVisual") -- 动态插槽
    nebula_app_register_component("login_btn", "ButtonVisual")
  nebula_app_end()
]]

-- 2. 自动派生 App 结构体与方法
## nebula_derive_app("LoginApp")
```
*   `nebula_derive_app` 将在编译期生成一个包含所有注册组件 `Context` 和所需共享 `Pipeline` 的 `LoginApp` 记录。
*   自动生成 `app:update(input, dt)`，内部按注册顺序显式调用 `self.card:update(...)` 等，并遍历动态插槽数据。
*   自动生成 `app:draw(pass)`，内部将同类型组件（包括静态组件和动态插槽数据）收集到连续数组中，调用专属管线的 `upload` 和 `draw_instanced`。

### 2.4 新增交互原语：Toggleable（支持正交状态）
为了支持复选框（Checkbox）和开关（Switch），在 `interaction_factory.lua` 中新增 `toggleable` 原语。

**技术方案：**
*   **状态机重构**：在引入 `toggleable` 之前，重构状态机生成逻辑，支持正交状态（Orthogonal States）或位掩码（Bitmask）表示法，解决 `focusable` 和 `toggleable` 同时存在时的优先级冲突。
*   生成 `toggle: ToggleableState`（包含 `is_on` 布尔值）。
*   在 `process_input` 中，如果检测到 `click.just_clicked`，则翻转 `is_on` 的值。

---

## 3. 子阶段实施计划

| 子阶段 | 标题 | 核心交付物 |
| :--- | :--- | :--- |
| **3.5.1** | 全面 Instancing 化 | 修改 `pipeline_factory.lua` 和 `shader_compose.lua`，为所有派生管线生成基于 Storage Buffer 的 `draw_instanced` 方法。 |
| **3.5.2** | 编译期显式编排与动态插槽 | 实现 `nebula_derive_app` 宏；自动生成包含显式调用序列的 `update` 和 `draw` 方法；支持动态插槽的数据收集。 |
| **3.5.3** | `Toggleable` 原语与正交状态 | 重构状态机支持正交状态；扩展交互工厂实现 `toggleable` 原语；实现基础复选框组件。 |
| **3.5.4** | `form_demo` 综合演示与重构验证 | 封装 `nebula_frame_begin/end`；使用新的 App 编排机制重写 `login_demo`（更名为 `form_demo` 并加入复选框），验证代码量缩减目标和极致性能。 |

---

## 4. 预期收益与风险评估

### 4.1 预期收益
*   **极致性能**：通过全面 Instancing 化，将 $N$ 次 `WriteBuffer` + $N$ 次 `Draw` 优化为 1 次 `WriteBuffer` + 1 次 `Draw`。
*   **极简的开发者体验**：应用组装代码将从数百行锐减至几十行，且生成的代码清晰透明。
*   **架构统一**：彻底消除了静态表单与动态列表在底层渲染机制上的差异，为 Phase 3.6 铺平道路。

### 4.2 风险评估
*   **编译期代码生成的复杂性**：`nebula_derive_app` 需要在 Lua 环境中维护复杂的组件树状态，并生成高效的数据收集（Gathering）代码。这要求对现有的推导引擎进行小心翼翼的扩展。
*   **状态机重构的兼容性**：将状态机从线性枚举重构为正交状态（位掩码）可能会影响现有的 `transition_to` 逻辑，需要进行全面的回归测试。

## 参考文献
[1] `examples/login_demo.nelua` - 当前最复杂的静态组件演示，暴露了应用组装层的冗长痛点。
[2] `docs/DESIGN_PHASE1.md` - 确立了“零运行时开销”与“编译期元编程”的核心哲学。
[3] `docs/PLAN_PHASE2_3.md` - 确立了“形状即渲染”与“按需生成”的专属管线原则。
