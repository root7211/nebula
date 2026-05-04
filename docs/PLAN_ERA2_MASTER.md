# Nebula Era II 后半段实施总计划

**创建日期**：2026-05-01
**最后更新**：2026-05-04
**基准状态**：70/70 回归测试全绿 | D-4.1-C PASSED | Phase 4.8-S1 已完成

---

## 0. 当前已完成清单

| Phase | 状态 | 核心产出 |
|:------|:-----|:---------|
| 4.2.2-fix | ✅ | GPU deinit 40+ 泄漏修复 |
| 4.2.2 D-4.1-C | ✅ PASSED | Storage Buffer 1K→10K 退化仅 +2.5%，路径确认可行 |
| 4.2.3-S0 | ✅ | HarfBuzz 绑定 + CJK 20 字 shaping 表生成 |
| 4.2.3-S1 | ✅ | GB2312 一级 3755 字 shaping 表（102.7 KB，commit `c1cd8ee`） |
| 4.2.3-S2 | ✅ | CJK 运行时排版——零 HarfBuzz 依赖，O(log N) 表查找（commit `a6336e5`） |
| 4.3 S1-S4 | ✅ | 可编程原语注册表 + axiom_validator v2.0 |
| 4.4 S1-S3 | ✅ | scrollable / dropdown / multiline_editable |
| 4.X input | ✅ | 剪贴板 + Unicode 字符输入 |
| 全代码库审计 | ✅ | 10 项修复（2 高危 + 4 中危 + 2 低危 BUG + 2 内存安全，commit `8647048`） |
| 交互原语行为验证 | ✅ | 40 条运行时行为断言 + BUG-4/5/6 回归守护（commit `c424005`） |
| 4.5 S1-S3 | ✅ | 语法糖优化（inject_buffers / editor_visual / builtin_line_nums） |
| 4.7 S1-S7 | ✅ | 文本编辑器原型（语法高亮 / 行号 / Undo/Redo / File I/O） |
| 4.8-S1 | ✅ | 选区可视化 + 系统剪贴板（Shift+Arrow / Ctrl+C/V/X/A） |
| wgpu 绑定修复 | ✅ | `WGPUBindGroupLayoutEntry.bindingArraySize` 字段对齐修复 |

---

## 1. 优先级排序原则

基于三大公理 + D-4.1-C 结果，后续工作按以下原则排序：

1. **阶段闭合优先**：已启动的 Phase 优先收尾（4.2.3 S1→S2）
2. **用户可见价值优先**：能产生可运行 demo 的工作优先
3. **技术风险已消除**：D-4.1-C DISMISSED，Storage Buffer 路径无风险
4. **依赖链驱动**：文本编辑器愿景 → 需要 CJK + 高密度文本 → 需要 4.2.3 + 4.X

---

## 2. 实施路线图（四个梯队）

### 第一梯队：CJK 渲染闭环（Phase 4.2.3 S1-S2）— ✅ 已完成

**目标**：~~完成 4.2.3 剩余阶段，实现 CJK 文本零运行时排版。~~ ✅ 已实现。

#### Step 1: S1 — 编译期常量注入

| 任务 | 文件 | 描述 |
|:-----|:-----|:-----|
| 1.1 | `tools/font_preprocessor_cjk.nelua` | 扩展字符集到 GB2312 一级 3755 字 |
| 1.2 | `tools/font_preprocessor_cjk.nelua` | 对每个 CJK 字形调用 Slug band 分割逻辑（复用 4.2.2） |
| 1.3 | `assets/generated/cjk_shaping_tables.nelua` | 重新生成完整 shaping 表 |
| 1.4 | `assets/generated/cjk_slug_metrics.nelua` | 生成 CJK 字形的 Slug 曲线数据（band + curves） |
| 1.5 | `src/text_runtime.nelua` | `require "cjk_shaping_tables"` + `require "cjk_slug_metrics"` |
| 1.6 | `tests/smoke_phase4_2_3_s1.lua` | S1 阶段验证测试 |

**验收**：CJK shaping 表 + Slug 曲线数据编译期可用，回归全绿。

#### Step 2: S2 — 零开销运行时排版

| 任务 | 文件 | 描述 |
|:-----|:-----|:-----|
| 2.1 | `src/text_runtime.nelua` | 新增 `nebula_cjk_text_compute_advances()` — 纯查表 O(1) |
| 2.2 | `src/text_runtime.nelua` | 新增 `nebula_cjk_slug_text_build_vertices()` — CJK Slug 顶点生成 |
| 2.3 | `src/text_runtime.nelua` | 新增 `nebula_cjk_glyph_lookup(codepoint)` — 码点→索引查找 |
| 2.4 | `examples/cjk_text_demo.nelua` | CJK 文本渲染演示（"你好世界" Slug 渲染） |
| 2.5 | `tests/smoke_phase4_2_3_s2.lua` | S2 阶段验证测试 |

**验收**：CJK 文本通过 Slug 管线正确渲染，S2 无 HarfBuzz 调用（axiom_validator 通过）。

#### Step 3: 集成验证

| 任务 | 描述 |
|:-----|:-----|
| 3.1 | CJK + ASCII 混排测试（中英文交替） |
| 3.2 | 性能基线：500 字 CJK 密集排版帧时间 ≤ ASCII 的 2.5 倍 |
| 3.3 | 内存审计：shaping 表 + Slug 曲线 ≤ 4 MB |
| 3.4 | 更新 `docs/PLAN_PHASE4_2_3_CJK.md` 标记完成 |

---

### 第二梯队：高密度文本渲染通道（Phase 4.X）— 🔜 下一步

**目标**：实现 8192 字符 per-char 颜色的等宽文本网格（终端/代码编辑器基础）。

**前置**：D-4.1-C PASSED ✅ → 直接走方案 B（Instanced）

**新增 scope**：UAX#14 换行算法从 Phase 4.2.3 移入（换行是布局问题，与 dense grid 天然耦合）

| Step | 任务 | 文件 |
|:-----|:-----|:-----|
| 1 | 着色器生成 | `src/derive/shader_compose.lua` — `nebula_compose_dense_text_shader()` |
| 2 | 管线生成 | `src/derive/pipeline_factory.lua` — `gen_pipeline_dense_text()` |
| 3 | Record 定义 | `src/renderer.nelua` — `DenseCharInstance` (32B) + `DenseTextUniforms` (16B) |
| 4 | 派生入口 | `src/nebula_core.nelua` — `nebula_derive_dense_text_visual()` |
| 5 | 辅助运行时 | `src/text_runtime.nelua` — `nebula_dense_grid_fill_instance()` |
| 6 | 演示 | `examples/dense_text_demo.nelua` — 120×50 网格 6000 字符 |
| 7 | 测试 | `tests/smoke_phase4_x_dense.lua` |
| 8 | deinit | 为 DenseTextPipeline 添加 `:deinit()` 方法 |

**验收**：
- 6000 字符网格正确渲染，per-char fg/bg 颜色
- axiom_validator 通过
- 性能基线记录

---

### 第三梯队：语法糖 + 动画 + 主题（Phase 4.5 / 4.7-prereq）

**目标**：提升 DX（开发体验），为文本编辑器原型扫清障碍。

#### Phase 4.5 — 注册原语语法糖

| 任务 | 描述 |
|:-----|:-----|
| 简化 `nebula_annotate` | 允许 `primitives = {"editable"}` 隐含 `focusable + clickable + hoverable` |
| 简化 `nebula_app_begin` | 支持 inline layout 声明 |
| `nebula_init` 统一入口 | 合并 renderer.init + app.init 为单调用 |
| `nebula_should_close` | 封装 glfwWindowShouldClose |

#### L1 状态管理基础

| 任务 | 描述 |
|:-----|:-----|
| 定义 L1 数据协议 | 明确哪些状态跨帧持久（光标位置、滚动偏移、编辑历史） |
| `NebulaStateStore` | 编译期生成的 per-component L1 state record |
| Undo/Redo 栈 | 基于 Gap Buffer 的 edit history ring buffer |

---

### 第四梯队：收敛到文本编辑器原型（Phase 4.7）

**目标**：50 行愿景的中间里程碑——一个能用的纯文本编辑器。

| Step | 任务 | 依赖 |
|:-----|:-----|:-----|
| 1 | CJK + ASCII 混排 multiline_editable 升级 | 4.2.3 S2 |
| 2 | DenseText 路径接入 multiline_editable | 4.X |
| 3 | 行号显示（独立 DenseText 列） | 4.X |
| 4 | 语法高亮架构（per-char fg_color 驱动） | 4.X |
| 5 | 基础 Ctrl+Z/Y Undo/Redo | L1 State |
| 6 | 文件读写（`io.open` → Gap Buffer 加载） | — |
| 7 | `examples/text_editor_demo.nelua` | 全部 |

**验收**：能打开一个 .txt 文件，编辑、保存、支持中英文输入。

---

## 3. 不做列表（明确排除）

| 项目 | 理由 |
|:-----|:-----|
| Phase 4.6 Indirect Drawing | 过早优化，当前 instanced draw 性能足够 |
| 三端一致性验证 | Phase 4.2.1 PAL 骨架完成但 Windows/Web 端未搭建测试环境 |
| Latin 连字（Tier 2） | 装饰性功能（fi/fl/ffi），CJK 无需求，留给 Phase 5+ |
| IME 预编辑 | 需要 OS 级集成，复杂度高，留给 5.0 |
| Rope/Piece Table | Gap Buffer 对小型编辑器足够，超大文件支持留给 5.0 |
| 动画系统 | 非核心路径，待文本编辑器原型后再考虑 |

---

## 4. 关键决策记录

| 决策 | 结论 | 依据 |
|:-----|:-----|:-----|
| CJK 渲染路径 | Storage Buffer（Slug） | D-4.1-C: +2.5% 退化，远低于阈值 |
| 高密度文本方案 | 方案 B（Instanced 32B/instance） | 与 standard_instanced 架构一致，内存效率 4.4× |
| HarfBuzz 引入层 | 仅 S0 预处理 | 公理 A 合规，零运行时依赖 |
| CJK 字符集 | GB2312 一级 3755 字 | 覆盖 99.7% 日常使用，表大小可控 |
| 文本编辑器缓冲区 | Gap Buffer（已有 Phase 3.6） | 单行已实现，多行通过 NebulaMultiBuf 已实现 |

---

## 5. 风险与缓解

| 风险 | 影响 | 缓解 |
|:-----|:-----|:-----|
| CJK 3755 字 Slug 曲线数据量过大 | 编译产物膨胀 | 设 4MB 上限，超出则按曲线密度分层（高频字详细 band，低频字粗 band） |
| DenseText + Slug 双管线并存复杂度 | 维护成本 | 共享 bind group layout 模式，抽象公共 draw 逻辑 |
| multiline_editable 升级到 CJK 时变宽处理 | CJK 宽字符占 2 col | shaping 表已含 advance，排版函数直接查表 |

---

## 6. 里程碑时间线（相对顺序）

```
现在（2026-05-04）
 │
 ├─ 第一梯队: 4.2.3 S0+S1+S2 ✅ 已完成
 │
 ├─ 第二梯队: 4.X (高密度文本 Instanced 通道) ✅ 已完成
 │
 ├─ 第三梯队: 4.5 (语法糖) ✅ 已完成
 │
 ├─ 第四梯队: 4.7 (文本编辑器原型) ✅ 已完成
 │
 ├─ 第五梯队: 4.8 (文本编辑器产品化) ← 当前
 │    ├─ S1: 选区可视化 + 系统剪贴板 ✅
 │    ├─ S2: 搜索与替换 🔜
 │    ├─ S3: 状态栏 + 光标行高亮 🔜
 │    ├─ S4: 多语言语法高亮 🔜
 │    ├─ S5: 自动缩进 + Tab 🔜
 │    └─ S6: 集成验收 🔜
 │
 └─ Era II 收官 → Phase 5.0 (工程化 / CI/CD / 生态)
```

---

## 7. 立即可执行的下一步

**Phase 4.8 S2**：搜索与替换功能。

具体操作：
1. 在 `interaction_factory.lua` 中处理 Ctrl+F / Ctrl+H 触发搜索/替换模式
2. 新增 `SearchBarVisual`（`editable` 原语，单行，256 字节容量）
3. App 布局改为 column：`[搜索栏(flex_basis=30, 条件显示)] + [编辑区(flex_grow=1)]`
4. 搜索逻辑：逐行 `strstr` 匹配，结果存入静态数组 `match_positions[512]`
5. Producer 渲染时检查当前字符是否在匹配范围内，设置高亮背景色
6. 详见 `PLAN_PHASE4_8_EDITOR.md` S2 章节
