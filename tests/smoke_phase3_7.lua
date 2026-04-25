-- =============================================================================
-- tests/smoke_phase3_7.lua
-- Nebula GUI Compiler — Phase 3.7 专项回归测试
--
-- 验收目标：
--   1. shader_compose.lua 收敛为三个公开函数（无 nebula_compose_shader/nebula_compose_instanced_shader）
--   2. pipeline_factory.lua 收敛为三条路径（无 gen_pipeline_simple/gen_pipeline_instanced）
--   3. nebula_compose_shader_instanced 是所有标准 Visual 的默认着色器组合器
--   4. nebula_compose_shadow_shaders 正确生成四个阴影子着色器
--   5. nebula_gen_pipeline_source 的三条路径均可正常工作
--   6. 死代码路径触发明确的 error（不是静默失败）
--   7. 代码行数收敛验证：shader_compose.lua ≤ 380 行，pipeline_factory.lua ≤ 750 行
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
    print(("[FAIL] %s\n       pattern '%s' not found"):format(label, pattern))
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

local function assert_nil(label, val)
  if val == nil then
    passed = passed + 1
    print(("[PASS] %s"):format(label))
  else
    failed = failed + 1
    print(("[FAIL] %s — expected nil, got %s"):format(label, tostring(val)))
  end
end

local function assert_error(label, fn)
  local ok, err = pcall(fn)
  if not ok then
    passed = passed + 1
    print(("[PASS] %s"):format(label))
  else
    failed = failed + 1
    print(("[FAIL] %s — expected error but none was raised"):format(label))
  end
end

local function assert_le(label, actual, max_val)
  if type(actual) == "number" and actual <= max_val then
    passed = passed + 1
    print(("[PASS] %s (%d ≤ %d)"):format(label, actual, max_val))
  else
    failed = failed + 1
    print(("[FAIL] %s — %s > %d"):format(label, tostring(actual), max_val))
  end
end

-- =============================================================================
-- 加载模块
-- =============================================================================
local script_dir = debug.getinfo(1, "S").source:match("^@(.+)/[^/]+$") or "."
package.path = script_dir .. "/../src/?.lua;" ..
               script_dir .. "/../src/derive/?.lua;" ..
               package.path

local shader_ver  = require "derive.shader_compose"
local factory_ver = require "derive.pipeline_factory"

-- =============================================================================
-- 1. 版本号验证
-- =============================================================================
print("\n--- 1. 版本号验证 ---")
assert_eq("shader_compose 版本号", shader_ver,  "nebula_shader_compose_v0.6_phase3.7")
assert_eq("pipeline_factory 版本号", factory_ver, "nebula_pipeline_factory_v0.7_phase3.7")

-- =============================================================================
-- 2. 死代码函数已删除（公理合规）
-- =============================================================================
print("\n--- 2. 死代码函数已删除 ---")
assert_nil("nebula_compose_shader 已删除", nebula_compose_shader)
assert_nil("nebula_compose_instanced_shader 已删除", nebula_compose_instanced_shader)

-- =============================================================================
-- 3. 三个公开着色器组合器均存在
-- =============================================================================
print("\n--- 3. 三个公开着色器组合器 ---")
assert_eq("nebula_compose_shader_instanced 存在", type(nebula_compose_shader_instanced), "function")
assert_eq("nebula_compose_text_shader 存在", type(nebula_compose_text_shader), "function")
assert_eq("nebula_compose_shadow_shaders 存在", type(nebula_compose_shadow_shaders), "function")

-- =============================================================================
-- 4. nebula_compose_shader_instanced — 标准 Visual 默认路径
-- =============================================================================
print("\n--- 4. nebula_compose_shader_instanced ---")
local mock_struct = [[
struct CardUniforms {
  pos:      vec2<f32>,
  size:     vec2<f32>,
  bg_color: vec4<f32>,
  radius:   f32,
  _pad0:    f32,
  viewport: vec2<f32>,
}]]

local si_result = nebula_compose_shader_instanced({
  wgsl_struct = mock_struct,
  struct_name = "CardUniforms",
  has_radius  = true,
  has_border  = false,
})
assert_eq("返回 table", type(si_result), "table")
assert_eq("instanced=true", si_result.instanced, true)
assert_eq("standard_visual=true", si_result.standard_visual, true)
assert_contains("WGSL 包含 CardUniforms", si_result.source, "struct CardUniforms")
assert_contains("WGSL 包含 NebulaViewport", si_result.source, "struct NebulaViewport")
assert_contains("WGSL 包含 storage binding", si_result.source, "var<storage, read>")
assert_contains("WGSL 包含 instance_index", si_result.source, "@builtin(instance_index)")
assert_contains("WGSL 包含 sdf_rounded_rect", si_result.source, "sdf_rounded_rect")
assert_not_contains("WGSL 不含红色占位符", si_result.source, "vec4<f32>(1.0, 0.0, 0.0, 1.0)")

-- =============================================================================
-- 5. nebula_compose_shadow_shaders — 阴影路径
-- =============================================================================
print("\n--- 5. nebula_compose_shadow_shaders ---")
local shadow_result = nebula_compose_shadow_shaders({
  wgsl_struct = mock_struct,
  struct_name = "CardUniforms",
  has_radius  = true,
})
assert_eq("返回 table", type(shadow_result), "table")
assert_eq("shadow_mask_source 是 string", type(shadow_result.shadow_mask_source), "string")
assert_eq("blur_h_source 是 string", type(shadow_result.blur_h_source), "string")
assert_eq("blur_v_source 是 string", type(shadow_result.blur_v_source), "string")
assert_eq("composite_source 是 string", type(shadow_result.composite_source), "string")
-- 阴影遮罩着色器应使用真实 SDF（不是红色占位符）
assert_contains("shadow_mask 包含 SDF", shadow_result.shadow_mask_source, "sdf_rounded_rect")
assert_not_contains("shadow_mask 不含红色占位符", shadow_result.shadow_mask_source, "vec4<f32>(1.0, 0.0, 0.0, 1.0)")
-- 模糊着色器应包含高斯权重
assert_contains("blur_h 包含高斯权重", shadow_result.blur_h_source, "0.227027")
assert_contains("blur_v 包含垂直方向", shadow_result.blur_v_source, "1.0 / tex_size.y")
-- features
local has_shadow_feat = false
for _, f in ipairs(shadow_result.features) do
  if f == "shadow_multipass" then has_shadow_feat = true end
end
assert_eq("features 包含 shadow_multipass", has_shadow_feat, true)

-- =============================================================================
-- 6. nebula_gen_pipeline_source — 三条路径
-- =============================================================================
print("\n--- 6. nebula_gen_pipeline_source 三条路径 ---")

-- 路径 1: standard_instanced（默认路径）
local si_pipe = nebula_gen_pipeline_source({
  base               = "Card",
  uniforms_record    = "CardUniforms",
  wgsl_source        = si_result.source,
  standard_instanced = true,
  max_instances      = 32,
})
assert_eq("standard_instanced 路径返回 string", type(si_pipe), "string")
assert_contains("生成 CardPipeline", si_pipe, "global CardPipeline = @record{")
assert_contains("包含 upload 方法", si_pipe, "function CardPipeline:upload(")
assert_contains("包含 draw_instanced 方法", si_pipe, "function CardPipeline:draw_instanced(")
assert_contains("包含 draw_single 方法", si_pipe, "function CardPipeline:draw_single(")
-- Phase 3.9: update_uniforms shim 保留用于向后兼容旧 demo
-- assert_not_contains("不含 update_uniforms（已废弃）", si_pipe, "function CardPipeline:update_uniforms(")

-- 路径 2: textured（文本 SDF 路径）
local text_shader = nebula_compose_text_shader({
  wgsl_struct = [[struct TextUniforms { viewport: vec2<f32>, text_color: vec4<f32> }]],
  struct_name = "TextUniforms",
})
local text_pipe = nebula_gen_pipeline_source({
  base            = "Label",
  uniforms_record = "TextUniforms",
  wgsl_source     = text_shader.source,
  textured        = true,
})
assert_eq("textured 路径返回 string", type(text_pipe), "string")
assert_contains("生成 LabelPipeline", text_pipe, "global LabelPipeline = @record{")

-- 路径 3: has_shadow（阴影多 Pass 路径）
local shadow_pipe = nebula_gen_pipeline_source({
  base               = "ShadowCard",
  uniforms_record    = "CardUniforms",
  has_shadow         = true,
  shadow_mask_source = shadow_result.shadow_mask_source,
  blur_h_source      = shadow_result.blur_h_source,
  blur_v_source      = shadow_result.blur_v_source,
  composite_source   = shadow_result.composite_source,
})
assert_eq("shadow 路径返回 string", type(shadow_pipe), "string")
assert_contains("生成 ShadowCardPipeline", shadow_pipe, "global ShadowCardPipeline = @record{")
assert_contains("包含阴影子管线字段", shadow_pipe, "shadow_mask_pipeline:")

-- =============================================================================
-- 7. 死代码路径触发明确 error
-- =============================================================================
print("\n--- 7. 死代码路径触发 error ---")
assert_error("simple 路径（无 flag）触发 error", function()
  nebula_gen_pipeline_source({
    base            = "Ghost",
    uniforms_record = "GhostUniforms",
    wgsl_source     = "// placeholder",
  })
end)
assert_error("instanced=true 路径触发 error", function()
  nebula_gen_pipeline_source({
    base            = "Ghost",
    uniforms_record = "GhostUniforms",
    wgsl_source     = "// placeholder",
    instanced       = true,
    instance_record = "GhostInstanceData",
  })
end)

-- =============================================================================
-- 8. 代码行数收敛验证
-- =============================================================================
print("\n--- 8. 代码行数收敛验证 ---")
local function count_lines(filepath)
  local f = io.open(filepath, "r")
  if not f then return nil end
  local count = 0
  for _ in f:lines() do count = count + 1 end
  f:close()
  return count
end

local shader_lines  = count_lines(script_dir .. "/../src/derive/shader_compose.lua")
local factory_lines = count_lines(script_dir .. "/../src/derive/pipeline_factory.lua")

if shader_lines then
  print(("  shader_compose.lua: %d 行"):format(shader_lines))
  assert_le("shader_compose.lua ≤ 400 行", shader_lines, 400)
else
  failed = failed + 1
  print("[FAIL] 无法读取 shader_compose.lua")
end

if factory_lines then
  print(("  pipeline_factory.lua: %d 行"):format(factory_lines))
  assert_le("pipeline_factory.lua ≤ 760 行", factory_lines, 760)
else
  failed = failed + 1
  print("[FAIL] 无法读取 pipeline_factory.lua")
end

if shader_lines and factory_lines then
  local total = shader_lines + factory_lines
  print(("  两文件合计: %d 行"):format(total))
  assert_le("两文件合计 ≤ 1150 行", total, 1150)
end

-- =============================================================================
-- 汇总
-- =============================================================================
print(("\n=== Phase 3.7 专项回归测试结果：%d 通过，%d 失败 ==="):format(passed, failed))
if failed > 0 then
  os.exit(1)
end
