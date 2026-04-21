# Nebula GUI Compiler — Phase 2.5 开发计划：多 Pass 渲染与阴影效果

> **总目标**：在 Phase 2.4 实现声明式交互的基础上，进一步扩展渲染引擎的能力，使其能够处理需要多个渲染阶段（Pass）的复杂视觉效果。Phase 2.5 的核心是引入离屏纹理渲染机制和可分离高斯模糊算法，从而为组件提供高质量的真实阴影（Drop Shadow）效果。

---

## 1. 背景与现状分析

在 Phase 2.3 和 2.4 中，我们已经实现了高度自动化的渲染管线派生和交互原语注入。然而，当前的渲染架构存在一个根本性的限制：**单 Pass 渲染模型**。

目前 `src/derive/pipeline_factory.lua` 生成的每一个 `<T>Pipeline` 都只包含一个 WGPURenderPipeline、一个 Uniform Buffer 和一个 BindGroup。在 `draw` 方法中，它直接将全屏三角形渲染到当前的屏幕交换链（Swap Chain）上。这种架构对于纯色的填充、SDF 圆角和边框是非常高效的，但它无法实现需要对周围像素进行采样的效果，例如高质量的模糊和真实的阴影。

为了实现 CSS 级别的 `box-shadow`，业界通常有两种做法：

1.  **SDF 解析近似法（单 Pass）**：利用现有的 SDF 函数，在片段着色器中通过 `smoothstep` 扩大边界来近似模糊效果。这种方法性能极高，不需要额外的纹理，但模糊半径较大时视觉效果不佳，且只能处理规则的几何形状。
2.  **两 Pass 可分离高斯模糊法（多 Pass）**：先将组件的阴影形状渲染到离屏纹理，然后使用水平和垂直两个 Pass 对该纹理进行真正的高斯模糊处理，最后再将结果合成到屏幕上。这种方法视觉质量最高，是现代 UI 引擎（如 WebKit 和 Blink）处理大半径阴影的标准做法。

考虑到 Nebula 作为下一代 GUI 编译器的定位，我们决定在 Phase 2.5 彻底打破单 Pass 的限制，引入**两 Pass 可分离高斯模糊**作为阴影的底层实现。这不仅解决了阴影问题，也为未来的发光效果（Bloom）、毛玻璃（Backdrop Filter）等高级视觉特性铺平了道路。

---

## 2. 核心架构设计

为了支持多 Pass 渲染，我们需要对底层的 WebGPU 基础设施和编译期的管线工厂进行深度改造。

### 2.1 离屏渲染基础设施

在 `src/renderer.nelua` 中，我们需要引入创建离屏纹理（Offscreen Texture）和采样器（Sampler）的能力。目前的 `nebula_pipeline_base_init` 函数假设了单一的 Uniform Buffer 绑定。我们将新增一个 `nebula_offscreen_pass_init` 函数，用于初始化带有纹理采样的渲染管线。

新的 BindGroupLayout 将包含三个条目：
1.  Uniform Buffer（用于传递分辨率、模糊半径等参数）
2.  Texture（用于读取上一个 Pass 的输出）
3.  Sampler（用于对纹理进行双线性采样）

### 2.2 着色器组合器的扩展

`src/derive/shader_compose.lua` 将从单纯的单片段生成器升级为多片段生成器。当检测到 Visual 规格中包含 `shadow_color`、`shadow_offset` 和 `shadow_blur` 字段时，组合器将生成三个独立的 WGSL 着色器模块：

1.  **Shadow Mask Shader**：仅渲染组件的纯色形状（考虑圆角），输出到离屏纹理 A。
2.  **Horizontal Blur Shader**：读取纹理 A，执行水平方向的一维高斯模糊，输出到离屏纹理 B。
3.  **Vertical Blur & Composite Shader**：读取纹理 B，执行垂直方向的一维高斯模糊，并将模糊后的阴影与组件本身的主体（Fill + Border）混合后输出到最终屏幕。

`nebula_compose_shader` 的返回值中的 `required_passes` 将从 `{"main"}` 变为 `{"shadow_mask", "blur_h", "blur_v_and_main"}`。

### 2.3 管线工厂的重构

`src/derive/pipeline_factory.lua` 需要能够解析多 Pass 需求，并为 `<T>Pipeline` 生成更复杂的结构。生成的记录将包含多个 `WGPURenderPipeline` 实例以及用于在它们之间传递数据的中间纹理视图。

`draw` 方法将被重写，按顺序执行多个 Render Pass Encoder：
- 第一个 Encoder 绑定离屏纹理 A 作为颜色附件，执行 Mask 渲染。
- 第二个 Encoder 绑定离屏纹理 B 作为颜色附件，读取 A，执行水平模糊。
- 第三个 Encoder 绑定最终屏幕，读取 B，执行垂直模糊和主体渲染。

---

## 3. 实施步骤 (Sub-phases)

Phase 2.5 的开发将严格遵循渐进式增强的原则，分为以下四个子阶段：

### Sub-phase 2.5.1: 基础设施扩展
- 在 `src/renderer.nelua` 中新增 `nebula_create_render_target` 函数，用于分配指定尺寸和格式的离屏纹理及视图。
- 新增 `nebula_create_sampler` 函数，提供默认的线性采样器。
- 编写 `nebula_pipeline_textured_init` 函数，封装带有纹理和采样器绑定的 WebGPU 管线初始化逻辑。

### Sub-phase 2.5.2: 着色器生成逻辑升级
- 修改 `src/derive/shader_compose.lua`。
- 引入一维高斯模糊的 WGSL 代码片段（使用预计算的权重或动态循环）。
- 根据 Visual 的 `shadow_*` 属性，动态决定是否生成多 Pass 着色器集合。
- 确保不带阴影属性的组件仍然回退到高效的单 Pass 渲染路径。

### Sub-phase 2.5.3: 管线代码生成器改造
- 升级 `src/derive/pipeline_factory.lua`。
- 让生成的 `<T>Pipeline` 记录包含中间纹理和多个 BindGroup。
- 重写生成的 `init` 方法，按顺序初始化所有的 Sub-pipeline。
- 重写生成的 `draw` 方法，编排多个 Pass 的执行顺序和资源绑定。

### Sub-phase 2.5.4: 示例迁移与回归测试
- 新增 `examples/shadow_demo.nelua`，展示带有大半径高斯模糊阴影的卡片组件。
- 验证现有的 `button_demo` 和 `login_demo` 在新的管线生成器下是否仍然正常工作（单 Pass 路径回归）。
- 更新 `tools/headless_test.c`，增加对多 Pass 渲染结果的离线像素比对。

---

## 4. 预期收益与验收标准

完成 Phase 2.5 后，Nebula 引擎将具备真正的多 Pass 渲染编排能力。开发者只需在 `nebula_annotate` 中声明阴影参数，编译器即可自动推导出复杂的离屏渲染和高斯模糊管线。

**验收标准**：
1.  **视觉质量**：`shadow_demo` 必须呈现出平滑、无明显带状伪影（Banding）的高质量高斯模糊阴影。
2.  **按需生成**：未声明阴影属性的组件（如 `simple_rect_demo`），其生成的 Nelua 源码中绝不能包含任何离屏纹理或多余的 Pass 逻辑，保持零开销。
3.  **无缝集成**：阴影的生成必须完全由编译器在底层处理，开发者在编写 UI 逻辑时，不需要手动管理任何 WebGPU 纹理、采样器或命令编码器。

---

## 5. 风险提示

- **显存开销**：每个带有阴影的组件类型可能会分配独立的离屏纹理。如果屏幕上有大量不同尺寸的阴影组件，可能会导致显存占用过高。在后续阶段（Phase 3+）可能需要引入纹理池（Texture Pool）或图集（Atlas）机制来复用离屏资源。
- **性能瓶颈**：高分辨率下的大半径高斯模糊对 GPU 带宽要求较高。需要确保 WGSL 着色器中的纹理采样次数得到优化，例如利用双线性采样的特性减少 Fetch 次数。
