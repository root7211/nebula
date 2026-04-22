package.path = "/home/ubuntu/nebula/src/?.lua;/home/ubuntu/nebula/src/?/init.lua;" .. package.path

local mod = require "derive.pipeline_factory"
assert(mod == "nebula_pipeline_factory_v0.5_phase3.3", "unexpected pipeline_factory version (expected v0.4_phase3.2.4, got " .. tostring(mod) .. ")")

local src = nebula_gen_pipeline_source {
  base = "TextVisual",
  uniforms_record = "TextVisualUniforms",
  wgsl_source = [[
@group(0) @binding(0) var<uniform> u_dummy: vec4<f32>;
@group(0) @binding(1) var atlas_tex: texture_2d<f32>;
@group(0) @binding(2) var atlas_sampler: sampler;

struct VSIn {
  @location(0) position: vec2<f32>,
  @location(1) uv: vec2<f32>,
};

struct VSOut {
  @builtin(position) position: vec4<f32>,
  @location(0) uv: vec2<f32>,
};

@vertex
fn vs_main(in_: VSIn) -> VSOut {
  var out: VSOut;
  out.position = vec4<f32>(in_.position, 0.0, 1.0);
  out.uv = in_.uv;
  return out;
}

@fragment
fn fs_main(in_: VSOut) -> @location(0) vec4<f32> {
  return textureSample(atlas_tex, atlas_sampler, in_.uv);
}
]],
  textured = true,
  vertex_layout = "pos_uv",
}

assert(src:find("nebula_pipeline_textured_vertex_init", 1, true), "missing textured vertex init call")
assert(src:find("wgpuRenderPassEncoderSetVertexBuffer", 1, true), "missing vertex buffer draw path")
assert(src:find("update_texture_binding", 1, true), "missing texture binding updater")
assert(src:find("upload_vertices", 1, true), "missing vertex upload method")
print("[PASS] pipeline_factory Phase 3.2.2 textured+pos_uv path smoke test")
