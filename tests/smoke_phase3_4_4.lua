-- =============================================================================
-- smoke_phase3_4_4.lua
-- Phase 3.9 冒烟测试：login_demo 升级验证（Phase 3.4.4 → Phase 3.9）
--
-- ★ Phase 3.9 重写：
--   原 Phase 3.4.4 测试断言手动 process_text_input / draw_buffer / TextPipeline 存在。
--   现在 login_demo 已升级到 Phase 3.9 App 编排体系，上述手动调用已被
--   nebula_derive_app + nebula_app_register_text + nebula_frame_render 取代。
--   本测试更新为断言 Phase 3.9 API 的正确使用。
-- =============================================================================

local pass = 0
local fail = 0

local function check(name, cond)
  if cond then
    pass = pass + 1
  else
    fail = fail + 1
    print("  [FAIL] " .. name)
  end
end

local f = io.open("examples/login_demo.nelua", "r")
assert(f, "login_demo.nelua not found")
local src = f:read("*a")
f:close()

-- ---- 1. Phase 3.9: App 编排体系接入 ----
check("nebula_app_begin called",
  src:find("nebula_app_begin%(") ~= nil)
check("nebula_app_end called",
  src:find("nebula_app_end%(%)") ~= nil)
check("nebula_derive_app called for LoginApp",
  src:find('nebula_derive_app%("LoginApp"%)') ~= nil)
check("nebula_frame_render called",
  src:find("nebula_frame_render%(") ~= nil)

-- ---- 2. Phase 3.9: 组件注册 ----
check("card component registered",
  src:find('nebula_app_register_component%("card"') ~= nil)
check("email_input component registered",
  src:find('nebula_app_register_component%("email_input"') ~= nil)
check("password_input component registered",
  src:find('nebula_app_register_component%("password_input"') ~= nil)
check("login_btn component registered",
  src:find('nebula_app_register_component%("login_btn"') ~= nil)

-- ---- 3. Phase 3.9: 文本一等公民注册 ----
check("email_label text registered",
  src:find('nebula_app_register_text%("email_label"') ~= nil)
check("password_label text registered",
  src:find('nebula_app_register_text%("password_label"') ~= nil)
check("email_label bound to email_input",
  src:find('bound_to%s*=%s*"email_input"') ~= nil)
check("password_label bound to password_input",
  src:find('bound_to%s*=%s*"password_input"') ~= nil)
check("password mask_password = true",
  src:find("mask_password%s*=%s*true") ~= nil)

-- ---- 4. Phase 3.9: 无手动渲染样板 ----
check("no manual wgpuDeviceCreateCommandEncoder",
  src:find("wgpuDeviceCreateCommandEncoder") == nil)
check("no manual wgpuSurfaceGetCurrentTexture",
  src:find("wgpuSurfaceGetCurrentTexture") == nil)
check("no manual process_text_input in main loop",
  src:find("email_input:process_text_input") == nil)
check("no manual draw_buffer in main loop",
  src:find("pipe_email_text:draw_buffer") == nil)
check("no manual TextPipeline declaration",
  src:find("pipe_email_text%s*:%s*TextPipeline") == nil)

-- ---- 5. Phase 3.6+: InputVisual 仍使用 editable 原语 + Gap Buffer ----
check("editable primitive in InputVisual",
  src:find('"editable"') ~= nil)
check("gap_buf field in InputVisual",
  src:find("gap_buf%s*:%s*NebulaBuf") ~= nil)
check("NebulaBuf type injected",
  src:find("nebula_gen_gap_buffer_type") ~= nil)

-- ---- 6. 向后兼容性：焦点管理仍然存在 ----
check("component_id = 1 for email",
  src:find("email_input%.component_id%s*=%s*1") ~= nil)
check("component_id = 2 for password",
  src:find("password_input%.component_id%s*=%s*2") ~= nil)
check("nebula_collect_input still called",
  src:find("nebula_collect_input%(window") ~= nil)
check("nebula_input_install_callbacks called",
  src:find("nebula_input_install_callbacks%(window%)") ~= nil)

-- ---- 7. Enter 键处理（领域逻辑保留在应用层）----
check("Enter key triggers print",
  src:find("NebulaKey%.Enter") ~= nil)
check("printf email on Enter",
  src:find('printf.*email') ~= nil)

-- ---- 汇总 ----
print(string.format("[Phase 3.9 / login_demo] %d passed, %d failed", pass, fail))
assert(fail == 0, "Phase 3.9 login_demo smoke test FAILED")
