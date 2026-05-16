-- =============================================================================
-- smoke_phase5_0_s1a.lua
-- Phase 5.0 S1a: 依赖图构建 + dirty bit 基础 — 冒烟测试
--
-- 验证内容：
--   1. [dirty_map] allocate — 按拓扑序为钻石节点分配 bit index
--   2. [dirty_map] storage_type — 不同 bit 数量对应正确存储类型
--   3. [dirty_map] gen_set/gen_test — 单 chunk 和 multi-chunk
--   4. [dirty_map] gen_clear — 单值清零和数组清零
--   5. [omniscient_graph] 线性链 A→B→C 拓扑序正确，无钻石节点
--   6. [omniscient_graph] 钻石链 A→B,A→C,B→D,C→D，D 标记为钻石
--   7. [omniscient_graph] 无依赖状态
--   8. [omniscient_graph] 循环依赖返回 nil
--   9. [register_api] nebula_state/bind/on 数据正确存入 registry
--  10. [graph_build] nebula_build_omniscient_graph 通过 nebula_app_end 触发
-- =============================================================================

local script_dir = debug.getinfo(1, "S").source:match("^@(.+)/[^/]+$") or "."

-- ---- 加载被测模块 ----
local DirtyMap = dofile(script_dir .. "/../src/derive/dirty_map.lua")
local OmniscientGraph = dofile(script_dir .. "/../src/derive/omniscient_graph.lua")

-- 加载 app_factory（全局注册 API）
-- 需要先 stub nebula_layout_node 等布局函数（app_factory 依赖它们）
nebula_layout_node = nebula_layout_node or function(spec) return spec end
nebula_layout_solve = nebula_layout_solve or function() end
nebula_layout_collect = nebula_layout_collect or function() return {} end
nebula_layout_dump = nebula_layout_dump or function() end
nebula_layout_derive_segments = nebula_layout_derive_segments or function() return { segments = {} } end
nebula_registry = nebula_registry or {}

local factory_version = dofile(script_dir .. "/../src/derive/app_factory.lua")

-- ---- 辅助函数 ----
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

local function assert_true(desc, cond)
  if cond then
    passed = passed + 1
  else
    failed = failed + 1
    print(("[FAIL] %s"):format(desc))
  end
end

local function assert_nil(desc, val)
  if val == nil then
    passed = passed + 1
  else
    failed = failed + 1
    print(("[FAIL] %s — expected nil, got: %s"):format(desc, tostring(val)))
  end
end

local function table_eq(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return a == b end
  if #a ~= #b then return false end
  for i = 1, #a do
    if a[i] ~= b[i] then return false end
  end
  return true
end

-- =============================================================================
-- Test Group 1: DirtyMap
-- =============================================================================

-- 1.1 allocate — 基本分配
do
  local graph = {
    topo_order = {"a", "b", "c", "d"},
    diamond_nodes = { d = true },
  }
  local map, bit_count = DirtyMap.allocate(graph)
  assert_eq("dirty_allocate_count", bit_count, 1)
  assert_eq("dirty_allocate_d_index", map["d"], 0)
  assert_nil("dirty_allocate_a_nil", map["a"])
  assert_nil("dirty_allocate_b_nil", map["b"])
end

-- 1.2 allocate — 多个钻石节点按拓扑序
do
  local graph = {
    topo_order = {"x", "y", "z"},
    diamond_nodes = { x = true, z = true },
  }
  local map, bit_count = DirtyMap.allocate(graph)
  assert_eq("dirty_allocate_multi_count", bit_count, 2)
  assert_eq("dirty_allocate_x_before_z", map["x"] < map["z"], true)
end

-- 1.3 allocate — 无钻石节点
do
  local graph = {
    topo_order = {"a", "b"},
    diamond_nodes = {},
  }
  local map, bit_count = DirtyMap.allocate(graph)
  assert_eq("dirty_allocate_zero", bit_count, 0)
end

-- 1.4 storage_type
do
  assert_eq("storage_0", DirtyMap.storage_type(0), "uint8")
  assert_eq("storage_1", DirtyMap.storage_type(1), "uint8")
  assert_eq("storage_8", DirtyMap.storage_type(8), "uint8")
  assert_eq("storage_9", DirtyMap.storage_type(9), "uint16")
  assert_eq("storage_16", DirtyMap.storage_type(16), "uint16")
  assert_eq("storage_17", DirtyMap.storage_type(17), "uint32")
  assert_eq("storage_32", DirtyMap.storage_type(32), "uint32")
  assert_eq("storage_33", DirtyMap.storage_type(33), "uint64")
  assert_eq("storage_64", DirtyMap.storage_type(64), "uint64")
  assert_eq("storage_65", DirtyMap.storage_type(65), "array(uint64, 2)")
  assert_eq("storage_128", DirtyMap.storage_type(128), "array(uint64, 2)")
  assert_eq("storage_129", DirtyMap.storage_type(129), "array(uint64, 3)")
end

-- 1.5 gen_set — single chunk
do
  local code = DirtyMap.gen_set(0)
  assert_true("gen_set_0_has_shift", code:find("1_u64 << 0") ~= nil)
  assert_true("gen_set_0_has_or", code:find("|") ~= nil)
end

-- 1.6 gen_set — multi chunk
do
  local code = DirtyMap.gen_set(65)
  assert_true("gen_set_65_has_chunk_1", code:find("self._dirty%[1%]") ~= nil)
  assert_true("gen_set_65_has_shift_1", code:find("1_u64 << 1") ~= nil)
end

-- 1.7 gen_test — single chunk
do
  local code = DirtyMap.gen_test(3)
  assert_true("gen_test_3_has_shift", code:find("1_u64 << 3") ~= nil)
  assert_true("gen_test_3_has_neq", code:find("~= 0") ~= nil)
end

-- 1.8 gen_test — multi chunk
do
  local code = DirtyMap.gen_test(127)
  assert_true("gen_test_127_has_chunk_1", code:find("self._dirty%[1%]") ~= nil)
  assert_true("gen_test_127_has_shift_63", code:find("1_u64 << 63") ~= nil)
end

-- 1.9 gen_clear — single
do
  local code = DirtyMap.gen_clear(32)
  assert_eq("gen_clear_32", code, "self._dirty = 0")
end

-- 1.10 gen_clear — multi chunk
do
  local code = DirtyMap.gen_clear(65)
  assert_true("gen_clear_65_chunk0", code:find("self._dirty%[0%] = 0") ~= nil)
  assert_true("gen_clear_65_chunk1", code:find("self._dirty%[1%] = 0") ~= nil)
end

-- =============================================================================
-- Test Group 2: OmniscientGraph
-- =============================================================================

-- 2.1 线性链 A→B→C
do
  local bindings = {
    { target = "b", depends = {"a"} },
    { target = "c", depends = {"b"} },
  }
  local adj = OmniscientGraph.build_dependency_adjacency(bindings)
  assert_true("linear_adj_a_to_b", adj["a"] and adj["a"][1] == "b")
  assert_true("linear_adj_b_to_c", adj["b"] and adj["b"][1] == "c")

  local topo = OmniscientGraph.topological_sort(adj, {"a", "b", "c"})
  assert_true("linear_topo_not_nil", topo ~= nil)
  -- a 必须在 b 之前，b 必须在 c 之前
  if topo then
    local pos = {}
    for i, v in ipairs(topo) do pos[v] = i end
    assert_true("linear_topo_a_before_b", pos["a"] < pos["b"])
    assert_true("linear_topo_b_before_c", pos["b"] < pos["c"])
  end

  local diamonds = OmniscientGraph.detect_diamond_dependencies(adj)
  assert_nil("linear_no_diamond_b", diamonds["b"] and true or nil)
  assert_nil("linear_no_diamond_c", diamonds["c"] and true or nil)
end

-- 2.2 钻石链 A→B, A→C, B→D, C→D
do
  local bindings = {
    { target = "b", depends = {"a"} },
    { target = "c", depends = {"a"} },
    { target = "d", depends = {"b", "c"} },
  }
  local adj = OmniscientGraph.build_dependency_adjacency(bindings)
  local topo = OmniscientGraph.topological_sort(adj, {"a", "b", "c", "d"})
  assert_true("diamond_topo_not_nil", topo ~= nil)
  if topo then
    local pos = {}
    for i, v in ipairs(topo) do pos[v] = i end
    assert_true("diamond_a_before_b", pos["a"] < pos["b"])
    assert_true("diamond_a_before_c", pos["a"] < pos["c"])
    assert_true("diamond_b_before_d", pos["b"] < pos["d"])
    assert_true("diamond_c_before_d", pos["c"] < pos["d"])
  end

  local diamonds = OmniscientGraph.detect_diamond_dependencies(adj)
  assert_true("diamond_d_is_diamond", diamonds["d"] == true)
  assert_nil("diamond_b_not_diamond", diamonds["b"])
  assert_nil("diamond_c_not_diamond", diamonds["c"])
end

-- 2.3 无依赖状态
do
  local topo = OmniscientGraph.topological_sort({}, {"x", "y", "z"})
  assert_true("no_dep_topo_not_nil", topo ~= nil)
  assert_eq("no_dep_topo_len", topo and #topo or 0, 3)
end

-- 2.4 循环依赖
do
  local bindings = {
    { target = "b", depends = {"a"} },
    { target = "a", depends = {"b"} },
  }
  local adj = OmniscientGraph.build_dependency_adjacency(bindings)
  local topo = OmniscientGraph.topological_sort(adj, {"a", "b"})
  assert_nil("circular_topo_nil", topo)
end

-- 2.5 拓扑序稳定性（多次构建结果一致）
do
  local bindings = {
    { target = "b", depends = {"a"} },
    { target = "c", depends = {"a"} },
    { target = "d", depends = {"b", "c"} },
  }
  local adj = OmniscientGraph.build_dependency_adjacency(bindings)
  local topo1 = OmniscientGraph.topological_sort(adj, {"a", "b", "c", "d"})
  for i = 1, 5 do
    local adj2 = OmniscientGraph.build_dependency_adjacency(bindings)
    local topo2 = OmniscientGraph.topological_sort(adj2, {"a", "b", "c", "d"})
    assert_true("topo_stability_iter_" .. i, table_eq(topo1, topo2))
  end
end

-- =============================================================================
-- Test Group 3: Registration API
-- =============================================================================

-- 3.1 nebula_state/bind/on 数据正确存入 registry
do
  -- 清理之前的注册
  nebula_app_registry["TestStateApp"] = nil

  nebula_app_begin("TestStateApp")

  nebula_state("count", { type = "int32", default = 0 })
  nebula_state("label_text", { type = "cstring", default = '"Count: 0"' })

  nebula_bind("label_text", {
    depends = {"count"},
    compute = 'snprintf(self._label_buf, 32, "Count: %d", self.count)',
  })

  nebula_on("button", "click", {
    mutation = 'self.count = self.count + 1',
  })

  nebula_app_end()

  local reg = nebula_app_registry["TestStateApp"]
  assert_true("reg_states_exist", reg._states ~= nil)
  assert_true("reg_state_count", reg._states["count"] ~= nil)
  assert_eq("reg_state_count_type", reg._states["count"].type, "int32")
  assert_eq("reg_state_label_type", reg._states["label_text"].type, "cstring")

  assert_true("reg_bindings_exist", reg._bindings ~= nil)
  assert_eq("reg_bindings_len", #reg._bindings, 1)
  assert_eq("reg_binding_target", reg._bindings[1].target, "label_text")
  assert_true("reg_binding_depends", table_eq(reg._bindings[1].depends, {"count"}))

  assert_true("reg_events_exist", reg._events ~= nil)
  assert_eq("reg_events_len", #reg._events, 1)
  assert_eq("reg_event_target", reg._events[1].target, "button")
  assert_eq("reg_event_type", reg._events[1].event_type, "click")
end

-- =============================================================================
-- Test Group 4: Integrated graph build via nebula_app_end
-- =============================================================================

-- 4.1 nebula_app_end 自动构建全知图
do
  nebula_app_registry["TestGraphApp"] = nil

  nebula_app_begin("TestGraphApp")

  nebula_state("count", { type = "int32", default = 0 })
  nebula_state("label_text", { type = "cstring" })

  nebula_bind("label_text", {
    depends = {"count"},
    compute = 'snprintf(self._label_buf, 32, "Count: %d", self.count)',
  })

  nebula_on("button", "click", {
    mutation = 'self.count = self.count + 1',
  })

  nebula_app_end()

  local reg = nebula_app_registry["TestGraphApp"]
  local graph = reg._omniscient_graph
  assert_true("graph_exists", graph ~= nil)
  assert_true("graph_topo_not_nil", graph.topo_order ~= nil)
  assert_eq("graph_nodes_count", #graph.nodes, 2)  -- count, label_text
  assert_eq("graph_bindings_count", #graph.bindings, 1)
  assert_eq("graph_events_count", #graph.events, 1)
end

-- 4.2 无 states/bindings/events 的 App 不构建全知图
do
  nebula_app_registry["TestPlainApp"] = nil
  nebula_app_begin("TestPlainApp")
  nebula_app_end()
  local reg = nebula_app_registry["TestPlainApp"]
  assert_nil("plain_app_no_graph", reg._omniscient_graph)
end

-- 4.3 app_factory 版本号更新
do
  assert_true("factory_version_5_0",
    factory_version:find("phase5.0") ~= nil)
end

-- =============================================================================
-- Summary
-- =============================================================================

print(("=== Phase 5.0 S1a smoke: %d passed, %d failed ==="):format(passed, failed))
if failed > 0 then os.exit(1) end
