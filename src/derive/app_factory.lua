-- =============================================================================
-- derive/app_factory.lua — Nebula GUI Compiler Phase 3.10.5
--
-- 编译期显式编排工厂（App Factory）
-- 生成 <App> record + init + update + draw
--
-- ★ Phase 3.8 新增：Arena 内嵌，nebula_frame_render 封装
-- ★ Phase 3.9 新增：
--   · nebula_app_register_text  — 文本一等公民（原语 3）
--   · nebula_app_register_slot  — Slot Producer 重构（原语 4，废弃外部全局变量）
--   · NebulaSlotView            — 动态插槽视图 Record
-- ★ Phase 3.10.5 新增：
--   · nebula_app_register_text 扩展：支持独立文本标签（bound_to = nil）
--     · mode = "static"  — 静态文本，初始化后不再更新
--     · mode = "dynamic" — 动态文本，通过 updater 函数每帧更新
--     · mode = "bound"   — 绑定到 editable 组件（原有行为）
-- =============================================================================

-- 全局应用注册表
local nebula_app_registry = {}

-- 当前正在构建的 App 名称
local _current_app = nil

-- =============================================================================
-- 注册 API
-- =============================================================================

-- 开始声明一个新的 App
-- opts（可选）：
--   arena_size : number — FrameArena 后备内存字节数（默认 2 * 1024 * 1024 = 2MB）
function nebula_app_begin(app_name, opts)
  assert(app_name, "nebula_app_begin: app_name required")
  assert(not nebula_app_registry[app_name],
    ("nebula_app_begin: app '%s' already registered"):format(app_name))
  opts = opts or {}
  _current_app = app_name
  nebula_app_registry[app_name] = {
    name        = app_name,
    components  = {},  -- 静态组件列表：{name, visual_type, base, component_id}
    slots       = {},  -- 动态插槽列表：{name, visual_type, base, max_instances, producer}
    texts       = {},  -- ★ Phase 3.9: 文本组件列表：{name, visual_type, base, mode, bound_to, placeholder, mask_password, updater}
    shadows     = {},  -- ★ Phase 3.10.5: 阴影组件列表：{name, visual_type, base, blur_radius}
    -- 按 visual_type 分组，用于生成共享 Pipeline
    type_groups = {},  -- {visual_type -> {pipeline_name, base, members=[{name, is_slot}]}}
    -- ★ Phase 3.8: FrameArena 配置
    arena_size  = opts.arena_size or (2 * 1024 * 1024),  -- 默认 2MB
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
    -- 以下字段为 Phase 3.8 遗留，Phase 3.9 由 nebula_app_register_text 接管
    has_text_buf = opts.has_text_buf or false,
    text_context = opts.text_context or nil,
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

-- ★ Phase 3.9 / Phase 3.10.5: 注册一个文本组件（原语 3：编译期 Text 一等公民）
--
-- Phase 3.10.5 扩展：支持三种模式（mode 字段）：
--   · "bound"   — 绑定到 editable 组件（原有行为，默认当 bound_to 存在时）
--   · "static"  — 独立静态文本，初始化后不自动更新（适合标题、标签等）
--   · "dynamic" — 独立动态文本，通过 updater 函数每帧更新（适合计数器等）
--
-- opts:
--   bound_to      : string  — [bound 模式] 绑定的 editable 组件名（如 "email_input"）
--   placeholder   : string  — [bound 模式] 默认占位符文本（如 "email"）
--   mask_password : boolean — [bound 模式] 是否掩码显示（true 时将字符替换为 '*'）
--   mode          : string  — 模式："bound"（默认）/ "static" / "dynamic"
--   updater       : string  — [dynamic 模式] 用户实现的更新函数名
--                             签名：function(app: *<App>, arena: *NebulaArena): cstring
function nebula_app_register_text(name, visual_type, opts)
  assert(_current_app, "nebula_app_register_text: must be called between nebula_app_begin and nebula_app_end")
  opts = opts or {}
  local reg = nebula_app_registry[_current_app]
  local base = visual_type:sub(-#"Visual") == "Visual"
    and visual_type:sub(1, #visual_type - #"Visual")
    or visual_type

  -- ★ Phase 3.10.5: 自动推断模式
  local mode = opts.mode
  if not mode then
    if opts.bound_to then
      mode = "bound"
    elseif opts.updater then
      mode = "dynamic"
    else
      mode = "static"
    end
  end

  -- bound 模式仍然要求 bound_to
  if mode == "bound" then
    assert(opts.bound_to, ("nebula_app_register_text: '%s' in bound mode requires opts.bound_to"):format(name))
  end
  -- dynamic 模式要求 updater
  if mode == "dynamic" then
    assert(opts.updater, ("nebula_app_register_text: '%s' in dynamic mode requires opts.updater"):format(name))
  end

  table.insert(reg.texts, {
    name          = name,
    visual_type   = visual_type,
    base          = base,
    mode          = mode,
    -- bound 模式字段
    bound_to      = opts.bound_to,
    placeholder   = opts.placeholder or "",
    mask_password = opts.mask_password or false,
    -- dynamic 模式字段
    updater       = opts.updater,
  })
end

-- ★ Phase 3.9: 注册一个动态插槽（原语 4：插槽即 Arena Producer）
--
-- 废弃旧的 arena_var / count_var / data_var 外部全局变量模式，
-- 改为声明一个 Producer 函数，由框架自动管理 Arena 生命周期。
--
-- opts:
--   max_instances : number  — 最大实例数（决定 Arena 分配大小）
--   producer      : string  — 用户实现的纯函数名
--                             签名：function(app: *<App>, arena: *NebulaArena, slot: *NebulaSlotView(T)): void
function nebula_app_register_slot(name, visual_type, opts)
  assert(_current_app, "nebula_app_register_slot: must be called between nebula_app_begin and nebula_app_end")
  opts = opts or {}
  local reg = nebula_app_registry[_current_app]
  local base = visual_type:sub(-#"Visual") == "Visual"
    and visual_type:sub(1, #visual_type - #"Visual")
    or visual_type

  -- ★ Phase 3.9: producer 模式（新 API）
  local producer = opts.producer
  -- 向后兼容：若仍使用旧的 count_var/data_var 模式，保留但标记为 legacy
  local legacy_count_var = opts.count_var
  local legacy_data_var  = opts.data_var

  table.insert(reg.slots, {
    name          = name,
    visual_type   = visual_type,
    base          = base,
    max_instances = opts.max_instances or 128,
    producer      = producer,
    -- legacy 字段（Phase 3.9 前的旧 API，保留兼容性）
    legacy_count_var = legacy_count_var,
    legacy_data_var  = legacy_data_var,
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

-- ★ Phase 3.10.5: 注册一个阴影组件（多 Pass 渲染）
--
-- 将阴影组件纳入 App 编排系统，自动生成：
--   · <App> record 中注入 <T>Pipeline 字段（多 Pass 版本）
--   · <App>:init 中注入 shadow_pipeline:init 调用
--   · <App>:update 中注入 shadow_pipeline:update_uniforms 调用
--   · <App>:draw_pre_pass 中注入 shadow_pipeline:draw_shadow 调用（离屏 Pass 1-3）
--   · <App>:draw_surface_pass 中注入 draw_composite + draw 调用（Surface Pass 4）
--
-- opts:
--   blur_radius  : number  — 默认模糊半径（默认 8.0）
--   win_w        : number  — 窗口宽度（用于离屏纹理尺寸，默认 800）
--   win_h        : number  — 窗口高度（默认 600）
function nebula_app_register_shadow(name, visual_type, opts)
  assert(_current_app, "nebula_app_register_shadow: must be called between nebula_app_begin and nebula_app_end")
  opts = opts or {}
  local reg = nebula_app_registry[_current_app]
  local base = visual_type:sub(-#"Visual") == "Visual"
    and visual_type:sub(1, #visual_type - #"Visual")
    or visual_type

  table.insert(reg.shadows, {
    name         = name,
    visual_type  = visual_type,
    base         = base,
    blur_radius  = opts.blur_radius or 8.0,
    win_w        = opts.win_w or 800,
    win_h        = opts.win_h or 600,
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

-- 生成 <App> record
-- ★ Phase 3.8: 注入 arena + _arena_backing
-- ★ Phase 3.9: 注入 TextContext 字段（文本一等公民）
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

  -- ★ Phase 3.9: 注入 TextContext 字段
  if #reg.texts > 0 then
    emit("")
    emit("  -- ★ Phase 3.9: 文本组件 Context（一等公民）")
    -- 共享 TextPipeline（所有文本组件共用一个管线实例）
    emit("  pipe_text: TextPipeline,")
    for _, txt in ipairs(reg.texts) do
      emit(("  %s: %sContext,"):format(txt.name, txt.base))
    end
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
  -- ★ Phase 3.10.5: 注入阴影组件的 Context + Pipeline
  if #reg.shadows > 0 then
    emit("")
    emit("  -- ★ Phase 3.10.5: 阴影组件 Context + 多 Pass 管线")
    for _, shd in ipairs(reg.shadows) do
      emit(("  %s: %sContext,"):format(shd.name, shd.base))
      emit(("  pipe_%s: %sPipeline,"):format(shd.base:lower(), shd.base))
    end
  end

  emit("")
  emit("  -- ★ Phase 3.8: FrameArena（内嵌后备内存，无堆分配）")
  emit("  arena: NebulaArena,")
  emit(("  _arena_backing: [%d]uint8,"):format(reg.arena_size))
  emit("}")

  return table.concat(L, "\n")
end

-- 生成 <App>:init
-- ★ Phase 3.8: 注入 nebula_arena_init
-- ★ Phase 3.9: 注入 TextPipeline:init（文本一等公民）
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

  -- ★ Phase 3.9: 初始化 TextPipeline（文本一等公民）
  if #reg.texts > 0 then
    emit("")
    emit("  -- ★ Phase 3.9: 初始化文本管线（一等公民）")
    emit("  if not self.pipe_text:init(renderer) then return false end")
  end

  -- ★ Phase 3.10.5: 初始化阴影管线（多 Pass）
  if #reg.shadows > 0 then
    emit("")
    emit("  -- ★ Phase 3.10.5: 初始化阴影管线（多 Pass）")
    for _, shd in ipairs(reg.shadows) do
      emit(("  if not self.pipe_%s:init(renderer, %d, %d) then return false end"):format(
        shd.base:lower(), shd.win_w, shd.win_h))
    end
  end

  emit("")
  emit("  -- ★ Phase 3.8: 初始化 FrameArena（绑定内嵌后备内存）")
  emit(("  nebula_arena_init(&self.arena, &self._arena_backing[0], %d)"):format(reg.arena_size))
  emit("  return true")
  emit("end")

  return table.concat(L, "\n")
end

-- 生成 <App>:update
-- ★ Phase 3.8: 自动调用 nebula_arena_reset
-- ★ Phase 3.9: 注入 process_text_input + set_text 联动逻辑（文本一等公民）
local function gen_app_update(app_name, reg)
  local L = {}
  local function emit(s) table.insert(L, s) end

  emit(("function %s:update(input: *NebulaInputState, dt: float32): void"):format(app_name))
  emit("  -- ★ Phase 3.8: 每帧开始时重置 Arena（O(1)，仅移动游标）")
  emit("  nebula_arena_reset(&self.arena)")
  emit("  -- 按注册顺序显式更新所有静态组件")
  for _, comp in ipairs(reg.components) do
    emit(("  self.%s:update(input, dt)"):format(comp.name))
  end

  -- ★ Phase 3.9 / Phase 3.10.5: 文本组件联动逻辑
  if #reg.texts > 0 then
    emit("")
    emit("  -- ★ Phase 3.9 / Phase 3.10.5: 文本组件联动（一等公民）")
    for _, txt in ipairs(reg.texts) do
      local mode = txt.mode or "bound"
      if mode == "bound" then
        -- 原有绑定模式：联动 editable 组件
        emit(("  -- [bound] %s 绑定到 %s（placeholder: \"%s\", mask: %s）"):format(
          txt.name, txt.bound_to, txt.placeholder, tostring(txt.mask_password)))
        emit(("  if self.%s:process_text_input(input) then"):format(txt.bound_to))
        emit(("    if self.%s:get_text_len() > 0 then"):format(txt.bound_to))
        emit(("      local _%s_buf: [256]uint8"):format(txt.name))
        emit(("      local _%s_raw = self.%s:get_text(&_%s_buf[0], 255)"):format(
          txt.name, txt.bound_to, txt.name))
        if txt.mask_password then
          emit(("      local _%s_len = self.%s:get_text_len()"):format(txt.name, txt.bound_to))
          emit(("      local _%s_mask: [256]uint8"):format(txt.name))
          emit(("      local _%s_mi: uint16 = 0"):format(txt.name))
          emit(("      while _%s_mi < _%s_len do"):format(txt.name, txt.name))
          emit(("        _%s_mask[_%s_mi] = 0x2A"):format(txt.name, txt.name))
          emit(("        _%s_mi = _%s_mi + 1"):format(txt.name, txt.name))
          emit(("      end"):format())
          emit(("      _%s_mask[_%s_len] = 0"):format(txt.name, txt.name))
          emit(("      self.%s:set_text(self.renderer, (@cstring)(&_%s_mask[0]))"):format(
            txt.name, txt.name))
        else
          emit(("      self.%s:set_text(self.renderer, _%s_raw)"):format(txt.name, txt.name))
        end
        emit(("    else"):format())
        if txt.placeholder ~= "" then
          emit(("      self.%s:set_text(self.renderer, \"%s\")"):format(txt.name, txt.placeholder))
        else
          emit(("      self.%s:set_text(self.renderer, \"\")"):format(txt.name))
        end
        emit(("    end"):format())
        emit(("  end"):format())
      elseif mode == "dynamic" then
        -- ★ Phase 3.10.5: 动态模式：每帧调用 updater 函数
        emit(("  -- [dynamic] %s 通过 %s 每帧更新"):format(txt.name, txt.updater))
        emit(("  do"):format())
        emit(("    local _%s_mark = nebula_arena_mark(&self.arena)"):format(txt.name))
        emit(("    local _%s_str = %s(&self.arena)"):format(txt.name, txt.updater))
        emit(("    if _%s_str ~= nilptr then"):format(txt.name))
        emit(("      self.%s:set_text(self.renderer, _%s_str)"):format(txt.name, txt.name))
        emit(("    end"):format())
        emit(("    nebula_arena_rewind(&self.arena, _%s_mark)"):format(txt.name))
        emit(("  end"):format())
      end
      -- static 模式：不在 update 中生成任何代码（由用户在 main 中手动调用 set_text 一次）
      if mode == "static" then
        emit(("  -- [static] %s: 静态文本，由用户在 App:init 后手动调用 set_text 初始化"):format(txt.name))
      end
    end
  end

  emit("end")

  return table.concat(L, "\n")
end

-- ★ Phase 3.10.5: 生成 <App>:draw_pre_pass（阴影离屏 Pass 1-3）
-- 仅当 App 有阴影组件时才生成此方法；否则生成一个空实现以兼容 nebula_frame_render_multipass
local function gen_app_pre_pass(app_name, reg)
  local L = {}
  local function emit(s) table.insert(L, s) end

  emit(("function %s:draw_pre_pass(encoder: WGPUCommandEncoder, renderer: *NebulaRenderer): void"):format(app_name))
  if #reg.shadows > 0 then
    emit("  -- ★ Phase 3.10.5: 阴影组件离屏 Pass（每个阴影组件执行 3 个离屏 Pass）")
    for _, shd in ipairs(reg.shadows) do
      local u_expr = ("self.%s:to_uniforms(self.vw, self.vh)"):format(shd.name)
      emit(("  -- [shadow] %s: 更新 uniforms 并执行阴影离屏渲染"):format(shd.name))
      emit(("  do"):format())
      emit(("    local _u = %s"):format(u_expr))
      emit(("    self.pipe_%s:update_uniforms(renderer, &_u)"):format(shd.base:lower()))
      emit(("    self.pipe_%s:draw_shadow(encoder, renderer, %.1f)"):format(shd.base:lower(), shd.blur_radius))
      emit(("  end"):format())
    end
  end
  emit("end")

  return table.concat(L, "\n")
end

-- ★ Phase 3.10.5: 生成 <App>:draw_surface_pass（在 Surface Pass 中合成阴影+绘制主体）
-- 仅当 App 有阴影组件时才生成此方法；否则生成一个空实现
local function gen_app_surface_pass(app_name, reg)
  local L = {}
  local function emit(s) table.insert(L, s) end

  emit(("function %s:draw_surface_pass(pass: WGPURenderPassEncoder): void"):format(app_name))
  if #reg.shadows > 0 then
    emit("  -- ★ Phase 3.10.5: 阴影合成层（先合成模糊阴影，再绘制主体）")
    for _, shd in ipairs(reg.shadows) do
      emit(("  -- [shadow] %s: 先合成阴影，再绘制主体"):format(shd.name))
      emit(("  self.pipe_%s:draw_composite(pass)"):format(shd.base:lower()))
      emit(("  self.pipe_%s:draw(pass)"):format(shd.base:lower()))
    end
  end
  emit("end")

  return table.concat(L, "\n")
end

-- 生成 <App>:draw（按类型分组 upload + draw_instanced）
-- ★ Phase 3.9: 文本管线在所有标准管线之后绘制（确保文本在最上层）
-- ★ Phase 3.9: Slot Producer 模式（mark/rewind 局部内存管理）
local function gen_app_draw(app_name, reg)
  local L = {}
  local function emit(s) table.insert(L, s) end

  emit(("function %s:draw(pass: WGPURenderPassEncoder): void"):format(app_name))

  -- 按注册顺序遍历 type_groups
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

    -- ★ Phase 3.9: 收集动态插槽数据（Producer 模式）
    for _, slot in ipairs(slot_members) do
      if slot.producer then
        -- 新 API：Producer 函数模式（原语 4）
        emit(("    -- ★ Phase 3.9: 动态插槽 %s（Producer: %s）"):format(slot.name, slot.producer))
        emit(("    do"):format())
        emit(("      local _mark = nebula_arena_mark(&self.arena)"):format())
        emit(("      local _slot_raw = nebula_arena_alloc_array(&self.arena, %d, #%s, 8)"):format(
          slot.max_instances, uniforms_record))
        emit(("      if _slot_raw ~= nilptr then"):format())
        emit(("        local _slot_data = (@*[0]%s)(_slot_raw)"):format(uniforms_record))
        emit(("        local _slot_count: uint32 = 0"):format())
        emit(("        %s(&self.arena, _slot_data, &_slot_count, %d)"):format(
          slot.producer, slot.max_instances))
        emit(("        local _si: uint32 = 0"):format())
        emit(("        while _si < _slot_count and _count < %d do"):format(max_inst))
        emit(("          _batch[_count] = _slot_data[_si]"):format())
        emit(("          _count = _count + 1"):format())
        emit(("          _si = _si + 1"):format())
        emit(("        end"):format())
        emit(("      end"):format())
        emit(("      nebula_arena_rewind(&self.arena, _mark)"):format())
        emit(("    end"):format())
      elseif slot.legacy_count_var and slot.legacy_data_var then
        -- 旧 API：外部全局变量模式（向后兼容）
        emit(("    -- [legacy] 动态插槽 %s（外部变量: %s/%s）"):format(
          slot.name, slot.legacy_count_var, slot.legacy_data_var))
        emit(("    local _si: uint32 = 0"):format())
        emit(("    while _si < %s and _count < %d do"):format(slot.legacy_count_var, max_inst))
        emit(("      _batch[_count] = %s[_si]"):format(slot.legacy_data_var))
        emit(("      _count = _count + 1"):format())
        emit(("      _si = _si + 1"):format())
        emit(("    end"):format())
      end
    end

    -- upload + draw_instanced
    emit(("    if _count > 0 then"):format())
    emit(("      %s:upload(self.renderer, &_batch[0], _count)"):format(pipe_var))
    emit(("      %s:draw_instanced(pass, _count)"):format(pipe_var))
    emit(("    end"):format())
    emit(("  end"):format())

    ::continue::
  end

  -- ★ Phase 3.9: 文本管线在最后绘制（确保文本始终在最上层）
  if #reg.texts > 0 then
    emit("")
    emit("  -- ★ Phase 3.9: 文本渲染（一等公民，最后绘制确保在最上层）")
    for _, txt in ipairs(reg.texts) do
      emit(("  if self.%s.mesh.vertex_count > 0 then"):format(txt.name))
      emit(("    self.pipe_text:draw_buffer(pass,"):format())
      emit(("      self.%s.mesh.vertex_buffer,"):format(txt.name))
      emit(("      self.%s.mesh.vertex_buffer_size,"):format(txt.name))
      emit(("      self.%s.mesh.vertex_count)"):format(txt.name))
      emit(("  end"):format())
    end
  end

  emit("end")

  return table.concat(L, "\n")
end

-- =============================================================================
-- 主入口：nebula_app_generate(app_name)
-- =============================================================================
function nebula_app_generate(app_name)
  local reg = nebula_app_registry[app_name]
  assert(reg, ("nebula_derive_app: app '%s' not registered. Call nebula_app_begin/end first."):format(app_name))

  local parts = {
    gen_app_record(app_name, reg),
    gen_app_init(app_name, reg),
    gen_app_update(app_name, reg),
    gen_app_draw(app_name, reg),
    -- ★ Phase 3.10.5: 多 Pass 渲染支持
    gen_app_pre_pass(app_name, reg),
    gen_app_surface_pass(app_name, reg),
  }

  local source = table.concat(parts, "\n\n")

  local text_count = #reg.texts
  local slot_producer_count = 0
  for _, slot in ipairs(reg.slots) do
    if slot.producer then slot_producer_count = slot_producer_count + 1 end
  end

  print((("[derive-app] %s: emit App record + init + update + draw + pre_pass + surface_pass (%d components, %d texts, %d slots [%d producer], %d shadows, %d type_groups, arena=%dB)"):format(
    app_name,
    #reg.components,
    text_count,
    #reg.slots,
    slot_producer_count,
    #reg.shadows,
    (function()
      local n = 0
      for _ in pairs(reg.type_groups) do n = n + 1 end
      return n
    end)(),
    reg.arena_size
  )))

  return source
end

return "nebula_app_factory_v0.4_phase3.10.5"
