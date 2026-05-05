-- =============================================================================
-- smoke_nested_layout.lua
-- Nebula GUI Compiler — Phase 4.8-NL Smoke Test
--
-- 嵌套布局支持验证：
--   · nebula_app_register_layout_node 函数存在
--   · 带 container 的 nebula_app 声明可正确解析
--   · _build_container_node 递归嵌套正确
--   · layout_results 中包含容器和叶子节点的坐标
--   · 容器节点不生成 GPU 管线代码
--   · 被引用的组件不直接挂载到 root
--   · 100% 向后兼容：无 container 时行为不变
-- =============================================================================

local pass_count = 0
local fail_count = 0

local function check(desc, cond)
  if cond then
    pass_count = pass_count + 1
    print(("  [PASS] %s"):format(desc))
  else
    fail_count = fail_count + 1
    print(("  [FAIL] %s"):format(desc))
  end
end

local function approx(a, b, eps)
  eps = eps or 1.0
  return math.abs(a - b) <= eps
end

-- ---- 加载所需模块 ----
dofile("src/derive/layout_engine.lua")
dofile("src/derive/app_factory.lua")

-- =============================================================================
-- Part 1: API 存在性
-- =============================================================================
print("\n=== Part 1: API Existence ===")

check("nebula_app_register_layout_node is a function",
  type(nebula_app_register_layout_node) == "function")

check("nebula_app_begin is a function",
  type(nebula_app_begin) == "function")

check("nebula_app_end is a function",
  type(nebula_app_end) == "function")

check("nebula_app_registry is a table",
  type(nebula_app_registry) == "table")

-- =============================================================================
-- Part 2: 基础容器注册
-- =============================================================================
print("\n=== Part 2: Basic Container Registration ===")

-- 创建一个带容器的 App
nebula_registry = nebula_registry or {}
nebula_registry["CardVisual"] = { primitives = {} }
nebula_registry["InputVisual"] = { primitives = {} }

nebula_app_set_root_layout("ContainerApp", {
  direction = "column", width = 1280, height = 800,
})
nebula_app_begin("ContainerApp")

-- 注册标准组件
nebula_app_register_component("editor_bg", "CardVisual", {
  layout = { flex_grow = 1 },
})
-- 注册容器节点
nebula_app_register_layout_node("editor_body", {
  direction = "row",
  flex_grow = 1,
  container = {
    { ref = "line_nums" },
    { ref = "edit_area" },
  },
})
-- 注册被容器引用的组件
nebula_app_register_component("line_nums", "InputVisual", {
  layout = { flex_basis = 50 },
})
nebula_app_register_component("edit_area", "InputVisual", {
  layout = { flex_grow = 1 },
})
-- 注册不在容器中的组件
nebula_app_register_component("status_bar", "CardVisual", {
  layout = { flex_basis = 24 },
})

nebula_app_end()

local reg = nebula_app_registry["ContainerApp"]

check("ContainerApp registered",
  reg ~= nil)

check("layout_nodes has 1 entry",
  #reg.layout_nodes == 1)

check("layout_nodes[1].name == 'editor_body'",
  reg.layout_nodes[1].name == "editor_body")

check("layout_nodes[1].layout.container has 2 refs",
  #reg.layout_nodes[1].layout.container == 2)

check("container ref[1] = 'line_nums'",
  reg.layout_nodes[1].layout.container[1].ref == "line_nums")

check("container ref[2] = 'edit_area'",
  reg.layout_nodes[1].layout.container[2].ref == "edit_area")

-- =============================================================================
-- Part 3: 布局解算结果
-- =============================================================================
print("\n=== Part 3: Layout Results ===")

check("layout_results is not nil",
  reg.layout_results ~= nil)

-- editor_bg: flex_grow=1, 应占满除 status_bar 和 editor_body 之外的空间
local r_bg = reg.layout_results["editor_bg"]
check("editor_bg has layout result",
  r_bg ~= nil)

-- editor_body: direction=row, flex_grow=1
local r_body = reg.layout_results["editor_body"]
check("editor_body (container) has layout result",
  r_body ~= nil)

-- line_nums: flex_basis=50, 在 editor_body 内
local r_lnum = reg.layout_results["line_nums"]
check("line_nums has layout result",
  r_lnum ~= nil)

-- edit_area: flex_grow=1, 在 editor_body 内
local r_edit = reg.layout_results["edit_area"]
check("edit_area has layout result",
  r_edit ~= nil)

-- status_bar: flex_basis=24
local r_status = reg.layout_results["status_bar"]
check("status_bar has layout result",
  r_status ~= nil)

-- 验证 status_bar 在底部
if r_status then
  check("status_bar.h == 24",
    approx(r_status.h, 24))
  check("status_bar is at bottom (y + h ≈ 800)",
    approx(r_status.y + r_status.h, 800))
end

-- 验证 editor_body 和 status_bar 互不重叠
if r_body and r_status then
  check("editor_body.y + editor_body.h <= status_bar.y",
    r_body.y + r_body.h <= r_status.y + 1.0)
end

-- 验证 line_nums 和 edit_area 在同一行
if r_lnum and r_edit then
  check("line_nums.y ≈ edit_area.y (same row)",
    approx(r_lnum.y, r_edit.y))
  check("line_nums.w ≈ 50 (flex_basis)",
    approx(r_lnum.w, 50))
  check("line_nums.x + line_nums.w <= edit_area.x (side by side)",
    r_lnum.x + r_lnum.w <= r_edit.x + 1.0)
  check("edit_area.w > line_nums.w (flex_grow takes remaining space)",
    r_edit.w > r_lnum.w)
end

-- =============================================================================
-- Part 4: 容器节点不生成 GPU 管线
-- =============================================================================
print("\n=== Part 4: Container has no GPU pipeline ===")

-- type_groups 不应包含 editor_body
local has_body_pipeline = false
for vt, group in pairs(reg.type_groups) do
  for _, m in ipairs(group.members) do
    if m.name == "editor_body" then
      has_body_pipeline = true
    end
  end
end
check("editor_body NOT in type_groups",
  not has_body_pipeline)

-- components 不应包含 editor_body
local has_body_component = false
for _, comp in ipairs(reg.components) do
  if comp.name == "editor_body" then
    has_body_component = true
  end
end
check("editor_body NOT in components list",
  not has_body_component)

-- =============================================================================
-- Part 5: 生成代码不含容器节点的 GPU 代码
-- =============================================================================
print("\n=== Part 5: Generated code excludes container ===")

local source = nebula_app_generate("ContainerApp")
check("generated code is string",
  type(source) == "string")

check("generated code does NOT contain pipe_editor_body",
  source:find("pipe_editor_body") == nil)

check("generated code does NOT contain editor_body:update",
  source:find("editor_body:update") == nil)

check("generated code contains editor_bg:update",
  source:find("editor_bg:update") ~= nil)

check("generated code contains line_nums:update",
  source:find("line_nums:update") ~= nil)

check("generated code contains edit_area:update",
  source:find("edit_area:update") ~= nil)

check("generated code contains status_bar:update",
  source:find("status_bar:update") ~= nil)

-- =============================================================================
-- Part 6: 向后兼容——无 container 时行为不变
-- =============================================================================
print("\n=== Part 6: Backward Compatibility ===")

nebula_registry["BtnVisual"] = { primitives = {} }

nebula_app_set_root_layout("FlatApp", {
  direction = "column", width = 800, height = 600,
  justify = "center", align = "center",
})
nebula_app_begin("FlatApp")
nebula_app_register_component("card", "BtnVisual", {
  layout = { width = 360, height = 200 },
})
nebula_app_register_component("footer", "BtnVisual", {
  layout = { width = 360, height = 40 },
})
nebula_app_end()

local flat_reg = nebula_app_registry["FlatApp"]
check("FlatApp layout_results not nil",
  flat_reg.layout_results ~= nil)

local r_card = flat_reg.layout_results["card"]
check("card has layout result",
  r_card ~= nil)

local r_footer = flat_reg.layout_results["footer"]
check("footer has layout result",
  r_footer ~= nil)

check("FlatApp layout_nodes is empty",
  #flat_reg.layout_nodes == 0)

-- =============================================================================
-- Part 7: DenseText 组件也可被容器引用
-- =============================================================================
print("\n=== Part 7: DenseText in container ===")

nebula_registry["DenseVisual"] = { text_mode = "dense", primitives = {} }

nebula_app_set_root_layout("DenseContainerApp", {
  direction = "column", width = 1280, height = 800,
})
nebula_app_begin("DenseContainerApp")
nebula_app_register_layout_node("body_row", {
  direction = "row",
  flex_grow = 1,
  container = {
    { ref = "nums" },
    { ref = "content" },
  },
})
nebula_app_register_dense_text("nums", "DenseVisual", {
  max_chars = 200, cell_w = 10.0, cell_h = 16.0,
  producer = "fill_nums",
  layout = { flex_basis = 60 },
})
nebula_app_register_dense_text("content", "DenseVisual", {
  max_chars = 6000, cell_w = 10.0, cell_h = 16.0,
  producer = "fill_content",
  layout = { flex_grow = 1 },
})
nebula_app_end()

local dr = nebula_app_registry["DenseContainerApp"]
check("DenseContainerApp layout_results not nil",
  dr.layout_results ~= nil)

local r_nums = dr.layout_results["nums"]
local r_content = dr.layout_results["content"]
check("nums has layout result", r_nums ~= nil)
check("content has layout result", r_content ~= nil)

if r_nums and r_content then
  check("nums.w ≈ 60 (flex_basis)",
    approx(r_nums.w, 60))
  check("nums.y ≈ content.y (same row)",
    approx(r_nums.y, r_content.y))
  check("content.w > nums.w (flex_grow)",
    r_content.w > r_nums.w)
end

-- =============================================================================
-- Part 8: 嵌套容器递归
-- =============================================================================
print("\n=== Part 8: Nested container recursion ===")

nebula_registry["PanelVisual"] = { primitives = {} }

nebula_app_set_root_layout("NestedApp", {
  direction = "column", width = 1200, height = 800,
})
nebula_app_begin("NestedApp")
-- outer container: column
nebula_app_register_layout_node("outer", {
  direction = "column",
  flex_grow = 1,
  container = {
    { ref = "inner_row" },
    { ref = "bottom_panel" },
  },
})
-- inner container: row
nebula_app_register_layout_node("inner_row", {
  direction = "row",
  flex_grow = 1,
  container = {
    { ref = "sidebar" },
    { ref = "main_area" },
  },
})
nebula_app_register_component("sidebar", "PanelVisual", {
  layout = { flex_basis = 200 },
})
nebula_app_register_component("main_area", "PanelVisual", {
  layout = { flex_grow = 1 },
})
nebula_app_register_component("bottom_panel", "PanelVisual", {
  layout = { flex_basis = 100 },
})
nebula_app_end()

local nr = nebula_app_registry["NestedApp"]
check("NestedApp layout_results not nil",
  nr.layout_results ~= nil)

local r_sidebar = nr.layout_results["sidebar"]
local r_main = nr.layout_results["main_area"]
local r_bottom = nr.layout_results["bottom_panel"]

check("sidebar has layout result", r_sidebar ~= nil)
check("main_area has layout result", r_main ~= nil)
check("bottom_panel has layout result", r_bottom ~= nil)

if r_sidebar and r_main then
  check("sidebar.w ≈ 200 (flex_basis)",
    approx(r_sidebar.w, 200))
  check("sidebar.y ≈ main_area.y (same row in inner_row)",
    approx(r_sidebar.y, r_main.y))
  check("main_area.w > sidebar.w",
    r_main.w > r_sidebar.w)
end

if r_bottom then
  check("bottom_panel.h ≈ 100 (flex_basis)",
    approx(r_bottom.h, 100))
  check("bottom_panel at bottom (y + h ≈ 800)",
    approx(r_bottom.y + r_bottom.h, 800))
end

-- ---- 总结 ----
print("")
print(("--- smoke_nested_layout 结果: %d 通过, %d 失败 ---"):format(pass_count, fail_count))
if fail_count > 0 then
  os.exit(1)
end
