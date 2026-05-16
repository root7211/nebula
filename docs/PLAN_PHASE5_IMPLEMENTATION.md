# Phase 5.0 实施计划：从方案到代码

**基准文档**：
- `PLAN_PHASE5_OMNISCIENT_GRAPH.md` — 原始设计方案（2026-05-16 合并）
- `PLAN_PHASE5_PATCH.md` — 6 项补丁规范（2026-05-16 提交）

**本计划整合了原始方案与补丁文档，定义了具体的实施步骤、里程碑、验收标准和产出物。**

---

## 0. 总体策略

### 实施原则

1. **基础设施先行**：在生成代码之前，先把 AST 解析、dirty bit 分配等基础模块写好
2. **每个梯队产出可验证的产物**：不仅是"代码写了"，而是"冒烟测试全绿"
3. **回归守护**：每一步都要确保 77/77 现有回归全绿
4. **补丁嵌入而非追加**：补丁不是"Phase 5.0 之后再做"，而是"Phase 5.0 的一部分"

### 梯队划分

```
原始梯队          补丁注入点
─────────         ──────────
S1 基础设施    →   + mutation_ast, dirty_map, effect_model 基础模块
S2 代码生成    →   + AST 解析 + Effect 推导 + dirty bit 多 chunk
S3 验证 Demo   →   + 路由去重测试 + hit-test 语义测试 + 快照测试
S4 动态内容    →   + Repeater 与 Effect 模型集成
S5 编辑器迁移  →   + 完整应用，所有补丁协同验证
```

---

## 第一梯队：核心基础设施 + 补丁基础模块

**目标**：全知图的构建和分析能力就绪 + 所有补丁的基础模块可独立测试。

**预计产出**：3 个新文件 + 1 个修改文件 + 1 个测试文件

### Step 1.0：mutation AST 解析器（补丁 1）

**文件**：`src/derive/mutation_ast.lua`（新增）

| 子任务 | 内容 | 验收 |
|:-------|:-----|:-----|
| 1.0.1 | 词法分析器（tokenizer） | 支持 token: IDENT, NUMBER, STRING, OP(+, -, *, /, etc.), DOT, EQ, AND, OR, NOT, IF, THEN, ELSE, LPAREN, RPAREN, COMMA, SELF |
| 1.0.2 | 语法分析器（recursive descent parser） | 生成 AST 节点（Literal, BinOp, UnaryOp, FieldAccess, Call, IfExpr, Assign） |
| 1.0.3 | `read_set(ast)` — 读取集合提取 | 遍历 AST 返回所有 FieldAccess 的名称集合 |
| 1.0.4 | `write_set(ast)` — 写入集合提取 | 返回所有 Assign 的 target 集合 |
| 1.0.5 | `emit(ast, indent)` — 代码生成 | 将 AST 转回合法的 Nelua 代码字符串 |
| 1.0.6 | 错误定位 | 解析失败时返回 `{message, line, column}` |
| 1.0.7 | 白名单函数校验 | 仅允许 snprintf, math.floor, math.ceil, math.max, math.min |

**测试用例**：

| 输入 | 期望 write_set | 期望 read_set |
|:-----|:---------------|:--------------|
| `self.count = self.count + 1` | `{"count"}` | `{"count"}` |
| `self.active = self.count > 0` | `{"active"}` | `{"count"}` |
| `self.x = self.y + self.z` | `{"x"}` | `{"y", "z"}` |
| `self.label = snprintf(buf, 32, "%d", self.count)` | `{"label"}` | `{"count"}` |
| `self.status = self.count > 0 and "ok" or "idle"` | `{"status"}` | `{"count"}` |
| `function foo() end` | 解析错误 | — |
| `self.x = 1; for i=1,10 do end` | 解析错误 | — |

### Step 1.1：dirty bit 分配策略（补丁 5）

**文件**：`src/derive/dirty_map.lua`（新增）

| 子任务 | 内容 | 验收 |
|:-------|:-----|:-----|
| 1.1.1 | `allocate(graph)` — 按拓扑序分配 bit | 返回 `{target -> bit_index}` 映射 |
| 1.1.2 | `storage_type(bit_count)` — 选择存储类型 | ≤8→uint8, ≤16→uint16, ≤32→uint32, ≤64→uint64, >64→array<uint64, N> |
| 1.1.3 | `gen_set(bit_index)` — 生成置位代码 | 单 chunk 和 multi-chunk 两种情况 |
| 1.1.4 | `gen_test(bit_index)` — 生成测试代码 | 单 chunk 和 multi-chunk 两种情况 |
| 1.1.5 | `gen_clear()` — 生成清零代码 | `self._dirty = 0` |
| 1.1.6 | 编译期日志输出 | smoke 测试中输出 dirty bit 分配表 |

### Step 1.2：Effect / Invalidation 模型（补丁 2）

**文件**：`src/derive/effect_model.lua`（新增）

| 子任务 | 内容 | 验收 |
|:-------|:-----|:-----|
| 1.2.1 | EffectKind 枚举定义 | gpu_update, text_update, layout_invalidate, redraw |
| 1.2.2 | Effect 结构定义 | kind, target, field, method, depends_on |
| 1.2.3 | `derive_effects_from_graph(graph)` — 自动推导 | 从 binding → text component / visual binding 推导 effect |
| 1.2.4 | `build_effects_for_state(graph)` — 建立 state→effects 反向索引 | `graph.effects_for_state[state]` 可查 |

### Step 1.3：依赖图构建与拓扑分析

**文件**：`src/derive/omniscient_graph.lua`（新增）

| 子任务 | 内容 | 验收 |
|:-------|:-----|:-----|
| 1.3.1 | `build_dependency_adjacency(bindings)` — 邻接表 | `adj[source] = [target...]` |
| 1.3.2 | `topological_sort(adj)` — Kahn 算法 | 循环依赖返回 nil |
| 1.3.3 | `detect_diamond_dependencies(adj)` — 入度>1 检测 | 返回 `{node -> true}` |
| 1.3.4 | `nebula_build_omniscient_graph(reg)` — 统一入口 | 返回完整 graph 对象（含 states, bindings, events, dep_adj, topo_order, diamond_nodes, effects_for_state） |
| 1.3.5 | `trace_propagation(mutation, graph)` — 路径追踪 | 使用 AST.write_set + Effect 模型，返回传播链 |

### Step 1.4：路由去重规则（补丁 3）

**文件**：`src/derive/event_router.lua`（新增）—— 仅基础接口

| 子任务 | 内容 | 验收 |
|:-------|:-----|:-----|
| 1.4.1 | `build_declared_event_set(reg)` — 事件注册表 | `declared[comp][event_type] = true` |
| 1.4.2 | 路由去重规则文档写入代码注释 | 声明事件独占，未声明事件回落 |

### Step 1.5：注册 API（原始方案 Step 1.1）

**文件**：`src/derive/app_factory.lua`（修改）

| 子任务 | 内容 | 验收 |
|:-------|:-----|:-----|
| 1.5.1 | `nebula_state(name, config)` 注册 | 数据存入 `reg._states[name] = config` |
| 1.5.2 | `nebula_bind(target, config)` 注册 | 数据存入 `reg._bindings[target] = config` |
| 1.5.3 | `nebula_on(target, event_type, config)` 注册 | 数据存入 `reg._events[] = {...}` |
| 1.5.4 | `nebula_app_end` 调用全知图构建 | 在 `nebula_app_end` 时调用 `nebula_build_omniscient_graph(reg)` |

### Step 1.6：冒烟测试

**文件**：`tests/smoke_phase5_0.lua`（新增）

| 测试场景 | 覆盖内容 |
|:---------|:---------|
| `test_linear_chain` | A→B→C 的拓扑序正确，无钻石节点 |
| `test_diamond_chain` | A→B, A→C, B→D, C→D 的拓扑序正确，D 标记为钻石 |
| `test_no_dependency` | 独立状态，拓扑序任意 |
| `test_circular_dependency` | A→B→A，`topological_sort` 返回 nil |
| `test_mutation_ast_read_set` | 补丁 1 的 read_set 正确提取 |
| `test_mutation_ast_write_set` | 补丁 1 的 write_set 正确提取 |
| `test_mutation_ast_syntax_error` | 非法语法返回错误信息 |
| `test_dirty_map_allocate` | 补丁 5 的 bit 分配正确 |
| `test_effect_derivation` | 补丁 2 的 effect 自动推导正确 |
| `test_event_set_building` | 补丁 3 的事件注册表正确 |

**验收标准**：冒烟测试全绿 + 77/77 现有回归全绿

---

## 第二梯队：代码生成

**目标**：从全知图生成端到端的 Nelua 代码，包括所有补丁集成。

**预计产出**：修改 3 个文件 + 1 个测试文件

### Step 2.1：State 字段生成

**文件**：`src/derive/app_factory.lua`（修改）—— `gen_app_record`

| 子任务 | 内容 | 验收 |
|:-------|:-----|:-----|
| 2.1.1 | 生成 `nebula_state` 声明的字段 | `count: int32` 等 |
| 2.1.2 | 生成 `_dirty` 字段 | 使用 DirtyMap.storage_type 选择类型 |
| 2.1.3 | 生成默认值初始化 | `self.count = 0` |

### Step 2.2：端到端路径函数生成

**文件**：`src/derive/binding_factory.lua`（新增）

| 子任务 | 内容 | 验收 |
|:-------|:-----|:-----|
| 2.2.1 | `emit_event_handler(graph, evt, emit)` — 生成事件 handler | 使用 AST.write_set 解析 mutation，使用 AST.emit 生成代码 |
| 2.2.2 | 传播链生成 | 使用 trace_propagation，effect 调用使用 emit_effect_call |
| 2.2.3 | 钻石节点 dirty 标记 | 使用 DirtyMap.gen_set 生成置位代码 |

### Step 2.3：钻石 commit 生成

**文件**：`src/derive/binding_factory.lua`

| 子任务 | 内容 | 验收 |
|:-------|:-----|:-----|
| 2.3.1 | `emit_commit(graph, emit)` — 生成 _commit 函数 | 按拓扑序 commit |
| 2.3.2 | dirty bit 测试和清零 | 使用 DirtyMap.gen_test 和 DirtyMap.gen_clear |
| 2.3.3 | multi-chunk 支持 | 超过 64 个钻石节点时生成数组访问 |

### Step 2.4：输入路由生成

**文件**：`src/derive/event_router.lua`

| 子任务 | 内容 | 验收 |
|:-------|:-----|:-----|
| 2.4.1 | `emit_input_router(graph, emit)` — 生成 _route_input | 按键事件路由 + 点击事件路由 |
| 2.4.2 | 点击 hit-test 使用运行时 bounds（补丁 4） | `hit_test_rect(mx, my, self.<comp>.visual.bounds)` |
| 2.4.3 | `emit_legacy_input_router(graph, emit)` — 生成 _route_legacy_input | 过滤已声明事件，转发到 process_input |
| 2.4.4 | 路由去重日志（可选） | 编译期警告：事件在两条路径中重复声明 |

### Step 2.5：update 集成

**文件**：`src/derive/app_factory.lua`（修改）—— `gen_app_update`

| 子任务 | 内容 | 验收 |
|:-------|:-----|:-----|
| 2.5.1 | 插入 `_route_input` 调用 | 在输入收集之后 |
| 2.5.2 | 插入 `_commit` 调用 | 在帧末（仅当有钻石节点时） |

### Step 2.6：代码生成冒烟测试

**文件**：`tests/smoke_phase5_0_s2.lua`（新增）

| 测试场景 | 覆盖内容 |
|:---------|:---------|
| `test_counter_generated_code` | counter demo 生成的代码结构正确 |
| `test_linear_chain_inline` | 线性链内联到 handler 中 |
| `test_diamond_commit_deferred` | 钻石节点延迟到 _commit |
| `test_no_framework_runtime` | 生成代码中无事件系统/依赖追踪代码 |
| `test_dirty_bit_multi_chunk` | 超过 64 个钻石节点时生成数组访问 |

**验收标准**：代码生成冒烟测试全绿 + 77/77 现有回归全绿

---

## 第三梯队：验证 Demo

**目标**：用真实 demo 验证端到端路径的正确性和性能。

### Step 3.1：创建 counter_binding_demo

**文件**：`examples/counter_binding_demo.nelua`（新增）

```nelua
require "nebula"

## nebula_visual("ButtonVisual", { primitives = {"clickable"} })
## nebula_visual("LabelVisual", { max_text_len = 32, max_lines = 1 })

## nebula_app("CounterApp", {
##   components = {
##     { name = "button", type = "ButtonVisual" },
##     { name = "label",  type = "LabelVisual",  bound_state = "label_text" },
##   },
##   states = {
##     { name = "count", type = "int32", default = 0 },
##     { name = "label_text", type = "cstring", default = '"Count: 0"' },
##   },
##   bindings = {
##     { target = "label_text", depends = {"count"},
##       compute = 'snprintf(self._label_buf, 32, "Count: %d", self.count)' },
##   },
##   events = {
##     { target = "button", event_type = "click",
##       mutation = 'self.count = self.count + 1' },
##   },
## })
```

### Step 3.2：编译运行

| 验证项 | 标准 |
|:-------|:-----|
| 编译通过 | nelua 编译无错误 |
| 点击按钮 | count 增加，label 更新 |
| 生成 C 代码审计 | 无事件系统、无依赖追踪、无调度器代码 |

### Step 3.3：路由去重验证

**文件**：`examples/routing_coexistence_demo.nelua`（新增，可选）

验证 `nebula_on` 与 `process_input` 并存时的去重规则：
- `nebula_on("button", "click")` 声明的事件由 `_route_input` 独占
- 未声明的事件（如鼠标移动）仍落到 `process_input`

### Step 3.4：结构稳定性回归测试（补丁 6）

**文件**：`tests/smoke_phase5_0_structure.lua`（新增）

| 测试项 | 内容 |
|:-------|:-----|
| `test_topo_order_stability` | 相同输入多次构建，拓扑序稳定 |
| `test_dirty_bit_stability` | dirty bit 分配稳定 |
| `test_generated_code_snapshot` | 生成代码与快照比对 |
| `test_handler_name_stability` | handler 名称格式稳定 |
| `test_effect_derivation_stability` | Effect 推导结果稳定 |

**验收标准**：counter_binding_demo 可运行 + 生成代码无框架运行时开销 + 77/77 现有回归全绿 + 结构稳定性测试全绿

---

## 第四梯队：动态内容扩展

**目标**：支持 Repeater 和条件渲染，与 Effect 模型集成。

### Step 4.1-4.5

按原始方案执行，额外要求：
- Repeater 的循环体内 binding 也能通过 Effect 模型推导
- 条件渲染的两分支代码生成中，dirty bit 分配需稳定

**验收标准**：动态 demo 可运行 + 77/77 现有回归全绿

---

## 第五梯队：编辑器迁移

**目标**：将 `text_editor_demo` 从手动接线迁移到全知图驱动。

### Step 5.1-5.4

按原始方案执行，额外验证：
- 所有 6 项补丁在真实应用中的协同工作
- 编辑器复杂场景下的 hit-test 语义（补丁 4）
- 编辑器状态超过 64 个时 dirty bit 的多 chunk 行为（补丁 5）

**验收标准**：text_editor_demo 功能不变 + 不再有文件级全局变量 + 77/77 现有回归全绿

---

## 关键决策记录

| 决策 | 结论 | 依据 |
|:-----|:-----|:-----|
| 补丁是否嵌入 Phase 5.0 主流程 | 是 | 补丁解决的是"可实现性"问题，不是"后续优化" |
| mutation AST 是否在第一梯队完成 | 是 | 第二梯队的代码生成依赖 AST |
| Effect 模型是否在第一梯队完成 | 是（基础模块） | 第一梯队完成数据结构，第二梯队完成代码生成集成 |
| 路由去重是否在第一梯队完成 | 是（接口） | 第二梯队生成代码时直接使用 |
| hit-test 运行时 bounds 是否在第一梯队明确 | 是（规则） | 第二梯队生成代码时按规则实现 |
| dirty bit 策略是否在第一梯队完成 | 是 | 第二梯队生成 _commit 函数依赖 DirtyMap |

---

## 风险矩阵

| 风险 | 概率 | 影响 | 缓解 |
|:-----|:-----|:-----|:-----|
| mutation AST 解析器覆盖不了所有合法用法 | 中 | 高 | 第一阶段仅支持最小子集，后续扩展 |
| 生成代码与现有 app_factory 冲突 | 低 | 高 | 第一梯队先不改现有生成逻辑，新增独立模块 |
| dirty bit 超过 64 时的多 chunk 逻辑复杂 | 低 | 中 | 第一梯队只支持单 chunk，第二梯队再加多 chunk |
| Effect 模型推导不完整 | 中 | 中 | 第一梯队只覆盖 text_update + gpu_update，其他类型后续添加 |
| 77/77 回归在某个梯队被破坏 | 中 | 高 | 每个梯队结束时跑全量回归 |

---

## 产出物清单

### 新增文件

| 文件 | 梯队 | 描述 |
|:-----|:-----|:-----|
| `src/derive/mutation_ast.lua` | S1 | mutation 受限语法 AST 解析器 |
| `src/derive/dirty_map.lua` | S1 | dirty bit 分配策略 |
| `src/derive/effect_model.lua` | S1 | Effect/Invalidation 模型 |
| `src/derive/omniscient_graph.lua` | S1 | 全知图构建与分析 |
| `src/derive/binding_factory.lua` | S2 | 端到端路径代码生成 |
| `src/derive/event_router.lua` | S1/S2 | 事件路由代码生成（S1 接口 + S2 完整实现） |
| `examples/counter_binding_demo.nelua` | S3 | 验证 demo |
| `examples/routing_coexistence_demo.nelua` | S3 | 路由去重验证（可选） |
| `tests/smoke_phase5_0.lua` | S1 | 基础设施冒烟测试 |
| `tests/smoke_phase5_0_s2.lua` | S2 | 代码生成冒烟测试 |
| `tests/smoke_phase5_0_structure.lua` | S3 | 结构稳定性回归测试 |
| `tests/test_snapshot.lua` | S3 | 快照测试基础设施 |
| `tests/snapshots/*.txt` | S3 | 生成代码快照 |

### 修改文件

| 文件 | 梯队 | 描述 |
|:-----|:-----|:-----|
| `src/derive/app_factory.lua` | S1/S2 | 注册 API + gen_app_record/state + gen_app_update |
| `src/nebula_core.nelua` | S2 | 导出编译期 API + hit_test_rect 辅助函数 |

---

## 验收标准总表

| 梯队 | 冒烟测试 | 回归测试 | 生成代码审计 |
|:-----|:---------|:---------|:-------------|
| S1 | 全绿（10 项） | 77/77 全绿 | — |
| S2 | 全绿（5 项） | 77/77 全绿 | — |
| S3 | — | 77/77 全绿 | counter demo 逐行审查通过 |
| S4 | — | 77/77 全绿 | — |
| S5 | — | 77/77 全绿 | 编辑器生成代码无框架运行时 |
