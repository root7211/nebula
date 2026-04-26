-- derive/axiom_validator.lua
-- Nebula GUI Compiler — Phase 4.0
--
-- 编译期公理校验器（Axiom Validator）
--
-- 将 Nebula 的三大哲学公理与七大不变量从"文档共识"升级为"编译器强制约束"。
-- 本模块采用"只读断言（Read-only Assertions）"设计原则：
--   · 只检查元数据是否合法
--   · 若不合法，抛出带有精确定位信息的编译错误
--   · 绝不修改任何注册表状态（Separation of Concerns）
--
-- ★ 任务 A：生命周期类型白名单（公理 B 约束）
--   防止 L2（帧级）数据泄漏到 L1（持久层 Visual Record）。
--
-- ★ 任务 B：只读管线冲突检测（公理 C 约束，降级版）
--   检测同一 App 内不同 Visual 类型的管线路径是否存在结构性冲突。
--   不自动合并，发现冲突时要求开发者手动修正。
--
-- ★ 任务 C：静态展开验证（不变量 I1 约束）
--   确保所有组件名为合法静态标识符，Slot 的 max_instances 为编译期常量。
--
-- 公开 API：
--   nebula_validate_visual(type_name, reg)        — Visual 级校验（在 nebula_derive 中调用）
--   nebula_validate_app(app_name, reg)             — App 级校验（在 nebula_derive_app 中调用）
--
-- =============================================================================

-- =============================================================================
-- ★ 任务 A：L1 类型白名单
--
-- 公理 B（生命周期三层原则）规定，L1 持久层（Visual Record）只能包含以下基础类型。
-- 任何 L2 帧级类型（如 NebulaTextMesh、GapBuffer、指针）均被禁止出现在 Visual Record 中。
-- =============================================================================

-- L1 持久层允许的字段类型白名单
local L1_TYPE_ALLOWLIST = {
  ["float32"] = true,
  ["Vec2"]    = true,
  ["Vec4"]    = true,
  ["Color"]   = true,
  ["bool"]    = true,
  ["uint8"]   = true,
  ["uint16"]  = true,
  ["uint32"]  = true,
  ["int32"]   = true,
}

-- 明确禁止的 L2 帧级类型（用于生成更友好的错误信息）
local L2_FORBIDDEN_TYPES = {
  ["NebulaTextMesh"]  = "L2 帧级文本网格（应通过 nebula_app_register_text 注册，而非内嵌在 Visual 中）",
  ["GapBuffer"]       = "L2 帧级 Gap Buffer（应通过 editable 原语自动注入，而非内嵌在 Visual 中）",
  ["NebulaArena"]     = "L0 永久层 Arena（不应出现在 L1 Visual Record 中）",
  ["pointer"]         = "裸指针（违反 L1 持久层的值语义要求）",
}

-- 检查类型名是否为指针类型（以 * 开头或包含 pointer）
local function is_pointer_type(type_name)
  if not type_name then return false end
  return type_name:sub(1, 1) == "*" or type_name:find("pointer", 1, true) ~= nil
end

-- ★ 任务 A 核心校验函数
-- 校验单个 Visual 类型的所有字段是否符合 L1 类型白名单
-- 参数：
--   type_name : string  — Visual 类型名（如 "ButtonVisual"）
--   base_fields  : table   — nebula_parse_shape 返回的基础字段列表
--   state_fields : table   — nebula_parse_shape 返回的状态字段映射
function nebula_validate_visual_fields(type_name, base_fields, state_fields)
  -- 收集所有字段（基础字段 + 所有状态字段）
  local all_violations = {}

  -- 检查基础字段
  for _, field in ipairs(base_fields) do
    local ftype = field.type
    if not L1_TYPE_ALLOWLIST[ftype] then
      local reason = L2_FORBIDDEN_TYPES[ftype]
        or (is_pointer_type(ftype) and L2_FORBIDDEN_TYPES["pointer"])
        or ("未知类型 '%s'，不在 L1 持久层白名单中"):format(ftype)
      table.insert(all_violations, {
        field  = field.name,
        ftype  = ftype,
        reason = reason,
        scope  = "base",
      })
    end
  end

  -- 检查各状态字段
  if state_fields then
    for state_name, fields in pairs(state_fields) do
      for prop_name, field_info in pairs(fields) do
        local ftype = field_info.type
        if not L1_TYPE_ALLOWLIST[ftype] then
          local reason = L2_FORBIDDEN_TYPES[ftype]
            or (is_pointer_type(ftype) and L2_FORBIDDEN_TYPES["pointer"])
            or ("未知类型 '%s'，不在 L1 持久层白名单中"):format(ftype)
          table.insert(all_violations, {
            field  = field_info.name,
            ftype  = ftype,
            reason = reason,
            scope  = ("state '%s'"):format(state_name),
          })
        end
      end
    end
  end

  -- 如有违规，生成详细的编译错误
  if #all_violations > 0 then
    local lines = {
      ("[Axiom-B 违规] Visual 类型 '%s' 包含非法的 L2/L0 字段："):format(type_name),
    }
    for _, v in ipairs(all_violations) do
      table.insert(lines, ("  · 字段 '%s' (%s) in %s — %s"):format(
        v.field, v.ftype, v.scope, v.reason))
    end
    table.insert(lines, "")
    table.insert(lines, "修复建议：")
    table.insert(lines, "  · 若需要文本渲染，请使用 nebula_app_register_text 注册独立的 TextContext")
    table.insert(lines, "  · 若需要文本输入，请在 primitives 中声明 'editable' 原语")
    table.insert(lines, "  · Visual Record 只应包含描述外观的纯值类型（float32/Vec2/Vec4/Color/bool）")
    error(table.concat(lines, "\n"), 2)
  end
end

-- =============================================================================
-- ★ 任务 B：只读管线路径冲突检测（降级版，公理 C 约束）
--
-- 公理 C（形即渲染原则）要求每个 Visual 类型确定性地映射到一个管线签名。
-- 本函数检测同一 App 内的管线路径冲突：
--   · 标准实例化路径（standard_instanced）
--   · 文本 SDF 路径（textured_vertex）
--   · 阴影多 Pass 路径（shadow_multipass）
--
-- 冲突定义：同一 pipeline_name 被两个具有不同路径类型的 Visual 类型共享。
-- 发现冲突时报错，要求开发者手动修正，而不是自动合并。
-- =============================================================================

-- 推断管线路径类型（基于 visual_type 名称约定和注册表信息）
-- 返回 "shadow_multipass" | "textured_vertex" | "standard_instanced"
local function infer_pipeline_path(visual_type, app_reg)
  -- 检查是否在 shadows 列表中
  if app_reg and app_reg.shadows then
    for _, shd in ipairs(app_reg.shadows) do
      if shd.visual_type == visual_type then
        return "shadow_multipass"
      end
    end
  end
  -- 检查是否在 texts 列表中
  if app_reg and app_reg.texts then
    for _, txt in ipairs(app_reg.texts) do
      if txt.visual_type == visual_type then
        return "textured_vertex"
      end
    end
  end
  -- 默认为标准实例化路径
  return "standard_instanced"
end

-- ★ 任务 B 核心校验函数
-- 检测 App 内所有 type_groups 的管线路径一致性
function nebula_validate_app_pipelines(app_name, reg)
  if not reg.type_groups then return end

  -- pipeline_name -> { path_type, first_visual_type }
  local pipeline_path_registry = {}
  local violations = {}

  for visual_type, group in pairs(reg.type_groups) do
    local pipeline_name = group.pipeline_name
    local path_type = infer_pipeline_path(visual_type, reg)

    if pipeline_path_registry[pipeline_name] then
      local existing = pipeline_path_registry[pipeline_name]
      -- 同一 pipeline_name 被不同路径类型的 Visual 共享 → 冲突
      if existing.path_type ~= path_type then
        table.insert(violations, {
          pipeline_name    = pipeline_name,
          existing_visual  = existing.visual_type,
          existing_path    = existing.path_type,
          conflict_visual  = visual_type,
          conflict_path    = path_type,
        })
      end
    else
      pipeline_path_registry[pipeline_name] = {
        path_type   = path_type,
        visual_type = visual_type,
      }
    end
  end

  if #violations > 0 then
    local lines = {
      ("[Axiom-C 违规] App '%s' 存在管线路径冲突："):format(app_name),
    }
    for _, v in ipairs(violations) do
      table.insert(lines, ("  · 管线 '%s'："):format(v.pipeline_name))
      table.insert(lines, ("      Visual '%s' → 路径 '%s'"):format(v.existing_visual, v.existing_path))
      table.insert(lines, ("      Visual '%s' → 路径 '%s'（冲突）"):format(v.conflict_visual, v.conflict_path))
    end
    table.insert(lines, "")
    table.insert(lines, "修复建议：")
    table.insert(lines, "  · 不同渲染路径的 Visual 类型不能共享同一管线名称")
    table.insert(lines, "  · 请检查 Visual 类型的命名或注册方式，确保管线路径一致")
    error(table.concat(lines, "\n"), 2)
  end
end

-- =============================================================================
-- ★ 任务 C：静态展开验证（不变量 I1 约束）
--
-- 不变量 I1（零运行时分发）规定：
--   · 所有组件名必须为合法的静态 Nelua 标识符（字母/数字/下划线，不以数字开头）
--   · Slot 的 max_instances 必须为编译期正整数常量（> 0）
--   · 不允许动态注册（组件名不能包含运行时变量引用）
-- =============================================================================

-- 检查标识符是否合法（Nelua/Lua 标识符规则）
local function is_valid_identifier(name)
  if type(name) ~= "string" or #name == 0 then return false end
  -- 必须以字母或下划线开头，后续只含字母、数字、下划线
  return name:match("^[%a_][%a%d_]*$") ~= nil
end

-- ★ 任务 C 核心校验函数
function nebula_validate_app_static_expansion(app_name, reg)
  local violations = {}

  -- 检查静态组件名
  for _, comp in ipairs(reg.components or {}) do
    if not is_valid_identifier(comp.name) then
      table.insert(violations, {
        kind   = "invalid_component_name",
        name   = comp.name,
        reason = ("组件名 '%s' 不是合法的静态标识符"):format(tostring(comp.name)),
      })
    end
  end

  -- 检查 Slot 名称和 max_instances
  for _, slot in ipairs(reg.slots or {}) do
    if not is_valid_identifier(slot.name) then
      table.insert(violations, {
        kind   = "invalid_slot_name",
        name   = slot.name,
        reason = ("Slot 名 '%s' 不是合法的静态标识符"):format(tostring(slot.name)),
      })
    end
    -- max_instances 必须为正整数
    local mi = slot.max_instances
    if type(mi) ~= "number" or mi ~= math.floor(mi) or mi <= 0 then
      table.insert(violations, {
        kind   = "invalid_max_instances",
        name   = slot.name,
        reason = ("Slot '%s' 的 max_instances=%s 不是正整数编译期常量"):format(
          tostring(slot.name), tostring(mi)),
      })
    end
  end

  -- 检查文本组件名
  for _, txt in ipairs(reg.texts or {}) do
    if not is_valid_identifier(txt.name) then
      table.insert(violations, {
        kind   = "invalid_text_name",
        name   = txt.name,
        reason = ("文本组件名 '%s' 不是合法的静态标识符"):format(tostring(txt.name)),
      })
    end
  end

  -- 检查阴影组件名
  for _, shd in ipairs(reg.shadows or {}) do
    if not is_valid_identifier(shd.name) then
      table.insert(violations, {
        kind   = "invalid_shadow_name",
        name   = shd.name,
        reason = ("阴影组件名 '%s' 不是合法的静态标识符"):format(tostring(shd.name)),
      })
    end
  end

  if #violations > 0 then
    local lines = {
      ("[Invariant-I1 违规] App '%s' 违反静态展开约束："):format(app_name),
    }
    for _, v in ipairs(violations) do
      table.insert(lines, ("  · [%s] %s"):format(v.kind, v.reason))
    end
    table.insert(lines, "")
    table.insert(lines, "修复建议：")
    table.insert(lines, "  · 组件名必须是合法的 Nelua 标识符（字母/下划线开头，只含字母/数字/下划线）")
    table.insert(lines, "  · Slot 的 max_instances 必须是大于 0 的整数字面量")
    error(table.concat(lines, "\n"), 2)
  end
end

-- =============================================================================
-- 公开 API：顶层校验入口
-- =============================================================================

-- Visual 级校验（在 nebula_derive 入口调用）
-- 参数：
--   type_name    : string  — Visual 类型名
--   base_fields  : table   — nebula_parse_shape 返回的基础字段列表
--   state_fields : table   — nebula_parse_shape 返回的状态字段映射
function nebula_validate_visual(type_name, base_fields, state_fields)
  -- 任务 A：生命周期类型白名单
  nebula_validate_visual_fields(type_name, base_fields, state_fields)
  -- Visual 级别暂无其他校验（任务 B/C 均为 App 级）
end

-- App 级校验（在 nebula_derive_app / nebula_app_end 调用）
-- 参数：
--   app_name : string  — App 名称
--   reg      : table   — nebula_app_registry[app_name]
function nebula_validate_app(app_name, reg)
  -- 任务 C：静态展开验证（先于任务 B，因为名称合法性是管线检测的前提）
  nebula_validate_app_static_expansion(app_name, reg)
  -- 任务 B：只读管线路径冲突检测
  nebula_validate_app_pipelines(app_name, reg)
end

-- =============================================================================
-- 模块版本标识（供 nebula_core.nelua 的 require + assert 校验）
-- =============================================================================
return "nebula_axiom_validator_v1.0_phase4.0"
