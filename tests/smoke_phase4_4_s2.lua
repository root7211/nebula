-- =============================================================================
-- tests/smoke_phase4_4_s2.lua
-- Phase 4.4 S2 — Dropdown 下拉选择器
--
-- 测试目标：
--   1. dropdown_manager 原语可以正确注册到 NEBULA_PRIMITIVES
--   2. dropdown_manager 依赖 hoverable + clickable，依赖解析正确
--   3. dropdown_manager 原语的 context_fields 包含 is_open/selected_index/item_count
--   4. dropdown_manager 原语的 process_body 包含 toggle 和 close-outside 逻辑
--   5. 跨组件依赖链解析正确（focusable + dropdown_manager 不重复）
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

local function assert_true(desc, val)
  if val then
    print("[PASS] " .. desc)
    pass_count = pass_count + 1
  else
    print("[FAIL] " .. desc)
    print("       expected truthy, got: " .. tostring(val))
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
    print("       " .. tostring(haystack):sub(1, 500))
    fail_count = fail_count + 1
  end
end

-- =============================================================================
print("")
print("=== Phase 4.4 S2: dropdown_manager 原语注册验证 ===")
print("")

-- §1: 注册 dropdown_manager 原语
nebula_register_primitive("dropdown_manager", {
  dependencies = {"hoverable", "clickable"},
  context_fields = {
    {name="is_open",        type="boolean"},
    {name="selected_index", type="uint32"},
    {name="item_count",     type="uint32"},
  },
  state_transitions = {},
  process_body = function(spec, lines)
    table.insert(lines, "  if self.click.just_clicked then")
    table.insert(lines, "    self.is_open = not self.is_open")
    table.insert(lines, "  end")
    table.insert(lines, "  if self.is_open and input.mouse_left_pressed and not hovered then")
    table.insert(lines, "    self.is_open = false")
    table.insert(lines, "  end")
  end,
})

assert_true("§1.1: dropdown_manager registered in NEBULA_PRIMITIVES",
  NEBULA_PRIMITIVES["dropdown_manager"] ~= nil)

local dm = NEBULA_PRIMITIVES["dropdown_manager"]
assert_eq("§1.2: dropdown_manager has 2 dependencies", #dm.dependencies, 2)
assert_eq("§1.3: dep[1] = hoverable", dm.dependencies[1], "hoverable")
assert_eq("§1.4: dep[2] = clickable", dm.dependencies[2], "clickable")
assert_eq("§1.5: dropdown_manager has 3 context fields", #dm.context_fields, 3)
assert_eq("§1.6: ctx[1] = is_open", dm.context_fields[1].name, "is_open")
assert_eq("§1.6b: is_open type = boolean", dm.context_fields[1].type, "boolean")
assert_eq("§1.7: ctx[2] = selected_index", dm.context_fields[2].name, "selected_index")
assert_eq("§1.7b: selected_index type = uint32", dm.context_fields[2].type, "uint32")
assert_eq("§1.8: ctx[3] = item_count", dm.context_fields[3].name, "item_count")
assert_eq("§1.8b: item_count type = uint32", dm.context_fields[3].type, "uint32")

-- §2: nebula_gen_process_input generates toggle and close-outside logic
local gen = nebula_gen_process_input({
  base       = "DropdownVisual",
  state_type = "DropdownVisualState",
  primitives = {"hoverable", "clickable", "dropdown_manager"},
  states     = {"default", "hovered", "pressed"},
})
assert_contains("§2.1: process_input contains is_open field", gen, "is_open")
assert_contains("§2.2: process_input contains toggle logic (is_open = not)", gen, "is_open = not")
assert_contains("§2.3: process_input contains close-outside check (mouse_left_pressed)", gen, "mouse_left_pressed")
assert_contains("§2.4: process_input contains hovered check for outside-click", gen, "hovered")

-- §3: context_fields includes dropdown_manager fields
local fields = nebula_get_context_fields({"hoverable", "clickable", "dropdown_manager"})
local field_names = {}
for _, f in ipairs(fields) do field_names[f.name] = true end
assert_true("§3.1: context has hover field", field_names["hover"] ~= nil)
assert_true("§3.2: context has click field", field_names["click"] ~= nil)
assert_true("§3.3: context has is_open field", field_names["is_open"] ~= nil)
assert_true("§3.4: context has selected_index field", field_names["selected_index"] ~= nil)
assert_true("§3.5: context has item_count field", field_names["item_count"] ~= nil)

-- §4: Dependency resolution
local resolved = nebula_resolve_primitives({"dropdown_manager"})
assert_eq("§4.1: dropdown_manager resolves to 3 primitives", #resolved, 3)
assert_eq("§4.2: resolved[1] = hoverable", resolved[1], "hoverable")
assert_eq("§4.3: resolved[2] = clickable", resolved[2], "clickable")
assert_eq("§4.4: resolved[3] = dropdown_manager", resolved[3], "dropdown_manager")

-- §5: Deduplication
local resolved2 = nebula_resolve_primitives({"clickable", "dropdown_manager"})
assert_eq("§5.1: clickable + dropdown_manager dedup to 3", #resolved2, 3)

local resolved3 = nebula_resolve_primitives({"dropdown_manager", "hoverable"})
assert_eq("§5.2: dropdown_manager + hoverable dedup to 3", #resolved3, 3)

-- §6: Cross-component chain (focusable deps=[hoverable,clickable], dropdown_manager deps=[hoverable,clickable])
-- merged: hoverable → clickable → focusable → dropdown_manager = 4 (deduped)
local resolved4 = nebula_resolve_primitives({"focusable", "dropdown_manager"})
assert_eq("§6.1: focusable + dropdown_manager resolves to 4 (shared deps deduped)", #resolved4, 4)

-- §7: Duplicate registration fails
local ok_dup, err_dup = pcall(function()
  nebula_register_primitive("dropdown_manager", {
    dependencies = {"hoverable"},
    context_fields = {},
    state_transitions = {},
    process_body = function(spec, lines) end,
  })
end)
assert_true("§7.1: duplicate registration raises error", not ok_dup)
assert_contains("§7.2: error message mentions 'already registered'", err_dup, "already registered")

-- =============================================================================
-- 结果统计
-- =============================================================================
local total = pass_count + fail_count
print("")
print(string.format("[smoke_phase4_4_s2] %d/%d assertions passed", pass_count, total))
if fail_count > 0 then
  print("[FAIL] " .. fail_count .. " assertions FAILED")
  os.exit(1)
else
  print("[PASS] all assertions passed")
end
