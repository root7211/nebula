-- =============================================================================
-- smoke_json_viewer.lua
-- Nebula GUI Compiler — Phase 4.X-J
--
-- JSON Viewer compile-time verification:
--   · DenseText pipeline generation for line_nums + content
--   · App factory: dual DenseText + standard_instanced coexistence
--   · Layout: flex_basis (line_nums) + flex_grow (content)
--   · Scrollable primitive on read-only Visual (no editable)
--   · Framework/application separation: no new src/ files
-- =============================================================================

local pass = 0
local fail = 0

local function check(desc, cond)
  if cond then
    pass = pass + 1
    print("[PASS] " .. desc)
  else
    fail = fail + 1
    print("[FAIL] " .. desc)
  end
end

local function approx(a, b, eps)
  eps = eps or 0.1
  return math.abs(a - b) < eps
end

local script_dir = (debug.getinfo(1, "S").source:match("^@(.+/)[^/]+$") or "./"):gsub("/$", "")

-- =============================================================================
-- 1. Module loading
-- =============================================================================
local layout_path = script_dir .. "/../src/derive/layout_engine.lua"
local layout_ver = dofile(layout_path)
check("layout_engine loaded", layout_ver ~= nil)

local factory_path = script_dir .. "/../src/derive/app_factory.lua"
local factory_ver = dofile(factory_path)
check("app_factory loaded", factory_ver ~= nil)

local pipeline_path = script_dir .. "/../src/derive/pipeline_factory.lua"
local pipeline_ver = dofile(pipeline_path)
check("pipeline_factory loaded", pipeline_ver ~= nil)

local shader_path = script_dir .. "/../src/derive/shader_compose.lua"
local shader_ver = dofile(shader_path)
check("shader_compose loaded", shader_ver ~= nil)

-- =============================================================================
-- 2. Layout: flex_basis + flex_grow for line_nums + content
-- =============================================================================
local root = nebula_layout_node({
  name = "_root",
  direction = "row",
  width = 1280,
  height = 800,
  children = {
    nebula_layout_node({ name = "line_nums", flex_basis = 60 }),
    nebula_layout_node({ name = "content",   flex_grow = 1 }),
  },
})
nebula_layout_solve(root)
local result = nebula_layout_collect(root)

check("Layout: line_nums.x = 0",
  result.line_nums and approx(result.line_nums.x, 0))
check("Layout: line_nums.w = 60 (flex_basis)",
  result.line_nums and approx(result.line_nums.w, 60))
check("Layout: content.x = 60",
  result.content and approx(result.content.x, 60))
check("Layout: content.w = 1220 (remaining after basis)",
  result.content and approx(result.content.w, 1220))

-- =============================================================================
-- 3. DenseText pipeline: shader generation
-- =============================================================================
local dense_result = nebula_compose_dense_text_shader()
local dense_shader = dense_result and dense_result.source or nil
check("DenseText shader generated", dense_shader ~= nil and #dense_shader > 0)
check("DenseText shader has vertex entry",
  dense_shader and dense_shader:find("@vertex") ~= nil)
check("DenseText shader has fragment entry",
  dense_shader and dense_shader:find("@fragment") ~= nil)
check("DenseText shader uses Storage Buffer",
  dense_shader and dense_shader:find("storage") ~= nil)

-- =============================================================================
-- 4. DenseText pipeline: verify pipeline_factory source contains dense_text
-- =============================================================================
local pf = io.open(script_dir .. "/../src/derive/pipeline_factory.lua", "r")
local pf_src = pf and pf:read("*a") or ""
if pf then pf:close() end

check("pipeline_factory has gen_pipeline_dense_text",
  pf_src:find("gen_pipeline_dense_text") ~= nil)
check("pipeline_factory has DenseText init method",
  pf_src:find("function.-DenseTextPipeline.-:init") ~= nil)
check("pipeline_factory has DenseText upload method",
  pf_src:find("function.-DenseTextPipeline.-:upload") ~= nil)
check("pipeline_factory has DenseText draw method",
  pf_src:find("function.-DenseTextPipeline.-:draw") ~= nil)
check("pipeline_factory has DenseText deinit method",
  pf_src:find("function.-DenseTextPipeline.-:deinit") ~= nil)

-- =============================================================================
-- 5. Framework/application separation: no JSON files in src/
-- =============================================================================
local function file_exists(path)
  local f = io.open(path, "r")
  if f then f:close() return true end
  return false
end

check("json_parser NOT in src/ (application layer)",
  not file_exists(script_dir .. "/../src/json_parser.nelua"))
check("json_tree NOT in src/ (application layer)",
  not file_exists(script_dir .. "/../src/json_tree.nelua"))
check("json_parser exists in examples/json_viewer/",
  file_exists(script_dir .. "/../examples/json_viewer/json_parser.nelua"))
check("json_tree exists in examples/json_viewer/",
  file_exists(script_dir .. "/../examples/json_viewer/json_tree.nelua"))
check("json_viewer_demo exists in examples/",
  file_exists(script_dir .. "/../examples/json_viewer_demo.nelua"))

-- =============================================================================
-- 6. Build script: json_viewer_demo target registered
-- =============================================================================
local build_f = io.open(script_dir .. "/../build.sh", "r")
local build_content = build_f and build_f:read("*a") or ""
if build_f then build_f:close() end

check("build.sh includes json_viewer_demo target",
  build_content:find("json_viewer_demo") ~= nil)
check("build.sh adds json_viewer search path",
  build_content:find("examples/json_viewer") ~= nil)

-- =============================================================================
-- 7. Scrollable primitive on read-only Visual (no editable/focusable)
-- =============================================================================
-- Verify that scrollable works without editable by checking NEBULA_PRIMITIVES
local interaction_path = script_dir .. "/../src/derive/interaction_factory.lua"
local interaction_ver = dofile(interaction_path)
check("interaction_factory loaded", interaction_ver ~= nil)
check("scrollable primitive registered",
  NEBULA_PRIMITIVES and NEBULA_PRIMITIVES["scrollable"] ~= nil)
check("clickable primitive registered",
  NEBULA_PRIMITIVES and NEBULA_PRIMITIVES["clickable"] ~= nil)
check("hoverable primitive registered",
  NEBULA_PRIMITIVES and NEBULA_PRIMITIVES["hoverable"] ~= nil)

-- =============================================================================
-- Summary
-- =============================================================================
print("")
print(string.format("--- smoke_json_viewer results: %d passed, %d failed ---", pass, fail))
if fail > 0 then
  error(string.format("[REGRESSION] %d test(s) failed", fail))
end
