# Nebula Phase 3.8：渲染循环与 FrameArena 内嵌于 App

**作者**：Manus AI
**日期**：2026-04-24

## 1. 背景与目标

根据《Nebula 架构总纲领》，在 Phase 3.7 完成了管线层面的收敛后，应用层仍然存在大量重复的 WebGPU 样板代码（**张力 6**），并且 `FrameArena` 的生命周期未能被 `<App>` 有效接管（缺乏跨原语共享能力，**张力 5** 的前置障碍）。

**Phase 3.8 的核心目标是：**
1. 兑现 Phase 3.5 的承诺，实现统一的 `nebula_frame_render` 渲染循环封装。
2. 将 `NebulaArena` 内嵌进由 `nebula_derive_app` 生成的 `<App>` record 中。
3. 消除 `form_demo.nelua` 中手写的 50 行渲染样板代码，使主循环收缩至 3 行。

这不仅是一次代码清理，更是为 Phase 3.9（文本一等公民 + Slot Producer 重构）奠定必要的内存管理基础。

## 2. 核心原语设计

### 2.1 原语 5：渲染循环 `nebula_frame_render`

当前 `form_demo.nelua` 中的主循环充斥着 `wgpuSurfaceGetCurrentTexture`、`wgpuDeviceCreateCommandEncoder` 等底层调用。Phase 3.8 将在 `src/app.nelua` 中新增一个 Nelua 泛型函数：

```nelua
-- app.nelua
global function nebula_frame_render(
  renderer: *NebulaRenderer,
  app:      auto,           -- 泛型参数，接受任意由 app_factory 生成的 App 指针
  input:    *NebulaInputState,
  dt:       float32,
  clear_color: Color
): void
```

该函数内部将执行以下严格的时序：
1. **获取 Surface**：如果失败则直接返回。
2. **App Update**：调用 `app:update(input, dt)`。
3. **Arena Reset**：调用 `app.arena:reset()`（依赖 2.2 的内嵌）。
4. **创建 Render Pass**：使用传入的 `clear_color`。
5. **App Draw**：调用 `app:draw(pass)`。
6. **Submit & Present**：结束 pass，提交队列，呈现画面并释放资源。

### 2.2 原语 8：FrameArena 内嵌于 App

当前 `NebulaArena` 必须由开发者手动声明和初始化。Phase 3.8 将修改 `src/derive/app_factory.lua`，在生成的 `<App>` 中自动注入 Arena：

```nelua
-- 由 app_factory.lua 自动生成
global FormApp = @record{
  -- ... 现有字段
  arena: NebulaArena,
  _arena_backing: [2 * 1024 * 1024]uint8, -- 默认 2MB 后备内存
}

function FormApp:init(...)
  -- ... 现有管线初始化
  nebula_arena_init(&self.arena, &self._arena_backing[0], 2 * 1024 * 1024)
  return true
end
```

同时，在 `app_factory.lua` 中扩展 `nebula_app_begin` API，允许配置 Arena 容量：

```lua
nebula_app_begin("FormApp", { arena_size = 2 * 1024 * 1024 })
```

## 3. 执行计划

Phase 3.8 将分为 5 个子任务（Task），预计总耗时 2-3 天。

### Task 3.8.1：实现 `nebula_frame_render`

- **文件**：`src/app.nelua`（或新建 `src/frame_render.nelua`，考虑到 `app.nelua` 目前仅处理输入，可能需要重命名或扩展）。
- **内容**：将 `form_demo.nelua` 中的 WGPU 渲染循环提取为泛型函数。
- **注意**：由于 Nelua 泛型在 C 编译期的展开特性，`app:update` 和 `app:draw` 的调用将完美内联，无运行时虚函数开销。

### Task 3.8.2：`app_factory.lua` 注入 Arena

- **文件**：`src/derive/app_factory.lua`
- **内容**：修改 `gen_app_record` 和 `gen_app_init`，注入 `arena` 和 `_arena_backing`。
- **参数**：支持通过 `nebula_app_begin(name, opts)` 传入 `arena_size`（默认 2MB）。

### Task 3.8.3：重构 `form_demo.nelua` 与 `dynamic_list_demo.nelua`

- **文件**：`examples/form_demo.nelua`、`examples/dynamic_list_demo.nelua`
- **内容**：删除手写的渲染循环和独立的 Arena 声明，改用 `nebula_frame_render`。
- **特殊处理**：文本渲染管线（`pipe_email_text` 等）目前仍独立于 App 之外。在 Phase 3.9 将其纳入一等公民之前，Phase 3.8 允许在 `nebula_frame_render` 外部传递一个回调函数，或者暂时将文本渲染作为 `nebula_frame_render` 的一个可选 hook 参数。

> **架构折衷**：由于 Phase 3.9 才会彻底解决文本的编排问题，Task 3.8.1 设计 `nebula_frame_render` 时，需要支持一个可选的 `post_draw_cb: function(pass: WGPURenderPassEncoder)` 回调，用于在 `app:draw(pass)` 之后执行自定义的绘制（如文本绘制）。

### Task 3.8.4：更新测试套件

- **文件**：`tests/smoke_phase3_8.lua`（新增）
- **内容**：验证 `app_factory.lua` 是否正确生成了 Arena 字段和初始化代码。
- **回归**：运行 `tools/run_all_tests.sh` 确保编译通过。

### Task 3.8.5：代码收敛与提交

- **验证**：确保 `form_demo.nelua` 的代码行数大幅减少。
- **文档**：更新 `README.md`。

## 4. 风险与缓解

- **泛型实例化失败**：Nelua 的泛型要求传入的参数具有精确匹配的方法签名。
  - *缓解*：确保 `app_factory` 生成的 `update` 和 `draw` 签名严格一致。
- **Arena 容量不足**：2MB 默认值可能在某些极端测试下溢出。
  - *缓解*：在 `nebula_frame_render` 中添加对 `app.arena.peak` 的日志警告（如果接近 capacity）。

## 5. 结论

Phase 3.8 是一次承前启后的重构。它消除了最显眼的样板代码，并为后续的声明式文本编排（Phase 3.9）铺平了道路。严格执行本计划将确保 Nebula 在迈向 1.0 的过程中保持架构的纯洁性。
