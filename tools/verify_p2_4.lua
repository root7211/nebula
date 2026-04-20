-- =============================================================================
-- verify_p2_4.lua
-- 模拟编译期 Lua 逻辑，验证 interaction_factory.lua 的代码生成是否正确
-- =============================================================================

-- 设置 package.path 以加载 src/derive/ 中的模块
package.path = package.path .. ";/home/ubuntu/nebula/src/?.lua"

local factory = require "derive.interaction_factory"
print("Loaded interaction_factory: " .. tostring(factory))

-- 模拟 ButtonVisual 的规格
local button_spec = {
  base         = "Button",
  state_type   = "ButtonState",
  primitives   = {"hoverable", "clickable"},
  states       = {"default", "hovered", "pressed"},
}

-- 模拟 InputVisual 的规格（focusable）
local input_spec = {
  base         = "Input",
  state_type   = "InputState",
  primitives   = {"hoverable", "clickable", "focusable"},
  states       = {"default", "hovered", "focused"},
}

print("\n--- [Test 1] Button (hoverable + clickable) ---")
local hit_test_src = nebula_gen_hit_test(button_spec)
local process_input_src = nebula_gen_process_input(button_spec)
print("Hit Test Source:")
print(hit_test_src)
print("\nProcess Input Source:")
print(process_input_src)

print("\n--- [Test 2] Input (hoverable + clickable + focusable) ---")
local input_hit_test_src = nebula_gen_hit_test(input_spec)
local input_process_input_src = nebula_gen_process_input(input_spec)
print("Hit Test Source:")
print(input_hit_test_src)
print("\nProcess Input Source:")
print(input_process_input_src)

-- 简单的断言验证
assert(process_input_src:find("self.click.is_pressed"), "Should handle clickable")
assert(process_input_src:find("self.hover.is_hovered"), "Should handle hoverable")
assert(input_process_input_src:find("self.component_id"), "Should handle focusable with self.component_id")
assert(input_process_input_src:find("input.focused_id"), "Should handle focusable with input.focused_id")

print("\n[SUCCESS] interaction_factory.lua logic verified!")
