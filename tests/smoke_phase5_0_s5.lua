-- =============================================================================
-- smoke_phase5_0_s5.lua
-- Phase 5.0 S5: 编辑器迁移 — 冒烟测试
--
-- 验证内容：
--   1. [states] nebula_app sugar 的 states spec 正确传递到全知图
--   2. [states] NebulaEditorState 类型在 record 字段中正确生成
--   3. [states] 多状态（编辑器级别数量）图构建稳定
--   4. [codegen] 编辑器状态的 record 字段生成
--   5. [codegen] 编辑器状态的 init 代码生成
--   6. [integration] states + bindings + events 混合声明
--   7. [integration] editor_state 下的 binding 依赖追踪
--   8. [stability] 回归：S1a-S4 基础能力不受影响
--   9. [stability] 大状态集合（>20 个状态）拓扑排序稳定
--  10. [no-globals] 验证 App Record 模式不依赖全局变量
-- =============================================================================

local script_dir = debug.getinfo(1, "S").source:match("^@(.+)/[^/]+$") or "."

-- 加载被测模块
local MutationAST     = dofile(script_dir .. "/../src/derive/mutation_ast.lua")
local EffectModel     = dofile(script_dir .. "/../src/derive/effect_model.lua")
local EventRouter     = dofile(script_dir .. "/../src/derive/event_router.lua")
local OmniscientGraph = dofile(script_dir .. "/../src/derive/omniscient_graph.lua")
local DirtyMap        = dofile(script_dir .. "/../src/derive/dirty_map.lua")
local BindingFactory  = dofile(script_dir .. "/../src/derive/binding_factory.lua")

-- stub layout functions for app_factory
nebula_layout_node = nebula_layout_node or function(spec) return spec end
nebula_layout_solve = nebula_layout_solve or function() end
nebula_layout_collect = nebula_layout_collect or function() return {} end
nebula_layout_dump = nebula_layout_dump or function() end
nebula_layout_derive_segments = nebula_layout_derive_segments or function() return { segments = {} } end
nebula_registry = nebula_registry or {}

local factory_version = dofile(script_dir .. "/../src/derive/app_factory.lua")

-- 辅助函数
local passed = 0
local failed = 0

local function assert_eq(desc, got, expected)
  if got == expected then
    passed = passed + 1
  else
    failed = failed + 1
    print(("[FAIL] %s\n       expected: %s\n       got:      %s"):format(
      desc, tostring(expected), tostring(got)))
  end
end

local function assert_true(desc, val)
  if val then
    passed = passed + 1
  else
    failed = failed + 1
    print(("[FAIL] %s — expected true, got: %s"):format(desc, tostring(val)))
  end
end

local function assert_match(desc, str, pattern)
  if type(str) == "string" and str:find(pattern) then
    passed = passed + 1
  else
    failed = failed + 1
    print(("[FAIL] %s\n       pattern: %s\n       string:  %s"):format(
      desc, pattern, tostring(str):sub(1, 200)))
  end
end

local function assert_not_match(desc, str, pattern)
  if type(str) ~= "string" or not str:find(pattern) then
    passed = passed + 1
  else
    failed = failed + 1
    print(("[FAIL] %s — should NOT match: %s"):format(desc, pattern))
  end
end

local function group(name) print(("\n--- Group: %s ---"):format(name)) end

-- =============================================================================
-- Group 1: NebulaEditorState 类型状态声明
-- =============================================================================
group("1: NebulaEditorState 类型状态声明")

nebula_app_begin("EditorS5App1")
nebula_state("es", { type = "NebulaEditorState" })
nebula_app_end()

local reg1 = nebula_app_registry["EditorS5App1"]
assert_true("1.1 reg has _states", reg1._states ~= nil)
assert_true("1.2 _states has 'es'", reg1._states["es"] ~= nil)
assert_eq("1.3 es type = NebulaEditorState", reg1._states["es"].type, "NebulaEditorState")

-- =============================================================================
-- Group 2: 全知图构建（单状态 NebulaEditorState）
-- =============================================================================
group("2: 全知图构建")

local graph1 = reg1._omniscient_graph
assert_true("2.1 graph exists", graph1 ~= nil)
assert_true("2.2 topo_order exists (no cycle)", graph1.topo_order ~= nil)
assert_true("2.3 nodes contain 'es'", (function()
  for _, n in ipairs(graph1.nodes) do if n == "es" then return true end end
  return false
end)())

-- =============================================================================
-- Group 3: Record 字段代码生成
-- =============================================================================
group("3: Record 字段代码生成")

local result1 = BindingFactory.generate("EditorS5App1", reg1)
assert_match("3.1 record has es field", result1.record_fields, "es: NebulaEditorState")
assert_match("3.2 init code references es", result1.init_code, "self%.es")

-- =============================================================================
-- Group 4: 多状态声明（编辑器级别）
-- =============================================================================
group("4: 多状态声明（编辑器级别）")

nebula_app_begin("EditorS5App2")
-- 模拟编辑器级别的多状态声明
nebula_state("es", { type = "NebulaEditorState" })
nebula_state("cursor_row", { type = "uint32", default = 0 })
nebula_state("cursor_col", { type = "uint32", default = 0 })
nebula_state("scroll_y", { type = "float32", default = "0.0" })
nebula_state("line_count", { type = "uint32", default = 1 })
nebula_state("tab_size", { type = "uint32", default = 4 })
nebula_state("word_wrap", { type = "boolean", default = false })
nebula_state("show_whitespace", { type = "boolean", default = false })
nebula_state("auto_indent", { type = "boolean", default = true })
nebula_state("font_size", { type = "float32", default = "14.0" })
nebula_state("zoom_level", { type = "float32", default = "1.0" })
nebula_state("theme_id", { type = "uint32", default = 0 })
nebula_app_end()

local reg2 = nebula_app_registry["EditorS5App2"]
local graph2 = reg2._omniscient_graph
assert_true("4.1 graph exists", graph2 ~= nil)
assert_true("4.2 topo_order exists (no cycle)", graph2.topo_order ~= nil)
assert_eq("4.3 node count = 12", #graph2.nodes, 12)
assert_eq("4.4 state count", (function()
  local c = 0; for _ in pairs(graph2.states) do c = c + 1 end; return c
end)(), 12)

-- =============================================================================
-- Group 5: states + bindings 混合声明
-- =============================================================================
group("5: states + bindings 混合")

nebula_app_begin("EditorS5App3")
nebula_state("es", { type = "NebulaEditorState" })
nebula_state("cursor_row", { type = "uint32", default = 0 })
nebula_state("cursor_col", { type = "uint32", default = 0 })
nebula_bind("cursor_display", {
  depends = { "cursor_row", "cursor_col" },
  compute = "self.cursor_display = self.cursor_row * 1000 + self.cursor_col",
  type    = "int32",
})
nebula_app_end()

local reg3 = nebula_app_registry["EditorS5App3"]
local graph3 = reg3._omniscient_graph
assert_true("5.1 graph exists", graph3 ~= nil)
assert_true("5.2 topo_order exists", graph3.topo_order ~= nil)

-- cursor_display 应该在 cursor_row 和 cursor_col 之后
local function topo_index(topo, name)
  for i, n in ipairs(topo) do if n == name then return i end end
  return nil
end
assert_true("5.3 cursor_row before cursor_display",
  topo_index(graph3.topo_order, "cursor_row") < topo_index(graph3.topo_order, "cursor_display"))
assert_true("5.4 cursor_col before cursor_display",
  topo_index(graph3.topo_order, "cursor_col") < topo_index(graph3.topo_order, "cursor_display"))

-- cursor_display 是钻石节点（入度 = 2）
assert_true("5.5 cursor_display is diamond node", graph3.diamond_nodes["cursor_display"] == true)

-- =============================================================================
-- Group 6: states + bindings + events 全链路
-- =============================================================================
group("6: states + bindings + events 全链路")

nebula_app_begin("EditorS5App4")
nebula_app_register_component("btn", "CounterButtonVisual")
nebula_state("es", { type = "NebulaEditorState" })
nebula_state("count", { type = "int32", default = 0 })
nebula_bind("doubled", {
  depends = { "count" },
  compute = "self.doubled = self.count * 2",
})
nebula_on("btn", "click", { mutation = "self.count = self.count + 1" })
nebula_app_end()

local reg4 = nebula_app_registry["EditorS5App4"]
local result4 = BindingFactory.generate("EditorS5App4", reg4)
assert_match("6.1 handler generated", result4.handlers_code, "_on_btn_click")
assert_match("6.2 mutation in handler", result4.handlers_code, "self%.count = self%.count %+ 1")
assert_match("6.3 recompute doubled", result4.handlers_code, "self%.doubled = self%.count %* 2")
assert_match("6.4 route_input generated", result4.handlers_code, "_route_input")
assert_match("6.5 es field in record", result4.record_fields, "es: NebulaEditorState")
assert_match("6.6 count field in record", result4.record_fields, "count: int32")

-- =============================================================================
-- Group 7: 大状态集合拓扑排序稳定性
-- =============================================================================
group("7: 大状态集合拓扑排序稳定性")

nebula_app_begin("EditorS5App5")
-- 声明 25 个独立状态
for i = 1, 25 do
  nebula_state("state_" .. string.format("%02d", i), { type = "int32", default = i })
end
nebula_app_end()

local reg5 = nebula_app_registry["EditorS5App5"]
local graph5 = reg5._omniscient_graph
assert_true("7.1 graph exists", graph5 ~= nil)
assert_eq("7.2 25 nodes", #graph5.nodes, 25)
assert_true("7.3 topo_order exists", graph5.topo_order ~= nil)
assert_eq("7.4 topo_order has 25 entries", #graph5.topo_order, 25)

-- 验证稳定性：连续构建两次，结果相同
local graph5b = OmniscientGraph.build(reg5)
assert_true("7.5 stable: same topo_order", (function()
  for i, n in ipairs(graph5.topo_order) do
    if graph5b.topo_order[i] ~= n then return false end
  end
  return true
end)())

-- =============================================================================
-- Group 8: Record/Init 代码内容检查
-- =============================================================================
group("8: Record/Init 代码内容检查")

local result5 = BindingFactory.generate("EditorS5App5", reg5)

-- 所有 25 个 state 都应在 record 中
for i = 1, 25 do
  local sname = "state_" .. string.format("%02d", i)
  assert_match("8." .. i .. " record has " .. sname, result5.record_fields, sname .. ": int32")
end

-- =============================================================================
-- Group 9: init 代码默认值
-- =============================================================================
group("9: init 代码默认值")

nebula_app_begin("EditorS5App6")
nebula_state("flag_a", { type = "boolean", default = true })
nebula_state("flag_b", { type = "boolean", default = false })
nebula_state("counter", { type = "int32", default = 42 })
nebula_state("ratio", { type = "float32", default = "3.14" })
nebula_app_end()

local reg6 = nebula_app_registry["EditorS5App6"]
local result6 = BindingFactory.generate("EditorS5App6", reg6)
assert_match("9.1 flag_a init true", result6.init_code, "self%.flag_a = true")
assert_match("9.2 flag_b init false", result6.init_code, "self%.flag_b = false")
assert_match("9.3 counter init 42", result6.init_code, "self%.counter = 42")
assert_match("9.4 ratio init 3.14", result6.init_code, "self%.ratio = 3.14")

-- =============================================================================
-- Group 10: 回归 — S1a/S1b/S2 基础能力
-- =============================================================================
group("10: 回归 — 基础能力不退化")

-- S1a: 拓扑排序
local adj = OmniscientGraph.build_dependency_adjacency({
  { target = "b", depends = { "a" } },
  { target = "c", depends = { "a", "b" } },
})
local topo = OmniscientGraph.topological_sort(adj, { "a", "b", "c" })
assert_eq("10.1 topo[1] = a", topo[1], "a")
assert_eq("10.2 topo[2] = b", topo[2], "b")
assert_eq("10.3 topo[3] = c", topo[3], "c")

-- S1a: 钻石检测
local diamonds = OmniscientGraph.detect_diamond_dependencies(adj)
assert_true("10.4 c is diamond", diamonds["c"] == true)
assert_true("10.5 a is not diamond", diamonds["a"] == nil)

-- S1b: MutationAST
local stmts, err = MutationAST.parse("self.x = self.x + 1")
assert_true("10.6 MutationAST parse ok", stmts ~= nil)
local ws = MutationAST.write_set(stmts)
assert_true("10.7 write_set has x", ws["x"] == true)

-- S2: 事件路由
local declared = EventRouter.build_declared_event_set({
  _events = { { target = "btn", event_type = "click", mutation = "self.x = 1" } }
})
assert_true("10.8 EventRouter declared btn.click", declared["btn"] and declared["btn"]["click"])

-- =============================================================================
-- Group 11: 回归 — S4 repeater/conditional 基础
-- =============================================================================
group("11: 回归 — S4 不退化")

nebula_app_begin("EditorS5App7")
nebula_state("n", { type = "int32", default = 3 })
nebula_state("es", { type = "NebulaEditorState" })
nebula_repeater("items", "ItemVisual", {
  max = 10, count_var = "n",
  bind = {
    { field = "label", source = "self.n + _i", type = "int32" },
  },
})
nebula_when("word_wrap_enabled", {
  on_true  = { { action = "show", target = "wrap_indicator" } },
})
nebula_app_end()

local reg7 = nebula_app_registry["EditorS5App7"]
local graph7 = reg7._omniscient_graph
assert_true("11.1 graph has repeaters", #graph7.repeaters > 0)
assert_true("11.2 graph has conditionals", #graph7.conditionals > 0)

local result7 = BindingFactory.generate("EditorS5App7", reg7)
assert_match("11.3 repeater dirty field", result7.record_fields, "_items_dirty: boolean")
assert_match("11.4 conditional field", result7.record_fields, "_when_word_wrap_enabled_active: boolean")
assert_match("11.5 es field coexists", result7.record_fields, "es: NebulaEditorState")

-- =============================================================================
-- Group 12: 无运行时事件系统验证
-- =============================================================================
group("12: 无运行时事件系统")

local result4_handlers = result4.handlers_code
assert_not_match("12.1 no addEventListener", result4_handlers, "addEventListener")
assert_not_match("12.2 no EventEmitter", result4_handlers, "EventEmitter")
assert_not_match("12.3 no subscribe", result4_handlers, "subscribe")
assert_not_match("12.4 no dispatch", result4_handlers, "dispatch%(")
assert_not_match("12.5 no on%(", result4_handlers, "[^_]on%(")

-- =============================================================================
-- 结果汇总
-- =============================================================================
print(("\n=== Phase 5.0 S5 Smoke Tests: %d passed, %d failed ==="):format(passed, failed))
if failed > 0 then
  os.exit(1)
end
