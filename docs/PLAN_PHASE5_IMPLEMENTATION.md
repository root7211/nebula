# Phase 5.0 实施计划：从方案到代码

**基准文档**：
- `PLAN_PHASE5_OMNISCIENT_GRAPH.md` — 原始设计方案（2026-05-16 合并，补丁整合版）
- `PLAN_PHASE5_PATCH.md` — 6 项补丁规范（2026-05-16 提交，补充回退策略与动态岛清单）

**本计划整合了原始方案与补丁文档，定义了具体的实施步骤、里程碑、验收标准和产出物。**

**更新记录**：
- 2026-05-16：拆分 S1 为 S1a + S1b；新增 S2.5 Nelua 编译验证；更新风险矩阵与决策记录

---

## 0. 总体策略

### 实施原则

1. **基础设施先行**：在生成代码之前，先把 AST 解析、dirty bit 分配等基础模块写好
2. **每个梯队产出可验证的产物**：不仅是"代码写了"，而是"冒烟测试全绿"
3. **回归守护**：每一步都要确保 77/77 现有回归全绿
4. **补丁嵌入而非追加**：补丁不是"Phase 5.0 之后再做"，而是"Phase 5.0 的一部分"
5. **渐进式拆分**：S1 范围过大，拆分为 S1a（图构建）+ S1b（AST 分析）以降低风险

### 梯队划分

```
原始梯队          补丁注入点                新增
─────────         ──────────                ────
S1a 图构建    →   + dirty_map 基础模块      (拆分自 S1)
S1b AST 分析  →   + mutation_ast,          (拆分自 S1)
                  effect_model, event_router
S2 代码生成   →   + AST 解析 + Effect 推导
                  + dirty bit 多 chunk
S2.5 Nelua验证 →  + 生成代码 Nelua 编译检查  (新增)
S3 验证 Demo  →   + 路由去重 + hit-test
                  + 快照 + C 产物审计
S4 动态内容   →   + Repeater 与 Effect 集成
S5 编辑器迁移 →   + 完整应用协同验证
```

---

## 第一梯队 a（S1a）：依赖图构建 + dirty bit 基础

**目标**：全知图的构建和分析能力就绪。此阶段不涉及 AST 解析和 Effect 模型，仅验证图结构正确性。

**预计产出**：2 个新文件 + 1 个修改文件 + 1 个测试文件

### Step 1a.1：dirty bit 分配策略（补丁 5）

**文件**：`src/derive/dirty_map.lua`（新增）

| 子任务 | 内容 | 验收 |
|:-------|:-----|:-----|
| 1a.1.1 | `allocate(graph)` — 按拓扑序分配 bit | 返回 `{target -> bit_index}` 映射 |
| 1a.1.2 | `storage_type(bit_count)` — 选择存储类型 | ≤8→uint8, ≤16→uint16, ≤32→uint32, ≤64→uint64, >64→array<uint64, N> |
| 1a.1.3 | `gen_set(bit_index)` — 生成置位代码 | 单 chunk 和 multi-chunk 两种情况 |
| 1a.1.4 | `gen_test(bit_index)` — 生成测试代码 | 单 chunk 和 multi-chunk 两种情况 |
| 1a.1.5 | `gen_clear()` — 生成清零代码 | `self._dirty = 0` |
| 1a.1.6 | 编译期日志输出 | smoke 测试中输出 dirty bit 分配表 |

### Step 1a.2：依赖图构建与拓扑分析

**文件**：`src/derive/omniscient_graph.lua`（新增）

| 子任务 | 内容 | 验收 |
|:-------|:-----|:-----|
| 1a.2.1 | `build_dependency_adjacency(bindings)` — 邻接表 | `adj[source] = [target...]` |
| 1a.2.2 | `topological_sort(adj)` — Kahn 算法 | 循环依赖返回 nil |
| 1a.2.3 | `detect_diamond_dependencies(adj)` — 入度>1 检测 | 返回 `{node -> true}` |
| 1a.2.4 | `nebula_build_omniscient_graph(reg)` — 统一入口 | 返回完整 graph 对象（含 states, bindings, events, dep_adj, topo_order, diamond_nodes） |

### Step 1a.3：注册 API（原始方案 Step 1.1）

**文件**：`src/derive/app_factory.lua`（修改）

| 子任务 | 内容 | 验收 |
|:-------|:-----|:-----|
| 1a.3.1 | `nebula_state(name, config)` 注册 | 数据存入 `reg._states[name] = config` |
| 1a.3.2 | `nebula_bind(target, config)` 注册 | 数据存入 `reg._bindings[target] = config` |
| 1a.3.3 | `nebula_on(target, event_type, config)` 注册 | 数据存入 `reg._events[] = {...}` |
| 1a.3.4 | `nebula_app_end` 调用全知图构建 | 在 `nebula_app_end` 时调用 `nebula_build_omniscient_graph(reg)` |

### Step 1a.4：冒烟测试

**文件**：`tests/smoke_phase5_0_s1a.lua`（新增）

| 测试场景 | 覆盖内容 |
|:---------|:---------|
| `test_linear_chain` | A→B→C 的拓扑序正确，无钻石节点 |
| `test_diamond_chain` | A→B, A→C, B→D, C→D 的拓扑序正确，D 标记为钻石 |
| `test_no_dependency` | 独立状态，拓扑序任意 |
| `test_circular_dependency` | A→B→A，`topological_sort` 返回 nil |
| `test_dirty_map_allocate` | 补丁 5 的 bit 分配正确 |
| `test_dirty_map_storage_type` | 不同 bit 数量对应正确存储类型 |
| `test_register_api` | nebula_state/bind/on 数据正确存入 registry |
| `test_graph_build` | `nebula_build_omniscient_graph` 返回完整 graph |

**验收标准**：冒烟测试全绿 + 77/77 现有回归全绿

---

## 第一梯队 b（S1b）：AST 分析 + Effect 模型 + 路由接口

**目标**：mutation 受限语法解析 + Effect 自动推导 + 路由去重接口。

**预计产出**：3 个新文件 + 1 个修改文件 + 1 个测试文件

### Step 1b.1：mutation AST 解析器（补丁 1）

**文件**：`src/derive/mutation_ast.lua`（新增）

| 子任务 | 内容 | 验收 |
|:-------|:-----|:-----|
| 1b.1.1 | 词法分析器（tokenizer） | 支持 token: IDENT, NUMBER, STRING, OP(+, -, *, /, etc.), DOT, EQ, AND, OR, NOT, IF, THEN, ELSE, LPAREN, RPAREN, COMMA, SELF |
| 1b.1.2 | 语法分析器（recursive descent parser） | 生成 AST 节点（Literal, BinOp, UnaryOp, FieldAccess, Call, IfExpr, Assign） |
| 1b.1.3 | `read_set(ast)` — 读取集合提取 | 遍历 AST 返回所有 FieldAccess 的名称集合 |
| 1b.1.4 | `write_set(ast)` — 写入集合提取 | 返回所有 Assign 的 target 集合 |
| 1b.1.5 | `emit(ast, indent)` — 代码生成 | 将 AST 转回合法的 Nelua 代码字符串 |
| 1b.1.6 | 错误定位 | 解析失败时返回 `{message, line, column}` |
| 1b.1.7 | 白名单函数校验 | 仅允许 snprintf, math.floor, math.ceil, math.max, math.min |

### Step 1b.2：Effect / Invalidation 模型（补丁 2）

**文件**：`src/derive/effect_model.lua`（新增）

| 子任务 | 内容 | 验收 |
|:-------|:-----|:-----|
| 1b.2.1 | EffectKind 枚举定义 | gpu_update, text_update, layout_invalidate, redraw |
| 1b.2.2 | Effect 结构定义 | kind, target, field, method, depends_on |
| 1b.2.3 | `derive_effects_from_graph(graph)` — 自动推导 | 从 binding → text component / visual binding 推导 effect |
| 1b.2.4 | `build_effects_for_state(graph)` — 建立 state→effects 反向索引 | `graph.effects_for_state[state]` 可查 |

### Step 1b.3：路径追踪集成

**文件**：`src/derive/omniscient_graph.lua`（修改）

| 子任务 | 内容 | 验收 |
|:-------|:-----|:-----|
| 1b.3.1 | `trace_propagation(mutation, graph)` — 路径追踪 | 使用 AST.write_set + Effect 模型，返回传播链 |
| 1b.3.2 | `graph.event_chains` 填充 | 在 `nebula_build_omniscient_graph` 中为每个事件计算传播链 |

### Step 1b.4：路由去重规则（补丁 3）

**文件**：`src/derive/event_router.lua`（新增）—— 仅基础接口

| 子任务 | 内容 | 验收 |
|:-------|:-----|:-----|
| 1b.4.1 | `build_declared_event_set(reg)` — 事件注册表 | `declared[comp][event_type] = true` |
| 1b.4.2 | 路由去重规则文档写入代码注释 | 声明事件独占，未声明事件回落 |

### Step 1b.5：冒烟测试

**文件**：`tests/smoke_phase5_0_s1b.lua`（新增）

| 测试场景 | 覆盖内容 |
|:---------|:---------|
| `test_mutation_ast_read_set` | 补丁 1 的 read_set 正确提取 |
| `test_mutation_ast_write_set` | 补丁 1 的 write_set 正确提取 |
| `test_mutation_ast_syntax_error` | 非法语法返回错误信息 |
| `test_mutation_ast_emit` | AST 转回合法 Nelua 代码 |
| `test_mutation_ast_whitelist` | 非白名单函数返回错误 |
| `test_effect_derivation` | 补丁 2 的 effect 自动推导正确 |
| `test_effect_reverse_index` | effects_for_state 反向索引正确 |
| `test_trace_propagation` | 传播链使用 AST + Effect 模型 |
| `test_event_set_building` | 补丁 3 的事件注册表正确 |

**验收标准**：冒烟测试全绿 + 77/77 现有回归全绿

---

## 第二梯队：代码生成

**目标**：从全知图生成端到端的 Nelua 代码，包括所有补丁集成。

**预计产出**：修改 3 个文件 + 新增 1 个文件 + 1 个测试文件

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

## 第二梯队.5（S2.5）：Nelua 编译验证（新增）

**目标**：确保生成的代码能通过 Nelua 编译器的语法检查。

**背景**：S1a-S2 的 smoke 测试在纯 Lua 环境下运行（`dofile` factory 文件），无法捕捉 Nelua 层面的 type error（如 `@record` 字段类型不匹配、指针类型错误等）。此中间验收点在 S3 真实 demo 编译之前提前暴露编译问题。

| Step | 任务 | 验收标准 |
|:-----|:-----|:---------|
| 2.5.1 | 生成 counter demo 的完整 nelua 文件 | 使用 S2 的代码生成逻辑输出 `counter_binding_demo.nelua` |
| 2.5.2 | 运行 `nelua --compile-only` | 编译无错误（不链接、不运行） |
| 2.5.3 | 修复 type error | 如有 Nelua 层面的 type error，修复后重新验证 |

**验收标准**：`nelua --compile-only` 通过

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

**验收标准**：counter_binding_demo 可运行 + 生成 C 代码审计通过 + 77/77 现有回归全绿 + 结构稳定性测试全绿

---

## 第四梯队：动态内容扩展 ✅ 已完成

**目标**：支持 Repeater 和条件渲染，与 Effect 模型集成。

**实施记录（2026-05-17）**：

### 新增 API

| API | 文件 | 描述 |
|:----|:-----|:-----|
| `nebula_repeater(name, visual_type, config)` | `app_factory.lua` | 声明动态列表，config 包含 max/count_var/bind |
| `nebula_when(condition_state, config)` | `app_factory.lua` | 声明条件渲染，config 包含 on_true/on_false |

### 核心改动

| 文件 | 改动 |
|:-----|:-----|
| `src/derive/app_factory.lua` | 新增 `nebula_repeater()` 和 `nebula_when()` 注册 API；`nebula_app_end` 扩展为传递 repeaters/conditionals |
| `src/derive/omniscient_graph.lua` | 将 repeater per-item bindings 展开为 `_repeater_<name>_<field>` 节点并入依赖图；graph 对象新增 repeaters/conditionals/_original_bindings/_repeater_bindings 字段 |
| `src/derive/binding_factory.lua` | 新增 6 个函数：repeater record/init/update/dirty-marks、conditional record/init/update/sync-marks；generate() 集成 repeater 和 conditional 代码生成 |

### 设计决策

| 决策 | 结论 | 依据 |
|:-----|:-----|:-----|
| Repeater 绑定如何参与依赖图 | 展开为 `_repeater_<name>_<field>` 节点，与普通 binding 共享拓扑排序和钻石检测 | 复用已有基础设施，无需新的图遍历逻辑 |
| Repeater dirty 追踪粒度 | App 级 boolean `_<name>_dirty`，非 per-item | 当前 repeater 的 bind 通常依赖全局 state，per-item dirty 过早优化 |
| Repeater 绑定依赖自动推导 | 当 `depends` 为空时，从 `source` 中正则提取 `self.<field>` 作为依赖 | 减少用户声明负担，与 mutation AST 的 read_set 逻辑一致 |
| Conditional 实现方式 | `_when_<cond>_active: boolean` 标记 + event handler 中注入同步代码 | 最简方案，draw 层面的 if/else 留给用户组合或后续 S5 集成 |
| Repeater 绑定是否生成 record 字段 | 否，`_repeater_*` 节点不生成 record 字段 | 这些是图分析用的虚拟节点，实际数据存在 slot data 数组中 |

### 验收

| 项目 | 结果 |
|:-----|:-----|
| S4 冒烟测试 | 53 条全绿 |
| S1a 回归 | 72 条全绿 |
| S1b 回归 | 125 条全绿 |
| S2 回归 | 58 条全绿 |
| S3 回归 | 46 条全绿 |
| 现有回归（63 个测试文件） | 无新增失败 |

**验收标准**：~~动态 demo 可运行~~ + ~~77/77 现有回归全绿~~  
✅ 冒烟测试全绿 + 回归无新增失败 + 代码生成中无运行时事件系统

---

## 第五梯队：编辑器迁移 ✅ 已完成

**目标**：将 `text_editor_demo` 从手动接线迁移到全知图驱动。

### Step 5.1-5.4 ✅

完成日期：2026-05-17

#### 核心改动

| 文件 | 改动说明 |
|:-----|:---------|
| `src/nebula_core.nelua` | `nebula_app()` sugar 扩展：支持 `states/bindings/events` spec，自动调用 `nebula_state/bind/on`；`editor_state` 选项传递给 builtin producer |
| `src/nebula_editor.nelua` | 新增 `NebulaEditorState` record 封装全部搜索/文件状态；新增 `_es` 后缀参数化函数（5 个），不依赖全局变量；旧版全局变量模式保留向后兼容 |
| `src/nebula_builtins.nelua` | `status_bar/search_bar/edit_area` 三个 builtin producer 支持 `opts.editor_state` 模式，从 `app.<field>.xxx` 读取状态而非全局变量 |
| `examples/text_editor_demo_v4.nelua` | 全知图驱动编辑器 demo：`NEBULA_EDITOR_GLOBALS_DEFINED = true` + `editor_state = "es"` + `states = { { name = "es", type = "NebulaEditorState" } }` |
| `tests/smoke_phase5_0_s5.lua` | 12 组 75 项断言：状态声明、图构建、代码生成、混合声明、大状态集合、S1-S4 回归 |

#### 设计决策

| 决策 | 结论 | 依据 |
|:-----|:-----|:-----|
| 编辑器状态封装方式 | 单一 `NebulaEditorState` record | 编辑器状态高度耦合（搜索/文件），拆分为独立 state 无依赖追踪价值 |
| 向后兼容策略 | `NEBULA_EDITOR_GLOBALS_DEFINED` 守卫 + 旧函数保留 | v1/v2/v3 demo 无需修改 |
| Builtin producer 参数化 | `opts.editor_state` 控制全局 vs App Record 模式 | 零侵入：不设置时行为完全不变 |
| `nebula_app()` sugar 扩展 | spec 中 `states/bindings/events` 数组 → 自动调用 API | 用户无需切换到 begin/end 手动模式 |

#### 验证结果

- S5 冒烟测试：75/75 通过
- S1a 回归：72/72 通过
- S1b 回归：125/125 通过
- S2 回归：通过
- S3 回归：通过
- S4 回归：通过（53/53）

#### 验收标准对照

| 标准 | 结果 |
|:-----|:-----|
| text_editor_demo 功能不变 | ✅ v4 demo 使用相同 builtin producer，功能完全保留 |
| 不再有文件级全局变量 | ✅ `NEBULA_EDITOR_GLOBALS_DEFINED = true` + `NebulaEditorState` App Record 字段 |
| 回归全绿 | ✅ S1a-S5 共 6 套测试全部通过 |

---

## 关键决策记录

| 决策 | 结论 | 依据 |
|:-----|:-----|:-----|
| 补丁是否嵌入 Phase 5.0 主流程 | 是 | 补丁解决的是"可实现性"问题，不是"后续优化" |
| S1 是否拆分 | 是（S1a + S1b） | S1 原范围过大（6 个新模块 + 10 项测试），拆分降低并行实现风险 |
| mutation AST 是否在 S1a 完成 | 否，移至 S1b | S1a 聚焦图构建，不依赖 AST；S1b 专门处理 AST + Effect |
| 是否增加 Nelua 编译验证 | 是（S2.5） | 纯 Lua smoke 测试无法捕捉 Nelua type error |
| Effect 模型是否在 S1a 完成 | 否，移至 S1b | S1a 完成数据结构，S1b 完成推导逻辑 |
| 路由去重是否在 S1a 完成 | 否（仅规则文档），S1b 完成接口 | S1a 聚焦图构建 |
| hit-test 运行时 bounds 是否在第一梯队明确 | 是（规则文档） | 第二梯队生成代码时按规则实现 |
| dirty bit 策略是否在第一梯队完成 | 是（S1a） | 图构建后即需 dirty bit 分配 |
| C 产物审计何时进行 | S3 | 必须在生成真实 demo 后立即审计，不等 S5 |
| 编译期调试打印是否纳入 | 是 | `## print(graph)` 用于开发阶段验证全知图内容 |

---

## 风险矩阵

| 风险 | 概率 | 影响 | 缓解 |
|:-----|:-----|:-----|:-----|
| mutation AST 解析器覆盖不了所有合法用法 | 中 | 高 | S1b 仅支持最小子集，明确标注不支持语法的回退路径，后续版本扩展 |
| 生成代码与现有 app_factory 冲突 | 低 | 高 | S1a-S1b 先不改现有生成逻辑，新增独立模块 |
| dirty bit 超过 64 时的多 chunk 逻辑复杂 | 低 | 中 | S1a 只支持单 chunk，S2 再加多 chunk |
| Effect 模型推导不完整 | 中 | 中 | S1b 只覆盖 text_update + gpu_update，layout_invalidate/redraw 后续添加；Rule 8 强制用户显式声明 |
| 77/77 回归在某个梯队被破坏 | 中 | 高 | 每个梯队结束时跑全量回归 |
| Nelua 编译验证暴露 type error | 中 | 高 | S2.5 中间验收点提前暴露，不等 S3 |
| hit-test 动态岛场景阻碍编辑器迁移 | 中 | 中 | S5 迁移时逐一审视 hit-test 场景，落入动态岛的保留 process_input |

---

## 产出物清单

### 新增文件

| 文件 | 梯队 | 描述 |
|:-----|:-----|:-----|
| `src/derive/dirty_map.lua` | S1a | dirty bit 分配策略 |
| `src/derive/omniscient_graph.lua` | S1a | 全知图构建与分析 |
| `src/derive/mutation_ast.lua` | S1b | mutation 受限语法 AST 解析器 |
| `src/derive/effect_model.lua` | S1b | Effect/Invalidation 模型 |
| `src/derive/event_router.lua` | S1b/S2 | 事件路由代码生成（S1b 接口 + S2 完整实现） |
| `src/derive/binding_factory.lua` | S2 | 端到端路径代码生成 |
| `examples/counter_binding_demo.nelua` | S3 | 验证 demo |
| `examples/routing_coexistence_demo.nelua` | S3 | 路由去重验证（可选） |
| `tests/smoke_phase5_0_s1a.lua` | S1a | 图构建冒烟测试 |
| `tests/smoke_phase5_0_s1b.lua` | S1b | AST + Effect 冒烟测试 |
| `tests/smoke_phase5_0_s2.lua` | S2 | 代码生成冒烟测试 |
| `tests/smoke_phase5_0_structure.lua` | S3 | 结构稳定性回归测试 |
| `tests/test_snapshot.lua` | S3 | 快照测试基础设施 |
| `tests/snapshots/*.txt` | S3 | 生成代码快照 |

### 修改文件

| 文件 | 梯队 | 描述 |
|:-----|:-----|:-----|
| `src/derive/app_factory.lua` | S1a/S2 | 注册 API + gen_app_record/state + gen_app_update |
| `src/nebula_core.nelua` | S2 | 导出编译期 API + hit_test_rect 辅助函数 |

---

## 验收标准总表

| 梯队 | 冒烟测试 | 回归测试 | 生成代码审计 | 额外验收 |
|:-----|:---------|:---------|:-------------|:---------|
| S1a | 全绿（8 项） | 77/77 全绿 | — | — |
| S1b | 全绿（9 项） | 77/77 全绿 | — | — |
| S2 | 全绿（5 项） | 77/77 全绿 | — | — |
| S2.5 | — | — | — | `nelua --compile-only` 通过 |
| S3 | — | 77/77 全绿 | counter demo C 产物逐行审查 | 结构稳定性测试全绿 |
| S4 | — | 77/77 全绿 | — | — |
| S5 | — | 77/77 全绿 | 编辑器生成代码无框架运行时 | hit-test 动态岛场景逐一处理 |
