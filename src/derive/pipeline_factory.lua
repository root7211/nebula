-- =============================================================================
-- derive/pipeline_factory.lua
-- Nebula GUI Compiler — Phase 2.3.2
--
-- 管线代码生成器（Pipeline Factory）
--
-- 根据给定的 Visual 规格，在编译期生成以下 Nelua 源码字符串：
--   · global <T>Pipeline = @record{ ... }
--   · function <T>Pipeline:init(renderer)
--   · function <T>Pipeline:update_uniforms(renderer, uniforms)
--   · function <T>Pipeline:draw(pass)
--
-- 同时辅助生成强类型 to_uniforms 方法的源码，返回紧凑布局 <T>Uniforms
-- （无 force_viewport_align，遵循 std140 原生对齐）。
--
-- 所有生成的 <T>Pipeline:init 都委托调用 nebula_pipeline_base_init（由
-- renderer.nelua 提供），从而共享统一的 WGPU 样板代码。
--
-- 公开 API：
--   nebula_gen_pipeline_source(spec)       -> string  (Nelua 源码)
--   nebula_gen_to_uniforms_typed(spec)     -> string  (仅 to_uniforms 方法)
--
-- spec = {
--   base            : string  — 派生基名（如 "Button"），将生成 <base>Pipeline
--   visual_type     : string  — 原始 Visual 记录名（如 "ButtonVisual"）
--   uniforms_record : string  — 派生 uniforms 记录名（如 "ButtonUniforms"）
--   wgsl_source     : string  — 完整 WGSL 着色器源码
--   uniform_size    : number  — uniforms 字节大小（紧凑模式）
--   layout_fields   : table   — nebula_gen_uniform_layout 返回的 fields 数组
--   base_fields     : table   — Visual 中的非状态字段（如 pos / size / radius）
--   all_props       : table   — 动画属性列表（如 bg_color / border_color / ...）
-- }
-- =============================================================================

-- ===== 小工具：转义 WGSL 源码到 Nelua 字符串字面量 =====
-- Nelua 支持 Lua 风格的长括号字符串 [[...]]，但如果 WGSL 内部出现 ]] 会破坏
-- 定界符。最安全的做法是使用 [=[ ... ]=] 长括号（源码不可能包含 ]=]）。
local function escape_to_long_bracket(src)
  -- 若源码恰好包含 ]=] 则升到 [==[...]==]；实际 WGSL 永远不会包含，但保持健壮。
  local level = 1
  while src:find("]" .. string.rep("=", level) .. "]", 1, true) do
    level = level + 1
  end
  local open  = "[" .. string.rep("=", level) .. "["
  local close = "]" .. string.rep("=", level) .. "]"
  return open .. src .. close
end

-- ===== 生成 <T>Pipeline 结构体 + 方法 =====
local function gen_pipeline_record(base, uniforms_record, wgsl_source)
  local pipe = base .. "Pipeline"
  local lines = {}

  table.insert(lines, ("-- === Derived pipeline: %s (uniforms=%s) ==="):format(pipe, uniforms_record))

  -- record 定义
  table.insert(lines, ("global %s = @record{"):format(pipe))
  table.insert(lines,  "  pipeline:    WGPURenderPipeline,")
  table.insert(lines,  "  bind_layout: WGPUBindGroupLayout,")
  table.insert(lines,  "  uniform_buf: WGPUBuffer,")
  table.insert(lines,  "  bind_group:  WGPUBindGroup,")
  table.insert(lines,  "}")

  -- WGSL 源码常量（comptime 字符串）
  local wgsl_const = "NEBULA_WGSL_" .. base:upper()
  table.insert(lines, ("local %s <comptime> = %s"):format(
    wgsl_const, escape_to_long_bracket(wgsl_source)))

  -- init：委托 nebula_pipeline_base_init
  table.insert(lines, ("function %s:init(renderer: *NebulaRenderer): boolean"):format(pipe))
  table.insert(lines, ("  local ok = nebula_pipeline_base_init("))
  table.insert(lines,  "    &self.pipeline,")
  table.insert(lines,  "    &self.bind_layout,")
  table.insert(lines,  "    &self.uniform_buf,")
  table.insert(lines,  "    &self.bind_group,")
  table.insert(lines,  "    renderer,")
  table.insert(lines, ("    %s,"):format(wgsl_const))
  table.insert(lines, ("    (@csize)(#%s),"):format(uniforms_record))
  table.insert(lines, ("    \"%s\""):format("nebula-" .. base:lower()))
  table.insert(lines,  "  )")
  table.insert(lines, ("  if ok then printf(\"wgpu: %s pipeline created\\n\") end"):format(base:lower()))
  table.insert(lines,  "  return ok")
  table.insert(lines,  "end")

  -- update_uniforms：强类型 <T>Uniforms 指针
  table.insert(lines, ("function %s:update_uniforms(renderer: *NebulaRenderer, uniforms: *%s): void"):format(
    pipe, uniforms_record))
  table.insert(lines, ("  wgpuQueueWriteBuffer(renderer.queue, self.uniform_buf, 0, uniforms, #%s)"):format(
    uniforms_record))
  table.insert(lines,  "end")

  -- draw
  table.insert(lines, ("function %s:draw(pass: WGPURenderPassEncoder): void"):format(pipe))
  table.insert(lines,  "  wgpuRenderPassEncoderSetPipeline(pass, self.pipeline)")
  table.insert(lines,  "  wgpuRenderPassEncoderSetBindGroup(pass, 0, self.bind_group, 0, nilptr)")
  table.insert(lines,  "  wgpuRenderPassEncoderDraw(pass, 3, 1, 0, 0)  -- 全屏三角形")
  table.insert(lines,  "end")

  return table.concat(lines, "\n")
end

-- ===== 主入口：生成完整的 <T>Pipeline 源码 =====
function nebula_gen_pipeline_source(spec)
  assert(spec.base,            "nebula_gen_pipeline_source: spec.base required")
  assert(spec.uniforms_record, "nebula_gen_pipeline_source: spec.uniforms_record required")
  assert(spec.wgsl_source,     "nebula_gen_pipeline_source: spec.wgsl_source required")

  return gen_pipeline_record(spec.base, spec.uniforms_record, spec.wgsl_source)
end

-- =============================================================================
-- ★ 2.3.2 辅助：生成强类型的 <T>Context:to_uniforms 方法
--
-- 与 nebula_core 中硬编码的 NebulaRectUniforms 版本不同，这里严格根据
-- layout_fields 逐字段 emit，保证与紧凑布局 <T>Uniforms 一一对应，既不
-- 写死字段名，也不依赖 _pad0 / _pad6 等命名约定。
--
-- 规则：
--   · 所有 is_pad=true 的字段 —— 全部填 0.0（保持 C ABI 可移植）
--   · "viewport"        —— 由 to_uniforms(vw, vh) 参数构造 Vec2
--   · "radius"          —— 优先 self.visual.radius；Visual 无 radius 时填 0.0
--   · 其它 base 字段     —— 直接从 self.visual.<name> 读取
--   · 动画属性           —— 读取 self.current_<name>（由 Context 插值好）
-- =============================================================================
function nebula_gen_to_uniforms_typed(spec)
  local ctx             = spec.base .. "Context"
  local uniforms_record = spec.uniforms_record
  local layout_fields   = spec.layout_fields
  local base_fields     = spec.base_fields
  local all_props       = spec.all_props

  -- 构建字段查找集
  local base_set = {}
  for _, f in ipairs(base_fields) do base_set[f.name] = f end
  local prop_set = {}
  for _, p in ipairs(all_props) do prop_set[p.name] = p end

  local lines = {}
  table.insert(lines, ("function %s:to_uniforms(vw: float32, vh: float32): %s"):format(
    ctx, uniforms_record))
  table.insert(lines, ("  return %s{"):format(uniforms_record))

  for _, f in ipairs(layout_fields) do
    if f.is_pad then
      -- padding 字段：保持紧凑布局的 ABI 一致性，全部零值
      table.insert(lines, ("    %s = 0.0,"):format(f.name))
    elseif f.name == "viewport" then
      table.insert(lines,  "    viewport = Vec2{ x = vw, y = vh },")
    elseif prop_set[f.name] then
      -- 动画属性：使用已在 update() 中插值好的 current_<name>
      table.insert(lines, ("    %s = self.current_%s,"):format(f.name, f.name))
    elseif base_set[f.name] then
      -- base 字段：直接取 self.visual
      table.insert(lines, ("    %s = self.visual.%s,"):format(f.name, f.name))
    elseif f.name == "radius" then
      -- Visual 未声明 radius 时用 0.0 兜底（与旧 to_uniforms 行为一致）
      table.insert(lines,  "    radius = 0.0,")
    else
      -- 未知字段，零值兜底（不应到达此分支）
      if f.type == "Color" then
        table.insert(lines, ("    %s = Color{r=0.0,g=0.0,b=0.0,a=0.0},"):format(f.name))
      elseif f.type == "Vec2" then
        table.insert(lines, ("    %s = Vec2{x=0.0,y=0.0},"):format(f.name))
      else
        table.insert(lines, ("    %s = 0.0,"):format(f.name))
      end
    end
  end

  table.insert(lines,  "  }")
  table.insert(lines,  "end")
  return table.concat(lines, "\n")
end

-- 返回模块标识
return "nebula_pipeline_factory_v0.1"
