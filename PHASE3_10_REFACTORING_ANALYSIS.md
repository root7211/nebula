# Nebula Phase 3.10 重构工作深度分析报告

**日期**：2026-04-26

---

## 1. 总览：Phase 3.10 在路线图中的定位

Phase 3.10 对应架构总纲领中的**原语 6（原语统一注册中心）**，旨在消除**张力 7（交互原语的层级混乱）**。它是 Phase 3.8（渲染循环封装）和 Phase 3.9（文本一等公民 + Slot Producer）之后的自然延续，也是 Phase 3.11（Layout-App 桥接）的必要前置条件。

根据对源码和规划文档的深度审查，Phase 3.10 的重构工作可以划分为**两大主线**：一是 `PLAN_PHASE3_10.md` 中定义的**核心重构任务**（原语注册中心），二是 `GRAND_PLAN_EVALUATION.md` 中识别出的**执行偏差修补任务**（Phase 3.10.5 已部分完成）。

---

## 2. 当前进度判定

通过对代码库的审查，Phase 3.10 的工作实际上已经**分叉为两条线**：

| 子阶段 | 内容 | 状态 |
| :--- | :--- | :--- |
| **Phase 3.10.5**（已完成） | `app_factory.lua` 功能扩展：独立文本标签（static/dynamic 模式）、阴影组件注册（`nebula_app_register_shadow`）、多 Pass 渲染架构（`draw_pre_pass` / `draw_surface_pass`） | 已合入主线，39 项测试通过 |
| **Phase 3.10 核心**（未开始） | `interaction_factory.lua` 原语注册中心重构：建立 `NEBULA_PRIMITIVES` 统一注册表，消除 `nebula_core.nelua` 中的硬编码分支和 `toggleable` 的字符串后处理 Hack | 仅有规划文档，代码尚未改动 |

Phase 3.10.5 解决的是 `GRAND_PLAN_EVALUATION.md` 中识别的执行偏差（独立文本、多 Pass 阴影），而 Phase 3.10 的核心任务——**原语注册中心**——尚未动工。

---

## 3. 核心重构任务详解

### 3.1 问题根源：原语注入逻辑的三处散布

当前代码库中，五个交互原语（hoverable、clickable、focusable、toggleable、editable）的注入逻辑散布在三个不同位置，构成了显著的维护债务。

**散布点 A：`nebula_core.nelua` 的 `gen_context_for` 函数（第 757-779 行）**

该函数通过 `has_prim(reg, "xxx")` 硬编码分支，为 Context Record 注入原语相关字段。每个原语都有独立的 `if` 判断：

```lua
if has_hover then table.insert(lines, "  hover:  HoverableState,") end
if has_click then table.insert(lines, "  click:  ClickableState,") end
if has_focus then table.insert(lines, "  component_id: uint32,") end
if has_prim(reg, "toggleable") then
  table.insert(lines, "  toggle: NebulaToggleState,")
end
if has_prim(reg, "editable") then
  table.insert(lines, "  selection_anchor: uint32,")
  table.insert(lines, "  is_dragging: boolean,")
end
```

这种模式意味着**每新增一个原语，都必须在此处手动添加一个 `if` 分支**，极易遗漏。

**散布点 B：`nebula_core.nelua` 的 `nebula_derive` 宏（第 1029-1125 行）**

全局类型注入和代码生成的编排同样依赖硬编码分支。`toggleable` 需要提前注入 `NebulaToggleState` 类型（第 1038-1045 行），`editable` 需要提前注入 `NebulaBuf{N}` 类型（第 1050-1058 行），且两者的注入时机和方式完全不同。整个 `nebula_derive` 宏中共有 **6 处** `has_prim` 调用，分散在约 100 行代码中。

**散布点 C：`interaction_factory.lua` 的 `toggleable` 字符串后处理（第 450-463 行）**

这是当前代码库中**最脆弱的技术债务**。为了在不修改主状态机逻辑的前提下实现 `toggleable` 的正交状态注入，代码采用了一种 Monkey-patch 模式：

```lua
local _orig_gen_process_input = nebula_gen_process_input
function nebula_gen_process_input(spec)
  local source = _orig_gen_process_input(spec)
  if not has(spec.primitives or {}, "toggleable") then
    return source
  end
  local last_end_pos = source:match(".*()\nend$")
  if last_end_pos then
    source = source:sub(1, last_end_pos - 1) .. "\n  self:process_toggle(input)\nend"
  end
  return source
end
```

它通过正则匹配已生成代码的最后一个 `\nend`，然后用 `source:sub` 截断并拼接 `process_toggle` 调用。这种基于纯文本匹配的代码生成方式**极易因上游代码格式的微小变动而崩溃**，是公认的编译期元编程反模式。

### 3.2 目标架构：元数据驱动的 `NEBULA_PRIMITIVES` 注册表

Phase 3.10 的核心设计是在 `interaction_factory.lua` 顶部引入一个全局的 `NEBULA_PRIMITIVES` 注册表，将所有原语的行为特征收敛为结构化元数据。`nebula_core.nelua` 中的宏只需遍历该注册表即可完成所有代码拼装，不再需要任何硬编码分支。

注册表中每个原语的元数据结构如下：

| 字段 | 类型 | 说明 | 示例 |
| :--- | :--- | :--- | :--- |
| `name` | string | 原语名称 | `"hoverable"` |
| `dependencies` | string[] | 隐式依赖的其他原语 | `clickable` 依赖 `hoverable` |
| `global_type_meta` | table | 需要注入的全局类型元数据 | `NebulaToggleState` 的字段定义 |
| `context_field_meta` | table | 注入到 Context Record 的字段元数据 | `{ name = "hover", type = "HoverableState" }` |
| `context_init_meta` | table | Context `init()` 中的初始化代码元数据 | `{ field = "hover", record_name = "HoverableState" }` |
| `process_input_meta` | table | `process_input` 主体中的状态更新逻辑元数据 | hover 检测、click 检测逻辑 |
| `post_process_meta` | table | `process_input` 后处理逻辑元数据（替代 Monkey-patch） | `toggleable` 的 `process_toggle` 调用 |
| `extra_methods_meta` | table | 额外方法元数据 | `editable` 的 `mouse_to_cursor`、`sync_cursor_to` |

### 3.3 四步实施路径

根据 `PLAN_PHASE3_10.md` 的规划，重构将分四步渐进式推进：

**步骤一：构建注册表并迁移基础原语（hoverable、clickable、focusable）**

这三个原语是最简单的，没有全局类型注入需求，也没有额外方法。迁移工作包括：
- 在 `interaction_factory.lua` 中定义 `NEBULA_PRIMITIVES` 表，填入三个基础原语的元数据。
- 修改 `nebula_core.nelua` 中的 `gen_context_for` 函数，将 `has_hover`/`has_click`/`has_focus` 的硬编码分支替换为遍历注册表的循环。
- 修改 `nebula_derive` 宏中的初始化逻辑，同样改为注册表驱动。

**涉及文件**：`src/derive/interaction_factory.lua`、`src/nebula_core.nelua`

**步骤二：处理原语依赖与迁移 toggleable**

这是最关键的一步，因为它将**彻底消除字符串后处理 Hack**。具体工作包括：
- 增强注册表以支持 `dependencies` 字段（如 `clickable` 自动注入 `hoverable`）。
- 将 `NebulaToggleState` 的类型定义移入 `global_type_meta` 字段。
- 将 `process_toggle` 的调用逻辑定义为 `post_process_meta`，由 `nebula_core.nelua` 宏在 `process_input` 生成完毕后，通过固定模板顺序拼装，而非文本替换。
- **删除第 450-463 行的 Monkey-patch 代码**。

**涉及文件**：`src/derive/interaction_factory.lua`（删除约 15 行 Hack 代码）、`src/nebula_core.nelua`

**步骤三：迁移 editable 原语与动态类型**

`editable` 是最复杂的原语，因为它需要根据 `max_text_len` 动态生成 `NebulaBuf{N}` 类型。具体工作包括：
- 在注册表的 `global_type_meta` 中提供一个返回类型元数据的**工厂函数**，而非静态定义。
- 将 `selection_anchor`、`is_dragging` 等字段移入 `context_field_meta`。
- 将 `mouse_to_cursor`、`sync_cursor_to`、`process_text_input` 等方法通过 `extra_methods_meta` 注入。
- 确保工厂函数的执行时机正确，避免在类型尚未完全解析时触发生成逻辑。

**涉及文件**：`src/derive/interaction_factory.lua`、`src/nebula_core.nelua`、`src/derive/gap_buffer_factory.lua`

**步骤四：`primitives.nelua` 瘦身与清理**

在完成所有原语迁移后，进行最终清理：
- 将 `nebula_core.nelua` 第 84-93 行中硬编码的 `HoverableState` 和 `ClickableState` 全局 Record 定义移除，改为通过注册表的 `global_type_meta` 按需注入。
- 确保 `nm` 命令在编译产物中再也找不到 `HoverableState_update` 等旧时代的幽灵符号。
- 清理 `nebula_core.nelua` 中所有残留的 `has_prim` 硬编码分支。

**涉及文件**：`src/nebula_core.nelua`（预计净减少约 40-60 行硬编码分支）

---

## 4. 涉及文件与改动量估算

| 文件 | 当前行数 | 改动类型 | 预估改动量 |
| :--- | :--- | :--- | :--- |
| `src/derive/interaction_factory.lua` | 466 行 | **重构核心**：新增 `NEBULA_PRIMITIVES` 注册表；删除 Monkey-patch；重构 `nebula_gen_process_input` | 新增约 80-120 行注册表定义，删除约 15 行 Hack 代码，净增约 60-100 行 |
| `src/nebula_core.nelua` | 1252 行 | **重构核心**：`gen_context_for` 和 `nebula_derive` 中的硬编码分支替换为注册表遍历 | 删除约 40-60 行硬编码分支，新增约 20-30 行遍历逻辑，净减少约 20-30 行 |
| `src/derive/gap_buffer_factory.lua` | 不变 | 可能需要适配注册表的工厂函数接口 | 微调 |
| `tests/smoke_phase3_10.lua`（新建） | — | 新增 Phase 3.10 核心重构专项测试 | 约 80-120 行 |

---

## 5. 风险点与注意事项

### 5.1 最高风险：`editable` 原语的动态类型生成

`editable` 需要根据 `max_text_len` 动态生成 `NebulaBuf{N}` 类型。在注册表模式下，`global_type_meta` 需要提供一个工厂函数来处理这种参数化类型。**关键风险在于执行时机**：工厂函数必须在 `nebula_derive` 宏解析 Visual Record 之前被调用，否则 Nelua 编译器会因为找不到 `NebulaBuf{N}` 类型而报错。

**建议**：在注册表中为 `editable` 的 `global_type_meta` 设计一个延迟求值（lazy evaluation）机制，仅在 `nebula_derive` 实际处理到包含 `editable` 原语的 Visual 时才触发类型生成。

### 5.2 中等风险：`NebulaToggleState` 的重复注入防护

当前代码通过 `_nebula_toggle_state_injected` 全局标志防止 `NebulaToggleState` 被多次注入。迁移到注册表后，这一防护逻辑需要被保留或以更优雅的方式实现（如在注册表层面标记"已注入"状态）。

### 5.3 低风险：测试回归

Phase 3.10 是纯架构重构，不应改变任何运行时行为。所有现有的 25 个测试套件和 7 个 Demo 编译必须在重构后保持完全通过。建议在每完成一步迁移后立即运行 `tools/run_all_tests.sh`，确保零退化。

---

## 6. 与前后 Phase 的依赖关系

```
Phase 3.9 (已完成)          Phase 3.10.5 (已完成)
  文本一等公民                 独立文本标签
  Slot Producer               阴影组件注册
       │                           │
       └──────────┬────────────────┘
                  │
          Phase 3.10 核心 (待实施)
          原语统一注册中心
          消除硬编码分支
          消除 Monkey-patch
                  │
                  ▼
          Phase 3.11 (规划中)
          Layout-App 桥接
```

Phase 3.10 核心重构是 Phase 3.11 的**必要前置**，因为 Layout-App 桥接需要在 `app_factory.lua` 中为每个组件注入编译期解算的坐标。如果原语注入逻辑仍然是散布式的，Layout 桥接将进一步加剧代码的碎片化。

---

## 7. 总结

Phase 3.10 的核心重构工作可以用一句话概括：**将五个交互原语的注入逻辑从"命令式硬编码分支"转变为"声明式元数据驱动"**。

这项工作的本质不是功能新增，而是**架构收敛**。它消除的是 Phase 2.4 到 Phase 3.9 演进过程中积累的"原语注入散布"技术债务，其核心产出是一张统一的 `NEBULA_PRIMITIVES` 注册表。完成后，`nebula_core.nelua` 中将不再存在任何针对特定原语的硬编码分支，`interaction_factory.lua` 中将不再存在任何字符串后处理 Hack，新增原语的成本将从"在多个文件中寻找并修改注入点"降低为"在注册表中添加一条记录"。

从工程量来看，这是一个**中等规模的重构**（约 200-300 行代码改动），但其架构影响深远——它为 Phase 3.11 及后续所有 Phase 铺平了道路。
