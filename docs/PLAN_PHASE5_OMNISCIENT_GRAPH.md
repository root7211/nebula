# Phase 5.0：全知图与端到端特化路径

**创建日期**：2026-05-16
**基准状态**：Era II 全部完成 | 77/77 回归全绿 | 架构审计 P0/P1 已修复

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
  
  -- Step 4: 为每个事件追踪端到端影响链
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
-- 返回有序的 {state_update, binding_recompute, gpu_update} 列表
function trace_propagation(mutation, graph)
  local chain = {}
  
  -- 解析 mutation 中涉及的状态名
  local mutated_states = parse_mutated_states(mutation)
  
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
      
      -- 查找受影响的 GPU 操作
      local gpu_op = find_gpu_effect(graph, state)
      if gpu_op then
        table.insert(chain, {
          type   = "gpu_update",
          target = gpu_op.component,
          op     = gpu_op.operation,
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
  
  -- Step 1: 执行 mutation
  emit(("  %s"):format(evt.mutation))
  
  -- Step 2: 沿传播链生成直接调用
  for _, step in ipairs(chain) do
    if step.type == "recompute" then
      -- 检查是否为钻石节点
      if graph.diamond_nodes[step.target] then
        -- 钻石依赖：标记 dirty，延迟到 _commit
        local bit = graph.dirty_bit_map[step.target]
        emit(("  self._dirty = self._dirty | %d"):format(bit))
      else
        -- 线性依赖：直接内联
        emit(("  -- recompute %s"):format(step.target))
        emit(("  %s"):format(step.compute))
      end
    elseif step.type == "gpu_update" then
      emit(("  -- update GPU: %s.%s"):format(step.target, step.op))
      emit(("  self.%s:%s(self)"):format(step.target, step.op))
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
  emit("  if self._dirty == 0 then return end")
  
  -- 按拓扑序 commit
  for _, node in ipairs(graph.topo_order) do
    if graph.diamond_nodes[node] then
      local bit = graph.dirty_bit_map[node]
      local binding = find_binding(graph.bindings, node)
      emit(("  if self._dirty & %d ~= 0 then"):format(bit))
      emit(("    %s"):format(binding.compute))
      -- 传播到下游 GPU 更新
      local gpu_op = find_gpu_effect(graph, node)
      if gpu_op then
        emit(("    self.%s:%s(self)"):format(gpu_op.component, gpu_op.operation))
      end
      emit("  end")
    end
  end
  
  emit("  self._dirty = 0")
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
  
  -- 点击事件路由
  local click_events = filter(graph.events, function(e) return e.event_type == "click" end)
  if #click_events > 0 then
    emit("  -- 点击路由（编译期生成的直接 hit-test 链）")
    emit("  if input.mouse_left_pressed then")
    for _, evt in ipairs(click_events) do
      local comp = find_component(graph, evt.target)
      if comp and graph.layout_results and graph.layout_results[evt.target] then
        local lr = graph.layout_results[evt.target]
        -- 编译期已知的坐标范围
        emit(("    -- %s bounds: known at compile time via layout_results"):format(evt.target))
        emit(("    if input.mouse_x >= self.%s.visual.position.x and"):format(evt.target))
        emit(("       input.mouse_x <= self.%s.visual.position.x + self.%s.visual.size.x and"):format(evt.target, evt.target))
        emit(("       input.mouse_y >= self.%s.visual.position.y and"):format(evt.target))
        emit(("       input.mouse_y <= self.%s.visual.position.y + self.%s.visual.size.y then"):format(evt.target, evt.target))
        emit(("      self:_%s_on_%s_click()"):format(graph.app_name, evt.target))
        emit(("    end"))
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
| `src/derive/app_factory.lua` | **修改** | 注册 API（`nebula_state`, `nebula_bind`, `nebula_on`, `nebula_repeater`, `nebula_when`）；`nebula_app_end` 中调用全知图构建；`gen_app_record` 生成状态字段和 `_dirty`；`gen_app_update` 插入 `_route_input` 和 `_commit` 调用 |
| `src/nebula_core.nelua` | **修改** | 导出 `nebula_state`/`nebula_bind`/`nebula_on` 编译期 API（转发到 Lua 注册函数） |
| `tests/smoke_phase5_0.lua` | **新增** | 全知图构建 + 代码生成冒烟测试 |

### 4.2 向后兼容性

**所有新增 API 为可选。** 不使用 `nebula_state`/`nebula_bind`/`nebula_on` 的现有 demo 走原有的 `process_input` 路径，行为不变。

兼容策略：

| 场景 | 行为 |
|:--|:--|
| 旧 demo（无 `nebula_state` 声明） | 全知图为空，不生成额外代码，走原有路径 |
| 新 demo（有 `nebula_state` 但也用 `process_input`） | 两套机制并存，`nebula_on` 处理声明的事件，`process_input` 处理未声明的 |
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

---

## 5. 实施计划

### 第一梯队：核心基础设施（S1 — 全知图引擎）

**目标**：建立全知图的构建和分析能力。此阶段不生成运行时代码，仅验证编译期分析正确性。

| Step | 任务 | 文件 | 验收标准 |
|:-----|:-----|:-----|:---------|
| 1.1 | 注册 API 实现 | `app_factory.lua` | `nebula_state`/`nebula_bind`/`nebula_on` 可被调用，数据存入 `reg._states`/`_bindings`/`_events` |
| 1.2 | 依赖图构建 | `omniscient_graph.lua` | `build_dependency_adjacency` 从 bindings 构建邻接表 |
| 1.3 | 拓扑排序 | `omniscient_graph.lua` | `topological_sort` 输出正确拓扑序；循环依赖时报错 |
| 1.4 | 钻石检测 | `omniscient_graph.lua` | `detect_diamond_dependencies` 正确标记入度 > 1 的节点 |
| 1.5 | 路径追踪 | `omniscient_graph.lua` | `trace_propagation` 从 mutation 追踪到叶子 GPU 操作 |
| 1.6 | 冒烟测试 | `tests/smoke_phase5_0.lua` | 覆盖线性链、钻石链、无依赖、循环依赖四种场景 |

**验收**：冒烟测试全绿 + 77/77 现有回归全绿

### 第二梯队：代码生成（S1 → Nelua 输出）

**目标**：从全知图生成端到端的 Nelua 代码。

| Step | 任务 | 文件 | 验收标准 |
|:-----|:-----|:-----|:---------|
| 2.1 | State 字段生成 | `app_factory.lua` | `gen_app_record` 生成 `nebula_state` 声明的字段 + `_dirty: uint64` |
| 2.2 | 端到端路径函数生成 | `binding_factory.lua` | 为每个 `nebula_on` 事件生成独立的处理函数 |
| 2.3 | 钻石 commit 生成 | `binding_factory.lua` | 为有钻石依赖的节点生成 `_commit()` 函数 |
| 2.4 | 输入路由生成 | `event_router.lua` | 生成 `_route_input` 函数，直接分发到端到端路径 |
| 2.5 | update 集成 | `app_factory.lua` | `gen_app_update` 在输入收集后调用 `_route_input`，帧末调用 `_commit` |
| 2.6 | 代码生成冒烟测试 | `tests/smoke_phase5_0_s2.lua` | 验证生成的代码结构正确 |

**验收**：生成的代码通过冒烟测试 + 77/77 现有回归全绿

### 第三梯队：验证 Demo

**目标**：用一个真实 demo 验证端到端路径的正确性和性能。

| Step | 任务 | 文件 | 验收标准 |
|:-----|:-----|:-----|:---------|
| 3.1 | 创建 counter_demo | `examples/counter_binding_demo.nelua` | 使用 `nebula_state` + `nebula_bind` + `nebula_on` 声明一个计数器 |
| 3.2 | 编译运行 | — | counter demo 能正确编译、运行、点击按钮后数字更新 |
| 3.3 | 对比验证 | — | 与手写等价代码的生成 C 产物对比，确认无多余间接调用 |
| 3.4 | 回归 | — | 现有 demo 全部不受影响 |

**验收**：counter_binding_demo 可运行 + 生成代码无框架运行时开销 + 全量回归绿

### 第四梯队：动态内容扩展

**目标**：支持 Repeater 和条件渲染。

| Step | 任务 | 文件 | 验收标准 |
|:-----|:-----|:-----|:---------|
| 4.1 | `nebula_repeater` API | `app_factory.lua` | 注册 API，数据存入 `reg._repeaters` |
| 4.2 | Repeater 代码生成 | `binding_factory.lua` | 生成模板化循环体 + 运行时 count 控制 |
| 4.3 | `nebula_when` API | `app_factory.lua` | 注册 API，数据存入 `reg._conditionals` |
| 4.4 | 条件渲染代码生成 | `binding_factory.lua` | 生成两分支代码 + 运行时 if 选择 |
| 4.5 | 动态 demo | `examples/dynamic_list_binding_demo.nelua` | 列表增删正确、条件渲染切换正确 |

**验收**：动态 demo 可运行 + 全量回归绿

### 第五梯队：编辑器迁移

**目标**：将 `text_editor_demo` 从手动接线迁移到全知图驱动，消除 `nebula_editor.nelua` 的 15 个全局变量。

| Step | 任务 | 验收标准 |
|:-----|:-----|:---------|
| 5.1 | 用 `nebula_state` 声明编辑器状态 | `_search_active`、`_editor_file_path` 等迁移为 App Record 字段 |
| 5.2 | 用 `nebula_bind` 声明编辑器绑定 | 标题栏文本 ← 文件名 + 修改标记 |
| 5.3 | 用 `nebula_on` 声明编辑器事件 | Ctrl+S → save, Ctrl+F → search |
| 5.4 | 删除 `nebula_editor.nelua` 全局变量 | 全部状态归入 App Record |

**验收**：text_editor_demo 功能不变 + `nebula_editor.nelua` 不再有文件级全局变量 + 全量回归绿

---

## 6. 关键决策记录

| 决策 | 结论 | 依据 |
|:-----|:-----|:-----|
| 依赖传播方式 | 线性内联 + 钻石延迟 | 线性链零开销；钻石链避免重复计算 |
| 是否引入运行时信号系统 | 否 | Nebula 编译器拥有全局视野，依赖图 S1 完全可知，不需要运行时追踪 |
| 是否引入运行时事件系统 | 否 | 组件位置和事件绑定 S1 已知，直接生成分发链 |
| 动态内容处理方式 | Repeater 模式 | 编译期生成模板，运行时只控制数量和数据 |
| 条件渲染处理方式 | 编译期生成两分支 | 两分支代码都编译，运行时 if 选择，无动态分配 |
| 与现有 `process_input` 的关系 | 并存 | 旧 demo 不改，新 demo 可选择全知图路径 |

---

## 7. 风险与缓解

| 风险 | 影响 | 缓解 |
|:-----|:-----|:-----|
| 大型 App 的依赖图导致生成代码膨胀 | 编译产物变大 | 钻石延迟策略已控制最坏情况；超过 64 个状态时可分组管理 |
| `nebula_on` 的 mutation 字段是字符串，难以静态分析 | 编译器无法自动追踪 mutation 中修改了哪些状态 | 约束 mutation 格式为 `self.xxx = ...`，编译器正则提取状态名 |
| 第三方组件需要源码接入全知图 | 限制预编译分发 | 对标 Nelua 生态的 `require` 模式；预编译组件可通过 `nebula_on` 接口声明输入输出 |
| Repeater 的 `max` 上限限制动态能力 | 列表超限时截断 | 提供运行时容量检查 + overflow 回调 |

---

## 8. 不做列表

| 排除项 | 理由 |
|:-------|:-----|
| 运行时信号/响应式系统 | 编译期全知图已覆盖，运行时信号为多余中间层 |
| 通用事件冒泡/捕获 | DOM 模型的概念，对编译期已知树结构无意义 |
| Virtual DOM / 树 diff | 树结构 S1 已知，无需运行时 diff |
| 热重载 | 可作为独立 Phase 在 5.0 之后实现（独立于全知图） |
| 通用 ECS / 组件注册表 | 与全知图的"编译期穷尽"原则冲突 |

---

## 9. 成功标准

Phase 5.0 完成后，以下目标应全部达成：

1. **50 行计数器 demo** — 使用 `nebula_state` + `nebula_bind` + `nebula_on` 声明，编译后无框架运行时开销
2. **编辑器迁移** — `text_editor_demo` 不再有文件级全局变量，全部状态通过全知图管理
3. **生成代码审计** — 对 counter demo 生成的 C 代码逐行审查，确认无事件系统、无依赖追踪、无调度器代码
4. **零回归** — 77/77 现有测试全绿
5. **公理合规** — axiom_validator 增加对 `nebula_state` / `nebula_bind` 的校验规则

---

## 10. 与总纲领的对齐

Phase 5.0 完成后，Nebula 的编译期消解覆盖将从 80% 提升到接近 100%：

```
Era I:  形即渲染 — Visual → Pipeline 编译期映射     ✅
Era II: 全功能框架 — 组件、布局、文本、编辑器       ✅
Phase 5.0: 全知图 — 状态、绑定、事件编译期消解       ← 当前
```

"GUI 编译器"的完整含义：**不是"一个编译到 C 的 GUI 框架"，而是"一个把 GUI 声明编译成最优 C 代码的编译器"。** Phase 5.0 是这个定义的最终兑现。
