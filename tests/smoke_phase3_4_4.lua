-- =============================================================================
-- smoke_phase3_4_4.lua
-- Phase 3.4.4 冒烟测试：login_demo 升级验证
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

-- ---- 1. Phase 3.4.1 接入 ----
check("nebula_input_install_callbacks called",
  src:find("nebula_input_install_callbacks%(window%)") ~= nil)
check("require app present",
  src:find('require "app"') ~= nil)
check("require nebula_cursor present",
  src:find('require "nebula_cursor"') ~= nil)

-- ---- 2. InputVisual 新增文本缓冲区字段 ----
check("text_buf field in InputVisual",
  src:find("text_buf%s*:%s*%[256%]uint8") ~= nil)
check("text_len field in InputVisual",
  src:find("text_len%s*:%s*uint32") ~= nil)
check("cursor_pos field in InputVisual",
  src:find("cursor_pos%s*:%s*uint32") ~= nil)

-- ---- 3. nebula_gen_text_buffer 调用 ----
check("nebula_gen_text_buffer called for Input",
  src:find('nebula_gen_text_buffer.*base.*=.*"Input"') ~= nil)

-- ---- 4. 主循环中的文本处理 ----
check("process_text_input called for email",
  src:find("email_input:process_text_input") ~= nil)
check("process_text_input called for password",
  src:find("password_input:process_text_input") ~= nil)
check("email text rebuild on change",
  src:find("email_text:set_text") ~= nil)
check("password mask rendering (* chars)",
  src:find("0x2A") ~= nil)
check("get_text called",
  src:find(":get_text%(%)") ~= nil)

-- ---- 5. Enter 键处理 ----
check("Enter key triggers print",
  src:find("NebulaKey%.Enter") ~= nil)
check("printf email on Enter",
  src:find('printf.*email') ~= nil)

-- ---- 6. 文本管线集成 ----
check("TextPipeline for email declared",
  src:find("pipe_email_text%s*:%s*TextPipeline") ~= nil)
check("TextPipeline for password declared",
  src:find("pipe_password_text%s*:%s*TextPipeline") ~= nil)
check("draw_buffer called for email text",
  src:find("pipe_email_text:draw_buffer") ~= nil)
check("draw_buffer called for password text",
  src:find("pipe_password_text:draw_buffer") ~= nil)

-- ---- 7. 向后兼容性：Phase 2.4 焦点管理仍然存在 ----
check("component_id = 1 for email",
  src:find("email_input%.component_id%s*=%s*1") ~= nil)
check("component_id = 2 for password",
  src:find("password_input%.component_id%s*=%s*2") ~= nil)
check("nebula_collect_input still called",
  src:find("nebula_collect_input%(window") ~= nil)

-- ---- 汇总 ----
print(string.format("[Phase 3.4.4] %d passed, %d failed", pass, fail))
assert(fail == 0, "Phase 3.4.4 smoke test FAILED")
