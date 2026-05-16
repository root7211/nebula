-- =============================================================================
-- derive/dirty_map.lua — Nebula GUI Compiler Phase 5.0 S1a
--
-- dirty bit 分配策略
--
-- dirty bit 绑定的是 binding target（派生状态），而非原始 state。
-- 仅钻石节点（入度 > 1 的派生状态）需要 dirty bit 来延迟计算。
--
-- 功能：
--   allocate(graph)        — 按拓扑序为钻石节点分配 bit index
--   storage_type(bit_count) — 选择最小存储类型
--   gen_set(bit_index)     — 生成置位代码
--   gen_test(bit_index)    — 生成测试代码
--   gen_clear(bit_count)   — 生成清零代码
-- =============================================================================

local DirtyMap = {}

--- 为全知图中的钻石节点分配 dirty bit。
--- 按拓扑序分配以保证 commit 顺序稳定。
---
--- @param graph table 全知图对象，需包含 topo_order 和 diamond_nodes
--- @return table map  {target_name -> bit_index}
--- @return number bit_count 分配的总 bit 数
function DirtyMap.allocate(graph)
  assert(graph, "DirtyMap.allocate: graph required")
  assert(graph.topo_order, "DirtyMap.allocate: graph.topo_order required")
  assert(graph.diamond_nodes, "DirtyMap.allocate: graph.diamond_nodes required")

  local map = {}
  local bit = 0

  for _, node in ipairs(graph.topo_order) do
    if graph.diamond_nodes[node] then
      map[node] = bit
      bit = bit + 1
    end
  end

  return map, bit
end

--- 根据 bit 数量选择最小的 dirty 存储类型。
---
--- @param bit_count number 需要的 bit 总数
--- @return string nelua 类型字符串
function DirtyMap.storage_type(bit_count)
  assert(type(bit_count) == "number", "DirtyMap.storage_type: bit_count must be a number")
  assert(bit_count >= 0, "DirtyMap.storage_type: bit_count must be >= 0")

  if bit_count == 0 then
    return "uint8"  -- 即使无钻石节点也生成最小类型，避免零大小
  elseif bit_count <= 8 then
    return "uint8"
  elseif bit_count <= 16 then
    return "uint16"
  elseif bit_count <= 32 then
    return "uint32"
  elseif bit_count <= 64 then
    return "uint64"
  else
    local chunks = math.ceil(bit_count / 64)
    return ("array(uint64, %d)"):format(chunks)
  end
end

--- 生成 dirty bit 置位代码。
---
--- @param bit_index number 要置位的 bit 索引
--- @return string 生成的 Nelua 代码
function DirtyMap.gen_set(bit_index)
  assert(type(bit_index) == "number", "DirtyMap.gen_set: bit_index must be a number")
  assert(bit_index >= 0, "DirtyMap.gen_set: bit_index must be >= 0")

  if bit_index < 64 then
    return ("self._dirty = self._dirty | (1_u64 << %d)"):format(bit_index)
  else
    local chunk = math.floor(bit_index / 64)
    local offset = bit_index % 64
    return ("self._dirty[%d] = self._dirty[%d] | (1_u64 << %d)"):format(chunk, chunk, offset)
  end
end

--- 生成 dirty bit 测试代码（返回布尔表达式字符串）。
---
--- @param bit_index number 要测试的 bit 索引
--- @return string 生成的 Nelua 条件表达式
function DirtyMap.gen_test(bit_index)
  assert(type(bit_index) == "number", "DirtyMap.gen_test: bit_index must be a number")
  assert(bit_index >= 0, "DirtyMap.gen_test: bit_index must be >= 0")

  if bit_index < 64 then
    return ("self._dirty & (1_u64 << %d) ~= 0"):format(bit_index)
  else
    local chunk = math.floor(bit_index / 64)
    local offset = bit_index % 64
    return ("self._dirty[%d] & (1_u64 << %d) ~= 0"):format(chunk, offset)
  end
end

--- 生成 dirty bit 清零代码。
---
--- @param bit_count number 总 bit 数（用于决定单值清零还是数组清零）
--- @return string 生成的 Nelua 代码
function DirtyMap.gen_clear(bit_count)
  bit_count = bit_count or 0
  if bit_count <= 64 then
    return "self._dirty = 0"
  else
    local chunks = math.ceil(bit_count / 64)
    local lines = {}
    for i = 0, chunks - 1 do
      table.insert(lines, ("self._dirty[%d] = 0"):format(i))
    end
    return table.concat(lines, "\n")
  end
end

return DirtyMap
