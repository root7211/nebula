-- shader_compose.lua — Phase 3.7
-- 三个公开函数：nebula_compose_shader_instanced / nebula_compose_text_shader / nebula_compose_shadow_shaders
-- 已删除：nebula_compose_shader（红色占位符）、nebula_compose_instanced_shader（Phase 3.3 遗留）

local WGSL_FRAGMENTS = {
  -- 基础 SDF 矩形
  sdf_rect = [[
fn sdf_rect(p: vec2<f32>, b: vec2<f32>) -> f32 {
  let d = abs(p) - b;
  return length(max(d, vec2<f32>(0.0))) + min(max(d.x, d.y), 0.0);
}
]],

  -- 圆角矩形
  sdf_rounded_rect = [[
fn sdf_rounded_rect(p: vec2<f32>, b: vec2<f32>, r: f32) -> f32 {
  let q = abs(p) - b + r;
  return length(max(q, vec2<f32>(0.0))) + min(max(q.x, q.y), 0.0) - r;
}
]],
}

-- =============================================================================
-- 文本着色器组合 (Phase 3.2.4)
-- =============================================================================
function nebula_compose_text_shader(opts)
  local struct_def = opts.wgsl_struct or ""
  local struct_name = opts.struct_name or "TextUniforms"
  local source = [[
]] .. struct_def .. [[
@group(0) @binding(0) var<uniform> u: ]] .. struct_name .. [[;
@group(0) @binding(1) var glyph_atlas:   texture_2d<f32>;
@group(0) @binding(2) var glyph_sampler: sampler;

struct TextVertexInput {
  @location(0) position: vec2<f32>,
  @location(1) uv:       vec2<f32>,
}
struct VertexOutput {
  @builtin(position) clip_pos: vec4<f32>,
  @location(0)       uv:       vec2<f32>,
}

@vertex
fn vs_main(in: TextVertexInput) -> VertexOutput {
  var out: VertexOutput;
  // Use u.viewport from the provided struct
  let ndc = vec2<f32>(
    (in.position.x / u.viewport.x) * 2.0 - 1.0,
    (in.position.y / u.viewport.y) * 2.0 - 1.0
  );
  out.clip_pos = vec4<f32>(ndc.x, -ndc.y, 0.0, 1.0);
  out.uv = in.uv;
  return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
  let sdf_sample = textureSample(glyph_atlas, glyph_sampler, in.uv).r;
  
  // Basic SDF anti-aliasing with fwidth
  let width = fwidth(sdf_sample);
  let alpha = smoothstep(0.5 - width, 0.5 + width, sdf_sample);
  
  if (alpha < 0.001) {
    discard;
  }
  
  return vec4<f32>(u.text_color.rgb, u.text_color.a * alpha);
}
]]
  return {
    source          = source,
    textured        = true,
    vertex_layout   = "pos_uv",
    features        = {"text_sdf", "textured", "vertex_pos_uv"},
    required_passes = {"main"},
  }
end

-- ★ Phase 3.7: 标准 Visual 的 Instanced 着色器组合（所有非阴影、非文本 Visual 的唯一路径）
function nebula_compose_shader_instanced(opts)
  opts = opts or {}
  local struct_name = opts.struct_name or "Uniforms"
  local has_radius  = opts.has_radius  or false
  local has_border  = opts.has_border  or false

  local features = {"instanced", "standard_visual"}
  if has_radius then table.insert(features, "radius") end
  if has_border then table.insert(features, "border") end

  -- 使用传入的 wgsl_struct 作为 InstanceData（字段与 <T>Uniforms 完全一致）
  local instance_struct = (opts.wgsl_struct or "") .. "\n"

  -- 绑定声明：binding 0 = viewport uniform，binding 1 = storage array
  local bindings = string.format([[

struct NebulaViewport {
  size: vec2<f32>,
  _pad0: f32,
  _pad1: f32,
}

@group(0) @binding(0) var<uniform>       vp:        NebulaViewport;
@group(0) @binding(1) var<storage, read>  instances: array<%s>;
]], struct_name)

  -- VertexOutput
  local vertex_io = [[

struct VertexOutput {
  @builtin(position) clip_position: vec4<f32>,
  @location(0)       inst_idx:      u32,
}
]]

  -- 顶点着色器：每个实例生成 6 个顶点（两个三角形），通过 instance_index 定位
  local vs_main = [[

@vertex
fn vs_main(
  @builtin(vertex_index)   vi:   u32,
  @builtin(instance_index) inst: u32,
) -> VertexOutput {
  let d = instances[inst];
  var pos = array<vec2<f32>, 6>(
    vec2<f32>(0.0, 0.0),
    vec2<f32>(1.0, 0.0),
    vec2<f32>(0.0, 1.0),
    vec2<f32>(0.0, 1.0),
    vec2<f32>(1.0, 0.0),
    vec2<f32>(1.0, 1.0)
  );
  let p = d.pos + pos[vi] * d.size;
  let ndc = (p / vp.size) * 2.0 - 1.0;
  var out: VertexOutput;
  out.clip_position = vec4<f32>(ndc.x, -ndc.y, 0.0, 1.0);
  out.inst_idx      = inst;
  return out;
}
]]

  -- SDF 函数
  local sdf_func = ""
  if has_radius then
    sdf_func = WGSL_FRAGMENTS.sdf_rounded_rect
  else
    sdf_func = WGSL_FRAGMENTS.sdf_rect
  end

  -- 片段着色器
  local fs_lines = {}
  table.insert(fs_lines, "\n@fragment")
  table.insert(fs_lines, "fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {")
  table.insert(fs_lines, "  let d = instances[in.inst_idx];")
  table.insert(fs_lines, "  let pixel     = in.clip_position.xy;")
  table.insert(fs_lines, "  let center    = d.pos + d.size * 0.5;")
  table.insert(fs_lines, "  let p         = pixel - center;")
  table.insert(fs_lines, "  let half_size = d.size * 0.5;")
  table.insert(fs_lines, "")
  table.insert(fs_lines, "  if (pixel.x < d.pos.x || pixel.x > d.pos.x + d.size.x ||")
  table.insert(fs_lines, "      pixel.y < d.pos.y || pixel.y > d.pos.y + d.size.y) {")
  table.insert(fs_lines, "    discard;")
  table.insert(fs_lines, "  }")

  if has_radius then
    table.insert(fs_lines, "  let dist = sdf_rounded_rect(p, half_size, d.radius);")
  else
    table.insert(fs_lines, "  let dist = sdf_rect(p, half_size);")
  end

  table.insert(fs_lines, "  let aa = 1.0;")
  table.insert(fs_lines, "  let fill_alpha = 1.0 - smoothstep(-aa, aa, dist);")
  if has_border then
    table.insert(fs_lines, "  let border_alpha = (1.0 - smoothstep(-aa, aa, dist + d.border_width)) - fill_alpha;")
  end
  table.insert(fs_lines, "  var color = d.bg_color * fill_alpha;")
  if has_border then
    table.insert(fs_lines, "  color = color + d.border_color * border_alpha;")
  end
  table.insert(fs_lines, "  if color.a < 0.001 { discard; }")
  table.insert(fs_lines, "  return color;")
  table.insert(fs_lines, "}")

  return {
    source          = instance_struct .. bindings .. vertex_io .. vs_main .. sdf_func .. table.concat(fs_lines, "\n"),
    features        = features,
    required_passes = {"main"},
    instanced       = true,
    standard_visual = true,
  }
end

-- =============================================================================
-- ★ Phase 3.7: 阴影多 Pass 子着色器组合（仅供 gen_pipeline_shadow 使用）
--
-- 原 nebula_compose_shader 同时承担"主着色器"和"阴影子着色器"两个职责，
-- 其中主着色器是红色占位符（违反公理 C）。
-- Phase 3.7 将阴影子着色器提取为独立函数，主着色器改用 nebula_compose_shader_instanced。
--
-- 返回值：仅包含阴影相关的四个 WGSL 源码字段，不含 source（主着色器）。
-- opts:
--   wgsl_struct  : string  — 已生成的 WGSL struct 定义
--   struct_name  : string  — struct 名称
--   has_radius   : boolean
--   has_border   : boolean
-- =============================================================================
function nebula_compose_shadow_shaders(opts)
  opts = opts or {}
  local struct_def  = opts.wgsl_struct or ""
  local struct_name = opts.struct_name or "Uniforms"
  local has_radius  = opts.has_radius  or false

  -- 阴影遮罩着色器（Pass 1）：生成高斯模糊前的原始阴影形状
  local shadow_mask_source = struct_def .. string.format([[

struct Viewport { size: vec2<f32>, _pad0: f32, _pad1: f32 }
@group(0) @binding(0) var<uniform> vp: Viewport;
@group(0) @binding(1) var<uniform> u:  %s;

struct VertexOutput {
  @builtin(position) clip_pos: vec4<f32>,
  @location(0)       p:        vec2<f32>,
}

@vertex
fn vs_main(@builtin(vertex_index) vi: u32) -> VertexOutput {
  var corners = array<vec2<f32>, 4>(
    vec2<f32>(0.0, 0.0), vec2<f32>(1.0, 0.0),
    vec2<f32>(0.0, 1.0), vec2<f32>(1.0, 1.0)
  );
  let p = u.pos + corners[vi] * u.size;
  let ndc = (p / vp.size) * 2.0 - 1.0;
  var out: VertexOutput;
  out.clip_pos = vec4<f32>(ndc.x, -ndc.y, 0.0, 1.0);
  out.p = corners[vi];
  return out;
}

]], struct_name)

  if has_radius then
    shadow_mask_source = shadow_mask_source .. WGSL_FRAGMENTS.sdf_rounded_rect .. [[

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
  let center    = vec2<f32>(0.5, 0.5);
  let p         = (in.p - center) * u.size;
  let half_size = u.size * 0.5;
  let dist = sdf_rounded_rect(p, half_size, u.radius);
  let alpha = 1.0 - smoothstep(-1.0, 1.0, dist);
  return vec4<f32>(0.0, 0.0, 0.0, alpha * 0.5);
}
]]
  else
    shadow_mask_source = shadow_mask_source .. WGSL_FRAGMENTS.sdf_rect .. [[

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
  let center    = vec2<f32>(0.5, 0.5);
  let p         = (in.p - center) * u.size;
  let half_size = u.size * 0.5;
  let dist = sdf_rect(p, half_size);
  let alpha = 1.0 - smoothstep(-1.0, 1.0, dist);
  return vec4<f32>(0.0, 0.0, 0.0, alpha * 0.5);
}
]]
  end

  -- 水平模糊着色器（Pass 2）
  local blur_h_source = [[
@group(0) @binding(0) var shadow_tex:     texture_2d<f32>;
@group(0) @binding(1) var shadow_sampler: sampler;

struct VertexOutput {
  @builtin(position) clip_pos: vec4<f32>,
  @location(0)       uv:       vec2<f32>,
}

@vertex
fn vs_main(@builtin(vertex_index) vi: u32) -> VertexOutput {
  var pos = array<vec2<f32>, 4>(
    vec2<f32>(-1.0,  1.0), vec2<f32>(1.0,  1.0),
    vec2<f32>(-1.0, -1.0), vec2<f32>(1.0, -1.0)
  );
  var uv = array<vec2<f32>, 4>(
    vec2<f32>(0.0, 0.0), vec2<f32>(1.0, 0.0),
    vec2<f32>(0.0, 1.0), vec2<f32>(1.0, 1.0)
  );
  var out: VertexOutput;
  out.clip_pos = vec4<f32>(pos[vi], 0.0, 1.0);
  out.uv = uv[vi];
  return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
  let tex_size = vec2<f32>(textureDimensions(shadow_tex));
  let offset = vec2<f32>(1.0 / tex_size.x, 0.0);
  var color = vec4<f32>(0.0);
  let weights = array<f32, 5>(0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216);
  color += textureSample(shadow_tex, shadow_sampler, in.uv) * weights[0];
  for (var i = 1; i < 5; i++) {
    color += textureSample(shadow_tex, shadow_sampler, in.uv + offset * f32(i)) * weights[i];
    color += textureSample(shadow_tex, shadow_sampler, in.uv - offset * f32(i)) * weights[i];
  }
  return color;
}
]]

  -- 垂直模糊着色器（Pass 3）
  local blur_v_source = [[
@group(0) @binding(0) var shadow_tex:     texture_2d<f32>;
@group(0) @binding(1) var shadow_sampler: sampler;

struct VertexOutput {
  @builtin(position) clip_pos: vec4<f32>,
  @location(0)       uv:       vec2<f32>,
}

@vertex
fn vs_main(@builtin(vertex_index) vi: u32) -> VertexOutput {
  var pos = array<vec2<f32>, 4>(
    vec2<f32>(-1.0,  1.0), vec2<f32>(1.0,  1.0),
    vec2<f32>(-1.0, -1.0), vec2<f32>(1.0, -1.0)
  );
  var uv = array<vec2<f32>, 4>(
    vec2<f32>(0.0, 0.0), vec2<f32>(1.0, 0.0),
    vec2<f32>(0.0, 1.0), vec2<f32>(1.0, 1.0)
  );
  var out: VertexOutput;
  out.clip_pos = vec4<f32>(pos[vi], 0.0, 1.0);
  out.uv = uv[vi];
  return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
  let tex_size = vec2<f32>(textureDimensions(shadow_tex));
  let offset = vec2<f32>(0.0, 1.0 / tex_size.y);
  var color = vec4<f32>(0.0);
  let weights = array<f32, 5>(0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216);
  color += textureSample(shadow_tex, shadow_sampler, in.uv) * weights[0];
  for (var i = 1; i < 5; i++) {
    color += textureSample(shadow_tex, shadow_sampler, in.uv + offset * f32(i)) * weights[i];
    color += textureSample(shadow_tex, shadow_sampler, in.uv - offset * f32(i)) * weights[i];
  }
  return color;
}
]]

  -- 合成着色器（Pass 4）：将模糊后的阴影与主场景合成
  local composite_source = [[
@group(0) @binding(0) var shadow_tex:     texture_2d<f32>;
@group(0) @binding(1) var shadow_sampler: sampler;

struct VertexOutput {
  @builtin(position) clip_pos: vec4<f32>,
  @location(0)       uv:       vec2<f32>,
}

@vertex
fn vs_main(@builtin(vertex_index) vi: u32) -> VertexOutput {
  var pos = array<vec2<f32>, 4>(
    vec2<f32>(-1.0,  1.0), vec2<f32>(1.0,  1.0),
    vec2<f32>(-1.0, -1.0), vec2<f32>(1.0, -1.0)
  );
  var uv = array<vec2<f32>, 4>(
    vec2<f32>(0.0, 0.0), vec2<f32>(1.0, 0.0),
    vec2<f32>(0.0, 1.0), vec2<f32>(1.0, 1.0)
  );
  var out: VertexOutput;
  out.clip_pos = vec4<f32>(pos[vi], 0.0, 1.0);
  out.uv = uv[vi];
  return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
  return textureSample(shadow_tex, shadow_sampler, in.uv);
}
]]

  return {
    shadow_mask_source = shadow_mask_source,
    blur_h_source      = blur_h_source,
    blur_v_source      = blur_v_source,
    composite_source   = composite_source,
    features           = {"shadow_multipass"},
  }
end

return "nebula_shader_compose_v0.6_phase3.7"
