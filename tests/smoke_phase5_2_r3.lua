-- =============================================================================
-- smoke_phase5_2_r3.lua
-- Phase 5.2 R3: Generated Code Preview — Smoke Test
--
-- Verifies that the R3 infrastructure is correctly implemented:
--   3.1  _NEBULA_GENERATED_SOURCE initialization exists in nebula_sugar.nelua
--   3.2  print_source function is defined in nebula_sugar.nelua
--   3.3  Source caching lines exist in nebula_derive_engine.nelua
--   3.4  Source caching lines exist in nebula_apps.nelua
--   3.5  Source caching for builtins exists in nebula_sugar.nelua
--   3.6  Cache structure has visuals/apps/builtins sub-tables
--
-- Method: Static analysis of source text (same approach as smoke_phase5_2_r2).
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

local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  return content
end

-- Locate src directory
local script_dir = debug.getinfo(1, "S").source:match("@(.*/)")
local src_dir = script_dir and (script_dir .. "../src/") or "src/"

local sugar_src = read_file(src_dir .. "nebula_sugar.nelua")
assert(sugar_src, "nebula_sugar.nelua not found at: " .. src_dir)
local derive_src = read_file(src_dir .. "nebula_derive_engine.nelua")
assert(derive_src, "nebula_derive_engine.nelua not found at: " .. src_dir)
local apps_src = read_file(src_dir .. "nebula_apps.nelua")
assert(apps_src, "nebula_apps.nelua not found at: " .. src_dir)

-- =============================================================================
-- Test Group 1: _NEBULA_GENERATED_SOURCE initialization
-- =============================================================================

check("3.1_cache_table_initialized",
  sugar_src:find("_NEBULA_GENERATED_SOURCE") ~= nil)

check("3.1_cache_visuals_subtable",
  sugar_src:find("visuals%s*=%s*{}") ~= nil or
  sugar_src:find("visuals%s*=%s*{},") ~= nil)

check("3.1_cache_apps_subtable",
  sugar_src:find("apps%s*=%s*{}") ~= nil or
  sugar_src:find("apps%s*=%s*{},") ~= nil)

check("3.1_cache_builtins_subtable",
  sugar_src:find("builtins%s*=%s*{}") ~= nil or
  sugar_src:find("builtins%s*=%s*{},") ~= nil)

-- Guard: init before first usage (appears before Phase 4.5 block)
local init_pos = sugar_src:find("_NEBULA_GENERATED_SOURCE%s*=%s*{")
local phase45_pos = sugar_src:find("Phase 4.5: 语法糖 API")
check("3.1_init_before_phase45",
  init_pos ~= nil and phase45_pos ~= nil and init_pos < phase45_pos)

-- =============================================================================
-- Test Group 2: print_source function definition
-- =============================================================================

check("3.2_print_source_defined",
  sugar_src:find("function print_source") ~= nil)

check("3.2_print_source_handles_mode_all",
  sugar_src:find('mode == "all"') ~= nil)

check("3.2_print_source_handles_mode_visual",
  sugar_src:find('mode == "visual"') ~= nil)

check("3.2_print_source_handles_mode_app",
  sugar_src:find('mode == "app"') ~= nil)

check("3.2_print_source_handles_mode_builtin",
  sugar_src:find('mode == "builtin"') ~= nil)

check("3.2_print_source_emit_delimiter",
  sugar_src:find("%[nebula%] ===== Generated source") ~= nil)

-- =============================================================================
-- Test Group 3: Source caching in nebula_derive_engine.nelua
-- =============================================================================

check("3.3_derive_visuals_cache",
  derive_src:find("_NEBULA_GENERATED_SOURCE%.visuals%[type_name%]") ~= nil)

check("3.3_derive_apps_cache",
  derive_src:find("_NEBULA_GENERATED_SOURCE%.apps%[app_name%]") ~= nil)

-- =============================================================================
-- Test Group 4: Source caching in nebula_apps.nelua
-- =============================================================================

check("3.4_apps_main_cache",
  apps_src:find('_NEBULA_GENERATED_SOURCE%.apps%["main:"') ~= nil)

check("3.4_apps_editor_main_cache",
  apps_src:find('_NEBULA_GENERATED_SOURCE%.apps%["editor_main:"') ~= nil)

check("3.4_apps_terminal_main_cache",
  apps_src:find('_NEBULA_GENERATED_SOURCE%.apps%["terminal_main:"') ~= nil)

-- =============================================================================
-- Test Group 5: Source caching for builtins in nebula_sugar.nelua
-- =============================================================================

check("3.5_builtins_cache_in_sugar",
  sugar_src:find("_NEBULA_GENERATED_SOURCE%.builtins%[") ~= nil)

-- =============================================================================
-- Test Group 6: aster.parse tags — verify tag prefix patterns (with or without caller location)
-- =============================================================================

check("3.6_compat_aster_parse_derive",
  derive_src:find('_nebula_parse_tag.-"nebula_derive"') ~= nil or
  derive_src:find('aster%.parse%(source, "<nebula_derive:"') ~= nil)

check("3.6_compat_aster_parse_derive_app",
  derive_src:find('_nebula_parse_tag.-"nebula_derive_app"') ~= nil or
  derive_src:find('aster%.parse%(source, "<nebula_derive_app:"') ~= nil)

check("3.6_compat_aster_parse_main",
  apps_src:find('_nebula_parse_tag.-"nebula_main"') ~= nil or
  apps_src:find('aster%.parse%(src, "<nebula_main:"') ~= nil)

check("3.6_compat_aster_parse_editor",
  apps_src:find('_nebula_parse_tag.-"nebula_editor_main"') ~= nil or
  apps_src:find('aster%.parse%(src, "<nebula_editor_main:"') ~= nil)

check("3.6_compat_aster_parse_terminal",
  apps_src:find('_nebula_parse_tag.-"nebula_terminal_main"') ~= nil or
  apps_src:find('aster%.parse%(src, "<nebula_terminal_main:"') ~= nil)

-- =============================================================================
-- Test Group 7: Phase 5.2 R3 Step 3.2 — Caller location helper
-- =============================================================================

check("3.7_caller_loc_defined",
  sugar_src:find("function _nebula_caller_loc") ~= nil)

check("3.7_caller_loc_uses_debug_getinfo",
  sugar_src:find("debug%.getinfo") ~= nil)

check("3.7_caller_loc_skips_internal_files",
  sugar_src:find("nebula_sugar") ~= nil and
  sugar_src:find("nebula_derive_engine") ~= nil and
  sugar_src:find("nebula_apps") ~= nil)

check("3.7_parse_tag_defined",
  sugar_src:find("function _nebula_parse_tag") ~= nil)

check("3.7_parse_tag_appends_location",
  sugar_src:find('" at "') ~= nil)

check("3.7_parse_tag_fallback_without_loc",
  sugar_src:find('return "<" .. prefix .. ":" .. name .. ">"') ~= nil)

check("3.7_visual_uses_parse_tag",
  sugar_src:find('_nebula_parse_tag%("nebula_visual"') ~= nil)

check("3.7_derive_uses_parse_tag",
  derive_src:find('_nebula_parse_tag.-"nebula_derive"') ~= nil)

check("3.7_apps_uses_parse_tag",
  apps_src:find('_nebula_parse_tag.-"nebula_main"') ~= nil)

-- =============================================================================
-- Summary
-- =============================================================================
local total = pass_count + fail_count
print(("\n[smoke_phase5_2_r3] %d/%d passed"):format(pass_count, total))
if fail_count > 0 then
  print(("[smoke_phase5_2_r3] %d FAILED"):format(fail_count))
  os.exit(1)
else
  print("[smoke_phase5_2_r3] ALL PASSED")
end
