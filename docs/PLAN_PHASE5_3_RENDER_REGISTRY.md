# Phase 5.3: 渲染侧可编程注册表 (Render-Side Programmable Registry)

**状态**：✅ 已完成（2026-05-22）
**前置依赖**：Phase 5.0 (全知图), Phase 5.2 (Sugar Fix)
**目标**：补齐渲染侧最后一层可编程缺口 — 让 SDF 形状与着色器组合策略像交互原语一样可注册

---

## 1. 问题陈述

Nebula 编译器的可编程性存在不对称：

| 层级 | 注册表 | 公开 API | 可扩展？ |
|------|--------|----------|---------|
| 交互原语 | `NEBULA_PRIMITIVES` | `nebula_register_primitive()` | ✅ Phase 4.4 |
| 管线类型 | `NEBULA_PIPELINES` | `nebula_register_pipeline()` | ✅ P1-4 |
| SDF 形状 | `WGSL_FRAGMENTS` (local) | 无 | ❌ |
| 着色器组合 | 5 个硬编码函数 | 无 | ❌ |

交互侧：用户调用 `nebula_register_primitive("draggable", {...})` 即可注入新的交互行为，编译器自动编织进状态机。

渲染侧：管线层已经有了数据驱动分发（`NEBULA_PIPELINES`），但其下游的 `shader_compose.lua` 仍然是封闭的：

1. **SDF 形状硬编码** — `WGSL_FRAGMENTS` 是 `shader_compose.lua` 顶部的 `local` 表，仅含 `sdf_rect` 和 `sdf_rounded_rect`。用户无法注册圆形、胶囊体、星形等新 SDF。
2. **着色器组合器硬编码** — 5 个 `nebula_compose_*` 函数直接暴露为顶层函数，无注册表分发。`nebula_derive()` 中通过 `text_mode` / `has_shadow` 硬编码 if-else 选择组合器。用户无法声明新的着色方式（图片纹理、渐变填充、自定义后处理）。

## 2. 设计目标

- 与 `NEBULA_PRIMITIVES` / `NEBULA_PIPELINES` 风格对称
- 编译期注册，零运行时开销（公理 A 合规）
- 内建形状/组合器通过同一 API 自注册（吃自己的狗粮）
- 不破坏现有 API（向后兼容）

## 3. 架构设计

### 3.1 层次关系

```
用户 Visual 声明 (nebula_annotate)
        │
        ▼
┌─────────────────────────────────────────┐
│  nebula_derive()  (derive_engine)       │
│  ┌──────────────┐  ┌─────────────────┐  │
│  │ 交互侧       │  │ 渲染侧          │  │
│  │ PRIMITIVES   │  │                 │  │
│  │ register_    │  │ ┌─────────────┐ │  │
│  │ primitive()  │  │ │ L3: SHAPES  │ │  │  ← 新增
│  │              │  │ │ register_   │ │  │
│  │              │  │ │ sdf_shape() │ │  │
│  │              │  │ ├─────────────┤ │  │
│  │              │  │ │ L2: SHADER  │ │  │  ← 新增
│  │              │  │ │ COMPOSERS   │ │  │
│  │              │  │ │ register_   │ │  │
│  │              │  │ │ shader_     │ │  │
│  │              │  │ │ composer()  │ │  │
│  │              │  │ ├─────────────┤ │  │
│  │              │  │ │ L1: PIPE-   │ │  │  ← 已有 (P1-4)
│  │              │  │ │ LINES       │ │  │
│  │              │  │ │ register_   │ │  │
│  │              │  │ │ pipeline()  │ │  │
│  │              │  │ └─────────────┘ │  │
│  └──────────────┘  └─────────────────┘  │
└─────────────────────────────────────────┘
```

### 3.2 新增注册表 A: `NEBULA_SDF_SHAPES`

**位置**：`src/derive/shader_compose.lua`

**数据结构**：

```lua
NEBULA_SDF_SHAPES = {}

-- 每个条目的结构：
NEBULA_SDF_SHAPES["circle"] = {
  name         = "circle",
  fn_name      = "sdf_circle",           -- WGSL 函数名
  wgsl_source  = "fn sdf_circle(...)",   -- 完整 WGSL 函数定义
  params       = "p: vec2<f32>, r: f32", -- 参数签名（人类可读，用于文档/校验）
  returns      = "f32",                  -- 返回类型
  extra_fields = {},                     -- 需要 Visual 额外声明的字段（如 radius）
  description  = "...",                  -- 可选描述
}
```

**公开 API**：

```lua
function nebula_register_sdf_shape(name, spec)
  -- name: string — 形状标识符
  -- spec:
  --   fn_name      : string   — WGSL 函数名（必须）
  --   wgsl_source  : string   — 完整 WGSL 函数源码（必须）
  --   params       : string   — 参数签名，如 "p: vec2<f32>, r: f32"（必须）
  --   returns      : string   — 返回类型（默认 "f32"）
  --   extra_fields : table[]? — 需要 Visual 声明的额外字段 [{name, type}]
  --   description  : string?  — 可选描述
end
```

**内建自注册**：

```lua
-- 现有两个 SDF 通过同一 API 注册
nebula_register_sdf_shape("rect", {
  fn_name     = "sdf_rect",
  wgsl_source = [[
fn sdf_rect(p: vec2<f32>, b: vec2<f32>) -> f32 {
  let d = abs(p) - b;
  return length(max(d, vec2<f32>(0.0))) + min(max(d.x, d.y), 0.0);
}
]],
  params  = "p: vec2<f32>, b: vec2<f32>",
  returns = "f32",
})

nebula_register_sdf_shape("rounded_rect", {
  fn_name     = "sdf_rounded_rect",
  wgsl_source = [[
fn sdf_rounded_rect(p: vec2<f32>, b: vec2<f32>, r: f32) -> f32 {
  let q = abs(p) - b + r;
  return length(max(q, vec2<f32>(0.0))) + min(max(q.x, q.y), 0.0) - r;
}
]],
  params       = "p: vec2<f32>, b: vec2<f32>, r: f32",
  returns      = "f32",
  extra_fields = {{ name = "radius", type = "f32" }},
})
```

**用户扩展示例**：

```lua
-- 用户注册圆形 SDF
nebula_register_sdf_shape("circle", {
  fn_name     = "sdf_circle",
  wgsl_source = [[
fn sdf_circle(p: vec2<f32>, r: f32) -> f32 {
  return length(p) - r;
}
]],
  params       = "p: vec2<f32>, r: f32",
  returns      = "f32",
  extra_fields = {{ name = "radius", type = "f32" }},
})

-- 用户注册胶囊体 SDF
nebula_register_sdf_shape("capsule", {
  fn_name     = "sdf_capsule",
  wgsl_source = [[
fn sdf_capsule(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>, r: f32) -> f32 {
  let pa = p - a;
  let ba = b - a;
  let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h) - r;
}
]],
  params       = "p: vec2<f32>, a: vec2<f32>, b: vec2<f32>, r: f32",
  returns      = "f32",
  extra_fields = {{ name = "radius", type = "f32" }},
})
```

**消费方式 — `nebula_compose_shader_instanced` 改造**：

```lua
-- 改造前（硬编码）：
if has_radius then
  sdf_func = WGSL_FRAGMENTS.sdf_rounded_rect
else
  sdf_func = WGSL_FRAGMENTS.sdf_rect
end

-- 改造后（查注册表）：
local shape_name = opts.sdf_shape or (has_radius and "rounded_rect" or "rect")
local shape = NEBULA_SDF_SHAPES[shape_name]
assert(shape, ("nebula_compose_shader_instanced: unknown SDF shape '%s'"):format(shape_name))
sdf_func = shape.wgsl_source
```

这让 `nebula_annotate` 可以声明 `sdf_shape = "circle"`，derive engine 传递给 compose 函数。

### 3.3 新增注册表 B: `NEBULA_SHADER_COMPOSERS`

**位置**：`src/derive/shader_compose.lua`

**动机**：5 个 `nebula_compose_*` 函数是独立的顶层函数，`nebula_derive()` 中的调用路径通过 `text_mode` / `has_shadow` if-else 硬编码选择。新增着色方式（如图片纹理、渐变、自定义后处理）需要同时修改 `shader_compose.lua` 和 `nebula_derive_engine.nelua`。

**数据结构**：

```lua
NEBULA_SHADER_COMPOSERS = {}

-- 每个条目的结构：
NEBULA_SHADER_COMPOSERS["instanced"] = {
  name            = "instanced",
  description     = "标准 Visual 的 Instanced SDF 着色器",
  compose         = nebula_compose_shader_instanced,  -- function(opts) -> result
  pipeline_flag   = "standard_instanced",             -- 对应 NEBULA_PIPELINES 中的 flag
  match           = function(reg, feats)              -- 匹配函数：从 annotate 注册信息判断
    return not reg.text_mode and not feats.has_shadow
  end,
  priority        = 0,                                -- 匹配优先级（数字越大越优先）
}
```

**公开 API**：

```lua
function nebula_register_shader_composer(name, spec)
  -- name: string — 组合器标识符
  -- spec:
  --   compose       : function(opts) -> result  — 着色器组合函数（必须）
  --   pipeline_flag : string                    — 对应的 NEBULA_PIPELINES flag（必须）
  --   match         : function(reg, feats) -> boolean — 自动匹配谓词（可选）
  --   priority      : number                    — 匹配优先级（默认 0）
  --   description   : string?                   — 可选描述
end
```

**内建自注册**：

```lua
nebula_register_shader_composer("instanced", {
  compose       = nebula_compose_shader_instanced,
  pipeline_flag = "standard_instanced",
  match         = function(reg, feats)
    return not reg.text_mode and not feats.has_shadow
  end,
  priority      = 0,
  description   = "标准 Visual 的 Instanced SDF 着色器（默认路径）",
})

nebula_register_shader_composer("shadow", {
  compose       = nebula_compose_shadow_shaders,
  pipeline_flag = "has_shadow",
  match         = function(reg, feats)
    return not reg.text_mode and feats.has_shadow
  end,
  priority      = 10,
  description   = "阴影多 Pass 路径",
})

nebula_register_shader_composer("text_sdf", {
  compose       = nebula_compose_text_shader,
  pipeline_flag = "textured",
  match         = function(reg, feats)
    return reg.text_mode == "ascii_sdf"
  end,
  priority      = 20,
  description   = "SDF Atlas 文本着色器",
})

nebula_register_shader_composer("slug", {
  compose       = nebula_compose_slug_shader,
  pipeline_flag = "slug_text",
  match         = function(reg, feats)
    return reg.text_mode == "slug"
  end,
  priority      = 20,
  description   = "Slug 矢量文本着色器",
})

nebula_register_shader_composer("dense_text", {
  compose       = nebula_compose_dense_text_shader,
  pipeline_flag = "atlas_dense",
  match         = function(reg, feats)
    return reg.text_mode == "dense"
  end,
  priority      = 20,
  description   = "高密度 Instanced 文本着色器",
})
```

**用户扩展示例**：

```lua
-- 用户注册图片纹理着色器
nebula_register_shader_composer("image_texture", {
  compose = function(opts)
    return {
      source = opts.wgsl_struct .. [[
        @group(0) @binding(0) var<uniform> vp: NebulaViewport;
        @group(0) @binding(1) var<storage, read> instances: array<]] .. opts.struct_name .. [[>;
        @group(0) @binding(2) var img_tex: texture_2d<f32>;
        @group(0) @binding(3) var img_sampler: sampler;
        // ... 顶点 + 片段着色器 ...
      ]],
      features = {"image_texture", "instanced", "textured"},
      required_passes = {"main"},
      instanced = true,
    }
  end,
  pipeline_flag = "image_textured",  -- 需同时注册对应管线
  match = function(reg, feats)
    return reg.render_mode == "image"
  end,
  priority = 30,
  description = "图片纹理着色器",
})
```

### 3.4 `nebula_derive()` 分发改造

**改造前**（`nebula_derive_engine.nelua:1310-1416`，硬编码 if-else）：

```lua
function nebula_derive(type_name)
  local reg = nebula_registry[type_name]

  if reg.text_mode == "ascii_sdf" then
    return nebula_derive_text_visual(type_name)
  end
  if reg.text_mode == "slug" then
    return nebula_derive_slug_text_visual(type_name)
  end
  if reg.text_mode == "dense" then
    return nebula_derive_dense_text_visual(base, {...})
  end

  -- ... 标准路径：再判断 has_shadow vs instanced ...
  if feats.has_shadow then
    shadow_shaders = nebula_compose_shadow_shaders({...})
  end
  -- ...
  instanced_shader_result = nebula_compose_shader_instanced({...})
end
```

**改造后**（查注册表分发）：

```lua
function nebula_derive(type_name)
  local reg = nebula_registry[type_name]
  local feats = detect_shader_features(...)

  -- ★ Phase 5.3: 通过 NEBULA_SHADER_COMPOSERS 注册表分发
  -- 优先匹配用户指定的 shader_composer，否则按 match + priority 自动选择
  local composer = nebula_resolve_shader_composer(reg, feats)
  assert(composer, "no matching shader composer for " .. type_name)

  local compose_result = composer.compose({
    wgsl_struct  = layout.wgsl_struct,
    struct_name  = layout.wgsl_struct_name,
    has_radius   = feats.has_radius,
    has_border   = feats.has_border,
    sdf_shape    = reg.sdf_shape,  -- ★ Phase 5.3: 传递 SDF 形状名
    -- ... 其他字段 ...
  })

  -- 构建 pipeline_spec，使用 composer.pipeline_flag 激活对应管线
  local pipeline_spec = { ... }
  pipeline_spec[composer.pipeline_flag] = true
  -- ...
end
```

**分发辅助函数**：

```lua
-- 解析 shader composer：先查 annotate 中的显式声明，再按 match + priority 自动选择
function nebula_resolve_shader_composer(reg, feats)
  -- 1. 显式声明优先
  if reg.shader_composer then
    local c = NEBULA_SHADER_COMPOSERS[reg.shader_composer]
    assert(c, ("unknown shader_composer '%s'"):format(reg.shader_composer))
    return c
  end

  -- 2. 按 match + priority 自动选择
  local best, best_priority = nil, -1
  for _, composer in pairs(NEBULA_SHADER_COMPOSERS) do
    if composer.match and composer.match(reg, feats) then
      if composer.priority > best_priority then
        best = composer
        best_priority = composer.priority
      end
    end
  end
  return best
end
```

### 3.5 `nebula_annotate` 扩展

新增两个可选字段：

```lua
nebula_annotate(@MyVisual, {
  -- 现有字段...
  states = {"Default", "Hovered", "Pressed"},
  primitives = {"hoverable", "clickable"},

  -- ★ Phase 5.3 新增字段：
  sdf_shape       = "circle",        -- 可选，默认按 has_radius 自动选择
  shader_composer = "image_texture", -- 可选，默认按 match 自动选择
})
```

## 4. 实施计划

### Step 1: SDF 形状注册表 (`NEBULA_SDF_SHAPES`)

**改动文件**：`src/derive/shader_compose.lua`

- 将 `local WGSL_FRAGMENTS` 替换为全局 `NEBULA_SDF_SHAPES` 注册表
- 实现 `nebula_register_sdf_shape(name, spec)` 并添加校验逻辑
- 将 `sdf_rect` 和 `sdf_rounded_rect` 通过自注册方式注册
- 改造 `nebula_compose_shader_instanced()` 和 `nebula_compose_shadow_shaders()` 从注册表查 SDF
- 保持 `WGSL_FRAGMENTS` 为向后兼容别名

**验收标准**：
- 所有现有 smoke test 不变绿不变红
- 新增 smoke test 验证：注册自定义 SDF → compose 输出包含该 SDF 函数

### Step 2: 着色器组合器注册表 (`NEBULA_SHADER_COMPOSERS`)

**改动文件**：`src/derive/shader_compose.lua`（注册表定义 + 内建自注册）

- 实现 `NEBULA_SHADER_COMPOSERS` 注册表
- 实现 `nebula_register_shader_composer(name, spec)` 并添加校验逻辑
- 将 5 个内建组合器通过自注册方式注册
- 实现 `nebula_resolve_shader_composer(reg, feats)` 分发函数

**验收标准**：
- 组合器自注册后，`NEBULA_SHADER_COMPOSERS` 包含全部 5 个内建条目
- `nebula_resolve_shader_composer` 在各种 `text_mode` / `has_shadow` 组合下返回正确的组合器

### Step 3: derive engine 分发改造

**改动文件**：`src/nebula_derive_engine.nelua`

- 将 `nebula_derive()` 中的 if-else 链替换为 `nebula_resolve_shader_composer()` 调用
- 文本模式的三个特化分支（ascii_sdf / slug / dense）迁移为 composer match 逻辑
- `nebula_annotate` 新增 `sdf_shape` 和 `shader_composer` 可选字段

**验收标准**：
- 所有现有 example demo 编译输出不变
- `nebula_annotate` 中指定 `shader_composer = "instanced"` 等同于不指定

### Step 4: 公理校验集成

**改动文件**：`src/derive/axiom_validator.lua`

- 在 `nebula_validate_visual` 中新增校验：
  - 若声明 `sdf_shape`，必须已注册于 `NEBULA_SDF_SHAPES`
  - 若声明 `shader_composer`，必须已注册于 `NEBULA_SHADER_COMPOSERS`
  - SDF 的 `extra_fields` 必须在 Visual base_fields 中存在

**验收标准**：
- 声明不存在的 sdf_shape → 编译期断言失败并给出明确错误信息
- 声明 sdf_shape = "circle" 但 Visual 无 radius 字段 → 断言失败

### Step 5: Smoke Test 全覆盖

**新增文件**：`tests/smoke_phase5_3_s1.lua` ~ `tests/smoke_phase5_3_s4.lua`

- S1: `NEBULA_SDF_SHAPES` 内建自注册 + `nebula_register_sdf_shape` 自定义注册 + 重复注册拦截
- S2: `NEBULA_SHADER_COMPOSERS` 内建自注册 + `nebula_register_shader_composer` + 匹配逻辑
- S3: compose 函数从注册表查 SDF → 输出正确 WGSL
- S4: `nebula_resolve_shader_composer` 分发逻辑 + 显式声明优先级

## 5. 向后兼容保证

| 现有用法 | Phase 5.3 后行为 | 变化 |
|---------|-----------------|------|
| `nebula_compose_shader_instanced({...})` | 不变，函数仍存在 | 无 |
| `nebula_compose_shadow_shaders({...})` | 不变 | 无 |
| `nebula_compose_text_shader({...})` | 不变 | 无 |
| `nebula_compose_slug_shader({...})` | 不变 | 无 |
| `nebula_compose_dense_text_shader({...})` | 不变 | 无 |
| `WGSL_FRAGMENTS.sdf_rect` | 保留为别名，指向注册表 | 无 |
| `nebula_annotate` 无 sdf_shape 字段 | 按现有逻辑自动选择 | 无 |
| `nebula_register_pipeline(...)` | 不变，两层独立 | 无 |

## 6. 三层渲染注册表最终全景

Phase 5.3 完成后，渲染侧可编程架构：

```
用户代码:
  nebula_register_sdf_shape("star", {...})
  nebula_register_shader_composer("gradient_fill", {...})
  nebula_register_pipeline("gradient_instanced", {...})

  nebula_annotate(@MyVisual, {
    sdf_shape = "star",
    shader_composer = "gradient_fill",
  })

编译期:
  nebula_derive("MyVisual")
    → NEBULA_SHADER_COMPOSERS["gradient_fill"].compose({
        sdf_shape = "star",
        ...
      })
      → NEBULA_SDF_SHAPES["star"].wgsl_source 注入着色器
      → 返回 {source = "...", pipeline_flag = "gradient_instanced", ...}
    → NEBULA_PIPELINES["gradient_instanced"].generate(spec)
      → 生成 Nelua 管线代码

运行时: 零开销（所有选择在 S1 编译期消解）
```

与交互侧完全对称：

| | 交互侧 | 渲染侧 |
|---|--------|--------|
| 原子单元 | 原语 (primitive) | SDF 形状 (shape) |
| 组合策略 | 状态机编织 (auto) | 着色器组合器 (composer) |
| 管线生成 | — | 管线注册表 (pipeline) |
| 注册 API | `register_primitive()` | `register_sdf_shape()` + `register_shader_composer()` |
| 选择方式 | `primitives = [...]` | `sdf_shape = "..."` + `shader_composer = "..."` |
| 公理校验 | axiom_validator | axiom_validator (扩展) |

---

*Phase 5.3 — 让 Nebula 编译器的渲染侧达到与交互侧同等的可编程水平。*
