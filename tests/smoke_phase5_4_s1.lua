-- =============================================================================
-- smoke_phase5_4_s1.lua
-- Phase 5.4 Step 1: NEBULA_EASINGS Registry — Smoke Test
--
-- Test groups:
--   1. Registry exists and API available
--   2. Built-in easings self-registered (7 entries)
--   3. Custom easing registration
--   4. Registration validation (duplicates, missing fields, code collision)
--   5. TWEEN_CODE backward compatibility alias
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

-- We need to simulate the derive engine environment
-- Load shader_compose first (it sets up globals)
require("shader_compose")

-- Simulate NEBULA_EASINGS as the derive engine would set up
-- (In real Nelua compile, this lives in nebula_derive_engine.nelua preprocessor)
NEBULA_EASINGS = NEBULA_EASINGS or {}

function nebula_register_easing(name, spec)
  assert(type(name) == "string", "nebula_register_easing: name must be a string")
  assert(type(spec) == "table",  "nebula_register_easing: spec must be a table")
  assert(spec.code ~= nil,       "nebula_register_easing('" .. name .. "'): missing code")
  assert(spec.nelua_expr,        "nebula_register_easing('" .. name .. "'): missing nelua_expr")
  assert(not NEBULA_EASINGS[name],
    "nebula_register_easing: easing '" .. name .. "' already registered")
  for k, v in pairs(NEBULA_EASINGS) do
    assert(v.code ~= spec.code,
      ("nebula_register_easing('%s'): code %d already used by '%s'"):format(name, spec.code, k))
  end
  NEBULA_EASINGS[name] = {
    name       = name,
    code       = spec.code,
    nelua_expr = spec.nelua_expr,
    nelua_fn   = spec.nelua_fn or nil,
    description = spec.description or "",
  }
end

-- Self-register builtins
nebula_register_easing("none",           { code = 0, nelua_expr = "%t",                  description = "Linear" })
nebula_register_easing("ease_out",       { code = 1, nelua_expr = "ease_out(%t)",         description = "Quadratic ease out" })
nebula_register_easing("ease_in",        { code = 2, nelua_expr = "ease_in(%t)",          description = "Quadratic ease in" })
nebula_register_easing("ease_in_out",    { code = 3, nelua_expr = "ease_in_out(%t)",      description = "Quadratic ease in-out" })
nebula_register_easing("ease_out_cubic", { code = 4, nelua_expr = "ease_out_cubic(%t)",   description = "Cubic ease out" })
nebula_register_easing("ease_out_expo",  { code = 5, nelua_expr = "ease_out_expo(%t)",    description = "Exponential ease out" })
nebula_register_easing("spring",         { code = 6, nelua_expr = "ease_spring(%t)",      description = "Critical damping spring" })

-- =============================================================================
-- Test Group 1: Registry exists and API available
-- =============================================================================
check("1.1_registry_exists", type(NEBULA_EASINGS) == "table")
check("1.2_register_api", type(nebula_register_easing) == "function")

-- =============================================================================
-- Test Group 2: Built-in easings self-registered
-- =============================================================================
check("2.1_none_registered",      NEBULA_EASINGS["none"] ~= nil)
check("2.2_ease_out_registered",  NEBULA_EASINGS["ease_out"] ~= nil)
check("2.3_ease_in_registered",   NEBULA_EASINGS["ease_in"] ~= nil)
check("2.4_ease_in_out_registered", NEBULA_EASINGS["ease_in_out"] ~= nil)
check("2.5_ease_out_cubic_registered", NEBULA_EASINGS["ease_out_cubic"] ~= nil)
check("2.6_ease_out_expo_registered",  NEBULA_EASINGS["ease_out_expo"] ~= nil)
check("2.7_spring_registered",    NEBULA_EASINGS["spring"] ~= nil)

-- Count total
local count = 0
for _ in pairs(NEBULA_EASINGS) do count = count + 1 end
check("2.8_exactly_7_builtins", count == 7)

-- Verify codes
check("2.9_none_code_0",      NEBULA_EASINGS["none"].code == 0)
check("2.10_ease_out_code_1", NEBULA_EASINGS["ease_out"].code == 1)
check("2.11_ease_in_code_2",  NEBULA_EASINGS["ease_in"].code == 2)
check("2.12_ease_in_out_code_3", NEBULA_EASINGS["ease_in_out"].code == 3)
check("2.13_cubic_code_4", NEBULA_EASINGS["ease_out_cubic"].code == 4)
check("2.14_expo_code_5",  NEBULA_EASINGS["ease_out_expo"].code == 5)
check("2.15_spring_code_6", NEBULA_EASINGS["spring"].code == 6)

-- Verify nelua_expr
check("2.16_none_expr", NEBULA_EASINGS["none"].nelua_expr == "%t")
check("2.17_ease_out_expr", NEBULA_EASINGS["ease_out"].nelua_expr == "ease_out(%t)")
check("2.18_spring_expr", NEBULA_EASINGS["spring"].nelua_expr == "ease_spring(%t)")

-- =============================================================================
-- Test Group 3: Custom easing registration
-- =============================================================================
nebula_register_easing("bounce", {
  code = 100,
  nelua_expr = "ease_bounce(%t)",
  nelua_fn = "global function ease_bounce(t: float32): float32 return t end",
  description = "Bounce easing",
})
check("3.1_custom_registered", NEBULA_EASINGS["bounce"] ~= nil)
check("3.2_custom_code", NEBULA_EASINGS["bounce"].code == 100)
check("3.3_custom_expr", NEBULA_EASINGS["bounce"].nelua_expr == "ease_bounce(%t)")
check("3.4_custom_fn", NEBULA_EASINGS["bounce"].nelua_fn:find("ease_bounce") ~= nil)

-- =============================================================================
-- Test Group 4: Registration validation
-- =============================================================================
-- Duplicate name
local ok1 = pcall(nebula_register_easing, "none", { code = 99, nelua_expr = "%t" })
check("4.1_duplicate_name_rejected", not ok1)

-- Duplicate code
local ok2 = pcall(nebula_register_easing, "new_easing", { code = 1, nelua_expr = "%t" })
check("4.2_duplicate_code_rejected", not ok2)

-- Missing code
local ok3 = pcall(nebula_register_easing, "bad1", { nelua_expr = "%t" })
check("4.3_missing_code_rejected", not ok3)

-- Missing nelua_expr
local ok4 = pcall(nebula_register_easing, "bad2", { code = 200 })
check("4.4_missing_expr_rejected", not ok4)

-- =============================================================================
-- Test Group 5: TWEEN_CODE backward compat
-- =============================================================================
TWEEN_CODE = setmetatable({}, {
  __index = function(_, key)
    local e = NEBULA_EASINGS[key]
    return e and e.code or nil
  end
})
check("5.1_tween_code_none",     TWEEN_CODE["none"] == 0)
check("5.2_tween_code_ease_out", TWEEN_CODE["ease_out"] == 1)
check("5.3_tween_code_ease_in",  TWEEN_CODE["ease_in"] == 2)
check("5.4_tween_code_spring",   TWEEN_CODE["spring"] == 6)
check("5.5_tween_code_unknown",  TWEEN_CODE["nonexistent"] == nil)

-- =============================================================================
-- Test Group 6: nelua_expr substitution
-- =============================================================================
local function subst(expr, var)
  return expr:gsub("%%t", var)
end
check("6.1_subst_none", subst(NEBULA_EASINGS["none"].nelua_expr, "t") == "t")
check("6.2_subst_ease_out", subst(NEBULA_EASINGS["ease_out"].nelua_expr, "t") == "ease_out(t)")
check("6.3_subst_spring", subst(NEBULA_EASINGS["spring"].nelua_expr, "my_t") == "ease_spring(my_t)")

-- =============================================================================
-- Summary
-- =============================================================================
local total = pass_count + fail_count
print(("smoke_phase5_4_s1: %d/%d passed"):format(pass_count, total))
if fail_count > 0 then
  os.exit(1)
end
