# Phase 4.5-S3 语法糖深化实施方案

**创建日期**：2026-05-04
**基准状态**：68/68 回归测试全绿 | Phase 4.7-S7 已完成

---

## 0. 动机

README 愿景是 50 行实现工业级文本编辑器。当前最简单的 button_demo 需要 147 行，差距 10 倍。

Phase 4.5 S1-S2 已完成组件声明和 App 声明的糖化，但**没有触及最大的样板来源**：

| 样板来源 | 占比 | 现有糖化 |
|:---------|:-----|:---------|
| Visual record 手写（三态颜色字段） | ~16 行/类型 | ❌ 未覆盖 |
| init 颜色值传递 | ~15 行/组件 | ❌ 未覆盖 |
| require 样板 | ~10 行/demo | ❌ 未覆盖 |
| 主循环 dt/input 样板 | ~5 行/demo | ❌ 未覆盖 |
| 组件声明（annotate+derive） | ~12 行/类型 | ✅ nebula_component |
| App 编排（begin/end/derive） | ~5 行/app | ✅ nebula_app |

---

## 1. 设计原则

**P1 — 零成本抽象**：所有糖化在编译期（S1）完成，生成代码与手写等价，不引入任何运行时间接调用、虚函数表或额外内存分配。

**P2 — 分层可逃逸**：三层 API 可自由混用。高层糖出问题时，用户随时降到低层，不需要重写全部代码。

```
L2 (Visual) : nebula_visual + init_themed         ← 本次新增
L1 (Sugar)  : nebula_component + nebula_app       ← Phase 4.5 已有
L0 (Raw)    : nebula_annotate + nebula_derive     ← 最初的 raw API
```

**P3 — 约定优于配置**：从 primitives 推导一切可推导的信息（states、transitions、record 字段、主题颜色），用户只声明领域意图。

**P4 — 正交可组合**：每个糖函数独立工作，不强制绑定。用户可以用 `nebula_visual` 生成 record 但手写 init 颜色，也可以手写 record 但用 `init_themed`。

**P5 — 糖与模板的边界**：糖消除"从已有信息可确定性推导的机械重复"。应用层架构决策（Producer 函数、文件 I/O、UI 布局组合）不属于糖的范畴。

---

## 2. 新增 API 清单（4 项）

### 2.1 `require "nebula"` — 统一入口

**文件**：新建 `src/nebula.nelua`

**实现**：

```nelua
## cinclude "<stdio.h>"
## cinclude "<string.h>"
require "nebula_core"
require "glfw_bindings"
require "wgpu_bindings"
require "renderer"
require "app"
require "text_runtime"
require "nebula_cursor"
require "nebula_arena"
require "nebula_theme"

global function printf(fmt: cstring, ...: cvarargs): int32 <cimport, nodecl> end
global function snprintf(buf: cstring, size: csize, fmt: cstring, ...: cvarargs): int32 <cimport, nodecl> end
```

**代价**：零。Nelua 的 `require` 是编译期包含，未使用的符号不进入二进制（dead code elimination）。

**收益**：每个 demo 省 ~10 行 → 1 行。

---

### 2.2 `nebula_visual(type_name, spec)` — 自动生成 Visual Record

**文件**：`src/nebula_core.nelua`（在 `nebula_component` 之后新增）

**输入**：

```lua
nebula_visual(type_name, {
  primitives   = {"clickable"},          -- 必选：交互原语列表
  fields       = { "score: int32" },     -- 可选：用户附加字段
  text_mode    = nil,                    -- 可选："dense" 时生成轻量 record
  max_chars    = 256,                    -- 可选：text_mode="dense" 时的容量
  max_text_len = 256,                    -- 可选：editable 系原语的 buffer 容量
  max_lines    = 32,                     -- 可选：multiline_editable 的行数
  component_id = 0,                      -- 可选：focusable 组件 ID
})
```

**编译期转换链**：

```
Step 1: 解析 primitives 依赖链
  clickable → 依赖 hoverable
  最终: ["hoverable", "clickable"]

Step 2: 推导 states
  hoverable → "hovered"
  clickable → "pressed"
  结果: ["default", "hovered", "pressed"]

Step 3: 生成 record 字段
  ┌─ 基础字段（永远生成）
  │   pos: Vec2, size: Vec2, radius: float32
  ├─ 每个 state 生成三元组
  │   {state}_bg_color: Color
  │   {state}_border_color: Color
  │   {state}_border_width: float32
  ├─ 原语附加字段
  │   scrollable       → content_height: float32
  │                      + {state}_track_color, {state}_thumb_color
  │   editable         → pixel_height: float32
  │                      gap_buf: NebulaBuf{N}
  │   multiline_edit.  → pixel_height, text_origin_x, content_height
  │                      multi_buf: NebulaMultiBuf{N}_{L}
  │                      gap_buf: NebulaBuf{N}
  └─ 用户附加字段
      spec.fields 逐项追加

Step 4: aster.parse + inject_statement 注入 record AST
Step 5: 如需 multiline_editable → 前置 nebula_inject_buffers
Step 6: 调用 nebula_component(type_name, spec)
```

**生成等价代码示例**（`nebula_visual("ButtonVisual", { primitives = {"clickable"} })`）：

```nelua
global ButtonVisual = @record{
  pos: Vec2,
  size: Vec2,
  radius: float32,
  default_bg_color: Color,
  default_border_color: Color,
  default_border_width: float32,
  hovered_bg_color: Color,
  hovered_border_color: Color,
  hovered_border_width: float32,
  pressed_bg_color: Color,
  pressed_border_color: Color,
  pressed_border_width: float32,
}
-- + nebula_component("ButtonVisual", { primitives = {"clickable"} })
-- = ButtonState enum + ButtonContext record + ButtonPipeline record + 全部方法
```

**DenseText 简写**（`nebula_visual("LineNumVisual", { text_mode = "dense", max_chars = 1024 })`）：

```nelua
global LineNumVisual = @record{ pos: Vec2, size: Vec2 }
-- + nebula_component("LineNumVisual", { text_mode = "dense", max_chars = 1024 })
```

**公理合规**：inject_statement 让类型立即对 symbols 可见 → nebula_derive 内的 nebula_parse_shape 能正常内省字段。此机制已被现有 nebula_editor_visual 验证。

**逃逸路径**：用户手写 record（添加任意自定义字段），然后只调用 `nebula_component`。两种方式生成的 Context/Pipeline 完全相同。

---

### 2.3 `init_themed` — 主题默认 init 方法

**文件**：`src/nebula_core.nelua`（在 `nebula_derive` 生成 Context 时额外注入）

**编译期主题表**（Lua 侧）：

```lua
NEBULA_THEME_DEFAULTS = {
  default = {
    bg     = { r=0.22, g=0.22, b=0.24, a=1.0 },
    border = { r=0.40, g=0.40, b=0.45, a=1.0 },
    border_width = 1.0,
    track  = { r=0.20, g=0.20, b=0.25, a=1.0 },
    thumb  = { r=0.45, g=0.45, b=0.50, a=1.0 },
  },
  hovered = {
    bg     = { r=0.28, g=0.28, b=0.32, a=1.0 },
    border = { r=0.40, g=0.60, b=1.00, a=1.0 },
    border_width = 2.0,
    track  = { r=0.22, g=0.22, b=0.28, a=1.0 },
    thumb  = { r=0.55, g=0.65, b=0.90, a=1.0 },
  },
  pressed = {
    bg     = { r=0.16, g=0.16, b=0.20, a=1.0 },
    border = { r=0.60, g=0.80, b=1.00, a=1.0 },
    border_width = 2.5,
  },
  focused = {
    bg     = { r=0.16, g=0.18, b=0.24, a=1.0 },
    border = { r=0.35, g=0.60, b=1.00, a=1.0 },
    border_width = 2.0,
  },
  draggingbar = {
    bg     = { r=0.16, g=0.16, b=0.22, a=1.0 },
    border = { r=0.50, g=0.80, b=1.00, a=1.0 },
    border_width = 2.5,
    track  = { r=0.25, g=0.25, b=0.32, a=1.0 },
    thumb  = { r=0.65, g=0.80, b=1.00, a=1.0 },
  },
}
```

**生成的方法**（以 3-state Button 为例）：

```nelua
function ButtonContext:init_themed(pos: Vec2, size: Vec2, radius: float32): void
  self:init(ButtonVisual{
    pos = pos, size = size, radius = radius,
    default_bg_color     = Color{ r=0.22, g=0.22, b=0.24, a=1.0 },
    default_border_color = Color{ r=0.40, g=0.40, b=0.45, a=1.0 },
    default_border_width = 1.0,
    hovered_bg_color     = Color{ r=0.28, g=0.28, b=0.32, a=1.0 },
    hovered_border_color = Color{ r=0.40, g=0.60, b=1.00, a=1.0 },
    hovered_border_width = 2.0,
    pressed_bg_color     = Color{ r=0.16, g=0.16, b=0.20, a=1.0 },
    pressed_border_color = Color{ r=0.60, g=0.80, b=1.00, a=1.0 },
    pressed_border_width = 2.5,
  })
end
```

**零成本证明**：主题颜色值在编译期 Lua 中定义，生成代码时直接内联为 float 字面量。编译后的机器码与手写 `init(ButtonVisual{...})` 完全相同。无函数指针，无查表，无条件分支。

**用户可全局覆盖主题**：

```nelua
##[[ NEBULA_THEME_DEFAULTS.hovered.border = { r=1.0, g=0.4, b=0.0, a=1.0 } ]]
-- 之后所有 init_themed 调用都使用橙色 hover 边框
```

**逃逸路径**：不用 `init_themed`，直接调用 `init(FullVisual{...})` 传入自定义颜色。

---

### 2.4 `nebula_frame_begin(input)` — 帧循环整合

**文件**：`src/app.nelua`

**实现**：

```nelua
global _nebula_prev_time: float64 = 0.0

global function nebula_frame_begin(input: *NebulaInputState): float32
  nebula_poll_events()
  local now = glfwGetTime()
  local dt = (@float32)(now - _nebula_prev_time)
  _nebula_prev_time = now
  nebula_collect_input(_nebula_window, input, dt)
  return dt
end
```

**性能分析**：一个函数调用 + 4 次赋值 ≈ ~5ns/frame。帧预算 16.6ms（60fps），开销 0.00003%。

**使用方式**：

```nelua
local input: NebulaInputState
while not nebula_should_close() do
  local dt = nebula_frame_begin(&input)
  -- 业务逻辑
  nebula_frame_render(&renderer, &app, &input, dt, 0.09, 0.09, 0.10)
end
```

---

## 3. 明确排除的设计

| 排除项 | 理由 |
|:-------|:-----|
| `nebula_text_editor` 一站式编辑器声明 | 应用模板，不是语法糖。它替用户做 UI 布局决策（行号+编辑区两列），假设功能组合（undo/file_io），逃逸代价过高 |
| `nebula_builtin_edit_area` 内置编辑区 Producer | 领域绑定：高亮器名称、光标渲染策略、数据源（multi_buf vs JsonTreeView）各异，无法确定性推导 |
| 闭包回调主循环 `nebula_run(app, fn)` | Nelua 闭包捕获受限，且隐藏控制流不利于调试 |
| 运行时主题切换 | 引入 if 分支到热路径（per-instance uniform 计算），违反零成本原则 |
| DSL / 自定义语法 | 超出 `##[[...]]` 机制，需要魔改 Nelua 编译器 |
| 隐式 app/renderer 全局变量 | 多窗口场景不兼容，显式传参更安全 |

**糖与模板的边界判定标准**：

> 这段代码能否从已有信息**确定性推导**出来？
> - 能 → 糖（消除它）
> - 不能 → 应用逻辑（保留它）

---

## 4. 公理合规验证

| API | 类型 | 公理 A（阶段封闭） | 公理 B（生命周期） | 公理 C（形即渲染） |
|:----|:-----|:-------------------|:-------------------|:-------------------|
| `require "nebula"` | S1 编译期 | 纯 include，无跨阶段 | N/A | N/A |
| `nebula_visual` | S1 编译期 | Lua→AST 注入，S1 完成 | 无 L0/L1/L2 影响 | record → pipeline 映射不变 |
| `init_themed` | S2 运行时 | 仅 runtime，不跨回 S1 | L0 init 语义不变 | 颜色常量内联，pipeline 签名不变 |
| `nebula_frame_begin` | S2 运行时 | 仅 runtime | L2 帧级数据 | N/A |

---

## 5. 实施计划

### Step 1: `require "nebula"` + `nebula_frame_begin`

| 任务 | 文件 | 描述 |
|:-----|:-----|:-----|
| 1.1 | `src/nebula.nelua` | 新建统一入口模块 |
| 1.2 | `src/app.nelua` | 新增 `nebula_frame_begin` 函数 + `_nebula_prev_time` 全局 |
| 1.3 | `tests/smoke_phase4_5_s3.lua` | 验证 nebula.nelua 导出完整性 + nebula_frame_begin 签名 |

### Step 2: `nebula_visual`

| 任务 | 文件 | 描述 |
|:-----|:-----|:-----|
| 2.1 | `src/nebula_core.nelua` | 实现 `nebula_visual` 编译期函数 |
| 2.2 | `src/nebula_core.nelua` | 实现字段推导逻辑（primitives → states → fields） |
| 2.3 | `tests/smoke_phase4_5_s3.lua` | 验证各原语组合的字段生成正确性 |

### Step 3: `init_themed`

| 任务 | 文件 | 描述 |
|:-----|:-----|:-----|
| 3.1 | `src/nebula_core.nelua` | 定义 `NEBULA_THEME_DEFAULTS` 编译期主题表 |
| 3.2 | `src/nebula_core.nelua` | 在 `nebula_derive` 生成 Context 时注入 `init_themed` 方法 |
| 3.3 | `tests/smoke_phase4_5_s3.lua` | 验证 init_themed 生成代码的字段完整性 |

### Step 4: 验证 Demo

| 任务 | 文件 | 描述 |
|:-----|:-----|:-----|
| 4.1 | `examples/button_v2_demo.nelua` | 用全部新 API 重写 button_demo，目标 ~13 行 |
| 4.2 | 回归测试 | 全量 `bash tools/run_all_tests.sh`，确保 68+ 全绿 |

---

## 6. 预期效果

### button_v2_demo.nelua（极限形态，~13 行）

```nelua
require "nebula"

## nebula_visual("ButtonVisual", { primitives = {"clickable"} })
## nebula_app("ButtonApp", { components = {{ name="btn", type="ButtonVisual" }} })

local function main(): int32
  local renderer: NebulaRenderer
  local app: ButtonApp
  if not nebula_init(&renderer, &app, "Button Demo", 800, 600) then return 1 end
  app.btn:init_themed(Vec2{x=300,y=250}, Vec2{x=200,y=60}, 12.0)
  local input: NebulaInputState
  while not nebula_should_close() do
    local dt = nebula_frame_begin(&input)
    if app.btn.click.just_clicked then printf("clicked!\n") end
    nebula_frame_render(&renderer, &app, &input, dt, 0.09, 0.09, 0.10)
  end
  app:deinit()
  nebula_shutdown(&renderer)
  return 0
end
main()
```

### 各 Demo 极限行数对照

| Demo | 现状 | 极限 | 压缩比 | 压缩源 |
|:-----|-----:|-----:|-------:|:-------|
| button | 147 | ~13 | 11x | visual + init_themed + require + frame_begin |
| slider | 183 | ~20 | 9x | visual + init_themed |
| multiline_sugar | 153 | ~20 | 8x | visual + init_themed |
| layout | 304 | ~30 | 10x | 多个 visual + init_themed |
| form | 323 | ~45 | 7x | 4 种 visual + init_themed |
| dropdown | 339 | ~45 | 8x | visual + init_themed（领域逻辑不可压） |
| scrollable | 351 | ~50 | 7x | visual + init_themed（手动渲染循环不可压） |
| highlight_sugar | 386 | ~120 | 3x | visual + init_themed（Producer 不可压） |
| text_editor | 320 | ~110 | 3x | visual + init_themed（Producer/File I/O 不可压） |
| json_viewer | 474 | ~200 | 2x | visual（领域逻辑占 60%） |

> 注：压缩比与领域逻辑占比成反比。简单组件压缩 8-11 倍，复杂应用压缩 2-3 倍。这是正确的——框架糖化的边界恰好在领域逻辑的入口处。

---

## 7. 向后兼容

所有现有 demo 和测试**不受影响**：

- `nebula_visual` 是新增函数，不修改 `nebula_component` / `nebula_annotate` / `nebula_derive`
- `init_themed` 是 Context 上的新增方法，现有 `init` 方法保持不变
- `nebula_frame_begin` 是新增函数，现有的 poll + dt + collect 写法继续有效
- `require "nebula"` 是新文件，现有的逐个 require 写法继续有效

旧写法和新写法可在同一个项目中混用（P2 分层可逃逸）。
