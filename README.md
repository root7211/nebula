# Nebula GUI Compiler — Phase 2.5 已完成，Phase 3.1 已合入
> 当前仓库的**主线能力**已完成到 **Phase 2.5**：开发者只写**形状声明 + 注解**，框架即可在编译期自动派生 `State` 枚举、`StateMachine`、`Context`、`hit_test`、`process_input` 与多 Pass 阴影管线。与此同时，**Phase 3.1 的编译期静态布局系统也已合入仓库**，对应 `layout_engine.lua` 与 `layout_demo.nelua`。
---
## 各阶段演进（主线到 Phase 2.5，布局子系统已进入 Phase 3.1）

| 项目 | Phase 0 | Phase 1 | Phase 2.1 | Phase 2.2 | Phase 2.3 | Phase 2.4 | Phase 2.5 |
|---|---|---|---|---|---|---|---|
| 状态枚举 `<T>State` | 手写 | **`nebula_derive` 自动生成** | 同左 | 同左 | 同左 | 同左 | 同左 |
| 状态机 `<T>StateMachine` | 手写 | **`nebula_derive` 自动生成** | 同左 | 同左 | 同左 | 同左 | 同左 |
| 上下文 `<T>Context` | 手写 | **`nebula_derive` 自动生成** | 同左 | 同左 | 同左 | 同左 | 同左 |
| 属性插值 | 手写调用链 | **按字段类型自动派生** | 同左 | 同左 | 同左 | 同左 | 同左 |
| Uniform std140 padding | 手写 `_pad` | 手写 `_pad` | **`nebula_gen_uniform_layout` 自动生成** | 同左 | 同左 | 同左 | 同左 |
| 着色器 WGSL | 硬编码字符串 | 硬编码字符串 | 硬编码（struct 部分自动） | **`nebula_gen_wgsl_shader` 按字段自动组合** | 同左 | 同左 | **多 Pass 着色器集合自动生成** |
| 渲染管线 `<T>Pipeline` | 共享单一硬编码 | 共享单一硬编码 | 共享单一硬编码 | 共享单一硬编码 | **`nebula_derive` 专属自动派生** | 同左 | **多 Sub-pipeline 阴影管线自动派生** |
| 碰撞检测 `hit_test` | 手写 | 手写 | 手写 | 手写 | 手写 | **`nebula_derive` 内联 AABB 自动派生** | 同左 |
| 交互逻辑 `process_input` | 手写 | 手写 | 手写 | 手写 | 手写 | **`interaction_factory` 按 primitives 自动派生** | 同左 |
| 焦点管理 | 手写 `focused_id` 逻辑 | 手写 | 手写 | 手写 | 手写 | **`focusable` 原语 + 运行时 `component_id` 自动管理** | 同左 |
| 输入收集 | 手写 `glfwGetCursorPos` | 手写 | 手写 | 手写 | 手写 | **`nebula_collect_input()` 统一封装** | 同左 |
| 阴影 / 模糊 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 | **声明 `shadow_*` 字段 → 4-Pass 管线自动生成** |

---

## 项目结构

```text
nebula/
├── src/
│   ├── nebula_core.nelua      # 编译期推导引擎（主线到 Phase 2.5，并接入 Phase 3.1 布局模块）
│   ├── app.nelua              # Phase 2.4: 统一输入收集层（nebula_collect_input）
│   ├── derive/
│   │   ├── shader_compose.lua     # Phase 2.5: WGSL 片段表 + 着色器组合器（含阴影/模糊）
│   │   ├── pipeline_factory.lua   # Phase 2.5: 渲染管线工厂（含多 Sub-pipeline）
│   │   ├── interaction_factory.lua # Phase 2.4: 交互原语代码生成器
│   │   └── layout_engine.lua      # Phase 3.1: 编译期静态 Flexbox 布局引擎
│   ├── wgpu_bindings.nelua    # wgpu-native v29.0.0.0 的 Nelua FFI 绑定
│   ├── glfw_bindings.nelua    # GLFW 3 的 Nelua FFI 绑定
│   ├── primitives.nelua       # 交互原语层（HoverableState、ClickableState）
│   └── renderer.nelua         # WebGPU 渲染层（含离屏纹理 + textured pipeline 基础设施）
├── examples/
│   ├── shadow_demo.nelua      # ★ Phase 2.5 主线 Demo（4-Pass 多管线渲染）
│   ├── button_demo.nelua      # Phase 2.4: 单组件 Demo（hoverable + clickable）
│   ├── login_demo.nelua       # Phase 2.4: 多组件 Demo（focusable 焦点自动管理）
│   ├── simple_rect_demo.nelua # Phase 2.4: 边界验证 Demo（hoverable only）
│   ├── layout_demo.nelua      # ★ Phase 3.1 子阶段 Demo（编译期静态 Flexbox 布局）
│   └── uniform_layout_test.nelua  # Phase 2.1 布局验证
├── docs/
│   ├── DESIGN_PHASE1.md       # Phase 1 设计说明
│   ├── PLAN_PHASE2.md         # Phase 2 总体开发计划
│   ├── PLAN_PHASE2_2.md       # Phase 2.2 开发计划
│   ├── PLAN_PHASE2_3.md       # Phase 2.3 开发计划
│   ├── PLAN_PHASE2_4.md       # Phase 2.4 开发计划
│   ├── PLAN_PHASE2_5.md       # ★ Phase 2.5 开发计划
│   └── PLAN_PHASE3.md         # ★ Phase 3 开发计划（其中 3.1 已合入）
├── tools/
│   ├── headless_test.c        # 离屏渲染验证工具
│   ├── fixture_shader.h       # 自动生成的着色器 C 头文件
│   ├── export_shader_fixture.nelua  # 着色器 Fixture 导出工具
│   └── verify_p2_4.lua        # Phase 2.4: interaction_factory 验证脚本
├── build.sh                   # 一键构建脚本
└── README.md
```

---

## ★ Phase 2.5 主线核心：多 Pass 渲染（Shadow / Blur）

Phase 2.5 打破了单 Pass 渲染的限制。开发者只需在 Visual 中声明 `shadow_color`、`shadow_offset`、`shadow_blur` 三个字段，`nebula_derive` 即可自动检测并生成完整的 4-Pass 阴影管线。

### 架构

```text
Pass 1 (shadow_mask):  渲染偏移后的组件 SDF 遮罩 → 离屏纹理 A
Pass 2 (blur_h):       从纹理 A 采样，水平高斯模糊 → 离屏纹理 B
Pass 3 (blur_v):       从纹理 B 采样，垂直高斯模糊 → 离屏纹理 A
Pass 4 (main):         Surface Pass：合成模糊阴影 + 绘制主组件
```

### 自动生成的内容

| 组件 | 无阴影（Phase 2.3 兼容） | 有阴影（Phase 2.5） |
|---|---|---|
| `<T>Pipeline` record | 4 字段（pipeline, bgl, ubuf, bg） | 扩展至 20+ 字段（含子管线、离屏纹理、采样器） |
| `<T>Pipeline:init()` | 委托 `nebula_pipeline_base_init` | 初始化 4 条子管线 + 2 张离屏纹理 + 采样器 + BindGroup |
| `<T>Pipeline:draw()` | 单 Pass 全屏三角形 | 向后兼容，仅绘制主组件 |
| `<T>Pipeline:draw_shadow()` | 不存在 | 编排 3 个离屏 Pass（mask → blur_h → blur_v） |
| `<T>Pipeline:draw_composite()` | 不存在 | 在 surface 主 Pass 中合成模糊阴影 |
| WGSL 着色器 | 1 个主着色器 | 4 个着色器（shadow_mask + blur + composite + main） |

### 使用示例

```nelua
global ShadowButtonVisual = @record{
  pos: Vec2, size: Vec2, radius: float32,
  -- ★ 声明这三个字段即可触发阴影管线
  shadow_offset: Vec2,
  shadow_blur:   float32,
  -- 每状态阴影颜色（可动画）
  default_shadow_color: Color,
  hovered_shadow_color: Color,
  pressed_shadow_color: Color,
  -- 其余字段...
  default_bg_color: Color, hovered_bg_color: Color, pressed_bg_color: Color,
  default_border_color: Color, hovered_border_color: Color, pressed_border_color: Color,
  default_border_width: float32, hovered_border_width: float32, pressed_border_width: float32,
}

##[[
nebula_annotate("ShadowButtonVisual", {
  states     = {"default", "hovered", "pressed"},
  primitives = {"hoverable", "clickable"},
  transitions = { ... },
})
]]
## nebula_derive("ShadowButtonVisual")

-- 运行时：阴影管线需要窗口尺寸
local pipeline: ShadowButtonPipeline
pipeline:init(&renderer, WIN_W, WIN_H)

-- 主循环中编排多 Pass
pipeline:draw_shadow(encoder, &renderer, button_vis.shadow_blur)
-- 然后在 surface pass 中依次调用：
--   pipeline:draw_composite(pass)
--   pipeline:draw(pass)
```

### 编译期日志

```text
[derive] ShadowButtonVisual: emit State + StateMachine + Context + Uniforms + Shader + Pipeline + Interaction (4 props, 4 transitions, 128B uniforms, features=[radius, fill, border, shadow], primitives=[hoverable, clickable], passes=[shadow_mask, blur_h, blur_v, main])
```

### 零开销保证

未声明 `shadow_*` 字段的组件仍然走高效的单 Pass 路径，不会引入任何额外的纹理分配或 Pass 开销。阴影特性的检测完全在编译期完成。

---

## Phase 2.4 核心：交互原语自动派生

Phase 2.4 完成了交互逻辑的最后一块手写代码的消除。开发者在 `nebula_annotate` 中声明 `primitives`，`nebula_derive` 自动生成碰撞检测与状态转换逻辑。

### 支持的原语

| 原语 | 自动生成的行为 |
|---|---|
| `"hoverable"` | `hit_test` AABB 内联碰撞检测；`hover.is_hovered / just_entered / just_left` 字段更新；`Hovered` 状态转换 |
| `"clickable"` | `click.is_pressed / just_clicked` 字段更新；`Pressed` 状态转换（需同时声明 `"hoverable"`） |
| `"focusable"` | 基于运行时 `component_id` 的焦点管理；`Focused` 状态转换（需同时声明 `"clickable"`） |

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
| `shadow_color` + `shadow_offset` + `shadow_blur` | ★ 注入阴影遮罩 + 高斯模糊着色器集合 |

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
| 多 Pass 着色器 | `shader_compose` 生成 shadow_mask + blur + main 三套 WGSL | 编译期确定 |
| 管线工厂 | `pipeline_factory` 生成单管线或多 Sub-pipeline | 编译期确定 |
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
./build.sh shadow_demo       # ★ Phase 2.5 主线 Demo（4-Pass 多管线渲染）
./build.sh layout_demo       # ★ Phase 3.1 子阶段 Demo（编译期静态 Flexbox 布局）
./build.sh button_demo       # Phase 2.4 单组件 Demo（hoverable + clickable）
./build.sh login_demo        # Phase 2.4 多组件 Demo（focusable 焦点自动管理）
./build.sh simple_rect_demo  # Phase 2.4 边界验证 Demo（hoverable only）
```

### 运行

```bash
LD_LIBRARY_PATH=vendor/wgpu-native/lib ~/.cache/nelua/shadow_demo
# 或在无显示环境下使用 Xvfb
Xvfb :99 -screen 0 1024x768x24 &
DISPLAY=:99 LD_LIBRARY_PATH=vendor/wgpu-native/lib ~/.cache/nelua/shadow_demo
```

---

## 阶段状态汇总

### Phase 2 主线进度

- [x] **Phase 2.1** — Uniform std140 自动对齐（`nebula_gen_uniform_layout`）
- [x] **Phase 2.2** — WGSL 着色器按字段组合（`nebula_gen_wgsl_shader`）
- [x] **Phase 2.3** — 渲染管线工厂自动派生（`<T>Pipeline` 与强类型 `to_uniforms`）
- [x] **Phase 2.4** — 交互原语自动派生（`hit_test` + `process_input` + `focusable` 焦点管理）
- [x] **Phase 2.5** — 多 Pass 渲染（Shadow / Blur：4-Pass 阴影管线自动派生）

### Phase 3 子阶段进度

- [x] **Phase 3.1** — 编译期静态 Flexbox 布局系统（`layout_engine.lua` + `layout_demo.nelua`）
- [ ] **Phase 3.2** — GPU SDF 文本渲染管线
- [ ] **Phase 3.3** — 运行时动态列表与实例渲染

## Phase 3 后续展望

- 在已合入的 Phase 3.1 静态布局基础上，继续推进文本渲染与动态列表能力。
- 文本渲染管线（字形光栅化 / 图集 / Shaping）。
- 动态列表与条件渲染（运行时对象池）。
