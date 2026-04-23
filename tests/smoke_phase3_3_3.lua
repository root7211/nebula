-- =============================================================================
-- tests/smoke_phase3_3_3.lua
-- Nebula GUI Compiler — Phase 3.3.3
--
-- Instanced 着色器组合器冒烟测试
--
-- 验证 shader_compose.lua 中新增的 nebula_compose_instanced_shader：
--   · 函数存在且可调用
--   · 生成的 WGSL 包含正确的 Storage Buffer 绑定声明
--   · 包含 @builtin(instance_index) 使用
--   · 包含 InstanceData struct 定义
--   · 包含 Viewport uniform 绑定
--   · SDF 逻辑按 has_radius 选项正确切换
--   · has_border 选项正确控制边框逻辑
--   · 返回对象包含 instanced=true 标志
--   · 模块版本号已更新至 phase3.3.3
--   · 现有 nebula_compose_shader 和 nebula_compose_text_shader 未被破坏
-- =============================================================================

-- 加载 shader_compose.lua（通过 Nelua 编译期 Lua 环境）
local compose = dofile("src/derive/shader_compose.lua")

local pass = 0
local fail = 0

local function check(name, cond, msg)
  if cond then
    pass = pass + 1
    print(("[PASS] %s"):format(name))
  else
    fail = fail + 1
    print(("[FAIL] %s — %s"):format(name, msg or "assertion failed"))
  end
end

-- ===== 模块版本检查 =====
check("module_version_updated",
  compose == "nebula_shader_compose_v0.5_phase3.5.1",
  "模块版本号未更新至 phase3.3.3，当前: " .. tostring(compose))

-- ===== 函数存在性检查 =====
check("func_nebula_compose_instanced_shader_exists",
  type(nebula_compose_instanced_shader) == "function",
  "nebula_compose_instanced_shader 函数不存在")

check("func_nebula_compose_shader_intact",
  type(nebula_compose_shader) == "function",
  "现有 nebula_compose_shader 函数被破坏")

check("func_nebula_compose_text_shader_intact",
  type(nebula_compose_text_shader) == "function",
  "现有 nebula_compose_text_shader 函数被破坏")

-- ===== 基础调用（无选项）=====
local result_basic = nebula_compose_instanced_shader({})
check("basic_call_returns_table",
  type(result_basic) == "table",
  "nebula_compose_instanced_shader({}) 未返回 table")

check("basic_result_has_source",
  type(result_basic.source) == "string" and #result_basic.source > 0,
  "返回对象缺少 source 字段")

check("basic_result_has_features",
  type(result_basic.features) == "table",
  "返回对象缺少 features 字段")

check("basic_result_instanced_flag",
  result_basic.instanced == true,
  "返回对象缺少 instanced=true 标志")

check("basic_result_required_passes",
  type(result_basic.required_passes) == "table" and result_basic.required_passes[1] == "main",
  "required_passes 应为 {\"main\"}")

-- ===== WGSL 结构断言（基础模式）=====
local src = result_basic.source

check("wgsl_has_instance_data_struct",
  src:find("struct InstanceData") ~= nil,
  "生成的 WGSL 缺少 InstanceData struct 定义")

check("wgsl_has_pos_field",
  src:find("pos:%s*vec2<f32>") ~= nil,
  "InstanceData 缺少 pos 字段")

check("wgsl_has_size_field",
  src:find("size:%s*vec2<f32>") ~= nil,
  "InstanceData 缺少 size 字段")

check("wgsl_has_bg_color_field",
  src:find("bg_color:%s*vec4<f32>") ~= nil,
  "InstanceData 缺少 bg_color 字段")

check("wgsl_has_border_color_field",
  src:find("border_color:%s*vec4<f32>") ~= nil,
  "InstanceData 缺少 border_color 字段")

check("wgsl_has_radius_field",
  src:find("radius:%s*f32") ~= nil,
  "InstanceData 缺少 radius 字段")

check("wgsl_has_viewport_uniform",
  src:find("var<uniform>") ~= nil and src:find("Viewport") ~= nil,
  "生成的 WGSL 缺少 Viewport uniform 绑定")

check("wgsl_has_storage_binding",
  src:find("var<storage, read>") ~= nil,
  "生成的 WGSL 缺少 var<storage, read> 绑定")

check("wgsl_has_instance_array",
  src:find("array<InstanceData>") ~= nil,
  "生成的 WGSL 缺少 array<InstanceData> 声明")

check("wgsl_binding0_is_uniform",
  src:find("@binding%(0%)") ~= nil,
  "生成的 WGSL 缺少 @binding(0)")

check("wgsl_binding1_is_storage",
  src:find("@binding%(1%)") ~= nil,
  "生成的 WGSL 缺少 @binding(1)")

check("wgsl_has_instance_index_builtin",
  src:find("@builtin%(instance_index%)") ~= nil,
  "生成的 WGSL 缺少 @builtin(instance_index)")

check("wgsl_has_vertex_index_builtin",
  src:find("@builtin%(vertex_index%)") ~= nil,
  "生成的 WGSL 缺少 @builtin(vertex_index)")

check("wgsl_has_vs_main",
  src:find("fn vs_main") ~= nil,
  "生成的 WGSL 缺少 vs_main 函数")

check("wgsl_has_fs_main",
  src:find("fn fs_main") ~= nil,
  "生成的 WGSL 缺少 fs_main 函数")

check("wgsl_has_discard",
  src:find("discard;") ~= nil,
  "生成的 WGSL 缺少透明像素 discard 逻辑")

check("wgsl_no_radius_by_default",
  src:find("sdf_rounded_rect") == nil,
  "未启用 has_radius 时不应包含 sdf_rounded_rect")

check("wgsl_uses_sdf_rect_by_default",
  src:find("sdf_rect") ~= nil,
  "默认模式应使用 sdf_rect")

-- ===== has_radius=true 模式 =====
local result_radius = nebula_compose_instanced_shader({ has_radius = true })
local src_r = result_radius.source

check("radius_mode_uses_sdf_rounded_rect",
  src_r:find("sdf_rounded_rect") ~= nil,
  "has_radius=true 时应使用 sdf_rounded_rect")

check("radius_mode_feature_flag",
  (function()
    for _, f in ipairs(result_radius.features) do
      if f == "radius" then return true end
    end
    return false
  end)(),
  "has_radius=true 时 features 应包含 \"radius\"")

-- ===== has_border=true 模式 =====
local result_border = nebula_compose_instanced_shader({ has_border = true })
local src_b = result_border.source

check("border_mode_has_border_alpha",
  src_b:find("border_alpha") ~= nil,
  "has_border=true 时应包含 border_alpha 计算")

check("border_mode_uses_border_color",
  src_b:find("border_color") ~= nil,
  "has_border=true 时应使用 border_color")

check("border_mode_feature_flag",
  (function()
    for _, f in ipairs(result_border.features) do
      if f == "border" then return true end
    end
    return false
  end)(),
  "has_border=true 时 features 应包含 \"border\"")

-- ===== 无边框模式不含 border_alpha =====
check("no_border_mode_no_border_alpha",
  result_basic.source:find("border_alpha") == nil,
  "未启用 has_border 时不应包含 border_alpha")

-- ===== 6 顶点矩形（非全屏三角形）=====
check("wgsl_uses_6_vertices_per_instance",
  src:find("array<vec2<f32>, 6>") ~= nil,
  "实例渲染应使用 6 顶点（两个三角形）覆盖矩形区域")

-- ===== 汇总 =====
print(("\n--- smoke_phase3_3_3 结果: %d 通过, %d 失败 ---"):format(pass, fail))
if fail > 0 then
  os.exit(1)
end
