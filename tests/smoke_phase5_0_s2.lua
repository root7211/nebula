-- =============================================================================
-- smoke_phase5_0_s2.lua
-- Phase 5.0 S2: 代码生成 — 冒烟测试
--
-- 验证内容：
--   1. [binding_factory] counter demo 生成的代码结构正确
--   2. [binding_factory] 线性链内联到 handler 中
--   3. [binding_factory] 钻石节点延迟到 _commit
--   4. [binding_factory] 生成代码中无事件系统/依赖追踪代码
--   5. [binding_factory] 超过 64 个钻石节点时生成数组访问
--   6. [app_factory] state 字段注入到 record
--   7. [app_factory] state 默认值注入到 init
--   8. [app_factory] _route_input / _commit 注入到 update
--   9. [app_factory] handler 代码追加到生成源码
--  10. [integration] 全链路 app_begin → state/bind/on → app_end → generate
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

local function assert_nil(desc, val)
  if val == nil then
    passed = passed + 1
  else
    failed = failed + 1
    print(("[FAIL] %s — expected nil, got: %s"):format(desc, tostring(val)))
  end
end

local function assert_match(desc, str, pattern)
  if str and str:find(pattern) then
    passed = passed + 1
  else
    failed = failed + 1
    print(("[FAIL] %s\n       pattern: %s\n       string:  %s"):format(
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
-- Test Group 1: BindingFactory.emit_effect_call
-- =============================================================================
print("--- Test Group 1: emit_effect_call ---")

do
  local line = BindingFactory.emit_effect_call(
    { kind = "gpu_update", target = "button", field = "color" },
    "TestApp", "    ")
  assert_match("effect_call gpu_update contains target",
    line, "gpu_update")
  assert_match("effect_call gpu_update contains field",
    line, "button%.color")
end

do
  local line = BindingFactory.emit_effect_call(
    { kind = "text_update", target = "label" },
    "TestApp", "    ")
  assert_match("effect_call text_update contains target",
    line, "text_update")
end

do
  local line = BindingFactory.emit_effect_call(
    { kind = "redraw", target = "panel" },
    "TestApp", "    ")
  assert_match("effect_call redraw contains target",
    line, "redraw")
end

-- =============================================================================
-- Test Group 2: Counter demo — 基础代码生成
-- =============================================================================
print("--- Test Group 2: Counter demo code generation ---")

do
  -- 构建一个简单的 counter app
  local reg = {
    name = "CounterApp",
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

  -- 构建全知图（带 AST + Effect）
  local graph = OmniscientGraph.build(reg, {
    MutationAST = MutationAST,
    EffectModel = EffectModel,
  })

  reg._omniscient_graph = graph
  local result = BindingFactory.generate("CounterApp", reg)

  -- 2.1: record 字段应包含 count: int32
  assert_match("counter record has count field",
    result.record_fields, "count: int32")

  -- 2.2: init 应包含默认值
  assert_match("counter init has default value",
    result.init_code, "self%.count = 0")

  -- 2.3: handler 代码应包含 _on_button_click
  assert_match("counter handler has _on_button_click",
    result.handlers_code, "_on_button_click")

  -- 2.4: handler 应包含 mutation 代码
  assert_match("counter handler has mutation code",
    result.handlers_code, "self%.count = self%.count %+ 1")

  -- 2.5: handler 应包含 recompute（线性链内联）
  assert_match("counter handler has inline recompute",
    result.handlers_code, "recompute")

  -- 2.6: 应有 _route_input
  assert_match("counter has _route_input",
    result.handlers_code, "_route_input")

  -- 2.7: _route_input 应有 click hit-test
  assert_match("counter route_input has click hit-test",
    result.handlers_code, "mouse_left_pressed")

  -- 2.8: update 应包含路由调用
  assert_match("counter update has _route_input call",
    result.update_code, "_route_input")

  -- 2.9: 无钻石节点 → 不应有 _commit
  assert_no_match("counter no _commit (no diamond)",
    result.update_code, "_commit")

  -- 2.10: 不应有 _dirty 字段（无钻石节点）
  assert_no_match("counter no _dirty field",
    result.record_fields, "_dirty")
end

-- =============================================================================
-- Test Group 3: 线性链内联
-- =============================================================================
print("--- Test Group 3: Linear chain inline ---")

do
  -- A→B→C 线性链，应全部内联
  local reg = {
    name = "LinearApp",
    _states = {
      a = { name = "a", type = "int32", default = 0 },
    },
    _bindings = {
      { target = "b", depends = {"a"}, compute = "self.b = self.a * 2" },
      { target = "c", depends = {"b"}, compute = "self.c = self.b + 10" },
    },
    _events = {
      { target = "input", event_type = "click", mutation = "self.a = self.a + 1" },
    },
  }

  local graph = OmniscientGraph.build(reg, {
    MutationAST = MutationAST,
    EffectModel = EffectModel,
  })
  reg._omniscient_graph = graph

  local result = BindingFactory.generate("LinearApp", reg)

  -- 线性链中应包含内联 recompute
  assert_match("linear chain has recompute b inline",
    result.handlers_code, "recompute 'b'")
  assert_match("linear chain has recompute c inline",
    result.handlers_code, "recompute 'c'")
  assert_match("linear chain b compute code",
    result.handlers_code, "self%.b = self%.a %* 2")
  assert_match("linear chain c compute code",
    result.handlers_code, "self%.c = self%.b %+ 10")

  -- 无钻石 → 不应有 _commit
  assert_no_match("linear no _commit",
    result.handlers_code, "_commit")
end

-- =============================================================================
-- Test Group 4: 钻石节点延迟到 _commit
-- =============================================================================
print("--- Test Group 4: Diamond node deferred to _commit ---")

do
  -- A→B, A→C, B→D, C→D — D 是钻石节点
  local reg = {
    name = "DiamondApp",
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

  local result = BindingFactory.generate("DiamondApp", reg)

  -- 4.1: 应有 _dirty 字段
  assert_match("diamond has _dirty field",
    result.record_fields, "_dirty")

  -- 4.2: handler 中 D 应标记为 defer to _commit
  assert_match("diamond handler defers D to _commit",
    result.handlers_code, "diamond node 'd'")

  -- 4.3: handler 中 B 和 C 应内联（非钻石）
  assert_match("diamond handler inlines B",
    result.handlers_code, "recompute 'b' %(inline%)")
  assert_match("diamond handler inlines C",
    result.handlers_code, "recompute 'c' %(inline%)")

  -- 4.4: 应有 _commit 函数
  assert_match("diamond has _commit function",
    result.handlers_code, "_commit")

  -- 4.5: _commit 中应有 D 的 recompute
  assert_match("diamond _commit recomputes D",
    result.handlers_code, "recompute 'd'")

  -- 4.6: _commit 中应有 dirty bit 清零
  assert_match("diamond _commit clears dirty",
    result.handlers_code, "_dirty = 0")

  -- 4.7: update 应有 _commit 调用
  assert_match("diamond update has _commit call",
    result.update_code, "_commit")
end

-- =============================================================================
-- Test Group 5: 生成代码中无运行时事件系统
-- =============================================================================
print("--- Test Group 5: No framework runtime in generated code ---")

do
  local reg = {
    name = "PureApp",
    _states = {
      x = { name = "x", type = "float32", default = 0.0 },
    },
    _bindings = {},
    _events = {
      { target = "slider", event_type = "click", mutation = "self.x = self.x + 0.1" },
    },
  }

  local graph = OmniscientGraph.build(reg, {
    MutationAST = MutationAST,
    EffectModel = EffectModel,
  })
  reg._omniscient_graph = graph

  local result = BindingFactory.generate("PureApp", reg)
  local all_code = result.record_fields .. result.init_code .. result.handlers_code .. result.update_code

  -- 不应包含运行时事件系统关键字
  assert_no_match("no 'EventBus' in code", all_code, "EventBus")
  assert_no_match("no 'subscribe' in code", all_code, "subscribe")
  assert_no_match("no 'dispatch' in code", all_code, "dispatch")
  assert_no_match("no 'observer' in code", all_code, "observer")
  assert_no_match("no 'dependency_tracker' in code", all_code, "dependency_tracker")
end

-- =============================================================================
-- Test Group 6: Dirty bit multi-chunk（超过 64 个钻石节点）
-- =============================================================================
print("--- Test Group 6: Dirty bit multi-chunk ---")

do
  -- 构建 70 个钻石节点
  local states = { root = { name = "root", type = "int32", default = 0 } }
  local bindings = {}

  -- 创建 70 个钻石节点：每个依赖 root + 前一个节点
  for i = 1, 70 do
    local name = ("d%03d"):format(i)
    states[name] = { name = name, type = "int32" }
    local prev = i > 1 and ("d%03d"):format(i - 1) or "root"
    table.insert(bindings, {
      target  = name,
      depends = { "root", prev },
      compute = ("self.%s = self.root + %d"):format(name, i),
    })
  end

  local reg = {
    name = "MultiChunkApp",
    _states = states,
    _bindings = bindings,
    _events = {
      { target = "btn", event_type = "click", mutation = "self.root = self.root + 1" },
    },
  }

  local graph = OmniscientGraph.build(reg, {
    MutationAST = MutationAST,
    EffectModel = EffectModel,
  })
  reg._omniscient_graph = graph

  local result = BindingFactory.generate("MultiChunkApp", reg)

  -- 6.1: 应有 array 类型的 dirty 字段
  assert_match("multi-chunk dirty type is array",
    result.record_fields, "array")

  -- 6.2: handler 中应有 array 访问形式的 gen_set
  assert_match("multi-chunk handler has array set",
    result.handlers_code, "self%._dirty%[")

  -- 6.3: _commit 中应有 array 清零
  assert_match("multi-chunk commit has array clear",
    result.handlers_code, "self%._dirty%[0%] = 0")
end

-- =============================================================================
-- Test Group 7: 多状态类型
-- =============================================================================
print("--- Test Group 7: Multiple state types ---")

do
  local reg = {
    name = "TypesApp",
    _states = {
      count   = { name = "count",   type = "int32",   default = 0 },
      ratio   = { name = "ratio",   type = "float32", default = 1.0 },
      enabled = { name = "enabled", type = "boolean", default = true },
    },
    _bindings = {},
    _events = {},
  }

  local graph = OmniscientGraph.build(reg, {
    MutationAST = MutationAST,
    EffectModel = EffectModel,
  })
  reg._omniscient_graph = graph

  local result = BindingFactory.generate("TypesApp", reg)

  assert_match("types record has int32 field",
    result.record_fields, "count: int32")
  assert_match("types record has float32 field",
    result.record_fields, "ratio: float32")
  assert_match("types record has boolean field",
    result.record_fields, "enabled: boolean")

  assert_match("types init has int default",
    result.init_code, "self%.count = 0")
  assert_match("types init has float default",
    result.init_code, "self%.ratio = 1%.0")
  assert_match("types init has boolean default",
    result.init_code, "self%.enabled = true")
end

-- =============================================================================
-- Test Group 8: 无状态/事件 App 不应崩溃
-- =============================================================================
print("--- Test Group 8: Stateless app ---")

do
  local reg = {
    name = "StatelessApp",
    -- no _states, _bindings, _events
  }

  local result = BindingFactory.generate("StatelessApp", reg)
  assert_eq("stateless record_fields empty", result.record_fields, "")
  assert_eq("stateless init_code empty", result.init_code, "")
  assert_eq("stateless handlers_code empty", result.handlers_code, "")
  assert_eq("stateless update_code empty", result.update_code, "")
end

-- =============================================================================
-- Test Group 9: 全链路集成（app_begin → generate）
-- =============================================================================
print("--- Test Group 9: Full integration ---")

do
  -- 使用 app_factory 的注册 API 走完整链路
  nebula_app_begin("IntegrationTestApp", { arena_size = 1024 })

  nebula_state("score", { type = "int32", default = 0 })
  nebula_state("lives", { type = "int32", default = 3 })

  nebula_bind("total", {
    depends = { "score", "lives" },
    compute = "self.total = self.score * self.lives",
  })

  nebula_on("play_btn", "click", {
    mutation = "self.score = self.score + 10",
  })

  nebula_app_end()

  -- 验证注册表中有全知图
  local reg = nebula_app_registry["IntegrationTestApp"]
  assert_true("integration: omniscient_graph exists",
    reg._omniscient_graph ~= nil)
  assert_true("integration: event_chains exists",
    reg._omniscient_graph.event_chains ~= nil)

  -- 生成代码
  local source = nebula_app_generate("IntegrationTestApp")

  -- 9.1: source 应包含 state 字段
  assert_match("integration source has score field",
    source, "score: int32")
  assert_match("integration source has lives field",
    source, "lives: int32")

  -- 9.2: source 应包含 handler
  assert_match("integration source has handler",
    source, "_on_play_btn_click")

  -- 9.3: source 应包含 mutation 代码
  assert_match("integration source has mutation",
    source, "self%.score = self%.score %+ 10")

  -- 9.4: source 应包含 _route_input
  assert_match("integration source has _route_input",
    source, "_route_input")

  -- 9.5: source 应包含默认值初始化
  assert_match("integration source has score default",
    source, "self%.score = 0")
  assert_match("integration source has lives default",
    source, "self%.lives = 3")
end

-- =============================================================================
-- Test Group 10: 多事件路由
-- =============================================================================
print("--- Test Group 10: Multiple event routing ---")

do
  local reg = {
    name = "MultiEventApp",
    _states = {
      x = { name = "x", type = "int32", default = 0 },
      y = { name = "y", type = "int32", default = 0 },
    },
    _bindings = {},
    _events = {
      { target = "btn_a", event_type = "click", mutation = "self.x = self.x + 1" },
      { target = "btn_b", event_type = "click", mutation = "self.y = self.y + 1" },
    },
  }

  local graph = OmniscientGraph.build(reg, {
    MutationAST = MutationAST,
    EffectModel = EffectModel,
  })
  reg._omniscient_graph = graph

  local result = BindingFactory.generate("MultiEventApp", reg)

  -- 应有两个独立的 handler
  assert_match("multi-event has btn_a handler",
    result.handlers_code, "_on_btn_a_click")
  assert_match("multi-event has btn_b handler",
    result.handlers_code, "_on_btn_b_click")

  -- _route_input 应有两个 hit-test
  assert_match("multi-event route has btn_a hit-test",
    result.handlers_code, "self%.btn_a%.visual%.pos%.x")
  assert_match("multi-event route has btn_b hit-test",
    result.handlers_code, "self%.btn_b%.visual%.pos%.x")
end

-- =============================================================================
-- 汇总
-- =============================================================================
print(("\n=== Phase 5.0 S2 Smoke Tests: %d passed, %d failed ==="):format(passed, failed))
if failed > 0 then
  os.exit(1)
else
  print("ALL TESTS PASSED")
end
