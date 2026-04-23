-- =============================================================================
-- derive/app_factory.lua
-- Nebula GUI Compiler — Phase 3.5.2
--
-- 编译期显式编排工厂（App Factory）
--
-- 职责：
--   · 维护应用组件树注册表（nebula_app_registry）
--   · 提供 nebula_app_begin / nebula_app_register_component /
--     nebula_app_register_slot / nebula_app_end API
--   · 提供 nebula_derive_app(app_name) 主入口，生成：
--       global <App> = @record{ ... }          -- 包含所有 Context + Pipeline
--       function <App>:init(renderer, vw, vh)  -- 初始化所有管线和组件
--       function <App>:update(input, dt)        -- 显式调用序列（编译期展开）
--       function <App>:draw(pass)               -- 收集 + upload + draw_instanced
--
-- 设计哲学：
--   · 零运行时开销：所有编排逻辑在编译期展开为等价于手写的静态代码
--   · 形状即渲染：同类型组件共享专属 Pipeline，通过 Instancing 批量绘制
--   · 声明意图派生代码：开发者只需声明组件树，框架生成显式执行代码
-- =============================================================================

-- 全局应用注册表
local nebula_app_registry = {}

-- 当前正在构建的 App 名称
local _current_app = nil

-- =============================================================================
-- 注册 API
-- =============================================================================

-- 开始声明一个新的 App
function nebula_app_begin(app_name)
  assert(app_name, "nebula_app_begin: app_name required")
  assert(not nebula_app_registry[app_name],
    ("nebula_app_begin: app '%s' already registered"):format(app_name))
  _current_app = app_name
  nebula_app_registry[app_name] = {
    name       = app_name,
    components = {},  -- 静态组件列表：{name, visual_type, base, component_id}
    slots      = {},  -- 动态插槽列表：{name, visual_type, base, max_instances}
    -- 按 visual_type 分组，用于生成共享 Pipeline
    type_groups = {},  -- {visual_type -> {pipeline_name, base, members=[{name, is_slot}]}}
  }
end

-- 注册一个静态组件
-- opts:
--   name         : string  — 组件实例名（如 "card", "email_input"）
--   visual_type  : string  — Visual 类型名（如 "CardVisual", "InputVisual"）
--   component_id : number  — focusable 组件的 ID（可选，默认 0）
function nebula_app_register_component(name, visual_type, opts)
  assert(_current_app, "nebula_app_register_component: must be called between nebula_app_begin and nebula_app_end")
  opts = opts or {}
  local reg = nebula_app_registry[_current_app]
  local base = visual_type:sub(-#"Visual") == "Visual"
    and visual_type:sub(1, #visual_type - #"Visual")
    or visual_type

  table.insert(reg.components, {
    name         = name,
    visual_type  = visual_type,
    base         = base,
    component_id = opts.component_id or 0,
    has_text_buf = opts.has_text_buf or false,  -- 是否有 process_text_input
    text_context = opts.text_context or nil,    -- 关联的 TextContext 名称
  })

  -- 更新 type_groups
  if not reg.type_groups[visual_type] then
    reg.type_groups[visual_type] = {
      visual_type    = visual_type,
      base           = base,
      pipeline_name  = base .. "Pipeline",
      members        = {},
    }
  end
  table.insert(reg.type_groups[visual_type].members, {
    name     = name,
    is_slot  = false,
  })
end

-- 注册一个动态插槽（对应 Arena 分配的动态列表）
-- opts:
--   name          : string  — 插槽名（如 "list_items"）
--   visual_type   : string  — Visual 类型名
--   max_instances : number  — 最大实例数（决定 Storage Buffer 大小）
--   arena_var     : string  — 运行时 Arena 变量名（如 "item_arena"）
--   count_var     : string  — 运行时实例计数变量名（如 "item_count"）
--   data_var      : string  — 运行时实例数据数组变量名（如 "item_instances"）
function nebula_app_register_slot(name, visual_type, opts)
  assert(_current_app, "nebula_app_register_slot: must be called between nebula_app_begin and nebula_app_end")
  opts = opts or {}
  local reg = nebula_app_registry[_current_app]
  local base = visual_type:sub(-#"Visual") == "Visual"
    and visual_type:sub(1, #visual_type - #"Visual")
    or visual_type

  table.insert(reg.slots, {
    name          = name,
    visual_type   = visual_type,
    base          = base,
    max_instances = opts.max_instances or 128,
    arena_var     = opts.arena_var  or (name .. "_arena"),
    count_var     = opts.count_var  or (name .. "_count"),
    data_var      = opts.data_var   or (name .. "_instances"),
  })

  -- 更新 type_groups
  if not reg.type_groups[visual_type] then
    reg.type_groups[visual_type] = {
      visual_type    = visual_type,
      base           = base,
      pipeline_name  = base .. "Pipeline",
      members        = {},
    }
  end
  table.insert(reg.type_groups[visual_type].members, {
    name     = name,
    is_slot  = true,
  })
end

-- 结束 App 声明
function nebula_app_end()
  assert(_current_app, "nebula_app_end: no app currently being declared")
  _current_app = nil
end

-- =============================================================================
-- 代码生成：nebula_derive_app(app_name)
-- =============================================================================

-- 生成 <App> record 定义
local function gen_app_record(app_name, reg)
  local L = {}
  local function emit(s) table.insert(L, s) end

  emit(("-- === Derived App: %s ==="):format(app_name))
  emit(("global %s = @record{"):format(app_name))
  emit("  renderer: *NebulaRenderer,")
  emit("  vw: float32,")
  emit("  vh: float32,")
  emit("")
  emit("  -- 组件 Context")
  for _, comp in ipairs(reg.components) do
    emit(("  %s: %sContext,"):format(comp.name, comp.base))
  end
  emit("")
  emit("  -- 共享 Pipeline（每种 Visual 类型一个）")
  local emitted_pipes = {}
  for vt, group in pairs(reg.type_groups) do
    if not emitted_pipes[group.pipeline_name] then
      emit(("  pipe_%s: %s,"):format(group.base:lower(), group.pipeline_name))
      emitted_pipes[group.pipeline_name] = true
    end
  end
  emit("}")

  return table.concat(L, "\n")
end

-- 生成 <App>:init(renderer, vw, vh) 方法
local function gen_app_init(app_name, reg)
  local L = {}
  local function emit(s) table.insert(L, s) end

  emit(("function %s:init(renderer: *NebulaRenderer, vw: float32, vh: float32): boolean"):format(app_name))
  emit("  self.renderer = renderer")
  emit("  self.vw = vw")
  emit("  self.vh = vh")
  emit("")
  emit("  -- 初始化所有 Pipeline")
  local inited_pipes = {}
  for vt, group in pairs(reg.type_groups) do
    if not inited_pipes[group.pipeline_name] then
      -- 计算该类型的最大实例数：静态组件数 + 所有插槽的 max_instances
      local max_inst = 0
      for _, m in ipairs(group.members) do
        if not m.is_slot then
          max_inst = max_inst + 1
        end
      end
      for _, slot in ipairs(reg.slots) do
        if slot.visual_type == vt then
          max_inst = max_inst + slot.max_instances
        end
      end
      if max_inst == 0 then max_inst = 1 end
      emit(("  if not self.pipe_%s:init(renderer, %d) then return false end"):format(
        group.base:lower(), max_inst))
      emit(("  self.pipe_%s:update_viewport(renderer, vw, vh)"):format(group.base:lower()))
      inited_pipes[group.pipeline_name] = true
    end
  end
  emit("  return true")
  emit("end")

  return table.concat(L, "\n")
end

-- 生成 <App>:update(input, dt) 方法
-- 按注册顺序显式调用每个组件的 update，并处理 text_buf 组件
local function gen_app_update(app_name, reg)
  local L = {}
  local function emit(s) table.insert(L, s) end

  emit(("function %s:update(input: *NebulaInputState, dt: float32): void"):format(app_name))
  emit("  -- 按注册顺序显式更新所有静态组件")
  for _, comp in ipairs(reg.components) do
    emit(("  self.%s:update(input, dt)"):format(comp.name))
  end
  emit("end")

  return table.concat(L, "\n")
end

-- 生成 <App>:draw(pass) 方法
-- 按类型分组，收集所有同类型组件的 Uniforms 到临时数组，然后 upload + draw_instanced
local function gen_app_draw(app_name, reg)
  local L = {}
  local function emit(s) table.insert(L, s) end

  emit(("function %s:draw(pass: WGPURenderPassEncoder): void"):format(app_name))

  -- 按 type_groups 分组生成批量绘制代码
  local processed_types = {}
  -- 先处理静态组件，再处理插槽
  -- 为了保持绘制顺序（先注册先绘制），按注册顺序遍历 type_groups
  local ordered_types = {}
  local seen_types = {}
  for _, comp in ipairs(reg.components) do
    if not seen_types[comp.visual_type] then
      table.insert(ordered_types, comp.visual_type)
      seen_types[comp.visual_type] = true
    end
  end
  for _, slot in ipairs(reg.slots) do
    if not seen_types[slot.visual_type] then
      table.insert(ordered_types, slot.visual_type)
      seen_types[slot.visual_type] = true
    end
  end

  for _, vt in ipairs(ordered_types) do
    local group = reg.type_groups[vt]
    if not group then goto continue end

    -- 统计静态成员
    local static_members = {}
    for _, m in ipairs(group.members) do
      if not m.is_slot then
        table.insert(static_members, m.name)
      end
    end

    -- 统计动态插槽
    local slot_members = {}
    for _, slot in ipairs(reg.slots) do
      if slot.visual_type == vt then
        table.insert(slot_members, slot)
      end
    end

    -- 计算最大实例数
    local max_inst = #static_members
    for _, slot in ipairs(slot_members) do
      max_inst = max_inst + slot.max_instances
    end
    if max_inst == 0 then goto continue end

    local uniforms_record = group.base .. "Uniforms"
    local pipe_var = "self.pipe_" .. group.base:lower()

    emit(("  -- 批量绘制 %s（%d 静态 + %d 动态插槽）"):format(
      vt, #static_members, #slot_members))
    emit(("  do"):format())
    emit(("    local _batch: [%d]%s"):format(max_inst, uniforms_record))
    emit(("    local _count: uint32 = 0"):format())

    -- 收集静态组件的 Uniforms
    for _, name in ipairs(static_members) do
      emit(("    _batch[_count] = self.%s:to_uniforms(self.vw, self.vh)"):format(name))
      emit(("    _count = _count + 1"):format())
    end

    -- 收集动态插槽数据（直接引用外部变量）
    for _, slot in ipairs(slot_members) do
      emit(("    -- 动态插槽：%s（运行时由 %s 提供）"):format(slot.name, slot.data_var))
      emit(("    local _si: uint32 = 0"):format())
      emit(("    while _si < %s and _count < %d do"):format(slot.count_var, max_inst))
      emit(("      _batch[_count] = %s[_si]"):format(slot.data_var))
      emit(("      _count = _count + 1"):format())
      emit(("      _si = _si + 1"):format())
      emit(("    end"):format())
    end

    -- upload + draw_instanced
    emit(("    if _count > 0 then"):format())
    emit(("      %s:upload(self.renderer, &_batch[0], _count)"):format(pipe_var))
    emit(("      %s:draw_instanced(pass, _count)"):format(pipe_var))
    emit(("    end"):format())
    emit(("  end"):format())

    ::continue::
  end

  emit("end")

  return table.concat(L, "\n")
end

-- =============================================================================
-- 主入口：nebula_app_generate(app_name)
-- 注意：此函数名不同于 nebula_derive_app，避免与 nebula_core.nelua 中的同名宏冲突
-- =============================================================================
function nebula_app_generate(app_name)
  local reg = nebula_app_registry[app_name]
  assert(reg, ("nebula_derive_app: app '%s' not registered. Call nebula_app_begin/end first."):format(app_name))

  local parts = {
    gen_app_record(app_name, reg),
    gen_app_init(app_name, reg),
    gen_app_update(app_name, reg),
    gen_app_draw(app_name, reg),
  }

  local source = table.concat(parts, "\n\n")

  print(("[derive-app] %s: emit App record + init + update + draw (%d components, %d slots, %d type_groups)"):format(
    app_name,
    #reg.components,
    #reg.slots,
    (function()
      local n = 0
      for _ in pairs(reg.type_groups) do n = n + 1 end
      return n
    end)()
  ))

  return source
end

return "nebula_app_factory_v0.1_phase3.5.2"
