-- =============================================================================
-- tests/smoke_phase3_12.lua — Nebula Phase 3.12 专项回归测试
--
-- 覆盖范围：
--   1. nebula_layout_derive_segments API 可用性
--   2. 无临界点场景：单一全局线性段
--   3. 有临界点场景：多分段系数推导（Clamp 感知）
--   4. 分段系数数学正确性验证（在各视口尺寸下误差 < 1px）
--   5. app_factory 分段系数推导集成（layout_segments 填充）
--   6. 生成代码包含 Phase 3.12 响应式更新代码
--   7. 生成代码结构验证（if viewport_resized / update_viewport / if-else 分支）
--   8. 无 layout 时生成代码不含响应式更新代码（向后兼容）
--   9. NebulaInputState 新字段存在性验证（通过 nebula_core.nelua 文本检查）
--  10. glfw_bindings.nelua 包含 framebuffer resize 绑定
--  11. app.nelua 包含 resize 回调注册和视口状态收集
--  12. app_factory.lua 版本标识
--  13. 行数收敛验证
-- =============================================================================

local passed = 0
local failed = 0

local script_dir = (debug.getinfo(1, "S").source:match("^@(.+/)[^/]+$") or "./"):gsub("/$", "")

-- =============================================================================
-- 测试工具函数
-- =============================================================================
local function assert_eq(name, got, expected)
  if got == expected then
    passed = passed + 1
    print(("[PASS] %s"):format(name))
  else
    failed = failed + 1
    print(("[FAIL] %s\n       expected: %s\n       got:      %s"):format(name, tostring(expected), tostring(got)))
  end
end

local function assert_contains(name, haystack, needle)
  if type(haystack) == "string" and haystack:find(needle, 1, true) then
    passed = passed + 1
    print(("[PASS] %s"):format(name))
  else
    failed = failed + 1
    print(("[FAIL] %s\n       needle not found: %s"):format(name, needle))
  end
end

local function assert_not_contains(name, haystack, needle)
  if type(haystack) == "string" and not haystack:find(needle, 1, true) then
    passed = passed + 1
    print(("[PASS] %s"):format(name))
  else
    failed = failed + 1
    print(("[FAIL] %s\n       needle unexpectedly found: %s"):format(name, needle))
  end
end

local function assert_le(name, got, limit)
  if got <= limit then
    passed = passed + 1
    print(("[PASS] %s (%d <= %d)"):format(name, got, limit))
  else
    failed = failed + 1
    print(("[FAIL] %s (%d > %d)"):format(name, got, limit))
  end
end

local function assert_near(name, got, expected, tolerance)
  tolerance = tolerance or 1.0
  if math.abs(got - expected) <= tolerance then
    passed = passed + 1
    print(("[PASS] %s (%.2f ≈ %.2f ±%.1f)"):format(name, got, expected, tolerance))
  else
    failed = failed + 1
    print(("[FAIL] %s (%.2f ≠ %.2f ±%.1f)"):format(name, got, expected, tolerance))
  end
end

local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  return content
end

local function count_lines(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local n = 0
  for _ in f:lines() do n = n + 1 end
  f:close()
  return n
end

-- =============================================================================
-- 加载依赖模块
-- =============================================================================
package.path = script_dir .. "/../src/?.lua;" .. script_dir .. "/../src/?/init.lua;" .. package.path

local layout_engine_path = script_dir .. "/../src/derive/layout_engine.lua"
local layout_engine_version = dofile(layout_engine_path)

local factory_path = script_dir .. "/../src/derive/app_factory.lua"
local factory_version = dofile(factory_path)

-- =============================================================================
-- 1. nebula_layout_derive_segments API 可用性
-- =============================================================================
print("\n--- 1. nebula_layout_derive_segments API 可用性 ---")

assert_eq("nebula_layout_derive_segments 是全局函数",
  type(nebula_layout_derive_segments), "function")
assert_eq("nebula_layout_node 是全局函数",
  type(nebula_layout_node), "function")
assert_eq("nebula_layout_solve 是全局函数",
  type(nebula_layout_solve), "function")

-- =============================================================================
-- 2. 无临界点场景：单一全局线性段
-- =============================================================================
print("\n--- 2. 无临界点场景：单一全局线性段 ---")

-- 构建一个简单的 column 布局，子元素不会溢出视口
local simple_spec = {
  name      = "_root",
  direction = "column",
  justify   = "center",
  align     = "center",
  padding   = 0,
  gap       = 0,
  width     = 800,
  height    = 600,
  children  = {
    nebula_layout_node({ name="box", width=200, height=100 }),
  },
}

local result_simple = nebula_layout_derive_segments(simple_spec, 800, 600)
assert_eq("无临界点场景返回 table", type(result_simple), "table")
assert_eq("无临界点场景 segments 字段存在", type(result_simple.segments), "table")
-- 注：即使子元素不会溢出，也会根据子元素总尺寸生成一个临界点（防溢出保护）
-- 因此无溢出场景也可能有 2 个分段，断言改为 >= 1
assert_eq("无溢出场景至少有 1 个分段", #result_simple.segments >= 1, true)

-- 验证第一个分段（默认分段，即 threshold = nil 的分段）必存在
local seg0 = nil
for _, s in ipairs(result_simple.segments) do
  if s.threshold_h == nil and s.threshold_w == nil then
    seg0 = s
    break
  end
end
assert_eq("默认分段（threshold=nil）存在", seg0 ~= nil, true)
if seg0 then
  assert_eq("默认分段 coeffs 存在", type(seg0.coeffs), "table")
  assert_eq("默认分段 box 系数存在", type(seg0.coeffs["box"]), "table")
end

-- =============================================================================
-- 3. 有临界点场景：多分段系数推导（Clamp 感知）
-- =============================================================================
print("\n--- 3. 有临界点场景：多分段系数推导 ---")

-- 构建一个 column 布局，子元素总高度 = 300，当视口高度 < 300 时会触发 clamp
local clamp_spec = {
  name      = "_root",
  direction = "column",
  justify   = "space_between",
  align     = "center",
  padding   = 0,
  gap       = 0,
  width     = 800,
  height    = 600,
  children  = {
    nebula_layout_node({ name="item_a", width=200, height=150 }),
    nebula_layout_node({ name="item_b", width=200, height=150 }),
  },
}

local result_clamp = nebula_layout_derive_segments(clamp_spec, 800, 600)
assert_eq("有临界点场景返回 table", type(result_clamp), "table")
assert_eq("有临界点场景 segments 字段存在", type(result_clamp.segments), "table")
-- 应该有至少 2 个分段（一个正常区域，一个溢出区域）
local seg_count = #result_clamp.segments
assert_eq("有临界点场景有 >= 2 个分段", seg_count >= 2, true)
print(("  [INFO] 检测到 %d 个分段"):format(seg_count))

-- =============================================================================
-- 4. 分段系数数学正确性验证
-- =============================================================================
print("\n--- 4. 分段系数数学正确性验证 ---")

-- 使用 Phase 3.11 的标准登录表单布局进行验证
local login_spec = {
  name      = "_root",
  direction = "column",
  justify   = "center",
  align     = "center",
  padding   = 0,
  gap       = 0,
  width     = 800,
  height    = 600,
  children  = {
    nebula_layout_node({
      name      = "card",
      width     = 360,
      height    = 440,
      direction = "column",
      justify   = "start",
      align     = "center",
      padding   = 32,
      gap       = 16,
      children  = {
        nebula_layout_node({ name="email_input",    width=296, height=44 }),
        nebula_layout_node({ name="password_input", width=296, height=44 }),
        nebula_layout_node({ name="login_btn",      width=296, height=48 }),
      },
    }),
  },
}

local result_login = nebula_layout_derive_segments(login_spec, 800, 600)

-- 辅助函数：使用分段系数预测给定视口下的组件坐标
local function predict_with_segments(segments, comp_name, vw, vh)
  -- 找到匹配的分段（按 threshold_h 降序检查）
  local normal_segs = {}
  local default_seg = nil
  for _, seg in ipairs(segments) do
    if seg.threshold_h ~= nil or seg.threshold_w ~= nil then
      table.insert(normal_segs, seg)
    else
      default_seg = seg
    end
  end
  table.sort(normal_segs, function(a, b)
    local ta = a.threshold_h or a.threshold_w or 0
    local tb = b.threshold_h or b.threshold_w or 0
    return ta > tb
  end)

  local matched_seg = default_seg
  for _, seg in ipairs(normal_segs) do
    if seg.threshold_h and vh >= seg.threshold_h then
      matched_seg = seg
      break
    elseif seg.threshold_w and vw >= seg.threshold_w then
      matched_seg = seg
      break
    end
  end

  if not matched_seg then return nil end
  local c = matched_seg.coeffs[comp_name]
  if not c then return nil end

  return {
    x = c.cx_vw * vw + c.cx_c,
    y = c.cy_vh * vh + c.cy_c,
    w = c.cw_vw * vw + c.cw_c,
    h = c.ch_vh * vh + c.ch_c,
  }
end

-- 辅助函数：直接解算给定视口下的组件坐标（ground truth）
local function solve_at(spec, comp_name, vw, vh)
  local root = nebula_layout_node(spec)
  nebula_layout_solve(root, vw, vh)
  local results = nebula_layout_collect(root)
  return results[comp_name]
end

-- 测试多个视口尺寸下的预测精度
local test_viewports = {
  {800, 600},   -- 基准视口
  {1024, 768},  -- 较大视口
  {1280, 900},  -- 更大视口
  {600, 480},   -- 较小视口（可能触发 clamp）
  {400, 300},   -- 很小视口（溢出区域）
}

for _, vp in ipairs(test_viewports) do
  local vw, vh = vp[1], vp[2]
  local pred = predict_with_segments(result_login.segments, "card", vw, vh)
  local truth = solve_at(login_spec, "card", vw, vh)
  if pred and truth then
    assert_near(
      ("card.x 在视口 %dx%d 下预测误差 < 1px"):format(vw, vh),
      pred.x, truth.x, 1.0)
    assert_near(
      ("card.y 在视口 %dx%d 下预测误差 < 1px"):format(vw, vh),
      pred.y, truth.y, 1.0)
  else
    failed = failed + 1
    print(("[FAIL] 视口 %dx%d 下预测或解算失败"):format(vw, vh))
  end
end

-- =============================================================================
-- 5. app_factory 分段系数推导集成
-- =============================================================================
print("\n--- 5. app_factory 分段系数推导集成 ---")

nebula_app_set_root_layout("Phase312TestApp", {
  direction = "column",
  justify   = "center",
  align     = "center",
  width     = 800,
  height    = 600,
})

nebula_app_begin("Phase312TestApp")
  nebula_app_register_component("card", "CardVisual", {
    layout = {
      width     = 360,
      height    = 440,
      direction = "column",
      justify   = "start",
      align     = "center",
      padding   = 32,
      gap       = 16,
      children  = {
        { name="email_input",    width=296, height=44 },
        { name="password_input", width=296, height=44 },
        { name="login_btn",      width=296, height=48 },
      },
    },
  })
  nebula_app_register_component("email_input",    "InputVisual",  {component_id=1})
  nebula_app_register_component("password_input", "InputVisual",  {component_id=2})
  nebula_app_register_component("login_btn",      "ButtonVisual")
nebula_app_end()

local reg312 = nebula_app_registry["Phase312TestApp"]
assert_eq("layout_results 已填充（Phase 3.11 兼容）",
  reg312.layout_results ~= nil, true)
assert_eq("layout_segments 已填充（Phase 3.12 新增）",
  reg312.layout_segments ~= nil, true)
assert_eq("layout_segments.segments 是 table",
  type(reg312.layout_segments.segments), "table")
assert_eq("layout_segments 至少有 1 个分段",
  #reg312.layout_segments.segments >= 1, true)

-- =============================================================================
-- 6. 生成代码包含 Phase 3.12 响应式更新代码
-- =============================================================================
print("\n--- 6. 生成代码包含 Phase 3.12 响应式更新代码 ---")

local gen312 = nebula_app_generate("Phase312TestApp")
assert_eq("生成代码是 string", type(gen312), "string")

-- 验证包含 Phase 3.12 注释
assert_contains("生成代码包含 Phase 3.12 注释",
  gen312, "Phase 3.12")

-- 验证包含 viewport_resized 检查
assert_contains("生成代码包含 viewport_resized 检查",
  gen312, "input.viewport_resized")

-- 验证包含 self.vw / self.vh 更新
assert_contains("生成代码包含 self.vw 更新",
  gen312, "self.vw = input.viewport_w")
assert_contains("生成代码包含 self.vh 更新",
  gen312, "self.vh = input.viewport_h")

-- 验证包含 update_viewport 调用
assert_contains("生成代码包含 update_viewport 调用",
  gen312, "update_viewport(self.renderer, input.viewport_w, input.viewport_h)")

-- 验证包含组件坐标更新（线性插值）
assert_contains("生成代码包含 card pos.x 插值",
  gen312, "self.card.visual.pos.x")
assert_contains("生成代码包含 card pos.y 插值",
  gen312, "self.card.visual.pos.y")

-- =============================================================================
-- 7. 生成代码结构验证
-- =============================================================================
print("\n--- 7. 生成代码结构验证 ---")

-- 验证 if-else 分支结构（多分段时应有 if/elseif/else）
-- 至少应有 if viewport_resized 块
assert_contains("生成代码包含 if viewport_resized 块",
  gen312, "if input.viewport_resized then")
assert_contains("生成代码包含 end -- viewport_resized 结束标记",
  gen312, "end  -- viewport_resized")

-- 验证 Phase 3.11 的 init 坐标注入仍然存在（向后兼容）
assert_contains("生成代码仍包含 Phase 3.11 init 坐标注入",
  gen312, "Phase 3.11")
assert_contains("生成代码 init 中包含 card pos 注入",
  gen312, "self.card.visual.pos")

-- =============================================================================
-- 8. 无 layout 时生成代码不含响应式更新代码（向后兼容）
-- =============================================================================
print("\n--- 8. 无 layout 时向后兼容 ---")

nebula_app_begin("NoLayout312App")
  nebula_app_register_component("btn", "ButtonVisual")
nebula_app_end()

local gen_no_layout = nebula_app_generate("NoLayout312App")
assert_eq("无 layout 时生成代码是 string", type(gen_no_layout), "string")
assert_not_contains("无 layout 时不含 Phase 3.12 注释",
  gen_no_layout, "Phase 3.12")
assert_not_contains("无 layout 时不含 viewport_resized 检查",
  gen_no_layout, "input.viewport_resized")

-- =============================================================================
-- 9. NebulaInputState 新字段存在性验证
-- =============================================================================
print("\n--- 9. NebulaInputState 新字段验证 ---")

local core_src = read_file(script_dir .. "/../src/nebula_core.nelua")
if core_src then
  assert_contains("nebula_core.nelua 包含 viewport_w 字段",
    core_src, "viewport_w:")
  assert_contains("nebula_core.nelua 包含 viewport_h 字段",
    core_src, "viewport_h:")
  assert_contains("nebula_core.nelua 包含 viewport_resized 字段",
    core_src, "viewport_resized:")
  assert_contains("nebula_core.nelua 包含 Phase 3.12 注释",
    core_src, "Phase 3.12")
else
  failed = failed + 1
  print("[FAIL] 无法读取 src/nebula_core.nelua")
end

-- =============================================================================
-- 10. glfw_bindings.nelua 包含 framebuffer resize 绑定
-- =============================================================================
print("\n--- 10. glfw_bindings.nelua framebuffer resize 绑定 ---")

local glfw_src = read_file(script_dir .. "/../src/glfw_bindings.nelua")
if glfw_src then
  assert_contains("glfw_bindings 包含 GLFWframebuffersizefun 类型",
    glfw_src, "GLFWframebuffersizefun")
  assert_contains("glfw_bindings 包含 glfwSetFramebufferSizeCallback",
    glfw_src, "glfwSetFramebufferSizeCallback")
  assert_contains("glfw_bindings 包含 glfwGetFramebufferSize",
    glfw_src, "glfwGetFramebufferSize")
  assert_contains("glfw_bindings 包含 Phase 3.12 注释",
    glfw_src, "Phase 3.12")
else
  failed = failed + 1
  print("[FAIL] 无法读取 src/glfw_bindings.nelua")
end

-- =============================================================================
-- 11. app.nelua 包含 resize 回调注册和视口状态收集
-- =============================================================================
print("\n--- 11. app.nelua resize 回调与视口状态 ---")

local app_src = read_file(script_dir .. "/../src/app.nelua")
if app_src then
  assert_contains("app.nelua 包含 _nebula_framebuffer_size_callback",
    app_src, "_nebula_framebuffer_size_callback")
  assert_contains("app.nelua 包含 glfwSetFramebufferSizeCallback 注册",
    app_src, "glfwSetFramebufferSizeCallback(window, _nebula_framebuffer_size_callback)")
  assert_contains("app.nelua 包含 _nebula_viewport_resized 全局变量",
    app_src, "_nebula_viewport_resized")
  assert_contains("app.nelua 包含 viewport_resized 赋值",
    app_src, "input.viewport_resized = _nebula_viewport_resized")
  assert_contains("app.nelua 包含 GLFW_RESIZABLE = GLFW_TRUE",
    app_src, "GLFW_RESIZABLE, GLFW_TRUE")
  assert_contains("app.nelua 包含 Phase 3.12 注释",
    app_src, "Phase 3.12")
else
  failed = failed + 1
  print("[FAIL] 无法读取 src/app.nelua")
end

-- =============================================================================
-- 12. app_factory.lua 版本标识
-- =============================================================================
print("\n--- 12. app_factory.lua 版本标识 ---")

assert_eq("app_factory 版本标识为 phase4.7-s3",
  factory_version, "nebula_app_factory_v0.9_phase4.7-s3")
assert_contains("layout_engine 版本标识包含 phase4.7-s3",
  layout_engine_version, "phase4.7-s3")

-- =============================================================================
-- 13. 行数收敛验证
-- =============================================================================
print("\n--- 13. 行数收敛验证 ---")

local le_lines = count_lines(script_dir .. "/../src/derive/layout_engine.lua")
local af_lines = count_lines(script_dir .. "/../src/derive/app_factory.lua")
local app_lines = count_lines(script_dir .. "/../src/app.nelua")

if le_lines then
  assert_le("layout_engine.lua 行数 <= 650", le_lines, 650)
  print(("  [INFO] layout_engine.lua: %d 行"):format(le_lines))
end
if af_lines then
  assert_le("app_factory.lua 行数 <= 1300", af_lines, 1300)
  print(("  [INFO] app_factory.lua: %d 行"):format(af_lines))
end
if app_lines then
  assert_le("app.nelua 行数 <= 545 (Phase 4.5-S3: nebula_frame_begin)", app_lines, 545)
  print(("  [INFO] app.nelua: %d 行"):format(app_lines))
end

-- =============================================================================
-- 汇总
-- =============================================================================
print(("\n=== Phase 3.12 回归测试结果：%d passed, %d failed ==="):format(passed, failed))
if failed > 0 then
  os.exit(1)
end
