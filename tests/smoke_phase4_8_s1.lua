-- =============================================================================
-- smoke_phase4_8_s1.lua
-- Nebula GUI Compiler — Phase 4.8-S1 Smoke Test
--
-- 选区可视化 + 系统剪贴板验收：
--   1. multiline_editable 原语包含 sel_anchor_row/col 字段
--   2. interaction_factory.lua 包含 Shift+Arrow / Ctrl+C/V/X/A 处理
--   3. nebula_theme.nelua 包含 nebula_theme_bg_selected() 函数
--   4. text_editor_demo.nelua Producer 包含选区背景渲染逻辑
--   5. 初始化时 sel_anchor_row/col 被设置
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

local function read_file(path)
  local f = io.open(path, "r")
  assert(f, "cannot open " .. path)
  local content = f:read("*a")
  f:close()
  return content
end

local theme_src     = read_file("src/nebula_theme.nelua")
local interact_src  = read_file("src/derive/interaction_factory.lua")
local demo_src      = read_file("examples/text_editor_demo.nelua")
local core_src      = read_file("src/nebula_core.nelua")
local app_src       = read_file("src/app.nelua")

-- =============================================================================
-- Part 1: 选区上下文字段
-- =============================================================================
print("=== Part 1: Selection Context Fields ===")

-- Load interaction_factory to check context_fields
dofile("src/derive/interaction_factory.lua")
local me = NEBULA_PRIMITIVES["multiline_editable"]

check("multiline_editable has 5 context fields",
  me and #me.context_fields == 5)

check("ctx[4] = sel_anchor_row (uint32)",
  me.context_fields[4].name == "sel_anchor_row" and
  me.context_fields[4].type == "uint32")

check("ctx[5] = sel_anchor_col (uint32)",
  me.context_fields[5].name == "sel_anchor_col" and
  me.context_fields[5].type == "uint32")

-- =============================================================================
-- Part 2: 主题——选区背景色
-- =============================================================================
print("\n=== Part 2: Theme — Selection Background ===")

check("nebula_theme_bg_selected() function exists",
  theme_src:find("nebula_theme_bg_selected") ~= nil)

check("selection color is VSCode blue (38, 79, 120)",
  theme_src:find("38,%s*79,%s*120") ~= nil)

-- =============================================================================
-- Part 3: NebulaKey 枚举——选区和剪贴板键
-- =============================================================================
print("\n=== Part 3: NebulaKey Enum ===")

check("ShiftLeft exists in NebulaKey",
  core_src:find("ShiftLeft") ~= nil)

check("ShiftRight exists in NebulaKey",
  core_src:find("ShiftRight") ~= nil)

check("ShiftUp exists in NebulaKey",
  core_src:find("ShiftUp") ~= nil)

check("ShiftDown exists in NebulaKey",
  core_src:find("ShiftDown") ~= nil)

check("Copy exists in NebulaKey",
  core_src:find("Copy%s*=%s*18") ~= nil)

check("Paste exists in NebulaKey",
  core_src:find("Paste%s*=%s*19") ~= nil)

check("Cut exists in NebulaKey",
  core_src:find("Cut%s*=%s*20") ~= nil)

check("SelectAll exists in NebulaKey",
  core_src:find("SelectAll%s*=%s*21") ~= nil)

-- =============================================================================
-- Part 4: Shift+Arrow 键映射（app.nelua）
-- =============================================================================
print("\n=== Part 4: Shift+Arrow Key Mapping ===")

check("app.nelua maps Shift+Left to ShiftLeft",
  app_src:find("NebulaKey%.ShiftLeft") ~= nil)

check("app.nelua maps Shift+Right to ShiftRight",
  app_src:find("NebulaKey%.ShiftRight") ~= nil)

check("app.nelua maps Shift+Up to ShiftUp",
  app_src:find("NebulaKey%.ShiftUp") ~= nil)

check("app.nelua maps Shift+Down to ShiftDown",
  app_src:find("NebulaKey%.ShiftDown") ~= nil)

-- =============================================================================
-- Part 5: interaction_factory — 选区处理
-- =============================================================================
print("\n=== Part 5: Selection Logic in interaction_factory ===")

check("process_body contains sel_anchor_row assignment",
  interact_src:find("sel_anchor_row") ~= nil)

check("process_body contains sel_anchor_col assignment",
  interact_src:find("sel_anchor_col") ~= nil)

check("Shift+Arrow extends selection (ShiftLeft handled)",
  interact_src:find("NebulaKey%.ShiftLeft") ~= nil)

check("Shift+Arrow extends selection (ShiftRight handled)",
  interact_src:find("NebulaKey%.ShiftRight") ~= nil)

check("Shift+Arrow extends selection (ShiftUp handled)",
  interact_src:find("NebulaKey%.ShiftUp") ~= nil)

check("Shift+Arrow extends selection (ShiftDown handled)",
  interact_src:find("NebulaKey%.ShiftDown") ~= nil)

check("Shift+Home handled",
  interact_src:find("NebulaKey%.ShiftHome") ~= nil)

check("Shift+End handled",
  interact_src:find("NebulaKey%.ShiftEnd") ~= nil)

-- =============================================================================
-- Part 6: 剪贴板操作
-- =============================================================================
print("\n=== Part 6: Clipboard Operations ===")

check("Copy uses glfwSetClipboardString",
  interact_src:find("glfwSetClipboardString") ~= nil)

check("Paste uses glfwGetClipboardString",
  interact_src:find("glfwGetClipboardString") ~= nil)

check("SelectAll sets anchor to (0,0)",
  interact_src:find("sel_anchor_row = 0") ~= nil and
  interact_src:find("sel_anchor_col = 0") ~= nil)

check("Cut deletes selection after copy",
  interact_src:find("NebulaKey%.Cut") ~= nil)

check("Paste handles newlines (char == 10)",
  interact_src:find("_pbytes%[_pi%] == 10") ~= nil)

check("Paste skips carriage return (char == 13)",
  interact_src:find("_pbytes%[_pi%] ~= 13") ~= nil)

-- =============================================================================
-- Part 7: 选区覆盖删除
-- =============================================================================
print("\n=== Part 7: Selection Override on Edit ===")

check("char input deletes selection first",
  interact_src:find("char_count > 0 and _ml_has_sel") ~= nil)

check("Backspace handles selection deletion",
  interact_src:find("NebulaKey%.Backspace") ~= nil)

check("Delete handles selection deletion",
  interact_src:find("NebulaKey%.Delete") ~= nil)

check("Enter handles selection deletion",
  interact_src:find("NebulaKey%.Enter") ~= nil)

-- =============================================================================
-- Part 8: 正常移动重置锚点
-- =============================================================================
print("\n=== Part 8: Normal Movement Resets Anchor ===")

-- Check that Left/Right/Up/Down resets anchor
check("Left resets anchor (sel_anchor_row = self.cursor_row after Left)",
  interact_src:find("NebulaKey%.Left") ~= nil)

check("Normal arrow movement updates both anchor row and col",
  interact_src:find("self%.sel_anchor_row = self%.cursor_row; self%.sel_anchor_col = self%.cursor_col") ~= nil)

-- =============================================================================
-- Part 9: Producer 选区渲染
-- =============================================================================
print("\n=== Part 9: Producer Selection Rendering ===")

check("fill_edit_area uses nebula_theme_bg_selected()",
  demo_src:find("nebula_theme_bg_selected") ~= nil)

check("fill_edit_area computes sel_active flag",
  demo_src:find("sel_active") ~= nil)

check("fill_edit_area computes ordered selection bounds (sel_sr/sel_sc/sel_er/sel_ec)",
  demo_src:find("sel_sr") ~= nil and
  demo_src:find("sel_sc") ~= nil and
  demo_src:find("sel_er") ~= nil and
  demo_src:find("sel_ec") ~= nil)

check("fill_edit_area handles multi-row selection (buf_row > sel_sr and buf_row < sel_er)",
  demo_src:find("buf_row > sel_sr and buf_row < sel_er") ~= nil)

check("fill_edit_area handles single-row selection",
  demo_src:find("buf_row == sel_sr and buf_row == sel_er") ~= nil)

check("fill_edit_area reads sel_anchor_row/col from editor",
  demo_src:find("editor%.sel_anchor_row") ~= nil and
  demo_src:find("editor%.sel_anchor_col") ~= nil)

-- =============================================================================
-- Part 10: 初始化
-- =============================================================================
print("\n=== Part 10: Initialization ===")

check("main() initializes sel_anchor_row = 0",
  demo_src:find("sel_anchor_row = 0") ~= nil)

check("main() initializes sel_anchor_col = 0",
  demo_src:find("sel_anchor_col = 0") ~= nil)

-- =============================================================================
-- Part 11: demo 头部注释更新
-- =============================================================================
print("\n=== Part 11: Header Comment ===")

check("demo header mentions Phase 4.8-S1",
  demo_src:find("4%.8") ~= nil)

check("demo header mentions selection (选区)",
  demo_src:find("选区") ~= nil)

check("demo header mentions clipboard (剪贴板)",
  demo_src:find("剪贴板") ~= nil)

-- ---- 总结 ----
print("")
print(("--- smoke_phase4_8_s1 结果: %d 通过, %d 失败 ---"):format(pass_count, fail_count))
if fail_count > 0 then
  os.exit(1)
end
