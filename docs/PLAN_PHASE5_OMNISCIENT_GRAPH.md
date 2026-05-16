# Phase 5.0：全知图与端到端特化路径

**创建日期**：2026-05-16
**基准状态**：Era II 全部完成 | 77/77 回归全绿 | 架构审计 P0/P1 已修复
**更新日期**：2026-05-16（补丁整合版）

---

## 0. 动机：走完最后 20%

Nebula 的三条公理要求"凡是编译期可确定的，就不应该留到运行时"。

回顾现有的编译期消解清单：

| 传统框架用运行时做的事 | Nebula 已在 S1 消解 | Phase |
|:--|:--|:--|
| GPU 管线创建 | `pipeline_factory.lua` 编译期生成 | Phase 2 |
| 着色器编译 | `shader_compose.lua` 编译期生成 WGSL | Phase 2 |
| 状态机构建 | `nebula_derive` 生成 State/StateMachine/Context | Phase 1 |
| 交互分发 | `interaction_factory.lua` 生成 `process_input` | Phase 3 |
| 布局求解 | `layout_engine.lua` 编译期推导系数 | Phase 3.12 |
| 公理校验 | `axiom_validator.lua` 编译期验证 | Phase 4.0 |

但有两个领域仍在使用运行时通用机制，违反了 Axiom A 的判定准则：

| 领域 | 当前做法 | 公理违反 |
|:--|:--|:--|
| **依赖传播** | `nebula_editor.nelua` 的 15 个全局变量、手动命令式接线 | 依赖关系在 S1 已知，但传播逻辑写在 S2 |
| **事件路由** | `nebula_collect_input` 全局轮询 + 每组件独立 `process_input` | 组件位置和事件绑定在 S1 已知，路由逻辑应在 S1 生成 |

Phase 5.0 的目标是消解这两个领域，使 Nebula 的公理体系覆盖 GUI 程序的完整生命周期。

---

## 1. 核心概念：全知图（Omniscient Graph）

### 1.1 定义

全知图是编译器在 S1 阶段构建的 App 完整信息图。它包含：

```
OmniscientGraph = {
  -- 组件拓扑（已有，来自 app_factory 的 components/slots/texts/dense_texts）
  components: ComponentNode[],
  
  -- ★ 新增：状态声明（每个可变状态的名称、类型、初始值）
  states: StateDecl[],
  
  -- ★ 新增：绑定声明（状态 → 属性的映射关系 + 计算函数）
  bindings: BindingEdge[],
  
  -- ★ 新增：事件声明（输入事件 → 状态变化的映射）
  events: EventEdge[],
  
  -- 布局约束（已有，来自 layout_engine）
  layout: LayoutTree,
  
  -- 管线签名（已有，来自 pipeline_factory）
  pipelines: PipelineSignature[],
}
```

### 1.2 与公理体系的关系

| 公理 | 全知图的角色 |
|:--|:--|
| Axiom A（阶段封闭） | 全知图的全部信息在 S1 可知。编译器从全知图生成特化代码，S2 只执行 |
| Axiom B（三层生命周期） | 全知图本身是 S1 瞬时数据。其产出（struct 布局、函数体）归入 L0/L1 |
| Axiom C（形即渲染） | 全知图包含每个 Visual 的管线签名映射，Axiom C 是全知图的子集 |

### 1.3 设计原则

**P1：端到端特化。** 编译器为每一种输入事件生成一条从事件到 GPU 更新的直接代码路径。不经过通用事件系统、不经过依赖追踪器、不经过调度器。

**P2：线性链内联，钻石链延迟。** 依赖传播链为线性（A→B→C）时，直接内联到 setter 函数中。存在钻石依赖（A→C, B→C）时，生成 dirty bit + 帧末 commit，避免重复计算。

**P3：静态路径为主，动态岛为辅。** 编译期可确定的路径生成硬编码调用。运行时数量未知的动态内容（列表、条件渲染）隔离为"运行时岛"，使用编译期生成的模板 + 运行时循环。

---

## 2. 用户 API 设计

### 2.1 状态声明：`nebula_state`

在 `nebula_app_begin` / `nebula_app_end` 块内声明 App 级状态：

```lua
nebula_app_begin("CounterApp")
  -- ★ 新增 API
  nebula_state("count", {
    type    = "int32",
    default = 0,
  })
  
  nebula_state("label_text", {
    type    = "cstring",
    default = '"Count: 0"',
  })
  
  nebula_app_register_component("button", "ButtonVisual", { ... })
  nebula_app_register_text("label", "LabelVisual", { ... })
nebula_app_end()
```

### 2.2 绑定声明：`nebula_bind`

声明状态之间的派生关系：

```lua
nebula_app_begin("CounterApp")
  nebula_state("count", { type = "int32", default = 0 })
  
  -- ★ 绑定：count 变化时，label_text 自动更新
  nebula_bind("label_text", {
    depends = {"count"},
    compute = 'snprintf(self._label_buf, 32, "Count: %d", self.count); self.label_text = &self._label_buf[0]',
  })
  
  nebula_app_register_component("button", "ButtonVisual", { ... })
  nebula_app_register_text("label", "LabelVisual", {
    mode = "dynamic",
    bound_state = "label_text",  -- ★ 文本组件绑定到 state
  })
nebula_app_end()
```

### 2.3 事件声明：`nebula_on`

声明输入事件到状态变化的映射：

```lua
nebula_app_begin("CounterApp")
  -- ...states and bindings...
  
  nebula_app_register_component("button", "ButtonVisual", {
    component_id = 1,
    layout = { width = 100, height = 30 },
  })
  
  -- ★ 事件绑定：button 被点击时，count += 1
  nebula_on("button", "click", {
    mutation = 'self.count = self.count + 1',
  })
  
  -- ★ 全局快捷键
  nebula_on("_app", "key:Ctrl+R", {
    mutation = 'self.count = 0',
  })
nebula_app_end()
```

### 2.4 动态内容：`nebula_repeater`

运行时数量未知的列表：

```lua
nebula_app_begin("FileListApp")
  nebula_state("file_count", { type = "uint32", default = 0 })
  
  -- ★ Repeater：编译期生成模板，运行时控制数量
  nebula_repeater("items", "FileItemVisual", {
    max       = 256,
    count_var = "file_count",
    bind      = function(fields)
      -- 每个实例的绑定模板（编译期展开为特化代码）
      return {
        { field = "filename", source = "self.file_data[_i].name" },
        { field = "size",     source = "self.file_data[_i].size" },
      }
    end,
  })
nebula_app_end()
```

### 2.5 条件渲染：`nebula_when`

```lua
-- ★ 条件渲染：编译期生成两套代码，运行时选择
nebula_when("is_logged_in", {
  on_true  = function()
    nebula_app_register_component("dashboard", "DashboardVisual", { ... })
  end,
  on_false = function()
    nebula_app_register_component("login_form", "LoginFormVisual", { ... })
  end,
})
```

### 2.6 编译期调试：`## print(graph)`

在开发阶段，用户可以通过编译期打印指令查看全知图内容：

```nelua
## print(graph.topo_order)      -- 打印拓扑序
## print(graph.diamond_nodes)   -- 打印钻石节点
## print(graph.dirty_map)       -- 打印 dirty bit 分配表
## print(graph.effects)         -- 打印 Effect 推导结果
## print(graph.event_chains)    -- 打印事件传播链
```

这些打印语句仅在开发时保留，生产代码中删除。输出的信息包括：

| 打印项 | 内容 | 用途 |
|:-------|:-----|:-----|
| `graph.topo_order` | 状态拓扑序数组 | 验证依赖关系是否正确 |
| `graph.diamond_nodes` | 钻石节点集合 | 确认哪些状态会被延迟 commit |
| `graph.dirty_map` | `{name → bit_index}` 映射 | 审计 dirty bit 分配 |
| `graph.effects` | 每个 state 对应的 Effect 列表 | 验证渲染 invalidation 是否完整 |
| `graph.event_chains` | 每个事件的传播链 | 确认端到端路径覆盖范围 |

---

## 3. 编译器内部：全知图构建与代码生成

### 3.1 全知图构建（在 `nebula_app_end` 时执行）

```lua
-- derive/omniscient_graph.lua（新增文件）

function nebula_build_omniscient_graph(reg)
  local graph = {
    states   = reg._states   or {},
    bindings = reg._bindings or {},
    events   = reg._events   or {},
    components = reg.components,
    -- ...existing fields...
  }
  
  -- Step 1: 构建依赖邻接表
  graph.dep_adj = build_dependency_adjacency(graph.bindings)
  
  -- Step 2: 拓扑排序（检测循环依赖）
  graph.topo_order = topological_sort(graph.dep_adj)
  assert(graph.topo_order, "nebula: circular dependency detected in bindings")
  
  -- Step 3: 检测钻石依赖
  graph.diamond_nodes = detect_diamond_dependencies(graph.dep_adj)
  
  -- Step 4: 分配 dirty bit
  graph.dirty_map, graph.dirty_bit_count = DirtyMap.allocate(graph)
  
  -- Step 5: 推导 Effect
  graph.effects_for_state = derive_effects_from_graph(graph)
  
  -- Step 6: 为每个事件追踪端到端影响链
  graph.event_chains = {}
  for _, evt in ipairs(graph.events) do
    graph.event_chains[evt] = trace_propagation(evt.mutation, graph)
  end
  
  return graph
end
```

### 3.2 依赖图分析算法

```lua
-- 构建依赖邻接表
-- 输入：bindings = [{target, depends=[source...], compute}]
-- 输出：adj[source] = [target...]（source 变化时影响哪些 target）
function build_dependency_adjacency(bindings)
  local adj = {}
  for _, b in ipairs(bindings) do
    for _, dep in ipairs(b.depends) do
      adj[dep] = adj[dep] or {}
      table.insert(adj[dep], b.target)
    end
  end
  return adj
end

-- 拓扑排序（Kahn 算法）
function topological_sort(adj)
  local all_nodes = collect_all_nodes(adj)
  local in_degree = compute_in_degrees(adj, all_nodes)
  local queue, order = {}, {}
  
  for node, deg in pairs(in_degree) do
    if deg == 0 then table.insert(queue, node) end
  end
  
  while #queue > 0 do
    local node = table.remove(queue, 1)
    table.insert(order, node)
    for _, neighbor in ipairs(adj[node] or {}) do
      in_degree[neighbor] = in_degree[neighbor] - 1
      if in_degree[neighbor] == 0 then
        table.insert(queue, neighbor)
      end
    end
  end
  
  if #order < #all_nodes then return nil end  -- 循环依赖
  return order
end

-- 检测钻石依赖：入度 > 1 的节点
function detect_diamond_dependencies(adj)
  local in_degree = compute_in_degrees(adj, collect_all_nodes(adj))
  local diamonds = {}
  for node, deg in pairs(in_degree) do
    if deg > 1 then diamonds[node] = true end
  end
  return diamonds
end
```

### 3.3 端到端路径追踪

```lua
-- 从一个 mutation 出发，追踪完整的影响链
-- 返回有序的 {state_update, binding_recompute, effect} 列表
function trace_propagation(mutation, graph)
  local chain = {}
  
  -- 解析 mutation 中涉及的状态名（通过 AST）
  local stmts, err = MutationAST.parse(mutation)
  if err then return nil, err end
  local mutated_states = MutationAST.write_set(stmts)
  
  -- BFS 沿依赖图向下传播
  local visited = {}
  local queue = {}
  for _, s in ipairs(mutated_states) do
    table.insert(queue, s)
  end
  
  while #queue > 0 do
    local state = table.remove(queue, 1)
    if not visited[state] then
      visited[state] = true
      
      -- 查找受影响的绑定
      for _, target in ipairs(graph.dep_adj[state] or {}) do
        local binding = find_binding(graph.bindings, target)
        if binding then
          table.insert(chain, {
            type    = "recompute",
            target  = target,
            compute = binding.compute,
          })
          table.insert(queue, target)  -- 继续传播
        end
      end
      
      -- 使用 Effect 模型（而非猜测函数）
      local state_effects = graph.effects_for_state[state] or {}
      for _, effect in ipairs(state_effects) do
        table.insert(chain, {
          type   = "effect",
          effect = effect,
        })
      end
    end
  end
  
  return chain
end
```

### 3.4 代码生成：端到端路径函数

```lua
-- derive/binding_factory.lua（新增文件）

-- 为一个事件生成端到端处理函数
function emit_event_handler(graph, evt, emit)
  local chain = graph.event_chains[evt]
  local handler_name = ("%s_on_%s_%s"):format(
    graph.app_name, evt.target, evt.event_type)
  
  emit(("function %s:_%s()"):format(graph.app_name, handler_name))
  
  -- Step 1: 执行 mutation（通过 AST emit 生成合法 Nelua）
  local stmts = MutationAST.parse(evt.mutation)
  for _, line in ipairs(MutationAST.emit(stmts, 1)) do
    emit(line)
  end
  
  -- Step 2: 沿传播链生成直接调用
  for _, step in ipairs(chain) do
    if step.type == "recompute" then
      -- 检查是否为钻石节点
      if graph.diamond_nodes[step.target] then
        -- 钻石依赖：标记 dirty，延迟到 _commit
        local bit = graph.dirty_map[step.target]
        emit(DirtyMap.gen_set(bit))
      else
        -- 线性依赖：直接内联
        local binding = find_binding(graph.bindings, step.target)
        emit(("  -- recompute %s"):format(step.target))
        emit(("  %s"):format(binding.compute))
      end
    elseif step.type == "effect" then
      emit_effect_call(step.effect, emit)
    end
  end
  
  emit("end")
end

-- 为钻石节点生成 _commit 函数
function emit_commit(graph, emit)
  local has_diamonds = false
  for _ in pairs(graph.diamond_nodes) do has_diamonds = true; break end
  if not has_diamonds then return end
  
  emit(("function %s:_commit()"):format(graph.app_name))
  
  if graph.dirty_bit_count <= 64 then
    emit("  if self._dirty == 0 then return end")
  else
    local chunks = math.ceil(graph.dirty_bit_count / 64)
    for i = 0, chunks - 1 do
      emit(("  if self._dirty[%d] ~= 0 then"):format(i))
    end
  end
  
  -- 按拓扑序 commit
  for _, node in ipairs(graph.topo_order) do
    if graph.diamond_nodes[node] then
      local bit = graph.dirty_map[node]
      local binding = find_binding(graph.bindings, node)
      emit(("  if %s then"):format(DirtyMap.gen_test(bit)))
      emit(("    %s"):format(binding.compute))
      -- 传播到下游 Effect
      local effects = graph.effects_for_state[node] or {}
      for _, effect in ipairs(effects) do
        emit_effect_call(effect, emit)
      end
      emit("  end")
    end
  end
  
  emit(DirtyMap.gen_clear())
  
  if graph.dirty_bit_count > 64 then
    local chunks = math.ceil(graph.dirty_bit_count / 64)
    for i = 0, chunks - 1 do
      emit("  end")
    end
  end
  
  emit("end")
end
```

### 3.5 代码生成：输入路由

```lua
-- derive/event_router.lua（新增文件）

-- 生成编译期直接分发的输入路由函数
function emit_input_router(graph, emit)
  emit(("function %s:_route_input(input: *NebulaInputState)"):format(graph.app_name))
  
  -- 按键事件路由
  local key_events = filter(graph.events, function(e) return e.event_type:sub(1,4) == "key:" end)
  if #key_events > 0 then
    emit("  -- 快捷键路由（编译期生成的直接分发）")
    for _, evt in ipairs(key_events) do
      local key = evt.event_type:sub(5)  -- "key:Ctrl+S" → "Ctrl+S"
      local nk = map_key_name(key)
      emit(("  for _ki = 0, input.key_count - 1 do"))
      emit(("    if input.key_input[_ki] == NebulaKey.%s then"):format(nk))
      emit(("      self:_%s_on_%s_%s()"):format(graph.app_name, evt.target, evt.event_type:gsub("[:%+]", "_")))
      emit(("    end"))
      emit(("  end"))
    end
  end
  
  -- 点击事件路由（补丁 4：运行时 bounds + 编译期分发链）
  local click_events = filter(graph.events, function(e) return e.event_type == "click" end)
  if #click_events > 0 then
    emit("  -- 点击路由：分发链编译期生成，bounds 运行时读取")
    emit("  if input.mouse_left_pressed then")
    emit("    local mx, my = input.mouse_x, input.mouse_y")
    
    -- 按 z-order 反向遍历（上层组件优先）
    local ordered_clicks = reverse_z_order(click_events, graph)
    
    for _, evt in ipairs(ordered_clicks) do
      local comp = find_component(graph, evt.target)
      if comp then
        emit(("    if hit_test_rect(mx, my, self.%s.visual.bounds) then"):format(evt.target))
        emit(("      self:_%s_on_%s_click()"):format(graph.app_name, evt.target))
        emit(("      return"))  -- 命中后返回，不继续检查下层
        emit("    end")
      end
    end
    
    emit("  end")
  end
  
  emit("end")
end
```

---

## 4. 与现有架构的集成

### 4.1 改动文件清单

| 文件 | 改动类型 | 描述 |
|:--|:--|:--|
| `src/derive/omniscient_graph.lua` | **新增** | 全知图构建：依赖分析、拓扑排序、钻石检测、路径追踪 |
| `src/derive/binding_factory.lua` | **新增** | 绑定代码生成：端到端路径函数、_commit 函数 |
| `src/derive/event_router.lua` | **新增** | 事件路由代码生成：输入直接分发链 |
| `src/derive/mutation_ast.lua` | **新增** | mutation/compute 受限语法 AST 解析器 |
| `src/derive/effect_model.lua` | **新增** | Effect/Invalidation 模型与自动推导 |
| `src/derive/dirty_map.lua` | **新增** | dirty bit 分配策略与多 chunk 支持 |
| `src/derive/app_factory.lua` | **修改** | 注册 API + gen_app_record/state + gen_app_update + 全知图构建集成 |
| `src/nebula_core.nelua` | **修改** | 导出编译期 API + `hit_test_rect` 辅助函数 |
| `tests/smoke_phase5_0.lua` | **新增** | 全知图构建 + 代码生成冒烟测试 |
| `tests/smoke_phase5_0_structure.lua` | **新增** | 结构稳定性回归测试 |
| `tests/test_snapshot.lua` | **新增** | 快照测试基础设施 |
| `tests/snapshots/` | **新增** | 生成代码快照目录 |

### 4.2 向后兼容性

**所有新增 API 为可选。** 不使用 `nebula_state`/`nebula_bind`/`nebula_on` 的现有 demo 走原有的 `process_input` 路径，行为不变。

兼容策略：

| 场景 | 行为 |
|:--|:--|
| 旧 demo（无 `nebula_state` 声明） | 全知图为空，不生成额外代码，走原有路径 |
| 新 demo（有 `nebula_state` 但也用 `process_input`） | 两套机制并存，`nebula_on` 处理声明的事件，`process_input` 处理未声明的（见 §4.4 路由去重） |
| 完全迁移的 demo（只用 `nebula_on`） | 不再生成 `process_input` 调用，完全由端到端路径驱动 |

### 4.3 与现有子系统的关系

```
                    ┌──────────────────────────────┐
                    │    nebula_annotate (已有)      │
                    │    Visual 类型声明             │
                    └──────────┬───────────────────┘
                               │
    ┌──────────────────────────┼──────────────────────────┐
    ▼                          ▼                          ▼
┌──────────┐         ┌────────────────┐         ┌────────────────┐
│ pipeline │         │ interaction    │         │ shader         │
│ _factory │         │ _factory       │         │ _compose       │
│ (已有)    │         │ (已有)          │         │ (已有)          │
│ 管线生成  │         │ process_input  │         │ WGSL 生成      │
└──────────┘         └───────┬────────┘         └────────────────┘
                             │
                    ┌────────┴────────┐
                    ▼                 ▼
              现有路径            ★ 新增路径
           (process_input       (全知图端到端
            per-component)       特化路径)
                    │                 │
                    ▼                 ▼
            ┌────────────────────────────────┐
            │        app_factory (修改)       │
            │   gen_app_record / init /       │
            │   update / draw / deinit        │
            │   ★ + _route_input / _commit    │
            └────────────────────────────────┘
```

### 4.4 路由去重规则（补丁 3）

当 `nebula_on` 与 `process_input` 并存时，严格执行以下去重规则：

```
路由优先级规则：

1. nebula_on 声明的 (target, event_type) 组合由 _route_input 独占处理
2. 未被 nebula_on 声明的 (target, event_type) 组合才落到旧 process_input
3. 一个组件可以同时使用两种机制，但事件类型不重叠
```

实现：在 `nebula_app_end` 时构建已声明事件集合 `declared[comp][event_type]`，生成 `_route_legacy_input` 时过滤掉已声明的事件。

编译期警告示例：
```
nebula: component 'button' handles 'click' in both nebula_on and process_input.
  The nebula_on handler takes precedence; process_input will not receive this event.
```

### 4.5 hit-test 语义与动态岛（补丁 4）

#### 支持的范围

Phase 5.0 的 hit-test 模型支持：
- 静态/半静态布局的矩形命中测试
- 无嵌套滚动的平面布局
- 编译期已知 z-order 的组件

#### 动态岛清单（Phase 5.0 不支持，需使用 `process_input` 手动处理）

| 场景 | 原因 | 替代方案 |
|:-----|:-----|:---------|
| 滚动容器内的子组件 hit-test | bounds 随滚动偏移动态变化，编译期无法确定最终位置 | 在 `process_input` 中手动计算滚动后的 bounds |
| 嵌套裁剪区域（clip） | clip 区域可能运行时变化，hit-test 需要裁剪判断 | 使用 `process_input` + 手动裁剪检测 |
| 动态 z-order（运行时排序） | 组件层级顺序运行时变化，编译期分发链无法覆盖 | 使用 `process_input` + 运行时 z-order 排序 |
| 富文本局部命中 | 文字组件内不同字符有不同 bounds | 使用 `process_input` + 字符级 hit-test |
| 拖拽过程中的动态目标 | 拖拽目标在运行时变化 | 使用 `process_input` + 拖拽状态机 |

**架构债务记录**：上述动态岛场景将在 Phase 5.x 中作为扩展处理。在迁移 `text_editor_demo` 到全知图时（第五梯队），需要逐一审视其 hit-test 场景是否落入动态岛范围。如果落入，保留该场景的 `process_input` 处理，其余场景迁移到 `nebula_on`。

### 4.6 `axiom_validator` 新增规则

在 `axiom_validator.lua` 中新增以下规则（Rule 5-8）：

| 规则 | 内容 | 错误级别 |
|:-----|:-----|:---------|
| **Rule 5** | `mutation` 的 `write_set` 必须全部对应已声明的 `nebula_state` | 编译错误 |
| **Rule 6** | `compute` 的 `read_set` 必须是 `depends` 声明的超集（`depends` 中声明的状态必须被实际使用） | 编译警告 |
| **Rule 7** | `mutation` 和 `compute` 不得调用白名单以外的函数 | 编译错误 |
| **Rule 8** | 如果 `nebula_bind` 的 target 没有对应的 text component (`bound_state`) 或 visual binding 引用，则必须显式声明 `affects` 字段 | 编译错误 |

Rule 8 的理由：当 binding target 是一个纯逻辑中间变量（不被任何组件直接消费）时，编译器无法自动推导其 Effect。此时用户必须显式声明 `affects`，否则这个状态的变更将永远不会触发任何渲染更新。

---

## 5. 受限 DSL 规范（补丁 1）

### 5.1 允许的语法子集

`mutation` 和 `compute` 字段接受受限的 DSL 子集，编译期解析为 AST。

| 类别 | 允许 | 示例 |
|:-----|:-----|:-----|
| 赋值 | `self.<state> = <expr>` | `self.count = self.count + 1` |
| 算术运算 | `+`, `-`, `*, `/`, `%` | `self.x = self.x * 2` |
| 比较运算 | `==`, `!=`, `<`, `>`, `<=`, `>=` | `self.active = self.count > 0` |
| 逻辑运算 | `and`, `or`, `not` | `self.visible = self.active and not self.hidden` |
| 字段访问 | 仅 `self.<state>` | `self.label_text = self.count` |
| 白名单函数 | `snprintf`, `math.floor`, `math.ceil`, `math.max`, `math.min` | `snprintf(buf, 32, "Count: %d", self.count)` |
| 条件表达式 | `if <cond> then <expr> else <expr>` | `self.status = if self.count > 0 then "ok" else "idle"` |
| 字面量 | 整数、浮点、布尔、字符串（双引号） | `self.enabled = true` |

### 5.2 禁止的语法

| 类别 | 禁止 | 理由 |
|:-----|:-----|:-----|
| 函数调用 | 除白名单外的任意调用 | 无法静态分析 side effects |
| 外部变量 | 非 `self.` 开头的变量 | 破坏编译期封闭性 |
| 循环 | `for`, `while`, `repeat` | 复杂度不可控 |
| 表构造 | `{}` 表字面量 | 需要运行时分配 |
| 表索引访问 | `self.data[i]` | 运行时索引无法静态分析 |
| 方法调用 | `self:do_something()` | side effects 不可追踪 |
| 元方法 | `__index`, `__newindex` 等 | 运行时行为不可预测 |

### 5.3 不支持语法的回退策略

当用户的逻辑超出受限 DSL 范围时，有以下回退路径：

| 场景 | 回退方案 |
|:-----|:---------|
| 需要循环逻辑 | 在 `process_input` 中手写循环，或使用白名单函数 + 条件表达式组合 |
| 需要表索引访问 | 将数据操作封装为编译期可展开的固定大小循环（unroll），或使用 `process_input` |
| 需要方法调用 | 将方法体展开为 DSL 支持的语句序列，或在 `process_input` 中调用 |
| 需要复杂控制流 | 拆分多个 `nebula_on` 声明，或在 `process_input` 中处理 |

**重要**：受限 DSL 是 Phase 5.0 的初始版本限制。后续版本可能扩展语法子集（如支持表索引、更多白名单函数）。在 DSL 不支持的场景下，用户应回退到 `process_input` 手动处理，这不会影响应用的其他部分使用全知图。

### 5.4 AST 数据结构

```lua
-- derive/mutation_ast.lua（新增文件）

-- AST 节点类型
-- Expr = Literal | BinOp | UnaryOp | FieldAccess | Call | IfExpr
-- Stmt = Assign

Expr = {
  tag = "Literal",       value = 42,                 -- 整数/浮点/布尔/字符串
  tag = "BinOp",         op = "+", left = Expr, right = Expr,
  tag = "UnaryOp",       op = "not", operand = Expr,
  tag = "FieldAccess",   name = "count",             -- 自 self.<name> 提取
  tag = "Call",          fn = "snprintf", args = {Expr, ...},
  tag = "IfExpr",        cond = Expr, then_ = Expr, else_ = Expr,
}

Stmt = {
  tag = "Assign",        target = "count", value = Expr,  -- self.<target> = value
}
```

### 5.5 错误定位策略

| 错误类型 | 错误信息示例 |
|:---------|:-------------|
| 语法错误 | `nebula: mutation syntax error at line 3, col 12: unexpected token 'function'` |
| 禁止语法 | `nebula: mutation uses disallowed 'for' loop (allowed: assign, arithmetic, comparison, logic, whitelist functions)` |
| 未知状态 | `nebula: mutation references unknown state 'self.coutn' (did you mean 'count'?)` |
| 类型不匹配 | `nebula: mutation assigns string to state 'count' (declared as int32)` |
| 非白名单函数 | `nebula: mutation calls 'table.insert' which is not in whitelist (allowed: snprintf, math.floor, math.ceil, math.max, math.min)` |

---

## 6. Effect / Invalidation 模型（补丁 2）

### 6.1 问题

原始方案中 `find_gpu_effect(graph, state)` 是一个"猜测函数"，靠手写规则映射 state → GPU 操作。这会导致新增 Visual 类型时需要手动更新映射表，可能出现状态变化但未触发正确渲染 invalidation。

### 6.2 设计：从 BindingEdge 声明自动推导 Effect

#### BindingEdge 扩展

```lua
-- 扩展后（新增 affects 字段，可选）
nebula_bind("label_text", {
  depends = {"count"},
  compute = 'snprintf(self._label_buf, 32, "Count: %d", self.count)',
  affects = {
    { target = "label", field = "text", invalidation = "text_update" },
  },
})
```

#### Invalidation 类型枚举

```lua
-- derive/effect_model.lua（新增文件）

EffectKind = {
  "gpu_update",        -- 更新 GPU buffer / push constants / descriptor
  "text_update",       -- 更新文本缓存 / glyph atlas / vertex buffer
  "layout_invalidate", -- 标记布局需要重新求解
  "redraw",            -- 标记区域需要重绘
}

-- Effect 结构
Effect = {
  kind       = "text_update",       -- EffectKind
  target     = "label",             -- 组件名
  field      = "text",              -- 影响的 Visual 字段
  method     = "update_text",       -- 调用的更新方法名
  depends_on = "label_text",        -- 触发此 effect 的 state
}
```

#### 自动推导规则

当 `affects` 未指定时，编译器通过以下规则自动推导：

```lua
function derive_effects_from_graph(graph)
  local effects = {}
  
  for _, binding in ipairs(graph.bindings) do
    -- 规则 1：如果绑定目标是一个 text 组件的 bound_state
    local text_comp = find_text_component_by_bound_state(graph, binding.target)
    if text_comp then
      table.insert(effects, {
        kind       = "text_update",
        target     = text_comp.name,
        field      = "text",
        method     = "update_text",
        depends_on = binding.target,
      })
    end
    
    -- 规则 2：如果绑定目标是一个 Visual 的某个属性
    local visual_binding = find_visual_binding(graph, binding.target)
    if visual_binding then
      table.insert(effects, {
        kind       = "gpu_update",
        target     = visual_binding.component,
        field      = visual_binding.field,
        method     = visual_binding.update_method,
        depends_on = binding.target,
      })
    end
    
    -- 规则 3（axiom_validator Rule 8）：如果既不是 text 也不是 visual binding，
    -- 则必须显式声明 affects，否则编译报错
  end
  
  return effects
end
```

#### 在代码生成中使用

```lua
function emit_effect_call(effect, emit)
  if effect.kind == "text_update" then
    emit(("  self.%s:%s(self)"):format(effect.target, effect.method))
  elseif effect.kind == "gpu_update" then
    emit(("  self.%s:%s(self)"):format(effect.target, effect.method))
  elseif effect.kind == "layout_invalidate" then
    emit(("  self._layout_dirty = true"))
  elseif effect.kind == "redraw" then
    emit(("  self._needs_redraw = true"))
  end
end
```

---

## 7. dirty bit 分配策略（补丁 5）

### 7.1 绑定对象

```
dirty bit 绑定的是 **binding target**（即派生状态的名称），而非原始 state。

理由：
- 原始 state（如 count）的 mutation 在 event handler 中直接执行，不需要 dirty 标记
- 派生状态（如 label_text）可能依赖多个上游，需要 dirty 标记来延迟计算
```

### 7.2 分配策略

```lua
-- derive/dirty_map.lua（新增文件）

DirtyMap = {}

-- 为每个 binding target 分配 dirty bit
-- 返回: { target_name -> bit_index }, bit_count
function DirtyMap.allocate(graph)
  local map = {}
  local bit = 0
  
  -- 按拓扑序分配（保证 commit 顺序稳定）
  for _, node in ipairs(graph.topo_order) do
    if graph.diamond_nodes[node] then
      map[node] = bit
      bit = bit + 1
    end
  end
  
  return map, bit
end

-- 根据 bit 数量选择 dirty 存储类型
function DirtyMap.storage_type(bit_count)
  if bit_count <= 8  then return "uint8"
  elseif bit_count <= 16 then return "uint16"
  elseif bit_count <= 32 then return "uint32"
  elseif bit_count <= 64 then return "uint64"
  else
    local chunks = math.ceil(bit_count / 64)
    return ("array<uint64, %d]"):format(chunks)
  end
end

-- 生成 dirty bit 操作代码
function DirtyMap.gen_set(bit_index)
  if bit_index < 64 then
    return ("  self._dirty = self._dirty | (1ULL << %d)"):format(bit_index)
  else
    local chunk = bit_index // 64
    local offset = bit_index % 64
    return ("  self._dirty[%d] = self._dirty[%d] | (1ULL << %d)"):format(chunk, chunk, offset)
  end
end

function DirtyMap.gen_test(bit_index)
  if bit_index < 64 then
    return ("self._dirty & (1ULL << %d) ~= 0"):format(bit_index)
  else
    local chunk = bit_index // 64
    local offset = bit_index % 64
    return ("self._dirty[%d] & (1ULL << %d) ~= 0"):format(chunk, offset)
  end
end

function DirtyMap.gen_clear()
  return "  self._dirty = 0"  -- Nelua 的 = 0 会清零整个数组
end
```

---

## 8. 实施计划

### 梯队划分与补丁注入

```
梯队            补丁注入点
─────           ──────────
S1a 图构建    →   + dirty_map 基础模块 + omniscient_graph 核心
S1b AST 分析  →   + mutation_ast + effect_model + event_router 接口
S2 代码生成   →   + AST 解析集成 + Effect 推导 + dirty bit 多 chunk
S2.5 Nelua验证 →   + 生成代码 Nelua 编译检查（中间验收点）
S3 验证 Demo  →   + 路由去重测试 + hit-test 语义测试 + 快照测试 + C 产物审计
S4 动态内容   →   + Repeater 与 Effect 模型集成
S5 编辑器迁移 →   + 完整应用，所有补丁协同验证
```

### 第一梯队 a（S1a）：依赖图构建 + dirty bit 基础

**目标**：全知图的构建和分析能力就绪。此阶段不涉及 AST 解析，仅验证图结构正确性。

| Step | 任务 | 文件 | 验收标准 |
|:-----|:-----|:-----|:---------|
| 1a.1 | dirty bit 分配策略 | `dirty_map.lua` | allocate/storage_type/gen_set/gen_test/gen_clear 可独立测试 |
| 1a.2 | 依赖图构建 | `omniscient_graph.lua` | `build_dependency_adjacency` 从 bindings 构建邻接表 |
| 1a.3 | 拓扑排序 | `omniscient_graph.lua` | `topological_sort` 输出正确拓扑序；循环依赖时报错 |
| 1a.4 | 钻石检测 | `omniscient_graph.lua` | `detect_diamond_dependencies` 正确标记入度 > 1 的节点 |
| 1a.5 | 注册 API 实现 | `app_factory.lua` | `nebula_state`/`nebula_bind`/`nebula_on` 可被调用，数据存入 registry |
| 1a.6 | 全知图构建入口 | `omniscient_graph.lua` | `nebula_build_omniscient_graph(reg)` 返回完整 graph 对象 |
| 1a.7 | 冒烟测试 | `tests/smoke_phase5_0_s1a.lua` | 覆盖线性链、钻石链、无依赖、循环依赖、dirty bit 分配 |

**验收**：冒烟测试全绿 + 77/77 现有回归全绿

### 第一梯队 b（S1b）：AST 分析 + Effect 模型 + 路由接口

**目标**：mutation 受限语法解析 + Effect 自动推导 + 路由去重接口。

| Step | 任务 | 文件 | 验收标准 |
|:-----|:-----|:-----|:---------|
| 1b.1 | mutation AST 解析器 | `mutation_ast.lua` | tokenizer + parser + read_set/write_set/emit 可独立测试 |
| 1b.2 | 白名单函数校验 | `mutation_ast.lua` | 非白名单函数调用返回解析错误 |
| 1b.3 | Effect 模型 | `effect_model.lua` | EffectKind 枚举 + derive_effects_from_graph + effects_for_state 反向索引 |
| 1b.4 | 路径追踪集成 | `omniscient_graph.lua` | `trace_propagation` 使用 AST.write_set + Effect 模型 |
| 1b.5 | 路由去重接口 | `event_router.lua` | `build_declared_event_set` + 去重规则文档 |
| 1b.6 | 冒烟测试 | `tests/smoke_phase5_0_s1b.lua` | AST 解析、Effect 推导、路由去重 |

**验收**：冒烟测试全绿 + 77/77 现有回归全绿

### 第二梯队：代码生成

**目标**：从全知图生成端到端的 Nelua 代码。

| Step | 任务 | 文件 | 验收标准 |
|:-----|:-----|:-----|:---------|
| 2.1 | State 字段生成 | `app_factory.lua` | `gen_app_record` 生成 `nebula_state` 声明的字段 + `_dirty`（使用 DirtyMap.storage_type） |
| 2.2 | 端到端路径函数生成 | `binding_factory.lua` | 为每个 `nebula_on` 事件生成独立处理函数（使用 AST.emit 生成 mutation 代码） |
| 2.3 | 钻石 commit 生成 | `binding_factory.lua` | 为有钻石依赖的节点生成 `_commit()` 函数（使用 DirtyMap） |
| 2.4 | 输入路由生成 | `event_router.lua` | 生成 `_route_input`（运行时 bounds hit-test）+ `_route_legacy_input`（去重过滤） |
| 2.5 | update 集成 | `app_factory.lua` | `gen_app_update` 在输入收集后调用 `_route_input`，帧末调用 `_commit` |
| 2.6 | 代码生成冒烟测试 | `tests/smoke_phase5_0_s2.lua` | 验证生成的代码结构正确 |

**验收**：代码生成冒烟测试全绿 + 77/77 现有回归全绿

### 第二梯队.5：Nelua 编译验证（新增）

**目标**：确保生成的代码能通过 Nelua 编译器的语法检查。

| Step | 任务 | 验收标准 |
|:-----|:-----|:---------|
| 2.5.1 | 生成 counter demo 的完整 nelua 文件 | 使用 S2 的代码生成逻辑输出 `counter_binding_demo.nelua` |
| 2.5.2 | 运行 `nelua --compile-only` | 编译无错误（不链接、不运行） |
| 2.5.3 | 修复 type error | 如有 Nelua 层面的 type error（如 `@record` 字段类型不匹配），修复后重新验证 |

**验收**：`nelua --compile-only` 通过

**理由**：S1-S2 的 smoke 测试在纯 Lua 环境下运行（`dofile` factory 文件），无法捕捉 Nelua 层面的 type error。此中间验收点确保代码生成逻辑与 Nelua 类型系统兼容，避免 S3 才暴露编译错误。

### 第三梯队：验证 Demo

**目标**：用真实 demo 验证端到端路径的正确性和性能。

| Step | 任务 | 文件 | 验收标准 |
|:-----|:-----|:-----|:---------|
| 3.1 | 创建 counter_binding_demo | `examples/counter_binding_demo.nelua` | 使用 `nebula_state` + `nebula_bind` + `nebula_on` 声明 |
| 3.2 | Nelua 编译运行 | — | 编译无错误，点击按钮后 count 增加、label 更新 |
| 3.3 | 生成 C 代码审计 | — | 逐行审查 counter demo 生成的 C 产物，确认无事件系统、无依赖追踪、无调度器代码 |
| 3.4 | 路由去重验证 | `examples/routing_coexistence_demo.nelua` | `nebula_on` 与 `process_input` 并存时事件不重复触发 |
| 3.5 | 结构稳定性回归 | `tests/smoke_phase5_0_structure.lua` | 拓扑序/dirty bit/生成代码快照/handler 名称/Effect 推导稳定性 |

**验收**：counter_binding_demo 可运行 + C 产物审计通过 + 77/77 现有回归全绿 + 结构稳定性测试全绿

### 第四梯队：动态内容扩展

**目标**：支持 Repeater 和条件渲染。

| Step | 任务 | 验收标准 |
|:-----|:-----|:---------|
| 4.1-4.5 | 按原始方案执行 | Repeater 循环体内 binding 也能通过 Effect 模型推导；条件渲染 dirty bit 分配稳定 |

**验收**：动态 demo 可运行 + 77/77 现有回归全绿

### 第五梯队：编辑器迁移

**目标**：将 `text_editor_demo` 从手动接线迁移到全知图驱动。

| Step | 任务 | 验收标准 |
|:-----|:-----|:---------|
| 5.1-5.4 | 按原始方案执行 | 所有 6 项补丁协同验证；hit-test 动态岛场景正确处理；>64 状态时 dirty bit 多 chunk 行为正确 |

**验收**：text_editor_demo 功能不变 + `nebula_editor.nelua` 不再有文件级全局变量 + 77/77 现有回归全绿

---

## 9. 关键决策记录

| 决策 | 结论 | 依据 |
|:-----|:-----|:-----|
| 补丁是否嵌入 Phase 5.0 主流程 | 是 | 补丁解决的是"可实现性"问题，不是"后续优化" |
| S1 是否拆分 | 是（S1a + S1b） | S1 原范围过大（6 个新模块 + 10 项测试），拆分降低并行实现风险 |
| mutation AST 是否在 S1a 完成 | 否，移至 S1b | S1a 聚焦图构建，不依赖 AST；S1b 专门处理 AST + Effect |
| 是否增加 Nelua 编译验证 | 是（S2.5） | 纯 Lua smoke 测试无法捕捉 Nelua type error |
| Effect 模型是否在 S1a 完成 | 否，移至 S1b | S1a 完成数据结构，S1b 完成推导逻辑 |
| 路由去重是否在 S1a 完成 | 否（仅规则文档），S1b 完成接口 | S1a 聚焦图构建 |
| hit-test 运行时 bounds 是否在 S1a 明确 | 是（规则文档） | 第二梯队生成代码时按规则实现 |
| dirty bit 策略是否在 S1a 完成 | 是 | 图构建后即需 dirty bit 分配 |
| C 产物审计何时进行 | S3 | 必须在生成真实 demo 后立即审计，不等 S5 |

---

## 10. 风险矩阵

| 风险 | 概率 | 影响 | 缓解 |
|:-----|:-----|:-----|:-----|
| mutation AST 解析器覆盖不了所有合法用法 | 中 | 高 | S1b 仅支持最小子集，明确标注不支持语法的回退路径（§5.3），后续版本扩展 |
| 生成代码与现有 app_factory 冲突 | 低 | 高 | S1a-S1b 先不改现有生成逻辑，新增独立模块 |
| dirty bit 超过 64 时的多 chunk 逻辑复杂 | 低 | 中 | S1a 只支持单 chunk，S2 再加多 chunk |
| Effect 模型推导不完整 | 中 | 中 | S1b 只覆盖 text_update + gpu_update，layout_invalidate/redraw 后续添加；Rule 8 强制用户显式声明 |
| 77/77 回归在某个梯队被破坏 | 中 | 高 | 每个梯队结束时跑全量回归 |
| Nelua 编译验证暴露 type error | 中 | 高 | S2.5 中间验收点提前暴露，不等 S3 |
| hit-test 动态岛场景阻碍编辑器迁移 | 中 | 中 | S5 迁移时逐一审视 hit-test 场景，落入动态岛的保留 process_input |

---

## 11. 不做列表

| 排除项 | 理由 |
|:-------|:-----|
| 运行时信号/响应式系统 | 编译期全知图已覆盖，运行时信号为多余中间层 |
| 通用事件冒泡/捕获 | DOM 模型的概念，对编译期已知树结构无意义 |
| Virtual DOM / 树 diff | 树结构 S1 已知，无需运行时 diff |
| 热重载 | 可作为独立 Phase 在 5.0 之后实现（独立于全知图） |
| 通用 ECS / 组件注册表 | 与全知图的"编译期穷尽"原则冲突 |
| 复杂 hit-test（滚动容器/嵌套裁剪/动态 z-order/富文本局部命中） | Phase 5.0 仅支持平面布局矩形命中测试，复杂场景标记为动态岛，Phase 5.x 扩展 |

---

## 12. 成功标准

Phase 5.0 完成后，以下目标应全部达成：

1. **50 行计数器 demo** — 使用 `nebula_state` + `nebula_bind` + `nebula_on` 声明，编译后无框架运行时开销
2. **编辑器迁移** — `text_editor_demo` 不再有文件级全局变量，全部状态通过全知图管理
3. **生成代码审计** — 对 counter demo 生成的 C 代码逐行审查，确认无事件系统、无依赖追踪、无调度器代码
4. **零回归** — 77/77 现有测试全绿
5. **公理合规** — axiom_validator 新增 Rule 5-8，对 `nebula_state` / `nebula_bind` / `mutation` / `affects` 进行校验
6. **Nelua 编译通过** — 生成的代码能通过 `nelua --compile-only` 检查
7. **受限 DSL 文档完整** — 明确标注支持的语法子集、禁止的语法、以及不支持场景的回退路径

---

## 13. 与总纲领的对齐

Phase 5.0 完成后，Nebula 的编译期消解覆盖将从 80% 提升到接近 100%：

```
Era I:  形即渲染 — Visual → Pipeline 编译期映射     ✅
Era II: 全功能框架 — 组件、布局、文本、编辑器       ✅
Phase 5.0: 全知图 — 状态、绑定、事件编译期消解       ← 当前
```

"GUI 编译器"的完整含义：**不是"一个编译到 C 的 GUI 框架"，而是"一个把 GUI 声明编译成最优 C 代码的编译器"。** Phase 5.0 是这个定义的最终兑现。
