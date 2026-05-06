# Nebula Sugar 语法统一化计划

> Phase 4.6 — API Unification & Ergonomics
> 基于 term_demo_v2 / text_editor_demo_v3 / button_v2_demo 三端验证结论

## 现状评估

Sugar 体系在编辑器和终端场景已达到极高完成度，但整体存在结构性不一致。

### 压缩比成果

| Demo | v1 行数 | Sugar 行数 | 压缩比 | main 生成 |
|------|---------|-----------|--------|-----------|
| text_editor_demo_v3 | 886 | 19 | 46.6x | `nebula_editor_main()` 全自动 |
| term_demo_v2 | 489 | 32 | 15.3x | `nebula_terminal_main()` 全自动 |
| button_v2_demo | 147 | 33 | 4.5x | **手写 main()** |

### 问题 1: main() 生成的不对称

button_v2_demo 仍需手动编写完整 main 循环：`nebula_init` → `nebula_frame_begin` → 业务逻辑 → `nebula_frame_render` → `nebula_shutdown`。

编辑器和终端都有 `nebula_*_main()` 全自动生成，但通用交互类应用没有。这导致：
- 最简单的应用（按钮）反而比最复杂的应用（编辑器）需要更多样板代码
- 新用户从 button demo 入门时，体验到的抽象层级低于实际能力

**建议**: 引入 `nebula_interactive_main()` 或泛用 `nebula_main()`，接受一个可选的 `on_frame` 回调表：

```
## nebula_main("ButtonApp", {
##   title = "Button V2 Demo",
##   width = 800, height = 600,
##   on_frame = function(app_type)
##     return [[
##       if app.btn.click.just_clicked then printf("clicked!\n") end
##     ]]
##   end,
## })
```

这样 button_v2_demo 可以降到 ~10 行。

### 问题 2: `##` 前缀的认知负担

Nelua 的 `##` 是语言层决定，Nebula 无法改变。但现实是：

- text_editor_demo_v3: 19 行中 17 行以 `##` 开头
- term_demo_v2: 32 行中 14 行以 `##` 开头

用户面对的是"两种语言混写"的视觉体验。这不是 bug，但限制了框架作为声明式 GUI 工具的易用性上限。

**建议**: 
- 文档中明确解释 `##` = "编译期声明"的心智模型
- 考虑是否能提供一个 `.nebula` 配置文件格式（JSON/TOML），让纯声明部分脱离 `##` 语法
- 短期内：确保所有 demo 的 `##` 块集中在文件顶部，运行时代码在底部，避免交错

### 问题 3: components DSL 一致性

当前 components 数组中三种模式混用：

```lua
{ name = "editor",      type = "EditorBgVisual" }        -- 类型引用
{ name = "edit_area",   dense = 6000, builtin = "edit_area" }  -- 内置 Producer
{ name = "editor_body", row = true, flex_grow = 1, children = {...} }  -- 布局容器
```

`dense` 是渲染管线配置，`builtin` 是行为绑定，`type` 是类型引用——三个不同语义层次在同一数组里交叉出现。

**建议**:
- `dense` 应作为 `builtin` 的隐含属性，由框架根据 builtin 类型自动推导默认值
- 用户仍可显式覆盖 `dense` 值，但不应强制声明
- 例如 `builtin = "edit_area"` 应隐含 `dense = 4096`（可配置默认值）

## 实施路径

### S1: nebula_main() 泛用生成器
- 在 `nebula_core.nelua` 中新增 `nebula_main()` 函数
- 接受 `on_frame` 回调，生成标准 main 循环
- 用它重写 button_v2_demo，验证压缩比

### S2: components DSL 简化
- builtin Producer 自带默认 dense 值
- 用户只需写 `{ name = "edit_area", builtin = "edit_area", flex_grow = 1 }`
- 向后兼容：显式 `dense = N` 仍然生效

### S3: 文档与开发者体验
- 编写 5 分钟 quickstart guide
- 用 quickstart 的解释成本测试 API 可理解性
- 如果解释超过 1 页，说明抽象层还不够

## 验证标准

- button_v2_demo 降到 ≤15 行
- 新用户（不了解 Nelua）能在 5 分钟内理解 demo 结构
- 所有应用类型（按钮/编辑器/终端）使用统一的 `nebula_app` + `nebula_*_main` 模式
