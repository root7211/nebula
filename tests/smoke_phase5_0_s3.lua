-- =============================================================================
-- smoke_phase5_0_s3.lua
-- Phase 5.0 S3: 验证 Demo + 结构稳定性 — 冒烟测试
--
-- 验证内容：
--   1. [stability] 拓扑序稳定性 — 相同输入多次构建结果一致
--   2. [stability] dirty bit 分配稳定性
--   3. [stability] handler 名称格式稳定
--   4. [stability] Effect 推导稳定性
--   5. [stability] 生成代码快照比对
--   6. [audit] 生成代码中无运行时事件系统
--   7. [audit] binding target 字段出现在 record 中
--   8. [audit] 钻石节点使用 dirty bit 延迟
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

local function assert_true(desc, cond)
  if cond then
    passed = passed + 1
  else
    failed = failed + 1
    print(("[FAIL] %s"):format(desc))
  end
end

local function assert_match(desc, str, pattern)
  if str and str:find(pattern) then
    passed = passed + 1
  else
    failed = failed + 1
    print(("[FAIL] %s\n       pattern: %s\n       in: %s"):format(
      desc, pattern, tostring(str):sub(1, 200)))
  end
end

local function assert_no_match(desc, str, pattern)
  if str and not str:find(pattern) then
    passed = passed + 1
  else
    failed = failed + 1
    print(("[FAIL] %s\n       should NOT contain: %s"):format(desc, pattern))
  end
end

-- =============================================================================
-- 辅助：构建标准 counter app 图
-- =============================================================================
local function build_counter_graph()
  local reg = {
    name = "StabilityApp",
    _states = {
      count = { name = "count", type = "int32", default = 0 },
    },
    _bindings = {
      { target = "label_text", depends = {"count"}, compute = "self.label_text = self.count" },
    },
    _events = {
      { target = "button", event_type = "click", mutation = "self.count = self.count + 1" },
    },
  }
  local graph = OmniscientGraph.build(reg, {
    MutationAST = MutationAST,
    EffectModel = EffectModel,
  })
  reg._omniscient_graph = graph
  return reg, graph
end

-- =============================================================================
-- 辅助：构建钻石 app 图
-- =============================================================================
local function build_diamond_graph()
  local reg = {
    name = "DiamondStabilityApp",
    _states = {
      a = { name = "a", type = "int32", default = 0 },
    },
    _bindings = {
      { target = "b", depends = {"a"}, compute = "self.b = self.a + 1" },
      { target = "c", depends = {"a"}, compute = "self.c = self.a * 2" },
      { target = "d", depends = {"b", "c"}, compute = "self.d = self.b + self.c" },
    },
    _events = {
      { target = "trigger", event_type = "click", mutation = "self.a = self.a + 1" },
    },
  }
  local graph = OmniscientGraph.build(reg, {
    MutationAST = MutationAST,
    EffectModel = EffectModel,
  })
  reg._omniscient_graph = graph
  return reg, graph
end

-- =============================================================================
-- Test Group 1: 拓扑序稳定性
-- =============================================================================
print("--- Test Group 1: Topological order stability ---")

do
  local _, graph1 = build_counter_graph()
  local _, graph2 = build_counter_graph()
  local _, graph3 = build_counter_graph()

  local topo1 = table.concat(graph1.topo_order, ",")
  local topo2 = table.concat(graph2.topo_order, ",")
  local topo3 = table.concat(graph3.topo_order, ",")

  assert_eq("topo_order run1 == run2", topo1, topo2)
  assert_eq("topo_order run2 == run3", topo2, topo3)
end

do
  local _, graph1 = build_diamond_graph()
  local _, graph2 = build_diamond_graph()

  local topo1 = table.concat(graph1.topo_order, ",")
  local topo2 = table.concat(graph2.topo_order, ",")

  assert_eq("diamond topo_order stable", topo1, topo2)
end

-- =============================================================================
-- Test Group 2: Dirty bit 分配稳定性
-- =============================================================================
print("--- Test Group 2: Dirty bit allocation stability ---")

do
  local _, graph1 = build_diamond_graph()
  local _, graph2 = build_diamond_graph()

  local alloc1, count1 = DirtyMap.allocate(graph1)
  local alloc2, count2 = DirtyMap.allocate(graph2)

  assert_eq("dirty bit_count stable", count1, count2)
  assert_eq("dirty bit_count = 1 (node d)", count1, 1)
  assert_eq("dirty d bit_index stable", alloc1["d"], alloc2["d"])
end

-- =============================================================================
-- Test Group 3: Handler 名称格式稳定
-- =============================================================================
print("--- Test Group 3: Handler name stability ---")

do
  local reg1, _ = build_counter_graph()
  local reg2, _ = build_counter_graph()

  local result1 = BindingFactory.generate("StabilityApp", reg1)
  local result2 = BindingFactory.generate("StabilityApp", reg2)

  -- handler 名称应为 _on_<target>_<event_type>
  assert_match("handler name format",
    result1.handlers_code, "_on_button_click")
  assert_eq("handler code stable",
    result1.handlers_code, result2.handlers_code)
end

-- =============================================================================
-- Test Group 4: Effect 推导稳定性
-- =============================================================================
print("--- Test Group 4: Effect derivation stability ---")

do
  local _, graph1 = build_counter_graph()
  local _, graph2 = build_counter_graph()

  -- event_chains 数量应一致
  assert_eq("event_chains count stable",
    #(graph1.event_chains or {}), #(graph2.event_chains or {}))

  -- 每个 chain 的 write_set 应一致
  if graph1.event_chains and graph2.event_chains then
    for i, chain1 in ipairs(graph1.event_chains) do
      local chain2 = graph2.event_chains[i]
      -- 比较 write_set keys
      local ws1_keys = {}
      for k, _ in pairs(chain1.write_set) do ws1_keys[#ws1_keys+1] = k end
      table.sort(ws1_keys)
      local ws2_keys = {}
      for k, _ in pairs(chain2.write_set) do ws2_keys[#ws2_keys+1] = k end
      table.sort(ws2_keys)
      assert_eq("write_set keys stable [" .. i .. "]",
        table.concat(ws1_keys, ","), table.concat(ws2_keys, ","))
    end
  end
end

-- =============================================================================
-- Test Group 5: 生成代码快照比对
-- =============================================================================
print("--- Test Group 5: Generated code snapshot ---")

do
  local reg1, _ = build_counter_graph()
  local reg2, _ = build_counter_graph()

  local result1 = BindingFactory.generate("StabilityApp", reg1)
  local result2 = BindingFactory.generate("StabilityApp", reg2)

  assert_eq("record_fields snapshot stable",
    result1.record_fields, result2.record_fields)
  assert_eq("init_code snapshot stable",
    result1.init_code, result2.init_code)
  assert_eq("handlers_code snapshot stable",
    result1.handlers_code, result2.handlers_code)
  assert_eq("update_code snapshot stable",
    result1.update_code, result2.update_code)
end

do
  local reg1, _ = build_diamond_graph()
  local reg2, _ = build_diamond_graph()

  local result1 = BindingFactory.generate("DiamondStabilityApp", reg1)
  local result2 = BindingFactory.generate("DiamondStabilityApp", reg2)

  assert_eq("diamond record stable",
    result1.record_fields, result2.record_fields)
  assert_eq("diamond handlers stable",
    result1.handlers_code, result2.handlers_code)
end

-- =============================================================================
-- Test Group 6: 生成代码无运行时事件系统
-- =============================================================================
print("--- Test Group 6: No runtime event system ---")

do
  local reg, _ = build_counter_graph()
  local result = BindingFactory.generate("StabilityApp", reg)
  local all = result.record_fields .. result.init_code ..
              result.handlers_code .. result.update_code

  assert_no_match("no EventBus", all, "EventBus")
  assert_no_match("no subscribe", all, "subscribe")
  assert_no_match("no dispatch", all, "dispatch")
  assert_no_match("no observer", all, "observer")
  assert_no_match("no listener", all, "listener")
  assert_no_match("no signal_emit", all, "signal_emit")
  assert_no_match("no dependency_tracker", all, "dependency_tracker")
  assert_no_match("no event_queue", all, "event_queue")
end

-- =============================================================================
-- Test Group 7: Binding target 字段存在于 record
-- =============================================================================
print("--- Test Group 7: Binding target in record ---")

do
  local reg, _ = build_counter_graph()
  local result = BindingFactory.generate("StabilityApp", reg)

  -- count 是 state → 应出现在 record
  assert_match("state 'count' in record",
    result.record_fields, "count: int32")
  -- label_text 是 binding target → 也应出现在 record
  assert_match("binding target 'label_text' in record",
    result.record_fields, "label_text: int32")
end

do
  local reg, _ = build_diamond_graph()
  local result = BindingFactory.generate("DiamondStabilityApp", reg)

  assert_match("state 'a' in record", result.record_fields, "a: int32")
  assert_match("binding target 'b' in record", result.record_fields, "b: int32")
  assert_match("binding target 'c' in record", result.record_fields, "c: int32")
  assert_match("binding target 'd' in record", result.record_fields, "d: int32")
  assert_match("_dirty in record", result.record_fields, "_dirty")
end

-- =============================================================================
-- Test Group 8: 钻石节点使用 dirty bit 延迟
-- =============================================================================
print("--- Test Group 8: Diamond dirty bit deferral ---")

do
  local reg, _ = build_diamond_graph()
  local result = BindingFactory.generate("DiamondStabilityApp", reg)

  -- handler 中 d 应延迟
  assert_match("diamond defer comment in handler",
    result.handlers_code, "diamond node 'd'")

  -- _commit 中应 recompute d
  assert_match("_commit recomputes d",
    result.handlers_code, "recompute 'd'")

  -- _commit 中应清零 dirty
  assert_match("_commit clears dirty",
    result.handlers_code, "_dirty = 0")

  -- b 和 c 应内联（非钻石）
  assert_match("b is inlined",
    result.handlers_code, "recompute 'b' %(inline%)")
  assert_match("c is inlined",
    result.handlers_code, "recompute 'c' %(inline%)")
end

-- =============================================================================
-- Test Group 9: 全链路集成 — app_begin → generate 快照
-- =============================================================================
print("--- Test Group 9: Full pipeline snapshot ---")

do
  nebula_app_begin("SnapshotApp1", { arena_size = 1024 })
  nebula_state("hp", { type = "int32", default = 100 })
  nebula_state("mp", { type = "int32", default = 50 })
  nebula_bind("total_power", {
    depends = { "hp", "mp" },
    compute = "self.total_power = self.hp + self.mp",
  })
  nebula_on("heal_btn", "click", {
    mutation = "self.hp = self.hp + 10",
  })
  nebula_app_end()

  local source1 = nebula_app_generate("SnapshotApp1")

  -- 重新构建同样的 app
  nebula_app_begin("SnapshotApp2", { arena_size = 1024 })
  nebula_state("hp", { type = "int32", default = 100 })
  nebula_state("mp", { type = "int32", default = 50 })
  nebula_bind("total_power", {
    depends = { "hp", "mp" },
    compute = "self.total_power = self.hp + self.mp",
  })
  nebula_on("heal_btn", "click", {
    mutation = "self.hp = self.hp + 10",
  })
  nebula_app_end()

  local source2 = nebula_app_generate("SnapshotApp2")

  -- 名称不同但结构应一致（替换 app 名后比较）
  local norm1 = source1:gsub("SnapshotApp1", "APPNAME")
  local norm2 = source2:gsub("SnapshotApp2", "APPNAME")

  assert_eq("full pipeline snapshot stable", norm1, norm2)

  -- 内容审计
  assert_match("source has hp field", source1, "hp: int32")
  assert_match("source has mp field", source1, "mp: int32")
  assert_match("source has total_power field", source1, "total_power: int32")
  assert_match("source has _dirty field", source1, "_dirty")
  assert_match("source has _on_heal_btn_click", source1, "_on_heal_btn_click")
  assert_match("source has _commit", source1, "_commit")
  assert_match("source has _route_input", source1, "_route_input")
  assert_match("source has hp default init", source1, "self%.hp = 100")
  assert_match("source has mp default init", source1, "self%.mp = 50")
end

-- =============================================================================
-- 汇总
-- =============================================================================
print(("\n=== Phase 5.0 S3 Smoke Tests: %d passed, %d failed ==="):format(passed, failed))
if failed > 0 then
  os.exit(1)
else
  print("ALL TESTS PASSED")
end
