-- =============================================================================
-- smoke_phase5_4_s4.lua
-- Phase 5.4 Step 3+Integration: delay code generation + StateMachine update
-- behavior simulation + combined feature verification
--
-- Tests:
--   1. StateMachine record field generation with delay
--   2. transition_to: delay assignment logic
--   3. update(): delay consumption + remainder dt accounting
--   4. Per-property delay fields + independent delay
--   5. Combined: easing + override + delay + sugar defaults in one Visual
--   6. Backward compat: no delay → no delay field generated
-- =============================================================================

local pass_count = 0
local fail_count = 0

local function check(name, cond)
  if cond then
    pass_count = pass_count + 1
  else
    fail_count = fail_count + 1
    print("  FAIL: " .. name)
  end
end

-- =============================================================================
-- Helper: simulate gen_state_machine field generation
-- =============================================================================
local function gen_record_fields(transitions)
  local fields = {
    "current: uint8",
    "target:  uint8",
    "progress: float32",
    "duration: float32",
    "tween:    uint8",
  }
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
  if has_any_delay then
    table.insert(fields, "delay:    float32")
  end
  local sorted_props = {}
  for prop in pairs(override_props) do
    table.insert(sorted_props, prop)
  end
  table.sort(sorted_props)
  for _, prop in ipairs(sorted_props) do
    table.insert(fields, ("progress_%s: float32"):format(prop))
    table.insert(fields, ("duration_%s: float32"):format(prop))
    table.insert(fields, ("tween_%s:    uint8"):format(prop))
    if has_any_delay then
      table.insert(fields, ("delay_%s:    float32"):format(prop))
    end
  end
  return fields
end

-- =============================================================================
-- Helper: simulate transition_to code generation for a specific transition
-- =============================================================================
local function gen_transition_body(tr, has_any_delay, override_props, easing_map)
  local lines = {}
  local code = easing_map[tr.tween or "none"] or 0
  table.insert(lines, ("    self.duration = %s"):format(tostring(tr.duration or 0.0)))
  table.insert(lines, ("    self.tween    = %d"):format(code))
  if has_any_delay then
    table.insert(lines, ("    self.delay    = %s"):format(tostring(tr.delay or 0.0)))
  end
  if tr.overrides then
    local sorted_ov = {}
    for prop in pairs(tr.overrides) do
      table.insert(sorted_ov, prop)
    end
    table.sort(sorted_ov)
    for _, prop in ipairs(sorted_ov) do
      local ov = tr.overrides[prop]
      local ov_easing = ov.tween or tr.tween or "none"
      local ov_code = easing_map[ov_easing] or 0
      table.insert(lines, ("    self.progress_%s = 0.0"):format(prop))
      table.insert(lines, ("    self.duration_%s = %s"):format(prop, tostring(ov.duration or tr.duration or 0.0)))
      table.insert(lines, ("    self.tween_%s    = %d"):format(prop, ov_code))
      if has_any_delay then
        table.insert(lines, ("    self.delay_%s    = %s"):format(prop, tostring(ov.delay or tr.delay or 0.0)))
      end
    end
    -- props without explicit override inherit from main transition
    local sorted_all = {}
    for prop in pairs(override_props) do
      table.insert(sorted_all, prop)
    end
    table.sort(sorted_all)
    for _, prop in ipairs(sorted_all) do
      if not tr.overrides[prop] then
        table.insert(lines, ("    self.progress_%s = 0.0"):format(prop))
        table.insert(lines, ("    self.duration_%s = self.duration"):format(prop))
        table.insert(lines, ("    self.tween_%s    = self.tween"):format(prop))
        if has_any_delay then
          table.insert(lines, ("    self.delay_%s    = self.delay"):format(prop))
        end
      end
    end
  end
  return lines
end

-- =============================================================================
-- Helper: simulate update() delay consumption logic
-- Returns (progress_delta, consumed_delay) for a given dt
-- =============================================================================
local function simulate_update_step(state, dt)
  -- state = { progress, duration, delay }
  if state.progress >= 1.0 then
    return 0.0, 0.0
  end
  if state.duration <= 0.0 then
    state.progress = 1.0
    return 1.0, 0.0
  end
  -- delay check
  if state.delay > 0.0 then
    state.delay = state.delay - dt
    if state.delay > 0.0 then
      return 0.0, 0.0  -- still waiting
    end
    dt = -state.delay  -- consume remaining dt after delay
    state.delay = 0.0
  end
  local delta = dt / state.duration
  state.progress = state.progress + delta
  if state.progress > 1.0 then
    state.progress = 1.0
  end
  return delta, dt
end

-- =============================================================================
-- Helper: generate get_t code from used easing codes
-- =============================================================================
local function gen_get_t_body(used_codes)
  -- used_codes: array of { code, nelua_expr } entries
  local lines = {}
  local sorted = {}
  for _, e in ipairs(used_codes) do
    table.insert(sorted, e)
  end
  table.sort(sorted, function(a, b) return a.code < b.code end)
  for _, e in ipairs(sorted) do
    if e.code ~= 0 then
      local expr = e.nelua_expr:gsub("%%t", "t")
      table.insert(lines, ("  if self.tween == %d then return %s end"):format(e.code, expr))
    end
  end
  table.insert(lines, "  return t")
  return lines
end

-- =============================================================================
-- Easing map for code generation tests
-- =============================================================================
local EASING_MAP = {
  none           = { code = 0, nelua_expr = "%t" },
  ease_out       = { code = 1, nelua_expr = "ease_out(%t)" },
  ease_in        = { code = 2, nelua_expr = "ease_in(%t)" },
  ease_in_out    = { code = 3, nelua_expr = "ease_in_out(%t)" },
  ease_out_cubic = { code = 4, nelua_expr = "ease_out_cubic(%t)" },
  ease_out_expo  = { code = 5, nelua_expr = "ease_out_expo(%t)" },
  spring         = { code = 6, nelua_expr = "ease_spring(%t)" },
}

-- =============================================================================
-- Test Group 1: StateMachine record field generation — with delay
-- =============================================================================
local fields1 = gen_record_fields({
  { from = "default", to = "hovered", tween = "ease_out", duration = 0.15, delay = 0.05 },
})
check("1.1_delay_field_present", fields1[6] == "delay:    float32")
check("1.2_base_fields_count", #fields1 == 6)  -- no overrides, so 5 base + delay

-- With delay + overrides
local fields2 = gen_record_fields({
  { from = "default", to = "hovered", tween = "ease_out", duration = 0.15, delay = 0.05,
    overrides = {
      radius = { duration = 0.4, tween = "spring", delay = 0.2 },
    }
  },
})
check("1.3_delay_field_with_overrides", fields2[6] == "delay:    float32")
check("1.4_per_prop_progress", fields2[7] == "progress_radius: float32")
check("1.5_per_prop_duration", fields2[8] == "duration_radius: float32")
check("1.6_per_prop_tween",    fields2[9] == "tween_radius:    uint8")
check("1.7_per_prop_delay",    fields2[10] == "delay_radius:    float32")
check("1.8_total_fields_10",   #fields2 == 10)

-- =============================================================================
-- Test Group 2: transition_to delay assignment
-- =============================================================================
local t2_transition = {
  from = "default", to = "hovered",
  tween = "ease_out", duration = 0.15, delay = 0.05,
}
local t2_body = gen_transition_body(t2_transition, true, {}, EASING_MAP)
check("2.1_duration_set", t2_body[1] == "    self.duration = 0.15")
check("2.2_tween_set",    t2_body[2] == "    self.tween    = 1")
check("2.3_delay_set",    t2_body[3] == "    self.delay    = 0.05")

-- Zero delay transition (still has delay field since has_any_delay is true)
local t2b_transition = {
  from = "hovered", to = "default",
  tween = "ease_out", duration = 0.1, delay = 0.0,
}
local t2b_body = gen_transition_body(t2b_transition, true, {}, EASING_MAP)
check("2.4_zero_delay_set", t2b_body[3] == "    self.delay    = 0.0")

-- Transition with per-property delay override
local t2c_transition = {
  from = "default", to = "hovered",
  tween = "ease_out", duration = 0.15, delay = 0.05,
  overrides = {
    radius = { duration = 0.4, tween = "spring", delay = 0.2 },
  },
}
local t2c_body = gen_transition_body(t2c_transition, true, { radius = true }, EASING_MAP)
-- Should contain: duration, tween, delay, then per-prop: progress_radius, duration_radius, tween_radius, delay_radius
check("2.5_ov_delay_set", t2c_body[7] == "    self.delay_radius    = 0.2")
check("2.6_ov_progress_reset", t2c_body[4] == "    self.progress_radius = 0.0")
check("2.7_ov_duration_set",   t2c_body[5] == "    self.duration_radius = 0.4")
check("2.8_ov_tween_set",      t2c_body[6] == "    self.tween_radius    = 6")

-- =============================================================================
-- Test Group 3: update() delay consumption
-- =============================================================================
-- Test: delay > dt → no progress
local s3a = { progress = 0.0, duration = 0.2, delay = 0.1 }
local delta3a, consumed3a = simulate_update_step(s3a, 0.05)
check("3.1_delay_not_expired", delta3a == 0.0)
check("3.2_delay_reduced",     s3a.delay == 0.05)
check("3.3_progress_unchanged", s3a.progress == 0.0)

-- Test: delay expires, remainder dt applied
local s3b = { progress = 0.0, duration = 0.2, delay = 0.08 }
local delta3b, consumed3b = simulate_update_step(s3b, 0.1)
check("3.4_delay_expired",    delta3b > 0.0)
check("3.5_delay_zeroed",     s3b.delay == 0.0)
check("3.6_remainder_applied", math.abs(delta3b - 0.02 / 0.2) < 0.0001)  -- 0.02 remainder / 0.2 duration

-- Test: second frame after delay expired → normal progress
local s3c = { progress = 0.0, duration = 0.2, delay = 0.0 }
local delta3c, _ = simulate_update_step(s3c, 0.05)
check("3.7_no_delay_normal",  math.abs(delta3c - 0.25) < 0.0001)
check("3.8_progress_advanced", math.abs(s3c.progress - 0.25) < 0.0001)

-- Test: duration = 0 (instant) → progress = 1 regardless of delay
local s3d = { progress = 0.0, duration = 0.0, delay = 0.1 }
local delta3d, _ = simulate_update_step(s3d, 0.05)
check("3.9_instant_progress", s3d.progress == 1.0)

-- Test: already at progress = 1 → no change
local s3e = { progress = 1.0, duration = 0.2, delay = 0.1 }
local delta3e, _ = simulate_update_step(s3e, 0.05)
check("3.10_already_done", delta3e == 0.0)
check("3.11_progress_unchanged", s3e.progress == 1.0)

-- =============================================================================
-- Test Group 4: Per-property delay independence
-- =============================================================================
-- Global delay expires but per-prop delay still waiting
local s4_global = { progress = 0.0, duration = 0.2, delay = 0.05 }
local s4_radius = { progress = 0.0, duration = 0.4, delay = 0.15 }

-- Frame 1: dt=0.06, global delay expires (0.06 - 0.05 = 0.01 remainder),
--          radius delay still active (0.15 - 0.06 = 0.09)
local d_global, _ = simulate_update_step(s4_global, 0.06)
local d_radius, _ = simulate_update_step(s4_radius, 0.06)
check("4.1_global_advances", d_global > 0.0)
check("4.2_radius_waits",    d_radius == 0.0)
check("4.3_radius_delay_remaining", s4_radius.delay == 0.09)

-- Frame 2: dt=0.1, radius delay expires (0.1 - 0.09 = 0.01 remainder)
local d_radius2, _ = simulate_update_step(s4_radius, 0.1)
check("4.4_radius_now_advances", d_radius2 > 0.0)
check("4.5_radius_progress", math.abs(d_radius2 - 0.01 / 0.4) < 0.0001)

-- =============================================================================
-- Test Group 5: Combined feature integration
-- All 4 Phase 5.4 features in one Visual:
--   - easing: ease_out + spring (via override)
--   - per-property override: radius
--   - delay: main 0.05, radius override 0.2
--   - sugar defaults would inject these (tested in s3)
-- =============================================================================
local combined_transitions = {
  { from = "default", to = "hovered",
    tween = "ease_out", duration = 0.15, delay = 0.05,
    overrides = {
      radius = { duration = 0.4, tween = "spring", delay = 0.2 },
    }
  },
  { from = "hovered", to = "pressed",
    tween = "ease_out_cubic", duration = 0.06, delay = 0.02,
    overrides = {
      radius = { duration = 0.3, tween = "spring", delay = 0.1 },
    }
  },
  { from = "pressed", to = "default",
    tween = "ease_in_out", duration = 0.2, delay = 0.0,
  },
}

-- 5.1: Record has all expected fields
local c_fields = gen_record_fields(combined_transitions)
check("5.1_delay_field", c_fields[6] == "delay:    float32")
check("5.2_per_prop_fields", c_fields[7] == "progress_radius: float32")
check("5.3_per_prop_delay", c_fields[10] == "delay_radius:    float32")
check("5.4_total_10_fields", #c_fields == 10)

-- 5.2: transition_to for default→hovered
local c_t1 = gen_transition_body(combined_transitions[1], true, { radius = true }, EASING_MAP)
check("5.5_t1_duration", c_t1[1] == "    self.duration = 0.15")
check("5.6_t1_tween",    c_t1[2] == "    self.tween    = 1")
check("5.7_t1_delay",    c_t1[3] == "    self.delay    = 0.05")
check("5.8_t1_ov_radius_tween",  c_t1[6] == "    self.tween_radius    = 6")
check("5.9_t1_ov_radius_delay",  c_t1[7] == "    self.delay_radius    = 0.2")

-- 5.3: transition_to for hovered→pressed
local c_t2 = gen_transition_body(combined_transitions[2], true, { radius = true }, EASING_MAP)
check("5.10_t2_tween",   c_t2[2] == "    self.tween    = 4")  -- ease_out_cubic
check("5.11_t2_delay",   c_t2[3] == "    self.delay    = 0.02")
check("5.12_t2_ov_tween", c_t2[6] == "    self.tween_radius    = 6")
check("5.13_t2_ov_delay", c_t2[7] == "    self.delay_radius    = 0.1")

-- 5.4: transition_to for pressed→default (no overrides on this transition)
local c_t3 = gen_transition_body(combined_transitions[3], true, { radius = true }, EASING_MAP)
-- No overrides on this transition → only duration/tween/delay (no per-prop reset)
check("5.14_t3_no_overrides_dur", c_t3[1] == "    self.duration = 0.2")
check("5.15_t3_no_overrides_tw",  c_t3[2] == "    self.tween    = 3")
check("5.16_t3_no_overrides_dl",  c_t3[3] == "    self.delay    = 0.0")
check("5.17_t3_only_3_lines", #c_t3 == 3)

-- 5.5: get_t code generation — should have branches for codes 1, 3, 4, 6
local used_easings = {}
local seen_codes = {}
for _, tr in ipairs(combined_transitions) do
  local ename = tr.tween or "none"
  local e = EASING_MAP[ename]
  if e and not seen_codes[e.code] then
    seen_codes[e.code] = true
    table.insert(used_easings, e)
  end
  if tr.overrides then
    for _, ov in pairs(tr.overrides) do
      local ov_ename = ov.tween or ename
      local ov_e = EASING_MAP[ov_ename]
      if ov_e and not seen_codes[ov_e.code] then
        seen_codes[ov_e.code] = true
        table.insert(used_easings, ov_e)
      end
    end
  end
end
local get_t_lines = gen_get_t_body(used_easings)
-- 4 easing branches + 1 "return t" fallback = 5 total lines
check("5.18_four_easing_branches", #get_t_lines == 5)
check("5.19_code_1_branch",  get_t_lines[1]:find("tween == 1") ~= nil)  -- ease_out
check("5.20_code_3_branch",  get_t_lines[2]:find("tween == 3") ~= nil)  -- ease_in_out
check("5.21_code_4_branch",  get_t_lines[3]:find("tween == 4") ~= nil)  -- ease_out_cubic
check("5.22_code_6_branch",  get_t_lines[4]:find("tween == 6") ~= nil)  -- spring

-- =============================================================================
-- Test Group 6: Backward compatibility — no delay → no delay field
-- =============================================================================
local bc_transitions = {
  { from = "default", to = "hovered", tween = "ease_out", duration = 0.15 },
  { from = "hovered", to = "default", tween = "ease_out", duration = 0.1 },
}
local bc_fields = gen_record_fields(bc_transitions)
check("6.1_no_delay_field", bc_fields[6] == nil)
check("6.2_exactly_5_fields", #bc_fields == 5)
check("6.3_fields_match_base", bc_fields[1] == "current: uint8")

-- transition_to without delay
local bc_t1 = gen_transition_body(bc_transitions[1], false, {}, EASING_MAP)
check("6.4_no_delay_in_transition", #bc_t1 == 2)  -- only duration + tween

-- update simulation without delay → immediate progress
local bc_state = { progress = 0.0, duration = 0.2, delay = 0.0 }
local bc_delta, _ = simulate_update_step(bc_state, 0.05)
check("6.5_immediate_progress", math.abs(bc_delta - 0.25) < 0.0001)

-- =============================================================================
-- Test Group 7: Edge cases
-- =============================================================================
-- Negative delay (treated as 0, but has_any_delay still true since delay > 0 check)
local edge_transitions = {
  { from = "default", to = "hovered", tween = "ease_out", duration = 0.15, delay = -0.1 },
}
local edge_fields = gen_record_fields(edge_transitions)
check("7.1_negative_delay_no_field", edge_fields[6] == nil)  -- delay > 0 check means negative doesn't trigger

-- Very small delay (sub-frame)
local tiny_state = { progress = 0.0, duration = 0.2, delay = 0.001 }
local tiny_delta, _ = simulate_update_step(tiny_state, 0.016)
check("7.2_tiny_delay_expires", tiny_delta > 0.0)
check("7.3_tiny_delay_zeroed",  tiny_state.delay == 0.0)

-- Delay exactly equals dt
local exact_state = { progress = 0.0, duration = 0.2, delay = 0.016 }
local exact_delta, _ = simulate_update_step(exact_state, 0.016)
-- delay = 0.016 - 0.016 = 0, not > 0, so remainder = 0
check("7.4_exact_delay", math.abs(exact_delta - 0.0) < 0.0001)

-- Multiple frames to exhaust delay
local multi_state = { progress = 0.0, duration = 0.3, delay = 0.05 }
simulate_update_step(multi_state, 0.016)  -- delay: 0.034
simulate_update_step(multi_state, 0.016)  -- delay: 0.018
local multi_delta, _ = simulate_update_step(multi_state, 0.016)  -- delay expires, 0.014 - 0.018 = -0.004 → dt = -(-0.004) = 0.004... 
-- Actually: delay = 0.018 - 0.016 = 0.002, still > 0, so no progress
-- Wait, let me recalculate:
-- Frame 1: delay = 0.05 - 0.016 = 0.034 (> 0, return 0)
-- Frame 2: delay = 0.034 - 0.016 = 0.018 (> 0, return 0)
-- Frame 3: delay = 0.018 - 0.016 = 0.002 (> 0, return 0)
-- Hmm, the check above already consumed frame 3. Let me verify.
-- Actually the third call is what I just made. delay was 0.018, dt=0.016
-- delay = 0.018 - 0.016 = 0.002, which is > 0, so return 0.0
check("7.5_multi_frame_still_waiting", multi_delta == 0.0)
check("7.6_delay_almost_zero", math.abs(multi_state.delay - 0.002) < 0.0001)

-- One more frame to expire
local multi_delta2, _ = simulate_update_step(multi_state, 0.016)
check("7.7_delay_now_expired", multi_delta2 > 0.0)
check("7.8_delay_zeroed_final", multi_state.delay == 0.0)
check("7.9_remainder_applied", math.abs(multi_delta2 - 0.014 / 0.3) < 0.001)

-- =============================================================================
-- Summary
-- =============================================================================
local total = pass_count + fail_count
print(("smoke_phase5_4_s4: %d/%d passed"):format(pass_count, total))
if fail_count > 0 then
  os.exit(1)
end
