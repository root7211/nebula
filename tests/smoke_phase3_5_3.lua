-- =============================================================================
-- tests/smoke_phase3_5_3.lua
-- Nebula GUI Compiler — Phase 3.5.3 回归测试
--
-- 测试目标：
--   · nebula_gen_toggle_state(spec) 生成正确的 NebulaToggleState record 和 process_toggle 方法
--   · nebula_gen_process_input 在 toggleable 原语下自动追加 process_toggle 调用
--   · toggleable 与 hoverable/clickable/focusable 的正交性（不干扰主状态机）
--   · 版本号升级到 v0.3
-- =============================================================================

-- 设置正确的模块搜索路径
local script_dir = debug.getinfo(1, "S").source:match("^@(.+)/[^/]+$") or "."
package.path = script_dir .. "/../src/?.lua;" ..
               script_dir .. "/../src/derive/?.lua;" ..
               package.path

local interaction_ver = require "derive.interaction_factory"

-- =============================================================================
-- 测试工具
-- =============================================================================
local pass_count = 0
local fail_count = 0

local function assert_eq(desc, actual, expected)
  if actual == expected then
    print("[PASS] " .. desc)
    pass_count = pass_count + 1
  else
    print("[FAIL] " .. desc)
    print("       expected: " .. tostring(expected))
    print("       actual:   " .. tostring(actual))
    fail_count = fail_count + 1
  end
end

local function assert_contains(desc, haystack, needle)
  if type(haystack) == "string" and haystack:find(needle, 1, true) then
    print("[PASS] " .. desc)
    pass_count = pass_count + 1
  else
    print("[FAIL] " .. desc)
    print("       pattern '" .. needle .. "' not found in:")
    print("       " .. tostring(haystack):sub(1, 300))
    fail_count = fail_count + 1
  end
end

local function assert_not_contains(desc, haystack, needle)
  if type(haystack) == "string" and not haystack:find(needle, 1, true) then
    print("[PASS] " .. desc)
    pass_count = pass_count + 1
  else
    print("[FAIL] " .. desc)
    print("       pattern '" .. needle .. "' should NOT be found")
    fail_count = fail_count + 1
  end
end

-- =============================================================================
-- 测试 1: 版本号
-- =============================================================================
assert_eq("interaction_factory 版本号", interaction_ver, "nebula_interaction_factory_v0.3_phase3.5.3")

-- =============================================================================
-- 测试 2: nebula_gen_toggle_state 生成 NebulaToggleState 和 process_toggle
-- =============================================================================
local toggle_src = nebula_gen_toggle_state({ base = "Checkbox" })
assert_eq("nebula_gen_toggle_state 返回字符串", type(toggle_src), "string")
assert_contains("生成 NebulaToggleState record", toggle_src, "global NebulaToggleState = @record{")
assert_contains("包含 is_on 字段", toggle_src, "is_on:        boolean,")
assert_contains("包含 just_toggled 字段", toggle_src, "just_toggled: boolean,")
assert_contains("生成 process_toggle 方法", toggle_src, "function CheckboxContext:process_toggle(input: *NebulaInputState): void")
assert_contains("process_toggle 检测 just_clicked", toggle_src, "if self.click.just_clicked then")
assert_contains("process_toggle 翻转 is_on", toggle_src, "self.toggle.is_on = not self.toggle.is_on")
assert_contains("process_toggle 记录 just_toggled", toggle_src, "self.toggle.just_toggled = (self.toggle.is_on ~= prev_on)")

-- =============================================================================
-- 测试 3: toggleable 原语在 process_input 中自动追加 process_toggle 调用
-- =============================================================================
local spec_toggle = {
  base       = "Checkbox",
  state_type = "CheckboxState",
  primitives = {"hoverable", "clickable", "toggleable"},
  states     = {"default", "hovered", "pressed"},
}
local pi_toggle_src = nebula_gen_process_input(spec_toggle)
assert_contains("process_input 包含 toggleable 时追加 process_toggle 调用",
  pi_toggle_src, "self:process_toggle(input)")
assert_contains("process_input 仍包含主状态机逻辑（hovered）",
  pi_toggle_src, "transition_to(CheckboxState.Hovered)")
assert_contains("process_input 仍包含主状态机逻辑（pressed）",
  pi_toggle_src, "transition_to(CheckboxState.Pressed)")

-- =============================================================================
-- 测试 4: 不含 toggleable 时，process_input 不包含 process_toggle 调用
-- =============================================================================
local spec_no_toggle = {
  base       = "Button",
  state_type = "ButtonState",
  primitives = {"hoverable", "clickable"},
  states     = {"default", "hovered", "pressed"},
}
local pi_no_toggle_src = nebula_gen_process_input(spec_no_toggle)
assert_not_contains("无 toggleable 时不包含 process_toggle 调用",
  pi_no_toggle_src, "process_toggle")

-- =============================================================================
-- 测试 5: toggleable 与 focusable 正交（不干扰焦点管理）
-- =============================================================================
local spec_focus_toggle = {
  base         = "CheckSwitch",
  state_type   = "CheckSwitchState",
  primitives   = {"hoverable", "clickable", "focusable", "toggleable"},
  states       = {"default", "hovered", "focused"},
  component_id = 5,
}
local pi_focus_toggle_src = nebula_gen_process_input(spec_focus_toggle)
assert_contains("focusable+toggleable 包含焦点管理",
  pi_focus_toggle_src, "input.focused_id = self.component_id")
assert_contains("focusable+toggleable 包含 process_toggle 调用",
  pi_focus_toggle_src, "self:process_toggle(input)")
assert_contains("focusable+toggleable 包含 focused 状态转换",
  pi_focus_toggle_src, "transition_to(CheckSwitchState.Focused)")

-- =============================================================================
-- 测试 6: 纯 toggleable（无 hoverable/clickable）的边界情况
-- =============================================================================
local spec_pure_toggle = {
  base       = "SimpleToggle",
  state_type = "SimpleToggleState",
  primitives = {"toggleable"},
  states     = {"default"},
}
-- 纯 toggleable 没有 clickable，just_clicked 不会被设置，process_toggle 仍应生成
-- 但由于没有 clickable，process_input 会是 no-op 版本，process_toggle 也不会被追加
-- （因为 toggleable 依赖 clickable 的 just_clicked）
-- 这是预期行为：toggleable 必须与 clickable 配合使用
local pi_pure_toggle_src = nebula_gen_process_input(spec_pure_toggle)
-- 没有 hoverable/clickable/focusable，应生成 no-op
assert_contains("纯 toggleable 无 clickable 时生成 no-op process_input",
  pi_pure_toggle_src, "no interaction primitives declared")

-- =============================================================================
-- 测试 7: 向后兼容性 — 现有测试的 process_input 不受影响
-- =============================================================================
local spec_button = {
  base       = "Button",
  state_type = "ButtonState",
  primitives = {"hoverable", "clickable"},
  states     = {"default", "hovered", "pressed"},
}
local button_src = nebula_gen_process_input(spec_button)
assert_contains("向后兼容：Button process_input 包含 hovered 逻辑",
  button_src, "transition_to(ButtonState.Hovered)")
assert_contains("向后兼容：Button process_input 包含 pressed 逻辑",
  button_src, "transition_to(ButtonState.Pressed)")
assert_not_contains("向后兼容：Button process_input 不含 toggle",
  button_src, "process_toggle")

-- =============================================================================
-- 结果汇总
-- =============================================================================
print(("=== Phase 3.5.3 回归测试结果：%d 通过，%d 失败 ==="):format(pass_count, fail_count))
if fail_count > 0 then os.exit(1) end
