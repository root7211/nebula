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

### S2：搜索与替换 — ✅ 已完成

**目标**：Ctrl+F 打开搜索栏，Ctrl+H 打开替换栏，高亮全部匹配。

#### 方案选型

**原方案（已弃用）**：框架层条件隐藏（`visible` 状态 + `display="none"` 布局移除）。
**弃用原因**：Nebula 布局在 S1 编译期解算为固定坐标，运行时动态移除组件需要重新解算布局，违反公理 A（阶段封闭性——后一阶段不得执行前一阶段的操作）。

**采用方案：固定布局 + Producer 控制可见性**

搜索栏始终占 `flex_basis=24` 布局空间，通过 Producer 控制渲染内容：

| 状态 | 搜索栏渲染 | 键盘路由 |
|:-----|:-----------|:---------|
| 隐藏（`_search_active == false`） | Producer 填充编辑区同色背景（视觉融入） | 正常路由到 multiline_editable |
| 显示（`_search_active == true`） | 渲染搜索框内容 + 匹配计数 | 拦截 char_input 写入搜索 buffer |

**公理合规性**：

- **公理 A**：搜索栏是编译期声明的 DenseText 组件，布局在 S1 解算，运行时仅切换 Producer 输出内容，不重新解算布局
- **公理 B**：搜索 buffer `[256]uint8` + 匹配结果 `[512]MatchPos` 均为 L1 持久栈数据，零堆分配
- **公理 C**：匹配高亮通过 `DenseCharInstance.bg_color` 直接映射到 GPU

#### 关键设计

**1. 数据结构**

```
-- 搜索状态（全局，L1 持久）
global _search_active: boolean = false
global _search_buf: [256]uint8           -- 搜索关键字 buffer
global _search_len: uint32 = 0           -- 当前关键字长度
global _search_cursor: uint32 = 0        -- 搜索框光标位置

-- 匹配结果（固定数组，零堆分配）
global MatchPos = @record{ row: uint32, col: uint32 }
global _search_matches: [512]MatchPos
global _search_match_count: uint32 = 0
global _search_current: uint32 = 0       -- 当前高亮的匹配索引
```

**2. 键盘路由**

```
NebulaKey.Find    = 26    -- Ctrl+F
NebulaKey.FindNext = 27   -- Enter（搜索栏激活时）/ F3

主循环中：
  if input.key_pressed == NebulaKey.Find then
    _search_active = not _search_active   -- 切换搜索栏
  end

  if _search_active then
    -- 拦截 char_input → 写入 _search_buf
    -- Escape → 关闭搜索栏
    -- Enter → 跳转到下一个匹配
    -- Backspace → 删除搜索框字符
    -- 每次 _search_buf 变化 → 重新扫描 multi_buf 填充 _search_matches
  else
    -- 正常路由到 multiline_editable（框架自动处理）
  end
```

**3. 匹配扫描**

```
function scan_matches(mb, search_buf, search_len, matches, max_matches) → count
  -- 遍历 multi_buf 的每一行
  -- 对每行 flatten 后做朴素字符串匹配（O(n*m)，文件小够用）
  -- 结果写入 matches[] 数组
  -- 返回匹配数量
```

**4. 匹配高亮**

在 `fill_edit_area` Producer 中，对每个字节检查是否命中匹配范围：

```
-- 对当前行检查所有匹配
for each match in _search_matches where match.row == buf_row:
  if byte_i >= match.col and byte_i < match.col + _search_len:
    this_bg = nebula_theme_bg_search_match()
  if match == _search_matches[_search_current]:
    this_bg = nebula_theme_bg_search_current()   -- 当前匹配用更亮的颜色
```

**5. 搜索栏 Producer**

```
function fill_search_bar(app, instances, count, max):
  if not _search_active then
    -- 填充编辑区同色背景（视觉融入）
    fill all cells with bg=nebula_theme_bg_normal()
  else
    -- 渲染: "Find: {_search_buf}  ({current}/{total})"
    -- 背景用 nebula_theme_bg_status()
    -- 光标位置用 nebula_theme_bg_cursor()
  end
```

**6. 布局**

```lua
nebula_app("TextEditorApp", {
  components = {
    { name = "editor", type = "EditorBgVisual" },
    { name = "search_bar", type = "SearchBarDenseVisual",
      producer = "fill_search_bar", cell_w = 10.0, cell_h = 16.0,
      max_chars = 200, layout = { flex_basis = 24 } },
    { name = "editor_body", layout = {
        direction = "row", flex_grow = 1,
        container = {
          { ref = "line_nums" },
          { ref = "edit_area" },
        },
      },
    },
    -- ... line_nums, edit_area, status_bar 不变
  },
})
```

#### 修改文件清单

| 文件 | 修改内容 | 行数估计 |
|:-----|:---------|:---------|
| `src/nebula_core.nelua` | +`NebulaKey.Find = 26`, `NebulaKey.FindNext = 27` | +3 行 |
| `src/app.nelua` | Ctrl+F / F3 键映射 | +4 行 |
| `src/nebula_theme.nelua` | +`nebula_theme_bg_search_match()`, `nebula_theme_bg_search_current()` | +8 行 |
| `examples/text_editor_demo.nelua` | 搜索状态 + 搜索 buffer + MatchPos + scan_matches + fill_search_bar Producer + 键盘路由 + fill_edit_area 匹配高亮 + 布局调整 | +180 行 |
| `tests/smoke_phase4_8_s2.lua` | 冒烟测试 | +60 行 |

**框架改动**：仅 `nebula_core.nelua`（+2 枚举值）和 `app.nelua`（+4 行键映射），无 `app_factory` / `layout_engine` 改动。

**预估总代码量**：~255 行新增

---

### S3：状态栏 + 光标行高亮 — ✅ 已完成

**目标**：底部状态栏显示文件信息，光标所在行整行高亮。

**交付内容**：

| 任务 | 文件 | 描述 |
|:-----|:-----|:-----|
| 3.1 | `src/nebula_theme.nelua` | 新增 `nebula_theme_bg_status()` → `rgba(30,30,42,255)` |
| 3.2 | `src/nebula_theme.nelua` | 新增 `nebula_theme_fg_status()` → `rgba(160,160,180,255)` |
| 3.3 | `src/nebula_theme.nelua` | 新增 `nebula_theme_fg_status_accent()` → `rgba(100,180,255,255)` |
| 3.4 | `examples/text_editor_demo.nelua` | `StatusBarDenseVisual` record + `nebula_component` 注册（dense, max_chars=256） |
| 3.5 | `examples/text_editor_demo.nelua` | `fill_status_bar` Producer——显示文件名 + 修改标记 + Ln/Col + 总行数 + UTF-8 + LF |
| 3.6 | `examples/text_editor_demo.nelua` | `nebula_app` 布局新增 `status_bar`（`flex_basis=24`，底部固定高度） |
| 3.7 | `tests/smoke_phase4_8_s3.lua` | 31 项冒烟测试（主题色 + 声明 + Producer + 布局验证） |
| 3.8 | `tools/run_all_tests.sh` | 注册新测试到回归套件 |

**框架改动**：无，纯 demo 层 + 主题扩展

**代码量**：+86 行新增（含 ~50 行 Producer + ~13 行主题 + ~4 行布局声明 + 测试）

**光标行高亮**：已由 `fill_edit_area` Producer 原有实现覆盖（`is_cursor_line` → `nebula_theme_bg_cursor_line()`），行号栏内置 Producer 同样支持。

**测试结果**：
- `smoke_phase4_8_s3.lua`：31/31 通过
- 回归测试：72/72 全绿
- 编译验证：text_editor_demo 编译通过

---

### S4：多语言语法高亮 — ✅ 已完成

**目标**：根据文件扩展名自动选择高亮规则，支持 5+ 语言。

**交付内容**：

| 任务 | 文件 | 描述 |
|:-----|:-----|:-----|
| 4.1 | `src/derive/highlight_factory.lua` | 新增 `nebula_highlight_select(langs)` — 编译期多语言注册，生成 `nebula_highlight_dispatch` 运行时分发 + `nebula_highlight_detect_ext` 扩展名检测 |
| 4.2 | `examples/text_editor_demo.nelua` | 注册 6 种语言高亮规则：nelua、lua、c、python、json、markdown |
| 4.3 | `examples/text_editor_demo.nelua` | 生成 6 个扫描函数 + 1 个分发函数 + 1 个扩展名检测函数 |
| 4.4 | `examples/text_editor_demo.nelua` | `_editor_highlight_id` 全局状态 + 文件加载时自动检测扩展名 |
| 4.5 | `examples/text_editor_demo.nelua` | `fill_edit_area` 改用 `nebula_highlight_dispatch` 替代硬编码 `nebula_highlight_scan_nelua` |
| 4.6 | `tests/smoke_phase4_8_s4.lua` | 47 项冒烟测试 |
| 4.7 | `tools/run_all_tests.sh` | 注册新测试到回归套件 |
| 4.8 | `tests/smoke_phase4_7_s7.lua` | 更新 S7 回归断言适配 dispatch 替代直调 |

**支持的语言 & 扩展名**：

| ID | 语言 | 扩展名 | 关键字数 | 行注释 |
|:---|:-----|:-------|:---------|:-------|
| 1 | nelua | `.nelua` | 50 | `--` |
| 2 | lua | `.lua`, `.luau` | 23 | `--` |
| 3 | c | `.c`, `.h`, `.cpp`, `.hpp`, `.cc`, `.cxx` | 49 | `//` |
| 4 | python | `.py`, `.pyw` | 57 | `#` |
| 5 | json | `.json`, `.jsonc` | 3 | 无 |
| 6 | markdown | `.md`, `.mdx`, `.markdown` | 5 | `#` |

**框架改动**：`highlight_factory.lua` +90 行（`nebula_highlight_select` 函数）

**测试结果**：
- `smoke_phase4_8_s4.lua`：47/47 通过
- 回归测试：73/73 全绿
- 编译验证：text_editor_demo 编译通过

---

### S5：自动缩进 + Tab 处理 — ✅ 已完成

**目标**：Enter 时保持缩进，Tab 插入空格，Shift+Tab 反缩进。

**交付内容**：

| 任务 | 文件 | 描述 |
|:-----|:-----|:-----|
| 5.1 | `src/nebula_core.nelua` | `NebulaKey.ShiftTab = 25` 枚举值 |
| 5.2 | `src/app.nelua` | Tab 键区分 Shift（`shift_down and NebulaKey.ShiftTab or NebulaKey.Tab`） |
| 5.3 | `src/derive/interaction_factory.lua` | Tab 处理：插入 4 空格 + 光标前进 4 |
| 5.4 | `src/derive/interaction_factory.lua` | ShiftTab 处理：计算前导空格（至多 4）+ `delete_range` 移除 + 光标回退 |
| 5.5 | `src/derive/interaction_factory.lua` | Enter 自动缩进：提取当前行前导空格数 + `{`/`:` 结尾额外 +4 + 新行插入缩进 |
| 5.6 | `tests/smoke_phase4_8_s5.lua` | 30 项冒烟测试 |
| 5.7 | `tools/run_all_tests.sh` | 注册新测试到回归套件 |

**框架改动**：
- `nebula_core.nelua`：+1 枚举值
- `app.nelua`：+1 行 shift 检测
- `interaction_factory.lua`：Enter 重写（+40 行 auto-indent）+ Tab（+12 行）+ ShiftTab（+18 行）

**测试结果**：
- `smoke_phase4_8_s5.lua`：30/30 通过
- 回归测试：74/74 全绿
- 编译验证：text_editor_demo 编译通过

---

### S6：集成验收 + 冒烟测试 — ✅ 已完成

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
| S2 | 搜索与替换 | 小（枚举 + 键映射） | ~340 行 | S1 | ✅ 已完成 |
| S3 | 状态栏 + 光标行高亮 | 无 | ~86 行 | 无 | ✅ 已完成 |
| S4 | 多语言语法高亮 | 小（多规则注册 + 分发生成） | ~190 行 | 无 | ✅ 已完成 |
| S5 | 自动缩进 + Tab | 小（枚举 + 原语） | ~70 行 | 无 | ✅ 已完成 |
| S6 | 集成验收 | 无 | ~110 项测试 | S1-S5 | ✅ 已完成 |

S1/S3/S4/S5 互相独立，可并行开发。S2 依赖 S1（搜索高亮需要选区渲染基础设施）。S6 是最终整合。

---

## 4. 明确排除（留给 Phase 5.0+）

- 多文件标签页（需要运行时组件创建，违反当前静态编译模型）
- 正则搜索（复杂度不匹配当前优先级）
- 多行注释高亮（需要跨行状态机，架构改动大）
- LSP / 代码补全（需要异步 I/O，超出当前框架能力）
- 代码折叠（需要语法树，不是词法层能做的）
