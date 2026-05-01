# Phase 4.2.3 实施计划 v2：字体自动机编译 + 动态文本排版

**目标**：在 S0 阶段将字体文件编译为确定性有限自动机（DFA），使 S2 运行时能够对**任意输入文本**（包括用户键入、网络加载、剪贴板粘贴）执行正确的 shaping 和排版，且运行时零 HarfBuzz 依赖、零规则解析，纯状态转移 + 查表。

**v2 修订摘要**（2026-05-01）：
- 废弃 v1 的 `charset = "zh-CN-common"` 子集化方案——该方案无法处理运行时不可预知的输入
- 引入"字体自动机"架构：S0 编译字体全量 OpenType 规则为静态 DFA + 查找表
- 新增分级部署模型（内嵌 / 侧载 / notdef）
- 新增 Unicode UAX#14 换行表预生成，解决动态文本的运行时排版
- 明确公理合规性的理论基础：字体是封闭有限集

> **依赖声明**：硬依赖 Phase 4.2.1（PAL）与 Phase 4.2.2（Slug 生产级化）已完成。

---

## 1. 架构背景与核心洞察

### 1.1 v1 方案的根本缺陷

v1 要求开发者在 `nebula_annotate` 中显式声明字符集（`charset = "zh-CN-common"`），然后仅对声明的字符集预处理 shaping 规则。这带来了一个无法回避的问题：

> **用户输入了声明之外的字符怎么办？**

网络加载的文本、剪贴板粘贴的内容、IME 输入的生僻字——这些都无法在编译时预知。v1 的回答是"超出范围显示 tofu"，但这对于通用 GUI 框架是不可接受的。

### 1.2 核心洞察：字体是封闭有限集

关键认识是：**"不可预知"有上界——上界就是字体文件本身。**

一个 `.ttf/.otf` 文件包含：
- **有限的字形集**：NotoSansCJK ~65K glyphs，不会更多
- **有限的 GSUB 规则**：连字替换（f+f+i → ﬃ）在字体中穷举定义
- **有限的 GPOS 规则**：字距调整对（A+V → -30 units）在字体中穷举定义
- **有限的 Script/Language 标签**：字体声明自己支持哪些书写系统

因此：

```
shaping(font_rules, char_sequence) → glyph_sequence
```

其中 `font_rules` 在 S0 **完全已知且有限**。用户输入再不可预知，也不可能超出字体的 glyph 覆盖范围。超出的部分就是 `.notdef`（tofu □），不需要 shaping。

**这意味着我们可以在 S0 将字体的全部 shaping 能力编译为确定性自动机，而无需预知运行时的具体输入。**

### 1.3 与 HarfBuzz 的关系

HarfBuzz 在运行时做的事情本质上是：
1. 读取字体的 OpenType Layout 表
2. 构建内部状态机
3. 对输入文本执行状态转移

Nebula 的策略是将步骤 1-2 推到 S0，S2 只执行步骤 3。HarfBuzz 仍然是 S0 的工具（用于提取和验证规则），但**不是 S2 的运行时依赖**。

---

## 2. 实施路径

### 2.1 S0 阶段：字体自动机编译

#### 2.1.1 全量规则提取

在 S0 阶段，使用 HarfBuzz C API 对字体文件进行完整分析，提取所有 shaping 规则：

```
输入：font.ttf
输出：
  ┌─ glyph_metrics[glyph_id]    → {advance_x, advance_y, lsb, bbox}
  ├─ kern_pairs[(glyph_a, glyph_b)] → {x_offset, y_offset}
  ├─ gsub_rules[{script, feature, input_seq}] → output_glyph_seq
  ├─ gpos_rules[{script, feature, glyph_seq}] → position_adjustments
  ├─ cmap[codepoint] → glyph_id
  └─ glyph_bands[glyph_id] → Slug band data（复用 Phase 4.2.2）
```

**关键约束**：不做子集化。提取字体中**所有** glyph 的完整数据。

#### 2.1.2 GSUB 规则编译为 DFA

OpenType GSUB 表定义了有限的替换规则。将这些规则编译为确定性有限自动机：

```
S0 处理流程：
  1. 枚举字体所有 GSUB Lookup（按 script + feature 分组）
  2. 对每个 Lookup，提取所有 (input_sequence → output_sequence) 映射
  3. 构建 Aho-Corasick 多模式匹配自动机
  4. 最小化状态数（Hopcroft 算法）
  5. 输出为紧凑的状态转移表

输出格式：
  gsub_dfa = {
    states: [N]DFAState,          -- 状态数组
    transitions: [N][M]StateID,   -- 转移表（state × input_class → next_state）
    outputs: [N]?GlyphSubst,      -- 输出表（若该状态为接受态，记录替换结果）
    input_classes: [65536]ClassID -- codepoint → input_class 映射（压缩输入空间）
  }
```

典型的 Latin 字体 GSUB 规则约 200-500 条，生成的 DFA 状态数约 1000-3000。CJK 字体 GSUB 规则极少（CJK 文字基本不做连字），状态数更少。

#### 2.1.3 GPOS/Kerning 编译为哈希表

```
S0 处理流程：
  1. 提取所有 kern pair（从 GPOS PairPos 或旧式 kern 表）
  2. 构建 (glyph_a, glyph_b) → offset 的完美哈希表（MPH）
  3. 对于 Class-based kerning，展开为 glyph pair 级别

输出格式：
  kern_table = {
    hash_seeds: [bucket_count]uint32,   -- 完美哈希种子
    entries: [pair_count]KernEntry,      -- {glyph_a, glyph_b, x_offset, y_offset}
  }
```

典型字体的 kern pair 数量：Latin ~3000-8000 对，CJK ~0-100 对。完美哈希查找为严格 O(1)。

#### 2.1.4 Unicode UAX#14 换行属性表

为支持动态文本的运行时折行，预生成 Unicode 换行属性表：

```
S0 处理流程：
  1. 解析 Unicode Character Database 的 LineBreak.txt
  2. 为 0x0000-0x10FFFF 的每个 codepoint 分配 Line_Break 类别（共 43 类）
  3. 使用两级分页表压缩（大部分 block 共享相同模式）
  4. 生成 UAX#14 pair table（43×43 矩阵，定义相邻字符间是否允许断行）

输出格式：
  line_break = {
    stage1: [2176]uint8,            -- 第一级索引（codepoint >> 8）
    stage2: [N][256]uint8,          -- 第二级（LineBreak class, 6 bit 够用）
    pair_table: [43][43]BreakAction -- {PROHIBITED, ALLOWED, MANDATORY}
  }
```

压缩后的两级表约 40-80 KB。

#### 2.1.5 输出文件结构

S0 的最终产物是一组 `.nfp`（Nebula Font Package）文件：

```
my_font.nfp（单文件，内部分段）:
  ├─ header        (magic + version + section offsets)
  ├─ cmap          (codepoint → glyph_id, 两级分页表)
  ├─ metrics       (glyph_id → advance/bearing/bbox)
  ├─ gsub_dfa      (状态转移表 + 输出表)
  ├─ kern_mph      (完美哈希 kerning 表)
  ├─ line_break    (UAX#14 两级分页表 + pair table)
  └─ slug_bands    (glyph_id → Slug 渲染数据，按 Unicode block 分段)
```

### 2.2 S1 阶段：分级部署策略

编译期根据开发者声明决定数据的部署方式：

```nelua
##[[
  nebula_annotate("MyVisual", {
    -- 分级部署声明
    font = "NotoSansCJK-Regular.ttf",
    font_deploy = {
      embedded = {"latin", "cjk_common_3500"},  -- 内嵌到二进制 .rodata
      sidecar  = "full",                         -- 全量 .nfp 侧载文件
      fallback = "notdef"                        -- 超出字体覆盖：□
    }
  })
]]
```

| 部署层级 | 数据来源 | 首次访问延迟 | 后续延迟 | 适用场景 |
|:---------|:---------|:-------------|:---------|:---------|
| **embedded** | 二进制 `.rodata` 段 | 0 | 0 | UI 标签、按钮文字等确定内容 |
| **sidecar** | mmap `.nfp` 文件 | ~1ms (page fault) | 0 | 用户输入、网络文本、文件内容 |
| **notdef** | 硬编码 □ glyph | 0 | 0 | 字体不覆盖的 codepoint |

S1 代码生成器的职责：
1. 将 `embedded` 声明的 Unicode block 对应的数据直接内联为 Nelua 编译期常量
2. 生成 sidecar 加载器代码（mmap + page table 索引）
3. 生成 fallback 路径代码（直接返回 `.notdef` glyph 数据）

### 2.3 S2 阶段：纯查表运行时

运行时的文本处理退化为三个线性扫描：

#### 2.3.1 Shaping（GSUB 替换）

```
-- 伪代码：对输入文本执行 GSUB DFA
state = DFA_START
for i = 0, text.len - 1 do
  local cls = gsub_dfa.input_classes[text[i]]  -- O(1) codepoint → class
  state = gsub_dfa.transitions[state][cls]      -- O(1) 状态转移
  if gsub_dfa.outputs[state] then
    apply_substitution(gsub_dfa.outputs[state])  -- 替换 glyph
  end
end
```

**复杂度**：O(N)，每字符两次数组索引。无分支预测失败（转移表是连续内存）。

#### 2.3.2 Positioning（GPOS/Kerning）

```
-- 伪代码：查 kerning
for i = 1, glyphs.len - 1 do
  local offset = kern_mph.lookup(glyphs[i-1], glyphs[i])  -- O(1) 完美哈希
  positions[i].x += offset.x
  positions[i].y += offset.y
end
```

**复杂度**：O(N)，每字符一次哈希查找。

#### 2.3.3 Line Breaking（换行）

```
-- 伪代码：贪心换行
line_x = 0
for i = 0, glyphs.len - 1 do
  local w = metrics[glyphs[i]].advance_x       -- O(1)
  if line_x + w > container_width then
    local cls_prev = line_break.lookup(text[i-1]) -- O(1) 两级分页
    local cls_curr = line_break.lookup(text[i])   -- O(1)
    local action = line_break.pair_table[cls_prev][cls_curr] -- O(1)
    if action == ALLOWED or action == MANDATORY then
      emit_line_break()
      line_x = 0
    end
  end
  line_x += w
end
```

**复杂度**：O(N)，每字符最多三次数组索引。

#### 2.3.4 运行时禁止清单

`axiom_validator.lua` 新增规则——以下符号在 S2 代码中**禁止出现**：

```lua
S2_FORBIDDEN_SYMBOLS = {
  "hb_shape", "hb_buffer_create", "hb_font_create",  -- HarfBuzz
  "stbtt_GetCodepointHMetrics", "stbtt_GetGlyphKernAdvance",  -- stb_truetype shaping
  "FT_Load_Glyph", "FT_Get_Kerning",  -- FreeType
}
```

允许的 S2 操作：数组索引、哈希查找、mmap、memcpy。

---

## 3. 尺寸估算

### 3.1 典型字体的 .nfp 文件大小

| 字体 | Glyphs | GSUB 规则 | Kern Pairs | .nfp 估算 |
|:------|:-------|:----------|:-----------|:----------|
| Inter (Latin) | ~2,500 | ~300 | ~5,000 | ~8 MB |
| NotoSansCJK | ~65,000 | ~50 | ~100 | ~180 MB |
| NotoSans-Regular | ~3,500 | ~400 | ~8,000 | ~12 MB |

CJK 字体的体积主要来自 `slug_bands`（每个字形的矢量渲染数据）。如果使用 SDF atlas 替代 Slug，可降至 ~40 MB。

### 3.2 内嵌与侧载的权衡

| 策略 | 二进制体积增量 | 运行时延迟 | 适用场景 |
|:-----|:---------------|:-----------|:---------|
| 全量内嵌 | +180 MB | 0 | 嵌入式设备（Flash 足够大） |
| Latin 内嵌 + CJK 侧载 | +8 MB | 首次 ~1ms | 桌面应用 |
| 全量侧载 | +0 | 首次 ~1ms | 包体积敏感场景 |

---

## 4. 公理合规性论证

### 4.1 公理 A（阶段封闭性）

> 每个操作必须归属于其输入最早全部可知的阶段。

- **字体规则**在 S0 全部可知 → shaping 规则编译（DFA 构建）属于 S0 ✓
- **用户输入文本**在 S2 才可知 → 对 DFA 执行状态转移属于 S2 ✓
- **容器宽度**在 S2 才可知 → 换行判定属于 S2 ✓

没有操作被放在错误的阶段。S2 执行的不是"shaping 计算"，而是"对预编译自动机的线性执行"——正如 regex 区分"编译"和"匹配"。

### 4.2 公理 B（生命周期三层）

- DFA 转移表、kern hash 表、line break pair table → **L0（永久）**，程序启动后不变
- mmap 的 sidecar 页面 → **L1（持久）**，按需加载后持久驻留
- 排版结果（glyph positions, line breaks） → **L2（帧级）**，每帧可能因窗口 resize 重算

### 4.3 公理 C（形即渲染）

字体自动机不改变 Visual 类型到管线签名的映射关系——它只影响管线的**输入数据**（哪些 glyph、什么位置），不影响管线**结构**。

---

## 5. 实施步骤

### S1：全量规则提取器（font_compiler）

- 扩展 `font_preprocessor.nelua`，调用 HarfBuzz 枚举字体的全部 GSUB/GPOS Lookup
- 输出中间格式：规则列表 JSON（用于调试和验证）
- 验证：对比 HarfBuzz 运行时 shaping 结果与提取的规则是否一致

### S2：DFA 编译器 + MPH 构建器

- 实现 GSUB 规则 → Aho-Corasick DFA 的编译
- 实现 Hopcroft DFA 最小化
- 实现 kern pairs → 完美哈希表（CHD 算法）
- 实现 UAX#14 两级分页表生成
- 输出 `.nfp` 二进制文件

### S3：S2 运行时集成

- 实现 `.nfp` mmap 加载器（`nebula_font_load`）
- 重构 `text_runtime.nelua`：用 DFA 执行替代 `stbtt_GetCodepointHMetrics`
- 实现换行算法（贪心 + UAX#14 pair table）
- `axiom_validator` 新增 S2 禁止符号规则

### S4：验证与基准

- 正确性：对 1000 组随机文本，对比 DFA 执行结果与 HarfBuzz 运行时结果
- 性能：CJK 500 字/屏的 shaping + layout 延迟 ≤ 0.1ms
- 尺寸：验证 .nfp 文件大小符合预期

---

## 6. 验收标准

1. **动态文本正确性**：对任意运行时输入（包括编译时未声明的字符），shaping 结果与 HarfBuzz 运行时一致
2. **公理合规性**：S2 代码中无 HarfBuzz/stb_truetype/FreeType 的 shaping 函数调用；`axiom_validator` 通过
3. **性能**：500 字 CJK 文本的 shaping + positioning + line breaking 合计 ≤ 0.1ms/帧
4. **分级部署**：embedded 路径零延迟；sidecar 路径首次 page fault ≤ 2ms
5. **三端一致性**：Linux/Windows/Web 上相同输入文本的 glyph 序列和位置完全一致
6. **尺寸**：NotoSansCJK 的 .nfp 文件 ≤ 200 MB；embedded Latin subset ≤ 10 MB

---

## 7. 与其他 Phase 的关系

| 关系 | 对象 | 说明 |
|:-----|:-----|:-----|
| **硬前置** | Phase 4.2.1（PAL） | 三端 mmap 实现差异需 PAL 抽象 |
| **硬前置** | Phase 4.2.2（Slug 生产级化） | slug_bands 数据生成依赖 4.2.2 的 band 分割算法 |
| **解锁** | Phase 4.X（高密度文本） | 字体自动机提供 per-char metrics，高密度文本通道需要 |
| **解锁** | Phase 4.7（文本编辑器） | 换行算法 + 动态 shaping 是编辑器的硬前置 |
| **不再阻塞** | 用户输入场景 | v1 的 charset 限制被移除 |

---

## 8. 相对于 v1 的变化总结

| 维度 | v1（子集化方案） | v2（字体自动机方案） |
|:-----|:-----------------|:--------------------|
| 覆盖范围 | 仅声明的 charset | 字体全量 glyph |
| 动态文本 | 不支持（tofu） | 完全支持 |
| S2 依赖 | 无 | 无 |
| 输出体积 | ≤ 4 MB | 8-200 MB（分级部署） |
| 开发者负担 | 必须声明 charset | 可选声明 embedded 范围 |
| 公理合规性 | 合规 | 合规（更强的理论基础） |
| 核心权衡 | 功能受限换体积小 | 体积大换功能完整 |

---

## 参考文献

[1] HarfBuzz Contributors. "HarfBuzz text shaping engine". GitHub. https://github.com/harfbuzz/harfbuzz
[2] Unicode Consortium. "UAX #14: Unicode Line Breaking Algorithm". https://www.unicode.org/reports/tr14/
[3] Aho, A. & Corasick, M. "Efficient String Matching: An Aid to Bibliographic Search". CACM, 1975.
[4] Belazzougui, D. et al. "Hash, Displace, and Compress" (CHD perfect hashing). ESA, 2009.
[5] Hopcroft, J. "An n log n algorithm for minimizing states in a finite automaton". 1971.
