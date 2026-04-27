-- =============================================================================
-- derive/pipeline_factory.lua
-- Nebula GUI Compiler — Phase 3.7
--
-- 管线代码生成器（Pipeline Factory）
--
-- Phase 3.7: 收敛为三条显式路径（删除死代码）：
--   · gen_pipeline_standard_instanced  — 所有标准 Visual 的默认路径
--   · gen_pipeline_textured_vertex     — 文本 SDF 路径
--   · gen_pipeline_shadow              — 阴影多 Pass 路径
--
-- 已删除（Phase 3.7 死代码清理）：
--   · gen_pipeline_simple              — Phase 2.3 占位符路径
--   · gen_pipeline_instanced           — Phase 3.3 遗留路径
--
-- 公开 API：
--   nebula_gen_pipeline_source(spec)       -> string  (Nelua 源码)
--   nebula_gen_to_uniforms_typed(spec)     -> string  (仅 to_uniforms 方法)
--
-- spec 字段：
--   has_shadow           : boolean  — 选择 shadow_multipass 路径
--   standard_instanced   : boolean  — 选择 standard_instanced 路径（默认）
--   textured             : boolean  — 选择 textured_vertex 路径
--   shadow_mask_source   : string   — 阴影遮罩 WGSL
--   blur_h_source        : string   — 水平模糊 WGSL
--   blur_v_source        : string   — 垂直模糊 WGSL
--   composite_source     : string   — 最终阴影合成 WGSL
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

  table.insert(lines, ("function %s:draw_buffer(pass: WGPURenderPassEncoder, vertex_buf: WGPUBuffer, vertex_buf_size: uint64, vertex_count: uint32): void"):format(pipe))
  table.insert(lines,  "  if self.bind_group == nilptr or vertex_buf == nilptr or vertex_count == 0 then return end")
  table.insert(lines,  "  wgpuRenderPassEncoderSetPipeline(pass, self.pipeline)")
  table.insert(lines,  "  wgpuRenderPassEncoderSetBindGroup(pass, 0, self.bind_group, 0, nilptr)")
  table.insert(lines,  "  wgpuRenderPassEncoderSetVertexBuffer(pass, 0, vertex_buf, 0, vertex_buf_size)")
  table.insert(lines,  "  wgpuRenderPassEncoderDraw(pass, vertex_count, 1, 0, 0)")
  table.insert(lines,  "end")

  table.insert(lines, ("function %s:draw(pass: WGPURenderPassEncoder): void"):format(pipe))
  table.insert(lines,  "  self:draw_buffer(pass, self.vertex_buf, self.vertex_buf_size, self.vertex_count)")
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
-- ★ Phase 3.5.1: 为标准 Visual 类型生成 Instanced Pipeline
--
-- 与 gen_pipeline_instanced 的区别：
--   · 本函数的 instance_record 就是 <T>Uniforms（由 nebula_gen_uniform_layout 生成）
--   · 这样 to_uniforms() 生成的数据可以直接上传到 Storage Buffer，实现零拷贝
--   · 生成的管线名称为 <T>Pipeline（与原 simple 路径一致），新增 upload/draw_instanced/draw_single
--   · 单实例场景使用 update_viewport + upload + draw_instanced，或使用 draw_single 便捷方法
-- =============================================================================
local function gen_pipeline_standard_instanced(base, uniforms_record, wgsl_source, max_instances)
  local pipe = base .. "Pipeline"
  local L = {}
  local function emit(s) table.insert(L, s) end

  max_instances = max_instances or 128

  emit(("-- === Derived standard-instanced pipeline: %s (uniforms=%s, max=%d) ==="):format(
    pipe, uniforms_record, max_instances))

  -- record 定义：兼容 simple 路径的字段，同时新增 storage buffer 支持
  emit(("global %s = @record{"):format(pipe))
  emit("  pipeline:      WGPURenderPipeline,")
  emit("  bind_layout:   WGPUBindGroupLayout,")
  emit("  -- binding 0: viewport uniform（16 字节）")
  emit("  uniform_buf:   WGPUBuffer,")
  emit("  -- binding 1: Storage Buffer（所有实例的 <T>Uniforms 数组）")
  emit("  storage_buf:   WGPUBuffer,")
  emit("  storage_size:  uint64,")
  emit("  bind_group:    WGPUBindGroup,")
  emit("  max_instances: uint32,")
  emit("}")

  -- WGSL 源码常量
  local wgsl_const = "NEBULA_WGSL_" .. base:upper() .. "_INST"
  emit(("local %s <comptime> = %s"):format(wgsl_const, escape_to_long_bracket(wgsl_source)))

  -- ===== init =====
  emit(("function %s:init(renderer: *NebulaRenderer, max_inst: uint32): boolean"):format(pipe))
  emit("  self.max_instances = max_inst")
  emit("")
  emit("  -- 1. Viewport Uniform Buffer（16 字节）")
  emit("  local vp_desc = WGPUBufferDescriptor{")
  emit("    nextInChain      = nilptr,")
  emit(("    label            = wgpu_str(\"%s-vp\"),"):format("nebula-" .. base:lower() .. "-si"))
  emit("    usage            = (@uint32)(WGPUBufferUsage_Uniform) | (@uint32)(WGPUBufferUsage_CopyDst),")
  emit("    size             = 16,")
  emit("    mappedAtCreation = false,")
  emit("  }")
  emit("  self.uniform_buf = wgpuDeviceCreateBuffer(renderer.device, &vp_desc)")
  emit("  if self.uniform_buf == nilptr then")
  emit(("    printf(\"wgpu: %s si: failed to create vp uniform\\n\")\n    return false"):format(base:lower()))
  emit("  end")
  emit("")
  emit("  -- 2. Storage Buffer（max_instances * sizeof(<T>Uniforms)）")
  emit(("  self.storage_size = (@uint64)(max_inst) * (@uint64)(#%s)"):format(uniforms_record))
  emit("  local sb_desc = WGPUBufferDescriptor{")
  emit("    nextInChain      = nilptr,")
  emit(("    label            = wgpu_str(\"%s-sb\"),"):format("nebula-" .. base:lower() .. "-si"))
  emit("    usage            = (@uint32)(WGPUBufferUsage_Storage) | (@uint32)(WGPUBufferUsage_CopyDst),")
  emit("    size             = self.storage_size,")
  emit("    mappedAtCreation = false,")
  emit("  }")
  emit("  self.storage_buf = wgpuDeviceCreateBuffer(renderer.device, &sb_desc)")
  emit("  if self.storage_buf == nilptr then")
  emit(("    printf(\"wgpu: %s si: failed to create storage buffer\\n\")\n    return false"):format(base:lower()))
  emit("  end")
  emit("")
  emit("  -- 3. BindGroupLayout（binding 0: uniform, binding 1: read-only storage）")
  emit("  local entries: [2]WGPUBindGroupLayoutEntry")
  emit("  entries[0] = WGPUBindGroupLayoutEntry{")
  emit("    nextInChain = nilptr, binding = 0,")
  emit("    visibility  = (@uint64)(WGPUShaderStage_Vertex) | (@uint64)(WGPUShaderStage_Fragment),")
  emit("    buffer      = { nextInChain = nilptr, type = (@uint32)(WGPUBufferBindingType_Uniform), hasDynamicOffset = 0, minBindingSize = 16 },")
  emit("    sampler = { nextInChain = nilptr, type = 0 }, texture = { nextInChain = nilptr, sampleType = 0, viewDimension = 0, multisampled = 0 },")
  emit("    storageTexture = { nextInChain = nilptr, access = 0, format = WGPUTextureFormat_Undefined, viewDimension = 0 },")
  emit("  }")
  emit("  entries[1] = WGPUBindGroupLayoutEntry{")
  emit("    nextInChain = nilptr, binding = 1,")
  emit("    visibility  = (@uint64)(WGPUShaderStage_Vertex) | (@uint64)(WGPUShaderStage_Fragment),  -- BUG-4 fix: vertex shader also reads instances[inst]")
  emit("    buffer      = { nextInChain = nilptr, type = (@uint32)(WGPUBufferBindingType_ReadOnlyStorage), hasDynamicOffset = 0, minBindingSize = 0 },")
  emit("    sampler = { nextInChain = nilptr, type = 0 }, texture = { nextInChain = nilptr, sampleType = 0, viewDimension = 0, multisampled = 0 },")
  emit("    storageTexture = { nextInChain = nilptr, access = 0, format = WGPUTextureFormat_Undefined, viewDimension = 0 },")
  emit("  }")
  emit("  local bgl_desc = WGPUBindGroupLayoutDescriptor{")
  emit("    nextInChain = nilptr,")
  emit(("    label       = wgpu_str(\"%s-bgl\"),"):format("nebula-" .. base:lower() .. "-si"))
  emit("    entryCount  = 2, entries = &entries[0],")
  emit("  }")
  emit("  self.bind_layout = wgpuDeviceCreateBindGroupLayout(renderer.device, &bgl_desc)")
  emit("  if self.bind_layout == nilptr then")
  emit(("    printf(\"wgpu: %s si: failed to create bgl\\n\")\n    return false"):format(base:lower()))
  emit("  end")
  emit("")
  emit("  -- 4. BindGroup")
  emit("  local bg_entries: [2]WGPUBindGroupEntry")
  emit("  bg_entries[0] = WGPUBindGroupEntry{")
  emit("    nextInChain = nilptr, binding = 0,")
  emit("    buffer = self.uniform_buf, offset = 0, size = 16,")
  emit("    sampler = nilptr, textureView = nilptr,")
  emit("  }")
  emit("  bg_entries[1] = WGPUBindGroupEntry{")
  emit("    nextInChain = nilptr, binding = 1,")
  emit("    buffer = self.storage_buf, offset = 0, size = self.storage_size,")
  emit("    sampler = nilptr, textureView = nilptr,")
  emit("  }")
  emit("  local bg_desc = WGPUBindGroupDescriptor{")
  emit("    nextInChain = nilptr,")
  emit(("    label       = wgpu_str(\"%s-bg\"),"):format("nebula-" .. base:lower() .. "-si"))
  emit("    layout = self.bind_layout, entryCount = 2, entries = &bg_entries[0],")
  emit("  }")
  emit("  self.bind_group = wgpuDeviceCreateBindGroup(renderer.device, &bg_desc)")
  emit("  if self.bind_group == nilptr then")
  emit(("    printf(\"wgpu: %s si: failed to create bind group\\n\")\n    return false"):format(base:lower()))
  emit("  end")
  emit("")
  emit("  -- 5. 着色器模块")
  emit("  local wgsl_src = WGPUShaderSourceWGSL{")
  emit("    chain = WGPUChainedStruct{ next = nilptr, sType = WGPUSType_ShaderSourceWGSL },")
  emit(("    code  = wgpu_str(%s),"):format(wgsl_const))
  emit("  }")
  emit("  local shader_desc = WGPUShaderModuleDescriptor{")
  emit("    nextInChain = (@*WGPUChainedStruct)(&wgsl_src),")
  emit(("    label       = wgpu_str(\"%s-si-shader\"),"):format("nebula-" .. base:lower()))
  emit("  }")
  emit("  local shader = wgpuDeviceCreateShaderModule(renderer.device, &shader_desc)")
  emit("  if shader == nilptr then")
  emit(("    printf(\"wgpu: %s si: failed to create shader\\n\")\n    return false"):format(base:lower()))
  emit("  end")
  emit("")
  emit("  -- 6. PipelineLayout")
  emit("  local pl_desc = WGPUPipelineLayoutDescriptor{")
  emit("    nextInChain = nilptr,")
  emit(("    label       = wgpu_str(\"%s-si-pl\"),"):format("nebula-" .. base:lower()))
  emit("    bindGroupLayoutCount = 1, bindGroupLayouts = &self.bind_layout,")
  emit("  }")
  emit("  local pipeline_layout = wgpuDeviceCreatePipelineLayout(renderer.device, &pl_desc)")
  emit("")
  emit("  -- 7. Alpha 混合状态")
  emit("  local blend_state = WGPUBlendState{")
  emit("    color = WGPUBlendComponent{ operation = WGPUBlendOperation_Add, srcFactor = WGPUBlendFactor_SrcAlpha, dstFactor = WGPUBlendFactor_OneMinusSrcAlpha },")
  emit("    alpha = WGPUBlendComponent{ operation = WGPUBlendOperation_Add, srcFactor = WGPUBlendFactor_One, dstFactor = WGPUBlendFactor_OneMinusSrcAlpha },")
  emit("  }")
  emit("  local color_target = WGPUColorTargetState{")
  emit("    nextInChain = nilptr, format = renderer.format, blend = &blend_state,")
  emit("    writeMask   = (@uint32)(WGPUColorWriteMask_All),")
  emit("  }")
  emit("  local frag_state = WGPUFragmentState{")
  emit("    nextInChain = nilptr, module = shader, entryPoint = wgpu_str(\"fs_main\"),")
  emit("    constantCount = 0, constants = nilptr, targetCount = 1, targets = &color_target,")
  emit("  }")
  emit("")
  emit("  -- 8. RenderPipeline（无顶点缓冲，通过 instance_index 驱动）")
  emit("  local rp_desc = WGPURenderPipelineDescriptor{")
  emit("    nextInChain = nilptr,")
  emit(("    label       = wgpu_str(\"%s-si-rp\"),"):format("nebula-" .. base:lower()))
  emit("    layout      = pipeline_layout,")
  emit("    vertex      = { nextInChain = nilptr, module = shader, entryPoint = wgpu_str(\"vs_main\"),")
  emit("                    constantCount = 0, constants = nilptr, bufferCount = 0, buffers = nilptr },")
  emit("    primitive   = { nextInChain = nilptr, topology = WGPUPrimitiveTopology_TriangleList,")
  emit("                    stripIndexFormat = 0, frontFace = 0, cullMode = 0, unclippedDepth = false },")
  emit("    depthStencil = nilptr,")
  emit("    multisample  = { nextInChain = nilptr, count = 1, mask = 0xFFFFFFFF, alphaToCoverageEnabled = false },")
  emit("    fragment     = &frag_state,")
  emit("  }")
  emit("  self.pipeline = wgpuDeviceCreateRenderPipeline(renderer.device, &rp_desc)")
  emit("  wgpuShaderModuleRelease(shader)")
  emit("  if self.pipeline == nilptr then")
  emit(("    printf(\"wgpu: %s si: failed to create pipeline\\n\")\n    return false"):format(base:lower()))
  emit("  end")
  emit("")
  emit(("  printf(\"wgpu: %s standard-instanced pipeline created (max=%%u)\\n\", max_inst)"):format(base:lower()))
  emit("  return true")
  emit("end")

  -- ===== update_viewport =====
  emit(("function %s:update_viewport(renderer: *NebulaRenderer, vw: float32, vh: float32): void"):format(pipe))
  emit("  local vp: [4]float32 = { vw, vh, 0.0, 0.0 }")
  emit("  wgpuQueueWriteBuffer(renderer.queue, self.uniform_buf, 0, &vp[0], 16)")
  emit("end")

  -- ===== upload（批量上传 <T>Uniforms 数组到 Storage Buffer） =====
  emit(("function %s:upload(renderer: *NebulaRenderer, data: pointer, count: uint32): boolean"):format(pipe))
  emit("  if count == 0 or data == nilptr then return true end")
  emit("  if count > self.max_instances then")
  emit(("    printf(\"nebula: %s si: count %%u exceeds max_instances %%u\\n\", count, self.max_instances)"):format(base:lower()))
  emit("    count = self.max_instances")
  emit("  end")
  emit(("  local byte_size = (@uint64)(count) * (@uint64)(#%s)"):format(uniforms_record))
  emit("  wgpuQueueWriteBuffer(renderer.queue, self.storage_buf, 0, data, (@csize)(byte_size))")
  emit("  return true")
  emit("end")

  -- ===== draw_instanced（批量绘制 N 个实例） =====
  emit(("function %s:draw_instanced(pass: WGPURenderPassEncoder, count: uint32): void"):format(pipe))
  emit("  if count == 0 then return end")
  emit("  wgpuRenderPassEncoderSetPipeline(pass, self.pipeline)")
  emit("  wgpuRenderPassEncoderSetBindGroup(pass, 0, self.bind_group, 0, nilptr)")
  emit("  -- 每个实例渲染 6 顶点（两个三角形），通过 instance_index 定位 Storage Buffer 中的数据")
  emit("  wgpuRenderPassEncoderDraw(pass, 6, count, 0, 0)")
  emit("end")

  -- ===== draw_single（单实例快捷方法，上传 1 个 uniforms 并绘制） =====
  emit(("function %s:draw_single(renderer: *NebulaRenderer, pass: WGPURenderPassEncoder, uniforms: pointer): void"):format(pipe))
  emit("  if self:upload(renderer, uniforms, 1) then")
  emit("    self:draw_instanced(pass, 1)")
  emit("  end")
  emit("end")

  return table.concat(L, "\n")
end



--- [gen_pipeline_instanced 已在 Phase 3.7 中删除]
-- 请使用 gen_pipeline_standard_instanced（通过 nebula_derive 自动派生）

-- =============================================================================
-- ★ Phase 4.1: Slug 文本管线生成（必须在 nebula_gen_pipeline_source 之前定义）
--
-- 生成支持 Slug 算法的 <T>Pipeline 源码。
-- 绑定布局：
--   Binding 0: Uniform Buffer (视口大小等)
--   Binding 1: Storage Buffer (曲线数据，只读)
--   Binding 2: Storage Buffer (Band 元数据，只读)
--   Binding 3: Storage Buffer (Band 曲线引用索引，只读)
-- 顶点格式： NebulaSlugVertex (4 x vec4<f32> = 64 bytes/vertex)
-- =============================================================================
local function gen_pipeline_slug_text(base, uniforms_record, wgsl_source)
  local pipe = base .. "Pipeline"
  local wgsl_const = "NEBULA_SLUG_WGSL_" .. base:upper()
  local lines = {}
  local function emit(s) table.insert(lines, s) end

  emit(("-- === Derived pipeline: %s (uniforms=%s, slug_text=true) ==="):format(pipe, uniforms_record))
  emit(("global %s = @record{"):format(pipe))
  emit("  pipeline:         WGPURenderPipeline,")
  emit("  bind_layout:      WGPUBindGroupLayout,")
  emit("  uniform_buf:      WGPUBuffer,")
  emit("  curve_buf:        WGPUBuffer,")
  emit("  band_meta_buf:    WGPUBuffer,")
  emit("  band_ref_buf:     WGPUBuffer,")
  emit("  bind_group:       WGPUBindGroup,")
  emit("  vertex_buf:       WGPUBuffer,")
  emit("  vertex_buf_size:  uint64,")
  emit("  vertex_count:     uint32,")
  emit("}")

  emit(("local %s <comptime> = %s"):format(wgsl_const, escape_to_long_bracket(wgsl_source)))

  -- init
  emit(("function %s:init(renderer: *NebulaRenderer): boolean"):format(pipe))
  emit(("  if not nebula_create_uniform_buffer(&self.uniform_buf, renderer, (@csize)(#%s), \"nebula-%s-slug-ubuf\") then return false end"):format(uniforms_record, base:lower()))
  emit("  local bgl_entries: [4]WGPUBindGroupLayoutEntry")
  emit("  nebula_bgl_entry_uniform(&bgl_entries[0], 0)")
  emit("  nebula_bgl_entry_storage_ro(&bgl_entries[1], 1)")
  emit("  nebula_bgl_entry_storage_ro(&bgl_entries[2], 2)")
  emit("  nebula_bgl_entry_storage_ro(&bgl_entries[3], 3)")
  emit(("  self.bind_layout = nebula_create_bind_group_layout(renderer, &bgl_entries[0], 4, \"nebula-%s-slug-bgl\")"):format(base:lower()))
  emit("  if self.bind_layout == nilptr then return false end")
  emit("  local attrs: [4]WGPUVertexAttribute")
  emit("  local vlayout: WGPUVertexBufferLayout")
  emit("  nebula_init_slug_vertex_layout(&vlayout, &attrs[0])")
  emit(("  self.pipeline = nebula_create_render_pipeline_with_layout(renderer, self.bind_layout, %s, #%s, renderer.format, &vlayout, \"nebula-%s-slug-pipeline\")"):format(wgsl_const, wgsl_const, base:lower()))
  emit("  if self.pipeline == nilptr then return false end")
  emit("  self.bind_group = nilptr")
  emit("  self.vertex_buf = nilptr")
  emit("  self.vertex_buf_size = 0")
  emit("  self.vertex_count = 0")
  emit("  self.curve_buf = nilptr")
  emit("  self.band_meta_buf = nilptr")
  emit("  self.band_ref_buf = nilptr")
  emit(("  printf(\"wgpu: %s slug text pipeline created\\n\")"):format(base:lower()))
  emit("  return true")
  emit("end")

  -- update_uniforms
  emit(("function %s:update_uniforms(renderer: *NebulaRenderer, uniforms: *%s): void"):format(pipe, uniforms_record))
  emit(("  wgpuQueueWriteBuffer(renderer.queue, self.uniform_buf, 0, uniforms, #%s)"):format(uniforms_record))
  emit("end")

  -- upload_slug_buffers
  emit(("function %s:upload_slug_buffers(renderer: *NebulaRenderer, curves: pointer, curves_size: csize, band_metas: pointer, band_metas_size: csize, band_refs: pointer, band_refs_size: csize): boolean"):format(pipe))
  emit(("  if not nebula_create_storage_buffer(&self.curve_buf, renderer, curves, curves_size, \"nebula-%s-slug-curves\") then return false end"):format(base:lower()))
  emit(("  if not nebula_create_storage_buffer(&self.band_meta_buf, renderer, band_metas, band_metas_size, \"nebula-%s-slug-bands\") then return false end"):format(base:lower()))
  emit(("  if not nebula_create_storage_buffer(&self.band_ref_buf, renderer, band_refs, band_refs_size, \"nebula-%s-slug-refs\") then return false end"):format(base:lower()))
  emit("  return true")
  emit("end")

  -- update_slug_bind_group
  emit(("function %s:update_slug_bind_group(renderer: *NebulaRenderer): boolean"):format(pipe))
  emit("  local entries: [4]WGPUBindGroupEntry")
  emit("  nebula_bge_buffer(&entries[0], 0, self.uniform_buf, 0, wgpuBufferGetSize(self.uniform_buf))")
  emit("  nebula_bge_buffer(&entries[1], 1, self.curve_buf, 0, wgpuBufferGetSize(self.curve_buf))")
  emit("  nebula_bge_buffer(&entries[2], 2, self.band_meta_buf, 0, wgpuBufferGetSize(self.band_meta_buf))")
  emit("  nebula_bge_buffer(&entries[3], 3, self.band_ref_buf, 0, wgpuBufferGetSize(self.band_ref_buf))")
  emit(("  self.bind_group = nebula_create_bind_group(renderer, self.bind_layout, &entries[0], 4, \"nebula-%s-slug-bg\")"):format(base:lower()))
  emit("  return self.bind_group ~= nilptr")
  emit("end")

  -- upload_vertices
  emit(("function %s:upload_vertices(renderer: *NebulaRenderer, data: pointer, size: csize, vertex_count: uint32): boolean"):format(pipe))
  emit("  if self.vertex_buf ~= nilptr and self.vertex_buf_size < (@uint64)(size) then")
  emit("    wgpuBufferRelease(self.vertex_buf)")
  emit("    self.vertex_buf = nilptr")
  emit("  end")
  emit("  if self.vertex_buf == nilptr then")
  emit(("    if not nebula_create_vertex_buffer(&self.vertex_buf, renderer, data, size, \"nebula-%s-slug-vbuf\") then return false end"):format(base:lower()))
  emit("    self.vertex_buf_size = (@uint64)(size)")
  emit("  elseif data ~= nilptr and size > 0 then")
  emit("    wgpuQueueWriteBuffer(renderer.queue, self.vertex_buf, 0, data, size)")
  emit("  end")
  emit("  self.vertex_count = vertex_count")
  emit("  return true")
  emit("end")

  -- draw
  emit(("function %s:draw(pass: WGPURenderPassEncoder): void"):format(pipe))
  emit("  if self.bind_group == nilptr or self.vertex_buf == nilptr or self.vertex_count == 0 then return end")
  emit("  wgpuRenderPassEncoderSetPipeline(pass, self.pipeline)")
  emit("  wgpuRenderPassEncoderSetBindGroup(pass, 0, self.bind_group, 0, nilptr)")
  emit("  wgpuRenderPassEncoderSetVertexBuffer(pass, 0, self.vertex_buf, 0, self.vertex_buf_size)")
  emit("  wgpuRenderPassEncoderDraw(pass, self.vertex_count, 1, 0, 0)")
  emit("end")

  return table.concat(lines, "\n")
end

-- =============================================================================
-- 主入口：生成完整的 <T>Pipeline 源码
--
-- Phase 3.7: 三条显式路径，无 else 兑底。任何未识别的 spec 触发 error()。
-- =============================================================================
function nebula_gen_pipeline_source(spec)
  assert(spec.base,            "nebula_gen_pipeline_source: spec.base required")
  assert(spec.uniforms_record, "nebula_gen_pipeline_source: spec.uniforms_record required")

  if spec.has_shadow then
    -- 阴影多 Pass 路径：需要四个子着色器源码
    assert(spec.shadow_mask_source, "nebula_gen_pipeline_source: shadow_mask_source required when has_shadow")
    assert(spec.blur_h_source,      "nebula_gen_pipeline_source: blur_h_source required when has_shadow")
    assert(spec.blur_v_source,      "nebula_gen_pipeline_source: blur_v_source required when has_shadow")
    assert(spec.composite_source,   "nebula_gen_pipeline_source: composite_source required when has_shadow")
    -- Phase 3.7: 阴影路径的主着色器使用 nebula_compose_shadow_shaders 的 shadow_mask_source
    -- 主管线的 WGSL 由 gen_pipeline_shadow 内部使用 shadow_mask_source 作为主着色器
    return gen_pipeline_shadow(
      spec.base, spec.uniforms_record, spec.shadow_mask_source,
      spec.shadow_mask_source, spec.blur_h_source, spec.blur_v_source, spec.composite_source)
  elseif spec.standard_instanced then
    -- ★ Phase 3.5.1 / Phase 3.7: 标准 Visual 的默认路径
    assert(spec.wgsl_source, "nebula_gen_pipeline_source: wgsl_source required for standard_instanced path")
    local max_inst = spec.max_instances or 128
    return gen_pipeline_standard_instanced(spec.base, spec.uniforms_record, spec.wgsl_source, max_inst)
  elseif spec.textured then
    -- 文本 SDF 路径
    assert(spec.wgsl_source, "nebula_gen_pipeline_source: wgsl_source required for textured path")
    return gen_pipeline_textured_vertex(spec.base, spec.uniforms_record, spec.wgsl_source)
  elseif spec.slug_text then
    -- ★ Phase 4.1: Slug 文本管线路径
    assert(spec.wgsl_source, "nebula_gen_pipeline_source: wgsl_source required for slug_text path")
    return gen_pipeline_slug_text(spec.base, spec.uniforms_record, spec.wgsl_source)
  else
    error("nebula_gen_pipeline_source: unrecognized spec for '" .. tostring(spec.base) .. "'. " ..
          "All standard Visuals must use standard_instanced path (set via nebula_derive). " ..
          "Phase 3.7: gen_pipeline_simple and gen_pipeline_instanced have been removed.")
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
return "nebula_pipeline_factory_v0.8_phase4.1"
