# Phase 5.0 全知图方案：完整补丁文档

**基准文档**：`docs/PLAN_PHASE5_OMNISCIENT_GRAPH.md`（2026-05-16 提交）
**评估来源**：`Phase5_0_全知图方案_契合度评估.md`
**目标**：将评估文档中的 6 项补丁清单落地为具体的 API/数据结构变更草案，使原始方案从"设计正确"升级为"可实现、可审计、可控"。

---

## 补丁 1：mutation / compute 的受限语法与 AST

### 1.1 问题

原始方案中 `mutation` 和 `compute` 是任意字符串，编译器用正则提取状态名。这导致：
- 语法错误延迟到 Nelua 编译阶段才暴露
- 错误栈无法回溯到用户声明处
- 静态分析（mutated states / read set）不完整
- 无法与 `axiom_validator` 配合

### 1.2 设计：受限语法（Constrained Syntax）

将 `mutation` / `compute` 从"任意字符串"收敛为一个极小 DSL 子集，编译期解析为 AST。

#### 允许的语法子集

| 类别 | 允许 | 示例 |
|:-----|:-----|:-----|
| 赋值 | `self.<state> = <expr>` | `self.count = self.count + 1` |
| 算术运算 | `+`, `-`, `*`, `/`, `%` | `self.x = self.x * 2` |
| 比较运算 | `==`, `!=`, `<`, `>`, `<=`, `>=` | `self.active = self.count > 0` |
| 逻辑运算 | `and`, `or`, `not` | `self.visible = self.active and not self.hidden` |
| 字段访问 | 仅 `self.<state>` | `self.label_text = self.count` |
| 白名单函数 | `snprintf`, `math.floor`, `math.ceil`, `math.max`, `math.min` | `snprintf(buf, 32, "Count: %d", self.count)` |
| 条件表达式 | `if <cond> then <expr> else <expr>` | `self.status = self.count > 0 and "ok" or "idle"` |
| 字面量 | 整数、浮点、布尔、字符串（双引号） | `self.enabled = true` |

#### 禁止的语法

| 类别 | 禁止 | 理由 |
|:-----|:-----|:-----|
| 函数调用 | 除白名单外的任意调用 | 无法静态分析 side effects |
| 外部变量 | 非 `self.` 开头的变量 | 破坏编译期封闭性 |
| 循环 | `for`, `while`, `repeat` | 复杂度不可控 |
| 表构造 | `{}` 表字面量 | 需要运行时分配 |
| 元方法 | `__index`, `__newindex` 等 | 运行时行为不可预测 |

### 1.3 AST 数据结构

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

### 1.4 解析器接口

```lua
local MutationAST = {}

-- 解析 mutation 字符串，返回 {stmts, error}
-- stmts: Stmt[]
-- error: {message, line, column} 或 nil
function MutationAST.parse(source)
  -- 词法分析 → 语法分析 → AST
  -- 如果解析失败，返回带行号/列号的错误信息
end

-- 从 AST 中提取被修改的状态名集合
function MutationAST.read_set(stmts)
  -- 遍历 AST，收集所有 FieldAccess 的 name
  -- 返回: { "count", "active", ... }
end

-- 从 AST 中被赋值的状态名集合
function MutationAST.write_set(stmts)
  -- 返回: { target for each Assign stmt }
end

-- 从 AST 中重新生成 Nelua 代码字符串
function MutationAST.emit(stmts, indent)
  -- 将 AST 转回为合法的 Nelua 代码
  -- indent: 缩进级别（默认 0）
  -- 返回: string
end
```

### 1.5 API 变更

```lua
-- 原始 API（仍支持，但已弃用，将在 Phase 5.1 移除）
nebula_on("button", "click", {
  mutation = 'self.count = self.count + 1',  -- 字符串，向后兼容
})

-- 新 API（推荐）
nebula_on("button", "click", {
  mutation = 'self.count = self.count + 1',  -- 仍为字符串，但内部经过 AST 解析
  -- 编译期会自动解析和校验，错误信息指向声明行
})

nebula_bind("label_text", {
  depends = {"count"},
  compute = 'snprintf(self._label_buf, 32, "Count: %d", self.count)',
  -- 如果 depends 未指定，编译器可从 compute 的 AST read_set 自动推导
})
```

### 1.6 错误定位策略

| 错误类型 | 错误信息示例 |
|:---------|:-------------|
| 语法错误 | `nebula: mutation syntax error at line 3, col 12: unexpected token 'function'` |
| 禁止语法 | `nebula: mutation uses disallowed 'for' loop (allowed: assign, arithmetic, comparison, logic, whitelist functions)` |
| 未知状态 | `nebula: mutation references unknown state 'self.coutn' (did you mean 'count'?)` |
| 类型不匹配 | `nebula: mutation assigns string to state 'count' (declared as int32)` |

### 1.7 与 axiom_validator 的集成

```lua
-- 在 axiom_validator 中新增规则：
-- Rule 5: mutation 的 write_set 必须对应已声明的 nebula_state
-- Rule 6: compute 的 read_set 必须是 depends 的超集（depends 中声明的状态必须被使用）
-- Rule 7: mutation 不得调用非白名单函数
```

---

## 补丁 2：Effect / Invalidation 模型

### 2.1 问题

原始方案中 `find_gpu_effect(graph, state)` 是一个"猜测函数"，靠手写规则映射 state → GPU 操作。这会导致：
- 新增 Visual 类型时需要手动更新映射表
- 可能出现状态变化但未触发正确渲染 invalidation
- 违背"可审计"原则

### 2.2 设计：从 BindingEdge 声明自动推导 Effect

#### BindingEdge 扩展

```lua
-- 原始
nebula_bind("label_text", {
  depends = {"count"},
  compute = 'snprintf(self._label_buf, 32, "Count: %d", self.count)',
})

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
  "gpu_update",     -- 更新 GPU buffer / push constants / descriptor
  "text_update",    -- 更新文本缓存 / glyph atlas / vertex buffer
  "layout_invalidate", -- 标记布局需要重新求解
  "redraw",         -- 标记区域需要重绘
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
  end
  
  return effects
end
```

#### 在代码生成中使用

```lua
-- 原始方案中的 trace_propagation 改为：
function trace_propagation(mutation, graph)
  local chain = {}
  local mutated_states = MutationAST.write_set(MutationAST.parse(mutation))
  
  -- BFS 沿依赖图向下传播
  local visited = {}
  local queue = {}
  for _, s in ipairs(mutated_states) do table.insert(queue, s) end
  
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
          table.insert(queue, target)
        end
      end
      
      -- ★ 改为使用 Effect 模型，而非 find_gpu_effect 猜测
      local state_effects = graph.effects_for_state[state] or {}
      for _, effect in ipairs(state_effects) do
        table.insert(chain, {
          type   = "effect",
          effect = effect,  -- Effect 结构
        })
      end
    end
  end
  
  return chain
end

-- 生成 effect 调用代码
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

### 2.3 API 变更

```lua
-- nebula_bind 新增可选字段
nebula_bind("label_text", {
  depends = {"count"},
  compute = '...',
  -- ★ 新增：显式声明此绑定影响哪些组件/字段
  -- 如果不指定，编译器自动推导
  affects = {
    { target = "label", field = "text", invalidation = "text_update" },
  },
})
```

---

## 补丁 3：路由去重规则

### 3.1 问题

原始方案允许 `nebula_on` 与 `process_input` 并存，但未定义去重规则，可能导致同一输入触发两次处理。

### 3.2 设计：声明事件独占规则

#### 规则定义

```
路由优先级规则（严格执行）：

1. nebula_on 声明的 (target, event_type) 组合由 _route_input 独占处理
2. 未被 nebula_on 声明的 (target, event_type) 组合才落到旧 process_input
3. 一个组件可以同时使用两种机制，但事件类型不重叠
```

#### 实现：事件注册表

```lua
-- derive/event_router.lua 中新增

-- 在 nebula_app_end 时构建已声明事件集合
function build_declared_event_set(reg)
  local declared = {}  -- declared[component_name][event_type] = true
  for _, evt in ipairs(reg._events or {}) do
    declared[evt.target] = declared[evt.target] or {}
    declared[evt.target][evt.event_type] = true
  end
  return declared
end

-- 在 app_factory.lua 的 gen_app_update 中修改输入分发逻辑
function gen_app_update_with_routing(graph, emit)
  local declared = build_declared_event_set(graph.reg)
  
  emit("function self:update(dt)")
  emit("  local input = self:_collect_input()")
  
  -- ★ Step 1: 全知图路由（处理已声明事件）
  if #graph.events > 0 then
    emit("  self:_route_input(input)")
  end
  
  -- ★ Step 2: 旧 process_input 路由（仅处理未声明事件）
  if has_process_input(graph) then
    emit("  self:_route_legacy_input(input)")
  end
  
  -- ★ Step 3: commit
  if has_diamond_nodes(graph) then
    emit("  self:_commit()")
  end
  
  emit("end")
end

-- 生成旧输入路由的过滤器
function emit_legacy_input_router(graph, emit, declared)
  emit("function self:_route_legacy_input(input)")
  emit("  -- 仅转发未被 nebula_on 声明的事件到 process_input")
  emit("  local filtered_input = input:clone()")
  
  -- 为每个组件过滤掉已声明的事件
  for comp_name, events in pairs(declared) do
    for event_type, _ in pairs(events) do
      emit(("  -- %s.%s is handled by nebula_on, skip in legacy path"):format(comp_name, event_type))
      -- 在 filtered_input 中标记该事件已处理
    end
  end
  
  emit("  self:process_input(filtered_input)")
  emit("end")
end
```

#### 编译期警告

```lua
-- 如果用户在 nebula_on 声明的事件类型和 process_input 中重复处理
-- 编译器发出警告：
-- "nebula: component 'button' handles 'click' in both nebula_on and process_input.
--  The nebula_on handler takes precedence; process_input will not receive this event."
```

---

## 补丁 4：hit-test 语义落地

### 4.1 问题

原始方案中点击路由假设 `graph.layout_results[evt.target]` 编译期已知，但 Nebula 支持动态文本等运行时尺寸变化的场景。

### 4.2 设计：编译期分发链 + 运行时 bounds

#### 规则定义

```
hit-test 语义规则：

1. 路由链的结构（hit-test 顺序、组件遍历顺序）在编译期确定
2. bounds 的来源允许运行时变化，从 self.<comp>.visual.bounds 读取
3. 暂不支持的复杂场景明确标记为"动态岛"：
   - 滚动容器内的子组件 hit-test
   - 嵌套裁剪区域
   - z-order 动态变化（运行时排序）
   - 文字组件的局部命中（富文本）
```

#### 实现

```lua
-- derive/event_router.lua 中修改点击路由生成

function emit_click_router(graph, emit)
  local click_events = filter(graph.events, function(e)
    return e.event_type == "click"
  end)
  if #click_events == 0 then return end
  
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

-- 使用统一的 hit_test_rect 辅助函数
-- 此函数在 nebula_core.nelua 中定义，读取运行时 bounds
-- function hit_test_rect(mx, my, bounds: Rect): bool
```

#### 不支持场景的声明

```lua
-- 在文档中明确标注：
-- Phase 5.0 的 hit-test 模型仅支持：
-- - 静态/半静态布局的矩形命中测试
-- - 无嵌套滚动的平面布局
-- 
-- 以下场景标记为"动态岛"，需使用 process_input 手动处理：
-- - 滚动容器内的子组件
-- - 嵌套裁剪（clip）
-- - 动态 z-order
-- - 富文本局部命中
-- 
-- 这些将在 Phase 5.x 中作为扩展处理。
```

### 4.3 与 interaction_factory 的关系

```
interaction_factory（已有）生成的 process_input 仍然保留，作为：
1. 旧 demo 的兼容路径
2. 动态岛场景的手动处理入口
3. 复杂 hit-test 的 fallback

全知图的 _route_input 是主路径，处理所有可静态确定的事件分发。
```

---

## 补丁 5：dirty bit 分配策略

### 5.1 问题

原始方案使用 `_dirty: uint64`，但未定义超过 64 个状态时的处理策略，也未明确 dirty bit 绑定的是 state 还是 binding target。

### 5.2 设计

#### dirty bit 绑定对象

```
dirty bit 绑定的是 **binding target**（即派生状态的名称），而非原始 state。

理由：
- 原始 state（如 count）的 mutation 在 event handler 中直接执行，不需要 dirty 标记
- 派生状态（如 label_text）可能依赖多个上游，需要 dirty 标记来延迟计算
```

#### 分配策略

```lua
-- derive/dirty_map.lua（新增文件）

DirtyMap = {}

-- 为每个 binding target 分配 dirty bit
-- 返回: { target_name -> bit_index }
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
  
  return map, bit  -- 返回 map 和最大 bit 数
end

-- 根据 bit 数量选择 dirty 存储类型
function DirtyMap.storage_type(bit_count)
  if bit_count <= 8  then return "uint8"
  elseif bit_count <= 16 then return "uint16"
  elseif bit_count <= 32 then return "uint32"
  elseif bit_count <= 64 then return "uint64"
  else
    -- 超过 64：使用数组
    local chunks = math.ceil(bit_count / 64)
    return ("array<uint64, %d]"):format(chunks)
  end
end

-- 生成 dirty bit 操作代码
function DirtyMap.gen_set(bit_index)
  if bit_index < 64 then
    return ("self._dirty = self._dirty | (1ULL << %d)"):format(bit_index)
  else
    local chunk = bit_index // 64
    local offset = bit_index % 64
    return ("self._dirty[%d] = self._dirty[%d] | (1ULL << %d)"):format(chunk, chunk, offset)
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
  return "self._dirty = 0"  -- 对数组类型也适用（Nelua 的 = 0 会清零整个数组）
end
```

#### 生成代码示例

```lua
-- ≤ 64 个钻石节点
function CounterApp:_commit()
  if self._dirty == 0 then return end
  -- topo order: label_text
  if self._dirty & (1ULL << 0) ~= 0 then
    snprintf(self._label_buf, 32, "Count: %d", self.count)
    self.label:update_text(self)
  end
  self._dirty = 0
end

-- > 64 个钻石节点
function LargeApp:_commit()
  -- chunk 0
  if self._dirty[0] ~= 0 then
    if self._dirty[0] & (1ULL << 0) ~= 0 then
      -- recompute node_0
    end
    if self._dirty[0] & (1ULL << 1) ~= 0 then
      -- recompute node_1
    end
  end
  -- chunk 1
  if self._dirty[1] ~= 0 then
    -- ...
  end
  self._dirty = 0
end
```

#### 编译期日志输出

```lua
-- 在 smoke 测试中输出 dirty bit 分配表，用于审计：
-- [dirty_bit_map] node_0 → bit 0
-- [dirty_bit_map] node_3 → bit 1
-- [dirty_bit_map] node_7 → bit 2
-- total bits: 3, storage: uint8
```

---

## 补丁 6：回归测试维度扩展

### 6.1 问题

原始方案只测运行结果，但不验证生成代码的结构稳定性。当编译器内部重构时，可能出现行为正确但生成结构大变的情况（如 topo 顺序改变导致性能退化）。

### 6.2 设计：双轨回归测试

#### 轨道 A：行为回归（已有）

```lua
-- tests/smoke_phase5_0.lua（已有的行为测试保持不变）
-- 验证：
-- - 线性链：A→B→C 的传播正确
-- - 钻石链：A→B, A→C, B→D, C→D 的计算只执行一次
-- - 无依赖：独立状态互不影响
-- - 循环依赖：编译期报错
```

#### 轨道 B：结构稳定性回归（新增）

```lua
-- tests/smoke_phase5_0_structure.lua（新增文件）

-- 测试 1：拓扑序稳定性
-- 给定相同的输入 app 定义，拓扑序必须稳定
function test_topo_order_stability()
  local app = define_test_app("CounterApp")
  local graph = nebula_build_omniscient_graph(app)
  
  -- 预期拓扑序
  assert_equal(graph.topo_order, {"count", "label_text", "button_color"})
  
  -- 多次构建，确保稳定
  for i = 1, 10 do
    local g2 = nebula_build_omniscient_graph(app)
    assert_equal(g2.topo_order, graph.topo_order)
  end
end

-- 测试 2：dirty bit 分配稳定性
function test_dirty_bit_stability()
  local app = define_test_app("DiamondApp")
  local graph = nebula_build_omniscient_graph(app)
  local dirty_map = DirtyMap.allocate(graph)
  
  -- 预期分配
  assert_equal(dirty_map["node_d"], 0)
  assert_equal(dirty_map["node_e"], 1)
end

-- 测试 3：生成代码快照比对
function test_generated_code_snapshot()
  local app = define_test_app("CounterApp")
  local code = generate_app_code(app)
  
  -- 将生成的代码与预期快照比对
  -- 快照文件：tests/snapshots/counter_app_generated.txt
  assert_snapshot("counter_app_generated", code)
  
  -- 如果快照不匹配，测试失败并输出 diff
  -- 开发者需要审阅 diff，确认变更是否合理，然后更新快照
end

-- 测试 4：事件 handler 名称稳定性
function test_handler_name_stability()
  local app = define_test_app("CounterApp")
  local graph = nebula_build_omniscient_graph(app)
  
  -- handler 名称格式：{app_name}_on_{target}_{event_type}
  local handler = graph.handlers["button_click"]
  assert_equal(handler.name, "CounterApp_on_button_click")
end

-- 测试 5：Effect 推导稳定性
function test_effect_derivation_stability()
  local app = define_test_app("TextBindingApp")
  local graph = nebula_build_omniscient_graph(app)
  
  -- 验证 effects_for_state 的推导结果稳定
  local effects = graph.effects_for_state["label_text"]
  assert_equal(#effects, 1)
  assert_equal(effects[1].kind, "text_update")
  assert_equal(effects[1].target, "label")
end
```

#### 快照测试基础设施

```lua
-- tests/test_snapshot.lua（新增基础设施）

local Snapshot = {}

function Snapshot.assert_snapshot(name, actual)
  local path = ("tests/snapshots/%s.txt"):format(name)
  
  if os.getenv("UPDATE_SNAPSHOTS") then
    -- 更新快照模式
    local f = io.open(path, "w")
    f:write(actual)
    f:close()
    print(("  [snapshot] updated: %s"):format(path))
    return true
  end
  
  local expected = read_file(path)
  if expected ~= actual then
    -- 输出 diff
    local diff = compute_diff(expected, actual)
    error(("snapshot mismatch: %s\n%s"):format(path, diff))
  end
end

return Snapshot
```

---

## 补丁汇总：对原始文档的变更映射

| 原始文档章节 | 补丁 | 变更类型 |
|:-------------|:-----|:---------|
| §2.2 `nebula_bind` | 补丁 2 | 新增 `affects` 字段（可选） |
| §2.3 `nebula_on` | 补丁 1, 3 | `mutation` 改为 AST 解析；新增路由去重规则 |
| §3.1 `nebula_build_omniscient_graph` | 补丁 2 | 新增 `graph.effects_for_state` |
| §3.3 `trace_propagation` | 补丁 2 | `find_gpu_effect` 替换为 Effect 模型 |
| §3.4 emit_event_handler | 补丁 1 | mutation 通过 AST.write_set 解析 |
| §3.5 emit_input_router | 补丁 4 | hit-test 改用运行时 bounds |
| §3.4 emit_commit | 补丁 5 | dirty bit 分配使用 DirtyMap 模块 |
| §4.2 向后兼容性 | 补丁 3 | 新增路由去重规则表 |
| §7 风险与缓解 | 补丁 1, 5 | 更新 mutation DSL 和 dirty bit 策略 |
| 新文件 | 补丁 1 | `derive/mutation_ast.lua` |
| 新文件 | 补丁 2 | `derive/effect_model.lua` |
| 新文件 | 补丁 5 | `derive/dirty_map.lua` |
| 新文件 | 补丁 6 | `tests/smoke_phase5_0_structure.lua` |
| 新文件 | 补丁 6 | `tests/test_snapshot.lua` |
| 新文件 | 补丁 6 | `tests/snapshots/*.txt` |

---

## 更新后的文件清单

| 文件 | 改动类型 | 描述 |
|:-----|:---------|:-----|
| `src/derive/omniscient_graph.lua` | 修改 | 新增 Effect 推导集成 |
| `src/derive/binding_factory.lua` | 修改 | 使用 AST 解析 mutation，使用 DirtyMap 分配 dirty bit |
| `src/derive/event_router.lua` | 修改 | 运行时 bounds hit-test，路由去重逻辑 |
| `src/derive/app_factory.lua` | 修改 | 路由去重集成 |
| `src/derive/mutation_ast.lua` | **新增** | mutation/compute 受限语法解析器 |
| `src/derive/effect_model.lua` | **新增** | Effect/Invalidation 模型与自动推导 |
| `src/derive/dirty_map.lua` | **新增** | dirty bit 分配与多 chunk 支持 |
| `src/nebula_core.nelua` | 修改 | 新增 `hit_test_rect` 辅助函数 |
| `tests/smoke_phase5_0.lua` | 修改 | 保持行为回归测试 |
| `tests/smoke_phase5_0_structure.lua` | **新增** | 结构稳定性回归测试 |
| `tests/test_snapshot.lua` | **新增** | 快照测试基础设施 |
| `tests/snapshots/` | **新增** | 生成代码快照目录 |

---

## 实施建议

这 6 个补丁可以分两批实施：

### 第一批（必须，阻塞 Phase 5.0 实作）

1. **补丁 1**：mutation AST 解析器（没有它，静态分析不稳）
2. **补丁 3**：路由去重规则（没有它，会出现双重触发 bug）
3. **补丁 5**：dirty bit 分配策略（没有它，超过 64 状态时行为未定义）

### 第二批（重要，但可在 Phase 5.0 第一梯队后追加）

4. **补丁 2**：Effect 模型（可以先用 find_gpu_effect 临时方案，再迁移）
5. **补丁 4**：hit-test 语义（可以先用 bounds 运行时读取，复杂场景后续扩展）
6. **补丁 6**：结构稳定性回归测试（可以在代码生成稳定后追加）
