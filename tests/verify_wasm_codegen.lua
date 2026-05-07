-- =============================================================================
-- verify_wasm_codegen.lua
-- 验证 WASM 条件编译路径的代码生成正确性
--
-- 检查：
--   1. renderer.nelua WASM 分支存在 CanvasHTMLSelector 路径
--   2. app.nelua WASM 分支存在 emscripten_set_main_loop 调用
--   3. glfw_bindings.nelua WASM 分支存在 emscripten.h include
--   4. build_wasm.sh 存在且包含正确的 emcc 标志
--   5. web/shell.html 存在且包含 nebula-canvas
-- =============================================================================

local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  return content
end

local function assert_contains(content, pattern, file, desc)
  assert(content:find(pattern, 1, true),
    string.format("%s: missing %s", file, desc))
end

-- 1. renderer.nelua — WASM Surface 路径
local renderer = read_file("src/renderer.nelua")
assert(renderer, "src/renderer.nelua not found")
assert_contains(renderer, "WGPUSurfaceSourceCanvasHTMLSelector", "renderer.nelua", "Canvas HTML Selector surface")
assert_contains(renderer, "#nebula-canvas", "renderer.nelua", "canvas element selector")
assert_contains(renderer, "NEBULA_TARGET == 'wasm'", "renderer.nelua", "WASM conditional branch")

-- 2. app.nelua — emscripten main loop
local app = read_file("src/app.nelua")
assert(app, "src/app.nelua not found")
assert_contains(app, "emscripten_set_main_loop", "app.nelua", "emscripten main loop")
assert_contains(app, "_nebula_wasm_frame", "app.nelua", "WASM frame callback")

-- 3. glfw_bindings.nelua — emscripten header
local glfw = read_file("src/glfw_bindings.nelua")
assert(glfw, "src/glfw_bindings.nelua not found")
assert_contains(glfw, "emscripten.h", "glfw_bindings.nelua", "emscripten.h include")

-- 4. build_wasm.sh
local build = read_file("build_wasm.sh")
assert(build, "build_wasm.sh not found")
assert_contains(build, "USE_WEBGPU=1", "build_wasm.sh", "-sUSE_WEBGPU=1 flag")
assert_contains(build, "USE_GLFW=3", "build_wasm.sh", "-sUSE_GLFW=3 flag")
assert_contains(build, "preload-file", "build_wasm.sh", "asset preloading")
assert_contains(build, "shell-file", "build_wasm.sh", "HTML shell template")

-- 5. web/shell.html
local shell = read_file("web/shell.html")
assert(shell, "web/shell.html not found")
assert_contains(shell, 'id="nebula-canvas"', "web/shell.html", "canvas element")
assert_contains(shell, "navigator.gpu", "web/shell.html", "WebGPU feature detection")
assert_contains(shell, "{{{ SCRIPT }}}", "web/shell.html", "Emscripten script placeholder")

print("verify_wasm_codegen: ALL 5 checks passed")
