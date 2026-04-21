-- =============================================================================
-- derive/shader_compose.lua
-- Nebula GUI Compiler — Phase 2.5
--
-- WGSL 着色器按字段组合器（Shader Composer）
--
-- 根据 Visual 规格中声明的字段，自动拼装出对应的 WGSL 着色器代码。
--
-- Phase 2.2: 单 Pass 渲染（fill + border + radius）
-- Phase 2.5: 多 Pass 渲染（shadow_mask + blur_h + blur_v + composite main）
--
-- 公开 API：
--   nebula_compose_shader(opts) -> {
--     source,           -- 主 Pass WGSL 源码
--     features,         -- 特性列表
--     required_passes,  -- {"main"} 或 {"shadow_mask","blur_h","blur_v","main"}
--     shadow_mask_source,  -- 阴影遮罩 Pass WGSL（仅 has_shadow 时存在）
--     blur_h_source,       -- 水平模糊 Pass WGSL（仅 has_shadow 时存在）
--     blur_v_source,       -- 垂直模糊 Pass WGSL（仅 has_shadow 时存在）
--   }
--
-- opts = {
--   wgsl_struct    : string   — 已由 nebula_gen_uniform_layout 生成的 WGSL struct
--   has_radius     : boolean  — Visual 中是否存在 radius 字段
--   has_bg_color   : boolean  — Visual 中是否存在 bg_color 属性
--   has_border     : boolean  — Visual 中是否同时存在 border_color 和 border_width
--   has_shadow     : boolean  — Visual 中是否存在 shadow_color/shadow_offset/shadow_blur
--   struct_name    : string   — WGSL struct 名称（默认 "Uniforms"）
-- }
-- =============================================================================

-- ===== WGSL 片段表 =====
local WGSL_FRAGMENTS = {}

-- 通用头部：uniform 绑定 + VertexOutput 定义
WGSL_FRAGMENTS.binding = function(opts)
  local struct_name = opts.struct_name or "Uniforms"
  return ("\n@group(0) @binding(0) var<uniform> u: %s;\n"):format(struct_name)
end

WGSL_FRAGMENTS.vertex_output = function(_opts)
  return [[

struct VertexOutput {
  @builtin(position) clip_position: vec4<f32>,
}
]]
end

-- 全屏三角形顶点着色器（所有变体共用）
WGSL_FRAGMENTS.vs_main = function(_opts)
  return [[

// 全屏三角形：3 个顶点覆盖整个 NDC 空间
@vertex
fn vs_main(@builtin(vertex_index) vi: u32) -> VertexOutput {
  var pos = array<vec2<f32>, 3>(
    vec2<f32>(-1.0, -1.0),
    vec2<f32>( 3.0, -1.0),
    vec2<f32>(-1.0,  3.0),
  );
  var out: VertexOutput;
  out.clip_position = vec4<f32>(pos[vi], 0.0, 1.0);
  return out;
}
]]
end

-- SDF 函数：圆角矩形
WGSL_FRAGMENTS.sdf_rounded_rect = function(_opts)
  return [[

// SDF：圆角矩形的有符号距离函数
fn sdf_rounded_rect(p: vec2<f32>, b: vec2<f32>, r: f32) -> f32 {
  let q = abs(p) - b + vec2<f32>(r, r);
  return length(max(q, vec2<f32>(0.0, 0.0))) + min(max(q.x, q.y), 0.0) - r;
}
]]
end

-- SDF 函数：简单矩形（无圆角）
WGSL_FRAGMENTS.sdf_rect = function(_opts)
  return [[

// SDF：简单矩形距离函数（无圆角）
fn sdf_rect(p: vec2<f32>, b: vec2<f32>) -> f32 {
  let q = abs(p) - b;
  return length(max(q, vec2<f32>(0.0, 0.0))) + min(max(q.x, q.y), 0.0);
}
]]
end

-- Fragment 着色器主函数：根据特性组合
WGSL_FRAGMENTS.fs_main = function(opts)
  local lines = {}

  table.insert(lines, "\n@fragment")
  table.insert(lines, "fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {")
  table.insert(lines, "  // @builtin(position).xy 直接提供像素坐标（y 向下，原点在左上角）")
  table.insert(lines, "  let pixel = in.clip_position.xy;")
  table.insert(lines, "  let center = u.pos + u.size * 0.5;")
  table.insert(lines, "  let p = pixel - center;")
  table.insert(lines, "  let half_size = u.size * 0.5;")
  table.insert(lines, "")

  -- SDF 距离计算：根据 has_radius 选择函数
  if opts.has_radius then
    table.insert(lines, "  let dist = sdf_rounded_rect(p, half_size, u.radius);")
  else
    table.insert(lines, "  let dist = sdf_rect(p, half_size);")
  end

  table.insert(lines, "")
  table.insert(lines, "  // 抗锯齿：在边界附近平滑过渡（1px 宽度）")
  table.insert(lines, "  let aa = 1.0;")

  -- 填充逻辑
  if opts.has_bg_color then
    table.insert(lines, "  let fill_alpha  = 1.0 - smoothstep(-aa, aa, dist);")
  else
    table.insert(lines, "  let fill_alpha  = 1.0 - smoothstep(-aa, aa, dist);")
  end

  -- 边框逻辑
  if opts.has_border then
    table.insert(lines, "  let border_alpha = (1.0 - smoothstep(-aa, aa, dist + u.border_width)) - fill_alpha;")
  end

  table.insert(lines, "")

  -- 颜色合成
  if opts.has_bg_color then
    table.insert(lines, "  var color = u.bg_color * fill_alpha;")
  else
    table.insert(lines, "  var color = vec4<f32>(1.0, 1.0, 1.0, 1.0) * fill_alpha;")
  end

  if opts.has_border then
    table.insert(lines, "  color = color + u.border_color * border_alpha;")
  end

  table.insert(lines, "")
  table.insert(lines, "  if color.a < 0.001 {")
  table.insert(lines, "    discard;")
  table.insert(lines, "  }")
  table.insert(lines, "")
  table.insert(lines, "  return color;")
  table.insert(lines, "}")

  return table.concat(lines, "\n")
end


-- =============================================================================
-- ★ Phase 2.5: 阴影遮罩 Pass 着色器
--
-- 渲染组件的纯色形状（考虑圆角）到离屏纹理。
-- 使用与主 Pass 相同的 Uniforms struct（binding 0）。
-- 输出 shadow_color 乘以 SDF 遮罩的 alpha。
-- =============================================================================
local function gen_shadow_mask_shader(opts)
  local parts = {}

  -- 使用与主 Pass 相同的 Uniforms struct
  table.insert(parts, opts.wgsl_struct)
  table.insert(parts, WGSL_FRAGMENTS.binding(opts))
  table.insert(parts, WGSL_FRAGMENTS.vertex_output(opts))
  table.insert(parts, WGSL_FRAGMENTS.vs_main(opts))

  if opts.has_radius then
    table.insert(parts, WGSL_FRAGMENTS.sdf_rounded_rect(opts))
  else
    table.insert(parts, WGSL_FRAGMENTS.sdf_rect(opts))
  end

  -- Fragment：渲染偏移后的组件形状，输出 shadow_color * mask_alpha
  local lines = {}
  table.insert(lines, "\n@fragment")
  table.insert(lines, "fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {")
  table.insert(lines, "  let pixel = in.clip_position.xy;")
  table.insert(lines, "  // 阴影形状 = 组件形状 + shadow_offset")
  table.insert(lines, "  let shadow_center = u.pos + u.size * 0.5 + u.shadow_offset;")
  table.insert(lines, "  let p = pixel - shadow_center;")
  table.insert(lines, "  let half_size = u.size * 0.5;")
  if opts.has_radius then
    table.insert(lines, "  let dist = sdf_rounded_rect(p, half_size, u.radius);")
  else
    table.insert(lines, "  let dist = sdf_rect(p, half_size);")
  end
  table.insert(lines, "  let aa = 1.0;")
  table.insert(lines, "  let mask = 1.0 - smoothstep(-aa, aa, dist);")
  table.insert(lines, "  let color = u.shadow_color * mask;")
  table.insert(lines, "  if color.a < 0.001 {")
  table.insert(lines, "    discard;")
  table.insert(lines, "  }")
  table.insert(lines, "  return color;")
  table.insert(lines, "}")

  table.insert(parts, table.concat(lines, "\n"))
  return table.concat(parts, "")
end


-- =============================================================================
-- ★ Phase 2.5: 可分离高斯模糊 Pass 着色器
--
-- 使用独立的 BlurUniforms（direction + texel_size），
-- 从 binding 1 的纹理中采样并执行一维高斯模糊。
--
-- 高斯核使用 9 个采样点（sigma ≈ blur_radius / 3），
-- 利用双线性采样优化减少 fetch 次数。
-- =============================================================================
local function gen_blur_shader(opts)
  -- 模糊着色器使用独立的 BlurUniforms
  return [[
struct BlurUniforms {
  direction:  vec2<f32>,  // (1,0) 水平 或 (0,1) 垂直
  texel_size: vec2<f32>,  // 1.0 / texture_size
  blur_radius: f32,       // 模糊半径（像素）
  _pad0: f32,
  _pad1: f32,
  _pad2: f32,
}

@group(0) @binding(0) var<uniform> blur: BlurUniforms;
@group(0) @binding(1) var input_tex: texture_2d<f32>;
@group(0) @binding(2) var input_sampler: sampler;

struct VertexOutput {
  @builtin(position) clip_position: vec4<f32>,
}

@vertex
fn vs_main(@builtin(vertex_index) vi: u32) -> VertexOutput {
  var pos = array<vec2<f32>, 3>(
    vec2<f32>(-1.0, -1.0),
    vec2<f32>( 3.0, -1.0),
    vec2<f32>(-1.0,  3.0),
  );
  var out: VertexOutput;
  out.clip_position = vec4<f32>(pos[vi], 0.0, 1.0);
  return out;
}

// 一维高斯模糊（9 采样点，sigma = blur_radius / 3）
@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
  let uv = in.clip_position.xy * blur.texel_size;
  let step = blur.direction * blur.texel_size;

  // 预计算高斯权重（9 点，sigma ≈ 1.5 归一化到 blur_radius）
  let w0 = 0.2270270270;
  let w1 = 0.1945945946;
  let w2 = 0.1216216216;
  let w3 = 0.0540540541;
  let w4 = 0.0162162162;

  // blur_radius 缩放因子：将固定核映射到实际半径
  let scale = blur.blur_radius / 4.0;

  var color = textureSample(input_tex, input_sampler, uv) * w0;
  color += textureSample(input_tex, input_sampler, uv + step * 1.0 * scale) * w1;
  color += textureSample(input_tex, input_sampler, uv - step * 1.0 * scale) * w1;
  color += textureSample(input_tex, input_sampler, uv + step * 2.0 * scale) * w2;
  color += textureSample(input_tex, input_sampler, uv - step * 2.0 * scale) * w2;
  color += textureSample(input_tex, input_sampler, uv + step * 3.0 * scale) * w3;
  color += textureSample(input_tex, input_sampler, uv - step * 3.0 * scale) * w3;
  color += textureSample(input_tex, input_sampler, uv + step * 4.0 * scale) * w4;
  color += textureSample(input_tex, input_sampler, uv - step * 4.0 * scale) * w4;

  return color;
}
]]
end


-- =============================================================================
-- 公开 API：nebula_compose_shader(opts)
-- =============================================================================
function nebula_compose_shader(opts)
  assert(opts.wgsl_struct, "nebula_compose_shader: wgsl_struct required")

  local struct_name = opts.struct_name or "Uniforms"
  local has_radius   = opts.has_radius   or false
  local has_bg_color = opts.has_bg_color or false
  local has_border   = opts.has_border   or false
  local has_shadow   = opts.has_shadow   or false

  local compose_opts = {
    struct_name  = struct_name,
    has_radius   = has_radius,
    has_bg_color = has_bg_color,
    has_border   = has_border,
    has_shadow   = has_shadow,
    wgsl_struct  = opts.wgsl_struct,
  }

  -- 收集特性列表（用于编译期日志）
  local features = {}
  if has_radius   then table.insert(features, "radius")   end
  if has_bg_color then table.insert(features, "fill")     end
  if has_border   then table.insert(features, "border")   end
  if has_shadow   then table.insert(features, "shadow")   end

  -- 按固定顺序拼接主 Pass 片段
  local parts = {}
  table.insert(parts, opts.wgsl_struct)
  table.insert(parts, WGSL_FRAGMENTS.binding(compose_opts))
  table.insert(parts, WGSL_FRAGMENTS.vertex_output(compose_opts))
  table.insert(parts, WGSL_FRAGMENTS.vs_main(compose_opts))

  if has_radius then
    table.insert(parts, WGSL_FRAGMENTS.sdf_rounded_rect(compose_opts))
  else
    table.insert(parts, WGSL_FRAGMENTS.sdf_rect(compose_opts))
  end

  table.insert(parts, WGSL_FRAGMENTS.fs_main(compose_opts))

  local source = table.concat(parts, "")

  -- Phase 2.5: 如果有阴影，生成额外的 Pass 着色器
  local result = {
    source   = source,
    features = features,
  }

  if has_shadow then
    result.required_passes    = {"shadow_mask", "blur_h", "blur_v", "main"}
    result.shadow_mask_source = gen_shadow_mask_shader(compose_opts)
    result.blur_h_source      = gen_blur_shader(compose_opts)
    result.blur_v_source      = gen_blur_shader(compose_opts)  -- 同一着色器，方向由 uniform 控制
  else
    result.required_passes = {"main"}
  end

  return result
end

-- 返回模块标识，供 require 验证
return "nebula_shader_compose_v0.2_phase2.5"
