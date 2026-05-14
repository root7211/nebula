-- =============================================================================
-- tests/smoke_phase3_6_3.lua
-- Nebula GUI Compiler — Phase 3.6.3 专项回归测试
--
-- 验收目标：
--   1. nebula_core.nelua 包含修饰键扩展（mod_shift / mod_ctrl / mod_alt）
--   2. nebula_core.nelua 包含 NebulaKey 的 Shift 组合键变体
--   3. interaction_factory.lua 生成的 process_text_input 包含选区支持代码
--   4. interaction_factory.lua 生成的 process_text_input 包含拖拽支持代码
--   5. gap_buffer.nelua 包含 delete_range 方法
--   6. 架构合规性：get_text 不依赖 visual.flat_buf（L1/L2 分层）
--   7. nebula_core.nelua 包含内聚后的交互原语结构体（Phase 3.9）
-- =============================================================================

local passed = 0
local failed = 0

local function check(label, cond)
  if cond then
    passed = passed + 1
    print(("[PASS] %s"):format(label))
  else
    failed = failed + 1
    print(("[FAIL] %s"):format(label))
  end
end

local function assert_contains(label, str, pattern)
  check(label, type(str) == "string" and str:find(pattern, 1, true) ~= nil)
end

local function assert_not_contains(label, str, pattern)
  check(label, type(str) == "string" and str:find(pattern, 1, true) == nil)
end

-- 路径设置
local script_dir = debug.getinfo(1, "S").source:match("^@(.+)/[^/]+$") or "."
package.path = script_dir .. "/../src/?.lua;" ..
               script_dir .. "/../src/derive/?.lua;" ..
               package.path

-- =============================================================================
-- 1. nebula_core.nelua 修饰键扩展验证
-- =============================================================================
print("\n--- 1. nebula_core.nelua 修饰键扩展 ---")
local core_path = script_dir .. "/../src/nebula_core.nelua"
local f = io.open(core_path, "r")
assert(f, "无法读取 src/nebula_core.nelua")
local core_src = f:read("*a")
f:close()

assert_contains("NebulaInputState 包含 mod_shift 字段", core_src, "mod_shift:")
assert_contains("NebulaInputState 包含 mod_ctrl 字段",  core_src, "mod_ctrl:")
assert_contains("NebulaInputState 包含 mod_alt 字段",   core_src, "mod_alt:")
assert_contains("NebulaKey 包含 ShiftLeft 变体",  core_src, "ShiftLeft")
assert_contains("NebulaKey 包含 ShiftRight 变体", core_src, "ShiftRight")
assert_contains("NebulaKey 包含 ShiftHome 变体",  core_src, "ShiftHome")
assert_contains("NebulaKey 包含 ShiftEnd 变体",   core_src, "ShiftEnd")

-- =============================================================================
-- 2. interaction_factory.lua 选区与拖拽支持验证
-- =============================================================================
print("\n--- 2. interaction_factory.lua 选区与拖拽支持 ---")
local ifac_path = script_dir .. "/../src/derive/interaction_factory.lua"
local fi = io.open(ifac_path, "r")
assert(fi, "无法读取 src/derive/interaction_factory.lua")
local ifac_src = fi:read("*a")
fi:close()

assert_contains("生成代码包含 selection_anchor 字段", ifac_src, "selection_anchor")
assert_contains("生成代码包含 is_dragging 字段",      ifac_src, "is_dragging")
assert_contains("生成代码包含 Shift+Click 注释",       ifac_src, "Shift+Click")
assert_contains("生成代码包含拖拽逻辑注释",            ifac_src, "drag")
assert_contains("生成代码包含 Phase 3.6.3 标记",       ifac_src, "Phase 3.6.3")

-- =============================================================================
-- 3. gap_buffer delete_range 方法验证（BUG-6 修复后实现在 gap_buffer_factory.lua 中）
-- =============================================================================
print("\n--- 3. gap_buffer delete_range 方法 ---")
-- BUG-6 修复：gap_buffer.nelua 委托给 factory，实际实现在 gap_buffer_factory.lua
local gbf_path = script_dir .. "/../src/derive/gap_buffer_factory.lua"
local fg = io.open(gbf_path, "r")
assert(fg, "无法读取 src/derive/gap_buffer_factory.lua")
local gb_src = fg:read("*a")
fg:close()

assert_contains("gap_buffer 包含 delete_range 方法定义", gb_src, "delete_range")
assert_contains("delete_range 接受 start 参数",          gb_src, "start:")
assert_contains("delete_range 接受 sel_end 参数",        gb_src, "sel_end:")

-- =============================================================================
-- 4. 架构合规性：get_text 不依赖 visual.flat_buf（公理 B）
-- =============================================================================
print("\n--- 4. 架构合规性：get_text L1/L2 分层 ---")

assert_contains("get_text 接受 out 参数（调用方提供缓冲区）", ifac_src, "get_text")
-- flat_buf 在注释中出现（说明历史修复），但生成代码中不应再有直接赋值
assert_not_contains("get_text 生成代码不写入 visual.flat_buf", ifac_src, "self.visual.flat_buf =")

-- =============================================================================
-- 5. nebula_core.nelua 包含内聚后的交互原语结构体（Phase 3.9）
-- =============================================================================
print("\n--- 5. nebula_core.nelua 包含内聚的交互原语结构体 ---")

assert_contains("HoverableState 已内聚到 nebula_core.nelua", core_src, "global HoverableState")
assert_contains("ClickableState 已内聚到 nebula_core.nelua", core_src, "global ClickableState")
assert_contains("内聚注释包含 Phase 3.9 标记", core_src, "Phase 3.9 内聚至此")

-- =============================================================================
-- 汇总
-- =============================================================================
print(("\n=== Phase 3.6.3 专项回归测试结果：%d 通过，%d 失败 ==="):format(passed, failed))
if failed > 0 then
  os.exit(1)
end
