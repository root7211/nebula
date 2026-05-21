-- =============================================================================
-- smoke_phase5_2_r5_s3.lua
-- Phase 5.2 R5 Step 5.3: Component Template System — Smoke Test
--
-- Verifies:
--   1. nebula_component_template function exists in nebula_sugar.nelua
--   2. _nebula_component_templates registry initialized
--   3. Built-in templates registered (StandardSearchBar, StandardStatusBar, StandardLineNums)
--   4. nebula_app resolves `use` field to template spec
--   5. Template fields merge correctly with component overrides
--   6. Unknown template name triggers assertion message in code
================================================================================

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

local script_dir = debug.getinfo(1, "S").source:match("@(.*/)")
local src_dir = script_dir and (script_dir .. "../src/") or "src/"

local sugar_src = read_file(src_dir .. "nebula_sugar.nelua")
assert(sugar_src, "nebula_sugar.nelua not found at: " .. src_dir)

-- =============================================================================
-- Test Group 1: nebula_component_template function exists
-- =============================================================================
check("1.1_template_function_defined",
  sugar_src:find("function nebula_component_template%(name, spec%)") ~= nil)

check("1.2_template_registry_init",
  sugar_src:find("_nebula_component_templates%s*=%s*_nebula_component_templates%s*or%s*{}") ~= nil)

check("1.3_template_asserts_name_string",
  sugar_src:find('name must be a string') ~= nil)

check("1.4_template_asserts_spec_table",
  sugar_src:find('spec must be a table') ~= nil)

check("1.5_template_stores_in_registry",
  sugar_src:find('_nebula_component_templates%[name%]%s*=%s*spec') ~= nil)

check("1.6_template_prints_registration",
  sugar_src:find("nebula_component_template:.*registered") ~= nil)

-- =============================================================================
-- Test Group 2: Built-in templates registered
-- =============================================================================
check("2.1_searchbar_template_registered",
  sugar_src:find('nebula_component_template%("StandardSearchBar"') ~= nil)

check("2.2_statusbar_template_registered",
  sugar_src:find('nebula_component_template%("StandardStatusBar"') ~= nil)

check("2.3_linenums_template_registered",
  sugar_src:find('nebula_component_template%("StandardLineNums"') ~= nil)

-- StandardSearchBar should have builtin="search_bar"
check("2.4_searchbar_has_search_bar_builtin",
  sugar_src:find('builtin%s*=%s*"search_bar"') ~= nil)

-- StandardStatusBar should have builtin="status_bar"
check("2.5_statusbar_has_status_bar_builtin",
  sugar_src:find('builtin%s*=%s*"status_bar"') ~= nil)

-- Templates should have flex_basis
check("2.6_templates_have_flex_basis",
  sugar_src:find('flex_basis%s*=%s*24') ~= nil)

-- Templates should have cell dimensions
check("2.7_templates_have_cell_w",
  sugar_src:find('cell_w%s*=%s*10%.0') ~= nil)

check("2.8_templates_have_cell_h",
  sugar_src:find('cell_h%s*=%s*16%.0') ~= nil)

-- =============================================================================
-- Test Group 3: nebula_app resolves `use` field
-- =============================================================================
-- Look for the `use` resolution loop in nebula_app
check("3.1_use_field_resolution",
  sugar_src:find("c%.use") ~= nil)

check("3.2_use_looks_up_template",
  sugar_src:find('_nebula_component_templates%[c%.use%]') ~= nil)

check("3.3_use_asserts_template_exists",
  sugar_src:find("unknown component template") ~= nil)

-- Template merge logic: copy template fields, then override with component fields
check("3.4_use_merges_template_fields",
  sugar_src:find("for k, v in pairs%(tpl%) do merged%[k%] = v end") ~= nil)

check("3.5_use_overrides_component_fields",
  sugar_src:find('if k%s*~=%s*"use" then merged%[k%] = v end') ~= nil)

check("3.6_use_replaces_component",
  sugar_src:find("for k, _ in pairs%(c%) do c%[k%] = nil end") ~= nil)

check("3.7_use_prints_resolution",
  sugar_src:find("resolved template.*for component") ~= nil)

-- Resolution happens before layout processing (Phase 4.9.1)
check("3.8_use_before_layout_processing",
  sugar_src:find("R5%-S3.*resolve.*use") ~= nil)

-- =============================================================================
-- Test Group 4: Header documentation updated
-- =============================================================================
check("4.1_header_mentions_templates",
  sugar_src:find("nebula_component_template") ~= nil)

check("4.2_header_mentions_phase",
  sugar_src:find("Phase 5.2 R5%-S3") ~= nil)

-- =============================================================================
-- Summary
-- =============================================================================
local total = pass_count + fail_count
print(("smoke_phase5_2_r5_s3: %d/%d passed"):format(pass_count, total))
if fail_count > 0 then
  os.exit(1)
end
