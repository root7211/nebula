-- =============================================================================
-- smoke_phase4_5_s2.lua
-- Nebula GUI Compiler — Phase 4.5-S2
--
-- 混合管线自动编排验证：
--   · nebula_app components 数组中 text_mode="dense" 的 Visual 自动路由到
--     nebula_app_register_dense_text
--   · 标准 Visual（无 text_mode）仍路由到 nebula_app_register_component
--   · producer 必需校验（dense 组件缺 producer 应报错）
--   · 向后兼容：显式 dense_texts 数组仍然工作
--   · highlight_sugar_demo.nelua 文件存在 + 使用新 API
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

-- 加载依赖模块
dofile(script_dir .. "/../src/derive/gap_buffer_factory.lua")
dofile(script_dir .. "/../src/derive/interaction_factory.lua")
dofile(script_dir .. "/../src/derive/layout_engine.lua")
dofile(script_dir .. "/../src/derive/app_factory.lua")

-- =============================================================================
-- 1. nebula_registry text_mode 属性检测
-- =============================================================================
print("\n=== 1. text_mode 属性检测 ===\n")

nebula_registry = nebula_registry or {}

-- 注册标准 Visual（无 text_mode）
nebula_registry["StdVisual"] = {
  states = {"default", "hovered", "pressed"},
  primitives = {"hoverable", "clickable"},
  transitions = {},
}

-- 注册 dense Visual（text_mode = "dense"）
nebula_registry["DenseVisualA"] = {
  states = {"default"},
  primitives = {},
  transitions = {},
  text_mode = "dense",
  max_chars = 4096,
}

nebula_registry["DenseVisualB"] = {
  states = {"default"},
  primitives = {},
  transitions = {},
  text_mode = "dense",
  max_chars = 1024,
}

check("StdVisual: text_mode is nil",
  nebula_registry["StdVisual"].text_mode == nil)
check("DenseVisualA: text_mode = 'dense'",
  nebula_registry["DenseVisualA"].text_mode == "dense")
check("DenseVisualB: text_mode = 'dense'",
  nebula_registry["DenseVisualB"].text_mode == "dense")

-- =============================================================================
-- 2. 混合管线自动路由逻辑模拟
-- =============================================================================
print("\n=== 2. 混合管线自动路由 ===\n")

-- 模拟 nebula_app 的 S2 路由逻辑（不调用 derive_app / inject）
local function nebula_app_s2_test(app_name, spec)
  spec = spec or {}
  if spec.layout then
    nebula_app_set_root_layout(app_name, spec.layout)
  end
  nebula_app_begin(app_name, { arena_size = spec.arena_size })

  -- ★ S2 混合管线自动编排逻辑
  for _, c in ipairs(spec.components or {}) do
    local reg = nebula_registry[c.type]
    local text_mode = reg and reg.text_mode or nil
    if text_mode == "dense" then
      assert(c.producer, ("nebula_app: component '%s' (type=%s, text_mode=dense) requires producer"):format(c.name, c.type))
      nebula_app_register_dense_text(c.name, c.type, {
        max_chars = c.max_chars,
        cell_w    = c.cell_w,
        cell_h    = c.cell_h,
        producer  = c.producer,
        layout    = c.layout,
      })
    else
      nebula_app_register_component(c.name, c.type, {
        component_id = c.component_id,
        layout       = c.layout,
      })
    end
  end

  -- 向后兼容：显式 dense_texts
  for _, d in ipairs(spec.dense_texts or {}) do
    nebula_app_register_dense_text(d.name, d.type, {
      max_chars = d.max_chars,
      cell_w    = d.cell_w,
      cell_h    = d.cell_h,
      producer  = d.producer,
      layout    = d.layout,
    })
  end

  nebula_app_end()
end

-- 测试：混合 components 数组 → 标准 + dense 自动分流
nebula_app_s2_test("MixedApp", {
  layout = { direction = "row", width = 1280, height = 800 },
  components = {
    { name = "bg",       type = "StdVisual" },
    { name = "dense_a",  type = "DenseVisualA",
      producer = "fill_a", cell_w = 10.0, cell_h = 16.0,
      max_chars = 4000, layout = { flex_grow = 1 } },
    { name = "dense_b",  type = "DenseVisualB",
      producer = "fill_b", cell_w = 10.0, cell_h = 16.0,
      max_chars = 1000, layout = { flex_basis = 50 } },
  },
})

local mreg = nebula_app_registry["MixedApp"]
check("MixedApp: 已注册", mreg ~= nil)
check("MixedApp: 1 个标准组件", mreg and #mreg.components == 1)
check("MixedApp: 标准组件名 = bg", mreg and mreg.components[1].name == "bg")
check("MixedApp: 2 个 dense_text 组件", mreg and #mreg.dense_texts == 2)
check("MixedApp: dense_text[1] = dense_a",
  mreg and mreg.dense_texts[1].name == "dense_a")
check("MixedApp: dense_text[2] = dense_b",
  mreg and mreg.dense_texts[2].name == "dense_b")
check("MixedApp: dense_a producer = fill_a",
  mreg and mreg.dense_texts[1].producer == "fill_a")
check("MixedApp: dense_b layout.flex_basis = 50",
  mreg and mreg.dense_texts[2].layout and mreg.dense_texts[2].layout.flex_basis == 50)
check("MixedApp: root_layout direction = row",
  mreg and mreg.root_layout and mreg.root_layout.direction == "row")

-- =============================================================================
-- 3. producer 必需校验（dense 缺 producer 应报错）
-- =============================================================================
print("\n=== 3. producer 必需校验 ===\n")

local ok_no_prod, err_no_prod = pcall(nebula_app_s2_test, "BadDenseApp", {
  components = {
    { name = "no_prod", type = "DenseVisualA", max_chars = 100 },
  },
})
check("dense without producer: rejected",
  not ok_no_prod and err_no_prod:find("requires producer"))

-- =============================================================================
-- 4. 纯标准组件（无 dense）仍然正常
-- =============================================================================
print("\n=== 4. 纯标准组件 ===\n")

nebula_app_s2_test("PureStdApp", {
  layout = { direction = "column", width = 800, height = 600 },
  components = {
    { name = "a", type = "StdVisual", component_id = 1 },
    { name = "b", type = "StdVisual", component_id = 2 },
  },
})

local preg = nebula_app_registry["PureStdApp"]
check("PureStdApp: 2 个标准组件", preg and #preg.components == 2)
check("PureStdApp: 0 个 dense_text", preg and #preg.dense_texts == 0)

-- =============================================================================
-- 5. 向后兼容：显式 dense_texts 数组
-- =============================================================================
print("\n=== 5. 向后兼容 dense_texts ===\n")

nebula_app_s2_test("CompatApp", {
  components = {
    { name = "bg", type = "StdVisual" },
  },
  dense_texts = {
    { name = "dt1", type = "DenseVisualA",
      producer = "fill_dt1", cell_w = 10.0, cell_h = 16.0, max_chars = 2000 },
  },
})

local creg = nebula_app_registry["CompatApp"]
check("CompatApp: 1 个标准组件", creg and #creg.components == 1)
check("CompatApp: 1 个 dense_text (显式)", creg and #creg.dense_texts == 1)
check("CompatApp: dense_text 来自 dense_texts 数组",
  creg and creg.dense_texts[1].name == "dt1")

-- =============================================================================
-- 6. 混合：components auto + 显式 dense_texts 共存
-- =============================================================================
print("\n=== 6. auto + 显式 dense_texts 共存 ===\n")

nebula_app_s2_test("HybridApp", {
  components = {
    { name = "bg",      type = "StdVisual" },
    { name = "auto_dt", type = "DenseVisualA",
      producer = "fill_auto", cell_w = 10.0, cell_h = 16.0, max_chars = 500 },
  },
  dense_texts = {
    { name = "explicit_dt", type = "DenseVisualB",
      producer = "fill_explicit", cell_w = 10.0, cell_h = 16.0, max_chars = 300 },
  },
})

local hreg = nebula_app_registry["HybridApp"]
check("HybridApp: 1 个标准组件", hreg and #hreg.components == 1)
check("HybridApp: 2 个 dense_text (auto + explicit)",
  hreg and #hreg.dense_texts == 2)

-- =============================================================================
-- 7. highlight_sugar_demo.nelua 文件验证
-- =============================================================================
print("\n=== 7. highlight_sugar_demo 文件验证 ===\n")

local demo_file = io.open(script_dir .. "/../examples/highlight_sugar_demo.nelua", "r")
check("highlight_sugar_demo.nelua exists", demo_file ~= nil)

if demo_file then
  local content = demo_file:read("*a")
  demo_file:close()

  -- 使用新 API
  check("demo uses nebula_component",
    content:find("nebula_component") ~= nil)
  check("demo uses nebula_app with components array",
    content:find("nebula_app") ~= nil and content:find("components") ~= nil)
  check("demo uses nebula_init",
    content:find("nebula_init") ~= nil)
  check("demo uses nebula_should_close",
    content:find("nebula_should_close") ~= nil)
  check("demo uses nebula_shutdown",
    content:find("nebula_shutdown") ~= nil)
  check("demo uses nebula_inject_buffers",
    content:find("nebula_inject_buffers") ~= nil)

  -- 不使用旧 API（组件声明部分，排除注释中的引用）
  check("demo does NOT use nebula_annotate",
    content:find("nebula_annotate") == nil)
  -- nebula_app_begin/end 仅出现在注释中（旧写法对比），不作为实际 API 调用
  -- 检查：没有非注释行调用 nebula_app_begin/end
  local has_active_app_begin = false
  local has_active_app_end = false
  for line in content:gmatch("[^\n]+") do
    local stripped = line:match("^%s*(.-)%s*$") or ""
    if not stripped:match("^%-%-") and not stripped:match("^##%s*%-%-") then
      if stripped:find("nebula_app_begin") then has_active_app_begin = true end
      if stripped:find("nebula_app_end") then has_active_app_end = true end
    end
  end
  check("demo does NOT actively call nebula_app_begin",
    not has_active_app_begin)
  check("demo does NOT actively call nebula_app_end",
    not has_active_app_end)

  -- 语法高亮功能仍在
  check("demo uses nebula_highlight_rules",
    content:find("nebula_highlight_rules") ~= nil)
  check("demo uses nebula_highlight_scan_nelua",
    content:find("nebula_highlight_scan_nelua") ~= nil)
end

-- =============================================================================
-- 8. build.sh 目标验证
-- =============================================================================
print("\n=== 8. build.sh 验证 ===\n")

local build_sh = io.open(script_dir .. "/../build.sh", "r")
if build_sh then
  local content = build_sh:read("*a")
  build_sh:close()
  check("build.sh: includes highlight_sugar_demo target",
    content:find("highlight_sugar_demo") ~= nil)
else
  check("build.sh: file readable", false)
end

-- =============================================================================
-- 总结
-- =============================================================================
print(("\n--- smoke_phase4_5_s2 结果: %d 通过, %d 失败 ---"):format(pass, fail))
if fail > 0 then
  os.exit(1)
end
