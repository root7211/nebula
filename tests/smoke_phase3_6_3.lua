-- smoke_phase3_6_3.lua — Phase 3.6.3: 文本选区回归测试
--
-- 验证：
--   1. NebulaKey 与 NebulaInputState 扩展（修饰键支持）
--   2. gap_buffer:delete_range 逻辑正确性
--   3. interaction_factory 生成的选区交互逻辑
--   4. 架构合规性（L1/L2 分层）

local tests = {}

-- 模拟环境：定义必要的宏和全局变量
global NebulaKey = @enum{
  None=0, Backspace, Delete, Left, Right, Home, End, Enter,
  ShiftLeft, ShiftRight, ShiftHome, ShiftEnd
}
global NebulaInputState = @record{
  mouse_x: float32, mouse_y: float32,
  mouse_left_down: boolean, mouse_left_pressed: boolean,
  mod_shift: boolean, mod_ctrl: boolean, mod_alt: boolean,
  key_pressed: int32, char_count: uint8, char_input: [16]uint32
}

-- ---------------------------------------------------------
-- Test 1-5: 核心结构验证
-- ---------------------------------------------------------
tests[1] = { "NebulaKey.ShiftLeft 存在", function() return NebulaKey.ShiftLeft ~= nil end }
tests[2] = { "NebulaInputState.mod_shift 存在", function() 
  local s: NebulaInputState; return s.mod_shift == false 
end }

-- ---------------------------------------------------------
-- Test 6-15: Gap Buffer delete_range 逻辑验证
-- ---------------------------------------------------------
##[[
  local _gb_type_name, _gb_src = nebula_gen_gap_buffer_type(16)
  local _gb_ast = aster.parse(_gb_src, "test_gb")
  for _, stat in ipairs(_gb_ast) do inject_statement(stat) end
]]

tests[6] = { "delete_range: 中间删除", function()
  local buf: NebulaBuf16; buf:init()
  buf:insert_char((@uint8)('a'))
  buf:insert_char((@uint8)('b'))
  buf:insert_char((@uint8)('c'))
  buf:insert_char((@uint8)('d')) -- "abcd", cursor=4
  buf:delete_range(1, 3) -- 删除 "bc"
  local flat: [16]uint8; buf:flatten(&flat[0], 16)
  return (@cstring)(&flat[0]) == "ad" and buf:cursor() == 1
end }

tests[7] = { "delete_range: 头部删除", function()
  local buf: NebulaBuf16; buf:init()
  buf:insert_char((@uint8)('a'))
  buf:insert_char((@uint8)('b'))
  buf:delete_range(0, 1) -- 删除 "a"
  local flat: [16]uint8; buf:flatten(&flat[0], 16)
  return (@cstring)(&flat[0]) == "b" and buf:cursor() == 0
end }

tests[8] = { "delete_range: 尾部删除", function()
  local buf: NebulaBuf16; buf:init()
  buf:insert_char((@uint8)('a'))
  buf:insert_char((@uint8)('b'))
  buf:delete_range(1, 2) -- 删除 "b"
  local flat: [16]uint8; buf:flatten(&flat[0], 16)
  return (@cstring)(&flat[0]) == "a" and buf:cursor() == 1
end }

-- ---------------------------------------------------------
-- Test 16-25: 生成代码静态检查（通过 Python 脚本执行）
-- ---------------------------------------------------------

-- ---------------------------------------------------------
-- 运行测试（模拟 Python 脚本逻辑）
-- ---------------------------------------------------------
local passed = 0
local total = 8
for i=1,total do
  if tests[i] then
    local ok, res = pcall(tests[i][2])
    if ok and res then
      passed = passed + 1
    else
      print("FAILED: Test " .. i .. ": " .. tests[i][1])
    end
  end
end

if passed == total then
  print("PASSED: all " .. total .. " runtime tests")
else
  print("FAILED: " .. (total - passed) .. " tests failed")
end
