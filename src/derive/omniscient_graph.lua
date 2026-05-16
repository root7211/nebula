-- =============================================================================
-- derive/omniscient_graph.lua — Nebula GUI Compiler Phase 5.0 S1b
--
-- 全知图构建与分析
--
-- 全知图是编译器在 S1 阶段构建的 App 完整信息图，包含：
--   · states   — 状态声明（名称、类型、默认值）
--   · bindings — 绑定声明（target、depends、compute）
--   · events   — 事件声明（target、event_type、mutation）
--   · dep_adj  — 依赖邻接表（source -> [target...]）
--   · topo_order    — 拓扑排序结果
--   · diamond_nodes — 钻石节点集合（入度 > 1）
--   · event_chains  — 事件传播链（S1b 新增）
--
-- 功能：
--   build_dependency_adjacency(bindings) — 构建邻接表
--   topological_sort(adj, nodes)         — Kahn 拓扑排序
--   detect_diamond_dependencies(adj)     — 钻石依赖检测
--   trace_propagation(mutation, graph)   — 路径追踪（S1b 新增）
--   nebula_build_omniscient_graph(reg)   — 统一入口
-- =============================================================================

local OmniscientGraph = {}

--- 从 bindings 列表构建依赖邻接表。
--- 邻接表方向：source -> [target...]，表示 source 变化时 target 需要重新计算。
---
--- @param bindings table 绑定声明列表 [{target, depends}]
--- @return table adj {source -> {target1, target2, ...}}
function OmniscientGraph.build_dependency_adjacency(bindings)
  assert(type(bindings) == "table", "build_dependency_adjacency: bindings must be a table")

  local adj = {}

  for _, binding in ipairs(bindings) do
    assert(binding.target, "build_dependency_adjacency: binding must have target")
    local depends = binding.depends or {}
    for _, dep in ipairs(depends) do
      if not adj[dep] then
        adj[dep] = {}
      end
      table.insert(adj[dep], binding.target)
    end
  end

  return adj
end

--- Kahn 算法拓扑排序。
--- 输入节点集合和邻接表，返回拓扑序列表。
--- 如果存在循环依赖，返回 nil。
---
--- @param adj table 邻接表 {source -> [target...]}
--- @param nodes table 所有节点名称列表
--- @return table|nil topo_order 拓扑序，循环依赖时返回 nil
function OmniscientGraph.topological_sort(adj, nodes)
  assert(type(adj) == "table", "topological_sort: adj must be a table")
  assert(type(nodes) == "table", "topological_sort: nodes must be a table")

  -- 计算入度
  local in_degree = {}
  for _, node in ipairs(nodes) do
    in_degree[node] = 0
  end
  for source, targets in pairs(adj) do
    for _, target in ipairs(targets) do
      in_degree[target] = (in_degree[target] or 0) + 1
    end
  end

  -- 初始化零入度队列（按字母序确保稳定性）
  local queue = {}
  for _, node in ipairs(nodes) do
    if in_degree[node] == 0 then
      table.insert(queue, node)
    end
  end
  table.sort(queue)

  local result = {}
  local head = 1

  while head <= #queue do
    local current = queue[head]
    head = head + 1
    table.insert(result, current)

    local targets = adj[current] or {}
    -- 按字母序处理 targets，确保稳定性
    local sorted_targets = {}
    for _, t in ipairs(targets) do
      table.insert(sorted_targets, t)
    end
    table.sort(sorted_targets)

    for _, target in ipairs(sorted_targets) do
      in_degree[target] = in_degree[target] - 1
      if in_degree[target] == 0 then
        -- 插入排序维持队列有序
        local inserted = false
        for i = head, #queue do
          if target < queue[i] then
            table.insert(queue, i, target)
            inserted = true
            break
          end
        end
        if not inserted then
          table.insert(queue, target)
        end
      end
    end
  end

  -- 如果结果数量少于节点数量，存在循环依赖
  if #result < #nodes then
    return nil
  end

  return result
end

--- 检测钻石依赖节点（入度 > 1 的节点）。
--- 钻石节点需要 dirty bit 来避免重复计算。
---
--- @param adj table 邻接表 {source -> [target...]}
--- @return table diamond_nodes {node_name -> true}
function OmniscientGraph.detect_diamond_dependencies(adj)
  assert(type(adj) == "table", "detect_diamond_dependencies: adj must be a table")

  local in_degree = {}

  for _, targets in pairs(adj) do
    for _, target in ipairs(targets) do
      in_degree[target] = (in_degree[target] or 0) + 1
    end
  end

  local diamonds = {}
  for node, degree in pairs(in_degree) do
    if degree > 1 then
      diamonds[node] = true
    end
  end

  return diamonds
end

--- 路径追踪：从 mutation 的 write_set 出发，沿依赖图 BFS 向下传播，
--- 收集所有需要重计算的 binding 和触发的 effect。
---
--- @param write_set table  {state_name -> true} 被修改的状态集合
--- @param graph table      全知图（含 dep_adj, bindings, effects_for_state）
--- @return table chain     传播链 [{type="recompute"|"effect", ...}]
function OmniscientGraph.trace_propagation(write_set, graph)
  assert(type(write_set) == "table", "trace_propagation: write_set must be a table")
  assert(graph, "trace_propagation: graph required")

  local chain = {}
  local visited = {}
  local queue = {}

  -- 初始化队列：所有被修改的状态
  for state, _ in pairs(write_set) do
    queue[#queue + 1] = state
  end
  -- 按字母序排序以确保稳定性
  table.sort(queue)

  local head = 1
  while head <= #queue do
    local state = queue[head]
    head = head + 1

    if not visited[state] then
      visited[state] = true

      -- 查找依赖此 state 的 binding targets
      local targets = graph.dep_adj[state] or {}
      local sorted_targets = {}
      for _, t in ipairs(targets) do sorted_targets[#sorted_targets + 1] = t end
      table.sort(sorted_targets)

      for _, target in ipairs(sorted_targets) do
        -- 找到对应的 binding
        for _, binding in ipairs(graph.bindings or {}) do
          if binding.target == target then
            chain[#chain + 1] = {
              type    = "recompute",
              target  = target,
              compute = binding.compute,
            }
            break
          end
        end
        -- 将 target 加入传播队列
        if not visited[target] then
          queue[#queue + 1] = target
        end
      end

      -- 收集该 state 的 effects
      local state_effects = (graph.effects_for_state or {})[state] or {}
      for _, effect in ipairs(state_effects) do
        chain[#chain + 1] = {
          type   = "effect",
          effect = effect,
        }
      end
    end
  end

  return chain
end

--- 全知图构建统一入口。
--- 从注册表中收集 states/bindings/events，构建依赖图并分析。
--- S1b: 增加 trace_propagation 和 event_chains 计算。
---
--- @param reg table App 注册表（需包含 _states, _bindings, _events）
--- @param opts table|nil 可选配置 { MutationAST, EffectModel }
--- @return table graph 全知图对象
function OmniscientGraph.build(reg, opts)
  assert(reg, "nebula_build_omniscient_graph: reg required")

  local states   = reg._states   or {}
  local bindings = reg._bindings or {}
  local events   = reg._events   or {}

  -- 收集所有节点名称（states + binding targets）
  local node_set = {}
  local nodes = {}

  for name, _ in pairs(states) do
    if not node_set[name] then
      node_set[name] = true
      table.insert(nodes, name)
    end
  end
  for _, binding in ipairs(bindings) do
    if not node_set[binding.target] then
      node_set[binding.target] = true
      table.insert(nodes, binding.target)
    end
  end
  -- 按字母序排序节点列表，确保稳定性
  table.sort(nodes)

  -- 构建邻接表
  local dep_adj = OmniscientGraph.build_dependency_adjacency(bindings)

  -- 拓扑排序
  local topo_order = OmniscientGraph.topological_sort(dep_adj, nodes)

  -- 检测钻石依赖
  local diamond_nodes = OmniscientGraph.detect_diamond_dependencies(dep_adj)

  -- 构建 graph 对象
  local graph = {
    app_name      = reg.name,
    states        = states,
    bindings      = bindings,
    events        = events,
    dep_adj       = dep_adj,
    topo_order    = topo_order,    -- nil 表示存在循环依赖
    diamond_nodes = diamond_nodes,
    nodes         = nodes,
  }

  -- ★ S1b: 如果提供了 MutationAST 和 EffectModel，计算 effects 和 event_chains
  opts = opts or {}
  local MutationAST  = opts.MutationAST
  local EffectModel  = opts.EffectModel

  if EffectModel and topo_order then
    -- 推导 effects
    local derive_graph = {
      bindings       = bindings,
      states         = states,
      texts          = reg.texts or {},
      visual_bindings = reg.visual_bindings,
    }
    graph.effects = EffectModel.derive_effects(derive_graph)
    graph.effects_for_state = EffectModel.build_effects_index(graph.effects, dep_adj)
  end

  if MutationAST and topo_order then
    -- 为每个事件计算传播链
    graph.event_chains = {}
    for _, evt in ipairs(events) do
      if evt.mutation then
        local stmts, parse_err = MutationAST.parse(evt.mutation)
        if stmts then
          local ws = MutationAST.write_set(stmts)
          local chain = OmniscientGraph.trace_propagation(ws, graph)
          graph.event_chains[#graph.event_chains + 1] = {
            event      = evt,
            write_set  = ws,
            chain      = chain,
            parse_error = nil,
          }
        else
          graph.event_chains[#graph.event_chains + 1] = {
            event      = evt,
            write_set  = {},
            chain      = {},
            parse_error = parse_err,
          }
        end
      end
    end
  end

  -- 编译期日志输出
  if topo_order then
    print(("[omniscient_graph] %s: %d states, %d bindings, %d events, topo_order=[%s], diamonds={%s}"):format(
      reg.name or "?",
      #nodes,
      #bindings,
      #events,
      table.concat(topo_order, ", "),
      (function()
        local d = {}
        for k, _ in pairs(diamond_nodes) do table.insert(d, k) end
        table.sort(d)
        return table.concat(d, ", ")
      end)()
    ))
  else
    print(("[omniscient_graph] %s: CIRCULAR DEPENDENCY DETECTED"):format(reg.name or "?"))
  end

  return graph
end

return OmniscientGraph
