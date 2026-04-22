-- =============================================================================
-- smoke_phase3_4_3.lua
-- Phase 3.4.3 冒烟测试：极简光标渲染模块
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

-- ---- 1. nebula_cursor.nelua 静态结构断言 ----
local f = io.open("src/nebula_cursor.nelua", "r")
assert(f, "nebula_cursor.nelua not found")
local src = f:read("*a")
f:close()

check("nebula_cursor_x_offset defined",
  src:find("nebula_cursor_x_offset") ~= nil)
check("nebula_cursor_visible defined",
  src:find("nebula_cursor_visible") ~= nil)
check("advances parameter present",
  src:find("advances%s*:%s*%*float32") ~= nil)
check("cursor_pos parameter present",
  src:find("cursor_pos%s*:%s*uint32") ~= nil)
check("accumulation loop present",
  src:find("offset = offset %+ advances%[i%]") ~= nil)
check("returns float32 offset",
  src:find("return offset") ~= nil)
check("time parameter in cursor_visible",
  src:find("time%s*:%s*float64") ~= nil)
check("0.5s blink logic present",
  src:find("0%.5") ~= nil)
check("returns boolean",
  src:find("return t < 0%.5") ~= nil)

-- ---- 2. 逻辑正确性：用纯 Lua 模拟 nebula_cursor_x_offset ----
local function cursor_x_offset(advances, cursor_pos, count)
  local offset = 0.0
  local i = 0
  while i < cursor_pos and i < count do
    offset = offset + advances[i]
    i = i + 1
  end
  return offset
end

local advances = {[0]=8.0, [1]=6.0, [2]=7.0, [3]=5.0, [4]=9.0}
local count = 5

check("cursor at pos 0 -> offset 0",
  cursor_x_offset(advances, 0, count) == 0.0)
check("cursor at pos 1 -> offset 8",
  cursor_x_offset(advances, 1, count) == 8.0)
check("cursor at pos 3 -> offset 21",
  cursor_x_offset(advances, 3, count) == 21.0)
check("cursor at pos 5 (end) -> offset 35",
  cursor_x_offset(advances, 5, count) == 35.0)
check("cursor beyond count -> clamped to count",
  cursor_x_offset(advances, 100, count) == 35.0)
check("empty string -> offset 0",
  cursor_x_offset(advances, 0, 0) == 0.0)

-- ---- 3. 逻辑正确性：用纯 Lua 模拟 nebula_cursor_visible ----
local function cursor_visible(time)
  local t = time - math.floor(time)
  return t < 0.5
end

check("t=0.0 -> visible",    cursor_visible(0.0) == true)
check("t=0.25 -> visible",   cursor_visible(0.25) == true)
check("t=0.499 -> visible",  cursor_visible(0.499) == true)
check("t=0.5 -> invisible",  cursor_visible(0.5) == false)
check("t=0.75 -> invisible", cursor_visible(0.75) == false)
check("t=0.999 -> invisible",cursor_visible(0.999) == false)
check("t=1.0 -> visible (next cycle)", cursor_visible(1.0) == true)
check("t=1.3 -> visible",    cursor_visible(1.3) == true)
check("t=1.7 -> invisible",  cursor_visible(1.7) == false)

-- ---- 汇总 ----
print(string.format("[Phase 3.4.3] %d passed, %d failed", pass, fail))
assert(fail == 0, "Phase 3.4.3 smoke test FAILED")
