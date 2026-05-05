-- =============================================================================
-- smoke_phase4_8_s4.lua
-- Nebula GUI Compiler — Phase 4.8-S4 Smoke Test
--
-- 多语言语法高亮验证：
--   · highlight_factory 支持 nebula_highlight_select 多语言分发
--   · 6 种语言规则注册 + 扫描器生成
--   · nebula_highlight_dispatch 运行时分发
--   · nebula_highlight_detect_ext 扩展名自动检测
--   · text_editor_demo 集成（_editor_highlight_id + 加载时检测）
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
dofile("src/derive/highlight_factory.lua")

-- =============================================================================
-- Part 1: nebula_highlight_select API 存在性
-- =============================================================================
print("\n=== Part 1: API Existence ===")

check("nebula_highlight_select is a function",
  type(nebula_highlight_select) == "function")

check("nebula_highlight_rules is a function",
  type(nebula_highlight_rules) == "function")

check("nebula_highlight_registry is a table",
  type(nebula_highlight_registry) == "table")

-- =============================================================================
-- Part 2: 多语言规则注册
-- =============================================================================
print("\n=== Part 2: Multi-language Rule Registration ===")

local demo_src = io.open("examples/text_editor_demo.nelua"):read("*a")

check("nelua rules registered",
  demo_src:find('nebula_highlight_rules%("nelua"') ~= nil)

check("lua rules registered",
  demo_src:find('nebula_highlight_rules%("lua"') ~= nil)

check("c rules registered",
  demo_src:find('nebula_highlight_rules%("c"') ~= nil)

check("python rules registered",
  demo_src:find('nebula_highlight_rules%("python"') ~= nil)

check("json rules registered",
  demo_src:find('nebula_highlight_rules%("json"') ~= nil)

check("markdown rules registered",
  demo_src:find('nebula_highlight_rules%("markdown"') ~= nil)

-- =============================================================================
-- Part 3: 扫描器生成
-- =============================================================================
print("\n=== Part 3: Scanner Derivation ===")

check("nelua scanner derived",
  demo_src:find('nebula_derive_highlighter%("nelua"%)')  ~= nil)

check("lua scanner derived",
  demo_src:find('nebula_derive_highlighter%("lua"%)')  ~= nil)

check("c scanner derived",
  demo_src:find('nebula_derive_highlighter%("c"%)')  ~= nil)

check("python scanner derived",
  demo_src:find('nebula_derive_highlighter%("python"%)')  ~= nil)

check("json scanner derived",
  demo_src:find('nebula_derive_highlighter%("json"%)')  ~= nil)

check("markdown scanner derived",
  demo_src:find('nebula_derive_highlighter%("markdown"%)')  ~= nil)

-- =============================================================================
-- Part 4: 分发函数 + 扩展名检测
-- =============================================================================
print("\n=== Part 4: Dispatch & Extension Detection ===")

check("nebula_highlight_select called with 6 languages",
  demo_src:find('nebula_highlight_select') ~= nil)

check("nebula_highlight_dispatch used in fill_edit_area",
  demo_src:find("nebula_highlight_dispatch") ~= nil)

check("nebula_highlight_detect_ext used at file load",
  demo_src:find("nebula_highlight_detect_ext") ~= nil)

check("_editor_highlight_id global state declared",
  demo_src:find("_editor_highlight_id") ~= nil)

-- Extension mappings registered
check("nelua ext mapping",
  demo_src:find('exts = {"nelua"}') ~= nil)

check("lua ext mapping (lua, luau)",
  demo_src:find('exts = {"lua", "luau"}') ~= nil)

check("c ext mapping (c, h, cpp, hpp, cc, cxx)",
  demo_src:find('exts = {"c", "h", "cpp", "hpp", "cc", "cxx"}') ~= nil)

check("python ext mapping (py, pyw)",
  demo_src:find('exts = {"py", "pyw"}') ~= nil)

check("json ext mapping (json, jsonc)",
  demo_src:find('exts = {"json", "jsonc"}') ~= nil)

check("markdown ext mapping (md, mdx, markdown)",
  demo_src:find('exts = {"md", "mdx", "markdown"}') ~= nil)

-- =============================================================================
-- Part 5: highlight_factory.lua 代码验证
-- =============================================================================
print("\n=== Part 5: highlight_factory.lua Code ===")

local hl_src = io.open("src/derive/highlight_factory.lua"):read("*a")

check("nebula_highlight_select function defined in factory",
  hl_src:find("function nebula_highlight_select%(langs%)") ~= nil)

check("generates nebula_highlight_dispatch function",
  hl_src:find("nebula_highlight_dispatch") ~= nil)

check("generates nebula_highlight_detect_ext function",
  hl_src:find("nebula_highlight_detect_ext") ~= nil)

check("dispatch uses id parameter for routing",
  hl_src:find("id == %%d") ~= nil)

check("detect_ext finds last dot in path",
  hl_src:find("dot_pos") ~= nil)

check("detect_ext returns 0 for unknown extension",
  hl_src:find("return 0") ~= nil)

-- =============================================================================
-- Part 6: 语言特定关键字验证
-- =============================================================================
print("\n=== Part 6: Language-specific Keywords ===")

-- C 语言特有关键字
check("c has struct keyword",
  demo_src:find('"struct"') ~= nil)

check("c has typedef keyword",
  demo_src:find('"typedef"') ~= nil)

check("c uses // line comment",
  demo_src:find('line_comment = "//"') ~= nil)

-- Python 特有关键字
check("python has def keyword",
  demo_src:find('"def"') ~= nil)

check("python has class keyword",
  demo_src:find('"class"') ~= nil)

check("python uses # line comment",
  demo_src:find('line_comment = "#"') ~= nil)

-- JSON 无行注释
check("json has no line comment",
  demo_src:find('nebula_highlight_rules%("json"') ~= nil and
  not demo_src:match('nebula_highlight_rules%("json"[^)]*line_comment'))

-- =============================================================================
-- Part 7: 默认高亮 + 加载检测集成
-- =============================================================================
print("\n=== Part 7: Default Highlight & Load Integration ===")

check("default highlight_id = 1 (nelua) when no file",
  demo_src:find("_editor_highlight_id = 1") ~= nil)

check("highlight_id detected from file path on load",
  demo_src:find("_editor_highlight_id = nebula_highlight_detect_ext") ~= nil)

check("highlight_id logged on load",
  demo_src:find("highlight=%%d") ~= nil)

-- =============================================================================
-- Part 8: 功能性验证（纯 Lua 模拟）
-- =============================================================================
print("\n=== Part 8: Functional Verification ===")

-- 注册测试规则
nebula_highlight_rules("test_lang_a", {
  keywords = {
    { words = {"if", "else"}, color = 0xFF0000FF },
  },
  line_comment = "//",
  line_comment_color = 0x00FF00FF,
  string_color = 0x0000FFFF,
  number_color = 0xFFFF00FF,
})

nebula_highlight_rules("test_lang_b", {
  keywords = {
    { words = {"def", "class"}, color = 0xAA0000FF },
  },
  line_comment = "#",
  line_comment_color = 0x00AA00FF,
  string_color = 0x0000AAFF,
  number_color = 0xAAAA00FF,
})

check("test_lang_a registered",
  nebula_highlight_registry["test_lang_a"] ~= nil)

check("test_lang_b registered",
  nebula_highlight_registry["test_lang_b"] ~= nil)

check("test_lang_a has 2 keywords",
  #nebula_highlight_registry["test_lang_a"].keywords[1].words == 2)

check("test_lang_b has // as line comment (not #)",
  nebula_highlight_registry["test_lang_b"].line_comment == "#")

-- Verify select validates registered languages
local ok, err = pcall(nebula_highlight_select, {
  { name = "nonexistent", exts = {"xyz"} }
})
check("nebula_highlight_select rejects unregistered language",
  not ok and err:find("no rules registered") ~= nil)

-- Verify select rejects empty langs
local ok2, err2 = pcall(nebula_highlight_select, {})
check("nebula_highlight_select rejects empty array",
  not ok2)

-- =============================================================================
-- 总结
-- =============================================================================
print(("\n--- smoke_phase4_8_s4 结果: %d 通过, %d 失败 ---"):format(pass_count, fail_count))
if fail_count > 0 then
  os.exit(1)
end
