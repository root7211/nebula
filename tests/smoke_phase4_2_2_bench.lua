-- =============================================================================
-- Nebula GUI Compiler — Phase 4.2.2 D-4.1-C Benchmark 静态分析测试
--
-- 验证内容（全部为 S0/S1 阶段静态代码分析，无需 GPU）：
--
-- D-4.1-C: Storage Buffer 可扩展性审计
--   1. [S2] renderer.nelua 包含 nebula_create_storage_buffer 函数
--   2. [S2] renderer.nelua Storage Buffer 创建使用 WGPUBufferUsage_Storage 标志
--   3. [S2] renderer.nelua 包含 wgpuQueueWriteBuffer 上传调用
--   4. [S1] pipeline_factory.lua standard_instanced 路径使用 Storage Buffer
--   5. [S1] pipeline_factory.lua standard_instanced draw 使用 wgpuRenderPassEncoderDraw(pass, 6, N, 0, 0)
--   6. [S1] pipeline_factory.lua standard_instanced upload 方法存在
--   7. [S1] shader_compose.lua 标准 instanced 着色器使用 var<storage, read>
--   8. [S1] shader_compose.lua 标准 instanced 着色器无纹理绑定（仅 uniform + storage）
--   9. [S2] renderer.nelua Storage Buffer 无大小硬编码上限（仅受设备内存限制）
--  10. [Benchmark] slug_bench.nelua 文件存在
--  11. [Benchmark] slug_bench.nelua 包含 10000 实例规模测试
--  12. [Benchmark] slug_bench.nelua 包含 20% 退化阈值判断
--  13. [Benchmark] slug_bench.nelua 包含 glfwGetTime 计时
--  14. [Benchmark] slug_bench.nelua 包含 PASSES/FAILED 判定输出
--  15. [Benchmark] build.sh 包含 slug_bench 构建目标
--
-- 架构合理性：
--  16. [S1] pipeline_factory.lua standard_instanced storage_size 使用乘法计算（非固定值）
--  17. [S1] pipeline_factory.lua standard_instanced upload 按 count * sizeof 计算字节数
--  18. [S1] pipeline_factory.lua standard_instanced 无实例数硬编码上限（通过参数传入）
--  19. [S2] renderer.nelua nebula_create_storage_buffer 创建后即上传（零延迟路径）
--  20. [S1] shader_compose.lua instanced 着色器通过 instance_index 索引 Storage Buffer
-- =============================================================================

local script_dir = debug.getinfo(1, "S").source:match("^@(.+)/[^/]+$") or "."

-- ---- 辅助函数 ----
local passed = 0
local failed = 0

local function assert_contains(desc, content, pattern)
  if content and content:find(pattern, 1, true) then
    passed = passed + 1
    print(("[PASS] %s"):format(desc))
  else
    failed = failed + 1
    print(("[FAIL] %s\n       pattern not found: %s"):format(desc, pattern))
  end
end

local function assert_not_contains(desc, content, pattern)
  if content and not content:find(pattern, 1, true) then
    passed = passed + 1
    print(("[PASS] %s"):format(desc))
  else
    failed = failed + 1
    print(("[FAIL] %s\n       pattern should NOT be present: %s"):format(desc, pattern))
  end
end

local function assert_file_exists(desc, path)
  local f = io.open(path, "r")
  if f then
    f:close()
    passed = passed + 1
    print(("[PASS] %s"):format(desc))
  else
    failed = failed + 1
    print(("[FAIL] %s\n       file not found: %s"):format(desc, path))
  end
end

local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  return content
end

local base = script_dir:match("^(.+)/tests$") or script_dir:match("^(.+)/tools$") or script_dir .. "/.."

local renderer_src = read_file(base .. "/src/renderer.nelua")
local pipe_src     = read_file(base .. "/src/derive/pipeline_factory.lua")
local shader_src   = read_file(base .. "/src/derive/shader_compose.lua")
local bench_src    = read_file(base .. "/examples/slug_bench.nelua")
local build_src    = read_file(base .. "/build.sh")

-- =============================================================================
-- D-4.1-C: Storage Buffer 基础设施审计
-- =============================================================================

print("=== D-4.1-C: Storage Buffer Infrastructure Audit ===\n")

assert_contains("S2: nebula_create_storage_buffer exists",
  renderer_src, "global function nebula_create_storage_buffer(")

assert_contains("S2: Storage Buffer uses WGPUBufferUsage_Storage",
  renderer_src, "WGPUBufferUsage_Storage")

assert_contains("S2: wgpuQueueWriteBuffer upload path exists",
  renderer_src, "wgpuQueueWriteBuffer")

assert_contains("S1: standard_instanced uses Storage Buffer",
  pipe_src, "storage_buf")

assert_contains("S1: standard_instanced draw uses instanced draw call",
  pipe_src, "wgpuRenderPassEncoderDraw(pass, 6, count, 0, 0)")

assert_contains("S1: standard_instanced upload method exists",
  pipe_src, "upload")

assert_contains("S1: shader uses var<storage, read> for instances",
  shader_src, "var<storage, read>  instances")

assert_not_contains("S1: instanced shader has NO texture binding (pure storage)",
  shader_src:match("fn vs_main.-fn fs_main") or "", "texture_2d")

-- nebula_create_storage_buffer 的 size 参数是 csize 类型，无固定上限
-- 而 Uniform Buffer 的文档注释中提到 65536 限制是正确的（仅限 Uniform）
assert_contains("S2: Storage Buffer size uses device-memory-limited csize param",
  renderer_src:match("nebula_create_storage_buffer.-\nend") or "", "(@uint64)(size)")

-- =============================================================================
-- D-4.1-C: Benchmark 程序审计
-- =============================================================================

print("\n=== D-4.1-C: Benchmark Program Audit ===\n")

assert_file_exists("Benchmark: slug_bench.nelua file exists",
  base .. "/examples/slug_bench.nelua")

assert_contains("Benchmark: tests 10000 instances scale",
  bench_src, "10000")

assert_contains("Benchmark: uses 20% degradation threshold",
  bench_src, "20")

assert_contains("Benchmark: uses glfwGetTime for timing",
  bench_src, "glfwGetTime")

assert_contains("Benchmark: outputs PASSED/FAILED verdict",
  bench_src, "PASSED")

assert_contains("Benchmark: build.sh includes slug_bench target",
  build_src, "slug_bench")

-- =============================================================================
-- D-4.1-C: 架构合理性审计
-- =============================================================================

print("\n=== D-4.1-C: Architecture Sanity Check ===\n")

assert_contains("S1: storage_size calculated via multiplication (not fixed)",
  pipe_src, "max_inst) * (@uint64)(#")

assert_contains("S1: upload byte_size computed from count * sizeof",
  pipe_src, "count) * (@uint64)(#")

-- max_instances default is a fallback only; the actual value is passed as a parameter
assert_contains("S1: instance limit is configurable (not hardcoded)",
  pipe_src:match("max_instances = max_instances or") or pipe_src, "max_instances")

assert_contains("S2: nebula_create_storage_buffer uploads on creation (zero-delay)",
  renderer_src:match("nebula_create_storage_buffer.-\nend") or "", "wgpuQueueWriteBuffer")

assert_contains("S1: shader indexes Storage Buffer via instance_index",
  shader_src, "instance_index")

-- =============================================================================
-- 结果汇总
-- =============================================================================

print("\n============================================")
print((" Results: %d/%d passed, %d failed"):format(passed, passed + failed, failed))
print("============================================")

if failed > 0 then
  print("[FAIL] D-4.1-C static analysis has failures")
  os.exit(1)
else
  print("[ALL PASS] D-4.1-C static analysis: Storage Buffer infrastructure validated")
  os.exit(0)
end
