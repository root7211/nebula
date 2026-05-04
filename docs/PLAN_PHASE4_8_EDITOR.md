# Phase 4.8：文本编辑器产品化计划

**创建日期**：2026-05-04
**基准状态**：70/70 回归测试全绿 | Phase 4.7-S7 已完成 | text_editor_demo 可打开/编辑/保存文件

---

## 0. 背景

Phase 4.7 交付了文本编辑器原型（`text_editor_demo.nelua`），具备：
- CJK multiline editable（UTF-8 aware gap buffer）
- DenseText App 编排（Producer 模式）
- 行号显示（内置 Producer）
- 语法高亮（编译期规则注入 + 运行时 per-char 着色）
- Undo/Redo（Ctrl+Z / Ctrl+Y）
- File I/O（load_file / save_file）

Phase 4.8 的目标是将其从原型推进为**可日常使用的编辑器**，同时验证框架的自举能力（用自己的编辑器编辑 `.nelua` 源码）。

---

## 1. 总体架构约束

严格遵循 Nebula 三大公理：
- **公理 A（阶段封闭性）**：所有新功能通过编译期代码生成注入，不引入运行时动态分配
- **公理 B（生命周期三层）**：选区状态、搜索结果等为 L1 持久数据（应用生命周期），零堆分配
- **公理 C（形即渲染）**：选区背景色通过 DenseCharInstance 的 bg_color 字段直接映射到 GPU

---

## 2. 实施步骤

分为 6 个 Step，每个 Step 独立可交付、可测试。

### S1：选区可视化 + 系统剪贴板 — ✅ 已完成

**目标**：让用户能看到自己选中了什么，并与系统剪贴板互通。

**交付内容**：

| 任务 | 文件 | 描述 |
|:-----|:-----|:-----|
| 1.1 | `src/nebula_theme.nelua` | 新增 `nebula_theme_bg_selected()` → VSCode 风格蓝色 `rgba(38,79,120,255)` |
| 1.2 | `src/derive/interaction_factory.lua` | `multiline_editable` 新增 `sel_anchor_row/col` 上下文字段 |
| 1.3 | `src/derive/interaction_factory.lua` | Shift+Left/Right/Up/Down/Home/End 选区扩展（移动光标，保持锚点） |
| 1.4 | `src/derive/interaction_factory.lua` | 普通方向键/Home/End 移动后重置锚点到光标位置 |
| 1.5 | `src/derive/interaction_factory.lua` | Ctrl+A 全选（锚点→(0,0)，光标→末尾） |
| 1.6 | `src/derive/interaction_factory.lua` | Ctrl+C 复制选中文本到系统剪贴板（跨行序列化，`glfwSetClipboardString`） |
| 1.7 | `src/derive/interaction_factory.lua` | Ctrl+X 剪切（复制 + 删除选区，支持单行/跨行） |
| 1.8 | `src/derive/interaction_factory.lua` | Ctrl+V 粘贴（有选区先删除，插入剪贴板内容，处理换行符分行） |
| 1.9 | `src/derive/interaction_factory.lua` | 字符输入/Backspace/Delete/Enter 有选区时先删除选中内容 |
| 1.10 | `examples/text_editor_demo.nelua` | `fill_edit_area()` Producer 增加选区背景渲染（判断 byte 是否在选区范围内） |
| 1.11 | `examples/text_editor_demo.nelua` | 初始化 `sel_anchor_row/col = 0` |
| 1.12 | `src/wgpu_bindings.nelua` | 修复 `WGPUBindGroupLayoutEntry` 缺少 `bindingArraySize` 字段导致的结构体对齐错误 |
| 1.13 | `tests/smoke_phase4_4_s3.lua` | 更新字段数量断言（3 → 5） |
| 1.14 | `tests/smoke_phase4_8_s1.lua` | 新增 48 项冒烟测试 |

**框架改动**：
- `nebula_theme.nelua`：+1 函数（`nebula_theme_bg_selected`）
- `interaction_factory.lua`：`multiline_editable.context_fields` +2 字段，`process_body` 重写（+390 行）

**代码量**：+448 行新增，-33 行删除

**测试结果**：
- `smoke_phase4_8_s1.lua`：48/48 通过
- 回归测试：1789 通过，18 失败（失败均为历史遗留行数限制，与 S1 无关）
- 编译验证：text_editor_demo + 4 个其他 demo 全部编译通过

---

### S2：搜索与替换 — 🔜 下一步

**目标**：Ctrl+F 打开搜索栏，Ctrl+H 打开替换栏，高亮全部匹配。

**关键设计**：
- 搜索栏用 `editable` 原语（单行，256 字节容量）
- App 布局改为 column：`[搜索栏(flex_basis=30, 条件显示)] + [编辑区(flex_grow=1)]`
- 匹配结果用固定数组 `[512]MatchPos` 存储（公理 B：零堆分配）
- 不做正则——先做精确字符串匹配

**框架改动**：
- `app_factory.lua`：支持组件条件隐藏（`visible` 状态驱动 draw skip）
- `layout_engine.lua`：支持 `display = "none"` 时从布局中移除

**预估代码量**：~200 行新增，~40 行框架修改

---

### S3：状态栏 + 光标行高亮 — 🔜

**目标**：底部状态栏显示文件信息，光标所在行整行高亮。

**关键设计**：
- 光标行高亮：Producer 中检测 `current_line_idx`，该行所有字符 bg 设为 `nebula_theme_bg_cursor_line()`
- 状态栏：底部固定高度区域（`flex_basis=24`），用独立 DenseText 组件渲染
- 内容：`Ln {行}, Col {列} | {编码} | {行尾符} | {文件大小} | {修改标记}`

**框架改动**：无，纯 demo 层改动

**预估代码量**：~60 行新增

---

### S4：多语言语法高亮 — 🔜

**目标**：根据文件扩展名自动选择高亮规则，支持 5+ 语言。

**关键设计**：
- 新增语言规则：lua、c、python、json、markdown
- 文件打开时根据扩展名选择 scanner 函数指针
- 不做 multi-line 高亮（块注释 `/* */`），留给 Phase 5.0

**框架改动**：
- `highlight_factory.lua`：允许单次编译注册多组规则，生成多个 scanner 函数
- 新增 `nebula_highlight_select(ext)` 编译期辅助

**预估代码量**：~150 行规则定义，~40 行分发逻辑

---

### S5：自动缩进 + Tab 处理 — 🔜

**目标**：Enter 时保持缩进，Tab 插入空格，Shift+Tab 反缩进。

**关键设计**：
- Enter 时扫描当前行前导空格数，新行自动插入相同数量空格
- `{` / `:` 结尾时额外增加一级缩进（4 空格）
- Tab 键插入 4 空格（可配置 `TAB_WIDTH` 编译期常量）

**框架改动**：
- `interaction_factory.lua`：`multiline_editable` 增加 `NebulaKey.Tab`/`NebulaKey.ShiftTab` 处理
- `gap_buffer_factory.lua`：新增 `insert_spaces(n)` 批量方法

**预估代码量**：~100 行

---

### S6：集成验收 + 冒烟测试 — 🔜

**目标**：将 S1-S5 整合为 `text_editor_v2_demo.nelua`，全量测试。

**交付标准**：
- 全部冒烟测试通过
- 70 + N 项回归测试全绿
- `text_editor_v2_demo` 可打开自身源码编辑并保存

---

## 3. 总览

| Step | 内容 | 框架改动 | 新增代码 | 依赖 | 状态 |
|:-----|:-----|:---------|:---------|:-----|:-----|
| S1 | 选区可视化 + 系统剪贴板 | 小（主题 + 原语导出） | ~448 行 | 无 | ✅ 已完成 |
| S2 | 搜索与替换 | 中（条件显示 + 布局） | ~240 行 | S1 | 🔜 |
| S3 | 状态栏 + 光标行高亮 | 无 | ~60 行 | 无 | 🔜 |
| S4 | 多语言语法高亮 | 小（多规则注册） | ~190 行 | 无 | 🔜 |
| S5 | 自动缩进 + Tab | 小（原语 + 缓冲区） | ~100 行 | 无 | 🔜 |
| S6 | 集成验收 | 无 | ~80 行 | S1-S5 | 🔜 |

S1/S3/S4/S5 互相独立，可并行开发。S2 依赖 S1（搜索高亮需要选区渲染基础设施）。S6 是最终整合。

---

## 4. 明确排除（留给 Phase 5.0+）

- 多文件标签页（需要运行时组件创建，违反当前静态编译模型）
- 正则搜索（复杂度不匹配当前优先级）
- 多行注释高亮（需要跨行状态机，架构改动大）
- LSP / 代码补全（需要异步 I/O，超出当前框架能力）
- 代码折叠（需要语法树，不是词法层能做的）
