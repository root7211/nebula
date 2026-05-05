-- =============================================================================
-- smoke_phase4_7_s3.lua
-- Nebula GUI Compiler — Phase 4.7-S3
--
-- 行号显示 + 多列布局验证：
--   · layout_engine: flex_grow + flex_basis 支持
--   · app_factory: DenseText 参与 Flexbox 布局
--   · 多 DenseText 组件并存 + 独立布局坐标
--   · 行号栏（固定宽度）+ 编辑区（弹性宽度）并排
-- =============================================================================

local pass = 0
local fail = 0

local function check(desc, cond)
  if cond then
    pass = pass + 1
    print("[PASS] " .. desc)
  else
    fail = fail + 1
    print("[FAIL] " .. desc)
  end
end

-- 浮点近似比较
local function approx(a, b, eps)
  eps = eps or 0.1
  return math.abs(a - b) < eps
end

-- 获取测试文件所在目录
local script_dir = (debug.getinfo(1, "S").source:match("^@(.+/)[^/]+$") or "./"):gsub("/$", "")

-- 加载依赖模块
local layout_path = script_dir .. "/../src/derive/layout_engine.lua"
local layout_ver = dofile(layout_path)

local factory_path = script_dir .. "/../src/derive/app_factory.lua"
local factory_ver = dofile(factory_path)

-- =============================================================================
-- 1. 模块版本验证
-- =============================================================================
check("layout_engine version >= v0.3 (Phase 4.7-S3)",
  layout_ver and layout_ver and (layout_ver:find("v0.3") ~= nil or layout_ver:find("v0.4") ~= nil))

check("app_factory version >= v0.9 (Phase 4.7-S3)",
  factory_ver and factory_ver and (factory_ver:find("v0.9") ~= nil or factory_ver:find("v0.10") ~= nil))

-- =============================================================================
-- 2. flex_basis: 固定宽度列
-- =============================================================================
local root_fb = nebula_layout_node({
  name = "_root",
  direction = "row",
  width = 800,
  height = 600,
  children = {
    nebula_layout_node({ name = "linenum", flex_basis = 60 }),
    nebula_layout_node({ name = "editor", flex_basis = 740 }),
  },
})
nebula_layout_solve(root_fb, 800, 600)
local r_fb = nebula_layout_collect(root_fb)

check("flex_basis: linenum x = 0",
  r_fb.linenum and approx(r_fb.linenum.x, 0))
check("flex_basis: linenum w = 60",
  r_fb.linenum and approx(r_fb.linenum.w, 60))
check("flex_basis: editor x = 60",
  r_fb.editor and approx(r_fb.editor.x, 60))
check("flex_basis: editor w = 740",
  r_fb.editor and approx(r_fb.editor.w, 740))
check("flex_basis: both h = 600 (cross-axis stretch)",
  r_fb.linenum and approx(r_fb.linenum.h, 600) and
  r_fb.editor  and approx(r_fb.editor.h, 600))

-- =============================================================================
-- 3. flex_grow: 弹性增长
-- =============================================================================
local root_fg = nebula_layout_node({
  name = "_root",
  direction = "row",
  width = 1000,
  height = 600,
  children = {
    nebula_layout_node({ name = "sidebar", flex_basis = 100 }),
    nebula_layout_node({ name = "content", flex_grow = 1 }),
  },
})
nebula_layout_solve(root_fg, 1000, 600)
local r_fg = nebula_layout_collect(root_fg)

check("flex_grow: sidebar w = 100 (fixed)",
  r_fg.sidebar and approx(r_fg.sidebar.w, 100))
check("flex_grow: content w = 900 (fills remaining)",
  r_fg.content and approx(r_fg.content.w, 900))
check("flex_grow: content x = 100",
  r_fg.content and approx(r_fg.content.x, 100))

-- =============================================================================
-- 4. flex_grow 多元素比例分配
-- =============================================================================
local root_multi = nebula_layout_node({
  name = "_root",
  direction = "row",
  width = 600,
  height = 400,
  children = {
    nebula_layout_node({ name = "a", flex_grow = 1 }),
    nebula_layout_node({ name = "b", flex_grow = 2 }),
    nebula_layout_node({ name = "c", flex_grow = 3 }),
  },
})
nebula_layout_solve(root_multi, 600, 400)
local r_multi = nebula_layout_collect(root_multi)

check("flex_grow ratio: a.w = 100 (1/6)",
  r_multi.a and approx(r_multi.a.w, 100))
check("flex_grow ratio: b.w = 200 (2/6)",
  r_multi.b and approx(r_multi.b.w, 200))
check("flex_grow ratio: c.w = 300 (3/6)",
  r_multi.c and approx(r_multi.c.w, 300))
check("flex_grow ratio: b.x = 100",
  r_multi.b and approx(r_multi.b.x, 100))
check("flex_grow ratio: c.x = 300",
  r_multi.c and approx(r_multi.c.x, 300))

-- =============================================================================
-- 5. flex_basis + flex_grow 组合（行号栏 + 编辑区模式）
-- =============================================================================
local root_combo = nebula_layout_node({
  name = "_root",
  direction = "row",
  width = 1200,
  height = 800,
  children = {
    nebula_layout_node({ name = "linenum", flex_basis = 50 }),
    nebula_layout_node({ name = "editor", flex_grow = 1 }),
  },
})
nebula_layout_solve(root_combo, 1200, 800)
local r_combo = nebula_layout_collect(root_combo)

check("combo: linenum.w = 50 (flex_basis, no grow)",
  r_combo.linenum and approx(r_combo.linenum.w, 50))
check("combo: editor.w = 1150 (absorbs remaining space)",
  r_combo.editor and approx(r_combo.editor.w, 1150))
check("combo: editor.x = 50",
  r_combo.editor and approx(r_combo.editor.x, 50))

-- =============================================================================
-- 6. column 方向的 flex_basis + flex_grow
-- =============================================================================
local root_col = nebula_layout_node({
  name = "_root",
  direction = "column",
  width = 800,
  height = 600,
  children = {
    nebula_layout_node({ name = "header", flex_basis = 50 }),
    nebula_layout_node({ name = "body", flex_grow = 1 }),
  },
})
nebula_layout_solve(root_col, 800, 600)
local r_col = nebula_layout_collect(root_col)

check("column flex_basis: header.h = 50",
  r_col.header and approx(r_col.header.h, 50))
check("column flex_grow: body.h = 550",
  r_col.body and approx(r_col.body.h, 550))
check("column flex_grow: body.y = 50",
  r_col.body and approx(r_col.body.y, 50))

-- =============================================================================
-- 7. app_factory: DenseText layout 注册
-- =============================================================================
nebula_app_begin("TestLineNumApp")
nebula_app_register_dense_text("dt_linenum", "DenseTextVisual", {
  max_chars = 2000,
  cell_w = 8.0,
  cell_h = 16.0,
  producer = "fill_linenum",
  layout = { flex_basis = 60 },
})
nebula_app_register_dense_text("dt_editor", "DenseTextVisual", {
  max_chars = 6000,
  cell_w = 10.0,
  cell_h = 16.0,
  producer = "fill_editor",
  layout = { flex_grow = 1 },
})
nebula_app_end()

local reg_ln = nebula_app_registry["TestLineNumApp"]
check("dense_text layout: linenum has layout",
  reg_ln.dense_texts[1].layout ~= nil)
check("dense_text layout: linenum flex_basis = 60",
  reg_ln.dense_texts[1].layout.flex_basis == 60)
check("dense_text layout: editor has layout",
  reg_ln.dense_texts[2].layout ~= nil)
check("dense_text layout: editor flex_grow = 1",
  reg_ln.dense_texts[2].layout.flex_grow == 1)

-- =============================================================================
-- 8. app_factory: DenseText + component 混合布局
-- =============================================================================
nebula_app_begin("TestMixedLayoutApp")
nebula_app_set_root_layout("TestMixedLayoutApp", {
  direction = "row",
  width = 1000,
  height = 600,
})
nebula_app_register_dense_text("dt_nums", "DenseTextVisual", {
  max_chars = 1000,
  producer = "fill_nums",
  layout = { flex_basis = 80 },
})
nebula_app_register_dense_text("dt_code", "DenseTextVisual", {
  max_chars = 6000,
  producer = "fill_code",
  layout = { flex_grow = 1 },
})
nebula_app_end()

local reg_ml = nebula_app_registry["TestMixedLayoutApp"]
check("mixed layout: root_layout set",
  reg_ml.root_layout ~= nil)
check("mixed layout: root_layout direction = row",
  reg_ml.root_layout.direction == "row")
check("mixed layout: layout_results populated",
  reg_ml.layout_results ~= nil)
check("mixed layout: dt_nums in layout_results",
  reg_ml.layout_results and reg_ml.layout_results["dt_nums"] ~= nil)
check("mixed layout: dt_code in layout_results",
  reg_ml.layout_results and reg_ml.layout_results["dt_code"] ~= nil)

-- 验证布局坐标
if reg_ml.layout_results then
  local r_nums = reg_ml.layout_results["dt_nums"]
  local r_code = reg_ml.layout_results["dt_code"]
  check("mixed layout: dt_nums.x = 0",
    r_nums and approx(r_nums.x, 0))
  check("mixed layout: dt_nums.w = 80 (flex_basis)",
    r_nums and approx(r_nums.w, 80))
  check("mixed layout: dt_code.x = 80",
    r_code and approx(r_code.x, 80))
  check("mixed layout: dt_code.w = 920 (flex_grow fills remaining)",
    r_code and approx(r_code.w, 920))
  check("mixed layout: both h = 600 (cross-axis)",
    r_nums and approx(r_nums.h, 600) and
    r_code and approx(r_code.h, 600))
end

-- =============================================================================
-- 9. DenseText without layout 保持向后兼容
-- =============================================================================
nebula_app_begin("TestNoLayoutDense")
nebula_app_register_dense_text("dt_plain", "DenseTextVisual", {
  producer = "fill_plain",
})
nebula_app_end()

local reg_nl = nebula_app_registry["TestNoLayoutDense"]
check("no layout: dense_text registered",
  #reg_nl.dense_texts == 1)
check("no layout: layout field is nil",
  reg_nl.dense_texts[1].layout == nil)

-- =============================================================================
-- 10. gap + padding + flex_basis + flex_grow
-- =============================================================================
local root_gap = nebula_layout_node({
  name = "_root",
  direction = "row",
  width = 500,
  height = 300,
  gap = 10,
  padding = 20,
  children = {
    nebula_layout_node({ name = "left", flex_basis = 60 }),
    nebula_layout_node({ name = "right", flex_grow = 1 }),
  },
})
nebula_layout_solve(root_gap, 500, 300)
local r_gap = nebula_layout_collect(root_gap)

-- 可用宽度 = 500 - 20*2 = 460, gap = 10
-- left = 60, right = 460 - 60 - 10 = 390
check("gap+padding: left.x = 20 (padding.left)",
  r_gap.left and approx(r_gap.left.x, 20))
check("gap+padding: left.w = 60",
  r_gap.left and approx(r_gap.left.w, 60))
check("gap+padding: right.x = 90 (20 + 60 + 10)",
  r_gap.right and approx(r_gap.right.x, 90))
check("gap+padding: right.w = 390",
  r_gap.right and approx(r_gap.right.w, 390))

-- =============================================================================
-- 总结
-- =============================================================================
print("")
print(("--- smoke_phase4_7_s3 结果: %d 通过, %d 失败 ---"):format(pass, fail))
if fail > 0 then
  os.exit(1)
end
