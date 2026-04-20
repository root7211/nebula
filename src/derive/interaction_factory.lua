-- =============================================================================
-- derive/interaction_factory.lua
-- Nebula GUI Compiler — Phase 2.4
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

-- 返回模块标识
return "nebula_interaction_factory_v0.1"
