-- =============================================================================
-- derive/pipeline_factory.lua
-- Nebula GUI Compiler — Phase 2.5
--
-- 管线代码生成器（Pipeline Factory）
--
-- 根据给定的 Visual 规格，在编译期生成以下 Nelua 源码字符串：
--   · global <T>Pipeline = @record{ ... }
--   · function <T>Pipeline:init(renderer)
--   · function <T>Pipeline:update_uniforms(renderer, uniforms)
--   · function <T>Pipeline:draw(pass)
--
-- Phase 2.5 扩展：
--   当 has_shadow=true 时，<T>Pipeline 额外包含：
--     · shadow_mask_pipeline / blur_h_pipeline / blur_v_pipeline（子管线）
--     · 两张离屏纹理（shadow_tex_a/b）及其视图
--     · 采样器和模糊 BindGroup
--     · init() 中初始化全部子管线和离屏资源
--     · draw_shadow(encoder, main_view) 编排多 Pass 渲染
--
-- 公开 API：
--   nebula_gen_pipeline_source(spec)       -> string  (Nelua 源码)
--   nebula_gen_to_uniforms_typed(spec)     -> string  (仅 to_uniforms 方法)
--
-- spec 新增字段（Phase 2.5）：
--   has_shadow           : boolean
--   shadow_mask_source   : string  — 阴影遮罩 WGSL
--   blur_h_source        : string  — 水平模糊 WGSL
--   blur_v_source        : string  — 垂直模糊 WGSL
--   composite_source     : string  — 最终阴影合成 WGSL
-- =============================================================================

-- ===== 小工具：转义 WGSL 源码到 Nelua 字符串字面量 =====
local function escape_to_long_bracket(src)
  local level = 1
  while src:find("]" .. string.rep("=", level) .. "]", 1, true) do
    level = level + 1
  end
  local open  = "[" .. string.rep("=", level) .. "["
  local close = "]" .. string.rep("=", level) .. "]"
  return open .. src .. close
end

-- =============================================================================
-- 生成无阴影的简单 <T>Pipeline（与 Phase 2.3 一致）
-- =============================================================================
local function gen_pipeline_simple(base, uniforms_record, wgsl_source)
  local pipe = base .. "Pipeline"
  local lines = {}

  table.insert(lines, ("-- === Derived pipeline: %s (uniforms=%s, shadow=false) ==="):format(pipe, uniforms_record))

  -- record 定义
  table.insert(lines, ("global %s = @record{"):format(pipe))
  table.insert(lines,  "  pipeline:    WGPURenderPipeline,")
  table.insert(lines,  "  bind_layout: WGPUBindGroupLayout,")
  table.insert(lines,  "  uniform_buf: WGPUBuffer,")
  table.insert(lines,  "  bind_group:  WGPUBindGroup,")
  table.insert(lines,  "}")

  -- WGSL 源码常量
  local wgsl_const = "NEBULA_WGSL_" .. base:upper()
  table.insert(lines, ("local %s <comptime> = %s"):format(
    wgsl_const, escape_to_long_bracket(wgsl_source)))

  -- init
  table.insert(lines, ("function %s:init(renderer: *NebulaRenderer): boolean"):format(pipe))
  table.insert(lines,  "  local ok = nebula_pipeline_base_init(")
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

  -- update_uniforms
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

-- =============================================================================
-- ★ Phase 3.2.2: 生成带 Position/UV 顶点布局的 textured <T>Pipeline
--
-- 用于后续文本渲染管线：
--   · uniform buffer 继续承载布局/颜色/屏幕参数
--   · bind group 额外绑定字体 atlas 纹理与 sampler
--   · draw() 改为显式设置 vertex buffer
-- =============================================================================
local function gen_pipeline_textured_vertex(base, uniforms_record, wgsl_source)
  local pipe = base .. "Pipeline"
  local lines = {}

  table.insert(lines, ("-- === Derived pipeline: %s (uniforms=%s, textured_vertex=true) ==="):format(pipe, uniforms_record))
  table.insert(lines, ("global %s = @record{"):format(pipe))
  table.insert(lines,  "  pipeline:      WGPURenderPipeline,")
  table.insert(lines,  "  bind_layout:   WGPUBindGroupLayout,")
  table.insert(lines,  "  uniform_buf:   WGPUBuffer,")
  table.insert(lines,  "  bind_group:    WGPUBindGroup,")
  table.insert(lines,  "  vertex_buf:    WGPUBuffer,")
  table.insert(lines,  "  vertex_buf_size: uint64,")
  table.insert(lines,  "  vertex_count:  uint32,")
  table.insert(lines,  "}")

  local wgsl_const = "NEBULA_WGSL_" .. base:upper()
  table.insert(lines, ("local %s <comptime> = %s"):format(
    wgsl_const, escape_to_long_bracket(wgsl_source)))

  table.insert(lines, ("function %s:init(renderer: *NebulaRenderer): boolean"):format(pipe))
  table.insert(lines,  "  local attrs: [2]WGPUVertexAttribute")
  table.insert(lines,  "  local layout: WGPUVertexBufferLayout")
  table.insert(lines,  "  nebula_init_pos_uv_vertex_layout(&layout, &attrs[0])")
  table.insert(lines,  "  local ok = nebula_pipeline_textured_vertex_init(")
  table.insert(lines,  "    &self.pipeline,")
  table.insert(lines,  "    &self.bind_layout,")
  table.insert(lines,  "    &self.uniform_buf,")
  table.insert(lines,  "    renderer,")
  table.insert(lines, ("    %s,"):format(wgsl_const))
  table.insert(lines, ("    (@csize)(#%s),"):format(uniforms_record))
  table.insert(lines,  "    renderer.format,")
  table.insert(lines,  "    &layout,")
  table.insert(lines, ("    \"%s\""):format("nebula-" .. base:lower() .. "-textured"))
  table.insert(lines,  "  )")
  table.insert(lines,  "  if ok then")
  table.insert(lines,  "    self.bind_group = nilptr")
  table.insert(lines,  "    self.vertex_buf = nilptr")
  table.insert(lines,  "    self.vertex_buf_size = 0")
  table.insert(lines,  "    self.vertex_count = 0")
  table.insert(lines, ("    printf(\"wgpu: %s textured vertex pipeline created\\n\")"):format(base:lower()))
  table.insert(lines,  "  end")
  table.insert(lines,  "  return ok")
  table.insert(lines,  "end")

  table.insert(lines, ("function %s:update_uniforms(renderer: *NebulaRenderer, uniforms: *%s): void"):format(
    pipe, uniforms_record))
  table.insert(lines, ("  wgpuQueueWriteBuffer(renderer.queue, self.uniform_buf, 0, uniforms, #%s)"):format(
    uniforms_record))
  table.insert(lines,  "end")

  table.insert(lines, ("function %s:update_texture_binding(renderer: *NebulaRenderer, tex_view: WGPUTextureView, sampler: WGPUSampler): boolean"):format(pipe))
  table.insert(lines, ("  self.bind_group = nebula_create_textured_bind_group(renderer, self.bind_layout, self.uniform_buf, tex_view, sampler, (@csize)(#%s), \"%s\")"):format(
    uniforms_record, "nebula-" .. base:lower() .. "-textured-bg"))
  table.insert(lines,  "  return self.bind_group ~= nilptr")
  table.insert(lines,  "end")

  table.insert(lines, ("function %s:upload_vertices(renderer: *NebulaRenderer, data: pointer, size: csize, vertex_count: uint32): boolean"):format(pipe))
  table.insert(lines,  "  if self.vertex_buf ~= nilptr and self.vertex_buf_size < (@uint64)(size) then")
  table.insert(lines,  "    wgpuBufferRelease(self.vertex_buf)")
  table.insert(lines,  "    self.vertex_buf = nilptr")
  table.insert(lines,  "  end")
  table.insert(lines,  "  if self.vertex_buf == nilptr then")
  table.insert(lines, ("    if not nebula_create_vertex_buffer(&self.vertex_buf, renderer, data, size, \"%s\") then return false end"):format(
    "nebula-" .. base:lower() .. "-vbuf"))
  table.insert(lines,  "    self.vertex_buf_size = (@uint64)(size)")
  table.insert(lines,  "  elseif data ~= nilptr and size > 0 then")
  table.insert(lines,  "    wgpuQueueWriteBuffer(renderer.queue, self.vertex_buf, 0, data, size)")
  table.insert(lines,  "  end")
  table.insert(lines,  "  self.vertex_count = vertex_count")
  table.insert(lines,  "  return true")
  table.insert(lines,  "end")

  table.insert(lines, ("function %s:draw(pass: WGPURenderPassEncoder): void"):format(pipe))
  table.insert(lines,  "  if self.bind_group == nilptr or self.vertex_buf == nilptr or self.vertex_count == 0 then return end")
  table.insert(lines,  "  wgpuRenderPassEncoderSetPipeline(pass, self.pipeline)")
  table.insert(lines,  "  wgpuRenderPassEncoderSetBindGroup(pass, 0, self.bind_group, 0, nilptr)")
  table.insert(lines,  "  wgpuRenderPassEncoderSetVertexBuffer(pass, 0, self.vertex_buf, 0, self.vertex_buf_size)")
  table.insert(lines,  "  wgpuRenderPassEncoderDraw(pass, self.vertex_count, 1, 0, 0)")
  table.insert(lines,  "end")

  return table.concat(lines, "\n")
end

-- =============================================================================
-- ★ Phase 2.5: 生成带阴影的多 Sub-pipeline <T>Pipeline
--
-- 架构：
--   Pass 1 (shadow_mask): 渲染偏移后的组件 SDF 遮罩到 tex_a
--   Pass 2 (blur_h):      从 tex_a 采样，水平模糊输出到 tex_b
--   Pass 3 (blur_v):      从 tex_b 采样，垂直模糊输出到 tex_a
--   Pass 4 (main):        在 surface 上先合成 tex_a（模糊阴影），再绘制主组件
--
-- BlurUniforms 结构体（32 字节，std140 对齐）：
--   direction:  vec2<f32>  (offset 0)
--   texel_size: vec2<f32>  (offset 8)
--   blur_radius: f32       (offset 16)
--   _pad0: f32             (offset 20)
--   _pad1: f32             (offset 24)
--   _pad2: f32             (offset 28)
-- =============================================================================
local function gen_pipeline_shadow(base, uniforms_record, wgsl_source,
                                    shadow_mask_source, blur_h_source, blur_v_source, composite_source)
  local pipe = base .. "Pipeline"
  local L = {}  -- lines accumulator
  local function emit(s) table.insert(L, s) end

  emit(("-- === Derived pipeline: %s (uniforms=%s, shadow=true, multi-pass) ==="):format(pipe, uniforms_record))

  -- BlurUniforms record（编译期注入，所有阴影组件共享）
  emit("global NebulaBlurUniforms = @record{")
  emit("  direction:   Vec2,")
  emit("  texel_size:  Vec2,")
  emit("  blur_radius: float32,")
  emit("  _pad0: float32,")
  emit("  _pad1: float32,")
  emit("  _pad2: float32,")
  emit("}")
  emit("global NebulaCompositeUniforms = @record{")
  emit("  opacity: float32,")
  emit("  _pad0: float32,")
  emit("  _pad1: float32,")
  emit("  _pad2: float32,")
  emit("}")

  -- record 定义（扩展版）
  emit(("global %s = @record{"):format(pipe))
  emit("  -- 主管线（Phase 2.3 兼容）")
  emit("  pipeline:    WGPURenderPipeline,")
  emit("  bind_layout: WGPUBindGroupLayout,")
  emit("  uniform_buf: WGPUBuffer,")
  emit("  bind_group:  WGPUBindGroup,")
  emit("  -- Phase 2.5: 阴影子管线")
  emit("  shadow_mask_pipeline: WGPURenderPipeline,")
  emit("  shadow_mask_bgl:      WGPUBindGroupLayout,")
  emit("  shadow_mask_ubuf:     WGPUBuffer,")
  emit("  shadow_mask_bg:       WGPUBindGroup,")
  emit("  blur_h_pipeline:      WGPURenderPipeline,")
  emit("  blur_h_bgl:           WGPUBindGroupLayout,")
  emit("  blur_h_ubuf:          WGPUBuffer,")
  emit("  blur_v_pipeline:      WGPURenderPipeline,")
  emit("  blur_v_bgl:           WGPUBindGroupLayout,")
  emit("  blur_v_ubuf:          WGPUBuffer,")
  emit("  composite_pipeline:   WGPURenderPipeline,")
  emit("  composite_bgl:        WGPUBindGroupLayout,")
  emit("  composite_ubuf:       WGPUBuffer,")
  emit("  -- 离屏纹理 ping-pong")
  emit("  tex_a:      WGPUTexture,")
  emit("  tex_a_view: WGPUTextureView,")
  emit("  tex_b:      WGPUTexture,")
  emit("  tex_b_view: WGPUTextureView,")
  emit("  -- 采样器")
  emit("  sampler:    WGPUSampler,")
  emit("  -- 模糊 BindGroup（每帧重建或缓存）")
  emit("  blur_h_bg:  WGPUBindGroup,")
  emit("  blur_v_bg:  WGPUBindGroup,")
  emit("  composite_bg: WGPUBindGroup,")
  emit("  -- 尺寸缓存")
  emit("  rt_width:   uint32,")
  emit("  rt_height:  uint32,")
  emit("}")

  -- WGSL 源码常量
  local wgsl_main  = "NEBULA_WGSL_" .. base:upper()
  local wgsl_mask  = "NEBULA_WGSL_" .. base:upper() .. "_SHADOW_MASK"
  local wgsl_blur  = "NEBULA_WGSL_" .. base:upper() .. "_BLUR"
  local wgsl_comp  = "NEBULA_WGSL_" .. base:upper() .. "_COMPOSITE"
  emit(("local %s <comptime> = %s"):format(wgsl_main, escape_to_long_bracket(wgsl_source)))
  emit(("local %s <comptime> = %s"):format(wgsl_mask, escape_to_long_bracket(shadow_mask_source)))
  emit(("local %s <comptime> = %s"):format(wgsl_blur, escape_to_long_bracket(blur_h_source)))
  emit(("local %s <comptime> = %s"):format(wgsl_comp, escape_to_long_bracket(composite_source)))

  -- ===== init =====
  emit(("function %s:init(renderer: *NebulaRenderer, win_w: uint32, win_h: uint32): boolean"):format(pipe))
  emit("  self.rt_width  = win_w")
  emit("  self.rt_height = win_h")
  emit("")
  -- 主管线
  emit("  -- 1. 主管线（与无阴影版本一致）")
  emit("  local ok = nebula_pipeline_base_init(")
  emit("    &self.pipeline, &self.bind_layout, &self.uniform_buf, &self.bind_group,")
  emit(("    renderer, %s, (@csize)(#%s), \"%s\""):format(wgsl_main, uniforms_record, "nebula-" .. base:lower()))
  emit("  )")
  emit("  if not ok then return false end")
  emit(("  printf(\"wgpu: %s main pipeline created\\n\")"):format(base:lower()))
  emit("")
  -- 阴影遮罩管线（使用 base_init，因为它只需要 uniform buffer）
  emit("  -- 2. 阴影遮罩管线")
  emit("  ok = nebula_pipeline_base_init(")
  emit("    &self.shadow_mask_pipeline, &self.shadow_mask_bgl,")
  emit("    &self.shadow_mask_ubuf, &self.shadow_mask_bg,")
  emit(("    renderer, %s, (@csize)(#%s), \"%s\""):format(wgsl_mask, uniforms_record, "nebula-" .. base:lower() .. "-shadow-mask"))
  emit("  )")
  emit("  if not ok then return false end")
  emit(("  printf(\"wgpu: %s shadow mask pipeline created\\n\")"):format(base:lower()))
  emit("")
  -- 模糊管线（使用 textured_init，需要纹理+采样器绑定）
  emit("  -- 3. 水平模糊管线")
  emit("  ok = nebula_pipeline_textured_init(")
  emit("    &self.blur_h_pipeline, &self.blur_h_bgl, &self.blur_h_ubuf,")
  emit(("    renderer, %s, (@csize)(#NebulaBlurUniforms),"):format(wgsl_blur))
  emit("    renderer.format, \"" .. "nebula-" .. base:lower() .. "-blur-h\"")
  emit("  )")
  emit("  if not ok then return false end")
  emit(("  printf(\"wgpu: %s blur-h pipeline created\\n\")"):format(base:lower()))
  emit("")
  emit("  -- 4. 垂直模糊管线")
  emit("  ok = nebula_pipeline_textured_init(")
  emit("    &self.blur_v_pipeline, &self.blur_v_bgl, &self.blur_v_ubuf,")
  emit(("    renderer, %s, (@csize)(#NebulaBlurUniforms),"):format(wgsl_blur))
  emit("    renderer.format, \"" .. "nebula-" .. base:lower() .. "-blur-v\"")
  emit("  )")
  emit("  if not ok then return false end")
  emit(("  printf(\"wgpu: %s blur-v pipeline created\\n\")"):format(base:lower()))
  emit("")
  emit("  -- 5. 最终阴影合成管线")
  emit("  ok = nebula_pipeline_textured_init(")
  emit("    &self.composite_pipeline, &self.composite_bgl, &self.composite_ubuf,")
  emit(("    renderer, %s, (@csize)(#NebulaCompositeUniforms),"):format(wgsl_comp))
  emit("    renderer.format, \"" .. "nebula-" .. base:lower() .. "-composite\"")
  emit("  )")
  emit("  if not ok then return false end")
  emit(("  printf(\"wgpu: %s composite pipeline created\\n\")"):format(base:lower()))
  emit("")
  -- 离屏纹理
  emit("  -- 6. 离屏纹理 ping-pong")
  emit("  if not nebula_create_render_target(&self.tex_a, &self.tex_a_view, renderer, win_w, win_h, \"shadow-tex-a\") then return false end")
  emit("  if not nebula_create_render_target(&self.tex_b, &self.tex_b_view, renderer, win_w, win_h, \"shadow-tex-b\") then return false end")
  emit("")
  -- 采样器
  emit("  -- 7. 采样器")
  emit("  self.sampler = nebula_create_sampler(renderer)")
  emit("  if self.sampler == nilptr then return false end")
  emit("")
  -- 模糊 BindGroup
  emit("  -- 8. 采样 BindGroup（blur_h 从 tex_a 读，blur_v 从 tex_b 读，composite 从 tex_a 读）")
  emit("  self.blur_h_bg = nebula_create_blur_bind_group(renderer, self.blur_h_bgl, self.blur_h_ubuf, self.tex_a_view, self.sampler, (@csize)(#NebulaBlurUniforms), \"blur-h-bg\")")
  emit("  if self.blur_h_bg == nilptr then return false end")
  emit("  self.blur_v_bg = nebula_create_blur_bind_group(renderer, self.blur_v_bgl, self.blur_v_ubuf, self.tex_b_view, self.sampler, (@csize)(#NebulaBlurUniforms), \"blur-v-bg\")")
  emit("  if self.blur_v_bg == nilptr then return false end")
  emit("  self.composite_bg = nebula_create_blur_bind_group(renderer, self.composite_bgl, self.composite_ubuf, self.tex_a_view, self.sampler, (@csize)(#NebulaCompositeUniforms), \"composite-bg\")")
  emit("  if self.composite_bg == nilptr then return false end")
  emit("  local comp_u = NebulaCompositeUniforms{ opacity = 1.0, _pad0 = 0.0, _pad1 = 0.0, _pad2 = 0.0 }")
  emit("  wgpuQueueWriteBuffer(renderer.queue, self.composite_ubuf, 0, &comp_u, #NebulaCompositeUniforms)")
  emit("")
  emit(("  printf(\"wgpu: %s shadow pipeline fully initialized (%%dx%%d)\\n\", win_w, win_h)"):format(base:lower()))
  emit("  return true")
  emit("end")

  -- ===== update_uniforms（主 + 阴影遮罩共享同一份 uniforms） =====
  emit(("function %s:update_uniforms(renderer: *NebulaRenderer, uniforms: *%s): void"):format(pipe, uniforms_record))
  emit(("  wgpuQueueWriteBuffer(renderer.queue, self.uniform_buf, 0, uniforms, #%s)"):format(uniforms_record))
  emit(("  wgpuQueueWriteBuffer(renderer.queue, self.shadow_mask_ubuf, 0, uniforms, #%s)"):format(uniforms_record))
  emit("end")

  -- ===== draw_composite（在 surface 主 Pass 中合成模糊阴影） =====
  emit(("function %s:draw_composite(pass: WGPURenderPassEncoder): void"):format(pipe))
  emit("  wgpuRenderPassEncoderSetPipeline(pass, self.composite_pipeline)")
  emit("  wgpuRenderPassEncoderSetBindGroup(pass, 0, self.composite_bg, 0, nilptr)")
  emit("  wgpuRenderPassEncoderDraw(pass, 3, 1, 0, 0)")
  emit("end")

  -- ===== draw（单 Pass 主管线，向后兼容） =====
  emit(("function %s:draw(pass: WGPURenderPassEncoder): void"):format(pipe))
  emit("  wgpuRenderPassEncoderSetPipeline(pass, self.pipeline)")
  emit("  wgpuRenderPassEncoderSetBindGroup(pass, 0, self.bind_group, 0, nilptr)")
  emit("  wgpuRenderPassEncoderDraw(pass, 3, 1, 0, 0)")
  emit("end")

  -- ===== draw_shadow（多 Pass 阴影渲染编排） =====
  -- 此方法接收 encoder 和主 surface view，自行创建和管理多个 render pass
  emit(("function %s:draw_shadow(encoder: WGPUCommandEncoder, renderer: *NebulaRenderer, blur_radius: float32): void"):format(pipe))
  emit("  local tw = (@float32)(self.rt_width)")
  emit("  local th = (@float32)(self.rt_height)")
  emit("")
  emit("  -- Pass 1: 阴影遮罩 → tex_a")
  emit("  do")
  emit("    local att = WGPURenderPassColorAttachment{")
  emit("      nextInChain = nilptr,")
  emit("      view        = self.tex_a_view,")
  emit("      depthSlice  = 0xFFFFFFFF,")
  emit("      resolveTarget = nilptr,")
  emit("      loadOp  = WGPULoadOp_Clear,")
  emit("      storeOp = WGPUStoreOp_Store,")
  emit("      clearValue = WGPUColor{ r=0.0, g=0.0, b=0.0, a=0.0 },")
  emit("    }")
  emit("    local desc = WGPURenderPassDescriptor{")
  emit("      nextInChain            = nilptr,")
  emit("      label                  = wgpu_str_null(),")
  emit("      colorAttachmentCount   = 1,")
  emit("      colorAttachments       = &att,")
  emit("      depthStencilAttachment = nilptr,")
  emit("      occlusionQuerySet      = nilptr,")
  emit("      timestampWrites        = nilptr,")
  emit("    }")
  emit("    local pass = wgpuCommandEncoderBeginRenderPass(encoder, &desc)")
  emit("    wgpuRenderPassEncoderSetPipeline(pass, self.shadow_mask_pipeline)")
  emit("    wgpuRenderPassEncoderSetBindGroup(pass, 0, self.shadow_mask_bg, 0, nilptr)")
  emit("    wgpuRenderPassEncoderDraw(pass, 3, 1, 0, 0)")
  emit("    wgpuRenderPassEncoderEnd(pass)")
  emit("    wgpuRenderPassEncoderRelease(pass)")
  emit("  end")
  emit("")
  emit("  -- Pass 2: 水平模糊 tex_a → tex_b")
  emit("  do")
  emit("    local blur_u = NebulaBlurUniforms{")
  emit("      direction   = Vec2{ x = 1.0, y = 0.0 },")
  emit("      texel_size  = Vec2{ x = 1.0 / tw, y = 1.0 / th },")
  emit("      blur_radius = blur_radius,")
  emit("      _pad0 = 0.0, _pad1 = 0.0, _pad2 = 0.0,")
  emit("    }")
  emit("    wgpuQueueWriteBuffer(renderer.queue, self.blur_h_ubuf, 0, &blur_u, #NebulaBlurUniforms)")
  emit("    local att = WGPURenderPassColorAttachment{")
  emit("      nextInChain = nilptr,")
  emit("      view        = self.tex_b_view,")
  emit("      depthSlice  = 0xFFFFFFFF,")
  emit("      resolveTarget = nilptr,")
  emit("      loadOp  = WGPULoadOp_Clear,")
  emit("      storeOp = WGPUStoreOp_Store,")
  emit("      clearValue = WGPUColor{ r=0.0, g=0.0, b=0.0, a=0.0 },")
  emit("    }")
  emit("    local desc = WGPURenderPassDescriptor{")
  emit("      nextInChain            = nilptr,")
  emit("      label                  = wgpu_str_null(),")
  emit("      colorAttachmentCount   = 1,")
  emit("      colorAttachments       = &att,")
  emit("      depthStencilAttachment = nilptr,")
  emit("      occlusionQuerySet      = nilptr,")
  emit("      timestampWrites        = nilptr,")
  emit("    }")
  emit("    local pass = wgpuCommandEncoderBeginRenderPass(encoder, &desc)")
  emit("    wgpuRenderPassEncoderSetPipeline(pass, self.blur_h_pipeline)")
  emit("    wgpuRenderPassEncoderSetBindGroup(pass, 0, self.blur_h_bg, 0, nilptr)")
  emit("    wgpuRenderPassEncoderDraw(pass, 3, 1, 0, 0)")
  emit("    wgpuRenderPassEncoderEnd(pass)")
  emit("    wgpuRenderPassEncoderRelease(pass)")
  emit("  end")
  emit("")
  emit("  -- Pass 3: 垂直模糊 tex_b → tex_a")
  emit("  do")
  emit("    local blur_u = NebulaBlurUniforms{")
  emit("      direction   = Vec2{ x = 0.0, y = 1.0 },")
  emit("      texel_size  = Vec2{ x = 1.0 / tw, y = 1.0 / th },")
  emit("      blur_radius = blur_radius,")
  emit("      _pad0 = 0.0, _pad1 = 0.0, _pad2 = 0.0,")
  emit("    }")
  emit("    wgpuQueueWriteBuffer(renderer.queue, self.blur_v_ubuf, 0, &blur_u, #NebulaBlurUniforms)")
  emit("    local att = WGPURenderPassColorAttachment{")
  emit("      nextInChain = nilptr,")
  emit("      view        = self.tex_a_view,")
  emit("      depthSlice  = 0xFFFFFFFF,")
  emit("      resolveTarget = nilptr,")
  emit("      loadOp  = WGPULoadOp_Clear,")
  emit("      storeOp = WGPUStoreOp_Store,")
  emit("      clearValue = WGPUColor{ r=0.0, g=0.0, b=0.0, a=0.0 },")
  emit("    }")
  emit("    local desc = WGPURenderPassDescriptor{")
  emit("      nextInChain            = nilptr,")
  emit("      label                  = wgpu_str_null(),")
  emit("      colorAttachmentCount   = 1,")
  emit("      colorAttachments       = &att,")
  emit("      depthStencilAttachment = nilptr,")
  emit("      occlusionQuerySet      = nilptr,")
  emit("      timestampWrites        = nilptr,")
  emit("    }")
  emit("    local pass = wgpuCommandEncoderBeginRenderPass(encoder, &desc)")
  emit("    wgpuRenderPassEncoderSetPipeline(pass, self.blur_v_pipeline)")
  emit("    wgpuRenderPassEncoderSetBindGroup(pass, 0, self.blur_v_bg, 0, nilptr)")
  emit("    wgpuRenderPassEncoderDraw(pass, 3, 1, 0, 0)")
  emit("    wgpuRenderPassEncoderEnd(pass)")
  emit("    wgpuRenderPassEncoderRelease(pass)")
  emit("  end")
  emit("")
  emit("  -- Pass 4: 主 surface pass 由调用者创建，并在其中先调用 draw_composite")
  emit("  -- 再调用 draw 绘制主组件本体。这样多个组件仍可共享同一个 surface pass。")
  emit("end")

  return table.concat(L, "\n")
end


-- =============================================================================
-- 主入口：生成完整的 <T>Pipeline 源码
-- =============================================================================
function nebula_gen_pipeline_source(spec)
  assert(spec.base,            "nebula_gen_pipeline_source: spec.base required")
  assert(spec.uniforms_record, "nebula_gen_pipeline_source: spec.uniforms_record required")
  assert(spec.wgsl_source,     "nebula_gen_pipeline_source: spec.wgsl_source required")

  if spec.has_shadow then
    assert(spec.shadow_mask_source, "nebula_gen_pipeline_source: shadow_mask_source required when has_shadow")
    assert(spec.blur_h_source,      "nebula_gen_pipeline_source: blur_h_source required when has_shadow")
    assert(spec.blur_v_source,      "nebula_gen_pipeline_source: blur_v_source required when has_shadow")
    assert(spec.composite_source,   "nebula_gen_pipeline_source: composite_source required when has_shadow")
    return gen_pipeline_shadow(
      spec.base, spec.uniforms_record, spec.wgsl_source,
      spec.shadow_mask_source, spec.blur_h_source, spec.blur_v_source, spec.composite_source)
  elseif spec.textured and spec.vertex_layout == "pos_uv" then
    return gen_pipeline_textured_vertex(spec.base, spec.uniforms_record, spec.wgsl_source)
  else
    return gen_pipeline_simple(spec.base, spec.uniforms_record, spec.wgsl_source)
  end
end


-- =============================================================================
-- 生成强类型的 <T>Context:to_uniforms 方法
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
      table.insert(lines, ("    %s = 0.0,"):format(f.name))
    elseif f.name == "viewport" then
      table.insert(lines,  "    viewport = Vec2{ x = vw, y = vh },")
    elseif prop_set[f.name] then
      table.insert(lines, ("    %s = self.current_%s,"):format(f.name, f.name))
    elseif base_set[f.name] then
      table.insert(lines, ("    %s = self.visual.%s,"):format(f.name, f.name))
    elseif f.name == "radius" then
      table.insert(lines,  "    radius = 0.0,")
    else
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
return "nebula_pipeline_factory_v0.3_phase3.2.2"
