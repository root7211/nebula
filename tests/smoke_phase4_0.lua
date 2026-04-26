-- smoke_phase4_0.lua
-- Nebula GUI Compiler — Phase 4.0 专项回归测试
--
-- 验证内容：
--   1. [模块加载] axiom_validator.lua 版本标识正确
--   2. [任务 A] 合法 Visual 字段（L1 白名单类型）通过校验
--   3. [任务 A] 非法字段 NebulaTextMesh 被拦截，错误信息含 Axiom-B
--   4. [任务 A] 非法字段 GapBuffer 被拦截，错误信息含 Axiom-B
--   5. [任务 A] 指针类型字段被拦截，错误信息含 Axiom-B
--   6. [任务 A] 状态字段中的非法类型被拦截
--   7. [任务 C] 合法 App 注册通过校验
--   8. [任务 C] 非法组件名（含空格）被拦截，错误信息含 Invariant-I1
--   9. [任务 C] 非法组件名（数字开头）被拦截
--  10. [任务 C] Slot max_instances 为 0 被拦截
--  11. [任务 C] Slot max_instances 为非整数被拦截
--  12. [任务 C] Slot max_instances 为负数被拦截
--  13. [任务 B] 无冲突的 App 通过校验
--  14. [任务 B] 管线路径冲突（shadow vs standard）被拦截，错误信息含 Axiom-C
--  15. [集成] nebula_app_generate 在合法 App 上正常生成代码
--  16. [集成] nebula_app_generate 在违规 App 上抛出错误
--  17. [行数收敛] axiom_validator.lua 行数在合理范围内
--  18. [行数收敛] app_factory.lua 行数在合理范围内（含 Phase 4.0 挂载）
-- =============================================================================

local script_dir = debug.getinfo(1, "S").source:match("^@(.+)/[^/]+$") or "."

-- ---- 加载被测模块 ----
-- 先加载 app_factory（它会全局暴露 nebula_app_begin/end/register 等 API）
local factory_version = dofile(script_dir .. "/../src/derive/app_factory.lua")
-- 再加载 axiom_validator（它会全局暴露 nebula_validate_visual / nebula_validate_app）
local validator_version = dofile(script_dir .. "/../src/derive/axiom_validator.lua")

-- ---- 辅助函数 ----
local passed = 0
local failed = 0

local function assert_eq(desc, got, expected)
  if got == expected then
    passed = passed + 1
    print(("[PASS] %s"):format(desc))
  else
    failed = failed + 1
    print(("[FAIL] %s\n       expected: %s\n       got:      %s"):format(
      desc, tostring(expected), tostring(got)))
  end
end

local function assert_contains(desc, haystack, needle)
  if type(haystack) == "string" and haystack:find(needle, 1, true) then
    passed = passed + 1
    print(("[PASS] %s"):format(desc))
  else
    failed = failed + 1
    print(("[FAIL] %s\n       needle not found: '%s'\n       in: %s"):format(
      desc, needle, tostring(haystack):sub(1, 200)))
  end
end

local function assert_not_contains(desc, haystack, needle)
  if type(haystack) == "string" and not haystack:find(needle, 1, true) then
    passed = passed + 1
    print(("[PASS] %s"):format(desc))
  else
    failed = failed + 1
    print(("[FAIL] %s\n       unexpected needle found: '%s'"):format(desc, needle))
  end
end

local function assert_le(desc, got, limit)
  if type(got) == "number" and got <= limit then
    passed = passed + 1
    print(("[PASS] %s (%d ≤ %d)"):format(desc, got, limit))
  else
    failed = failed + 1
    print(("[FAIL] %s (%s > %d)"):format(desc, tostring(got), limit))
  end
end

-- 断言 pcall 应该失败，并且错误信息包含指定关键字
local function assert_error_contains(desc, fn, keyword)
  local ok, err = pcall(fn)
  if not ok and type(err) == "string" and err:find(keyword, 1, true) then
    passed = passed + 1
    print(("[PASS] %s (拦截成功，含 '%s')"):format(desc, keyword))
  elseif ok then
    failed = failed + 1
    print(("[FAIL] %s — 期望抛出错误，但调用成功了"):format(desc))
  else
    failed = failed + 1
    print(("[FAIL] %s — 抛出了错误，但不含 '%s'\n       实际错误: %s"):format(
      desc, keyword, tostring(err):sub(1, 300)))
  end
end

local function count_lines(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local n = 0
  for _ in f:lines() do n = n + 1 end
  f:close()
  return n
end

-- =============================================================================
-- 1. 模块加载与版本标识
-- =============================================================================
print("\n--- 1. 模块加载与版本标识 ---")

assert_eq("axiom_validator 版本标识正确",
  validator_version, "nebula_axiom_validator_v1.0_phase4.0")

assert_eq("nebula_validate_visual 函数已暴露",
  type(nebula_validate_visual), "function")

assert_eq("nebula_validate_app 函数已暴露",
  type(nebula_validate_app), "function")

-- =============================================================================
-- 2. 任务 A：合法 Visual 字段通过校验
-- =============================================================================
print("\n--- 2. 任务 A：合法字段通过校验 ---")

-- 构造合法的 base_fields（全部为 L1 白名单类型）
local legal_base_fields = {
  { name = "pos",    type = "Vec2"    },
  { name = "size",   type = "Vec2"    },
  { name = "radius", type = "float32" },
  { name = "color",  type = "Color"   },
  { name = "border", type = "float32" },
  { name = "visible",type = "bool"    },
}
local legal_state_fields = {
  default = {
    bg_color = { name = "default_bg_color", type = "Color" },
    opacity  = { name = "default_opacity",  type = "float32" },
  },
  hovered = {
    bg_color = { name = "hovered_bg_color", type = "Color" },
  },
}

local ok_legal = pcall(nebula_validate_visual, "ButtonVisual", legal_base_fields, legal_state_fields)
assert_eq("合法 Visual 字段通过校验（无错误）", ok_legal, true)

-- =============================================================================
-- 3. 任务 A：NebulaTextMesh 被拦截
-- =============================================================================
print("\n--- 3. 任务 A：NebulaTextMesh 被拦截 ---")

local illegal_mesh_fields = {
  { name = "pos",  type = "Vec2"          },
  { name = "mesh", type = "NebulaTextMesh" },  -- 非法！L2 帧级类型
}

assert_error_contains(
  "NebulaTextMesh 在 Visual 中被拦截",
  function() nebula_validate_visual("BadTextVisual", illegal_mesh_fields, {}) end,
  "Axiom-B"
)

assert_error_contains(
  "错误信息包含字段名 'mesh'",
  function() nebula_validate_visual("BadTextVisual", illegal_mesh_fields, {}) end,
  "mesh"
)

-- =============================================================================
-- 4. 任务 A：GapBuffer 被拦截
-- =============================================================================
print("\n--- 4. 任务 A：GapBuffer 被拦截 ---")

local illegal_gap_fields = {
  { name = "pos",    type = "Vec2"      },
  { name = "buffer", type = "GapBuffer" },  -- 非法！L2 帧级类型
}

assert_error_contains(
  "GapBuffer 在 Visual 中被拦截",
  function() nebula_validate_visual("BadInputVisual", illegal_gap_fields, {}) end,
  "Axiom-B"
)

assert_error_contains(
  "错误信息包含字段名 'buffer'",
  function() nebula_validate_visual("BadInputVisual", illegal_gap_fields, {}) end,
  "buffer"
)

-- =============================================================================
-- 5. 任务 A：指针类型被拦截
-- =============================================================================
print("\n--- 5. 任务 A：指针类型被拦截 ---")

local illegal_ptr_fields = {
  { name = "pos",      type = "Vec2"    },
  { name = "data_ptr", type = "*uint8"  },  -- 非法！指针类型
}

assert_error_contains(
  "指针类型字段被拦截",
  function() nebula_validate_visual("BadPtrVisual", illegal_ptr_fields, {}) end,
  "Axiom-B"
)

-- =============================================================================
-- 6. 任务 A：状态字段中的非法类型被拦截
-- =============================================================================
print("\n--- 6. 任务 A：状态字段中的非法类型被拦截 ---")

local legal_base = { { name = "pos", type = "Vec2" } }
local illegal_state_fields = {
  default = {
    color = { name = "default_color", type = "Color" },
  },
  hovered = {
    -- 在状态字段中嵌入非法类型
    mesh = { name = "hovered_mesh", type = "NebulaTextMesh" },
  },
}

assert_error_contains(
  "状态字段中的非法类型被拦截",
  function() nebula_validate_visual("BadStateVisual", legal_base, illegal_state_fields) end,
  "Axiom-B"
)

-- =============================================================================
-- 7. 任务 C：合法 App 注册通过校验
-- =============================================================================
print("\n--- 7. 任务 C：合法 App 注册通过校验 ---")

nebula_app_begin("LegalApp")
  nebula_app_register_component("card",     "CardVisual")
  nebula_app_register_component("btn_ok",   "ButtonVisual")
  nebula_app_register_component("btn_cancel", "ButtonVisual")
  nebula_app_register_slot("item_slot", "ItemVisual", { max_instances = 50 })
nebula_app_end()

local ok_legal_app = pcall(nebula_validate_app, "LegalApp", nebula_app_registry["LegalApp"])
assert_eq("合法 App 通过 App 级校验", ok_legal_app, true)

-- =============================================================================
-- 8. 任务 C：非法组件名（含空格）被拦截
-- =============================================================================
print("\n--- 8. 任务 C：非法组件名（含空格）被拦截 ---")

nebula_app_begin("BadNameApp1")
  -- 直接向注册表注入非法组件名（绕过 register 的正常路径，模拟未来 API 误用）
nebula_app_end()
-- 手动注入非法组件名到注册表
nebula_app_registry["BadNameApp1"].components = {
  { name = "my card", visual_type = "CardVisual", base = "Card" },  -- 含空格！
}

assert_error_contains(
  "含空格的组件名被拦截",
  function() nebula_validate_app("BadNameApp1", nebula_app_registry["BadNameApp1"]) end,
  "Invariant-I1"
)

-- =============================================================================
-- 9. 任务 C：非法组件名（数字开头）被拦截
-- =============================================================================
print("\n--- 9. 任务 C：非法组件名（数字开头）被拦截 ---")

nebula_app_begin("BadNameApp2")
nebula_app_end()
nebula_app_registry["BadNameApp2"].components = {
  { name = "1card", visual_type = "CardVisual", base = "Card" },  -- 数字开头！
}

assert_error_contains(
  "数字开头的组件名被拦截",
  function() nebula_validate_app("BadNameApp2", nebula_app_registry["BadNameApp2"]) end,
  "Invariant-I1"
)

-- =============================================================================
-- 10. 任务 C：Slot max_instances 为 0 被拦截
-- =============================================================================
print("\n--- 10. 任务 C：Slot max_instances 为 0 被拦截 ---")

nebula_app_begin("BadSlotApp1")
nebula_app_end()
nebula_app_registry["BadSlotApp1"].slots = {
  { name = "item_slot", visual_type = "ItemVisual", base = "Item", max_instances = 0 },
}

assert_error_contains(
  "max_instances=0 的 Slot 被拦截",
  function() nebula_validate_app("BadSlotApp1", nebula_app_registry["BadSlotApp1"]) end,
  "Invariant-I1"
)

-- =============================================================================
-- 11. 任务 C：Slot max_instances 为非整数被拦截
-- =============================================================================
print("\n--- 11. 任务 C：Slot max_instances 为非整数被拦截 ---")

nebula_app_begin("BadSlotApp2")
nebula_app_end()
nebula_app_registry["BadSlotApp2"].slots = {
  { name = "item_slot", visual_type = "ItemVisual", base = "Item", max_instances = 3.14 },
}

assert_error_contains(
  "max_instances=3.14（非整数）的 Slot 被拦截",
  function() nebula_validate_app("BadSlotApp2", nebula_app_registry["BadSlotApp2"]) end,
  "Invariant-I1"
)

-- =============================================================================
-- 12. 任务 C：Slot max_instances 为负数被拦截
-- =============================================================================
print("\n--- 12. 任务 C：Slot max_instances 为负数被拦截 ---")

nebula_app_begin("BadSlotApp3")
nebula_app_end()
nebula_app_registry["BadSlotApp3"].slots = {
  { name = "item_slot", visual_type = "ItemVisual", base = "Item", max_instances = -10 },
}

assert_error_contains(
  "max_instances=-10（负数）的 Slot 被拦截",
  function() nebula_validate_app("BadSlotApp3", nebula_app_registry["BadSlotApp3"]) end,
  "Invariant-I1"
)

-- =============================================================================
-- 13. 任务 B：无冲突的 App 通过校验
-- =============================================================================
print("\n--- 13. 任务 B：无冲突的 App 通过校验 ---")

nebula_app_begin("NoPipelineConflictApp")
  nebula_app_register_component("card",   "CardVisual")
  nebula_app_register_component("button", "ButtonVisual")
nebula_app_end()

local ok_no_conflict = pcall(nebula_validate_app,
  "NoPipelineConflictApp", nebula_app_registry["NoPipelineConflictApp"])
assert_eq("无管线冲突的 App 通过校验", ok_no_conflict, true)

-- =============================================================================
-- 14. 任务 B：管线路径冲突被拦截
-- =============================================================================
print("\n--- 14. 任务 B：管线路径冲突被拦截 ---")

-- 构造一个 type_groups 中存在路径冲突的场景：
-- 同一 pipeline_name 被 standard_instanced 和 shadow_multipass 两种路径共享
nebula_app_begin("ConflictPipelineApp")
nebula_app_end()

-- 手动构造冲突的 type_groups
nebula_app_registry["ConflictPipelineApp"].type_groups = {
  ["CardVisual"] = {
    pipeline_name = "CardPipeline",
    base          = "Card",
    members       = { { name = "card", is_slot = false } },
  },
  ["ShadowCardVisual"] = {
    pipeline_name = "CardPipeline",  -- 与 CardVisual 共享同一管线名！
    base          = "Card",
    members       = { { name = "shadow_card", is_slot = false } },
  },
}
-- 将 ShadowCardVisual 注册为阴影组件，使其路径为 shadow_multipass
nebula_app_registry["ConflictPipelineApp"].shadows = {
  { name = "shadow_card", visual_type = "ShadowCardVisual", base = "ShadowCard" },
}

assert_error_contains(
  "管线路径冲突（shadow vs standard）被拦截",
  function() nebula_validate_app("ConflictPipelineApp", nebula_app_registry["ConflictPipelineApp"]) end,
  "Axiom-C"
)

-- =============================================================================
-- 15. 集成测试：nebula_app_generate 在合法 App 上正常生成代码
-- =============================================================================
print("\n--- 15. 集成测试：合法 App 代码生成 ---")

local ok_gen, gen_result = pcall(nebula_app_generate, "LegalApp")
assert_eq("合法 App 的 nebula_app_generate 调用成功", ok_gen, true)
if ok_gen then
  assert_eq("生成结果是 string", type(gen_result), "string")
  assert_contains("生成代码包含 LegalApp record",
    gen_result, "global LegalApp")
  assert_contains("生成代码包含 card 组件",
    gen_result, "card: CardContext")
  assert_contains("生成代码包含 btn_ok 组件",
    gen_result, "btn_ok: ButtonContext")
  assert_contains("生成代码包含 item_slot 管线",
    gen_result, "pipe_item:")
  -- 确认生成代码包含 init 方法（完整代码生成标志）
  assert_contains("生成代码包含 :init 方法",
    gen_result, ":init(")
end

-- =============================================================================
-- 16. 集成测试：nebula_app_generate 在违规 App 上抛出错误
-- =============================================================================
print("\n--- 16. 集成测试：违规 App 代码生成被阻断 ---")

-- 复用 BadNameApp1（含非法组件名）
assert_error_contains(
  "含非法组件名的 App 的代码生成被阻断",
  function() nebula_app_generate("BadNameApp1") end,
  "Invariant-I1"
)

-- =============================================================================
-- 17. 行数收敛：axiom_validator.lua
-- =============================================================================
print("\n--- 17. 行数收敛：axiom_validator.lua ---")

local validator_lines = count_lines(script_dir .. "/../src/derive/axiom_validator.lua")
if validator_lines then
  print(("  axiom_validator.lua: %d 行"):format(validator_lines))
  assert_le("axiom_validator.lua ≤ 340 行（Phase 4.0 初版）", validator_lines, 340)
else
  failed = failed + 1
  print("[FAIL] 无法读取 src/derive/axiom_validator.lua")
end

-- =============================================================================
-- 18. 行数收敛：app_factory.lua
-- =============================================================================
print("\n--- 18. 行数收敛：app_factory.lua ---")

local factory_lines = count_lines(script_dir .. "/../src/derive/app_factory.lua")
if factory_lines then
  print(("  app_factory.lua: %d 行"):format(factory_lines))
  assert_le("app_factory.lua ≤ 1020 行（含 Phase 4.0 挂载）", factory_lines, 1020)
else
  failed = failed + 1
  print("[FAIL] 无法读取 src/derive/app_factory.lua")
end

-- =============================================================================
-- 汇总
-- =============================================================================
print(("\n=== Phase 4.0 专项回归测试结果：%d 通过，%d 失败 ==="):format(passed, failed))
if failed > 0 then
  os.exit(1)
end
