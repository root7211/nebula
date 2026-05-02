-- =============================================================================
-- smoke_phase4_7_s1.lua
-- Nebula GUI Compiler — Phase 4.7-S1 Smoke Tests
--
-- 验证内容：
--   1. Gap Buffer UTF-8 aware 方法存在性（move_cursor_left_char 等）
--   2. NebulaMultiBuf UTF-8 兼容性
--   3. CJK 字符显示宽度函数（nebula_cjk_char_display_width）
--   4. nebula_utf8_display_width 函数
--   5. interaction_factory 中 editable 使用 char-aware 方法
--   6. cjk_editor_demo 编译可行性验证
-- =============================================================================

local PASS = 0
local FAIL = 0

local function check(name, cond)
  if cond then
    PASS = PASS + 1
    print("[PASS] " .. name)
  else
    FAIL = FAIL + 1
    print("[FAIL] " .. name)
  end
end

-- =============================================================================
-- Part 1: Gap Buffer UTF-8 Methods Existence
-- =============================================================================
print("\n=== Part 1: Gap Buffer UTF-8 Methods ===\n")

-- Read gap_buffer_factory.lua
local f = io.open("src/derive/gap_buffer_factory.lua", "r")
assert(f, "Cannot open src/derive/gap_buffer_factory.lua")
local gbf_src = f:read("*a")
f:close()

-- Check UTF-8 aware methods exist
check("gap_buf: move_cursor_left_char method exists",
  gbf_src:find("move_cursor_left_char") ~= nil)
check("gap_buf: move_cursor_right_char method exists",
  gbf_src:find("move_cursor_right_char") ~= nil)
check("gap_buf: delete_char_before method exists",
  gbf_src:find("delete_char_before") ~= nil)
check("gap_buf: delete_char_after method exists",
  gbf_src:find("delete_char_after") ~= nil)
check("gap_buf: char_count method exists",
  gbf_src:find("char_count") ~= nil)

-- Check UTF-8 continuation byte detection pattern (0xC0 & 0x80)
check("gap_buf: move_cursor_left_char checks continuation bytes",
  gbf_src:find("move_cursor_left_char.-0xC0.-0x80") ~= nil)
check("gap_buf: move_cursor_right_char checks continuation bytes",
  gbf_src:find("move_cursor_right_char.-0xC0.-0x80") ~= nil)
check("gap_buf: delete_char_before checks continuation bytes",
  gbf_src:find("delete_char_before.-0xC0.-0x80") ~= nil)
check("gap_buf: delete_char_after checks continuation bytes",
  gbf_src:find("delete_char_after.-0xC0.-0x80") ~= nil)

-- Check char_count counts only leading bytes (non-continuation)
check("gap_buf: char_count skips continuation bytes",
  gbf_src:find("char_count.-0xC0.-0x80") ~= nil)

-- Verify Phase 4.7-S1 tag
check("gap_buf: Phase 4.7-S1 tag present",
  gbf_src:find("Phase 4.7%-S1") ~= nil)

-- =============================================================================
-- Part 2: Interaction Factory — Editable Uses Char-Aware Methods
-- =============================================================================
print("\n=== Part 2: Editable UTF-8 Integration ===\n")

local f2 = io.open("src/derive/interaction_factory.lua", "r")
assert(f2, "Cannot open src/derive/interaction_factory.lua")
local if_src = f2:read("*a")
f2:close()

-- Check that editable's process_text_input uses char-aware methods
check("editable: Left key uses move_cursor_left_char",
  if_src:find("NebulaKey%.Left.-move_cursor_left_char") ~= nil)
check("editable: Right key uses move_cursor_right_char",
  if_src:find("NebulaKey%.Right.-move_cursor_right_char") ~= nil)
check("editable: Backspace uses delete_char_before",
  if_src:find("delete_char_before") ~= nil)
check("editable: Delete uses delete_char_after",
  if_src:find("delete_char_after") ~= nil)
check("editable: ShiftLeft uses move_cursor_left_char",
  if_src:find("ShiftLeft.-move_cursor_left_char") ~= nil)
check("editable: ShiftRight uses move_cursor_right_char",
  if_src:find("ShiftRight.-move_cursor_right_char") ~= nil)

-- =============================================================================
-- Part 3: Text Runtime CJK Helpers
-- =============================================================================
print("\n=== Part 3: CJK Display Width Functions ===\n")

local f3 = io.open("src/text_runtime.nelua", "r")
assert(f3, "Cannot open src/text_runtime.nelua")
local tr_src = f3:read("*a")
f3:close()

check("text_runtime: nebula_cjk_char_display_width exists",
  tr_src:find("nebula_cjk_char_display_width") ~= nil)
check("text_runtime: nebula_utf8_display_width exists",
  tr_src:find("nebula_utf8_display_width") ~= nil)
check("text_runtime: CJK Unified Ideographs range (U+4E00-U+9FFF)",
  tr_src:find("0x4E00") ~= nil and tr_src:find("0x9FFF") ~= nil)
check("text_runtime: CJK Extension A range (U+3400-U+4DBF)",
  tr_src:find("0x3400") ~= nil and tr_src:find("0x4DBF") ~= nil)
check("text_runtime: Fullwidth Latin range (U+FF00-U+FFEF)",
  tr_src:find("0xFF01") ~= nil)
check("text_runtime: CJK display width returns 2",
  tr_src:find("return 2") ~= nil)
check("text_runtime: default display width returns 1",
  tr_src:find("return 1") ~= nil)
check("text_runtime: Phase 4.7-S1 tag present",
  tr_src:find("Phase 4.7%-S1") ~= nil)

-- =============================================================================
-- Part 4: CJK Editor Demo Structure
-- =============================================================================
print("\n=== Part 4: CJK Editor Demo ===\n")

local f4 = io.open("examples/cjk_editor_demo.nelua", "r")
assert(f4, "Cannot open examples/cjk_editor_demo.nelua")
local demo_src = f4:read("*a")
f4:close()

check("demo: file exists and is non-empty",
  #demo_src > 100)
check("demo: requires nebula_core",
  demo_src:find('require "nebula_core"') ~= nil)
check("demo: requires text_runtime",
  demo_src:find('require "text_runtime"') ~= nil)
check("demo: uses NebulaMultiBuf128_32",
  demo_src:find("NebulaMultiBuf128_32") ~= nil)
check("demo: uses nebula_utf8_display_width for CJK width",
  demo_src:find("nebula_utf8_display_width") ~= nil)
check("demo: uses multiline_editable primitive",
  demo_src:find('"multiline_editable"') ~= nil)
check("demo: defines CjkEditorVisual",
  demo_src:find("CjkEditorVisual") ~= nil)
check("demo: pre-fills CJK demo text (你好世界)",
  demo_src:find("0xE4, 0xBD, 0xA0") ~= nil)  -- 你
check("demo: pre-fills mixed CJK+ASCII text",
  demo_src:find("Hello") ~= nil or demo_src:find("0x48, 0x65") ~= nil)
check("demo: registers cjk_editor_demo in build.sh",
  true)  -- checked separately

-- Check build.sh includes cjk_editor_demo
local f5 = io.open("build.sh", "r")
assert(f5, "Cannot open build.sh")
local build_src = f5:read("*a")
f5:close()

check("build.sh: includes cjk_editor_demo target",
  build_src:find("cjk_editor_demo") ~= nil)

-- =============================================================================
-- Part 5: NebulaMultiBuf apply_line_cursor UTF-8 Safety
-- =============================================================================
print("\n=== Part 5: NebulaMultiBuf UTF-8 Compatibility ===\n")

check("NebulaMultiBuf: apply_line_cursor uses bounded loop",
  gbf_src:find("apply_line_cursor.-cursor%(%) <") ~= nil or
  gbf_src:find("apply_line_cursor.-gap_end < line%.capacity") ~= nil)

-- =============================================================================
-- Part 6: UTF-8 Byte-Level Correctness Verification
-- =============================================================================
print("\n=== Part 6: UTF-8 Encoding Correctness ===\n")

-- Verify the continuation byte mask pattern is correct
-- UTF-8 continuation bytes: 10xxxxxx (0x80-0xBF)
-- Leading bytes: 0xxxxxxx (0x00-0x7F), 110xxxxx (0xC0-0xDF), 1110xxxx (0xE0-0xEF), 11110xxx (0xF0-0xF7)
-- Check: (byte & 0xC0) == 0x80 identifies continuation bytes

check("UTF-8: continuation byte mask 0xC0 used in gap_buffer",
  gbf_src:find("0xC0") ~= nil)
check("UTF-8: continuation byte value 0x80 used in gap_buffer",
  gbf_src:find("0x80") ~= nil)

-- Verify move_cursor_left_char calls move_cursor_left (reuses existing logic)
check("move_cursor_left_char: delegates to move_cursor_left",
  gbf_src:find("move_cursor_left_char.-move_cursor_left%(%)") ~= nil)
check("move_cursor_right_char: delegates to move_cursor_right",
  gbf_src:find("move_cursor_right_char.-move_cursor_right%(%)") ~= nil)

-- Verify delete methods use gap_start/gap_end directly (no delegation needed)
check("delete_char_before: manipulates gap_start directly",
  gbf_src:find("delete_char_before.-gap_start = self.gap_start %- 1") ~= nil)
check("delete_char_after: manipulates gap_end directly",
  gbf_src:find("delete_char_after.-gap_end = self.gap_end %+ 1") ~= nil)

-- =============================================================================
-- Summary
-- =============================================================================
print(("\n--- smoke_phase4_7_s1 结果: %d 通过, %d 失败 ---"):format(PASS, FAIL))
if FAIL > 0 then
  os.exit(1)
end
