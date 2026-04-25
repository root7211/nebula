# Phase 3.9 分析笔记

## 1. 架构纲领对 Phase 3.9 的定义
- **对应原语**：原语 3（编译期 Text 一等公民 `nebula_app_register_text`）+ 原语 4（插槽即 Arena Producer）
- **消除张力**：张力 4（App 编排与文本组件的二等公民身份）+ 张力 5（动态插槽依赖外部全局变量）
- **预估工期**：2 周
- **前置条件**：Phase 3.8（渲染循环封装 + FrameArena 内嵌）已完成

## 2. 当前文本子系统的二等公民问题（张力 4）

### 2.1 TextVisual 的派生路径
- `nebula_derive_text_visual` 在 `nebula_core.nelua:940` 定义
- 生成 `TextContext`（含 visual, sm, mesh, current_text_color）
- 生成 `TextContext:set_text(renderer, text)` — 构建顶点并上传 GPU
- 生成 `TextPipeline` — 使用 `text_vertex` 着色器路径

### 2.2 form_demo.nelua 中的手动编排（需消除的样板）
- **手动声明文本管线**（L289-293）：`pipe_email_text: TextPipeline` / `pipe_password_text: TextPipeline`
- **手动声明 TextContext**（L295-308）：`email_text: TextContext` / `password_text: TextContext`
- **手动调用 set_text**（L310-311）：初始化 placeholder
- **手动调用 process_text_input + set_text**（L331-354）：业务逻辑
- **独立渲染 pass**（L370-412）：因为文本不在 FormApp:draw 中，需要额外 40 行 WGPU 样板
  - 这是 Phase 3.8 无法消除的最后一块样板代码

### 2.3 app_factory.lua 中的半成品 metadata
- `has_text_buf` 和 `text_context` 字段在 `nebula_app_register_component` 中被注册
- 但 `gen_app_update` 完全没有使用这些字段
- `gen_app_draw` 也没有处理文本管线的绘制

## 3. 当前动态插槽的外部全局变量问题（张力 5）

### 3.1 nebula_app_register_slot 的实现
- 接受 `arena_var`, `count_var`, `data_var` 三个字符串参数
- 生成的 draw 代码直接引用外部全局变量：`while _si < item_count do _batch[_count] = item_instances[_si]`
- 开发者必须在 App 外部维护这些变量

### 3.2 dynamic_list_demo.nelua 的现状
- 完全不使用 `nebula_derive_app`
- 手动管理 Arena、手动 upload、手动渲染循环
- Phase 3.7 已迁移到 standard_instanced 路径，但编排仍是手动的

## 4. Phase 3.8 对 3.9 的前瞻性描述
- PLAN_PHASE3_8.md 第 87-89 行："文本渲染管线目前仍独立于 App 之外。在 Phase 3.9 将其纳入一等公民之前"
- form_demo.nelua 第 16-18 行注释："Phase 3.9 将文本纳入一等公民后，此限制将被彻底消除"
- form_demo.nelua 第 369 行注释："TODO Phase 3.9: 将文本管线纳入 FormApp，消除此独立 pass"
- nebula_frame_render 当前不支持 post_draw 回调（3.8 计划中提到但未实现）

## 5. 关键技术约束
- TextPipeline 使用 `text_vertex` 着色器路径，与标准 `standard_instanced` 路径不同
- TextPipeline 的 draw 方法是 `draw_buffer(pass, vertex_buffer, size, count)`，不是 `draw_instanced`
- TextContext:set_text 需要 `renderer` 指针（上传 GPU 缓冲区）
- 文本渲染需要共享的 NebulaAsciiFontAtlas（纹理 + sampler），目前由 TextPipeline:init 内部加载
- FrameArena 已内嵌在 App 中（Phase 3.8），可用于 L2 数据分配
- app_factory 的版本号：`nebula_app_factory_v0.2_phase3.8`

## 6. 纲领中原语 3 的设计蓝图
```lua
nebula_app_register_text("email_label", "TextVisual", {
    bound_to        = "email_input",
    placeholder     = "email",
    mask_password   = false,
})
```
自动在 update 中注入 process_text_input + set_text 逻辑
自动在 draw 中调用 pipe_text:draw_buffer

## 7. 纲领中原语 4 的设计蓝图
```lua
nebula_app_register_slot("list_items", "ListItemVisual", {
    max_instances = 10000,
    producer      = "compute_visible_items",
})
```
自动生成 Arena mark/rewind + producer 调用 + upload + draw_instanced
引入 NebulaSlotView 视图 Record
