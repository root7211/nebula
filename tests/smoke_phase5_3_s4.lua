-- =============================================================================
-- smoke_phase5_3_s4.lua
-- Phase 5.3 Step 4: Axiom Validator + annotate integration — Smoke Test
--
-- Test groups:
--   1. nebula_annotate stores sdf_shape / shader_composer
--   2. axiom_validator rejects unknown sdf_shape
--   3. axiom_validator rejects unknown shader_composer
--   4. axiom_validator checks SDF extra_fields
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

-- Load shader_compose (populates NEBULA_SDF_SHAPES + NEBULA_SHADER_COMPOSERS)
require("shader_compose")

-- Load axiom_validator
local av_ver = require("axiom_validator")
check("0.1_axiom_validator_loads", av_ver ~= nil)
check("0.2_axiom_validator_version", type(av_ver) == "string" and av_ver:find("phase5.3") ~= nil)

-- We need nebula_registry to be global for axiom_validator to read
nebula_registry = nebula_registry or {}

-- =============================================================================
-- Test Group 1: annotate stores new fields
-- =============================================================================
-- Simulate nebula_annotate behavior (we can't call the real one without Nelua)
local function mock_annotate(type_name, spec)
  nebula_registry[type_name] = {
    states        = spec.states or {"default"},
    primitives    = spec.primitives or {},
    transitions   = spec.transitions or {},
    component_id  = spec.component_id or 0,
    text_mode     = spec.text_mode or nil,
    sdf_shape     = spec.sdf_shape or nil,
    shader_composer = spec.shader_composer or nil,
  }
end

mock_annotate("TestVisualA", { sdf_shape = "rect" })
check("1.1_sdf_shape_stored", nebula_registry["TestVisualA"].sdf_shape == "rect")

mock_annotate("TestVisualB", { shader_composer = "instanced" })
check("1.2_shader_composer_stored", nebula_registry["TestVisualB"].shader_composer == "instanced")

mock_annotate("TestVisualC", { sdf_shape = "rounded_rect", shader_composer = "shadow" })
check("1.3_both_stored", nebula_registry["TestVisualC"].sdf_shape == "rounded_rect")
check("1.4_both_stored_2", nebula_registry["TestVisualC"].shader_composer == "shadow")

mock_annotate("TestVisualD", {})
check("1.5_nil_by_default", nebula_registry["TestVisualD"].sdf_shape == nil)
check("1.6_nil_by_default_2", nebula_registry["TestVisualD"].shader_composer == nil)

-- =============================================================================
-- Test Group 2: axiom_validator accepts valid sdf_shape
-- =============================================================================
local base_fields_with_radius = {
  { name = "pos",      type = "Vec2" },
  { name = "size",     type = "Vec2" },
  { name = "radius",   type = "float32" },
  { name = "bg_color", type = "Vec4" },
}
local state_fields_empty = { default = {} }

-- Valid sdf_shape = "rounded_rect" with radius field present
mock_annotate("ValidRR", { sdf_shape = "rounded_rect" })
local ok1 = pcall(nebula_validate_visual, "ValidRR", base_fields_with_radius, state_fields_empty)
check("2.1_valid_sdf_accepted", ok1)

-- Valid sdf_shape = "rect" (no extra_fields required)
mock_annotate("ValidRect", { sdf_shape = "rect" })
local base_fields_no_radius = {
  { name = "pos",  type = "Vec2" },
  { name = "size", type = "Vec2" },
}
local ok2 = pcall(nebula_validate_visual, "ValidRect", base_fields_no_radius, state_fields_empty)
check("2.2_valid_rect_accepted", ok2)

-- =============================================================================
-- Test Group 3: axiom_validator rejects unknown sdf_shape
-- =============================================================================
mock_annotate("BadSDF", { sdf_shape = "nonexistent_shape" })
local ok3 = pcall(nebula_validate_visual, "BadSDF", base_fields_no_radius, state_fields_empty)
check("3.1_unknown_sdf_rejected", not ok3)

-- =============================================================================
-- Test Group 4: axiom_validator rejects unknown shader_composer
-- =============================================================================
mock_annotate("BadComposer", { shader_composer = "nonexistent_composer" })
local ok4 = pcall(nebula_validate_visual, "BadComposer", base_fields_no_radius, state_fields_empty)
check("4.1_unknown_composer_rejected", not ok4)

-- Valid shader_composer accepted
mock_annotate("ValidComposer", { shader_composer = "instanced" })
local ok5 = pcall(nebula_validate_visual, "ValidComposer", base_fields_no_radius, state_fields_empty)
check("4.2_valid_composer_accepted", ok5)

-- =============================================================================
-- Test Group 5: axiom_validator checks SDF extra_fields
-- =============================================================================
-- sdf_shape = "rounded_rect" requires "radius" field, but it's missing
mock_annotate("MissingRadius", { sdf_shape = "rounded_rect" })
local ok6 = pcall(nebula_validate_visual, "MissingRadius", base_fields_no_radius, state_fields_empty)
check("5.1_missing_extra_field_rejected", not ok6)

-- sdf_shape = "rounded_rect" with radius present → accepted
mock_annotate("HasRadius", { sdf_shape = "rounded_rect" })
local ok7 = pcall(nebula_validate_visual, "HasRadius", base_fields_with_radius, state_fields_empty)
check("5.2_extra_field_present_accepted", ok7)

-- Register a custom SDF with extra_fields, verify validator checks them
nebula_register_sdf_shape("test_ellipse", {
  fn_name     = "sdf_ellipse",
  wgsl_source = "fn sdf_ellipse() -> f32 { return 0.0; }",
  params      = "p: vec2<f32>, r: vec2<f32>",
  extra_fields = {{ name = "radii", type = "Vec2" }},
})
mock_annotate("MissingRadii", { sdf_shape = "test_ellipse" })
local ok8 = pcall(nebula_validate_visual, "MissingRadii", base_fields_no_radius, state_fields_empty)
check("5.3_custom_extra_field_rejected", not ok8)

local base_with_radii = {
  { name = "pos",   type = "Vec2" },
  { name = "radii", type = "Vec2" },
}
mock_annotate("HasRadii", { sdf_shape = "test_ellipse" })
local ok9 = pcall(nebula_validate_visual, "HasRadii", base_with_radii, state_fields_empty)
check("5.4_custom_extra_field_accepted", ok9)

-- =============================================================================
-- Summary
-- =============================================================================
local total = pass_count + fail_count
print(("smoke_phase5_3_s4: %d/%d passed"):format(pass_count, total))
if fail_count > 0 then
  os.exit(1)
end
