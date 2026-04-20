# Phase 2.3 开发计划：渲染管线工厂自动派生 (Pipeline Derivation)

> **总目标**：让 `nebula_derive` 编译期推导引擎能够为每个 `Visual` 规格自动生成专属的 `Uniforms` 布局、`Shader` 着色器常量和 `Pipeline` 渲染管线结构体。通过这一阶段，彻底消除 `renderer.nelua` 中对 `NebulaRectUniforms` 和 `RECT_SHADER_WGSL` 的硬编码依赖，实现真正的"形即渲染"（Shape-Is-Rendering）架构。

---

## 1. 现状与挑战

在 Phase 2.1 和 2.2 中，我们已经实现了 Uniform 布局的自动化（std140 规则）和 WGSL 着色器的按字段组合。然而，目前的架构仍然存在一个核心的**运行时耦合**：

在 `renderer.nelua` 中，所有渲染操作仍然依赖于一个硬编码的 `NebulaRectPipeline` 和一个兼容性的 96 字节 `NebulaRectUniforms`（使用 `force_viewport_align=16` 维持历史布局）。这意味着无论开发者声明了怎样极简的 `Visual`（如无圆角、无边框的 `SimpleRectVisual`），底层的管线和内存布局仍然是基于"最大公约数"的矩形规格构建的。

**Phase 2.3 的核心任务**是打破这种大一统的管线设计，让编译器为每个具体的 `Visual` 生成**量身定制的紧凑管线**：
- **专属布局**：每个 `Visual` 拥有自己严格按 std140 紧凑排列的 `<T>Uniforms`（例如 `ButtonUniforms` 为 80 字节），不再为了兼容性强行填充 `_pad`。
- **专属着色器**：每个 `Visual` 拥有自己按需组合的 `<T>Shader` 常量字符串。
- **专属管线**：每个 `Visual` 拥有自己的 `<T>Pipeline` 结构体，独立管理 WGPU 资源。

---

## 2. 技术方案

### 2.1 模块化架构

为了避免 `nebula_core.nelua` 的代码过度膨胀，我们将管线代码生成逻辑独立封装为 `src/derive/pipeline_factory.lua` 模块。该模块只负责生成 Nelua 源码字符串，由 `nebula_core.nelua` 统一进行 AST 注入。

```text
src/
├── nebula_core.nelua          # 集成入口：扩展 nebula_derive
└── derive/
    ├── shader_compose.lua     # (Phase 2.2) WGSL 着色器组合器
    └── pipeline_factory.lua   # (Phase 2.3) 管线代码生成器
```

### 2.2 核心 API 改造

在 `src/derive/pipeline_factory.lua` 中实现以下生成器：

1. **`nebula_gen_pipeline_source`**：生成 `<T>Pipeline` 的完整结构体及 `init`、`update_uniforms`、`draw` 方法。
2. **`nebula_gen_to_uniforms_typed`**：生成强类型的 `<T>Context:to_uniforms` 方法，返回紧凑布局的 `<T>Uniforms`。

在 `src/renderer.nelua` 中，抽取公共的 WGPU 管线创建基础设施：

```nelua
global function nebula_pipeline_base_init(
  out_pipeline:    *WGPURenderPipeline,
  out_bind_layout: *WGPUBindGroupLayout,
  out_uniform_buf: *WGPUBuffer,
  out_bind_group:  *WGPUBindGroup,
  renderer:        *NebulaRenderer,
  wgsl_source:     cstring,
  uniform_size:    csize,
  label:           cstring
): boolean
```

所有派生的 `<T>Pipeline:init` 都将委托调用 `nebula_pipeline_base_init`，从而避免在每个派生管线中重复 200 行 WGPU 样板代码。

### 2.3 派生流程扩展

当开发者调用 `## nebula_derive("ButtonVisual")` 时，编译期的行为将扩展为：

1. **(Phase 1)** 生成 `ButtonState` 枚举和 `ButtonStateMachine` 记录。
2. **(Phase 2.3)** 生成紧凑的 `ButtonUniforms` 记录（无 `force_viewport_align`）。
3. **(Phase 2.3)** 组合出 `ButtonShader` WGSL 常量字符串。
4. **(Phase 2.3)** 生成 `ButtonPipeline` 记录及相关方法。
5. **(Phase 1/2.3)** 生成 `ButtonContext` 记录，并注入强类型的 `to_uniforms` 方法。

---

## 3. 实施步骤

### 第一阶段：公共基础设施抽取 (Sub-phase 2.3.1)

1. 在 `src/renderer.nelua` 中，新增 `nebula_pipeline_base_init` 函数，封装 WGPU 管线、布局和缓冲区的创建逻辑。
2. 暂时保留 `NebulaRectUniforms` 和 `NebulaRectPipeline` 作为过渡，验证抽取后的逻辑是否正确。

### 第二阶段：管线工厂模块开发 (Sub-phase 2.3.2)

1. 创建 `src/derive/pipeline_factory.lua`。
2. 实现 `nebula_gen_pipeline_source`，生成调用 `nebula_pipeline_base_init` 的 `<T>Pipeline` 代码。
3. 实现 `nebula_gen_to_uniforms_typed`，生成返回 `<T>Uniforms` 的 `to_uniforms` 方法。

### 第三阶段：集成与解耦 (Sub-phase 2.3.3)

1. 修改 `src/nebula_core.nelua`，在 `nebula_derive` 中集成 `pipeline_factory`。
2. 移除 `src/renderer.nelua` 中的 `NebulaRectUniforms`、`RECT_SHADER_WGSL` 和 `NebulaRectPipeline`。
3. 更新 `examples/button_demo.nelua`、`login_demo.nelua` 和 `simple_rect_demo.nelua`，使用派生的 `<T>Pipeline`。

### 第四阶段：测试回归修复 (Sub-phase 2.3.4)

1. 随着 `NebulaRectUniforms` 被移除，`tools/headless_test.c` 将失去依赖。
2. 更新 `tools/export_shader_fixture.nelua`，基于 `ButtonVisual` 的紧凑布局（80 字节）重新生成 `fixture_shader.h`。
3. 调整 `headless_test.c`，使用新的紧凑布局和偏移量进行像素回归测试。

---

## 4. 验收标准

1. **代码清理**：`src/renderer.nelua` 中不再包含任何以 `Rect` 命名的 Uniform 或 Pipeline 结构，完全成为通用的 WebGPU 渲染器封装。
2. **强类型管线**：`examples/login_demo.nelua` 中的 `Card`、`Input`、`Button` 组件分别使用独立派生的 `CardPipeline`、`InputPipeline` 和 `ButtonPipeline`。
3. **紧凑布局验证**：`examples/uniform_layout_test.nelua` 仍然通过，证明 `ButtonUniforms` 的大小严格为 80 字节（紧凑模式），不再是 96 字节。
4. **编译期日志**：`nebula_derive` 的输出必须包含 Uniforms、Shader 和 Pipeline 的生成确认，例如：
   ```text
   [derive] ButtonVisual: emit State + StateMachine + Context + Uniforms + Shader + Pipeline (3 props, 4 transitions)
   ```
5. **回归测试**：`tools/headless_test.c` 编译通过，且离线渲染的 PPM 图像与 Phase 2.2 的基线在视觉上保持一致。

---

## 5. 风险提示

- **Nelua 方法覆盖机制**：在 `nebula_derive` 中，我们通过 AST 注入新的 `to_uniforms` 方法。需要确认 Nelua 编译器是否允许同名方法在同一个作用域内覆盖，或者我们需要在生成时避免产生重复的方法定义。
- **管线切换开销**：在 Phase 2.3 之后，不同类型的 `Visual`（即使着色器内容相同）也会拥有不同的 WGPU Pipeline 对象。在 `login_demo` 等多组件场景中，频繁的 `wgpuRenderPassEncoderSetPipeline` 可能会带来微小的 CPU 开销。这是架构解耦的必然代价，可在后续阶段通过 Pipeline 缓存池进行优化。
- **C 互操作断层**：`headless_test.c` 强依赖于 C 结构体的内存布局。当我们从 96 字节兼容布局切换到 80 字节紧凑布局时，必须确保 `fixture_shader.h` 中的 C 结构体与 Nelua 派生的 record 在内存上严格对齐，否则会导致渲染花屏。

---

## 6. 不在 Phase 2.3 范围

- **原语内联展开 (Primitive Inlining)**：`HoverableState:update` 的 AABB 碰撞检测内联推迟至 Phase 2.4。
- **多 Pass 渲染 (Shadow)**：虽然架构上已支持，但具体的阴影模糊 Pass 实现和 `shadow_demo.nelua` 推迟至 Phase 2.4 或之后。
- **管线缓存优化**：相同着色器的 Pipeline 实例去重不在此阶段考虑。

---

## 7. 新增/修改文件清单

| 文件 | 变更类型 | 用途 |
|---|---|---|
| `src/derive/pipeline_factory.lua` | 新增 | 管线代码生成器模块 |
| `src/nebula_core.nelua` | 修改 | 集成 pipeline_factory，扩展 nebula_derive |
| `src/renderer.nelua` | 重构 | 抽取公共 init，移除硬编码的 Rect 管线 |
| `examples/*.nelua` | 修改 | 迁移至专属 Pipeline |
| `tools/export_shader_fixture.nelua` | 修改 | 切换至基于 ButtonVisual 的紧凑布局导出 |
| `tools/headless_test.c` | 修改 | 适配紧凑布局的 C 结构体 |
