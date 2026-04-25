# Nebula Phase 3.9：文本一等公民与 Slot Producer 重构

**作者**：Manus AI
**日期**：2026-04-25
**前置**：Phase 3.8（渲染循环封装与 FrameArena 内嵌）已完成
**对应纲领**：`ARCHITECTURE_GRAND_PLAN.md` 原语 3（编译期 Text 一等公民）与原语 4（插槽即 Arena Producer）
**消除张力**：张力 4（App 编排与文本组件的二等公民身份）与张力 5（动态插槽依赖外部全局变量）
**预估工期**：2 周

---

## 1. 背景与目标

在 Phase 3.8 中，Nebula 成功实现了 `nebula_frame_render` 渲染循环的泛型封装，并将 `FrameArena` 自动内嵌于 `App` record 中 [1]。这一重构将 `form_demo.nelua` 的主循环从 50 行 WGPU 样板代码收缩至 3 行。然而，由于文本渲染管线（`TextPipeline`）和动态插槽（Slot）的编排机制尚未完善，应用层仍残留着大量手动编排的样板代码。

**当前架构面临的两大核心痛点：**

1.  **文本组件的二等公民身份（张力 4）**：在 `form_demo.nelua` 中，开发者必须手动声明 `TextPipeline` 和 `TextContext`，手动调用 `set_text` 初始化占位符，并在主循环中手动处理 `process_text_input` 逻辑。更严重的是，由于文本管线未被纳入 `FormApp:draw` 的自动生成逻辑中，开发者不得不在 `nebula_frame_render` 之后手写一个长达 40 行的独立 Render Pass 来绘制文本 [2]。这不仅破坏了 `nebula_frame_render` 的封装性，也违反了"声明意图，自动派生"的框架哲学。
2.  **动态插槽依赖外部全局变量（张力 5）**：当前的 `nebula_app_register_slot` API 要求开发者提供 `arena_var`、`count_var` 和 `data_var` 三个字符串参数，生成的 `draw` 代码直接引用这些外部全局变量 [3]。这意味着开发者必须在 App 外部手动维护 Arena 的生命周期和数据填充逻辑，导致 `dynamic_list_demo.nelua` 完全无法使用 `nebula_derive_app` 宏，只能退回到全手动编排的原始状态 [4]。

**Phase 3.9 的核心目标是：**

1.  **实现原语 3（编译期 Text 一等公民）**：引入 `nebula_app_register_text` API，将文本组件的输入处理、状态同步和渲染管线全面纳入 `app_factory.lua` 的自动编排中，彻底消除 `form_demo.nelua` 中剩余的 40 行独立渲染 Pass。
2.  **实现原语 4（插槽即 Arena Producer）**：重构 `nebula_app_register_slot` API，引入 `NebulaSlotView` 视图 Record，将动态插槽的数据生产逻辑从"外部全局变量"转变为"App 内部托管的 Producer 函数"，使 `dynamic_list_demo.nelua` 能够全面接入 `nebula_derive_app` 体系。

---

## 2. 核心原语设计

### 2.1 原语 3：编译期 Text 一等公民

为了将文本组件提升为一等公民，Phase 3.9 将在 `src/derive/app_factory.lua` 中引入全新的注册 API `nebula_app_register_text`。该 API 允许开发者以声明式的方式将文本标签绑定到输入组件上。

**API 签名设计：**

```lua
nebula_app_register_text("email_label", "TextVisual", {
    bound_to        = "email_input",   -- 绑定到某个 editable 组件
    placeholder     = "email",         -- 默认占位符文本
    mask_password   = false,           -- 是否掩码显示（如密码框）
})
```

**自动生成的代码结构：**

1.  **Record 注入**：在生成的 `<App>` record 中自动注入 `email_label: TextContext` 和共享的 `pipe_text: TextPipeline`。
2.  **Init 注入**：在 `<App>:init` 中自动调用 `pipe_text:init(renderer)`，并初始化 `email_label` 的默认文本（调用 `set_text`）。
3.  **Update 注入**：在 `<App>:update` 中自动生成输入处理与状态同步逻辑。当绑定的输入组件内容发生变化时，自动更新文本标签：

```nelua
-- 由 app_factory.lua 自动生成于 <App>:update
if self.email_input:process_text_input(input) then
  if self.email_input:get_text_len() > 0 then
    -- 使用内嵌的 FrameArena 分配临时缓冲区，修复 L1/L2 渗透
    local _flat_buf: [256]uint8
    local _text = self.email_input:get_text(&_flat_buf[0], 255)
    -- 如果 mask_password 为 true，则在此处生成掩码逻辑
    self.email_label:set_text(self.renderer, _text)
  else
    self.email_label:set_text(self.renderer, "email")
  end
end
```

4.  **Draw 注入**：在 `<App>:draw` 中自动调用 `pipe_text:draw_buffer`，将文本渲染无缝集成到主 Render Pass 中。

### 2.2 原语 4：插槽即 Arena Producer

为了消除动态插槽对外部全局变量的依赖，Phase 3.9 将重构 `nebula_app_register_slot` API，引入 `producer` 概念。开发者只需提供一个纯函数（Producer），框架将自动处理 Arena 的内存分配与回收。

**API 签名设计：**

```lua
nebula_app_register_slot("list_items", "ListItemVisual", {
    max_instances = 10000,
    producer      = "compute_visible_items",  -- 用户实现的纯函数名
})
```

**NebulaSlotView 视图 Record：**

在 `src/nebula_core.nelua` 中新增泛型视图 Record，用于在 App 和 Producer 之间传递数据：

```nelua
global NebulaSlotView = @record{T: type}
  data:  *[0]T,
  count: uint32,
  max:   uint32,
end
```

**自动生成的代码结构：**

在 `<App>:draw` 中，框架将自动生成 Arena 的 `mark/rewind` 逻辑，并调用用户提供的 Producer 函数：

```nelua
-- 由 app_factory.lua 自动生成于 <App>:draw
do
  local _arena_mark = self.arena:mark()
  local _slot_data = (@*[0]ListItemUniforms)(nebula_arena_alloc(&self.arena, 10000 * #ListItemUniforms))
  local _slot = NebulaSlotView(ListItemUniforms){ data = _slot_data, count = 0, max = 10000 }
  
  -- 调用用户提供的 Producer 函数，填充 _slot.data 并更新 _slot.count
  compute_visible_items(&self, &self.arena, &_slot)
  
  if _slot.count > 0 then
    self.pipe_listitem:upload(self.renderer, _slot.data, _slot.count)
    self.pipe_listitem:draw_instanced(pass, _slot.count)
  end
  
  self.arena:rewind(_arena_mark)
end
```

这种设计使得动态插槽与静态组件在 App 层面拥有完全相同的接口，所有 L2 状态都被 App 自身托管，彻底贯彻了公理 B（生命周期严格分层原则）[5]。

---

## 3. 执行计划

Phase 3.9 将分为 4 个子任务（Task），预计总耗时 2 周。

### Task 3.9.1：实现 `nebula_app_register_text`（Day 1-3）

*   **文件**：`src/derive/app_factory.lua`
*   **内容**：
    *   新增 `nebula_app_register_text` API，解析 `bound_to`、`placeholder` 和 `mask_password` 参数。
    *   修改 `gen_app_record`，自动注入 `TextContext` 和 `TextPipeline`。
    *   修改 `gen_app_init`，自动初始化文本管线和占位符。
    *   修改 `gen_app_update`，生成 `process_text_input` 和 `set_text` 的联动逻辑。注意使用栈上数组或 `FrameArena` 作为临时缓冲区，避免 L1/L2 渗透。
    *   修改 `gen_app_draw`，在所有 `standard_instanced` 管线绘制完成后，统一调用 `TextPipeline:draw_buffer`。

### Task 3.9.2：重构 `form_demo.nelua`（Day 4-5）

*   **文件**：`examples/form_demo.nelua`
*   **内容**：
    *   使用 `nebula_app_register_text` 替换手动声明的文本组件。
    *   删除主循环中手写的 `process_text_input` 业务逻辑。
    *   **关键**：删除 `nebula_frame_render` 之后长达 40 行的独立 Render Pass 代码。
    *   验证表单的输入、焦点切换、掩码显示等功能是否正常工作。

### Task 3.9.3：实现 Slot Producer 重构（Day 6-8）

*   **文件**：`src/derive/app_factory.lua`、`src/nebula_core.nelua`
*   **内容**：
    *   在 `nebula_core.nelua` 中定义 `NebulaSlotView` 泛型 Record。
    *   修改 `nebula_app_register_slot` API，废弃 `arena_var`、`count_var`、`data_var`，引入 `producer` 参数。
    *   修改 `gen_app_draw`，生成 `arena:mark()`、`nebula_arena_alloc`、调用 Producer 函数、`upload` + `draw_instanced` 以及 `arena:rewind()` 的完整逻辑。

### Task 3.9.4：重构 `dynamic_list_demo.nelua`（Day 9-10）

*   **文件**：`examples/dynamic_list_demo.nelua`
*   **内容**：
    *   引入 `nebula_derive_app` 宏，使用 `nebula_app_begin` 和 `nebula_app_register_slot` 声明应用结构。
    *   将原有的列表项计算逻辑提取为独立的纯函数 `compute_visible_items(app: *ListApp, arena: *NebulaArena, slot: *NebulaSlotView(ListItemUniforms))`。
    *   删除手动维护的 `NebulaArena` 和渲染循环，全面改用 `nebula_frame_render`。
    *   验证动态列表的滚动、裁剪和 Hover 高亮功能是否正常工作，且无内存泄漏。

---

## 4. 风险与缓解

*   **文本渲染顺序问题**：文本通常需要渲染在所有背景组件之上。如果 `gen_app_draw` 的生成顺序不当，可能导致文本被遮挡。
    *   *缓解*：在 `gen_app_draw` 中，强制将所有 `TextPipeline` 的绘制逻辑放置在生成的代码末尾，确保文本始终位于最上层。
*   **Producer 函数签名匹配**：Nelua 是强类型语言，如果生成的 Producer 调用签名与用户定义的函数不匹配，将导致编译失败。
    *   *缓解*：在文档和示例中明确规定 Producer 函数的标准签名，并在 `app_factory.lua` 生成代码时添加清晰的注释，指导开发者如何实现该函数。
*   **Arena 内存碎片**：如果 Producer 函数内部进行了额外的 Arena 分配，且未正确管理生命周期，可能导致内存泄漏。
    *   *缓解*：`gen_app_draw` 中生成的 `arena:mark()` 和 `arena:rewind()` 机制能够确保单次 Draw 调用内的所有临时分配在结束后被完全回收，从架构层面杜绝了此类泄漏。

## 5. 结论

Phase 3.9 是 Nebula 迈向完全声明式编排的关键一步。通过将文本组件提升为一等公民并重构动态插槽机制，我们彻底消除了应用层残留的 WGPU 样板代码和全局变量依赖。这不仅大幅降低了开发者的心智负担，也使得 `form_demo` 和 `dynamic_list_demo` 能够以最纯粹、最优雅的形态展现 Nebula 的架构哲学。

---

## 参考文献

[1] `docs/PLAN_PHASE3_8.md` — Nebula Phase 3.8：渲染循环与 FrameArena 内嵌于 App。
[2] `examples/form_demo.nelua` — Phase 3.8 综合演示，包含手动编排的文本管线和独立 Render Pass。
[3] `src/derive/app_factory.lua` — 编译期显式编排工厂，包含当前的 `nebula_app_register_slot` 实现。
[4] `examples/dynamic_list_demo.nelua` — 动态列表演示，目前完全绕过 `nebula_derive_app`。
[5] `docs/ARCHITECTURE_GRAND_PLAN.md` — Nebula 架构总纲领，定义了原语 3 和原语 4 的设计蓝图。
