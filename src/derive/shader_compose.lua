-- =============================================================================
-- derive/shader_compose.lua
-- Nebula GUI Compiler — Phase 2.2
--
-- WGSL 着色器按字段组合器（Shader Composer）
--
-- 根据 Visual 规格中声明的字段，自动拼装出对应的 WGSL 着色器代码。
-- 本模块仅处理单 Pass 渲染；多 Pass（如 Shadow）留给 Phase 2.3。
--
-- 公开 API：
--   nebula_compose_shader(opts) -> { source, features, required_passes }
--
-- opts = {
--   wgsl_struct    : string   — 已由 nebula_gen_uniform_layout 生成的 WGSL struct
--   has_radius     : boolean  — Visual 中是否存在 radius 字段
--   has_bg_color   : boolean  — Visual 中是否存在 bg_color 属性
--   has_border     : boolean  — Visual 中是否同时存在 border_color 和 border_width
--   struct_name    : string   — WGSL struct 名称（默认 "Uniforms"）
-- }
-- =============================================================================

-- ===== WGSL 片段表 =====
-- 每个片段是一个返回 WGSL 代码段的函数，接收 opts 以支持条件化

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
    -- 无 bg_color 时使用白色作为默认填充
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
    -- 无 bg_color 时使用纯白填充
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
-- 公开 API：nebula_compose_shader(opts)
-- =============================================================================
function nebula_compose_shader(opts)
  assert(opts.wgsl_struct, "nebula_compose_shader: wgsl_struct required")

  local struct_name = opts.struct_name or "Uniforms"
  local has_radius   = opts.has_radius   or false
  local has_bg_color = opts.has_bg_color or false
  local has_border   = opts.has_border   or false

  local compose_opts = {
    struct_name = struct_name,
    has_radius  = has_radius,
    has_bg_color = has_bg_color,
    has_border  = has_border,
  }

  -- 收集特性列表（用于编译期日志）
  local features = {}
  if has_radius   then table.insert(features, "radius")   end
  if has_bg_color then table.insert(features, "fill")     end
  if has_border   then table.insert(features, "border")   end

  -- 按固定顺序拼接片段：
  --   1. struct（外部传入）
  --   2. binding
  --   3. vertex_output
  --   4. vs_main
  --   5. SDF 函数（按需）
  --   6. fs_main（内部按需组合）
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

  return {
    source          = source,
    features        = features,
    required_passes = {"main"},   -- Phase 2.2 仅支持单 Pass
  }
end

-- 返回模块标识，供 require 验证
return "nebula_shader_compose_v0.1"
