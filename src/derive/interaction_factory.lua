-- =============================================================================
-- derive/interaction_factory.lua
-- Nebula GUI Compiler — Phase 2.4 → 3.6.2
--
-- 交互原语代码生成器（Interaction Factory）
--
-- 根据 Visual 规格中声明的 primitives 列表，在编译期生成以下 Nelua 源码：
--   · <T>Context:hit_test(x, y)      — 内联 AABB 碰撞检测（无函数调用层）
--   · <T>Context:process_input(input) — 按 primitives 自动生成状态机触发逻辑
--
-- 支持的原语：
--   · "hoverable"  — 生成 hovered 状态检测与 transition_to(Hovered/Default)
--   · "clickable"  — 在 hoverable 基础上叠加 pressed 状态与 just_clicked 检测
--   · "focusable"  — 生成基于 self.component_id / input.focused_id 的焦点管理
--                    component_id 是运行时字段，允许同类型多实例拥有不同焦点 ID
--
-- 公开 API：
--   nebula_gen_hit_test(spec)       -> string  (Nelua 源码)
--   nebula_gen_process_input(spec)  -> string  (Nelua 源码)
--   nebula_gen_text_buffer(spec)    -> string  (Nelua 源码)
--   nebula_gen_toggle_state(spec)   -> string  (Nelua 源码)
--
-- spec = {
--   base        : string  — 派生基名（如 "Button"），生成 ButtonContext 方法
--   state_type  : string  — 状态枚举名（如 "ButtonState"）
--   primitives  : table   — {"hoverable", "clickable"} 等
--   states      : table   — 注解中声明的所有状态名列表
-- }
-- =============================================================================

-- ===== 小工具 =====
local function has(list, name)
  for _, v in ipairs(list) do
    if v == name then return true end
  end
  return false
end

local function cap(s)
  return s:sub(1,1):upper() .. s:sub(2)
end

local function has_state(states, name)
  for _, s in ipairs(states) do
    if s == name then return true end
  end
  return false
end

-- =============================================================================
-- nebula_gen_hit_test(spec) -> string
-- =============================================================================
function nebula_gen_hit_test(spec)
  assert(spec.base, "nebula_gen_hit_test: spec.base required")
  local ctx = spec.base .. "Context"
  local lines = {}

  table.insert(lines, ("-- [interaction] %s: hit_test (AABB inline)"):format(ctx))
  table.insert(lines, ("function %s:hit_test(x: float32, y: float32): boolean"):format(ctx))
  table.insert(lines,  "  local v = &self.visual")
  table.insert(lines,  "  return x >= v.pos.x and x < v.pos.x + v.size.x and")
  table.insert(lines,  "         y >= v.pos.y and y < v.pos.y + v.size.y")
  table.insert(lines,  "end")

  return table.concat(lines, "\n")
end

-- =============================================================================
-- nebula_gen_process_input(spec) -> string
--
-- focusable 原语使用 self.component_id（运行时字段），而非编译期常量。
-- 这允许同一 Visual 类型的多个实例拥有不同的焦点 ID。
-- =============================================================================
function nebula_gen_process_input(spec)
  assert(spec.base,       "nebula_gen_process_input: spec.base required")
  assert(spec.state_type, "nebula_gen_process_input: spec.state_type required")
  assert(spec.primitives, "nebula_gen_process_input: spec.primitives required")
  assert(spec.states,     "nebula_gen_process_input: spec.states required")

  local ctx        = spec.base .. "Context"
  local st         = spec.state_type
  local prims      = spec.primitives
  local states     = spec.states

  local is_hoverable  = has(prims, "hoverable")
  local is_clickable  = has(prims, "clickable")
  local is_focusable  = has(prims, "focusable")

  -- 无任何交互原语：生成空体，保持接口统一
  if not is_hoverable and not is_clickable and not is_focusable then
    local lines = {}
    table.insert(lines, ("-- [interaction] %s: process_input (no primitives, no-op)"):format(ctx))
    table.insert(lines, ("function %s:process_input(input: *NebulaInputState): void"):format(ctx))
    table.insert(lines,  "  -- no interaction primitives declared")
    table.insert(lines,  "end")
    return table.concat(lines, "\n")
  end

  local lines = {}
  table.insert(lines, ("-- [interaction] %s: process_input (primitives=[%s])"):format(
    ctx, table.concat(prims, ", ")))
  table.insert(lines, ("function %s:process_input(input: *NebulaInputState): void"):format(ctx))

  -- ---- 1. AABB 碰撞检测 ----
  table.insert(lines,  "  local hovered = self:hit_test(input.mouse_x, input.mouse_y)")

  -- ---- 2. 更新 hover 原语字段 ----
  if is_hoverable then
    table.insert(lines,  "  local prev_hovered = self.hover.is_hovered")
    table.insert(lines,  "  self.hover.is_hovered  = hovered")
    table.insert(lines,  "  self.hover.just_entered = (hovered and not prev_hovered)")
    table.insert(lines,  "  self.hover.just_left    = (not hovered and prev_hovered)")
  end

  -- ---- 3. 更新 click 原语字段 ----
  if is_clickable then
    table.insert(lines,  "  local prev_pressed = self.click.is_pressed")
    table.insert(lines,  "  self.click.is_pressed   = (hovered and input.mouse_left_down)")
    table.insert(lines,  "  self.click.just_clicked = (prev_pressed and not self.click.is_pressed and hovered)")
  end

  -- ---- 4. 焦点管理（focusable 原语，使用运行时 self.component_id） ----
  if is_focusable then
    table.insert(lines,  "  -- focusable: uses runtime self.component_id")
    table.insert(lines,  "  if self.click.just_clicked then")
    table.insert(lines,  "    input.focused_id = self.component_id")
    table.insert(lines,  "  elseif input.mouse_left_pressed and not hovered then")
    table.insert(lines,  "    if input.focused_id == self.component_id then")
    table.insert(lines,  "      input.focused_id = 0")
    table.insert(lines,  "    end")
    table.insert(lines,  "  end")
  end

  -- ---- 5. 状态机转换（按优先级：pressed > focused > hovered > default） ----
  local has_pressed = is_clickable and has_state(states, "pressed")
  local has_focused = is_focusable and has_state(states, "focused")
  local has_hovered = is_hoverable and has_state(states, "hovered")
  local default_st  = cap(states[1])

  if has_pressed then
    table.insert(lines,  "  if self.click.is_pressed then")
    table.insert(lines, ("    self.sm:transition_to(%s.Pressed)"):format(st))
    if has_focused then
      table.insert(lines,  "  elseif input.focused_id == self.component_id then")
      table.insert(lines, ("    self.sm:transition_to(%s.Focused)"):format(st))
    end
    if has_hovered then
      table.insert(lines,  "  elseif hovered then")
      table.insert(lines, ("    self.sm:transition_to(%s.Hovered)"):format(st))
    end
    table.insert(lines,  "  else")
    table.insert(lines, ("    self.sm:transition_to(%s.%s)"):format(st, default_st))
    table.insert(lines,  "  end")
  elseif has_focused then
    table.insert(lines,  "  if input.focused_id == self.component_id then")
    table.insert(lines, ("    self.sm:transition_to(%s.Focused)"):format(st))
    if has_hovered then
      table.insert(lines,  "  elseif hovered then")
      table.insert(lines, ("    self.sm:transition_to(%s.Hovered)"):format(st))
    end
    table.insert(lines,  "  else")
    table.insert(lines, ("    self.sm:transition_to(%s.%s)"):format(st, default_st))
    table.insert(lines,  "  end")
  elseif has_hovered then
    table.insert(lines,  "  if hovered then")
    table.insert(lines, ("    self.sm:transition_to(%s.Hovered)"):format(st))
    table.insert(lines,  "  else")
    table.insert(lines, ("    self.sm:transition_to(%s.%s)"):format(st, default_st))
    table.insert(lines,  "  end")
  end

  table.insert(lines,  "end")
  return table.concat(lines, "\n")
end

-- =============================================================================
-- ★ Phase 3.6.1 → 3.6.2: nebula_gen_text_buffer(spec) -> string
--
-- 为声明了 "editable" 原语的 Visual 生成 Gap Buffer 驱动的文本输入方法。
--
-- Phase 3.6.2 改进（相较于 3.6.1）：
--   · 删除 get_text() 对 visual.flat_buf 的依赖（修复 L1/L2 渗透，公理 B）
--   · get_text(out, max) 改为接受调用方提供的栈上缓冲区，零持久占用
--   · 新增 mouse_to_cursor(local_x, pixel_height) 方法：
--       在栈上即时计算 advances，调用 nebula_text_hit_test，返回目标光标位置
--   · 新增 sync_cursor_to(target_pos) 方法：
--       将 Gap Buffer 光标从当前位置移动到目标位置（O(N)，N 通常极小）
--   · process_text_input 在 just_clicked 时自动调用 mouse_to_cursor + sync_cursor_to
--
-- spec:
--   base         : string  — 派生基名（如 "Input"）
--   max_text_len : number  — 编译期最大容量（默认 255）
--   text_origin_x_field : string — visual 中文本起始 X 坐标字段名（默认 "pos.x"，
--                                  可覆盖为 "text_origin_x" 等）
--   pixel_height_field  : string — visual 中像素高度字段名（默认 "pixel_height"）
-- =============================================================================
function nebula_gen_text_buffer(spec)
  assert(spec.base, "nebula_gen_text_buffer: spec.base required")
  local ctx      = spec.base .. "Context"
  local cap_val  = spec.max_text_len or 255
  local lines    = {}

  -- -------------------------------------------------------------------------
  -- process_text_input：消费键盘事件，委托给 Gap Buffer 方法
  -- Phase 3.6.2: 在 just_clicked 时额外执行鼠标命中测试并同步光标
  -- -------------------------------------------------------------------------
  table.insert(lines, ("-- [editable/gap_buffer] %s: process_text_input (Phase 3.6.2)"):format(ctx))
  table.insert(lines, ("function %s:process_text_input(input: *NebulaInputState): boolean"):format(ctx))
  table.insert(lines,  "  if input.focused_id ~= self.component_id then return false end")
  table.insert(lines,  "  local changed = false")

  -- ★ Phase 3.6.2: just_clicked → 鼠标命中测试，同步光标位置
  -- 在栈上分配临时 advances 数组，用完即丢，不写入任何持久字段（公理 B）
  table.insert(lines,  "  -- ★ Phase 3.6.2: mouse click → hit-test → cursor sync")
  table.insert(lines,  "  if self.click.just_clicked then")
  table.insert(lines, ("    local target = self:mouse_to_cursor(input.mouse_x, self.visual.pixel_height)"))
  table.insert(lines,  "    self:sync_cursor_to(target)")
  table.insert(lines,  "    changed = true")
  table.insert(lines,  "  end")

  -- 字符输入：O(1) 插入
  table.insert(lines,  "  local i: uint8 = 0")
  table.insert(lines,  "  while i < input.char_count do")
  table.insert(lines,  "    local cp = input.char_input[i]")
  table.insert(lines,  "    if cp >= 0x20 and cp <= 0x7E then")
  table.insert(lines,  "      if self.visual.gap_buf:insert_char((@uint8)(cp)) then")
  table.insert(lines,  "        changed = true")
  table.insert(lines,  "      end")
  table.insert(lines,  "    end")
  table.insert(lines,  "    i = i + 1")
  table.insert(lines,  "  end")

  -- 控制键处理：全部 O(1) 或 O(N) 操作
  table.insert(lines,  "  local k = input.key_pressed")
  table.insert(lines,  "  if k == NebulaKey.Backspace then")
  table.insert(lines,  "    if self.visual.gap_buf:delete_before() then changed = true end")
  table.insert(lines,  "  elseif k == NebulaKey.Delete then")
  table.insert(lines,  "    if self.visual.gap_buf:delete_after() then changed = true end")
  table.insert(lines,  "  elseif k == NebulaKey.Left then")
  table.insert(lines,  "    self.visual.gap_buf:move_cursor_left()")
  table.insert(lines,  "  elseif k == NebulaKey.Right then")
  table.insert(lines,  "    self.visual.gap_buf:move_cursor_right()")
  table.insert(lines,  "  elseif k == NebulaKey.Home then")
  table.insert(lines,  "    self.visual.gap_buf:move_cursor_home()")
  table.insert(lines,  "  elseif k == NebulaKey.End then")
  table.insert(lines,  "    self.visual.gap_buf:move_cursor_end()")
  table.insert(lines,  "  end")
  table.insert(lines,  "  return changed")
  table.insert(lines,  "end")

  -- -------------------------------------------------------------------------
  -- get_text_len：直接从 Gap Buffer 读取文本长度（无变化）
  -- -------------------------------------------------------------------------
  table.insert(lines, ("-- [editable/gap_buffer] %s: get_text_len"):format(ctx))
  table.insert(lines, ("function %s:get_text_len(): uint16"):format(ctx))
  table.insert(lines,  "  return self.visual.gap_buf:len()")
  table.insert(lines,  "end")

  -- -------------------------------------------------------------------------
  -- ★ Phase 3.6.2: get_text(out, max) — 修复 L1/L2 渗透
  --
  -- 旧版（3.6.1）将展平结果写入 visual.flat_buf（持久 L1 字段），违反公理 B。
  -- 新版接受调用方提供的栈上缓冲区 out，展平后立即使用，帧结束自动回收。
  --
  -- 调用方示例：
  --   local flat: [256]uint8
  --   local text = ctx:get_text(&flat[0], 255)
  -- -------------------------------------------------------------------------
  table.insert(lines, ("-- [editable/gap_buffer] %s: get_text (Phase 3.6.2: 栈上缓冲区，修复 L1/L2 渗透)"):format(ctx))
  table.insert(lines, ("function %s:get_text(out: *[0]uint8, max_out: uint16): cstring"):format(ctx))
  table.insert(lines,  "  self.visual.gap_buf:flatten(out, max_out)")
  table.insert(lines,  "  return (@cstring)(out)")
  table.insert(lines,  "end")

  -- -------------------------------------------------------------------------
  -- ★ Phase 3.6.2: mouse_to_cursor(mouse_x, pixel_height) -> uint32
  --
  -- 鼠标命中测试：将鼠标屏幕 X 坐标映射到 Gap Buffer 光标位置。
  --
  -- 实现：
  --   1. 在栈上分配 [cap+1]float32 临时 advances 数组（零堆分配，公理 A+B）
  --   2. 将 Gap Buffer 展平到栈上临时 [cap+1]uint8 缓冲区（不写入持久字段）
  --   3. 调用 nebula_text_compute_advances 填充 advances
  --   4. 调用 nebula_text_hit_test 返回目标光标索引
  --   5. 所有临时数据在函数返回时自动回收
  -- -------------------------------------------------------------------------
  table.insert(lines, ("-- [editable/gap_buffer] %s: mouse_to_cursor (Phase 3.6.2)"):format(ctx))
  table.insert(lines, ("function %s:mouse_to_cursor(mouse_x: float32, pixel_height: float32): uint32"):format(ctx))
  -- 栈上临时展平缓冲区（不写入 visual 任何字段）
  table.insert(lines, ("  local tmp_flat: [%d]uint8"):format(cap_val + 1))
  table.insert(lines,  "  local text_len = self.visual.gap_buf:flatten(&tmp_flat[0], self.visual.gap_buf.capacity)")
  -- 栈上临时 advances 数组（N+1 个元素，含末尾哨兵）
  table.insert(lines, ("  local tmp_adv: [%d]float32"):format(cap_val + 1))
  table.insert(lines,  "  local char_count = nebula_text_compute_advances(")
  table.insert(lines,  "    (@cstring)(&tmp_flat[0]),")
  table.insert(lines,  "    pixel_height,")
  table.insert(lines,  "    &tmp_adv[0],")
  table.insert(lines, ("    %d"):format(cap_val + 1))
  table.insert(lines,  "  )")
  -- 计算文本在输入框内的起始 X（相对于 visual.pos.x 加内边距）
  table.insert(lines,  "  local text_origin_x = self.visual.pos.x + 8.0  -- 8px 内边距（与渲染一致）")
  table.insert(lines,  "  local local_x = mouse_x - text_origin_x")
  table.insert(lines,  "  return nebula_text_hit_test(local_x, &tmp_adv[0], char_count)")
  table.insert(lines,  "end")

  -- -------------------------------------------------------------------------
  -- ★ Phase 3.6.2: sync_cursor_to(target_pos) -> void
  --
  -- 将 Gap Buffer 光标从当前位置（gap_start）移动到目标位置 target_pos。
  -- 通过逐步调用 move_cursor_left / move_cursor_right 实现，O(|delta|)。
  -- delta 通常极小（鼠标点击附近），实际性能接近 O(1)。
  -- -------------------------------------------------------------------------
  table.insert(lines, ("-- [editable/gap_buffer] %s: sync_cursor_to (Phase 3.6.2)"):format(ctx))
  table.insert(lines, ("function %s:sync_cursor_to(target_pos: uint32): void"):format(ctx))
  table.insert(lines,  "  -- 向左移动直到 gap_start == target_pos")
  table.insert(lines,  "  while self.visual.gap_buf.gap_start > (@uint16)(target_pos) do")
  table.insert(lines,  "    self.visual.gap_buf:move_cursor_left()")
  table.insert(lines,  "  end")
  table.insert(lines,  "  -- 向右移动直到 gap_start == target_pos")
  table.insert(lines,  "  while self.visual.gap_buf.gap_start < (@uint16)(target_pos) do")
  table.insert(lines,  "    self.visual.gap_buf:move_cursor_right()")
  table.insert(lines,  "  end")
  table.insert(lines,  "end")

  return table.concat(lines, "\n")
end

-- =============================================================================
-- ★ Phase 3.5.3: nebula_gen_toggle_state(spec) -> string
--
-- 为声明了 "toggleable" 原语的 Visual 生成正交开关状态字段和翻转方法。
--
-- 设计哲学：
--   · toggleable 是一个正交状态（Orthogonal State），与主状态机（hovered/pressed/focused）完全独立
--   · 不修改现有的主状态机逻辑，避免引入优先级冲突
--   · 在 process_input 中检测到 just_clicked 时翻转 is_on
--   · 生成的 toggle 字段包含： is_on: boolean / just_toggled: boolean
--
-- spec:
--   base : string  — 派生基名（如 "Checkbox"）
-- =============================================================================
function nebula_gen_toggle_state(spec)
  assert(spec.base, "nebula_gen_toggle_state: spec.base required")
  local ctx = spec.base .. "Context"
  local lines = {}

  -- 生成 ToggleState record（内联到 <T>Context 中）
  table.insert(lines, "-- [toggleable] ToggleState: 正交开关状态")
  table.insert(lines, "global NebulaToggleState = @record{")
  table.insert(lines, "  is_on:        boolean,")
  table.insert(lines, "  just_toggled: boolean,")
  table.insert(lines, "}")

  -- 生成 toggle 处理方法：在 process_input 之后调用
  table.insert(lines, ("-- [toggleable] %s: process_toggle"):format(ctx))
  table.insert(lines, ("function %s:process_toggle(input: *NebulaInputState): void"):format(ctx))
  table.insert(lines,  "  local prev_on = self.toggle.is_on")
  table.insert(lines,  "  -- 当 just_clicked 时翻转开关状态")
  table.insert(lines,  "  if self.click.just_clicked then")
  table.insert(lines,  "    self.toggle.is_on = not self.toggle.is_on")
  table.insert(lines,  "  end")
  table.insert(lines,  "  self.toggle.just_toggled = (self.toggle.is_on ~= prev_on)")
  table.insert(lines,  "end")

  return table.concat(lines, "\n")
end

-- =============================================================================
-- ★ Phase 3.5.3: 扩展 nebula_gen_process_input 支持 toggleable 原语
--
-- 对现有函数的增量扩展：
--   · 检测到 "toggleable" 时，在 process_input 末尾自动调用 process_toggle
--   · 不修改主状态机逻辑，实现真正的正交状态
-- =============================================================================
local _orig_gen_process_input = nebula_gen_process_input
function nebula_gen_process_input(spec)
  local source = _orig_gen_process_input(spec)
  if not has(spec.primitives or {}, "toggleable") then
    return source
  end
  -- 在 process_input 的最后一行（end）之前插入 process_toggle 调用
  -- 利用字符串替换：将最后的 "\nend" 替换为 toggle 调用 + end
  local last_end_pos = source:match(".*()\nend$")
  if last_end_pos then
    source = source:sub(1, last_end_pos - 1) .. "\n  self:process_toggle(input)\nend"
  end
  return source
end

-- 返回模块标识
return "nebula_interaction_factory_v0.5_phase3.6.2"
