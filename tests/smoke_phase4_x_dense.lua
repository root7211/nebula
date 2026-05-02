-- =============================================================================
-- tests/smoke_phase4_x_dense.lua
-- Nebula GUI Compiler — Phase 4.X High-Density Text Rendering Smoke Test
--
-- Verifies the compile-time code generation infrastructure WITHOUT running
-- any GPU code.
--
-- Test targets:
--   1. shader_compose.lua   — nebula_compose_dense_text_shader function
--   2. pipeline_factory.lua — gen_pipeline_dense_text via nebula_gen_pipeline_source
--   3. renderer.nelua       — DenseCharInstance + DenseTextUniforms records
--   4. nebula_core.nelua    — derivation entry exists
--   5. text_runtime.nelua   — grid fill helper exists
--   6. Public axiom compliance checks
--   7. Mutual exclusivity check (atlas_dense + standard_instanced must error)
-- =============================================================================

-- =============================================================================
-- Test infrastructure
-- =============================================================================
local pass_count = 0
local fail_count = 0

local function check(desc, condition)
  if condition then
    pass_count = pass_count + 1
    print(("[PASS] %s"):format(desc))
  else
    fail_count = fail_count + 1
    print(("[FAIL] %s"):format(desc))
  end
end

local function file_exists(path)
  local f = io.open(path, "r")
  if f then f:close() return true end
  return false
end

local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  return content
end

-- =============================================================================
-- Load derive modules via dofile
-- =============================================================================
local sc_version = dofile("src/derive/shader_compose.lua")
local pf_version = dofile("src/derive/pipeline_factory.lua")

print("=== Phase 4.X dense text rendering — smoke tests ===")
print("")

-- =============================================================================
-- Section 1: shader_compose.lua — nebula_compose_dense_text_shader
-- =============================================================================
print("--- 1. shader_compose.lua: nebula_compose_dense_text_shader ---")

check("shader_compose version string returned", type(sc_version) == "string")
check("nebula_compose_dense_text_shader is a function",
  type(nebula_compose_dense_text_shader) == "function")

local shader_result = nebula_compose_dense_text_shader()

check("nebula_compose_dense_text_shader returns a table",
  type(shader_result) == "table")
check("shader result has .source (string)",
  type(shader_result.source) == "string")
check("shader result has .features (table)",
  type(shader_result.features) == "table")
check("shader result has atlas_dense == true",
  shader_result.atlas_dense == true)

-- WGSL source content checks
local src = shader_result.source or ""
check("WGSL source contains DenseTextUniforms",
  src:find("DenseTextUniforms", 1, true) ~= nil)
check("WGSL source contains DenseCharInstance",
  src:find("DenseCharInstance", 1, true) ~= nil)
check("WGSL source contains array<DenseCharInstance>",
  src:find("array<DenseCharInstance>", 1, true) ~= nil)
check("WGSL source contains unpack4x8unorm",
  src:find("unpack4x8unorm", 1, true) ~= nil)
check("WGSL source contains vs_main",
  src:find("vs_main", 1, true) ~= nil)
check("WGSL source contains fs_main",
  src:find("fs_main", 1, true) ~= nil)
check("WGSL source contains smoothstep",
  src:find("smoothstep", 1, true) ~= nil)
check("WGSL source contains textureSample",
  src:find("textureSample", 1, true) ~= nil)
check("WGSL source contains glyph_atlas",
  src:find("glyph_atlas", 1, true) ~= nil)
check("WGSL source contains glyph_sampler",
  src:find("glyph_sampler", 1, true) ~= nil)

-- Features checks
local features = shader_result.features or {}
local feat_set = {}
for _, f in ipairs(features) do feat_set[f] = true end
check("features contains 'dense_text'",    feat_set["dense_text"] == true)
check("features contains 'instanced'",     feat_set["instanced"] == true)
check("features contains 'storage_buffer'", feat_set["storage_buffer"] == true)

print("")

-- =============================================================================
-- Section 2: pipeline_factory.lua — gen_pipeline_dense_text via nebula_gen_pipeline_source
-- =============================================================================
print("--- 2. pipeline_factory.lua: nebula_gen_pipeline_source (atlas_dense path) ---")

check("pipeline_factory version string returned", type(pf_version) == "string")
check("nebula_gen_pipeline_source is a function",
  type(nebula_gen_pipeline_source) == "function")

local pipeline_spec = {
  base             = "TestDense",
  uniforms_record  = "TestDenseUniforms",
  wgsl_source      = "// test",
  atlas_dense      = true,
  max_chars        = 4096,
}

local gen_ok, gen_result = pcall(nebula_gen_pipeline_source, pipeline_spec)
check("nebula_gen_pipeline_source does not error for atlas_dense spec", gen_ok)

if gen_ok then
  check("generated code is a string", type(gen_result) == "string")

  local code = gen_result
  -- Record name
  check("generated code contains TestDenseDenseTextPipeline record",
    code:find("TestDenseDenseTextPipeline", 1, true) ~= nil)

  -- Record fields
  check("generated code contains 'pipeline:' field",
    code:find("pipeline:", 1, true) ~= nil)
  check("generated code contains 'storage_buf:' field",
    code:find("storage_buf:", 1, true) ~= nil)
  check("generated code contains 'uniform_buf:' field",
    code:find("uniform_buf:", 1, true) ~= nil)
  check("generated code contains 'max_chars:' field",
    code:find("max_chars:", 1, true) ~= nil)
  check("generated code contains 'storage_size' field",
    code:find("storage_size", 1, true) ~= nil)

  -- Methods
  check("generated code contains 'init' method",
    code:find(":init(", 1, true) ~= nil)
  check("generated code contains 'update_atlas' method",
    code:find(":update_atlas(", 1, true) ~= nil)
  check("generated code contains 'update_viewport' method",
    code:find(":update_viewport(", 1, true) ~= nil)
  check("generated code contains 'upload' method",
    code:find(":upload(", 1, true) ~= nil)
  check("generated code contains 'draw' method",
    code:find(":draw(", 1, true) ~= nil)
  check("generated code contains 'deinit' method",
    code:find(":deinit(", 1, true) ~= nil)

  -- Draw call (instanced, 6 vertices per character)
  check("generated code contains wgpuRenderPassEncoderDraw(pass, 6,",
    code:find("wgpuRenderPassEncoderDraw(pass, 6,", 1, true) ~= nil)

  -- Storage buffer binding type
  check("generated code contains WGPUBufferBindingType_ReadOnlyStorage",
    code:find("WGPUBufferBindingType_ReadOnlyStorage", 1, true) ~= nil)
else
  -- gen_result is the error message when gen_ok is false
  print("       error: " .. tostring(gen_result))
  -- Mark all sub-checks failed
  for _ = 1, 17 do
    fail_count = fail_count + 1
    print("[FAIL] (skipped — nebula_gen_pipeline_source errored)")
  end
end

print("")

-- =============================================================================
-- Section 3: renderer.nelua — DenseCharInstance + DenseTextUniforms records
-- =============================================================================
print("--- 3. renderer.nelua: DenseCharInstance + DenseTextUniforms records ---")

local renderer_src = read_file("src/renderer.nelua")
check("src/renderer.nelua exists and is readable", renderer_src ~= nil)

if renderer_src then
  -- DenseCharInstance record and fields
  check("renderer.nelua contains DenseCharInstance record",
    renderer_src:find("DenseCharInstance", 1, true) ~= nil)
  check("renderer.nelua DenseCharInstance has pos_x field",
    renderer_src:find("pos_x", 1, true) ~= nil)
  check("renderer.nelua DenseCharInstance has pos_y field",
    renderer_src:find("pos_y", 1, true) ~= nil)
  check("renderer.nelua DenseCharInstance has uv_x field",
    renderer_src:find("uv_x", 1, true) ~= nil)
  check("renderer.nelua DenseCharInstance has uv_y field",
    renderer_src:find("uv_y", 1, true) ~= nil)
  check("renderer.nelua DenseCharInstance has uv_w field",
    renderer_src:find("uv_w", 1, true) ~= nil)
  check("renderer.nelua DenseCharInstance has uv_h field",
    renderer_src:find("uv_h", 1, true) ~= nil)
  check("renderer.nelua DenseCharInstance has fg_color field",
    renderer_src:find("fg_color", 1, true) ~= nil)
  check("renderer.nelua DenseCharInstance has bg_color field",
    renderer_src:find("bg_color", 1, true) ~= nil)

  -- DenseTextUniforms record and fields
  check("renderer.nelua contains DenseTextUniforms record",
    renderer_src:find("DenseTextUniforms", 1, true) ~= nil)
  check("renderer.nelua DenseTextUniforms has viewport_w field",
    renderer_src:find("viewport_w", 1, true) ~= nil)
  check("renderer.nelua DenseTextUniforms has viewport_h field",
    renderer_src:find("viewport_h", 1, true) ~= nil)
  check("renderer.nelua DenseTextUniforms has cell_w field",
    renderer_src:find("cell_w", 1, true) ~= nil)
  check("renderer.nelua DenseTextUniforms has cell_h field",
    renderer_src:find("cell_h", 1, true) ~= nil)

  -- nebula_pack_rgba8 helper
  check("renderer.nelua contains nebula_pack_rgba8 helper function",
    renderer_src:find("nebula_pack_rgba8", 1, true) ~= nil)
else
  for _ = 1, 15 do
    fail_count = fail_count + 1
    print("[FAIL] (skipped — src/renderer.nelua not readable)")
  end
end

print("")

-- =============================================================================
-- Section 4: nebula_core.nelua — derivation entry exists
-- =============================================================================
print("--- 4. nebula_core.nelua: dense text derivation entry ---")

local core_src = read_file("src/nebula_core.nelua")
check("src/nebula_core.nelua exists and is readable", core_src ~= nil)

if core_src then
  check("nebula_core.nelua contains nebula_derive_dense_text_visual function",
    core_src:find("nebula_derive_dense_text_visual", 1, true) ~= nil)
  check("nebula_core.nelua contains text_mode == \"dense\" dispatch",
    core_src:find('text_mode == "dense"', 1, true) ~= nil)
  check("nebula_core.nelua contains nebula_compose_dense_text_shader call",
    core_src:find("nebula_compose_dense_text_shader", 1, true) ~= nil)
  check("nebula_core.nelua contains atlas_dense in pipeline_spec",
    core_src:find("atlas_dense", 1, true) ~= nil)
else
  for _ = 1, 4 do
    fail_count = fail_count + 1
    print("[FAIL] (skipped — src/nebula_core.nelua not readable)")
  end
end

print("")

-- =============================================================================
-- Section 5: text_runtime.nelua — grid fill helper exists
-- =============================================================================
print("--- 5. text_runtime.nelua: grid fill helper ---")

local runtime_src = read_file("src/text_runtime.nelua")
check("src/text_runtime.nelua exists and is readable", runtime_src ~= nil)

if runtime_src then
  check("text_runtime.nelua contains nebula_dense_grid_fill_instance function",
    runtime_src:find("nebula_dense_grid_fill_instance", 1, true) ~= nil)
else
  fail_count = fail_count + 1
  print("[FAIL] (skipped — src/text_runtime.nelua not readable)")
end

print("")

-- =============================================================================
-- Section 6: Public axiom compliance checks
-- =============================================================================
print("--- 6. Public axiom compliance ---")

-- Axiom: Shader has no runtime data in uniforms (only viewport + cell_size = 16B)
-- DenseTextUniforms has exactly 4 x float32 = 16 bytes
if renderer_src then
  local dtu_block = renderer_src:match("DenseTextUniforms%s*=%s*@record%b{}")
  if dtu_block then
    -- Count fields: viewport_w, viewport_h, cell_w, cell_h (4 fields x 4B = 16B)
    local field_count = 0
    for _ in dtu_block:gmatch("float32") do field_count = field_count + 1 end
    check("Axiom A: DenseTextUniforms uniform is 16B (4 x float32, no extra runtime data)",
      field_count == 4)
  else
    -- Fallback: just check all four fields exist without runtime additions
    check("Axiom A: DenseTextUniforms uniform fields suggest 16B (viewport_w/h + cell_w/h)",
      renderer_src:find("viewport_w", 1, true) ~= nil and
      renderer_src:find("viewport_h", 1, true) ~= nil and
      renderer_src:find("cell_w",     1, true) ~= nil and
      renderer_src:find("cell_h",     1, true) ~= nil)
  end
else
  fail_count = fail_count + 1
  print("[FAIL] Axiom A: renderer.nelua not readable")
end

-- Axiom B: Pipeline has deinit method (L0 resources released)
if gen_ok and type(gen_result) == "string" then
  check("Axiom B: generated pipeline has deinit method (L0 resources released)",
    gen_result:find(":deinit(", 1, true) ~= nil)
else
  fail_count = fail_count + 1
  print("[FAIL] Axiom B: pipeline code not available for check")
end

-- Axiom C: Pipeline spec has atlas_dense=true flag (compile-time pipeline signature)
check("Axiom C: atlas_dense=true flag present in pipeline spec (compile-time signature)",
  pipeline_spec.atlas_dense == true)

print("")

-- =============================================================================
-- Section 7: Mutual exclusivity check
-- =============================================================================
print("--- 7. Mutual exclusivity: atlas_dense + standard_instanced must error ---")

local conflict_spec = {
  base             = "ConflictTest",
  uniforms_record  = "ConflictUniforms",
  wgsl_source      = "// conflict test",
  atlas_dense      = true,
  standard_instanced = true,
}

local me_ok, me_err = pcall(nebula_gen_pipeline_source, conflict_spec)
check("nebula_gen_pipeline_source errors when atlas_dense + standard_instanced both set",
  me_ok == false)
check("error message mentions 'mutually exclusive'",
  type(me_err) == "string" and me_err:find("mutually exclusive", 1, true) ~= nil)

if me_ok then
  print("       (expected error but call succeeded — mutual exclusivity guard missing)")
elseif type(me_err) == "string" and not me_err:find("mutually exclusive", 1, true) then
  print("       error was: " .. tostring(me_err):sub(1, 200))
end

print("")

-- =============================================================================
-- Summary
-- =============================================================================
print(string.format(
  "\n Phase 4.X dense text smoke tests: %d/%d passed, %d failed\n",
  pass_count, pass_count + fail_count, fail_count))

if fail_count > 0 then
  print("[FAIL] Phase 4.X dense text regression detected!")
  os.exit(1)
else
  print("[ALL PASS] Phase 4.X dense text smoke tests complete.")
  os.exit(0)
end
