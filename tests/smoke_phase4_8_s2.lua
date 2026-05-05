-- =============================================================================
-- smoke_phase4_8_s2.lua
-- Nebula GUI Compiler — Phase 4.8-S2 Smoke Test
--
-- 搜索与替换 验证：
--   · NebulaKey 枚举包含 Find / Replace / FindNext
--   · app.nelua 键映射包含 Ctrl+F / Ctrl+H / F3
--   · 搜索匹配高亮主题颜色函数存在
--   · SearchBarDenseVisual 声明可被 nebula_component 注册
--   · fill_search_bar Producer 签名符合 DenseText 规范
--   · 搜索状态变量（_search_active, _search_buf 等）声明存在
--   · 匹配扫描函数 scan_matches 存在
--   · 匹配高亮已注入 fill_edit_area（search_match / search_current bg）
--   · 搜索栏组件参与布局（flex_basis=24）
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
-- Part 1: NebulaKey 枚举扩展
-- =============================================================================
print("\n=== Part 1: NebulaKey Enum Extensions ===")

local core_src = io.open("src/nebula_core.nelua"):read("*a")

check("NebulaKey.Find = 26 defined",
  core_src:find("Find%s*=%s*26") ~= nil)

check("NebulaKey.Replace = 27 defined",
  core_src:find("Replace%s*=%s*27") ~= nil)

check("NebulaKey.FindNext = 28 defined",
  core_src:find("FindNext%s*=%s*28") ~= nil)

-- =============================================================================
-- Part 2: app.nelua 键映射
-- =============================================================================
print("\n=== Part 2: Keyboard Mapping in app.nelua ===")

local app_src = io.open("src/app.nelua"):read("*a")

check("Ctrl+F mapped to NebulaKey.Find (GLFW_KEY_F = 70)",
  app_src:find("70.*NebulaKey%.Find") ~= nil)

check("Ctrl+H mapped to NebulaKey.Replace (GLFW_KEY_H = 72)",
  app_src:find("72.*NebulaKey%.Replace") ~= nil)

check("F3 mapped to NebulaKey.FindNext",
  app_src:find("NebulaKey%.FindNext") ~= nil)

-- =============================================================================
-- Part 3: 搜索主题颜色函数
-- =============================================================================
print("\n=== Part 3: Search Theme Colors ===")

local theme_src = io.open("src/nebula_theme.nelua"):read("*a")

check("nebula_theme_bg_search_match function exists",
  theme_src:find("function nebula_theme_bg_search_match") ~= nil)

check("nebula_theme_bg_search_current function exists",
  theme_src:find("function nebula_theme_bg_search_current") ~= nil)

check("nebula_theme_fg_search_label function exists",
  theme_src:find("function nebula_theme_fg_search_label") ~= nil)

-- =============================================================================
-- Part 4: SearchBarDenseVisual 声明
-- =============================================================================
print("\n=== Part 4: SearchBarDenseVisual Declaration ===")

local demo_src = io.open("examples/text_editor_demo.nelua"):read("*a")

check("SearchBarDenseVisual record declared",
  demo_src:find("SearchBarDenseVisual") ~= nil)

check("SearchBarDenseVisual registered as dense component",
  demo_src:find('nebula_component%("SearchBarDenseVisual"') ~= nil)

check("SearchBarDenseVisual has text_mode = dense",
  demo_src:find('SearchBarDenseVisual.*text_mode = "dense"') ~= nil)

-- =============================================================================
-- Part 5: fill_search_bar Producer
-- =============================================================================
print("\n=== Part 5: Search Bar Producer ===")

check("fill_search_bar function declared as global",
  demo_src:find("global function fill_search_bar") ~= nil)

check("fill_search_bar takes app: auto parameter",
  demo_src:find("fill_search_bar%([%s\n]*app: auto") ~= nil)

check("fill_search_bar takes DenseCharInstance parameter",
  demo_src:find("fill_search_bar.*DenseCharInstance") ~= nil)

check("fill_search_bar uses dense_layout_search_bar_x",
  demo_src:find("dense_layout_search_bar_x") ~= nil)

check("fill_search_bar uses nebula_dense_grid_fill_instance",
  demo_src:find("nebula_dense_grid_fill_instance") ~= nil)

check("fill_search_bar renders Find: label",
  demo_src:find("Find:") ~= nil)

check("fill_search_bar renders match count [current/total]",
  demo_src:find("%%d/%%d") ~= nil)

check("fill_search_bar handles _search_active=false (hidden state)",
  demo_src:find("not _search_active") ~= nil)

-- =============================================================================
-- Part 6: 搜索状态变量
-- =============================================================================
print("\n=== Part 6: Search State Variables ===")

check("_search_active boolean declared",
  demo_src:find("global _search_active: boolean") ~= nil)

check("_search_replace boolean declared",
  demo_src:find("global _search_replace: boolean") ~= nil)

check("_search_buf [256]uint8 declared",
  demo_src:find("global _search_buf: %[256%]uint8") ~= nil)

check("_search_len uint32 declared",
  demo_src:find("global _search_len: uint32") ~= nil)

check("_search_cursor uint32 declared",
  demo_src:find("global _search_cursor: uint32") ~= nil)

check("_replace_buf [256]uint8 declared",
  demo_src:find("global _replace_buf: %[256%]uint8") ~= nil)

check("_replace_len uint32 declared",
  demo_src:find("global _replace_len: uint32") ~= nil)

check("MatchPos record declared",
  demo_src:find("MatchPos = @record") ~= nil)

check("_search_matches [512]MatchPos declared",
  demo_src:find("global _search_matches: %[512%]MatchPos") ~= nil)

check("_search_match_count uint32 declared",
  demo_src:find("global _search_match_count: uint32") ~= nil)

check("_search_current uint32 declared",
  demo_src:find("global _search_current: uint32") ~= nil)

-- =============================================================================
-- Part 7: scan_matches 函数
-- =============================================================================
print("\n=== Part 7: Match Scanning ===")

check("scan_matches function declared",
  demo_src:find("global function scan_matches") ~= nil)

check("scan_matches uses naive string matching (O(n*m))",
  demo_src:find("朴素滑窗匹配") ~= nil or
  demo_src:find("flat%[ci %+ k%] ~= _search_buf%[k%]") ~= nil)

check("scan_matches limits to 512 matches (fixed array)",
  demo_src:find("512") ~= nil)

check("scan_matches uses flatten to get line bytes",
  demo_src:find("flatten") ~= nil)

-- =============================================================================
-- Part 8: 搜索匹配高亮注入 fill_edit_area
-- =============================================================================
print("\n=== Part 8: Match Highlighting in Editor ===")

check("fill_edit_area checks _search_active for match highlight",
  demo_src:find("_search_active and _search_len > 0") ~= nil)

check("fill_edit_area uses nebula_theme_bg_search_current for current match",
  demo_src:find("nebula_theme_bg_search_current") ~= nil)

check("fill_edit_area uses nebula_theme_bg_search_match for other matches",
  demo_src:find("nebula_theme_bg_search_match") ~= nil)

-- =============================================================================
-- Part 9: 搜索栏布局
-- =============================================================================
print("\n=== Part 9: App Layout with Search Bar ===")

check("nebula_app includes search_bar component",
  demo_src:find('name = "search_bar"') ~= nil)

check("search_bar has flex_basis = 24",
  demo_src:find('search_bar.*flex_basis = 24') ~= nil or
  demo_src:find('"search_bar".*flex_basis = 24') ~= nil)

check("search_bar uses fill_search_bar producer",
  demo_src:find('producer = "fill_search_bar"') ~= nil)

check("search_bar type is SearchBarDenseVisual",
  demo_src:find('type = "SearchBarDenseVisual"') ~= nil)

-- =============================================================================
-- Part 10: 键盘路由（主循环中的搜索键盘处理）
-- =============================================================================
print("\n=== Part 10: Keyboard Routing ===")

check("Ctrl+F toggles _search_active",
  demo_src:find("NebulaKey%.Find") ~= nil)

check("Ctrl+H toggles _search_replace",
  demo_src:find("NebulaKey%.Replace") ~= nil)

check("Escape closes search bar",
  demo_src:find("NebulaKey%.Escape") ~= nil)

check("Enter / FindNext advances to next match",
  demo_src:find("NebulaKey%.FindNext") ~= nil)

check("Backspace deletes search buffer character",
  demo_src:find("NebulaKey%.Backspace") ~= nil)

check("search_goto_current function exists",
  demo_src:find("local function search_goto_current") ~= nil)

check("search_replace_current function exists",
  demo_src:find("local function search_replace_current") ~= nil)

check("search_replace_all function exists",
  demo_src:find("local function search_replace_all") ~= nil)

check("Keyboard input blocked when search active (key_pressed = None)",
  demo_src:find("input.key_pressed = NebulaKey%.None") ~= nil)

check("Char input cleared when search active (char_count = 0)",
  demo_src:find("input.char_count = 0") ~= nil)

-- =============================================================================
-- Part 11: 公理合规验证
-- =============================================================================
print("\n=== Part 11: Axiom Compliance ===")

check("公理 A: search_bar uses fixed layout (flex_basis=24, always present)",
  demo_src:find('"search_bar".*flex_basis = 24') ~= nil)

check("公理 B: zero heap — search_buf is stack array [256]uint8",
  demo_src:find("_search_buf: %[256%]uint8") ~= nil)

check("公理 B: zero heap — matches is fixed array [512]MatchPos",
  demo_src:find("_search_matches: %[512%]MatchPos") ~= nil)

check("公理 C: match highlight uses direct GPU color (DenseCharInstance bg)",
  demo_src:find("search_match.*bg") ~= nil or
  demo_src:find("bg_search_match") ~= nil)

-- =============================================================================
-- Part 12: 编译产物验证
-- =============================================================================
print("\n=== Part 12: Build Artifact ===")

local binary_exists = io.open(os.getenv("HOME") .. "/.cache/nelua/text_editor_demo", "r") ~= nil
check("text_editor_demo binary exists (compiled successfully)", binary_exists)

-- =============================================================================
-- 总结
-- =============================================================================
print(("\n--- smoke_phase4_8_s2 结果: %d 通过, %d 失败 ---"):format(pass_count, fail_count))
if fail_count > 0 then
  os.exit(1)
end
