-- verify_interaction_behavior.lua
-- Nebula — 运行时行为验证：交互原语的逻辑正确性
--
-- 与现有冒烟测试不同，本测试不匹配源码模式，而是在 Lua 中模拟
-- interaction_factory 生成的 Nelua 代码所实现的算法，验证行为正确性。
--
-- 覆盖范围：
--   1. hit_test AABB 碰撞检测
--   2. click.just_clicked 边沿检测（仅释放帧为 true）
--   3. scrollable scroll_offset_y 滚动 + 钳位
--   4. scrollable hit-test 在滚动偏移下的正确性（BUG-4 回归）
--   5. dropdown_manager is_open 切换 + 外部点击关闭
--   6. dropdown 隐藏项不可命中（BUG-5 回归）
--   7. Gap Buffer extract_range 边界行为（BUG-6 回归）
-- =============================================================================

local passed = 0
local failed = 0

local function check(name, cond)
  if cond then
    passed = passed + 1
    print(("[PASS] %s"):format(name))
  else
    failed = failed + 1
    print(("[FAIL] %s"):format(name))
  end
end

-- =========================================================================
-- 辅助：模拟 AABB hit_test（与 nebula_gen_hit_test 生成的逻辑一致）
-- =========================================================================
local function hit_test(pos_x, pos_y, size_x, size_y, mx, my)
  return mx >= pos_x and mx < pos_x + size_x and
         my >= pos_y and my < pos_y + size_y
end

-- =========================================================================
-- 辅助：模拟 click 原语的 process_body（与 interaction_factory clickable 一致）
-- =========================================================================
local function click_update(state, hovered, mouse_left_down)
  local prev_pressed = state.is_pressed
  state.is_pressed   = (hovered and mouse_left_down)
  state.just_clicked = (prev_pressed and not state.is_pressed and hovered)
  return state
end

-- =========================================================================
-- 辅助：模拟 scrollable 原语的 process_body（与 interaction_factory scrollable 一致）
-- =========================================================================
local function scroll_update(ctx, input)
  -- max_scroll
  ctx.max_scroll = ctx.content_height - ctx.size_y
  if ctx.max_scroll < 0 then ctx.max_scroll = 0 end
  -- wheel
  if ctx.is_hovered then
    local scroll_speed = 30.0
    ctx.scroll_offset_y = ctx.scroll_offset_y - input.scroll_dy * scroll_speed
  end
  -- clamp
  if ctx.scroll_offset_y < 0 then ctx.scroll_offset_y = 0 end
  if ctx.scroll_offset_y > ctx.max_scroll then ctx.scroll_offset_y = ctx.max_scroll end
  return ctx
end

-- =========================================================================
-- 辅助：模拟 dropdown_manager 原语的 process_body
-- =========================================================================
local function dropdown_update(ctx, hovered, input)
  if ctx.just_clicked then
    ctx.is_open = not ctx.is_open
  end
  if ctx.is_open and input.mouse_left_pressed and not hovered then
    ctx.is_open = false
  end
  return ctx
end

-- =========================================================================
-- 辅助：模拟 Gap Buffer（与 gap_buffer.nelua / gap_buffer_factory.lua 一致）
-- =========================================================================
local function new_gap_buffer(capacity)
  local gb = {
    buf = {},
    gap_start = 0,
    gap_end = capacity,
    capacity = capacity,
  }
  for i = 0, capacity do gb.buf[i] = 0 end

  function gb:insert_char(ch)
    if self.gap_start == self.gap_end then return false end
    self.buf[self.gap_start] = ch
    self.gap_start = self.gap_start + 1
    return true
  end

  function gb:len()
    return self.capacity - (self.gap_end - self.gap_start)
  end

  function gb:move_cursor_left()
    if self.gap_start == 0 then return false end
    self.gap_end = self.gap_end - 1
    self.buf[self.gap_end] = self.buf[self.gap_start - 1]
    self.gap_start = self.gap_start - 1
    return true
  end

  function gb:move_cursor_right()
    if self.gap_end >= self.capacity then return false end
    self.buf[self.gap_start] = self.buf[self.gap_end]
    self.gap_start = self.gap_start + 1
    self.gap_end = self.gap_end + 1
    return true
  end

  function gb:extract_range(sel_start, sel_end)
    if sel_start >= sel_end then return "" end
    local out = {}
    local idx = sel_start
    while idx < sel_end do
      local phys
      if idx < self.gap_start then
        phys = idx
      else
        phys = self.gap_end + (idx - self.gap_start)
      end
      table.insert(out, string.char(self.buf[phys]))
      idx = idx + 1
    end
    return table.concat(out)
  end

  return gb
end


print("============================================")
print(" Nebula — Interaction Behavior Verification")
print("============================================")

-- =========================================================================
-- 1. hit_test AABB
-- =========================================================================
print("\n=== 1. hit_test AABB ===")

check("hit_test: 中心命中",       hit_test(100, 200, 50, 30, 125, 215))
check("hit_test: 左上角命中",     hit_test(100, 200, 50, 30, 100, 200))
check("hit_test: 右下角不命中",   not hit_test(100, 200, 50, 30, 150, 230))
check("hit_test: 完全在外不命中", not hit_test(100, 200, 50, 30, 0, 0))
check("hit_test: 左侧 1px 外",   not hit_test(100, 200, 50, 30, 99, 215))
check("hit_test: 上方 1px 外",    not hit_test(100, 200, 50, 30, 125, 199))

-- =========================================================================
-- 2. click.just_clicked 边沿检测
-- =========================================================================
print("\n=== 2. click.just_clicked edge detection ===")

local click = { is_pressed = false, just_clicked = false }

-- 帧 1：鼠标未按下，悬停
click = click_update(click, true, false)
check("click F1: 未按下时 just_clicked=false", not click.just_clicked)
check("click F1: is_pressed=false",            not click.is_pressed)

-- 帧 2：鼠标按下，悬停
click = click_update(click, true, true)
check("click F2: 按下时 just_clicked=false",   not click.just_clicked)
check("click F2: is_pressed=true",             click.is_pressed)

-- 帧 3：鼠标保持按下
click = click_update(click, true, true)
check("click F3: 保持按下 just_clicked=false", not click.just_clicked)

-- 帧 4：鼠标释放，仍悬停 → just_clicked!
click = click_update(click, true, false)
check("click F4: 释放时 just_clicked=true",    click.just_clicked)

-- 帧 5：下一帧自动复位
click = click_update(click, true, false)
check("click F5: 下一帧 just_clicked=false（单帧脉冲）", not click.just_clicked)

-- 帧 6：按下后拖出再释放 → 不触发
click = click_update(click, true, true)   -- 按下
click = click_update(click, false, true)  -- 拖出（不悬停但仍按下）
click = click_update(click, false, false) -- 释放（不悬停）
check("click F6: 拖出后释放 just_clicked=false", not click.just_clicked)

-- =========================================================================
-- 3. scrollable scroll_offset_y 滚动 + 钳位
-- =========================================================================
print("\n=== 3. scrollable scroll behavior ===")

local scroll = {
  scroll_offset_y = 0,
  max_scroll = 0,
  content_height = 500,
  size_y = 300,
  is_hovered = true,
}

-- 向下滚动（scroll_dy < 0 → offset 增加）
scroll = scroll_update(scroll, { scroll_dy = -2 })
check("scroll: 向下滚动后 offset > 0", scroll.scroll_offset_y > 0)
check("scroll: max_scroll = 200",       scroll.max_scroll == 200)

-- 连续滚动到底部
for _ = 1, 100 do
  scroll = scroll_update(scroll, { scroll_dy = -2 })
end
check("scroll: 钳位到 max_scroll",     scroll.scroll_offset_y == 200)

-- 反方向滚动到顶部
for _ = 1, 100 do
  scroll = scroll_update(scroll, { scroll_dy = 2 })
end
check("scroll: 钳位到 0",              scroll.scroll_offset_y == 0)

-- 内容小于容器时 max_scroll = 0
scroll.content_height = 100
scroll = scroll_update(scroll, { scroll_dy = -5 })
check("scroll: 内容 < 容器时 max_scroll=0", scroll.max_scroll == 0)
check("scroll: 内容 < 容器时 offset 保持 0", scroll.scroll_offset_y == 0)

-- 未悬停时不响应滚轮
scroll.content_height = 500
scroll.is_hovered = false
scroll.scroll_offset_y = 100
scroll = scroll_update(scroll, { scroll_dy = -5 })
check("scroll: 未悬停时滚轮无效", scroll.scroll_offset_y == 100)

-- =========================================================================
-- 4. BUG-4 回归：scrollable hit-test 必须在滚动偏移之后
-- =========================================================================
print("\n=== 4. BUG-4 regression: scroll offset before hit-test ===")

-- 模拟：滚动区域 y=100, h=200, 子按钮间距 50, 滚动偏移 80
local scroll_area = { pos_y = 100, size_y = 200 }
local scroll_offset = 80
local child_base_y = scroll_area.pos_y + 8
local child_h = 40
local child_gap = 10

-- 子按钮 0 的偏移后 Y = 108 + 0*50 - 80 = 28（在滚动区域上方，不可见）
local child0_y = child_base_y + 0 * (child_h + child_gap) - scroll_offset
-- 子按钮 2 的偏移后 Y = 108 + 2*50 - 80 = 128（在滚动区域内）
local child2_y = child_base_y + 2 * (child_h + child_gap) - scroll_offset

-- 用户点击 y=140 → 应命中 child2（偏移后），不应命中 child0
local click_y = 140
local hit_child0 = hit_test(0, child0_y, 200, child_h, 100, click_y)
local hit_child2 = hit_test(0, child2_y, 200, child_h, 100, click_y)

check("BUG-4: 偏移后 child0 不可命中（已滚出视区）", not hit_child0)
check("BUG-4: 偏移后 child2 可命中",                 hit_child2)

-- 对比 BUG-4 修复前的错误行为：如果不应用偏移
local bad_child0_y = child_base_y + 0 * (child_h + child_gap)  -- 108
local bad_child2_y = child_base_y + 2 * (child_h + child_gap)  -- 208
local bad_hit_child0 = hit_test(0, bad_child0_y, 200, child_h, 100, click_y)
check("BUG-4: 未偏移时 child0 会被误命中（旧行为）", bad_hit_child0)

-- =========================================================================
-- 5. dropdown_manager is_open 切换 + 外部点击关闭
-- =========================================================================
print("\n=== 5. dropdown toggle + outside click ===")

local dd = { is_open = false, just_clicked = false }

-- 点击打开
dd.just_clicked = true
dd = dropdown_update(dd, true, { mouse_left_pressed = false })
check("dropdown: 点击后打开",       dd.is_open)

-- 再次点击关闭
dd.just_clicked = true
dd = dropdown_update(dd, true, { mouse_left_pressed = false })
check("dropdown: 再次点击关闭",     not dd.is_open)

-- 打开状态，外部点击关闭
dd.just_clicked = true
dd = dropdown_update(dd, true, { mouse_left_pressed = false })
check("dropdown: 打开状态",         dd.is_open)
dd.just_clicked = false
dd = dropdown_update(dd, false, { mouse_left_pressed = true })
check("dropdown: 外部点击后关闭",   not dd.is_open)

-- 关闭状态，外部点击无效果
dd.just_clicked = false
dd = dropdown_update(dd, false, { mouse_left_pressed = true })
check("dropdown: 关闭状态外部点击不变", not dd.is_open)

-- =========================================================================
-- 6. BUG-5 回归：隐藏项 y=-1000 不可命中
-- =========================================================================
print("\n=== 6. BUG-5 regression: hidden dropdown items ===")

-- 下拉关闭时，项目在 y=-1000
local item_visible_y = 250
local item_hidden_y  = -1000
local item_h = 30

check("BUG-5: 可见项 (y=250) 可命中",
  hit_test(50, item_visible_y, 200, item_h, 100, 260))
check("BUG-5: 隐藏项 (y=-1000) 不可命中",
  not hit_test(50, item_hidden_y, 200, item_h, 100, 260))

-- 模拟完整的 dropdown 帧序列：
-- 帧 1: dropdown 打开，项目可见 → 点击项目
local item_y = item_visible_y
local can_hit_open = hit_test(50, item_y, 200, item_h, 100, 260)
check("BUG-5: 打开时项目可命中",   can_hit_open)

-- 帧 2: dropdown 关闭，项目移到 y=-1000 → 不可命中
-- 关键：位置更新必须在 hit-test 之前（BUG-5 修复保证）
item_y = item_hidden_y
local can_hit_closed = hit_test(50, item_y, 200, item_h, 100, 260)
check("BUG-5: 关闭后项目不可命中", not can_hit_closed)

-- =========================================================================
-- 7. BUG-6 回归：Gap Buffer extract_range 行为
-- =========================================================================
print("\n=== 7. BUG-6 regression: gap_buffer extract_range ===")

local gb = new_gap_buffer(16)
-- 插入 "Hello"
for _, ch in ipairs({72, 101, 108, 108, 111}) do  -- H e l l o
  gb:insert_char(ch)
end
check("gap_buffer: 插入后 len=5", gb:len() == 5)

-- extract_range 全范围
local full = gb:extract_range(0, 5)
check("gap_buffer: extract_range(0,5) = 'Hello'", full == "Hello")

-- extract_range 子范围
local sub = gb:extract_range(1, 4)
check("gap_buffer: extract_range(1,4) = 'ell'",   sub == "ell")

-- extract_range 空范围
local empty = gb:extract_range(3, 3)
check("gap_buffer: extract_range(3,3) = ''",       empty == "")

-- extract_range 反向无效
local inv = gb:extract_range(4, 2)
check("gap_buffer: extract_range(4,2) = '' (无效)", inv == "")

-- 光标移动后 extract_range 仍正确
gb:move_cursor_left()  -- 光标在 'o' 前
gb:move_cursor_left()  -- 光标在 'l' 前
local after_move = gb:extract_range(0, 5)
check("gap_buffer: 移动光标后 extract_range 仍正确", after_move == "Hello")

-- 在中间插入后 extract_range
gb:insert_char(88)  -- 'X'
local after_insert = gb:extract_range(0, 6)
check("gap_buffer: 中间插入后 extract_range = 'HelXlo'", after_insert == "HelXlo")


-- =========================================================================
-- 汇总
-- =========================================================================
print(string.format(
  "\n============================================\n Results: %d/%d passed, %d failed\n============================================",
  passed, passed + failed, failed))

if failed > 0 then
  print("[REGRESSION DETECTED]")
  os.exit(1)
else
  print("[ALL PASS] Interaction behavior verification complete.")
end
