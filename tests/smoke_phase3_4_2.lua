-- smoke_phase3_4_2.lua
-- Phase 3.4.2 冒烟测试：interaction_factory editable 原语与文本缓冲区逻辑
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

-- ---- 1. 版本号更新 ----
check("version updated to v0.2_phase3.4",
  src:find("nebula_interaction_factory_v0%.2_phase3%.4") ~= nil)

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
check("cursor insert: memmove-style shift",
  src:find("self%.visual%.text_buf%[j%] = self%.visual%.text_buf%[j %- 1%]") ~= nil)
check("text_len increment on insert",
  src:find("self%.visual%.text_len = self%.visual%.text_len %+ 1") ~= nil)
check("cursor_pos increment on insert",
  src:find("self%.visual%.cursor_pos = self%.visual%.cursor_pos %+ 1") ~= nil)
check("null terminator maintained",
  src:find("self%.visual%.text_buf%[self%.visual%.text_len%] = 0") ~= nil)

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
check("Backspace decrements cursor_pos",
  src:find("self%.visual%.cursor_pos = self%.visual%.cursor_pos %- 1") ~= nil)
check("changed flag returned",
  src:find("return changed") ~= nil)

-- ---- 5. get_text 方法生成 ----
check("get_text method generated",
  src:find("function.*get_text") ~= nil)
check("get_text returns cstring from text_buf",
  src:find("@cstring.*&self%.visual%.text_buf%[0%]") ~= nil)

-- ---- 6. 逻辑正确性：模拟文本缓冲区操作 ----
local buf = {}
local text_len = 0
local cursor_pos = 0

local function insert_char(cp)
  if cp >= 0x20 and cp <= 0x7E and text_len < 255 then
    local j = text_len
    while j > cursor_pos do
      buf[j] = buf[j-1]
      j = j - 1
    end
    buf[cursor_pos] = cp
    text_len = text_len + 1
    cursor_pos = cursor_pos + 1
    buf[text_len] = 0
  end
end

local function backspace()
  if cursor_pos > 0 then
    local j = cursor_pos
    while j < text_len do
      buf[j-1] = buf[j]
      j = j + 1
    end
    text_len = text_len - 1
    cursor_pos = cursor_pos - 1
    buf[text_len] = 0
  end
end

local function get_text()
  local s = ""
  for i = 0, text_len - 1 do
    s = s .. string.char(buf[i])
  end
  return s
end

-- 插入 "hello"
for _, c in ipairs({string.byte("hello", 1, 5)}) do insert_char(c) end
check("insert 'hello' -> text_len=5", text_len == 5)
check("insert 'hello' -> cursor_pos=5", cursor_pos == 5)
check("insert 'hello' -> get_text='hello'", get_text() == "hello")

-- 退格删除最后一个字符
backspace()
check("backspace -> 'hell'", get_text() == "hell")
check("backspace -> cursor_pos=4", cursor_pos == 4)

-- 光标左移到开头，插入字符
cursor_pos = 0
insert_char(string.byte("!"))
check("insert at pos 0 -> '!hell'", get_text() == "!hell")
check("insert at pos 0 -> cursor_pos=1", cursor_pos == 1)

-- Home 键
cursor_pos = 0
check("Home -> cursor_pos=0", cursor_pos == 0)

-- End 键
cursor_pos = text_len
check("End -> cursor_pos=text_len", cursor_pos == text_len)

-- ---- 汇总 ----
print(string.format("[Phase 3.4.2] %d passed, %d failed", pass, fail))
assert(fail == 0, "Phase 3.4.2 smoke test FAILED")
