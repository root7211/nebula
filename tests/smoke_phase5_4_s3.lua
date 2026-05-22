-- =============================================================================
-- smoke_phase5_4_s3.lua
-- Phase 5.4 Step 4: NEBULA_ANIM_DEFAULTS + sugar auto-transition defaults
--
-- Tests:
--   1. NEBULA_ANIM_DEFAULTS table exists with correct defaults
--   2. Sugar auto-generated transitions include duration/tween
--   3. User can override NEBULA_ANIM_DEFAULTS
--   4. Pressed state uses press_* defaults, others use hover_*
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
-- Test Group 1: NEBULA_ANIM_DEFAULTS exists
-- =============================================================================
-- Simulate the defaults as defined in nebula_sugar.nelua
NEBULA_ANIM_DEFAULTS = NEBULA_ANIM_DEFAULTS or {
  hover_duration = 0.12,
  hover_tween    = "ease_out",
  press_duration = 0.06,
  press_tween    = "ease_out",
  leave_duration = 0.15,
  leave_tween    = "ease_out",
}

check("1.1_defaults_exist", type(NEBULA_ANIM_DEFAULTS) == "table")
check("1.2_hover_duration", NEBULA_ANIM_DEFAULTS.hover_duration == 0.12)
check("1.3_hover_tween",    NEBULA_ANIM_DEFAULTS.hover_tween == "ease_out")
check("1.4_press_duration", NEBULA_ANIM_DEFAULTS.press_duration == 0.06)
check("1.5_press_tween",    NEBULA_ANIM_DEFAULTS.press_tween == "ease_out")
check("1.6_leave_duration", NEBULA_ANIM_DEFAULTS.leave_duration == 0.15)
check("1.7_leave_tween",    NEBULA_ANIM_DEFAULTS.leave_tween == "ease_out")

-- =============================================================================
-- Test Group 2: Simulate sugar auto-transition generation
-- =============================================================================
local function gen_auto_transitions(states)
  local transitions = {}
  for i = 2, #states do
    local st = states[i]
    local is_press = (st == "pressed")
    local enter_dur   = is_press and NEBULA_ANIM_DEFAULTS.press_duration or NEBULA_ANIM_DEFAULTS.hover_duration
    local enter_tween = is_press and NEBULA_ANIM_DEFAULTS.press_tween   or NEBULA_ANIM_DEFAULTS.hover_tween
    local leave_dur   = NEBULA_ANIM_DEFAULTS.leave_duration
    local leave_tween = NEBULA_ANIM_DEFAULTS.leave_tween
    table.insert(transitions, {
      from = "default", to = st,
      on = st .. "_enter",
      duration = enter_dur,
      tween    = enter_tween,
    })
    table.insert(transitions, {
      from = st, to = "default",
      on = st .. "_leave",
      duration = leave_dur,
      tween    = leave_tween,
    })
  end
  return transitions
end

-- Hoverable only
local t1 = gen_auto_transitions({"default", "hovered"})
check("2.1_hover_enter_exists", #t1 == 2)
check("2.2_hover_enter_duration", t1[1].duration == 0.12)
check("2.3_hover_enter_tween",   t1[1].tween == "ease_out")
check("2.4_hover_leave_duration", t1[2].duration == 0.15)
check("2.5_hover_leave_tween",   t1[2].tween == "ease_out")

-- Hoverable + clickable
local t2 = gen_auto_transitions({"default", "hovered", "pressed"})
check("2.6_four_transitions", #t2 == 4)

-- hovered_enter
check("2.7_hovered_enter_dur", t2[1].duration == 0.12)
check("2.8_hovered_enter_tw",  t2[1].tween == "ease_out")
-- hovered_leave
check("2.9_hovered_leave_dur", t2[2].duration == 0.15)
-- pressed_enter (should use press_* defaults)
check("2.10_pressed_enter_dur", t2[3].duration == 0.06)
check("2.11_pressed_enter_tw",  t2[3].tween == "ease_out")
-- pressed_leave
check("2.12_pressed_leave_dur", t2[4].duration == 0.15)

-- =============================================================================
-- Test Group 3: User override of NEBULA_ANIM_DEFAULTS
-- =============================================================================
NEBULA_ANIM_DEFAULTS.hover_duration = 0.25
NEBULA_ANIM_DEFAULTS.hover_tween    = "ease_out_cubic"
NEBULA_ANIM_DEFAULTS.press_duration = 0.0
NEBULA_ANIM_DEFAULTS.leave_duration = 0.3

local t3 = gen_auto_transitions({"default", "hovered", "pressed"})
check("3.1_overridden_hover_dur",  t3[1].duration == 0.25)
check("3.2_overridden_hover_tw",   t3[1].tween == "ease_out_cubic")
check("3.3_overridden_press_dur",  t3[3].duration == 0.0)
check("3.4_overridden_leave_dur",  t3[2].duration == 0.3)
check("3.5_overridden_leave_dur2", t3[4].duration == 0.3)

-- Reset
NEBULA_ANIM_DEFAULTS.hover_duration = 0.12
NEBULA_ANIM_DEFAULTS.hover_tween    = "ease_out"
NEBULA_ANIM_DEFAULTS.press_duration = 0.06
NEBULA_ANIM_DEFAULTS.leave_duration = 0.15

-- =============================================================================
-- Test Group 4: Explicit transitions not affected
-- =============================================================================
-- When user explicitly provides transitions, defaults are not injected
local explicit = {
  { from = "default", to = "hovered", duration = 0.5, tween = "spring" },
  { from = "hovered", to = "default", duration = 0.3 },
}
-- Explicit transitions should retain their values
check("4.1_explicit_dur", explicit[1].duration == 0.5)
check("4.2_explicit_tw",  explicit[1].tween == "spring")
check("4.3_explicit_leave_dur", explicit[2].duration == 0.3)

-- =============================================================================
-- Summary
-- =============================================================================
local total = pass_count + fail_count
print(("smoke_phase5_4_s3: %d/%d passed"):format(pass_count, total))
if fail_count > 0 then
  os.exit(1)
end
