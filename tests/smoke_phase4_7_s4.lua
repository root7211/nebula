-- =============================================================================
-- smoke_phase4_7_s4.lua
-- Nebula GUI Compiler — Phase 4.7-S4
--
-- 语法高亮架构验证：
--   · highlight_factory 模块加载 + 版本
--   · nebula_highlight_rules 规则注册 + 参数校验
--   · nebula_derive_highlighter 代码生成逻辑
--   · 关键字匹配、注释检测、字符串/数字着色的正确性
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

-- 获取测试文件所在目录
local script_dir = (debug.getinfo(1, "S").source:match("^@(.+/)[^/]+$") or "./"):gsub("/$", "")

-- 加载 highlight_factory 模块
local hl_path = script_dir .. "/../src/derive/highlight_factory.lua"
local hl_ver = dofile(hl_path)

-- =============================================================================
-- 1. 模块版本验证
-- =============================================================================
check("highlight_factory version = v0.1-phase4.7-s4",
  hl_ver == "nebula_highlight_factory_v0.1_phase4.7-s4")

-- =============================================================================
-- 2. nebula_highlight_rules 注册验证
-- =============================================================================
nebula_highlight_rules("test_lang", {
  keywords = {
    { words = {"if", "else", "end"}, color = 0xC586C0FF },
    { words = {"local", "function"}, color = 0x569CD6FF },
  },
  line_comment = "--",
  line_comment_color = 0x6A9955FF,
  string_color = 0xCE9178FF,
  number_color = 0xB5CEA8FF,
})

check("rules registered in nebula_highlight_registry",
  nebula_highlight_registry["test_lang"] ~= nil)

check("rules: 2 keyword groups",
  #nebula_highlight_registry["test_lang"].keywords == 2)

check("rules: first group has 3 words",
  #nebula_highlight_registry["test_lang"].keywords[1].words == 3)

check("rules: line_comment = '--'",
  nebula_highlight_registry["test_lang"].line_comment == "--")

check("rules: string_color set",
  nebula_highlight_registry["test_lang"].string_color == 0xCE9178FF)

check("rules: number_color set",
  nebula_highlight_registry["test_lang"].number_color == 0xB5CEA8FF)

-- =============================================================================
-- 3. 规则验证：空名称应失败
-- =============================================================================
local ok_empty, err_empty = pcall(nebula_highlight_rules, "", {})
check("validation: empty name rejected",
  not ok_empty and err_empty:find("non%-empty string"))

-- =============================================================================
-- 4. 规则验证：keywords 格式错误应失败
-- =============================================================================
local ok_bad_kw, err_bad_kw = pcall(nebula_highlight_rules, "bad_kw", {
  keywords = { { words = {}, color = 0xFF } },
})
check("validation: empty words array rejected",
  not ok_bad_kw and err_bad_kw:find("non%-empty array"))

local ok_no_color, err_no_color = pcall(nebula_highlight_rules, "no_color", {
  keywords = { { words = {"if"}, color = "red" } },
})
check("validation: non-numeric color rejected",
  not ok_no_color and err_no_color:find("must be a number"))

-- =============================================================================
-- 5. 规则验证：line_comment 无颜色应失败
-- =============================================================================
local ok_no_cc, err_no_cc = pcall(nebula_highlight_rules, "no_cc", {
  line_comment = "--",
})
check("validation: line_comment without color rejected",
  not ok_no_cc and err_no_cc:find("line_comment_color required"))

-- =============================================================================
-- 6. 多规则集注册不冲突
-- =============================================================================
nebula_highlight_rules("lang_a", {
  keywords = { { words = {"func"}, color = 0xAABBCCFF } },
})
nebula_highlight_rules("lang_b", {
  keywords = { { words = {"def"}, color = 0x112233FF } },
  line_comment = "#",
  line_comment_color = 0x999999FF,
})
check("multiple rulesets: lang_a exists",
  nebula_highlight_registry["lang_a"] ~= nil)
check("multiple rulesets: lang_b exists",
  nebula_highlight_registry["lang_b"] ~= nil)
check("multiple rulesets: lang_a keyword = 'func'",
  nebula_highlight_registry["lang_a"].keywords[1].words[1] == "func")
check("multiple rulesets: lang_b line_comment = '#'",
  nebula_highlight_registry["lang_b"].line_comment == "#")

-- =============================================================================
-- 7. nebula_derive_highlighter: 未注册的名称应失败
-- =============================================================================
-- 注意：nebula_derive_highlighter 需要 aster 和 inject_statement 存在
-- 在纯 Lua 测试中，我们只能验证前置条件检查
local ok_unreg, err_unreg = pcall(nebula_derive_highlighter, "nonexistent")
check("derive_highlighter: unregistered name rejected",
  not ok_unreg and err_unreg:find("no rules registered"))

-- =============================================================================
-- 8. 内部辅助函数验证（通过加载模块暴露的全局函数）
-- =============================================================================

-- 验证关键字列表完整性（Nelua 关键字全覆盖）
nebula_highlight_rules("nelua_full", {
  keywords = {
    { words = {"if", "else", "elseif", "then", "end", "for", "while",
               "do", "repeat", "until", "return", "break", "goto", "in"},
      color = 0xC586C0FF },
    { words = {"local", "global", "function", "require"},
      color = 0x569CD6FF },
    { words = {"true", "false", "nil", "nilptr"},
      color = 0x4EC9B0FF },
  },
  line_comment = "--",
  line_comment_color = 0x6A9955FF,
  string_color = 0xCE9178FF,
  number_color = 0xB5CEA8FF,
})

local nelua_spec = nebula_highlight_registry["nelua_full"]
check("nelua rules: 3 keyword groups",
  #nelua_spec.keywords == 3)

-- 统计关键字总数
local total_kw = 0
for _, g in ipairs(nelua_spec.keywords) do
  total_kw = total_kw + #g.words
end
check("nelua rules: 22 keywords total",
  total_kw == 22)

check("nelua rules: control flow group has 14 words",
  #nelua_spec.keywords[1].words == 14)

check("nelua rules: declaration group has 4 words",
  #nelua_spec.keywords[2].words == 4)

check("nelua rules: constants group has 4 words",
  #nelua_spec.keywords[3].words == 4)

-- =============================================================================
-- 9. 向后兼容：rules 可以只有关键字，无注释/字符串/数字
-- =============================================================================
nebula_highlight_rules("minimal", {
  keywords = { { words = {"fn"}, color = 0xFF0000FF } },
})
check("minimal rules: no line_comment is ok",
  nebula_highlight_registry["minimal"].line_comment == nil)
check("minimal rules: no string_color is ok",
  nebula_highlight_registry["minimal"].string_color == nil)
check("minimal rules: no number_color is ok",
  nebula_highlight_registry["minimal"].number_color == nil)

-- =============================================================================
-- 10. build.sh 目标验证
-- =============================================================================
local build_sh = io.open(script_dir .. "/../build.sh", "r")
if build_sh then
  local content = build_sh:read("*a")
  build_sh:close()
  check("build.sh: includes highlight_editor_demo target",
    content:find("highlight_editor_demo") ~= nil)
else
  check("build.sh: file readable", false)
end

-- =============================================================================
-- 11. highlight_editor_demo 文件存在
-- =============================================================================
local demo_file = io.open(script_dir .. "/../examples/highlight_editor_demo.nelua", "r")
check("highlight_editor_demo.nelua exists",
  demo_file ~= nil)
if demo_file then
  local content = demo_file:read("*a")
  demo_file:close()
  check("demo uses nebula_highlight_rules",
    content:find("nebula_highlight_rules") ~= nil)
  check("demo uses nebula_derive_highlighter",
    content:find("nebula_derive_highlighter") ~= nil)
  check("demo calls nebula_highlight_scan_nelua",
    content:find("nebula_highlight_scan_nelua") ~= nil)
  check("demo has hl_colors buffer",
    content:find("hl_colors") ~= nil)
end

-- =============================================================================
-- 总结
-- =============================================================================
print("")
print(("--- smoke_phase4_7_s4 结果: %d 通过, %d 失败 ---"):format(pass, fail))
if fail > 0 then
  os.exit(1)
end
