package.path = "/home/ubuntu/nebula/src/?.lua;/home/ubuntu/nebula/src/?/init.lua;" .. package.path

local mod = require "derive.shader_compose"
assert(mod == "nebula_shader_compose_v0.3_phase3.2.3", "unexpected shader_compose version")

local result = nebula_compose_text_shader {
  wgsl_struct = [[
struct TextVisualUniforms {
  viewport: vec2<f32>,
  _pad0: vec2<f32>,
  text_color: vec4<f32>,
}
]],
  struct_name = "TextVisualUniforms",
}

assert(result.textured == true, "expected textured pipeline metadata")
assert(result.vertex_layout == "pos_uv", "expected pos_uv vertex layout")
assert(result.required_passes[1] == "main", "expected single main pass")
assert(result.source:find("@binding%(1%) var glyph_atlas", 1), "missing atlas texture binding")
assert(result.source:find("@binding%(2%) var glyph_sampler", 1), "missing sampler binding")
assert(result.source:find("struct TextVertexInput", 1), "missing text vertex input")
assert(result.source:find("@location%(0%) position", 1), "missing position attribute")
assert(result.source:find("@location%(1%) uv", 1), "missing uv attribute")
assert(result.source:find("textureSample%(glyph_atlas, glyph_sampler, in%.uv%)", 1), "missing glyph texture sample")
assert(result.source:find("fwidth%(sdf_sample%)", 1), "missing derivative anti-aliasing")
assert(result.source:find("u%.text_color", 1), "missing text color field")

print("[PASS] shader_compose Phase 3.2.3 text SDF shader smoke test")
