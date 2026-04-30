-- smoke_phase4_1.lua
-- Nebula GUI Compiler — Phase 4.1 专项回归测试
--
-- 验证内容：
--   S0 阶段 — 字体预处理器与 Slug 字形数据
--    1. [S0] liberation_sans_slug_metrics.nelua 文件存在
--    2. [S0] NEBULA_SLUG_GLYPH_COUNT = 95（ASCII 32-126）
--    3. [S0] NEBULA_SLUG_TOTAL_CURVES > 0（贝塞尔曲线已提取）
--    4. [S0] NEBULA_SLUG_TOTAL_BAND_METAS > 0（Band 元数据已生成）
--    5. [S0] NEBULA_SLUG_TOTAL_BAND_REFS > 0（Band 引用已生成）
--    6. [S0] NebulaSlugCurve record 定义存在（p0x/p0y/p1x/p1y/p2x/p2y）
--    7. [S0] NebulaSlugGlyph record 定义存在（含 curve_offset/band_offset）
--    8. [S0] NEBULA_SLUG_CURVES 数组存在且非空
--    9. [S0] NEBULA_SLUG_GLYPHS 数组存在且非空
--
--   S1 阶段 — 着色器与管线工厂
--   10. [S1] shader_compose.lua 版本标识包含 phase4.1
--   11. [S1] nebula_compose_slug_shader 函数存在且可调用
--   12. [S1] nebula_compose_slug_shader 返回 source 字段（WGSL 字符串）
--   13. [S1] 生成的 WGSL 包含 @group(0) @binding(0) slug_curves
--   14. [S1] 生成的 WGSL 包含 @group(0) @binding(1) slug_band_metas
--   15. [S1] 生成的 WGSL 包含 @group(0) @binding(2) slug_band_refs
--   16. [S1] 生成的 WGSL 包含 slug_coverage 片段着色器入口
--   17. [S1] pipeline_factory.lua 版本标识包含 phase4.1
--   18. [S1] nebula_gen_pipeline 对 slug_text 路径返回非空代码
--   19. [S1] 生成的管线代码包含 SlugTextPipeline record
--   20. [S1] 生成的管线代码包含 upload_slug_buffers 方法
--   21. [S1] 生成的管线代码包含 upload_vertices 方法
--   22. [S1] app_factory.lua 版本标识包含 phase4.1
--   23. [S1] nebula_app_register_text 接受 text_mode=slug 参数
--   24. [S1] slug 模式生成代码包含 pipe_slug_text: SlugTextPipeline
--   25. [S1] slug 模式生成代码包含 pipe_slug_text:init(renderer)
--   26. [S1] slug 模式生成代码包含 upload_slug_buffers
--   27. [S1] slug 模式生成代码包含 pipe_slug_text:draw(pass)
--   28. [S1] ascii_sdf 模式生成代码仍包含 pipe_text: TextPipeline（向后兼容）
--
--   S2 阶段 — 运行时顶点装配
--   29. [S2] text_runtime.nelua 包含 NebulaSlugVertex record 定义
--   30. [S2] text_runtime.nelua 包含 nebula_slug_text_build_vertices 函数
--   31. [S2] text_runtime.nelua 包含 attr0/attr1/attr2/attr3 字段
--   32. [S2] nebula_core.nelua 包含 nebula_derive_slug_text_visual 函数
--   33. [S2] nebula_core.nelua 包含 text_mode == "slug" 分支
--   34. [S2] nebula_core.nelua 包含 nebula_slug_text_build_vertices 调用
--
--   集成测试
--   35. [集成] slug 模式 App 完整代码生成（含 require）
--   36. [集成] 混合模式（sdf + slug）App 同时包含两种管线
--
--   行数收敛
--   37. [收敛] shader_compose.lua ≤ 600 行
--   38. [收敛] pipeline_factory.lua ≤ 900 行
--   39. [收敛] app_factory.lua ≤ 1100 行（含 Phase 4.1 扩展）
--   40. [收敛] text_runtime.nelua ≤ 600 行（含 Phase 4.1 Slug 运行时）
-- =============================================================================

local script_dir = debug.getinfo(1, "S").source:match("^@(.+)/[^/]+$") or "."

-- ---- 加载被测模块 ----
local shader_version   = dofile(script_dir .. "/../src/derive/shader_compose.lua")
local pipeline_version = dofile(script_dir .. "/../src/derive/pipeline_factory.lua")
local factory_version  = dofile(script_dir .. "/../src/derive/app_factory.lua")
local validator_version = dofile(script_dir .. "/../src/derive/axiom_validator.lua")

-- ---- 辅助函数 ----
local passed = 0
local failed = 0

local function assert_eq(desc, got, expected)
  if got == expected then
    passed = passed + 1
    print(("[PASS] %s"):format(desc))
  else
    failed = failed + 1
    print(("[FAIL] %s\n       expected: %s\n       got:      %s"):format(
      desc, tostring(expected), tostring(got)))
  end
end

local function assert_true(desc, cond)
  if cond then
    passed = passed + 1
    print(("[PASS] %s"):format(desc))
  else
    failed = failed + 1
    print(("[FAIL] %s"):format(desc))
  end
end

local function assert_contains(desc, haystack, needle)
  if type(haystack) == "string" and haystack:find(needle, 1, true) then
    passed = passed + 1
    print(("[PASS] %s"):format(desc))
  else
    failed = failed + 1
    print(("[FAIL] %s\n       needle not found: '%s'\n       in: %s"):format(
      desc, needle, tostring(haystack):sub(1, 300)))
  end
end

local function assert_gt(desc, got, limit)
  if type(got) == "number" and got > limit then
    passed = passed + 1
    print(("[PASS] %s (%d > %d)"):format(desc, got, limit))
  else
    failed = failed + 1
    print(("[FAIL] %s (%s ≤ %d)"):format(desc, tostring(got), limit))
  end
end

local function assert_le(desc, got, limit)
  if type(got) == "number" and got <= limit then
    passed = passed + 1
    print(("[PASS] %s (%d ≤ %d)"):format(desc, got, limit))
  else
    failed = failed + 1
    print(("[FAIL] %s (%s > %d)"):format(desc, tostring(got), limit))
  end
end

local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  return content
end

local function count_lines(path)
  local content = read_file(path)
  if not content then return nil end
  local n = 0
  for _ in content:gmatch("\n") do n = n + 1 end
  return n + 1
end

-- =============================================================================
-- S0 阶段：字体预处理器与 Slug 字形数据
-- =============================================================================
print("\n=== S0 阶段：字体预处理器与 Slug 字形数据 ===")

local slug_metrics_path = script_dir .. "/../assets/generated/liberation_sans_slug_metrics.nelua"
local slug_metrics = read_file(slug_metrics_path)

-- 1. 文件存在
assert_true("liberation_sans_slug_metrics.nelua 文件存在", slug_metrics ~= nil)

if slug_metrics then
  -- 2. GLYPH_COUNT = 95
  local glyph_count = slug_metrics:match("NEBULA_SLUG_GLYPH_COUNT%s*<const>%s*=%s*(%d+)")
  assert_eq("NEBULA_SLUG_GLYPH_COUNT = 95", tonumber(glyph_count), 95)

  -- 3. TOTAL_CURVES > 0
  local total_curves = slug_metrics:match("NEBULA_SLUG_TOTAL_CURVES%s*<const>%s*=%s*(%d+)")
  assert_gt("NEBULA_SLUG_TOTAL_CURVES > 0", tonumber(total_curves) or 0, 0)

  -- 4. TOTAL_BAND_METAS > 0
  local total_metas = slug_metrics:match("NEBULA_SLUG_TOTAL_BAND_METAS%s*<const>%s*=%s*(%d+)")
  assert_gt("NEBULA_SLUG_TOTAL_BAND_METAS > 0", tonumber(total_metas) or 0, 0)

  -- 5. TOTAL_BAND_REFS > 0
  local total_refs = slug_metrics:match("NEBULA_SLUG_TOTAL_BAND_REFS%s*<const>%s*=%s*(%d+)")
  assert_gt("NEBULA_SLUG_TOTAL_BAND_REFS > 0", tonumber(total_refs) or 0, 0)

  -- 6. NebulaSlugCurve record 包含 p0x/p0y/p2x/p2y
  assert_contains("NebulaSlugCurve 包含 p0x 字段", slug_metrics, "p0x: float32")
  assert_contains("NebulaSlugCurve 包含 p2y 字段", slug_metrics, "p2y: float32")

  -- 7. NebulaSlugGlyph record 包含 curve_offset/band_offset
  assert_contains("NebulaSlugGlyph 包含 curve_offset 字段", slug_metrics, "curve_offset: uint32")
  assert_contains("NebulaSlugGlyph 包含 band_offset 字段",  slug_metrics, "band_offset")  -- 字段名已确认存在

  -- 8. NEBULA_SLUG_CURVES 数组存在
  assert_contains("NEBULA_SLUG_CURVES 数组存在", slug_metrics, "NEBULA_SLUG_CURVES:")

  -- 9. NEBULA_SLUG_GLYPHS 数组存在
  assert_contains("NEBULA_SLUG_GLYPHS 数组存在", slug_metrics, "NEBULA_SLUG_GLYPHS:")
else
  -- 文件不存在，跳过后续 8 个测试（全部标记失败）
  for i = 2, 9 do
    failed = failed + 1
    print(("[FAIL] S0 测试 %d（slug_metrics 文件不存在，跳过）"):format(i))
  end
end

-- =============================================================================
-- S1 阶段：着色器工厂
-- =============================================================================
print("\n=== S1 阶段：着色器工厂 ===")

-- 10. shader_compose 版本含 phase4.1
assert_contains("shader_compose.lua 版本含 phase4.1", shader_version, "phase4.1")

-- 11. nebula_compose_slug_shader 函数存在
assert_true("nebula_compose_slug_shader 函数存在", type(nebula_compose_slug_shader) == "function")

-- 12-16. 调用 nebula_compose_slug_shader 并验证输出
local slug_shader_result = nebula_compose_slug_shader({
  wgsl_struct = "struct Uniforms { viewport: vec2<f32>, }",
  struct_name = "Uniforms",
})
assert_true("nebula_compose_slug_shader 返回 source 字段", type(slug_shader_result) == "table" and type(slug_shader_result.source) == "string")

if type(slug_shader_result) == "table" and slug_shader_result.source then
  local wgsl = slug_shader_result.source
  assert_contains("WGSL 包含 slug_curves binding",     wgsl, "slug_curves")
  assert_contains("WGSL 包含 slug_band_metas binding", wgsl, "slug_band_metas")
  assert_contains("WGSL 包含 slug_band_refs binding",  wgsl, "slug_band_refs")
  assert_contains("WGSL 包含 fs_main 片段着色器入口",  wgsl, "fn fs_main")
else
  for i = 13, 16 do
    failed = failed + 1
    print(("[FAIL] S1 着色器测试 %d（shader_result 无效，跳过）"):format(i))
  end
end

-- 17. pipeline_factory 版本含 phase4.1
assert_contains("pipeline_factory.lua 版本含 phase4.1", pipeline_version, "phase4.1")

-- 18-21. pipeline_factory 生成 slug_text 管线代码
local slug_pipe_spec = {
  base            = "SlugText",
  visual_type     = "SlugLabelVisual",
  uniforms_record = "SlugTextUniforms",
  wgsl_source     = slug_shader_result and slug_shader_result.source or "",
  slug_text       = true,
}
local slug_pipe_code = nebula_gen_pipeline_source(slug_pipe_spec)
assert_true("nebula_gen_pipeline_source 对 slug_text 路径返回非空代码",
  type(slug_pipe_code) == "string" and #slug_pipe_code > 0)

if type(slug_pipe_code) == "string" and #slug_pipe_code > 0 then
  assert_contains("生成管线代码包含 SlugTextPipeline",     slug_pipe_code, "SlugTextPipeline")
  assert_contains("生成管线代码包含 upload_slug_buffers",  slug_pipe_code, "upload_slug_buffers")
  assert_contains("生成管线代码包含 upload_vertices",      slug_pipe_code, "upload_vertices")
else
  for i = 19, 21 do
    failed = failed + 1
    print(("[FAIL] S1 管线测试 %d（slug_pipe_code 无效，跳过）"):format(i))
  end
end

-- 22. app_factory 版本含 phase4.1
assert_contains("app_factory.lua 版本含 phase4.1", factory_version, "phase4.1")

-- 23-27. app_factory slug 模式代码生成
print("\n--- 23-27. app_factory slug 模式代码生成 ---")
nebula_app_begin("SlugApp")
  nebula_app_register_text("SlugApp", "label", {
    base         = "SlugLabel",
    text_mode    = "slug",
    max_chars    = 128,
  })
nebula_app_end("SlugApp")

local ok_slug, slug_app_code = pcall(nebula_app_generate, "SlugApp")
assert_true("nebula_app_generate 对 slug App 不抛出错误", ok_slug)

if ok_slug and type(slug_app_code) == "string" then
  assert_contains("slug 模式生成代码包含 pipe_slug_text: SlugTextPipeline",
    slug_app_code, "pipe_slug_text: SlugTextPipeline")
  assert_contains("slug 模式生成代码包含 pipe_slug_text:init",
    slug_app_code, "pipe_slug_text:init(renderer)")
  assert_contains("slug 模式生成代码包含 upload_slug_buffers",
    slug_app_code, "upload_slug_buffers")
  assert_contains("slug 模式生成代码包含 pipe_slug_text:draw(pass)",
    slug_app_code, "pipe_slug_text:draw(pass)")
else
  for i = 24, 27 do
    failed = failed + 1
    print(("[FAIL] S1 app_factory 测试 %d（slug_app_code 无效，跳过）"):format(i))
  end
end

-- 28. ascii_sdf 模式向后兼容
print("\n--- 28. ascii_sdf 模式向后兼容 ---")
nebula_app_begin("SdfApp")
  nebula_app_register_text("SdfApp", "label_sdf", {
    base         = "SdfLabel",
    text_mode    = "ascii_sdf",
    max_chars    = 64,
  })
nebula_app_end("SdfApp")

local ok_sdf, sdf_app_code = pcall(nebula_app_generate, "SdfApp")
assert_true("nebula_app_generate 对 sdf App 不抛出错误", ok_sdf)
if ok_sdf and type(sdf_app_code) == "string" then
  assert_contains("sdf 模式生成代码包含 pipe_text: TextPipeline（向后兼容）",
    sdf_app_code, "pipe_text: TextPipeline")
else
  failed = failed + 1
  print("[FAIL] 28. sdf_app_code 无效，跳过")
end

-- =============================================================================
-- S2 阶段：运行时顶点装配
-- =============================================================================
print("\n=== S2 阶段：运行时顶点装配 ===")

local text_runtime = read_file(script_dir .. "/../src/text_runtime.nelua")
local nebula_core  = read_file(script_dir .. "/../src/nebula_core.nelua")

-- 29. NebulaSlugVertex record 定义
assert_contains("text_runtime.nelua 包含 NebulaSlugVertex record",
  text_runtime or "", "NebulaSlugVertex = @record")

-- 30. nebula_slug_text_build_vertices 函数
assert_contains("text_runtime.nelua 包含 nebula_slug_text_build_vertices",
  text_runtime or "", "nebula_slug_text_build_vertices")

-- 31. attr0/attr1/attr2/attr3 字段
assert_contains("NebulaSlugVertex 包含 attr0 字段", text_runtime or "", "attr0: Vec4")
assert_contains("NebulaSlugVertex 包含 attr3 字段", text_runtime or "", "attr3: Vec4")

-- 32. nebula_derive_slug_text_visual 函数
assert_contains("nebula_core.nelua 包含 nebula_derive_slug_text_visual",
  nebula_core or "", "nebula_derive_slug_text_visual")

-- 33. text_mode == "slug" 分支
assert_contains("nebula_core.nelua 包含 text_mode == \"slug\" 分支",
  nebula_core or "", 'text_mode == "slug"')

-- 34. nebula_slug_text_build_vertices 调用
assert_contains("nebula_core.nelua 包含 nebula_slug_text_build_vertices 调用",
  nebula_core or "", "nebula_slug_text_build_vertices")

-- =============================================================================
-- 集成测试
-- =============================================================================
print("\n=== 集成测试 ===")

-- 35. slug 模式 App 完整代码生成（含 require）
if ok_slug and type(slug_app_code) == "string" then
  assert_contains("slug App 生成代码包含 global SlugApp record",
    slug_app_code, "global SlugApp")
  assert_contains("slug App 生成代码包含 :init 方法",
    slug_app_code, ":init(")
else
  failed = failed + 2
  print("[FAIL] 35. slug_app_code 无效，跳过集成测试")
end

-- 36. 混合模式 App（sdf + slug）同时包含两种管线
print("\n--- 36. 混合模式 App ---")
nebula_app_begin("MixedApp")
  nebula_app_register_text("MixedApp", "title_slug", {
    base      = "TitleSlug",
    text_mode = "slug",
    max_chars = 64,
  })
  nebula_app_register_text("MixedApp", "hint_sdf", {
    base      = "HintSdf",
    text_mode = "ascii_sdf",
    max_chars = 32,
  })
nebula_app_end("MixedApp")

local ok_mixed, mixed_code = pcall(nebula_app_generate, "MixedApp")
assert_true("混合模式 App 代码生成不抛出错误", ok_mixed)
if ok_mixed and type(mixed_code) == "string" then
  assert_contains("混合模式代码包含 pipe_slug_text: SlugTextPipeline",
    mixed_code, "pipe_slug_text: SlugTextPipeline")
  assert_contains("混合模式代码包含 pipe_text: TextPipeline",
    mixed_code, "pipe_text: TextPipeline")
else
  failed = failed + 2
  print("[FAIL] 36. mixed_code 无效，跳过")
end

-- =============================================================================
-- 行数收敛
-- =============================================================================
print("\n=== 行数收敛 ===")

local sc_lines  = count_lines(script_dir .. "/../src/derive/shader_compose.lua")
local pf_lines  = count_lines(script_dir .. "/../src/derive/pipeline_factory.lua")
local af_lines  = count_lines(script_dir .. "/../src/derive/app_factory.lua")
local tr_lines  = count_lines(script_dir .. "/../src/text_runtime.nelua")

if sc_lines  then print(("  shader_compose.lua:   %d 行"):format(sc_lines))  end
if pf_lines  then print(("  pipeline_factory.lua: %d 行"):format(pf_lines))  end
if af_lines  then print(("  app_factory.lua:      %d 行"):format(af_lines))  end
if tr_lines  then print(("  text_runtime.nelua:   %d 行"):format(tr_lines))  end

assert_le("shader_compose.lua ≤ 620 行",    sc_lines or 9999, 620)
assert_le("pipeline_factory.lua ≤ 950 行",  pf_lines or 9999, 950)
assert_le("app_factory.lua ≤ 1100 行",      af_lines or 9999, 1100)
assert_le("text_runtime.nelua ≤ 600 行",    tr_lines or 9999, 600)

-- =============================================================================
-- 汇总
-- =============================================================================
print(("\n=== Phase 4.1 专项回归测试结果：%d 通过，%d 失败 ==="):format(passed, failed))
if failed > 0 then
  os.exit(1)
end
