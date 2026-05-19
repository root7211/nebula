-- =============================================================================
-- smoke_phase5_2_r5_s1.lua
-- Phase 5.2 R5 Step 5.1: State Binding L2 Sugar Integration — Smoke Test
--
-- Verifies:
--   1. counter_demo.nelua uses L2 API (not L0 app_begin/end)
--   2. nebula_sugar.nelua correctly forwards states/bindings/events to L0 API
--   3. counter_binding_demo.nelua has L0 deprecation notice
--   4. app_factory.lua has nebula_state/nebula_bind/nebula_on definitions
--   5. binding_factory.lua generates record fields + handlers
--   6. Structural integrity of the L2 sugar integration path
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

-- Locate directories
local script_dir = debug.getinfo(1, "S").source:match("@(.*/)")
local src_dir = script_dir and (script_dir .. "../src/") or "src/"
local examples_dir = script_dir and (script_dir .. "../examples/") or "examples/"

-- Load source files
local counter_demo = read_file(examples_dir .. "counter_demo.nelua")
assert(counter_demo, "counter_demo.nelua not found at: " .. examples_dir)

local counter_binding = read_file(examples_dir .. "counter_binding_demo.nelua")
assert(counter_binding, "counter_binding_demo.nelua not found at: " .. examples_dir)

local sugar_src = read_file(src_dir .. "nebula_sugar.nelua")
assert(sugar_src, "nebula_sugar.nelua not found at: " .. src_dir)

local app_factory = read_file(src_dir .. "derive/app_factory.lua")
assert(app_factory, "app_factory.lua not found at: " .. src_dir .. "derive/")

local binding_factory = read_file(src_dir .. "derive/binding_factory.lua")
assert(binding_factory, "binding_factory.lua not found at: " .. src_dir .. "derive/")

-- =============================================================================
-- Test Group 1: counter_demo.nelua — L2 API structure
-- =============================================================================
check("1.1_uses_require_nebula",
  counter_demo:find('require "nebula"') ~= nil)

check("1.2_uses_nebula_visual",
  counter_demo:find("nebula_visual") ~= nil)

check("1.3_uses_nebula_app",
  counter_demo:find("nebula_app") ~= nil)

check("1.4_uses_nebula_main",
  counter_demo:find("nebula_main") ~= nil)

check("1.5_no_app_begin",
  counter_demo:find("nebula_app_begin") == nil)

check("1.6_no_app_end",
  counter_demo:find("nebula_app_end") == nil)

check("1.7_no_nebula_derive",
  counter_demo:find("nebula_derive%(") == nil and
  counter_demo:find("nebula_derive_app%(") == nil)

check("1.8_no_manual_record",
  counter_demo:find("@record") == nil)

check("1.9_has_states",
  counter_demo:find("states%s*=") ~= nil)

check("1.10_has_bindings",
  counter_demo:find("bindings%s*=") ~= nil)

check("1.11_has_events",
  counter_demo:find("events%s*=") ~= nil)

check("1.12_state_count",
  counter_demo:find('name = "count"') ~= nil)

check("1.13_state_type_int32",
  counter_demo:find('type = "int32"') ~= nil)

check("1.14_binding_doubled",
  counter_demo:find('target = "doubled"') ~= nil)

check("1.15_binding_compute",
  counter_demo:find("self%.doubled = self%.count %* 2") ~= nil)

check("1.16_event_click",
  counter_demo:find('event_type = "click"') ~= nil)

check("1.17_event_mutation",
  counter_demo:find("self%.count = self%.count %+ 1") ~= nil)

check("1.18_on_init_themed",
  counter_demo:find("init_themed") ~= nil)

check("1.19_on_frame_printf",
  counter_demo:find("printf") ~= nil)

check("1.20_clickable_primitive",
  counter_demo:find('"clickable"') ~= nil)

-- Line count check: should be concise
local line_count = 0
for _ in counter_demo:gmatch("\n") do line_count = line_count + 1 end
check("1.21_concise_under_60_lines", line_count < 60)

-- =============================================================================
-- Test Group 2: counter_binding_demo.nelua — L0 deprecation notice
-- =============================================================================
check("2.1_l0_has_deprecation_notice",
  counter_binding:find("L0 Raw API") ~= nil)

check("2.2_l0_has_recommend_notice",
  counter_binding:find("推荐写法") ~= nil or
  counter_binding:find("L2 API") ~= nil)

check("2.3_l0_uses_app_begin",
  counter_binding:find("nebula_app_begin") ~= nil)

-- =============================================================================
-- Test Group 3: nebula_sugar.nelua — L2 forwarding
-- =============================================================================
check("3.1_sugar_forwards_states",
  sugar_src:find("nebula_state%(st%.name") ~= nil)

check("3.2_sugar_forwards_bindings",
  sugar_src:find("nebula_bind%(bd%.target") ~= nil)

check("3.3_sugar_forwards_events",
  sugar_src:find("nebula_on%(ev%.target") ~= nil)

check("3.4_sugar_iterates_states",
  sugar_src:find("for _%s*, st in ipairs%(spec%.states") ~= nil)

check("3.5_sugar_iterates_bindings",
  sugar_src:find("for _%s*, bd in ipairs%(spec%.bindings") ~= nil)

check("3.6_sugar_iterates_events",
  sugar_src:find("for _%s*, ev in ipairs%(spec%.events") ~= nil)

-- =============================================================================
-- Test Group 4: app_factory.lua — L0 API definitions
-- =============================================================================
check("4.1_has_nebula_state",
  app_factory:find("function nebula_state") ~= nil)

check("4.2_has_nebula_bind",
  app_factory:find("function nebula_bind") ~= nil)

check("4.3_has_nebula_on",
  app_factory:find("function nebula_on") ~= nil)

check("4.4_state_stores_to_registry",
  app_factory:find("_states") ~= nil)

check("4.5_bind_stores_depends",
  app_factory:find("depends") ~= nil)

check("4.6_on_stores_mutation",
  app_factory:find("mutation") ~= nil)

-- =============================================================================
-- Test Group 5: binding_factory.lua — Code generation
-- =============================================================================
check("5.1_has_gen_record_fields",
  binding_factory:find("record") ~= nil or
  binding_factory:find("field") ~= nil)

check("5.2_has_gen_handler",
  binding_factory:find("handler") ~= nil or
  binding_factory:find("_on_") ~= nil)

check("5.3_has_gen_commit",
  binding_factory:find("commit") ~= nil or
  binding_factory:find("_commit") ~= nil)

check("5.4_has_dirty_bit",
  binding_factory:find("dirty") ~= nil)

-- =============================================================================
-- Test Group 6: Compression ratio
-- =============================================================================
local l0_lines = 0
for _ in counter_binding:gmatch("\n") do l0_lines = l0_lines + 1 end
local ratio = l0_lines / line_count
check("6.1_compression_ratio_gte_2x", ratio >= 2.0)

-- =============================================================================
-- Summary
-- =============================================================================
local total = pass_count + fail_count
print(("smoke_phase5_2_r5_s1: %d/%d passed"):format(pass_count, total))
if fail_count > 0 then
  print(("  L0 lines: %d, L2 lines: %d, ratio: %.1fx"):format(l0_lines, line_count, ratio))
  os.exit(1)
else
  print(("  L0: %d lines → L2: %d lines (%.1fx compression)"):format(l0_lines, line_count, ratio))
end
