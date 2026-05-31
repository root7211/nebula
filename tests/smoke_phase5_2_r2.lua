-- =============================================================================
-- smoke_phase5_2_r2.lua
-- Phase 5.2 R2: 全局状态消除 — 冒烟测试
--
-- 验证 nebula_sugar.nelua 中三处全局状态已迁移至 per-visual / per-app registry：
--   2.1  _NEBULA_AUTO_DENSE    → nebula_registry[type]._auto_dense
--   2.2  _nebula_last_app_spec → nebula_app_registry[app]._spec
--   2.3  _NEBULA_AUTO_DENSE_PRODUCERS → nebula_app_registry[app]._auto_dense_producers
--
-- 方法：静态分析 nebula_sugar.nelua 和 nebula_apps.nelua 的源码文本，
-- 确认 per-registry 写入和读取代码存在，且向后兼容路径保留。
-- =============================================================================

local pass_count = 0
local fail_count = 0

local function check(name, cond)
  if cond then
    pass_count = pass_count + 1
  else
    fail_count = fail_count + 1
    print(("[FAIL] %s"):format(name))
  end
end

local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  return content
end

-- 定位 src 目录
local script_dir = debug.getinfo(1, "S").source:match("@(.*/)")
local src_dir = script_dir and (script_dir .. "../src/") or "src/"

local sugar_src = read_file(src_dir .. "nebula_sugar.nelua")
assert(sugar_src, "nebula_sugar.nelua not found at: " .. src_dir)
local apps_src = read_file(src_dir .. "nebula_apps.nelua")
assert(apps_src, "nebula_apps.nelua not found at: " .. src_dir)

-- =============================================================================
-- ★ Test Group 1: Step 2.1 — _NEBULA_AUTO_DENSE per-visual registry
-- =============================================================================

-- 1.1 写入端：vis_reg._auto_dense 存储
check("2.1_write_per_visual_registry",
  sugar_src:find("vis_reg%._auto_dense") ~= nil)

-- 1.2 写入端：全局写入已消除（R2 finalized — 不再双写）
check("2.1_no_global_write",
  sugar_src:find("_NEBULA_AUTO_DENSE%[type_name%]") == nil)

-- 1.3 读取端：per-visual registry 优先读取
check("2.1_read_per_visual_registry",
  sugar_src:find("c_reg and c_reg%._auto_dense") ~= nil
  or sugar_src:find("c_reg%._auto_dense") ~= nil)

-- 1.4 读取端：全局 fallback 已消除
check("2.1_no_read_global_fallback",
  sugar_src:find("_NEBULA_AUTO_DENSE and _NEBULA_AUTO_DENSE%[c%.type%]") == nil)

-- =============================================================================
-- ★ Test Group 2: Step 2.2 — _nebula_last_app_spec per-app registry
-- =============================================================================

-- 2.1 写入端：nebula_app_registry[app_name]._spec 存储
check("2.2_write_per_app_spec",
  sugar_src:find("nebula_app_registry%[app_name%]%._spec = spec") ~= nil)

-- 2.2 写入端：全局写入已消除（R2 finalized）
check("2.2_no_global_write",
  sugar_src:find("_nebula_last_app_spec = spec") == nil)

-- 2.3 读取端（nebula_apps.nelua）：per-app registry 优先读取
check("2.2_read_per_app_registry",
  apps_src:find("nebula_app_registry%[_r2_app_name%]") ~= nil)

-- 2.4 读取端（nebula_apps.nelua）：全局 fallback 已消除
check("2.2_no_read_global_fallback",
  apps_src:find("_nebula_last_app_spec") == nil)

-- 2.5 读取端（nebula_apps.nelua）：app_type 作为注册键
check("2.2_app_type_as_key",
  apps_src:find("opts%.app_name or app_type") ~= nil)

-- =============================================================================
-- ★ Test Group 3: Step 2.3 — _NEBULA_AUTO_DENSE_PRODUCERS per-app registry
-- =============================================================================

-- 3.1 写入端：app_reg._auto_dense_producers 存储
check("2.3_write_per_app_producers",
  sugar_src:find("app_reg%._auto_dense_producers") ~= nil)

-- 3.2 写入端：全局写入已消除（R2 finalized）
check("2.3_no_global_write",
  sugar_src:find("_NEBULA_AUTO_DENSE_PRODUCERS%[c%.name%]") == nil)

-- 3.3 读取端：per-app registry 优先读取
check("2.3_read_per_app_producers",
  sugar_src:find("nebula_app_registry%[app_name%].*_auto_dense_producers") ~= nil)

-- 3.4 读取端：全局 fallback 已消除
check("2.3_no_read_global_fallback",
  sugar_src:find("_NEBULA_AUTO_DENSE_PRODUCERS") == nil)

-- =============================================================================
-- ★ Test Group 4: 结构完整性（无误删关键函数）
-- =============================================================================

-- 4.1 nebula_visual 函数仍存在
check("4.1_nebula_visual_exists",
  sugar_src:find("function nebula_visual%(type_name") ~= nil)

-- 4.2 nebula_app 函数仍存在
check("4.2_nebula_app_exists",
  sugar_src:find("function nebula_app%(app_name") ~= nil)

-- 4.3 nebula_terminal_main 函数仍存在
check("4.3_nebula_terminal_main_exists",
  apps_src:find("function nebula_terminal_main%(app_type") ~= nil)

-- 4.4 nebula_main 函数仍存在
check("4.4_nebula_main_exists",
  apps_src:find("function nebula_main%(app_type") ~= nil)

-- 4.5 nebula_editor_main 函数仍存在
check("4.5_nebula_editor_main_exists",
  apps_src:find("function nebula_editor_main%(app_type") ~= nil)

-- =============================================================================
-- ★ Result
-- =============================================================================
print(("Phase 5.2 R2 smoke test: %d/%d passed"):format(pass_count, pass_count + fail_count))
if fail_count > 0 then
  print(("  !! %d FAILED !!"):format(fail_count))
  os.exit(1)
else
  print("  ALL PASSED")
end
