-- =============================================================================
-- tests/smoke_phase3_3_4.lua
-- Nebula GUI Compiler — Phase 3.3.4（Phase 3.7 更新）
--
-- Phase 3.7 变更说明：
--   · gen_pipeline_instanced 已在 Phase 3.7 中删除（死代码清理）
--   · gen_pipeline_simple 已在 Phase 3.7 中删除（Phase 2.3 占位符路径）
--   · 本测试已更新为验证 Phase 3.7 的 nebula_gen_pipeline_source 行为：
--     - standard_instanced 路径（原 gen_pipeline_instanced 的替代方案）
--     - 死代码路径触发明确 error
-- =============================================================================

local script_dir = debug.getinfo(1, "S").source:match("^@(.+)/[^/]+$") or "."
package.path = script_dir .. "/../src/?.lua;" ..
               script_dir .. "/../src/derive/?.lua;" ..
               package.path

require "derive.shader_compose"
local factory_ver = require "derive.pipeline_factory"

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

local function check_error(name, fn)
  local ok, err = pcall(fn)
  if not ok then
    pass = pass + 1
    print(("[PASS] %s"):format(name))
  else
    fail = fail + 1
    print(("[FAIL] %s — expected error but none was raised"):format(name))
  end
end

-- ===== 版本号检查（Phase 3.7）=====
check("pipeline_factory_version_phase4_1",
  factory_ver == "nebula_pipeline_factory_v0.8_phase4.1",
  "版本号未更新至 phase3.7，当前: " .. tostring(factory_ver))

-- ===== 函数存在性 =====
check("func_nebula_gen_pipeline_source_exists",
  type(nebula_gen_pipeline_source) == "function",
  "nebula_gen_pipeline_source 函数不存在")

check("func_nebula_gen_to_uniforms_typed_intact",
  type(nebula_gen_to_uniforms_typed) == "function",
  "nebula_gen_to_uniforms_typed 函数不存在")

-- ===== Phase 3.7: standard_instanced 路径（替代原 gen_pipeline_instanced）=====
local mock_struct = [[
struct ListItemUniforms {
  pos:          vec2<f32>,
  size:         vec2<f32>,
  bg_color:     vec4<f32>,
  border_color: vec4<f32>,
  border_width: f32,
  radius:       f32,
  viewport:     vec2<f32>,
}]]

local si_shader = nebula_compose_shader_instanced({
  wgsl_struct = mock_struct,
  struct_name = "ListItemUniforms",
  has_radius  = true,
  has_border  = true,
})

local code = nebula_gen_pipeline_source({
  base               = "ListItem",
  uniforms_record    = "ListItemUniforms",
  wgsl_source        = si_shader.source,
  standard_instanced = true,
  max_instances      = 16,
})

check("standard_instanced_generates_code",
  type(code) == "string" and #code > 0,
  "nebula_gen_pipeline_source 对 standard_instanced spec 未生成代码")

-- Phase 3.7: 管线名称是 ListItemPipeline（不再是 ListItemInstancedPipeline）
check("generates_ListItemPipeline",
  code:find("global ListItemPipeline = @record{", 1, true) ~= nil,
  "应生成 ListItemPipeline（Phase 3.7 standard_instanced 路径）")

check("has_storage_buf_field",
  code:find("storage_buf:") ~= nil,
  "应包含 storage_buf 字段")

check("has_storage_size_field",
  code:find("storage_size:") ~= nil,
  "应包含 storage_size 字段")

check("has_max_instances_field",
  code:find("max_instances:") ~= nil,
  "应包含 max_instances 字段")

check("has_init_method",
  code:find("function ListItemPipeline:init(renderer: *NebulaRenderer, max_inst: uint32)", 1, true) ~= nil,
  "应包含 init(renderer, max_inst) 方法")

check("has_upload_method",
  code:find("function ListItemPipeline:upload(", 1, true) ~= nil,
  "应包含 upload 方法")

check("has_draw_instanced_method",
  code:find("function ListItemPipeline:draw_instanced(", 1, true) ~= nil,
  "应包含 draw_instanced 方法")

check("has_update_viewport_method",
  code:find("function ListItemPipeline:update_viewport(", 1, true) ~= nil,
  "应包含 update_viewport 方法")

check("has_draw_single_method",
  code:find("function ListItemPipeline:draw_single(", 1, true) ~= nil,
  "应包含 draw_single 方法")

check("uses_readonly_storage",
  code:find("WGPUBufferBindingType_ReadOnlyStorage") ~= nil,
  "应使用 ReadOnlyStorage 绑定类型")

check("no_vertex_buffer",
  code:find("bufferCount = 0") ~= nil,
  "应使用无顶点缓冲管线（通过 instance_index 驱动）")

-- ===== Phase 3.7: 死代码路径触发 error =====
check_error("instanced=true 路径触发 error（gen_pipeline_instanced 已删除）", function()
  nebula_gen_pipeline_source({
    base            = "ListItem",
    uniforms_record = "ListItemUniforms",
    wgsl_source     = "// placeholder",
    instanced       = true,
    instance_record = "ListItemInstanceData",
    max_instances   = 10000,
  })
end)

check_error("simple 路径触发 error（gen_pipeline_simple 已删除）", function()
  nebula_gen_pipeline_source({
    base            = "SimpleRect",
    uniforms_record = "SimpleRectUniforms",
    wgsl_source     = "// placeholder",
  })
end)

-- ===== 汇总 =====
print(("\n=== smoke_phase3_3_4（Phase 3.7 更新）：%d 通过，%d 失败 ==="):format(pass, fail))
if fail > 0 then os.exit(1) end
