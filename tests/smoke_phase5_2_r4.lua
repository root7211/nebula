-- =============================================================================
-- smoke_phase5_2_r4.lua
-- Phase 5.2 R4: Builtin AST Refactoring — Smoke Test
--
-- Verifies that builtin_factory.lua AST-based code generation produces
-- functionally equivalent output to the old string template approach.
--
-- Test groups:
--   1. Module loading and version check
--   2. Registry completeness (all 5 builtins registered)
--   3. AST emit correctness for each builtin
--   4. Custom builtin registration
--   5. Code equivalence: key patterns present in generated output
-- =============================================================================

local pass_count = 0
local fail_count = 0

local function check(name, cond)
  if cond then
    pass_count = pass_count + 1
  else
    fail_count = fail_count + 1
    print(("[FAIL] %s"):format(name))
  end
end

-- Setup package path
local script_dir = debug.getinfo(1, "S").source:match("@(.*/)")
if script_dir then
  package.path = script_dir .. "../src/derive/?.lua;" .. package.path
end

-- =============================================================================
-- Test Group 1: Module loading
-- =============================================================================
local ver = require("builtin_factory")
check("1.1_module_loads", ver ~= nil)
check("1.2_version_string", type(ver) == "string" and ver:find("builtin_factory") ~= nil)
check("1.3_version_phase", ver:find("phase5.2") ~= nil)

-- =============================================================================
-- Test Group 2: Registry completeness
-- =============================================================================
check("2.1_registry_exists", type(NEBULA_BUILTIN_SPECS) == "table")
check("2.2_line_nums_registered",  type(NEBULA_BUILTIN_SPECS.line_nums)  == "function")
check("2.3_status_bar_registered", type(NEBULA_BUILTIN_SPECS.status_bar) == "function")
check("2.4_search_bar_registered", type(NEBULA_BUILTIN_SPECS.search_bar) == "function")
check("2.5_edit_area_registered",  type(NEBULA_BUILTIN_SPECS.edit_area)  == "function")
check("2.6_term_grid_registered",  type(NEBULA_BUILTIN_SPECS.term_grid)  == "function")
check("2.7_emit_api_exists", type(nebula_builtin_emit) == "function")
check("2.8_register_api_exists", type(nebula_register_builtin_spec) == "function")

-- =============================================================================
-- Test Group 3: line_nums AST emit
-- =============================================================================
local ln_fname, ln_src = nebula_builtin_emit("line_nums", {
  editor_name = "editor", cell_w = 10.0, cell_h = 16.0, rows = 50,
})
check("3.1_line_nums_fname", ln_fname == "nebula_fill_line_nums_editor")
check("3.2_line_nums_has_function", ln_src:find("global function nebula_fill_line_nums_editor") ~= nil)
check("3.3_line_nums_has_editor_ref", ln_src:find("local editor = &app.editor") ~= nil)
check("3.4_line_nums_has_multi_buf", ln_src:find("local mb = &editor.visual.multi_buf") ~= nil)
check("3.5_line_nums_has_scroll", ln_src:find("scroll_row") ~= nil)
check("3.6_line_nums_has_digits", ln_src:find("local digits: %[7%]uint32") ~= nil)
check("3.7_line_nums_has_pipe", ln_src:find("NEBULA_CHAR_PIPE") ~= nil)
check("3.8_line_nums_has_tilde", ln_src:find("NEBULA_CHAR_TILDE") ~= nil)
check("3.9_line_nums_has_fill", ln_src:find("nebula_dense_grid_fill_instance") ~= nil)
check("3.10_line_nums_has_count", ln_src:find("%$count = idx") ~= nil)
check("3.11_line_nums_has_theme", ln_src:find("nebula_theme_fg_linenum") ~= nil)
check("3.12_line_nums_has_cursor_line", ln_src:find("nebula_theme_bg_cursor_line") ~= nil)
check("3.13_line_nums_cell_w", ln_src:find("10.0") ~= nil)
check("3.14_line_nums_cell_h", ln_src:find("16.0") ~= nil)
check("3.15_line_nums_layout_x", ln_src:find("app.dense_layout_line_nums_x") ~= nil)
check("3.16_line_nums_layout_y", ln_src:find("app.dense_layout_line_nums_y") ~= nil)

-- =============================================================================
-- Test Group 4: status_bar AST emit
-- =============================================================================
local sb_fname, sb_src = nebula_builtin_emit("status_bar", {
  editor_name = "editor", cell_w = 10.0, cell_h = 16.0, cols = 128,
})
check("4.1_status_bar_fname", sb_fname == "nebula_fill_status_bar_editor")
check("4.2_status_bar_has_function", sb_src:find("global function nebula_fill_status_bar_editor") ~= nil)
check("4.3_status_bar_has_snprintf", sb_src:find("snprintf") ~= nil)
check("4.4_status_bar_has_utf8", sb_src:find("UTF%-8") ~= nil)
check("4.5_status_bar_has_lf", sb_src:find("LF") ~= nil)
check("4.6_status_bar_has_modified", sb_src:find("_editor_modified") ~= nil)
check("4.7_status_bar_has_file_path", sb_src:find("_editor_file_path") ~= nil)
check("4.8_status_bar_has_untitled", sb_src:find("%[untitled%]") ~= nil)
check("4.9_status_bar_has_require", sb_src:find('require "nebula_editor"') ~= nil)

-- Test App Record mode
local sb2_fname, sb2_src = nebula_builtin_emit("status_bar", {
  editor_name = "ed", cell_w = 10.0, cell_h = 16.0, cols = 128,
  editor_state = "es",
})
check("4.10_status_bar_record_modified", sb2_src:find("app.es.modified") ~= nil)
check("4.11_status_bar_record_has_file", sb2_src:find("app.es.has_file") ~= nil)
check("4.12_status_bar_record_file_path", sb2_src:find("app.es.file_path") ~= nil)

-- =============================================================================
-- Test Group 5: search_bar AST emit
-- =============================================================================
local srch_fname, srch_src = nebula_builtin_emit("search_bar", {
  editor_name = "editor", cell_w = 10.0, cell_h = 16.0, cols = 128,
})
check("5.1_search_bar_fname", srch_fname == "nebula_fill_search_bar_editor")
check("5.2_search_bar_has_function", srch_src:find("global function nebula_fill_search_bar_editor") ~= nil)
check("5.3_search_bar_has_search_active", srch_src:find("_search_active") ~= nil)
check("5.4_search_bar_has_replace", srch_src:find("Replace:") ~= nil)
check("5.5_search_bar_has_find", srch_src:find("Find:") ~= nil)
check("5.6_search_bar_has_cursor", srch_src:find("nebula_theme_bg_cursor") ~= nil)
check("5.7_search_bar_has_label", srch_src:find("nebula_theme_fg_search_label") ~= nil)
check("5.8_search_bar_has_hide", srch_src:find("nebula_theme_bg_normal") ~= nil)

-- =============================================================================
-- Test Group 6: edit_area AST emit
-- =============================================================================
local ea_fname, ea_src = nebula_builtin_emit("edit_area", {
  editor_name = "editor", cell_w = 10.0, cell_h = 16.0, cols = 120, rows = 50,
})
check("6.1_edit_area_fname", ea_fname == "nebula_fill_edit_area_editor")
check("6.2_edit_area_has_function", ea_src:find("global function nebula_fill_edit_area_editor") ~= nil)
check("6.3_edit_area_has_highlight", ea_src:find("nebula_highlight_dispatch") ~= nil)
check("6.4_edit_area_has_selection", ea_src:find("sel_active") ~= nil)
check("6.5_edit_area_has_search_match", ea_src:find("nebula_theme_bg_search_current") ~= nil)
check("6.6_edit_area_has_cursor", ea_src:find("nebula_theme_bg_cursor") ~= nil)
check("6.7_edit_area_has_utf8_skip", ea_src:find("0xC0") ~= nil)
check("6.8_edit_area_has_hl_colors", ea_src:find("hl_colors") ~= nil)
check("6.9_edit_area_has_flatten", ea_src:find("flatten") ~= nil)
check("6.10_edit_area_has_line_buf", ea_src:find("NEBULA_LINE_BUF_SIZE") ~= nil)
check("6.11_edit_area_has_require", ea_src:find('require "nebula_editor"') ~= nil)

-- Test with editor_state (App Record mode)
local ea2_fname, ea2_src = nebula_builtin_emit("edit_area", {
  editor_name = "ed", cell_w = 10.0, cell_h = 16.0, cols = 80, rows = 40,
  editor_state = "es",
})
check("6.12_edit_area_record_highlight", ea2_src:find("app.es.highlight_id") ~= nil)
check("6.13_edit_area_record_search", ea2_src:find("app.es.search_active") ~= nil)

-- =============================================================================
-- Test Group 7: term_grid AST emit
-- =============================================================================
local tg_fname, tg_src = nebula_builtin_emit("term_grid", {
  comp_name = "grid", cell_w = 12.0, cell_h = 18.0, rows = 24, cols = 80,
})
check("7.1_term_grid_fname", tg_fname == "nebula_fill_term_grid_grid")
check("7.2_term_grid_has_function", tg_src:find("global function nebula_fill_term_grid_grid") ~= nil)
check("7.3_term_grid_has_term_buf", tg_src:find("_nebula_term_buf") ~= nil)
check("7.4_term_grid_has_nilptr", tg_src:find("nilptr") ~= nil)
check("7.5_term_grid_has_get_cell", tg_src:find("get_cell") ~= nil)
check("7.6_term_grid_has_cursor", tg_src:find("_nebula_term_cursor_visible") ~= nil)
check("7.7_term_grid_has_reverse", tg_src:find("cursor_fg") ~= nil)
check("7.8_term_grid_layout_x", tg_src:find("app.dense_layout_grid_x") ~= nil)
check("7.9_term_grid_layout_y", tg_src:find("app.dense_layout_grid_y") ~= nil)

-- =============================================================================
-- Test Group 8: Custom builtin registration
-- =============================================================================
local function custom_builder(opts)
  return "custom_func", {
    kind = "func", name = "custom_func",
    params = {{"app", "auto"}, {"instances", "*[0]DenseCharInstance"}, {"count", "*uint32"}, {"max", "uint32"}},
    ret = "void",
    body = {{ kind = "line", fragments = {{ kind = "lit", value = "$count = 0" }} }},
  }
end
nebula_register_builtin_spec("custom_test", custom_builder)
check("8.1_custom_registered", NEBULA_BUILTIN_SPECS.custom_test == custom_builder)
local cf, cs = nebula_builtin_emit("custom_test", {})
check("8.2_custom_emit_fname", cf == "custom_func")
check("8.3_custom_emit_src", cs:find("global function custom_func") ~= nil)

-- Error case: duplicate registration
local ok = pcall(nebula_register_builtin_spec, "custom_test", custom_builder)
check("8.4_duplicate_rejected", not ok)

-- Error case: unknown builtin
local ok2 = pcall(nebula_builtin_emit, "nonexistent", {})
check("8.5_unknown_rejected", not ok2)

-- =============================================================================
-- Test Group 9: Structural invariants
-- =============================================================================
-- All builtins should produce code with matching function/end pairs
for _, name in ipairs({"line_nums", "status_bar", "search_bar", "edit_area", "term_grid"}) do
  local opts = { editor_name = "editor", comp_name = "grid",
                 cell_w = 10.0, cell_h = 16.0, cols = 80, rows = 40 }
  local _, src = nebula_builtin_emit(name, opts)
  -- Count "global function" and top-level "end"
  local func_count = 0
  for _ in src:gmatch("global function") do func_count = func_count + 1 end
  check(("9.%s_single_function_%s"):format(name, name), func_count == 1)
  -- Should end with "end"
  local trimmed = src:match("^(.-)%s*$")
  check(("9.%s_ends_with_end_%s"):format(name, name), trimmed:sub(-3) == "end")
end

-- =============================================================================
-- Summary
-- =============================================================================
local total = pass_count + fail_count
print(("smoke_phase5_2_r4: %d/%d passed"):format(pass_count, total))
if fail_count > 0 then
  os.exit(1)
end
