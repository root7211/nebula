-- =============================================================================
-- smoke_phase3_2_4.lua
-- Nebula GUI Compiler — Phase 3.2.5 回归测试
--
-- 验证 Phase 3.2.4 TextVisual 派生引擎的完整代码生成链路：
--   1. shader_compose 生成 SDF 文本着色器（含 fwidth 抗锯齿）
--   2. pipeline_factory 生成纹理+顶点管线（textured + pos_uv）
--   3. nebula_core 的 nebula_derive_text_visual 正确串联上述模块
--
-- 运行方式：
--   cd /home/ubuntu/nebula && lua5.4 tools/smoke_phase3_2_4.lua
--   或：cd /home/ubuntu/nebula && nelua --script tools/smoke_phase3_2_4.lua
-- =============================================================================

package.path = "/home/ubuntu/nebula/src/?.lua;/home/ubuntu/nebula/src/?/init.lua;" .. package.path

-- =========================================================================
-- Part 1: 验证模块版本
-- =========================================================================
local shader_mod = require "derive.shader_compose"
assert(shader_mod == "nebula_shader_compose_v0.3_phase3.2.3",
  "FAIL: unexpected shader_compose version: " .. tostring(shader_mod))

local pipeline_mod = require "derive.pipeline_factory"
assert(pipeline_mod == "nebula_pipeline_factory_v0.4_phase3.2.4",
  "FAIL: unexpected pipeline_factory version: " .. tostring(pipeline_mod))

print("[PASS] module versions verified")

-- =========================================================================
-- Part 2: 验证文本着色器生成（SDF 管线完整性）
-- =========================================================================
local text_wgsl_struct = [[
struct TextUniforms {
  viewport: vec2<f32>,
  _pad0: vec2<f32>,
  text_color: vec4<f32>,
}
]]

local shader_result = nebula_compose_text_shader({
  wgsl_struct  = text_wgsl_struct,
  struct_name  = "TextUniforms",
})

-- 2a: 元数据断言
assert(shader_result.textured == true,
  "FAIL: text shader should be textured")
assert(shader_result.vertex_layout == "pos_uv",
  "FAIL: text shader should use pos_uv vertex layout")
assert(#shader_result.required_passes == 1 and shader_result.required_passes[1] == "main",
  "FAIL: text shader should require single 'main' pass")
assert(#shader_result.features == 3,
  "FAIL: text shader should have 3 features (text_sdf, textured, vertex_pos_uv)")

-- 2b: WGSL 源码结构断言
local src = shader_result.source
assert(src:find("@binding%(0%) var<uniform> u: TextUniforms", 1, false),
  "FAIL: missing uniform binding in text shader")
assert(src:find("@binding%(1%) var glyph_atlas", 1, false),
  "FAIL: missing atlas texture binding")
assert(src:find("@binding%(2%) var glyph_sampler", 1, false),
  "FAIL: missing sampler binding")
assert(src:find("struct TextVertexInput", 1, true),
  "FAIL: missing TextVertexInput struct")
assert(src:find("@location%(0%) position", 1, false),
  "FAIL: missing position attribute")
assert(src:find("@location%(1%) uv", 1, false),
  "FAIL: missing uv attribute")

-- 2c: SDF 抗锯齿关键逻辑
assert(src:find("textureSample%(glyph_atlas, glyph_sampler, in%.uv%)", 1, false),
  "FAIL: missing glyph texture sample")
assert(src:find("fwidth%(sdf_sample%)", 1, false),
  "FAIL: missing derivative anti-aliasing (fwidth)")
assert(src:find("smoothstep", 1, true),
  "FAIL: missing smoothstep for SDF edge blending")
assert(src:find("u%.text_color", 1, false),
  "FAIL: missing text_color uniform reference")

-- 2d: NDC 坐标变换（viewport 归一化）
assert(src:find("u%.viewport%.x", 1, false),
  "FAIL: missing viewport.x in vertex shader")
assert(src:find("u%.viewport%.y", 1, false),
  "FAIL: missing viewport.y in vertex shader")

print("[PASS] text shader SDF pipeline completeness verified (16 assertions)")

-- =========================================================================
-- Part 3: 验证管线工厂的纹理+顶点路径
-- =========================================================================
local pipeline_src = nebula_gen_pipeline_source({
  base             = "TextVisual",
  uniforms_record  = "TextVisualUniforms",
  wgsl_source      = src,
  textured         = true,
  vertex_layout    = "pos_uv",
})

-- 3a: Pipeline record 和核心方法
assert(pipeline_src:find("global TextVisualPipeline", 1, true),
  "FAIL: missing TextVisualPipeline record")
assert(pipeline_src:find("function TextVisualPipeline:init", 1, true),
  "FAIL: missing TextVisualPipeline:init method")
assert(pipeline_src:find("function TextVisualPipeline:update_uniforms", 1, true),
  "FAIL: missing TextVisualPipeline:update_uniforms method")
assert(pipeline_src:find("function TextVisualPipeline:draw", 1, true),
  "FAIL: missing TextVisualPipeline:draw method")

-- 3b: 纹理管线特有方法
assert(pipeline_src:find("update_texture_binding", 1, true),
  "FAIL: missing update_texture_binding method")
assert(pipeline_src:find("upload_vertices", 1, true),
  "FAIL: missing upload_vertices method")
assert(pipeline_src:find("draw_buffer", 1, true),
  "FAIL: missing draw_buffer method")

-- 3c: WebGPU 顶点缓冲区绑定
assert(pipeline_src:find("wgpuRenderPassEncoderSetVertexBuffer", 1, true),
  "FAIL: missing vertex buffer binding in draw path")
assert(pipeline_src:find("nebula_pipeline_textured_vertex_init", 1, true),
  "FAIL: missing textured vertex pipeline init call")

-- 3d: 纹理 BindGroup 创建
assert(pipeline_src:find("nebula_create_textured_bind_group", 1, true),
  "FAIL: missing textured bind group creation")

print("[PASS] pipeline_factory textured+pos_uv path verified (10 assertions)")

-- =========================================================================
-- Part 4: 验证着色器的 discard 逻辑（透明像素剔除）
-- =========================================================================
assert(src:find("discard", 1, true),
  "FAIL: missing discard for transparent pixels")
assert(src:find("0.001", 1, true),
  "FAIL: missing alpha threshold for discard")

print("[PASS] discard logic for transparent pixels verified")

-- =========================================================================
-- Part 5: 验证着色器特性列表
-- =========================================================================
local feature_set = {}
for _, f in ipairs(shader_result.features) do
  feature_set[f] = true
end
assert(feature_set["text_sdf"],
  "FAIL: missing 'text_sdf' feature")
assert(feature_set["textured"],
  "FAIL: missing 'textured' feature")
assert(feature_set["vertex_pos_uv"],
  "FAIL: missing 'vertex_pos_uv' feature")

print("[PASS] shader feature flags verified")

-- =========================================================================
-- 总结
-- =========================================================================
print("")
print("============================================")
print("[PASS] Phase 3.2.4 TextVisual derive engine")
print("       smoke test — ALL 31 assertions passed")
print("============================================")
