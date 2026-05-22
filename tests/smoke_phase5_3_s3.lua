-- =============================================================================
-- smoke_phase5_3_s3.lua
-- Phase 5.3 Step 3: Compose functions use SDF registry — WGSL output test
--
-- Test groups:
--   1. nebula_compose_shader_instanced → registry SDF in WGSL output
--   2. nebula_compose_shadow_shaders → registry SDF in WGSL output
--   3. Custom SDF flows through to WGSL output
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

local ver = require("shader_compose")

-- Register a test SDF for this suite
nebula_register_sdf_shape("star", {
  fn_name     = "sdf_star",
  wgsl_source = [[
fn sdf_star(p: vec2<f32>, r: f32, n: u32) -> f32 {
  return length(p) - r;
}
]],
  params       = "p: vec2<f32>, r: f32, n: u32",
  returns      = "f32",
  extra_fields = {{ name = "radius", type = "f32" }},
})

-- =============================================================================
-- Test Group 1: nebula_compose_shader_instanced WGSL output
-- =============================================================================
local struct_def = "struct Uniforms { pos: vec2<f32>, size: vec2<f32>, bg_color: vec4<f32> }"

-- Default (no radius) → sdf_rect
local r1 = nebula_compose_shader_instanced({
  wgsl_struct = struct_def, struct_name = "Uniforms",
  has_radius = false, has_border = false,
})
check("1.1_default_has_sdf_rect_fn", r1.source:find("fn sdf_rect%(") ~= nil)
check("1.2_default_has_sdf_rect_call", r1.source:find("sdf_rect%(p, half_size%)") ~= nil)
check("1.3_default_instanced_flag", r1.instanced == true)
check("1.4_default_standard_visual", r1.standard_visual == true)

-- With radius → sdf_rounded_rect
local r2 = nebula_compose_shader_instanced({
  wgsl_struct = struct_def .. "\n", struct_name = "Uniforms",
  has_radius = true, has_border = false,
})
check("1.5_radius_has_rounded_fn", r2.source:find("fn sdf_rounded_rect%(") ~= nil)
check("1.6_radius_has_rounded_call", r2.source:find("sdf_rounded_rect%(p, half_size, d.radius%)") ~= nil)

-- Custom sdf_shape = "star"
local r3 = nebula_compose_shader_instanced({
  wgsl_struct = struct_def, struct_name = "Uniforms",
  has_radius = false, has_border = false,
  sdf_shape = "star",
})
check("1.7_star_has_sdf_star_fn", r3.source:find("fn sdf_star%(") ~= nil)
check("1.8_star_no_sdf_rect", r3.source:find("fn sdf_rect%(") == nil)

-- =============================================================================
-- Test Group 2: nebula_compose_shadow_shaders WGSL output
-- =============================================================================
local shadow_struct = "struct Uniforms { pos: vec2<f32>, size: vec2<f32>, bg_color: vec4<f32>, radius: f32, shadow_offset: vec2<f32>, shadow_blur: f32 }"

-- Default shadow with radius
local s1 = nebula_compose_shadow_shaders({
  wgsl_struct = shadow_struct, struct_name = "Uniforms",
  has_radius = true, has_border = false,
})
check("2.1_shadow_has_mask", s1.shadow_mask_source ~= nil)
check("2.2_shadow_has_blur_h", s1.blur_h_source ~= nil)
check("2.3_shadow_has_blur_v", s1.blur_v_source ~= nil)
check("2.4_shadow_has_composite", s1.composite_source ~= nil)
check("2.5_shadow_mask_has_rounded", s1.shadow_mask_source:find("fn sdf_rounded_rect%(") ~= nil)
check("2.6_shadow_mask_has_rounded_call", s1.shadow_mask_source:find("sdf_rounded_rect%(p, half_size, u.radius%)") ~= nil)
check("2.7_shadow_features", s1.features[1] == "shadow_multipass")

-- Default shadow without radius
local s2 = nebula_compose_shadow_shaders({
  wgsl_struct = shadow_struct, struct_name = "Uniforms",
  has_radius = false, has_border = false,
})
check("2.8_shadow_no_radius_has_rect", s2.shadow_mask_source:find("fn sdf_rect%(") ~= nil)
check("2.9_shadow_no_radius_rect_call", s2.shadow_mask_source:find("sdf_rect%(p, half_size%)") ~= nil)

-- Custom SDF in shadow path
local s3 = nebula_compose_shadow_shaders({
  wgsl_struct = shadow_struct, struct_name = "Uniforms",
  has_radius = false, has_border = false,
  sdf_shape = "star",
})
check("2.10_shadow_custom_star", s3.shadow_mask_source:find("fn sdf_star%(") ~= nil)

-- =============================================================================
-- Test Group 3: Text/Slug/Dense composers unchanged
-- =============================================================================
local t1 = nebula_compose_text_shader({ struct_name = "TextUniforms" })
check("3.1_text_shader_ok", t1.source:find("fs_main") ~= nil)
check("3.2_text_textured", t1.textured == true)

local t2 = nebula_compose_slug_shader({})
check("3.3_slug_shader_ok", t2.source:find("slug_calc_coverage") ~= nil)
check("3.4_slug_bindings", t2.slug_bindings == true)

local t3 = nebula_compose_dense_text_shader({})
check("3.5_dense_shader_ok", t3.source:find("DenseCharInstance") ~= nil)
check("3.6_dense_atlas", t3.atlas_dense == true)

-- =============================================================================
-- Summary
-- =============================================================================
local total = pass_count + fail_count
print(("smoke_phase5_3_s3: %d/%d passed"):format(pass_count, total))
if fail_count > 0 then
  os.exit(1)
end
