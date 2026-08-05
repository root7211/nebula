# Phase 6.4 — 文本优先的视觉打磨方案

> **目标**：消除 demo「无字界面」这一最大观感缺陷，并把设计系统从颜色表升级为完整 token 阶梯。
> **约束**：全部改动必须通过 `axiom_validator` 校验，不引入任何 S2 期抽象。

## 问题诊断

Phase 6.0–6.3 补齐了渐变（6.1）、语义主题（6.2）、Shadow Sugar（6.3），GPU 能力已相当完整。但 `docs/screenshots/*.png` 的观感仍显粗糙，根因**不在渲染器**。

### 缺口 1（P0）：屏幕上没有一个字

`docs/screenshots/login_default.png` 呈现为三个色块，无 "Email" / "Password" / "Sign In" 任何标签。

`examples/login_v2_demo.nelua:62-70` 用**蓝色小长条假装标题**：

```nelua
-- 标题栏（蓝色短横线）
app .. ".title_bar:init(TitleBarVisual{",
"    pos=Vec2{x=310,y=190}, size=Vec2{x=180,y=4}, radius=2.0,",
```

`examples/counter_demo.nelua:44` 的计数值走 `printf` 打到终端 stdout，**不在窗口内**：

```nelua
('  printf("count = %%d, doubled = %%d\\n", %s.count, %s.doubled)')
```

**事实核定**（避免误判）：

- L2 的 `nebula_app` **已支持** `texts` 字段（`nebula_sugar.nelua:557`，于 `:751` 转发至 `nebula_app_register_text`）。文本标签是可表达的。
- 但 `NEBULA_PRIMITIVES`（`interaction_factory.lua:160-419`）9 个原语全为交互类，无 `label`。
- `NEBULA_BUILTIN_SPECS`（`builtin_factory.lua:791-796`）5 个能画字的 builtin（`line_nums` / `status_bar` / `search_bar` / `edit_area` / `term_grid`）全部硬绑 `nebula_editor`，非编辑器场景不可复用。

**真正的缺口是「对齐」，不是「文本能力」。** `bound_to`（`app_factory.lua:248`）只做**内容**绑定——把 editable 的输入同步进文本 mesh（`app_factory.lua:993-1013`），**不做任何位置计算**。

证据在 L0 版 demo。`examples/login_demo.nelua:247-249` 为对齐 `:192-193` 的输入框，手写了偏移：

| 元素 | 位置 | 来源 |
|---|---|---|
| `email_input` | `x=252, y=196` | `login_demo.nelua:192` |
| `email_label` | `x=260, y=212` | `login_demo.nelua:248` |

偏移量 `(+8, +16)` 是开发者人肉算出来的。**这是典型的 S1 期可推导量却下沉到手写常量** —— 输入全部在编译期已知（两者的 rect、字号、字体 metrics），依公理 A 判定准则第 2 条，它属于 S1。

### 缺口 2（P1）：单一字重

`tools/font_preprocessor.nelua:56-60` 硬编码：

```nelua
local FONT_PATH <const> = "assets/fonts/JetBrainsMono-Regular.ttf"
local PIXEL_HEIGHT <const> = 48.0
```

仅 Regular 一个字重。标题与正文无法形成对比，界面必然扁平。

### 缺口 3（P2）：主题只有颜色

`themes/nebula_themes.lua` 与 `nebula_theme.nelua` 只定义颜色 token，缺 spacing / radius / typography / elevation 阶梯。后果是 `login_v2_demo` 手写 20+ 个魔法坐标，无间距节奏。

另有对比度问题：卡片 `0.10` vs 背景 `0.05`（`login_v2_demo.nelua:46,52`），亮度差 0.05，层次几乎不可辨。

### 缺口 4（P3）：Layout engine 建好了没人用

`layout_engine.lua:46-250` 已实现完整 flexbox（row/column、flex_grow、flex_basis、gap、padding、justify、align），但 `login_v2_demo` 全用绝对坐标。此项为 Phase 6.0 遗留缺口 #4，至今未闭合。

---

## 公理合规性审查

每项改动逐条对照 `axiom_validator.lua` 的实际校验逻辑，而非仅对照文档。

### P0 label — 需按公理 C 设计，不可走捷径

**被否决的朴素方案**：给 Visual record 加 `text: [N]uint8` 字段。

两处硬性阻挡：

1. **公理 B 白名单**（`axiom_validator.lua:36-46`）仅允许 `float32 / Vec2 / Vec4 / Color / bool / uint8 / uint16 / uint32 / int32`。裸数组类型不在其中（仅 `NebulaBuf{N}` 经 `is_nebula_buf_type` 特批）。校验器的修复建议（`:126`）明确指路：

   > · 若需要文本渲染，请使用 nebula_app_register_text 注册独立的 TextContext

2. **公理 C 路径互斥**。`infer_pipeline_path`（`:147-166`）返回三个互斥值之一：`standard_instanced` / `textured_vertex` / `shadow_multipass`。一个 Visual 同时是形状与文本 → `nebula_validate_app_pipelines`（`:171-216`）报「管线路径冲突」，编译失败。

**采纳方案**：形状与文本保持为两个 Visual，各自签名唯一，公理 C 完好。新增的只是 S1 期对齐推导：

```nelua
## nebula_app("LoginApp", {
##   components = {{ name = "login_btn", type = "BtnVisual" }},
##   texts = {{ name = "login_label", type = "LabelVisual",
##              mode = "static",
##              anchor_to = "login_btn",      -- ★ 新增：几何锚定
##              align = "center",             -- ★ 新增：对齐方式
##              text = "Sign In" }},
## })
```

命名刻意区分 `anchor_to`（几何）与既有 `bound_to`（内容），避免语义混淆；两者可正交组合。

`anchor_to` 的解算完全是编译期算术——读锚点组件已解算的 rect，加字体 metrics（`NEBULA_ASCII_PIXEL_HEIGHT`、ascent/descent），算出 text origin 并烘焙为字面量：

```
origin_x = rect.x + (rect.w - text_len * advance * scale) / 2   -- center
origin_y = rect.y + (rect.h + (ascent + descent) * scale) / 2   -- 垂直居中
```

产出与 `login_demo.nelua:248` 的手写 `x=260, y=212` 同类，但由编译器推导。符合公理 A（输入 S1 全知）、不新增 L1 字段（公理 B 无影响）、不改管线签名（公理 C 无影响）。

### P1–P3 — 零公理影响

| 改动 | 判定 | 依据 |
|---|---|---|
| P1 多字重图集 | 零影响 | 纯 S0。`font_preprocessor` 正是公理 A 表格中 S0 的执行者 |
| P2 token 阶梯 | 零影响 | S1 期 Lua 表，与现有 `nebula_themes.lua` 同性质，宏展开即消解为字面量 |
| P3 demo 改 flexbox | 零影响，且**向公理靠拢** | `layout_engine.lua` 本身是 S1 求解器，结果烘焙为绝对坐标；替换手写常量是减少而非增加运行时行为 |

### P4 elevation — 一项被公理有意禁止的效果

`shadow_color` 是 L1 纯值，逐帧修改合法。

但 **`shadow_blur` / `shadow_offset` 不能动画**。原因不在公理 B，而在公理 A：4-pass 高斯的采样权重 `[0.227, 0.195, 0.122, 0.054, 0.016]` 于 S1 期烘焙进 shader（`shader_compose.lua:281-416`）。运行时改 blur 意味着重新组合 shader，即 S1 操作下沉到 S2，**违反阶段封闭性**。

故「hover 时阴影变大」不是未实现，而是被架构有意排除。可行替代：

- 动 `shadow_color.a`（纯 L1 值，合法）——推荐
- 预编译 2–3 档 blur 管线，S2 期切换——合规但需多份管线，Phase 6.5 再议

---

## 实施优先级

| 优先级 | 改动 | 影响面 | 观感收益 |
|---|---|---|---|
| **P0** | `anchor_to` + `align` 对齐推导；通用 `label` builtin（剥离 `build_status_bar:356-420` 的 editor 依赖） | `app_factory.lua`、`builtin_factory.lua`、`nebula_sugar.lua` | **最高** |
| P1 | `font_preprocessor` 参数化，增生 Bold / Medium 图集 | `tools/`、`assets/generated/` | 高 |
| P2 | 四组 token 阶梯 + `surface` 三层拆分 | `themes/nebula_themes.lua` | 中高 |
| P3 | `login_v2_demo` / `form_demo` 改 flexbox + token | `examples/` | 中（同时验证 layout engine 非编辑器路径） |
| P4 | 组件挂 elevation + hover 动 shadow alpha | `examples/`、`nebula_sugar.nelua` | 中 |

P2 建议阶梯：

```lua
spacing   = {4, 8, 12, 16, 24, 32}                  -- 8pt 网格
radius    = {sm=4, md=8, lg=12, xl=16, full=9999}
text      = {xs=11, sm=13, base=15, lg=18, xl=24, xxl=32}
elevation = {1={blur=4,y=1,a=.20}, 2={blur=8,y=2,a=.28}, 3={blur=16,y=4,a=.36}}
```

注：`text` 阶梯上限受 48px 图集约束，超过会糊（`text_runtime.nelua` scale 逻辑）。若需 >48px，应在 S0 期另生成大号图集。

## 已知限制（不在本 Phase 解决）

- 文字仅左对齐 + 固定基线（`text_runtime.nelua:203`）——P0 的居中在 S1 期算 origin 绕过，未改文本运行时
- 渐变硬编码 2 色标（`shader_compose.lua:237-244`）
- 圆角单一半径，无 per-corner
- 无 letter-spacing / 可调 line-height
- 无 inner shadow

## 验收标准

1. `tools/run_all_tests.sh` 全绿，`tests/golden` 无回归
2. `axiom_validator` 无新增违规
3. `login_v2_demo` 截图含可读文字标签，且无一处手写 label 坐标
4. `counter_demo` 计数显示在窗口内，非 stdout
5. 重生成 `docs/screenshots/*.png` 作为前后对照
