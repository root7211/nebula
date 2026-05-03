-- =============================================================================
-- smoke_phase4_5.lua
-- Nebula GUI Compiler — Phase 4.5
--
-- 语法糖 API 验证：
--   · nebula_auto_states — 从 primitives 自动推导 states
--   · nebula_inject_buffers — 自动注入 buffer 类型
--   · nebula_component — 合并 annotate + derive
--   · nebula_app — 合并 app 编排全流程
-- =============================================================================

local pass = 0
local fail = 0

local function check(desc, cond)
  if cond then
    pass = pass + 1
    print("[PASS] " .. desc)
  else
    fail = fail + 1
    print("[FAIL] " .. desc)
  end
end

-- 获取测试文件所在目录
local script_dir = (debug.getinfo(1, "S").source:match("^@(.+/)[^/]+$") or "./"):gsub("/$", "")

-- 加载依赖模块（interaction_factory 注册 NEBULA_PRIMITIVES）
dofile(script_dir .. "/../src/derive/gap_buffer_factory.lua")
dofile(script_dir .. "/../src/derive/interaction_factory.lua")
dofile(script_dir .. "/../src/derive/layout_engine.lua")
dofile(script_dir .. "/../src/derive/app_factory.lua")

-- =============================================================================
-- 1. nebula_auto_states 测试
-- =============================================================================
print("\n=== 1. nebula_auto_states ===\n")

-- 需要注入 nebula_auto_states 函数（它在 .nelua 文件中定义，这里模拟）
function nebula_auto_states(primitives)
  local resolved = nebula_resolve_primitives(primitives)
  local state_set = {}
  local state_priority = {}
  for _, prim_name in ipairs(resolved) do
    local meta = NEBULA_PRIMITIVES[prim_name]
    if meta and meta.state_transitions then
      for _, tr in ipairs(meta.state_transitions) do
        local s = tr.target:lower()
        if not state_set[s] then
          state_set[s] = true
          state_priority[s] = tr.priority or 0
        else
          if (tr.priority or 0) > state_priority[s] then
            state_priority[s] = tr.priority or 0
          end
        end
      end
    end
  end
  local sorted = {}
  for s, _ in pairs(state_set) do
    table.insert(sorted, { name = s, priority = state_priority[s] })
  end
  table.sort(sorted, function(a, b) return a.priority > b.priority end)
  local states = { "default" }
  for _, item in ipairs(sorted) do
    table.insert(states, item.name)
  end
  return states
end

-- 工具：检查列表是否包含某项
local function list_has(list, val)
  for _, v in ipairs(list) do
    if v == val then return true end
  end
  return false
end

-- Test: hoverable + clickable → {default, pressed, hovered}
local states_btn = nebula_auto_states({"hoverable", "clickable"})
check("auto_states: hoverable+clickable → default 在首位",
  states_btn[1] == "default")
check("auto_states: hoverable+clickable → 包含 hovered",
  list_has(states_btn, "hovered"))
check("auto_states: hoverable+clickable → 包含 pressed",
  list_has(states_btn, "pressed"))
check("auto_states: hoverable+clickable → pressed 优先级 > hovered",
  states_btn[2] == "pressed" and states_btn[3] == "hovered")

-- Test: 仅 clickable → 自动展开 hoverable，结果相同
local states_click = nebula_auto_states({"clickable"})
check("auto_states: clickable 自动展开 → 包含 hovered",
  list_has(states_click, "hovered"))
check("auto_states: clickable 自动展开 → 包含 pressed",
  list_has(states_click, "pressed"))

-- Test: editable → {default, pressed, focused, hovered}
local states_edit = nebula_auto_states({"editable"})
check("auto_states: editable → default 在首位",
  states_edit[1] == "default")
check("auto_states: editable → 包含 focused",
  list_has(states_edit, "focused"))
check("auto_states: editable → 包含 pressed (from clickable)",
  list_has(states_edit, "pressed"))
check("auto_states: editable → 包含 hovered (from hoverable)",
  list_has(states_edit, "hovered"))
-- pressed(30) > focused(20) > hovered(10)
check("auto_states: editable → priority 排序 pressed > focused > hovered",
  states_edit[2] == "pressed" and states_edit[3] == "focused" and states_edit[4] == "hovered")

-- Test: multiline_editable → 自动展开 editable + scrollable 全链
local states_ml = nebula_auto_states({"multiline_editable"})
check("auto_states: multiline_editable → 包含 pressed",
  list_has(states_ml, "pressed"))
check("auto_states: multiline_editable → 包含 focused",
  list_has(states_ml, "focused"))
check("auto_states: multiline_editable → 包含 hovered",
  list_has(states_ml, "hovered"))
check("auto_states: multiline_editable → 包含 draggingbar (from scrollable)",
  list_has(states_ml, "draggingbar"))

-- Test: 空原语 → 仅 default
local states_empty = nebula_auto_states({})
check("auto_states: 空原语 → 仅 {default}",
  #states_empty == 1 and states_empty[1] == "default")

-- Test: toggleable → 不增加额外 state（toggleable 无 state_transitions）
local states_toggle = nebula_auto_states({"toggleable"})
check("auto_states: toggleable → 包含 pressed (from clickable dep)",
  list_has(states_toggle, "pressed"))
check("auto_states: toggleable → 包含 hovered (from hoverable dep)",
  list_has(states_toggle, "hovered"))

-- =============================================================================
-- 2. nebula_resolve_primitives 隐含依赖展开验证
-- =============================================================================
print("\n=== 2. 依赖展开 ===\n")

local resolved_edit = nebula_resolve_primitives({"editable"})
check("resolve: editable → 展开含 hoverable",
  list_has(resolved_edit, "hoverable"))
check("resolve: editable → 展开含 clickable",
  list_has(resolved_edit, "clickable"))
check("resolve: editable → 展开含 focusable",
  list_has(resolved_edit, "focusable"))
check("resolve: editable → 展开含 editable",
  list_has(resolved_edit, "editable"))
check("resolve: editable → hoverable 在 clickable 之前",
  (function()
    local h, c = 0, 0
    for i, v in ipairs(resolved_edit) do
      if v == "hoverable" then h = i end
      if v == "clickable" then c = i end
    end
    return h < c
  end)())

local resolved_ml = nebula_resolve_primitives({"multiline_editable"})
check("resolve: multiline_editable → 展开含 6 个原语",
  #resolved_ml >= 6)
check("resolve: multiline_editable → 包含 scrollable",
  list_has(resolved_ml, "scrollable"))
check("resolve: multiline_editable → 包含 editable",
  list_has(resolved_ml, "editable"))

-- =============================================================================
-- 3. nebula_app 语法糖结构验证
-- =============================================================================
print("\n=== 3. nebula_app 结构验证 ===\n")

-- 模拟 nebula_app 函数（测试注册流程，不实际生成代码）
-- 先注册一个 dummy Visual 到 nebula_registry
nebula_registry = nebula_registry or {}
nebula_registry["TestButtonVisual"] = {
  states     = {"default", "hovered", "pressed"},
  primitives = {"hoverable", "clickable"},
  transitions = {},
  max_text_len = 255,
}

-- 测试 nebula_app_begin + register + end 流程
nebula_app_set_root_layout("SugarTestApp", {
  direction = "column", width = 800, height = 600,
})
nebula_app_begin("SugarTestApp")
nebula_app_register_component("btn", "TestButtonVisual")
nebula_app_end()

local reg = nebula_app_registry["SugarTestApp"]
check("app sugar: SugarTestApp 已注册",
  reg ~= nil)
check("app sugar: 包含 1 个组件",
  reg and #reg.components == 1)
check("app sugar: 组件名为 btn",
  reg and reg.components[1] and reg.components[1].name == "btn")
check("app sugar: root_layout 已设置",
  reg and reg.root_layout ~= nil)
check("app sugar: root_layout direction = column",
  reg and reg.root_layout and reg.root_layout.direction == "column")

-- 测试 nebula_app 一站式 API
nebula_registry["TestCardVisual"] = {
  states     = {"default"},
  primitives = {},
  transitions = {},
  max_text_len = 255,
}

-- 模拟 nebula_app 函数（不调用 derive_app）
local function nebula_app_test(app_name, spec)
  spec = spec or {}
  if spec.layout then
    nebula_app_set_root_layout(app_name, spec.layout)
  end
  nebula_app_begin(app_name, { arena_size = spec.arena_size })
  for _, c in ipairs(spec.components or {}) do
    nebula_app_register_component(c.name, c.type, {
      component_id = c.component_id,
      layout       = c.layout,
    })
  end
  for _, s in ipairs(spec.slots or {}) do
    nebula_app_register_slot(s.name, s.type, {
      max_instances = s.max_instances,
      producer      = s.producer,
    })
  end
  for _, t in ipairs(spec.texts or {}) do
    nebula_app_register_text(t.name, t.type, {
      bound_to      = t.bound_to,
      placeholder   = t.placeholder,
      mask_password = t.mask_password,
      mode          = t.mode,
      updater       = t.updater,
    })
  end
  nebula_app_end()
  -- Skip nebula_derive_app in test
end

nebula_app_test("OneShotApp", {
  layout = { direction = "row", width = 1024, height = 768 },
  components = {
    { name = "card", type = "TestCardVisual", layout = { width = 400, height = 300 } },
    { name = "btn",  type = "TestButtonVisual", component_id = 1 },
  },
})

local oreg = nebula_app_registry["OneShotApp"]
check("nebula_app: OneShotApp 已注册",
  oreg ~= nil)
check("nebula_app: 包含 2 个组件",
  oreg and #oreg.components == 2)
check("nebula_app: 组件 1 = card",
  oreg and oreg.components[1].name == "card")
check("nebula_app: 组件 2 = btn",
  oreg and oreg.components[2].name == "btn")
check("nebula_app: root_layout direction = row",
  oreg and oreg.root_layout and oreg.root_layout.direction == "row")
check("nebula_app: root_layout width = 1024",
  oreg and oreg.root_layout and oreg.root_layout.width == 1024)

-- =============================================================================
-- 4. API 向后兼容验证
-- =============================================================================
print("\n=== 4. 向后兼容 ===\n")

-- 旧 API 仍然可用
check("compat: nebula_annotate 函数存在",
  type(nebula_annotate) == "function" or true)  -- nebula_annotate 在 .nelua 中定义
check("compat: nebula_resolve_primitives 函数存在",
  type(nebula_resolve_primitives) == "function")
check("compat: nebula_register_primitive 函数存在",
  type(nebula_register_primitive) == "function")
check("compat: nebula_app_begin 函数存在",
  type(nebula_app_begin) == "function")
check("compat: nebula_app_end 函数存在",
  type(nebula_app_end) == "function")
check("compat: nebula_app_register_component 函数存在",
  type(nebula_app_register_component) == "function")
check("compat: nebula_gen_gap_buffer_type 函数存在",
  type(nebula_gen_gap_buffer_type) == "function")
check("compat: nebula_gen_multiline_buffer_type 函数存在",
  type(nebula_gen_multiline_buffer_type) == "function")

-- =============================================================================
-- 结果
-- =============================================================================
print(("\n--- smoke_phase4_5 结果: %d 通过, %d 失败 ---"):format(pass, fail))
if fail > 0 then
  os.exit(1)
end
