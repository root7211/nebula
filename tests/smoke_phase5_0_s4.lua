-- =============================================================================
-- smoke_phase5_0_s4.lua
-- Phase 5.0 S4: 动态内容扩展 — 冒烟测试
--
-- 验证内容：
--   1. [repeater] nebula_repeater 注册 API
--   2. [repeater] repeater 绑定展开到全知图
--   3. [repeater] repeater dirty 标记生成
--   4. [repeater] repeater 更新函数生成
--   5. [repeater] repeater + event handler 联动
--   6. [conditional] nebula_when 注册 API
--   7. [conditional] conditional record 字段生成
--   8. [conditional] conditional 同步代码生成
--   9. [conditional] conditional + event handler 联动
--  10. [stability] repeater + conditional dirty bit 分配稳定
--  11. [integration] repeater + conditional + binding 全链路
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
-- Test Group 1: nebula_repeater 注册 API
-- =============================================================================
print("--- Test Group 1: nebula_repeater registration ---")

do
  nebula_app_begin("RepeaterTestApp1", { arena_size = 1024 })
  nebula_state("item_count", { type = "uint32", default = 0 })
  nebula_repeater("items", "ItemVisual", {
    max       = 256,
    count_var = "item_count",
    bind      = {
      { field = "color", source = "self.base_color", depends = {"base_color"} },
    },
  })
  nebula_app_end()

  local reg = nebula_app_registry["RepeaterTestApp1"]
  assert_true("repeater registered", reg._repeaters ~= nil)
  assert_eq("repeater count", #reg._repeaters, 1)
  assert_eq("repeater name", reg._repeaters[1].name, "items")
  assert_eq("repeater visual_type", reg._repeaters[1].visual_type, "ItemVisual")
  assert_eq("repeater max", reg._repeaters[1].max, 256)
  assert_eq("repeater count_var", reg._repeaters[1].count_var, "item_count")
  assert_eq("repeater bind count", #reg._repeaters[1].bind, 1)
end

-- =============================================================================
-- Test Group 2: repeater 绑定展开到全知图
-- =============================================================================
print("--- Test Group 2: repeater binding expansion ---")

do
  nebula_app_begin("RepeaterGraphApp", { arena_size = 1024 })
  nebula_state("item_count", { type = "uint32", default = 0 })
  nebula_state("base_color", { type = "uint32", default = 0 })
  nebula_repeater("items", "ItemVisual", {
    max       = 64,
    count_var = "item_count",
    bind      = {
      { field = "color", source = "self.base_color", depends = {"base_color"} },
    },
  })
  nebula_app_end()

  local reg = nebula_app_registry["RepeaterGraphApp"]
  local graph = reg._omniscient_graph
  assert_true("graph built", graph ~= nil)
  assert_true("graph has repeaters", graph.repeaters ~= nil)
  assert_eq("graph repeater count", #graph.repeaters, 1)

  -- 检查 repeater 绑定是否展开到 bindings 中
  local found_repeater_binding = false
  for _, b in ipairs(graph.bindings) do
    if b.target == "_repeater_items_color" then
      found_repeater_binding = true
      assert_eq("repeater binding depends", b.depends[1], "base_color")
    end
  end
  assert_true("repeater binding expanded to graph", found_repeater_binding)

  -- 检查 _repeater_bindings
  assert_true("_repeater_bindings exists", graph._repeater_bindings ~= nil)
  assert_eq("_repeater_bindings count", #graph._repeater_bindings, 1)
end

-- =============================================================================
-- Test Group 3: repeater 代码生成 — record + init
-- =============================================================================
print("--- Test Group 3: repeater code generation ---")

do
  nebula_app_begin("RepeaterCodeApp", { arena_size = 1024 })
  nebula_state("item_count", { type = "uint32", default = 5 })
  nebula_state("base_color", { type = "uint32", default = 0 })
  nebula_repeater("items", "ItemVisual", {
    max       = 64,
    count_var = "item_count",
    bind      = {
      { field = "color", source = "self.base_color", depends = {"base_color"} },
    },
  })
  nebula_on("btn", "click", {
    mutation = "self.base_color = self.base_color + 1",
  })
  nebula_app_end()

  local reg = nebula_app_registry["RepeaterCodeApp"]
  local result = BindingFactory.generate("RepeaterCodeApp", reg)

  -- record 字段中应包含 _items_dirty
  assert_match("record has repeater dirty field",
    result.record_fields, "_items_dirty")

  -- init 中应包含 repeater 初始化
  assert_match("init has repeater dirty init",
    result.init_code, "_items_dirty = true")

  -- handler 代码中应包含 _update_repeater_items
  assert_match("handler has repeater update function",
    result.handlers_code, "_update_repeater_items")

  -- handler 代码中应包含 repeater dirty mark（因为 base_color 变化影响 repeater）
  assert_match("handler marks repeater dirty",
    result.handlers_code, "_items_dirty = true")

  -- update 代码中应包含 repeater 更新调用
  assert_match("update calls repeater update",
    result.update_code, "_update_repeater_items")
end

-- =============================================================================
-- Test Group 4: repeater 更新函数结构
-- =============================================================================
print("--- Test Group 4: repeater update function structure ---")

do
  nebula_app_begin("RepeaterUpdateApp", { arena_size = 1024 })
  nebula_state("item_count", { type = "uint32", default = 10 })
  nebula_state("theme", { type = "uint32", default = 0 })
  nebula_repeater("cards", "CardVisual", {
    max       = 128,
    count_var = "item_count",
    bind      = {
      { field = "bg", source = "self.theme", depends = {"theme"} },
      { field = "fg", source = "self.theme + 1", depends = {"theme"} },
    },
  })
  nebula_app_end()

  local reg = nebula_app_registry["RepeaterUpdateApp"]
  local result = BindingFactory.generate("RepeaterUpdateApp", reg)

  -- 更新函数应包含 count 检查
  assert_match("repeater update checks dirty",
    result.handlers_code, "_cards_dirty")
  -- 应包含 count_var 读取
  assert_match("repeater reads count_var",
    result.handlers_code, "self%.item_count")
  -- 应包含 max 上限
  assert_match("repeater clamps to max",
    result.handlers_code, "128")
  -- 应包含循环
  assert_match("repeater has loop",
    result.handlers_code, "while _i < _count")
end

-- =============================================================================
-- Test Group 5: nebula_when 注册 API
-- =============================================================================
print("--- Test Group 5: nebula_when registration ---")

do
  nebula_app_begin("WhenTestApp1", { arena_size = 1024 })
  nebula_state("is_logged_in", { type = "boolean", default = false })
  nebula_when("is_logged_in", {
    on_true  = {"dashboard"},
    on_false = {"login_form"},
  })
  nebula_app_end()

  local reg = nebula_app_registry["WhenTestApp1"]
  assert_true("conditional registered", reg._conditionals ~= nil)
  assert_eq("conditional count", #reg._conditionals, 1)
  assert_eq("conditional condition", reg._conditionals[1].condition, "is_logged_in")
  assert_eq("conditional on_true count", #reg._conditionals[1].on_true, 1)
  assert_eq("conditional on_true[1]", reg._conditionals[1].on_true[1], "dashboard")
  assert_eq("conditional on_false[1]", reg._conditionals[1].on_false[1], "login_form")
end

-- =============================================================================
-- Test Group 6: conditional 代码生成 — record + init
-- =============================================================================
print("--- Test Group 6: conditional code generation ---")

do
  nebula_app_begin("WhenCodeApp", { arena_size = 1024 })
  nebula_state("is_dark", { type = "boolean", default = true })
  nebula_when("is_dark", {
    on_true  = {"dark_panel"},
    on_false = {"light_panel"},
  })
  nebula_on("toggle_btn", "click", {
    mutation = "self.is_dark = not self.is_dark",
  })
  nebula_app_end()

  local reg = nebula_app_registry["WhenCodeApp"]
  local result = BindingFactory.generate("WhenCodeApp", reg)

  -- record 中应有 _when_is_dark_active
  assert_match("record has conditional visibility field",
    result.record_fields, "_when_is_dark_active")

  -- init 中应初始化为 true（因为 default = true）
  assert_match("init sets conditional active to true",
    result.init_code, "_when_is_dark_active = true")

  -- handler 中应有 _sync_conditionals 函数
  assert_match("handler has sync conditionals function",
    result.handlers_code, "_sync_conditionals")

  -- handler 中应在 click handler 注入 conditional 同步
  assert_match("click handler syncs conditional",
    result.handlers_code, "_when_is_dark_active = self%.is_dark")
end

-- =============================================================================
-- Test Group 7: conditional 默认值 false
-- =============================================================================
print("--- Test Group 7: conditional default false ---")

do
  nebula_app_begin("WhenFalseApp", { arena_size = 1024 })
  nebula_state("show_menu", { type = "boolean", default = false })
  nebula_when("show_menu", {
    on_true  = {"menu"},
    on_false = {},
  })
  nebula_app_end()

  local reg = nebula_app_registry["WhenFalseApp"]
  local result = BindingFactory.generate("WhenFalseApp", reg)

  assert_match("init sets conditional to false",
    result.init_code, "_when_show_menu_active = false")
end

-- =============================================================================
-- Test Group 8: stability — 多次构建结果一致
-- =============================================================================
print("--- Test Group 8: stability ---")

do
  local function build_complex_app(name)
    nebula_app_begin(name, { arena_size = 1024 })
    nebula_state("count", { type = "int32", default = 0 })
    nebula_state("visible", { type = "boolean", default = true })
    nebula_state("list_len", { type = "uint32", default = 5 })
    nebula_repeater("items", "ItemVisual", {
      max       = 100,
      count_var = "list_len",
      bind      = {
        { field = "idx", source = "self.count + _i", depends = {"count"} },
      },
    })
    nebula_when("visible", {
      on_true  = {"main_panel"},
      on_false = {},
    })
    nebula_on("btn", "click", {
      mutation = "self.count = self.count + 1",
    })
    nebula_app_end()
    return nebula_app_registry[name]
  end

  local reg1 = build_complex_app("StabilityS4App1")
  local reg2 = build_complex_app("StabilityS4App2")

  local result1 = BindingFactory.generate("StabilityS4App1", reg1)
  local result2 = BindingFactory.generate("StabilityS4App2", reg2)

  -- 名称替换后比较
  local norm1 = result1.record_fields:gsub("StabilityS4App1", "APP")
  local norm2 = result2.record_fields:gsub("StabilityS4App2", "APP")
  assert_eq("record fields stable", norm1, norm2)

  norm1 = result1.init_code:gsub("StabilityS4App1", "APP")
  norm2 = result2.init_code:gsub("StabilityS4App2", "APP")
  assert_eq("init code stable", norm1, norm2)

  norm1 = result1.handlers_code:gsub("StabilityS4App1", "APP")
  norm2 = result2.handlers_code:gsub("StabilityS4App2", "APP")
  assert_eq("handlers code stable", norm1, norm2)

  norm1 = result1.update_code:gsub("StabilityS4App1", "APP")
  norm2 = result2.update_code:gsub("StabilityS4App2", "APP")
  assert_eq("update code stable", norm1, norm2)
end

-- =============================================================================
-- Test Group 9: graph 中 repeater 绑定不影响原始 dirty bit 分配
-- =============================================================================
print("--- Test Group 9: dirty bit isolation ---")

do
  nebula_app_begin("DirtyIsolationApp", { arena_size = 1024 })
  nebula_state("a", { type = "int32", default = 0 })
  nebula_state("item_count", { type = "uint32", default = 0 })
  nebula_bind("b", { depends = {"a"}, compute = "self.b = self.a + 1" })
  nebula_bind("c", { depends = {"a"}, compute = "self.c = self.a * 2" })
  nebula_bind("d", { depends = {"b", "c"}, compute = "self.d = self.b + self.c" })
  nebula_repeater("list", "ListVisual", {
    max       = 50,
    count_var = "item_count",
    bind      = {
      { field = "val", source = "self.a", depends = {"a"} },
    },
  })
  nebula_app_end()

  local reg = nebula_app_registry["DirtyIsolationApp"]
  local graph = reg._omniscient_graph

  -- 钻石节点仍应只有 d
  assert_true("d is diamond", graph.diamond_nodes["d"] == true)
  -- repeater 的 _repeater_list_val 不应是钻石（只有一个依赖）
  assert_true("repeater binding not diamond",
    not graph.diamond_nodes["_repeater_list_val"])

  local alloc, count = DirtyMap.allocate(graph)
  assert_eq("dirty bit count still 1 (only d)", count, 1)
end

-- =============================================================================
-- Test Group 10: repeater + conditional 共存
-- =============================================================================
print("--- Test Group 10: repeater + conditional coexistence ---")

do
  nebula_app_begin("CoexistApp", { arena_size = 1024 })
  nebula_state("count", { type = "uint32", default = 10 })
  nebula_state("active", { type = "boolean", default = true })
  nebula_repeater("items", "ItemVisual", {
    max       = 100,
    count_var = "count",
    bind      = {},
  })
  nebula_when("active", {
    on_true  = {"panel"},
    on_false = {},
  })
  nebula_on("toggle", "click", {
    mutation = "self.active = not self.active",
  })
  nebula_app_end()

  local reg = nebula_app_registry["CoexistApp"]
  local result = BindingFactory.generate("CoexistApp", reg)

  -- 两者都应存在
  assert_match("record has repeater dirty", result.record_fields, "_items_dirty")
  assert_match("record has conditional active", result.record_fields, "_when_active_active")
  assert_match("init has repeater dirty init", result.init_code, "_items_dirty = true")
  assert_match("init has conditional init", result.init_code, "_when_active_active = true")
end

-- =============================================================================
-- Test Group 11: repeater source 自动推导依赖
-- =============================================================================
print("--- Test Group 11: repeater auto-derive depends ---")

do
  nebula_app_begin("AutoDepsApp", { arena_size = 1024 })
  nebula_state("n", { type = "uint32", default = 0 })
  nebula_state("color_base", { type = "uint32", default = 0 })
  nebula_repeater("items", "ItemVisual", {
    max       = 10,
    count_var = "n",
    bind      = {
      -- depends 为空，应从 source 自动推导
      { field = "fg", source = "self.color_base + 1" },
    },
  })
  nebula_on("btn", "click", {
    mutation = "self.color_base = self.color_base + 1",
  })
  nebula_app_end()

  local reg = nebula_app_registry["AutoDepsApp"]
  local graph = reg._omniscient_graph

  -- 检查自动推导的依赖
  local found = false
  for _, b in ipairs(graph._repeater_bindings or {}) do
    if b._repeater_field == "fg" then
      found = true
      -- depends 应包含 color_base
      local has_dep = false
      for _, d in ipairs(b.depends) do
        if d == "color_base" then has_dep = true end
      end
      assert_true("auto-derived depends includes color_base", has_dep)
    end
  end
  assert_true("found fg repeater binding", found)

  -- 代码生成应在 click handler 中标记 items dirty
  local result = BindingFactory.generate("AutoDepsApp", reg)
  assert_match("click handler marks items dirty",
    result.handlers_code, "_items_dirty = true")
end

-- =============================================================================
-- Test Group 12: 无运行时事件系统（S4 扩展后仍不应有）
-- =============================================================================
print("--- Test Group 12: no runtime event system ---")

do
  nebula_app_begin("NoRuntimeApp", { arena_size = 1024 })
  nebula_state("n", { type = "uint32", default = 0 })
  nebula_state("show", { type = "boolean", default = true })
  nebula_repeater("items", "ItemVisual", {
    max = 10, count_var = "n",
    bind = { { field = "x", source = "self.n" } },
  })
  nebula_when("show", { on_true = {"a"}, on_false = {"b"} })
  nebula_on("btn", "click", { mutation = "self.n = self.n + 1" })
  nebula_app_end()

  local reg = nebula_app_registry["NoRuntimeApp"]
  local result = BindingFactory.generate("NoRuntimeApp", reg)
  local all = result.record_fields .. result.init_code ..
              result.handlers_code .. result.update_code

  assert_no_match("no EventBus", all, "EventBus")
  assert_no_match("no subscribe", all, "subscribe")
  assert_no_match("no dispatch", all, "dispatch")
  assert_no_match("no observer", all, "observer")
  assert_no_match("no signal_emit", all, "signal_emit")
end

-- =============================================================================
-- 汇总
-- =============================================================================
print(("\n=== Phase 5.0 S4 Smoke Tests: %d passed, %d failed ==="):format(passed, failed))
if failed > 0 then
  os.exit(1)
else
  print("ALL TESTS PASSED")
end
