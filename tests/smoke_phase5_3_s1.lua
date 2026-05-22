-- =============================================================================
-- smoke_phase5_3_s1.lua
-- Phase 5.3 Step 1: NEBULA_SDF_SHAPES Registry — Smoke Test
--
-- Test groups:
--   1. Module loading and version check
--   2. Built-in SDF self-registration (rect, rounded_rect)
--   3. Custom SDF registration
--   4. Registration validation (duplicates, missing fields)
--   5. WGSL_FRAGMENTS backward compatibility alias
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
local ver = require("shader_compose")
check("1.1_module_loads", ver ~= nil)
check("1.2_version_string", type(ver) == "string" and ver:find("shader_compose") ~= nil)
check("1.3_version_phase5.3", ver:find("phase5.3") ~= nil)

-- =============================================================================
-- Test Group 2: Built-in SDF self-registration
-- =============================================================================
check("2.1_registry_exists", type(NEBULA_SDF_SHAPES) == "table")
check("2.2_rect_registered", NEBULA_SDF_SHAPES["rect"] ~= nil)
check("2.3_rounded_rect_registered", NEBULA_SDF_SHAPES["rounded_rect"] ~= nil)

-- Verify rect fields
local rect = NEBULA_SDF_SHAPES["rect"]
check("2.4_rect_fn_name", rect.fn_name == "sdf_rect")
check("2.5_rect_has_wgsl", rect.wgsl_source:find("fn sdf_rect") ~= nil)
check("2.6_rect_params", rect.params == "p: vec2<f32>, b: vec2<f32>")
check("2.7_rect_returns", rect.returns == "f32")
check("2.8_rect_no_extra_fields", #rect.extra_fields == 0)

-- Verify rounded_rect fields
local rr = NEBULA_SDF_SHAPES["rounded_rect"]
check("2.9_rr_fn_name", rr.fn_name == "sdf_rounded_rect")
check("2.10_rr_has_wgsl", rr.wgsl_source:find("fn sdf_rounded_rect") ~= nil)
check("2.11_rr_extra_fields", #rr.extra_fields == 1)
check("2.12_rr_extra_radius", rr.extra_fields[1].name == "radius")

-- =============================================================================
-- Test Group 3: Custom SDF registration
-- =============================================================================
nebula_register_sdf_shape("circle", {
  fn_name     = "sdf_circle",
  wgsl_source = [[
fn sdf_circle(p: vec2<f32>, r: f32) -> f32 {
  return length(p) - r;
}
]],
  params       = "p: vec2<f32>, r: f32",
  returns      = "f32",
  extra_fields = {{ name = "radius", type = "f32" }},
  description  = "Circle SDF",
})
check("3.1_circle_registered", NEBULA_SDF_SHAPES["circle"] ~= nil)
check("3.2_circle_fn_name", NEBULA_SDF_SHAPES["circle"].fn_name == "sdf_circle")
check("3.3_circle_wgsl", NEBULA_SDF_SHAPES["circle"].wgsl_source:find("fn sdf_circle") ~= nil)
check("3.4_circle_description", NEBULA_SDF_SHAPES["circle"].description == "Circle SDF")

nebula_register_sdf_shape("capsule", {
  fn_name     = "sdf_capsule",
  wgsl_source = "fn sdf_capsule(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>, r: f32) -> f32 { return 0.0; }",
  params      = "p: vec2<f32>, a: vec2<f32>, b: vec2<f32>, r: f32",
})
check("3.5_capsule_registered", NEBULA_SDF_SHAPES["capsule"] ~= nil)
check("3.6_capsule_default_returns", NEBULA_SDF_SHAPES["capsule"].returns == "f32")
check("3.7_capsule_default_extra", #NEBULA_SDF_SHAPES["capsule"].extra_fields == 0)

-- =============================================================================
-- Test Group 4: Registration validation
-- =============================================================================
-- Duplicate registration should fail
local ok1 = pcall(nebula_register_sdf_shape, "rect", {
  fn_name = "sdf_rect2", wgsl_source = "...", params = "...",
})
check("4.1_duplicate_rejected", not ok1)

-- Missing fn_name
local ok2 = pcall(nebula_register_sdf_shape, "bad1", {
  wgsl_source = "...", params = "...",
})
check("4.2_missing_fn_name_rejected", not ok2)

-- Missing wgsl_source
local ok3 = pcall(nebula_register_sdf_shape, "bad2", {
  fn_name = "sdf_bad", params = "...",
})
check("4.3_missing_wgsl_rejected", not ok3)

-- Missing params
local ok4 = pcall(nebula_register_sdf_shape, "bad3", {
  fn_name = "sdf_bad", wgsl_source = "...",
})
check("4.4_missing_params_rejected", not ok4)

-- Non-string name
local ok5 = pcall(nebula_register_sdf_shape, 42, {
  fn_name = "sdf_bad", wgsl_source = "...", params = "...",
})
check("4.5_non_string_name_rejected", not ok5)

-- =============================================================================
-- Test Group 5: Compose function uses registry
-- =============================================================================
-- nebula_compose_shader_instanced should use SDF from registry
local result = nebula_compose_shader_instanced({
  wgsl_struct = "struct Uniforms { pos: vec2<f32>, size: vec2<f32>, bg_color: vec4<f32> }",
  struct_name = "Uniforms",
  has_radius  = false,
  has_border  = false,
})
check("5.1_compose_instanced_has_sdf_rect", result.source:find("fn sdf_rect") ~= nil)
check("5.2_compose_instanced_no_rounded", result.source:find("fn sdf_rounded_rect") == nil)

local result2 = nebula_compose_shader_instanced({
  wgsl_struct = "struct U { pos: vec2<f32>, size: vec2<f32>, bg_color: vec4<f32>, radius: f32 }",
  struct_name = "U",
  has_radius  = true,
  has_border  = false,
})
check("5.3_compose_radius_has_rounded", result2.source:find("fn sdf_rounded_rect") ~= nil)

-- Custom SDF via sdf_shape parameter
local result3 = nebula_compose_shader_instanced({
  wgsl_struct = "struct U { pos: vec2<f32>, size: vec2<f32>, bg_color: vec4<f32>, radius: f32 }",
  struct_name = "U",
  has_radius  = true,
  has_border  = false,
  sdf_shape   = "circle",
})
check("5.4_compose_custom_sdf_circle", result3.source:find("fn sdf_circle") ~= nil)
check("5.5_compose_custom_no_rect", result3.source:find("fn sdf_rect") == nil)

-- =============================================================================
-- Summary
-- =============================================================================
local total = pass_count + fail_count
print(("smoke_phase5_3_s1: %d/%d passed"):format(pass_count, total))
if fail_count > 0 then
  os.exit(1)
end
