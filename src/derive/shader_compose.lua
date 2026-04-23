-- =============================================================================
-- shader_compose.lua
-- 负责 WGSL 着色器的动态组合与片段拼接
-- =============================================================================

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
-- 实例化着色器组合 (Phase 3.3.3)
-- =============================================================================
function nebula_compose_instanced_shader(opts)
  opts = opts or {}
  local has_radius = opts.has_radius or false
  local has_border = opts.has_border or false

  local features = {"instanced"}
  if has_radius then table.insert(features, "radius") end
  if has_border then table.insert(features, "border") end

  -- InstanceData struct 定义
  local instance_struct = [[
struct InstanceData {
  pos:          vec2<f32>,
  size:         vec2<f32>,
  bg_color:     vec4<f32>,
  border_color: vec4<f32>,
  border_width: f32,
  radius:       f32,
  _pad0:        f32,
  _pad1:        f32,
}
]]

  -- 着色器绑定声明
  local bindings = [[
struct Viewport {
  size: vec2<f32>,
  _pad0: f32,
  _pad1: f32,
}

@group(0) @binding(0) var<uniform>          vp:        Viewport;
@group(0) @binding(1) var<storage, read>    instances: array<InstanceData>;
]]

  -- VertexOutput
  local vertex_io = [[
struct VertexOutput {
  @builtin(position) clip_position: vec4<f32>,
  @location(0)       inst_idx:      u32,
}
]]

  -- 顶点着色器：为每个实例生成 6 个顶点（两个三角形）
  local vs_main = [[
@vertex
fn vs_main(
  @builtin(vertex_index)   vi:   u32,
  @builtin(instance_index) inst: u32,
) -> VertexOutput {
  let d = instances[inst];
  
  // 6 vertices for 2 triangles (0-1-2, 2-1-3)
  var pos = array<vec2<f32>, 6>(
    vec2<f32>(0.0, 0.0), // top-left
    vec2<f32>(1.0, 0.0), // top-right
    vec2<f32>(0.0, 1.0), // bottom-left
    vec2<f32>(0.0, 1.0), // bottom-left
    vec2<f32>(1.0, 0.0), // top-right
    vec2<f32>(1.0, 1.0)  // bottom-right
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
  }
end

-- =============================================================================
-- 文本着色器组合 (Phase 3.2.4)
-- ============================================================================
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
-- =============================================================================
-- 基础形状着色器组合 (Phase 2.3.3)
-- =============================================================================
function nebula_compose_shader(opts)
  local struct_def = opts.wgsl_struct or ""
  local source = [[
struct Viewport { size: vec2<f32>, _pad0: f32, _pad1: f32 }
@group(0) @binding(0) var<uniform> vp: Viewport;
]] .. struct_def .. [[

struct VertexOutput {
  @builtin(position) clip_pos: vec4<f32>,
  @location(0)       p:        vec2<f32>,
}

@vertex
fn vs_main(@builtin(vertex_index) vi: u32) -> VertexOutput {
  var pos = array<vec2<f32>, 4>(
    vec2<f32>(-1.0,  1.0),
    vec2<f32>( 1.0,  1.0),
    vec2<f32>(-1.0, -1.0),
    vec2<f32>( 1.0, -1.0)
  );
  var out: VertexOutput;
  out.clip_pos = vec4<f32>(pos[vi], 0.0, 1.0);
  out.p = pos[vi];
  return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
  // 基础占位实现：渲染红色矩形
  return vec4<f32>(1.0, 0.0, 0.0, 1.0);
}
]]
  return { 
    source             = source,
    features           = {},
    required_passes    = {"main"},
    shadow_mask_source = "// placeholder\n",
    blur_h_source      = "// placeholder\n",
    blur_v_source      = "// placeholder\n",
    composite_source   = "// placeholder\n",
  }
end

return "nebula_shader_compose_v0.4_phase3.3.3"
