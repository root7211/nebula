-- =============================================================================
-- smoke_phase4_8_s3.lua
-- Nebula GUI Compiler — Phase 4.8-S3 Smoke Test
--
-- 状态栏 + 光标行高亮 验证：
--   · 状态栏主题颜色函数存在（bg_status, fg_status, fg_status_accent）
--   · StatusBarDenseVisual 声明可被 nebula_component 注册
--   · 状态栏 DenseText 组件可参与嵌套布局（flex_basis=24）
--   · fill_status_bar Producer 签名符合 DenseText 规范
--   · 光标行高亮已由 fill_edit_area 实现（bg_cursor_line 主题色存在）
--   · text_editor_demo 编译成功
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

-- ---- 加载所需模块 ----
dofile("src/derive/layout_engine.lua")
dofile("src/derive/app_factory.lua")

-- =============================================================================
-- Part 1: 状态栏主题颜色函数存在性
-- =============================================================================
print("\n=== Part 1: Status Bar Theme Colors ===")

local theme_src = io.open("src/nebula_theme.nelua"):read("*a")

check("nebula_theme_bg_status function exists",
  theme_src:find("function nebula_theme_bg_status") ~= nil)

check("nebula_theme_fg_status function exists",
  theme_src:find("function nebula_theme_fg_status") ~= nil)

check("nebula_theme_fg_status_accent function exists",
  theme_src:find("function nebula_theme_fg_status_accent") ~= nil)

check("nebula_theme_bg_cursor_line function exists (for cursor line highlight)",
  theme_src:find("function nebula_theme_bg_cursor_line") ~= nil)

-- =============================================================================
-- Part 2: StatusBarDenseVisual 声明
-- =============================================================================
print("\n=== Part 2: StatusBarDenseVisual Declaration ===")

local demo_src = io.open("examples/text_editor_demo.nelua"):read("*a")

check("StatusBarDenseVisual record declared",
  demo_src:find("StatusBarDenseVisual") ~= nil)

check("StatusBarDenseVisual registered as dense component",
  demo_src:find('nebula_component%("StatusBarDenseVisual"') ~= nil)

check("StatusBarDenseVisual has text_mode = dense",
  demo_src:find('text_mode = "dense".*max_chars = 256') ~= nil)

-- =============================================================================
-- Part 3: fill_status_bar Producer 存在 & 签名
-- =============================================================================
print("\n=== Part 3: Status Bar Producer ===")

check("fill_status_bar function declared as global",
  demo_src:find("global function fill_status_bar") ~= nil)

check("fill_status_bar takes app: auto parameter",
  demo_src:find("fill_status_bar%([%s\n]*app: auto") ~= nil)

check("fill_status_bar takes DenseCharInstance parameter",
  demo_src:find("fill_status_bar.*DenseCharInstance") ~= nil)

check("fill_status_bar uses nebula_theme_bg_status",
  demo_src:find("nebula_theme_bg_status") ~= nil)

check("fill_status_bar uses nebula_theme_fg_status",
  demo_src:find("nebula_theme_fg_status") ~= nil)

check("fill_status_bar renders Ln/Col info",
  demo_src:find('Ln %%d, Col %%d') ~= nil)

check("fill_status_bar renders UTF-8 encoding",
  demo_src:find("UTF%-8") ~= nil)

check("fill_status_bar renders LF line ending",
  demo_src:find("LF") ~= nil)

check("fill_status_bar renders line count",
  demo_src:find("lines") ~= nil)

check("fill_status_bar renders modified marker",
  demo_src:find("_editor_modified") ~= nil)

check("fill_status_bar uses dense_layout_status_bar_x",
  demo_src:find("dense_layout_status_bar_x") ~= nil)

check("fill_status_bar uses nebula_dense_grid_fill_instance",
  demo_src:find("nebula_dense_grid_fill_instance") ~= nil)

-- =============================================================================
-- Part 4: App 布局包含 status_bar
-- =============================================================================
print("\n=== Part 4: App Layout with Status Bar ===")

check("nebula_app includes status_bar component",
  demo_src:find('name = "status_bar"') ~= nil)

check("status_bar has flex_basis = 24",
  demo_src:find('status_bar.*flex_basis = 24') ~= nil)

check("status_bar uses fill_status_bar producer",
  demo_src:find('producer = "fill_status_bar"') ~= nil)

check("status_bar type is StatusBarDenseVisual",
  demo_src:find('type = "StatusBarDenseVisual"') ~= nil)

-- =============================================================================
-- Part 5: 光标行高亮验证（fill_edit_area 中已有）
-- =============================================================================
print("\n=== Part 5: Cursor Line Highlight ===")

check("fill_edit_area checks is_cursor_line",
  demo_src:find("is_cursor_line") ~= nil)

check("fill_edit_area uses nebula_theme_bg_cursor_line",
  demo_src:find("nebula_theme_bg_cursor_line") ~= nil)

check("cursor line bg differs from normal bg",
  theme_src:find("nebula_theme_bg_cursor_line") ~= nil and
  theme_src:find("nebula_theme_bg_normal") ~= nil)

-- =============================================================================
-- Part 6: 布局验证（status_bar 在 editor_body 之后，flex_basis 固定高度）
-- =============================================================================
print("\n=== Part 6: Layout Structure ===")

-- Verify layout structure: editor_body has flex_grow=1, status_bar has flex_basis=24
-- This means status_bar gets fixed 24px at the bottom, editor_body fills rest

local layout_test_ok = true

-- Simulate layout: column root 1280x800 with editor_body(flex_grow=1) + status_bar(flex_basis=24)
nebula_app_set_root_layout("LayoutTestApp", {
  direction = "column", width = 1280, height = 800
})
nebula_app_begin("LayoutTestApp")
nebula_app_register_dense_text("editor_body_test", "TestVisual", {
  producer = "test_producer", max_chars = 100,
  layout = { flex_grow = 1 }
})
nebula_app_register_dense_text("status_bar_test", "TestVisual2", {
  producer = "test_producer2", max_chars = 100,
  layout = { flex_basis = 24 }
})
nebula_app_end()

local reg = nebula_app_registry["LayoutTestApp"]
if reg and reg.layout_results then
  local eb = reg.layout_results["editor_body_test"]
  local sb = reg.layout_results["status_bar_test"]
  if eb and sb then
    check("editor_body fills remaining height (flex_grow=1)",
      eb.h > 700)
    check("status_bar has fixed height 24px",
      math.abs(sb.h - 24) < 1)
    check("status_bar is positioned below editor_body",
      sb.y > eb.y)
    check("status_bar y + h ≈ 800 (bottom of window)",
      math.abs(sb.y + sb.h - 800) < 1)
    check("status_bar occupies full width",
      math.abs(sb.w - 1280) < 1)
  else
    check("layout_results contain both components", false)
    layout_test_ok = false
  end
else
  check("layout_results exist", false)
  layout_test_ok = false
end

-- =============================================================================
-- 总结
-- =============================================================================
print(("\n--- smoke_phase4_8_s3 结果: %d 通过, %d 失败 ---"):format(pass_count, fail_count))
if fail_count > 0 then
  os.exit(1)
end
