# Nebula 架构总纲领：在极致哲学下的最终综合方案

**作者**：Manus AI
**日期**：2026-04-24
**版本**：v1.0（涵盖 Phase 0 至 Phase 3.6.1 全部既成事实，并指导 Phase 3.6.2 至 Phase 5 的演进）
**适用范围**：所有未来 Phase 规划、所有 PR 评审、所有架构决策

---

## 序言

Nebula GUI Compiler 在过去十二个 Phase 中，从一个"形即数据"的玩具逐步演化为一个具备 SDF 文本、动态列表、Gap Buffer 文本编辑能力的 GUI 框架。然而，正是这种演化的层叠性，使得当前代码库中沉积了**多个不同时代的架构残骸**：占位符着色器路径、混生的管线工厂、模糊的状态/渲染边界、以及若干未被严格执行的哲学承诺。

本纲领的目的不是再增加一个 Phase，而是**对整个架构做一次"总清算"**：把哲学公理化、把含混的边界形式化、把所有现存与潜在的冲突彻底消除，并据此给出一份贯穿整个剩余生命周期的演进路线图。

---

## 1. 三大哲学公理与一条元规则

为了让"哲学"不再是模糊的口号，本纲领将散落于 `DESIGN_PHASE1.md`、`PLAN_PHASE2.md`、`PLAN_PHASE3_6.md` 等文档中的核心承诺，正式公理化为三条不可违反的规则，外加一条用于裁决冲突的元规则 [1] [2] [3]。

**公理 A（编译期最大化原则）**：任何能在编译期确定的事实，必须在编译期确定。Nelua 宏（`##`）是 Nebula 唯一合法的编译期推导通道；运行时不应出现可由编译期消除的虚函数分发、字符串查表或 `if reg.has_xxx then` 风格的特性开关。

**公理 B（生命周期严格分层原则）**：Nebula 中只存在两种内存生命周期，且必须显式归属之一：

| 层 | 名称 | 生命周期 | 合法存储位置 | 典型数据 |
| :--- | :--- | :--- | :--- | :--- |
| **L1** | 持久层（Persistent） | 跨帧存活 | 栈分配的静态 Record、编译期定容容器（如 Gap Buffer） | 文本内容、焦点 ID、状态机当前态、Toggle 开关 |
| **L2** | 帧级层（Transient） | 单帧瞬时 | Frame Arena | 排版结果、动态列表实例数据、本帧收集的批量 Uniforms |

**公理 C（形即渲染原则）**：每一个 `Visual` 类型必须拥有一条专属的、按字段精确组合而成的渲染管线。运行时不应存在"通用渲染器"，也不应存在通过运行时分支选择字段集合的着色器。

**元规则（Π，冲突裁决）**：当公理 A、B、C 出现冲突时，按 **B > C > A** 的优先级裁决。即：宁可放弃部分编译期推导，也要保住生命周期的严格分层；宁可让多个 `Visual` 共用底层管线生成器，也要保住生命周期的严格分层。

> 示例：Phase 3.6.1 的编译期定容 Gap Buffer 看似违反公理 A（容量在编译期硬编码无法运行时增长），实则是公理 B 在 L1 层的最优实现——它用编译期决策换取了零堆分配，是 A 与 B 的协同而非冲突。

---

## 2. 当前代码库的架构盘点：八处张力点

本节基于对 `src/` 目录全部 6,512 行代码、`docs/` 目录全部 16 篇规划文档、以及 `examples/` 目录全部演示的逐行审计，识别出截至 Phase 3.6.1 的八处架构张力点。每一处都将在第 3 节给出统一的解决方案。

### 张力 1：双脑渲染（Split-Brain Rendering）

`src/derive/shader_compose.lua` 同时存在四个着色器组合器：`nebula_compose_shader`（基础 SDF）、`nebula_compose_instanced_shader`（Phase 3.3 的硬编码 InstanceData）、`nebula_compose_text_shader`（文本专属）、`nebula_compose_shader_instanced`（Phase 3.5.1 的标准 Visual Instanced）。其中 `nebula_compose_shader` 的 fragment 阶段实际上只返回一个红色矩形占位符 [4]，真正的 SDF 圆角矩形与边框逻辑已迁移到 `nebula_compose_shader_instanced`。这是典型的"未完成的架构迁移"，违反公理 C 的"专属性"承诺。

### 张力 2：管线分发的五条路径

`src/derive/pipeline_factory.lua` 中 `nebula_gen_pipeline_source(spec)` 通过 `if spec.has_shadow / standard_instanced / instanced / textured / else` 五分支分发到 `gen_pipeline_simple` / `gen_pipeline_textured_vertex` / `gen_pipeline_shadow` / `gen_pipeline_standard_instanced` / `gen_pipeline_instanced` 五个生成器 [4]。其中 `gen_pipeline_simple` 与 `gen_pipeline_instanced` 已经被 `gen_pipeline_standard_instanced` 实质性取代，但代码并未删除。这是公理 A 的反模式——本应在编译期消除的分支留在了 Lua 元代码层面，徒增维护成本。

### 张力 3：状态层与渲染层的渗透

最初的 Phase 3.6.2 方案（`PLAN_PHASE3_6_2.md`）建议在 `InputVisual` 中注入 `advances: [256]float32`，把字符的屏幕 X 坐标缓存进持久 Record。这违反公理 B：`advances` 是 L2 数据，硬塞进 L1 会导致字号或视口缩放时缓存失效。修订方案（`PLAN_PHASE3_6_2_REVISED.md`）已纠正为栈上即时计算。但同样的渗透风险还潜伏在多处：例如 `flat_buf: [256]uint8` 字段（用于 `get_text` 输出 cstring）实际上也是 L2 数据被错放在了 L1 [5]。

### 张力 4：App 编排与文本组件的二等公民身份

`src/derive/app_factory.lua` 生成的 `<App>:update` / `<App>:draw` 只覆盖了 `nebula_derive` 派生的标准 Visual [6]。而 `TextVisual`（由 `nebula_derive_text_visual` 派生）必须在 `examples/form_demo.nelua` 中**手动**调用 `set_text` / `draw_buffer` [7]。这是一个明显的二等公民问题——文本不是声明意图，而是被强行排除在编排之外。`has_text_buf` 字段虽然在 `app_factory.lua` 中被注册了，但生成的 `update` 并没有真正调用 `process_text_input`，只是聊胜于无的元数据 [6]。

### 张力 5：动态插槽依赖外部全局变量

`app_factory.lua` 在生成 `<App>:draw` 时，对动态插槽生成的代码形如 `while _si < <count_var> do _batch[_count] = <data_var>[_si]` [6]。这里的 `count_var` 和 `data_var` 是开发者必须在 App 之外提供的运行时全局变量。这违反了公理 A 的"编译期最大化"原则，也违反了 Phase 3.5.2 自己宣称的"显式编排"哲学——开发者仍然需要手动维护 Arena 的填充逻辑。`dynamic_list_demo.nelua` 完全不使用 `nebula_derive_app`，正是这一问题的体现 [8]。

### 张力 6：渲染循环模板化的承诺未兑现

Phase 3.5 计划提出 `nebula_frame_begin()` / `nebula_frame_end()` 来封装 WebGPU 渲染循环 [9]。但 `form_demo.nelua` 中 surface 获取、view 创建、encoder 创建、render pass 配置、submit、present 仍然是手写的近 50 行模板代码 [7]。这是一个"声明但未实现"的承诺。

### 张力 7：交互原语的层级混乱

`primitives.nelua` 中保留了 `HoverableState:update(mx, my, px, py, sw, sh)` 和 `ClickableState:update(...)` 的运行时函数定义 [10]，但 Phase 2.4 已承诺将其内联展开（`nm` 中不应出现 `HoverableState_update` 符号）[11]。当前 `interaction_factory.lua` 确实生成了内联代码，但旧的运行时函数并未删除，造成了"两套并存、行为相同、调用不一"的歧义。`focusable` / `editable` / `toggleable` 也存在类似的"原语在哪里被生成"的归属混乱：`focusable` 在 `interaction_factory.lua` 内部，`editable` 通过独立的 `nebula_gen_text_buffer` 注入，`toggleable` 通过 `nebula_gen_toggle_state` + 字符串后处理注入。这是典型的"特性按需手补"导致的架构碎片化。

### 张力 8：Layout 引擎与 App 编排的脱钩

`src/derive/layout_engine.lua` 提供了完整的编译期 Flexbox 解算 [12]，但 `app_factory.lua` 在生成 `<App>` 时**完全没有引用 layout 结果**——开发者仍然需要在 `form_demo.nelua` 中手动写 `pos = Vec2{x = 260.0, y = 80.0}` [7]。Phase 3.1 与 Phase 3.5 之间断了一座桥。

---

## 3. 八大原语的统一解决方案

针对上述八处张力，本纲领提出一套**统一的、自洽的、不再产生新冲突的**架构原语集合。每一条原语都注明它所对应的张力编号、所遵循的公理。

### 原语 1：唯一管线生成器 `gen_pipeline_universal`（解决张力 1、2）

废弃 `gen_pipeline_simple` / `gen_pipeline_instanced` / `nebula_compose_shader` 的占位符路径，将所有标准 Visual（含未来的多边形、椭圆等）统一收敛到 `gen_pipeline_standard_instanced` 一条路径上。文本和阴影分别保留为两条**显式具名**的特殊路径：`gen_pipeline_text_vertex` 和 `gen_pipeline_shadow_multipass`，由 `text_mode = "ascii_sdf"` 和 `has_shadow = true` 两个**注解层布尔位**显式选择，而不是通过 `spec.textured / spec.has_shadow / spec.instanced` 三个逻辑可组合但实际上互斥的字段隐式分发。

| 字段 | 策略 | 公理 |
| :--- | :--- | :--- |
| `text_mode == "ascii_sdf"` | 走 `text_vertex` 路径 | C |
| `has_shadow == true` | 走 `shadow_multipass` 路径 | C |
| 其他全部情况 | 走 `standard_instanced` 路径 | A + C |

实现层面：删除 `nebula_compose_shader`、`nebula_compose_instanced_shader`、`gen_pipeline_simple`、`gen_pipeline_instanced` 共约 600 行死代码。`pipeline_factory.lua` 从 1011 行收敛到约 450 行。

### 原语 2：L1/L2 严格分区器（解决张力 3）

在 `nebula_derive` 中引入一个**编译期校验阶段**：扫描 Visual Record 的每个字段，根据字段名后缀强制归类。任何违反归类的字段必须由开发者显式标注：

| 字段命名 | 归属层 | 含义 |
| :--- | :--- | :--- |
| 后缀 `_buf`、含 `gap_`、`state`、`is_`、`current_` | L1 持久层 | 跨帧状态 |
| 后缀 `_color`、`_pos`、`_size`、`_radius` 等视觉属性 | L1 持久层（被状态机插值） | 跨帧状态 |
| 后缀 `_cache`、`_advances`、`_glyphs`、`_instances` | **禁止出现在 Visual** | 必须在 L2 |

校验失败时编译期 `error()` 中止编译，附友好的错误信息：`"InputVisual.advances violates Axiom B (transient cache must live in Frame Arena, not Visual Record). Move it into Phase 3.6.2's stack-allocated buffer or arena allocation."`

`flat_buf: [256]uint8` 的迁移：将 `get_text()` 改为 `get_text(arena)` 接受 Arena 指针，输出 cstring 指向 Arena 内存。`InputVisual` 中删除 `flat_buf` 字段。

### 原语 3：编译期 Text 一等公民 `nebula_app_register_text`（解决张力 4）

取消 `has_text_buf` / `text_context` 这种"半 metadata"，转而引入一类全新的注册 API：

```lua
nebula_app_register_text("email_label", "TextVisual", {
    bound_to        = "email_input",   -- 绑定到某个 editable 组件
    placeholder     = "email",
    mask_password   = false,
})
```

`app_factory.lua` 据此自动在生成的 `<App>:update` 中注入：

```nelua
if self.email_input:process_text_input(input) then
  if self.email_input:get_text_len() > 0 then
    self.email_label:set_text(self.renderer, self.email_input:get_text(arena))
  else
    self.email_label:set_text(self.renderer, "email")
  end
end
```

`<App>:draw` 中也自动调用 `pipe_text:draw_buffer(...)`。文本组件从此成为编排的一等公民，不再需要在 demo 中手写 50 行 set_text / draw_buffer 模板代码。

### 原语 4：插槽即 Arena Producer（解决张力 5）

将 `nebula_app_register_slot` 从"声明外部全局变量"改为"声明 Producer 函数"：

```lua
nebula_app_register_slot("list_items", "ListItemVisual", {
    max_instances = 10000,
    producer      = "compute_visible_items",  -- 用户实现的纯函数
})
```

`<App>:draw` 自动生成：

```nelua
do
  local _arena_mark = self.arena:mark()
  local _slot: NebulaSlotView(ListItemUniforms)
  compute_visible_items(self, &self.arena, &_slot)  -- 用户实现，把数据填进 Arena
  -- 收集到 _batch 并 upload + draw_instanced
  ...
  self.arena:rewind(_arena_mark)
end
```

`NebulaSlotView` 是一个由派生器为每个 slot 类型自动生成的视图 Record，包含 `data: *[0]<T>Uniforms` 与 `count: uint32`。这样动态插槽与静态组件在 App 层面拥有**完全相同的接口**：你不再需要外部全局变量，不再需要手动维护 Arena 生命周期，所有 L2 状态都被 App 自身托管。

### 原语 5：渲染循环 `nebula_frame_render`（解决张力 6）

兑现 Phase 3.5 的承诺，提供唯一的渲染循环原语：

```nelua
while glfwWindowShouldClose(window) == 0 do
  glfwPollEvents()
  nebula_collect_input(window, &input, dt)
  
  nebula_frame_render(&renderer, &app, &input, dt)
  -- 内部展开为：app:update + frame_begin + app:draw + frame_end
end
```

`nebula_frame_render` 是一个 Nelua 泛型函数（不是宏），它的实现包含 Surface 获取、错误处理、view/encoder/render-pass 创建与释放、submit、present。开发者再也看不见 WGPU 的样板代码。`form_demo.nelua` 的渲染循环将从 100 行收缩到 5 行。

### 原语 6：原语统一注册中心（解决张力 7）

**删除** `primitives.nelua` 中 `HoverableState:update` 和 `ClickableState:update` 的运行时实现（保留纯 Record 作为状态字段类型）。所有原语生成器统一收敛到 `src/derive/interaction_factory.lua` 内部的一张表：

```lua
local NEBULA_PRIMITIVES = {
  hoverable  = { gen_state_field = ..., gen_process = ... },
  clickable  = { ... },
  focusable  = { ... },
  editable   = { ... },  -- 内部包含 Gap Buffer 注入
  toggleable = { ... },  -- 内部包含正交状态注入
}
```

`nebula_gen_process_input` 通过查这张表生成代码，不再需要硬编码字符串后处理（`"\nend" → "\n  self:process_toggle(input)\nend"`），消除张力 7 中的最后一处 hack。

### 原语 7：Layout 即 App Position 源（解决张力 8）

引入一条注册 API：

```lua
nebula_app_attach_layout("FormApp", function()
  return nebula_layout_node({
    name = "root", direction = "column", padding = 32, gap = 16,
    children = {
      {name = "card", visual_type = "CardVisual", width = 480, height = 320},
      {name = "email_input", visual_type = "InputVisual", height = 40},
      ...
    }
  })
end)
```

`app_factory.lua` 在编译期调用该函数得到布局树，并将解算结果写入 `<App>:init` 中：

```nelua
self.card.visual.pos = Vec2{x = 32.0, y = 32.0}
self.card.visual.size = Vec2{x = 480.0, y = 320.0}
self.email_input.visual.pos = Vec2{x = 48.0, y = 380.0}
...
```

所有坐标在编译期解算并嵌入字面量，开发者不再需要写一行 `pos = Vec2{x=260.0, ...}`。这才是公理 A + C 协同时应有的形态：声明意图（layout 树），派生位置（编译期常量）。

### 原语 8：FrameArena 全局单例（解决跨原语共享）

`Frame Arena` 由 `<App>` 内部持有一个固定容量（编译期声明）的实例，每帧 `nebula_frame_render` 自动调用 `arena.reset()`。所有 L2 数据（排版结果、Slot Producer 输出、`get_text` 返回的 cstring）统一从这个 Arena 分配。开发者不再需要在 `form_demo.nelua` 顶层声明 `local arena: NebulaArena` 与 `arena_backing` 等样板代码。

---

## 4. 修订后的 Phase 路线图

基于上述纲领，以下是从当前 Phase 3.6.1 出发到 Nebula 1.0 的完整路线图。所有 Phase 都有明确的"消除哪一个张力"或"实现哪一条原语"的对应关系。

| Phase | 名称 | 对应原语 | 消除张力 | 估时 |
| :--- | :--- | :--- | :--- | :--- |
| **3.6.2** | 鼠标命中与栈上排版 | 原语 2 | 张力 3 | 1 周 |
| **3.6.3** | 多行文本与 Selection（基于 L2 的排版） | 原语 2、原语 8 | 张力 3 | 2 周 |
| **3.7** | 管线生成器收敛与死代码清理 | 原语 1 | 张力 1、2 | 1 周 |
| **3.8** | 渲染循环与 FrameArena 内嵌于 App | 原语 5、原语 8 | 张力 6 | 1 周 |
| **3.9** | 文本一等公民 + Slot Producer 重构 | 原语 3、原语 4 | 张力 4、5 | 2 周 |
| **3.10** | 原语注册中心与 primitives.nelua 瘦身 | 原语 6 | 张力 7 | 1 周 |
| **3.11** | Layout-App 桥接 | 原语 7 | 张力 8 | 1 周 |
| **4.0** | 哲学公理校验器（编译期 lint） | 公理 A/B/C 自动校验 | 防止未来回退 | 2 周 |
| **4.1** | 中文 / Unicode 全量支持 | 扩展原语 3 | — | 4 周 |
| **5.0** | WASM 后端与端到端冒烟 | 跨原语整合 | — | 6 周 |

总工期约 21 周。每个 Phase 完成后，都必须运行**公理校验脚本**（Phase 4.0 提供）来证明本次改动没有引入新的哲学违反。

### 4.1 关键路径与并行度

Phase 3.6.2 与 Phase 3.7 不互相依赖，可并行；Phase 3.8/3.9/3.10 高度串行，因为它们都修改 `app_factory.lua`；Phase 3.11 必须在 3.9 之后，因为它需要 `<App>:init` 已经被重构为接受布局树。Phase 4.0 是质量门槛，必须先于任何 4.x 工作完成。

---

## 5. 公理校验器（Phase 4.0）的具体形式

为了让公理 A/B/C 不再依赖人工自觉，Phase 4.0 将提供一个 Lua 脚本 `tools/axiom_lint.lua`，它在每次 `build.sh` 时自动运行，对 `src/` 目录做静态分析：

| 校验 | 公理 | 实现方式 |
| :--- | :--- | :--- |
| 不允许 `malloc` / `calloc` / `free` | B | grep + 白名单 |
| Visual Record 的字段必须满足原语 2 的命名表 | B | Lua AST 扫描 `global * = @record{...}` |
| 不允许在 `interaction_factory.lua` 之外注入 process_input | A | grep `^function .*Context:process_input` |
| `nebula_compose_shader` 必须返回非占位符着色器 | C | grep `vec4<f32>(1.0, 0.0, 0.0, 1.0)` 出现位置 |
| 每条原语的生成必须在 `NEBULA_PRIMITIVES` 表中注册 | A | Lua 扫描 |

校验失败时编译终止，错误信息引用本纲领的对应章节号，便于新贡献者理解。

---

## 6. 不变量与红线

为防止未来 Phase 的"目的性漂移"，本纲领固化以下五条不可逾越的红线，任何违反者都必须在 PR 中显式援引"豁免条款"并经过架构评审：

1. **永不引入 GC**。Lua 仅作为编译期元代码语言存在，运行时不应有任何 Lua 运行时。
2. **永不引入运行时反射**。所有类型信息必须在编译期被消解为静态字段访问。
3. **永不让 L1 状态依赖 L2 数据**。Frame Arena 一旦 `reset`，L1 必须仍然完全可用。
4. **永不允许"通用渲染器"复活**。`Visual` 与 `Pipeline` 是一对多还是一对一可调（共享 standard_instanced 生成器是允许的），但每个 Visual 类型在编译期必须能 `print` 出"我属于哪条管线路径"。
5. **永不让 demo 写 50 行渲染样板**。任何 demo 必须能用 `<App>:init` + `nebula_frame_render` 在 30 行内完成主循环。

---

## 7. 总结：Nebula 该是什么样

经过这次架构清算，Nebula 应当回答的核心问题是：**"我究竟是什么？"**

它不是 GPUI（GPUI 用 Bump Allocator 但保留了 Rust 的 trait dispatch），不是 Dear ImGUI（IMGUI 不追求零运行时分发），也不是 Flutter（Flutter 完全运行时构建）。Nebula 是一个**用编译期元编程把"声明意图"翻译成"等价手写代码"的 GUI 编译器**，它的优雅完全来自三件事：

> 公理 A 让运行时没有任何"框架开销"。
> 公理 B 让内存生命周期一目了然。
> 公理 C 让每个 Visual 都拥有"为它量身定制"的渲染管线。

当本纲领描述的全部八大原语落地之后，开发者的最终体验应该是这样的：

```nelua
require "nebula"

##[[
  nebula_annotate("CardVisual",   { ... })
  nebula_annotate("InputVisual",  { primitives = {"hoverable","clickable","focusable","editable"}, max_text_len = 255 })
  nebula_annotate("TextVisual",   { text_mode = "ascii_sdf" })
  nebula_annotate("ButtonVisual", { ... })
]]
## nebula_derive("CardVisual"); nebula_derive("InputVisual"); nebula_derive("TextVisual"); nebula_derive("ButtonVisual")

##[[
  nebula_app_begin("FormApp")
    nebula_app_register_component("card",  "CardVisual")
    nebula_app_register_component("email", "InputVisual",  {component_id=1})
    nebula_app_register_text     ("email_label", {bound_to="email", placeholder="email"})
    nebula_app_register_component("login", "ButtonVisual")
  nebula_app_end()

  nebula_app_attach_layout("FormApp", function() ... end)
]]
## nebula_derive_app("FormApp")

local function main()
  local renderer: NebulaRenderer
  local app:      FormApp
  if not nebula_init(&renderer, &app) then return 1 end
  while not nebula_should_close() do
    nebula_frame_render(&renderer, &app)
  end
  return 0
end
main()
```

整个应用 30 行，零样板，零 WGPU 调用，零 Pipeline 初始化代码，零 Arena 管理代码。这才是 Nebula 该有的样子。

---

## 参考文献

[1] `docs/DESIGN_PHASE1.md` — Nebula Phase 1 设计原则（零运行时开销、命名约定即契约）。
[2] `docs/PLAN_PHASE2.md` — 形即渲染原则与 std140 编译期推导。
[3] `docs/PLAN_PHASE3_6.md` — 持久状态与 Frame Arena 双层架构。
[4] `src/derive/shader_compose.lua` 与 `src/derive/pipeline_factory.lua` — 当前的多代码路径分裂。
[5] `examples/form_demo.nelua` 第 59–88 行 — InputVisual 中 `flat_buf` 字段的定义。
[6] `src/derive/app_factory.lua` 第 53–124、204–313 行 — App 编排生成器。
[7] `examples/form_demo.nelua` 第 280–397 行 — 文本组件与渲染循环的手写样板。
[8] `examples/dynamic_list_demo.nelua` — 完全绕过 `nebula_derive_app` 的动态列表实现。
[9] `docs/PLAN_PHASE3_5.md` 第 28–35 行 — 渲染循环模板化的承诺。
[10] `src/primitives.nelua` 第 14–42 行 — Hoverable/Clickable 的运行时函数残留。
[11] `docs/PLAN_PHASE2.md` 第 168–171 行 — Phase 2.4 关于 `HoverableState_update` 应被消除的承诺。
[12] `src/derive/layout_engine.lua` — 编译期 Flexbox 解算引擎。
