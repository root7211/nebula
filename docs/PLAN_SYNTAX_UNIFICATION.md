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

## 问题与方案

### S1: nebula_main() 泛用生成器

**问题**：button_v2_demo 仍需手动编写完整 main 循环：`nebula_init` → `nebula_frame_begin` → 业务逻辑 → `nebula_frame_render` → `nebula_shutdown`。编辑器和终端都有 `nebula_*_main()` 全自动生成，但通用交互类没有。最简单的应用（按钮）反而比最复杂的应用（编辑器）需要更多样板代码。

**方案**：引入 `nebula_main()` 泛用生成器，接受编译期 `on_frame` 回调：

```lua
## nebula_main("ButtonApp", {
##   title = "Button V2 Demo",
##   width = 800, height = 600,
##   on_frame = function(app)
##     if app.btn.click.just_clicked then printf("clicked!\n") end
##   end,
## })
```

`on_frame` 是编译期 Lua 函数，接收 app 类型定义，直接在生成的 main 函数体中插入代码。不需要字符串模板拼接。生成的等价 Nelua 代码：

```nelua
local function main(): int32
  local renderer: NebulaRenderer
  local app: ButtonApp
  if not nebula_init(&renderer, &app, "Button V2 Demo", 800, 600) then return 1 end
  app:init_themed()  -- 如果 on_init 存在则调用
  local input: NebulaInputState
  while not nebula_should_close() do
    local dt = nebula_frame_begin(&input)
    -- on_frame 回调代码注入于此
    if app.btn.click.just_clicked then printf("clicked!\n") end
    nebula_frame_render(&renderer, &app, &input, dt, 0.09, 0.09, 0.10)
  end
  app:deinit()
  nebula_shutdown(&renderer)
  return 0
end
main()
```

**实现**：在 `nebula_core.nelua` 中新增 `nebula_main` 函数（编译期），解析 opts.title/width/height/on_frame/on_init，生成完整 main 函数。

**验证**：用 `nebula_main()` 重写 button_v2_demo，目标 ≤15 行。

### S2: components DSL 简化

**问题**：components 数组中三种语义层次交叉出现——`type` 是类型引用，`dense` 是渲染管线配置，`builtin` 是行为绑定。用户需要知道每个 builtin 的默认 dense 值才能写出正确的声明。

**方案**：`builtin` 隐含默认 `dense` 值，用户无需显式声明。

```lua
-- 之前：用户需要知道 edit_area 的默认 dense 是 6006
{ name = "edit_area", dense = 6006, builtin = "edit_area", flex_grow = 1 }

-- 之后：builtin 自动推导 dense
{ name = "edit_area", builtin = "edit_area", flex_grow = 1 }
```

内置默认值表：

| builtin | 默认 dense | 说明 |
|---------|-----------|------|
| `edit_area` | 6006 | 200行 × 30字符（含宽字符余量） |
| `line_nums` | 250 | 250行行号 |
| `status_bar` | 200 | 单行状态栏 |
| `search_bar` | 256 | 单行搜索栏 |
| `term_grid` | 6000 | 200行 × 30列终端网格 |

**向后兼容**：显式 `dense = N` 仍然生效，覆盖默认值。

**实现**：在 `nebula_app()` 第一个 layout 循环中，检测 `c.builtin` 且无 `c.dense` 时，从默认值表填充。

## 不做的事情

**`##` 前缀不是问题。** Nelua 的 `##` 和 Zig 的 `comptime`、Rust 的 `macro` 本质一样——编译期计算的标记。所有使用元编程的语言都有这个视觉噪声，但没有哪个框架把它当成待解决的问题。`.nebula` 配置文件格式（JSON/TOML）的提议更不可取：引入第二语言增加心智负担，JSON 无法表达回调，本质上是在讨论给 Nelua 写前端，远超本阶段范围。

## 实施节奏

S1 单独做，验证通过后再做 S2。不同时提交。

1. **S1 commit**: `nebula_main()` 生成器 + button_v2_demo 重写（目标 ≤15 行）+ regression
2. **S2 commit**: builtin 默认 dense 值 + 三端 demo 验证 + regression

## 验证标准

- [ ] button_v2_demo 使用 `nebula_main()` 后 ≤15 行
- [ ] text_editor_demo_v3 / term_demo_v2 不受影响（回归通过）
- [ ] 所有 demo 中显式 `dense = N` 仍然生效（向后兼容）
- [ ] `builtin = "edit_area"` 不写 `dense` 时自动推导正确值
- [ ] 77/77 回归测试全绿
