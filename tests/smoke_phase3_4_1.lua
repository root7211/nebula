-- =============================================================================
-- smoke_phase3_4_1.lua
-- Phase 3.4.1 冒烟测试：键盘事件收集基础设施
-- =============================================================================

local pass = 0
local fail = 0

local function check(name, cond)
  if cond then
    pass = pass + 1
    -- print("  [PASS] " .. name)
  else
    fail = fail + 1
    print("  [FAIL] " .. name)
  end
end

-- ---- 1. glfw_bindings.nelua 键盘常量 ----
local glfw = io.open("src/glfw_bindings.nelua", "r")
assert(glfw, "glfw_bindings.nelua not found")
local glfw_src = glfw:read("*a")
glfw:close()

check("GLFW_KEY_BACKSPACE defined", glfw_src:find("GLFW_KEY_BACKSPACE%s*<comptime>%s*=%s*259") ~= nil)
check("GLFW_KEY_DELETE defined",    glfw_src:find("GLFW_KEY_DELETE%s*<comptime>%s*=%s*261") ~= nil)
check("GLFW_KEY_ENTER defined",     glfw_src:find("GLFW_KEY_ENTER%s*<comptime>%s*=%s*257") ~= nil)
check("GLFW_KEY_TAB defined",       glfw_src:find("GLFW_KEY_TAB%s*<comptime>%s*=%s*258") ~= nil)
check("GLFW_KEY_ESCAPE defined",    glfw_src:find("GLFW_KEY_ESCAPE%s*<comptime>%s*=%s*256") ~= nil)
check("GLFW_KEY_LEFT defined",      glfw_src:find("GLFW_KEY_LEFT%s*<comptime>%s*=%s*263") ~= nil)
check("GLFW_KEY_RIGHT defined",     glfw_src:find("GLFW_KEY_RIGHT%s*<comptime>%s*=%s*262") ~= nil)
check("GLFW_KEY_HOME defined",      glfw_src:find("GLFW_KEY_HOME%s*<comptime>%s*=%s*268") ~= nil)
check("GLFW_KEY_END defined",       glfw_src:find("GLFW_KEY_END%s*<comptime>%s*=%s*269") ~= nil)
check("glfwSetKeyCallback declared",  glfw_src:find("glfwSetKeyCallback") ~= nil)
check("glfwSetCharCallback declared", glfw_src:find("glfwSetCharCallback") ~= nil)
check("GLFWkeyfun type declared",     glfw_src:find("GLFWkeyfun") ~= nil)
check("GLFWcharfun type declared",    glfw_src:find("GLFWcharfun") ~= nil)

-- ---- 2. nebula_types.nelua NebulaKey 枚举 ----
local core = io.open("src/nebula_types.nelua", "r")
assert(core, "nebula_types.nelua not found")
local core_src = core:read("*a")
core:close()

check("NebulaKey enum defined",       core_src:find("NebulaKey%s*=%s*@enum") ~= nil)
check("NebulaKey.None = 0",           core_src:find("None%s*=%s*0") ~= nil)
check("NebulaKey.Backspace = 1",      core_src:find("Backspace%s*=%s*1") ~= nil)
check("NebulaKey.Enter = 3",          core_src:find("Enter%s*=%s*3") ~= nil)
check("NebulaKey.Left = 6",           core_src:find("Left%s*=%s*6") ~= nil)
check("NebulaKey.Right = 7",          core_src:find("Right%s*=%s*7") ~= nil)
check("NebulaInputState.char_input",  core_src:find("char_input") ~= nil)
check("NebulaInputState.char_count",  core_src:find("char_count") ~= nil)
check("NebulaInputState.key_pressed", core_src:find("key_pressed") ~= nil)

-- ---- 3. app.nelua 回调与收集逻辑 ----
local app = io.open("src/app.nelua", "r")
assert(app, "app.nelua not found")
local app_src = app:read("*a")
app:close()

check("_nebula_char_callback defined",       app_src:find("_nebula_char_callback") ~= nil)
check("_nebula_key_callback defined",        app_src:find("_nebula_key_callback") ~= nil)
check("nebula_input_install_callbacks",      app_src:find("nebula_input_install_callbacks") ~= nil)
check("glfwSetCharCallback called",          app_src:find("glfwSetCharCallback%(window") ~= nil)
check("glfwSetKeyCallback called",           app_src:find("glfwSetKeyCallback%(window") ~= nil)
check("char_count cleared each frame",       app_src:find("char_count%s*=%s*0") ~= nil)
check("key_pressed set to None on no key",   app_src:find("NebulaKey%.None") ~= nil)
check("char queue ring buffer uses NEBULA_INPUT_QUEUE_SIZE",
  app_src:find("%%%s*NEBULA_INPUT_QUEUE_SIZE") ~= nil)
check("key queue ring buffer uses NEBULA_INPUT_QUEUE_SIZE",
  app_src:find("%%%s*NEBULA_INPUT_QUEUE_SIZE") ~= nil)
check("GLFW_RELEASE guard in key callback",  app_src:find("GLFW_RELEASE") ~= nil)

-- ---- 汇总 ----
print(string.format("[Phase 3.4.1] %d passed, %d failed", pass, fail))
assert(fail == 0, "Phase 3.4.1 smoke test FAILED")
