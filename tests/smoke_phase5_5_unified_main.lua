-- =============================================================================
-- smoke_phase5_5_unified_main.lua
-- Phase 5.5: nebula_main 统一声明模式 — Smoke Test
--
-- Verifies:
--   1. nebula_main 接受 components/states/bindings/events 并自动委托 nebula_app
--   2. counter_unified_demo.nelua 结构正确性
--   3. nebula_apps.nelua 中 nebula_main 的委托逻辑存在
--   4. 与 counter_demo.nelua (分离模式) 行为等价
--   5. 文档注释更新
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
local unified_demo = read_file(examples_dir .. "counter_unified_demo.nelua")
assert(unified_demo, "counter_unified_demo.nelua not found at: " .. examples_dir)

local counter_demo = read_file(examples_dir .. "counter_demo.nelua")
assert(counter_demo, "counter_demo.nelua not found at: " .. examples_dir)

local apps_src = read_file(src_dir .. "nebula_apps.nelua")
assert(apps_src, "nebula_apps.nelua not found at: " .. src_dir)

-- =============================================================================
-- Test Group 1: counter_unified_demo.nelua — 结构正确性
-- =============================================================================
check("1.1_uses_require_nebula",
  unified_demo:find('require "nebula"') ~= nil)

check("1.2_uses_nebula_visual",
  unified_demo:find("nebula_visual") ~= nil)

check("1.3_uses_nebula_main",
  unified_demo:find("nebula_main") ~= nil)

-- ★ 关键：单调用模式不需要独立的 nebula_app 调用
check("1.4_no_separate_nebula_app",
  unified_demo:find("nebula_app%(") == nil)

check("1.5_no_app_begin",
  unified_demo:find("nebula_app_begin") == nil)

check("1.6_no_app_end",
  unified_demo:find("nebula_app_end") == nil)

check("1.7_no_derive_app",
  unified_demo:find("nebula_derive_app") == nil)

-- ★ states/bindings/events 直接在 nebula_main opts 中
check("1.8_has_components_in_main",
  unified_demo:find("components%s*=") ~= nil)

check("1.9_has_states_in_main",
  unified_demo:find("states%s*=") ~= nil)

check("1.10_has_bindings_in_main",
  unified_demo:find("bindings%s*=") ~= nil)

check("1.11_has_events_in_main",
  unified_demo:find("events%s*=") ~= nil)

check("1.12_has_on_init",
  unified_demo:find("on_init") ~= nil)

check("1.13_has_on_frame",
  unified_demo:find("on_frame") ~= nil)

check("1.14_has_title",
  unified_demo:find("title%s*=") ~= nil)

check("1.15_state_count",
  unified_demo:find('name = "count"') ~= nil)

check("1.16_binding_doubled",
  unified_demo:find('target = "doubled"') ~= nil)

check("1.17_event_click",
  unified_demo:find('event_type = "click"') ~= nil)

check("1.18_init_themed",
  unified_demo:find("init_themed") ~= nil)

-- =============================================================================
-- Test Group 2: nebula_apps.nelua — 委托逻辑存在
-- =============================================================================
check("2.1_main_checks_components",
  apps_src:find("if opts%.components then") ~= nil)

check("2.2_main_calls_nebula_app",
  apps_src:find("nebula_app%(app_type, app_spec%)") ~= nil)

check("2.3_main_forwards_states",
  apps_src:find("states%s*=%s*opts%.states") ~= nil)

check("2.4_main_forwards_bindings",
  apps_src:find("bindings%s*=%s*opts%.bindings") ~= nil)

check("2.5_main_forwards_events",
  apps_src:find("events%s*=%s*opts%.events") ~= nil)

check("2.6_main_forwards_components",
  apps_src:find("components%s*=%s*opts%.components") ~= nil)

check("2.7_main_clears_consumed_fields",
  apps_src:find("opts%.components%s*=%s*nil") ~= nil)

check("2.8_main_forwards_slots",
  apps_src:find("slots%s*=%s*opts%.slots") ~= nil)

check("2.9_main_forwards_texts",
  apps_src:find("texts%s*=%s*opts%.texts") ~= nil)

check("2.10_main_forwards_layout",
  apps_src:find("layout%s*=%s*opts%.layout") ~= nil)

-- =============================================================================
-- Test Group 3: 文档注释
-- =============================================================================
check("3.1_has_unified_usage_comment",
  apps_src:find("unified single call") ~= nil or
  apps_src:find("单调用模式") ~= nil)

check("3.2_has_phase_5_5_tag",
  apps_src:find("Phase 5%.5") ~= nil)

-- =============================================================================
-- Test Group 4: 对比 counter_demo.nelua (分离模式) — 功能等价性
-- =============================================================================
-- 两个 demo 应该声明相同的 Visual、状态、绑定、事件
check("4.1_both_have_clickable",
  unified_demo:find('"clickable"') ~= nil and
  counter_demo:find('"clickable"') ~= nil)

check("4.2_both_have_count_state",
  unified_demo:find('name = "count"') ~= nil and
  counter_demo:find('name = "count"') ~= nil)

check("4.3_both_have_doubled_binding",
  unified_demo:find('target = "doubled"') ~= nil and
  counter_demo:find('target = "doubled"') ~= nil)

check("4.4_both_have_click_event",
  unified_demo:find('event_type = "click"') ~= nil and
  counter_demo:find('event_type = "click"') ~= nil)

check("4.5_both_have_same_mutation",
  unified_demo:find("self%.count = self%.count %+ 1") ~= nil and
  counter_demo:find("self%.count = self%.count %+ 1") ~= nil)

check("4.6_both_have_same_compute",
  unified_demo:find("self%.doubled = self%.count %* 2") ~= nil and
  counter_demo:find("self%.doubled = self%.count %* 2") ~= nil)

-- ★ 统一模式应更简洁（少一个 nebula_app 调用）
local unified_lines = 0
for _ in unified_demo:gmatch("\n") do unified_lines = unified_lines + 1 end
local separate_lines = 0
for _ in counter_demo:gmatch("\n") do separate_lines = separate_lines + 1 end
check("4.7_unified_not_longer_than_separate",
  unified_lines <= separate_lines)

-- =============================================================================
-- Test Group 5: 向后兼容——分离模式不受影响
-- =============================================================================
-- counter_demo.nelua 使用分离的 nebula_app + nebula_main，不应被破坏
check("5.1_separate_mode_has_nebula_app",
  counter_demo:find('nebula_app%(') ~= nil)

check("5.2_separate_mode_has_nebula_main",
  counter_demo:find('nebula_main%(') ~= nil)

check("5.3_separate_mode_components_in_app",
  counter_demo:find('nebula_app%("CounterApp"') ~= nil)

-- =============================================================================
-- Summary
-- =============================================================================
local total = pass_count + fail_count
print(("smoke_phase5_5_unified_main: %d/%d passed"):format(pass_count, total))
if fail_count > 0 then
  print(("  unified: %d lines, separate: %d lines"):format(unified_lines, separate_lines))
  os.exit(1)
else
  print(("  unified: %d lines, separate: %d lines (-%d lines)"):format(
    unified_lines, separate_lines, separate_lines - unified_lines))
end
