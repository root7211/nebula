# Phase 3 开发计划与技术挑战分析：多组件布局、文本与动态列表

> **总目标**：在 Phase 2 完成“形即渲染”的基础上，Phase 3 将 Nebula 的能力从“独立的静态组件”提升为“完整的动态界面系统”。这需要引入编译期布局解算、基于 GPU 的文本渲染管线以及运行时对象池与虚拟化技术。

本文档基于 Nebula 现有的编译期推导引擎架构（`nebula_core.nelua`），对 Phase 3 规划的三大核心方向进行深入的技术挑战分析，并制定详细的子阶段开发计划。

---

## 1. 核心方向与技术挑战评估

Nebula 的核心设计哲学是**“零运行时开销”**与**“编译期元编程”**。在 Phase 2 中，我们成功实现了组件状态机、Uniform 布局、着色器组合与多 Pass 阴影管线的编译期自动派生。然而，Phase 3 的需求与这一哲学产生了剧烈的碰撞，带来了全新的架构挑战。

### 1.1 多组件布局（`@layout` 宏 + Flexbox 编译期解算）

当前 Nebula 中的组件（如 `login_demo.nelua` 中的 `Card`、`Input`、`Button`）都是通过硬编码的绝对坐标（`pos` 和 `size`）进行定位的。这使得构建复杂的响应式界面变得极其困难。

**技术方案：**
业界主流的 UI 布局引擎（如 React Native 使用的 Yoga [1] 或 Rust 编写的 Taffy [2]）通常采用 Flexbox 算法。Flexbox 算法能够处理复杂的父子尺寸依赖、自动换行与对齐。在 Nebula 中，我们的目标是通过一个 `@layout` 宏，在编译期解析类似 HTML/JSX 的组件树声明，并运行一个简化的 Flexbox 求解器，最终将解算出的绝对坐标和尺寸注入到生成的 Nelua 代码中。

**技术挑战：**
- **编译期树结构解析**：Nelua 目前的宏系统（`##`）能够执行 Lua 代码，但我们需要一个能够解析嵌套布局声明（如 `@layout { Row { Button, Button } }`）的 AST 转换器。
- **循环依赖与多遍遍历**：Flexbox 算法本质上需要多遍遍历组件树（自顶向下确定约束，自底向上计算内容尺寸，再自顶向下分配剩余空间）[3]。在编译期的 Lua 环境中实现这一算法需要仔细管理状态。
- **动态尺寸的矛盾**：如果组件的尺寸依赖于运行时的文本内容或窗口大小，纯编译期的静态解算将失效。这要求我们设计一种“混合模式”：编译期解算静态结构，生成高效的运行时布局更新函数处理动态约束。

### 1.2 文本渲染管线（字形光栅化 / 图集 / Shaping）

文本是 GUI 中最基本也最复杂的元素。目前 Nebula 只能渲染几何图形（矩形、圆角、阴影），完全不支持文本显示。

**技术方案：**
基于 GPU 的文本渲染通常有两种高效路径：位图图集（Bitmap Atlas）或有符号距离场（SDF / MSDF）[4]。考虑到 Nebula 对分辨率无关性和高质量缩放的需求，SDF 字体渲染是最佳选择。我们需要在编译期或初始化时解析 TTF 文件，提取字形轮廓，生成 SDF 纹理图集，并在运行时通过专门的 Text Pipeline 渲染四边形。

**技术挑战：**
- **TTF 解析与整形（Shaping）**：解析 OpenType 字体文件极其复杂，涉及字距调整（Kerning）和连字处理。在 C/C++ 生态中通常依赖 FreeType 和 HarfBuzz，但这违背了 Nebula 尽量减少外部 C 依赖的初衷。
- **GPU 资源管理**：中日韩（CJK）字符集极其庞大，无法预先将所有字形打包进一张 2048x2048 的纹理中。必须实现动态的运行时字形缓存（Glyph Cache）与图集更新机制，这与 Nebula 目前静态分配资源的模式冲突。
- **SDF 渲染质量**：标准的 SDF 在小字号下会丢失尖角细节（需要 MSDF 算法），且多通道 SDF 的着色器实现复杂度远高于当前的几何着色器。

### 1.3 动态列表与条件渲染（运行时对象池）

目前的 Nebula 架构是“保留模式（Retained Mode）”的极端体现：每个组件在编译期派生一个专属的 `<T>Context`，并在主循环中显式调用 `update()` 和 `to_uniforms()`。这对于数量固定且已知的组件（如登录界面的几个按钮）非常高效。

**技术方案：**
当面对包含成百上千条数据的滚动列表或需要根据状态条件显示/隐藏的弹窗时，静态代码生成将无法应对。我们需要引入类似 Immediate Mode GUI（IMGUI）[5] 的虚拟化技术，或者在运行时维护一个由预分配对象池支持的动态组件树。

**技术挑战：**
- **内存分配与零开销冲突**：动态列表必然涉及运行时的内存分配。Nelua 提供了多种分配器（如 `gc_allocator` 或 `general_allocator`），但在要求严格控制内存布局的渲染管线中，动态分配可能引入性能抖动。
- **GPU 状态爆炸**：如果每个列表项都拥有自己独立的 Uniform Buffer 和 BindGroup，当列表项达到数千个时，将迅速耗尽 WebGPU 的绑定限制。必须实现 Uniform 数组（UBO Arrays）或实例渲染（Instanced Rendering），这需要彻底重构 `pipeline_factory.lua` 中现有的单实例管线生成逻辑。
- **生命周期与焦点管理**：条件渲染意味着组件会被销毁和重建，此时 `focused_id` 和输入状态的连贯性管理将变得异常复杂。

---

## 2. Phase 3 详细开发周期计划

为了逐步攻克上述挑战，Phase 3 将被拆分为三个主要子阶段。本着“先静态后动态、先基础后高级”的原则，我们将从纯编译期的静态布局系统开始。

### Phase 3.1 — 编译期静态 Flexbox 布局系统（预计 1 周）

**目标**：消除硬编码的绝对坐标，允许开发者通过嵌套语法声明组件树，并在编译期（Lua 环境中）运行简易 Flexbox 算法，将计算出的绝对坐标硬编码到生成的 Nelua 代码中。

**核心任务**：
1. **设计 `@layout` 宏语法**：允许使用类似声明式的语法定义界面层级。
2. **实现 AST 解析器**：在 `nebula_core.nelua` 的预处理块中，解析布局声明树。
3. **集成简易 Flexbox 求解器**：在 Lua 中实现一个支持 `flex-direction`、`justify-content` 和 `align-items` 的三遍遍历布局算法。
4. **生成静态坐标**：将解算结果注入到生成的 `<T>Context:init()` 代码中。

**验收标准**：
- 新增 `examples/layout_demo.nelua`，使用 `@layout` 宏定义包含横向和纵向排列的卡片与按钮。
- 编译后生成的 C 代码中，组件的 `pos` 和 `size` 已被替换为计算好的常量值。
- 运行结果的像素布局与预期一致，无运行时计算开销。

### Phase 3.2 — GPU SDF 文本渲染管线（预计 2 周）

**目标**：引入基本的文本显示能力，支持英文字符的 SDF 渲染。

**核心任务**：
1. **字体预处理工具**：开发一个离线工具，读取 TTF 文件，生成包含 ASCII 字符集的单通道 SDF 纹理（PNG）和包含字形度量（Metrics）的 JSON/Lua 表。
2. **`TextVisual` 与专属管线**：扩展 `nebula_derive`，支持一种新的内置视觉类型 `TextVisual`。
3. **文本布局算法**：在运行时实现一个简单的基于字形度量的文本排版函数（处理换行和字符间距）。
4. **Text Pipeline**：生成能够接收纹理图集 BindGroup 并在 Fragment Shader 中执行 SDF 阈值测试的专属渲染管线。

**验收标准**：
- 新增 `examples/text_demo.nelua`，能够渲染清晰的缩放文本。
- 文本着色器正确处理颜色和抗锯齿（基于 SDF 梯度）。

### Phase 3.3 — 运行时动态列表与实例渲染（预计 2-3 周）

**目标**：重构底层渲染基础设施，支持大规模相同类型组件的实例渲染（Instancing），并实现基于对象池的动态列表。

**核心任务**：
1. **重构 Uniform 管理**：修改 `pipeline_factory.lua`，将单一的 `<T>Uniforms` 升级为 Uniform Buffer Array 或 Storage Buffer，支持一次上传多个组件的数据。
2. **实例渲染管线**：修改生成的 `draw()` 方法，使用 `wgpuRenderPassEncoderDraw(pass, 3, instance_count, 0, 0)` 进行实例化绘制。
3. **虚拟化列表容器**：开发 `ListView` 组件，在运行时仅计算和提交当前滚动视口内的可见元素数据到 GPU。
4. **对象池内存管理**：使用 Nelua 的静态数组或自定义分配器预分配组件 Context 内存。

**验收标准**：
- 新增 `examples/list_demo.nelua`，流畅渲染包含 10,000 个带悬停效果按钮的滚动列表，帧率稳定在 60FPS。
- WebGPU API 追踪显示，每帧仅产生 1-2 次 Draw Call，而不是 10,000 次。

---

## 3. 启动 Phase 3.1 开发

按照上述计划，我们将立即启动 **Phase 3.1** 的开发工作。重点将放在实现一个纯编译期的 Flexbox 求解器，并将其与 Nebula 现有的代码生成器集成。

### 参考文献
[1] Facebook Engineering. "Yoga: A cross-platform layout engine." https://engineering.fb.com/2016/12/07/android/yoga-a-cross-platform-layout-engine/
[2] DioxusLabs. "Taffy: A high performance rust-powered UI layout library." https://github.com/dioxusLabs/taffy
[3] Tomasz Czajęcki. "How to Write a Flexbox Layout Engine." https://tchayen.com/how-to-write-a-flexbox-layout-engine
[4] Valve Corporation. "Improved Alpha-Tested Magnification for Vector Textures and Special Effects." 
[5] Casey Muratori. "Immediate-Mode Graphical User Interfaces (2005)." https://caseymuratori.com/blog_0001
