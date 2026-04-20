# Nebula GUI Compiler — Phase 2.4

> "形即（Shape-Is）"范式的编译期代码生成阶段：开发者只写**形状声明 + 注解**，框架在编译期自动派生 `State` 枚举、`StateMachine`、`Context`、`hit_test`、`process_input` 全部样板代码，并按字段自动组合 WGSL 着色器。运行时仍然只是数据插值与一次 GPU 提交。

---

## 各阶段演进

| 项目 | Phase 0 | Phase 1 | Phase 2.1 | Phase 2.2 | Phase 2.3 | Phase 2.4 |
|---|---|---|---|---|---|---|
| 状态枚举 `<T>State` | 手写 | **`nebula_derive` 自动生成** | 同左 | 同左 | 同左 | 同左 |
| 状态机 `<T>StateMachine` | 手写 | **`nebula_derive` 自动生成** | 同左 | 同左 | 同左 | 同左 |
| 上下文 `<T>Context` | 手写 | **`nebula_derive` 自动生成** | 同左 | 同左 | 同左 | 同左 |
| 属性插值 | 手写调用链 | **按字段类型自动派生** | 同左 | 同左 | 同左 | 同左 |
| Uniform std140 padding | 手写 `_pad` | 手写 `_pad` | **`nebula_gen_uniform_layout` 自动生成** | 同左 | 同左 | 同左 |
| 着色器 WGSL | 硬编码字符串 | 硬编码字符串 | 硬编码（struct 部分自动） | **`nebula_gen_wgsl_shader` 按字段自动组合** | 同左 | 同左 |
| 渲染管线 `<T>Pipeline` | 共享单一硬编码 | 共享单一硬编码 | 共享单一硬编码 | 共享单一硬编码 | **`nebula_derive` 专属自动派生** | 同左 |
| 碰撞检测 `hit_test` | 手写 | 手写 | 手写 | 手写 | 手写 | **`nebula_derive` 内联 AABB 自动派生** |
| 交互逻辑 `process_input` | 手写 | 手写 | 手写 | 手写 | 手写 | **`interaction_factory` 按 primitives 自动派生** |
| 焦点管理 | 手写 `focused_id` 逻辑 | 手写 | 手写 | 手写 | 手写 | **`focusable` 原语 + 运行时 `component_id` 自动管理** |
| 输入收集 | 手写 `glfwGetCursorPos` | 手写 | 手写 | 手写 | 手写 | **`nebula_collect_input()` 统一封装** |

---

## 项目结构

```text
nebula/
├── src/
│   ├── nebula_core.nelua      # 编译期推导引擎 + nebula_derive + NebulaInputState
│   ├── app.nelua              # ★ Phase 2.4: 统一输入收集层（nebula_collect_input）
│   ├── derive/
│   │   ├── shader_compose.lua     # Phase 2.2: WGSL 片段表 + 着色器组合器
│   │   ├── pipeline_factory.lua   # Phase 2.3: 渲染管线工厂
│   │   └── interaction_factory.lua # ★ Phase 2.4: 交互原语代码生成器
│   ├── wgpu_bindings.nelua    # wgpu-native v29.0.0.0 的 Nelua FFI 绑定
│   ├── glfw_bindings.nelua    # GLFW 3 的 Nelua FFI 绑定
│   ├── primitives.nelua       # 交互原语层（HoverableState、ClickableState）
│   └── renderer.nelua         # WebGPU 渲染层
├── examples/
│   ├── button_demo.nelua      # ★ Phase 2.4: 单组件 Demo（hoverable + clickable）
│   ├── login_demo.nelua       # ★ Phase 2.4: 多组件 Demo（focusable 焦点自动管理）
│   ├── simple_rect_demo.nelua # Phase 2.4: 边界验证 Demo（hoverable only）
│   └── uniform_layout_test.nelua  # Phase 2.1 布局验证
├── docs/
│   ├── DESIGN_PHASE1.md       # Phase 1 设计说明
│   ├── PLAN_PHASE2.md         # Phase 2 总体开发计划
│   ├── PLAN_PHASE2_2.md       # Phase 2.2 开发计划
│   ├── PLAN_PHASE2_3.md       # Phase 2.3 开发计划
│   └── PLAN_PHASE2_4.md       # ★ Phase 2.4 开发计划
├── tools/
│   ├── headless_test.c        # 离屏渲染验证工具
│   ├── fixture_shader.h       # 自动生成的着色器 C 头文件
│   ├── export_shader_fixture.nelua  # 着色器 Fixture 导出工具
│   └── verify_p2_4.lua        # ★ Phase 2.4: interaction_factory 验证脚本
├── build.sh                   # 一键构建脚本
└── README.md
```

---

## ★ Phase 2.4 核心：交互原语自动派生

Phase 2.4 完成了交互逻辑的最后一块手写代码的消除。开发者在 `nebula_annotate` 中声明 `primitives`，`nebula_derive` 自动生成碰撞检测与状态转换逻辑。

### 支持的原语

| 原语 | 自动生成的行为 |
|---|---|
| `"hoverable"` | `hit_test` AABB 内联碰撞检测；`hover.is_hovered / just_entered / just_left` 字段更新；`Hovered` 状态转换 |
| `"clickable"` | `click.is_pressed / just_clicked` 字段更新；`Pressed` 状态转换（需同时声明 `"hoverable"`） |
| `"focusable"` | 基于运行时 `component_id` 的焦点管理；`Focused` 状态转换（需同时声明 `"clickable"`） |

### 使用示例

```nelua
-- 1. 声明 Visual 形状（开发者只需写这些）
global InputVisual = @record{
  pos: Vec2, size: Vec2, radius: float32,
  default_bg_color:     Color, hovered_bg_color:     Color, focused_bg_color:     Color,
  default_border_color: Color, hovered_border_color: Color, focused_border_color: Color,
  default_border_width: float32, hovered_border_width: float32, focused_border_width: float32,
}

##[[
nebula_annotate("InputVisual", {
  states     = {"default", "hovered", "focused"},
  primitives = {"hoverable", "clickable", "focusable"},
  transitions = { ... },
})
]]
## nebula_derive("InputVisual")

-- 2. 运行时：为同类型多实例分配不同 component_id
local email_input: InputContext
email_input:init(InputVisual{ ... })
email_input.component_id = 1   -- 区分焦点实例

local password_input: InputContext
password_input:init(InputVisual{ ... })
password_input.component_id = 2

-- 3. 主循环：一行收集输入，一行更新（交互逻辑全部自动处理）
local input: NebulaInputState
while glfwWindowShouldClose(window) == 0 do
  glfwPollEvents()
  nebula_collect_input(window, &input, dt)
  email_input:update(&input, dt)     -- 内部自动调用 process_input
  password_input:update(&input, dt)
end
```

### 编译期日志

```text
[derive] InputVisual: emit State + StateMachine + Context + Uniforms + Shader + Pipeline + Interaction (3 props, 5 transitions, 80B uniforms, features=[radius, fill, border], primitives=[hoverable, clickable, focusable])
```

---

## Phase 2.3 核心 API：渲染管线工厂

`nebula_derive` 在 Phase 2.3 中额外派生专属渲染管线，消除了共享管线的硬编码：

- `global <T>Uniforms` — 紧凑 std140 record（无 `force_viewport_align`）
- `global <T>Pipeline` — 专属渲染管线，委托 `nebula_pipeline_base_init`
- `<T>Context:to_uniforms(w, h)` — 强类型版本，返回 `<T>Uniforms`

---

## Phase 2.2 核心 API：`nebula_gen_wgsl_shader(type_name)`

着色器组合器根据 Visual 规格中声明的字段，自动选择并拼装 WGSL 片段：

| Visual 字段 | 触发的着色器行为 |
|---|---|
| `radius: float32` | 注入 `sdf_rounded_rect` 圆角距离函数 |
| 无 `radius` | 注入 `sdf_rect` 简单矩形距离函数 |
| `bg_color: Color` | 注入填充颜色计算 |
| `border_color` + `border_width` | 注入边框 alpha 计算与颜色叠加 |

---

## Phase 1 核心 API：`nebula_derive(type_name)`

调用者只需要：

```nelua
global ButtonVisual = @record{
  pos: Vec2, size: Vec2, radius: float32,
  default_bg_color:  Color, hovered_bg_color:  Color, pressed_bg_color:  Color,
  default_border_color: Color, hovered_border_color: Color, pressed_border_color: Color,
  default_border_width: float32, hovered_border_width: float32, pressed_border_width: float32,
}

##[[
nebula_annotate("ButtonVisual", {
  states     = {"default", "hovered", "pressed"},
  primitives = {"hoverable", "clickable"},
  transitions = {
    {from="default", to="hovered", tween="ease_out", duration=0.15},
    {from="hovered", to="default", tween="ease_out", duration=0.15},
    {from="hovered", to="pressed", tween="none",     duration=0.0},
    {from="pressed", to="hovered", tween="ease_out", duration=0.1},
  },
})
]]

## nebula_derive("ButtonVisual")
```

---

## 实现要点

| 层次 | 实现方式 | 零开销验证 |
|------|---------|-----------|
| 注解注册 | `nebula_annotate(type_name, spec)` | 仅在编译期 Lua 表存活 |
| 形状解析 | `nebula_parse_shape` 遍历 `T.value.fields` | 无运行时反射 |
| 代码生成 | Lua 拼接 Nelua 源码 → `aster.parse` → 逐条 `inject_statement` | 注入产物等价于手写代码 |
| Uniform 布局 | `nebula_gen_uniform_layout` 按 std140 规则自动对齐 | 编译期确定 |
| 着色器组合 | `nebula_compose_shader` 按字段选择 WGSL 片段 | 编译期字符串拼接 |
| 碰撞检测 | `interaction_factory` 内联 AABB，无函数调用层 | 编译期展开 |
| 交互原语 | `primitives` 列表 → `hit_test / process_input` 自动生成 | 编译期确定 |
| 焦点管理 | 运行时 `component_id` 字段区分同类型多实例 | 无虚分发 |
| 命名映射 | `<Visual>` 后缀剥离 → 派生 `<Base>State / <Base>StateMachine / <Base>Context` | 静态确定 |
| 状态优先级 | `pressed > focused > hovered > default` 自动展开为 if-else | 无虚分发 |
| 属性插值 | `Color → lerp_color`、`float32 → lerp_f32`、`Vec2 → lerp_vec2` | 全部内联 |

---

## 构建与运行

### 环境要求

- Linux x86_64 / WSL2
- Nelua 0.2.0-dev（[GitHub 安装](https://github.com/edubart/nelua-lang)）
- GCC 11+
- GLFW 3：`sudo apt install libglfw3-dev`
- wgpu-native v29.0.0.0：

```bash
mkdir -p vendor && cd vendor
wget https://github.com/gfx-rs/wgpu-native/releases/download/v29.0.0.0/wgpu-linux-x86_64-release.zip
unzip wgpu-linux-x86_64-release.zip -d wgpu-native
rm wgpu-linux-x86_64-release.zip
```

### 编译

```bash
chmod +x build.sh
./build.sh button_demo       # Phase 2.4 单组件 Demo（hoverable + clickable）
./build.sh login_demo        # Phase 2.4 多组件 Demo（focusable 焦点自动管理）
./build.sh simple_rect_demo  # Phase 2.4 边界验证 Demo（hoverable only）
```

### 运行

```bash
LD_LIBRARY_PATH=vendor/wgpu-native/lib ~/.cache/nelua/button_demo
# 或在无显示环境下使用 Xvfb
Xvfb :99 -screen 0 1024x768x24 &
DISPLAY=:99 LD_LIBRARY_PATH=vendor/wgpu-native/lib ~/.cache/nelua/button_demo
```

---

## Phase 2 进度

- [x] **Phase 2.1** — Uniform std140 自动对齐（`nebula_gen_uniform_layout`）
- [x] **Phase 2.2** — WGSL 着色器按字段组合（`nebula_gen_wgsl_shader`）
- [x] **Phase 2.3** — 渲染管线工厂自动派生（`<T>Pipeline` 与强类型 `to_uniforms`）
- [x] **Phase 2.4** — 交互原语自动派生（`hit_test` + `process_input` + `focusable` 焦点管理）
- [ ] **Phase 2.5** — 多 Pass 渲染（Shadow / Blur）

## Phase 3+ 展望

- 多组件布局（`@layout` 宏 + Flexbox 编译期解算）。
- 文本渲染管线（字形光栅化 / 图集 / Shaping）。
- 动态列表与条件渲染（运行时对象池）。
