-- =============================================================================
-- tests/smoke_phase3_3_2.lua
-- Nebula GUI Compiler — Phase 3.3.2
--
-- Storage Buffer 基础设施冒烟测试
--
-- 验证 renderer.nelua 中新增的 Phase 3.3.2 扩展：
--   · nebula_create_storage_buffer 函数存在且签名正确
--   · nebula_create_vertex_buffer 函数已提升为公共 API
--   · Storage Buffer 使用正确的 WGPUBufferUsage 标志
--   · 两个函数均为纯扩展，不破坏现有接口
-- =============================================================================

local src_path = "src/renderer.nelua"
local f = io.open(src_path, "r")
assert(f, "smoke_phase3_3_2: cannot open " .. src_path)
local src = f:read("*a")
f:close()

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

-- ===== nebula_create_storage_buffer 断言 =====

check("storage_buf_func_exists",
  src:find("function nebula_create_storage_buffer") ~= nil,
  "缺少 nebula_create_storage_buffer 函数")

check("storage_buf_is_global",
  src:find("global function nebula_create_storage_buffer") ~= nil,
  "nebula_create_storage_buffer 未声明为 global")

check("storage_buf_param_out_buf",
  src:find("nebula_create_storage_buffer%s*%([^)]*out_buf") ~= nil,
  "nebula_create_storage_buffer 缺少 out_buf 参数")

check("storage_buf_param_renderer",
  src:find("nebula_create_storage_buffer%s*%([^)]*renderer") ~= nil,
  "nebula_create_storage_buffer 缺少 renderer 参数")

check("storage_buf_param_size",
  src:find("nebula_create_storage_buffer%s*%([^)]*size") ~= nil,
  "nebula_create_storage_buffer 缺少 size 参数")

check("storage_buf_param_label",
  src:find("nebula_create_storage_buffer%s*%([^)]*label") ~= nil,
  "nebula_create_storage_buffer 缺少 label 参数")

check("storage_buf_uses_storage_usage",
  src:find("WGPUBufferUsage_Storage") ~= nil,
  "nebula_create_storage_buffer 未使用 WGPUBufferUsage_Storage")

check("storage_buf_uses_copydst",
  src:find("WGPUBufferUsage_CopyDst") ~= nil,
  "nebula_create_storage_buffer 未使用 WGPUBufferUsage_CopyDst")

check("storage_buf_returns_bool",
  src:find("nebula_create_storage_buffer[^)]*%): boolean") ~= nil,
  "nebula_create_storage_buffer 返回类型应为 boolean")

check("storage_buf_checks_nilptr",
  src:find("failed to create storage buffer") ~= nil,
  "nebula_create_storage_buffer 缺少 nilptr 失败日志")

-- ===== nebula_create_vertex_buffer 断言 =====

check("vertex_buf_func_exists",
  src:find("function nebula_create_vertex_buffer") ~= nil,
  "缺少 nebula_create_vertex_buffer 函数")

check("vertex_buf_is_global",
  src:find("global function nebula_create_vertex_buffer") ~= nil,
  "nebula_create_vertex_buffer 未声明为 global")

check("vertex_buf_uses_vertex_usage",
  src:find("WGPUBufferUsage_Vertex") ~= nil,
  "nebula_create_vertex_buffer 未使用 WGPUBufferUsage_Vertex")

check("vertex_buf_returns_bool",
  src:find("nebula_create_vertex_buffer[^)]*%): boolean") ~= nil,
  "nebula_create_vertex_buffer 返回类型应为 boolean")

check("vertex_buf_supports_nil_data",
  src:find("data ~= nilptr and size > 0") ~= nil,
  "nebula_create_vertex_buffer 未处理 data=nilptr 的情况")

-- ===== 现有接口未被破坏 =====

check("existing_nebula_pipeline_base_init_intact",
  src:find("function nebula_pipeline_base_init") ~= nil,
  "现有 nebula_pipeline_base_init 函数被意外删除")

check("existing_nebula_upload_texture_intact",
  src:find("function nebula_upload_texture") ~= nil,
  "现有 nebula_upload_texture 函数被意外删除")

check("existing_nebula_create_render_target_intact",
  src:find("function nebula_create_render_target") ~= nil,
  "现有 nebula_create_render_target 函数被意外删除")

check("existing_nebula_create_sampler_intact",
  src:find("function nebula_create_sampler") ~= nil,
  "现有 nebula_create_sampler 函数被意外删除")

check("existing_nebula_create_blur_bind_group_intact",
  src:find("function nebula_create_blur_bind_group") ~= nil,
  "现有 nebula_create_blur_bind_group 函数被意外删除")

-- ===== 汇总 =====
print(("\n--- smoke_phase3_3_2 结果: %d 通过, %d 失败 ---"):format(pass, fail))
if fail > 0 then
  os.exit(1)
end
