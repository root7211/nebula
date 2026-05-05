# Phase 4.9.1 — 语法打磨：22 行终态

> **目标**: 将 `text_editor_demo_v2.nelua`（85 行）收敛到 ~22 行终态
> **约束**: 每项改动必须通过三公理合规性验证（A/B/C），不引入运行时开销
> **原则**: 仅消除可确定性推导的冗余，不引入模板假设
> **日期**: 2026-05-05
> **前置**: Phase 4.9 已完成（885→85 行，10.4x 压缩）

---

## 1. 诊断：v2 的 7 个冗余源

| # | 冗余类型 | 行数 | 根因 |
|---|---|---|---|
| 1 | 4 个 DenseText Visual record 声明完全相同 (`{ pos: Vec2, size: Vec2 }`) | 8 行 | `nebula_app` 不自动生成 DenseText record |
| 2 | `cell_w = 10.0, cell_h = 16.0` 重复 8 次 | 散布 | 无 app 级默认值 |
| 3 | 4 个 `nebula_builtin_*` 调用独立于 `nebula_app` | 4 行 | builtin 未内联到 components |
| 4 | Producer 名称是需要记忆的字符串约定 | 4 处 | 无自动绑定 |
| 5 | `layout = { flex_basis = 24 }` 嵌套过深 | 多处 | 无 layout 字段提升 |
| 6 | `container = { { ref = "x" }, { ref = "y" } }` 冗长 | 2 行 | 无 children 简写 |
| 7 | 35 行 highlight 关键词定义 | 35 行 | 无内置语言包 |

**核心问题**: Phase 4.9 把 boilerplate 从 demo 搬到了 `nebula_builtin_*` 调用，但没有把这些调用**吸收**进 `nebula_app` 的声明中。信息分散在三个地方（Visual 声明、builtin 调用、components 数组），而它们本应归一。

---

## 2. 设计原则

每项改动都必须满足：

1. **可推导性判据**: 该信息能否从已有声明中确定性推导？能 → sugar（消除），不能 → 应用逻辑（保留）
2. **三公理合规**: A（S1 编译期展开）、B（零堆分配）、C（Visual→Pipeline 1:1 映射）
3. **分层可逃逸**: 新 sugar 可被旧 API 覆盖，用户随时可降级
4. **正交可组合**: 每个改动独立生效，不强制捆绑

---

## 3. 终态目标：text_editor_demo_v3.nelua（~22 行）

```nelua
require "nebula"

## nebula_highlight_builtins({"nelua", "lua", "c", "python", "json", "markdown"})

## nebula_visual("EditorBg", {
##   primitives = {"multiline_editable"},
##   max_text_len = 256, max_lines = 256, component_id = 1,
## })

## nebula_app("TextEditor", {
##   title = "Nebula Editor",
##   cell  = { w = 10.0, h = 16.0 },
##   components = {
##     { name = "editor",      type = "EditorBg" },
##     { name = "search_bar",  dense = 256,  builtin = "search_bar",  flex_basis = 24 },
##     { name = "editor_body", row = true, flex_grow = 1,
##       children = { "line_nums", "edit_area" } },
##     { name = "line_nums",   dense = 250,  builtin = "line_nums",   flex_basis = 50 },
##     { name = "edit_area",   dense = 6000, builtin = "edit_area",   flex_grow = 1 },
##     { name = "status_bar",  dense = 200,  builtin = "status_bar",  flex_basis = 24 },
##   },
## })

## nebula_editor_main("TextEditor", { editor = "editor" })
```

**85 行 → 22 行，压缩 3.9x（累计从 v1 的 885 行压缩 40x）。**

---

## 4. 逐项改进方案

### 改进 1: `dense = N` — 消除 DenseText Visual record 手写

**Before (8 行):**
```nelua
global LineNumDenseVisual = @record{ pos: Vec2, size: Vec2 }
## nebula_component("LineNumDenseVisual", { text_mode = "dense", max_chars = 1024 })
global EditAreaDenseVisual = @record{ pos: Vec2, size: Vec2 }
## nebula_component("EditAreaDenseVisual", { text_mode = "dense", max_chars = 8192 })
global StatusBarDenseVisual = @record{ pos: Vec2, size: Vec2 }
## nebula_component("StatusBarDenseVisual", { text_mode = "dense", max_chars = 256 })
global SearchBarDenseVisual = @record{ pos: Vec2, size: Vec2 }
## nebula_component("SearchBarDenseVisual", { text_mode = "dense", max_chars = 256 })
```

**After (0 行，内联到 components):**
```nelua
{ name = "status_bar", dense = 200, ... },
```

**推导依据**: DenseText Visual 的 record 结构永远是 `{ pos: Vec2, size: Vec2 }`，字段零变化。`nebula_app` 检测到 `dense = N` 时，自动生成对应的 Visual record + `nebula_component` 调用。类型名自动推导为 `<AppName>_<ComponentName>_DenseVisual`。

**公理合规**:
- A ✅ — record 和 component 在 S1 编译期生成，与手写等价
- B ✅ — 固定数组 `[N]DenseCharInstance`，零堆分配
- C ✅ — DenseText pipeline 签名由 `text_mode="dense"` 唯一确定

**逃逸路径**: 如果用户需要自定义 DenseText record 字段，用 `type = "MyCustomDenseVisual"` 覆盖 `dense`。

---

### 改进 2: `cell = { w, h }` — App 级单元格默认值

**Before (重复 8 次):**
```nelua
## nebula_builtin_line_nums("editor", { cell_w = 10.0, cell_h = 16.0, rows = 50 })
## nebula_builtin_status_bar("editor", { cell_w = 10.0, cell_h = 16.0, cols = 128 })
-- ... 同样的值在 builtin 调用中出现 4 次
-- ... 同样的值在 nebula_app components 中又出现 4 次
```

**After (声明 1 次):**
```nelua
## nebula_app("TextEditor", {
##   cell = { w = 10.0, h = 16.0 },
##   ...
## })
```

**推导依据**: 同一个 app 内的 DenseText 组件共享相同的字体网格尺寸（等宽字符网格）。`cell` 作为 app 级默认值，各组件继承。个别组件可通过 `cell_w`/`cell_h` 覆盖。

**实现**: `nebula_app` 将 `spec.cell` 保存到 `nebula_app_registry[app_name].cell`，`nebula_builtin_*` 和 `nebula_app_register_dense_text` 从 registry 读取默认值。

**公理合规**: 纯 S1 常量传播，运行时生成代码不变。

---

### 改进 3: `builtin = "..."` — Producer 自动绑定

**Before (4 行独立调用 + 4 处字符串引用):**
```nelua
## nebula_builtin_line_nums("editor", { cell_w = 10.0, cell_h = 16.0, rows = 50 })
## nebula_builtin_status_bar("editor", { cell_w = 10.0, cell_h = 16.0, cols = 128 })
## nebula_builtin_search_bar("editor", { cell_w = 10.0, cell_h = 16.0, cols = 128 })
## nebula_builtin_edit_area("editor",  { cell_w = 10.0, cell_h = 16.0, cols = 120, rows = 50 })

-- nebula_app 中还需要手动写 producer 名称:
{ name = "status_bar", type = "StatusBarDenseVisual",
  producer = "nebula_fill_status_bar_editor", cell_w = 10.0, cell_h = 16.0,
  max_chars = 200, layout = { flex_basis = 24 } },
```

**After (内联到 components):**
```nelua
{ name = "status_bar", dense = 200, builtin = "status_bar", flex_basis = 24 },
```

**推导依据**: `builtin = "status_bar"` + 组件名确定性推导出：
1. 调用 `nebula_builtin_status_bar(editor_name, opts)`
2. Producer 函数名 `nebula_fill_status_bar_{editor_name}`
3. cell_w/cell_h 从 app 级 `cell` 继承
4. cols/rows 从 `dense` 值和 cell 尺寸自动计算

**builtin 类型与 editor_name 的绑定**: `nebula_app` 遍历 components，找到第一个 `primitives` 包含 `multiline_editable` 的组件名作为 `editor_name`。

**实现**: `nebula_app` 在处理 components 时，对含 `builtin` 字段的组件：
```lua
if comp.builtin == "status_bar" then
  nebula_builtin_status_bar(editor_name, {
    cell_w = app_cell.w, cell_h = app_cell.h,
    cols = math.floor(comp.dense / (app_cell.h / app_cell.w))
  })
  comp.producer = "nebula_fill_status_bar_" .. editor_name
end
```

**公理合规**: 生成的代码与手动调用 `nebula_builtin_status_bar` 完全一致。

---

### 改进 4: Layout 字段提升

**Before:**
```nelua
{ name = "search_bar", ..., layout = { flex_basis = 24 } },
```

**After:**
```nelua
{ name = "search_bar", ..., flex_basis = 24 },
```

**推导依据**: `flex_basis`、`flex_grow`、`direction` 等 layout 属性只在 layout 上下文中有意义，不会与其他 component 字段名冲突。可安全提升到组件顶层，由 `nebula_app` 在 S1 自动归入 `layout = {...}`。

**实现**: `nebula_app` 在解析每个 component spec 时：
```lua
local layout_keys = { "flex_basis", "flex_grow", "direction", "justify", "align", "width", "height" }
for _, key in ipairs(layout_keys) do
  if comp[key] ~= nil then
    comp.layout = comp.layout or {}
    comp.layout[key] = comp[key]
  end
end
```

**向后兼容**: `layout = { flex_basis = 24 }` 仍然有效，与直接写 `flex_basis = 24` 等价。

---

### 改进 5: `children` 简写 + `row` 标记

**Before:**
```nelua
{ name = "editor_body", layout = { direction = "row", flex_grow = 1,
    container = { { ref = "line_nums" }, { ref = "edit_area" } } } },
```

**After:**
```nelua
{ name = "editor_body", row = true, flex_grow = 1,
  children = { "line_nums", "edit_area" } },
```

**推导依据**:
- `row = true` → `direction = "row"`（`column` 为默认值，大多数容器不需要声明）
- `children = { "x", "y" }` → `container = { { ref = "x" }, { ref = "y" } }`，因为 `ref` 是 container 子项的唯一语义

**实现**:
```lua
if comp.row then
  comp.layout = comp.layout or {}
  comp.layout.direction = "row"
end
if comp.children then
  comp.layout = comp.layout or {}
  comp.layout.container = {}
  for _, child_name in ipairs(comp.children) do
    table.insert(comp.layout.container, { ref = child_name })
  end
end
```

**公理合规**: 纯 S1 spec 变换，运行时不变。

---

### 改进 6: `nebula_highlight_builtins` — 内置语言包

**Before (35 行):**
```nelua
##[[ nebula_highlight_pack({
  { name="nelua", exts={"nelua"},
    keywords={
      {words={"if","else","elseif","then","end","for","while","do",
              "repeat","until","return","break","goto","in","switch",
              "case","continue","defer"}, color=0xC586C0FF},
      {words={"local","global","function","require","record","enum",
              "union","type"}, color=0x569CD6FF},
      ...
    }, line_comment="--", line_comment_color=0x6A9955FF,
       string_color=0xCE9178FF, number_color=0xB5CEA8FF },
  -- ... 5 more languages with identical color scheme ...
}) ]]
```

**After (1 行):**
```nelua
## nebula_highlight_builtins({"nelua", "lua", "c", "python", "json", "markdown"})
```

**推导依据**: 这 6 种语言的关键词列表、注释符号、颜色方案都是**静态的公共知识**，不含任何用户特定信息。框架将它们作为内置数据表（类似 VS Code 内置语言包），在 S1 编译期注入。

**实现**: `highlight_factory.lua` 新增 `NEBULA_BUILTIN_LANGS` 数据表：

```lua
local NEBULA_BUILTIN_LANGS = {
  nelua = {
    exts = {"nelua"},
    keywords = {
      { words = {"if","else","elseif","then","end","for","while","do",
                 "repeat","until","return","break","goto","in","switch",
                 "case","continue","defer"},                              color = 0xC586C0FF },
      { words = {"local","global","function","require","record","enum",
                 "union","type"},                                         color = 0x569CD6FF },
      { words = {"true","false","nil","nilptr"},                          color = 0x4EC9B0FF },
      { words = {"int8","int16","int32","int64","uint8","uint16","uint32",
                 "uint64","float32","float64","boolean","cstring","cint",
                 "csize","pointer","void","auto","byte","isize","usize"}, color = 0x4DC9A0FF },
    },
    line_comment = "--",
    line_comment_color = 0x6A9955FF,
    string_color       = 0xCE9178FF,
    number_color       = 0xB5CEA8FF,
  },
  lua = { ... },
  c   = { ... },
  python   = { ... },
  json     = { ... },
  markdown = { ... },
}

function nebula_highlight_builtins(lang_names)
  local pack = {}
  for _, name in ipairs(lang_names) do
    local def = NEBULA_BUILTIN_LANGS[name]
    if not def then
      error("[nebula_highlight_builtins] unknown language: " .. name)
    end
    local entry = {}
    for k, v in pairs(def) do entry[k] = v end
    entry.name = name
    table.insert(pack, entry)
  end
  nebula_highlight_pack(pack)
end
```

**公理合规**:
- A ✅ — 关键词在 S0/S1 确定，不依赖运行时输入
- B ✅ — 与 `nebula_highlight_pack` 生成完全相同的代码
- C ✅ — 匹配结果直接写入 `DenseCharInstance.fg_color`

**逃逸路径**: 如需自定义语言或覆盖内置语言的颜色，仍可直接用 `nebula_highlight_pack` 或 `nebula_highlight_rules`。

---

### 改进 7: `nebula_editor_main` 读取 app 级 `title` 和 `cell`

**Before:**
```nelua
## nebula_editor_main("TextEditorApp", { editor = "editor", title = "Nebula Editor", cell_h = 16.0 })
```

**After:**
```nelua
## nebula_editor_main("TextEditor", { editor = "editor" })
```

**推导依据**: `title` 和 `cell_h` 已在 `nebula_app` 的 spec 中声明并存储到 `nebula_app_registry[app_name]`。`nebula_editor_main` 可直接从 registry 读取，不需要用户重复传递。

**实现**:
```lua
function nebula_editor_main(app_type, opts)
  local reg = nebula_app_registry[app_type]
  local title  = opts.title  or (reg and reg.title)  or "Nebula Editor"
  local cell_h = opts.cell_h or (reg and reg.cell and reg.cell.h) or 16.0
  -- ... 其余逻辑不变
end
```

**向后兼容**: 如果用户在 `nebula_editor_main` 中显式传递 `title` 或 `cell_h`，优先使用用户值。

---

## 5. 对比总览

| 度量 | v1 (Phase 4.8) | v2 (Phase 4.9) | v3 (Phase 4.9.1) |
|---|---|---|---|
| 总行数 | 885 | 85 | **22** |
| DenseText 声明 | ~40 | 8 | **0** |
| cell_w/h 出现次数 | ~12 | 8 | **1** |
| Producer 字符串引用 | 6 | 4 | **0** |
| 高亮规则 | 130 | 35 | **1** |
| 累计压缩比 | — | 10.4x | **40x** |

---

## 6. button_v2 一致性验证

提案不影响简单 demo 的写法。button_v2 保持不变（30 行），因为：
- 它没有 DenseText 组件 → 改进 1/2/3 不涉及
- 它有自定义主循环逻辑（`if just_clicked`）→ 不使用 `nebula_editor_main`
- 它已经足够优雅 → 无需进一步压缩

**唯一微调**（可选）：`init_themed` 可受益于 layout 系统——当 pos/size 由布局引擎提供时，只需传 radius：
```nelua
-- 当前 (Phase 4.5-S3):
app.btn:init_themed(Vec2{x=300,y=250}, Vec2{x=200,y=60}, 12.0)

-- 可选改进 (如果使用 layout):
app.btn:init_themed(12.0)  -- pos/size 由 layout 注入
```

这是向后兼容的——`init_themed` 检测参数数量，1 个参数时从 `visual.pos`/`visual.size` 读取布局注入的值。

---

## 7. 实现影响范围

| 文件 | 改动 | 风险 |
|---|---|---|
| `src/derive/app_factory.lua` | `nebula_app` 解析 `dense`/`builtin`/`cell`/`row`/`children`/`title`，自动生成 DenseText record + 调用 `nebula_builtin_*` | 中（核心编排逻辑） |
| `src/derive/highlight_factory.lua` | 新增 `NEBULA_BUILTIN_LANGS` 表 + `nebula_highlight_builtins()` 函数 | 低（纯增量） |
| `src/nebula_core.nelua` | `nebula_editor_main` 从 app registry 读取 `title`/`cell` | 低（fallback 逻辑） |
| `examples/text_editor_demo_v3.nelua` | 新增 22 行终态 demo | 无 |
| `tests/smoke_phase4_9_1.lua` | 验证新 sugar 生成等价代码 | 无 |

**不需要改动的文件**: renderer.nelua、app.nelua、pipeline_factory.lua、layout_engine.lua、interaction_factory.lua、gap_buffer_factory.lua、shader_compose.lua。

**关键保证**: 改动完全局限在 S1 元编程层，运行时生成代码与 v2 完全一致，零性能影响。

---

## 8. 依赖关系与实施顺序

```
改进 6 (highlight_builtins)     ← 最独立，无依赖
    ↓
改进 4 (layout 字段提升)        ← 独立，只改 spec 解析
    ↓
改进 5 (children + row)         ← 独立，只改 spec 解析
    ↓
改进 2 (cell 默认值)            ← 需要 registry 存储
    ↓
改进 1 (dense = N)              ← 依赖改进 2（需要 cell 默认值）
    ↓
改进 3 (builtin 自动绑定)       ← 依赖改进 1+2（需要 dense record + cell）
    ↓
改进 7 (editor_main 读 registry) ← 依赖改进 2（读取 title/cell）
```

**建议实施顺序**: 6 → 4 → 5 → 2 → 1 → 3 → 7

---

## 9. 公理合规性总结

| 公理 | 改进 1 | 改进 2 | 改进 3 | 改进 4 | 改进 5 | 改进 6 | 改进 7 |
|------|--------|--------|--------|--------|--------|--------|--------|
| A (S1 展开) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| B (零堆分配) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| C (GPU 直映) | ✅ | N/A | ✅ | N/A | N/A | ✅ | ✅ |

**所有改动均为 S1 编译期 spec 变换，展开后生成与手写等价的代码，运行时行为零变化。**

---

## 10. 逃逸路径清单

| 场景 | 使用 | 逃逸到 |
|---|---|---|
| 需要自定义 DenseText record 字段 | `dense = N` | `type = "MyDenseVisual"` + 手动 record |
| 需要自定义 Producer | `builtin = "status_bar"` | `producer = "my_custom_fill"` + 手写 Producer |
| 需要组件级 cell 覆盖 | app 级 `cell` | 组件级 `cell_w`/`cell_h` |
| 需要自定义语言高亮 | `nebula_highlight_builtins` | `nebula_highlight_pack` 或 `nebula_highlight_rules` |
| 需要复杂布局 | `row`/`children` 简写 | 完整 `layout = { ... }` |
| 需要自定义主循环 | `nebula_editor_main` | 手写 `main()` 函数 |

---

## 11. 风险与缓解

| 风险 | 缓解 |
|---|---|
| `dense = N` 自动生成的类型名冲突 | 类型名包含 app name + component name，保证唯一 |
| `builtin` editor_name 自动推断错误 | 如果有多个 multiline_editable 组件，要求用户显式传 `editor_name` |
| `NEBULA_BUILTIN_LANGS` 表增大编译时间 | 惰性加载：只在 `nebula_highlight_builtins` 被调用时初始化 |
| layout 字段提升与 component 字段名冲突 | 枚举所有 layout 字段名，确认无冲突（`width`/`height` 需要特别处理） |

---

*文档版本: 1.0*
*最后更新: 2026-05-05*
