# Phase 3 开发计划与技术挑战分析：多组件布局、文本与动态列表

> **总目标**：在 Phase 2 完成“形即渲染”的基础上，Phase 3 将 Nebula 的能力从“独立的静态组件”提升为“完整的动态界面系统”。这需要引入编译期布局解算、基于 GPU 的文本渲染管线以及运行时对象池与虚拟化技术。

本文档基于 Nebula 现有的编译期推导引擎架构（`nebula_core.nelua`），对 Phase 3 规划的三大核心方向进行深入的技术挑战分析，并制定详细的子阶段开发计划。

---

## 1. 核心方向与技术挑战评估

Nebula 的核心设计哲学是**“零运行时开销”**与**“编译期元编程”**。在 Phase 2 中，我们成功实现了组件状态机、Uniform 布局、着色器组合与多 Pass 阴影管线的编译期自动派生。然而，Phase 3 的需求与这一哲学产生了剧烈的碰撞，带来了全新的架构挑战。

### 1.1 多组件布局（`@layout` 宏 + Flexbox 编译期解算）

**技术方案：**
业界主流的 UI 布局引擎（如 React Native 使用的 Yoga 或 Rust 编写的 Taffy）通常采用 Flexbox 算法。在 Nebula 中，我们的目标是通过一个 `@layout` 宏，在编译期解析类似 HTML/JSX 的组件树声明，并运行一个简化的 Flexbox 求解器，最终将解算出的绝对坐标和尺寸注入到生成的 Nelua 代码中。

**技术挑战：**
- **编译期树结构解析**：Nelua 目前的宏系统（`##`）能够执行 Lua 代码，但我们需要一个能够解析嵌套布局声明（如 `@layout { Row { Button, Button } }`）的 AST 转换器。
- **循环依赖与多遍遍历**：Flexbox 算法本质上需要多遍遍历组件树（自顶向下确定约束，自底向上计算内容尺寸，再自顶向下分配剩余空间）。在编译期的 Lua 环境中实现这一算法需要仔细管理状态。
- **动态尺寸的矛盾**：如果组件的尺寸依赖于运行时的文本内容或窗口大小，纯编译期的静态解算将失效。这要求我们设计一种“混合模式”：编译期解算静态结构，生成高效的运行时布局更新函数处理动态约束。

### 1.2 文本渲染管线（GPU SDF / MSDF 文本渲染）

**技术方案：**
基于 GPU 的文本渲染通常有两种高效路径：位图图集（Bitmap Atlas）或有符号距离场（SDF / MSDF）。考虑到 Nebula 对分辨率无关性和高质量缩放的需求，SDF 字体渲染是最佳选择。我们将使用 `stb_truetype` 在初始化或离线时解析 TTF 文件，生成 SDF 纹理图集，并在运行时通过专门的 Text Pipeline 渲染四边形。

**技术挑战与集成评估：**
- **架构范式转换**：目前的 Nebula 渲染器使用“全屏三角形 + SDF 几何计算（无顶点缓冲区）”。文本渲染需要引入“顶点缓冲区（Vertex Buffer）”来为每个字形绘制一个四边形，以及“纹理绑定（Texture Binding）”来采样 SDF 图集。
- **管线工厂重构**：`pipeline_factory.lua` 需要扩展以支持带纹理和采样器的 BindGroupLayout，以及带顶点属性输入的 RenderPipeline。
- **文本排版（Shaping）**：虽然 `stb_truetype` 提供了基本的字距调整（Kerning）和度量数据，但处理复杂脚本（如中日韩或阿拉伯语）需要 HarfBuzz 等重型库。Phase 3.2 将首先支持基于简单度量数据的 ASCII/拉丁字符排版。
- **内存与性能**：文本通常包含大量字符。如果每个字符都作为一个独立的 Draw Call 提交，性能将迅速下降。必须引入**实例化渲染（Instancing）**或**批量渲染（Batching）**，通过一次 Draw Call 渲染一段文本的所有字形。

### 1.3 动态列表与条件渲染（运行时对象池）

**技术方案：**
当面对包含成百上千条数据的滚动列表或需要根据状态条件显示/隐藏的弹窗时，静态代码生成将无法应对。我们需要引入类似 Immediate Mode GUI (IMGUI) 的虚拟化技术，或者在运行时维护一个由预分配对象池支持的动态组件树。

**技术挑战：**
- **内存分配与零开销冲突**：动态列表必然涉及运行时的内存分配。Nelua 提供了多种分配器，但在要求严格控制内存布局的渲染管线中，动态分配可能引入性能抖动。
- **GPU 状态爆炸**：如果每个列表项都拥有自己独立的 Uniform Buffer 和 BindGroup，将迅速耗尽 WebGPU 的绑定限制。必须实现 Uniform 数组（UBO Arrays）或实例渲染（Instanced Rendering）。
- **生命周期与焦点管理**：条件渲染意味着组件会被销毁和重建，此时 `focused_id` 和输入状态的连贯性管理将变得异常复杂。

---

## 2. Phase 3 详细开发周期计划

### Phase 3.1 — 编译期静态 Flexbox 布局系统（已合入仓库）

**目标**：消除硬编码的绝对坐标，允许开发者通过嵌套语法声明组件树，并在编译期运行简易 Flexbox 算法。
**交付物**：`src/derive/layout_engine.lua`，支持 `direction`, `justify`, `align`, `padding`, `gap` 的编译期解算。

### Phase 3.2 — GPU SDF 文本渲染管线（已完成）

**目标**：引入高质量文本显示能力，支持基于 SDF 的英文字符渲染。

**子阶段计划：**

1.  **Phase 3.2.1: 字体预处理与 SDF 图集生成 (已完成)**
    - 集成 `stb_truetype` 的 Nelua 绑定。
    - 开发 `tools/font_preprocessor.nelua`：读取 TTF，按像素高度生成 ASCII 字符的单通道 SDF 位图，并打包成 1024x1024 纹理。
    - 导出字形度量表（Advance, Bearing, UV 坐标）为 Nelua 静态数组。

2.  **Phase 3.2.2: 纹理与顶点缓冲区基础设施 (已完成)**
    - 在 `renderer.nelua` 中实现 `nebula_upload_texture`：支持从 CPU 像素数据创建 WGPUTexture。
    - 扩展 `pipeline_factory.lua`：支持 `nebula_pipeline_textured_init`，自动生成包含 TextureView 和 Sampler 的 BindGroup 布局。
    - 在 `pipeline_factory.lua` 中添加顶点属性声明支持（Position, UV）。

3.  **Phase 3.2.3: 文本着色器组合器 (已完成)**
    - 在 `shader_compose.lua` 中添加文本专属模板。
    - 顶点着色器：接收顶点位置与 UV，计算字形在屏幕上的位置。
    - 片段着色器：执行 SDF 阈值测试（Thresholding）与抗锯齿（基于 `fwidth` 的梯度计算）。

4.  **Phase 3.2.4: `TextVisual` 派生引擎与运行时文本更新 (已完成)**
    - 扩展 `nebula_derive` 支持 `TextVisual`：自动派生文本布局计算逻辑。
    - 实现 `TextContext:set_text(str)`：运行时动态更新顶点缓冲区（或使用 Storage Buffer 存储字形实例数据）。
    - 集成基础字距调整（Kerning）支持。
    - 开发 `examples/text_demo.nelua`：展示多字号、多颜色的清晰文本渲染。

5.  **Phase 3.2.5: 演示完善与全面回归测试 (已完成)**
    - 升级 `text_demo` 为包含 7 个文本组件的综合展示：48px 标题、28px 副标题、20px 多行正文、16px ASCII 全范围符号、14px 小字号极限、24px 动态帧计数器、64px 大字号验证。
    - 编写 `smoke_phase3_2_4.lua`：31 项 Lua 断言覆盖 SDF 着色器生成、管线工厂纹理路径、discard 逻辑和特性标志。
    - 编写 `run_all_tests.sh`：自动化回归测试运行器，包含 4 项 Lua 冒烟测试 + 7 项编译回归测试（共 11 项）。
    - 验证所有历史 demo（button_demo、login_demo、shadow_demo、layout_demo 等）无回归。

### Phase 3.3 — 运行时动态列表与实例渲染

**目标**：重构底层渲染基础设施，支持大规模相同类型组件的实例渲染（Instancing），并实现基于 Frame Arena 的动态列表。

**子阶段计划：**

1.  **Phase 3.3.1: Frame Arena 分配器 (进行中)**
    - 新增 `src/nebula_arena.nelua`：实现线性 Frame Arena 分配器。
    - 提供 `nebula_arena_init`、`nebula_arena_reset`、`nebula_arena_alloc`、`nebula_arena_alloc_array` 等接口。
    - 每帧开始时调用 `reset` 将游标归零，帧内所有动态数据从此处线性分配，无 GC、无碎片，O(1) 分配复杂度。
    - 编写 `tests/smoke_arena.lua`：覆盖分配、对齐、溢出检测、reset 语义等核心断言。

2.  **Phase 3.3.2: Storage Buffer 基础设施**
    - 在 `renderer.nelua` 中新增 `nebula_create_storage_buffer`：创建 `WGPUBufferUsage_Storage | CopyDst` 类型的 Buffer。
    - 将 Phase 3.2.2 中内联使用的顶点缓冲区创建逻辑提升为公共 API `nebula_create_vertex_buffer`。
    - 两个函数均为纯扩展，不修改任何现有接口。

3.  **Phase 3.3.3: Instanced 着色器组合器**
    - 在 `shader_compose.lua` 中新增 `nebula_compose_instanced_shader(opts)` 函数。
    - 生成基于 `@builtin(instance_index)` 索引 `var<storage, read>` Storage Buffer 的 WGSL 着色器。
    - 支持从 `InstanceData` struct 中解包 `pos`、`size`、`bg_color`、`radius`、`border_color`、`border_width` 等字段。
    - 编写 `tests/smoke_phase3_3_3.lua`：覆盖 instance_index 绑定、storage buffer 声明、SDF 逻辑等断言。

4.  **Phase 3.3.4: Instanced 管线工厂**
    - 在 `pipeline_factory.lua` 中新增 `gen_pipeline_instanced` 函数。
    - 生成 `<T>InstancedPipeline` record，包含 `init(renderer, max_instances)`、`upload(renderer, data, count)`、`update_viewport(renderer, vw, vh)`、`draw(pass, count)` 四个方法。
    - 在 `nebula_gen_pipeline_source` 入口中添加 `spec.instanced` 分支。
    - 编写 `tests/smoke_phase3_3_4.lua`：覆盖管线代码生成的结构正确性断言。

5.  **Phase 3.3.5: 动态列表 Demo 与全面回归测试**
    - 编写 `examples/dynamic_list_demo.nelua`：展示 10,000 个可交互列表项的单帧渲染，验证 60FPS 稳定性。
    - 列表项支持 hover 高亮（通过 `component_id` 焦点链维护）。
    - 将新增测试项集成至 `tools/run_all_tests.sh`。
    - 验证所有历史 Demo（button_demo、login_demo、shadow_demo、layout_demo、text_demo）无回归。

---

## 3. 下一步行动

Phase 3.2 的所有子阶段（3.2.1 至 3.2.5）均已完成，文本渲染子系统已通过全面的回归测试验证。下一步我们将启动 **Phase 3.3**，开始引入运行时动态列表与实例渲染能力，以支持大规模组件的高效渲染。

### Phase 3.2.5 测试覆盖摘要

| 测试类型 | 数量 | 覆盖范围 |
|---|---|---|
| Lua 冒烟断言 | 31 项 | SDF 着色器结构、管线工厂纹理路径、discard 逻辑、特性标志 |
| Lua 冒烟脚本 | 4 个 | smoke_phase3_2_2/3/4 + verify_p2_4 |
| 编译回归测试 | 7 个 | text_demo, button_demo, login_demo, simple_rect_demo, shadow_demo, layout_demo, uniform_layout_test |
| text_demo 组件 | 7 个 | 6 种字号 (14-64px)、5 种颜色、多行换行、动态更新、ASCII 全范围 |

### 参考文献
- [1] Tomasz Czajęcki. "How to Write a Flexbox Layout Engine."
- [2] WebGPU Samples. "Text Rendering - MSDF."
- [3] Valve Corporation. "Improved Alpha-Tested Magnification for Vector Textures."
- [4] Red Blob Games. "Guide to SDF+MSDF Fonts."
