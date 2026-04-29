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
-- ★ BUG-2 修复：动态判断 NebulaBuf{N} 类型是否合法（由 editable 原语的 gap_buffer_factory 生成）
-- ★ Phase 4.4 S3 扩展：同时匹配 NebulaMultiBuf{N}_{L} 多行 buffer 类型
local function is_nebula_buf_type(type_name)
  if not type_name then return false end
  return type_name:match("^NebulaBuf%d+$") ~= nil
      or type_name:match("^NebulaMultiBuf%d+_%d+$") ~= nil
end

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
    if not L1_TYPE_ALLOWLIST[ftype] and not is_nebula_buf_type(ftype) then
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
        if not L1_TYPE_ALLOWLIST[ftype] and not is_nebula_buf_type(ftype) then
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
-- ★ 任务 D：process_body 引用域校验（公理 A + B 推导，v3 — 分支覆盖增强）
--
-- Nebula 的 process_body 安全校验问题与 eBPF verifier 面对的是同构问题：
-- 如何允许用户态代码在特权环境中安全执行？
--
-- eBPF 用符号执行（寄存器抽象域 + 路径合并），复杂度 O(指令数 × 分支数)。
-- Nebula 用类型感知 proxy 具体执行 + boolean 笛卡尔展开，复杂度 O(2^n)。
-- 因为 boolean 值域 = {true, false}，2^n 对于 n ≤ 12 完全可行（微秒级）。
--
-- 三层防御架构：
--   Layer 0 — Proxy 验证 + 分支覆盖增强（新约定 process_body(self, input, hovered)）
--   Layer 1 — Token 扫描兜底（旧约定 process_body(spec, lines)）
--   Layer 2 — Trace 报错（公理推导路径，所有层共用）
-- =============================================================================

-- ★ Layer 0 辅助：NebulaInputState boolean 字段表
local INPUT_BOOLEAN_FIELDS = {
  ["mouse_left_down"]    = true,
  ["mouse_left_pressed"] = true,
  ["viewport_resized"]   = true,
}

-- ★ Layer 0 辅助：收集所有 boolean 类型的字段
-- 来源：context_fields（self域）+ input 域 + 函数参数（hovered）
local function collect_boolean_fields(prim_meta, resolved_deps)
  local booleans = {}

  -- 1. context_fields 中的 boolean（self 域）
  for _, dep_name in ipairs(resolved_deps) do
    local meta = NEBULA_PRIMITIVES[dep_name]
    if meta and meta.context_fields then
      for _, field in ipairs(meta.context_fields) do
        if field.type == "boolean" then
          table.insert(booleans, {
            path  = "self." .. field.name,
            name  = field.name,
            scope = "self",
          })
        end
      end
    end
  end

  -- 2. input 字段中的 boolean
  for field_name, _ in pairs(INPUT_BOOLEAN_FIELDS) do
    table.insert(booleans, {
      path  = "input." .. field_name,
      name  = field_name,
      scope = "input",
    })
  end

  -- 3. 函数参数中的 boolean（总是 hovered）
  table.insert(booleans, {
    path  = "hovered",
    name  = "hovered",
    scope = "param",
  })

  return booleans
end

-- ★ Layer 0 辅助：笛卡尔展开 — 生成 2^n 个 boolean 组合
local function cartesian_booleans(booleans)
  local combos = { {} }  -- 初始：一个空组合

  for _, bool_field in ipairs(booleans) do
    local new_combos = {}
    for _, combo in ipairs(combos) do
      local combo_true = {}
      for k, v in pairs(combo) do combo_true[k] = v end
      combo_true[bool_field.path] = true

      local combo_false = {}
      for k, v in pairs(combo) do combo_false[k] = v end
      combo_false[bool_field.path] = false

      table.insert(new_combos, combo_true)
      table.insert(new_combos, combo_false)
    end
    combos = new_combos
  end

  return combos
end

-- ★ Layer 0 核心：类型感知 proxy 构造
-- 对 boolean 路径返回 combo 中的实际值（true/false），
-- 对非 boolean 路径返回嵌套 proxy（truthy table）。
local function make_typed_proxy(path, records, boolean_combo)
  return setmetatable({}, {
    __index = function(_, key)
      local full = path .. "." .. key
      table.insert(records, { kind = "read", path = full })
      -- boolean 覆盖：返回实际 boolean 值
      if boolean_combo[full] ~= nil then
        return boolean_combo[full]
      end
      -- 非 boolean：返回嵌套 proxy
      return make_typed_proxy(full, records, boolean_combo)
    end,
    __newindex = function(_, key, _)
      local full = path .. "." .. key
      table.insert(records, { kind = "write", path = full })
    end,
  })
end

-- ★ Layer 0 核心：分支覆盖增强
-- 对所有 boolean 输入做 2^n 笛卡尔展开，执行所有组合，
-- 合并所有路径的字段访问记录并集（去重）。
local function branch_expand(prim_meta, prim_name, resolved_deps)
  local booleans = collect_boolean_fields(prim_meta, resolved_deps)
  local combos = cartesian_booleans(booleans)

  local merged_records = {}  -- key = "kind:path" → record

  for _, combo in ipairs(combos) do
    local records = {}
    local self_proxy  = make_typed_proxy("self", records, combo)
    local input_proxy = make_typed_proxy("input", records, combo)
    local hovered = combo["hovered"]

    local ok, err = pcall(prim_meta.process_body, self_proxy, input_proxy, hovered)
    if not ok then
      error(("[Axiom-D] 原语 '%s' 的 process_body proxy 执行失败: %s"):format(
        prim_name, tostring(err)))
    end

    -- 合并到全局记录集（去重）
    for _, rec in ipairs(records) do
      local key = rec.kind .. ":" .. rec.path
      if not merged_records[key] then
        merged_records[key] = rec
      end
    end
  end

  -- 转换为数组
  local result = {}
  for _, rec in pairs(merged_records) do
    table.insert(result, rec)
  end
  return result, #combos
end

-- ★ Layer 2：NEBULA_INTRINSICS 辅助函数网关
-- 效仿 eBPF 的 bpf_helper_defs.h，定义 S2 阶段允许调用的函数白名单。
-- 所有不在白名单中的函数调用视为"非法外溢"。
local NEBULA_INTRINSICS = {
  -- 框架数学工具
  ["nebula_clamp"]  = true,
  ["nebula_lerp"]   = true,
  ["nebula_rgba"]   = true,
  -- Nelua 数学内置（S2 阶段合法子集）
  ["math.abs"]   = true,
  ["math.min"]   = true,
  ["math.max"]   = true,
  ["math.floor"] = true,
  ["math.ceil"]  = true,
  ["math.sqrt"]  = true,
  ["math.clamp"] = true,  -- Nelua 内置
  -- 注意：math.random/os.time/io.* 不在白名单中（违反确定性约束）
}

-- ★ D-3 确定性违反标识符表
local DETERMINISM_VIOLATORS = {
  -- ★ 确定性违反：math 库
  ["math.random"]     = true,
  ["math.randomseed"] = true,
  -- ★ 确定性违反：os 库
  ["os.time"]         = true,
  ["os.clock"]        = true,
  ["os.getenv"]       = true,
  ["os.execute"]      = true,
  ["os.remove"]       = true,
  ["os.rename"]       = true,
  -- ★ 确定性违反：io 库
  ["io.open"]         = true,
  ["io.read"]         = true,
  ["io.write"]        = true,
  ["io.popen"]        = true,
  ["io.lines"]        = true,
  -- ★ 确定性违反：debug 库
  ["debug.getinfo"]   = true,
  ["debug.getlocal"]  = true,
  ["debug.setlocal"]  = true,
  ["debug.getupvalue"] = true,
  ["debug.setupvalue"] = true,
  -- ★ 阶段封闭性违反：S0/S1 元编程操作
  ["require"]         = true,
  ["dofile"]          = true,
  ["loadfile"]        = true,
  ["load"]            = true,
  ["pcall"]           = true,
  ["xpcall"]          = true,
}

-- ★ D-1 + D-2：引用域闭合检查（Proxy 记录校验）
local function check_records(records, self_domain, input_domain, prim_name)
  local violations = {}

  for _, rec in ipairs(records) do
    local path = rec.path
    local parts = {}
    for part in path:gmatch("[^%.]+") do
      table.insert(parts, part)
    end

    local root = parts[1]

    if root == "self" then
      -- D-2：检查 self.xxx 在 self_domain 中
      local field = parts[2]
      if field and not self_domain[field] then
        table.insert(violations, {
          path   = path,
          kind   = rec.kind,
          axiom  = "B",
          reason = ("'%s' 未在原语 '%s' 的 context_fields 中声明"):format(field, prim_name),
          trace  = ("self.%s ∉ SELF_DOMAIN (L1 未声明的字段)"):format(field),
        })
      end
    elseif root == "input" then
      -- D-1：检查 input.xxx 在 input_domain 中
      local field = parts[2]
      if field and not input_domain[field] then
        table.insert(violations, {
          path   = path,
          kind   = rec.kind,
          axiom  = "A",
          reason = ("'%s' 不是 NebulaInputState 的已知字段"):format(field),
          trace  = ("input.%s ∉ INPUT_DOMAIN"):format(field),
        })
      end
    elseif root ~= "hovered" then
      -- 未知根标识符 → 违反公理 A
      table.insert(violations, {
        path   = path,
        kind   = rec.kind,
        axiom  = "A",
        reason = ("'%s' 不在 S2 许可域中"):format(root),
        trace  = ("%s ∉ SELF_DOMAIN ∪ INPUT_DOMAIN ∪ PARAMS"):format(root),
      })
    end
  end

  return violations
end

-- ★ D-3 确定性约束检查（Proxy 记录）
local function check_determinism(records, prim_name)
  local violations = {}
  for _, rec in ipairs(records) do
    local path = rec.path
    if DETERMINISM_VIOLATORS[path] then
      table.insert(violations, {
        path   = path,
        kind   = rec.kind,
        axiom  = "A",
        reason = "S2 阶段不得引入非确定性或外部状态访问",
        trace  = ("%s 违反阶段封闭性 — 相同输入应产生相同行为"):format(path),
      })
    end
  end
  return violations
end

-- ★ Layer 1：Token 扫描兜底（旧调用约定兼容）
-- 对 process_body(spec, lines) 注入的代码字符串做模式匹配，
-- 捕获 require/os/io/math.random 等已知危险操作。
local function scan_lines_for_violations(lines, prim_name)
  local violations = {}

  for i, line in ipairs(lines) do
    -- 提取 module.fname( 形式的函数调用
    for call in line:gmatch("([%a_][%a%d_]*%.[%a_][%a%d_]*)%s*%(") do
      if DETERMINISM_VIOLATORS[call] then
        table.insert(violations, {
          path   = call,
          kind   = "function_call",
          axiom  = "A",
          reason = "S0/S1 阶段操作在 S2 阶段不可调用",
          trace  = ("%s 是 S0/S1 阶段操作，在 process_body (S2) 中不可调用"):format(call),
          line   = i,
        })
      end
    end

    -- 提取裸函数调用：require(, dofile(, loadfile(, load(, pcall(, xpcall(
    for fn in line:gmatch("([%a_][%a%d_]*)%s*%(") do
      if DETERMINISM_VIOLATORS[fn] then
        table.insert(violations, {
          path   = fn,
          kind   = "s0_operation",
          axiom  = "A",
          reason = "S0/S1 阶段操作在 S2 阶段不可调用",
          trace  = ("%s 是 S0/S1 阶段操作，在 process_body (S2) 中不可调用"):format(fn),
          line   = i,
        })
      end
    end
  end

  return violations
end

-- ★ Layer 3：Trace 报错格式化
local function format_trace(violation, prim_name)
  local lines = {}
  table.insert(lines, ("[Axiom-%s Violation] 原语 '%s' 的 process_body 引用了非法标识符"):format(
    violation.axiom, prim_name))
  table.insert(lines, "")
  table.insert(lines, ("  访问记录: %s (%s)"):format(violation.path, violation.kind))
  table.insert(lines, "")
  table.insert(lines, "  Trace:")
  if violation.trace then
    table.insert(lines, ("    %s"):format(violation.trace))
  end
  table.insert(lines, "")
  table.insert(lines, ("  公理路径: Axiom-%s"):format(violation.axiom))
  if violation.axiom == "A" then
    table.insert(lines, "    → S2 阶段的合法输入来源 = {self, input, hovered}")
    table.insert(lines, ("    → %s 不在此许可域中"):format(violation.path))
    table.insert(lines, "    → 违反阶段封闭性")
  elseif violation.axiom == "B" then
    table.insert(lines, "    → L1 字段必须在 context_fields 中显式声明")
    table.insert(lines, ("    → %s 未声明"):format(violation.path))
    table.insert(lines, "    → 违反生命周期三层原则")
  end
  table.insert(lines, "")
  if violation.reason then
    table.insert(lines, ("  修复建议: %s"):format(violation.reason))
  end
  return table.concat(lines, "\n")
end

-- ★ 任务 D 主入口：nebula_validate_process_body(app_name, prims)
--
-- 对 App 中所有已注册原语的 process_body 进行引用域校验。
-- 自动检测调用约定（nparams >= 3 → Layer 0, nparams == 2 → Layer 1）。
function nebula_validate_process_body(app_name, prims)
  local resolved = nebula_resolve_primitives(prims)
  local all_violations = {}

  -- 许可域构建
  local self_domain = {}
  for _, dep_name in ipairs(resolved) do
    local meta = NEBULA_PRIMITIVES[dep_name]
    if meta and meta.context_fields then
      for _, field in ipairs(meta.context_fields) do
        self_domain[field.name] = true
      end
    end
  end
  self_domain["visual"] = true  -- Visual 字段（通用前缀，Nelua 类型系统兜底）

  local input_domain = {
    ["mouse_x"] = true, ["mouse_y"] = true,
    ["mouse_left_down"] = true, ["mouse_left_pressed"] = true,
    ["scroll_dy"] = true, ["key_pressed"] = true,
    ["char_input"] = true, ["focused_id"] = true,
    ["mod_shift"] = true, ["mod_ctrl"] = true,
    ["viewport_w"] = true, ["viewport_h"] = true,
    ["viewport_resized"] = true, ["dt"] = true,
  }

  for _, prim_name in ipairs(resolved) do
    local meta = NEBULA_PRIMITIVES[prim_name]
    if not meta or not meta.process_body then goto continue end

    -- 检测调用约定
    local info = debug.getinfo(meta.process_body, "u")
    local nparams = info.nparams

    if nparams >= 3 then
      -- ── Layer 0：分支覆盖增强的 Proxy 验证 ──
      local records, ncombos = branch_expand(meta, prim_name, resolved)

      -- D-1 + D-2：引用域闭合（所有路径的并集）
      local domain_violations = check_records(records, self_domain, input_domain, prim_name)
      for _, v in ipairs(domain_violations) do
        table.insert(all_violations, { prim = prim_name, violation = v })
      end

      -- D-3：确定性约束
      local det_violations = check_determinism(records, prim_name)
      for _, v in ipairs(det_violations) do
        table.insert(all_violations, { prim = prim_name, violation = v })
      end

      -- 覆盖率诊断
      if ncombos > 1 then
        io.write(("[axiom-D] 原语 '%s': %d boolean 组合, %d 路径并集记录\n"):format(
          prim_name, ncombos, #records))
      end

    elseif nparams == 2 then
      -- ── Layer 1：Token 扫描兜底 ──
      local lines = {}
      meta.process_body({ name = prim_name }, lines)

      local scan_violations = scan_lines_for_violations(lines, prim_name)
      for _, v in ipairs(scan_violations) do
        table.insert(all_violations, { prim = prim_name, violation = v })
      end
    end

    ::continue::
  end

  -- Layer 3：Trace 报错
  if #all_violations > 0 then
    local lines = {}
    table.insert(lines, ("[Axiom-D] App '%s' 的 process_body 校验失败："):format(app_name))
    table.insert(lines, ("  共 %d 处违规\n"):format(#all_violations))
    for _, entry in ipairs(all_violations) do
      table.insert(lines, format_trace(entry.violation, entry.prim))
      table.insert(lines, "")
    end
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
return "nebula_axiom_validator_v2.0_phase4.3"
