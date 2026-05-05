# Nebula 嵌套布局支持实施方案

**创建日期**：2026-05-05
**基准状态**：70/70 回归测试全绿 | Phase 4.8-S1 已完成
**触发原因**：text_editor_demo 需要 line_nums + edit_area 在同一行并排，status_bar 在下方，当前 nebula_app sugar 仅支持一级平铺布局

---

## 0. 问题诊断

### 0.1 当前布局结构（text_editor_demo）

```
column (root, 1280x800):
  ├── editor      (background, 无 layout)     ← 占满全屏背景
  ├── line_nums   (flex_basis=50)             ← 行号栏
  ├── edit_area   (flex_grow=1)               ← 编辑区
  └── status_bar  (flex_basis=24)             ← 状态栏（待加）
```

**结果**：line_nums、edit_area、status_bar 三者垂直堆叠，line_nums 窄条独占一行。

### 0.2 期望布局结构

```
column (root, 1280x800):
  ├── editor      (background, 全屏)
  ├── editor_body (direction=row, flex_grow=1) ← 嵌套容器
  │   ├── line_nums (flex_basis=50)
  │   └── edit_area (flex_grow=1)
  └── status_bar  (flex_basis=24)
```

### 0.3 瓶颈定位

`_solve_layout`（app_factory.lua:379-390）将所有组件**平铺挂载**到 root children：

```lua
for _, comp in ipairs(reg.components) do
  if comp.layout then
    table.insert(root_spec.children, _build_layout_node(comp.name, comp.layout))
  end
end
```

每个组件的 `layout` 字段只包含自身尺寸属性（flex_grow/flex_basis），没有 `children`。

而 `_build_layout_node`（app_factory.lua:331-353）**已经支持递归 children**：
```lua
if layout_spec.children then
  for _, child_spec in ipairs(layout_spec.children) do
    assert(child_spec.name, "_build_layout_node: child layout node must have a name")
    table.insert(spec.children, _build_layout_node(child_spec.name, child_spec))
  end
end
```

layout_engine 的 `nebula_layout_collect` 也**已支持递归收集命名节点**。

**结论**：底层能力完备，瓶颈仅在 sugar 层——需要一种声明方式，让组件能表达"我属于某个容器"。

---

## 1. 设计约束——不违背核心哲学

### 公理 A：阶段封闭性（S0/S1/S2）

- ✅ 布局容器是编译期（S1）概念，`_solve_layout` 在 `nebula_app_end()` 时执行
- ✅ 嵌套容器声明也是 S1 数据（components 数组中的附加结构）
- ✅ 运行时（S2）只读取已解算好的绝对坐标，零运行时开销

### 公理 B：生命周期三层（L0/L1/L2）

- ✅ 容器节点不创建新 L0 管线、不占 L1 状态、不占 L2 帧内存
- ✅ 容器节点只在 L2 的 layout_results 中产生坐标数据，已被现有机制管理

### 公理 C：形即渲染

- ✅ 容器节点不是 Visual，没有管线签名，不参与 GPU 渲染
- ✅ 容器节点是纯布局拓扑，解决的是"子元素的 pos/size 如何计算"

### 三层 API 原则（P2 — 分层可逃逸）

- ✅ L0 Raw API（`nebula_app_set_root_layout` + `nebula_app_begin`）完全不受影响
- ✅ L1 Sugar API（`nebula_app`）获得新的可选字段
- ✅ 用户随时可以降级到 L0 手写嵌套布局，已验证可行（editor_with_lines_demo 用 row 方向根布局实现行号+编辑区并排）

### 正交可组合（P4）

- ✅ `layout.container` 是可选字段，省略时行为与当前完全一致（100% 向后兼容）
- ✅ 不强制绑定，用户可以在 components 内混合使用容器和非容器

### P5 — 糖与模板的边界

> "糖消除'从已有信息可确定性推导的机械重复'。应用层架构决策不属于糖的范畴。"

- ⚠️ **设计决策**：容器本身是"UI 布局组合"，属于应用层架构决策还是可推导的机械重复？
- **判定**：容器是**布局拓扑声明**——它只表达"这些组件应在同一容器中"，不引入新的行为逻辑。类似于 HTML 的 `<div style="display:flex">`，是声明式的结构描述，而非应用层逻辑。因此**属于糖的范畴**。

---

## 2. 方案设计

### 2.1 语法：`layout.container` 字段

在组件的 `layout` 中新增可选 `container` 字段，声明"此组件是布局容器，其子组件通过 `ref` 引用"：

```lua
## nebula_app("TextEditorApp", {
##   components = {
##     { name = "editor", type = "EditorBgVisual" },
##     { name = "editor_body", layout = {
##         direction = "row",
##         flex_grow = 1,
##         container = {
##           { ref = "line_nums" },
##           { ref = "edit_area" },
##         },
##       },
##     },
##     { name = "line_nums", type = "LineNumDenseVisual",
##       producer = "fill_line_nums", cell_w = 10.0, cell_h = 16.0,
##       max_chars = 250, layout = { flex_basis = 50 } },
##     { name = "edit_area", type = "EditAreaDenseVisual",
##       producer = "fill_edit_area", cell_w = 10.0, cell_h = 16.0,
##       max_chars = 6000, layout = { flex_grow = 1 } },
##     { name = "status_bar", type = "StatusDenseVisual",
##       producer = "fill_status_bar", cell_w = 10.0, cell_h = 16.0,
##       max_chars = 200, layout = { flex_basis = 24 } },
##   },
## })
```

**设计要点**：

1. **`editor_body` 没有 `type`**——它是一个纯布局容器，不是 Visual，不产生 GPU 管线
2. **`container` 是一个 ref 数组**——每个 entry 的 `ref` 指向同 components 数组中的 `name`
3. **被引用的组件仍然是独立的 component**——它们的 layout 仍然定义在自身上，容器只负责拓扑分组
4. **容器可以嵌套**——`container` 内的 ref 可以指向另一个带 `container` 的节点

### 2.2 编译期转换逻辑

在 `_solve_layout` 中，改造当前的"平铺挂载"为"先构建拓扑，再解算"：

```
Step 1: 收集所有组件 → comp_map[name] = comp
Step 2: 标记哪些组件被 container 引用 → used_as_child[name] = true
Step 3: 构建 root.children:
  a. 对每个组件：
     - 如果有 layout.container → 构建容器节点，递归解析 ref
     - 如果被其他容器引用 → 跳过（不直接挂载到 root）
     - 否则 → 按当前逻辑挂载到 root
```

**伪代码**：

```lua
local function _solve_layout(reg)
  -- ... (root_spec 构建不变)

  local comp_map = {}
  for _, comp in ipairs(reg.components) do
    if comp.layout then comp_map[comp.name] = comp end
  end
  for _, dt in ipairs(reg.dense_texts) do
    if dt.layout then comp_map[dt.name] = dt end
  end

  -- 标记被 container 引用的组件
  local used_as_child = {}
  for _, comp in pairs(comp_map) do
    if comp.layout and comp.layout.container then
      for _, child_ref in ipairs(comp.layout.container) do
        used_as_child[child_ref.ref] = true
      end
    end
  end

  -- 构建 root.children（排除被引用的组件）
  for name, comp in pairs(comp_map) do
    if not used_as_child[name] then
      if comp.layout.container then
        -- 构建容器节点（递归）
        table.insert(root_spec.children, _build_container_node(name, comp.layout, comp_map))
      else
        table.insert(root_spec.children, _build_layout_node(name, comp.layout))
      end
    end
  end

  -- ... (后续解算逻辑不变)
end

local function _build_container_node(name, layout_spec, comp_map)
  local spec = {
    name      = name,
    direction = layout_spec.direction,
    justify   = layout_spec.justify,
    align     = layout_spec.align,
    padding   = layout_spec.padding,
    gap       = layout_spec.gap,
    width     = layout_spec.width,
    height    = layout_spec.height,
    flex_grow  = layout_spec.flex_grow,
    flex_basis = layout_spec.flex_basis,
    children   = {},
  }
  for _, child_ref in ipairs(layout_spec.container) do
    local child_comp = comp_map[child_ref.ref]
    assert(child_comp, ("container ref '%s' not found"):format(child_ref.ref))
    if child_comp.layout.container then
      -- 嵌套容器
      table.insert(spec.children, _build_container_node(child_ref.ref, child_comp.layout, comp_map))
    else
      -- 普通叶子节点
      table.insert(spec.children, _build_layout_node(child_ref.ref, child_comp.layout))
    end
  end
  return nebula_layout_node(spec)
end
```

### 2.3 对 nebula_app sugar 的修改

在 `nebula_core.nelua` 的 `nebula_app()` 函数中，对 `container` 组件的特殊处理：

1. **不注册为 GPU 组件**——没有 `type` 字段的条目不调用 `nebula_app_register_component` 或 `nebula_app_register_dense_text`
2. **layout 字段原样传递**——`container` 作为 layout 的子字段，跟随 layout 一起存入 reg

在 `nebula_app` 中新增判断逻辑：

```lua
for _, c in ipairs(spec.components or {}) do
  local reg = nebula_registry[c.type]
  if not c.type then
    -- ★ 纯布局容器：不注册 GPU 组件，只在 layout 中记录
    assert(c.layout and c.layout.container,
      ("nebula_app: component '%s' has no type and no layout.container"):format(c.name))
    -- 注册为一个无 GPU 管线的布局占位
    nebula_app_register_layout_node(c.name, c.layout)
  else
    -- ... 现有逻辑不变
  end
end
```

**新增 app_factory.lua 函数**：

```lua
function nebula_app_register_layout_node(name, layout)
  assert(_current_app, "no app being declared")
  local reg = nebula_app_registry[_current_app]
  -- 存入一个专用的 layout_nodes 列表
  reg.layout_nodes = reg.layout_nodes or {}
  table.insert(reg.layout_nodes, { name = name, layout = layout })
end
```

### 2.4 对 _solve_layout 的完整改造

```lua
local function _solve_layout(reg)
  if not reg.root_layout then ... end

  local root_spec = { ... }  -- 不变

  -- 构建组件索引
  local comp_map = {}
  for _, comp in ipairs(reg.components) do
    if comp.layout then comp_map[comp.name] = comp end
  end
  for _, dt in ipairs(reg.dense_texts) do
    if dt.layout then comp_map[dt.name] = dt end
  end
  for _, ln in ipairs(reg.layout_nodes or {}) do
    comp_map[ln.name] = ln
  end

  -- 标记被引用的节点
  local used_as_child = {}
  for _, comp in pairs(comp_map) do
    if comp.layout and comp.layout.container then
      for _, child_ref in ipairs(comp.layout.container) do
        used_as_child[child_ref.ref] = true
      end
    end
  end

  -- 挂载到 root（排除被引用的）
  for name, comp in pairs(comp_map) do
    if not used_as_child[name] then
      if comp.layout.container then
        table.insert(root_spec.children, _build_container_node(name, comp.layout, comp_map))
      else
        table.insert(root_spec.children, _build_layout_node(name, comp.layout))
      end
    end
  end

  -- 后续解算完全不变...
end
```

### 2.5 容器节点的坐标注入

容器节点**不对应任何组件**（没有 Visual、没有 Context），所以不需要坐标注入。

`layout_results` 中会包含容器节点的坐标，但 `gen_app_update` 中注入坐标时，只注入 `reg.components` 和 `reg.dense_texts` 的结果——容器节点自动被跳过。

`layout_segments` 也只对有 layout_results[name] 且 name 存在于 components/dense_texts 的条目生成更新代码。

**结论**：坐标注入层完全不需要改动。

---

## 3. 修改文件清单

| 文件 | 修改内容 | 行数估计 |
|------|---------|---------|
| `src/derive/app_factory.lua` | 新增 `nebula_app_register_layout_node()`；修改 `_solve_layout` 从平铺改为拓扑感知；新增 `_build_container_node()` | +50 行 |
| `src/nebula_core.nelua` | `nebula_app()` 中对无 type 组件的容器识别和注册 | +15 行 |
| `tests/smoke_nested_layout.lua` | 冒烟测试 | +60 行 |

**不修改**：
- `src/derive/layout_engine.lua` — 已支持嵌套 children + flex_grow/flex_basis
- 任何 shader / renderer 代码
- 任何现有 demo（100% 向后兼容）

---

## 4. 回归与验证策略

### 4.1 冒烟测试（smoke_nested_layout.lua）

```
Part 1: nebula_app_register_layout_node 函数存在
Part 2: 带 container 的 nebula_app 声明编译成功
Part 3: _build_container_node 递归嵌套正确
Part 4: layout_results 中包含容器节点和叶子节点的坐标
Part 5: 容器节点不生成 GPU 管线代码
Part 6: 被引用的组件不直接挂载到 root
```

### 4.2 回归测试

```bash
bash tools/run_all_tests.sh  # 期望 71+ 全绿（70 现有 + 1 新增冒烟）
```

### 4.3 编译验证

```bash
cd /home/root721/nebula && ./build.sh text_editor_demo 2>&1
```

---

## 5. 向后兼容性保证

- `layout.container` 是**可选字段**，省略时 `_solve_layout` 的行为与当前**完全一致**
- 无 `type` 字段的组件条目是新增语法，不影响任何现有 demo
- `nebula_app_register_layout_node` 是新函数，不修改任何现有函数签名
- layout_engine 的 `nebula_layout_node` 不变——它已原生支持带 children 的 spec

---

## 6. 未来扩展

嵌套容器支持为以下场景铺平道路：

1. **工具栏 + 内容区**：`row{ toolbar(flex_basis=40), content(flex_grow=1) }`
2. **侧边栏 + 主区域**：`row{ sidebar(flex_basis=200), main(flex_grow=1) }`
3. **Split pane**：`row{ left(flex_grow=1), right(flex_grow=1) }`
4. **多层嵌套**：`column{ header, row{ sidebar, column{ content, footer } } }`

所有这些只需声明容器拓扑，不需要手写任何坐标计算。

---

## 7. 时序计划

1. **实现 app_factory.lua**（+50 行）—— `nebula_app_register_layout_node` + `_build_container_node` + `_solve_layout` 改造
2. **实现 nebula_core.nelua**（+15 行）—— `nebula_app()` 容器识别
3. **冒烟测试**（+60 行）—— `smoke_nested_layout.lua`
4. **回归测试** —— 71/71 全绿
5. **text_editor_demo 重构** —— 使用新语法声明嵌套布局
6. **继续 Phase 4.8-S3**（状态栏 + 光标行高亮）—— 在嵌套布局基础上实现
