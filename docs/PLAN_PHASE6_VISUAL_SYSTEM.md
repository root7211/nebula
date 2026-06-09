# Phase 6.0 — Visual System 升级方案

> **目标**：在不违背 Nebula 三条核心公理的前提下，释放 GPU 的 95% 未用能力，使 demo 达到现代 GUI 框架的视觉水准。

## 问题诊断

当前 fragment shader（`shader_compose.lua:208-239`）仅支持**纯色填充 + 边框**：

```wgsl
let fill_alpha = 1.0 - smoothstep(-1.0, 1.0, dist);
let border_alpha = (...) - fill_alpha;
var color = d.bg_color * fill_alpha;
color = color + d.border_color * border_alpha;
return color;
```

Visual record 每状态仅 3 个属性（`bg_color` / `border_color` / `border_width`），所有 UI 元素都是 flat color，缺乏层次感和材质感。

### 六大缺口

| # | 缺口 | 影响 | 代码位置 |
|---|------|------|----------|
| 1 | **无渐变填充** | 所有元素 flat color | `shader_compose.lua:229-239` |
| 2 | **Shadow 未集成 Sugar** | 4-pass blur 已有但停留在 L0 手动 API | `shader_compose.lua:264-439` |
| 3 | **无背景模糊** | 无毛玻璃/磨砂效果 | 需新增 backdrop-blur pass |
| 4 | **绝对定位** | Layout engine 已实现 flexbox 但 demo 仍用硬编码像素 | `layout_engine.lua` |
| 5 | **单一主题** | `NEBULA_THEME_DEFAULTS` 硬编码灰色调，无语义 token | `nebula_derive_engine.nelua:889-925` |
| 6 | **位置不可动画** | pos/size 是 base_fields，不参与状态插值 | `nebula_derive_engine.nelua:95-100` |

## 不可逾越的红线

### ✗ 禁止（违反核心公理）

- 运行时主题切换（dark/light toggle）
- CSS-like cascade / 样式继承链
- 动态组件注册/销毁
- 反射 / 运行时类型查询
- 运行时事件总线 / 虚表分发

### ✓ 允许（编译期扩展）

- 编译期选择主题（`-D NEBULA_THEME=material`）
- 编译期 shader 路径分支（uniform 驱动）
- 编译期多 pass 管线推导
- 注册表扩展（SDF / shader / primitive / easing）
- 编译期布局解算（已实现）

---

## 五阶段实施

### Phase 6.1 — 渐变填充

**改动量**：~80 行 | **依赖**：无 | **风险**：低

#### Visual Record 新增字段

```nelua
global ButtonVisual = @record{
  -- ... 现有字段不变 ...

  -- ★ Phase 6.1 新增：渐变
  fill_mode:      uint32,    -- 0=solid, 1=linear, 2=radial
  color_end:      Color,     -- 渐变终止色
  gradient_angle: float32,   -- 线性渐变角度 (rad)
  -- radial 用 size 的半轴即可，无需额外字段
}
```

#### Fragment Shader 扩展（`shader_compose.lua:208-239`）

```wgsl
// shader_compose.lua 生成
var bg: vec4<f32>;

if (d.fill_mode == 1u) {
  // linear gradient
  let t = dot(p/half_size,
    vec2(cos(d.gradient_angle),
         sin(d.gradient_angle))) * 0.5 + 0.5;
  bg = mix(d.bg_color, d.color_end, t);
} else if (d.fill_mode == 2u) {
  // radial gradient
  let t = length(p / half_size);
  bg = mix(d.bg_color, d.color_end, t);
} else {
  bg = d.bg_color;  // 纯色（向后兼容）
}
```

#### Sugar API 声明方式

```nelua
## nebula_visual("CardVisual", {
  primitives = {"hoverable"},
  fill = {
    mode = "linear",
    angle = 135.0,  -- 度
  }
})

app.card:init(CardVisual{
  pos=..., size=..., radius=16.0,
  fill_mode = 1,
  gradient_angle = 2.356,  -- 135° in rad
  default_bg_color   = Color{r=0.20,g=0.15,b=0.35,a=1.0},
  default_color_end  = Color{r=0.10,g=0.25,b=0.45,a=1.0},
})
```

#### 改动文件

| 文件 | 位置 | 内容 | 行数 |
|------|------|------|------|
| `shader_compose.lua` | :29-40 | WGSL_TYPE_MAP 增加 uint32 映射 | +3 |
| `shader_compose.lua` | :208-239 | fragment shader 增加 gradient 分支 | +25 |
| `nebula_sugar.nelua` | :310-469 | record 生成增加新字段 | +30 |
| `nebula_derive_engine.nelua` | :95-100 | base_fields 增加新字段注册 | +12 |

---

### Phase 6.2 — 语义化主题 Token 系统

**改动量**：~250 行 | **依赖**：无 | **风险**：低

#### 新文件：`src/themes/nebula_themes.lua`

```lua
local THEMES = {}

THEMES.material_dark = {
  -- 语义 token
  primary    = {r=0.40, g=0.63, b=0.95, a=1.0},  -- #669CF2
  on_primary = {r=0.08, g=0.13, b=0.22, a=1.0},
  surface    = {r=0.12, g=0.12, b=0.14, a=1.0},
  on_surface = {r=0.90, g=0.90, b=0.92, a=1.0},
  outline    = {r=0.30, g=0.30, b=0.34, a=1.0},

  -- 组件级默认值（映射到 state_fields）
  button = {
    default  = { bg="primary", radius=8,  border_width=0 },
    hovered  = { bg={r=0.46,...}, radius=8 },
    pressed  = { bg={r=0.34,...}, radius=8 },
  },
  card = {
    default = { bg="surface", radius=12 },
  },
  input = {
    default  = { bg={r=0.16,...}, radius=6, border="outline" },
    focused  = { border="primary", border_width=2 },
  },
}

THEMES.nord = { ... }
THEMES.dracula = { ... }

return THEMES
```

#### 编译期选择方式

```nelua
-- 方式 1: 命令行定义
nelua -D NEBULA_THEME=material_dark demo.nelua

-- 方式 2: 代码内覆盖
## nebula_config_override({ THEME = "nord" })

-- 方式 3: init_themed 自动读取
app.btn:init_themed(pos, size, radius)
-- 自动从 NEBULA_THEME.button.default 读取颜色
-- 语义 token 在编译期解析为实际 Color 值
```

#### 预置主题配色

| 主题 | 风格 | Primary | Surface | Background |
|------|------|---------|---------|------------|
| **material_dark** | Material Design 3 深色 | #669CF2 | #1E1E2E | #121218 |
| **nord** | Nord 冷色调 | #88C0D0 | #3B4252 | #2E3440 |
| **dracula** | Dracula 暗紫 | #BD93F9 | #44475A | #282A36 |

#### 改动文件

| 文件 | 位置 | 内容 | 行数 |
|------|------|------|------|
| `src/themes/nebula_themes.lua` | NEW | 3 套预置主题 + 语义 token 解析器 | +180 |
| `nebula_derive_engine.nelua` | :889-925 | NEBULA_THEME_DEFAULTS → 从主题表动态解析 | +40 |
| `nebula_derive_engine.nelua` | :1009-1083 | init_themed 改用主题 token 映射颜色 | +30 |

---

### Phase 6.3 — Shadow 集成到 Sugar API

**改动量**：~150 行 | **依赖**：6.2 | **风险**：中

`shadow_demo.nelua` 已标注 "Phase 3.9 审计: 暂缓升级"。将 4-pass Gaussian blur 阴影从 L0 手动 API 提升到 L2 sugar 声明。

#### Sugar 声明方式

```nelua
## nebula_visual("CardVisual", {
  primitives = {"hoverable"},
  shadow = {
    blur = 16,
    offset = {0, 4},
    color  = {r=0, g=0, b=0, a=0.4},
    -- 可选: per-state 阴影
    hovered_blur = 24,
    hovered_offset = {0, 8},
  }
})
```

#### Derive Engine 扩展

```lua
-- nebula_annotate 检测 shadow 声明
-- → 设置 feats.has_shadow = true
-- → nebula_resolve_shader_composer 选择 shadow 路径
-- → 生成 4-pass pipeline 签名

-- 新增 base_fields:
shadow_blur:   float32
shadow_offset: Vec2

-- 新增 state_fields (可选):
default_shadow_color:  Color
hovered_shadow_color:  Color
-- ... 和 bg_color 一样参与动画插值
```

#### 关键改动点

1. **`shader_compose.lua:142-248`** — 检测 `reg.shadow` → 生成 `shadow_*` 字段到 uniform struct → 设置 `feats.has_shadow = true`
2. **`nebula_compose_shadow_shaders`** (已有, :264-439) — 复用现有 4-pass 实现，修改 shadow_mask 的 uniform 来源从独立 uniform buffer 改为 storage buffer instanced 数据
3. **`renderer.nelua`** (render loop) — 检测 pipeline 是否 `has_shadow` → 编排 4-pass 渲染
4. **`nebula_sugar.nelua`** — `nebula_visual` spec 解析 shadow 字段 → 注入 base/state fields

#### 改动文件

| 文件 | 位置 | 内容 | 行数 |
|------|------|------|------|
| `nebula_sugar.nelua` | :310-469 | spec 解析 shadow 字段 | +35 |
| `nebula_derive_engine.nelua` | :589-628 | shadow 属性注册为可动画 state_field | +20 |
| `shader_compose.lua` | :142-248 | instanced shader 增加 shadow uniform 字段 | +25 |
| `renderer.nelua` | :437-533 | render loop 检测 shadow → 编排 4-pass | +60 |

---

### Phase 6.4 — Transform 动画

**改动量**：~40 行 | **依赖**：无 | **风险**：低

当前 pos/size 是 base_fields，不参与状态插值。通过增加 transform layer（scale/offset）实现动画，不修改 pos/size 的 base_fields 性质。

#### 方案：Transform Layer

```nelua
global ButtonVisual = @record{
  pos:    Vec2,       -- base: 锚点位置
  size:   Vec2,       -- base: 基础尺寸

  -- ★ Phase 6.4 新增: transform (state_fields)
  default_scale:    float32,  -- 默认 1.0
  hovered_scale:    float32,  -- hover 时 1.05
  pressed_scale:    float32,  -- press 时 0.95

  default_offset_y: float32,  -- 默认 0
  hovered_offset_y: float32,  -- hover 时 -2
}
```

#### Vertex Shader 扩展（`shader_compose.lua:178-200`）

```wgsl
let p = d.pos + pos[vi] * d.size;

-- ★ 新增: transform 应用
let center = d.pos + d.size * 0.5;
let scaled = center + (p - center) * d.scale;
let final_pos = scaled + vec2<f32>(0.0, d.offset_y);

let ndc = (final_pos / vp.size) * 2.0 - 1.0;
```

#### 为什么安全？

- pos/size 保持为 base_fields → 编译期布局解算不受影响
- scale/offset 是 uniform float32 → 和 `bg_color` 同构
  - 自动获得: state_fields 注册 + transition 动画 + lerp 插值
  - 编译期生成 `current_scale` 字段 + `update_for_*` 函数
  - 零运行时开销（只是多两个 uniform 写入）

#### 改动文件

| 文件 | 位置 | 内容 | 行数 |
|------|------|------|------|
| `nebula_sugar.nelua` | :310-469 | spec 解析 transform 字段 | +25 |
| `shader_compose.lua` | :178-200 | vertex shader 增加 scale/offset 变换 | +15 |

---

### Phase 6.5 — 预制组件库 nebula_material

**改动量**：~330 行 | **依赖**：6.1-6.4 | **风险**：低

基于 Phase 6.1-6.4 的基础设施，构建预 styled 组件库。类比 React + Material UI 的关系：derive engine = React, nebula_material = MUI。

#### 新文件：`src/nebula_material.nelua`

```nelua
-- MaterialCard: 圆角12 + 阴影 + 渐变背景
## nebula_material_card("CardVisual", {
  radius = 12,
  shadow = { blur=16, offset={0,4} },
  fill = { mode="linear", angle=180 },
})

-- MaterialButton: 主按钮 / 次按钮 / 幽灵按钮
## nebula_material_button("PrimaryBtn", {
  variant = "filled",  -- "filled" | "outlined" | "ghost"
  radius = 8,
  transform = { scale={1.0, 1.03, 0.97} },
})

-- MaterialInput: 带 label 的输入框
## nebula_material_input("EmailInput", {
  radius = 8,
  label = "Email",
  placeholder = "you@example.com",
})

-- MaterialDivider / MaterialAvatar
## nebula_material_divider("Divider")
## nebula_material_avatar("Avatar", { size = 48 })
```

#### 使用示例：login_v2_demo 重写

```nelua
require "nebula"
require "nebula_material"

-- 组件声明（编译期展开为完整 Visual + App）
## nebula_material_card("LoginCard")
## nebula_material_button("LoginBtn", { variant="filled" })
## nebula_material_button("ForgotBtn", { variant="ghost" })
## nebula_material_input("EmailInput")
## nebula_material_input("PassInput")

## nebula_app("LoginApp", {
  components = {
    { name="card", type="LoginCard",
      width=400, height=480, center=true },
    { name="email", type="EmailInput",
      parent="card", flex_basis=48 },
    { name="pass", type="PassInput",
      parent="card", flex_basis=48 },
    { name="login", type="LoginBtn",
      parent="card", flex_basis=48 },
    { name="forgot", type="ForgotBtn",
      parent="card", flex_basis=36 },
  },
  direction = "column",
  padding = 32, gap = 16,
})

## nebula_main("LoginApp", {
  title = "Login", width = 800, height = 600,
  theme = "material_dark",
})

-- 从 158 行 → ~25 行
-- 从手动像素定位 → flexbox 自动布局
-- 从硬编码颜色 → 主题 token 自动映射
```

#### 改动文件

| 文件 | 位置 | 内容 | 行数 |
|------|------|------|------|
| `src/nebula_material.nelua` | NEW | 预制组件模板 | +250 |
| `src/nebula_sugar.nelua` | end | `nebula_material_*` 模板注册函数 | +80 |
| `examples/login_v2_demo.nelua` | rewrite | 用 nebula_material 重写 | -130 |

---

## 向后兼容保证

所有新增字段均有编译期默认值。现有 demo 零改动即可编译通过。

| 特性 | 默认值 | 效果 |
|------|--------|------|
| `fill_mode` | `0` (solid) | fragment shader 走原有纯色路径 |
| shadow | 未声明 → `has_shadow = false` | 走标准单 pass 路径 |
| `scale` | `1.0` | vertex shader 变换是恒等变换 |
| `offset_y` | `0.0` | 同上 |
| 主题 | 未指定 → 回退 `material_dark` | `init_themed()` 签名不变 |

**零 Breaking Changes**。所有 32 个现有 demo 无需修改即可编译通过。

## CI 验证清单

- [ ] compile-linux: 32 demo 全量编译通过
- [ ] compile-windows: 交叉编译通过
- [ ] compile-wasm: WASM 全量链接通过
- [ ] smoke-tests: 149 条断言全绿
- [ ] codegen-verify: 8 demo sugar 展开验证
- [ ] headless-render: lavapipe 渲染测试
- [ ] static-analysis: cppcheck 扫描
- [ ] **NEW**: gradient_demo 编译+运行验证
- [ ] **NEW**: shadow_sugar_demo 编译+运行验证
- [ ] **NEW**: material_login_demo 编译+运行验证

## 执行顺序

```
D0 ──┬── 6.1 渐变填充 (D0→D2)
     ├── 6.2 主题 Token (D0→D3)
     │         │
     │         └── 6.3 Shadow (D3→D5)
     │
     ├── 6.4 Transform (D2→D4)  [可并行]
     │
     └───────────── 6.5 组件库 (D5→D9)
```

- **6.1 + 6.2** 无依赖，可并行开发
- **6.3** 依赖 6.2 的主题 token（shadow 颜色引用语义 token）
- **6.4** 独立，可与 6.3 并行
- **6.5** 依赖全部，最后合并

## 总结

| 指标 | 值 |
|------|-----|
| 总新增行数 | ~900 |
| 可删除行数（demo 简化） | ~130 |
| Breaking Changes | 0 |
| 新文件 | 2（`nebula_themes.lua`, `nebula_material.nelua`） |
| 修改文件 | 5（`shader_compose.lua`, `nebula_derive_engine.nelua`, `nebula_sugar.nelua`, `renderer.nelua`, `login_v2_demo.nelua`） |
