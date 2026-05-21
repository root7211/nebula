# Phase 5.4: 声明式动画系统深化 (Declarative Animation System)

**状态**：规划中
**前置依赖**：Phase 5.3 (渲染注册表)
**目标**：将现有 duration + tween 基础设施从"够用"提升到"完备"，在不违反三条公理的前提下覆盖现代 UI 动画需求

---

## 1. 现状分析：已有基础比预期更多

审查代码后发现，Nebula **并非没有动画系统**。`StateMachine` record 已包含：

```nelua
-- 已有（nebula_derive_engine.nelua:612-618）
global ButtonStateMachine = @record{
  current:  ButtonState,
  target:   ButtonState,
  progress: float32,      -- 0.0 → 1.0 归一化进度
  duration: float32,      -- 秒，编译期常量
  tween:    uint8,         -- 0=linear, 1=ease_out, 2=ease_in
}
```

用户已可在 transition 中声明 `duration` 和 `tween`：

```lua
-- 已有（shadow_demo.nelua）
transitions = {
  {from="default", to="hovered", tween="ease_out", duration=0.15},
  {from="hovered", to="pressed", tween="none",     duration=0.0},
}
```

`get_t()` 方法已实现 tween 分发（编译期 if-else 链）：

```nelua
-- 已有（nebula_derive_engine.nelua:676-681）
function ButtonStateMachine:get_t(): float32
  local t = self.progress
  if self.tween == 1 then return ease_out(t) end
  if self.tween == 2 then return ease_in(t) end
  return t
end
```

`ease_out` / `ease_in` 定义于 `nebula_types.nelua:129-139`：

```nelua
-- 已有：二次 ease
global function ease_out(t: float32): float32
  return 1.0 - (1.0 - t) * (1.0 - t)
end
global function ease_in(t: float32): float32
  return t * t
end
```

**结论**：骨架已在。缺的不是"动画系统"，而是以下五个维度的深化。

## 2. 缺口清单

### 缺口 A：Easing 曲线库太小

现状仅有 3 种：`none`（linear）、`ease_out`（二次）、`ease_in`（二次）。

现代 UI 需要：

| 曲线 | 用途 | 现状 |
|------|------|------|
| `linear` | 进度条、计时器 | ✅ 已有 (tween=0) |
| `ease_out` | 入场动画 | ✅ 已有，但仅二次 |
| `ease_in` | 退场动画 | ✅ 已有，但仅二次 |
| `ease_in_out` | 通用过渡 | ❌ 缺 |
| `ease_out_cubic` | 更平滑的入场 | ❌ 缺 |
| `ease_out_expo` | 弹幕式快入慢停 | ❌ 缺 |
| `spring` | 物理反弹（按钮、弹窗） | ❌ 缺 |
| `cubic_bezier(x1,y1,x2,y2)` | 自定义曲线（CSS 兼容） | ❌ 缺 |

### 缺口 B：`TWEEN_CODE` 注册表封闭

`TWEEN_CODE` 是 derive engine 中的 local table，硬编码 3 个条目：

```lua
-- 已有（nebula_derive_engine.nelua:587）
local TWEEN_CODE = { none = 0, ease_out = 1, ease_in = 2 }
```

用户无法注册自定义 easing。这与 Phase 4.4 的 `nebula_register_primitive` 精神不一致。

### 缺口 C：无 per-property 动画控制

目前 duration + tween 是 **per-transition** 的（from→to 级别）。所有属性（bg_color、border_color、radius 等）共享同一 duration 和 easing。

现实需求：

```lua
-- 期望：颜色快速过渡，圆角缓慢过渡
transitions = {
  {from="default", to="hovered",
   duration = 0.15, tween = "ease_out",
   overrides = {
     radius = { duration = 0.4, tween = "spring" },
   }},
}
```

### 缺口 D：无 delay（延迟启动）

无法声明"等待 0.1 秒后开始过渡"。stagger 动画（列表项依次入场）需要 delay。

### 缺口 E：sugar 层未暴露动画参数

`nebula_component("ButtonVisual", { primitives = {"clickable"} })` 自动推导 transitions 时，未注入 duration / tween。sugar 生成的 transitions 全部 duration=0（瞬时）。

## 3. 设计方案

### 3.1 公理合规性论证

| 新增能力 | S1 消解部分 | 运行时计算部分 | 公理 A 合规 |
|---------|------------|---------------|------------|
| 新 easing 函数 | 函数选择（tween code 映射） | `ease_fn(t)` 求值 | ✅ |
| per-property override | 哪些属性有 override、用哪个 easing | 独立的 `progress_<prop>` 累加 | ✅ |
| delay | delay 值（编译期常量） | `elapsed < delay` 判断 | ✅ |
| cubic_bezier | 控制点（编译期常量） | 牛顿迭代求 t（~5 次循环） | ✅ |
| spring | 刚度/阻尼（编译期常量） | 微分方程步进 | ✅ |

**公理 B**：所有新增状态（per-property progress、delay elapsed）都是 StateMachine record 的固定字段，编译期确定数量，无堆分配。

**公理 C**：不引入中间层。easing 只改变 `t` 的计算方式，`mix(a, b, t)` 调用链不变。

### 3.2 新增注册表：`NEBULA_EASINGS`

**位置**：`src/nebula_derive_engine.nelua`（替换 `TWEEN_CODE`）

```lua
NEBULA_EASINGS = {}

function nebula_register_easing(name, spec)
  -- name: string — easing 名称（如 "ease_out_cubic"）
  -- spec:
  --   code        : number    — 唯一整数编码（必须）
  --   nelua_expr  : string    — Nelua 表达式模板，%t 被替换为变量名（必须）
  --                            或 Nelua 函数名（如 "ease_out_cubic"）
  --   nelua_fn    : string?   — 如需额外函数定义，注入到全局作用域
  --   description : string?   — 可选描述
end
```

**内建自注册**：

```lua
nebula_register_easing("none",    { code = 0, nelua_expr = "%t" })
nebula_register_easing("ease_out",{ code = 1, nelua_expr = "ease_out(%t)" })
nebula_register_easing("ease_in", { code = 2, nelua_expr = "ease_in(%t)" })

nebula_register_easing("ease_in_out", {
  code = 3,
  nelua_expr = "ease_in_out(%t)",
  nelua_fn = [[
global function ease_in_out(t: float32): float32
  if t <= 0.0 then return 0.0 end
  if t >= 1.0 then return 1.0 end
  if t < 0.5 then return 2.0 * t * t end
  return 1.0 - (-2.0 * t + 2.0) * (-2.0 * t + 2.0) * 0.5
end]],
})

nebula_register_easing("ease_out_cubic", {
  code = 4,
  nelua_expr = "ease_out_cubic(%t)",
  nelua_fn = [[
global function ease_out_cubic(t: float32): float32
  if t <= 0.0 then return 0.0 end
  if t >= 1.0 then return 1.0 end
  local u = 1.0 - t
  return 1.0 - u * u * u
end]],
})

nebula_register_easing("ease_out_expo", {
  code = 5,
  nelua_expr = "ease_out_expo(%t)",
  nelua_fn = [[
global function ease_out_expo(t: float32): float32
  if t >= 1.0 then return 1.0 end
  return 1.0 - math.exp(-7.0 * t)
end]],
})

nebula_register_easing("spring", {
  code = 6,
  nelua_expr = "ease_spring(%t)",
  nelua_fn = [[
global function ease_spring(t: float32): float32
  if t <= 0.0 then return 0.0 end
  if t >= 1.0 then return 1.0 end
  -- 临界阻尼弹簧近似：overshoot ≈ 5%，settle at t=1.0
  local w = 8.0   -- 角频率
  local d = 0.65  -- 阻尼比
  return 1.0 - math.exp(-d * w * t) * math.cos(w * math.sqrt(1.0 - d*d) * t)
end]],
})
```

**用户扩展**：

```lua
nebula_register_easing("bounce", {
  code = 100,
  nelua_expr = "ease_bounce(%t)",
  nelua_fn = [[
global function ease_bounce(t: float32): float32
  -- ... bounce 实现 ...
end]],
})
```

### 3.3 `get_t()` 代码生成改造

**改造前**（硬编码 if-else）：

```lua
table.insert(lines, "  if self.tween == 1 then return ease_out(t) end")
table.insert(lines, "  if self.tween == 2 then return ease_in(t) end")
table.insert(lines, "  return t")
```

**改造后**（遍历注册表生成）：

```lua
-- 收集当前 Visual 实际使用的 easing codes
local used_codes = collect_used_easings(reg.transitions)
for _, entry in ipairs(used_codes) do
  if entry.code ~= 0 then  -- 0 = linear，fallthrough
    table.insert(lines, ("  if self.tween == %d then return %s end"):format(
      entry.code, entry.nelua_expr:gsub("%%t", "t")))
  end
end
table.insert(lines, "  return t")
```

优势：只生成当前 Visual **实际使用**的 easing 分支，死代码为零。

### 3.4 per-property 动画 override（Step 2）

**StateMachine record 扩展**：

对于声明了 override 的属性，编译器额外生成独立的 progress 字段：

```nelua
-- 编译器生成（仅当 transitions 中存在 overrides.radius 时）
global ButtonStateMachine = @record{
  current:  ButtonState,
  target:   ButtonState,
  progress: float32,
  duration: float32,
  tween:    uint8,
  -- ★ Phase 5.4: per-property override 字段
  progress_radius: float32,
  duration_radius: float32,
  tween_radius:    uint8,
}
```

**`gen_update_for` 改造**：

```lua
-- 改造前：所有属性共享一个 t
local t = self.sm:get_t()
self.current_radius = lerp_f32(get_radius(current), get_radius(target), t)

-- 改造后：有 override 的属性用自己的 t
local t = self.sm:get_t()
local t_radius = self.sm:get_t_radius()  -- 独立 progress + easing
self.current_radius = lerp_f32(get_radius(current), get_radius(target), t_radius)
```

编译期只为有 override 的属性生成额外字段和方法。没有 override 的属性继续用全局 t。零运行时开销增量。

### 3.5 delay 支持（Step 3）

transition 声明扩展：

```lua
transitions = {
  {from="default", to="hovered", tween="ease_out", duration=0.2, delay=0.05},
}
```

StateMachine.update 改造：

```nelua
-- 编译器生成
function ButtonStateMachine:update(dt: float32): void
  if self.progress >= 1.0 then ... return end
  if self.duration <= 0.0 then ... return end
  -- ★ Phase 5.4: delay 支持
  if self.delay > 0.0 then
    self.delay = self.delay - dt
    if self.delay > 0.0 then return end
    -- delay 用尽，将多余 dt 计入 progress
    dt = -self.delay
    self.delay = 0.0
  end
  self.progress = self.progress + dt / self.duration
  ...
end
```

StateMachine record 新增 `delay: float32` 字段（仅当任一 transition 使用 delay 时生成）。

### 3.6 sugar 层动画默认值

`nebula_component` 的 primitives 自动推导出的 transitions 默认注入 duration：

```lua
-- 改造前（sugar 推导）：
{from="default", to="hovered", on="hover_enter"}
-- duration 默认 0.0 → 瞬时跳变

-- 改造后：
{from="default", to="hovered", on="hover_enter",
 duration = NEBULA_ANIM_DEFAULTS.hover_enter or 0.12,
 tween = NEBULA_ANIM_DEFAULTS.hover_tween or "ease_out"}
```

`NEBULA_ANIM_DEFAULTS` 为全局编译期表，用户可覆盖：

```lua
-- 用户在 require "nebula_core" 后覆盖：
##[[ NEBULA_ANIM_DEFAULTS.hover_enter = 0.2 ]]
##[[ NEBULA_ANIM_DEFAULTS.hover_tween = "ease_out_cubic" ]]
```

## 4. 实施计划

### Step 1: Easing 注册表 + 曲线库扩展

**改动文件**：
- `src/nebula_derive_engine.nelua` — 替换 `TWEEN_CODE` 为 `NEBULA_EASINGS` 注册表 + `nebula_register_easing()`
- `src/nebula_types.nelua` — 新增 `ease_in_out` / `ease_out_cubic` / `ease_out_expo` / `ease_spring`
- `src/nebula_derive_engine.nelua` 的 `get_t()` 生成 — 改为遍历注册表

**验收标准**：
- `NEBULA_EASINGS` 包含 7 个内建 easing
- `nebula_register_easing("custom", {...})` 可注册自定义 easing
- 现有 shadow_demo.nelua 编译输出不变

### Step 2: per-property 动画 override

**改动文件**：
- `src/nebula_derive_engine.nelua` 的 `gen_state_machine` — 条件生成 per-property 字段
- `src/nebula_derive_engine.nelua` 的 `gen_update_for` — per-property `t` 分支

**验收标准**：
- 无 override 时生成代码与现有完全一致（diff 为零）
- 有 override 时仅为指定属性生成额外字段，其余属性不受影响

### Step 3: delay 支持

**改动文件**：
- `src/nebula_derive_engine.nelua` 的 `gen_state_machine` — 条件生成 `delay` 字段 + `transition_to` 中设置 delay + `update` 中消耗 delay

**验收标准**：
- 无 delay 声明时 StateMachine record 不包含 delay 字段
- delay=0.1 时动画在 0.1 秒后开始

### Step 4: sugar 层动画默认值 + `NEBULA_ANIM_DEFAULTS`

**改动文件**：
- `src/nebula_sugar.nelua` — primitives 推导 transitions 时注入默认 duration/tween
- `src/nebula_derive_engine.nelua` — 定义 `NEBULA_ANIM_DEFAULTS` 编译期表

**验收标准**：
- `nebula_component("Button", {primitives={"clickable"}})` 生成的 transitions 默认有 duration=0.12
- 用户可通过 `NEBULA_ANIM_DEFAULTS` 覆盖默认值

### Step 5: Smoke Test 全覆盖

**新增文件**：`tests/smoke_phase5_4_s1.lua` ~ `tests/smoke_phase5_4_s4.lua`

- S1: `NEBULA_EASINGS` 内建自注册 + 自定义注册 + 重复拦截 + `get_t()` 生成验证
- S2: per-property override — 有/无 override 时 StateMachine record 字段差异
- S3: delay — transition_to 生成代码中 delay 赋值 + update 中 delay 消耗逻辑
- S4: sugar 默认值 — primitives 推导 transitions 包含 duration/tween + `NEBULA_ANIM_DEFAULTS` 覆盖

## 5. 向后兼容保证

| 现有用法 | Phase 5.4 后行为 | 变化 |
|---------|-----------------|------|
| `tween="ease_out", duration=0.15` | 不变，`NEBULA_EASINGS["ease_out"].code == 1` | 无 |
| `tween="none", duration=0.0` | 不变 | 无 |
| 无 tween/duration 声明 | 不变（默认 linear/0.0） | 无 |
| `ease_out(t)` / `ease_in(t)` 全局函数 | 保留 | 无 |
| `TWEEN_CODE` | 保留为内部别名，指向 `NEBULA_EASINGS` | 无 |
| sugar 推导的 transitions | **变化**：注入默认 duration | 行为改善（有动画感） |

sugar 默认值是唯一的行为变化，但方向是正确的（从瞬时跳变 → 平滑过渡）。用户可通过 `NEBULA_ANIM_DEFAULTS.hover_enter = 0.0` 恢复旧行为。

## 6. 不做列表

以下需求不在 Phase 5.4 范围内：

- **Keyframe 时间轴**（0% → 50% → 100% 多停点）— 需要全新的 AnimationTrack 结构，复杂度远超 transition 扩展。留待 Phase 6+。
- **命令式 animate() API** — 违反公理 A（运行时决定动画参数）。不做。
- **动画链/序列** — 需要协程或状态机链接。留待 Phase 6+。
- **cubic_bezier(x1,y1,x2,y2)** — 需要编译期参数化 easing 函数生成。可作为 Step 1 的后续扩展，不阻塞主流程。

## 7. 改动面估算

| Step | 文件数 | 新增/改动行数（估） | 风险 |
|------|--------|---------------------|------|
| Step 1 | 2 | ~80 行 | 低（纯追加） |
| Step 2 | 1 | ~60 行 | 中（gen_update_for 逻辑分支） |
| Step 3 | 1 | ~30 行 | 低（条件字段 + update 守卫） |
| Step 4 | 2 | ~40 行 | 低（sugar 表拼接） |
| Step 5 | 4 | ~200 行 | 无（测试） |
| **合计** | **~5 文件** | **~410 行** | |

---

*Phase 5.4 — 不是构建新的动画系统，而是把已有的 duration+tween 基础设施从 3 种 easing 扩展到可注册的完整曲线库，并补齐 per-property override、delay、sugar 默认值三个维度。*
