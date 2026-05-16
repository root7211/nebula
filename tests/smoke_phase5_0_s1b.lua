-- =============================================================================
-- smoke_phase5_0_s1b.lua
-- Phase 5.0 S1b: AST 分析 + Effect 模型 + 路由接口 — 冒烟测试
--
-- 验证内容：
--   1. [mutation_ast] tokenizer 基础
--   2. [mutation_ast] parse + read_set + write_set
--   3. [mutation_ast] emit 代码生成
--   4. [mutation_ast] 语法错误定位
--   5. [mutation_ast] 白名单函数校验
--   6. [mutation_ast] 复合表达式（if/比较/逻辑）
--   7. [effect_model] derive_effects 自动推导
--   8. [effect_model] build_effects_index 反向索引
--   9. [event_router] build_declared_event_set
--  10. [event_router] is_event_declared + detect_conflicts
--  11. [omniscient_graph] trace_propagation
--  12. [omniscient_graph] event_chains via build()
-- =============================================================================

local script_dir = debug.getinfo(1, "S").source:match("^@(.+)/[^/]+$") or "."

-- 加载被测模块
local MutationAST    = dofile(script_dir .. "/../src/derive/mutation_ast.lua")
local EffectModel    = dofile(script_dir .. "/../src/derive/effect_model.lua")
local EventRouter    = dofile(script_dir .. "/../src/derive/event_router.lua")
local OmniscientGraph = dofile(script_dir .. "/../src/derive/omniscient_graph.lua")

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

local function set_has(set, key)
  return set[key] == true
end

local function set_size(set)
  local n = 0
  for _ in pairs(set) do n = n + 1 end
  return n
end

-- =============================================================================
-- Test Group 1: MutationAST — Tokenizer
-- =============================================================================
do
  local tokens, err = MutationAST.tokenize("self.count = self.count + 1")
  assert_true("tokenize_basic_ok", tokens ~= nil and err == nil)
  -- SELF DOT IDENT EQ SELF DOT IDENT OP NUMBER EOF
  assert_eq("tokenize_basic_count", #tokens, 10)
  assert_eq("tokenize_tok1_self", tokens[1].type, MutationAST.TOKEN.SELF)
  assert_eq("tokenize_tok3_ident", tokens[3].value, "count")
  assert_eq("tokenize_tok4_eq", tokens[4].type, MutationAST.TOKEN.EQ)
  assert_eq("tokenize_tok8_plus", tokens[8].value, "+")
  assert_eq("tokenize_tok9_num", tokens[9].value, "1")
end

-- tokenizer: string literal
do
  local tokens, err = MutationAST.tokenize('self.x = "hello"')
  assert_true("tokenize_string_ok", tokens ~= nil and err == nil)
  assert_eq("tokenize_string_val", tokens[5].type, MutationAST.TOKEN.STRING)
end

-- tokenizer: comparison operators
do
  local tokens, err = MutationAST.tokenize("self.a == self.b")
  assert_true("tokenize_eqeq_ok", tokens ~= nil)
  -- find EQEQ token
  local found = false
  for _, t in ipairs(tokens) do
    if t.type == MutationAST.TOKEN.EQEQ then found = true end
  end
  assert_true("tokenize_eqeq_found", found)
end

-- tokenizer: forbidden keyword
do
  local tokens, err = MutationAST.tokenize("for i = 1, 10 do end")
  assert_nil("tokenize_forbidden_for", tokens)
  assert_true("tokenize_forbidden_msg", err and err.message:find("for") ~= nil)
end

-- =============================================================================
-- Test Group 2: MutationAST — Parse + read_set + write_set
-- =============================================================================

-- simple assignment
do
  local stmts, err = MutationAST.parse("self.count = self.count + 1")
  assert_true("parse_simple_ok", stmts ~= nil and err == nil)
  assert_eq("parse_simple_len", #stmts, 1)
  assert_eq("parse_simple_tag", stmts[1].tag, "Assign")
  assert_eq("parse_simple_target", stmts[1].target, "count")

  local rs = MutationAST.read_set(stmts)
  assert_true("read_set_has_count", set_has(rs, "count"))
  assert_eq("read_set_size", set_size(rs), 1)

  local ws = MutationAST.write_set(stmts)
  assert_true("write_set_has_count", set_has(ws, "count"))
  assert_eq("write_set_size", set_size(ws), 1)
end

-- multiple assignments
do
  local stmts, err = MutationAST.parse("self.x = self.a + self.b\nself.y = self.c * 2")
  assert_true("parse_multi_ok", stmts ~= nil and err == nil)
  assert_eq("parse_multi_len", #stmts, 2)

  local rs = MutationAST.read_set(stmts)
  assert_true("read_set_multi_a", set_has(rs, "a"))
  assert_true("read_set_multi_b", set_has(rs, "b"))
  assert_true("read_set_multi_c", set_has(rs, "c"))
  assert_eq("read_set_multi_size", set_size(rs), 3)

  local ws = MutationAST.write_set(stmts)
  assert_true("write_set_multi_x", set_has(ws, "x"))
  assert_true("write_set_multi_y", set_has(ws, "y"))
  assert_eq("write_set_multi_size", set_size(ws), 2)
end

-- boolean + logical operators
do
  local stmts, err = MutationAST.parse("self.visible = self.active and not self.hidden")
  assert_true("parse_logic_ok", stmts ~= nil)
  local rs = MutationAST.read_set(stmts)
  assert_true("read_set_logic_active", set_has(rs, "active"))
  assert_true("read_set_logic_hidden", set_has(rs, "hidden"))
end

-- comparison
do
  local stmts, err = MutationAST.parse("self.big = self.count > 10")
  assert_true("parse_cmp_ok", stmts ~= nil)
  assert_eq("parse_cmp_tag", stmts[1].value.tag, "BinOp")
  assert_eq("parse_cmp_op", stmts[1].value.op, ">")
end

-- if expression
do
  local stmts, err = MutationAST.parse('self.status = if self.count > 0 then true else false')
  assert_true("parse_if_ok", stmts ~= nil)
  assert_eq("parse_if_value_tag", stmts[1].value.tag, "IfExpr")
  local rs = MutationAST.read_set(stmts)
  assert_true("read_set_if_count", set_has(rs, "count"))
end

-- whitelist function call
do
  local stmts, err = MutationAST.parse("snprintf(self.buf, 32, self.count)")
  assert_true("parse_call_ok", stmts ~= nil)
  assert_eq("parse_call_tag", stmts[1].tag, "Call")
  assert_eq("parse_call_fn", stmts[1].fn, "snprintf")
  local rs = MutationAST.read_set(stmts)
  assert_true("read_set_call_buf", set_has(rs, "buf"))
  assert_true("read_set_call_count", set_has(rs, "count"))
end

-- math.floor
do
  local stmts, err = MutationAST.parse("self.x = math.floor(self.y)")
  assert_true("parse_math_floor_ok", stmts ~= nil)
  assert_eq("parse_math_floor_fn", stmts[1].value.fn, "math.floor")
end

-- =============================================================================
-- Test Group 3: MutationAST — emit
-- =============================================================================
do
  local stmts, _ = MutationAST.parse("self.count = self.count + 1")
  local code = MutationAST.emit(stmts)
  assert_true("emit_basic_has_self", code:find("self%.count = self%.count %+ 1") ~= nil)
end

do
  local stmts, _ = MutationAST.parse("self.x = self.a + self.b\nself.y = self.c * 2")
  local code = MutationAST.emit(stmts, 1)
  assert_true("emit_indent", code:find("  self.x") ~= nil)
  assert_true("emit_multiline", code:find("\n") ~= nil)
end

do
  local stmts, _ = MutationAST.parse("self.v = not self.v")
  local code = MutationAST.emit(stmts)
  assert_true("emit_not", code:find("not self.v") ~= nil)
end

-- =============================================================================
-- Test Group 4: MutationAST — Syntax errors
-- =============================================================================
do
  local stmts, err = MutationAST.parse("self.x = ")
  assert_nil("parse_err_incomplete", stmts)
  assert_true("parse_err_has_msg", err and err.message ~= nil)
  assert_true("parse_err_has_line", err and err.line ~= nil)
  assert_true("parse_err_has_col", err and err.col ~= nil)
end

do
  local stmts, err = MutationAST.parse("for i = 1, 10 do end")
  assert_nil("parse_err_forbidden", stmts)
  assert_true("parse_err_forbidden_msg", err and err.message:find("for") ~= nil)
end

-- =============================================================================
-- Test Group 5: MutationAST — Whitelist validation
-- =============================================================================
do
  local stmts, err = MutationAST.parse("table.insert(self.data, 1)")
  assert_nil("whitelist_reject", stmts)
  assert_true("whitelist_reject_msg", err and err.message:find("table.insert") ~= nil)
  assert_true("whitelist_reject_msg2", err and err.message:find("whitelist") ~= nil)
end

do
  local stmts, err = MutationAST.parse("self.x = math.max(self.a, self.b)")
  assert_true("whitelist_accept_math_max", stmts ~= nil)
end

do
  local stmts, err = MutationAST.parse("self.x = math.min(self.a, 0)")
  assert_true("whitelist_accept_math_min", stmts ~= nil)
end

-- =============================================================================
-- Test Group 6: MutationAST — complex expressions
-- =============================================================================

-- nested arithmetic
do
  local stmts, err = MutationAST.parse("self.z = (self.a + self.b) * self.c")
  assert_true("parse_paren_ok", stmts ~= nil)
  local rs = MutationAST.read_set(stmts)
  assert_eq("read_set_paren_size", set_size(rs), 3)
end

-- semicolon separator
do
  local stmts, err = MutationAST.parse("self.x = 1; self.y = 2")
  assert_true("parse_semi_ok", stmts ~= nil)
  assert_eq("parse_semi_len", #stmts, 2)
end

-- boolean literal
do
  local stmts, err = MutationAST.parse("self.active = true")
  assert_true("parse_bool_ok", stmts ~= nil)
  assert_eq("parse_bool_val", stmts[1].value.value, true)
end

-- or expression
do
  local stmts, err = MutationAST.parse("self.x = self.a or self.b")
  assert_true("parse_or_ok", stmts ~= nil)
  assert_eq("parse_or_op", stmts[1].value.op, "or")
end

-- ~= operator
do
  local stmts, err = MutationAST.parse("self.x = self.a ~= self.b")
  assert_true("parse_neq_ok", stmts ~= nil)
  assert_eq("parse_neq_op", stmts[1].value.op, "~=")
end

-- =============================================================================
-- Test Group 7: EffectModel — derive_effects
-- =============================================================================

-- rule 4: default redraw when no text/visual binding matches
do
  local graph = {
    bindings = {
      { target = "label_text", depends = {"count"}, compute = "..." },
    },
    states = { count = { type = "int32" }, label_text = { type = "cstring" } },
  }
  local effects = EffectModel.derive_effects(graph)
  assert_eq("effect_default_len", #effects, 1)
  assert_eq("effect_default_kind", effects[1].kind, "redraw")
  assert_eq("effect_default_depends_on", effects[1].depends_on, "label_text")
end

-- rule 1: explicit affects
do
  local graph = {
    bindings = {
      {
        target = "label_text",
        depends = {"count"},
        affects = {
          { target = "label", field = "text", invalidation = "text_update" },
        },
      },
    },
    states = {},
  }
  local effects = EffectModel.derive_effects(graph)
  assert_eq("effect_explicit_len", #effects, 1)
  assert_eq("effect_explicit_kind", effects[1].kind, "text_update")
  assert_eq("effect_explicit_target", effects[1].target, "label")
  assert_eq("effect_explicit_field", effects[1].field, "text")
end

-- rule 2: text component bound_state
do
  local graph = {
    bindings = {
      { target = "label_text", depends = {"count"} },
    },
    states = {},
    texts = {
      { name = "label", bound_to = "label_text" },
    },
  }
  local effects = EffectModel.derive_effects(graph)
  -- should have text_update effect
  local found_text_update = false
  for _, e in ipairs(effects) do
    if e.kind == "text_update" and e.target == "label" then
      found_text_update = true
    end
  end
  assert_true("effect_text_bound", found_text_update)
end

-- rule 3: visual binding
do
  local graph = {
    bindings = {
      { target = "color_val", depends = {"slider"} },
    },
    states = {},
    visual_bindings = {
      { state = "color_val", component = "box", field = "color", update_method = "update_color" },
    },
  }
  local effects = EffectModel.derive_effects(graph)
  local found_gpu = false
  for _, e in ipairs(effects) do
    if e.kind == "gpu_update" and e.target == "box" then
      found_gpu = true
    end
  end
  assert_true("effect_visual_binding", found_gpu)
end

-- =============================================================================
-- Test Group 8: EffectModel — build_effects_index
-- =============================================================================
do
  local effects = {
    { kind = "redraw", target = "label_text", depends_on = "label_text" },
  }
  local dep_adj = { count = { "label_text" } }
  local index = EffectModel.build_effects_index(effects, dep_adj)

  -- count → label_text (via dep_adj) → redraw effect
  assert_true("effects_index_count", index["count"] ~= nil)
  assert_eq("effects_index_count_len", index["count"] and #index["count"] or 0, 1)
  assert_eq("effects_index_count_kind", index["count"] and index["count"][1].kind, "redraw")

  -- label_text → direct effect
  assert_true("effects_index_label", index["label_text"] ~= nil)
end

-- multi-hop propagation
do
  local effects = {
    { kind = "text_update", target = "label", depends_on = "display" },
  }
  local dep_adj = {
    count = { "label_text" },
    label_text = { "display" },
  }
  local index = EffectModel.build_effects_index(effects, dep_adj)
  -- count → label_text → display → text_update effect
  assert_true("effects_index_multi_hop", index["count"] ~= nil)
  assert_eq("effects_index_multi_hop_kind", index["count"] and index["count"][1].kind, "text_update")
end

-- =============================================================================
-- Test Group 9: EventRouter — build_declared_event_set
-- =============================================================================
do
  local reg = {
    _events = {
      { target = "button", event_type = "click", mutation = "..." },
      { target = "button", event_type = "hover", mutation = "..." },
      { target = "slider", event_type = "drag", mutation = "..." },
    },
  }
  local declared = EventRouter.build_declared_event_set(reg)
  assert_true("event_set_button_click", declared["button"] and declared["button"]["click"] == true)
  assert_true("event_set_button_hover", declared["button"] and declared["button"]["hover"] == true)
  assert_true("event_set_slider_drag", declared["slider"] and declared["slider"]["drag"] == true)
  assert_nil("event_set_slider_click", declared["slider"] and declared["slider"]["click"])
end

-- empty events
do
  local declared = EventRouter.build_declared_event_set({ _events = {} })
  local count = 0
  for _ in pairs(declared) do count = count + 1 end
  assert_eq("event_set_empty", count, 0)
end

-- =============================================================================
-- Test Group 10: EventRouter — is_event_declared + detect_conflicts
-- =============================================================================
do
  local declared = {
    button = { click = true },
    slider = { drag = true },
  }
  assert_true("is_declared_yes", EventRouter.is_event_declared(declared, "button", "click"))
  assert_true("is_declared_no", not EventRouter.is_event_declared(declared, "button", "hover"))
  assert_true("is_declared_no2", not EventRouter.is_event_declared(declared, "unknown", "click"))
end

do
  local declared = { button = { click = true } }
  local legacy = {
    { target = "button", event_type = "click" },
    { target = "button", event_type = "hover" },
  }
  local conflicts = EventRouter.detect_conflicts(declared, legacy)
  assert_eq("conflict_count", #conflicts, 1)
  assert_eq("conflict_target", conflicts[1].target, "button")
  assert_eq("conflict_type", conflicts[1].event_type, "click")
  assert_true("conflict_warning", conflicts[1].warning:find("nebula_on") ~= nil)
end

-- summarize
do
  local declared = {
    button = { click = true, hover = true },
    slider = { drag = true },
  }
  local summary = EventRouter.summarize(declared)
  assert_eq("summarize_len", #summary, 2)
  assert_eq("summarize_first", summary[1].target, "button")
  assert_eq("summarize_first_events_len", #summary[1].events, 2)
  assert_eq("summarize_second", summary[2].target, "slider")
end

-- =============================================================================
-- Test Group 11: OmniscientGraph — trace_propagation
-- =============================================================================
do
  local graph = {
    dep_adj = {
      count = { "label_text" },
    },
    bindings = {
      { target = "label_text", depends = {"count"}, compute = "..." },
    },
    effects_for_state = {
      label_text = {
        { kind = "redraw", target = "label_text", depends_on = "label_text" },
      },
    },
  }
  local ws = { count = true }
  local chain = OmniscientGraph.trace_propagation(ws, graph)

  -- should have recompute for label_text and effect for label_text
  local has_recompute = false
  local has_effect = false
  for _, step in ipairs(chain) do
    if step.type == "recompute" and step.target == "label_text" then has_recompute = true end
    if step.type == "effect" then has_effect = true end
  end
  assert_true("trace_has_recompute", has_recompute)
  assert_true("trace_has_effect", has_effect)
  assert_true("trace_chain_nonempty", #chain >= 2)
end

-- trace with no downstream
do
  local graph = {
    dep_adj = {},
    bindings = {},
    effects_for_state = {},
  }
  local chain = OmniscientGraph.trace_propagation({ isolated = true }, graph)
  assert_eq("trace_isolated", #chain, 0)
end

-- diamond trace
do
  local graph = {
    dep_adj = {
      a = { "b", "c" },
      b = { "d" },
      c = { "d" },
    },
    bindings = {
      { target = "b", depends = {"a"}, compute = "b_compute" },
      { target = "c", depends = {"a"}, compute = "c_compute" },
      { target = "d", depends = {"b", "c"}, compute = "d_compute" },
    },
    effects_for_state = {},
  }
  local chain = OmniscientGraph.trace_propagation({ a = true }, graph)
  -- should have recompute for b, c, d
  local targets = {}
  for _, step in ipairs(chain) do
    if step.type == "recompute" then targets[step.target] = true end
  end
  assert_true("trace_diamond_b", targets["b"] == true)
  assert_true("trace_diamond_c", targets["c"] == true)
  assert_true("trace_diamond_d", targets["d"] == true)
end

-- =============================================================================
-- Test Group 12: OmniscientGraph — event_chains via build()
-- =============================================================================
do
  nebula_app_registry["TestChainApp"] = nil

  nebula_app_begin("TestChainApp")

  nebula_state("count", { type = "int32", default = 0 })
  nebula_state("label_text", { type = "cstring" })

  nebula_bind("label_text", {
    depends = {"count"},
    compute = 'snprintf(self.buf, 32, self.count)',
  })

  nebula_on("button", "click", {
    mutation = 'self.count = self.count + 1',
  })

  nebula_app_end()

  -- rebuild with MutationAST + EffectModel
  local reg = nebula_app_registry["TestChainApp"]
  local graph = OmniscientGraph.build(reg, {
    MutationAST = MutationAST,
    EffectModel = EffectModel,
  })

  assert_true("chain_graph_exists", graph ~= nil)
  assert_true("chain_event_chains", graph.event_chains ~= nil)
  assert_eq("chain_event_chains_len", #graph.event_chains, 1)

  local ec = graph.event_chains[1]
  assert_nil("chain_no_parse_error", ec.parse_error)
  assert_true("chain_write_set_count", ec.write_set["count"] == true)
  assert_true("chain_chain_nonempty", #ec.chain >= 1)

  -- the chain should include recompute of label_text
  local found_recompute = false
  for _, step in ipairs(ec.chain) do
    if step.type == "recompute" and step.target == "label_text" then
      found_recompute = true
    end
  end
  assert_true("chain_recompute_label", found_recompute)
end

-- build with parse error in mutation
do
  nebula_app_registry["TestChainErrApp"] = nil

  nebula_app_begin("TestChainErrApp")

  nebula_state("x", { type = "int32", default = 0 })

  nebula_on("btn", "click", {
    mutation = 'for i = 1, 10 do end',  -- forbidden syntax
  })

  nebula_app_end()

  local reg = nebula_app_registry["TestChainErrApp"]
  local graph = OmniscientGraph.build(reg, {
    MutationAST = MutationAST,
    EffectModel = EffectModel,
  })

  assert_true("chain_err_event_chains", graph.event_chains ~= nil)
  assert_eq("chain_err_len", #graph.event_chains, 1)
  assert_true("chain_err_has_parse_error", graph.event_chains[1].parse_error ~= nil)
  assert_true("chain_err_msg", graph.event_chains[1].parse_error.message:find("for") ~= nil)
end

-- build without opts (backward compat) — no event_chains
do
  nebula_app_registry["TestNoOptsApp"] = nil

  nebula_app_begin("TestNoOptsApp")
  nebula_state("x", { type = "int32" })
  nebula_on("btn", "click", { mutation = "self.x = self.x + 1" })
  nebula_app_end()

  local reg = nebula_app_registry["TestNoOptsApp"]
  local graph = OmniscientGraph.build(reg)  -- no opts
  assert_nil("no_opts_no_chains", graph.event_chains)
  assert_nil("no_opts_no_effects", graph.effects)
end

-- effects populated via build
do
  local reg = nebula_app_registry["TestChainApp"]
  local graph = OmniscientGraph.build(reg, {
    MutationAST = MutationAST,
    EffectModel = EffectModel,
  })
  assert_true("build_effects_populated", graph.effects ~= nil)
  assert_true("build_effects_nonempty", #graph.effects >= 1)
  assert_true("build_effects_for_state", graph.effects_for_state ~= nil)
end

-- =============================================================================
-- Summary
-- =============================================================================

print(("=== Phase 5.0 S1b smoke: %d passed, %d failed ==="):format(passed, failed))
if failed > 0 then os.exit(1) end
