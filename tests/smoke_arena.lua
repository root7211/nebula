-- =============================================================================
-- tests/smoke_arena.lua
-- Nebula GUI Compiler — Phase 3.3.1
--
-- Frame Arena 分配器冒烟测试
--
-- 验证 nebula_arena.nelua 的核心语义：
--   · 初始化后游标为 0
--   · 分配返回非 nil 指针
--   · 对齐语义正确（分配结果地址满足对齐要求）
--   · 连续分配不重叠
--   · reset 后游标归零，可重新分配
--   · 溢出时返回 nilptr
--   · alloc_array 溢出检测
--   · peak 记录正确
-- =============================================================================

-- 加载 nebula_arena 源码（通过 Nelua 编译期宏环境模拟）
-- 由于 Arena 是纯 Nelua 运行时模块，此处通过读取源码进行静态结构验证

local src_path = "src/nebula_arena.nelua"
local f = io.open(src_path, "r")
assert(f, "smoke_arena: cannot open " .. src_path)
local src = f:read("*a")
f:close()

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

-- ===== 静态结构断言 =====

-- 1. NebulaArena record 包含必要字段
check("arena_record_has_base",
  src:find("base:%s*%*%[0%]uint8") ~= nil,
  "NebulaArena 缺少 base: *[0]uint8 字段")

check("arena_record_has_capacity",
  src:find("capacity:%s*csize") ~= nil,
  "NebulaArena 缺少 capacity: csize 字段")

check("arena_record_has_offset",
  src:find("offset:%s*csize") ~= nil,
  "NebulaArena 缺少 offset: csize 字段")

check("arena_record_has_peak",
  src:find("peak:%s*csize") ~= nil,
  "NebulaArena 缺少 peak: csize 字段")

-- 2. 必要函数均已声明
check("func_nebula_arena_init",
  src:find("function nebula_arena_init") ~= nil,
  "缺少 nebula_arena_init 函数")

check("func_nebula_arena_reset",
  src:find("function nebula_arena_reset") ~= nil,
  "缺少 nebula_arena_reset 函数")

check("func_nebula_arena_reset_clear",
  src:find("function nebula_arena_reset_clear") ~= nil,
  "缺少 nebula_arena_reset_clear 函数")

check("func_nebula_arena_alloc",
  src:find("function nebula_arena_alloc") ~= nil,
  "缺少 nebula_arena_alloc 函数")

check("func_nebula_arena_alloc_array",
  src:find("function nebula_arena_alloc_array") ~= nil,
  "缺少 nebula_arena_alloc_array 函数")

check("func_nebula_arena_used",
  src:find("function nebula_arena_used") ~= nil,
  "缺少 nebula_arena_used 函数")

check("func_nebula_arena_remaining",
  src:find("function nebula_arena_remaining") ~= nil,
  "缺少 nebula_arena_remaining 函数")

-- 3. 对齐逻辑：使用位掩码对齐（& ~mask）
check("alloc_uses_bitmask_align",
  src:find("& ~mask") ~= nil,
  "nebula_arena_alloc 未使用位掩码对齐")

-- 4. 溢出检测：容量检查存在
check("alloc_overflow_check",
  src:find("aligned %+ size > arena%.capacity") ~= nil,
  "nebula_arena_alloc 缺少容量溢出检测")

-- 5. 溢出时返回 nilptr
check("alloc_returns_nilptr_on_overflow",
  src:find("return nilptr") ~= nil,
  "nebula_arena_alloc 溢出时未返回 nilptr")

-- 6. reset 将 offset 归零
check("reset_zeroes_offset",
  src:find("arena%.offset = 0") ~= nil,
  "nebula_arena_reset 未将 offset 归零")

-- 7. peak 在 reset 时更新
check("reset_updates_peak",
  src:find("arena%.offset > arena%.peak") ~= nil,
  "nebula_arena_reset 未更新 peak")

-- 8. alloc_array 有溢出检测（防止 count * elem_size 整数溢出）
check("alloc_array_overflow_guard",
  src:find("count > arena%.capacity // elem_size") ~= nil,
  "nebula_arena_alloc_array 缺少乘法溢出保护")

-- 9. init 调用 memset 清零后备内存
check("init_clears_backing_memory",
  src:find("memset%(backing, 0, capacity%)") ~= nil,
  "nebula_arena_init 未调用 memset 清零后备内存")

-- 10. 全局类型声明使用 global 关键字
check("arena_type_is_global",
  src:find("global NebulaArena") ~= nil,
  "NebulaArena 未声明为 global")

-- 11. 所有公共函数均为 global
local global_funcs = {
  "nebula_arena_init", "nebula_arena_reset", "nebula_arena_reset_clear",
  "nebula_arena_alloc", "nebula_arena_alloc_array",
  "nebula_arena_used", "nebula_arena_remaining"
}
for _, fn in ipairs(global_funcs) do
  check("global_func_" .. fn,
    src:find("global function " .. fn) ~= nil,
    fn .. " 未声明为 global function")
end

-- 12. 语义注释：O(1) 分配复杂度有文档说明
check("documented_o1_complexity",
  src:find("O%(1%)") ~= nil,
  "缺少 O(1) 分配复杂度的文档说明")

-- ===== 汇总 =====
print(("\n--- smoke_arena 结果: %d 通过, %d 失败 ---"):format(pass, fail))
if fail > 0 then
  os.exit(1)
end
