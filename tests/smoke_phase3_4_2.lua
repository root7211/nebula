-- smoke_phase3_4_2.lua
-- Phase 3.4.2 冒烟测试：interaction_factory editable 原语与文本缓冲区逻辑
-- Phase 3.6.1 更新：底层实现迁移至编译期定容 Gap Buffer，更新相关断言
-- =============================================================================

local pass = 0
local fail = 0

local function check(name, cond)
  if cond then
    pass = pass + 1
  else
    fail = fail + 1
    print("  [FAIL] " .. name)
  end
end

-- 加载 interaction_factory
local f = io.open("src/derive/interaction_factory.lua", "r")
assert(f, "interaction_factory.lua not found")
local src = f:read("*a")
f:close()

-- ---- 1. 版本号检查（仅验证包含 phase3 前缀）----
-- 版本号随 Phase 演进，不硬编码具体版本
check("version contains phase3 prefix",
  src:find("nebula_interaction_factory_v", 1, true) ~= nil and src:find("phase3", 1, true) ~= nil)

-- ---- 2. nebula_gen_text_buffer 函数存在 ----
check("nebula_gen_text_buffer defined",
  src:find("function nebula_gen_text_buffer") ~= nil)

-- ---- 3. process_text_input 方法生成 ----
check("process_text_input method generated",
  src:find("process_text_input") ~= nil)
check("focused_id guard in process_text_input",
  src:find("input%.focused_id ~= self%.component_id") ~= nil)
check("char_count loop",
  src:find("i < input%.char_count") ~= nil)
check("ASCII range guard (0x20..0x7E)",
  src:find("cp >= 0x20 and cp <= 0x7E") ~= nil)

-- Phase 3.6.1: 插入/删除逻辑已迁移至 Gap Buffer API
check("cursor insert: gap_buf:insert_char (Phase 3.6.1)",
  src:find("gap_buf:insert_char") ~= nil)
check("text insert via Gap Buffer (not memmove)",
  src:find("gap_buf:insert_char%(%([@]uint8%)%(cp%)%)") ~= nil)

-- ---- 4. 控制键处理 ----
check("Backspace handled",
  src:find("NebulaKey%.Backspace") ~= nil)
check("Delete handled",
  src:find("NebulaKey%.Delete") ~= nil)
check("Left arrow handled",
  src:find("NebulaKey%.Left") ~= nil)
check("Right arrow handled",
  src:find("NebulaKey%.Right") ~= nil)
check("Home key handled",
  src:find("NebulaKey%.Home") ~= nil)
check("End key handled",
  src:find("NebulaKey%.End") ~= nil)
-- Phase 3.6.1: Backspace 调用 gap_buf:delete_before()
check("Backspace calls gap_buf:delete_before (Phase 3.6.1)",
  src:find("gap_buf:delete_before%(%)") ~= nil)
check("changed flag returned",
  src:find("return changed") ~= nil)

-- ---- 5. get_text 方法生成 ----
check("get_text method generated",
  src:find("function.*get_text") ~= nil)
-- Phase 3.6.1: get_text 通过 gap_buf:flatten 输出
check("get_text uses gap_buf:flatten (Phase 3.6.1)",
  src:find("gap_buf:flatten") ~= nil)

-- ---- 6. get_text_len 方法生成（Phase 3.6.1 新增）----
check("get_text_len method generated (Phase 3.6.1)",
  src:find("get_text_len") ~= nil)
check("get_text_len uses gap_buf:len (Phase 3.6.1)",
  src:find("gap_buf:len%(%)") ~= nil)

-- ---- 7. 逻辑正确性：模拟 Gap Buffer 操作（Lua 层验证）----
-- 加载 gap_buffer 模块的 Lua 生成逻辑
local gb_file = io.open("src/gap_buffer.nelua", "r")
assert(gb_file, "gap_buffer.nelua not found")
local gb_content = gb_file:read("*a")
gb_file:close()

-- 提取并执行 ##[[ ]] 块
for block in gb_content:gmatch("##%[%[(.-)%]%]") do
  local fn, err = load(block, "gap_buffer.nelua##")
  assert(fn, "load error: " .. tostring(err))
  fn()
end

-- 生成 NebulaBuf16 用于逻辑测试
local _, gb_src = nebula_gen_gap_buffer_type(16)
assert(gb_src, "NebulaBuf16 source should be generated")

-- 验证 Gap Buffer 核心逻辑（通过源码模式匹配）
check("gap_buffer len formula: capacity - (gap_end - gap_start)",
  gb_src:find("return self%.capacity %- %(self%.gap_end %- self%.gap_start%)") ~= nil)
check("gap_buffer insert_char increments gap_start",
  gb_src:find("self%.gap_start = self%.gap_start %+ 1") ~= nil)
check("gap_buffer delete_before decrements gap_start",
  gb_src:find("self%.gap_start = self%.gap_start %- 1") ~= nil)
check("gap_buffer delete_after increments gap_end",
  gb_src:find("self%.gap_end = self%.gap_end %+ 1") ~= nil)
check("gap_buffer move_cursor_left: copy left char to right side",
  gb_src:find("self%.buf%[self%.gap_end%] = self%.buf%[self%.gap_start %- 1%]") ~= nil)
check("gap_buffer move_cursor_right: copy right char to left side",
  gb_src:find("self%.buf%[self%.gap_start%] = self%.buf%[self%.gap_end%]") ~= nil)
check("gap_buffer move_cursor_home: gap_start == 0",
  gb_src:find("self%.gap_start == 0") ~= nil)
check("gap_buffer move_cursor_end: loop while gap_end < capacity",
  gb_src:find("while self%.gap_end < self%.capacity do") ~= nil)

-- ---- 汇总 ----
print(string.format("[Phase 3.4.2] %d passed, %d failed", pass, fail))
assert(fail == 0, "Phase 3.4.2 smoke test FAILED")
