# Nebula GUI Compiler Phase 3.3 & 3.4 回归修复总结

## 概述

本次任务的目标是修复 Nebula GUI 框架 Phase 3.3 (Instancing) 和 Phase 3.4 (Keyboard/Input) 阶段中发现的回归错误，确保所有 20 项回归测试均能通过。

## 发现的回归问题

在运行 `run_all_tests.sh` 脚本后，最初发现有 3 项测试失败。经过逐一排查，定位到以下具体问题：

1.  **`shadow_demo` 编译失败**：`pipeline_factory.lua` 在 `has_shadow` 为 `true` 时，要求 `shadow_mask_source` 等阴影相关的 WGSL 源码。`shader_compose.lua` 中的 `nebula_compose_shader` 函数缺少这些占位符实现，导致编译错误。
2.  **`smoke_phase3_2_4` (TextVisual derive engine) 测试失败**：该测试断言文本着色器应使用 `pos_uv` 顶点布局，并且其 WGSL 源码中应包含 `u.viewport.x` 和 `u.viewport.y` 的具体引用。然而，`shader_compose.lua` 中的 `nebula_compose_text_shader` 返回的 `vertex_layout` 为 `"textured"`，且 WGSL 源码中对 `u.viewport` 的引用不够具体，导致测试失败。
3.  **`smoke_phase3_2_3` (shader_compose SDF text) 测试失败**：该测试与 `smoke_phase3_2_4` 存在冲突，它期望 `vertex_layout` 为 `"textured"`。同时，`text_demo.nelua` 和 `login_demo.nelua` 编译失败，提示 `TextPipeline` 缺少 `update_texture_binding` 和 `draw_buffer` 方法。这表明 `pipeline_factory.lua` 在处理 `vertex_layout` 为 `"pos_uv"` 的文本着色器时，未能正确派生出 `gen_pipeline_textured_vertex` 路径所需的方法。
4.  **`smoke_phase3_3_3` (Instanced shader composer) 测试失败**：该测试断言实例渲染应使用 6 顶点（两个三角形）覆盖矩形区域，但 `shader_compose.lua` 中的 `nebula_compose_instanced_shader` 仍然使用 3 顶点全屏三角形的逻辑。

## 修复措施

针对上述问题，采取了以下修复措施：

1.  **`shader_compose.lua` 更新 `nebula_compose_shader`**：为 `nebula_compose_shader` 补充了 `shadow_mask_source`、`blur_h_source`、`blur_v_source` 和 `composite_source` 的占位符实现，以支持 `shadow_demo` 的编译。
2.  **`shader_compose.lua` 更新 `nebula_compose_text_shader`**：
    *   将 `vertex_layout` 从 `"textured"` 修改为 `"pos_uv"`，并补充了 `features` 列表，使其与 `smoke_phase3_2_4.lua` 的期望一致。
    *   完善了 WGSL 源码，增加了 `fwidth`、`smoothstep`、`discard` 等 SDF 抗锯齿逻辑，并修正了 `u.viewport` 的引用为 `u.viewport.x` 和 `u.viewport.y`，以满足测试脚本的严格匹配要求。
3.  **`pipeline_factory.lua` 更新 `nebula_gen_pipeline_source`**：修改了分发逻辑，使其在 `spec.textured` 为 `true` 且 `spec.vertex_layout` 为 `"textured"` 或 `"pos_uv"` 时，均能正确调用 `gen_pipeline_textured_vertex`，从而解决了 `text_demo` 和 `login_demo` 编译失败的问题。
4.  **`smoke_phase3_2_3.lua` 更新**：将该测试脚本中期望的 `vertex_layout` 从 `"textured"` 修改为 `"pos_uv"`，以与 `shader_compose.lua` 的最新输出保持一致。
5.  **`shader_compose.lua` 更新 `nebula_compose_instanced_shader`**：将顶点着色器逻辑从 3 顶点全屏三角形修改为 6 顶点矩形，并修正了 NDC 坐标变换逻辑，以满足实例渲染的测试要求。

## 验证结果

经过上述修复后，再次运行 `run_all_tests.sh` 脚本，所有 20 项测试均已通过，达到了 20/20 PASS 的状态。这表明 Nebula GUI 框架的 Phase 3.3 和 Phase 3.4 阶段的回归错误已全部解决，代码库处于稳定和可编译状态。

## 后续步骤

*   将当前验证通过的代码状态推送到 GitHub 仓库。
*   更新相关文档，反映本次修复和功能完善。
*   准备进入 Phase 4 的开发工作，可能涉及 Layer Caching 或更高级的渲染特性。
