-- =============================================================================
-- tests/smoke_phase4_4_s3.lua
-- Phase 4.4 S3 — Multiline Editable 多行文本编辑
--
-- 测试目标：
--   1. multiline_editable 原语可以正确注册到 NEBULA_PRIMITIVES
--   2. multiline_editable 依赖 editable + scrollable，依赖解析正确（6 层链）
--   3. multiline_editable 原语的 context_fields 包含 cursor_row/cursor_col/line_count
--   4. multiline_editable 原语的 process_body 包含 Up/Down/Enter 键处理
--   5. NebulaMultiBuf{N}_{L} 编译期类型生成正确
--   6. NebulaMultiBuf 方法签名完整（init, get_line, current_line, insert_newline, etc.）
--   7. 与 editable 原语的上下文字段无冲突
--   8. Axiom validator 白名单扩展匹配 NebulaMultiBuf
-- =============================================================================

-- 设置正确的模块搜索路径
local script_dir = debug.getinfo(1, "S").source:match("^@(.+)/[^/]+$") or "."
package.path = script_dir .. "/../src/?.lua;" ..
               script_dir .. "/../src/derive/?.lua;" ..
               package.path

local interaction_ver = require "derive.interaction_factory"

-- =============================================================================
-- 测试工具
-- =============================================================================
local pass_count = 0
local fail_count = 0

local function assert_eq(desc, actual, expected)
  if actual == expected then
    print("[PASS] " .. desc)
    pass_count = pass_count + 1
  else
    print("[FAIL] " .. desc)
    print("       expected: " .. tostring(expected))
    print("       actual:   " .. tostring(actual))
    fail_count = fail_count + 1
  end
end

local function assert_true(desc, val)
  if val then
    print("[PASS] " .. desc)
    pass_count = pass_count + 1
  else
    print("[FAIL] " .. desc)
    print("       expected truthy, got: " .. tostring(val))
    fail_count = fail_count + 1
  end
end

local function assert_contains(desc, haystack, needle)
  if type(haystack) == "string" and haystack:find(needle, 1, true) then
    print("[PASS] " .. desc)
    pass_count = pass_count + 1
  else
    print("[FAIL] " .. desc)
    print("       pattern '" .. needle .. "' not found in:")
    print("       " .. tostring(haystack):sub(1, 500))
    fail_count = fail_count + 1
  end
end

local function assert_not_contains(desc, haystack, needle)
  if type(haystack) == "string" and not haystack:find(needle, 1, true) then
    print("[PASS] " .. desc)
    pass_count = pass_count + 1
  else
    print("[FAIL] " .. desc)
    print("       pattern '" .. needle .. "' should NOT be found but was")
    fail_count = fail_count + 1
  end
end

-- =============================================================================
print("")
print("=== Phase 4.4 S3: multiline_editable 原语注册与 NebulaMultiBuf 验证 ===")
print("")

-- §1: scrollable 原语已内置到 NEBULA_PRIMITIVES（interaction_factory.lua #6）
assert_true("§1.1: scrollable is built-in", NEBULA_PRIMITIVES["scrollable"] ~= nil)


-- §2: multiline_editable 原语已内置到 NEBULA_PRIMITIVES（interaction_factory.lua #8）
assert_true("§2.1: multiline_editable is built-in", NEBULA_PRIMITIVES["multiline_editable"] ~= nil)

local me = NEBULA_PRIMITIVES["multiline_editable"]
assert_eq("§2.2: multiline_editable has 2 dependencies", #me.dependencies, 2)
assert_eq("§2.3: dep[1] = editable", me.dependencies[1], "editable")
assert_eq("§2.4: dep[2] = scrollable", me.dependencies[2], "scrollable")
assert_eq("§2.5: multiline_editable has 5 context fields", #me.context_fields, 5)
assert_eq("§2.6: ctx[1] = cursor_row", me.context_fields[1].name, "cursor_row")
assert_eq("§2.6b: cursor_row type = uint32", me.context_fields[1].type, "uint32")
assert_eq("§2.7: ctx[2] = cursor_col", me.context_fields[2].name, "cursor_col")
assert_eq("§2.7b: cursor_col type = uint32", me.context_fields[2].type, "uint32")
assert_eq("§2.8: ctx[3] = line_count", me.context_fields[3].name, "line_count")
assert_eq("§2.8b: line_count type = uint32", me.context_fields[3].type, "uint32")
-- ★ Phase 4.8 S1: selection anchor fields
assert_eq("§2.9: ctx[4] = sel_anchor_row", me.context_fields[4].name, "sel_anchor_row")
assert_eq("§2.9b: sel_anchor_row type = uint32", me.context_fields[4].type, "uint32")
assert_eq("§2.10: ctx[5] = sel_anchor_col", me.context_fields[5].name, "sel_anchor_col")
assert_eq("§2.10b: sel_anchor_col type = uint32", me.context_fields[5].type, "uint32")

-- §3: nebula_gen_process_input generates multiline key handling
local gen = nebula_gen_process_input({
  base       = "MultilineEditVisual",
  state_type = "MultilineEditVisualState",
  primitives = {"hoverable", "clickable", "focusable", "editable", "scrollable", "multiline_editable"},
  states     = {"default", "hovered", "focused", "dragging", "draggingbar"},
})
assert_contains("§3.1: process_input contains NebulaKey.Up", gen, "NebulaKey.Up")
assert_contains("§3.2: process_input contains NebulaKey.Down", gen, "NebulaKey.Down")
assert_contains("§3.3: process_input contains NebulaKey.Enter", gen, "NebulaKey.Enter")
assert_contains("§3.4: process_input contains Home", gen, "NebulaKey.Home")
assert_contains("§3.5: process_input contains End", gen, "NebulaKey.End")
assert_contains("§3.6: process_input contains cursor_row logic", gen, "self.cursor_row")
assert_contains("§3.7: process_input contains line_count check", gen, "self.line_count")
assert_contains("§3.8: process_input contains cursor_col reset on Enter", gen, "self.cursor_col = 0")
-- §3.9-§3.14: S7-fix 新增的完整键盘支持
assert_contains("§3.9: process_input contains NebulaKey.Left", gen, "NebulaKey.Left")
assert_contains("§3.10: process_input contains NebulaKey.Right", gen, "NebulaKey.Right")
assert_contains("§3.11: process_input contains NebulaKey.Backspace", gen, "NebulaKey.Backspace")
assert_contains("§3.12: process_input contains NebulaKey.Delete", gen, "NebulaKey.Delete")
assert_contains("§3.13: Enter delegates to insert_newline", gen, "insert_newline")
assert_contains("§3.14: Backspace merges via merge_line_up", gen, "merge_line_up")
assert_contains("§3.15: char input inserts into multi_buf current line", gen, "insert_char")
assert_contains("§3.16: cursor sync before insert_newline", gen, "multi_buf.cursor_row = self.cursor_row")

-- §4: context_fields includes ALL fields from all primitives (6-layer chain)
-- editable → focusable → clickable → hoverable + scrollable → multiline_editable
local fields = nebula_get_context_fields({"editable", "scrollable", "multiline_editable"})
local field_names = {}
for _, f in ipairs(fields) do field_names[f.name] = true end

-- hoverable fields
assert_true("§4.1: context has hover field", field_names["hover"] ~= nil)
-- clickable fields
assert_true("§4.2: context has click field", field_names["click"] ~= nil)
-- focusable fields
assert_true("§4.3: context has component_id field", field_names["component_id"] ~= nil)
-- editable fields
assert_true("§4.4: context has selection_anchor field", field_names["selection_anchor"] ~= nil)
assert_true("§4.5: context has is_dragging field (editable)", field_names["is_dragging"] ~= nil)
-- scrollable fields
assert_true("§4.6: context has scroll_offset_y field", field_names["scroll_offset_y"] ~= nil)
assert_true("§4.7: context has max_scroll field", field_names["max_scroll"] ~= nil)
assert_true("§4.8: context has is_dragging_bar field", field_names["is_dragging_bar"] ~= nil)
-- multiline_editable fields
assert_true("§4.9: context has cursor_row field", field_names["cursor_row"] ~= nil)
assert_true("§4.10: context has cursor_col field", field_names["cursor_col"] ~= nil)
assert_true("§4.11: context has line_count field", field_names["line_count"] ~= nil)

-- §5: Dependency resolution — full chain
local resolved = nebula_resolve_primitives({"multiline_editable"})
-- Expected chain: hoverable → clickable → focusable → editable → scrollable → multiline_editable
-- (hoverable comes first because both clickable and scrollable depend on it)
assert_true("§5.1: resolved chain has >= 5 primitives", #resolved >= 5)
assert_eq("§5.2: last resolved = multiline_editable", resolved[#resolved], "multiline_editable")

-- Check that editable comes before multiline_editable
local edit_idx = 0
local multi_idx = 0
for i, name in ipairs(resolved) do
  if name == "editable" then edit_idx = i end
  if name == "multiline_editable" then multi_idx = i end
end
assert_true("§5.3: editable comes before multiline_editable in resolved chain", edit_idx < multi_idx)

-- Check scrollable comes before multiline_editable
local scroll_idx = 0
for i, name in ipairs(resolved) do
  if name == "scrollable" then scroll_idx = i end
end
assert_true("§5.4: scrollable comes before multiline_editable in resolved chain", scroll_idx < multi_idx)

-- §6: Deduplication
local resolved2 = nebula_resolve_primitives({"editable", "multiline_editable"})
assert_eq("§6.1: editable + multiline_editable dedup correctly", #resolved, #resolved2)

local resolved3 = nebula_resolve_primitives({"scrollable", "multiline_editable"})
assert_eq("§6.2: scrollable + multiline_editable dedup correctly", #resolved, #resolved3)

-- §7: Duplicate registration fails
local ok_dup, err_dup = pcall(function()
  nebula_register_primitive("multiline_editable", {
    dependencies = {"editable"},
    context_fields = {},
    state_transitions = {},
    process_body = function(spec, lines) end,
  })
end)
assert_true("§7.1: duplicate multiline_editable registration raises error", not ok_dup)
assert_contains("§7.2: error message mentions 'already registered'", err_dup, "already registered")

-- §8: NebulaMultiBuf type generation
local gap_buf_factory = require "derive.gap_buffer_factory"
local mb_type, mb_src, line_type = nebula_gen_multiline_buffer_type(128, 32)
assert_eq("§8.1: multiline buffer type name = NebulaMultiBuf128_32", mb_type, "NebulaMultiBuf128_32")
assert_eq("§8.2: line type name = NebulaBuf128", line_type, "NebulaBuf128")
assert_contains("§8.3: multiline source contains record definition", mb_src, "NebulaMultiBuf128_32 = @record{")
assert_contains("§8.4: multiline source has lines array field", mb_src, "lines:")
assert_contains("§8.5: multiline source has line_count field", mb_src, "line_count:")
assert_contains("§8.6: multiline source has cursor_row field", mb_src, "cursor_row:")
assert_contains("§8.7: multiline source has cursor_col field", mb_src, "cursor_col:")
assert_contains("§8.8: multiline source has init method", mb_src, "function NebulaMultiBuf128_32:init()")
assert_contains("§8.9: multiline source has get_line method", mb_src, "function NebulaMultiBuf128_32:get_line(")
assert_contains("§8.10: multiline source has current_line method", mb_src, "function NebulaMultiBuf128_32:current_line()")
assert_contains("§8.11: multiline source has insert_newline method", mb_src, "function NebulaMultiBuf128_32:insert_newline()")
assert_contains("§8.12: multiline source has merge_line_up method", mb_src, "function NebulaMultiBuf128_32:merge_line_up()")
assert_contains("§8.13: multiline source has move_cursor_up method", mb_src, "function NebulaMultiBuf128_32:move_cursor_up()")
assert_contains("§8.14: multiline source has move_cursor_down method", mb_src, "function NebulaMultiBuf128_32:move_cursor_down()")
assert_contains("§8.15: multiline source has sync_line_cursor method", mb_src, "function NebulaMultiBuf128_32:sync_line_cursor()")
assert_contains("§8.16: multiline source has apply_line_cursor method", mb_src, "function NebulaMultiBuf128_32:apply_line_cursor()")
assert_contains("§8.17: multiline source has flatten_lines method", mb_src, "function NebulaMultiBuf128_32:flatten_lines(")
assert_contains("§8.18: multiline source has clear method", mb_src, "function NebulaMultiBuf128_32:clear()")
-- The line buffer type (NebulaBuf128) source is prepended
assert_contains("§8.19: multiline source includes NebulaBuf128 definition", mb_src, "NebulaBuf128 = @record{")
assert_contains("§8.20: multiline source has lines array size = 32", mb_src, "[32]NebulaBuf128,")

-- §9: Dedup — second call returns empty source
local mb_type2, mb_src2 = nebula_gen_multiline_buffer_type(128, 32)
assert_eq("§9.1: dedup returns same type name", mb_type2, "NebulaMultiBuf128_32")
assert_eq("§9.2: dedup returns empty source", mb_src2, "")

-- §10: Different parameters generate different types
local mb_type3, mb_src3 = nebula_gen_multiline_buffer_type(256, 16)
assert_eq("§10.1: different params = different type name", mb_type3, "NebulaMultiBuf256_16")
assert_contains("§10.2: different params source has correct array", mb_src3, "[16]NebulaBuf256,")

-- §11: NebulaMultiBuf source contains correct line ordering (line_type BEFORE multiline_type)
local pos_line_def = mb_src:find("NebulaBuf128 = @record{")
local pos_multi_def = mb_src:find("NebulaMultiBuf128_32 = @record{")
assert_true("§11.1: NebulaBuf128 definition comes BEFORE NebulaMultiBuf128_32", pos_line_def < pos_multi_def)

-- §12: No context field conflicts between multiline_editable and editable
-- Both editable and multiline_editable use is_dragging — check it appears once
local all_fields = nebula_get_context_fields({"editable", "multiline_editable"})
local is_dragging_count = 0
for _, f in ipairs(all_fields) do
  if f.name == "is_dragging" then is_dragging_count = is_dragging_count + 1 end
end
assert_eq("§12.1: is_dragging field appears exactly once (deduped)", is_dragging_count, 1)

-- =============================================================================
-- 结果统计
-- =============================================================================
local total = pass_count + fail_count
print("")
print(string.format("[smoke_phase4_4_s3] %d/%d assertions passed", pass_count, total))
if fail_count > 0 then
  print("[FAIL] " .. fail_count .. " assertions FAILED")
  os.exit(1)
else
  print("[PASS] all assertions passed")
end
