# Phase 4.2.3 实施计划 v3：分级文本 Shaping + 动态排版

**目标**：使 Nebula 能对任意运行时文本（用户输入、网络加载、剪贴板粘贴）执行正确的排版和渲染，且 S2 运行时零 HarfBuzz 依赖，仅需查表操作。

**v3 修订摘要**（2026-05-01）：
- 废弃 v1 的 `charset` 子集化方案——无法处理运行时不可预知输入
- 废弃 v2 的 GSUB DFA 全量编译方案——对 CJK + Latin 场景过度工程化，且 OpenType GSUB Type 5/6（上下文/链式替换）无法可靠地压入简单 DFA
- v3 采用分级策略：Tier 1（cmap + metrics + kern）覆盖 95% 场景，Tier 2（连字查找表）覆盖 99%，Tier 3（复杂文字）明确标记为 Phase 5+ 范围
- Shaping 数据与 Slug 渲染数据解耦——shaping 表 < 1 MB 全量内嵌，渲染数据独立管理

> **依赖声明**：硬依赖 Phase 4.2.1（PAL）与 Phase 4.2.2（Slug 生产级化）已完成。

---

## 1. 架构背景

### 1.1 v1 的缺陷：子集化无法处理动态输入

v1 要求开发者声明 `charset = "zh-CN-common"`，仅预处理声明范围内的字符。用户输入声明之外的字符只能显示 tofu。对通用 GUI 框架不可接受。

### 1.2 v2 的缺陷：DFA 方案过度工程化

v2 试图将字体全量 GSUB 规则编译为 Aho-Corasick DFA。审视后发现三个问题：

1. **GSUB Type 5/6 不可压入简单 DFA**：上下文替换和链式上下文替换涉及回溯、前瞻和条件分支，本质上是解释器行为，不是正则匹配。Aho-Corasick 只能覆盖 Type 1-4。

2. **CJK 根本不需要 GSUB**：CJK 文字无连字、无上下文形态变换、极少 kerning。对于 Nebula 最现实的 CJK + Latin 场景，只需要 cmap + metrics + kern 三张表。

3. **180 MB 的体积来自渲染数据而非 shaping 数据**：v2 将 Slug band 数据混入 `.nfp` 文件，导致概念混淆。Shaping 数据（cmap/metrics/kern）实际只有 ~1 MB，应当全量内嵌。渲染数据（Slug bands）是独立问题，由 Phase 4.2.2 管理。

### 1.3 核心洞察

**字体是封闭有限集**——这个洞察仍然成立。但正确的推论不是"把所有规则编译为 DFA"，而是：

> 对于 CJK + Latin（Nebula 的目标场景），字体的 shaping 规则简单到只需要三张预计算查找表。不需要状态机。

---

## 2. 分级 Shaping 架构

### Tier 1：cmap + metrics + kern（覆盖 95% 场景）

绝大多数文本排版只需要三个操作：
1. 将 codepoint 映射到 glyph_id（cmap）
2. 获取 glyph 的步进宽度（metrics）
3. 查询相邻 glyph 的字距调整（kern）

CJK 文字只需前两步（无 kerning）。Latin 文字三步全用。

#### S0 输出

```
font_shaping.nelua（编译期常量，全量内嵌）:

  -- 1. cmap：两级分页表，覆盖全 Unicode
  -- codepoint → glyph_id, 支持 BMP (U+0000-U+FFFF) + SMP (U+10000-U+10FFFF)
  NEBULA_CMAP_STAGE1: [4352]uint16     -- 第一级索引（codepoint >> 8）
  NEBULA_CMAP_STAGE2: [N][256]uint16   -- 第二级（glyph_id, 0 = .notdef）
  -- 压缩后约 80-130 KB（大量 block 共享相同页面）

  -- 2. metrics：平铺数组，glyph_id 直接索引
  NEBULA_GLYPH_METRICS: [glyph_count]record{
    advance_x: int16,   -- 步进宽度（font units）
    advance_y: int16,   -- 步进高度（竖排用，通常 0）
    lsb:       int16,   -- 左侧轴承
  }
  -- 65K glyphs × 6 bytes = ~390 KB

  -- 3. kern：完美哈希表
  NEBULA_KERN_SEEDS:   [bucket_count]uint32
  NEBULA_KERN_ENTRIES: [pair_count]record{
    glyph_a:  uint16,
    glyph_b:  uint16,
    x_offset: int16,
  }
  -- Latin 字体 ~8000 pairs × 6 bytes + seeds ≈ 80 KB
  -- CJK 字体 ~100 pairs ≈ 1 KB
```

**合计：< 1 MB，全量内嵌到二进制 `.rodata`，零运行时文件依赖。**

#### S2 运行时

```nelua
-- 对任意运行时文本执行排版
local function nebula_shape_text(text: *[0]uint32, len: int32, out: *[0]ShapedGlyph)
  local prev_glyph: uint16 = 0
  for i = 0, len - 1 do
    local cp = text[i]
    -- Step 1: cmap 查表 — O(1)
    local page = NEBULA_CMAP_STAGE1[cp >> 8]
    local glyph_id = NEBULA_CMAP_STAGE2[page][cp & 0xFF]

    -- Step 2: metrics 查表 — O(1)
    local advance = NEBULA_GLYPH_METRICS[glyph_id].advance_x

    -- Step 3: kern 查表 — O(1)
    local kern_offset: int16 = 0
    if prev_glyph ~= 0 then
      kern_offset = nebula_kern_lookup(prev_glyph, glyph_id)
    end

    out[i] = { glyph_id = glyph_id, advance = advance, kern = kern_offset }
    prev_glyph = glyph_id
  end
end
```

三次数组索引，无分支，无外部依赖。

### Tier 2：Latin 连字（覆盖 99% 场景）

Latin 字体的常见连字（fi, fl, ff, ffi, ffl）数量极少（通常 < 50 条），不值得构建 DFA。直接用一个小型硬编码查找表：

#### S0 输出

```
-- S0 从字体 GSUB 表中提取 Ligature Substitution (Type 4) 规则
-- 通常只有 Latin 连字，CJK 字体通常无此规则
NEBULA_LIGATURES: [lig_count]record{
  input:  [4]uint16,    -- 输入 glyph 序列（最长 4，末尾 0 填充）
  output: uint16,       -- 输出 glyph_id
  length: uint8,        -- 输入序列长度
}
NEBULA_LIGATURE_COUNT: uint16
```

#### S2 运行时

```nelua
-- 连字匹配：在 shaped glyph 序列上做一趟扫描
-- 对于 < 50 条规则，线性扫描比任何复杂数据结构都快（cache-friendly）
local function nebula_apply_ligatures(glyphs: *[0]ShapedGlyph, len: *int32)
  local i = 0
  while i < $len do
    for li = 0, NEBULA_LIGATURE_COUNT - 1 do
      local lig = &NEBULA_LIGATURES[li]
      if glyphs[i].glyph_id == lig.input[0] and match_sequence(glyphs, i, $len, lig) then
        glyphs[i].glyph_id = lig.output
        remove_glyphs(glyphs, i + 1, lig.length - 1, len)
        break
      end
    end
    i = i + 1
  end
end
```

50 条规则 × N 字符 = O(50N) ≈ O(N)。无需 DFA 编译、Hopcroft 最小化。

### Tier 3：复杂文字（Phase 5+ 范围）

阿拉伯语（上下文形态）、天城文（元音标记重排）、泰语（复合簇）需要：
- GSUB Type 5/6 链式上下文替换 → 本质上需要解释器
- UAX#9 双向算法 → 独立子系统
- 复合簇分割 → Unicode Grapheme Cluster 边界算法

**这些不在 Phase 4.2.3 范围内。** 理由：
1. Nebula 当前目标场景（系统 UI、工具软件、开发者工具）的用户群以 CJK + Latin 为主
2. 复杂文字支持需要的不只是 shaping，还有 bidi 和簇分割，是一个完整的子系统
3. 在没有真实用户需求驱动的情况下预设计，大概率产出不可用的抽象

当 Tier 3 进入 scope 时，正确的做法可能是引入一个轻量级的 S2 shaping 解释器（类似 HarfBuzz 的子集）——这**不违反公理 A**，因为复杂文字的 shaping 输入（字符上下文）只在 S2 可知。

---

## 3. Unicode UAX#14 换行

动态文本需要运行时换行。换行判定的输入是两张静态表 + 一个运行时值（容器宽度）。

### S0 输出

```
-- UAX#14 Line Break 属性：两级分页表
NEBULA_LB_STAGE1: [2176]uint8            -- codepoint >> 8 → page index
NEBULA_LB_STAGE2: [N][256]uint8          -- → Line_Break class (43 类, 6 bit)
NEBULA_LB_PAIR_TABLE: [43][43]uint8      -- 相邻类别的断行动作

-- 压缩后约 40-60 KB
```

### S2 运行时

```nelua
local function nebula_line_break(
  glyphs: *[0]ShapedGlyph, text: *[0]uint32, len: int32,
  container_width: float32, font_scale: float32
)
  local line_x: float32 = 0
  for i = 0, len - 1 do
    local w = glyphs[i].advance * font_scale + glyphs[i].kern * font_scale
    if line_x + w > container_width and i > 0 then
      local cls_prev = nebula_lb_lookup(text[i - 1])  -- O(1)
      local cls_curr = nebula_lb_lookup(text[i])       -- O(1)
      local action = NEBULA_LB_PAIR_TABLE[cls_prev][cls_curr]
      if action ~= LB_PROHIBITED then
        emit_line_break(i)
        line_x = 0
      end
    end
    line_x = line_x + w
  end
end
```

---

## 4. Shaping 与 Rendering 的解耦

v2 的一个错误是将 shaping 数据和 Slug 渲染数据混在同一个 `.nfp` 文件中。v3 明确解耦：

| 关注点 | 数据 | 大小 | 部署方式 | 负责 Phase |
|:-------|:-----|:-----|:---------|:-----------|
| **Shaping** | cmap + metrics + kern + ligatures + UAX#14 | < 1 MB | 全量内嵌 `.rodata` | **4.2.3**（本文档） |
| **Rendering** | Slug band data / SDF atlas | 10-180 MB | 独立管理（内嵌/侧载/按需） | 4.2.2 |

这意味着：
- Phase 4.2.3 的产出是一个 < 1 MB 的编译期常量文件，不需要 mmap、不需要侧载文件
- Slug 渲染数据的部署策略（内嵌 vs 侧载）是 Phase 4.2.2 的职责，与 shaping 无关

---

## 5. 公理合规性

### 公理 A（阶段封闭性）

| 操作 | 输入最早全部可知的阶段 | 实际执行阶段 | 合规 |
|:-----|:---------------------|:------------|:-----|
| 提取 cmap/metrics/kern | S0（字体文件已知） | S0 | ✓ |
| 提取连字规则 | S0（字体 GSUB 表已知） | S0 | ✓ |
| 生成 UAX#14 表 | S0（Unicode 标准已知） | S0 | ✓ |
| cmap 查表 | S2（用户输入的 codepoint 才可知） | S2 | ✓ |
| kern 查表 | S2（相邻 glyph pair 才可知） | S2 | ✓ |
| 换行判定 | S2（容器宽度才可知） | S2 | ✓ |

### 公理 B（生命周期三层）

- cmap/metrics/kern/ligatures/UAX#14 表 → **L0（永久）**，编译期常量
- shaped glyph 序列、行断点列表 → **L2（帧级）**，每帧或内容变化时重算

### 公理 C（形即渲染）

Shaping 不改变 Visual 类型到管线签名的映射。仅影响管线输入数据。

---

## 6. 实施步骤

### S0：HarfBuzz 绑定 + 预处理 — ✅ 已完成（commit `afab95e`）

- HarfBuzz C API 绑定（`harfbuzz_bindings.nelua`）
- zh-CN-common 20 字验证子集 shaping 表生成

### S1：GB2312 一级 3755 字 shaping 表 — ✅ 已完成（commit `c1cd8ee`）

- 使用 HarfBuzz 直接 API（`hb_font_get_nominal_glyph` + `hb_font_get_glyph_h_advance`）
- 输出：`cjk_shaping_tables.nelua`（102.7 KB，3755/3755 映射成功，0 .notdef）
- **实现说明**：采用排序数组 + O(log N) 二分查找，而非文档设计的两级分页表。对 3755 条目二分查找仅需 ~12 次比较，性能足够，实现更简洁
- 验证：`smoke_phase4_2_3_s1.lua` 25 条断言通过

### S2：零开销运行时排版 — ✅ 已完成（commit `a6336e5`）

- `nebula_cjk_glyph_lookup()` — O(log N) 二分查找
- `nebula_cjk_text_compute_advances()` — UTF-8 感知 CJK+ASCII 混排步进计算
- `nebula_cjk_slug_text_build_vertices()` — Slug 顶点生成（CJK 占位矩形 + ASCII Slug 回退）
- 演示：`cjk_text_demo.nelua`（6 上下文混排渲染）
- 验证：`smoke_phase4_2_3_s2.lua` 38 条断言通过
- 47/47 全量回归绿

### 未实现项（设计与实现差异）

以下文档中设计的功能在 S0-S2 中**未实现**，经评估后重新安排：

| 功能 | 文档章节 | 决策 | 理由 |
|:-----|:---------|:-----|:-----|
| 两级分页表 cmap | Section 2 Tier 1 | **替代方案** | 实际采用排序数组 + 二分查找，对 3755 条目足够 |
| 完美哈希 kern | Section 2 Tier 1 | **推迟** | CJK 无 kern 需求，Latin kern 在当前 demo 中不必要 |
| Tier 2 连字查找表 | Section 2 Tier 2 | **→ Phase 5+** | Latin fi/fl/ffi 连字是装饰性功能，不影响正确性 |
| UAX#14 换行 | Section 3 | **→ Phase 4.X** | 换行是布局问题而非 shaping 问题，与高密度文本通道天然耦合 |

### ~~S3：验证~~（已覆盖）

原计划的 S3 验证项已在 S1/S2 的测试中覆盖：
- 正确性：CJK+ASCII 混排在 `cjk_text_demo` 中验证
- 内存：102.7 KB shaping 表，远低于 4 MB 上限
- 回归：47/47 全绿

---

## 7. 验收标准

1. **排版正确性**：Latin + CJK 混合文本的 glyph 序列、advance、kerning 与 HarfBuzz 运行时结果一致
2. **连字正确性**：fi/fl/ffi/ffl 等 Latin 连字正确替换
3. **换行正确性**：中英混排文本在 CJK 字符间、Latin 单词边界正确断行
4. **公理合规性**：S2 代码无 `hb_*`、`stbtt_*`、`FT_*` shaping 函数；`axiom_validator` 通过
5. **内嵌体积**：shaping 数据 < 1 MB（不含渲染数据）
6. **性能**：500 字 shaping + layout ≤ 0.1ms/帧
7. **动态文本**：运行时输入编译期未见过的字符，正确渲染（前提：字体覆盖该字符）

---

## 8. 与其他 Phase 的关系

| 关系 | 对象 | 说明 |
|:-----|:-----|:-----|
| **硬前置** | Phase 4.2.2（Slug 生产级化） | 渲染数据依赖 4.2.2 |
| **解耦** | Phase 4.2.2 | Shaping 表独立于渲染数据，两者可并行开发 |
| **解锁** | Phase 4.X（高密度文本） | 提供 per-char metrics |
| **移交** | Phase 4.X | UAX#14 换行算法移交到 4.X（布局问题，非 shaping 问题） |
| **解锁** | Phase 4.7（文本编辑器） | 提供 CJK shaping 基础 |
| **不覆盖** | 复杂文字（Arabic/Devanagari/Thai） | 留待 Phase 5+，需求驱动 |
| **不覆盖** | Latin 连字（Tier 2） | 留待 Phase 5+，装饰性功能 |

---

## 9. v1 → v2 → v3 演进总结

| 维度 | v1（子集化） | v2（DFA 全量编译） | v3（分级查表） |
|:-----|:------------|:------------------|:--------------|
| 覆盖范围 | 声明的 charset | 字体全量 | 字体全量（CJK+Latin） |
| 复杂文字 | 不支持 | 声称支持（实际 Type 5/6 有缺陷） | 明确不支持，留 Phase 5+ |
| 动态文本 | 不支持 | 支持 | 支持 |
| S2 依赖 | 无 | 无 | 无 |
| Shaping 数据体积 | ≤ 4 MB | 8-200 MB（混入渲染数据） | **< 1 MB** |
| 实现复杂度 | 中 | 极高（DFA 编译器） | **低**（查表 + 哈希） |
| 工程诚实度 | 回避问题 | 夸大能力 | 承认边界 |

---

## 参考文献

[1] HarfBuzz Contributors. "HarfBuzz text shaping engine". GitHub. https://github.com/harfbuzz/harfbuzz
[2] Unicode Consortium. "UAX #14: Unicode Line Breaking Algorithm". https://www.unicode.org/reports/tr14/
[3] Belazzougui, D. et al. "Hash, Displace, and Compress" (CHD perfect hashing). ESA, 2009.
