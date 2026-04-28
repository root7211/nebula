-- tests/golden_gen.lua
-- 生成 golden files 用于重构回归对比

package.path = "./src/?.lua;" .. "./src/derive/?.lua;" .. package.path
require "derive.interaction_factory"

-- Test 1: Button (hoverable + clickable)
local button_spec = {
    base = "Button", state_type = "ButtonState",
    primitives = {"hoverable", "clickable"},
    states = {"default", "hovered", "pressed"},
}
local button_out = nebula_gen_process_input(button_spec)

-- Test 2: Input (hoverable + clickable + focusable)
local input_spec = {
    base = "Input", state_type = "InputState",
    primitives = {"hoverable", "clickable", "focusable"},
    states = {"default", "hovered", "focused", "pressed"},
}
local input_out = nebula_gen_process_input(input_spec)

-- Test 3: Checkbox (hoverable + clickable + toggleable)
local checkbox_spec = {
    base = "Checkbox", state_type = "CheckboxState",
    primitives = {"hoverable", "clickable", "toggleable"},
    states = {"default", "hovered", "pressed"},
}
local checkbox_out = nebula_gen_process_input(checkbox_spec)

-- Test 4: No primitives
local noop_spec = {
    base = "Card", state_type = "CardState",
    primitives = {},
    states = {"default"},
}
local noop_out = nebula_gen_process_input(noop_spec)

-- Test 5: Hoverable only
local hover_spec = {
    base = "Simple", state_type = "SimpleState",
    primitives = {"hoverable"},
    states = {"default", "hovered"},
}
local hover_out = nebula_gen_process_input(hover_spec)

-- Write golden files
local function write(name, content)
    local f = io.open("tests/golden/" .. name .. ".golden", "w")
    f:write(content)
    f:close()
end

os.execute("mkdir -p tests/golden")
write("process_input_button", button_out)
write("process_input_input", input_out)
write("process_input_checkbox", checkbox_out)
write("process_input_noop", noop_out)
write("process_input_hoveronly", hover_out)

print("Golden files written:")
print("  button:    " .. #button_out .. " chars")
print("  input:     " .. #input_out .. " chars")
print("  checkbox:  " .. #checkbox_out .. " chars")
print("  noop:      " .. #noop_out .. " chars")
print("  hoveronly: " .. #hover_out .. " chars")
