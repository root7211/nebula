# Nebula Phase 3.10 实施方案：原语注册中心与 primitives.nelua 瘦身

**作者**：Manus AI
**日期**：2026-04-26
**目标**：消除原语注入逻辑在 `nebula_core.nelua` 和 `interaction_factory.lua` 中的散布，建立统一的 `NEBULA_PRIMITIVES` 注册表，彻底移除 `toggleable` 的字符串后处理 Hack，为 Phase 3.11 的 Layout-App 桥接提供稳固的基础设施。

---

## 1. 背景与动机

在 Phase 2.4 至 Phase 3.9 的演进过程中，Nebula 陆续引入了 `hoverable`、`clickable`、`focusable`、`toggleable` 和 `editable` 五个交互原语。然而，这些原语的注入机制呈现出严重的"散布式"增长模式。当前的代码库中，原语相关的逻辑至少分散在三个不同位置，构成了显著的维护债务 [1]。

首先，`interaction_factory.lua` 中存在硬编码的分支逻辑，特别是对于 `toggleable` 原语，采用了一种极其脆弱的 `source:sub` 字符串后处理技术（Monkey-patch）来在生成的代码末尾强行插入 `process_toggle` 调用 [2]。其次，在 `nebula_core.nelua` 的 `gen_context_for` 函数中，为 Context 记录注入原语字段以及在 `init()` 方法中初始化这些字段的代码，都使用了长串的硬编码 `if-else` 分支 [3]。最后，在 `nebula_derive` 宏中，全局类型的注入（如 `NebulaToggleState` 和 `NebulaBuf{N}`）也是通过条件判断散布在各处 [4]。

这种散布式实现不仅使得新增原语的成本极高，也违反了总纲领中关于"原语 6（原语统一注册中心）"的明确要求 [5]。因此，Phase 3.10 的核心任务是将所有原语的声明、类型注入、字段生成和状态处理收敛到一张统一的注册表中。

---

## 2. 核心设计：统一注册表模式

Phase 3.10 将在 `interaction_factory.lua` 顶部引入一个全局的 `NEBULA_PRIMITIVES` 注册表。该注册表将使用数据驱动的方式定义每个原语的全部行为特征，取代目前散落在各处的条件判断分支。

### 2.1 注册表结构设计

每个原语在注册表中将被定义为一个包含以下关键字段的表：

| 字段 | 类型 | 说明 |
| :--- | :--- | :--- |
| `name` | 字符串 | 原语名称，如 "hoverable" |
| `global_types` | 字符串（可选） | 需要在编译期注入的全局类型定义，如 `NebulaToggleState` 的记录定义 |
| `context_fields` | 字符串 | 注入到 `<T>Context` 记录中的字段声明，如 `hover: HoverableState,` |
| `context_init` | 字符串 | 在 `<T>Context:init()` 中执行的初始化代码，如 `self.hover = HoverableState{}` |
| `process_input` | 字符串（可选） | 在 `process_input` 方法主体中执行的状态更新逻辑 |
| `post_process` | 字符串（可选） | 在 `process_input` 状态机转换完成后执行的后处理逻辑，专为 `toggleable` 设计 |
| `extra_methods` | 函数（可选） | 生成额外方法的工厂函数，如 `editable` 的 `mouse_to_cursor` 和 `sync_cursor_to` |

### 2.2 消除字符串后处理 Hack

在引入注册表后，`nebula_gen_process_input` 的实现将被重构。它将不再通过字符串替换来修改已生成的代码，而是遍历 `spec.primitives` 列表，从注册表中提取相应的 `process_input` 和 `post_process` 代码块，并将它们按照固定的模板顺序组装成最终的源码。

> 通过将 toggleable 的处理逻辑声明为 `post_process` 回调，我们彻底消除了第 450-463 行的 `source:sub` 字符串后处理代码，使得代码生成过程变得确定且安全。

---

## 3. 实施步骤

实施过程将严格遵循安全重构的原则，确保在不破坏现有功能的前提下逐步替换旧机制。

### 步骤一：构建注册表并迁移基础原语
在 `interaction_factory.lua` 中定义 `NEBULA_PRIMITIVES` 表，并首先将 `hoverable`、`clickable` 和 `focusable` 这三个基础原语迁移到注册表驱动的模式。这包括将它们在 `gen_context_for` 中的字段声明和初始化逻辑提取到注册表中，并修改 `nebula_core.nelua` 以通过遍历注册表来生成这部分代码。

### 步骤二：迁移 toggleable 原语并消除 Hack
将 `toggleable` 原语迁移到注册表。将其全局类型 `NebulaToggleState` 定义移入 `global_types` 字段，将其字段声明和初始化移入相应字段。最关键的是，将其 `process_toggle` 的调用逻辑定义为 `post_process`，并重写 `nebula_gen_process_input` 以支持该回调机制，从而删除旧的 Monkey-patch 代码。

### 步骤三：迁移 editable 原语与动态类型
`editable` 原语具有特殊性，因为它需要根据 `max_text_len` 动态生成 `NebulaBuf{N}` 类型。在注册表中，我们将通过提供一个返回代码字符串的工厂函数来处理这种动态类型生成。同时，将 `editable` 相关的额外方法（如选区处理和光标同步）通过 `extra_methods` 字段进行注入。

### 步骤四：primitives.nelua 瘦身与清理
在完成所有原语的迁移后，`nebula_core.nelua` 中原有的硬编码 `HoverableState` 和 `ClickableState` 全局定义将被移除，转而通过注册表的 `global_types` 机制按需注入，实现框架核心代码的进一步瘦身。

---

## 4. 验证与测试策略

Phase 3.10 是一个纯粹的架构重构阶段，不应引入任何面向开发者的 API 变更，也不应改变现有的运行时行为。因此，验证的核心在于确保现有的测试套件和 Demo 能够在新架构下无缝运行。

### 4.1 核心测试集
所有 18 个 Lua 冒烟测试必须全部通过，特别需要关注以下专项测试：
- `smoke_phase3_5_3.lua`：验证 `toggleable` 原语的正交状态切换是否仍然正确工作。
- `smoke_phase3_6_3.lua`：验证 `editable` 原语的 Gap Buffer 文本选区功能是否未受影响。

### 4.2 编译回归测试
所有 7 个包含不同原语组合的 Demo 必须能够成功编译并运行：
- `form_demo`（包含所有 5 个原语的综合场景）
- `login_demo`（包含 `editable` 的复杂场景）
- `button_demo` 和 `layout_demo`（基础原语组合场景）

通过执行 `./tools/run_all_tests.sh`，我们期望看到 `25/25 passed, 0 failed` 的最终结果，这标志着 Phase 3.10 重构的圆满成功。

---

## 参考文献

[1] Nebula Phase 3.10 审计笔记：原语注入机制散布情况分析.
[2] `src/derive/interaction_factory.lua`: toggleable 字符串后处理实现.
[3] `src/nebula_core.nelua`: gen_context_for 函数实现细节.
[4] `src/nebula_core.nelua`: nebula_derive 宏的条件注入逻辑.
[5] Nebula 架构总纲领 (ARCHITECTURE_GRAND_PLAN.md): Phase 3.10 原语注册中心规划.
