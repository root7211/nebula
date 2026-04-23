# Nebula Phase 3.6 深度思考：在极致哲学下重构文本编辑架构

## 1. 核心矛盾的本质：生命周期的错位

在评估 Nebula 是否应该在 Phase 3.6 引入真正的文本编辑能力（如 Gap Buffer）时，我们遇到了一个看似不可调和的架构矛盾。

Nebula 的核心内存模型是 **Frame Arena**。它的语义是“帧级临时分配”：每帧开始时重置，所有数据在帧末尾烟消云散。这种设计带来了极致的性能和零 GC 开销，是 Nebula 能够单次 Draw Call 渲染上万动态列表项的基石。

然而，**文本编辑（Gap Buffer）的语义是“跨帧持久”的**。用户输入的文本必须在帧与帧之间存活。如果将文本数据放入 Frame Arena，它会在下一帧丢失；如果绕过 Arena 使用堆分配（`malloc`/`free`），则直接违背了 Nebula “零运行时开销”和“无堆分配”的第一性原理。

当前的 `InputContext` 采用了一种妥协的方案：在组件的 Record 内部硬编码一个 `[256]uint8` 的静态数组。这虽然避免了堆分配，但也彻底锁死了文本的扩展性（永远只能是 256 字节的单行文本），无法演进为真正的文本编辑器。

## 2. 业界模式的启示

为了寻找破局点，我深入研究了业界最前沿的高性能 UI 框架和编辑器的内存架构。

### 2.1 GPUI (Zed) 的双层解耦
Zed 编辑器背后的 GPUI 框架采用了一种严格的双层架构 [1]。
*   **Entity 层（持久）**：所有应用状态（包括文本缓冲区）由 App 集中所有权管理，跨帧存活。
*   **Element 层（帧级）**：每帧重新构建 UI 树，渲染数据走 Bump Allocator（类似 Arena）。

GPUI 的核心洞察是：**持久状态和帧级渲染是两个正交的关注点**。文本数据属于 Entity 层，而文本的排版结果（每个字符的屏幕坐标）属于 Element 层。

### 2.2 Handmade Hero 的双向 Arena
在游戏引擎领域，Casey Muratori 推广了“双 Arena”模式 [2]。游戏启动时分配一块巨大的内存，分为 Permanent Storage（持久区）和 Transient Storage（临时区）。Ryan Fleury 进一步将其优化为单块内存的双向分配：持久数据从底部向上增长，临时数据从顶部向下增长 [3]。

这证明了：**“无堆分配”并不意味着“不能有持久状态”**。只要生命周期管理得当，持久状态完全可以和临时状态在同一个静态内存块中共存。

### 2.3 嵌入式 Rust 的 Heapless 模式
在资源受限的嵌入式 Rust 领域，`heapless` crate 提供了无需堆分配的动态数据结构（如 `Vec`、`String`）[4]。其秘诀在于：**在编译期通过泛型参数确定最大容量，底层由静态数组支撑**。

这完美契合了 Nebula 的编译期元编程哲学：动态行为不一定需要运行时的动态分配。

## 3. 第一性原理推导：Nebula 的破局之道

回到 Nebula 的三大哲学公理（零运行时开销、形状即渲染、声明意图派生代码），我们可以推导出一套完美的解决方案。

### 3.1 摒弃堆分配，拥抱“编译期定容 Gap Buffer”
我们不需要一个可以无限增长的、基于堆分配的 Gap Buffer。根据 `heapless` 的启示，我们可以利用 Nelua 的宏系统，在编译期生成一个**固定最大容量的 Gap Buffer**。

当开发者在组件树中声明一个文本框时：
```lua
nebula_app_register_component("Editor", "TextAreaVisual", {
    max_capacity = 1024 * 1024 -- 声明 1MB 的最大容量
})
```
`nebula_derive` 引擎会在编译期生成一个专属的 `GapBuffer_1MB` 结构体，底层是一个 `[1048576]uint8` 的静态数组。这完全消除了运行时的堆分配开销，同时满足了绝大多数文本编辑场景的需求。

### 3.2 状态与渲染的严格解耦
借鉴 GPUI 的双层架构，我们必须将文本的“存储”与“排版”彻底分离。

*   **持久层（State）**：编译期生成的定容 Gap Buffer 存储在组件的持久状态（Record）中，跨帧存活。它只负责 O(1) 的光标移动和字符插入/删除。
*   **临时层（Render）**：每帧渲染时，排版引擎读取 Gap Buffer，计算出每个可见字符的屏幕坐标和 UV，将这些**排版结果（Instance Data）分配在 Frame Arena 中**。

这种解耦不仅解决了生命周期矛盾，还带来了巨大的性能优势：只有当文本内容或视口发生变化时，才需要重新计算排版并写入 Arena；否则，直接复用上一帧的排版结果。

### 3.3 声明式意图驱动的专属管线
遵循“形状即渲染”哲学，多行文本编辑器不应该复用单行输入框的管线。

`nebula_derive` 应该为 `TextAreaVisual` 生成专属的 Instanced 渲染管线。这个管线不仅包含字符的字形渲染，还应该包含光标（Cursor）和选区（Selection）的专属着色器逻辑。所有这些都是在编译期按需生成的，没有任何运行时的分支判断（`if (has_selection)`）。

## 4. 结论与 Phase 3.6 路线图建议

通过上述推导，我们可以确信：**在不违背 Nebula 任何一条设计哲学的前提下，引入真正的文本编辑能力（Gap Buffer）不仅是可行的，而且是架构演进的必然方向。**

它将补齐 Nebula 作为 GUI 框架的最后一块核心拼图，使其从“静态表单渲染器”蜕变为“全功能交互框架”。

我建议将 Phase 3.6 命名为 **“持久状态与文本编辑引擎”**，并按以下最小可行路径推进：

1.  **Phase 3.6.1：编译期定容 Gap Buffer**
    *   实现 `gap_buffer.nelua` 泛型模块（支持编译期指定容量）。
    *   替换现有的 `[256]uint8`，实现 O(1) 的插入/删除和 O(N) 的光标移动。
2.  **Phase 3.6.2：排版与渲染解耦**
    *   重构 `text_runtime.nelua`，将文本存储（持久）与字形排版（Frame Arena）分离。
    *   实现基于 Gap Buffer 的 Instanced 文本渲染。
3.  **Phase 3.6.3：多行与选区模型**
    *   引入换行符处理和行高计算。
    *   实现鼠标命中测试（Hit Testing）和 Shift 框选逻辑。

这条路线既坚守了 Nebula 的极致性能底线，又优雅地解决了持久状态的架构难题。

---
### References
[1] GPUI Framework Architectural Concepts. https://docsmith.aigne.io/docs/zed/architectural-concepts-gpui-framework-ae8f50
[2] The Arena - Custom Memory Allocators in C. https://www.bytesbeneath.com/p/the-arena-custom-memory-allocators
[3] Zero-Compromise Arena Allocation: A Practical Approach. https://dev.to/unmeinks/no-compromise-arena-allocation-2nlb
[4] heapless - Rust Package Registry. https://crates.io/crates/heapless/0.7.17
