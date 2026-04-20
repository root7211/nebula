# Nebula GUI Compiler — Phase 2.2

> "形即（Shape-Is）"范式的编译期代码生成阶段：开发者只写**形状声明 + 注解**，框架在编译期自动派生 `State` 枚举、`StateMachine`、`Context` 全部样板代码，并按字段自动组合 WGSL 着色器。运行时仍然只是数据插值与一次 GPU 提交。

---

## 各阶段演进

| 项目 | Phase 0 | Phase 1 | Phase 2.1 | Phase 2.2 |
|---|---|---|---|---|
| 状态枚举 `<T>State` | 手写 | **`nebula_derive` 自动生成** | 同左 | 同左 |
| 状态机 `<T>StateMachine` | 手写 | **`nebula_derive` 自动生成** | 同左 | 同左 |
| 上下文 `<T>Context` | 手写 | **`nebula_derive` 自动生成** | 同左 | 同左 |
| 属性插值 | 手写调用链 | **按字段类型自动派生** | 同左 | 同左 |
| Uniform std140 padding | 手写 `_pad` | 手写 `_pad` | **`nebula_gen_uniform_layout` 自动生成** | 同左 |
| 着色器 WGSL | 硬编码字符串 | 硬编码字符串 | 硬编码（struct 部分自动） | **`nebula_gen_wgsl_shader` 按字段自动组合** |

---

## 项目结构

```text
nebula/
├── src/
│   ├── nebula_core.nelua      # 编译期推导引擎 + nebula_derive + nebula_gen_wgsl_shader
│   ├── derive/
│   │   └── shader_compose.lua # ★ Phase 2.2: WGSL 片段表 + 着色器组合器
│   ├── wgpu_bindings.nelua    # wgpu-native v29.0.0.0 的 Nelua FFI 绑定
│   ├── glfw_bindings.nelua    # GLFW 3 的 Nelua FFI 绑定
│   ├── primitives.nelua       # 交互原语层（HoverableState、ClickableState）
│   └── renderer.nelua         # WebGPU 渲染层（Phase 2.2: 着色器由引擎自动生成）
├── examples/
│   ├── button_demo.nelua      # Phase 1 单组件 Demo（仅形状 + 注解 + derive）
│   ├── login_demo.nelua       # Phase 1 多组件 Demo（Card / Input / Button 全派生）
│   ├── simple_rect_demo.nelua # ★ Phase 2.2: 边界验证 Demo（无 radius、无 border）
│   └── uniform_layout_test.nelua  # Phase 2.1 布局验证
├── docs/
│   ├── DESIGN_PHASE1.md       # Phase 1 设计说明
│   ├── PLAN_PHASE2.md         # Phase 2 总体开发计划
│   └── PLAN_PHASE2_2.md       # Phase 2.2 开发计划
├── tools/
│   ├── headless_test.c        # 离屏渲染验证工具（Phase 2.2: 使用 fixture_shader.h）
│   ├── fixture_shader.h       # ★ Phase 2.2: 自动生成的着色器 C 头文件
│   └── export_shader_fixture.nelua  # ★ Phase 2.2: 着色器 Fixture 导出工具
├── build.sh                   # 一键构建脚本
└── README.md
```

---

## Phase 2.2 核心 API：`nebula_gen_wgsl_shader(type_name)`

Phase 2.2 新增了着色器按字段自动组合能力。着色器组合器根据 Visual 规格中声明的字段，自动选择并拼装 WGSL 片段：

```lua
-- 编译期调用
local result = nebula_gen_wgsl_shader("ButtonVisual", {
  wgsl_struct_name = "Uniforms",
  force_viewport_align = 16,
})
-- result.source   = "完整 WGSL 着色器源码"
-- result.features = {"radius", "fill", "border"}
-- result.required_passes = {"main"}
```

**字段 → 着色器片段映射**：

| Visual 字段 | 触发的着色器行为 |
|---|---|
| `radius: float32` | 注入 `sdf_rounded_rect` 圆角距离函数 |
| 无 `radius` | 注入 `sdf_rect` 简单矩形距离函数 |
| `bg_color: Color` | 注入填充颜色计算 |
| `border_color` + `border_width` | 注入边框 alpha 计算与颜色叠加 |

**编译期日志**输出形如：

```text
[shader] NebulaRectUniforms: features=[radius, fill, border]  (96B uniforms, 1 pass)
```

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

`nebula_derive` 在编译期发出：

- `global ButtonState = @enum{ Default=0, Hovered=1, Pressed=2 }`
- `global ButtonStateMachine = @record{...}` 及其 `init / transition_to / update / get_t` 方法（`transitions` 拓扑展开为 if-else 链）。
- `global ButtonContext = @record{ visual, sm, hover, click, current_bg_color, current_border_color, current_border_width }` 及 `init / update / to_uniforms`，自动按字段类型选择 `lerp_color` 或 `lerp_f32`。
- 命名约定：源类型若以 `Visual` 结尾（如 `ButtonVisual`），派生符号自动剥离后缀（`Button*`）；否则保留原名（`Foo*`）。

**编译期日志**会输出形如：

```text
[derive] ButtonVisual: emit State + StateMachine + Context (3 props, 4 transitions)
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
| 命名映射 | `<Visual>` 后缀剥离 → 派生 `<Base>State / <Base>StateMachine / <Base>Context` | 静态确定 |
| 状态优先级 | `pressed > hovered > default` 自动展开为 if-else | 无虚分发 |
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
./build.sh button_demo       # 单组件 Demo
./build.sh login_demo        # 多组件 Demo
./build.sh simple_rect_demo  # Phase 2.2 边界验证 Demo
```

### 运行

```bash
LD_LIBRARY_PATH=vendor/wgpu-native/lib ~/.cache/nelua/button_demo
# 或在无显示环境下使用 Xvfb
Xvfb :99 -screen 0 1024x768x24 &
DISPLAY=:99 LD_LIBRARY_PATH=vendor/wgpu-native/lib ~/.cache/nelua/button_demo
```

---

## 已知遗留问题

1. **多管线渲染稳定性**：`login_demo` 在 Phase 0 即存在多 pipeline 并发渲染的运行时显示问题。Phase 1 的派生器侧验证已通过（编译 + 初始化日志均正常），但实际窗口呈现需要在带显示的环境下进一步验证。
2. **Input 的 focus 状态**：派生器目前默认仅识别 `hovered` / `pressed` 优先级；`focused` 仍由 demo 在 `update` 后通过显式 `transition_to` 驱动。Phase 1.1 计划：在注解中支持自定义状态优先级映射。

---

## Phase 2 进度

- [x] **Phase 2.1** — Uniform std140 自动对齐（`nebula_gen_uniform_layout`）
- [x] **Phase 2.2** — WGSL 着色器按字段组合（`nebula_gen_wgsl_shader`）
- [ ] **Phase 2.3** — 渲染管线工厂自动派生 + 多 Pass + Shadow
- [ ] **Phase 2.4** — 交互原语自动派生（碰撞检测内联）

## Phase 3+ 展望

- 多组件布局（`@layout` 宏 + Flexbox 编译期解算）。
- 文本渲染管线（字形光栅化 / 图集 / Shaping）。
- 动态列表与条件渲染（运行时对象池）。
