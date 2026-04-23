-- tests/smoke_phase3_6_1.lua
-- Nebula Phase 3.6.1 回归测试：编译期定容 Gap Buffer
--
-- 测试覆盖：
--   1. nebula_gen_gap_buffer_type 代码生成
--   2. Gap Buffer 初始化状态
--   3. insert_char O(1) 插入
--   4. delete_before / delete_after O(1) 删除
--   5. move_cursor_left / move_cursor_right 光标移动
--   6. move_cursor_home / move_cursor_end 行首行尾
--   7. flatten 展平输出
--   8. is_full 边界检测
--   9. clear 清空
--  10. interaction_factory 版本号升级验证
--  11. nebula_gen_text_buffer 生成 Gap Buffer 驱动代码
-- =============================================================================

package.path = package.path
  .. ";/home/ubuntu/nebula/src/?.lua"
  .. ";/home/ubuntu/nebula/src/derive/?.lua"

-- 加载 gap_buffer 模块（通过 dofile 执行 .nelua 文件中的 ##[[ ]] 块）
-- 由于 gap_buffer.nelua 是 Nelua 文件，我们直接测试其 Lua 生成逻辑
-- 通过 loadstring 模拟 ##[[ ]] 块执行
local function load_gap_buffer_module()
  local f = io.open("/home/ubuntu/nebula/src/gap_buffer.nelua", "r")
  assert(f, "cannot open gap_buffer.nelua")
  local content = f:read("*a")
  f:close()
  -- 提取 ##[[ ]] 块中的 Lua 代码
  local lua_blocks = {}
  for block in content:gmatch("##%[%[(.-)%]%]") do
    table.insert(lua_blocks, block)
  end
  for _, block in ipairs(lua_blocks) do
    local fn, err = load(block, "gap_buffer.nelua##")
    assert(fn, "load error: " .. tostring(err))
    fn()
  end
end

load_gap_buffer_module()

-- 加载 interaction_factory
local interaction_factory_mod = require "interaction_factory"

-- =============================================================================
-- 测试框架
-- =============================================================================
local passed = 0
local failed = 0

local function check(name, cond, got, expected)
  if cond then
    passed = passed + 1
    -- print(("[PASS] %s"):format(name))
  else
    failed = failed + 1
    print(("[FAIL] %s | got: %s | expected: %s"):format(
      name, tostring(got), tostring(expected)))
  end
end

local function eq(a, b) return a == b end
local function neq(a, b) return a ~= b end
local function has_pattern(s, p) return s:find(p, 1, true) ~= nil end

-- =============================================================================
-- 测试 1: nebula_gen_gap_buffer_type 函数存在
-- =============================================================================
check("gap_buffer: nebula_gen_gap_buffer_type 函数已定义",
  type(nebula_gen_gap_buffer_type) == "function", type(nebula_gen_gap_buffer_type), "function")

-- =============================================================================
-- 测试 2: 生成 NebulaBuf16 类型（小容量用于测试）
-- =============================================================================
local type_name, src = nebula_gen_gap_buffer_type(16)
check("gap_buffer: type_name 为 NebulaBuf16", eq(type_name, "NebulaBuf16"), type_name, "NebulaBuf16")
check("gap_buffer: 生成源码不为空", type(src) == "string" and #src > 0, #src, ">0")

-- =============================================================================
-- 测试 3: 生成代码包含所有必要的方法
-- =============================================================================
local methods = {"init", "len", "is_full", "cursor", "insert_char",
                 "delete_before", "delete_after",
                 "move_cursor_left", "move_cursor_right",
                 "move_cursor_home", "move_cursor_end",
                 "flatten", "clear"}
for _, m in ipairs(methods) do
  check(("gap_buffer: 生成代码包含方法 %s"):format(m),
    has_pattern(src, "function NebulaBuf16:" .. m),
    src:find("function NebulaBuf16:" .. m), "found")
end

-- =============================================================================
-- 测试 4: 生成代码包含正确的容量常量
-- =============================================================================
check("gap_buffer: buf 数组大小为 17 (capacity+1)",
  has_pattern(src, "[17]uint8"), src:match("%[%d+%]uint8"), "[17]uint8")
check("gap_buffer: gap_end 初始化为 16",
  has_pattern(src, "self.gap_end   = 16"), nil, "found")
check("gap_buffer: capacity 初始化为 16",
  has_pattern(src, "self.capacity  = 16"), nil, "found")

-- =============================================================================
-- 测试 5: 重复生成同一容量不会重复定义（防重机制）
-- =============================================================================
local type_name2, src2 = nebula_gen_gap_buffer_type(16)
check("gap_buffer: 重复生成 NebulaBuf16 返回相同 type_name",
  eq(type_name2, "NebulaBuf16"), type_name2, "NebulaBuf16")
check("gap_buffer: 重复生成 NebulaBuf16 返回 nil src（防重）",
  src2 == nil, src2, "nil")

-- =============================================================================
-- 测试 6: 生成不同容量的类型
-- =============================================================================
local tn255, s255 = nebula_gen_gap_buffer_type(255)
check("gap_buffer: NebulaBuf255 type_name 正确", eq(tn255, "NebulaBuf255"), tn255, "NebulaBuf255")
check("gap_buffer: NebulaBuf255 buf 大小为 256",
  has_pattern(s255, "[256]uint8"), nil, "found")

local tn1024, s1024 = nebula_gen_gap_buffer_type(1024)
check("gap_buffer: NebulaBuf1024 type_name 正确", eq(tn1024, "NebulaBuf1024"), tn1024, "NebulaBuf1024")
check("gap_buffer: NebulaBuf1024 buf 大小为 1025",
  has_pattern(s1024, "[1025]uint8"), nil, "found")

-- =============================================================================
-- 测试 7: insert_char 生成代码逻辑正确
-- =============================================================================
check("gap_buffer: insert_char 检查 is_full",
  has_pattern(src, "if self:is_full() then return false end"), nil, "found")
check("gap_buffer: insert_char 写入 buf[gap_start]",
  has_pattern(src, "self.buf[self.gap_start] = ch"), nil, "found")
check("gap_buffer: insert_char 递增 gap_start",
  has_pattern(src, "self.gap_start = self.gap_start + 1"), nil, "found")

-- =============================================================================
-- 测试 8: delete_before 生成代码逻辑正确
-- =============================================================================
check("gap_buffer: delete_before 检查 gap_start == 0",
  has_pattern(src, "if self.gap_start == 0 then return false end"), nil, "found")
check("gap_buffer: delete_before 递减 gap_start",
  has_pattern(src, "self.gap_start = self.gap_start - 1"), nil, "found")

-- =============================================================================
-- 测试 9: delete_after 生成代码逻辑正确
-- =============================================================================
check("gap_buffer: delete_after 检查 gap_end >= capacity",
  has_pattern(src, "if self.gap_end >= self.capacity then return false end"), nil, "found")
check("gap_buffer: delete_after 递增 gap_end",
  has_pattern(src, "self.gap_end = self.gap_end + 1"), nil, "found")

-- =============================================================================
-- 测试 10: move_cursor_left 生成代码逻辑正确（O(1) 单字节移动）
-- =============================================================================
check("gap_buffer: move_cursor_left 检查 gap_start == 0",
  has_pattern(src, "if self.gap_start == 0 then return false end"), nil, "found")
check("gap_buffer: move_cursor_left 将左侧字符移到右侧",
  has_pattern(src, "self.buf[self.gap_end] = self.buf[self.gap_start - 1]"), nil, "found")

-- =============================================================================
-- 测试 11: move_cursor_right 生成代码逻辑正确（O(1) 单字节移动）
-- =============================================================================
check("gap_buffer: move_cursor_right 检查 gap_end >= capacity",
  has_pattern(src, "if self.gap_end >= self.capacity then return false end"), nil, "found")
check("gap_buffer: move_cursor_right 将右侧字符移到左侧",
  has_pattern(src, "self.buf[self.gap_start] = self.buf[self.gap_end]"), nil, "found")

-- =============================================================================
-- 测试 12: flatten 生成代码逻辑正确
-- =============================================================================
check("gap_buffer: flatten 先复制 left_text (0..gap_start)",
  has_pattern(src, "while i < self.gap_start and n < max_out do"), nil, "found")
check("gap_buffer: flatten 再复制 right_text (gap_end..capacity)",
  has_pattern(src, "i = self.gap_end"), nil, "found")
check("gap_buffer: flatten 写入 null terminator",
  has_pattern(src, "out[n] = 0"), nil, "found")

-- =============================================================================
-- 测试 13: clear 生成代码逻辑正确
-- =============================================================================
check("gap_buffer: clear 重置 gap_start 为 0",
  has_pattern(src, "self.gap_start = 0"), nil, "found")
check("gap_buffer: clear 重置 gap_end 为 capacity",
  has_pattern(src, "self.gap_end   = self.capacity"), nil, "found")

-- =============================================================================
-- 测试 14: len 计算公式正确
-- =============================================================================
check("gap_buffer: len = capacity - (gap_end - gap_start)",
  has_pattern(src, "return self.capacity - (self.gap_end - self.gap_start)"), nil, "found")

-- =============================================================================
-- 测试 15: interaction_factory 版本号升级到 v0.4
-- =============================================================================
check("interaction_factory: 版本号为 v0.4_phase3.6.1",
  eq(interaction_factory_mod, "nebula_interaction_factory_v0.4_phase3.6.1"),
  interaction_factory_mod, "nebula_interaction_factory_v0.4_phase3.6.1")

-- =============================================================================
-- 测试 16: nebula_gen_text_buffer 使用 Gap Buffer API
-- =============================================================================
local tb_src = nebula_gen_text_buffer({ base = "Input", max_text_len = 255 })
check("interaction_factory: nebula_gen_text_buffer 生成 Gap Buffer 驱动代码",
  has_pattern(tb_src, "gap_buf:insert_char"), tb_src:sub(1, 80), "contains gap_buf:insert_char")
check("interaction_factory: nebula_gen_text_buffer 使用 delete_before",
  has_pattern(tb_src, "gap_buf:delete_before"), nil, "found")
check("interaction_factory: nebula_gen_text_buffer 使用 delete_after",
  has_pattern(tb_src, "gap_buf:delete_after"), nil, "found")
check("interaction_factory: nebula_gen_text_buffer 使用 move_cursor_left",
  has_pattern(tb_src, "gap_buf:move_cursor_left"), nil, "found")
check("interaction_factory: nebula_gen_text_buffer 使用 move_cursor_right",
  has_pattern(tb_src, "gap_buf:move_cursor_right"), nil, "found")
check("interaction_factory: nebula_gen_text_buffer 使用 move_cursor_home",
  has_pattern(tb_src, "gap_buf:move_cursor_home"), nil, "found")
check("interaction_factory: nebula_gen_text_buffer 使用 move_cursor_end",
  has_pattern(tb_src, "gap_buf:move_cursor_end"), nil, "found")
check("interaction_factory: nebula_gen_text_buffer 生成 get_text_len 方法",
  has_pattern(tb_src, "get_text_len"), nil, "found")
check("interaction_factory: nebula_gen_text_buffer 生成 flatten 调用",
  has_pattern(tb_src, "gap_buf:flatten"), nil, "found")

-- =============================================================================
-- 测试 17: nebula_gen_gap_buffer_version 版本标记
-- =============================================================================
check("gap_buffer: 版本标记为 v0.1_phase3.6.1",
  eq(nebula_gap_buffer_version, "v0.1_phase3.6.1"),
  nebula_gap_buffer_version, "v0.1_phase3.6.1")

-- =============================================================================
-- 汇总
-- =============================================================================
local total = passed + failed
print(("Phase 3.6.1 回归测试: %d/%d 通过"):format(passed, total))
if failed > 0 then
  os.exit(1)
end
