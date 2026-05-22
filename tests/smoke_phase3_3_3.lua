-- =============================================================================
-- tests/smoke_phase3_3_3.lua
-- Nebula GUI Compiler — Phase 3.3.3（Phase 3.7 更新）
--
-- Phase 3.7 变更说明：
--   · nebula_compose_instanced_shader 已在 Phase 3.7 中删除（死代码清理）
--   · nebula_compose_shader 已在 Phase 3.7 中删除（主着色器是红色占位符，违反公理 C）
--   · 本测试已更新为验证 Phase 3.7 的新 API：
--     - nebula_compose_shader_instanced（标准 Visual 默认路径）
--     - nebula_compose_shadow_shaders（阴影路径）
--     - nebula_compose_text_shader（文本 SDF 路径）
-- =============================================================================

local script_dir = debug.getinfo(1, "S").source:match("^@(.+)/[^/]+$") or "."
package.path = script_dir .. "/../src/?.lua;" ..
               script_dir .. "/../src/derive/?.lua;" ..
               package.path

local compose_ver = require "derive.shader_compose"

local pass = 0
local fail = 0

local function check(name, cond, msg)
  if cond then
    pass = pass + 1
    print(("[PASS] %s"):format(name))
  else
    fail = fail + 1
    print(("[FAIL] %s — %s"):format(name, msg or "assertion failed"))
  end
end

-- ===== 模块版本检查（Phase 3.7）=====
check("module_version_phase4_2_2",
  compose_ver == "nebula_shader_compose_v1.0_phase5.3",
  "模块版本号断言失败，当前: " .. tostring(compose_ver))

-- ===== Phase 3.7: 已删除函数不应存在 =====
check("nebula_compose_instanced_shader_deleted",
  nebula_compose_instanced_shader == nil,
  "nebula_compose_instanced_shader 应已在 Phase 3.7 中删除")

check("nebula_compose_shader_deleted",
  nebula_compose_shader == nil,
  "nebula_compose_shader 应已在 Phase 3.7 中删除（主着色器是红色占位符）")

-- ===== Phase 3.7: 三个公开函数均存在 =====
check("nebula_compose_shader_instanced_exists",
  type(nebula_compose_shader_instanced) == "function",
  "nebula_compose_shader_instanced 函数不存在")

check("nebula_compose_text_shader_intact",
  type(nebula_compose_text_shader) == "function",
  "nebula_compose_text_shader 函数不存在")

check("nebula_compose_shadow_shaders_exists",
  type(nebula_compose_shadow_shaders) == "function",
  "nebula_compose_shadow_shaders 函数不存在")

-- ===== nebula_compose_shader_instanced 基础功能（替代原 nebula_compose_instanced_shader）=====
local mock_struct = [[
struct TestUniforms {
  pos:      vec2<f32>,
  size:     vec2<f32>,
  bg_color: vec4<f32>,
  radius:   f32,
  _pad0:    f32,
  viewport: vec2<f32>,
}]]

local result = nebula_compose_shader_instanced({
  wgsl_struct = mock_struct,
  struct_name = "TestUniforms",
  has_radius  = true,
  has_border  = true,
})

check("shader_instanced_returns_table",
  type(result) == "table",
  "nebula_compose_shader_instanced 应返回 table")

check("shader_instanced_has_source",
  type(result.source) == "string" and #result.source > 100,
  "source 字段不存在或为空")

check("shader_instanced_has_storage_binding",
  result.source:find("var<storage, read>", 1, true) ~= nil,
  "WGSL 应包含 Storage Buffer 绑定")

check("shader_instanced_has_instance_index",
  result.source:find("@builtin(instance_index)", 1, true) ~= nil,
  "WGSL 应包含 @builtin(instance_index)")

check("shader_instanced_has_sdf_rounded_rect",
  result.source:find("sdf_rounded_rect", 1, true) ~= nil,
  "WGSL 应包含 sdf_rounded_rect（has_radius=true）")

check("shader_instanced_has_border_logic",
  result.source:find("border_width", 1, true) ~= nil,
  "WGSL 应包含 border_width（has_border=true）")

check("shader_instanced_no_red_placeholder",
  result.source:find("vec4<f32>(1.0, 0.0, 0.0, 1.0)", 1, true) == nil,
  "WGSL 不应包含红色占位符（违反公理 C）")

check("shader_instanced_flag_true",
  result.instanced == true,
  "instanced 标志应为 true")

-- ===== 汇总 =====
print(("\n=== smoke_phase3_3_3（Phase 3.7 更新）：%d 通过，%d 失败 ==="):format(pass, fail))
if fail > 0 then os.exit(1) end
