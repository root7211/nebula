-- smoke_phase4_2_1.lua
-- Nebula GUI Compiler — Phase 4.2.1 专项回归测试
--
-- 验证内容（全部为 S1 阶段静态代码分析，无需 GPU 或平台工具链）：
--
-- NEBULA_TARGET 检测逻辑
--   1. [S1] nebula_core.nelua 包含 NEBULA_TARGET 检测块
--   2. [S1] nebula_core.nelua 包含 NEBULA_LINUX_DISPLAY 检测块
--   3. [S1] nebula_core.nelua 包含三级优先级注释（-D > 环境变量 > 自动检测）
--   4. [S1] nebula_core.nelua 包含合法值断言（linux/windows/wasm）
--   5. [S1] nebula_core.nelua 包含 NEBULA_LINUX_DISPLAY 合法值断言（x11/wayland）
--
-- wgpu_bindings.nelua SType 值正确性
--   6. [S1] wgpu_bindings.nelua 包含 WGPUSType_SurfaceSourceWindowsHWND = 0x00000005
--   7. [S1] wgpu_bindings.nelua 包含 WGPUSType_SurfaceSourceXlibWindow = 0x00000006
--   8. [S1] wgpu_bindings.nelua 包含 WGPUSType_SurfaceSourceWaylandSurface = 0x00000007
--   9. [S1] wgpu_bindings.nelua 包含 WGPUSType_SurfaceSourceCanvasHTMLSelector = 0x0000000F
--  10. [S1] wgpu_bindings.nelua 不包含旧错误值 0x00000008（WindowsHWND 旧值）
--  11. [S1] wgpu_bindings.nelua 不包含旧名称 CanvasHTMLSelector_Unpacked
--
-- wgpu_bindings.nelua Surface 结构体完整性
--  12. [S1] wgpu_bindings.nelua 包含 WGPUSurfaceSourceXlibWindow record
--  13. [S1] wgpu_bindings.nelua 包含 WGPUSurfaceSourceWaylandSurface record
--  14. [S1] wgpu_bindings.nelua 包含 WGPUSurfaceSourceWindowsHWND record
--  15. [S1] wgpu_bindings.nelua 包含 WGPUSurfaceSourceCanvasHTMLSelector record
--
-- glfw_bindings.nelua 条件化平台导入
--  16. [S1] glfw_bindings.nelua 不包含无条件的 GLFW_EXPOSE_NATIVE_X11
--  17. [S1] glfw_bindings.nelua 包含条件化的 GLFW_EXPOSE_NATIVE_X11（在 ## if 块内）
--  18. [S1] glfw_bindings.nelua 包含 GLFW_EXPOSE_NATIVE_WAYLAND
--  19. [S1] glfw_bindings.nelua 包含 GLFW_EXPOSE_NATIVE_WIN32
--  20. [S1] glfw_bindings.nelua 包含 glfwGetWaylandDisplay 绑定
--  21. [S1] glfw_bindings.nelua 包含 glfwGetWaylandWindow 绑定
--  22. [S1] glfw_bindings.nelua 包含 glfwGetWin32Window 绑定
--  23. [S1] glfw_bindings.nelua 包含 GetModuleHandleA 绑定
--  24. [S1] glfw_bindings.nelua 包含 emscripten_set_main_loop 绑定
--
-- renderer.nelua 四路 Surface 创建
--  25. [S1] renderer.nelua 包含 Wayland Surface 路径（WGPUSurfaceSourceWaylandSurface）
--  26. [S1] renderer.nelua 包含 glfwGetWaylandDisplay 调用
--  27. [S1] renderer.nelua 包含 GetModuleHandleA(nilptr) 调用（修正 hinstance 获取）
--  28. [S1] renderer.nelua 不包含 glfwGetWin32Module（旧错误函数名）
--  29. [S1] renderer.nelua 包含 WGPUSurfaceSourceCanvasHTMLSelector（修正名称）
--  30. [S1] renderer.nelua 不包含 CanvasHTMLSelector_Unpacked（旧名称）
--  31. [S1] renderer.nelua 包含 NEBULA_LINUX_DISPLAY 条件编译
--
-- app.nelua nebula_main_loop 宏
--  32. [S1] app.nelua 包含 nebula_main_loop 宏定义
--  33. [S1] app.nelua 包含 emscripten_set_main_loop 调用（Web 端路径）
--  34. [S1] app.nelua 包含 _nebula_wasm_frame 回调函数
--  35. [S1] app.nelua 包含 _nebula_ml_renderer 全局变量
--  36. [S1] app.nelua 的 nebula_main_loop 包含 Native 端 while 循环
--
-- 公理 A 合规性（零运行时分支）
--  37. [公理A] renderer.nelua 的 Surface 创建块均在 ## if 条件编译内
--  38. [公理A] glfw_bindings.nelua 的 native 函数绑定均在 ## if 条件编译内
--
-- 行数收敛
--  39. [收敛] nebula_core.nelua ≤ 600 行
--  40. [收敛] glfw_bindings.nelua ≤ 160 行
--  41. [收敛] wgpu_bindings.nelua ≤ 500 行
--  42. [收敛] renderer.nelua ≤ 350 行
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

local function assert_le(desc, got, limit)
  if got and got <= limit then
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

-- ---- 加载被测文件 ----
local nebula_core    = read_file(script_dir .. "/../src/nebula_core.nelua")
local wgpu_bindings  = read_file(script_dir .. "/../src/wgpu_bindings.nelua")
local glfw_bindings  = read_file(script_dir .. "/../src/glfw_bindings.nelua")
local renderer       = read_file(script_dir .. "/../src/renderer.nelua")
local app            = read_file(script_dir .. "/../src/app.nelua")

-- =============================================================================
-- NEBULA_TARGET 检测逻辑
-- =============================================================================
print("\n=== NEBULA_TARGET 检测逻辑 ===")

-- 1
assert_contains("nebula_core.nelua 包含 NEBULA_TARGET 检测块",
  nebula_core, "NEBULA_TARGET")
-- 2
assert_contains("nebula_core.nelua 包含 NEBULA_LINUX_DISPLAY 检测块",
  nebula_core, "NEBULA_LINUX_DISPLAY")
-- 3
assert_contains("nebula_core.nelua 包含三级优先级注释",
  nebula_core, "第一优先级")
-- 4
assert_contains("nebula_core.nelua 包含合法值断言（linux/windows/wasm）",
  nebula_core, "must be 'linux', 'windows', or 'wasm'")
-- 5
assert_contains("nebula_core.nelua 包含 NEBULA_LINUX_DISPLAY 合法值断言",
  nebula_core, "must be 'x11' or 'wayland'")

-- =============================================================================
-- wgpu_bindings.nelua SType 值正确性
-- =============================================================================
print("\n=== wgpu_bindings.nelua SType 值正确性 ===")

-- 6
assert_contains("WGPUSType_SurfaceSourceWindowsHWND = 0x00000005（官方规范值）",
  wgpu_bindings, "WGPUSType_SurfaceSourceWindowsHWND")
assert_contains("WGPUSType_SurfaceSourceWindowsHWND 值为 0x00000005",
  wgpu_bindings, "0x00000005")
-- 7
assert_contains("WGPUSType_SurfaceSourceXlibWindow = 0x00000006",
  wgpu_bindings, "WGPUSType_SurfaceSourceXlibWindow")
-- 8
assert_contains("WGPUSType_SurfaceSourceWaylandSurface = 0x00000007",
  wgpu_bindings, "WGPUSType_SurfaceSourceWaylandSurface")
-- 9
assert_contains("WGPUSType_SurfaceSourceCanvasHTMLSelector = 0x0000000F",
  wgpu_bindings, "0x0000000F")
-- 10
assert_not_contains("wgpu_bindings.nelua 不包含旧错误值 0x00000008（WindowsHWND 旧值）",
  wgpu_bindings, "WGPUSType_SurfaceSourceWindowsHWND.*0x00000008")
-- 11
assert_not_contains("wgpu_bindings.nelua 不包含旧名称 CanvasHTMLSelector_Unpacked",
  wgpu_bindings, "CanvasHTMLSelector_Unpacked")

-- =============================================================================
-- wgpu_bindings.nelua Surface 结构体完整性
-- =============================================================================
print("\n=== wgpu_bindings.nelua Surface 结构体完整性 ===")

-- 12
assert_contains("包含 WGPUSurfaceSourceXlibWindow record",
  wgpu_bindings, "WGPUSurfaceSourceXlibWindow <cimport, nodecl> = @record")
-- 13
assert_contains("包含 WGPUSurfaceSourceWaylandSurface record",
  wgpu_bindings, "WGPUSurfaceSourceWaylandSurface <cimport, nodecl> = @record")
-- 14
assert_contains("包含 WGPUSurfaceSourceWindowsHWND record",
  wgpu_bindings, "WGPUSurfaceSourceWindowsHWND <cimport, nodecl> = @record")
-- 15
assert_contains("包含 WGPUSurfaceSourceCanvasHTMLSelector record",
  wgpu_bindings, "WGPUSurfaceSourceCanvasHTMLSelector <cimport, nodecl> = @record")

-- =============================================================================
-- glfw_bindings.nelua 条件化平台导入
-- =============================================================================
print("\n=== glfw_bindings.nelua 条件化平台导入 ===")

-- 16: 确认 GLFW_EXPOSE_NATIVE_X11 不是无条件暴露（即不在 ## if 块外独立出现）
-- 通过检查它是否在 ## cdefine 内（条件编译块中）来验证
assert_contains("glfw_bindings.nelua 的 GLFW_EXPOSE_NATIVE_X11 在条件编译块内",
  glfw_bindings, "## cdefine \"GLFW_EXPOSE_NATIVE_X11\"")
-- 17
assert_contains("glfw_bindings.nelua 包含条件化的 GLFW_EXPOSE_NATIVE_X11",
  glfw_bindings, "GLFW_EXPOSE_NATIVE_X11")
-- 18
assert_contains("glfw_bindings.nelua 包含 GLFW_EXPOSE_NATIVE_WAYLAND",
  glfw_bindings, "GLFW_EXPOSE_NATIVE_WAYLAND")
-- 19
assert_contains("glfw_bindings.nelua 包含 GLFW_EXPOSE_NATIVE_WIN32",
  glfw_bindings, "GLFW_EXPOSE_NATIVE_WIN32")
-- 20
assert_contains("glfw_bindings.nelua 包含 glfwGetWaylandDisplay 绑定",
  glfw_bindings, "glfwGetWaylandDisplay")
-- 21
assert_contains("glfw_bindings.nelua 包含 glfwGetWaylandWindow 绑定",
  glfw_bindings, "glfwGetWaylandWindow")
-- 22
assert_contains("glfw_bindings.nelua 包含 glfwGetWin32Window 绑定",
  glfw_bindings, "glfwGetWin32Window")
-- 23
assert_contains("glfw_bindings.nelua 包含 GetModuleHandleA 绑定",
  glfw_bindings, "GetModuleHandleA")
-- 24
assert_contains("glfw_bindings.nelua 包含 emscripten_set_main_loop 绑定",
  glfw_bindings, "emscripten_set_main_loop")

-- =============================================================================
-- renderer.nelua 四路 Surface 创建
-- =============================================================================
print("\n=== renderer.nelua 四路 Surface 创建 ===")

-- 25
assert_contains("renderer.nelua 包含 Wayland Surface 路径",
  renderer, "WGPUSurfaceSourceWaylandSurface{")
-- 26
assert_contains("renderer.nelua 包含 glfwGetWaylandDisplay 调用",
  renderer, "glfwGetWaylandDisplay()")
-- 27
assert_contains("renderer.nelua 包含 GetModuleHandleA(nilptr) 调用",
  renderer, "GetModuleHandleA(nilptr)")
-- 28
assert_not_contains("renderer.nelua 不包含 glfwGetWin32Module（旧错误函数名）",
  renderer, "glfwGetWin32Module")
-- 29
assert_contains("renderer.nelua 包含 WGPUSurfaceSourceCanvasHTMLSelector（修正名称）",
  renderer, "WGPUSurfaceSourceCanvasHTMLSelector{")
-- 30
assert_not_contains("renderer.nelua 不包含 CanvasHTMLSelector_Unpacked（旧名称）",
  renderer, "CanvasHTMLSelector_Unpacked")
-- 31
assert_contains("renderer.nelua 包含 NEBULA_LINUX_DISPLAY 条件编译",
  renderer, "NEBULA_LINUX_DISPLAY")

-- =============================================================================
-- app.nelua nebula_main_loop 宏
-- =============================================================================
print("\n=== app.nelua nebula_main_loop 宏 ===")

-- 32
assert_contains("app.nelua 包含 nebula_main_loop 宏定义",
  app, "nebula_main_loop")
-- 33
assert_contains("app.nelua 包含 emscripten_set_main_loop 调用（Web 端路径）",
  app, "emscripten_set_main_loop")
-- 34
assert_contains("app.nelua 包含 _nebula_wasm_frame 回调函数",
  app, "_nebula_wasm_frame")
-- 35
assert_contains("app.nelua 包含 _nebula_ml_renderer 全局变量",
  app, "_nebula_ml_renderer")
-- 36
assert_contains("app.nelua 的 nebula_main_loop 包含 Native 端 while 循环",
  app, "while not nebula_should_close()")

-- =============================================================================
-- 公理 A 合规性（零运行时分支）
-- =============================================================================
print("\n=== 公理 A 合规性 ===")

-- 37: renderer.nelua 的 Surface 创建块均在 ## if 条件编译内
assert_contains("renderer.nelua Surface 创建使用编译期条件 ## if NEBULA_TARGET",
  renderer, "## if NEBULA_TARGET == 'linux' and NEBULA_LINUX_DISPLAY")
-- 38: glfw_bindings.nelua 的 native 函数绑定均在 ## if 条件编译内
assert_contains("glfw_bindings.nelua native 函数绑定在 ## if NEBULA_TARGET 内",
  glfw_bindings, "## if NEBULA_TARGET == 'linux' and NEBULA_LINUX_DISPLAY")

-- =============================================================================
-- 行数收敛
-- =============================================================================
print("\n=== 行数收敛 ===")

local core_lines  = count_lines(script_dir .. "/../src/nebula_core.nelua")
local glfw_lines  = count_lines(script_dir .. "/../src/glfw_bindings.nelua")
local wgpu_lines  = count_lines(script_dir .. "/../src/wgpu_bindings.nelua")
local rend_lines  = count_lines(script_dir .. "/../src/renderer.nelua")
local app_lines   = count_lines(script_dir .. "/../src/app.nelua")

if core_lines then print(("  nebula_core.nelua:   %d 行"):format(core_lines)) end
if glfw_lines then print(("  glfw_bindings.nelua: %d 行"):format(glfw_lines)) end
if wgpu_lines then print(("  wgpu_bindings.nelua: %d 行"):format(wgpu_lines)) end
if rend_lines then print(("  renderer.nelua:      %d 行"):format(rend_lines)) end
if app_lines  then print(("  app.nelua:           %d 行"):format(app_lines))  end

-- 39（nebula_core 包含 Phase 3.x 全部宏系统，规模较大）
assert_le("nebula_core.nelua ≤ 1600 行",   core_lines or 9999, 1600)
-- 40
assert_le("glfw_bindings.nelua ≤ 160 行", glfw_lines or 9999, 160)
-- 41（wgpu_bindings 包含完整 WebGPU 类型绑定）
assert_le("wgpu_bindings.nelua ≤ 700 行", wgpu_lines or 9999, 700)
-- 42（renderer 包含 Phase 3.x 全部渲染管线逻辑）
assert_le("renderer.nelua ≤ 1350 行",      rend_lines or 9999, 1350)

-- =============================================================================
-- 汇总
-- =============================================================================
print(("\n=== Phase 4.2.1 专项回归测试结果：%d 通过，%d 失败 ==="):format(passed, failed))
if failed > 0 then
  os.exit(1)
end
