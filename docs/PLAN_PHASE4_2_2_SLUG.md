# Phase 4.2.2 实施计划：Slug 渲染内核生产级化

**目标**：清算 Phase 4.1 作为 MVP 引入的三项渲染内核债务（D-4.1-A / D-4.1-B / D-4.1-C），将 Slug 实现从 "ASCII + 轴对齐" 的简化形态升级为 "Latin 全量 + 任意仿射 + 可扩展至 CJK 规模" 的生产级形态。

> **叙事定位**（v3.1 重构）：本阶段在叙事上是 **Era I "形即渲染" 的终章补完**，在时间线上与 Phase 4.2.1（PAL）并行推进。它不是 Era II "形即行为" 的开篇，但它是 Phase 4.2.3 CJK 集成的**必要前置**。

---

## 1. 架构背景：三项已识别债务

对照 Slug 原始论文（Lengyel 2017 JCGT）与 2018 SOTA 演讲的 Banding 章节（pp. 876–955），Phase 4.1 的实现存在三项有意识的简化取舍。在 ASCII（95 字形、2328 曲线、最大曲线数 < 100/字形）规模下这些取舍无感，但在 CJK 或任意仿射变换场景下会触发失效。

### 债务 D-4.1-A：固定均匀 Band 分割

- **现状**：`tools/font_preprocessor_slug.nelua:58` 使用 `BAND_COUNT = 8` 固定常量，水平/垂直各 8 个均匀分带，无合并逻辑。
- **论文立场**：*"Use large number of bands, merge those with equal subsets of Bézier curves"*（SOTA slides 940–955）。Slug 的正确设计是先生成大量细 band，再基于等价曲线子集做合并，保证最坏 band 曲线数最少，以维持 GPU warp 同步收敛（32 或 64 像素组等待最长循环迭代）。
- **失效条件**：字形曲线数 > 50 或 CJK 导致单 band 曲线数 > 12。

### 债务 D-4.1-B：跳过 Jacobian 与 SlugDilate

- **现状**：`slug_reference_notes.md:59` 已承认 "skip jac for now"，顶点格式 `NebulaSlugVertex` 仅包含 4 个 `vec4<f32>`（pos / tex / bnd / col），缺少 `jac: (invScale, 0, 0, invScale)` 属性；片元着色器未实现 SlugDilate sub-pixel 膨胀。
- **论文立场**：Jacobian 逆矩阵是从屏幕空间像素占用回推 em 空间覆盖区间的核心变换；SlugDilate 是在 sub-pixel 尺度上膨胀曲线以补偿采样不足。二者协同保证**任意仿射变换下的正确覆盖率计算**。
- **失效条件**：任意旋转、倾斜、非各向同性缩放；或文本以 < 12pt 呈现。

### 债务 D-4.1-C：Storage Buffer 替代纹理

- **现状**：曲线 / band_meta / band_ref 通过三个 Storage Buffer binding 上传（`pipeline_factory.lua:657–730`）。
- **论文立场**：Slug 原论文使用 RGBA32Float（曲线）+ RGBA32Uint（band）纹理，充分利用 GPU 纹理缓存的空间局部性。
- **失效条件**：字形总数 > 500 或帧内有效渲染字符数 > 5000，进入内存带宽受限区间。
- **注**：本债务的实际影响需通过 benchmark 量化后再决定是否强制清算，参见第 4 节。

---

## 2. 实施路径

### 2.1 D-4.1-A 清算：自适应 Band 分割与等价子集合并

**S0 阶段工作**（`tools/font_preprocessor_slug.nelua`）：

1. **Band 数量自适应**：基于字形曲线密度动态确定 `BAND_COUNT`。
   - 稀疏字形（曲线数 < 20）：4 bands。
   - 中等字形（20–80）：8 bands。
   - 密集字形（> 80，CJK 常见）：16 或 32 bands。
2. **等价子集哈希合并**：
   - 生成细 band 后，为每个 band 计算其曲线索引集合的哈希签名。
   - 将签名相同的相邻 band 合并为一个，保留 band 边界坐标数组。
   - 发射 `NebulaSlugBandBoundary: [N]float32` 描述每个字形的非均匀 band 边界。
3. **Schema 扩展**：`liberation_sans_slug_metrics.nelua` 的 `NebulaSlugGlyph` 新增 `h_band_count`, `v_band_count` 字段，取代编译期常量 `NEBULA_SLUG_BAND_COUNT`。

**S1 阶段工作**（`shader_compose.lua`）：

着色器中通过二分查找定位像素落入的 band（不再是常数除法），利用 `storage` buffer 中的 boundary 数组。

### 2.2 D-4.1-B 清算：Jacobian 与 SlugDilate 上线

**S1 阶段工作**：

1. `text_runtime.nelua` 中 `NebulaSlugVertex` 扩展为 5 个 `vec4<f32>`（80 bytes/vertex），新增 `jac: (invScaleX, 0, 0, invScaleY)` 属性。
2. `shader_compose.lua` 的 vertex shader 从 MVP 矩阵中解算逆 Jacobian 并写入输出；fragment shader 引入 `SlugDilate` 辅助函数（参考 [EricLengyel/Slug](https://github.com/EricLengyel/Slug) 公共领域代码）。
3. `nebula_slug_text_build_vertices`（`text_runtime.nelua`）在 S2 顶点装配时填入 Jacobian（从 Visual 的仿射变换矩阵反解）。

### 2.3 D-4.1-C 评估：Storage Buffer 与纹理的 benchmark

**新增工具**（`tools/slug_bench.nelua`）：

1. 实现两套完全对等的 slug text pipeline：一套保留 Storage Buffer，一套改用 RGBA32Float/Uint 纹理。
2. 渲染合成场景（1000 个字形、5000 个字形、10000 个字形三档），采集帧时间 p50/p95/p99。
3. 基于测量结果，在 Phase 4.2.3 规划中决定是否强制迁移到纹理。

---

## 3. 任务分解与工作量预估

| 任务 | 影响文件 | 预期规模 |
| :--- | :--- | :--- |
| Band 数量自适应 + 等价子集合并 | `tools/font_preprocessor_slug.nelua`、`liberation_sans_slug_metrics.nelua` schema | ~350 行 |
| 着色器二分查找 + boundary 存储 | `shader_compose.lua` | ~80 行 |
| Jacobian 顶点属性 + SlugDilate 着色器 | `text_runtime.nelua`、`shader_compose.lua`、`pipeline_factory.lua` | ~200 行 |
| 旋转/缩放 demo + pixel diff 基线 | `examples/rotated_text_demo.nelua`、`tests/smoke_phase4_2_2.lua` | ~350 行（含测试） |
| Storage Buffer vs 纹理 benchmark | `tools/slug_bench.nelua` | ~150 行 |
| **合计** | | **~1130 行** |

---

## 4. 验收标准

1. **债务清算**：D-4.1-A 与 D-4.1-B 从 `ARCHITECTURE_GRAND_PLAN.md §5.2` 登记表中移除，并在 CHANGELOG 留下溯源条目。
2. **Latin 全量支持**：字形覆盖扩展至 Latin Extended-A（共 ~384 字形），所有字形在 pixel diff 下与 Slug 参考实现偏差 ≤ 1 LSB。
3. **任意仿射正确性**：`rotated_text_demo.nelua` 在 0°/15°/30°/45°/60°/75°/90° 七种旋转角度下均通过 pixel diff。
4. **性能保持**：`form_demo.nelua`（ASCII）在本阶段升级后的 FPS 不低于 Phase 4.1 基线的 95%。
5. **Benchmark 输出**：`slug_bench.nelua` 在三档规模下的测量报告提交至 `docs/REPORT_PHASE4_2_2_BENCH.md`，作为 Phase 4.2.3 的 D-4.1-C 决策依据。
6. **回归测试**：全量回归测试套件通过，新增 `smoke_phase4_2_2.lua` 的专项断言（预计 30+ 项，覆盖 band 合并逻辑、Jacobian 装配、pixel diff 边界）。
7. **新债务登记**：本阶段如引入新简化（例如 benchmark 结果选择保留 Storage Buffer），必须在登记表新增一行并明确触发条件。

---

## 5. 与其他 Phase 的依赖

| 依赖关系 | 对象 | 方向 |
| :--- | :--- | :--- |
| 并行可行 | Phase 4.2.1（PAL） | 代码冲突面为零，二者可并行推进 |
| 前置依赖 | Phase 4.2.3（HarfBuzz + CJK） | 4.2.3 的"CJK 7000 字性能可接受"验收要求本阶段完成 D-4.1-A 和 D-4.1-B 清算 |
| 不阻塞 | Phase 4.3（可编程原语注册表） | 4.3 属于交互层，与本阶段的渲染内核工作正交 |
