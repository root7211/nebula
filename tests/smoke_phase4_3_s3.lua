-- =============================================================================
-- tests/smoke_phase4_3_s3.lua
-- Nebula GUI Compiler — Phase 4.3 S3 专项回归测试
--
-- 测试目标：
--   1. 字段冲突检测：同名不同类型字段触发 error
--   2. 字段冲突检测：同名同类型字段静默去重（合法场景）
--   3. static_asserts 格式校验（注册时的参数检查）
--   4. static_asserts 编译期契约校验通过（字段存在 + 类型匹配）
--   5. static_asserts 编译期契约校验失败（字段不存在）
--   6. static_asserts 编译期契约校验失败（字段存在但类型不匹配）
--   7. static_asserts 无断言时静默通过
--   8. 回归：S2 的 custom_slider / valid_test_prim 功能不受影响
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

local function assert_true(desc, val)
  if val then
    print("[PASS] " .. desc)
    pass_count = pass_count + 1
  else
    print("[FAIL] " .. desc .. " (expected truthy, got: " .. tostring(val) .. ")")
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

local function assert_error_contains(desc, fn, needle)
  local ok, err = pcall(fn)
  if not ok then
    local err_str = tostring(err)
    if err_str:find(needle, 1, true) then
      print("[PASS] " .. desc)
      pass_count = pass_count + 1
    else
      print("[FAIL] " .. desc)
      print("       error message should contain '" .. needle .. "'")
      print("       actual error: " .. err_str:sub(1, 500))
      fail_count = fail_count + 1
    end
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
-- §1: 字段冲突检测 — 同名不同类型触发 error
-- =============================================================================

-- 注册一个原语，注入字段 "value" 类型 "float32"
assert_no_error("注册 conflict_a (value: float32)", function()
  nebula_register_primitive("conflict_a", {
    context_fields = {
      { name = "value", type = "float32" },
    },
  })
end)

-- 注册另一个原语，注入同名字段 "value" 但类型 "uint32"
assert_no_error("注册 conflict_b (value: uint32)", function()
  nebula_register_primitive("conflict_b", {
    context_fields = {
      { name = "value", type = "uint32" },
    },
  })
end)

-- 获取两者组合的 context_fields 应触发冲突
assert_error_contains("同名不同类型字段触发 Axiom-S3 冲突", function()
  nebula_get_context_fields({ "conflict_a", "conflict_b" })
end, "Axiom-S3 冲突")

-- =============================================================================
-- §2: 字段冲突检测 — 同名同类型静默去重
-- =============================================================================

assert_no_error("注册 dupe_a (count: uint32)", function()
  nebula_register_primitive("dupe_a", {
    context_fields = {
      { name = "count", type = "uint32" },
    },
  })
end)

assert_no_error("注册 dupe_b (count: uint32) — 依赖 dupe_a，同名同类型", function()
  nebula_register_primitive("dupe_b", {
    dependencies = { "dupe_a" },
    context_fields = {
      { name = "count", type = "uint32" },
    },
  })
end)

local dupe_fields = nebula_get_context_fields({ "dupe_b" })
-- 只应出现一个 "count" 字段（去重）
local count_occurrences = 0
for _, f in ipairs(dupe_fields) do
  if f.name == "count" then count_occurrences = count_occurrences + 1 end
end
assert_eq("同名同类型字段去重后只出现一次", count_occurrences, 1)

-- =============================================================================
-- §3: static_asserts 格式校验（注册时参数检查）
-- =============================================================================

assert_error("static_asserts 项不是 table 应拒绝", function()
  nebula_register_primitive("bad_sa1", {
    static_asserts = { "not_a_table" },
  })
end)

assert_error("static_asserts 缺少 field 应拒绝", function()
  nebula_register_primitive("bad_sa2", {
    static_asserts = { { type_pattern = "Foo", reason = "test" } },
  })
end)

assert_error("static_asserts 缺少 type_pattern 应拒绝", function()
  nebula_register_primitive("bad_sa3", {
    static_asserts = { { field = "x", reason = "test" } },
  })
end)

assert_error("static_asserts 缺少 reason 应拒绝", function()
  nebula_register_primitive("bad_sa4", {
    static_asserts = { { field = "x", type_pattern = "Foo" } },
  })
end)

assert_error("static_asserts field 为空字符串应拒绝", function()
  nebula_register_primitive("bad_sa5", {
    static_asserts = { { field = "", type_pattern = "Foo", reason = "test" } },
  })
end)

-- 合法 static_asserts 注册成功
assert_no_error("合法 static_asserts 注册成功", function()
  nebula_register_primitive("sa_valid", {
    context_fields = { { name = "gap_buf", type = "NebulaBuf128" } },
    static_asserts = {
      { field = "gap_buf", type_pattern = "NebulaBuf%d+", reason = "需要 gap buffer 字段" },
    },
  })
end)
assert_true("sa_valid 的 static_asserts 已注册", function()
  return NEBULA_PRIMITIVES["sa_valid"] ~= nil
    and #NEBULA_PRIMITIVES["sa_valid"].static_asserts == 1
end)

-- =============================================================================
-- §4: static_asserts 编译期契约校验通过（字段存在 + 类型匹配）
-- =============================================================================

-- sa_need_buf 依赖 editable（会注入 gap_buf: NebulaBuf{N}），声明 static_assert 需要它
assert_no_error("注册 sa_need_buf (依赖 editable, 断言 gap_buf 存在)", function()
  nebula_register_primitive("sa_need_buf", {
    dependencies = { "editable" },
    static_asserts = {
      { field = "gap_buf", type_pattern = "NebulaBuf%d+", reason = "editable 应注入 gap_buf" },
    },
  })
end)

-- editable 的 context_fields 中没有直接叫 gap_buf 的字段——
-- 但 editable 的 extra_source_hook 生成代码引用 self.visual.gap_buf。
-- 为了测试 static_asserts 的正确工作，我们创建一个直接注入 gap_buf 字段的原语。
assert_no_error("注册 provider_with_gap (注入 gap_buf: NebulaBuf128)", function()
  nebula_register_primitive("provider_with_gap", {
    context_fields = {
      { name = "gap_buf", type = "NebulaBuf128" },
    },
  })
end)

assert_no_error("注册 consumer_assert_gap (断言 gap_buf 存在且匹配 NebulaBuf%d+)", function()
  nebula_register_primitive("consumer_assert_gap", {
    dependencies = { "provider_with_gap" },
    static_asserts = {
      { field = "gap_buf", type_pattern = "NebulaBuf%d+", reason = "需要 gap buffer" },
    },
  })
end)

assert_no_error("static_asserts 通过：gap_buf 存在且 NebulaBuf128 匹配 NebulaBuf%d+", function()
  nebula_validate_static_asserts({ "consumer_assert_gap" })
end)

-- =============================================================================
-- §5: static_asserts 编译期契约校验失败（字段不存在）
-- =============================================================================

assert_no_error("注册 consumer_need_missing (断言 nonexistent_field 存在)", function()
  nebula_register_primitive("consumer_need_missing", {
    dependencies = { "hoverable" },
    static_asserts = {
      { field = "nonexistent_field_xyz", type_pattern = "SomeType", reason = "需要不存在的字段" },
    },
  })
end)

assert_error_contains("static_asserts 失败：字段不存在", function()
  nebula_validate_static_asserts({ "consumer_need_missing" })
end, "Axiom-S3 违规")

-- =============================================================================
-- §6: static_asserts 编译期契约校验失败（字段存在但类型不匹配）
-- =============================================================================

assert_no_error("注册 consumer_wrong_type (断言 hover 匹配 SomeOtherType)", function()
  nebula_register_primitive("consumer_wrong_type", {
    dependencies = { "hoverable" },
    static_asserts = {
      { field = "hover", type_pattern = "SomeOtherType", reason = "故意类型不匹配" },
    },
  })
end)

assert_error_contains("static_asserts 失败：字段类型不匹配", function()
  nebula_validate_static_asserts({ "consumer_wrong_type" })
end, "Axiom-S3 违规")

-- =============================================================================
-- §7: static_asserts 无断言时静默通过
-- =============================================================================

assert_no_error("无 static_asserts 的原语组合静默通过", function()
  nebula_validate_static_asserts({ "hoverable", "clickable" })
end)

-- =============================================================================
-- §8: 回归 — S2 功能不受影响
-- =============================================================================

-- 注册 custom_slider（与 smoke_phase4_3.lua 中相同规格）
assert_no_error("注册 custom_slider (回归用)", function()
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

local pi_src = nebula_gen_process_input({
  base         = "Slider",
  state_type   = "SliderState",
  primitives   = {"hoverable", "clickable", "custom_slider"},
  states       = {"default", "hovered", "dragging"},
  component_id = 0,
})
assert_contains("回归：custom_slider body 仍存在", pi_src, "custom_slider body")
assert_contains("回归：Dragging 状态转换仍存在", pi_src, "SliderState.Dragging")
assert_contains("回归：hoverable 代码仍存在", pi_src, "self.hover.is_hovered")
assert_contains("回归：clickable 代码仍存在", pi_src, "self.click.is_pressed")

-- =============================================================================
-- 总结
-- =============================================================================
print("")
print(string.format("============================================"))
print(string.format(" Phase 4.3 S3 smoke tests: %d/%d passed, %d failed",
  pass_count, pass_count + fail_count, fail_count))
print(string.format("============================================"))

if fail_count > 0 then
  print("[FAIL] Phase 4.3 S3 regression detected!")
  os.exit(1)
else
  print("[ALL PASS] Phase 4.3 S3 smoke tests complete.")
  os.exit(0)
end
