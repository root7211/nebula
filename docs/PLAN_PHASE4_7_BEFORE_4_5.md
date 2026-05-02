# Phase 4.7→4.5 调序实施方案：先积累样本，再提炼语法糖

**创建日期**：2026-05-02
**基准状态**：49/49 回归测试全绿 | Phase 4.X-T 已完成 | Era II 第二梯队收官

---

## 0. 调序动机

### 问题：Phase 4.5 语法糖的样本覆盖度不足

Phase 4.5（注册原语语法糖）计划糖化四个主要 API 表面：

| 糖化目标 | 现有样本数 | 覆盖度 |
|:---------|:----------|:-------|
| `nebula_annotate` + `nebula_derive` 合并 | 10/10 demos | 充分 |
| `nebula_app_begin/end` 简化 | 8/10 demos | 充分 |
| editable 字段自动初始化 | 3/10 demos | 充分（模式一致） |
| **布局声明内联化** | **1/10 demos（仅 form_demo）** | **严重不足** |
| **Slot/Producer 泛化** | **1/10 demos（仅 dynamic_list_demo）** | **严重不足** |
| **自定义原语组合** | **1/10 demos（仅 slider_demo）** | **严重不足** |

布局系统仅 1 个 demo 使用，而 Phase 4.7（文本编辑器原型）恰恰需要**多列布局 + DenseText 混合管线**——这正是当前样本缺失的维度。

### 结论：先做 4.7 前置步骤积累样本，再提炼 4.5 语法糖

过早固化 API 的代价远大于延迟发布。调整后的顺序：

```
原计划: 4.X ✅ → 4.5 (语法糖) → 4.7 (文本编辑器)
调整后: 4.X ✅ → 4.7-S1~S4 (编辑器前置) → 4.5 (语法糖) → 4.7-S5~S7 (编辑器收尾)
```

4.7 前半程产出的 3-4 个新 demo 模式将为 4.5 语法糖设计提供关键输入：

- 多列布局（行号列 + 编辑区并排）→ 布局糖的真实需求
- DenseText 接入 App 编排 → 混合管线糖的真实需求
- 文件 I/O + Undo/Redo → L1 状态管理糖的真实需求

---

## 1. Phase 4.7-S1：CJK + ASCII 混排 multiline_editable 升级

**目标**：让现有 `multiline_editable` 原语支持 CJK 宽字符混排。

**前置依赖**：Phase 4.2.3-S2 ✅（CJK 运行时排版已完成）

### 任务清单

| # | 文件 | 描述 |
|:--|:-----|:-----|
| 1.1 | `src/derive/interaction_factory.lua` | `multiline_editable` 的 `process_body` 中接入 `nebula_cjk_glyph_lookup`，光标移动按实际 advance 宽度而非固定 col |
| 1.2 | `src/derive/gap_buffer_factory.lua` | `NebulaMultiBuf` 的 `insert_char` 方法扩展为接受 UTF-8 多字节序列（1-4 bytes） |
| 1.3 | `src/text_runtime.nelua` | `nebula_cjk_text_compute_advances` 适配 multiline 场景（逐行排版） |
| 1.4 | `examples/cjk_editor_demo.nelua` | 中英文混排多行编辑器演示 |
| 1.5 | `tests/smoke_phase4_7_s1.lua` | S1 阶段验证：CJK 宽字符光标定位、UTF-8 插入/删除、混排行宽计算 |

### 验收标准

- cjk_editor_demo 能输入/删除中英文混排文本
- 光标在 CJK 字符上移动时跳 2 col 宽度
- 回归测试全绿

### 样本贡献

- **新模式**：CJK 宽字符 + editable 原语组合（现有 multiline_editable_demo 仅 ASCII）
- **对 4.5 的输入**：暴露 `nebula_annotate` 中是否需要声明 `text_encoding="utf8"` 等元数据

---

## 2. Phase 4.7-S2：DenseText 路径接入 multiline_editable

**目标**：将 Phase 4.X 的高密度文本渲染通道接入 App 编排层，替代现有 Slug per-glyph 路径用于代码/编辑器场景。

**前置依赖**：Phase 4.X Step 1-5 ✅（DenseText 管线已完成）

### 任务清单

| # | 文件 | 描述 |
|:--|:-----|:-----|
| 2.1 | `src/derive/app_factory.lua` | `nebula_app_register_component` 识别 `text_mode="dense"` 并生成 DenseText 管线初始化代码（与 standard_instanced 管线并存） |
| 2.2 | `src/derive/pipeline_factory.lua` | `gen_pipeline_dense_text` 的 init/deinit 接入 App 生命周期管理（L0 层） |
| 2.3 | `src/derive/interaction_factory.lua` | `multiline_editable` 的渲染输出从 Slug vertex buffer 切换到 DenseCharInstance Storage Buffer |
| 2.4 | `examples/dense_editor_demo.nelua` | 使用 DenseText 管线的多行编辑器（120 col × 50 row，per-char 颜色） |
| 2.5 | `tests/smoke_phase4_7_s2.lua` | S2 阶段验证：DenseText 管线 App 生命周期、编辑交互、per-char 颜色正确性 |

### 验收标准

- dense_editor_demo 通过 `nebula_app_begin/end` 编排（非手动渲染循环）
- DenseText 管线的 init/deinit 由 App 自动管理
- 编辑交互（键盘输入、光标移动、选区）在 DenseText 路径下正常工作
- 回归测试全绿

### 样本贡献

- **新模式**：DenseText 管线 + App 编排 + 交互原语三者首次整合
- **对 4.5 的输入**：暴露 `nebula_app_register_component` 对混合管线的真实 API 需求——当前 dense_text_demo 和 term_demo 都绕过了 App 层，说明 App 编排对 DenseText 的支持尚未设计

---

## 3. Phase 4.7-S3：行号显示（独立 DenseText 列）

**目标**：实现编辑器行号栏，作为多列布局的首个真实用例。

**前置依赖**：4.7-S2

### 任务清单

| # | 文件 | 描述 |
|:--|:-----|:-----|
| 3.1 | `src/derive/layout_engine.lua` | 扩展 Flexbox 支持 `flex_basis` 固定宽度列（行号栏宽度 = char_width × max_digits） |
| 3.2 | `src/derive/app_factory.lua` | 支持同一 App 内注册多个 DenseText 组件（行号 + 编辑区），各自独立管线实例 |
| 3.3 | `examples/editor_with_lines_demo.nelua` | 带行号的编辑器：左侧行号栏（只读 DenseText）+ 右侧编辑区（可交互 DenseText） |
| 3.4 | `tests/smoke_phase4_7_s3.lua` | S3 阶段验证：行号同步滚动、多 DenseText 组件并存、布局正确性 |

### 验收标准

- 行号栏与编辑区并排渲染，行号随滚动同步
- 布局引擎正确分配固定宽度列 + flex_grow 弹性列
- 两个 DenseText 管线实例共存无 GPU 资源冲突
- 回归测试全绿

### 样本贡献

- **新模式**：多列布局 + 多 DenseText 实例 + 滚动同步
- **对 4.5 的输入**：这是布局系统的第 2 个真实用例（form_demo 之后），将暴露 `nebula_app_set_root_layout` inline 声明的真实痛点

---

## 4. Phase 4.7-S4：语法高亮架构

**目标**：基于 DenseText per-char fg_color 实现关键字着色，验证"编译期规则 + 运行时应用"的着色模型。

**前置依赖**：4.7-S2

### 任务清单

| # | 文件 | 描述 |
|:--|:-----|:-----|
| 4.1 | `src/derive/` 新文件或 `interaction_factory.lua` | `nebula_highlight_rules` 编译期宏：接受关键字列表 + 颜色映射，生成 S2 运行时的逐行扫描函数 |
| 4.2 | `src/text_runtime.nelua` | `nebula_dense_apply_highlight()` — 将高亮结果写入 DenseCharInstance 的 fg_color 字段 |
| 4.3 | `examples/highlight_editor_demo.nelua` | 带语法高亮的编辑器（Nelua/Lua 关键字着色） |
| 4.4 | `tests/smoke_phase4_7_s4.lua` | S4 验证：关键字匹配、颜色正确性、编辑后实时重着色 |

### 验收标准

- 关键字（if/else/for/function/local/return 等）实时着色
- 编辑文本后高亮立即更新（帧级刷新）
- 高亮规则在 S1 编译期定义，运行时仅做线性扫描
- 回归测试全绿

### 样本贡献

- **新模式**：编译期规则注入 + 运行时 per-char 属性修改
- **对 4.5 的输入**：暴露 `nebula_annotate` 是否需要 `highlight_rules` 声明字段，以及高亮规则与原语注册的交互方式

---

## 5. Phase 4.5：语法糖（基于充分样本的设计）

**前置依赖**：4.7-S1~S4 完成，样本量从 10 增加到 14+

此时的样本覆盖：

| 维度 | 调序前 | 调序后 |
|:-----|:-------|:-------|
| 布局系统 | 1 demo（form） | 3 demos（form + editor_with_lines + highlight_editor） |
| DenseText + App 编排 | 0 demos | 3 demos（dense_editor + editor_with_lines + highlight_editor） |
| CJK + editable | 0 demos | 1 demo（cjk_editor） |
| 混合管线（Slug + DenseText 并存） | 0 demos | 可能出现于 editor_with_lines |
| 编译期规则注入 | 1 demo（slider） | 2 demos（slider + highlight_editor） |

### S1：原语声明糖化

| 任务 | 描述 | 样本依据 |
|:-----|:-----|:---------|
| 隐含依赖展开 | `primitives = {"editable"}` 自动展开为 `focusable + clickable + hoverable + editable` | multiline_editable_demo + cjk_editor_demo |
| `text_mode` 自动推导 | 组件含 `multiline_editable` 且 char 数 > 阈值时自动选择 `dense` 模式 | dense_editor_demo vs multiline_editable_demo |
| 类型注入自动化 | `nebula_gen_gap_buffer_type` / `nebula_gen_multiline_buffer_type` 从 annotate 元数据自动生成 | login_demo + form_demo + cjk_editor_demo |

### S2：App 编排糖化

| 任务 | 描述 | 样本依据 |
|:-----|:-----|:---------|
| inline layout | `nebula_app_register_component` 内联 layout 声明（消除 `nebula_app_set_root_layout` 分离调用） | form_demo + editor_with_lines_demo |
| 混合管线自动编排 | App 自动检测组件的 `text_mode` 并生成对应管线初始化 | dense_editor_demo（当前需手动指定） |
| `nebula_init` / `nebula_should_close` 统一 | 已在 form_demo 实现，推广到所有新 demo | 全部 14+ demos |

### S3：L1 状态管理基础

| 任务 | 描述 | 样本依据 |
|:-----|:-----|:---------|
| L1 数据协议 | 明确跨帧持久状态：光标位置、滚动偏移、编辑历史、高亮缓存 | multiline_editable_demo + highlight_editor_demo |
| `NebulaStateStore` | 编译期生成 per-component L1 state record | 4.7-S1~S4 全部编辑器 demo |
| Undo/Redo 栈 | 基于 Gap Buffer 的 edit history ring buffer | 4.7-S5 将消费此能力 |

### S4：全量 demo 糖化重写 + 回归验证

| 任务 | 描述 |
|:-----|:-----|
| 重写全部 14+ demos | 用新语法糖重写，验证 API 通用性 |
| 代码行数对比报告 | 量化糖化前后各 demo 的代码行数变化 |
| 回归测试 | 全部测试绿 + 6+ demos 编译运行验证 |

### 验收标准

- 全部 demo 可用语法糖重写，无特例需要 escape hatch
- 50 行愿景代码能够编译运行（即使功能尚不完整）
- 回归测试全绿

---

## 6. Phase 4.7-S5~S7：文本编辑器收尾

语法糖就绪后，回到文本编辑器原型的最后三步：

| Step | 任务 | 依赖 |
|:-----|:-----|:-----|
| S5 | Ctrl+Z/Y Undo/Redo | 4.5-S3（L1 State + Undo 栈） |
| S6 | 文件读写（`io.open` → Gap Buffer 加载/保存） | — |
| S7 | `examples/text_editor_demo.nelua` — 完整文本编辑器 | S1~S6 全部 |

### S7 验收标准

- 能打开 .txt / .nelua 文件，编辑、保存
- 支持中英文输入
- 行号显示 + 语法高亮（Nelua 关键字）
- Ctrl+Z/Y Undo/Redo
- 代码量 ≤ 80 行（受益于 4.5 语法糖）

---

## 7. 调序后的完整时间线

```
现在（2026-05-02）
 │
 ├─ 4.7-S1: CJK multiline 升级          → 新增 cjk_editor_demo
 │
 ├─ 4.7-S2: DenseText 接入 App 编排      → 新增 dense_editor_demo
 │
 ├─ 4.7-S3: 行号列 + 多列布局            → 新增 editor_with_lines_demo
 │
 ├─ 4.7-S4: 语法高亮架构                 → 新增 highlight_editor_demo
 │
 ├─ 4.5:    语法糖（基于 14+ 样本设计）   → 全量 demo 重写
 │
 ├─ 4.7-S5: Undo/Redo
 │
 ├─ 4.7-S6: 文件 I/O
 │
 └─ 4.7-S7: text_editor_demo             → Era II 收官里程碑
       │
       v
    Era III (5.0 生态/CI/CD)
```

---

## 8. 风险与缓解

| 风险 | 影响 | 缓解 |
|:-----|:-----|:-----|
| 4.7-S2 DenseText 接入 App 编排改动面大 | 可能破坏现有 dense_text_demo 和 term_demo | 保留手动渲染路径不变，App 编排作为可选上层抽象 |
| 多 DenseText 实例 GPU 资源竞争 | bind group / buffer 冲突 | 4.2.2-fix 已建立 deinit 范式，每实例独立资源 |
| 4.7-S4 语法高亮在 S1 编译期生成规则，运行时扫描可能成瓶颈 | 大文件（>1000 行）帧时间超标 | 仅对可见行做扫描（viewport 裁剪），高亮结果缓存到 L1 |
| 4.5 语法糖设计后仍有漏网模式 | 某些 demo 无法用糖重写 | S4 全量重写阶段作为兜底验证，允许保留 escape hatch |

---

## 9. 不做列表（本轮明确排除）

| 项目 | 理由 |
|:-----|:-----|
| Phase 4.6 Indirect Drawing | 过早优化，instanced draw 性能足够 |
| IME 预编辑 | OS 级集成复杂度高，留给 5.0 |
| Tree-sitter 集成 | 语法高亮先用简单关键字匹配验证架构，增量解析留给 5.0 |
| Rope/Piece Table | Gap Buffer 对目标规模足够 |
| 动画系统 | 非核心路径 |

---

## 10. 关键决策记录

| 决策 | 结论 | 依据 |
|:-----|:-----|:-----|
| Phase 4.5 与 4.7 的执行顺序 | 4.7 前半程先行 | 语法糖样本覆盖度不足（布局 1/10，DenseText+App 0/10） |
| 4.7 拆分点 | S4（语法高亮）之后切入 4.5 | S4 完成后新增 4 个 demo，覆盖布局/混合管线/CJK 编辑/规则注入全部维度 |
| 语法高亮实现层 | 编译期规则 + 运行时线性扫描 | 公理 A 合规（规则属于 S1，扫描属于 S2），避免引入 Tree-sitter 运行时依赖 |
| DenseText App 编排策略 | 可选上层抽象，不替代手动路径 | term_demo 等特殊应用需要完全控制渲染循环 |
