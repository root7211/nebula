-- =============================================================================
-- tests/smoke_phase3_5_1.lua
-- Nebula GUI Compiler — Phase 3.5.1 回归测试（Phase 3.7 更新）
--
-- 验收目标：
--   1. shader_compose.lua 版本号更新为 v0.6_phase3.7
--   2. pipeline_factory.lua 版本号更新为 v0.7_phase3.7
--   3. nebula_compose_shader_instanced 函数存在且返回正确的结构
--   4. nebula_gen_pipeline_source 的 standard_instanced 路径生成正确的代码
--   5. Phase 3.7: gen_pipeline_simple 和 gen_pipeline_instanced 路径已删除
-- =============================================================================

local passed = 0
local failed = 0

local function assert_eq(label, actual, expected)
  if actual == expected then
    passed = passed + 1
    print(("[PASS] %s"):format(label))
  else
    failed = failed + 1
    print(("[FAIL] %s\n       expected: %s\n       actual:   %s"):format(
      label, tostring(expected), tostring(actual)))
  end
end

local function assert_contains(label, str, pattern)
  if type(str) == "string" and str:find(pattern, 1, true) then
    passed = passed + 1
    print(("[PASS] %s"):format(label))
  else
    failed = failed + 1
    print(("[FAIL] %s\n       pattern '%s' not found in:\n%s"):format(
      label, pattern, tostring(str):sub(1, 200)))
  end
end

local function assert_not_contains(label, str, pattern)
  if type(str) == "string" and not str:find(pattern, 1, true) then
    passed = passed + 1
    print(("[PASS] %s"):format(label))
  else
    failed = failed + 1
    print(("[FAIL] %s\n       pattern '%s' should NOT be found"):format(label, pattern))
  end
end

local function assert_error(label, fn)
  local ok, err = pcall(fn)
  if not ok then
    passed = passed + 1
    print(("[PASS] %s (error: %s)"):format(label, tostring(err):sub(1, 80)))
  else
    failed = failed + 1
    print(("[FAIL] %s — expected error but none was raised"):format(label))
  end
end

-- =============================================================================
-- 加载模块
-- =============================================================================
local script_dir = debug.getinfo(1, "S").source:match("^@(.+)/[^/]+$") or "."
package.path = script_dir .. "/../src/?.lua;" ..
               script_dir .. "/../src/derive/?.lua;" ..
               package.path

local shader_ver = require "derive.shader_compose"
local factory_ver = require "derive.pipeline_factory"

-- =============================================================================
-- 1. 版本号验证（Phase 3.7 更新）
-- =============================================================================
assert_eq("shader_compose 版本号", shader_ver, "nebula_shader_compose_v0.6_phase3.7")
assert_eq("pipeline_factory 版本号", factory_ver, "nebula_pipeline_factory_v0.7_phase3.7")

-- =============================================================================
-- 2. nebula_compose_shader_instanced 基础功能
-- =============================================================================
local mock_wgsl_struct = [[
struct ButtonUniforms {
  pos:          vec2<f32>,
  size:         vec2<f32>,
  bg_color:     vec4<f32>,
  border_color: vec4<f32>,
  border_width: f32,
  radius:       f32,
  viewport:     vec2<f32>,
}]]

local result = nebula_compose_shader_instanced({
  wgsl_struct  = mock_wgsl_struct,
  struct_name  = "ButtonUniforms",
  has_radius   = true,
  has_border   = true,
})

assert_eq("nebula_compose_shader_instanced 返回 table", type(result), "table")
assert_eq("instanced 标志", result.instanced, true)
assert_eq("standard_visual 标志", result.standard_visual, true)
assert_eq("required_passes 包含 main", result.required_passes[1], "main")

-- 检查生成的 WGSL 包含关键内容
assert_contains("WGSL 包含 ButtonUniforms struct", result.source, "struct ButtonUniforms")
assert_contains("WGSL 包含 NebulaViewport", result.source, "struct NebulaViewport")
assert_contains("WGSL 包含 binding 0 uniform", result.source, "@group(0) @binding(0) var<uniform>")
assert_contains("WGSL 包含 binding 1 storage", result.source, "@group(0) @binding(1) var<storage, read>")
assert_contains("WGSL 包含 array<ButtonUniforms>", result.source, "array<ButtonUniforms>")
assert_contains("WGSL 包含 @builtin(instance_index)", result.source, "@builtin(instance_index)")
assert_contains("WGSL 包含 @builtin(vertex_index)", result.source, "@builtin(vertex_index)")
assert_contains("WGSL 包含 vs_main", result.source, "fn vs_main")
assert_contains("WGSL 包含 fs_main", result.source, "fn fs_main")
assert_contains("WGSL 包含 sdf_rounded_rect（has_radius=true）", result.source, "sdf_rounded_rect")
assert_contains("WGSL 包含 border_width（has_border=true）", result.source, "border_width")
assert_contains("WGSL 包含 6 顶点矩形", result.source, "vec2<f32>(1.0, 1.0)")

-- features 检查
local has_instanced_feat = false
local has_standard_visual_feat = false
local has_radius_feat = false
for _, f in ipairs(result.features) do
  if f == "instanced" then has_instanced_feat = true end
  if f == "standard_visual" then has_standard_visual_feat = true end
  if f == "radius" then has_radius_feat = true end
end
assert_eq("features 包含 instanced", has_instanced_feat, true)
assert_eq("features 包含 standard_visual", has_standard_visual_feat, true)
assert_eq("features 包含 radius（has_radius=true）", has_radius_feat, true)

-- 无 radius 时不应包含 sdf_rounded_rect
local result_no_radius = nebula_compose_shader_instanced({
  wgsl_struct = mock_wgsl_struct,
  struct_name = "ButtonUniforms",
  has_radius  = false,
  has_border  = false,
})
assert_not_contains("无 radius 时不包含 sdf_rounded_rect", result_no_radius.source, "sdf_rounded_rect")
assert_contains("无 radius 时包含 sdf_rect", result_no_radius.source, "fn sdf_rect")

-- =============================================================================
-- 3. nebula_gen_pipeline_source 的 standard_instanced 路径
-- =============================================================================
local pipe_code = nebula_gen_pipeline_source({
  base             = "Button",
  uniforms_record  = "ButtonUniforms",
  wgsl_source      = result.source,
  standard_instanced = true,
  max_instances    = 64,
})

assert_eq("standard_instanced 生成 string", type(pipe_code), "string")
assert_contains("生成 ButtonPipeline record", pipe_code, "global ButtonPipeline = @record{")
assert_contains("包含 storage_buf 字段", pipe_code, "storage_buf:")
assert_contains("包含 storage_size 字段", pipe_code, "storage_size:")
assert_contains("包含 max_instances 字段", pipe_code, "max_instances:")
assert_contains("init 方法接受 max_inst 参数", pipe_code, "function ButtonPipeline:init(renderer: *NebulaRenderer, max_inst: uint32)")
assert_contains("update_viewport 方法存在", pipe_code, "function ButtonPipeline:update_viewport(")
assert_contains("upload 方法存在", pipe_code, "function ButtonPipeline:upload(renderer: *NebulaRenderer, data: pointer, count: uint32)")
assert_contains("draw_instanced 方法存在", pipe_code, "function ButtonPipeline:draw_instanced(pass: WGPURenderPassEncoder, count: uint32)")
assert_contains("draw_single 方法存在", pipe_code, "function ButtonPipeline:draw_single(")
assert_contains("使用 Storage Buffer（ReadOnlyStorage）", pipe_code, "WGPUBufferBindingType_ReadOnlyStorage")
assert_contains("使用 max_instances=64", pipe_code, "max=64")
assert_contains("使用 ButtonUniforms 计算 storage_size", pipe_code, "#ButtonUniforms")
-- draw_instanced 应使用 6 顶点（两个三角形）
assert_contains("draw_instanced 使用 6 顶点", pipe_code, "wgpuRenderPassEncoderDraw(pass, 6, count, 0, 0)")

-- =============================================================================
-- 4. Phase 3.7: gen_pipeline_simple 路径已删除，应触发 error
-- =============================================================================
assert_error("simple 路径已删除（standard_instanced=false 且无 textured/has_shadow）", function()
  nebula_gen_pipeline_source({
    base             = "Card",
    uniforms_record  = "CardUniforms",
    wgsl_source      = "// placeholder",
    standard_instanced = false,
  })
end)

-- =============================================================================
-- 5. Phase 3.7: gen_pipeline_instanced 路径已删除，应触发 error
-- =============================================================================
assert_error("instanced 路径已删除（spec.instanced=true 不再被识别）", function()
  nebula_gen_pipeline_source({
    base             = "ListItem",
    uniforms_record  = "ListItemUniforms",
    wgsl_source      = "// placeholder",
    instanced        = true,
    instance_record  = "ListItemInstanceData",
    max_instances    = 10000,
  })
end)

-- =============================================================================
-- 6. Phase 3.7: nebula_compose_shadow_shaders 函数存在且返回正确结构
-- =============================================================================
local shadow_result = nebula_compose_shadow_shaders({
  wgsl_struct  = mock_wgsl_struct,
  struct_name  = "ButtonUniforms",
  has_radius   = true,
})
assert_eq("nebula_compose_shadow_shaders 返回 table", type(shadow_result), "table")
assert_eq("shadow_mask_source 是 string", type(shadow_result.shadow_mask_source), "string")
assert_eq("blur_h_source 是 string", type(shadow_result.blur_h_source), "string")
assert_eq("blur_v_source 是 string", type(shadow_result.blur_v_source), "string")
assert_eq("composite_source 是 string", type(shadow_result.composite_source), "string")
assert_contains("shadow_mask_source 包含 SDF", shadow_result.shadow_mask_source, "sdf_rounded_rect")
assert_contains("blur_h_source 包含高斯权重", shadow_result.blur_h_source, "0.227027")
assert_contains("blur_v_source 包含垂直方向", shadow_result.blur_v_source, "1.0 / tex_size.y")

-- Phase 3.7: nebula_compose_shader 已删除，不应存在
assert_eq("nebula_compose_shader 已删除", nebula_compose_shader, nil)
-- Phase 3.7: nebula_compose_instanced_shader 已删除，不应存在
assert_eq("nebula_compose_instanced_shader 已删除", nebula_compose_instanced_shader, nil)

-- =============================================================================
-- 汇总
-- =============================================================================
print(("\n=== Phase 3.5.1 / Phase 3.7 回归测试结果：%d 通过，%d 失败 ==="):format(passed, failed))
if failed > 0 then
  os.exit(1)
end
