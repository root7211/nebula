-- =============================================================================
-- smoke_phase5_0.lua
-- Phase 5.0: Slot Layout 自动定位 — 冒烟测试
--
-- 验证 app_factory.lua 对 slot.layout 的代码生成逻辑。
-- 通过静态分析生成的 .c 文件确认：
--   1. layout 定位循环存在
--   2. 常量正确内联（padding, stride, item_size）
--   3. scroll_var 正确引用
--   4. 无 layout 的 slot 不受影响
-- =============================================================================

local pass_count = 0
local fail_count = 0

local function check(name, cond)
  if cond then
    pass_count = pass_count + 1
    -- print(("[PASS] %s"):format(name))
  else
    fail_count = fail_count + 1
    print(("[FAIL] %s"):format(name))
  end
end

-- 读取生成的 C 文件
local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  return content
end

-- ★ Test Group 1: dynamic_list_v2_demo（有 slot layout）
local v2_c = read_file(os.getenv("HOME") .. "/.cache/nelua/dynamic_list_v2_demo.c")
assert(v2_c, "dynamic_list_v2_demo.c not found — build it first: ./build.sh dynamic_list_v2_demo")

-- 1.1 layout 定位循环生成
check("v2_has_layout_loop_var_li",
  v2_c:find("_li") ~= nil)

-- 1.2 padding_x = 20.0 内联
check("v2_padding_x_20",
  v2_c:find("20%.0f") ~= nil)

-- 1.3 stride = 44.0 内联（item_h=40 + gap=4）
check("v2_stride_44",
  v2_c:find("44%.0") ~= nil)

-- 1.4 item_size.w = 760.0 内联
check("v2_item_w_760",
  v2_c:find("760%.0f") ~= nil)

-- 1.5 item_size.h = 40.0 内联
check("v2_item_h_40",
  v2_c:find("%.y = 40%.0f") ~= nil)

-- 1.6 scroll_var 引用（list_scroll_y）
check("v2_scroll_var_ref",
  v2_c:find("list_scroll_y") ~= nil)

-- 1.7 pos 赋值包含 scroll 减法
check("v2_pos_minus_scroll",
  v2_c:find("_li.*44%.0.-list_scroll_y") ~= nil)

-- 1.8 size 赋值正确
check("v2_size_assignment",
  v2_c:find("_slot_data%[_li%]%.size") ~= nil)

-- ★ Test Group 2: dynamic_list_demo（无 slot layout，行为不变）
local v1_c = read_file(os.getenv("HOME") .. "/.cache/nelua/dynamic_list_demo.c")
if v1_c then
  -- 2.1 原版不应有 Phase 5.0 自动定位循环
  -- （_li 变量不存在于 draw 函数中——原版的 _li 不会出现）
  -- 更精确：原版不应有 "_slot_data[_li].pos" 模式
  check("v1_no_auto_layout_pos",
    v1_c:find("_slot_data%[_li%]%.pos") == nil)

  -- 2.2 原版不应有 "_slot_data[_li].size" 模式
  check("v1_no_auto_layout_size",
    v1_c:find("_slot_data%[_li%]%.size") == nil)

  -- 2.3 原版 Producer 仍负责写坐标
  check("v1_producer_writes_pos",
    v1_c:find("slot_data%[count%]") ~= nil or v1_c:find("slot_data%[.*%]%.pos") ~= nil)
else
  print("[SKIP] dynamic_list_demo.c not found — skipping v1 regression checks")
end

-- ★ Test Group 3: app_factory.lua 源码验证
local af = read_file("src/derive/app_factory.lua")
assert(af, "src/derive/app_factory.lua not found")

-- 3.1 register_slot 接受 layout 参数
check("factory_slot_accepts_layout",
  af:find("layout.*=.*opts%.layout") ~= nil)

-- 3.2 gen_app_draw 包含 Phase 5.0 代码生成
check("factory_has_phase5_codegen",
  af:find("Phase 5%.0") ~= nil)

-- 3.3 direction 条件分支存在
check("factory_direction_branch",
  af:find("if dir == \"column\"") ~= nil)

-- 3.4 scroll_var 可配置
check("factory_scroll_var_configurable",
  af:find("scroll_expr") ~= nil and af:find("scroll_var") ~= nil)

-- ★ Test Group 4: wgpu 绑定修复验证
local wgpu = read_file("src/wgpu_bindings.nelua")
assert(wgpu, "src/wgpu_bindings.nelua not found")

-- 4.1 WGPUBindGroupLayoutEntry 有 bindingArraySize
check("wgpu_has_bindingArraySize",
  wgpu:find("bindingArraySize") ~= nil)

-- 4.2 WGPUVertexAttribute 有 nextInChain
check("wgpu_vertex_attr_nextInChain",
  wgpu:find("WGPUVertexAttribute.-nextInChain") ~= nil)

-- 4.3 WGPUVertexBufferLayout 有 nextInChain
check("wgpu_vertex_buf_layout_nextInChain",
  wgpu:find("WGPUVertexBufferLayout.-nextInChain") ~= nil)

-- 4.4 WGPUShaderStage 是 uint64
check("wgpu_shader_stage_uint64",
  wgpu:find("WGPUShaderStage = @uint64") ~= nil)

print(("=== Phase 5.0 smoke: %d passed, %d failed ==="):format(pass_count, fail_count))
if fail_count > 0 then os.exit(1) end
