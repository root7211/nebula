# Nebula 架构总纲领 v3

**修订日期**：2026-04-27（v3.1 修订）
**修订动因**：
- v3.0（2026-04-26）：基于“可编程 GUI 编译器”的哲学演进分析，对路线图进行全面重构，引入三大纪元分层，并更新愿景终态。
- **v3.1（2026-04-27）**：识别出 Phase 4.2 捆绑了三条正交维度（PAL / Slug 生产级化 / CJK），违反“单一张力对应单一原语”的治理原则；同时承认 Phase 4.1 作为 MVP 引入的三项渲染内核债务。据此将 Phase 4.2 拆分为 4.2.1 / 4.2.2 / 4.2.3，并新增第 5 节“技术债登记表”作为阶段治理的形式化机制。
**适用范围**：所有未来 Phase 规划、所有 PR 评审、所有架构决策

---

## 1. 公理体系

Nebula 的全部设计决策由三条公理驱动。三条公理分别约束**时间**（操作归属哪个阶段）、**空间**（数据归属哪个生命周期层）和**映射**（Visual 如何确定性地对应管线），三者作用于正交维度。

### 1.1 公理 A：阶段封闭性原则

Nebula 的生命周期被划分为三个严格有序的阶段，每个阶段有且仅有一类合法操作。后一阶段不得执行前一阶段的操作，前一阶段的输出是后一阶段的不可变输入。

| 阶段 | 名称 | 合法操作 | 输出 | 执行者 |
| :--- | :--- | :--- | :--- | :--- |
| **S0** | 预处理阶段 | 字体解析、atlas/curve-data 生成、资源序列化 | 静态资产文件（`.nelua`、`.pgm`、`.bin`） | 离线工具（`font_preprocessor`） |
| **S1** | 编译阶段 | 类型派生、管线生成、布局解算、状态机构建、着色器组合 | Nelua 源码 → C 源码 → 机器码 | Nelua 宏（`##`） |
| **S2** | 运行阶段 | GPU 资源创建、输入处理、状态转移、渲染提交 | 帧画面 | 编译后的二进制 |

**判定准则**：给定一个操作 O，其合法阶段由输入来源决定——

1. 如果 O 的所有输入在 S0 时刻已知（如 TTF 文件路径、目标字符集），则 O 属于 S0。
2. 如果 O 的所有输入在 S1 时刻已知（如 Visual 的字段列表、原语声明），则 O 属于 S1。
3. 仅当 O 的输入依赖用户交互或外部事件（如鼠标位置、键盘输入、窗口 resize）时，O 属于 S2。

这是一个可机械判定的分类规则：只需检查操作的输入来源，即可确定其合法阶段。

### 1.2 公理 B：生命周期三层原则

Nebula 的运行时数据存在且仅存在三种生命周期，每个运行时数据必须显式归属其一。层间依赖严格单向。

| 层 | 名称 | 生命周期 | 创建时机 | 销毁时机 | 合法存储 | 典型数据 |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **L0** | 永久层 | 应用全生命周期 | `init()` | `deinit()` | 静态全局 / App Record | GPU 管线、纹理、Bind Group Layout、Sampler |
| **L1** | 持久层 | 跨帧存活 | `init()` 或状态转移 | 显式重置 | App Record 内的状态字段 | 焦点 ID、Gap Buffer 内容、Toggle 状态、状态机当前态 |
| **L2** | 帧级层 | 单帧瞬时 | 每帧 `update`/`draw` | `arena.reset()` | Frame Arena | 排版结果、Slot Producer 输出、临时 cstring |

**不变量**（形式化表述）：

```
∀ data ∈ L1: valid(data) ⟹ valid(data) after arena.reset()
∀ data ∈ L0: valid(data) ⟹ valid(data) after any L1 state transition
```

L2 的 reset 不得影响 L1 的有效性；L1 的任何状态变化不得影响 L0 的有效性。

### 1.3 公理 C：形即渲染原则

每一个 Visual 类型 V 在编译期（S1）必须确定性地映射到一个**管线签名**：

> Σ(V) = (VertexLayout, UniformsLayout, ShaderModule, BlendState)

两个 Visual 类型 V₁ ≠ V₂ 当且仅当 Σ(V₁) ≠ Σ(V₂) 时允许共享管线对象。对于多 Pass 渲染，签名扩展为有序序列 Σ(V) = [Σ₁, Σ₂, ..., Σₙ]，其中每个 Σᵢ 对应一个 Pass。

### 1.4 元规则 Π：正交性原则

公理 A 约束操作的**时间归属**（S0/S1/S2），公理 B 约束数据的**生命周期归属**（L0/L1/L2），公理 C 约束 Visual 的**管线映射**。三者作用于正交维度，不应产生冲突。如果出现表面冲突，应修订公理的形式化表述，而非裁决优先级。

---

## 2. 架构张力与原语映射

总纲领识别了八大架构张力，每个张力对应一个需要实现的"原语"。原语是消除张力的最小架构单元。

| 张力 | 描述 | 对应原语 | 解决方案 |
| :--- | :--- | :--- | :--- |
| T1 | 管线路径爆炸 | 原语 1：管线收敛 | `pipeline_factory.lua` 收敛为 3 条路径（standard_instanced、text_vertex、shadow_multipass） |
| T2 | 命中测试与排版分离 | 原语 2：栈上排版 + 命中测试 | `text_runtime.nelua` 中 L2 排版 + 编译期命中区域注入 |
| T3 | 文本渲染手动管理 | 原语 3：文本一等公民 | `nebula_app_register_text` 自动编排文本管线 |
| T4 | 动态列表外部依赖 | 原语 4：Slot Producer | `producer` 纯函数 + Arena mark/rewind |
| T5 | 渲染循环样板代码 | 原语 5：渲染循环封装 | `nebula_frame_render` 一行调用 |
| T6 | FrameArena 外置 | 原语 8：Arena 内嵌 | Arena 作为 App Record 的 L0 成员 |
| T7 | 交互原语硬编码 | 原语 6：原语注册中心 | `NEBULA_PRIMITIVES` 元数据驱动注册表 |
| T8 | 布局与 App 分离 | 原语 7：Layout-App 桥接 | 布局约束嵌入注册 API，编译期解算坐标 |

---

## 3. Nebula 发展路线图：三大纪元

Nebula 的发展并非线性，而是遵循着从“形即外观”到“形即行为”，最终迈向“计算统一”的哲学升维之路。我们将整个发展路线图划分为三大纪元（Era），每个纪元代表一次核心范式的转变。

### Era I：形即渲染 (Shape-Is Rendering) — Phase 0 至 Phase 4.1（已完成）

**核心命题**：开发者声明 Visual 的**外观**规格，编译器推导渲染代码。

**关键成就**：
*   确立三大公理体系（A、B、C）与不变量（I1-I7）。
*   实现编译期类型派生、状态机生成、管线收敛。
*   引入 Slug 文本渲染引擎，实现 Unicode 全量支持。
*   构建编译期公理校验器，将哲学约束强制化。

| Phase | 名称 | 消除张力 | 关键成果 | 完成日期 |
| :--- | :--- | :--- | :--- | :--- |
| 3.6.2 | 鼠标命中与栈上排版 | T2 | L2 栈上排版替代 L1 缓存 | 2026-04-24 |
| 3.6.3 | 多行文本与 Selection | T2 | Gap Buffer 选区支持 | 2026-04-24 |
| 3.7 | 管线生成器收敛与死代码清理 | T1 | 5 条路径 → 3 条路径，删除 600+ 行死代码 | 2026-04-24 |
| 3.8 | 渲染循环封装与 FrameArena 内嵌 | T5, T6 | `nebula_frame_render` 一行调用；Arena 内嵌 App Record | 2026-04-24 |
| 3.9 | 文本一等公民 + Slot Producer 重构 | T3, T4 | `nebula_app_register_text`；Producer 纯函数模式 | 2026-04-25 |
| 3.10 | 原语注册中心 | T7 | `NEBULA_PRIMITIVES` 统一注册表；Monkey-patch 彻底删除 | 2026-04-26 |
| 3.10.5 | 独立文本标签 + 多 Pass 渲染架构 | — | `register_text` static/dynamic 模式；`register_shadow`；多 Pass 渲染 | 2026-04-26 |
| 3.11 | Layout-App 统一注册 | T8 | 布局约束嵌入注册 API，消除独立 `attach_layout` | 2026-04-26 |
| 3.12 | 响应式重排 (Responsive Reflow) | 视口自适应 | 编译期线性函数推导，S2 扁平插值 | 2026-04-26 |
| 4.0 | 编译期公理校验器 | 防止回退 | 将公理从文档约束升级为编译期强制 | 2026-04-26 |
| **4.1** | **Slug 文本渲染引擎** | **Unicode 全量** | **纯数学矢量渲染，47/47 回归通过** | **2026-04-26** |

### Era II：形即行为 (Shape-Is Behavior) — Phase 4.2.1 至 Phase 5.x（进行中）

**核心命题**：将“形即”范式从外观扩展到**行为**。开发者不仅声明 Visual 的外观，还能通过暴露的编译器 API 声明和组合自定义交互原语，将 Nebula 升维为“可编程 GUI 编译器”。

**阶段拆分说明**：原 Phase 4.2 被识别出捆绑了三条正交维度——平台抽象（PAL）、Slug 渲染内核生产级化、CJK 字形与 shaping 集成。据此拆分为三个独立子阶段，各自对应单一张力，保持过往 Phase 3.6.x / 3.10.x 的细粒度验收习惯。其中 4.2.1 与 4.2.2 代码冲突面为零、可并行推进；4.2.3 必须在 4.2.1（三端一致）与 4.2.2（内核可扩展）之后方可验收。

| Phase | 名称 | 消除张力 / 目标 | 状态 |
| :--- | :--- | :--- | :--- |
| **4.2.1** | 跨平台 PAL 骨架 | 构建系统与渲染后端的平台耦合：`NEBULA_TARGET` 检测、`nebula_main_loop` 宏封装 Native 阻塞/Web 回调差异、Surface 描述符的 Linux/Windows/Web 三路径分化。**验收载体仍为 ASCII 字符集**，确保平台层与渲染内核解耦。 | 进行中 |
| **4.2.2** | Slug 渲染内核生产级化 | 清算 Phase 4.1 引入的三项内核债务（D-4.1-A/B/C，详见第 5 节）：自适应 band 分割与等价子集合并、Jacobian 逆矩阵与 SlugDilate 上线、Storage Buffer 与 RGBA32Uint 纹理的基准对比。验收载体为 Latin Extended 全量 + 任意旋转/缩放 pixel diff。**本阶段在叙事上是 Era I 的终章补完，在时间线上与 4.2.1 并行推进。** | 规划中 |
| **4.2.3** | HarfBuzz + CJK 集成 | 复杂文本排版与字形规模化：S0 阶段集成 HarfBuzz，按 `charset` 声明进行字形子集化并预计算 shaping 查找表；验证 CJK 7000 常用字在三端（依赖 4.2.1）以生产级 band 策略（依赖 4.2.2）正确渲染。 | 规划中 |
| **4.3** | **可编程原语注册表** | **暴露 `nebula_register_primitive` API，允许界面开发者在 S1 编译期安全注入自定义交互逻辑。** | **规划中** |
| 4.4 | 高级宏观原语库 | 基于可编程原语注册表，实现 `multiline_editable`、`scrollable_y`、`clipboard_aware` 等高级宏观原语。 | 规划中 |
| 4.5 | 小型文本编辑器原型 | 作为 Era II 的里程碑验证，使用自定义原语构建一个功能完备的小型文本编辑器原型。 | 规划中 |
| 5.0 | 自动化 CI/CD 与工业化发布 | 确保 Linux、Windows、Web 三端代码在每次提交时都能自动编译并通过全量回归测试，建立工业级的发布流程。 | 规划中 |

### Era III：计算统一 (Unified Computation) — Phase 6.0+（远期愿景）

**核心命题**：兑现公理 Ω——CPU 仅负责“意图的编排”（Orchestration），GPU 负责“事实的生成”（Generation）。将 UI 的复杂性与 CPU 性能彻底脱钩，释放前所未有的交互潜能。

| Phase | 名称 | 目标 | 状态 |
| :--- | :--- | :--- | :--- |
| 6.0 | GPU Compute Shader Layout (CSL) | 将布局算法完全迁移至 GPU Compute Shader，实现并行解算数万个节点的几何属性。 | 规划中 |
| 6.1 | 拓扑流渲染 (Indirect Drawing) | 引入 GPU 驱动的间接绘制，将 CPU 端的显式 Draw Call 替换为 GPU 端维护的 Indirect Buffer，实现真正的动态拓扑变化。 | 规划中 |
| 7.0 | 统一状态仓库 (Unified State Storage) | 所有 UI 状态原生驻留在 GPU 显存中，交互逻辑由 Compute Shader 直接在显存中完成状态更新。 | 规划中 |

---

## 4. 不变量与红线

以下不变量在任何 Phase 中都不得被打破：

**I1（零运行时分发）**：S2 阶段不存在虚函数表、字符串查表或 `if typeof(x)` 式的类型分支。所有分发在 S1 阶段由宏展开为直接调用。

**I2（Arena 唯一性）**：每个 App 实例有且仅有一个 Frame Arena（L2 层），所有帧级临时数据必须从该 Arena 分配。不得在 S2 阶段调用系统 `malloc` 分配帧级数据。

**I3（管线确定性）**：每个 Visual 的管线签名 Σ(V) 在 S1 阶段完全确定。S2 阶段不得动态创建或切换管线。

**I4（注册表完备性）**：所有交互原语必须通过 `NEBULA_PRIMITIVES` 注册表声明。`nebula_core.nelua` 中不得出现针对特定原语名称的硬编码分支。

**I5（层间隔离）**：L0 数据的有效性不依赖 L1 的状态；L1 数据的有效性不依赖 L2 的内容。`arena.reset()` 不得使任何 L1 数据失效。

**I6（永不引入 GC）**：Lua 仅作为 S1 阶段的编译期元代码语言存在，S2 阶段不应有任何 Lua 运行时或垃圾回收器。

**I7（永不引入运行时反射）**：所有类型信息必须在 S1 阶段被消解为静态字段访问。S2 阶段不存在类型元数据查询。

---

## 5. 技术债登记表（v3.1 新增）

### 5.1 登记表的作用

公理 A 约束了**操作**的时间归属。但在实际工程中，每个 Phase 为了按时交付 MVP，不可避免地会引入**简化取舍**——即某些操作当前的实现形式只对当前 Phase 的输入规模成立，在未来更大规模输入下会失效。这种取舍本身并不违反公理 A（因为它仍然归属于正确的阶段），但如果不形式化登记，容易在许多 Phase 后演化为隐性法债。

登记表是对公理 A 在债务维度上的自然延伸：每条债务必须明确声明（a）引入它的 Phase；（b）触发失效的具体条件；（c）计划清算的未来 Phase。本登记表是所有 PR 评审的必经档案，新引入的债务必须追加到本表中才可合并。

### 5.2 当前未清算债务

| 编号 | 引入 Phase | 描述 | 触发失效条件 | 计划清算 Phase | 状态 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **D-4.1-A** | 4.1 | Slug 预处理器采用固定均匀 `BAND_COUNT=8` 水平/垂直分割，无等价曲线子集合并逻辑 | 字形曲线数 > 50；或 CJK 字形导致单 band 曲线数 > 12（触发 GPU warp 等待超出 8 周期） | **4.2.2** | 待清算 |
| **D-4.1-B** | 4.1 | 顶点属性中跳过 Jacobian 逆矩阵（`slug_reference_notes.md:59` 已承认）和 SlugDilate sub-pixel 膨胀 | 任意仿射变换（旋转、倾斜、非各向同性缩放）；或文本以 < 12pt 呈现导致 sub-pixel 失真 | **4.2.2** | 待清算 |
| **D-4.1-C** | 4.1 | 曲线 / band_meta / band_ref 使用 Storage Buffer 而非 Slug 原论文推荐的 RGBA32Float/Uint 纹理 | 字形总数 > 500，或帧内有效渲染字符数 > 5000（进入带宽受限区间） | **4.2.3**（需 4.2.2 内完成 benchmark 后决策） | 待验证 |

### 5.3 登记表的治理规则

1. **不允许隐式债务**：任何 PR 引入的简化取舍，若其失效条件可预见，必须在本表新增一行。
2. **跨 Phase 传递**：一个 Phase 开始时必须审视本表，将其计划清算债务引用到该 Phase 的验收标准中。
3. **清算即删除**：债务在清算的 Phase 完成后从表中移除，并在历史档案（如 CHANGELOG）中留下序号溯源。
4. **验收增量**：每个 Phase 的验收标准除了传统的张力消除外，新增一项“本阶段产生的债务清单”，鼓励全零债务，但不禁止取舍——关键是透明。

---

## 6. 与 v2 总纲领的差异摘要

本版本（v3.1）相对于原始总纲领（v2）和 v3.0 的核心变更如下：

| 维度 | v2 | v3.0 | v3.1 | 变更理由 |
| :--- | :--- | :--- | :--- | :--- |
| 路线图结构 | 扁平的 Phase 列表 | 三大纪元分层（Era I/II/III） | 同 v3.0 | 更好地体现哲学演进与范式转变 |
| Phase 4.2 | 跨平台 PAL + CJK（捆绑） | 同 v2 | **拆分为 4.2.1 PAL + 4.2.2 Slug 生产级化 + 4.2.3 HarfBuzz/CJK** | 规避三维度捆绑导致的大 Phase 陷阱，明确承认 Phase 4.1 的内核债务需独立清算 |
| Phase 4.3 | 拓扑流渲染 | 可编程原语注册表 | 同 v3.0 | 将“可编程 GUI 编译器”核心功能提前，更符合 Era II 哲学 |
| Phase 6.1 | 未定义 | 拓扑流渲染 | 同 v3.0 | 将拓扑流渲染后移至 Era III，更符合公理 Ω 愿景 |
| 愿景终态 | 30 行表单 | 50 行文本编辑器 | 同 v3.0 | 反映 Era II 行为编程的新能力 |
| Phase 4.4 | 可编程 GUI 编译器（位于参考资料后） | 高级宏观原语库（位于 Era II 内） | 同 v3.0 | 修正文档结构，并明确其在 Era II 中的定位 |
| 技术债登记 | 无 | 无 | **新增第 5 节“技术债登记表”** | 将阶段简化取舍从隐性升为显性治理对象 |

---

## 7. 愿景：50 行终态（文本编辑器）

当 Era II 的路线图全部完成后，一个功能完备的小型文本编辑器将是这样的：

```nelua
require "nebula"

##[[
  -- 界面开发者自定义原语：一个简单的拖拽行为
  nebula_register_primitive("draggable", {
    state_fields = { is_dragging = "bool", start_x = "float32", start_y = "float32" },
    inline_process = [[ -- Nelua 代码片段，将在 S1 阶段注入
      if self.is_dragging then
        self.visual.pos.x = self.visual.pos.x + (mx - self.start_x)
        self.visual.pos.y = self.visual.pos.y + (my - self.start_y)
        self.start_x = mx
        self.start_y = my
      end
      if is_btn_down and not self.is_dragging and self.visual:hit_test(mx, my) then
        self.is_dragging = true
        self.start_x = mx
        self.start_y = my
      elseif not is_btn_down and self.is_dragging then
        self.is_dragging = false
      end
    ]],
    -- 编译期静态契约：要求 Visual 必须有 pos 字段
    static_asserts = { "visual.pos" }
  })

  nebula_annotate("EditorVisual", {
    primitives = {"multiline_editable", "scrollable_y", "clipboard_aware"},
    -- 其他视觉属性...
  })
]]
## nebula_derive("EditorVisual")

##[[
  nebula_app_begin("TextEditorApp")
    nebula_app_set_root_layout("TextEditorApp", { direction = "column", padding = 16 })
    nebula_app_register_component("editor", "EditorVisual", {
      component_id = 1,
      layout = { flex_grow = 1, width = 800, height = 600 }
    })
  nebula_app_end()
]]
## nebula_derive_app("TextEditorApp")

local function main()
  local renderer: NebulaRenderer
  local app:      TextEditorApp
  if not nebula_init(&renderer, &app) then return 1 end
  while not nebula_should_close() do
    nebula_frame_render(&renderer, &app)
  end
  return 0
end
main()
```

**50 行，零样板，零 WGPU 调用，零 Pipeline 初始化代码，零 Arena 管理代码。** 布局约束内嵌于注册 API，坐标在 S1 阶段解算并嵌入编译期常量。自定义原语的逻辑直接在 S1 阶段被编织进 `process_input`。这是公理 A（阶段封闭性）、公理 B（三层生命周期）和公理 C（形即渲染）协同时，结合“可编程 GUI 编译器”能力应有的形态。

---

## 8. 参考资料

| 资料 | 说明 |
| :--- | :--- |
| [Slug Algorithm (GitHub)](https://github.com/EricLengyel/Slug) | Eric Lengyel 的 Slug 算法参考着色器实现，2026 年 3 月进入公共领域 |
| [Sluggish (GitHub)](https://github.com/mightycow/Sluggish) | Slug 的 band-data / curve-data 纹理生成工具 |
| [HarfBuzz (GitHub)](https://github.com/harfbuzz/harfbuzz) | 文本 shaping 引擎，用于字距调整和连字替换 |
| [Slug JCGT Paper](https://jcgt.org/published/0006/02/02/) | Slug 算法的原始学术论文（2017） |
| [V3_UNIFIED_COMPUTATION_WHITEPAPER.md](docs/V3_UNIFIED_COMPUTATION_WHITEPAPER.md) | Nebula v3：计算统一架构白皮书 |
