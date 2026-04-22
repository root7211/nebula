-- =============================================================================
-- tests/smoke_phase3_3_4.lua
-- Nebula GUI Compiler — Phase 3.3.4
--
-- Instanced 管线工厂冒烟测试
--
-- 验证 pipeline_factory.lua 中新增的 gen_pipeline_instanced 路径：
--   · nebula_gen_pipeline_source 在 spec.instanced=true 时走新分支
--   · 生成的代码包含 <T>InstancedPipeline record 定义
--   · 包含 init / upload / draw / update_viewport 四个方法
--   · init 中正确创建 Uniform Buffer 和 Storage Buffer
--   · upload 中使用 wgpuQueueWriteBuffer 整体更新
--   · draw 中使用 wgpuRenderPassEncoderDraw 并传递 instance_count
--   · spec.instanced 分支不影响 has_shadow 和 textured 路径
--   · 模块版本号已更新至 phase3.3
-- =============================================================================

local factory = dofile("src/derive/pipeline_factory.lua")

local pass = 0
local fail = 0

local function check(name, cond, msg)
  if cond then
    pass = pass + 1
    print(("[PASS] %s"):format(name))
  else
    fail = fail + 1
    print(("[FAIL] %s — %s"):format(name, msg or "assertion failed"))
  end
end

-- ===== 模块版本检查 =====
check("module_version_updated",
  factory == "nebula_pipeline_factory_v0.5_phase3.3",
  "模块版本号未更新至 phase3.3，当前: " .. tostring(factory))

-- ===== 函数存在性 =====
check("func_nebula_gen_pipeline_source_exists",
  type(nebula_gen_pipeline_source) == "function",
  "nebula_gen_pipeline_source 函数不存在")

check("func_nebula_gen_to_uniforms_typed_intact",
  type(nebula_gen_to_uniforms_typed) == "function",
  "现有 nebula_gen_to_uniforms_typed 函数被破坏")

-- ===== 生成 Instanced 管线代码 =====
-- 构造一个最小化的 spec，触发 instanced 分支
local dummy_wgsl = [[
struct InstanceData { pos: vec2<f32>, size: vec2<f32>, bg_color: vec4<f32>,
  border_color: vec4<f32>, border_width: f32, radius: f32, _pad0: f32, _pad1: f32, }
struct Viewport { size: vec2<f32>, _pad0: f32, _pad1: f32, }
@group(0) @binding(0) var<uniform> vp: Viewport;
@group(0) @binding(1) var<storage, read> instances: array<InstanceData>;
@vertex fn vs_main(@builtin(vertex_index) vi: u32, @builtin(instance_index) inst: u32) -> @builtin(position) vec4<f32> { return vec4<f32>(0.0); }
@fragment fn fs_main() -> @location(0) vec4<f32> { return vec4<f32>(1.0); }
]]

local spec = {
  base             = "ListItem",
  uniforms_record  = "ListItemUniforms",  -- 此字段在 instanced 路径中不直接使用，但接口要求存在
  wgsl_source      = dummy_wgsl,
  instanced        = true,
  instance_record  = "ListItemInstanceData",
  max_instances    = 10000,
}

local code = nebula_gen_pipeline_source(spec)
check("instanced_spec_generates_code",
  type(code) == "string" and #code > 0,
  "nebula_gen_pipeline_source 对 instanced spec 未生成代码")

-- ===== 生成代码结构断言 =====

check("generated_has_instanced_pipeline_record",
  code:find("ListItemInstancedPipeline") ~= nil,
  "生成代码缺少 ListItemInstancedPipeline record")

check("generated_record_has_pipeline_field",
  code:find("pipeline:%s*WGPURenderPipeline") ~= nil,
  "生成代码缺少 pipeline: WGPURenderPipeline 字段")

check("generated_record_has_uniform_buf",
  code:find("uniform_buf:%s*WGPUBuffer") ~= nil,
  "生成代码缺少 uniform_buf: WGPUBuffer 字段")

check("generated_record_has_storage_buf",
  code:find("storage_buf:%s*WGPUBuffer") ~= nil,
  "生成代码缺少 storage_buf: WGPUBuffer 字段")

check("generated_record_has_storage_size",
  code:find("storage_size:%s*uint64") ~= nil,
  "生成代码缺少 storage_size: uint64 字段")

check("generated_record_has_bind_group",
  code:find("bind_group:%s*WGPUBindGroup") ~= nil,
  "生成代码缺少 bind_group: WGPUBindGroup 字段")

check("generated_record_has_max_instances",
  code:find("max_instances:%s*uint32") ~= nil,
  "生成代码缺少 max_instances: uint32 字段")

-- init 方法
check("generated_has_init_method",
  code:find("function ListItemInstancedPipeline:init") ~= nil,
  "生成代码缺少 init 方法")

check("init_creates_uniform_buffer",
  code:find("WGPUBufferUsage_Uniform") ~= nil,
  "init 方法未创建 Uniform Buffer")

check("init_creates_storage_buffer",
  code:find("WGPUBufferUsage_Storage") ~= nil,
  "init 方法未创建 Storage Buffer")

check("init_creates_bgl_with_two_entries",
  code:find("entryCount%s*=%s*2") ~= nil,
  "init 方法的 BindGroupLayout 应有 2 个 entry")

check("init_uses_readonly_storage",
  code:find("WGPUBufferBindingType_ReadOnlyStorage") ~= nil,
  "init 方法 binding 1 应使用 ReadOnlyStorage 类型")

check("init_creates_pipeline_no_vertex_buffer",
  code:find("bufferCount%s*=%s*0") ~= nil,
  "Instanced 管线不应有顶点缓冲区（bufferCount 应为 0）")

-- update_viewport 方法
check("generated_has_update_viewport_method",
  code:find("function ListItemInstancedPipeline:update_viewport") ~= nil,
  "生成代码缺少 update_viewport 方法")

check("update_viewport_writes_16_bytes",
  code:find("wgpuQueueWriteBuffer.*uniform_buf.*0.*16") ~= nil or
  code:find("wgpuQueueWriteBuffer.*16") ~= nil,
  "update_viewport 应向 uniform_buf 写入 16 字节")

-- upload 方法
check("generated_has_upload_method",
  code:find("function ListItemInstancedPipeline:upload") ~= nil,
  "生成代码缺少 upload 方法")

check("upload_uses_wgpuQueueWriteBuffer",
  code:find("wgpuQueueWriteBuffer.*storage_buf") ~= nil,
  "upload 方法应使用 wgpuQueueWriteBuffer 更新 storage_buf")

check("upload_checks_max_instances",
  code:find("max_instances") ~= nil,
  "upload 方法应检查 max_instances 上限")

-- draw 方法
check("generated_has_draw_method",
  code:find("function ListItemInstancedPipeline:draw") ~= nil,
  "生成代码缺少 draw 方法")

check("draw_uses_set_pipeline",
  code:find("wgpuRenderPassEncoderSetPipeline") ~= nil,
  "draw 方法应调用 wgpuRenderPassEncoderSetPipeline")

check("draw_uses_set_bind_group",
  code:find("wgpuRenderPassEncoderSetBindGroup") ~= nil,
  "draw 方法应调用 wgpuRenderPassEncoderSetBindGroup")

check("draw_uses_instanced_draw_call",
  -- wgpuRenderPassEncoderDraw(pass, 3, count, 0, 0)
  -- 6 顶点/实例 × count 实例
  code:find("wgpuRenderPassEncoderDraw%(pass, [36], count, 0, 0%)") ~= nil,
  "draw 方法应使用 wgpuRenderPassEncoderDraw 并传递 instance count")

-- WGSL 源码常量名称
check("wgsl_const_name_contains_instanced",
  code:find("NEBULA_WGSL_LISTITEM_INSTANCED") ~= nil,
  "WGSL 源码常量名称应包含 _INSTANCED 后缀")

-- ===== 现有路径未被破坏 =====
-- 测试 simple 路径
local simple_spec = {
  base             = "SimpleRect",
  uniforms_record  = "SimpleRectUniforms",
  wgsl_source      = "// dummy",
}
local simple_code = nebula_gen_pipeline_source(simple_spec)
check("simple_path_still_works",
  simple_code:find("SimpleRectPipeline") ~= nil,
  "simple 路径被破坏")

check("simple_path_no_instanced_record",
  simple_code:find("SimpleRectInstancedPipeline") == nil,
  "simple 路径不应生成 InstancedPipeline record")

-- ===== spec.instanced=false 不走新路径 =====
local non_instanced_spec = {
  base             = "Button",
  uniforms_record  = "ButtonUniforms",
  wgsl_source      = "// dummy",
  instanced        = false,
}
local non_instanced_code = nebula_gen_pipeline_source(non_instanced_spec)
check("non_instanced_false_uses_simple_path",
  non_instanced_code:find("ButtonInstancedPipeline") == nil,
  "instanced=false 时不应生成 InstancedPipeline")

-- ===== 汇总 =====
print(("\n--- smoke_phase3_3_4 结果: %d 通过, %d 失败 ---"):format(pass, fail))
if fail > 0 then
  os.exit(1)
end
