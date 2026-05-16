-- =============================================================================
-- derive/effect_model.lua — Nebula GUI Compiler Phase 5.0 S1b
--
-- Effect / Invalidation 模型
--
-- 从全知图中自动推导状态变更引发的 Effect（GPU 更新、文本更新、
-- 布局失效、重绘），替代原始 find_gpu_effect 猜测函数。
--
-- 功能：
--   EffectKind           — 枚举常量
--   derive_effects       — 从 binding 声明推导 Effect 列表
--   build_effects_index  — 建立 state → [Effect] 反向索引
-- =============================================================================

local EffectModel = {}

-- Effect 类型枚举
EffectModel.EffectKind = {
  GPU_UPDATE         = "gpu_update",
  TEXT_UPDATE         = "text_update",
  LAYOUT_INVALIDATE  = "layout_invalidate",
  REDRAW             = "redraw",
}

--- 从全知图中推导 Effect 列表。
---
--- 推导规则：
---   1. binding 显式声明了 affects → 直接使用
---   2. binding target 匹配文本组件的 bound_state → text_update
---   3. binding target 匹配 visual binding → gpu_update
---   4. 以上均不匹配 → 默认 redraw
---
--- @param graph table 全知图（含 bindings, states, 可选 texts/components）
--- @return table effects Effect[]
function EffectModel.derive_effects(graph)
  assert(graph, "derive_effects: graph required")

  local effects = {}
  local bindings = graph.bindings or {}

  -- 构建辅助索引：text_bound_states, visual_bindings
  local text_bound = {}   -- state_name -> text_component_name
  local visual_bound = {} -- state_name -> {component, field, method}

  -- 从注册表中收集文本组件绑定（如果存在）
  if graph.texts then
    for _, t in ipairs(graph.texts) do
      if t.bound_to then
        text_bound[t.bound_to] = t.name
      end
    end
  end

  -- 从注册表中收集 visual bindings（如果存在）
  if graph.visual_bindings then
    for _, vb in ipairs(graph.visual_bindings) do
      visual_bound[vb.state] = {
        component = vb.component,
        field     = vb.field,
        method    = vb.update_method or "update",
      }
    end
  end

  for _, binding in ipairs(bindings) do
    -- 规则 1：显式 affects
    if binding.affects then
      for _, af in ipairs(binding.affects) do
        effects[#effects + 1] = {
          kind       = af.invalidation or EffectModel.EffectKind.REDRAW,
          target     = af.target,
          field      = af.field,
          method     = af.method or "update",
          depends_on = binding.target,
        }
      end
    else
      -- 规则 2：文本组件绑定
      local text_name = text_bound[binding.target]
      if text_name then
        effects[#effects + 1] = {
          kind       = EffectModel.EffectKind.TEXT_UPDATE,
          target     = text_name,
          field      = "text",
          method     = "update_text",
          depends_on = binding.target,
        }
      end

      -- 规则 3：Visual binding
      local vb = visual_bound[binding.target]
      if vb then
        effects[#effects + 1] = {
          kind       = EffectModel.EffectKind.GPU_UPDATE,
          target     = vb.component,
          field      = vb.field,
          method     = vb.method,
          depends_on = binding.target,
        }
      end

      -- 规则 4：默认 redraw（如果没有匹配任何已知绑定）
      if not text_name and not vb and not binding.affects then
        effects[#effects + 1] = {
          kind       = EffectModel.EffectKind.REDRAW,
          target     = binding.target,
          field      = nil,
          method     = nil,
          depends_on = binding.target,
        }
      end
    end
  end

  return effects
end

--- 建立 state → [Effect] 反向索引。
--- 沿依赖图向上追溯：如果 state S 被修改，所有依赖 S 的 binding 的 Effect 都需要触发。
---
--- @param effects table  Effect[]
--- @param dep_adj table  邻接表 {source -> [target...]}
--- @return table index  {state_name -> Effect[]}
function EffectModel.build_effects_index(effects, dep_adj)
  assert(type(effects) == "table", "build_effects_index: effects must be a table")

  -- 直接索引：effect.depends_on → effect
  local direct = {}
  for _, eff in ipairs(effects) do
    if not direct[eff.depends_on] then
      direct[eff.depends_on] = {}
    end
    direct[eff.depends_on][#direct[eff.depends_on] + 1] = eff
  end

  -- 反向传播：对于每个 state，找到它能传播到的所有 effects
  local index = {}
  dep_adj = dep_adj or {}

  -- BFS 从 state 向下传播，收集所有触发的 effects
  local function collect_effects(start_state)
    local result = {}
    local visited = {}
    local queue = { start_state }
    local head = 1

    while head <= #queue do
      local state = queue[head]
      head = head + 1

      if not visited[state] then
        visited[state] = true

        -- 收集该 state 的直接 effects
        if direct[state] then
          for _, eff in ipairs(direct[state]) do
            result[#result + 1] = eff
          end
        end

        -- 沿邻接表向下传播
        if dep_adj[state] then
          for _, target in ipairs(dep_adj[state]) do
            if not visited[target] then
              queue[#queue + 1] = target
            end
          end
        end
      end
    end

    return result
  end

  -- 为每个 state 构建 effects 索引
  -- 使用所有 effects 的 depends_on 和 dep_adj 的 keys 作为起始 states
  local all_states = {}
  for state, _ in pairs(dep_adj) do
    all_states[state] = true
  end
  for _, eff in ipairs(effects) do
    all_states[eff.depends_on] = true
  end

  for state, _ in pairs(all_states) do
    local effs = collect_effects(state)
    if #effs > 0 then
      index[state] = effs
    end
  end

  return index
end

return EffectModel
