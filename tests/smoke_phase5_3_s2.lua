-- =============================================================================
-- smoke_phase5_3_s2.lua
-- Phase 5.3 Step 2: NEBULA_SHADER_COMPOSERS Registry — Smoke Test
--
-- Test groups:
--   1. Registry exists and API available
--   2. Built-in composers self-registered (5 entries)
--   3. Custom composer registration
--   4. Registration validation
--   5. nebula_resolve_shader_composer dispatch logic
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

-- Load module (also loads SDF shapes)
local ver = require("shader_compose")

-- =============================================================================
-- Test Group 1: Registry exists and API available
-- =============================================================================
check("1.1_registry_exists", type(NEBULA_SHADER_COMPOSERS) == "table")
check("1.2_register_api", type(nebula_register_shader_composer) == "function")
check("1.3_resolve_api", type(nebula_resolve_shader_composer) == "function")

-- =============================================================================
-- Test Group 2: Built-in composers self-registered
-- =============================================================================
check("2.1_instanced_registered", NEBULA_SHADER_COMPOSERS["instanced"] ~= nil)
check("2.2_shadow_registered",    NEBULA_SHADER_COMPOSERS["shadow"] ~= nil)
check("2.3_text_sdf_registered",  NEBULA_SHADER_COMPOSERS["text_sdf"] ~= nil)
check("2.4_slug_registered",      NEBULA_SHADER_COMPOSERS["slug"] ~= nil)
check("2.5_dense_text_registered", NEBULA_SHADER_COMPOSERS["dense_text"] ~= nil)

-- Count total
local count = 0
for _ in pairs(NEBULA_SHADER_COMPOSERS) do count = count + 1 end
check("2.6_exactly_5_builtins", count == 5)

-- Verify instanced fields
local inst = NEBULA_SHADER_COMPOSERS["instanced"]
check("2.7_instanced_compose_fn", type(inst.compose) == "function")
check("2.8_instanced_pipeline_flag", inst.pipeline_flag == "standard_instanced")
check("2.9_instanced_match_fn", type(inst.match) == "function")
check("2.10_instanced_priority", inst.priority == 0)

-- Verify shadow fields
local shd = NEBULA_SHADER_COMPOSERS["shadow"]
check("2.11_shadow_priority", shd.priority == 10)
check("2.12_shadow_pipeline_flag", shd.pipeline_flag == "has_shadow")

-- Verify text composers have higher priority
check("2.13_text_sdf_priority", NEBULA_SHADER_COMPOSERS["text_sdf"].priority == 20)
check("2.14_slug_priority", NEBULA_SHADER_COMPOSERS["slug"].priority == 20)
check("2.15_dense_priority", NEBULA_SHADER_COMPOSERS["dense_text"].priority == 20)

-- =============================================================================
-- Test Group 3: Custom composer registration
-- =============================================================================
nebula_register_shader_composer("gradient_fill", {
  compose = function(opts) return { source = "gradient shader", features = {"gradient"} } end,
  pipeline_flag = "gradient_instanced",
  match = function(reg, feats) return reg.render_mode == "gradient" end,
  priority = 30,
  description = "Gradient fill shader",
})
check("3.1_custom_registered", NEBULA_SHADER_COMPOSERS["gradient_fill"] ~= nil)
check("3.2_custom_compose", type(NEBULA_SHADER_COMPOSERS["gradient_fill"].compose) == "function")
check("3.3_custom_priority", NEBULA_SHADER_COMPOSERS["gradient_fill"].priority == 30)

-- Verify custom compose works
local gr = NEBULA_SHADER_COMPOSERS["gradient_fill"].compose({})
check("3.4_custom_compose_output", gr.source == "gradient shader")

-- =============================================================================
-- Test Group 4: Registration validation
-- =============================================================================
-- Duplicate
local ok1 = pcall(nebula_register_shader_composer, "instanced", {
  compose = function() end, pipeline_flag = "x",
})
check("4.1_duplicate_rejected", not ok1)

-- Missing compose
local ok2 = pcall(nebula_register_shader_composer, "bad1", {
  pipeline_flag = "x",
})
check("4.2_missing_compose_rejected", not ok2)

-- Missing pipeline_flag
local ok3 = pcall(nebula_register_shader_composer, "bad2", {
  compose = function() end,
})
check("4.3_missing_flag_rejected", not ok3)

-- =============================================================================
-- Test Group 5: nebula_resolve_shader_composer dispatch logic
-- =============================================================================

-- Case A: standard instanced (no text_mode, no shadow)
local reg_standard = { text_mode = nil, shader_composer = nil }
local feats_standard = { has_shadow = false }
local resolved_a = nebula_resolve_shader_composer(reg_standard, feats_standard)
check("5.1_standard_resolves_instanced", resolved_a ~= nil and resolved_a.name == "instanced")

-- Case B: shadow path (no text_mode, has_shadow)
local reg_shadow = { text_mode = nil, shader_composer = nil }
local feats_shadow = { has_shadow = true }
local resolved_b = nebula_resolve_shader_composer(reg_shadow, feats_shadow)
check("5.2_shadow_resolves_shadow", resolved_b ~= nil and resolved_b.name == "shadow")

-- Case C: text_mode = "ascii_sdf"
local reg_text = { text_mode = "ascii_sdf", shader_composer = nil }
local feats_text = { has_shadow = false }
local resolved_c = nebula_resolve_shader_composer(reg_text, feats_text)
check("5.3_text_sdf_resolves", resolved_c ~= nil and resolved_c.name == "text_sdf")

-- Case D: text_mode = "slug"
local reg_slug = { text_mode = "slug", shader_composer = nil }
local resolved_d = nebula_resolve_shader_composer(reg_slug, feats_text)
check("5.4_slug_resolves", resolved_d ~= nil and resolved_d.name == "slug")

-- Case E: text_mode = "dense"
local reg_dense = { text_mode = "dense", shader_composer = nil }
local resolved_e = nebula_resolve_shader_composer(reg_dense, feats_text)
check("5.5_dense_resolves", resolved_e ~= nil and resolved_e.name == "dense_text")

-- Case F: explicit shader_composer overrides match
local reg_explicit = { text_mode = nil, shader_composer = "shadow" }
local feats_no_shadow = { has_shadow = false }
local resolved_f = nebula_resolve_shader_composer(reg_explicit, feats_no_shadow)
check("5.6_explicit_overrides", resolved_f ~= nil and resolved_f.name == "shadow")

-- Case G: explicit unknown composer fails
local ok_g = pcall(nebula_resolve_shader_composer, { shader_composer = "nonexistent" }, {})
check("5.7_unknown_explicit_fails", not ok_g)

-- Case H: custom composer matched via render_mode
local reg_gradient = { render_mode = "gradient", shader_composer = nil }
local resolved_h = nebula_resolve_shader_composer(reg_gradient, { has_shadow = false })
check("5.8_custom_match_gradient", resolved_h ~= nil and resolved_h.name == "gradient_fill")

-- Case I: priority ordering — shadow (10) beats instanced (0) when both match
-- Both instanced.match and shadow.match check "not text_mode", but shadow also checks has_shadow
-- When has_shadow=true, only shadow matches (instanced.match returns false), so shadow wins
local reg_both = { text_mode = nil, shader_composer = nil }
local feats_both = { has_shadow = true }
local resolved_i = nebula_resolve_shader_composer(reg_both, feats_both)
check("5.9_priority_shadow_wins", resolved_i ~= nil and resolved_i.name == "shadow")

-- =============================================================================
-- Summary
-- =============================================================================
local total = pass_count + fail_count
print(("smoke_phase5_3_s2: %d/%d passed"):format(pass_count, total))
if fail_count > 0 then
  os.exit(1)
end
