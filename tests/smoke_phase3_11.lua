-- =============================================================================
-- tests/smoke_phase3_11.lua — Nebula Phase 3.11 专项回归测试
--
-- 覆盖范围：
--   1. nebula_app_set_root_layout API 可用性
--   2. nebula_app_register_component layout 字段支持
--   3. nebula_app_end 自动布局解算（layout_results 填充）
--   4. gen_app_init 注入编译期坐标（消除手写魔法数字）
--   5. nebula_init / nebula_should_close / nebula_shutdown 存在性验证
--   6. form_demo.nelua Phase 3.11 重构验证
--   7. layout_demo.nelua Phase 3.11 重构验证
--   8. app_factory.lua 版本标识
--   9. 行数收敛验证
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

local function assert_gt(name, got, limit)
  if got > limit then
    passed = passed + 1
    print(("[PASS] %s (%d > %d)"):format(name, got, limit))
  else
    failed = failed + 1
    print(("[FAIL] %s (%d <= %d)"):format(name, got, limit))
  end
end

local function assert_near(name, got, expected, tolerance)
  tolerance = tolerance or 1.0
  if math.abs(got - expected) <= tolerance then
    passed = passed + 1
    print(("[PASS] %s (%.1f ≈ %.1f ±%.1f)"):format(name, got, expected, tolerance))
  else
    failed = failed + 1
    print(("[FAIL] %s (%.1f ≠ %.1f ±%.1f)"):format(name, got, expected, tolerance))
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
-- 加载依赖模块（layout_engine 必须先于 app_factory 加载）
-- =============================================================================
-- 设置 package.path 以支持 require "derive.layout_engine"
package.path = script_dir .. "/../src/?.lua;" .. script_dir .. "/../src/?/init.lua;" .. package.path

-- 先加载 layout_engine（app_factory 内部通过 require 使用其全局函数）
local layout_engine_path = script_dir .. "/../src/derive/layout_engine.lua"
local layout_engine_version = dofile(layout_engine_path)

local factory_path = script_dir .. "/../src/derive/app_factory.lua"
local factory_version = dofile(factory_path)

-- =============================================================================
-- 1. nebula_app_set_root_layout API 可用性
-- =============================================================================
print("\n--- 1. nebula_app_set_root_layout API ---")

assert_eq("nebula_app_set_root_layout 是全局函数",
  type(nebula_app_set_root_layout), "function")
assert_eq("nebula_app_begin 是全局函数",
  type(nebula_app_begin), "function")
assert_eq("nebula_app_end 是全局函数",
  type(nebula_app_end), "function")
assert_eq("nebula_app_register_component 是全局函数",
  type(nebula_app_register_component), "function")

-- =============================================================================
-- 2. 布局解算：nebula_app_set_root_layout + layout 字段
-- =============================================================================
print("\n--- 2. 布局解算：layout 字段 + 自动坐标注入 ---")

nebula_app_set_root_layout("LayoutTestApp", {
  direction = "column",
  justify   = "center",
  align     = "center",
  width     = 800,
  height    = 600,
})

nebula_app_begin("LayoutTestApp")
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

-- 验证 layout_results 已被填充
local reg = nebula_app_registry["LayoutTestApp"]
assert_eq("layout_results 不为 nil", reg.layout_results ~= nil, true)

-- 验证卡片居中坐标（800x600 视口，卡片 360x440，应居中）
local card_r = reg.layout_results["card"]
assert_eq("card 布局结果存在", card_r ~= nil, true)
if card_r then
  assert_near("card.x 居中 (800-360)/2 = 220", card_r.x, 220, 1)
  assert_near("card.y 居中 (600-440)/2 = 80",  card_r.y, 80,  1)
  assert_near("card.w = 360", card_r.w, 360, 1)
  assert_near("card.h = 440", card_r.h, 440, 1)
end

-- 验证子组件坐标（email_input 在卡片内部，padding=32，从 card.y+32 开始）
local email_r = reg.layout_results["email_input"]
assert_eq("email_input 布局结果存在", email_r ~= nil, true)
if email_r and card_r then
  -- email_input.x = card.x + (card.w - email.w) / 2 = 220 + (360-296)/2 = 220+32 = 252
  assert_near("email_input.x = card.x + (360-296)/2 = 252", email_r.x, 252, 1)
  -- email_input.y = card.y + padding = 80 + 32 = 112
  assert_near("email_input.y = card.y + padding = 112", email_r.y, 112, 1)
  assert_near("email_input.w = 296", email_r.w, 296, 1)
  assert_near("email_input.h = 44",  email_r.h, 44,  1)
end

-- 验证 password_input（在 email_input 下方，gap=16）
local pass_r = reg.layout_results["password_input"]
assert_eq("password_input 布局结果存在", pass_r ~= nil, true)
if pass_r and email_r then
  assert_near("password_input.y = email.y + email.h + gap = 172", pass_r.y, 172, 1)
end

-- =============================================================================
-- 3. 生成代码包含编译期坐标注入
-- =============================================================================
print("\n--- 3. 生成代码包含编译期坐标注入 ---")

local gen = nebula_app_generate("LayoutTestApp")
assert_eq("生成代码是 string", type(gen), "string")

-- 验证 init 中包含 Phase 3.11 注释
assert_contains("生成代码包含 Phase 3.11 注释",
  gen, "Phase 3.11")

-- 验证 init 中包含 card 的坐标注入
assert_contains("生成代码包含 card pos 注入",
  gen, "self.card.visual.pos")
assert_contains("生成代码包含 card size 注入",
  gen, "self.card.visual.size")

-- 验证 init 中包含 email_input 的坐标注入
assert_contains("生成代码包含 email_input pos 注入",
  gen, "self.email_input.visual.pos")
assert_contains("生成代码包含 email_input size 注入",
  gen, "self.email_input.visual.size")

-- 验证坐标值正确（card 居中 x=220）
assert_contains("生成代码包含 card.x = 220.0",
  gen, "x = 220.0")
assert_contains("生成代码包含 card.y = 80.0",
  gen, "y = 80.0")

-- 验证不含 get_layout_pos 辅助函数调用（旧 API 已消除）
assert_not_contains("生成代码不含 get_layout_pos 调用",
  gen, "get_layout_pos")
assert_not_contains("生成代码不含 get_layout_size 调用",
  gen, "get_layout_size")

-- =============================================================================
-- 4. 无 layout 字段时不生成坐标注入（向后兼容）
-- =============================================================================
print("\n--- 4. 无 layout 字段时向后兼容 ---")

nebula_app_begin("NoLayoutApp")
  nebula_app_register_component("btn", "ButtonVisual")
nebula_app_end()

local gen_no_layout = nebula_app_generate("NoLayoutApp")
assert_eq("无 layout 时生成代码是 string", type(gen_no_layout), "string")
assert_not_contains("无 layout 时不含坐标注入",
  gen_no_layout, "Phase 3.11")
assert_not_contains("无 layout 时不含 visual.pos 注入",
  gen_no_layout, "self.btn.visual.pos")

-- =============================================================================
-- 5. form_demo.nelua Phase 3.11 重构验证
-- =============================================================================
print("\n--- 5. form_demo.nelua Phase 3.11 重构 ---")
local form_src = read_file(script_dir .. "/../examples/form_demo.nelua")
if form_src then
  -- Phase 3.11 标识
  assert_contains("form_demo 包含 Phase 3.11 注释",
    form_src, "Phase 3.11")
  -- 使用新 API
  assert_contains("form_demo 使用 nebula_app_set_root_layout",
    form_src, "nebula_app_set_root_layout")
  assert_contains("form_demo 使用 layout 字段",
    form_src, "layout =")
  assert_contains("form_demo 使用 nebula_init",
    form_src, "nebula_init(")
  assert_contains("form_demo 使用 nebula_should_close",
    form_src, "nebula_should_close()")
  assert_contains("form_demo 使用 nebula_shutdown",
    form_src, "nebula_shutdown(")
  -- 消除旧的手写魔法数字（不应出现 pos = Vec2{ x = 220 这样的手写坐标）
  assert_not_contains("form_demo 不含手写 card pos 魔法数字",
    form_src, "pos    = Vec2{ x = 220.0, y = 80.0 }")
  assert_not_contains("form_demo 不含手写 email_input pos 魔法数字",
    form_src, "pos    = Vec2{ x = 252.0, y = 176.0 }")
  -- 消除旧的 GLFW 样板
  assert_not_contains("form_demo 不含 glfwInit 直接调用",
    form_src, "if glfwInit() == 0 then")
  assert_not_contains("form_demo 不含 glfwCreateWindow 直接调用",
    form_src, "local window = glfwCreateWindow(")
  assert_not_contains("form_demo 不含手动 wgpuSurfaceRelease",
    form_src, "wgpuSurfaceRelease(")
  -- 保留 Phase 3.9 文本组件
  assert_contains("form_demo 保留 nebula_app_register_text",
    form_src, "nebula_app_register_text")
  assert_contains("form_demo 保留 nebula_frame_render",
    form_src, "nebula_frame_render(")
  assert_contains("form_demo 保留 Enter 键业务逻辑",
    form_src, "NebulaKey.Enter")
else
  failed = failed + 1
  print("[FAIL] 无法读取 examples/form_demo.nelua")
end

-- =============================================================================
-- 6. layout_demo.nelua Phase 3.11 重构验证
-- =============================================================================
print("\n--- 6. layout_demo.nelua Phase 3.11 重构 ---")
local layout_src = read_file(script_dir .. "/../examples/layout_demo.nelua")
if layout_src then
  -- Phase 3.11 标识
  assert_contains("layout_demo 包含 Phase 3.11 注释",
    layout_src, "Phase 3.11")
  -- 使用新 API
  assert_contains("layout_demo 使用 nebula_app_set_root_layout",
    layout_src, "nebula_app_set_root_layout")
  assert_contains("layout_demo 使用 nebula_init",
    layout_src, "nebula_init(")
  assert_contains("layout_demo 使用 nebula_should_close",
    layout_src, "nebula_should_close()")
  -- 消除旧的独立布局树声明
  assert_not_contains("layout_demo 不含独立 nebula_layout_solve 调用",
    layout_src, "nebula_layout_solve(root,")
  assert_not_contains("layout_demo 不含 get_layout_pos 辅助函数",
    layout_src, "function get_layout_pos(")
  assert_not_contains("layout_demo 不含 get_layout_size 辅助函数",
    layout_src, "function get_layout_size(")
  -- 消除旧的手写 pos/size 注入
  assert_not_contains("layout_demo 不含 #[get_layout_pos 注入",
    layout_src, "#[get_layout_pos(")
  assert_not_contains("layout_demo 不含 #[get_layout_size 注入",
    layout_src, "#[get_layout_size(")
  -- 消除旧的 GLFW 样板
  assert_not_contains("layout_demo 不含 glfwInit 直接调用",
    layout_src, "if glfwInit() == 0 then")
  assert_not_contains("layout_demo 不含手动 wgpuSurfaceRelease",
    layout_src, "wgpuSurfaceRelease(")
else
  failed = failed + 1
  print("[FAIL] 无法读取 examples/layout_demo.nelua")
end

-- =============================================================================
-- 7. app.nelua 便利性 API 存在性验证
-- =============================================================================
print("\n--- 7. app.nelua 便利性 API 存在性 ---")
local app_src = read_file(script_dir .. "/../src/app.nelua")
if app_src then
  assert_contains("app.nelua 包含 nebula_init 声明",
    app_src, "global function nebula_init(")
  assert_contains("app.nelua 包含 nebula_should_close 声明",
    app_src, "global function nebula_should_close()")
  assert_contains("app.nelua 包含 nebula_shutdown 声明",
    app_src, "global function nebula_shutdown(")
  assert_contains("app.nelua 包含 nebula_poll_events 声明",
    app_src, "global function nebula_poll_events()")
  assert_contains("app.nelua 包含 _nebula_window 全局",
    app_src, "global _nebula_window: GLFWwindow")
  assert_contains("app.nelua 包含 Phase 3.11 注释",
    app_src, "Phase 3.11")
else
  failed = failed + 1
  print("[FAIL] 无法读取 src/app.nelua")
end

-- =============================================================================
-- 8. app_factory.lua 版本标识
-- =============================================================================
print("\n--- 8. app_factory.lua 版本标识 ---")
-- ★ Phase 3.12 升级：版本号已更新为 phase3.12
assert_contains("版本标识包含 nebula_app_factory 前缀",
  factory_version, "nebula_app_factory")

-- =============================================================================
-- 9. 行数收敛验证
-- =============================================================================
print("\n--- 9. 行数收敛验证 ---")
local factory_lines = count_lines(script_dir .. "/../src/derive/app_factory.lua")
if factory_lines then
  assert_le("app_factory.lua <= 1300 行（Phase 4.7-S3 新增 DenseText 编排）", factory_lines, 1300)
end

local form_lines = count_lines(script_dir .. "/../examples/form_demo.nelua")
if form_lines then
  assert_le("form_demo.nelua <= 350 行（Phase 3.11 精简后）", form_lines, 350)
end

local layout_lines = count_lines(script_dir .. "/../examples/layout_demo.nelua")
if layout_lines then
  assert_le("layout_demo.nelua <= 350 行（Phase 3.11 精简后）", layout_lines, 350)
end

-- =============================================================================
-- 汇总
-- =============================================================================
print(("\n=== Phase 3.11 冒烟测试完成：%d 通过 / %d 失败 ==="):format(passed, failed))
if failed > 0 then
  os.exit(1)
end
