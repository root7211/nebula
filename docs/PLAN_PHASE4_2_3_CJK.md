# Phase 4.2.3 实施计划：HarfBuzz + CJK 集成

**目标**：在 S0 阶段（预处理）集成 HarfBuzz，完成所有字形数据提取和 shaping 规则预处理，实现 CJK 复杂文本的零运行时开销排版；并在 Phase 4.2.1（三端 PAL）与 Phase 4.2.2（Slug 生产级化）之上，验证 CJK 7000 常用字在 Linux/Windows/Web 三端的一致正确渲染。

> **依赖声明**（v3.1 重构）：本阶段是原 Phase 4.2 拆分后的收尾阶段，**硬依赖 Phase 4.2.1 与 Phase 4.2.2 已完成**。如在前两阶段完成前尝试推进本阶段，将同时承担 HarfBuzz 集成 + 平台抽象 + 渲染内核重构三条战线，违反 v3.1 总纲领的单一张力原则。

---

## 1. 架构背景与张力

如果说 Phase 4.2.2（Slug 生产级化）解决了"如何画好任意复杂字形"的问题，那么 Phase 4.2.3 解决的就是"如何把一堆字排好"的问题。

当前的 Nebula 依赖 `stb_truetype` 获取字符的 advance（步进宽度）进行简单排版。但这对于复杂的 Unicode 文本（尤其是包含连字、复杂字距调整的语言）是远远不够的。`stb_truetype` 仅支持基本的 kern 表，不支持高级的 GPOS（字形定位）和 GSUB（字形替换）表 [1]。

**HarfBuzz** 是业界标准的文本塑形（Text Shaping）引擎，被 Chrome、Android 等广泛使用 [2]。它能够将 Unicode 码点序列转换为正确排列和定位的字形序列。然而，HarfBuzz 的计算开销较大，如果将其引入运行时（S2），将严重违反 Nebula 的"零运行时分发"和"阶段封闭性"公理。

因此，Nebula 采取了极致的"阶段封闭性"策略：**拒绝在运行时引入 HarfBuzz，而是将其完全推入预处理阶段（S0）。**

---

## 2. 实施路径

### 2.1 S0 阶段：扩展 `font_preprocessor.nelua`

在预处理阶段，我们需要集成 HarfBuzz C API，并根据应用声明的字符集生成静态 shaping 查找表。

- **HarfBuzz 绑定**：创建 `harfbuzz_bindings.nelua`，通过 Nelua 的 `cimport` 机制绑定 HarfBuzz 的核心 C API（如 `hb_buffer_create`, `hb_shape`, `hb_font_create` 等）。
- **按需子集化 (Subset)**：
  - CJK 字符集庞大，穷举所有可能的 shaping 组合会导致状态爆炸。
  - 开发者必须在 `nebula_annotate` 中显式声明所需的字符范围（例如 `charset = "zh-CN-common"`）。
  - `font_preprocessor` 仅针对声明的字符集提取字形数据和 shaping 规则。
- **Shaping 规则预计算**：
  - 针对子集化后的字符集，在编译期运行 HarfBuzz，计算出所有可能的 shaping 规则（如特定字符对的 kerning 偏移、连字替换映射）。
  - 将这些规则导出为静态的查找表（Lookup Tables）。
- **输出生成**：生成 `shaping_tables.nelua`，包含预计算的偏移量和替换规则，作为编译期常量在 S1 阶段被包含。
- **复用 Phase 4.2.2 基础设施**：对每个子集化字形调用 4.2.2 中的自适应 band 分割与等价子集合并逻辑，确保 CJK 规模下的 GPU warp 收敛。

### 2.2 S1 阶段：编译期常量注入

在编译阶段，将 S0 生成的 shaping 表注入到运行时代码中。

- **常量加载**：在 `nebula_core.nelua` 中，加载 `shaping_tables.nelua`。
- **代码生成**：在生成 `TextContext` 和相关的排版函数时，确保它们能够访问这些静态查找表。

### 2.3 S2 阶段：零开销运行时排版

在运行阶段，文本排版逻辑将退化为简单的查表操作。

- **重构 `nebula_text_compute_advances`**：
  - 修改 `src/text_runtime.nelua` 中的排版函数。
  - 不再调用 `stbtt_GetCodepointHMetrics`，而是根据前一个字符和当前字符，从静态 shaping 表中获取偏移量（$O(1)$ 或 $O(\log N)$ 查表）。
- **零运行时开销**：没有任何复杂的 shaping 计算发生在用户的设备上，完全兑现了 Nebula 的架构承诺。

### 2.4 D-4.1-C 终裁

基于 Phase 4.2.2 产出的 `REPORT_PHASE4_2_2_BENCH.md`，在 CJK 规模下实测 Storage Buffer 路径的性能：
- 若 10000 字符规模下帧时间退化 < 20%，则保留 Storage Buffer，D-4.1-C 从登记表移除并标注"benchmark 驳回"。
- 若退化 ≥ 20%，则在本阶段内迁移至 RGBA32Float/Uint 纹理路径，D-4.1-C 正式清算。

---

## 3. 验收标准

1. **排版正确性**：能够正确处理 CJK 文本的字距调整（Kerning）和基本的连字（Ligature），排版结果与直接使用 HarfBuzz 运行时的结果一致。
2. **公理合规性**：S2 阶段没有任何 HarfBuzz 相关的函数调用或复杂的 shaping 计算，仅包含查表逻辑；`axiom_validator.lua` 通过。
3. **三端一致性**：相同的 `zh-CN-common` charset 应用在 Linux、Windows、Web (Wasm) 上渲染像素级一致（依赖 Phase 4.2.1）。
4. **CJK 规模性能**：7000 常用字在密集排版（如一屏 500 字）场景下，帧时间 ≤ 同数量 ASCII 渲染的 2.5 倍（依赖 Phase 4.2.2 的 band 优化）。
5. **内存占用**：生成的静态 shaping 表大小合理（对于 zh-CN-common 字符集，应控制在 4 MB 以内），不会导致编译产物过度膨胀。
6. **债务清算**：D-4.1-C 状态更新至 `ARCHITECTURE_GRAND_PLAN.md §5.2`（清算或驳回）。

---

## 4. 与其他 Phase 的依赖

| 依赖关系 | 对象 | 方向 |
| :--- | :--- | :--- |
| **硬前置** | Phase 4.2.1（PAL） | 本阶段验收需在三端运行 |
| **硬前置** | Phase 4.2.2（Slug 生产级化） | 本阶段的 CJK 7000 字规模需 D-4.1-A 与 D-4.1-B 已清算 |
| 不阻塞 | Phase 4.3（可编程原语注册表） | Phase 4.3 可在本阶段完成前启动，但涉及文本编辑的原语（如 `multiline_editable`）应等待本阶段 |

---

## 参考文献

[1] HarfBuzz Contributors. "Get kerning between two individual codepoints #2767". GitHub Discussions. https://github.com/harfbuzz/harfbuzz/discussions/2767
[2] HarfBuzz Contributors. "HarfBuzz text shaping engine". GitHub. https://github.com/harfbuzz/harfbuzz
