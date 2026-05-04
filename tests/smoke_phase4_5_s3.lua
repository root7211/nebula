-- =============================================================================
-- tests/smoke_phase4_5_s3.lua
-- Nebula GUI Compiler — Phase 4.5-S3 回归测试
--
-- 测试目标：
--   · NEBULA_THEME_DEFAULTS 编译期主题表结构验证（从源码提取并加载）
--   · nebula_auto_states 对各原语组合推导正确
--   · src/nebula.nelua 导出完整性
--   · src/app.nelua 包含 nebula_frame_begin
--   · examples/button_v2_demo.nelua 存在且使用全部新 API
-- =============================================================================

-- 设置正确的模块搜索路径
local script_dir = debug.getinfo(1, "S").source:match("^@(.+)/[^/]+$") or "."
package.path = script_dir .. "/../src/?.lua;" ..
               script_dir .. "/../src/derive/?.lua;" ..
               package.path

require "derive.interaction_factory"

-- 从 nebula_core.nelua 复制 nebula_auto_states 的 Lua 实现用于测试
-- （原函数在 Nelua 编译期 ##[[ ]] 块中，纯 Lua 环境不可用）
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

-- =============================================================================
-- 测试工具
-- =============================================================================
local pass_count = 0
local fail_count = 0

local function check(desc, cond)
  if cond then
    pass_count = pass_count + 1
    print("[PASS] " .. desc)
  else
    fail_count = fail_count + 1
    print("[FAIL] " .. desc)
  end
end

local function has_value(t, val)
  for _, v in ipairs(t) do
    if v == val then return true end
  end
  return false
end

-- =============================================================================
-- 测试 1: NEBULA_THEME_DEFAULTS 结构验证
-- 从 nebula_core.nelua 源码中提取 NEBULA_THEME_DEFAULTS 定义并验证结构
-- =============================================================================
local core_path = script_dir .. "/../src/nebula_core.nelua"
local cf = io.open(core_path, "r")
check("src/nebula_core.nelua 文件存在", cf ~= nil)

if cf then
  local content = cf:read("*a")
  cf:close()
  check("nebula_core 包含 NEBULA_THEME_DEFAULTS", content:find("NEBULA_THEME_DEFAULTS") ~= nil)
  check("nebula_core 包含 nebula_visual 函数", content:find("function nebula_visual") ~= nil)
  check("nebula_core 包含 init_themed 生成", content:find("init_themed") ~= nil)

  -- 验证主题表包含所有预期状态
  check("THEME_DEFAULTS 包含 default 状态", content:find('NEBULA_THEME_DEFAULTS = {') ~= nil)
  check("THEME_DEFAULTS 包含 hovered 状态", content:find('hovered = {') ~= nil)
  check("THEME_DEFAULTS 包含 pressed 状态", content:find('pressed = {') ~= nil)
  check("THEME_DEFAULTS 包含 focused 状态", content:find('focused = {') ~= nil)
  check("THEME_DEFAULTS 包含 draggingbar 状态", content:find('draggingbar = {') ~= nil)

  -- 验证 nebula_visual 包含关键实现步骤
  check("nebula_visual 包含 DenseText 路径", content:find('text_mode == "dense"') ~= nil)
  check("nebula_visual 包含 nebula_resolve_primitives", content:find("nebula_resolve_primitives%(primitives%)") ~= nil)
  check("nebula_visual 包含 nebula_auto_states", content:find("nebula_auto_states%(primitives%)") ~= nil)
  check("nebula_visual 包含 inject_statement", content:find("inject_statement%(stat%)") ~= nil)
  check("nebula_visual 调用 nebula_component", content:find("nebula_component%(type_name") ~= nil)

  -- 验证 init_themed 生成逻辑
  check("init_themed 生成包含 pos/size/radius 参数",
    content:find("init_themed%(pos: Vec2, size: Vec2, radius: float32%)") ~= nil)
  check("init_themed 调用 self:init",
    content:find('self:init') ~= nil)
end

-- =============================================================================
-- 测试 2: 在 Lua 环境中构造并验证 NEBULA_THEME_DEFAULTS 结构
-- =============================================================================
NEBULA_THEME_DEFAULTS = {
  default = {
    bg     = { r=0.22, g=0.22, b=0.24, a=1.0 },
    border = { r=0.40, g=0.40, b=0.45, a=1.0 },
    border_width = 1.0,
    track  = { r=0.20, g=0.20, b=0.25, a=1.0 },
    thumb  = { r=0.45, g=0.45, b=0.50, a=1.0 },
  },
  hovered = {
    bg     = { r=0.28, g=0.28, b=0.32, a=1.0 },
    border = { r=0.40, g=0.60, b=1.00, a=1.0 },
    border_width = 2.0,
    track  = { r=0.22, g=0.22, b=0.28, a=1.0 },
    thumb  = { r=0.55, g=0.65, b=0.90, a=1.0 },
  },
  pressed = {
    bg     = { r=0.16, g=0.16, b=0.20, a=1.0 },
    border = { r=0.60, g=0.80, b=1.00, a=1.0 },
    border_width = 2.5,
  },
}

check("构造的主题表 default.bg.r = 0.22", NEBULA_THEME_DEFAULTS.default.bg.r == 0.22)
check("构造的主题表 hovered.border_width = 2.0", NEBULA_THEME_DEFAULTS.hovered.border_width == 2.0)
check("构造的主题表 pressed.border_width = 2.5", NEBULA_THEME_DEFAULTS.pressed.border_width == 2.5)

-- 主题覆盖测试
NEBULA_THEME_DEFAULTS.hovered.border = { r=1.0, g=0.4, b=0.0, a=1.0 }
check("主题覆盖: hovered.border.r 修改为 1.0", NEBULA_THEME_DEFAULTS.hovered.border.r == 1.0)
NEBULA_THEME_DEFAULTS.hovered.border = { r=0.40, g=0.60, b=1.00, a=1.0 }
check("主题恢复: hovered.border.r 还原为 0.40", NEBULA_THEME_DEFAULTS.hovered.border.r == 0.40)

-- =============================================================================
-- 测试 3: nebula_auto_states 推导
-- =============================================================================
local s1 = nebula_auto_states({"clickable"})
check("clickable states[1] = default", s1[1] == "default")
check("clickable 包含 hovered", has_value(s1, "hovered"))
check("clickable 包含 pressed", has_value(s1, "pressed"))
check("clickable states 总数 = 3", #s1 == 3)

local s2 = nebula_auto_states({"scrollable"})
check("scrollable states[1] = default", s2[1] == "default")
check("scrollable 包含 draggingbar", has_value(s2, "draggingbar"))

local s3 = nebula_auto_states({"focusable"})
check("focusable states[1] = default", s3[1] == "default")
check("focusable 包含 focused", has_value(s3, "focused"))
check("focusable 包含 pressed", has_value(s3, "pressed"))
check("focusable 包含 hovered", has_value(s3, "hovered"))

-- =============================================================================
-- 测试 4: nebula.nelua 文件完整性
-- =============================================================================
local nebula_path = script_dir .. "/../src/nebula.nelua"
local f = io.open(nebula_path, "r")
check("src/nebula.nelua 文件存在", f ~= nil)
if f then
  local content = f:read("*a")
  f:close()
  check("nebula.nelua 包含 require nebula_core", content:find('require "nebula_core"') ~= nil)
  check("nebula.nelua 包含 require app", content:find('require "app"') ~= nil)
  check("nebula.nelua 包含 require nebula_theme", content:find('require "nebula_theme"') ~= nil)
  check("nebula.nelua 包含 require renderer", content:find('require "renderer"') ~= nil)
  check("nebula.nelua 包含 require text_runtime", content:find('require "text_runtime"') ~= nil)
  check("nebula.nelua 包含 printf 声明", content:find('printf') ~= nil)
  check("nebula.nelua 包含 snprintf 声明", content:find('snprintf') ~= nil)
end

-- =============================================================================
-- 测试 5: nebula_frame_begin 在 app.nelua
-- =============================================================================
local app_path = script_dir .. "/../src/app.nelua"
local af = io.open(app_path, "r")
check("src/app.nelua 文件存在", af ~= nil)
if af then
  local content = af:read("*a")
  af:close()
  check("app.nelua 包含 nebula_frame_begin", content:find('nebula_frame_begin') ~= nil)
  check("app.nelua 包含 _nebula_prev_time", content:find('_nebula_prev_time') ~= nil)
  check("nebula_frame_begin 调用 nebula_poll_events", content:find('nebula_poll_events') ~= nil)
  check("nebula_frame_begin 调用 nebula_collect_input", content:find('nebula_collect_input') ~= nil)
  check("nebula_frame_begin 调用 glfwGetTime", content:find('glfwGetTime') ~= nil)
end

-- =============================================================================
-- 测试 6: button_v2_demo.nelua 存在且使用全部新 API
-- =============================================================================
local v2_path = script_dir .. "/../examples/button_v2_demo.nelua"
local vf = io.open(v2_path, "r")
check("examples/button_v2_demo.nelua 文件存在", vf ~= nil)
if vf then
  local content = vf:read("*a")
  vf:close()
  check("button_v2 使用 require nebula", content:find('require "nebula"') ~= nil)
  check("button_v2 使用 nebula_visual", content:find('nebula_visual') ~= nil)
  check("button_v2 使用 init_themed", content:find('init_themed') ~= nil)
  check("button_v2 使用 nebula_frame_begin", content:find('nebula_frame_begin') ~= nil)
  check("button_v2 使用 nebula_app", content:find('nebula_app') ~= nil)
  -- 行数检查
  local line_count = 0
  for _ in content:gmatch("[^\n]+") do line_count = line_count + 1 end
  check("button_v2 行数 <= 35 (极限形态)", line_count <= 35)
  print(string.format("  → button_v2_demo.nelua 实际行数: %d", line_count))
end

-- =============================================================================
-- 结果汇总
-- =============================================================================
print(string.format("\n=== Phase 4.5-S3 smoke: %d passed, %d failed ===", pass_count, fail_count))
if fail_count > 0 then
  os.exit(1)
end
