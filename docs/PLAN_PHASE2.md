# Phase 2 开发计划：从"形即数据"到"形即渲染"

> **总目标**：让"形状的声明"在编译期被消化的范围从"数据布局 + 状态机"扩展到"渲染策略 + 内存对齐 + 碰撞检测"。Phase 2 完成后，开发者编写一个新的 `Visual` 规格时，**不需要再触碰任何 WGSL 源码、`_pad` 字段或 AABB 表达式**；这些产物全部由 `nebula_core` 在编译期从字段集合推导出来。

本文档与 `docs/DESIGN_PHASE1.md` 配套，沿用相同的"目标 → API 契约 → 实现策略 → 验收标准"叙述结构。

---

## 1. 现状基线（Phase 1 完成态）

| 改造点 | 现状文件 | 现状形态 | Phase 2 目标形态 |
|---|---|---|---|
| Uniform 布局 | `src/renderer.nelua` 第 230–262 行 | 96 字节 `NebulaRectUniforms` 含 8 个手写 `_pad`，注释手工标注每个 offset | 由 `nebula_gen_uniform_record(type_name)` 在编译期生成完整 record，开发者不再可见 `_pad*` |
| WGSL 着色器 | `src/renderer.nelua` 第 268–337 行 | 硬编码字符串 `RECT_SHADER_WGSL`，固定 SDF 圆角矩形 + 边框 + AA | 由 `nebula_gen_wgsl_shader(type_name)` 按字段组合 fragment 片段（`radius` ⇒ SDF 分支，`shadow` ⇒ 高斯模糊 Pass，`bg_color` ⇒ 填充项，`border_*` ⇒ 描边项） |
| 碰撞检测 | `src/primitives.nelua` 中 `HoverableState:update` 接收 `(mx,my,px,py,sw,sh)` | demo 必须自己拆开 `visual.pos.x / pos.y / size.x / size.y` 传进去 | 派生器在 `<T>Context:update` 内自动生成 `self.hover:update(mx, my, &self.visual)`；`HoverableState` 接收 `*Visual` 并由派生器内联展开几何字段访问 |
| 渲染管线创建 | `src/renderer.nelua` 第 342–492 行 | 单一 `NebulaRectPipeline`，所有 demo 共用相同的 BindGroupLayout/着色器 | 由 `nebula_gen_pipeline_for(type_name)` 在编译期为每种 `Visual` 生成专属 pipeline 创建器，使用本类型的自动 Uniform record + 自动 WGSL |

> **零回退保证**：所有 Phase 0 / Phase 1 已通过的产物（`button_demo`、`login_demo` 编译输出、`tools/headless_test.c` 渲染回归）必须在 Phase 2 完成时仍然成立。`renderer.nelua` 的现有手写 `NebulaRectUniforms` / `RECT_SHADER_WGSL` 在子阶段 2.1～2.3 之间作为"对照参考实现"保留，最终在子阶段 2.4 移除。

---

## 2. 子阶段拆分

Phase 2 分为四个子阶段，每个子阶段都有独立的、可单独验证的产物。每个子阶段在合并前都必须通过编译 + Xvfb 运行 + headless_test.c 渲染回归三重检验。

### Phase 2.1 — Uniform std140 自动对齐

**目标**：消除手写 `_pad`，由编译期推导器按 WebGPU std140 规则填充。

**新增 API**：

```lua
nebula_gen_uniform_layout(type_name) -> {
  fields    = { {name, type, offset, size, padding}, ... },
  total_size,                         -- 16 字节对齐后的总长度
  wgsl_struct,                        -- 对应的 WGSL struct 字符串
  nelua_record_source,                -- 对应的 Nelua record 源代码（含 _pad 自动填充）
}
```

**内部规则（std140 子集，足以支撑 Phase 2 demo）**：

| WGSL 类型 | 对齐 | 大小 |
|---|---:|---:|
| `f32` | 4 | 4 |
| `vec2<f32>` | 8 | 8 |
| `vec3<f32>` | 16 | 12 |
| `vec4<f32>` | 16 | 16 |
| `mat4x4<f32>` | 16 | 64 |

总大小向 16 对齐。`Vec2`、`Vec4`、`Color` 沿用 Phase 0 已有映射。Phase 2 暂不支持 array/struct 嵌套（划入 Phase 2.5+）。

**字段排列策略**：

1. 先放所有 `base_fields`（视觉规格的非状态字段，如 `pos`、`size`、`radius`）。
2. 再按字典序放所有 `props`（动画插值字段，如 `bg_color`、`border_color`、`border_width`）。
3. 末尾追加 `viewport: Vec2`。
4. 在每个字段前插入零或多个 `_pad<N>: f32` 把 offset 补到对齐边界。

**验收**：
- 对 `ButtonVisual` 调用 `nebula_gen_uniform_layout("ButtonVisual").total_size` 必须 ≥ 96（与现行手写一致或更紧凑）。
- 自动生成的 `nelua_record_source` 与 `wgsl_struct` 字段顺序一一对应，逐字段 offset 相等（用 Lua 单元测试断言）。
- 把自动生成的 record 替换 `NebulaRectUniforms`，`button_demo` 与 `login_demo` 仍然渲染正确（headless_test.c 保存的 PPM 像素 diff 必须为 0）。

**预计工作量**：1.5 个工作日。

---

### Phase 2.2 — WGSL 着色器按字段组合

**目标**：把 `RECT_SHADER_WGSL` 的硬编码字符串替换为按字段拼装的"片段编排器"，开发者只通过字段集合声明渲染意图。

**新增 API**：

```lua
nebula_gen_wgsl_shader(type_name) -> {
  source,                 -- 完整 WGSL 源码（含 vs_main + fs_main）
  features,               -- {has_radius, has_border, has_shadow, ...}
  required_passes,        -- {"main"} 或 {"shadow_blur","main"}
}
```

**字段 → 着色器片段映射表**（Phase 2 起步集合）：

| 字段名（在 `Visual` 中出现） | 注入的着色器行为 |
|---|---|
| `radius: float32` | `sdf_rounded_rect(...)` 取代默认矩形测试 |
| `bg_color: Color` | `fill_alpha = 1 - smoothstep(-aa, aa, dist); color = bg * fill_alpha` |
| `border_color: Color` 且 `border_width: float32` | 追加 `border_alpha` 计算并叠加到 `color` |
| `shadow_color: Color` 且 `shadow_offset: Vec2` 且 `shadow_blur: float32` | 在主 fragment 之前生成一个高斯模糊 Pass（先在 Phase 2.3 完成 Pass 串联） |

**实现策略**：

- 维护一个 Lua 表 `WGSL_FRAGMENTS = { radius=..., border=..., shadow=... }`，每个值是一个返回 WGSL 代码段的函数。
- `nebula_gen_wgsl_shader` 根据当前 type 的 `props + base_fields` 决定调用哪些片段，按固定顺序拼接：`shadow_pre → fill → border → discard_clip`。
- 顶点着色器（全屏三角形）保持唯一；fragment 着色器按片段拼装。
- 编译期 `print` 出 `[shader] <Type>: features=[radius, border]` 便于调试。

**验收**：
- 对 `ButtonVisual` 自动生成的着色器必须与现行 `RECT_SHADER_WGSL` **逐字符等价**（白名单字段下，作为回归基线）。
- 新增一个 `examples/shadow_demo.nelua`：在 `ButtonVisual` 上加 `shadow_color/shadow_offset/shadow_blur` 字段，验证自动注入的高斯模糊 Pass 能产生预期的阴影效果（headless 渲染对比固定 PPM 基线）。
- 移除 `RECT_SHADER_WGSL` 字符串后，`./build.sh button_demo` / `./build.sh login_demo` 仍然成功。

**预计工作量**：3 个工作日（其中阴影 Pass 单独 1 天）。

---

### Phase 2.3 — 渲染管线工厂自动派生

**目标**：让 `nebula_derive` 顺带派生本类型的 `<T>Pipeline:init/update_uniforms/draw`，从 `renderer.nelua` 中剥离对特定 `NebulaRectUniforms` 的依赖。

**新增 API**（在派生器内部组合）：

```nelua
## nebula_derive("ButtonVisual")
-- 自动展开包含：
--   global ButtonUniforms    = @record{ ... 自动 std140 ... }
--   global ButtonShader      = "wgsl source ..."   -- 编译期常量字符串
--   global ButtonPipeline    = @record{ pipeline, bind_layout, uniform_buf, bind_group }
--   ButtonPipeline:init(renderer): boolean
--   ButtonPipeline:update_uniforms(renderer, *ButtonUniforms): void
--   ButtonPipeline:draw(pass): void
```

**实现策略**：

- 把现行 `NebulaRectPipeline` 拆成两层：
  - 顶层 `NebulaPipelineBase`（`renderer.nelua`）保留 BindGroupLayout/PipelineLayout 创建、Surface 与 Queue 引用等"与 Visual 类型无关"的基础设施。
  - 派生层 `<T>Pipeline`（由 `nebula_derive` 注入）持有特定的 Uniform 类型与着色器字符串，在 `init` 中调用基础设施。
- `<T>Context:to_uniforms` 的返回类型从硬编码的 `NebulaRectUniforms` 改为 `<T>Uniforms`。
- 多 Pass 渲染（如带阴影）在 `<T>Pipeline:draw` 中按 `required_passes` 顺序调用对应 sub-pipeline。

**验收**：
- `login_demo` 中四种组件（Card/Input/Button × 2）现在分别使用 `CardPipeline`、`InputPipeline`、`ButtonPipeline`，`renderer.nelua` 中不再出现任何 `Rect*` 命名。
- `RECT_SHADER_WGSL` 与 `NebulaRectUniforms` 在本子阶段末尾从仓库中删除；`tools/headless_test.c` 改为以 `ButtonUniforms` 自动生成的产物作为对照。
- 编译期日志输出形如：
  ```text
  [derive] ButtonVisual: emit State + StateMachine + Context + Uniforms + Shader + Pipeline (3 props, 4 transitions)
  [shader] ButtonVisual: features=[radius, fill, border]  (96B uniforms, 1 pass)
  ```

**预计工作量**：2 个工作日。

---

### Phase 2.4 — 交互原语自动派生（碰撞检测内联）

**目标**：`HoverableState` 不再要求 demo 解构 `pos.x/pos.y/size.x/size.y`，由派生器从字段集合自动生成 AABB 调用。

**新增机制**：

- 派生器扫描 `Visual` 字段，识别"几何字段约定"：
  - `pos: Vec2` + `size: Vec2` → 矩形包围盒（Phase 2 唯一支持的形状）。
  - 未来可扩展 `center: Vec2` + `radius: float32` → 圆形包围盒。
- `HoverableState:update` 重新设计为接收 `*<T>Visual`，AABB 比较在 `<T>Context:update` 内联展开（避免反射）。
- 派生器把展开形式直接 emit 出去，例如：

  ```nelua
  -- 编译期生成
  self.hover.is_hovered = (mx >= self.visual.pos.x and
                           mx <= self.visual.pos.x + self.visual.size.x and
                           my >= self.visual.pos.y and
                           my <= self.visual.pos.y + self.visual.size.y)
  ```

  完全消除原 `HoverableState:update` 的函数调用层。

**验收**：
- `examples/button_demo.nelua` 与 `examples/login_demo.nelua` 在 demo 侧不变。
- `primitives.nelua` 的 `HoverableState:update` 函数被删除；`HoverableState` 退化为纯 record。
- `nm ~/.cache/nelua/button_demo` 中找不到 `HoverableState_update` 符号，证明确实零运行时调用。

**预计工作量**：1 个工作日。

---

## 3. 关键风险与缓解

| 风险 | 触发场景 | 缓解策略 |
|---|---|---|
| std140 推导与 wgpu-native 校验不一致 | WebGPU 在某些后端（如 Metal/MoltenVK）对 vec3 对齐更严格 | 子阶段 2.1 内增加 `tools/uniform_layout_check.c` 离线验证表；先支持 vec2/vec4，避免 vec3 |
| Shader 片段拼接顺序错误导致渲染破洞 | `border` 在 `shadow` 之前合成造成阴影遮挡边框 | 在 `WGSL_FRAGMENTS` 中显式编排 `(shadow_pre → fill → border → clip)` 顺序，并在 `tests/render_baseline/` 提交多张 PPM 基线 |
| Phase 2.3 多 Pass 拖慢 `headless_test.c` | 阴影模糊 Pass 在无 GPU 的 CI 环境里耗时陡增 | headless 测试默认只跑单 Pass；阴影 Pass 设独立 flag，本地手动执行 |
| 派生器代码膨胀，`nebula_core.nelua` 难以维护 | Phase 2 末，派生器源码可能从现 ~500 行涨到 ~1500 行 | 把派生器拆成 `src/derive/` 子目录：`uniform_layout.lua`、`shader_compose.lua`、`pipeline_factory.lua`、`primitive_inline.lua`；通过 `## require` 在编译期加载 |

---

## 4. 整体里程碑与版本管理

| 子阶段 | 分支 | 计划 tag | 依赖 |
|---|---|---|---|
| 2.1 Uniform 布局自动化 | `phase2-uniform` | `phase2.1-v0.1` | 仅 Phase 1 |
| 2.2 WGSL 着色器组合 | `phase2-shader` | `phase2.2-v0.1` | 2.1（共享 `wgsl_struct`） |
| 2.3 管线工厂派生 | `phase2-pipeline` | `phase2.3-v0.1` | 2.1 + 2.2 |
| 2.4 原语内联展开 | `phase2-primitive` | `phase2.4-v0.1` | 2.3 |
| 总验收 | `phase2-final` | `phase2-v0.1`（指向合并后 main） | 上述全部 |

每个子阶段的 PR 必须包含：

1. 修改的派生器源代码 + 必要的回归测试（PPM、字节比较、符号比较）。
2. 更新 `docs/PHASE2_PROGRESS.md`（每完成一个子阶段，追加一节"实测产物 + 与基线 diff"）。
3. 编译产物的 binary diff（用 `wc -c` 与 `nm` 摘要附在 PR description）。

---

## 5. 验收标准（Phase 2 总体）

完成 Phase 2 时，下列断言必须同时成立：

1. **零样板**：`grep -c "_pad" src/` 应输出 0；`grep -c "RECT_SHADER_WGSL" src/` 应输出 0。
2. **渲染一致**：`tools/headless_test.c` 输出的 PPM 与 Phase 1 基线逐像素一致（容忍 0 差异）。
3. **新增 demo**：`examples/shadow_demo.nelua` 仅声明 `ButtonVisual + shadow_*` 字段，不写一行着色器/管线代码即可渲染出阴影按钮。
4. **派生信息完整**：编译期对每个 Visual 输出形如：
   ```text
   [derive] FooVisual: emit State + StateMachine + Context + Uniforms + Shader + Pipeline (N props, M transitions)
   [shader] FooVisual: features=[radius, fill, border, shadow]  (XB uniforms, P passes)
   ```
5. **原语零调用**：`nm ~/.cache/nelua/button_demo | grep -c HoverableState_update` 输出 0。
6. **Phase 0/1 文档承诺兑现**：README "Phase 2 展望"三条全部勾掉，整个章节改写为"Phase 2 已交付"。

---

## 6. 不在 Phase 2 范围

下列工作明确推迟到后续阶段，避免计划膨胀：

- **多组件布局**（`@layout` 宏 + Flexbox 编译期解算）→ Phase 3。
- **文本渲染管线**（字形光栅化 / 图集 / Shaping）→ Phase 4。
- **动态列表与条件渲染**（运行时对象池）→ Phase 4+。
- **`login_demo` 多管线运行时显示问题**：仍作为独立 issue 跟踪（Phase 0 遗留），不阻塞 Phase 2 主线。
- **vec3 / 嵌套 struct / array 的 std140 支持**：Phase 2.5 视需求增量。

---

## 7. 时间盒与启动建议

| 周次 | 内容 |
|---|---|
| 第 1 周 | Phase 2.1 + 2.2 着手；建立 `tests/render_baseline/` 基线快照 |
| 第 2 周 | Phase 2.3 完成；删除 `RECT_SHADER_WGSL` / `NebulaRectUniforms` |
| 第 3 周 | Phase 2.4 + `shadow_demo`；总验收、文档收尾、合并 `phase2-final` |

启动顺序建议**严格串行**（2.1 → 2.2 → 2.3 → 2.4），因为后一阶段的修改半径完全包含前一阶段的接口；并行只会引入不必要的 merge conflict。

Phase 2 完成的判定信号：当一个新的 `Visual` 规格被加进 `examples/`，开发者既不需要打开 `renderer.nelua`，也不需要打开 `primitives.nelua` —— 这正是"形即渲染"应有的样子。
