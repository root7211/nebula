-- =============================================================================
-- derive/interaction_factory.lua
-- Nebula GUI Compiler — Phase 3.10
--
-- 交互原语代码生成器（Interaction Factory）
--
-- ★ Phase 3.10 重构：引入 NEBULA_PRIMITIVES 统一注册表
--
-- 根据 Visual 规格中声明的 primitives 列表，在编译期生成以下 Nelua 源码：
--   · <T>Context:hit_test(x, y)      — 内联 AABB 碰撞检测（无函数调用层）
--   · <T>Context:process_input(input) — 按 primitives 自动生成状态机触发逻辑
--
-- 支持的原语（通过 NEBULA_PRIMITIVES 注册表声明）：
--   · "hoverable"  — 生成 hovered 状态检测与 transition_to(Hovered/Default)
--   · "clickable"  — 在 hoverable 基础上叠加 pressed 状态与 just_clicked 检测
--   · "focusable"  — 生成基于 self.component_id / input.focused_id 的焦点管理
--   · "toggleable" — 正交开关状态，在 process_input 后调用 process_toggle
--   · "editable"   — Gap Buffer 驱动的文本输入，含选区、光标同步等方法
--
-- 公开 API：
--   NEBULA_PRIMITIVES                 -> table   (统一注册表)
--   nebula_resolve_primitives(prims)  -> table   (解析依赖后的有序原语列表)
--   nebula_gen_hit_test(spec)         -> string  (Nelua 源码)
--   nebula_gen_process_input(spec)    -> string  (Nelua 源码)
--   nebula_gen_text_buffer(spec)      -> string  (Nelua 源码)
--   nebula_gen_toggle_state(spec)     -> string  (Nelua 源码)
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
-- ★ Phase 3.10: NEBULA_PRIMITIVES 统一注册表
--
-- 每个原语的元数据结构：
--   name              : string    — 原语名称
--   dependencies      : string[]  — 隐式依赖的其他原语
--   global_type_meta  : table?    — 需要注入的全局类型 { type_name, source }
--                                   或 { factory = function(reg) -> type_name, source }
--   context_fields    : table[]   — 注入到 <T>Context record 的字段列表
--                                   每项 { name, type } 或 { factory = function(reg) -> fields[] }
--   context_init      : table[]   — Context:init() 中的初始化代码
--                                   每项 { type="record_init", field, record_name }
--   post_process      : table?    — process_input 末尾的后处理
--                                   { method_call = "self:process_toggle(input)" }
--   pre_derive_hook   : function? — 在 nebula_derive 中、Context 生成前执行的钩子
--                                   function(reg, type_name, inject_statement, aster)
--   extra_source_hook : function? — 在 source_parts 拼装中、process_input 之后执行的钩子
--                                   function(spec) -> string (额外 Nelua 源码)
-- =============================================================================
NEBULA_PRIMITIVES = {}

-- ---- 1. hoverable ----
NEBULA_PRIMITIVES["hoverable"] = {
  name         = "hoverable",
  dependencies = {},
  global_type_meta = nil,  -- HoverableState 已在 nebula_core.nelua 中全局定义
  context_fields = {
    { name = "hover", type = "HoverableState" },
  },
  context_init = {
    { type = "record_init", field = "hover", record_name = "HoverableState" },
  },
  -- ★ Phase 4.4: process_body — 更新 hover 状态字段
  process_body = function(spec, lines)
    table.insert(lines, "  local prev_hovered = self.hover.is_hovered")
    table.insert(lines, "  self.hover.is_hovered  = hovered")
    table.insert(lines, "  self.hover.just_entered = (hovered and not prev_hovered)")
    table.insert(lines, "  self.hover.just_left    = (not hovered and prev_hovered)")
  end,
  -- ★ Phase 4.4: state_transitions — 状态机转换声明
  state_transitions = {
    { guard = "hovered", target = "Hovered", priority = 10 },
  },
  post_process      = nil,
  pre_derive_hook   = nil,
  extra_source_hook = nil,
}

-- ---- 2. clickable ----
NEBULA_PRIMITIVES["clickable"] = {
  name         = "clickable",
  dependencies = { "hoverable" },  -- clickable 隐式依赖 hoverable
  global_type_meta = nil,  -- ClickableState 已在 nebula_core.nelua 中全局定义
  context_fields = {
    { name = "click", type = "ClickableState" },
  },
  context_init = {
    { type = "record_init", field = "click", record_name = "ClickableState" },
  },
  -- ★ Phase 4.4: process_body — 更新 click 状态字段
  process_body = function(spec, lines)
    table.insert(lines, "  local prev_pressed = self.click.is_pressed")
    table.insert(lines, "  self.click.is_pressed   = (hovered and input.mouse_left_down)")
    table.insert(lines, "  self.click.just_clicked = (prev_pressed and not self.click.is_pressed and hovered)")
  end,
  -- ★ Phase 4.4: state_transitions — 状态机转换声明
  state_transitions = {
    { guard = "self.click.is_pressed", target = "Pressed", priority = 30 },
  },
  post_process      = nil,
  pre_derive_hook   = nil,
  extra_source_hook = nil,
}

-- ---- 3. focusable ----
NEBULA_PRIMITIVES["focusable"] = {
  name         = "focusable",
  dependencies = { "clickable" },  -- focusable 需要 click.just_clicked
  global_type_meta = nil,
  context_fields = {
    { name = "component_id", type = "uint32" },
  },
  context_init = {},  -- component_id 默认零初始化即可
  -- ★ Phase 4.4: process_body — 焦点管理逻辑（依赖 clickable.just_clicked）
  process_body = function(spec, lines)
    table.insert(lines, "  -- focusable: uses runtime self.component_id")
    table.insert(lines, "  if self.click.just_clicked then")
    table.insert(lines, "    input.focused_id = self.component_id")
    table.insert(lines, "  elseif input.mouse_left_pressed and not hovered then")
    table.insert(lines, "    if input.focused_id == self.component_id then")
    table.insert(lines, "      input.focused_id = 0")
    table.insert(lines, "    end")
    table.insert(lines, "  end")
  end,
  -- ★ Phase 4.4: state_transitions — 状态机转换声明
  state_transitions = {
    { guard = "input.focused_id == self.component_id", target = "Focused", priority = 20 },
  },
  post_process      = nil,
  pre_derive_hook   = nil,
  extra_source_hook = nil,
}

-- ---- 4. toggleable ----
NEBULA_PRIMITIVES["toggleable"] = {
  name         = "toggleable",
  dependencies = { "clickable" },  -- toggleable 需要 click.just_clicked
  global_type_meta = {
    type_name = "NebulaToggleState",
    source    = "global NebulaToggleState = @record{\n  is_on: boolean,\n  just_toggled: boolean,\n}",
  },
  context_fields = {
    { name = "toggle", type = "NebulaToggleState" },
  },
  context_init = {},  -- toggle 默认零初始化即可（is_on=false, just_toggled=false）
  post_process = {
    method_call = "self:process_toggle(input)",
  },
  pre_derive_hook = function(reg, type_name, inject_statement, aster)
    -- 注入 NebulaToggleState 全局类型（防止重复注入）
    if not _nebula_toggle_state_injected then
      _nebula_toggle_state_injected = true
      local meta = NEBULA_PRIMITIVES["toggleable"].global_type_meta
      local ast = aster.parse(meta.source, "<nebula_derive:toggle_state:" .. type_name .. ">")
      for _, stat in ipairs(ast) do inject_statement(stat) end
    end
  end,
  extra_source_hook = function(spec)
    -- 生成 process_toggle 方法（必须在 process_input 之前声明）
    return nebula_gen_toggle_state(spec)
  end,
}

-- ---- 5. editable ----
NEBULA_PRIMITIVES["editable"] = {
  name         = "editable",
  dependencies = { "focusable" },  -- editable 需要 focusable（component_id + click）
  global_type_meta = {
    -- 动态类型：NebulaBuf{N}，通过工厂函数按需生成
    factory = function(reg, type_name, inject_statement, aster)
      local max_len = reg.max_text_len or 255
      local buf_type_name, buf_type_src = nebula_gen_gap_buffer_type(max_len)
      local buf_ast = aster.parse(buf_type_src, "<nebula_derive:gap_buffer:" .. type_name .. ">")
      for _, stat in ipairs(buf_ast) do
        inject_statement(stat)
      end
      print(("[derive] %s: injected %s (capacity=%d) for editable primitive"):format(type_name, buf_type_name, max_len))
      -- ★ Phase 4.7-S5: 注入 undo stack 类型
      local undo_entries = reg.undo_max_entries or 128
      local undo_data    = reg.undo_max_data    or 4096
      local undo_type, undo_src = nebula_gen_undo_stack_type(undo_entries, undo_data)
      if undo_src and #undo_src > 0 then
        local undo_ast = aster.parse(undo_src, "<nebula_derive:undo_stack:" .. type_name .. ">")
        for _, stat in ipairs(undo_ast) do
          inject_statement(stat)
        end
      end
      -- Store the undo type name for context field injection
      reg._undo_stack_type = undo_type
      print(("[derive] %s: injected %s (entries=%d, data=%d) for undo/redo"):format(
        type_name, undo_type, undo_entries, undo_data))
    end,
  },
  context_fields = {
    { name = "selection_anchor", type = "uint32" },
    { name = "is_dragging",      type = "boolean" },
  },
  -- ★ Phase 4.7-S5: dynamic context fields (undo_stack type depends on compile-time params)
  dynamic_context_fields = function(reg)
    local undo_entries = reg.undo_max_entries or 128
    local undo_data    = reg.undo_max_data    or 4096
    local undo_type = ("NebulaUndoStack%d_%d"):format(undo_entries, undo_data)
    return {
      { name = "undo_stack", type = undo_type },
    }
  end,
  context_init = {},  -- 默认零初始化
  post_process      = nil,
  pre_derive_hook = function(reg, type_name, inject_statement, aster)
    -- 注入 NebulaBuf{N} 动态类型
    local meta = NEBULA_PRIMITIVES["editable"].global_type_meta
    if meta.factory then
      meta.factory(reg, type_name, inject_statement, aster)
    end
  end,
  extra_source_hook = function(spec)
    -- 生成 text buffer 相关方法（mouse_to_cursor, sync_cursor_to, process_text_input 等）
    return nebula_gen_text_buffer({
      base         = spec.base,
      max_text_len = spec.max_text_len or 255,
    })
  end,
}

-- ---- 6. scrollable ----
-- ★ Phase 4.4 S1: 可滚动容器原语
-- 管理滚动偏移 + 滚动条拖拽状态，依赖 hoverable（需要 hovered 决定是否响应滚轮）
NEBULA_PRIMITIVES["scrollable"] = {
  name         = "scrollable",
  dependencies = { "hoverable" },
  global_type_meta = nil,
  context_fields = {
    { name = "scroll_offset_y",   type = "float32" },
    { name = "max_scroll",        type = "float32" },
    { name = "is_dragging_bar",   type = "boolean" },
    { name = "drag_start_y",      type = "float32" },
    { name = "drag_start_offset", type = "float32" },
  },
  context_init = {},
  process_body = function(spec, lines)
    -- 更新 max_scroll（内容高度可能每帧变化）
    table.insert(lines, "  self.max_scroll = self.visual.content_height - self.visual.size.y")
    table.insert(lines, "  if self.max_scroll < 0.0 then self.max_scroll = 0.0 end")
    -- 滚轮滚动（仅在 hovered 状态下响应）
    table.insert(lines, "  if self.hover.is_hovered then")
    table.insert(lines, "    local scroll_speed = 30.0")
    table.insert(lines, "    self.scroll_offset_y = self.scroll_offset_y - input.scroll_dy * scroll_speed")
    table.insert(lines, "  end")
    -- 滚动条拖拽逻辑
    table.insert(lines, "  if self.click.just_clicked then")
    table.insert(lines, "    local bar_x = self.visual.pos.x + self.visual.size.x - 10.0")
    table.insert(lines, "    if input.mouse_x >= bar_x then")
    table.insert(lines, "      self.is_dragging_bar = true")
    table.insert(lines, "      self.drag_start_y = input.mouse_y")
    table.insert(lines, "      self.drag_start_offset = self.scroll_offset_y")
    table.insert(lines, "    end")
    table.insert(lines, "  end")
    table.insert(lines, "  if not input.mouse_left_down then")
    table.insert(lines, "    self.is_dragging_bar = false")
    table.insert(lines, "  end")
    table.insert(lines, "  if self.is_dragging_bar then")
    table.insert(lines, "    local dy = input.mouse_y - self.drag_start_y")
    table.insert(lines, "    local scroll_ratio = self.visual.size.y / self.visual.content_height")
    table.insert(lines, "    if scroll_ratio > 1.0 then scroll_ratio = 1.0 end")
    table.insert(lines, "    self.scroll_offset_y = self.drag_start_offset + dy / scroll_ratio")
    table.insert(lines, "  end")
    table.insert(lines, "  if self.scroll_offset_y < 0.0 then self.scroll_offset_y = 0.0 end")
    table.insert(lines, "  if self.scroll_offset_y > self.max_scroll then self.scroll_offset_y = self.max_scroll end")
  end,
  state_transitions = {
    { guard = "self.is_dragging_bar", target = "Draggingbar", priority = 40 },
  },
  post_process      = nil,
  pre_derive_hook   = nil,
  extra_source_hook = nil,
}

-- ---- 7. dropdown_manager ----
-- ★ Phase 4.4 S2: 下拉选择器原语
-- 管理展开/收起状态 + 选中索引 + 点击外部关闭
NEBULA_PRIMITIVES["dropdown_manager"] = {
  name         = "dropdown_manager",
  dependencies = { "hoverable", "clickable" },
  global_type_meta = nil,
  context_fields = {
    { name = "is_open",        type = "boolean" },
    { name = "selected_index", type = "uint32" },
    { name = "item_count",     type = "uint32" },
  },
  context_init = {},
  process_body = function(spec, lines)
    -- Toggle open/close on click
    table.insert(lines, "  if self.click.just_clicked then")
    table.insert(lines, "    self.is_open = not self.is_open")
    table.insert(lines, "  end")
    -- Close on click outside (when open and mouse pressed but not on self)
    table.insert(lines, "  if self.is_open and input.mouse_left_pressed and not hovered then")
    table.insert(lines, "    self.is_open = false")
    table.insert(lines, "  end")
  end,
  state_transitions = {},
  post_process      = nil,
  pre_derive_hook   = nil,
  extra_source_hook = nil,
}

-- ---- 8. multiline_editable ----
-- ★ Phase 4.4 S3: 多行文本编辑原语
-- 依赖 editable（文本编辑核心）+ scrollable（滚动容器）
-- 添加 cursor_row/cursor_col/line_count 用于行级导航
-- 通过 global_type_meta.factory 注入 NebulaMultiBuf{N}_{L} 编译期泛型类型
NEBULA_PRIMITIVES["multiline_editable"] = {
  name         = "multiline_editable",
  dependencies = { "editable", "scrollable" },
  global_type_meta = {
    factory = function(reg, type_name, inject_statement, aster)
      local max_lines = reg.max_lines or 32
      local line_capacity = reg.max_text_len or 128
      local mb_type, mb_src = nebula_gen_multiline_buffer_type(line_capacity, max_lines)
      local mb_ast = aster.parse(mb_src, "<nebula_derive:multiline_buffer:" .. type_name .. ">")
      for _, stat in ipairs(mb_ast) do
        inject_statement(stat)
      end
      print(("[derive] %s: injected %s (lines=%d, capacity=%d) for multiline_editable primitive"):format(
        type_name, mb_type, max_lines, line_capacity))
    end,
  },
  context_fields = {
    { name = "cursor_row", type = "uint32" },
    { name = "cursor_col", type = "uint32" },
    { name = "line_count", type = "uint32" },
  },
  context_init = {},
  process_body = function(spec, lines)
    -- Up arrow: move cursor to previous line
    table.insert(lines, "  if input.key_pressed == NebulaKey.Up then")
    table.insert(lines, "    if self.cursor_row > 0 then")
    table.insert(lines, "      self.cursor_row = self.cursor_row - 1")
    table.insert(lines, "    end")
    table.insert(lines, "  end")
    -- Down arrow: move cursor to next line
    table.insert(lines, "  if input.key_pressed == NebulaKey.Down then")
    table.insert(lines, "    if self.cursor_row + 1 < self.line_count then")
    table.insert(lines, "      self.cursor_row = self.cursor_row + 1")
    table.insert(lines, "    end")
    table.insert(lines, "  end")
    -- Enter: increment line_count (newline)
    table.insert(lines, "  if input.key_pressed == NebulaKey.Enter then")
    table.insert(lines, "    if self.line_count < 32 then")
    table.insert(lines, "      self.line_count = self.line_count + 1")
    table.insert(lines, "      self.cursor_row = self.cursor_row + 1")
    table.insert(lines, "      self.cursor_col = 0")
    table.insert(lines, "    end")
    table.insert(lines, "  end")
    -- ShiftUp/ShiftDown: extend selection while moving lines
    table.insert(lines, "  if input.key_pressed == NebulaKey.ShiftUp then")
    table.insert(lines, "    if self.cursor_row > 0 then")
    table.insert(lines, "      self.cursor_row = self.cursor_row - 1")
    table.insert(lines, "    end")
    table.insert(lines, "  end")
    table.insert(lines, "  if input.key_pressed == NebulaKey.ShiftDown then")
    table.insert(lines, "    if self.cursor_row + 1 < self.line_count then")
    table.insert(lines, "      self.cursor_row = self.cursor_row + 1")
    table.insert(lines, "    end")
    table.insert(lines, "  end")
  end,
  state_transitions = {},
  post_process      = nil,
  pre_derive_hook = function(reg, type_name, inject_statement, aster)
    -- 注入 NebulaMultiBuf{N}_{L} 动态类型
    local meta = NEBULA_PRIMITIVES["multiline_editable"].global_type_meta
    if meta.factory then
      meta.factory(reg, type_name, inject_statement, aster)
    end
  end,
  extra_source_hook = nil,
}

-- =============================================================================
-- ★ Phase 4.4: nebula_register_primitive(name, spec)
--
-- 向界面开发者暴露的公开 API，用于在 S1 编译期注册自定义交互原语。
-- 注册后，原语在 nebula_annotate 中自动可用（与内置原语等价）。
--
-- 参数 spec 结构：
--   dependencies      : string[]? — 依赖的其他原语
--   context_fields    : table[]?  — 注入到 <T>Context 的字段 [{name, type}]
--   context_init      : table[]?  — Context:init() 初始化项
--   process_body      : function? — function(spec, lines) — 状态更新代码注入
--   state_transitions : table[]?  — [{guard, target, priority}]
--   post_process      : table?    — {method_call = "..."}
--   pre_derive_hook   : function? — Context 生成前的钩子
--   extra_source_hook : function? — 生成额外 Nelua 源码的钩子
-- =============================================================================
function nebula_register_primitive(name, spec)
  assert(type(name) == "string" and #name > 0,
    "nebula_register_primitive: name must be a non-empty string")
  assert(type(spec) == "table",
    "nebula_register_primitive: spec must be a table")
  assert(not NEBULA_PRIMITIVES[name],
    ("nebula_register_primitive: primitive '%s' is already registered (built-in or custom)"):format(name))

  -- ★ Phase 4.3 S2: 基础参数校验
  -- 依赖存在性检查：所有依赖必须已注册
  for _, dep in ipairs(spec.dependencies or {}) do
    assert(NEBULA_PRIMITIVES[dep],
      ("nebula_register_primitive: dependency '%s' for primitive '%s' is not registered"):format(dep, name))
  end

  -- context_fields 格式校验：每项必须是 {name=string, type=string}
  for i, f in ipairs(spec.context_fields or {}) do
    assert(type(f) == "table",
      ("nebula_register_primitive: context_fields[%d] for '%s' must be a table"):format(i, name))
    assert(type(f.name) == "string" and #f.name > 0,
      ("nebula_register_primitive: context_fields[%d].name for '%s' must be a non-empty string"):format(i, name))
    assert(type(f.type) == "string" and #f.type > 0,
      ("nebula_register_primitive: context_fields[%d].type for '%s' must be a non-empty string"):format(i, name))
  end

  -- state_transitions 格式校验
  for i, tr in ipairs(spec.state_transitions or {}) do
    assert(type(tr) == "table",
      ("nebula_register_primitive: state_transitions[%d] for '%s' must be a table"):format(i, name))
    assert(type(tr.guard) == "string" and #tr.guard > 0,
      ("nebula_register_primitive: state_transitions[%d].guard for '%s' must be a non-empty string"):format(i, name))
    assert(type(tr.target) == "string" and #tr.target > 0,
      ("nebula_register_primitive: state_transitions[%d].target for '%s' must be a non-empty string"):format(i, name))
  end

  -- process_body 格式校验
  if spec.process_body ~= nil then
    assert(type(spec.process_body) == "function",
      ("nebula_register_primitive: process_body for '%s' must be a function"):format(name))
  end

  -- ★ Phase 4.3 S3: static_asserts 格式校验
  -- 每项必须是 {field=string, type_pattern=string, reason=string}
  for i, sa in ipairs(spec.static_asserts or {}) do
    assert(type(sa) == "table",
      ("nebula_register_primitive: static_asserts[%d] for '%s' must be a table"):format(i, name))
    assert(type(sa.field) == "string" and #sa.field > 0,
      ("nebula_register_primitive: static_asserts[%d].field for '%s' must be a non-empty string"):format(i, name))
    assert(type(sa.type_pattern) == "string" and #sa.type_pattern > 0,
      ("nebula_register_primitive: static_asserts[%d].type_pattern for '%s' must be a non-empty string"):format(i, name))
    assert(type(sa.reason) == "string" and #sa.reason > 0,
      ("nebula_register_primitive: static_asserts[%d].reason for '%s' must be a non-empty string"):format(i, name))
  end

  NEBULA_PRIMITIVES[name] = {
    name              = name,
    dependencies      = spec.dependencies or {},
    global_type_meta  = spec.global_type_meta,
    context_fields    = spec.context_fields or {},
    context_init      = spec.context_init or {},
    static_asserts    = spec.static_asserts or {},  -- ★ Phase 4.3 S3
    process_body      = spec.process_body,
    state_transitions = spec.state_transitions,
    post_process      = spec.post_process,
    pre_derive_hook   = spec.pre_derive_hook,
    extra_source_hook = spec.extra_source_hook,
  }

  print(("[derive] registered custom primitive: %s (deps=[%s])"):format(
    name, table.concat(spec.dependencies or {}, ", ")))
end

-- =============================================================================
-- ★ Phase 3.10: nebula_resolve_primitives(prims) -> ordered_list
--
-- 解析原语列表，自动注入依赖，返回去重且拓扑排序后的有序原语名列表。
-- 保证依赖项在被依赖项之前出现。
-- =============================================================================
function nebula_resolve_primitives(prims)
  local resolved = {}
  local seen = {}

  local function resolve(name)
    if seen[name] then return end
    local meta = NEBULA_PRIMITIVES[name]
    if not meta then return end  -- 未知原语，跳过
    -- 先解析依赖
    for _, dep in ipairs(meta.dependencies or {}) do
      resolve(dep)
    end
    if not seen[name] then
      seen[name] = true
      table.insert(resolved, name)
    end
  end

  for _, p in ipairs(prims or {}) do
    resolve(p)
  end
  return resolved
end

-- =============================================================================
-- ★ Phase 3.10: nebula_get_context_fields(prims) -> fields[]
--
-- 根据已解析的原语列表，收集所有需要注入到 Context record 的字段。
-- 返回 { {name, type}, ... } 的有序列表（已去重）。
-- =============================================================================
function nebula_get_context_fields(prims)
  local fields = {}
  local seen = {}
  local source_map = {}  -- ★ Phase 4.3 S3: 记录每个字段的来源原语（用于冲突报告）
  local resolved = nebula_resolve_primitives(prims)
  for _, prim_name in ipairs(resolved) do
    local meta = NEBULA_PRIMITIVES[prim_name]
    if meta then
      for _, f in ipairs(meta.context_fields or {}) do
        if not seen[f.name] then
          seen[f.name] = f.type
          source_map[f.name] = prim_name
          table.insert(fields, f)
        else
          -- ★ Phase 4.3 S3: 字段冲突检测 — 同名但不同类型
          if seen[f.name] ~= f.type then
            error(("[Axiom-S3 冲突] 原语 '%s' 注入的字段 '%s' (类型 '%s') 与原语 '%s' 已注入的同名字段 (类型 '%s') 类型不一致。\n"):format(
              prim_name, f.name, f.type, source_map[f.name], seen[f.name])
              .. "修复建议：将其中一个原语的字段重命名，或统一类型。", 2)
          end
          -- 同名同类型：静默去重（依赖链中多处引用同一字段是合法的）
        end
      end
    end
  end
  return fields
end

-- =============================================================================
-- ★ Phase 4.3 S3: nebula_validate_static_asserts(prims) -> void
--
-- 编译期静态契约校验。
--
-- 收集所有已注册原语的 static_asserts 声明，然后检查 context fields 是否满足断言。
-- 每条断言声明：{field = "gap_buf", type_pattern = "NebulaBuf%d+", reason = "..."}
-- 含义：Context 中必须存在名为 `field` 的字段，且其类型匹配 `type_pattern`（Lua 模式）。
--
-- 典型用途：clipboard_aware 声明 "需要 editable 原语提供的 gap_buf 字段"，
-- 若组件未声明 editable 原语，则在此处报出清晰的编译期错误。
-- =============================================================================
function nebula_validate_static_asserts(prims)
  -- 收集所有已解析原语的 static_asserts
  local resolved = nebula_resolve_primitives(prims)
  local all_asserts = {}
  for _, prim_name in ipairs(resolved) do
    local meta = NEBULA_PRIMITIVES[prim_name]
    if meta and meta.static_asserts then
      for _, sa in ipairs(meta.static_asserts) do
        table.insert(all_asserts, {
          field        = sa.field,
          type_pattern = sa.type_pattern,
          reason       = sa.reason,
          source       = prim_name,
        })
      end
    end
  end

  if #all_asserts == 0 then return end

  -- 构建已注入字段的 name -> type 映射
  local fields = nebula_get_context_fields(prims)
  local field_map = {}
  for _, f in ipairs(fields) do
    field_map[f.name] = f.type
  end

  -- 逐条校验
  local violations = {}
  for _, sa in ipairs(all_asserts) do
    local actual_type = field_map[sa.field]
    if not actual_type then
      table.insert(violations, {
        field  = sa.field,
        expect = sa.type_pattern,
        actual = "(不存在)",
        reason = sa.reason,
        source = sa.source,
      })
    elseif not actual_type:match(sa.type_pattern) then
      table.insert(violations, {
        field  = sa.field,
        expect = sa.type_pattern,
        actual = actual_type,
        reason = sa.reason,
        source = sa.source,
      })
    end
  end

  if #violations > 0 then
    local lines = {
      "[Axiom-S3 违规] 编译期静态契约校验失败：",
    }
    for _, v in ipairs(violations) do
      table.insert(lines, ("  · 原语 '%s' 要求字段 '%s' 匹配模式 '%s'，实际类型 '%s' — %s"):format(
        v.source, v.field, v.expect, v.actual, v.reason))
    end
    table.insert(lines, "")
    table.insert(lines, "修复建议：")
    table.insert(lines, "  · 确保组件的 primitives 列表中包含了声明该字段的原语")
    table.insert(lines, "  · 或检查原语的依赖链是否正确")
    error(table.concat(lines, "\n"), 2)
  end
end

-- =============================================================================
-- ★ Phase 3.10: nebula_get_context_init(prims) -> init_items[]
--
-- 根据已解析的原语列表，收集所有 Context:init() 中的初始化项。
-- =============================================================================
function nebula_get_context_init(prims)
  local inits = {}
  local resolved = nebula_resolve_primitives(prims)
  for _, prim_name in ipairs(resolved) do
    local meta = NEBULA_PRIMITIVES[prim_name]
    if meta then
      for _, init in ipairs(meta.context_init or {}) do
        table.insert(inits, init)
      end
    end
  end
  return inits
end

-- =============================================================================
-- ★ Phase 3.10: nebula_get_post_process(prims) -> post_items[]
--
-- 根据已解析的原语列表，收集所有 process_input 末尾的后处理调用。
-- =============================================================================
function nebula_get_post_process(prims)
  local posts = {}
  local resolved = nebula_resolve_primitives(prims)
  for _, prim_name in ipairs(resolved) do
    local meta = NEBULA_PRIMITIVES[prim_name]
    if meta and meta.post_process then
      table.insert(posts, meta.post_process)
    end
  end
  return posts
end

-- =============================================================================
-- ★ Phase 3.10: nebula_run_pre_derive_hooks(reg, type_name, prims, inject_statement, aster)
--
-- 在 nebula_derive 中、Context 生成前，执行所有原语的 pre_derive_hook。
-- =============================================================================
function nebula_run_pre_derive_hooks(reg, type_name, prims, inject_statement, aster)
  local resolved = nebula_resolve_primitives(prims)
  for _, prim_name in ipairs(resolved) do
    local meta = NEBULA_PRIMITIVES[prim_name]
    if meta and meta.pre_derive_hook then
      meta.pre_derive_hook(reg, type_name, inject_statement, aster)
    end
  end
end

-- =============================================================================
-- ★ Phase 3.10: nebula_get_extra_sources(spec, prims) -> string
--
-- 在 source_parts 拼装中，收集所有原语的额外源码（如 toggleable 的 process_toggle、
-- editable 的 text_buffer 方法）。
-- =============================================================================
function nebula_get_extra_sources(spec, prims)
  local parts = {}
  local resolved = nebula_resolve_primitives(prims)
  for _, prim_name in ipairs(resolved) do
    local meta = NEBULA_PRIMITIVES[prim_name]
    if meta and meta.extra_source_hook then
      local src = meta.extra_source_hook(spec)
      if src and #src > 0 then
        table.insert(parts, src)
      end
    end
  end
  return table.concat(parts, "\n\n")
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
-- ★ Phase 4.4 重构：完全元数据驱动的 process_input 生成器。
--
-- 所有原语通过 NEBULA_PRIMITIVES 注册表声明自己的贡献：
--   process_body(spec, lines)   — 状态更新代码注入
--   state_transitions            — 状态机转换声明 {guard, target, priority}
--   post_process                 — 后处理方法调用
--
-- nebula_gen_process_input 只负责：
--   1. 公共基础设施（AABB hit_test 调用）
--   2. 收集各原语的 process_body → 生成状态更新代码
--   3. 收集各原语的 state_transitions → 按 priority 排序 → 生成 if-elseif 链
--   4. 收集 post_process → 生成后处理调用
--
-- 无任何 is_hoverable/is_clickable/is_focusable 硬编码分支。
-- 新增原语只需在 NEBULA_PRIMITIVES 中声明 process_body + state_transitions。
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

  -- ★ Phase 4.4: 检查是否有任何交互原语（有 process_body 或 state_transitions 的原语）
  -- 使用原始 prims 列表（非 resolved），保持与旧版本行为一致
  local resolved = nebula_resolve_primitives(prims)
  local has_interaction = false
  for _, prim_name in ipairs(resolved) do
    local meta = NEBULA_PRIMITIVES[prim_name]
    if meta and (meta.process_body or (meta.state_transitions and #meta.state_transitions > 0)) then
      has_interaction = true
      break
    end
  end

  -- 无任何基础交互原语：生成空体，保持接口统一
  if not has_interaction then
    local lines = {}
    table.insert(lines, ("-- [interaction] %s: process_input (no primitives, no-op)"):format(ctx))
    table.insert(lines, ("function %s:process_input(input: *NebulaInputState): void"):format(ctx))
    table.insert(lines, "  -- no interaction primitives declared")
    table.insert(lines, "end")
    return table.concat(lines, "\n")
  end

  local lines = {}
  table.insert(lines, ("-- [interaction] %s: process_input (primitives=[%s])"):format(
    ctx, table.concat(prims, ", ")))
  table.insert(lines, ("function %s:process_input(input: *NebulaInputState): void"):format(ctx))

  -- ---- 1. 公共基础设施：AABB 碰撞检测 ----
  table.insert(lines, "  local hovered = self:hit_test(input.mouse_x, input.mouse_y)")

  -- ---- 2. 元数据驱动的状态更新：收集各原语的 process_body ----
  for _, prim_name in ipairs(resolved) do
    local meta = NEBULA_PRIMITIVES[prim_name]
    if meta and meta.process_body then
      table.insert(lines, "")
      meta.process_body(spec, lines)
    end
  end

  -- ---- 3. 元数据驱动的状态机转换：收集各原语的 state_transitions，按 priority 排序 ----
  local transitions = {}
  for _, prim_name in ipairs(resolved) do
    local meta = NEBULA_PRIMITIVES[prim_name]
    if meta and meta.state_transitions then
      for _, tr in ipairs(meta.state_transitions) do
        -- 只在目标状态在 states 列表中存在时才生成
        if has_state(states, tr.target:lower()) then
          table.insert(transitions, {
            guard    = tr.guard,
            target   = tr.target,
            priority = tr.priority or 0,
          })
        end
      end
    end
  end

  -- 按 priority 降序排列（高优先级在前：pressed=30 > focused=20 > hovered=10）
  table.sort(transitions, function(a, b) return a.priority > b.priority end)

  -- 生成 if-elseif 链
  if #transitions > 0 then
    table.insert(lines, "")
    local default_st = cap(states[1])
    for i, tr in ipairs(transitions) do
      local keyword = (i == 1) and "if" or "elseif"
      table.insert(lines, ("  %s %s then"):format(keyword, tr.guard))
      table.insert(lines, ("    self.sm:transition_to(%s.%s)"):format(st, tr.target))
    end
    table.insert(lines, "  else")
    table.insert(lines, ("    self.sm:transition_to(%s.%s)"):format(st, default_st))
    table.insert(lines, "  end")
  end

  -- ---- 4. 元数据驱动的后处理注入 ----
  local post_items = nebula_get_post_process(prims)
  for _, post in ipairs(post_items) do
    if post.method_call then
      table.insert(lines, ("  %s"):format(post.method_call))
    end
  end

  table.insert(lines, "end")
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

-- ---------------------------------------------------------------------------
-- 子生成器 1: mouse_to_cursor + sync_cursor_to
-- Nelua 要求被调方法在调用方之前声明，因此这两个方法必须先于 process_text_input。
-- ---------------------------------------------------------------------------
local function _gen_cursor_helpers(lines, ctx, cap_val)
  -- mouse_to_cursor(mouse_x, pixel_height) -> uint32
  table.insert(lines, ("-- [editable/gap_buffer] %s: mouse_to_cursor (Phase 3.6.2)"):format(ctx))
  table.insert(lines, ("function %s:mouse_to_cursor(mouse_x: float32, pixel_height: float32): uint32"):format(ctx))
  table.insert(lines, ("  local tmp_flat: [%d]uint8"):format(cap_val + 1))
  table.insert(lines,  "  local text_len = self.visual.gap_buf:flatten(&tmp_flat[0], self.visual.gap_buf.capacity)")
  table.insert(lines, ("  local tmp_adv: [%d]float32"):format(cap_val + 1))
  table.insert(lines,  "  local char_count = nebula_text_compute_advances(")
  table.insert(lines,  "    (@cstring)(&tmp_flat[0]),")
  table.insert(lines,  "    pixel_height,")
  table.insert(lines,  "    &tmp_adv[0],")
  table.insert(lines, ("    %d"):format(cap_val + 1))
  table.insert(lines,  "  )")
  table.insert(lines,  "  local text_origin_x = self.visual.pos.x + 8.0  -- 8px 内边距")
  table.insert(lines,  "  local local_x = mouse_x - text_origin_x")
  table.insert(lines,  "  return nebula_text_hit_test(local_x, &tmp_adv[0], char_count)")
  table.insert(lines,  "end")
  -- sync_cursor_to(target_pos) -> void
  table.insert(lines, ("-- [editable/gap_buffer] %s: sync_cursor_to (Phase 3.6.2)"):format(ctx))
  table.insert(lines, ("function %s:sync_cursor_to(target_pos: uint32): void"):format(ctx))
  table.insert(lines,  "  while self.visual.gap_buf.gap_start > (@uint16)(target_pos) do")
  table.insert(lines,  "    self.visual.gap_buf:move_cursor_left()")
  table.insert(lines,  "  end")
  table.insert(lines,  "  while self.visual.gap_buf.gap_start < (@uint16)(target_pos) do")
  table.insert(lines,  "    self.visual.gap_buf:move_cursor_right()")
  table.insert(lines,  "  end")
  table.insert(lines,  "end")
end

-- ---------------------------------------------------------------------------
-- 子生成器 2: process_text_input — 消费键盘/鼠标事件，委托给 Gap Buffer
-- ---------------------------------------------------------------------------
local function _gen_process_text_input(lines, ctx)
  table.insert(lines, ("-- [editable/gap_buffer] %s: process_text_input (Phase 3.6.2 / Phase 4.7-S5 undo/redo)"):format(ctx))
  table.insert(lines, ("function %s:process_text_input(input: *NebulaInputState): boolean"):format(ctx))
  table.insert(lines,  "  if input.focused_id ~= self.component_id then return false end")
  table.insert(lines,  "  local changed = false")

  -- ★ Phase 3.6.2: just_clicked → 鼠标命中测试，同步光标位置
  table.insert(lines,  "  -- ★ Phase 3.6.2: mouse click → hit-test → cursor sync")
  table.insert(lines,  "  -- ★ Phase 3.6.3: Shift+Click 扩展选区；普通点击重置 anchor")
  table.insert(lines,  "  if self.click.just_clicked then")
  table.insert(lines, ("    local target = self:mouse_to_cursor(input.mouse_x, self.visual.pixel_height)"))
  table.insert(lines,  "    if not input.mod_shift then")
  table.insert(lines,  "      self.selection_anchor = target")
  table.insert(lines,  "    end")
  table.insert(lines,  "    self:sync_cursor_to(target)")
  table.insert(lines,  "    self.is_dragging = input.mouse_left_down")
  table.insert(lines,  "    changed = true")
  table.insert(lines,  "  end")
  -- ★ Phase 3.6.3: 鼠标拖拽
  table.insert(lines,  "  if self.is_dragging and input.mouse_left_down and not self.click.just_clicked then")
  table.insert(lines,  "    local drag_target = self:mouse_to_cursor(input.mouse_x, self.visual.pixel_height)")
  table.insert(lines,  "    self:sync_cursor_to(drag_target)")
  table.insert(lines,  "    changed = true")
  table.insert(lines,  "  end")
  table.insert(lines,  "  if not input.mouse_left_down then self.is_dragging = false end")

  -- ★ Phase 4.7-S5: undo/redo helper — record insert operation
  -- Records the bytes that were just inserted so undo can delete them.
  -- Called AFTER the insert into gap buffer. pre_cursor = cursor before insert.
  table.insert(lines,  "  -- ★ Phase 4.7-S5: undo/redo inline helpers")

  -- ★ Phase 4.X: 字符输入（支持完整 Unicode — UTF-8 编码插入）
  table.insert(lines,  "  local i: uint8 = 0")
  table.insert(lines,  "  while i < input.char_count do")
  table.insert(lines,  "    local cp = input.char_input[i]")
  table.insert(lines,  "    if cp >= 0x20 and cp ~= 0x7F then")
  -- Save pre-edit state for undo
  table.insert(lines,  "      local _undo_pre_cursor = (@uint32)(self.visual.gap_buf:cursor())")
  table.insert(lines,  "      local _undo_pre_anchor = self.selection_anchor")
  -- Delete selection if any
  table.insert(lines,  "      local _undo_had_sel = false")
  table.insert(lines,  "      local _undo_sel_data: [512]uint8")
  table.insert(lines,  "      local _undo_sel_len: uint16 = 0")
  table.insert(lines,  "      if self.selection_anchor ~= (@uint32)(self.visual.gap_buf:cursor()) then")
  table.insert(lines,  "        _undo_had_sel = true")
  table.insert(lines,  "        local cur = (@uint32)(self.visual.gap_buf:cursor())")
  table.insert(lines,  "        local anc = self.selection_anchor")
  table.insert(lines,  "        local sel_s = cur < anc and cur or anc")
  table.insert(lines,  "        local sel_e = cur < anc and anc or cur")
  table.insert(lines,  "        -- Save deleted selection for undo")
  table.insert(lines,  "        _undo_sel_len = (@uint16)(self.visual.gap_buf:extract_range(sel_s, sel_e, &_undo_sel_data[0], 511))")
  table.insert(lines,  "        self.visual.gap_buf:delete_range(sel_s, sel_e)")
  table.insert(lines,  "        self.selection_anchor = (@uint32)(self.visual.gap_buf:cursor())")
  table.insert(lines,  "      end")
  -- Record delete-selection as undo entry if had selection
  table.insert(lines,  "      if _undo_had_sel and _undo_sel_len > 0 then")
  table.insert(lines,  "        self.undo_stack:push(NEBULA_UNDO_OP_DELETE, _undo_pre_cursor, 0, 0, _undo_pre_anchor, &_undo_sel_data[0], _undo_sel_len)")
  table.insert(lines,  "      end")
  -- Now do the insert — save cursor before insert for undo recording
  table.insert(lines,  "      local _undo_ins_cursor = (@uint32)(self.visual.gap_buf:cursor())")
  table.insert(lines,  "      local _undo_ins_anchor = self.selection_anchor")
  -- UTF-8 encode and insert
  table.insert(lines,  "      local _ins_buf: [4]uint8")
  table.insert(lines,  "      local _ins_len: uint16 = 0")
  table.insert(lines,  "      if cp <= 0x7F then")
  table.insert(lines,  "        _ins_buf[0] = (@uint8)(cp)")
  table.insert(lines,  "        _ins_len = 1")
  table.insert(lines,  "      elseif cp <= 0x7FF then")
  table.insert(lines,  "        _ins_buf[0] = (@uint8)(0xC0 | (cp >> 6))")
  table.insert(lines,  "        _ins_buf[1] = (@uint8)(0x80 | (cp & 0x3F))")
  table.insert(lines,  "        _ins_len = 2")
  table.insert(lines,  "      elseif cp <= 0xFFFF then")
  table.insert(lines,  "        _ins_buf[0] = (@uint8)(0xE0 | (cp >> 12))")
  table.insert(lines,  "        _ins_buf[1] = (@uint8)(0x80 | ((cp >> 6) & 0x3F))")
  table.insert(lines,  "        _ins_buf[2] = (@uint8)(0x80 | (cp & 0x3F))")
  table.insert(lines,  "        _ins_len = 3")
  table.insert(lines,  "      elseif cp <= 0x10FFFF then")
  table.insert(lines,  "        _ins_buf[0] = (@uint8)(0xF0 | (cp >> 18))")
  table.insert(lines,  "        _ins_buf[1] = (@uint8)(0x80 | ((cp >> 12) & 0x3F))")
  table.insert(lines,  "        _ins_buf[2] = (@uint8)(0x80 | ((cp >> 6) & 0x3F))")
  table.insert(lines,  "        _ins_buf[3] = (@uint8)(0x80 | (cp & 0x3F))")
  table.insert(lines,  "        _ins_len = 4")
  table.insert(lines,  "      end")
  table.insert(lines,  "      local _ins_ok = true")
  table.insert(lines,  "      local _ii: uint16 = 0")
  table.insert(lines,  "      while _ii < _ins_len do")
  table.insert(lines,  "        if not self.visual.gap_buf:insert_char(_ins_buf[_ii]) then _ins_ok = false break end")
  table.insert(lines,  "        _ii = _ii + 1")
  table.insert(lines,  "      end")
  table.insert(lines,  "      if _ins_ok and _ins_len > 0 then")
  table.insert(lines,  "        -- ★ Phase 4.7-S5: record insert for undo")
  table.insert(lines,  "        self.undo_stack:push(NEBULA_UNDO_OP_INSERT, _undo_ins_cursor, 0, 0, _undo_ins_anchor, &_ins_buf[0], _ins_len)")
  table.insert(lines,  "        self.selection_anchor = (@uint32)(self.visual.gap_buf:cursor())")
  table.insert(lines,  "        changed = true")
  table.insert(lines,  "      end")
  table.insert(lines,  "    end")
  table.insert(lines,  "    i = i + 1")
  table.insert(lines,  "  end")

  -- 控制键处理
  table.insert(lines,  "  local k = input.key_pressed")
  table.insert(lines,  "  if k == NebulaKey.Backspace then")
  table.insert(lines,  "    if self.selection_anchor ~= self.visual.gap_buf:cursor() then")
  table.insert(lines,  "      local cur = (@uint32)(self.visual.gap_buf:cursor())")
  table.insert(lines,  "      local anc = self.selection_anchor")
  table.insert(lines,  "      local sel_s = cur < anc and cur or anc")
  table.insert(lines,  "      local sel_e = cur < anc and anc or cur")
  -- ★ Phase 4.7-S5: save deleted content for undo
  table.insert(lines,  "      local _del_buf: [512]uint8")
  table.insert(lines,  "      local _del_len: uint16 = (@uint16)(self.visual.gap_buf:extract_range(sel_s, sel_e, &_del_buf[0], 511))")
  table.insert(lines,  "      local _del_pre_cursor = cur")
  table.insert(lines,  "      local _del_pre_anchor = anc")
  table.insert(lines,  "      self.visual.gap_buf:delete_range(sel_s, sel_e)")
  table.insert(lines,  "      self.undo_stack:push(NEBULA_UNDO_OP_DELETE, _del_pre_cursor, 0, 0, _del_pre_anchor, &_del_buf[0], _del_len)")
  table.insert(lines,  "      self.selection_anchor = (@uint32)(self.visual.gap_buf:cursor())")
  table.insert(lines,  "      changed = true")
  -- Single char backspace
  table.insert(lines,  "    else")
  table.insert(lines,  "      local _bs_pre_cursor = (@uint32)(self.visual.gap_buf:cursor())")
  table.insert(lines,  "      local _bs_pre_anchor = self.selection_anchor")
  -- Figure out what bytes will be deleted (look behind cursor)
  table.insert(lines,  "      if self.visual.gap_buf.gap_start > 0 then")
  table.insert(lines,  "        -- Peek at bytes that will be deleted (before gap_start)")
  table.insert(lines,  "        local _bs_buf: [4]uint8")
  table.insert(lines,  "        local _bs_end = self.visual.gap_buf.gap_start")
  table.insert(lines,  "        local _bs_start = _bs_end - 1")
  table.insert(lines,  "        while _bs_start > 0 and (self.visual.gap_buf.buf[_bs_start] & 0xC0) == 0x80 do")
  table.insert(lines,  "          _bs_start = _bs_start - 1")
  table.insert(lines,  "        end")
  table.insert(lines,  "        local _bs_len: uint16 = _bs_end - _bs_start")
  table.insert(lines,  "        local _bi: uint16 = 0")
  table.insert(lines,  "        while _bi < _bs_len do")
  table.insert(lines,  "          _bs_buf[_bi] = self.visual.gap_buf.buf[_bs_start + _bi]")
  table.insert(lines,  "          _bi = _bi + 1")
  table.insert(lines,  "        end")
  table.insert(lines,  "        if self.visual.gap_buf:delete_char_before() then")
  table.insert(lines,  "          self.undo_stack:push(NEBULA_UNDO_OP_DELETE, _bs_pre_cursor, 0, 0, _bs_pre_anchor, &_bs_buf[0], _bs_len)")
  table.insert(lines,  "          self.selection_anchor = (@uint32)(self.visual.gap_buf:cursor())")
  table.insert(lines,  "          changed = true")
  table.insert(lines,  "        end")
  table.insert(lines,  "      end")
  table.insert(lines,  "    end")

  table.insert(lines,  "  elseif k == NebulaKey.Delete then")
  table.insert(lines,  "    if self.selection_anchor ~= self.visual.gap_buf:cursor() then")
  table.insert(lines,  "      local cur = (@uint32)(self.visual.gap_buf:cursor())")
  table.insert(lines,  "      local anc = self.selection_anchor")
  table.insert(lines,  "      local sel_s = cur < anc and cur or anc")
  table.insert(lines,  "      local sel_e = cur < anc and anc or cur")
  table.insert(lines,  "      local _del_buf: [512]uint8")
  table.insert(lines,  "      local _del_len: uint16 = (@uint16)(self.visual.gap_buf:extract_range(sel_s, sel_e, &_del_buf[0], 511))")
  table.insert(lines,  "      local _del_pre_cursor = cur")
  table.insert(lines,  "      local _del_pre_anchor = anc")
  table.insert(lines,  "      self.visual.gap_buf:delete_range(sel_s, sel_e)")
  table.insert(lines,  "      self.undo_stack:push(NEBULA_UNDO_OP_DELETE, _del_pre_cursor, 0, 0, _del_pre_anchor, &_del_buf[0], _del_len)")
  table.insert(lines,  "      self.selection_anchor = (@uint32)(self.visual.gap_buf:cursor())")
  table.insert(lines,  "      changed = true")
  -- Single char delete forward
  table.insert(lines,  "    else")
  table.insert(lines,  "      local _df_pre_cursor = (@uint32)(self.visual.gap_buf:cursor())")
  table.insert(lines,  "      local _df_pre_anchor = self.selection_anchor")
  table.insert(lines,  "      if self.visual.gap_buf.gap_end < self.visual.gap_buf.capacity then")
  table.insert(lines,  "        local _df_buf: [4]uint8")
  table.insert(lines,  "        local _df_start = self.visual.gap_buf.gap_end")
  table.insert(lines,  "        local _df_end = _df_start + 1")
  table.insert(lines,  "        while _df_end < self.visual.gap_buf.capacity and (self.visual.gap_buf.buf[_df_end] & 0xC0) == 0x80 do")
  table.insert(lines,  "          _df_end = _df_end + 1")
  table.insert(lines,  "        end")
  table.insert(lines,  "        local _df_len: uint16 = _df_end - _df_start")
  table.insert(lines,  "        local _di: uint16 = 0")
  table.insert(lines,  "        while _di < _df_len do")
  table.insert(lines,  "          _df_buf[_di] = self.visual.gap_buf.buf[_df_start + _di]")
  table.insert(lines,  "          _di = _di + 1")
  table.insert(lines,  "        end")
  table.insert(lines,  "        if self.visual.gap_buf:delete_char_after() then")
  table.insert(lines,  "          self.undo_stack:push(NEBULA_UNDO_OP_DELETE, _df_pre_cursor, 0, 0, _df_pre_anchor, &_df_buf[0], _df_len)")
  table.insert(lines,  "          changed = true")
  table.insert(lines,  "        end")
  table.insert(lines,  "      end")
  table.insert(lines,  "    end")

  -- Navigation keys (no undo recording needed)
  table.insert(lines,  "  elseif k == NebulaKey.Left then")
  table.insert(lines,  "    self.visual.gap_buf:move_cursor_left_char()")
  table.insert(lines,  "    self.selection_anchor = (@uint32)(self.visual.gap_buf:cursor())")
  table.insert(lines,  "    changed = true")
  table.insert(lines,  "  elseif k == NebulaKey.Right then")
  table.insert(lines,  "    self.visual.gap_buf:move_cursor_right_char()")
  table.insert(lines,  "    self.selection_anchor = (@uint32)(self.visual.gap_buf:cursor())")
  table.insert(lines,  "    changed = true")
  table.insert(lines,  "  elseif k == NebulaKey.Home then")
  table.insert(lines,  "    self.visual.gap_buf:move_cursor_home()")
  table.insert(lines,  "    self.selection_anchor = (@uint32)(self.visual.gap_buf:cursor())")
  table.insert(lines,  "    changed = true")
  table.insert(lines,  "  elseif k == NebulaKey.End then")
  table.insert(lines,  "    self.visual.gap_buf:move_cursor_end()")
  table.insert(lines,  "    self.selection_anchor = (@uint32)(self.visual.gap_buf:cursor())")
  table.insert(lines,  "    changed = true")
  -- ★ Phase 3.6.3: Shift 组合键变体——扩展选区（不重置 anchor）
  table.insert(lines,  "  elseif k == NebulaKey.ShiftLeft then")
  table.insert(lines,  "    self.visual.gap_buf:move_cursor_left_char()")
  table.insert(lines,  "    changed = true")
  table.insert(lines,  "  elseif k == NebulaKey.ShiftRight then")
  table.insert(lines,  "    self.visual.gap_buf:move_cursor_right_char()")
  table.insert(lines,  "    changed = true")
  table.insert(lines,  "  elseif k == NebulaKey.ShiftHome then")
  table.insert(lines,  "    self.visual.gap_buf:move_cursor_home()")
  table.insert(lines,  "    changed = true")
  table.insert(lines,  "  elseif k == NebulaKey.ShiftEnd then")
  table.insert(lines,  "    self.visual.gap_buf:move_cursor_end()")
  table.insert(lines,  "    changed = true")
  -- ★ Phase 4.X: 剪贴板操作（Ctrl+C / Ctrl+V / Ctrl+X / Ctrl+A）
  table.insert(lines,  "  elseif k == NebulaKey.SelectAll then")
  table.insert(lines,  "    self.visual.gap_buf:move_cursor_home()")
  table.insert(lines,  "    self.selection_anchor = (@uint32)(self.visual.gap_buf:cursor())")
  table.insert(lines,  "    self.visual.gap_buf:move_cursor_end()")
  table.insert(lines,  "    changed = true")
  table.insert(lines,  "  elseif k == NebulaKey.Copy or k == NebulaKey.Cut then")
  table.insert(lines,  "    if self.selection_anchor ~= (@uint32)(self.visual.gap_buf:cursor()) then")
  table.insert(lines,  "      local cur = (@uint32)(self.visual.gap_buf:cursor())")
  table.insert(lines,  "      local anc = self.selection_anchor")
  table.insert(lines,  "      local sel_s = cur < anc and cur or anc")
  table.insert(lines,  "      local sel_e = cur < anc and anc or cur")
  table.insert(lines,  "      local sel_len = sel_e - sel_s")
  table.insert(lines,  "      if sel_len > 0 and sel_len < 512 then")
  table.insert(lines,  "        local clip_buf: [512]uint8")
  table.insert(lines,  "        self.visual.gap_buf:extract_range(sel_s, sel_e, &clip_buf[0], 511)")
  table.insert(lines,  "        clip_buf[sel_len] = 0")
  table.insert(lines,  "        glfwSetClipboardString(nilptr, (@cstring)(&clip_buf[0]))")
  table.insert(lines,  "      end")
  table.insert(lines,  "      if k == NebulaKey.Cut then")
  -- ★ Phase 4.7-S5: record cut (delete) for undo
  table.insert(lines,  "        local _cut_buf: [512]uint8")
  table.insert(lines,  "        local _cut_len: uint16 = (@uint16)(self.visual.gap_buf:extract_range(sel_s, sel_e, &_cut_buf[0], 511))")
  table.insert(lines,  "        self.visual.gap_buf:delete_range(sel_s, sel_e)")
  table.insert(lines,  "        self.undo_stack:push(NEBULA_UNDO_OP_DELETE, cur, 0, 0, anc, &_cut_buf[0], _cut_len)")
  table.insert(lines,  "        self.selection_anchor = (@uint32)(self.visual.gap_buf:cursor())")
  table.insert(lines,  "        changed = true")
  table.insert(lines,  "      end")
  table.insert(lines,  "    end")
  table.insert(lines,  "  elseif k == NebulaKey.Paste then")
  table.insert(lines,  "    local clip = glfwGetClipboardString(nilptr)")
  table.insert(lines,  "    if clip ~= nilptr then")
  table.insert(lines,  "      local clip_bytes = (@*[0]uint8)(clip)")
  -- ★ Phase 4.7-S5: handle paste with undo
  table.insert(lines,  "      local _paste_pre_cursor = (@uint32)(self.visual.gap_buf:cursor())")
  table.insert(lines,  "      local _paste_pre_anchor = self.selection_anchor")
  table.insert(lines,  "      -- 有选区时先删除（record as separate undo entry）")
  table.insert(lines,  "      if self.selection_anchor ~= (@uint32)(self.visual.gap_buf:cursor()) then")
  table.insert(lines,  "        local cur = (@uint32)(self.visual.gap_buf:cursor())")
  table.insert(lines,  "        local anc = self.selection_anchor")
  table.insert(lines,  "        local sel_s = cur < anc and cur or anc")
  table.insert(lines,  "        local sel_e = cur < anc and anc or cur")
  table.insert(lines,  "        local _psd_buf: [512]uint8")
  table.insert(lines,  "        local _psd_len: uint16 = (@uint16)(self.visual.gap_buf:extract_range(sel_s, sel_e, &_psd_buf[0], 511))")
  table.insert(lines,  "        self.visual.gap_buf:delete_range(sel_s, sel_e)")
  table.insert(lines,  "        self.undo_stack:push(NEBULA_UNDO_OP_DELETE, _paste_pre_cursor, 0, 0, _paste_pre_anchor, &_psd_buf[0], _psd_len)")
  table.insert(lines,  "      end")
  table.insert(lines,  "      -- Insert pasted content")
  table.insert(lines,  "      local _pi_start = (@uint32)(self.visual.gap_buf:cursor())")
  table.insert(lines,  "      local _pi_anchor = self.selection_anchor")
  table.insert(lines,  "      local ci: uint32 = 0")
  table.insert(lines,  "      while clip_bytes[ci] ~= 0 and ci < 512 do")
  table.insert(lines,  "        if not self.visual.gap_buf:insert_char(clip_bytes[ci]) then break end")
  table.insert(lines,  "        ci = ci + 1")
  table.insert(lines,  "      end")
  table.insert(lines,  "      if ci > 0 then")
  table.insert(lines,  "        -- Record paste as insert for undo")
  table.insert(lines,  "        local _paste_buf: [512]uint8")
  table.insert(lines,  "        local _pi: uint32 = 0")
  table.insert(lines,  "        while _pi < ci and _pi < 512 do")
  table.insert(lines,  "          _paste_buf[_pi] = clip_bytes[_pi]")
  table.insert(lines,  "          _pi = _pi + 1")
  table.insert(lines,  "        end")
  table.insert(lines,  "        self.undo_stack:push(NEBULA_UNDO_OP_INSERT, _pi_start, 0, 0, _pi_anchor, &_paste_buf[0], (@uint16)(ci))")
  table.insert(lines,  "      end")
  table.insert(lines,  "      self.selection_anchor = (@uint32)(self.visual.gap_buf:cursor())")
  table.insert(lines,  "      changed = true")
  table.insert(lines,  "    end")

  -- ★ Phase 4.7-S5: Undo
  table.insert(lines,  "  elseif k == NebulaKey.Undo then")
  table.insert(lines,  "    if self.undo_stack:can_undo() then")
  table.insert(lines,  "      local entry = self.undo_stack:peek_undo()")
  table.insert(lines,  "      local edata = self.undo_stack:get_data(entry)")
  table.insert(lines,  "      if entry.op == NEBULA_UNDO_OP_INSERT then")
  table.insert(lines,  "        -- Undo insert = delete the inserted bytes")
  table.insert(lines,  "        -- Inserted bytes start at entry.cursor_pos, length = entry.data_len")
  table.insert(lines,  "        self.visual.gap_buf:delete_range(entry.cursor_pos, entry.cursor_pos + (@uint32)(entry.data_len))")
  table.insert(lines,  "        self.selection_anchor = entry.anchor")
  table.insert(lines,  "      elseif entry.op == NEBULA_UNDO_OP_DELETE then")
  table.insert(lines,  "        -- Undo delete = re-insert the deleted bytes at the delete position")
  table.insert(lines,  "        -- First move cursor to the position where bytes were (min of old cursor/anchor)")
  table.insert(lines,  "        local restore_pos = entry.cursor_pos < entry.anchor and entry.cursor_pos or entry.anchor")
  table.insert(lines,  "        -- Move gap to restore_pos")
  table.insert(lines,  "        self.visual.gap_buf:move_cursor_home()")
  table.insert(lines,  "        local _ri: uint32 = 0")
  table.insert(lines,  "        while _ri < restore_pos do")
  table.insert(lines,  "          self.visual.gap_buf:move_cursor_right()")
  table.insert(lines,  "          _ri = _ri + 1")
  table.insert(lines,  "        end")
  table.insert(lines,  "        -- Re-insert bytes")
  table.insert(lines,  "        local _rj: uint16 = 0")
  table.insert(lines,  "        while _rj < entry.data_len do")
  table.insert(lines,  "          self.visual.gap_buf:insert_char(edata[_rj])")
  table.insert(lines,  "          _rj = _rj + 1")
  table.insert(lines,  "        end")
  table.insert(lines,  "        -- Restore cursor and anchor")
  table.insert(lines,  "        self.selection_anchor = entry.anchor")
  table.insert(lines,  "        -- Move cursor to original pre-op position")
  table.insert(lines,  "        self.visual.gap_buf:move_cursor_home()")
  table.insert(lines,  "        local _rk: uint32 = 0")
  table.insert(lines,  "        while _rk < entry.cursor_pos do")
  table.insert(lines,  "          self.visual.gap_buf:move_cursor_right()")
  table.insert(lines,  "          _rk = _rk + 1")
  table.insert(lines,  "        end")
  table.insert(lines,  "      end")
  table.insert(lines,  "      self.undo_stack:step_undo()")
  table.insert(lines,  "      changed = true")
  table.insert(lines,  "    end")

  -- ★ Phase 4.7-S5: Redo
  table.insert(lines,  "  elseif k == NebulaKey.Redo then")
  table.insert(lines,  "    if self.undo_stack:can_redo() then")
  table.insert(lines,  "      local entry = self.undo_stack:peek_redo()")
  table.insert(lines,  "      local edata = self.undo_stack:get_data(entry)")
  table.insert(lines,  "      if entry.op == NEBULA_UNDO_OP_INSERT then")
  table.insert(lines,  "        -- Redo insert = re-insert the bytes")
  table.insert(lines,  "        self.visual.gap_buf:move_cursor_home()")
  table.insert(lines,  "        local _ri: uint32 = 0")
  table.insert(lines,  "        while _ri < entry.cursor_pos do")
  table.insert(lines,  "          self.visual.gap_buf:move_cursor_right()")
  table.insert(lines,  "          _ri = _ri + 1")
  table.insert(lines,  "        end")
  table.insert(lines,  "        local _rj: uint16 = 0")
  table.insert(lines,  "        while _rj < entry.data_len do")
  table.insert(lines,  "          self.visual.gap_buf:insert_char(edata[_rj])")
  table.insert(lines,  "          _rj = _rj + 1")
  table.insert(lines,  "        end")
  table.insert(lines,  "        self.selection_anchor = (@uint32)(self.visual.gap_buf:cursor())")
  table.insert(lines,  "      elseif entry.op == NEBULA_UNDO_OP_DELETE then")
  table.insert(lines,  "        -- Redo delete = re-delete the bytes")
  table.insert(lines,  "        local del_pos = entry.cursor_pos < entry.anchor and entry.cursor_pos or entry.anchor")
  table.insert(lines,  "        self.visual.gap_buf:delete_range(del_pos, del_pos + (@uint32)(entry.data_len))")
  table.insert(lines,  "        self.selection_anchor = (@uint32)(self.visual.gap_buf:cursor())")
  table.insert(lines,  "      end")
  table.insert(lines,  "      self.undo_stack:step_redo()")
  table.insert(lines,  "      changed = true")
  table.insert(lines,  "    end")

  table.insert(lines,  "  end")
  table.insert(lines,  "  return changed")
  table.insert(lines,  "end")
end

-- ---------------------------------------------------------------------------
-- 子生成器 3: 选区辅助方法 (has_selection / get_selection / clear_selection)
-- ---------------------------------------------------------------------------
local function _gen_selection_helpers(lines, ctx)
  table.insert(lines, ("-- [editable/selection] %s: has_selection (Phase 3.6.3)"):format(ctx))
  table.insert(lines, ("function %s:has_selection(): boolean"):format(ctx))
  table.insert(lines,  "  return self.selection_anchor ~= (@uint32)(self.visual.gap_buf:cursor())")
  table.insert(lines,  "end")
  table.insert(lines, ("-- [editable/selection] %s: get_selection (Phase 3.6.3)"):format(ctx))
  table.insert(lines, ("function %s:get_selection(sel_start: *uint32, sel_end: *uint32): void"):format(ctx))
  table.insert(lines,  "  local cur = (@uint32)(self.visual.gap_buf:cursor())")
  table.insert(lines,  "  local anc = self.selection_anchor")
  table.insert(lines,  "  $sel_start = cur < anc and cur or anc")
  table.insert(lines,  "  $sel_end   = cur < anc and anc or cur")
  table.insert(lines,  "end")
  table.insert(lines, ("-- [editable/selection] %s: clear_selection (Phase 3.6.3)"):format(ctx))
  table.insert(lines, ("function %s:clear_selection(): void"):format(ctx))
  table.insert(lines,  "  self.selection_anchor = (@uint32)(self.visual.gap_buf:cursor())")
  table.insert(lines,  "end")
end

-- ---------------------------------------------------------------------------
-- 子生成器 4: 文本访问器 (get_text_len / get_text)
-- ---------------------------------------------------------------------------
local function _gen_text_accessors(lines, ctx)
  table.insert(lines, ("-- [editable/gap_buffer] %s: get_text_len"):format(ctx))
  table.insert(lines, ("function %s:get_text_len(): uint16"):format(ctx))
  table.insert(lines,  "  return self.visual.gap_buf:len()")
  table.insert(lines,  "end")

  -- ★ Phase 3.6.2: get_text(out, max) — 修复 L1/L2 渗透
  --
  -- 旧版（3.6.1）将展平结果写入 visual.flat_buf（持久 L1 字段），违反公理 B。
  -- 新版接受调用方提供的栈上缓冲区 out，展平后立即使用，帧结束自动回收。
  --
  -- 调用方示例：
  --   local flat: [256]uint8
  --   local text = ctx:get_text(&flat[0], 255)
  table.insert(lines, ("-- [editable/gap_buffer] %s: get_text (Phase 3.6.2: 栈上缓冲区，修复 L1/L2 渗透)"):format(ctx))
  table.insert(lines, ("function %s:get_text(out: *[0]uint8, max_out: uint16): cstring"):format(ctx))
  table.insert(lines,  "  self.visual.gap_buf:flatten(out, max_out)")
  table.insert(lines,  "  return (@cstring)(out)")
  table.insert(lines,  "end")
end

-- ---------------------------------------------------------------------------
-- 主入口：编排所有子生成器，保持 Nelua 所需的声明顺序
-- ---------------------------------------------------------------------------
function nebula_gen_text_buffer(spec)
  assert(spec.base, "nebula_gen_text_buffer: spec.base required")
  local ctx      = spec.base .. "Context"
  local cap_val  = spec.max_text_len or 255
  local lines    = {}

  -- 生成顺序严格遵循 Nelua 前向声明规则：
  -- 1. cursor helpers (mouse_to_cursor, sync_cursor_to) — 被 process_text_input 调用
  -- 2. process_text_input — 主事件处理
  -- 3. selection helpers — 独立辅助方法
  -- 4. text accessors — 独立辅助方法
  _gen_cursor_helpers(lines, ctx, cap_val)
  _gen_process_text_input(lines, ctx)
  _gen_selection_helpers(lines, ctx)
  _gen_text_accessors(lines, ctx)

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

-- ★ Phase 3.10: Monkey-patch 已删除。
-- toggleable 的 process_toggle 调用现在通过 NEBULA_PRIMITIVES 注册表的
-- post_process 元数据驱动，在 nebula_gen_process_input 中按顺序插入。

-- 返回模块标识
return "nebula_interaction_factory_v0.7_phase3.10"
