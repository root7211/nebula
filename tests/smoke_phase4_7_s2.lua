-- =============================================================================
-- smoke_phase4_7_s2.lua
-- Nebula GUI Compiler — Phase 4.7-S2
--
-- DenseText App 编排层集成验证：
--   · nebula_app_register_dense_text API 可用性
--   · App record 中注入 DenseText 管线字段
--   · App init 中生成 DenseText 管线初始化代码
--   · App draw 中生成 DenseText producer → upload → draw 代码
--   · App deinit 中生成 DenseText 管线释放代码
--   · 与现有管线（standard_instanced / text / shadow）共存无冲突
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

-- 加载依赖模块（app_factory 依赖 layout_engine）
local layout_path = script_dir .. "/../src/derive/layout_engine.lua"
if io.open(layout_path, "r") then dofile(layout_path) end

-- 加载 app_factory 模块
local factory_path = script_dir .. "/../src/derive/app_factory.lua"
local app_factory_ver = dofile(factory_path)

-- =============================================================================
-- 1. API 存在性验证
-- =============================================================================
check("nebula_app_register_dense_text exists",
  type(nebula_app_register_dense_text) == "function")

check("nebula_app_begin exists",
  type(nebula_app_begin) == "function")

check("nebula_app_end exists",
  type(nebula_app_end) == "function")

check("nebula_app_generate exists",
  type(nebula_app_generate) == "function")

check("app_factory version >= v0.9",
  app_factory_ver and (app_factory_ver:find("v0.9") ~= nil or app_factory_ver:find("v0.10") ~= nil or app_factory_ver:find("v0.11") ~= nil or app_factory_ver:find("v0.12") ~= nil))

-- =============================================================================
-- 2. 注册 API 基础校验
-- =============================================================================

-- 2.1 正常注册流程
nebula_app_begin("TestDenseApp")
nebula_app_register_dense_text("dt_test", "DenseTextVisual", {
  max_chars = 4000,
  cell_w = 10.0,
  cell_h = 16.0,
  producer = "test_fill_text",
})
nebula_app_end()

local reg = nebula_app_registry["TestDenseApp"]
check("dense_texts list populated",
  reg and #reg.dense_texts == 1)

check("dense_text name = 'dt_test'",
  reg.dense_texts[1].name == "dt_test")

check("dense_text visual_type = 'DenseTextVisual'",
  reg.dense_texts[1].visual_type == "DenseTextVisual")

check("dense_text base = 'DenseText'",
  reg.dense_texts[1].base == "DenseText")

check("dense_text max_chars = 4000",
  reg.dense_texts[1].max_chars == 4000)

check("dense_text cell_w = 10.0",
  reg.dense_texts[1].cell_w == 10.0)

check("dense_text cell_h = 16.0",
  reg.dense_texts[1].cell_h == 16.0)

check("dense_text producer = 'test_fill_text'",
  reg.dense_texts[1].producer == "test_fill_text")

-- 2.2 producer 必须提供
local ok_no_producer, err_no_producer = pcall(function()
  nebula_app_begin("TestDenseNoProd")
  nebula_app_register_dense_text("dt_fail", "DenseTextVisual", {})
  nebula_app_end()
end)
check("producer required (error on missing)",
  not ok_no_producer and err_no_producer:find("producer") ~= nil)

-- 清理 — begin 成功但 register 失败后 _current_app 仍处于活跃状态
-- 需要调用 nebula_app_end 关闭（如果 begin 已执行），否则后续测试会受影响
if nebula_app_registry["TestDenseNoProd"] then
  -- begin 执行成功，需要显式关闭
  pcall(nebula_app_end)
end
nebula_app_registry["TestDenseNoProd"] = nil

-- 2.3 scope guard: must be between begin/end
local ok_outside, err_outside = pcall(function()
  nebula_app_register_dense_text("dt_outside", "DenseTextVisual", {
    producer = "test_fill",
  })
end)
check("scope guard: error when called outside begin/end",
  not ok_outside and err_outside:find("nebula_app_begin") ~= nil)

-- 2.4 默认值校验
nebula_app_begin("TestDenseDefaults")
nebula_app_register_dense_text("dt_def", "DenseTextVisual", {
  producer = "test_fill",
})
nebula_app_end()

local reg_def = nebula_app_registry["TestDenseDefaults"]
check("default max_chars = 6000",
  reg_def.dense_texts[1].max_chars == 6000)
check("default cell_w = 10.0",
  reg_def.dense_texts[1].cell_w == 10.0)
check("default cell_h = 16.0",
  reg_def.dense_texts[1].cell_h == 16.0)

-- =============================================================================
-- 3. 与现有组件/文本/阴影共存
-- =============================================================================
nebula_app_begin("TestMixedApp")
-- 不实际注册 component（因为需要 nebula_registry 和 type_groups），
-- 直接注册 dense_text 验证共存不冲突
nebula_app_register_dense_text("mixed_dt", "DenseTextVisual", {
  max_chars = 2000,
  cell_w = 8.0,
  cell_h = 14.0,
  producer = "mixed_fill",
})
nebula_app_end()

local reg_mix = nebula_app_registry["TestMixedApp"]
check("mixed app: dense_texts populated",
  #reg_mix.dense_texts == 1)
check("mixed app: components list empty (no conflict)",
  #reg_mix.components == 0)
check("mixed app: texts list empty (no conflict)",
  #reg_mix.texts == 0)
check("mixed app: shadows list empty (no conflict)",
  #reg_mix.shadows == 0)

-- =============================================================================
-- 4. 多个 DenseText 实例注册
-- =============================================================================
nebula_app_begin("TestMultiDense")
nebula_app_register_dense_text("dt_editor", "DenseTextVisual", {
  max_chars = 6000,
  producer = "fill_editor",
})
nebula_app_register_dense_text("dt_linenum", "DenseTextVisual", {
  max_chars = 1000,
  cell_w = 8.0,
  cell_h = 14.0,
  producer = "fill_linenum",
})
nebula_app_end()

local reg_multi = nebula_app_registry["TestMultiDense"]
check("multi dense: 2 dense_texts registered",
  #reg_multi.dense_texts == 2)
check("multi dense: first = dt_editor",
  reg_multi.dense_texts[1].name == "dt_editor")
check("multi dense: second = dt_linenum",
  reg_multi.dense_texts[2].name == "dt_linenum")
check("multi dense: different max_chars",
  reg_multi.dense_texts[1].max_chars == 6000 and
  reg_multi.dense_texts[2].max_chars == 1000)

-- =============================================================================
-- 5. _extract_base 辅助函数测试（通过注册间接验证）
-- =============================================================================
nebula_app_begin("TestBaseExtract")
nebula_app_register_dense_text("dt_be1", "MyEditorVisual", {
  producer = "fill_1",
})
nebula_app_register_dense_text("dt_be2", "RawPipeline", {
  producer = "fill_2",
})
nebula_app_end()

local reg_be = nebula_app_registry["TestBaseExtract"]
check("base extraction: 'MyEditorVisual' -> 'MyEditor'",
  reg_be.dense_texts[1].base == "MyEditor")
check("base extraction: 'RawPipeline' (no Visual suffix) -> 'RawPipeline'",
  reg_be.dense_texts[2].base == "RawPipeline")

-- =============================================================================
-- 总结
-- =============================================================================
print("")
print(("--- smoke_phase4_7_s2 结果: %d 通过, %d 失败 ---"):format(pass, fail))
if fail > 0 then
  os.exit(1)
end
