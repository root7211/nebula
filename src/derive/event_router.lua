-- =============================================================================
-- derive/event_router.lua — Nebula GUI Compiler Phase 5.0 S1b
--
-- 事件路由去重规则
--
-- 路由优先级规则（严格执行）：
--   1. nebula_on 声明的 (target, event_type) 由 _route_input 独占处理
--   2. 未被 nebula_on 声明的 (target, event_type) 回落到旧 process_input
--   3. 一个组件可以同时使用两种机制，但事件类型不重叠
--
-- 功能：
--   build_declared_event_set(reg) — 构建已声明事件集合
--   is_event_declared(set, target, event_type) — 查询事件是否已声明
--   detect_conflicts(declared, process_input_events) — 检测冲突并发出警告
-- =============================================================================

local EventRouter = {}

--- 构建已声明事件集合。
--- 从注册表的 _events 列表中提取所有 (target, event_type) 组合。
---
--- @param reg table App 注册表
--- @return table declared  {target -> {event_type -> true}}
function EventRouter.build_declared_event_set(reg)
  assert(reg, "build_declared_event_set: reg required")

  local declared = {}
  local events = reg._events or {}

  for _, evt in ipairs(events) do
    assert(evt.target, "build_declared_event_set: event must have target")
    assert(evt.event_type, "build_declared_event_set: event must have event_type")

    if not declared[evt.target] then
      declared[evt.target] = {}
    end
    declared[evt.target][evt.event_type] = true
  end

  return declared
end

--- 查询事件是否已由 nebula_on 声明。
---
--- @param declared table  build_declared_event_set 的返回值
--- @param target string   组件名
--- @param event_type string 事件类型
--- @return boolean
function EventRouter.is_event_declared(declared, target, event_type)
  return declared[target] ~= nil and declared[target][event_type] == true
end

--- 检测 nebula_on 声明与 process_input 处理的冲突。
--- 返回冲突列表和警告信息。
---
--- @param declared table       已声明事件集合
--- @param legacy_events table  process_input 中处理的事件列表 [{target, event_type}]
--- @return table conflicts     冲突列表 [{target, event_type, warning}]
function EventRouter.detect_conflicts(declared, legacy_events)
  local conflicts = {}

  for _, evt in ipairs(legacy_events or {}) do
    if EventRouter.is_event_declared(declared, evt.target, evt.event_type) then
      conflicts[#conflicts + 1] = {
        target     = evt.target,
        event_type = evt.event_type,
        warning    = ("nebula: component '%s' handles '%s' in both nebula_on and process_input. " ..
          "The nebula_on handler takes precedence; process_input will not receive this event."):format(
          evt.target, evt.event_type),
      }
    end
  end

  return conflicts
end

--- 按组件分组汇总已声明事件（用于代码生成诊断）。
---
--- @param declared table 已声明事件集合
--- @return table summary [{target, events = {event_type, ...}}]
function EventRouter.summarize(declared)
  local summary = {}
  for target, events in pairs(declared) do
    local event_list = {}
    for event_type, _ in pairs(events) do
      event_list[#event_list + 1] = event_type
    end
    table.sort(event_list)
    summary[#summary + 1] = { target = target, events = event_list }
  end
  table.sort(summary, function(a, b) return a.target < b.target end)
  return summary
end

return EventRouter
