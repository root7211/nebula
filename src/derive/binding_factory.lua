-- =============================================================================
-- derive/binding_factory.lua — Nebula GUI Compiler Phase 5.0 S2
--
-- 端到端路径代码生成
--
-- 从全知图（omniscient graph）生成完整的 Nelua 代码：
--   · 事件 handler（mutation + 传播链 + effect 调用）
--   · 钻石节点 _commit 函数（dirty bit 测试 + 延迟计算）
--   · 输入路由函数（_route_input / _route_legacy_input）
--
-- 设计原则（Phase 5.0 编译期消解范式）：
--   · 事件系统、依赖追踪在生成的代码中不存在——全部在编译期展开
--   · 线性链内联到 handler 中（零运行时开销）
--   · 仅钻石节点使用 dirty bit 延迟到 _commit（最小化位测试开销）
--
-- 依赖模块：
--   mutation_ast.lua  — AST 解析 + read_set/write_set + emit
--   effect_model.lua  — Effect 推导 + 反向索引
--   dirty_map.lua     — dirty bit 分配 + 代码生成
--   event_router.lua  — 事件路由去重
-- =============================================================================

local BindingFactory = {}

-- ★ 延迟加载依赖模块（与 app_factory 保持一致的加载模式）
local _modules = {}
local function _load_module(name)
  if _modules[name] then return _modules[name] end
  local ok, mod = pcall(require, "derive." .. name)
  if ok then
    _modules[name] = mod
  else
    local _this_dir = debug.getinfo(1, "S").source:match("^@(.+/)") or ""
    _modules[name] = dofile(_this_dir .. name .. ".lua")
  end
  return _modules[name]
end

-- =============================================================================
-- Effect 调用代码生成
-- =============================================================================

--- 生成单个 effect 调用的 Nelua 代码。
---
--- 根据 effect.kind 生成对应的运行时调用：
---   gpu_update         → self.<target>:<method>(self.renderer, self.<field>)
---   text_update        → self.<target>:set_text(self.renderer, self.<depends_on>)
---   layout_invalidate  → self._layout_dirty = true
---   redraw             → （无额外代码，帧末自动重绘）
---
--- @param effect table  Effect 对象
--- @param app_name string App 名称
--- @param indent string 缩进前缀
--- @return string|nil  生成的代码行，redraw 类型返回注释
function BindingFactory.emit_effect_call(effect, app_name, indent)
  indent = indent or "    "
  local EK = _load_module("effect_model").EffectKind

  if effect.kind == EK.GPU_UPDATE then
    return ("%s-- [effect] gpu_update: %s.%s"):format(indent, effect.target, effect.field or "?")
  elseif effect.kind == EK.TEXT_UPDATE then
    return ("%s-- [effect] text_update: %s"):format(indent, effect.target)
  elseif effect.kind == EK.LAYOUT_INVALIDATE then
    return ("%s-- [effect] layout_invalidate"):format(indent)
  elseif effect.kind == EK.REDRAW then
    return ("%s-- [effect] redraw: %s"):format(indent, effect.target)
  end

  return nil
end

-- =============================================================================
-- 事件 Handler 代码生成
-- =============================================================================

--- 生成单个事件 handler 函数。
---
--- 生成的函数结构：
---   function <App>:_on_<target>_<event_type>(): void
---     -- 1. mutation 代码（AST emit）
---     -- 2. 线性链传播：内联 recompute + effect 调用
---     -- 3. 钻石节点：dirty bit 置位（延迟到 _commit）
---   end
---
--- @param graph table       全知图
--- @param evt table         事件声明 {target, event_type, mutation}
--- @param event_chain table 传播链 {write_set, chain}
--- @param dirty_map_alloc table  dirty bit 分配 {target -> bit_index}
--- @param app_name string   App 名称
--- @param emit function     代码输出函数
function BindingFactory.emit_event_handler(graph, evt, event_chain, dirty_map_alloc, app_name, emit)
  local MutationAST = _load_module("mutation_ast")
  local DirtyMap    = _load_module("dirty_map")

  local handler_name = ("_on_%s_%s"):format(evt.target, evt.event_type)
  emit(("-- ★ Phase 5.0 S2: 端到端事件 handler（编译期展开）"))
  emit(("function %s:%s(): void"):format(app_name, handler_name))

  -- 1. Mutation 代码（AST → Nelua）
  if evt.mutation then
    local stmts, err = MutationAST.parse(evt.mutation)
    if stmts then
      emit("  -- [mutation]")
      local code = MutationAST.emit(stmts, 1)
      emit(code)
    else
      emit(("  -- [mutation parse error: %s]"):format(
        err and err.message or "unknown"))
    end
  end

  -- 2. 传播链处理
  if event_chain and event_chain.chain then
    local has_propagation = false
    for _, step in ipairs(event_chain.chain) do
      if step.type == "recompute" then
        -- 检查是否是钻石节点
        if graph.diamond_nodes[step.target] then
          -- 钻石节点：dirty bit 置位，延迟到 _commit
          local bit_idx = dirty_map_alloc[step.target]
          if bit_idx then
            if not has_propagation then
              emit("  -- [propagation]")
              has_propagation = true
            end
            emit(("  -- diamond node '%s': defer to _commit"):format(step.target))
            emit("  " .. DirtyMap.gen_set(bit_idx))
          end
        else
          -- 线性链：内联 recompute
          if not has_propagation then
            emit("  -- [propagation]")
            has_propagation = true
          end
          if step.compute then
            local compute_stmts, compute_err = MutationAST.parse(step.compute)
            if compute_stmts then
              emit(("  -- recompute '%s' (inline)"):format(step.target))
              local code = MutationAST.emit(compute_stmts, 1)
              emit(code)
            else
              emit(("  -- recompute '%s' parse error: %s"):format(
                step.target, compute_err and compute_err.message or "unknown"))
            end
          else
            emit(("  -- recompute '%s' (no compute expression)"):format(step.target))
          end
        end
      elseif step.type == "effect" then
        if not has_propagation then
          emit("  -- [propagation]")
          has_propagation = true
        end
        local line = BindingFactory.emit_effect_call(step.effect, app_name, "  ")
        if line then emit(line) end
      end
    end
  end

  emit("end")
end

-- =============================================================================
-- 钻石 Commit 函数生成
-- =============================================================================

--- 生成 _commit 函数：按拓扑序处理所有 dirty 钻石节点。
---
--- 生成的函数结构：
---   function <App>:_commit(): void
---     if self._dirty & (1 << bit_N) ~= 0 then
---       -- recompute binding_N
---       -- trigger effects for binding_N
---     end
---     self._dirty = 0
---   end
---
--- @param graph table       全知图
--- @param dirty_map_alloc table  dirty bit 分配 {target -> bit_index}
--- @param bit_count number  总 bit 数
--- @param app_name string   App 名称
--- @param emit function     代码输出函数
function BindingFactory.emit_commit(graph, dirty_map_alloc, bit_count, app_name, emit)
  local MutationAST = _load_module("mutation_ast")
  local DirtyMap    = _load_module("dirty_map")

  emit("-- ★ Phase 5.0 S2: 钻石节点 commit（按拓扑序延迟计算）")
  emit(("function %s:_commit(): void"):format(app_name))

  if bit_count == 0 then
    emit("  -- no diamond nodes, nothing to commit")
    emit("end")
    return
  end

  -- 按拓扑序遍历钻石节点
  local topo = graph.topo_order or {}
  for _, node in ipairs(topo) do
    local bit_idx = dirty_map_alloc[node]
    if bit_idx ~= nil then
      emit(("  if %s then"):format(DirtyMap.gen_test(bit_idx)))

      -- 找到对应的 binding
      for _, binding in ipairs(graph.bindings or {}) do
        if binding.target == node and binding.compute then
          local stmts, err = MutationAST.parse(binding.compute)
          if stmts then
            emit(("    -- recompute '%s'"):format(node))
            local code = MutationAST.emit(stmts, 2)
            emit(code)
          else
            emit(("    -- recompute '%s' parse error: %s"):format(
              node, err and err.message or "unknown"))
          end
          break
        end
      end

      -- 触发该节点的 effects
      local state_effects = (graph.effects_for_state or {})[node] or {}
      for _, effect in ipairs(state_effects) do
        local line = BindingFactory.emit_effect_call(effect, app_name, "    ")
        if line then emit(line) end
      end

      emit("  end")
    end
  end

  -- 清零 dirty bits
  emit("  " .. DirtyMap.gen_clear(bit_count))

  emit("end")
end

-- =============================================================================
-- 输入路由代码生成
-- =============================================================================

--- 生成 _route_input 函数：将输入事件路由到 nebula_on 声明的 handler。
---
--- 生成的函数结构：
---   function <App>:_route_input(input: *NebulaInputState): void
---     -- click 事件路由（hit-test）
---     if input.mouse_clicked then
---       if hit_test_rect(input.mouse_x, input.mouse_y, self.<comp>.visual) then
---         self:_on_<comp>_click()
---       end
---     end
---     -- key 事件路由
---     ...
---   end
---
--- @param graph table       全知图
--- @param declared table    已声明事件集合 {target -> {event_type -> true}}
--- @param app_name string   App 名称
--- @param emit function     代码输出函数
function BindingFactory.emit_input_router(graph, declared, app_name, emit)
  emit("-- ★ Phase 5.0 S2: 输入路由（编译期展开，无运行时分发）")
  emit(("function %s:_route_input(input: *NebulaInputState): void"):format(app_name))

  -- 按组件分组收集事件
  local by_target = {}
  for _, evt in ipairs(graph.events or {}) do
    if not by_target[evt.target] then
      by_target[evt.target] = {}
    end
    table.insert(by_target[evt.target], evt)
  end

  -- 按组件名排序以确保稳定性
  local sorted_targets = {}
  for target, _ in pairs(by_target) do
    sorted_targets[#sorted_targets + 1] = target
  end
  table.sort(sorted_targets)

  -- 分类事件类型
  local has_click_events = false
  local has_key_events = false

  for _, target in ipairs(sorted_targets) do
    for _, evt in ipairs(by_target[target]) do
      if evt.event_type == "click" then
        has_click_events = true
      elseif evt.event_type == "key_press" or evt.event_type == "key_down" then
        has_key_events = true
      end
    end
  end

  -- Click 事件路由（使用 hit-test）
  if has_click_events then
    emit("  -- [click events]")
    emit("  if input.mouse_left_pressed then")
    for _, target in ipairs(sorted_targets) do
      for _, evt in ipairs(by_target[target]) do
        if evt.event_type == "click" then
          -- ★ 补丁 4: 使用运行时 bounds 进行 hit-test
          emit(("    if input.mouse_x >= self.%s.visual.pos.x and input.mouse_x <= self.%s.visual.pos.x + self.%s.visual.size.x and input.mouse_y >= self.%s.visual.pos.y and input.mouse_y <= self.%s.visual.pos.y + self.%s.visual.size.y then"):format(
            target, target, target, target, target, target))
          emit(("      self:_on_%s_click()"):format(target))
          emit("    end")
        end
      end
    end
    emit("  end")
  end

  -- Key 事件路由
  if has_key_events then
    emit("  -- [key events]")
    for _, target in ipairs(sorted_targets) do
      for _, evt in ipairs(by_target[target]) do
        if evt.event_type == "key_press" then
          emit(("  -- key_press → %s"):format(target))
          emit(("  if input.key_count > 0 then"))
          emit(("    self:_on_%s_key_press()"):format(target))
          emit("  end")
        elseif evt.event_type == "key_down" then
          emit(("  -- key_down → %s"):format(target))
          emit(("  if input.key_count > 0 then"))
          emit(("    self:_on_%s_key_down()"):format(target))
          emit("  end")
        end
      end
    end
  end

  emit("end")
end

--- 生成 _route_legacy_input 过滤函数。
--- 在调用旧 process_input 之前，过滤掉已被 nebula_on 声明的事件。
---
--- @param declared table    已声明事件集合
--- @param app_name string   App 名称
--- @param emit function     代码输出函数
function BindingFactory.emit_legacy_input_filter(declared, app_name, emit)
  -- 收集所有已声明的 (target, event_type) 对，用于生成过滤条件
  local has_declared = false
  for _, _ in pairs(declared) do
    has_declared = true
    break
  end

  if not has_declared then
    -- 无已声明事件，无需过滤
    return
  end

  emit("-- ★ Phase 5.0 S2: Legacy 输入过滤（已声明事件不转发到 process_input）")
  emit(("-- Declared events filtered from legacy path:"))
  for target, events in pairs(declared) do
    local event_list = {}
    for event_type, _ in pairs(events) do
      event_list[#event_list + 1] = event_type
    end
    table.sort(event_list)
    emit(("--   %s: %s"):format(target, table.concat(event_list, ", ")))
  end
end

-- =============================================================================
-- 主入口：生成全部 binding 相关代码
-- =============================================================================

--- 从全知图生成完整的 binding 代码块。
--- 包括：state 字段声明、事件 handler、_commit、_route_input。
---
--- @param app_name string App 名称
--- @param reg table       App 注册表
--- @return table result   {record_fields, init_code, handlers_code, update_integration}
function BindingFactory.generate(app_name, reg)
  local MutationAST   = _load_module("mutation_ast")
  local EffectModel   = _load_module("effect_model")
  local DirtyMap      = _load_module("dirty_map")
  local EventRouter   = _load_module("event_router")

  local graph = reg._omniscient_graph
  if not graph then
    return {
      record_fields = "",
      init_code     = "",
      handlers_code = "",
      update_code   = "",
    }
  end

  -- ★ 确保 graph 中有 event_chains（需要 MutationAST + EffectModel）
  -- 如果 S1b 的 build() 没有传入 opts，这里补充构建
  if not graph.event_chains and graph.topo_order then
    local OG = _load_module("omniscient_graph")
    graph = OG.build(reg, { MutationAST = MutationAST, EffectModel = EffectModel })
    reg._omniscient_graph = graph
  end

  -- Dirty bit 分配
  local dirty_alloc, bit_count = DirtyMap.allocate(graph)

  -- 事件路由声明集合
  local declared = EventRouter.build_declared_event_set(reg)

  -- ===== 1. Record 字段 =====
  local record_lines = {}
  local function emit_record(s) table.insert(record_lines, s) end

  emit_record("  -- ★ Phase 5.0 S2: 状态字段（nebula_state 声明）")
  local state_count = 0
  -- 按名称排序确保稳定性
  local sorted_state_names = {}
  for name, _ in pairs(graph.states) do
    sorted_state_names[#sorted_state_names + 1] = name
  end
  table.sort(sorted_state_names)

  for _, name in ipairs(sorted_state_names) do
    local state = graph.states[name]
    emit_record(("  %s: %s,"):format(name, state.type or "int32"))
    state_count = state_count + 1
  end

  -- ★ Phase 5.0 S2: binding targets（派生状态）也需要 record 字段
  -- 它们不在 _states 中，而是在 _bindings 中声明
  local sorted_binding_targets = {}
  for _, binding in ipairs(graph.bindings or {}) do
    if not graph.states[binding.target] then
      sorted_binding_targets[#sorted_binding_targets + 1] = binding.target
    end
  end
  table.sort(sorted_binding_targets)

  if #sorted_binding_targets > 0 then
    emit_record("  -- ★ Phase 5.0 S2: 派生状态字段（nebula_bind target）")
    for _, name in ipairs(sorted_binding_targets) do
      -- 从 binding 推断类型：尝试从 compute 表达式的 write target 推断
      -- 默认 int32（与 state 默认类型一致）
      local binding_type = "int32"
      for _, b in ipairs(graph.bindings) do
        if b.target == name and b.type then
          binding_type = b.type
          break
        end
      end
      emit_record(("  %s: %s,"):format(name, binding_type))
    end
  end

  if bit_count > 0 then
    local storage = DirtyMap.storage_type(bit_count)
    emit_record(("  -- ★ Phase 5.0 S2: dirty bit（%d 个钻石节点）"):format(bit_count))
    emit_record(("  _dirty: %s,"):format(storage))
  end

  -- ===== 2. Init 代码 =====
  local init_lines = {}
  local function emit_init(s) table.insert(init_lines, s) end

  emit_init("  -- ★ Phase 5.0 S2: 状态默认值初始化")
  for _, name in ipairs(sorted_state_names) do
    local state = graph.states[name]
    if state.default ~= nil then
      if type(state.default) == "string" then
        emit_init(("  self.%s = %s"):format(name, state.default))
      elseif type(state.default) == "boolean" then
        emit_init(("  self.%s = %s"):format(name, state.default and "true" or "false"))
      else
        emit_init(("  self.%s = %s"):format(name, tostring(state.default)))
      end
    else
      emit_init(("  self.%s = 0"):format(name))
    end
  end
  -- ★ Phase 5.0 S2: 派生状态默认值初始化
  for _, name in ipairs(sorted_binding_targets) do
    emit_init(("  self.%s = 0"):format(name))
  end
  if bit_count > 0 then
    emit_init("  " .. DirtyMap.gen_clear(bit_count))
  end

  -- ===== 3. Handler 代码 =====
  local handler_lines = {}
  local function emit_handler(s) table.insert(handler_lines, s) end

  -- 为每个事件生成 handler
  local event_chains = graph.event_chains or {}
  for i, evt in ipairs(graph.events) do
    local chain_info = event_chains[i]
    BindingFactory.emit_event_handler(graph, evt, chain_info, dirty_alloc, app_name, emit_handler)
    emit_handler("")
  end

  -- 生成 _commit（如果有钻石节点）
  if bit_count > 0 then
    BindingFactory.emit_commit(graph, dirty_alloc, bit_count, app_name, emit_handler)
    emit_handler("")
  end

  -- 生成 _route_input
  if #graph.events > 0 then
    BindingFactory.emit_input_router(graph, declared, app_name, emit_handler)
    emit_handler("")
  end

  -- Legacy 过滤注释
  BindingFactory.emit_legacy_input_filter(declared, app_name, emit_handler)

  -- ===== 4. Update 集成代码 =====
  local update_lines = {}
  local function emit_update(s) table.insert(update_lines, s) end

  if #graph.events > 0 then
    emit_update("  -- ★ Phase 5.0 S2: 输入路由（在输入收集之后）")
    emit_update(("  self:_route_input(input)"):format())
  end
  if bit_count > 0 then
    emit_update("  -- ★ Phase 5.0 S2: 钻石节点 commit（帧末）")
    emit_update(("  self:_commit()"):format())
  end

  -- 编译期日志
  print(("[binding_factory] %s: %d states, %d events, %d handlers, %d diamond bits"):format(
    app_name, state_count, #graph.events, #graph.events, bit_count))

  return {
    record_fields = table.concat(record_lines, "\n"),
    init_code     = table.concat(init_lines, "\n"),
    handlers_code = table.concat(handler_lines, "\n"),
    update_code   = table.concat(update_lines, "\n"),
  }
end

return BindingFactory
