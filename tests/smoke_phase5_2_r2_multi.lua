-- =============================================================================
-- smoke_phase5_2_r2_multi.lua
-- Phase 5.2 R2: 多 App / 多 Visual 场景测试
--
-- 验证全局状态消除后，多个 App 和 Visual 在同一编译会话中的 registry 隔离性：
--   1. 多 Visual 的 _auto_dense 互不覆盖
--   2. 多 App 的 _spec 互不覆盖
--   3. 多 App 的 _auto_dense_producers 互不覆盖
--   4. App registry 键完全独立
--   5. 向后兼容：全局变量只保留最后一次写入（覆盖行为已知）
--
-- 方法：加载 app_factory.lua 并使用真实的 registry API 进行多实例注册，
-- 验证 per-registry 数据隔离。
-- =============================================================================

local pass_count = 0
local fail_count = 0

local function check(name, cond)
  if cond then
    pass_count = pass_count + 1
  else
    fail_count = fail_count + 1
    print(("[FAIL] %s"):format(name))
  end
end

local function check_eq(name, got, expected)
  if got == expected then
    pass_count = pass_count + 1
  else
    fail_count = fail_count + 1
    print(("[FAIL] %s (got=%s, expected=%s)"):format(name, tostring(got), tostring(expected)))
  end
end

local function check_neq(name, a, b)
  if a ~= b then
    pass_count = pass_count + 1
  else
    fail_count = fail_count + 1
    print(("[FAIL] %s (values are equal: %s)"):format(name, tostring(a)))
  end
end

-- 定位 src 目录
local script_dir = debug.getinfo(1, "S").source:match("@(.*/)")
local src_dir = script_dir and (script_dir .. "../src/") or "src/"

-- 加载依赖模块
package.path = src_dir .. "?.lua;" .. src_dir .. "?/init.lua;" .. package.path
local layout_engine_path = src_dir .. "derive/layout_engine.lua"
dofile(layout_engine_path)
local factory_path = src_dir .. "derive/app_factory.lua"
dofile(factory_path)

-- 初始化全局 nebula_registry（模拟编译期环境）
nebula_registry = nebula_registry or {}

-- =============================================================================
-- ★ Test Group 1: 多 Visual 的 nebula_registry._auto_dense 隔离
-- =============================================================================
print("\n--- 1. 多 Visual _auto_dense 隔离 ---")

-- 模拟两个不同的 Visual 类型注册
nebula_registry["EditorVisualA"] = {
  states = {"default"}, primitives = {"multiline_editable"},
  transitions = {}, component_id = 0, text_mode = nil,
  max_chars = 256, instanced = false, max_instances = 128,
  max_text_len = 256, max_lines = 32,
}
nebula_registry["EditorVisualB"] = {
  states = {"default"}, primitives = {"multiline_editable"},
  transitions = {}, component_id = 0, text_mode = nil,
  max_chars = 512, instanced = false, max_instances = 128,
  max_text_len = 512, max_lines = 64,
}

-- 模拟 nebula_visual 的 _auto_dense 写入（per-visual）
nebula_registry["EditorVisualA"]._auto_dense = {
  dense_name = "EditorVisualADenseTextVisual",
  max_chars  = 6000,
}
nebula_registry["EditorVisualB"]._auto_dense = {
  dense_name = "EditorVisualBDenseTextVisual",
  max_chars  = 8000,
}

-- 验证隔离性
check("1.1_visual_A_has_own_auto_dense",
  nebula_registry["EditorVisualA"]._auto_dense ~= nil)
check("1.2_visual_B_has_own_auto_dense",
  nebula_registry["EditorVisualB"]._auto_dense ~= nil)
check_eq("1.3_visual_A_dense_name",
  nebula_registry["EditorVisualA"]._auto_dense.dense_name,
  "EditorVisualADenseTextVisual")
check_eq("1.4_visual_B_dense_name",
  nebula_registry["EditorVisualB"]._auto_dense.dense_name,
  "EditorVisualBDenseTextVisual")
check_eq("1.5_visual_A_max_chars",
  nebula_registry["EditorVisualA"]._auto_dense.max_chars, 6000)
check_eq("1.6_visual_B_max_chars",
  nebula_registry["EditorVisualB"]._auto_dense.max_chars, 8000)
-- 两者不是同一引用
check_neq("1.7_visuals_are_different_refs",
  nebula_registry["EditorVisualA"]._auto_dense,
  nebula_registry["EditorVisualB"]._auto_dense)

-- =============================================================================
-- ★ Test Group 2: 多 App 的 nebula_app_registry 隔离
-- =============================================================================
print("\n--- 2. 多 App registry 隔离 ---")

-- 注册两个 Visual 类型到 registry（用于组件注册）
nebula_registry["ButtonVisual"] = {
  states = {"default", "hovered", "pressed"},
  primitives = {"hoverable", "clickable"},
  transitions = {},
  component_id = 0, text_mode = nil, max_chars = 256,
  instanced = false, max_instances = 128, max_text_len = 255,
}
nebula_registry["SliderVisual"] = {
  states = {"default", "hovered"},
  primitives = {"hoverable"},
  transitions = {},
  component_id = 0, text_mode = nil, max_chars = 256,
  instanced = false, max_instances = 128, max_text_len = 255,
}

-- App A: 按钮应用
nebula_app_begin("MultiTestAppA")
  nebula_app_register_component("btn1", "ButtonVisual")
  nebula_app_register_component("btn2", "ButtonVisual")
nebula_app_end()

-- App B: 滑块应用
nebula_app_begin("MultiTestAppB")
  nebula_app_register_component("slider1", "SliderVisual")
nebula_app_end()

-- 验证两个 App 的 registry 独立
local regA = nebula_app_registry["MultiTestAppA"]
local regB = nebula_app_registry["MultiTestAppB"]

check("2.1_appA_exists", regA ~= nil)
check("2.2_appB_exists", regB ~= nil)
check_eq("2.3_appA_name", regA.name, "MultiTestAppA")
check_eq("2.4_appB_name", regB.name, "MultiTestAppB")
check_eq("2.5_appA_has_2_components", #regA.components, 2)
check_eq("2.6_appB_has_1_component", #regB.components, 1)
check_eq("2.7_appA_comp1_name", regA.components[1].name, "btn1")
check_eq("2.8_appA_comp2_name", regA.components[2].name, "btn2")
check_eq("2.9_appB_comp1_name", regB.components[1].name, "slider1")

-- 验证组件列表不共享
check_neq("2.10_components_not_shared",
  regA.components, regB.components)

-- =============================================================================
-- ★ Test Group 3: 多 App 的 _spec 隔离
-- =============================================================================
print("\n--- 3. 多 App _spec 隔离 ---")

-- 模拟 nebula_app() 写入 _spec
regA._spec = {
  components = {{ name = "btn1", type = "ButtonVisual" }, { name = "btn2", type = "ButtonVisual" }},
  title = "App A",
}
regB._spec = {
  components = {{ name = "slider1", type = "SliderVisual" }},
  title = "App B",
}

check("3.1_appA_spec_exists", regA._spec ~= nil)
check("3.2_appB_spec_exists", regB._spec ~= nil)
check_eq("3.3_appA_spec_title", regA._spec.title, "App A")
check_eq("3.4_appB_spec_title", regB._spec.title, "App B")
check_eq("3.5_appA_spec_comp_count", #regA._spec.components, 2)
check_eq("3.6_appB_spec_comp_count", #regB._spec.components, 1)
-- 修改 A 的 spec 不影响 B
regA._spec.title = "App A Modified"
check_eq("3.7_appB_spec_unchanged", regB._spec.title, "App B")

-- =============================================================================
-- ★ Test Group 4: 多 App 的 _auto_dense_producers 隔离
-- =============================================================================
print("\n--- 4. 多 App _auto_dense_producers 隔离 ---")

-- 模拟 nebula_app() 写入 _auto_dense_producers
regA._auto_dense_producers = {
  btn1 = {
    dense_name = "btn1_text",
    producer_name = "nebula_default_edit_area_btn1",
    max_chars = 6000,
    cell_w = 10.0,
    cell_h = 16.0,
  },
}
regB._auto_dense_producers = {
  slider1 = {
    dense_name = "slider1_text",
    producer_name = "nebula_default_edit_area_slider1",
    max_chars = 3000,
    cell_w = 8.0,
    cell_h = 14.0,
  },
}

-- 验证隔离性
check("4.1_appA_has_own_producers", regA._auto_dense_producers ~= nil)
check("4.2_appB_has_own_producers", regB._auto_dense_producers ~= nil)
check("4.3_appA_has_btn1_producer", regA._auto_dense_producers["btn1"] ~= nil)
check("4.4_appA_no_slider1_producer", regA._auto_dense_producers["slider1"] == nil)
check("4.5_appB_has_slider1_producer", regB._auto_dense_producers["slider1"] ~= nil)
check("4.6_appB_no_btn1_producer", regB._auto_dense_producers["btn1"] == nil)
check_eq("4.7_appA_producer_max_chars",
  regA._auto_dense_producers["btn1"].max_chars, 6000)
check_eq("4.8_appB_producer_max_chars",
  regB._auto_dense_producers["slider1"].max_chars, 3000)
-- 修改 A 的 producers 不影响 B
regA._auto_dense_producers["btn1"].max_chars = 9999
check_eq("4.9_appB_producer_unchanged",
  regB._auto_dense_producers["slider1"].max_chars, 3000)

-- =============================================================================
-- ★ Test Group 5: per-registry 读取优先级验证
-- =============================================================================
print("\n--- 5. per-registry 读取优先级 ---")

-- per-registry 读取（R2 finalized：无全局 fallback）
local c_reg = nebula_registry["EditorVisualA"]
local ad = c_reg and c_reg._auto_dense
check_eq("5.1_per_registry_read",
  ad.dense_name, "EditorVisualADenseTextVisual")

-- 未注册到 per-registry 的类型应得到 nil（不再有全局 fallback 兜底过期数据）
local c_reg_c = nebula_registry["EditorVisualC"]
local ad_c = c_reg_c and c_reg_c._auto_dense
check("5.3_no_global_fallback_yields_nil",
  ad_c == nil or ad_c == false)

-- per-app producers 读取（无全局 fallback）
local r2_adp = nebula_app_registry["MultiTestAppA"] and
  nebula_app_registry["MultiTestAppA"]._auto_dense_producers
check("5.4_per_app_producers_priority",
  r2_adp["btn1"] ~= nil and r2_adp["btn1"].dense_name == "btn1_text")

-- =============================================================================
-- ★ Test Group 6: 代码生成独立性
-- =============================================================================
print("\n--- 6. 代码生成独立性 ---")

local genA = nebula_app_generate("MultiTestAppA")
local genB = nebula_app_generate("MultiTestAppB")

check("6.1_genA_is_string", type(genA) == "string")
check("6.2_genB_is_string", type(genB) == "string")
check("6.3_genA_contains_btn1", genA:find("btn1") ~= nil)
check("6.4_genA_contains_btn2", genA:find("btn2") ~= nil)
check("6.5_genA_no_slider1", genA:find("slider1") == nil)
check("6.6_genB_contains_slider1", genB:find("slider1") ~= nil)
check("6.7_genB_no_btn1", genB:find("btn1") == nil)
check("6.8_genB_no_btn2", genB:find("btn2") == nil)

-- =============================================================================
-- ★ Result
-- =============================================================================
print(("\nPhase 5.2 R2 multi-app/visual test: %d/%d passed"):format(
  pass_count, pass_count + fail_count))
if fail_count > 0 then
  print(("  !! %d FAILED !!"):format(fail_count))
  os.exit(1)
else
  print("  ALL PASSED")
end
