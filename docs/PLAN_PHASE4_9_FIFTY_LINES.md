# Phase 4.9 — 50 行终态收敛方案（完整版）

> **目标**: 将 `text_editor_demo.nelua` 从当前 885 行收敛到 <50 行终态
> **约束**: 每一层 sugar 必须通过三公理合规性验证（A/B/C），不引入运行时开销
> **日期**: 2026-05-05
> **当前状态**: 885 行，76/76 regression 全绿

---

## 1. 总体架构：三层次 API 哲学

Nebula 的 API 分三层，对应三个用户群体：

| 层次 | API | 用户 | 原则 |
|------|-----|------|------|
| L0 Raw | `nebula_dense_text_*()` | 框架开发者 | 1:1 映射 GPU，零抽象 |
| L1 Sugar | `nebula_highlight_*()` | 高级用户 | 编译期展开为 L0 代码 |
| L2 Visual | `nebula_app({components={...}})` | 终端用户 | 一行声明，零手写 Producer |

**50 行终态 = L2 Visual API**，即用户只需声明组件拓扑和配置，框架自动生成所有 Producer、layout 注入、初始化代码。

---

## 2. 现状分析：885 行的构成

```
组件声明（Phase 4.8-NL）    19 行   2%   ← 已是 L2，不可再压缩
DenseText 渲染层声明        12 行   1%   ← 可被 auto-dense 吸收
status_bar Producer         53 行   6%   ← 可被 L1 sugar 吸收
search Producer             78 行   9%   ← 可被 L1 sugar 吸收
edit_area Producer         121 行  14%   ← auto-dense 已能生成默认 Producer
highlight rules            130 行  15%   ← L1 sugar 可压缩到 1 行
搜索交互逻辑                91 行  10%   ← 交互 sugar（L1.Interaction）
文件加载函数                 23 行   3%   ← 框架内建辅助
窗口标题更新                 21 行   2%   ← 框架内建辅助
键盘交互（S1/S5）           103 行  12%   ← interaction sugar（L1.Interaction）
init_themed 主题配置         10 行   1%   ← 框架内建默认
主函数 + 渲染循环           ~225 行 25%   ← 框架内建 main loop
```

**压缩空间**: 885 - 290（应用逻辑） = 595 行 boilerplate → 目标压缩到 <20 行 sugar 声明

---

## 3. 分层实施方案

### Layer 1: Highlight Rules Sugar（压缩 ~125 行 → ~1 行）

**现状**: 8 个 `nebula_highlight_add_rule()` 调用 + 3 个注册宏调用，共 ~130 行。

**目标 API**:
```lua
nebula_highlight_init("c_keywords", "keyword",
  {"auto","break","case","char","const","continue","default","do",
   "double","else","enum","extern","float","for","goto","if",
   "inline","int","long","register","restrict","return","short",
   "signed","sizeof","static","struct","switch","typedef","union",
   "unsigned","void","volatile","while","bool","true","false","NULL"},
  {fg = theme_fg_keyword, match_type = "exact"})
```

**公理合规性分析**:
- **公理 A (布局零运行时)**: ✅ 规则在编译期（metaprogramming 阶段）注册到 `_HIGHLIGHT_RULES` 表，运行时只读查找，无布局计算。
- **公理 B (零堆分配)**: ✅ 规则字符串是 Nelua 字面量，编译期嵌入 `.rodata`；运行时模式匹配使用栈上固定缓冲区（已有 `nebula_highlight_add_word_boundary` 机制）。
- **公理 C (GPU 直映)**: ✅ 匹配结果直接写入 `DenseCharInstance.fg_color`（1:1 GPU 映射），无 CPU 中间层。

**实现要点**:
1. 新增 `nebula_highlight_init(group_name, default_match_type, word_list, style)` 函数
2. 内部循环调用已有的 `nebula_highlight_add_rule(group, pattern, style, match_type)`
3. 保留 `nebula_highlight_select` / `nebula_highlight_detect` 不变
4. 对于复杂模式（行注释 `//`、块注释、字符串），仍需单独调用 `nebula_highlight_add_rule`

**预期效果**: 130 行 → 8 行（每种规则类型一行）

---

### Layer 2: Producer Auto-Generation via Producers Block（压缩 ~252 行 → ~20 行）

**现状**: `edit_area_producer`、`status_bar_producer`、`search_producer` 手写 Producer，共 ~252 行。

**目标 API**:
```lua
nebula_app({
  components = { ... },
  producers = {
    nebula_producer("search", "DenseText", "frame_update", search_params),
    nebula_producer("status_bar", "DenseText", "frame_update", status_params),
  },
  ...
})
```

**公理合规性分析**:
- **公理 A (布局零运行时)**: ✅ Producer 函数在 metaprogramming 阶段生成，运行时只执行绑定代码。Producers block 在 app 初始化时注册到 `_NEBULA_PRODUCERS` 表，不涉及 layout 计算。
- **公理 B (零堆分配)**: ✅ Producer 函数体中使用的 DenseCharInstance 数组是栈上分配的（`dense_text.cells` 已由框架预分配），`nebula_fill_dense_text_area` 等工具函数只做 memset-like 操作。
- **公理 C (GPU 直映)**: ✅ Producer 输出直接写入 `DenseCharInstance` 数组，由 `nebula_app_dense_text_to_gpu` 直接上传到 GPU，无 CPU 中间缓冲。

**实现要点**:
1. `nebula_producer(name, component_type, hook, params)` 返回一个 Producer 描述表
2. `app_factory.lua` 在 `gen_app` 时扫描 `spec.producers` 数组
3. 对于每个 producer，调用 `nebula_app_register_slot`（或 `nebula_app_register_text`）并注入 producer 参数
4. **编辑区 auto-dense Producer**（已有 `_NEBULA_AUTO_DENSE` 机制）进一步扩展：
   - 如果用户在 `producers` 中指定了 `edit_area` 的 producer，则使用用户提供的
   - 如果未指定，使用 `_NEBULA_AUTO_DENSE` 自动生成的默认 `nebula_default_edit_area_` producer

**预期效果**: 252 行 → ~5 行 Producer 声明

---

### Layer 3: Interaction Sugar — Search Keyboard Logic（压缩 ~103 行 → ~5 行）

**现状**: `do_search`、`do_replace`、`do_find_next`、`do_replace_all`、`search_key` 函数共 ~103 行。

**目标 API**:
```lua
nebula_app({
  ...
  interactions = {
    nebula_interaction("search_bar", {
      on_enter = { action = "find_next", target = "edit_area", history = "search_history" },
      on_escape = { action = "close_search" },
    }),
    nebula_interaction("replace_bar", {
      on_enter = { action = "replace_and_next", target = "edit_area" },
    }),
  },
  keybindings = {
    { key = "F3", action = "find_next", when = "search_active" },
    { key = "Ctrl+F", action = "open_search" },
    { key = "Ctrl+H", action = "open_replace" },
  },
  ...
})
```

**公理合规性分析**:
- **公理 A**: ✅ interactions 声明在编译期展开为已有的 `nebula_interaction_init` 调用 + 组件 `on_key` 回调注册，运行时无布局计算。
- **公理 B**: ✅ 搜索历史用已有的 `[100]cstring` 固定数组，新增匹配位置用 `[512]MatchPos` 固定数组（已在 S2 中实现），均为栈分配。
- **公理 C**: ✅ 搜索高亮通过修改 `DenseCharInstance.bg_color` 实现，直接映射 GPU，无 CPU 中间层。

**实现要点**:
1. `nebula_interaction(component, action_map)` 在 metaprogramming 阶段展开为标准 interaction 注册代码
2. `keybindings` 数组展开为 `NebulaKeyMap` 数组，在 `_NEBULA_KEY_BINDINGS` 中追加
3. action string 映射到框架内置的 `nebula_search_*` 函数（需要先将 search 逻辑提升为框架内建功能）
4. **交互注册边界**: S1/S2 边界审查确认"运行时改 Producer 输出"合规，但"运行时改组件拓扑"不合规。此处 action 均为运行时数据操作，合规。

**预期效果**: 103 行 → ~5 行声明

---

### Layer 4: Framework Built-in Helpers（压缩 ~54 行 → ~2 行）

**现状**: `load_file_to_multibuf` (23 行) + `update_window_title` (21 行) + `init_themed` 手动覆盖 (10 行) = ~54 行。

**目标**: 这些函数提升为框架内建函数。

**公理合规性分析**:
- **公理 A**: ✅ `load_file_to_multibuf` 和 `update_window_title` 是纯运行时数据操作（文件 I/O + 字符串格式化），不涉及布局。
- **公理 B**: ✅ 文件读取使用已有的 `FILE*` 句柄和 `MultiBuf.insert_newline/merge_line_up`，均为栈上操作（MultiBuf 内部缓冲区在 record 声明时确定大小）。
- **公理 C**: ✅ 窗口标题是 GLFW 层操作，与 GPU 直映无关。

**实现要点**:
1. `nebula_load_file(multibuf, filepath)` — 提取为 `src/utils.nelua` 中的通用函数
2. `nebula_update_title(window, prefix, multibuf)` — 提取为 `src/app.nelua` 中的通用函数
3. `init_themed` 中的 `multiline_editable` 字段覆盖 — 由 `nebula_app` 在 auto-dense 时自动完成（已有 `_NEBULA_AUTO_DENSE` 机制，只需补全 pixel_height/text_origin_x/content_height 字段）

**预期效果**: 54 行 → 2 行调用

---

### Layer 5: Main Loop Sugar（压缩 ~225 行 → ~1 行）

**现状**: `main()` 函数中的渲染循环、事件处理、组件更新等 ~225 行。

**目标 API**:
```lua
nebula_editor_main()
```

**公理合规性分析**:
- **公理 A**: ✅ main loop 是框架内建的事件循环，组件布局在 init 阶段已确定，loop 中只做渲染和事件分发。
- **公理 B**: ✅ main loop 中无 heap allocation，所有临时变量在栈上。
- **公理 C**: ✅ main loop 调用 `nebula_app_dense_text_to_gpu` 直接上传 GPU buffer。

**实现要点**:
1. `nebula_editor_main()` 由 `nebula_app` 的 metaprogramming 自动生成
2. 内部包含完整的 `nebula_init` → `while not should_close` → `nebula_frame_render` → `nebula_deinit` 循环
3. 事件处理、组件更新、交互分发全部由框架内建
4. **关键边界**: main loop 中的交互分发（键盘/鼠标事件路由到对应组件）已由 `nebula_app_interaction_*` 系列函数处理（Phase 4.6-4.7），无需用户手写

**预期效果**: 225 行 → 1 行 `nebula_editor_main()`

---

## 4. 终态：50 行目标代码

```lua
-- Phase 4.9 终态：<50 行 text_editor_demo
local theme = require "nebula_theme"

nebula_app({
  name = "Text Editor Demo",
  layout = { direction = "vertical", main_axis = "start" },

  components = {
    { name = "menu_bar", type = "NebulaVisual", component_id = 100 },
    { name = "toolbar", type = "NebulaVisual", component_id = 101 },
    { name = "status_bar", type = "DenseText", component_id = 102, producer = "status_bar_producer" },
    { name = "search_bar", type = "DenseText", component_id = 103, producer = "search_producer" },
    { name = "replace_bar", type = "DenseText", component_id = 104, producer = "replace_producer" },
    { name = "edit_area", type = "multiline_editable", component_id = 105 },
  },

  producers = {
    nebula_producer("status_bar", { ... }),
    nebula_producer("search", { ... }),
  },

  interactions = {
    nebula_interaction("search_bar", {
      on_enter = { action = "find_next", target = "edit_area" },
    }),
    nebula_interaction("replace_bar", {
      on_enter = { action = "replace_and_next", target = "edit_area" },
    }),
  },

  keybindings = {
    { key = "Ctrl+F", action = "open_search" },
    { key = "Ctrl+H", action = "open_replace" },
    { key = "F3", action = "find_next" },
    { key = "Ctrl+S", action = "save_file" },
  },

  theme = theme.nebula_theme_default(),
  highlight = {
    nebula_highlight_init("c_keywords", "keyword", { "if", "else", "while", ... }),
    nebula_highlight_init("c_types", "keyword", { "int", "char", "void", ... }),
    nebula_highlight_init("c_preprocessor", "exact", { "#include", "#define", ... }),
    nebula_highlight_line_comment("c_line_comment", "//"),
    nebula_highlight_block_comment("c_block_comment", "/*", "*/"),
    nebula_highlight_string_literal("c_string", "\""),
    nebula_highlight_char_literal("c_char", "'"),
  },
})

nebula_editor_main()
```

**总计**: ~48 行

---

## 5. 依赖关系与实施顺序

```
Layer 1 (Highlight Sugar)          ← 最独立，无依赖
    ↓
Layer 2 (Producer Auto-Gen)        ← 依赖 L1（highlight 需要 producer 机制）
    ↓
Layer 3 (Interaction Sugar)        ← 依赖 L2（interactions 需要 producer 存在）
    ↓
Layer 4 (Framework Helpers)        ← 独立，可在任何阶段实施
    ↓
Layer 5 (Main Loop Sugar)          ← 依赖 L2+L3（需要所有组件和交互已注册）
```

**建议实施顺序**: L1 → L4 → L2 → L3 → L5（先做独立模块，再做依赖链）

---

## 6. 每层验收标准

| 层 | 验收条件 | 预期行数 |
|----|----------|----------|
| L1 | `nebula_highlight_init()` 生成等价的 rule 注册代码 | 130→8 |
| L2 | `nebula_producer()` 生成等价的 Producer 函数 | 252→5 |
| L3 | `nebula_interaction()` 生成等价的交互回调 | 103→5 |
| L4 | `nebula_load_file()` + `nebula_update_title()` 内建 | 54→2 |
| L5 | `nebula_editor_main()` 替代 main() | 225→1 |
| **总** | **所有层完成后** | **885→~48** |

---

## 7. 公理合规性总结

| 公理 | L1 | L2 | L3 | L4 | L5 |
|------|----|----|----|----|-----|
| A (布局零运行时) | ✅ | ✅ | ✅ | ✅ | ✅ |
| B (零堆分配) | ✅ | ✅ | ✅ | ✅ | ✅ |
| C (GPU 直映) | ✅ | ✅ | ✅ | ✅ | ✅ |

**所有 sugar 层均在编译期（metaprogramming 阶段）展开为与手写等价的 L0 代码，运行时行为完全一致，无任何运行时开销。**

---

## 8. 风险与缓解

1. **auto-dense Producer 灵活性不足** — 默认 Producer 只处理基础渲染，搜索高亮等高级功能需要用户自定义 Producer。**缓解**: `producers` 块允许用户覆盖默认 Producer。

2. **interaction sugar 表达力有限** — 简单的 action map 可能无法表达复杂的交互逻辑（如搜索历史管理）。**缓解**: 保留 L0 Raw API 作为 escape hatch，用户可随时降级到手写 Producer。

3. **main loop sugar 封装过度** — 某些应用可能需要自定义渲染循环。**缓解**: 提供 `nebula_editor_main()` 和 `nebula_app_main()` 两种封装级别。

---

## 9. 里程碑

- **M1**: L1 Highlight Sugar — 预计 2 天
- **M2**: L4 Framework Helpers — 预计 1 天
- **M3**: L2 Producer Auto-Gen — 预计 3 天（含 auto-dense 扩展）
- **M4**: L3 Interaction Sugar — 预计 2 天（含 search/replace 提升）
- **M5**: L5 Main Loop Sugar — 预计 1 天
- **M6**: 终态集成验收 — 预计 1 天

**总计**: ~10 天

---

## 10. 关键决策记录

1. **为什么不一步到位？** — 每层独立可验证，避免大爆炸式重构引入回归。
2. **为什么先做 L1 再做 L2？** — L1 最独立，不依赖其他 sugar 层；L2 依赖 L1 的 highlight 机制。
3. **为什么不引入新抽象层？** — 三层次 API（L0/L1/L2）已足够，新增层会违反"形即范式"的 record-first 原则。
4. **为什么保留 L0 Raw API？** — 作为 escape hatch，确保用户在 sugar 层表达力不足时可降级。

---

*文档版本: 1.0*
*最后更新: 2026-05-05*
