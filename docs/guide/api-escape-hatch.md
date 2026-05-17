# API 降级指南（Escape Hatch）

Nebula 提供三层 API，高层无法满足需求时可随时降级到低层，无需重写。三层可在同一项目中混用。

```
L2 (推荐) : nebula_visual + nebula_app + nebula_main       ← 声明式，零样板
L1 (进阶) : nebula_component + nebula_app + 手动主循环      ← 自定义初始化/帧逻辑
L0 (底层) : nebula_annotate + nebula_derive + nebula_app_begin/end ← 完全控制
```

---

## 何时需要降级

| 场景 | 推荐层级 |
| :--- | :--- |
| 标准组件 + 默认主题 + 框架主循环 | **L2** |
| 需要自定义 `on_init` / `on_frame` 逻辑 | **L2**（使用 `nebula_main` 的回调） |
| 需要手动控制主循环（自定义渲染顺序、多窗口） | **L1** |
| 需要手动声明 record 字段（自定义状态字段、非标准管线） | **L1** |
| 需要完全控制 annotate/derive 参数（自定义原语、自定义管线签名） | **L0** |
| 混合使用 App 编排与手动管线 | **L0** |

---

## 示例 1：L2 → L1 降级

### L2 写法（推荐）

```nelua
require "nebula"

## nebula_visual("ButtonVisual", { primitives = {"clickable"} })
## nebula_app("ButtonApp", { components = {{ name="btn", type="ButtonVisual" }} })

## local function on_init(app)
##   return { app .. ".btn:init_themed(Vec2{x=300,y=250}, Vec2{x=200,y=60}, 12.0)" }
## end
## local function on_frame(app)
##   return { "if " .. app .. ".btn.click.just_clicked then printf(\"clicked!\\n\") end" }
## end
## nebula_main("ButtonApp", {
##   title = "Button Demo", width = 800, height = 600,
##   bg_r = 0.09, bg_g = 0.09, bg_b = 0.10,
##   on_init = on_init, on_frame = on_frame,
## })
```

### L1 写法（需要手动控制主循环时）

```nelua
require "nebula"

## nebula_visual("ButtonVisual", { primitives = {"clickable"} })
## nebula_app("ButtonApp", { components = {{ name="btn", type="ButtonVisual" }} })

local function main(): int32
  local renderer: NebulaRenderer
  local app: ButtonApp

  if not nebula_init(&renderer, &app, "Button Demo", 800, 600) then return 1 end

  -- ★ L1 特权：手动控制初始化
  app.btn:init_themed(Vec2{x=300,y=250}, Vec2{x=200,y=60}, 12.0)

  local input: NebulaInputState
  while not nebula_should_close() do
    local dt = nebula_frame_begin(&input)

    -- ★ L1 特权：自定义帧逻辑
    if app.btn.click.just_clicked then
      printf("clicked!\n")
    end

    nebula_frame_render(&renderer, &app, &input, dt, 0.09, 0.09, 0.10)
  end

  app:deinit()
  nebula_shutdown(&renderer)
  return 0
end
main()
```

**差异**：L1 写法手动管理 `nebula_init` / 主循环 / `nebula_shutdown`，但仍使用 `nebula_visual` + `nebula_app` 声明组件。适用于需要在帧循环中插入复杂业务逻辑的场景。

---

## 示例 2：L1 → L0 降级

### L0 写法（需要手动声明 record 字段时）

```nelua
require "nebula_core"
require "glfw_bindings"
require "wgpu_bindings"
require "renderer"
require "app"
require "nebula_arena"

-- ★ L0 特权：手动声明 record 字段，完全控制数据布局
global ButtonVisual = @record{
  pos:    Vec2,
  size:   Vec2,
  radius: float32,
  default_bg_color:     Color,
  default_border_color: Color,
  default_border_width: float32,
  hovered_bg_color:     Color,
  hovered_border_color: Color,
  hovered_border_width: float32,
  pressed_bg_color:     Color,
  pressed_border_color: Color,
  pressed_border_width: float32,
}

-- ★ L0 特权：手动指定 states/transitions/primitives
##[[
nebula_annotate("ButtonVisual", {
  states     = {"default", "hovered", "pressed"},
  primitives = {"hoverable", "clickable"},
  transitions = {
    {from="default", to="hovered", on="hover_enter"},
    {from="hovered", to="default", on="hover_leave"},
    {from="hovered", to="pressed", on="press"},
    {from="pressed", to="hovered", on="release"},
  },
})
]]
## nebula_derive("ButtonVisual")

-- ★ L0 特权：手动声明 App 编排
##[[
  nebula_app_begin("ButtonApp")
    nebula_app_register_component("btn", "ButtonVisual")
  nebula_app_end()
]]
## nebula_derive_app("ButtonApp")

-- 主循环代码同 L1（省略）
```

**差异**：L0 写法手动声明 record 字段、states、transitions，并使用 `nebula_annotate` + `nebula_derive` 替代 `nebula_visual`，使用 `nebula_app_begin/end` + `nebula_derive_app` 替代 `nebula_app`。适用于需要添加自定义字段或非标准状态机的场景。

---

## 示例 3：混合使用

同一项目中可以混合不同层级。例如，主组件使用 L2，但特殊组件降级到 L0：

```nelua
require "nebula"

-- ★ L2：标准按钮
## nebula_visual("ButtonVisual", { primitives = {"clickable"} })

-- ★ L0：自定义组件（手动 record + 自定义字段）
global CustomVisual = @record{
  pos:    Vec2,
  size:   Vec2,
  radius: float32,
  my_custom_field: int32,  -- L2 无法声明的自定义字段
  default_bg_color:     Color,
  default_border_color: Color,
  default_border_width: float32,
}
##[[ nebula_annotate("CustomVisual", {
  states = {"default"}, primitives = {}, transitions = {},
}) ]]
## nebula_derive("CustomVisual")

-- ★ L2：App 编排（可以混合 L0 和 L2 组件）
## nebula_app("MyApp", {
##   components = {
##     { name = "btn",    type = "ButtonVisual" },
##     { name = "custom", type = "CustomVisual" },
##   },
## })
```

---

## 三层 API 字段映射表

| 功能 | L2 | L1 | L0 |
| :--- | :--- | :--- | :--- |
| 统一入口 | `require "nebula"` | `require "nebula_core"` + 各模块 | 同 L1 |
| 组件声明 | `nebula_visual(name, spec)` | `nebula_component(name, spec)` + 手动 record | 手动 record + `nebula_annotate` + `nebula_derive` |
| App 编排 | `nebula_app(name, spec)` | 同 L2 | `nebula_app_begin/end` + `nebula_derive_app` |
| 主循环 | `nebula_main(name, opts)` | 手动 `nebula_init` + while 循环 | 手动 GLFW/WGPU 初始化 + while 循环 |
| 初始化 | `on_init` 回调 | 手动调用 `init_themed` / `init` | 手动调用 `init` |
| 帧逻辑 | `on_frame` 回调 | 手动写在 while 循环中 | 同 L1 |
| 清理 | 自动 | `app:deinit()` + `nebula_shutdown` | 手动释放 GPU 资源 |

---

## FAQ

**Q: 如何添加自定义字段到组件 record？**

A: 降级到 L0，手动声明 record 并添加字段，然后使用 `nebula_annotate` + `nebula_derive`。

**Q: 如何访问生成的 Pipeline？**

A: Pipeline 存储在 App 的内部字段中。可以通过 `app._pipelines` 或 `app._dense_pipelines` 访问（需要了解生成的字段名，建议使用 `## print_source("app", "MyApp")` 查看）。

**Q: L2 的 `nebula_visual` 自动推导了哪些东西？**

A: 从 `primitives` 列表自动推导：record 字段（pos/size/radius + 每个 state 的 bg_color/border_color/border_width）、states 列表、transitions 状态机、以及 `init_themed` 方法（自动填充 One Dark 主题色）。

**Q: 三层可以在同一文件中混用吗？**

A: 可以。L0/L1/L2 的组件可以在同一个 `nebula_app` 中混合注册。
