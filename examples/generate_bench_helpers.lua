-- generate_bench_helpers.lua
-- 编译期辅助脚本：生成 benchmark 的 fill 和 render 函数
-- 在 slug_bench.nelua 中通过 ##dofile 调用

local reg = nebula_registry["BenchVisual"]
local layout = nebula_gen_uniform_layout("BenchVisual", {
  record_name      = "BenchVisualUniforms",
  wgsl_struct_name = "Uniforms",
})
BENCH_UNIFORMS_BYTES = layout.total_size

-- 生成 fill_bench_instances 函数
local uniform_bytes = BENCH_UNIFORMS_BYTES
local WIN_W = 800
local WIN_H = 600

-- 注入编译期常量到全局作用域
local const_src = string.format("global BENCH_UNIFORMS_BYTES_VAL: uint32 <comptime> = %d", BENCH_UNIFORMS_BYTES)
local const_ast = aster.parse(const_src, "<bench_const>")
for _, stat in ipairs(const_ast) do
  inject_statement(stat)
end
local fill_src = string.format(
  "global function fill_bench_instances(out: pointer, count: uint32): void\n"..
  "  local cols: uint32 = 100\n"..
  "  local rows: uint32 = (count + cols - 1) / cols\n"..
  "  local cell_w = (@float32)(%d) / (@float32)(cols)\n"..
  "  local cell_h = (@float32)(%d) / (@float32)(rows)\n"..
  "  local rect_w = cell_w * 0.9\n"..
  "  local rect_h = cell_h * 0.9\n"..
  "  local i: uint32 = 0\n"..
  "  while i < count do\n"..
  "    local col = i %% cols\n"..
  "    local row = i / cols\n"..
  "    local u = BenchVisualUniforms{\n"..
  "      pos_x = (@float32)(col) * cell_w + cell_w * 0.05,\n"..
  "      pos_y = (@float32)(row) * cell_h + cell_h * 0.05,\n"..
  "      size_x = rect_w,\n"..
  "      size_y = rect_h,\n"..
  "      color_r = 0.3, color_g = 0.6, color_b = 0.9, color_a = 1.0,\n"..
  "      border_color_r = 0.0, border_color_g = 0.0, border_color_b = 0.0, border_color_a = 0.0,\n"..
  "      border_width = 0.0,\n"..
  "      pad0 = 0.0,\n"..
  "    }\n"..
  "    memcpy((@pointer)((@*uint8)(out) + i * %d), &u, %d)\n"..
  "    i = i + 1\n"..
  "  end\n"..
  "end",
  WIN_W, WIN_H, uniform_bytes, uniform_bytes)

local ast = aster.parse(fill_src, "<fill_bench_instances>")
for _, stat in ipairs(ast) do
  inject_statement(stat)
end

-- 生成 bench_render_frame 函数
local render_src = string.format(
  "global function bench_render_frame(\n"..
  "  renderer: *NebulaRenderer,\n"..
  "  instances: pointer,\n"..
  "  count: uint32,\n"..
  "  max_instances: uint32\n"..
  "): boolean\n"..
  "  glfwPollEvents()\n"..
  "  local pipe: BenchVisualPipeline\n"..
  "  if not pipe:init(renderer, max_instances) then\n"..
  "    printf(\"bench: pipeline init failed\\n\")\n"..
  "    return false\n"..
  "  end\n"..
  "  pipe:upload(renderer, instances, count)\n"..
  "  local surf_tex = WGPUSurfaceTexture{}\n"..
  "  wgpuSurfaceGetCurrentTexture(renderer.surface, &surf_tex)\n"..
  "  if surf_tex.texture == nilptr then\n"..
  "    pipe:deinit()\n"..
  "    return false\n"..
  "  end\n"..
  "  local tex_view = wgpuTextureCreateView(surf_tex.texture, nilptr)\n"..
  "  local enc_desc = WGPUCommandEncoderDescriptor{ nextInChain = nilptr, label = wgpu_str(\"bench-enc\") }\n"..
  "  local encoder = wgpuDeviceCreateCommandEncoder(renderer.device, &enc_desc)\n"..
  "  local rp_color = WGPURenderPassColorAttachment{\n"..
  "    nextInChain = nilptr, view = tex_view, depthSlice = 0xFFFFFFFF,\n"..
  "    resolveTarget = nilptr, loadOp = WGPURenderOp_Clear, storeOp = WGPURenderOp_Store,\n"..
  "    clearValue = WGPUColor{ r = 0.05, g = 0.05, b = 0.07, a = 1.0 },\n"..
  "  }\n"..
  "  local rp_desc = WGPURenderPassDescriptor{\n"..
  "    nextInChain = nilptr, label = wgpu_str(\"bench-rp\"),\n"..
  "    colorAttachmentCount = 1, colorAttachments = &rp_color,\n"..
  "    depthStencilAttachment = nilptr, timestampWrites = nilptr,\n"..
  "  }\n"..
  "  local pass = wgpuCommandEncoderBeginRenderPass(encoder, &rp_desc)\n"..
  "  pipe:draw_instanced(pass, count)\n"..
  "  wgpuRenderPassEncoderEnd(pass)\n"..
  "  wgpuRenderPassEncoderRelease(pass)\n"..
  "  local cmd_buf_desc = WGPUCommandBufferDescriptor{ nextInChain = nilptr, label = wgpu_str(\"bench-cmd\") }\n"..
  "  local cmd_buf = wgpuCommandEncoderFinish(encoder, &cmd_buf_desc)\n"..
  "  wgpuCommandEncoderRelease(encoder)\n"..
  "  wgpuQueueSubmit(renderer.queue, 1, &cmd_buf)\n"..
  "  wgpuCommandBufferRelease(cmd_buf)\n"..
  "  wgpuTextureViewRelease(tex_view)\n"..
  "  wgpuSurfacePresent(renderer.surface)\n"..
  "  wgpuDevicePoll(renderer.device, false, nilptr)\n"..
  "  pipe:deinit()\n"..
  "  return true\n"..
  "end")

local ast2 = aster.parse(render_src, "<bench_render_frame>")
for _, stat in ipairs(ast2) do
  inject_statement(stat)
end
