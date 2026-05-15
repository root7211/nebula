-- =============================================================================
-- tests/smoke_phase4_x_input.lua
-- Nebula GUI Compiler — Phase 4.X 输入系统补全专项测试
--
-- 测试目标：
--   缺口 #5: 剪贴板 API 绑定（glfwGetClipboardString / glfwSetClipboardString）
--   缺口 #6: Unicode char callback 消费者扩展（全 Unicode 范围 + 剪贴板快捷键）
--
-- 验证项：
--   1. glfw_bindings.nelua 包含剪贴板函数绑定
--   2. editable 原语接受完整 Unicode（>= 0x20, != 0x7F）
--   3. editable 原语生成 UTF-8 编码逻辑（多字节序列）
--   4. NebulaKey 枚举包含 Copy/Paste/Cut/SelectAll
--   5. app.nelua key callback 包含 Ctrl+C/V/X/A 映射
--   6. editable 原语 process_input 源码包含剪贴板操作
--   7. Gap Buffer 包含 extract_range 方法
-- =============================================================================

-- =============================================================================
-- 测试工具
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

-- =============================================================================
-- 读取源文件
-- =============================================================================
local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  return content
end

local glfw_src    = read_file("src/glfw_bindings.nelua")
local app_src     = read_file("src/app.nelua")
local core_src    = read_file("src/nebula_types.nelua")
local interact_src = read_file("src/derive/interaction_factory.lua")
local gapbuf_src  = read_file("src/derive/gap_buffer_factory.lua")

assert(glfw_src,     "glfw_bindings.nelua not found")
assert(app_src,      "app.nelua not found")
assert(core_src,     "nebula_types.nelua not found")
assert(interact_src, "interaction_factory.lua not found")
assert(gapbuf_src,   "gap_buffer_factory.lua not found")

print("=== Phase 4.X: 输入系统补全 — 专项测试 ===")
print("")

-- =============================================================================
-- 缺口 #5: 剪贴板 API 绑定
-- =============================================================================
print("--- 缺口 #5: 剪贴板 API ---")

check("§5.1: glfwGetClipboardString 绑定存在",
  glfw_src:find("glfwGetClipboardString") ~= nil)

check("§5.2: glfwSetClipboardString 绑定存在",
  glfw_src:find("glfwSetClipboardString") ~= nil)

check("§5.3: GetClipboardString 返回 cstring",
  glfw_src:find("glfwGetClipboardString%(window: GLFWwindow%): cstring") ~= nil)

check("§5.4: SetClipboardString 接受 cstring 参数",
  glfw_src:find("glfwSetClipboardString%(window: GLFWwindow, str: cstring%)") ~= nil)

check("§5.5: 剪贴板绑定使用 <cimport, nodecl>",
  glfw_src:find("glfwGetClipboardString.-<cimport, nodecl>") ~= nil)

print("")

-- =============================================================================
-- 缺口 #6: Unicode 字符范围扩展
-- =============================================================================
print("--- 缺口 #6: Unicode 字符范围 ---")

check("§6.1: 接受 Unicode 可打印字符 (cp >= 0x20 and cp ~= 0x7F)",
  interact_src:find('cp >= 0x20 and cp ~= 0x7F') ~= nil)

check("§6.2: 不再限制为 ASCII 0x7E",
  interact_src:find('cp <= 0x7E') == nil)

-- UTF-8 编码验证
check("§6.3: UTF-8 单字节路径 (cp <= 0x7F)",
  interact_src:find('cp <= 0x7F') ~= nil)

check("§6.4: UTF-8 双字节路径 (cp <= 0x7FF)",
  interact_src:find('cp <= 0x7FF') ~= nil)

check("§6.5: UTF-8 三字节路径 (cp <= 0xFFFF — BMP, 含 CJK)",
  interact_src:find('cp <= 0xFFFF') ~= nil)

check("§6.6: UTF-8 四字节路径 (cp <= 0x10FFFF — 补充平面)",
  interact_src:find('cp <= 0x10FFFF') ~= nil)

-- UTF-8 编码正确性：验证 lead byte 掩码
check("§6.7: 双字节 lead byte 0xC0 | (cp >> 6)",
  interact_src:find('0xC0 | %(cp >> 6%)') ~= nil)

check("§6.8: 三字节 lead byte 0xE0 | (cp >> 12)",
  interact_src:find('0xE0 | %(cp >> 12%)') ~= nil)

check("§6.9: 四字节 lead byte 0xF0 | (cp >> 18)",
  interact_src:find('0xF0 | %(cp >> 18%)') ~= nil)

check("§6.10: 续字节掩码 0x80 | (cp & 0x3F)",
  interact_src:find('0x80 | %(cp & 0x3F%)') ~= nil)

print("")

-- =============================================================================
-- 剪贴板快捷键集成
-- =============================================================================
print("--- 剪贴板快捷键 ---")

-- NebulaKey 枚举
check("§7.1: NebulaKey 枚举包含 Copy",
  core_src:find("Copy%s*=") ~= nil)

check("§7.2: NebulaKey 枚举包含 Paste",
  core_src:find("Paste%s*=") ~= nil)

check("§7.3: NebulaKey 枚举包含 Cut",
  core_src:find("Cut%s*=") ~= nil)

check("§7.4: NebulaKey 枚举包含 SelectAll",
  core_src:find("SelectAll%s*=") ~= nil)

-- app.nelua key callback: Ctrl 组合键映射
check("§7.5: app.nelua 检测 ctrl_down",
  app_src:find("ctrl_down") ~= nil)

check("§7.6: Ctrl+C 映射到 Copy",
  app_src:find("NebulaKey%.Copy") ~= nil)

check("§7.7: Ctrl+V 映射到 Paste",
  app_src:find("NebulaKey%.Paste") ~= nil)

check("§7.8: Ctrl+X 映射到 Cut",
  app_src:find("NebulaKey%.Cut") ~= nil)

check("§7.9: Ctrl+A 映射到 SelectAll",
  app_src:find("NebulaKey%.SelectAll") ~= nil)

-- editable 原语中的剪贴板操作
check("§7.10: editable 包含 SelectAll 处理",
  interact_src:find('NebulaKey%.SelectAll') ~= nil)

check("§7.11: editable 包含 Copy/Cut 处理",
  interact_src:find('NebulaKey%.Copy or k == NebulaKey%.Cut') ~= nil)

check("§7.12: editable 包含 Paste 处理",
  interact_src:find('NebulaKey%.Paste') ~= nil)

check("§7.13: Copy/Cut 调用 glfwSetClipboardString",
  interact_src:find('glfwSetClipboardString') ~= nil)

check("§7.14: Paste 调用 glfwGetClipboardString",
  interact_src:find('glfwGetClipboardString') ~= nil)

check("§7.15: SelectAll 先 move_cursor_home 再 move_cursor_end",
  interact_src:find('SelectAll.-move_cursor_home.-move_cursor_end') ~= nil)

print("")

-- =============================================================================
-- Gap Buffer extract_range 方法
-- =============================================================================
print("--- Gap Buffer extract_range ---")

check("§8.1: gap_buffer_factory 包含 extract_range 方法定义",
  gapbuf_src:find("extract_range") ~= nil)

check("§8.2: extract_range 接受 (sel_start, sel_end, out, max_out) 参数",
  gapbuf_src:find("extract_range%(sel_start: uint32, sel_end: uint32, out:") ~= nil)

check("§8.3: extract_range 返回 uint32",
  gapbuf_src:find("extract_range.-: uint32") ~= nil)

check("§8.4: extract_range 处理 gap 跳跃 (gap_start/gap_end 映射)",
  gapbuf_src:find("self%.gap_start") ~= nil and gapbuf_src:find("self%.gap_end") ~= nil)

-- 验证通过 nebula_gen_gap_buffer_type 生成
package.path = "src/?.lua;src/derive/?.lua;" .. package.path
local gb_factory = require "derive.gap_buffer_factory"
local _, gb_code = nebula_gen_gap_buffer_type(64)

check("§8.5: 生成代码包含 extract_range 函数",
  gb_code:find("function NebulaBuf64:extract_range") ~= nil)

check("§8.6: 生成代码中 extract_range 映射逻辑索引到物理位置",
  gb_code:find("phys = self%.gap_end") ~= nil)

print("")

-- =============================================================================
-- 汇总
-- =============================================================================
print(("============================================"))
print(("  Results: %d passed, %d failed"):format(pass_count, fail_count))
print(("============================================"))
assert(fail_count == 0, "Phase 4.X input system test FAILED")
print("ALL TESTS PASSED!")
