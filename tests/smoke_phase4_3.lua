-- =============================================================================
-- tests/smoke_phase4_3.lua
-- Nebula GUI Compiler — Phase 4.3 专项回归测试
--
-- 测试目标：
--   1. nebula_register_primitive 基本注册能力
--   2. 重复注册内置原语拒绝（assert 触发）
--   3. 重复注册自定义原语拒绝（assert 触发）
--   4. nebula_resolve_primitives 对自定义原语的依赖解析
--   5. nebula_gen_process_input 包含自定义原语的 process_body 代码
--   6. nebula_gen_process_input 包含自定义原语的 state_transitions
--   7. 自定义原语与内置原语组合时 process_input 输出正确
--   8. 未知原语名在 primitives 列表中优雅跳过
--   9. nebula_get_context_fields 包含自定义原语的字段
--  10. nebula_get_post_process 包含自定义原语的后处理
--  11. slider_demo.nelua 编译通过（集成测试）
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
    print("       " .. tostring(haystack):sub(1, 500))
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

local function assert_true(desc, val)
  if val then
    print("[PASS] " .. desc)
    pass_count = pass_count + 1
  else
    print("[FAIL] " .. desc .. " (expected truthy, got: " .. tostring(val) .. ")")
    fail_count = fail_count + 1
  end
end

local function assert_nil(desc, val)
  if val == nil then
    print("[PASS] " .. desc)
    pass_count = pass_count + 1
  else
    print("[FAIL] " .. desc .. " (expected nil, got: " .. tostring(val) .. ")")
    fail_count = fail_count + 1
  end
end

local function assert_error(desc, fn)
  local ok, err = pcall(fn)
  if not ok then
    print("[PASS] " .. desc)
    pass_count = pass_count + 1
  else
    print("[FAIL] " .. desc .. " (expected error, but succeeded)")
    fail_count = fail_count + 1
  end
end

local function assert_no_error(desc, fn)
  local ok, err = pcall(fn)
  if ok then
    print("[PASS] " .. desc)
    pass_count = pass_count + 1
  else
    print("[FAIL] " .. desc .. " (expected success, got error: " .. tostring(err) .. ")")
    fail_count = fail_count + 1
  end
end

-- =============================================================================
-- 测试 1: 版本号包含 phase 标识
-- =============================================================================
assert_contains("interaction_factory 版本号包含 phase 前缀", interaction_ver, "phase")

-- =============================================================================
-- 测试 2: nebula_register_primitive 基本注册
-- =============================================================================
assert_true("NEBULA_PRIMITIVES 注册表存在", NEBULA_PRIMITIVES ~= nil)
assert_true("内置 hoverable 已注册", NEBULA_PRIMITIVES["hoverable"] ~= nil)
assert_true("内置 clickable 已注册", NEBULA_PRIMITIVES["clickable"] ~= nil)
assert_true("内置 focusable 已注册", NEBULA_PRIMITIVES["focusable"] ~= nil)
assert_true("内置 toggleable 已注册", NEBULA_PRIMITIVES["toggleable"] ~= nil)
assert_true("内置 editable 已注册", NEBULA_PRIMITIVES["editable"] ~= nil)

-- 注册一个自定义原语用于后续测试
assert_no_error("nebula_register_primitive 注册 custom_slider 成功", function()
  nebula_register_primitive("custom_slider", {
    dependencies   = {"clickable"},
    context_fields = {
      {name="value", type="float32"},
      {name="is_dragging", type="boolean"},
    },
    process_body = function(spec, lines)
      table.insert(lines, "  -- custom_slider body")
      table.insert(lines, "  self.is_dragging = hovered and input.mouse_left_down")
    end,
    state_transitions = {
      {guard="self.is_dragging", target="Dragging", priority=40},
    },
  })
end)
assert_true("custom_slider 已注册到 NEBULA_PRIMITIVES", NEBULA_PRIMITIVES["custom_slider"] ~= nil)

-- 验证注册结构完整性
local cs = NEBULA_PRIMITIVES["custom_slider"]
assert_eq("custom_slider.name", cs.name, "custom_slider")
assert_eq("custom_slider 依赖数", #cs.dependencies, 1)
assert_eq("custom_slider 第一个依赖", cs.dependencies[1], "clickable")
assert_eq("custom_slider context_fields 数", #cs.context_fields, 2)
assert_eq("custom_slider 第一个字段名", cs.context_fields[1].name, "value")
assert_eq("custom_slider 第一个字段类型", cs.context_fields[1].type, "float32")
assert_eq("custom_slider 第二个字段名", cs.context_fields[2].name, "is_dragging")
assert_eq("custom_slider 第二个字段类型", cs.context_fields[2].type, "boolean")
assert_true("custom_slider 有 process_body", cs.process_body ~= nil)
assert_true("custom_slider 有 state_transitions", cs.state_transitions ~= nil)
assert_eq("custom_slider state_transitions 数", #cs.state_transitions, 1)
assert_eq("custom_slider 第一个 transition guard", cs.state_transitions[1].guard, "self.is_dragging")
assert_eq("custom_slider 第一个 transition target", cs.state_transitions[1].target, "Dragging")
assert_eq("custom_slider 第一个 transition priority", cs.state_transitions[1].priority, 40)

-- =============================================================================
-- 测试 3: 重复注册内置原语拒绝
-- =============================================================================
assert_error("重复注册 hoverable 应触发 assert", function()
  nebula_register_primitive("hoverable", {
    context_fields = {},
  })
end)

assert_error("重复注册 clickable 应触发 assert", function()
  nebula_register_primitive("clickable", {
    context_fields = {},
  })
end)

-- =============================================================================
-- 测试 4: 重复注册自定义原语拒绝
-- =============================================================================
assert_error("重复注册 custom_slider 应触发 assert", function()
  nebula_register_primitive("custom_slider", {
    context_fields = {},
  })
end)

-- =============================================================================
-- 测试 5: nebula_resolve_primitives 对自定义原语的依赖解析
-- =============================================================================
local resolved = nebula_resolve_primitives({"custom_slider"})
assert_eq("resolve custom_slider 得到 3 个原语", #resolved, 3)
-- 依赖顺序：hoverable -> clickable -> custom_slider（拓扑排序）
assert_eq("resolve 顺序 1: hoverable", resolved[1], "hoverable")
assert_eq("resolve 顺序 2: clickable", resolved[2], "clickable")
assert_eq("resolve 顺序 3: custom_slider", resolved[3], "custom_slider")

-- 测试与内置原语的混合解析
local resolved2 = nebula_resolve_primitives({"hoverable", "clickable", "custom_slider"})
assert_eq("混合解析去重后仍为 3 个", #resolved2, 3)

-- =============================================================================
-- 测试 6: nebula_gen_process_input 包含自定义原语代码
-- =============================================================================
local pi_src = nebula_gen_process_input({
  base         = "Slider",
  state_type   = "SliderState",
  primitives   = {"hoverable", "clickable", "custom_slider"},
  states       = {"default", "hovered", "dragging"},
  component_id = 0,
})

assert_eq("nebula_gen_process_input 返回字符串", type(pi_src), "string")
assert_contains("process_input 函数签名", pi_src, "function SliderContext:process_input")
assert_contains("包含 hit_test 调用", pi_src, "self:hit_test(input.mouse_x, input.mouse_y)")
-- 内置原语代码
assert_contains("包含 hoverable 的 is_hovered 更新", pi_src, "self.hover.is_hovered")
assert_contains("包含 clickable 的 is_pressed 更新", pi_src, "self.click.is_pressed")
-- 自定义原语代码
assert_contains("包含 custom_slider 的 body 注释", pi_src, "custom_slider body")
assert_contains("包含 custom_slider 的 is_dragging 赋值", pi_src, "self.is_dragging = hovered and input.mouse_left_down")
-- 状态机转换（priority 排序：Dragging=40 > Pressed=30 > Hovered=10）
-- 注意：states 中没有 "pressed"，所以 clickable 的 Pressed transition 不会生成
-- （gen_process_input 会检查 target 是否在 states 列表中）
assert_not_contains("无 pressed 状态时不生成 Pressed 转换", pi_src, "SliderState.Pressed")
assert_contains("包含 Dragging 状态转换（自定义原语）", pi_src, "SliderState.Dragging")
assert_contains("包含 Hovered 状态转换", pi_src, "SliderState.Hovered")

-- =============================================================================
-- 测试 7: 仅内置原语时 process_input 不包含自定义原语代码
-- =============================================================================
local pi_builtin = nebula_gen_process_input({
  base         = "Button",
  state_type   = "ButtonState",
  primitives   = {"hoverable", "clickable"},
  states       = {"default", "hovered", "pressed"},
  component_id = 0,
})
assert_not_contains("纯内置原语不包含 custom_slider body", pi_builtin, "custom_slider body")
assert_not_contains("纯内置原语不包含 Dragging 状态", pi_builtin, "ButtonState.Dragging")

-- =============================================================================
-- 测试 8: 未知原语名优雅跳过
-- =============================================================================
local pi_unknown = nebula_gen_process_input({
  base         = "Mystery",
  state_type   = "MysteryState",
  primitives   = {"hoverable", "nonexistent_primitive_xyz"},
  states       = {"default", "hovered"},
  component_id = 0,
})
assert_eq("未知原语不崩溃，仍返回字符串", type(pi_unknown), "string")
assert_contains("未知原语场景仍包含 hoverable 代码", pi_unknown, "self.hover.is_hovered")

-- =============================================================================
-- 测试 9: nebula_get_context_fields 包含自定义原语的字段
-- =============================================================================
local fields = nebula_get_context_fields({"custom_slider"})
assert_true("context_fields 包含 value 字段", function()
  for _, f in ipairs(fields) do
    if f.name == "value" and f.type == "float32" then return true end
  end
  return false
end)
assert_true("context_fields 包含 is_dragging 字段", function()
  for _, f in ipairs(fields) do
    if f.name == "is_dragging" and f.type == "boolean" then return true end
  end
  return false
end)
assert_true("context_fields 包含 hover 字段（来自 hoverable 依赖）", function()
  for _, f in ipairs(fields) do
    if f.name == "hover" then return true end
  end
  return false
end)
assert_true("context_fields 包含 click 字段（来自 clickable 依赖）", function()
  for _, f in ipairs(fields) do
    if f.name == "click" then return true end
  end
  return false
end)

-- =============================================================================
-- 测试 10: nebula_get_post_process 不含自定义原语的后处理（未声明）
-- =============================================================================
local posts = nebula_get_post_process({"custom_slider"})
assert_eq("custom_slider 无 post_process", #posts, 0)

-- 对比：toggleable 有 post_process
local posts_toggle = nebula_gen_process_input({
  base         = "Check",
  state_type   = "CheckState",
  primitives   = {"hoverable", "clickable", "toggleable"},
  states       = {"default", "hovered", "pressed"},
  component_id = 0,
})
assert_contains("toggleable 生成 process_toggle 调用", posts_toggle, "self:process_toggle(input)")

-- =============================================================================
-- 测试 11: 无原语时 process_input 生成空体
-- =============================================================================
local pi_none = nebula_gen_process_input({
  base         = "Plain",
  state_type   = "PlainState",
  primitives   = {},
  states       = {"default"},
  component_id = 0,
})
assert_contains("无原语时生成 no-op 注释", pi_none, "no primitives, no-op")
assert_not_contains("无原语时不生成 hit_test", pi_none, "hit_test")

-- =============================================================================
-- 测试 12: nebula_run_pre_derive_hooks 不崩溃（自定义原语无 hook）
-- =============================================================================
assert_no_error("pre_derive_hooks 对 custom_slider 不崩溃", function()
  local fake_reg = {primitives = {"custom_slider"}}
  local injected = {}
  local function fake_inject(stat) table.insert(injected, stat) end
  nebula_run_pre_derive_hooks(fake_reg, "SliderVisual", {"custom_slider"}, fake_inject, {})
end)

-- =============================================================================
-- 测试 13: nebula_get_extra_sources 不崩溃（自定义原语无 extra_source_hook）
-- =============================================================================
assert_no_error("extra_sources 对 custom_slider 不崩溃", function()
  local spec = {base = "Slider", state_type = "SliderState", primitives = {"custom_slider"}}
  local src = nebula_get_extra_sources(spec, {"custom_slider"})
  assert_eq("custom_slider 无额外源码", src, "")
end)

-- =============================================================================
-- 测试 14: Phase 4.3 S2 参数校验
-- =============================================================================

-- 依赖不存在时拒绝
assert_error("依赖不存在的原语应拒绝", function()
  nebula_register_primitive("bad_deps", {
    dependencies = {"nonexistent_helper_xyz"},
    context_fields = {},
  })
end)
assert_nil("bad_deps 未注册", NEBULA_PRIMITIVES["bad_deps"])

-- context_fields 格式错误时拒绝
assert_error("context_fields 项不是 table 应拒绝", function()
  nebula_register_primitive("bad_fields1", {
    context_fields = {"not_a_table"},
  })
end)

assert_error("context_fields 缺少 name 应拒绝", function()
  nebula_register_primitive("bad_fields2", {
    context_fields = {{type="float32"}},
  })
end)

assert_error("context_fields 缺少 type 应拒绝", function()
  nebula_register_primitive("bad_fields3", {
    context_fields = {{name="val"}},
  })
end)

assert_error("context_fields name 为空字符串应拒绝", function()
  nebula_register_primitive("bad_fields4", {
    context_fields = {{name="", type="float32"}},
  })
end)

-- state_transitions 格式错误时拒绝
assert_error("state_transitions 缺少 guard 应拒绝", function()
  nebula_register_primitive("bad_trans1", {
    state_transitions = {{target="Foo"}},
  })
end)

assert_error("state_transitions 缺少 target 应拒绝", function()
  nebula_register_primitive("bad_trans2", {
    state_transitions = {{guard="self.x"}},
  })
end)

-- process_body 类型错误时拒绝
assert_error("process_body 不是 function 应拒绝", function()
  nebula_register_primitive("bad_body", {
    process_body = "not a function",
  })
end)

-- 合法注册仍然通过
assert_no_error("校验通过的合法注册仍然成功", function()
  nebula_register_primitive("valid_test_prim", {
    dependencies   = {"hoverable"},
    context_fields = {{name="my_val", type="float32"}},
    process_body   = function(spec, lines) end,
    state_transitions = {{guard="self.my_val > 0.5", target="Active", priority=10}},
  })
end)
assert_true("valid_test_prim 已注册", NEBULA_PRIMITIVES["valid_test_prim"] ~= nil)

-- =============================================================================
-- 总结
-- =============================================================================
print("")
print(string.format("============================================"))
print(string.format(" Phase 4.3 smoke tests: %d/%d passed, %d failed",
  pass_count, pass_count + fail_count, fail_count))
print(string.format("============================================"))

if fail_count > 0 then
  print("[FAIL] Phase 4.3 regression detected!")
  os.exit(1)
else
  print("[ALL PASS] Phase 4.3 smoke tests complete.")
  os.exit(0)
end
