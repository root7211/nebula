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

-- =============================================================================
-- ★ Phase 4.1: Slug 文本着色器组合
--
-- 生成基于 Slug 算法的 WGSL 着色器对（顶点 + 片段）。
-- 曲线数据和 Band 数据通过 Storage Buffer 传入（binding 1/2/3）。
-- 顶点格式（NebulaSlugVertex）：
--   location(0) pos: vec4<f32>  — (objX, objY, normalX, normalY)
--   location(1) tex: vec4<f32>  — (emX, emY, packedGlyphLoc, packedBandMax)
--   location(2) bnd: vec4<f32>  — (bandScaleX, bandScaleY, bandOffsetX, bandOffsetY)
--   location(3) col: vec4<f32>  — (r, g, b, a)
-- =============================================================================
function nebula_compose_slug_shader(opts)
  opts = opts or {}
  local struct_name = opts.struct_name or "NebulaSlugUniforms"
  local struct_def  = opts.wgsl_struct or (
    "struct " .. struct_name .. " {\n" ..
    "  viewport: vec2<f32>,\n" ..
    "}\n"
  )

  local source = struct_def .. [[
// ★ Phase 4.1: Slug 算法 Storage Buffer 绑定
// Binding 0: Uniform Buffer (视口等)
// Binding 1: 曲线数据 (NebulaSlugCurve 数组，每条曲线 6 个 f32)
// Binding 2: Band 元数据 (offset + count，每条 2 个 u32)
// Binding 3: Band 曲线引用索引 (uint32 数组)
@group(0) @binding(0) var<uniform> u_slug: ]] .. struct_name .. [[;

struct SlugCurveData {
  p0x: f32, p0y: f32,
  p1x: f32, p1y: f32,
  p2x: f32, p2y: f32,
}
struct SlugBandMeta {
  offset: u32,
  count:  u32,
}
@group(0) @binding(1) var<storage, read> slug_curves:     array<SlugCurveData>;
@group(0) @binding(2) var<storage, read> slug_band_metas: array<SlugBandMeta>;
@group(0) @binding(3) var<storage, read> slug_band_refs:  array<u32>;

// ---- 顶点输入/输出 ----
struct SlugVertexInput {
  @location(0) pos: vec4<f32>,
  @location(1) tex: vec4<f32>,
  @location(2) bnd: vec4<f32>,
  @location(3) col: vec4<f32>,
}
struct SlugVertexOutput {
  @builtin(position)              clip_pos:  vec4<f32>,
  @location(0)                    color:     vec4<f32>,
  @location(1)                    texcoord:  vec2<f32>,
  @location(2) @interpolate(flat) banding:   vec4<f32>,
  @location(3) @interpolate(flat) glyph_loc: vec4<u32>,
  @location(4) @interpolate(flat) band_base: u32,
}

// ---- 顶点着色器 ----
@vertex
fn vs_main(in: SlugVertexInput) -> SlugVertexOutput {
  var out: SlugVertexOutput;
  let ndc = vec2<f32>(
    (in.pos.x / u_slug.viewport.x) * 2.0 - 1.0,
    (in.pos.y / u_slug.viewport.y) * 2.0 - 1.0
  );
  out.clip_pos = vec4<f32>(ndc.x, -ndc.y, 0.0, 1.0);
  out.color    = in.col;
  out.texcoord = in.tex.xy;
  out.banding  = in.bnd;
  let gz = bitcast<u32>(in.tex.z);
  let gw = bitcast<u32>(in.tex.w);
  out.glyph_loc = vec4<u32>(gz & 0xFFFFu, gz >> 16u, gw & 0xFFFFu, gw >> 16u);
  out.band_base = out.glyph_loc.x;
  return out;
}

// ---- Slug 核心算法函数 ----

fn slug_calc_root_code(y1: f32, y2: f32, y3: f32) -> u32 {
  let i1 = bitcast<u32>(y1) >> 31u;
  let i2 = bitcast<u32>(y2) >> 30u;
  let i3 = bitcast<u32>(y3) >> 29u;
  let shift = (i3 & 4u) | (((i2 & 2u) | (i1 & ~2u)) & ~4u);
  return ((0x2E74u >> shift) & 0x0101u);
}

fn slug_solve_horiz(p12: vec4<f32>, p3: vec2<f32>) -> vec2<f32> {
  let a = vec2<f32>(p12.x - p12.z * 2.0 + p3.x, p12.y - p12.w * 2.0 + p3.y);
  let b = vec2<f32>(p12.x - p12.z, p12.y - p12.w);
  let ra = 1.0 / a.y;
  let rb = 0.5 / b.y;
  let d = sqrt(max(b.y * b.y - a.y * p12.y, 0.0));
  var t1 = (b.y - d) * ra;
  var t2 = (b.y + d) * ra;
  if (abs(a.y) < 1.0 / 65536.0) { t1 = p12.y * rb; t2 = p12.y * rb; }
  return vec2<f32>((a.x * t1 - b.x * 2.0) * t1 + p12.x,
                   (a.x * t2 - b.x * 2.0) * t2 + p12.x);
}

fn slug_solve_vert(p12: vec4<f32>, p3: vec2<f32>) -> vec2<f32> {
  let a = vec2<f32>(p12.x - p12.z * 2.0 + p3.x, p12.y - p12.w * 2.0 + p3.y);
  let b = vec2<f32>(p12.x - p12.z, p12.y - p12.w);
  let ra = 1.0 / a.x;
  let rb = 0.5 / b.x;
  let d = sqrt(max(b.x * b.x - a.x * p12.x, 0.0));
  var t1 = (b.x - d) * ra;
  var t2 = (b.x + d) * ra;
  if (abs(a.x) < 1.0 / 65536.0) { t1 = p12.x * rb; t2 = p12.x * rb; }
  return vec2<f32>((a.y * t1 - b.y * 2.0) * t1 + p12.y,
                   (a.y * t2 - b.y * 2.0) * t2 + p12.y);
}

fn slug_calc_coverage(xcov: f32, ycov: f32, xwgt: f32, ywgt: f32) -> f32 {
  return max(
    abs(xcov * xwgt + ycov * ywgt) / max(xwgt + ywgt, 1.0 / 65536.0),
    min(abs(xcov), abs(ycov))
  );
}

// ---- 片段着色器 ----
@fragment
fn fs_main(in: SlugVertexOutput) -> @location(0) vec4<f32> {
  let render_coord = in.texcoord;
  let bnd          = in.banding;
  let band_max_x   = i32(in.glyph_loc.z);
  let band_max_y   = i32(in.glyph_loc.w);
  let band_base    = in.band_base;

  let band_coord = render_coord * bnd.xy + bnd.zw;
  let band_ix    = clamp(i32(band_coord.x), 0, band_max_x);
  let band_iy    = clamp(i32(band_coord.y), 0, band_max_y);

  let dpx = dpdx(render_coord.x);
  let dpy = dpdy(render_coord.y);
  let pixels_per_em = vec2<f32>(
    1.0 / max(abs(dpx), 0.0001),
    1.0 / max(abs(dpy), 0.0001)
  );

  var xcov: f32 = 0.0;
  var xwgt: f32 = 0.0;

  // 处理水平 Band（h-bands，索引 0..band_max_y）
  let hband_meta_idx = band_base + u32(band_iy);
  let hband = slug_band_metas[hband_meta_idx];
  for (var ci: u32 = 0u; ci < hband.count; ci = ci + 1u) {
    let curve_idx = slug_band_refs[hband.offset + ci];
    let c = slug_curves[curve_idx];
    let p12 = vec4<f32>(c.p0x, c.p0y, c.p1x, c.p1y) - vec4<f32>(render_coord, render_coord);
    let p3  = vec2<f32>(c.p2x, c.p2y) - render_coord;
    if (max(max(p12.x, p12.z), p3.x) * pixels_per_em.x < -0.5) { break; }
    let code = slug_calc_root_code(p12.y, p12.w, p3.y);
    if (code != 0u) {
      let r = slug_solve_horiz(p12, p3) * pixels_per_em.x;
      if ((code & 1u) != 0u) {
        xcov += saturate(r.x + 0.5);
        xwgt = max(xwgt, saturate(1.0 - abs(r.x) * 2.0));
      }
      if (code > 1u) {
        xcov -= saturate(r.y + 0.5);
        xwgt = max(xwgt, saturate(1.0 - abs(r.y) * 2.0));
      }
    }
  }

  var ycov: f32 = 0.0;
  var ywgt: f32 = 0.0;

  // 处理垂直 Band（v-bands，索引 band_max_y+1..band_max_y+1+band_max_x）
  let vband_meta_idx = band_base + u32(band_max_y + 1) + u32(band_ix);
  let vband = slug_band_metas[vband_meta_idx];
  for (var ci: u32 = 0u; ci < vband.count; ci = ci + 1u) {
    let curve_idx = slug_band_refs[vband.offset + ci];
    let c = slug_curves[curve_idx];
    let p12 = vec4<f32>(c.p0x, c.p0y, c.p1x, c.p1y) - vec4<f32>(render_coord, render_coord);
    let p3  = vec2<f32>(c.p2x, c.p2y) - render_coord;
    if (max(max(p12.y, p12.w), p3.y) * pixels_per_em.y < -0.5) { break; }
    let code = slug_calc_root_code(p12.x, p12.z, p3.x);
    if (code != 0u) {
      let r = slug_solve_vert(p12, p3) * pixels_per_em.y;
      if ((code & 1u) != 0u) {
        ycov -= saturate(r.x + 0.5);
        ywgt = max(ywgt, saturate(1.0 - abs(r.x) * 2.0));
      }
      if (code > 1u) {
        ycov += saturate(r.y + 0.5);
        ywgt = max(ywgt, saturate(1.0 - abs(r.y) * 2.0));
      }
    }
  }

  let coverage = slug_calc_coverage(xcov, ycov, xwgt, ywgt);
  if (coverage < 0.001) { discard; }
  return in.color * coverage;
}
]]

  return {
    source          = source,
    textured        = false,
    vertex_layout   = "slug",
    features        = {"slug", "vertex_slug", "storage_buffer"},
    required_passes = {"main"},
    slug_bindings   = true,
  }
end

return "nebula_shader_compose_v0.7_phase4.1"
