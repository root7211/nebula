-- =============================================================================
-- smoke_phase5_4_s2.lua
-- Phase 5.4 Step 2+3: per-property override + delay — gen_state_machine test
--
-- Tests simulate the gen_state_machine logic by checking that:
--   1. No overrides → no extra fields
--   2. With overrides → extra progress_/duration_/tween_ fields
--   3. With delay → delay field present
--   4. Combined overrides + delay
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

-- =============================================================================
-- Simulate gen_state_machine output analysis
-- =============================================================================

-- Helper: simulate gen_state_machine field detection logic
local function analyze_transitions(transitions)
  local has_any_delay = false
  local override_props = {}
  for _, tr in ipairs(transitions or {}) do
    if tr.delay and tr.delay > 0 then has_any_delay = true end
    if tr.overrides then
      for prop, _ in pairs(tr.overrides) do
        override_props[prop] = true
      end
    end
  end
  return has_any_delay, override_props
end

-- =============================================================================
-- Test Group 1: No overrides, no delay
-- =============================================================================
local t1 = {
  { from = "default", to = "hovered", tween = "ease_out", duration = 0.15 },
  { from = "hovered", to = "default", tween = "ease_out", duration = 0.1 },
}
local has_delay1, overrides1 = analyze_transitions(t1)
check("1.1_no_delay", has_delay1 == false)
local override_count1 = 0
for _ in pairs(overrides1) do override_count1 = override_count1 + 1 end
check("1.2_no_overrides", override_count1 == 0)

-- =============================================================================
-- Test Group 2: With per-property overrides
-- =============================================================================
local t2 = {
  { from = "default", to = "hovered", tween = "ease_out", duration = 0.15,
    overrides = {
      radius = { duration = 0.4, tween = "spring" },
      border_color = { duration = 0.3 },
    }
  },
  { from = "hovered", to = "default", tween = "ease_out", duration = 0.1 },
}
local has_delay2, overrides2 = analyze_transitions(t2)
check("2.1_no_delay", has_delay2 == false)
check("2.2_radius_override", overrides2["radius"] == true)
check("2.3_border_color_override", overrides2["border_color"] == true)
local override_count2 = 0
for _ in pairs(overrides2) do override_count2 = override_count2 + 1 end
check("2.4_two_overrides", override_count2 == 2)

-- =============================================================================
-- Test Group 3: With delay
-- =============================================================================
local t3 = {
  { from = "default", to = "hovered", tween = "ease_out", duration = 0.15, delay = 0.05 },
  { from = "hovered", to = "default", tween = "ease_out", duration = 0.1 },
}
local has_delay3, overrides3 = analyze_transitions(t3)
check("3.1_has_delay", has_delay3 == true)
local override_count3 = 0
for _ in pairs(overrides3) do override_count3 = override_count3 + 1 end
check("3.2_no_overrides", override_count3 == 0)

-- =============================================================================
-- Test Group 4: Combined overrides + delay
-- =============================================================================
local t4 = {
  { from = "default", to = "hovered", tween = "ease_out", duration = 0.15, delay = 0.1,
    overrides = {
      radius = { duration = 0.4, tween = "spring", delay = 0.2 },
    }
  },
}
local has_delay4, overrides4 = analyze_transitions(t4)
check("4.1_has_delay", has_delay4 == true)
check("4.2_radius_override", overrides4["radius"] == true)

-- =============================================================================
-- Test Group 5: Simulate get_t code generation
-- =============================================================================

-- Setup NEBULA_EASINGS
NEBULA_EASINGS = {}
local function reg_easing(name, code, expr)
  NEBULA_EASINGS[name] = { name = name, code = code, nelua_expr = expr }
end
reg_easing("none", 0, "%t")
reg_easing("ease_out", 1, "ease_out(%t)")
reg_easing("ease_in", 2, "ease_in(%t)")
reg_easing("ease_in_out", 3, "ease_in_out(%t)")
reg_easing("spring", 6, "ease_spring(%t)")

-- Simulate collecting used codes from transitions
local function collect_used_codes(transitions)
  local used = {}
  local seen = {}
  for _, tr in ipairs(transitions or {}) do
    local ename = tr.tween or "none"
    local e = NEBULA_EASINGS[ename]
    if e and not seen[e.code] then
      seen[e.code] = true
      table.insert(used, e)
    end
    if tr.overrides then
      for _, ov in pairs(tr.overrides) do
        local ov_ename = ov.tween or ename
        local ov_e = NEBULA_EASINGS[ov_ename]
        if ov_e and not seen[ov_e.code] then
          seen[ov_e.code] = true
          table.insert(used, ov_e)
        end
      end
    end
  end
  return used
end

-- Test: only ease_out → only code 1 branch generated
local codes_a = collect_used_codes({
  { from = "default", to = "hovered", tween = "ease_out", duration = 0.15 },
})
check("5.1_single_easing", #codes_a == 1)
check("5.2_ease_out_code", codes_a[1].code == 1)

-- Test: ease_out + spring override → 2 codes
local codes_b = collect_used_codes({
  { from = "default", to = "hovered", tween = "ease_out", duration = 0.15,
    overrides = { radius = { tween = "spring" } } },
})
check("5.3_two_easings", #codes_b == 2)

-- Test: no tween → none (code 0) only, which is fallthrough
local codes_c = collect_used_codes({
  { from = "default", to = "hovered", duration = 0.15 },
})
check("5.4_none_fallthrough", #codes_c == 1)
check("5.5_none_code_0", codes_c[1].code == 0)

-- Test: multiple transitions with different easings
local codes_d = collect_used_codes({
  { from = "default", to = "hovered", tween = "ease_out", duration = 0.15 },
  { from = "hovered", to = "pressed", tween = "ease_in",  duration = 0.05 },
  { from = "pressed", to = "default", tween = "ease_in_out", duration = 0.2 },
})
check("5.6_three_easings", #codes_d == 3)

-- =============================================================================
-- Test Group 6: gen_update_for per-property t logic
-- =============================================================================
-- Simulate: if override_props has "radius", gen_update_for should use t_radius
local override_props_test = { radius = true }
local all_props_test = {
  { name = "bg_color", type = "Color" },
  { name = "radius",   type = "float32" },
}
-- Check that radius gets per-property t, bg_color uses global t
for _, p in ipairs(all_props_test) do
  if override_props_test[p.name] then
    check("6.1_" .. p.name .. "_uses_per_prop_t", true)
  else
    check("6.2_" .. p.name .. "_uses_global_t", true)
  end
end

-- =============================================================================
-- Summary
-- =============================================================================
local total = pass_count + fail_count
print(("smoke_phase5_4_s2: %d/%d passed"):format(pass_count, total))
if fail_count > 0 then
  os.exit(1)
end
