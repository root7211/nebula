-- =============================================================================
-- derive/app_factory.lua — Nebula GUI Compiler Phase 4.8-NL / P1-5
--
-- 编译期显式编排工厂（App Factory）
-- 生成 <App> record + init + update + draw
--
-- ★ P1-5: 组件类别抽象（NEBULA_CATEGORIES 注册表）
-- 新增组件类别仅需调用 nebula_register_category() 注册，
-- 无需修改 gen_app_record/init/update/draw/deinit 等 5 个函数。
--
-- ★ P2-8: 编译期默认值通过 nebula_config.lua 集中管理
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
-- ★ Phase 4.7-S2 新增：
--   · nebula_app_register_dense_text — DenseText 管线接入 App 编排
-- ★ Phase 4.7-S3 新增：
--   · DenseText 组件参与 Flexbox 布局解算（行号栏 + 编辑区并排）
-- ★ Phase 3.11 新增（原语 7：Layout-App 桥接）：
--   · nebula_app_set_root_layout(app_name, spec) — 声明根节点布局约束
--   · nebula_app_register_component 扩展：opts.layout 字段携带布局约束
-- ★ Phase 4.8-NL 新增：
--   · nebula_app_register_layout_node — 纯布局容器注册（无 GPU 管线）
--   · layout.container ref 拓扑：组件通过 ref 引用表达嵌套容器关系
--   · _build_container_node — 递归构建容器节点
--   · _solve_layout 改造：从平铺挂载→拓扑感知挂载
-- =============================================================================

-- 全局应用注册表（导出为全局，供测试和 nebula_derive_app 访问）
nebula_app_registry = nebula_app_registry or {}

-- ★ P2-8: 加载编译期配置常量
-- pcall 兼容两种加载路径：Nelua 预处理器（-L src）和 plain Lua 烟雾测试（dofile from repo root）
local _cfg_ok, _cfg = pcall(require, "derive.nebula_config")
if not _cfg_ok then
  local _this_dir = debug.getinfo(1, "S").source:match("^@(.+/)") or ""
  _cfg = dofile(_this_dir .. "nebula_config.lua")
end

-- ★ Phase 5.0 S1a: 延迟加载全知图构建模块（仅在需要时加载，避免影响无状态 App）
local _OmniscientGraph
local function _load_omniscient_graph()
  if _OmniscientGraph then return _OmniscientGraph end
  local ok, mod = pcall(require, "derive.omniscient_graph")
  if ok then
    _OmniscientGraph = mod
  else
    local _this_dir = debug.getinfo(1, "S").source:match("^@(.+/)") or ""
    _OmniscientGraph = dofile(_this_dir .. "omniscient_graph.lua")
  end
  return _OmniscientGraph
end

-- ★ Phase 5.0 S2: 延迟加载 binding_factory 模块
local _BindingFactory
local function _load_binding_factory()
  if _BindingFactory then return _BindingFactory end
  local ok, mod = pcall(require, "derive.binding_factory")
  if ok then
    _BindingFactory = mod
  else
    local _this_dir = debug.getinfo(1, "S").source:match("^@(.+/)") or ""
    _BindingFactory = dofile(_this_dir .. "binding_factory.lua")
  end
  return _BindingFactory
end

-- ★ Phase 5.0 S2: 延迟加载 MutationAST + EffectModel（供 omniscient_graph.build 使用）
local _MutationAST
local function _load_mutation_ast()
  if _MutationAST then return _MutationAST end
  local ok, mod = pcall(require, "derive.mutation_ast")
  if ok then
    _MutationAST = mod
  else
    local _this_dir = debug.getinfo(1, "S").source:match("^@(.+/)") or ""
    _MutationAST = dofile(_this_dir .. "mutation_ast.lua")
  end
  return _MutationAST
end

local _EffectModel
local function _load_effect_model()
  if _EffectModel then return _EffectModel end
  local ok, mod = pcall(require, "derive.effect_model")
  if ok then
    _EffectModel = mod
  else
    local _this_dir = debug.getinfo(1, "S").source:match("^@(.+/)") or ""
    _EffectModel = dofile(_this_dir .. "effect_model.lua")
  end
  return _EffectModel
end

-- 当前正在构建的 App 名称
local _current_app = nil

-- ★ Phase 4.7-S2: 辅助函数——从 visual_type 提取 base 名
local function _extract_base(visual_type)
  if visual_type:sub(-#"Visual") == "Visual" then
    return visual_type:sub(1, #visual_type - #"Visual")
  end
  return visual_type
end

-- ★ Phase 3.11: 预注册根布局配置（允许在 nebula_app_begin 之前调用 nebula_app_set_root_layout）
local _pending_root_layouts = {}

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
    components  = {},  -- 静态组件列表：{name, visual_type, base, component_id, layout}
    slots       = {},  -- 动态插槽列表：{name, visual_type, base, max_instances, producer}
    texts       = {},  -- ★ Phase 3.9: 文本组件列表：{name, visual_type, base, mode, bound_to, placeholder, mask_password, updater}
    dense_texts = {},  -- ★ Phase 4.7-S2: DenseText 组件列表：{name, visual_type, base, max_chars, cell_w, cell_h, producer}
    shadows     = {},  -- ★ Phase 3.10.5: 阴影组件列表：{name, visual_type, base, blur_radius}
    layout_nodes = {}, -- ★ Phase 4.8-NL: 纯布局容器列表：{name, layout}
    _layout_order = 0, -- ★ Phase 4.8-NL: 布局注册顺序计数器
    -- 按 visual_type 分组，用于生成共享 Pipeline
    type_groups = {},  -- {visual_type -> {pipeline_name, base, members=[{name, is_slot}]}}
    -- ★ Phase 3.8: FrameArena 配置
    arena_size  = opts.arena_size or (2 * 1024 * 1024),  -- 默认 2MB
    -- ★ Phase 3.11: 布局根节点配置（如果已预注册则合并）
    root_layout = _pending_root_layouts[app_name] or nil,
    layout_results = nil, -- nebula_app_end 时解算完成后填充
  }
  -- 清除预注册表中的对应条目
  _pending_root_layouts[app_name] = nil
end

-- ★ Phase 3.11: 声明 App 的根节点布局约束
-- 可在 nebula_app_begin 之前或之后调用。
-- spec 字段与 nebula_layout_node 完全一致：
--   direction  : "row" | "column"  (默认 "column")
--   justify    : "start" | "center" | "end" | "space_between" | "space_around"
--   align      : "start" | "center" | "end" | "stretch"
--   padding    : number | {top, right, bottom, left}
--   gap        : number
--   width      : number（默认 = 视口宽度，由 nebula_layout_solve 传入）
--   height     : number（默认 = 视口高度）
function nebula_app_set_root_layout(app_name, spec)
  assert(app_name, "nebula_app_set_root_layout: app_name required")
  -- 如果 App 已注册，直接设置；否则暂存到预注册表
  local reg = nebula_app_registry[app_name]
  if reg then
    reg.root_layout = spec or {}
  else
    _pending_root_layouts[app_name] = spec or {}
  end
end

-- 注册一个静态组件
-- opts:
--   name         : string  — 组件实例名（如 "card", "email_input"）
--   visual_type  : string  — Visual 类型名（如 "CardVisual", "InputVisual"）
--   component_id : number  — focusable 组件的 ID（可选，默认 0）
--   layout       : table   — ★ Phase 3.11: 布局约束（可选）
--     direction  : "row" | "column"
--     justify    : "start" | "center" | "end" | "space_between" | "space_around"
--     align      : "start" | "center" | "end" | "stretch"
--     padding    : number | {top, right, bottom, left}
--     gap        : number
--     width      : number
--     height     : number
--     children   : table — 嵌套子布局节点（用于容器组件）
function nebula_app_register_component(name, visual_type, opts)
  assert(_current_app, "nebula_app_register_component: must be called between nebula_app_begin and nebula_app_end")
  opts = opts or {}
  local reg = nebula_app_registry[_current_app]
  local base = _extract_base(visual_type)

  table.insert(reg.components, {
    name         = name,
    visual_type  = visual_type,
    base         = base,
    component_id = opts.component_id or 0,
    -- 以下字段为 Phase 3.8 遗留，Phase 3.9 由 nebula_app_register_text 接管
    has_text_buf = opts.has_text_buf or false,
    text_context = opts.text_context or nil,
    -- ★ Phase 3.11: 布局约束
    layout       = opts.layout or nil,
    -- ★ BUG-3 fix: 从 nebula_registry 查询该 visual_type 声明的 primitives，
    -- 使 Phase 4.3 process_body 公理校验能正确触发
    prims        = (nebula_registry and nebula_registry[visual_type] and nebula_registry[visual_type].primitives) or {},
    -- ★ Phase 4.8-NL: 布局注册顺序
    _layout_seq  = opts.layout and (function() reg._layout_order = reg._layout_order + 1; return reg._layout_order end)() or nil,
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
  -- ★ P2-5 fix: 复用 _extract_base helper（消除内联重复）
  local base = _extract_base(visual_type)

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
    -- ★ Phase 4.1: 渲染模式（"ascii_sdf" | "slug"）
    text_mode     = opts.text_mode or "ascii_sdf",
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
  -- ★ P2-5 fix: 复用 _extract_base helper（消除内联重复）
  local base = _extract_base(visual_type)

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
    -- ★ Phase 5.0: slot layout（可选，自动定位）
    layout        = opts.layout or nil,
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
  -- ★ P2-5 fix: 复用 _extract_base helper（消除内联重复）
  local base = _extract_base(visual_type)

  table.insert(reg.shadows, {
    name         = name,
    visual_type  = visual_type,
    base         = base,
    blur_radius  = opts.blur_radius or 8.0,
    win_w        = opts.win_w or _cfg.DEFAULT_VIEWPORT_WIDTH,
    win_h        = opts.win_h or _cfg.DEFAULT_VIEWPORT_HEIGHT,
  })
end

-- ★ Phase 4.7-S2: 注册一个 DenseText 渲染组件（高密度文本管线）
--
-- 将 Phase 4.X 的 DenseText 管线接入 App 编排层。
-- App 自动管理 DenseText 管线的生命周期（init/deinit），
-- 并在每帧调用 producer 函数填充 DenseCharInstance 数组后 upload + draw。
--
-- visual_type 必须通过 nebula_annotate + nebula_derive 以 text_mode="dense" 预先派生，
-- 以确保 <Base>DenseTextPipeline 类型已生成。
--
-- opts:
--   max_chars : number  — 最大字符数（默认 6000）
--   cell_w    : number  — 单元格宽度（像素，默认 10.0）
--   cell_h    : number  — 单元格高度（像素，默认 16.0）
--   producer  : string  — 帧级 Producer 函数名
--                         签名：function(app: *<App>, instances: *[0]DenseCharInstance, count: *uint32, max: uint32): void
--                         职责：从 App 状态（如 multi_buf）读取文本内容，填充 DenseCharInstance 数组
function nebula_app_register_dense_text(name, visual_type, opts)
  assert(_current_app, "nebula_app_register_dense_text: must be called between nebula_app_begin and nebula_app_end")
  opts = opts or {}
  local reg = nebula_app_registry[_current_app]
  local base = _extract_base(visual_type)

  assert(opts.producer, ("nebula_app_register_dense_text: '%s' requires opts.producer"):format(name))

  table.insert(reg.dense_texts, {
    name        = name,
    visual_type = visual_type,
    base        = base,
    max_chars   = opts.max_chars or _cfg.DEFAULT_MAX_DENSE_CHARS,
    cell_w      = opts.cell_w or _cfg.DEFAULT_CELL_W,
    cell_h      = opts.cell_h or _cfg.DEFAULT_CELL_H,
    producer    = opts.producer,
    layout      = opts.layout or nil,  -- ★ Phase 4.7-S3: 布局约束
    -- ★ Phase 4.8-NL: 布局注册顺序
    _layout_seq = opts.layout and (function() reg._layout_order = reg._layout_order + 1; return reg._layout_order end)() or nil,
  })
end

-- ★ Phase 4.8-NL: 注册一个纯布局容器节点（无 GPU 管线）
--
-- 容器节点仅参与布局解算，不产生任何 GPU 资源。
-- 通过 layout.container ref 数组声明子节点拓扑。
--
-- name   : string  — 容器名（如 "editor_body"）
-- layout : table   — 布局约束 + container ref 数组
--   direction  : "row" | "column"
--   flex_grow  : number
--   flex_basis : number
--   container  : { {ref="child1"}, {ref="child2"}, ... }
function nebula_app_register_layout_node(name, layout)
  assert(_current_app, "nebula_app_register_layout_node: must be called between nebula_app_begin and nebula_app_end")
  assert(layout, ("nebula_app_register_layout_node: '%s' requires layout"):format(name))
  assert(layout.container, ("nebula_app_register_layout_node: '%s' requires layout.container"):format(name))
  local reg = nebula_app_registry[_current_app]
  reg._layout_order = reg._layout_order + 1
  table.insert(reg.layout_nodes, {
    name       = name,
    layout     = layout,
    _layout_seq = reg._layout_order,
  })
end

-- =============================================================================
-- ★ Phase 5.0 S1a: 全知图注册 API
-- =============================================================================

--- 声明一个可变状态。
--- 在 nebula_app_end 时，所有 states/bindings/events 一起构建全知图。
---
--- @param name string 状态名（如 "count"）
--- @param config table 配置：{type, default}
function nebula_state(name, config)
  assert(_current_app, "nebula_state: must be called between nebula_app_begin and nebula_app_end")
  assert(name, "nebula_state: name required")
  config = config or {}
  local reg = nebula_app_registry[_current_app]
  if not reg._states then reg._states = {} end
  assert(not reg._states[name],
    ("nebula_state: state '%s' already declared in app '%s'"):format(name, _current_app))
  reg._states[name] = {
    name    = name,
    type    = config.type or "int32",
    default = config.default,
  }
end

--- 声明一个绑定（派生状态）。
--- 当 depends 中的状态变化时，compute 函数重新计算 target 的值。
---
--- @param target string 绑定目标状态名（如 "label_text"）
--- @param config table 配置：{depends, compute, affects}
function nebula_bind(target, config)
  assert(_current_app, "nebula_bind: must be called between nebula_app_begin and nebula_app_end")
  assert(target, "nebula_bind: target required")
  config = config or {}
  local reg = nebula_app_registry[_current_app]
  if not reg._bindings then reg._bindings = {} end
  -- 检查重复
  for _, b in ipairs(reg._bindings) do
    assert(b.target ~= target,
      ("nebula_bind: binding target '%s' already declared in app '%s'"):format(target, _current_app))
  end
  table.insert(reg._bindings, {
    target  = target,
    depends = config.depends or {},
    compute = config.compute,
    affects = config.affects,
    type    = config.type,  -- ★ Phase 5.0 S2: 派生状态类型（默认 int32）
  })
end

--- 声明一个事件处理。
--- 指定组件的事件类型及对应的 mutation 代码。
---
--- @param target string 目标组件名（如 "button"）
--- @param event_type string 事件类型（如 "click"）
--- @param config table 配置：{mutation}
function nebula_on(target, event_type, config)
  assert(_current_app, "nebula_on: must be called between nebula_app_begin and nebula_app_end")
  assert(target, "nebula_on: target required")
  assert(event_type, "nebula_on: event_type required")
  config = config or {}
  local reg = nebula_app_registry[_current_app]
  if not reg._events then reg._events = {} end
  table.insert(reg._events, {
    target     = target,
    event_type = event_type,
    mutation   = config.mutation,
  })
end

-- ★ Phase 3.11: 内部辅助函数 — 将组件的 layout 字段转换为 layout_engine 节点
-- 递归处理 layout.children（允许容器组件声明嵌套布局）
local function _build_layout_node(name, layout_spec)
  local spec = {
    name      = name,
    direction = layout_spec.direction,
    justify   = layout_spec.justify,
    align     = layout_spec.align,
    padding   = layout_spec.padding,
    gap       = layout_spec.gap,
    width      = layout_spec.width,
    height     = layout_spec.height,
    flex_grow  = layout_spec.flex_grow,    -- ★ Phase 4.7-S3
    flex_basis = layout_spec.flex_basis,   -- ★ Phase 4.7-S3
    children   = {},
  }
  -- 递归处理子节点
  if layout_spec.children then
    for _, child_spec in ipairs(layout_spec.children) do
      assert(child_spec.name, "_build_layout_node: child layout node must have a name")
      table.insert(spec.children, _build_layout_node(child_spec.name, child_spec))
    end
  end
  return nebula_layout_node(spec)
end

-- ★ Phase 4.8-NL: 递归构建容器节点
-- 容器节点通过 layout.container 的 ref 字段引用子组件。
-- 被引用的子组件如果自身也有 container 字段，则递归构建嵌套容器。
local function _build_container_node(name, layout_spec, comp_map)
  local spec = {
    name       = name,
    direction  = layout_spec.direction,
    justify    = layout_spec.justify,
    align      = layout_spec.align,
    padding    = layout_spec.padding,
    gap        = layout_spec.gap,
    width      = layout_spec.width,
    height     = layout_spec.height,
    flex_grow  = layout_spec.flex_grow,
    flex_basis = layout_spec.flex_basis,
    children   = {},
  }
  for _, child_ref in ipairs(layout_spec.container) do
    local ref_name = child_ref.ref
    local child_comp = comp_map[ref_name]
    assert(child_comp, ("_build_container_node: container '%s' ref '%s' not found"):format(name, ref_name))
    if child_comp.layout and child_comp.layout.container then
      -- 嵌套容器
      table.insert(spec.children, _build_container_node(ref_name, child_comp.layout, comp_map))
    else
      -- 普通叶子节点
      table.insert(spec.children, _build_layout_node(ref_name, child_comp.layout))
    end
  end
  return nebula_layout_node(spec)
end

-- ★ Phase 3.12: 内部辅助函数 — 在 nebula_app_end 时执行布局解算（升级为分段系数推导）
-- 如果 reg.root_layout 存在，则构建布局树并解算，将结果存入 reg.layout_results。
-- ★ Phase 3.12 升级：额外调用 nebula_layout_derive_segments 推导分段系数，
--   存入 reg.layout_segments，供 gen_app_update 生成响应式更新代码。
local function _solve_layout(reg)
  if not reg.root_layout then
    reg.layout_results  = nil
    reg.layout_segments = nil
    return
  end

  -- 构建根节点规格（不带 name，因为根节点本身不对应任何组件）
  local root_spec = {
    name      = "_root",
    direction = reg.root_layout.direction or "column",
    justify   = reg.root_layout.justify   or "center",
    align     = reg.root_layout.align     or "center",
    padding   = reg.root_layout.padding   or 0,
    gap       = reg.root_layout.gap       or 0,
    width     = reg.root_layout.width,
    height    = reg.root_layout.height,
    children  = {},
  }

  -- ★ Phase 4.8-NL: 构建组件索引 + 拓扑感知挂载
  -- 收集所有参与布局的节点
  local comp_map = {}
  for _, comp in ipairs(reg.components) do
    if comp.layout then comp_map[comp.name] = comp end
  end
  for _, dt in ipairs(reg.dense_texts) do
    if dt.layout then comp_map[dt.name] = dt end
  end
  for _, ln in ipairs(reg.layout_nodes or {}) do
    comp_map[ln.name] = ln
  end

  -- 标记被 container ref 引用的节点（不直接挂载到 root）
  local used_as_child = {}
  for _, item in pairs(comp_map) do
    if item.layout and item.layout.container then
      for _, child_ref in ipairs(item.layout.container) do
        used_as_child[child_ref.ref] = true
      end
    end
  end

  -- 挂载到 root（排除被容器引用的节点）
  -- ★ Phase 4.8-NL: 按 _layout_seq 维持原始注册顺序
  local mount_list = {}
  for name, item in pairs(comp_map) do
    if not used_as_child[name] then
      table.insert(mount_list, { name = name, item = item, seq = item._layout_seq or 0 })
    end
  end
  table.sort(mount_list, function(a, b) return a.seq < b.seq end)
  for _, entry in ipairs(mount_list) do
    local item = entry.item
    if item.layout and item.layout.container then
      table.insert(root_spec.children, _build_container_node(entry.name, item.layout, comp_map))
    else
      table.insert(root_spec.children, _build_layout_node(entry.name, item.layout))
    end
  end

  if #root_spec.children == 0 then
    reg.layout_results  = nil
    reg.layout_segments = nil
    return
  end

  -- 使用 root_layout 指定的视口尺寸，或默认 800x600
  local base_vw = reg.root_layout.width  or _cfg.DEFAULT_VIEWPORT_WIDTH
  local base_vh = reg.root_layout.height or _cfg.DEFAULT_VIEWPORT_HEIGHT

  -- ★ Phase 3.11: 保留单次解算结果（用于 init 中的初始坐标注入）
  local root = nebula_layout_node(root_spec)
  nebula_layout_solve(root, base_vw, base_vh)
  if _DEBUG_LAYOUT then
    print((("[layout] Phase 3.11 — App '%s' layout solved:"):format(reg.name)))
    nebula_layout_dump(root)
  end
  reg.layout_results = nebula_layout_collect(root)

  -- ★ Phase 3.12: 分段系数推导（用于 update 中的响应式更新代码生成）
  reg.layout_segments = nebula_layout_derive_segments(root_spec, base_vw, base_vh)
  if _DEBUG_LAYOUT then
    local segs = reg.layout_segments.segments
    print((("[layout] Phase 3.12 — App '%s' derived %d segments:"):format(reg.name, #segs)))
    for i, seg in ipairs(segs) do
      local th = seg.threshold_h and tostring(seg.threshold_h) or "nil"
      local tw = seg.threshold_w and tostring(seg.threshold_w) or "nil"
      print((("  segment %d: threshold_h=%s threshold_w=%s"):format(i, th, tw)))
    end
  end
end

-- 结束 App 声明
-- ★ Phase 3.11: 在 end 时自动执行布局解算
-- ★ Phase 5.0 S1a: 在 end 时构建全知图
function nebula_app_end()
  assert(_current_app, "nebula_app_end: no app currently being declared")
  local reg = nebula_app_registry[_current_app]
  -- ★ Phase 3.11: 自动解算布局
  _solve_layout(reg)
  -- ★ Phase 5.0 S2: 如果有 states/bindings/events 声明，构建全知图（带 AST + Effect 分析）
  if reg._states or reg._bindings or reg._events then
    reg._omniscient_graph = _load_omniscient_graph().build(reg, {
      MutationAST = _load_mutation_ast(),
      EffectModel = _load_effect_model(),
    })
  end
  _current_app = nil
end

-- =============================================================================
-- ★ P1-5: 组件类别抽象（NEBULA_CATEGORIES）
--
-- 数据驱动的组件类别系统。每个类别注册 6 个可选 hook：
--   emit_record(reg, emit)        — 生成 App record 中该类别的字段
--   emit_init(reg, emit)          — 生成 App:init 中该类别的初始化代码
--   emit_update(reg, emit)        — 生成 App:update 中该类别的更新逻辑
--   emit_draw(reg, emit)          — 生成 App:draw 中该类别的绘制代码
--   emit_deinit(reg, emit)        — 生成 App:deinit 中该类别的资源释放
--   emit_pre_pass(reg, emit)      — 生成离屏预渲染 Pass（仅阴影类别使用）
--   emit_surface_pass(reg, emit)  — 生成 Surface Pass 合成（仅阴影类别使用）
--
-- 新增组件类别仅需调用 nebula_register_category() 注册，
-- 无需修改 gen_app_record/init/update/draw/deinit 等 5 个函数。
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 类别 1: standard（静态组件 + 动态插槽，共享 type_groups 管线）
-- ---------------------------------------------------------------------------
local function _emit_record_standard(reg, emit)
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
end

local function _emit_init_standard(reg, emit)
  emit("  -- 初始化所有 Pipeline")
  local inited_pipes = {}
  for vt, group in pairs(reg.type_groups) do
    if not inited_pipes[group.pipeline_name] then
      local max_inst = 0
      for _, m in ipairs(group.members) do
        if not m.is_slot then max_inst = max_inst + 1 end
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
end

local function _emit_update_standard(reg, emit)
  emit("  -- 按注册顺序显式更新所有静态组件")
  for _, comp in ipairs(reg.components) do
    emit(("  self.%s:update(input, dt)"):format(comp.name))
  end
end

local function _emit_draw_standard(reg, emit)
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

    local static_members = {}
    for _, m in ipairs(group.members) do
      if not m.is_slot then table.insert(static_members, m.name) end
    end

    local slot_members = {}
    for _, slot in ipairs(reg.slots) do
      if slot.visual_type == vt then table.insert(slot_members, slot) end
    end

    local max_inst = #static_members
    for _, slot in ipairs(slot_members) do
      max_inst = max_inst + slot.max_instances
    end
    if max_inst == 0 then goto continue end

    local uniforms_record = group.base .. "Uniforms"
    local pipe_var = "self.pipe_" .. group.base:lower()

    local STACK_BATCH_LIMIT = _cfg.STACK_BATCH_LIMIT

    emit(("  -- 批量绘制 %s（%d 静态 + %d 动态插槽）"):format(
      vt, #static_members, #slot_members))
    emit("  do")
    if max_inst > STACK_BATCH_LIMIT then
      emit(("    -- MEM-3: max_inst=%d 超过栈安全阈值 %d，使用分批模式"):format(max_inst, STACK_BATCH_LIMIT))
      emit(("    local _batch: [%d]%s"):format(STACK_BATCH_LIMIT, uniforms_record))
    else
      emit(("    local _batch: [%d]%s"):format(max_inst, uniforms_record))
    end
    emit("    local _count: uint32 = 0")

    for _, name in ipairs(static_members) do
      emit(("    _batch[_count] = self.%s:to_uniforms(self.vw, self.vh)"):format(name))
      emit("    _count = _count + 1")
    end

    for _, slot in ipairs(slot_members) do
      if slot.producer then
        emit(("    -- ★ Phase 3.9: 动态插槽 %s（Producer: %s）"):format(slot.name, slot.producer))
        emit("    do")
        emit("      local _mark = nebula_arena_mark(&self.arena)")
        emit(("      local _slot_raw = nebula_arena_alloc_array(&self.arena, %d, #%s, 8)"):format(
          slot.max_instances, uniforms_record))
        emit("      if _slot_raw ~= nilptr then")
        emit(("        local _slot_data = (@*[0]%s)(_slot_raw)"):format(uniforms_record))
        emit("        local _slot_count: uint32 = 0")
        emit(("        %s(&self.arena, _slot_data, &_slot_count, %d)"):format(
          slot.producer, slot.max_instances))
        -- ★ Phase 5.0: slot layout auto-position
        if slot.layout then
          local lo = slot.layout
          local dir = lo.direction or "column"
          local gap = lo.gap or 0
          local pad = lo.padding or 0
          local pad_x, pad_y
          if type(pad) == "table" then
            pad_x = pad.left or pad[2] or 0
            pad_y = pad.top  or pad[1] or 0
          else
            pad_x = pad
            pad_y = pad
          end
          local iw = lo.item_size and lo.item_size.w or 100
          local ih = lo.item_size and lo.item_size.h or 40
          local stride = dir == "column" and (ih + gap) or (iw + gap)
          local scroll_expr = lo.scroll_var or "0.0"
          emit(("        -- ★ Phase 5.0: slot layout (dir=%s, gap=%g, stride=%g)"):format(dir, gap, stride))
          emit("        do")
          emit("          local _li: uint32 = 0")
          emit("          while _li < _slot_count do")
          if dir == "column" then
            emit(("            _slot_data[_li].pos = Vec2{ x = %.1f, y = %.1f + (@float32)(_li) * %.1f - %s }"):format(
              pad_x, pad_y, stride, scroll_expr))
          else
            emit(("            _slot_data[_li].pos = Vec2{ x = %.1f + (@float32)(_li) * %.1f - %s, y = %.1f }"):format(
              pad_x, stride, scroll_expr, pad_y))
          end
          emit(("            _slot_data[_li].size = Vec2{ x = %.1f, y = %.1f }"):format(iw, ih))
          emit("            _li = _li + 1")
          emit("          end")
          emit("        end")
        end
        emit(("        local _si: uint32 = 0"):format())
        emit(("        while _si < _slot_count and _count < %d do"):format(max_inst))
        emit("          _batch[_count] = _slot_data[_si]")
        emit("          _count = _count + 1")
        emit("          _si = _si + 1")
        emit("        end")
        emit("      end")
        emit("      nebula_arena_rewind(&self.arena, _mark)")
        emit("    end")
      elseif slot.legacy_count_var and slot.legacy_data_var then
        emit(("    -- [legacy] 动态插槽 %s（外部变量: %s/%s）"):format(
          slot.name, slot.legacy_count_var, slot.legacy_data_var))
        emit("    local _si: uint32 = 0")
        emit(("    while _si < %s and _count < %d do"):format(slot.legacy_count_var, max_inst))
        emit(("      _batch[_count] = %s[_si]"):format(slot.legacy_data_var))
        emit("      _count = _count + 1")
        emit("      _si = _si + 1")
        emit("    end")
      end
    end

    emit("    if _count > 0 then")
    emit(("      %s:upload(self.renderer, &_batch[0], _count)"):format(pipe_var))
    emit(("      %s:draw_instanced(pass, _count)"):format(pipe_var))
    emit("    end")
    emit("  end")

    ::continue::
  end
end

local function _emit_deinit_standard(reg, emit)
  local deinited_pipes = {}
  for _, group in pairs(reg.type_groups) do
    if not deinited_pipes[group.pipeline_name] then
      emit(("  self.pipe_%s:deinit()"):format(group.base:lower()))
      deinited_pipes[group.pipeline_name] = true
    end
  end
end

-- ---------------------------------------------------------------------------
-- 类别 2: texts（文本组件，SDF + Slug 管线）
-- ---------------------------------------------------------------------------
local function _emit_record_texts(reg, emit)
  if #reg.texts == 0 then return end
  emit("")
  emit("  -- ★ Phase 3.9 / Phase 4.1: 文本组件 Context（一等公民）")
  local has_sdf_txt  = false
  local has_slug_txt = false
  for _, txt in ipairs(reg.texts) do
    if txt.text_mode == "slug" then has_slug_txt = true
    else has_sdf_txt = true end
  end
  if has_sdf_txt  then emit("  pipe_text: TextPipeline,") end
  if has_slug_txt then emit("  pipe_slug_text: SlugTextPipeline,") end
  for _, txt in ipairs(reg.texts) do
    emit(("  %s: %sContext,"):format(txt.name, txt.base))
  end
end

local function _emit_init_texts(reg, emit)
  if #reg.texts == 0 then return end
  local has_sdf_init  = false
  local has_slug_init = false
  for _, txt in ipairs(reg.texts) do
    if txt.text_mode == "slug" then has_slug_init = true
    else has_sdf_init = true end
  end
  emit("")
  emit("  -- ★ Phase 3.9 / Phase 4.1: 初始化文本管线")
  if has_sdf_init then
    emit("  if not self.pipe_text:init(renderer) then return false end")
  end
  if has_slug_init then
    emit("  if not self.pipe_slug_text:init(renderer) then return false end")
    emit("  -- ★ Phase 4.1: 上传 Slug Storage Buffer（编译期常量数组）")
    emit("  do")
    emit("    local _curves_sz = (@csize)(NEBULA_SLUG_TOTAL_CURVES * #NebulaSlugCurve)")
    emit("    local _metas_sz  = (@csize)(NEBULA_SLUG_TOTAL_BAND_METAS * #NebulaSlugBandMeta)")
    emit("    local _refs_sz   = (@csize)(NEBULA_SLUG_TOTAL_BAND_REFS * #uint16)")
    emit("    if not self.pipe_slug_text:upload_slug_buffers(renderer,")
    emit("      &NEBULA_SLUG_CURVES[0], _curves_sz,")
    emit("      &NEBULA_SLUG_BAND_METAS[0], _metas_sz,")
    emit("      &NEBULA_SLUG_BAND_REFS[0], _refs_sz) then return false end")
    emit("    if not self.pipe_slug_text:update_slug_bind_group(renderer) then return false end")
    emit("  end")
  end
end

local function _emit_update_texts(reg, emit)
  if #reg.texts == 0 then return end
  emit("")
  emit("  -- ★ Phase 3.9 / Phase 3.10.5: 文本组件联动（一等公民）")
  for _, txt in ipairs(reg.texts) do
    local mode = txt.mode or "bound"
    if mode == "bound" then
      emit(("  -- [bound] %s 绑定到 %s（placeholder: \"%s\", mask: %s）"):format(
        txt.name, txt.bound_to, txt.placeholder, tostring(txt.mask_password)))
      emit(("  if self.%s:process_text_input(input) then"):format(txt.bound_to))
      emit(("    if self.%s:get_text_len() > 0 then"):format(txt.bound_to))
      emit(("      local _%s_buf: [256]uint8"):format(txt.name))
      emit(("      local _%s_raw = self.%s:get_text(&_%s_buf[0], 255)"):format(
        txt.name, txt.bound_to, txt.name))
      if txt.mask_password then
        emit(("      local _%s_len = self.%s:get_text_len()"):format(txt.name, txt.bound_to))
        emit(("      if _%s_len > 255 then _%s_len = 255 end"):format(txt.name, txt.name))
        emit(("      local _%s_mask: [256]uint8"):format(txt.name))
        emit(("      local _%s_mi: uint16 = 0"):format(txt.name))
        emit(("      while _%s_mi < _%s_len do"):format(txt.name, txt.name))
        emit(("        _%s_mask[_%s_mi] = 0x2A"):format(txt.name, txt.name))
        emit(("        _%s_mi = _%s_mi + 1"):format(txt.name, txt.name))
        emit("      end")
        emit(("      _%s_mask[_%s_len] = 0"):format(txt.name, txt.name))
        emit(("      self.%s:set_text(self.renderer, (@cstring)(&_%s_mask[0]))"):format(
          txt.name, txt.name))
      else
        emit(("      self.%s:set_text(self.renderer, _%s_raw)"):format(txt.name, txt.name))
      end
      emit("    else")
      if txt.placeholder ~= "" then
        emit(("      self.%s:set_text(self.renderer, \"%s\")"):format(txt.name, txt.placeholder))
      else
        emit(("      self.%s:set_text(self.renderer, \"\")"):format(txt.name))
      end
      emit("    end")
      emit("  end")
    elseif mode == "dynamic" then
      emit(("  -- [dynamic] %s 通过 %s 每帧更新"):format(txt.name, txt.updater))
      emit("  do")
      emit(("    local _%s_mark = nebula_arena_mark(&self.arena)"):format(txt.name))
      emit(("    local _%s_str = %s(&self.arena)"):format(txt.name, txt.updater))
      emit(("    if _%s_str ~= nilptr then"):format(txt.name))
      emit(("      self.%s:set_text(self.renderer, _%s_str)"):format(txt.name, txt.name))
      emit("    end")
      emit(("    nebula_arena_rewind(&self.arena, _%s_mark)"):format(txt.name))
      emit("  end")
    end
    if mode == "static" then
      emit(("  -- [static] %s: 静态文本，由用户在 App:init 后手动调用 set_text 初始化"):format(txt.name))
    end
  end
end

local function _emit_draw_texts(reg, emit)
  if #reg.texts == 0 then return end
  emit("")
  emit("  -- ★ Phase 3.9 / Phase 4.1: 文本渲染（一等公民，最后绘制）")
  for _, txt in ipairs(reg.texts) do
    emit(("  if self.%s.mesh.vertex_count > 0 then"):format(txt.name))
    if txt.text_mode == "slug" then
      emit(("    -- ★ Phase 4.1: Slug 渲染 %s"):format(txt.name))
      emit("    if self.pipe_slug_text:upload_vertices(self.renderer,")
      emit(("      self.%s.mesh.vertex_buffer, self.%s.mesh.vertex_buffer_size,"):format(txt.name, txt.name))
      emit(("      self.%s.mesh.vertex_count) then"):format(txt.name))
      emit("      self.pipe_slug_text:draw(pass)")
      emit("    end")
    else
      emit(("    self.pipe_text:draw_buffer(pass,"))
      emit(("      self.%s.mesh.vertex_buffer,"):format(txt.name))
      emit(("      self.%s.mesh.vertex_buffer_size,"):format(txt.name))
      emit(("      self.%s.mesh.vertex_count)"):format(txt.name))
    end
    emit("  end")
  end
end

local function _emit_deinit_texts(reg, emit)
  if #reg.texts == 0 then return end
  local has_sdf_txt  = false
  local has_slug_txt = false
  for _, txt in ipairs(reg.texts) do
    local mode = txt.text_mode or "sdf"
    if mode == "sdf" then has_sdf_txt = true end
    if mode == "slug" then has_slug_txt = true end
  end
  if has_sdf_txt  then emit("  self.pipe_text:deinit()") end
  if has_slug_txt then emit("  self.pipe_slug_text:deinit()") end
  for _, txt in ipairs(reg.texts) do
    local mode = txt.text_mode or "sdf"
    if mode == "sdf" then
      emit(("  if self.%s.mesh.vertex_buffer ~= nilptr then wgpuBufferRelease(self.%s.mesh.vertex_buffer) end"):format(txt.name, txt.name))
    end
  end
end

-- ---------------------------------------------------------------------------
-- 类别 3: shadows（阴影组件，多 Pass 管线）
-- ---------------------------------------------------------------------------
local function _emit_record_shadows(reg, emit)
  if #reg.shadows == 0 then return end
  emit("")
  emit("  -- ★ Phase 3.10.5: 阴影组件 Context + 多 Pass 管线")
  for _, shd in ipairs(reg.shadows) do
    emit(("  %s: %sContext,"):format(shd.name, shd.base))
    emit(("  pipe_%s: %sPipeline,"):format(shd.base:lower(), shd.base))
  end
end

local function _emit_init_shadows(reg, emit)
  if #reg.shadows == 0 then return end
  emit("")
  emit("  -- ★ Phase 3.10.5: 初始化阴影管线（多 Pass）")
  for _, shd in ipairs(reg.shadows) do
    emit(("  if not self.pipe_%s:init(renderer, %d, %d) then return false end"):format(
      shd.base:lower(), shd.win_w, shd.win_h))
  end
end

local function _emit_deinit_shadows(reg, emit)
  if #reg.shadows == 0 then return end
  for _, shd in ipairs(reg.shadows) do
    emit(("  self.pipe_%s:deinit()"):format(shd.base:lower()))
  end
end

local function _emit_pre_pass_shadows(reg, emit)
  if #reg.shadows == 0 then return end
  emit("  -- ★ Phase 3.10.5: 阴影组件离屏 Pass（每个阴影组件执行 3 个离屏 Pass）")
  for _, shd in ipairs(reg.shadows) do
    local u_expr = ("self.%s:to_uniforms(self.vw, self.vh)"):format(shd.name)
    emit(("  -- [shadow] %s: 更新 uniforms 并执行阴影离屏渲染"):format(shd.name))
    emit("  do")
    emit(("    local _u = %s"):format(u_expr))
    emit(("    self.pipe_%s:update_uniforms(renderer, &_u)"):format(shd.base:lower()))
    emit(("    self.pipe_%s:draw_shadow(encoder, renderer, %.1f)"):format(shd.base:lower(), shd.blur_radius))
    emit("  end")
  end
end

local function _emit_surface_pass_shadows(reg, emit)
  if #reg.shadows == 0 then return end
  emit("  -- ★ Phase 3.10.5: 阴影合成层（先合成模糊阴影，再绘制主体）")
  for _, shd in ipairs(reg.shadows) do
    emit(("  -- [shadow] %s: 先合成阴影，再绘制主体"):format(shd.name))
    emit(("  self.pipe_%s:draw_composite(pass)"):format(shd.base:lower()))
    emit(("  self.pipe_%s:draw(pass)"):format(shd.base:lower()))
  end
end

-- ---------------------------------------------------------------------------
-- 类别 4: dense_texts（高密度文本组件，DenseText 管线）
-- ---------------------------------------------------------------------------
local function _emit_record_dense_texts(reg, emit)
  if #reg.dense_texts == 0 then return end
  emit("")
  emit("  -- ★ Phase 4.7-S2: DenseText 管线（高密度文本渲染）")
  emit("  _dense_font: NebulaAsciiFontAtlas,")
  for _, dt in ipairs(reg.dense_texts) do
    emit(("  pipe_dense_%s: %sDenseTextPipeline,"):format(dt.name, dt.base))
    emit(("  _dense_%s_buf: [%d]DenseCharInstance,"):format(dt.name, dt.max_chars))
  end
  local has_layout = false
  for _, dt in ipairs(reg.dense_texts) do
    if dt.layout then has_layout = true; break end
  end
  if has_layout then
    emit("  -- ★ Phase 4.7-S3: DenseText 布局坐标（供 Producer 定位）")
    for _, dt in ipairs(reg.dense_texts) do
      if dt.layout then
        emit(("  dense_layout_%s_x: float32,"):format(dt.name))
        emit(("  dense_layout_%s_y: float32,"):format(dt.name))
        emit(("  dense_layout_%s_w: float32,"):format(dt.name))
        emit(("  dense_layout_%s_h: float32,"):format(dt.name))
      end
    end
  end
end

local function _emit_init_dense_texts(reg, emit)
  if #reg.dense_texts == 0 then return end
  emit("")
  emit("  -- ★ Phase 4.7-S2: 初始化 DenseText 管线（高密度文本渲染）")
  emit("  if not nebula_text_load_ascii_font(&self._dense_font, renderer) then return false end")
  for _, dt in ipairs(reg.dense_texts) do
    emit(("  if not self.pipe_dense_%s:init(renderer, %d) then return false end"):format(
      dt.name, dt.max_chars))
    emit(("  if not self.pipe_dense_%s:update_atlas(renderer, self._dense_font.view, self._dense_font.sampler) then return false end"):format(
      dt.name))
    emit(("  self.pipe_dense_%s:update_viewport(renderer, vw, vh, %.1f, %.1f)"):format(
      dt.name, dt.cell_w, dt.cell_h))
  end
  if reg.layout_results then
    for _, dt in ipairs(reg.dense_texts) do
      local r = reg.layout_results[dt.name]
      if r then
        emit(("  -- ★ Phase 4.7-S3: [layout] %s: pos=(%.1f, %.1f) size=(%.1f x %.1f)"):format(
          dt.name, r.x, r.y, r.w, r.h))
        emit(("  self.dense_layout_%s_x = %.1f"):format(dt.name, r.x))
        emit(("  self.dense_layout_%s_y = %.1f"):format(dt.name, r.y))
        emit(("  self.dense_layout_%s_w = %.1f"):format(dt.name, r.w))
        emit(("  self.dense_layout_%s_h = %.1f"):format(dt.name, r.h))
      end
    end
  end
end

local function _emit_draw_dense_texts(reg, emit)
  if #reg.dense_texts == 0 then return end
  emit("")
  emit("  -- ★ Phase 4.7-S2: DenseText 管线绘制（Producer → upload → draw）")
  for _, dt in ipairs(reg.dense_texts) do
    emit("  do")
    emit("    local _dt_count: uint32 = 0")
    emit(("    %s(self, &self._dense_%s_buf[0], &_dt_count, %d)"):format(
      dt.producer, dt.name, dt.max_chars))
    emit("    if _dt_count > 0 then")
    emit(("      self.pipe_dense_%s:upload(self.renderer, &self._dense_%s_buf[0], _dt_count)"):format(
      dt.name, dt.name))
    emit(("      self.pipe_dense_%s:draw(pass, _dt_count)"):format(dt.name))
    emit("    end")
    emit("  end")
  end
end

local function _emit_deinit_dense_texts(reg, emit)
  if #reg.dense_texts == 0 then return end
  emit("")
  emit("  -- ★ Phase 4.7-S2: 释放 DenseText 管线")
  for _, dt in ipairs(reg.dense_texts) do
    emit(("  self.pipe_dense_%s:deinit()"):format(dt.name))
  end
end

-- ---------------------------------------------------------------------------
-- NEBULA_CATEGORIES 注册表
-- ---------------------------------------------------------------------------
NEBULA_CATEGORIES = {
  {
    name         = "standard",
    order        = 10,
    emit_record  = _emit_record_standard,
    emit_init    = _emit_init_standard,
    emit_update  = _emit_update_standard,
    emit_draw    = _emit_draw_standard,
    emit_deinit  = _emit_deinit_standard,
  },
  {
    name           = "texts",
    order          = 20,
    emit_record    = _emit_record_texts,
    emit_init      = _emit_init_texts,
    emit_update    = _emit_update_texts,
    emit_draw      = _emit_draw_texts,
    emit_deinit    = _emit_deinit_texts,
  },
  {
    name              = "shadows",
    order             = 30,
    emit_record       = _emit_record_shadows,
    emit_init         = _emit_init_shadows,
    emit_deinit       = _emit_deinit_shadows,
    emit_pre_pass     = _emit_pre_pass_shadows,
    emit_surface_pass = _emit_surface_pass_shadows,
  },
  {
    name         = "dense_texts",
    order        = 40,
    emit_record  = _emit_record_dense_texts,
    emit_init    = _emit_init_dense_texts,
    emit_draw    = _emit_draw_dense_texts,
    emit_deinit  = _emit_deinit_dense_texts,
  },
}

-- 按 order 排序（确保新注册的类别插入正确位置）
table.sort(NEBULA_CATEGORIES, function(a, b) return a.order < b.order end)

-- 公开 API：注册自定义组件类别
function nebula_register_category(opts)
  assert(type(opts) == "table", "nebula_register_category: opts must be a table")
  assert(opts.name, "nebula_register_category: name required")
  -- 检查重名
  for _, cat in ipairs(NEBULA_CATEGORIES) do
    assert(cat.name ~= opts.name,
      ("nebula_register_category: category '%s' already registered"):format(opts.name))
  end
  table.insert(NEBULA_CATEGORIES, {
    name           = opts.name,
    order          = opts.order or 100,
    emit_record    = opts.emit_record,
    emit_init      = opts.emit_init,
    emit_update    = opts.emit_update,
    emit_draw      = opts.emit_draw,
    emit_deinit    = opts.emit_deinit,
    emit_pre_pass     = opts.emit_pre_pass,
    emit_surface_pass = opts.emit_surface_pass,
  })
  table.sort(NEBULA_CATEGORIES, function(a, b) return a.order < b.order end)
end

-- =============================================================================
-- 代码生成：nebula_derive_app(app_name)
-- =============================================================================

-- 生成 <App> record
-- ★ P1-5: 通过 NEBULA_CATEGORIES 注册表驱动
local function gen_app_record(app_name, reg)
  local L = {}
  local function emit(s) table.insert(L, s) end

  emit(("-- === Derived App: %s ==="):format(app_name))
  emit(("global %s = @record{"):format(app_name))
  emit("  renderer: *NebulaRenderer,")
  emit("  vw: float32,")
  emit("  vh: float32,")
  emit("")

  -- ★ P1-5: 遍历所有已注册类别，生成该类别的 record 字段
  for _, cat in ipairs(NEBULA_CATEGORIES) do
    if cat.emit_record then cat.emit_record(reg, emit) end
  end

  -- ★ Phase 5.0 S2: 注入状态字段 + dirty bit（来自 binding_factory）
  if reg._binding_code and reg._binding_code.record_fields ~= "" then
    emit("")
    emit(reg._binding_code.record_fields)
  end

  emit("")
  emit("  -- ★ Phase 3.8: FrameArena（内嵌后备内存，无堆分配）")
  emit("  arena: NebulaArena,")
  emit(("  _arena_backing: [%d]uint8,"):format(reg.arena_size))
  -- ★ Phase 3.11: 延迟布局注入标志
  if reg.layout_results and next(reg.layout_results) then
    emit("  _layout_injected: boolean,")
  end
  emit("}")

  -- ★ 窗口尺寸常量（从 root_layout 推导，供 nebula_init / init_themed 使用）
  local win_w = (reg.root_layout and reg.root_layout.width)  or _cfg.DEFAULT_WIN_WIDTH
  local win_h = (reg.root_layout and reg.root_layout.height) or _cfg.DEFAULT_WIN_HEIGHT
  emit("")
  emit("-- ★ 窗口尺寸常量（供 nebula_init / init_themed 使用）")
  emit(("global %s_WIN_WIDTH: integer <comptime> = %d"):format(app_name, win_w))
  emit(("global %s_WIN_HEIGHT: integer <comptime> = %d"):format(app_name, win_h))

  return table.concat(L, "\n")
end

-- 生成 <App>:init
-- ★ P1-5: 通过 NEBULA_CATEGORIES 注册表驱动
local function gen_app_init(app_name, reg)
  local L = {}
  local function emit(s) table.insert(L, s) end

  emit(("function %s:init(renderer: *NebulaRenderer, vw: float32, vh: float32): boolean"):format(app_name))
  emit("  self.renderer = renderer")
  emit("  self.vw = vw")
  emit("  self.vh = vh")
  emit("")

  -- ★ P1-5: 遍历所有已注册类别，生成该类别的初始化代码
  for _, cat in ipairs(NEBULA_CATEGORIES) do
    if cat.emit_init then cat.emit_init(reg, emit) end
  end

  emit("")
  emit("  -- ★ Phase 3.8: 初始化 FrameArena（绑定内嵌后备内存）")
  emit(("  nebula_arena_init(&self.arena, &self._arena_backing[0], %d)"):format(reg.arena_size))

  -- ★ Phase 5.0 S2: 状态默认值初始化
  if reg._binding_code and reg._binding_code.init_code ~= "" then
    emit("")
    emit(reg._binding_code.init_code)
  end

  -- ★ Phase 3.11: 延迟布局坐标注入标志
  if reg.layout_results and next(reg.layout_results) then
    emit("")
    emit("  -- ★ Phase 3.11: 延迟布局注入标志（在 update 第一帧执行）")
    emit("  self._layout_injected = false")
  end

  emit("  return true")
  emit("end")

  return table.concat(L, "\n")
end

-- 生成 <App>:update
-- ★ P1-5: 组件更新逻辑通过 NEBULA_CATEGORIES 驱动
-- 响应式重排（Phase 3.12）仍为跨类别共享基础设施
local function gen_app_update(app_name, reg)
  local L = {}
  local function emit(s) table.insert(L, s) end

  emit(("function %s:update(input: *NebulaInputState, dt: float32): void"):format(app_name))
  emit("  -- ★ Phase 3.8: 每帧开始时重置 Arena（O(1)，仅移动游标）")
  emit("  nebula_arena_reset(&self.arena)")

  -- ★ Phase 3.11: 延迟布局坐标注入（第一帧执行一次，在 Context_init 之后）
  if reg.layout_results and next(reg.layout_results) then
    emit("")
    emit("  -- ★ Phase 3.11: 延迟布局坐标注入（第一帧，在 Context_init 之后）")
    emit("  if not self._layout_injected then")
    emit("    self._layout_injected = true")
    for _, comp in ipairs(reg.components) do
      local r = reg.layout_results[comp.name]
      if r then
        emit(("    -- [layout] %s: pos=(%.1f, %.1f) size=(%.1f x %.1f)"):format(
          comp.name, r.x, r.y, r.w, r.h))
        emit(("    self.%s.visual.pos  = Vec2{ x = %.1f, y = %.1f }"):format(
          comp.name, r.x, r.y))
        emit(("    self.%s.visual.size = Vec2{ x = %.1f, y = %.1f }"):format(
          comp.name, r.w, r.h))
      end
    end
    -- ★ Phase 4.7-S3: DenseText 延迟布局坐标注入
    for _, dt in ipairs(reg.dense_texts) do
      if dt.layout then
        local r = reg.layout_results[dt.name]
        if r then
          emit(("    self.dense_layout_%s_x = %.1f"):format(dt.name, r.x))
          emit(("    self.dense_layout_%s_y = %.1f"):format(dt.name, r.y))
          emit(("    self.dense_layout_%s_w = %.1f"):format(dt.name, r.w))
          emit(("    self.dense_layout_%s_h = %.1f"):format(dt.name, r.h))
        end
      end
    end
    -- Also inject viewport uniform update for first frame
    local updated_pipes = {}
    for vt, group in pairs(reg.type_groups) do
      if not updated_pipes[group.pipeline_name] then
        emit(("    self.pipe_%s:update_viewport(self.renderer, self.vw, self.vh)"):format(group.base:lower()))
        updated_pipes[group.pipeline_name] = true
      end
    end
    emit("  end")
  end

  -- ★ P1-5: 遍历所有已注册类别，生成该类别的更新逻辑
  for _, cat in ipairs(NEBULA_CATEGORIES) do
    if cat.emit_update then cat.emit_update(reg, emit) end
  end

  -- ★ Phase 3.12: 响应式重排——分段线性插値更新代码
  -- 当检测到 input.viewport_resized 时，使用预计算的分段系数重新计算组件坐标
  if reg.layout_segments and #reg.layout_segments.segments > 0 then
    local segs = reg.layout_segments.segments
    emit("")
    emit("  -- ★ Phase 3.12: 响应式重排（分段线性插値）")
    emit("  if input.viewport_resized then")
    emit("    self.vw = input.viewport_w")
    emit("    self.vh = input.viewport_h")
    emit("    -- 更新所有管线的视口 Uniform")
    local updated_pipes = {}
    for vt, group in pairs(reg.type_groups) do
      if not updated_pipes[group.pipeline_name] then
        emit(("    self.pipe_%s:update_viewport(self.renderer, input.viewport_w, input.viewport_h)"):format(group.base:lower()))
        updated_pipes[group.pipeline_name] = true
      end
    end
    -- ★ Phase 4.7-S2: 更新 DenseText 管线视口
    if #reg.dense_texts > 0 then
      for _, dt in ipairs(reg.dense_texts) do
        emit(("    self.pipe_dense_%s:update_viewport(self.renderer, input.viewport_w, input.viewport_h, %.1f, %.1f)"):format(
          dt.name, dt.cell_w, dt.cell_h))
      end
    end
    emit("    -- 分段线性插値：根据视口尺寸选择对应系数段重新计算组件坐标")

    -- 生成分段 if-elseif-else 结构
    -- 分段按 threshold_h 降序排列（最高的临界点对应最后一个分段）
    -- 第一段（threshold_h = nil）是默认分段（else 分支）
    local normal_segs = {}
    local default_seg = nil
    for _, seg in ipairs(segs) do
      if seg.threshold_h ~= nil or seg.threshold_w ~= nil then
        table.insert(normal_segs, seg)
      else
        default_seg = seg
      end
    end

    -- 按 threshold_h 降序排列，确保 if-elseif 按临界点从大到小检查
    table.sort(normal_segs, function(a, b)
      local ta = a.threshold_h or a.threshold_w or 0
      local tb = b.threshold_h or b.threshold_w or 0
      return ta > tb
    end)

    local first_branch = true
    for _, seg in ipairs(normal_segs) do
      local cond
      if seg.threshold_h then
        cond = ("input.viewport_h >= %.1f"):format(seg.threshold_h)
      else
        cond = ("input.viewport_w >= %.1f"):format(seg.threshold_w)
      end
      if first_branch then
        emit(("    if %s then"):format(cond))
        first_branch = false
      else
        emit(("    elseif %s then"):format(cond))
      end
      -- 生成该分段的组件坐标赋値
      for _, comp in ipairs(reg.components) do
        local c = seg.coeffs[comp.name]
        if c then
          emit(("      -- [seg th_h=%.0f] %s"):format(seg.threshold_h or 0, comp.name))
          emit(("      self.%s.visual.pos.x  = %.6f * input.viewport_w + %.6f"):format(comp.name, c.cx_vw, c.cx_c))
          emit(("      self.%s.visual.pos.y  = %.6f * input.viewport_h + %.6f"):format(comp.name, c.cy_vh, c.cy_c))
          emit(("      self.%s.visual.size.x = %.6f * input.viewport_w + %.6f"):format(comp.name, c.cw_vw, c.cw_c))
          emit(("      self.%s.visual.size.y = %.6f * input.viewport_h + %.6f"):format(comp.name, c.ch_vh, c.ch_c))
        end
      end
      -- ★ Phase 4.7-S3: DenseText 布局系数应用
      for _, dt in ipairs(reg.dense_texts) do
        if dt.layout then
          local c = seg.coeffs[dt.name]
          if c then
            emit(("      self.dense_layout_%s_x = %.6f * input.viewport_w + %.6f"):format(dt.name, c.cx_vw, c.cx_c))
            emit(("      self.dense_layout_%s_y = %.6f * input.viewport_h + %.6f"):format(dt.name, c.cy_vh, c.cy_c))
            emit(("      self.dense_layout_%s_w = %.6f * input.viewport_w + %.6f"):format(dt.name, c.cw_vw, c.cw_c))
            emit(("      self.dense_layout_%s_h = %.6f * input.viewport_h + %.6f"):format(dt.name, c.ch_vh, c.ch_c))
          end
        end
      end
    end

    -- 生成默认分段（最小视口，即溢出区域）
    if default_seg then
      if #normal_segs > 0 then
        emit("    else")
      end
      for _, comp in ipairs(reg.components) do
        local c = default_seg.coeffs[comp.name]
        if c then
          emit(("      -- [seg default] %s"):format(comp.name))
          emit(("      self.%s.visual.pos.x  = %.6f * input.viewport_w + %.6f"):format(comp.name, c.cx_vw, c.cx_c))
          emit(("      self.%s.visual.pos.y  = %.6f * input.viewport_h + %.6f"):format(comp.name, c.cy_vh, c.cy_c))
          emit(("      self.%s.visual.size.x = %.6f * input.viewport_w + %.6f"):format(comp.name, c.cw_vw, c.cw_c))
          emit(("      self.%s.visual.size.y = %.6f * input.viewport_h + %.6f"):format(comp.name, c.ch_vh, c.ch_c))
        end
      end
      -- ★ Phase 4.7-S3: DenseText 默认段布局系数
      for _, dt in ipairs(reg.dense_texts) do
        if dt.layout then
          local c = default_seg.coeffs[dt.name]
          if c then
            emit(("      self.dense_layout_%s_x = %.6f * input.viewport_w + %.6f"):format(dt.name, c.cx_vw, c.cx_c))
            emit(("      self.dense_layout_%s_y = %.6f * input.viewport_h + %.6f"):format(dt.name, c.cy_vh, c.cy_c))
            emit(("      self.dense_layout_%s_w = %.6f * input.viewport_w + %.6f"):format(dt.name, c.cw_vw, c.cw_c))
            emit(("      self.dense_layout_%s_h = %.6f * input.viewport_h + %.6f"):format(dt.name, c.ch_vh, c.ch_c))
          end
        end
      end
    end

    if #normal_segs > 0 then
      emit("    end")
    end
    emit("  end  -- viewport_resized")
  end

  -- ★ Phase 5.0 S2: 注入输入路由 + 钻石 commit（来自 binding_factory）
  if reg._binding_code and reg._binding_code.update_code ~= "" then
    emit("")
    emit(reg._binding_code.update_code)
  end

  emit("end")

  return table.concat(L, "\n")
end

-- ★ P1-5: 生成 <App>:draw_pre_pass — 通过 NEBULA_CATEGORIES 驱动
local function gen_app_pre_pass(app_name, reg)
  local L = {}
  local function emit(s) table.insert(L, s) end

  emit(("function %s:draw_pre_pass(encoder: WGPUCommandEncoder, renderer: *NebulaRenderer): void"):format(app_name))
  for _, cat in ipairs(NEBULA_CATEGORIES) do
    if cat.emit_pre_pass then cat.emit_pre_pass(reg, emit) end
  end
  emit("end")

  return table.concat(L, "\n")
end

-- ★ P1-5: 生成 <App>:draw_surface_pass — 通过 NEBULA_CATEGORIES 驱动
local function gen_app_surface_pass(app_name, reg)
  local L = {}
  local function emit(s) table.insert(L, s) end

  emit(("function %s:draw_surface_pass(pass: WGPURenderPassEncoder): void"):format(app_name))
  for _, cat in ipairs(NEBULA_CATEGORIES) do
    if cat.emit_surface_pass then cat.emit_surface_pass(reg, emit) end
  end
  emit("end")

  return table.concat(L, "\n")
end

-- ★ P1-5: 生成 <App>:draw — 通过 NEBULA_CATEGORIES 驱动
local function gen_app_draw(app_name, reg)
  local L = {}
  local function emit(s) table.insert(L, s) end

  emit(("function %s:draw(pass: WGPURenderPassEncoder): void"):format(app_name))

  -- ★ P1-5: 遍历所有已注册类别，生成该类别的绘制代码
  for _, cat in ipairs(NEBULA_CATEGORIES) do
    if cat.emit_draw then cat.emit_draw(reg, emit) end
  end

  emit("end")

  return table.concat(L, "\n")
end

-- =============================================================================
-- ★ P1-5: gen_app_deinit — 通过 NEBULA_CATEGORIES 驱动
-- 生成 <App>:deinit() 方法，释放所有管线 GPU 资源
-- 公理 B：L0 资源在 deinit 时销毁
-- =============================================================================
local function gen_app_deinit(app_name, reg)
  local L = {}
  local function emit(s) table.insert(L, s) end

  emit(("-- === %s:deinit — GPU 资源释放（公理 B） ==="):format(app_name))
  emit(("function %s:deinit(): void"):format(app_name))

  -- ★ P1-5: 遍历所有已注册类别，生成该类别的资源释放代码
  for _, cat in ipairs(NEBULA_CATEGORIES) do
    if cat.emit_deinit then cat.emit_deinit(reg, emit) end
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

  -- ★ Phase 4.0: App 级公理校验（任务 B + 任务 C）
  -- 在代码生成之前执行，确保元数据合法性
  if nebula_validate_app then
    nebula_validate_app(app_name, reg)
  end

  -- ★ Phase 4.3: 任务 D — process_body 引用域校验 + 静态契约校验
  -- 在任务 B/C 之后执行，确保 process_body 中的引用域合法
  local app_prims = {}
  for _, comp in ipairs(reg.components or {}) do
    for _, p in ipairs(comp.prims or {}) do
      table.insert(app_prims, p)
    end
  end
  if #app_prims > 0 then
    if nebula_validate_process_body then
      nebula_validate_process_body(app_name, app_prims)
    end
    if nebula_validate_static_asserts then
      nebula_validate_static_asserts(app_prims)
    end
  end

  -- ★ Phase 5.0 S2: 在代码生成之前，调用 binding_factory 生成绑定代码
  if reg._omniscient_graph then
    reg._binding_code = _load_binding_factory().generate(app_name, reg)
  end

  local parts = {
    gen_app_record(app_name, reg),
    gen_app_init(app_name, reg),
  }

  -- ★ Phase 5.0 S2: 事件 handler / _commit / _route_input 必须在 update 之前
  --   Nelua 要求方法在调用点之前已定义
  if reg._binding_code and reg._binding_code.handlers_code ~= "" then
    parts[#parts + 1] = reg._binding_code.handlers_code
  end

  parts[#parts + 1] = gen_app_update(app_name, reg)
  parts[#parts + 1] = gen_app_draw(app_name, reg)
  -- ★ Phase 3.10.5: 多 Pass 渲染支持
  parts[#parts + 1] = gen_app_pre_pass(app_name, reg)
  parts[#parts + 1] = gen_app_surface_pass(app_name, reg)
  -- ★ Phase 4.2.2-fix: GPU 资源释放
  parts[#parts + 1] = gen_app_deinit(app_name, reg)

  local source = table.concat(parts, "\n\n")

  local text_count = #reg.texts
  local slot_producer_count = 0
  for _, slot in ipairs(reg.slots) do
    if slot.producer then slot_producer_count = slot_producer_count + 1 end
  end
  local layout_count = 0
  if reg.layout_results then
    for _ in pairs(reg.layout_results) do layout_count = layout_count + 1 end
  end

  print((("[derive-app] %s: emit App record + init + update + draw + pre_pass + surface_pass (%d components, %d texts, %d dense_texts, %d slots [%d producer], %d shadows, %d type_groups, %d layout_nodes, arena=%dB)"):format(
    app_name,
    #reg.components,
    text_count,
    #reg.dense_texts,
    #reg.slots,
    slot_producer_count,
    #reg.shadows,
    (function()
      local n = 0
      for _ in pairs(reg.type_groups) do n = n + 1 end
      return n
    end)(),
    layout_count,
    reg.arena_size
  )))

  return source
end

return "nebula_app_factory_v0.12_phase5.0-s2"
