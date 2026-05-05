# Phase 4.9: 50 行终态收敛计划

**创建日期**：2026-05-05
**目标**：将 text_editor_demo 从 885 行收敛到 <50 行，验证 Era II 终态
**前置**：Phase 4.8 全部完成（76/76 回归全绿）

---

## 0. 分析结果

885 行 demo 的行数分布：

| 区域 | 行数 | 可糖化? |
|:-----|:-----|:--------|
| 文件头注释 | 41 | 框架自动 |
| cinclude/printf 声明 | 11 | 框架自动 |
| 全局状态（搜索/替换 buffer） | 24 | 框架内置 |
| 语法高亮规则 + derive | 135 | `nebula_highlight_set` 一站式 |
| Visual + DenseText 声明 | 24 | nebula_app 自动推导 |
| edit_area Producer | 127 | `nebula_builtin_edit_area` |
| status_bar Producer | 58 | `nebula_builtin_status_bar` |
| search 逻辑 + Producer | 180 | `nebula_builtin_search` |
| window_title 函数 | 26 | `nebula_builtin_update_title` |
| app 声明 | 30 | 保持（但缩短） |
| main 初始化 | 57 | nebula_editor_init 糖化 |
| main 搜索键盘处理 | 112 | 内置到 search |
| main 主循环 + 关闭 | 48 | nebula_editor_loop 糖化 |
| **合计** | **885** | **67% 可糖化** |

---

## 1. 分层实施（5 层）

### Layer 1: 一站式语法高亮声明（~135 行 → ~10 行）

**现状**：用户手写 6 种语言的 `nebula_highlight_rules` + 6 个 `nebula_derive_highlighter` + `nebula_highlight_select` = 135 行

**目标 API**：
```nelua
## nebula_highlight_set({
##   { name = "nelua",  exts = {"nelua"}, line_comment = "--",
##     keywords = {
##       { words = {"if","else","end",...}, color = 0xC586C0FF },
##       ...
##     },
##     string_color = 0xCE9178FF, number_color = 0xB5CEA8FF },
##   { name = "lua", exts = {"lua"}, ... },
##   ...
## })
```

**实现**：在 `nebula_core.nelua` 中新增 `nebula_highlight_set(langs)` 函数，内部循环调用 `nebula_highlight_rules` + `nebula_derive_highlighter`，最后调用 `nebula_highlight_select`。

**文件**：`src/nebula_core.nelua`（新增 ~30 行 sugar 函数）

---

### Layer 2: 内置 status_bar + window_title（~84 行 → 0 行）

**现状**：用户手写 fill_status_bar Producer（58 行）+ update_window_title 函数（26 行）

**目标**：当 `nebula_app` 中有 `status_bar` 组件且 producer = `"builtin_status_bar"` 时，自动生成：
1. 状态栏 Producer（文件名 + 行列号 + 行数 + 编码 + 行尾符）
2. 窗口标题更新函数（文件名 + 修改标记 + 行列号）
3. 每帧自动调用 update_window_title

**实现**：
- `nebula_core.nelua`：新增 `nebula_builtin_status_bar(editor_name)` sugar
- `app_factory.lua`：识别 `producer = "builtin_status_bar"`，生成 Producer 函数 + 自动注入 update 调用

**文件**：`src/nebula_core.nelua`, `src/derive/app_factory.lua`

---

### Layer 3: 内置 search 功能（~292 行 → ~10 行）

**现状**：用户手写搜索状态变量（24 行）+ scan_matches + search_goto + replace + replace_all（97 行）+ fill_search_bar Producer（83 行）+ main 中搜索键盘处理（112 行）= ~316 行

**目标 API**：
```nelua
-- 声明时
{ name = "search_bar", type = "SearchBarDenseVisual",
  producer = "builtin_search", layout = { flex_basis = 24 } }

-- main 中（如果完全内置到 app 的 update 循环中则 0 行）
```

**实现**：
- `nebula_core.nelua`：新增 `nebula_builtin_search(editor_name, opts)` sugar
- `interaction_factory.lua`：在 multiline_editable 的 process_body 中内置 Ctrl+F/H/F3/Escape 处理
- `app_factory.lua`：识别 `producer = "builtin_search"`，生成：
  1. 搜索状态全局变量（_search_active, _search_buf 等）
  2. scan_matches / search_goto / search_replace 函数
  3. fill_search_bar Producer
  4. update 中的搜索键盘处理

**文件**：`src/nebula_core.nelua`, `src/derive/app_factory.lua`, `src/derive/interaction_factory.lua`

---

### Layer 4: 内置 edit_area Producer（~127 行 → 0 行）

**现状**：用户手写 fill_edit_area Producer（127 行），其中 80% 是通用逻辑（滚动、选区高亮、光标渲染、UTF-8 解码），只有语法高亮着色是领域特定的。

**目标**：当 Producer = `"builtin_edit_area"` 时，自动生成通用编辑区渲染，用户只需提供 `highlight_id`。

**实现**：
- `app_factory.lua`：生成 edit_area Producer，内含：
  1. 滚动计算
  2. 遍历 visible rows
  3. flatten + highlight dispatch（使用 app 的 `_editor_highlight_id`）
  4. 选区高亮
  5. 搜索匹配高亮
  6. 光标渲染
  7. UTF-8 宽字符处理

**文件**：`src/derive/app_factory.lua`

---

### Layer 5: 一站式 editor app（剩余样板 → <50 行）

**现状**：main 函数中还有文件加载、保存、修改检测、主循环样板

**目标 API**：
```nelua
## nebula_editor_app("TextEditorApp", {
##   title = "Nebula Editor",
##   highlight = "nelua",
##   layout = {  -- optional, defaults to standard editor layout
##     search_bar = true,
##     line_nums = true,
##     status_bar = true,
##   },
## })
```

自动生成：
1. App 声明（nebula_app + 所有组件）
2. init 函数（文件加载、highlight 检测、状态初始化）
3. update 循环（保存、搜索、修改检测、标题更新）
4. shutdown

用户只需：
```nelua
local function main(): int32
  return nebula_editor_main("path/to/file.nelua")  -- or nil for empty
end
main()
```

**文件**：`src/nebula_core.nelua`, `src/derive/app_factory.lua`

---

## 2. 实施顺序

```
Layer 1 (高亮声明) ← 无依赖，独立
Layer 2 (status_bar) ← 无依赖，独立
Layer 3 (search) ← 依赖 Layer 2（搜索栏使用 status_bar 的主题色）
Layer 4 (edit_area) ← 依赖 Layer 1（需要 highlight_id）
Layer 5 (editor_app) ← 依赖 Layer 1-4 全部完成
```

推荐实施顺序：**L1 → L2 → L3 → L4 → L5**（每层独立可验证）

---

## 3. 验证标准

每层完成后：
1. `./build.sh text_editor_demo` 编译通过
2. `bash tools/run_all_tests.sh` 回归全绿
3. demo 运行正常（视觉验证）
4. 行数递减趋势

最终验收：
1. `examples/minimal_editor_demo.nelua` < 50 行
2. 功能等价于 text_editor_demo（语法高亮、行号、搜索替换、状态栏）
3. 76+N 项回归全绿

---

## 4. 不做清单

| 项目 | 理由 |
|:-----|:-----|
| 完全消除 edit_area Producer | 语法高亮是领域特定的，不能完全通用化。但可以内置 90% 通用逻辑，保留 highlight dispatch 调用点 |
| 动态主题切换 | 非核心路径，留给 Phase 5+ |
| 多文件 Tab | 需要预分配 N 个 editor 实例，复杂度高，留给 Phase 5+ |

---

## 5. 里程碑

```
L1: 885 → ~760 行（-125，高亮声明糖化）
L2: ~760 → ~650 行（-110，status_bar 内置）
L3: ~650 → ~350 行（-300，search 内置）
L4: ~350 → ~220 行（-130，edit_area 框架化）
L5: ~220 → <50 行（-170+，editor_app 一站式）
```
