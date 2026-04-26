-- =============================================================================
-- tests/smoke_phase3_10.lua
-- Nebula GUI Compiler — Phase 3.10 回归测试
--
-- 测试目标：
--   · NEBULA_PRIMITIVES 统一注册表存在且包含 5 个原语
--   · nebula_resolve_primitives 正确解析依赖
--   · nebula_get_context_fields 正确收集字段
--   · nebula_get_post_process 正确收集后处理
--   · process_input 通过元数据驱动注入 toggleable 后处理（无 Monkey-patch）
--   · 旧的 Monkey-patch 代码已彻底删除
-- =============================================================================

-- 设置正确的模块搜索路径
local script_dir = debug.getinfo(1, "S").source:match("^@(.+)/[^/]+$") or "."
package.path = script_dir .. "/../src/?.lua;" ..
               script_dir .. "/../src/derive/?.lua;" ..
               package.path

local interaction_ver = require "derive.interaction_factory"

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

-- =============================================================================
-- 测试 1: 版本号
-- =============================================================================
check("interaction_factory 版本号 v0.7_phase3.10",
  interaction_ver == "nebula_interaction_factory_v0.7_phase3.10")

-- =============================================================================
-- 测试 2: NEBULA_PRIMITIVES 注册表
-- =============================================================================
check("NEBULA_PRIMITIVES 存在", type(NEBULA_PRIMITIVES) == "table")
check("包含 hoverable", NEBULA_PRIMITIVES["hoverable"] ~= nil)
check("包含 clickable", NEBULA_PRIMITIVES["clickable"] ~= nil)
check("包含 focusable", NEBULA_PRIMITIVES["focusable"] ~= nil)
check("包含 toggleable", NEBULA_PRIMITIVES["toggleable"] ~= nil)
check("包含 editable", NEBULA_PRIMITIVES["editable"] ~= nil)

-- =============================================================================
-- 测试 3: 依赖解析
-- =============================================================================
local r1 = nebula_resolve_primitives({"clickable"})
check("clickable 自动注入 hoverable", r1[1] == "hoverable" and r1[2] == "clickable")

local r2 = nebula_resolve_primitives({"toggleable"})
check("toggleable 自动注入 hoverable+clickable",
  r2[1] == "hoverable" and r2[2] == "clickable" and r2[3] == "toggleable")

local r3 = nebula_resolve_primitives({"editable"})
check("editable 自动注入完整依赖链",
  r3[1] == "hoverable" and r3[2] == "clickable" and r3[3] == "focusable" and r3[4] == "editable")

local r4 = nebula_resolve_primitives({"hoverable", "clickable"})
check("显式声明不重复", #r4 == 2)

-- =============================================================================
-- 测试 4: Context 字段收集
-- =============================================================================
local f1 = nebula_get_context_fields({"hoverable", "clickable"})
check("hoverable+clickable 生成 2 个字段", #f1 == 2)
check("第一个字段是 hover", f1[1].name == "hover" and f1[1].type == "HoverableState")
check("第二个字段是 click", f1[2].name == "click" and f1[2].type == "ClickableState")

local f2 = nebula_get_context_fields({"editable"})
check("editable 解析后生成 >= 4 个字段", #f2 >= 4)

-- =============================================================================
-- 测试 5: Post process 收集
-- =============================================================================
local p1 = nebula_get_post_process({"hoverable", "clickable", "toggleable"})
check("toggleable 有 1 个 post_process", #p1 == 1)
check("post_process 是 process_toggle 调用", p1[1].method_call == "self:process_toggle(input)")

local p2 = nebula_get_post_process({"hoverable", "clickable"})
check("无 toggleable 时无 post_process", #p2 == 0)

-- =============================================================================
-- 测试 6: process_input 元数据驱动注入
-- =============================================================================
local src = nebula_gen_process_input({
  base = "Checkbox", state_type = "CheckboxState",
  primitives = {"hoverable", "clickable", "toggleable"},
  states = {"default", "hovered", "pressed"},
})
check("process_input 包含 process_toggle 调用",
  src:find("self:process_toggle(input)", 1, true) ~= nil)

local src2 = nebula_gen_process_input({
  base = "Button", state_type = "ButtonState",
  primitives = {"hoverable", "clickable"},
  states = {"default", "hovered", "pressed"},
})
check("无 toggleable 时不含 process_toggle",
  not src2:find("process_toggle", 1, true))

-- =============================================================================
-- 测试 7: Monkey-patch 已删除
-- =============================================================================
local factory_file = io.open(script_dir .. "/../src/derive/interaction_factory.lua")
local factory_src = factory_file:read("*a")
factory_file:close()
check("无 _orig_gen_process_input 残留",
  not factory_src:find("_orig_gen_process_input", 1, true))
check("无 source:sub Monkey-patch 残留",
  not factory_src:find("source:sub", 1, true))

-- =============================================================================
-- 结果汇总
-- =============================================================================
print(("=== Phase 3.10 回归测试结果：%d 通过，%d 失败 ==="):format(pass_count, fail_count))
if fail_count > 0 then os.exit(1) end
