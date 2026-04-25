# Phase 3.9 架构合规性审查报告

**审查人**：Manus AI
**日期**：2026-04-25
**审查对象**：`PLAN_PHASE3_9.md`（文本一等公民与 Slot Producer 重构）
**审查依据**：`ARCHITECTURE_GRAND_PLAN.md`（三大公理、元规则与五条红线）

---

## 1. 审查结论摘要

经过对 Phase 3.9 计划的逐条审查，结论如下：**Phase 3.9 的设计不仅没有破坏总架构和原生哲学，反而是对架构总纲领的严格兑现。** 

它精确地解决了纲领中指出的"张力 4"（文本二等公民）和"张力 5"（动态插槽依赖外部全局变量），并且在实现路径上完全遵循了三大公理。

**唯一需要修正的技术细节**：Phase 3.9 计划草案中假设了 `Arena:mark()` 和 `Arena:rewind()` API 的存在，但当前 `nebula_arena.nelua` 仅支持 `reset` 语义。这需要在 Phase 3.9 的实际开发中补充实现该 API，以完全契合公理 B 的要求。

---

## 2. 对照三大公理的审查

### 2.1 公理 A（编译期最大化原则）

**公理定义**：任何能在编译期确定的事实，必须在编译期确定。不应出现可由编译期消除的虚函数分发或特性开关 [1]。

**Phase 3.9 的合规性：完全合规。**
*   **文本一等公民**：`nebula_app_register_text` 是在编译期（Lua 宏展开阶段）执行的。它将文本组件的 `TextContext` 和 `TextPipeline` 静态注入到 `<App>` record 中，并在 `update` 和 `draw` 中生成硬编码的函数调用。运行时没有任何 `if has_text then` 的分支判断，完全符合公理 A。
*   **Slot Producer**：`nebula_app_register_slot` 同样在编译期将用户提供的 `producer` 函数名静态绑定到生成的 `draw` 代码中。这消除了原本依赖外部全局变量（`count_var`、`data_var`）的动态性，将数据流转关系在编译期固化，是对公理 A 的一次重要修复。

### 2.2 公理 B（生命周期严格分层原则）

**公理定义**：只存在 L1（持久层，跨帧存活）和 L2（帧级层，单帧瞬时）两种内存生命周期。L1 状态绝不能依赖 L2 数据 [1]。

**Phase 3.9 的合规性：高度合规（需补充底层 API）。**
*   **文本缓冲区修复**：Phase 3.9 计划明确指出，在生成的 `process_text_input` 逻辑中，将使用栈上数组或 `FrameArena` 作为临时缓冲区来提取文本内容，并传递给 `set_text`。这彻底修复了之前 `flat_buf: [256]uint8` 错误地驻留在 L1（Visual Record）中的问题，严格遵守了公理 B。
*   **Slot 视图托管**：引入 `NebulaSlotView`，将动态插槽的实例数据（L2）完全托管在 App 内嵌的 `FrameArena` 中。每帧重新分配，随 Arena 重置而销毁。这完美契合了 L2 的定义。
*   **修正项**：当前 `nebula_arena.nelua` 仅提供了帧级别的 `nebula_arena_reset` [2]。为了支持 Slot Producer 在单次 Draw 调用内的局部内存回收，Phase 3.9 必须在 `nebula_arena.nelua` 中新增 `mark()` 和 `rewind()` 方法。这是对公理 B 基础设施的必要完善，而非破坏。

### 2.3 公理 C（形即渲染原则）

**公理定义**：每一个 `Visual` 类型必须拥有一条专属的、按字段精确组合而成的渲染管线。运行时不应存在"通用渲染器" [1]。

**Phase 3.9 的合规性：完全合规。**
*   **保留专属管线**：Phase 3.9 并没有试图将文本渲染强行塞入 `standard_instanced` 管线，也没有复活"通用渲染器"。相反，它在生成的 `<App>` 中显式注入了 `pipe_text: TextPipeline`，并在 `draw` 中调用其专属的 `draw_buffer` 方法。这证明了文本依然走的是 `text_vertex` 这条显式具名的特殊路径，完全符合公理 C。

---

## 3. 对照五条红线的审查

| 红线 | Phase 3.9 是否触碰 | 审查说明 |
| :--- | :--- | :--- |
| **1. 永不引入 GC** | 否 | 所有新增逻辑均依赖栈分配或 `FrameArena` 线性分配，无 GC 参与。 |
| **2. 永不引入运行时反射** | 否 | `app_factory.lua` 在编译期完成所有类型消解和代码生成。 |
| **3. 永不让 L1 依赖 L2** | 否 | 修复了 `flat_buf` 的渗透问题，进一步巩固了这条红线。 |
| **4. 永不允许通用渲染器复活** | 否 | 文本渲染依然使用专属的 `TextPipeline`。 |
| **5. 永不让 demo 写 50 行渲染样板** | **否（主动消除）** | Phase 3.9 的核心目的正是消除 `form_demo.nelua` 中残留的 40 行文本渲染样板代码，使其主循环收缩至 3 行。 |

---

## 4. 结论与建议

Phase 3.9 的设计不仅没有偏离 Nebula 的原生哲学，反而是对架构总纲领中**原语 3**和**原语 4**的精准落地。它通过编译期代码生成（公理 A），将文本和动态插槽的生命周期严格纳入 App 托管（公理 B），同时保留了专属的渲染管线（公理 C）。

**唯一建议**：在执行 Task 3.9.3（Slot Producer 重构）之前，先作为一个前置小任务，在 `src/nebula_arena.nelua` 中实现 `mark()` 和 `rewind()` 接口，以支撑局部 L2 内存的精细化管理。

---

## 参考文献

[1] `docs/ARCHITECTURE_GRAND_PLAN.md` — Nebula 架构总纲领，定义了三大公理与五条红线。
[2] `src/nebula_arena.nelua` — 当前的 Frame Arena 实现，仅包含 `reset` 语义。
