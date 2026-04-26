# Phase 4.3 实施方案：拓扑流渲染 (Indirect Drawing)

**目标**：引入 GPU 驱动的间接绘制（Indirect Drawing），将 CPU 端的显式 Draw Call 替换为 GPU 端维护的 Indirect Buffer，实现真正的动态拓扑变化，大幅降低 CPU 提交开销。

## 1. 架构背景与张力

在 Nebula 当前的架构中（Phase 3.10.5），虽然已经实现了基于 Storage Buffer 的实例渲染（Instanced Rendering），但渲染的控制权依然牢牢掌握在 CPU 手中。对于每个 Visual 类型，CPU 需要在每帧遍历其所有实例，计算存活数量，并显式调用 `wgpuRenderPassEncoderDraw`。

随着 UI 复杂度的增加，特别是当引入复杂的动画、滚动列表或大量动态生成的组件时，CPU 端的遍历和 Draw Call 提交将成为性能瓶颈。为了兑现 v3 白皮书中“拓扑流渲染”的愿景，我们需要将这部分工作卸载到 GPU。

## 2. 实施路径

### 2.1 S1 阶段：管线与着色器重构

在编译阶段，我们需要生成支持 Indirect Drawing 的 WebGPU 管线和着色器。

- **着色器扩展**：在 `src/derive/shader_compose.lua` 中，扩展现有的 `nebula_compose_shader_instanced`。新增一个 Compute Shader，用于执行视锥体剔除（Frustum Culling）和状态检查。
- **管线工厂更新**：在 `src/derive/pipeline_factory.lua` 中，修改 `gen_pipeline_standard_instanced` 路径。除了原有的 Render Pipeline，还需要生成一个 Compute Pipeline。
- **Buffer 布局调整**：除了存储实例数据的 Storage Buffer，还需要创建一个 `WGPUBufferUsage_Indirect` 类型的 Buffer，用于存储 Compute Shader 生成的绘制参数（如 `vertexCount`, `instanceCount`, `firstVertex`, `firstInstance`）。

### 2.2 S2 阶段：GPU 驱动的渲染循环

在运行阶段，CPU 的职责将大幅简化，主要负责触发 Compute Pass 和 Render Pass。

- **Compute Pass 调度**：在每帧渲染前，CPU 调度 Compute Shader。Compute Shader 遍历所有实例数据，判断其是否可见且处于激活状态。如果可见，则将其索引写入一个紧凑的可见实例数组，并原子地递增 Indirect Buffer 中的 `instanceCount`。
- **Render Pass 提交**：CPU 不再调用 `wgpuRenderPassEncoderDraw`，而是调用 `wgpuRenderPassEncoderDrawIndirect`，将 Indirect Buffer 作为参数传入。GPU 将根据 Compute Shader 写入的参数自动执行绘制。
- **数据同步优化**：为了配合 Indirect Drawing，CPU 侧的数据结构需要更加扁平化（Data-Oriented Design），以便通过一次 `wgpuQueueWriteBuffer` 将所有实例状态批量上传给 GPU。

## 3. 验收标准

1. **性能提升**：在包含 100,000 个动态组件的场景中，CPU 端的渲染提交时间显著降低，整体帧率提升至少 30%。
2. **功能等价性**：所有现有的 UI 组件（如按钮、输入框、动态列表）在 Indirect Drawing 模式下渲染结果与之前完全一致。
3. **剔除正确性**：视锥体剔除逻辑在 Compute Shader 中正确执行，屏幕外的组件不会被绘制。
4. **代码精简**：`app_factory.lua` 生成的 `<App>:draw` 函数中，针对每个 Visual 类型的显式循环和条件判断被移除，代码更加简洁。
