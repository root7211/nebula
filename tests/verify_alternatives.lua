-- verify_alternatives.lua
-- 深入分析 clamp 边界问题，并验证"符号化解算"替代方案的可行性

dofile("src/derive/layout_engine.lua")

local pass_count = 0
local fail_count = 0

local function check(cond, msg)
  if cond then
    pass_count = pass_count + 1
    print("[PASS] " .. msg)
  else
    fail_count = fail_count + 1
    print("[FAIL] " .. msg)
  end
end

-- ======================================================================
-- 分析 1: clamp 边界的精确触发条件
-- 场景 6 中 free_space < 0 时被 clamp 为 0，导致非线性
-- ======================================================================
print("=== 分析 1: clamp 边界触发条件 ===")

-- 场景 6: 3 个 250px 高的子元素 + gap=10，总高度 = 250*3 + 10*2 = 770
-- 当 vh = 600 时: free_space = 600 - 770 = -170 → clamp 到 0
-- 当 vh = 900 时: free_space = 900 - 770 = 130 → 正常
-- 所以在 vh=600 附近微扰采样时，free_space 始终为 0（因为 -170 和 -169 都 clamp 到 0）
-- 导致 dy/dvh = 0，但实际上当 vh > 770 时，dy/dvh ≠ 0

-- 验证：找到精确的临界点
local children_total = 250 * 3 + 10 * 2
print(string.format("  子元素总高度 = %d", children_total))
print(string.format("  当 vh < %d 时，free_space 被 clamp 为 0 → 线性假设失效", children_total))
print(string.format("  当 vh >= %d 时，free_space > 0 → 线性假设成立", children_total))

-- 验证：在 clamp 区域内（vh=600 和 vh=900 跨越了临界点）
local root_600 = nebula_layout_node({
  name = "_root", direction = "column", justify = "center", align = "center",
  padding = 0, gap = 10,
  children = {
    nebula_layout_node({ name = "big1", width = 300, height = 250 }),
    nebula_layout_node({ name = "big2", width = 300, height = 250 }),
    nebula_layout_node({ name = "big3", width = 300, height = 250 }),
  },
})
nebula_layout_solve(root_600, 1200, 600)
local r600 = nebula_layout_collect(root_600)

local root_770 = nebula_layout_node({
  name = "_root", direction = "column", justify = "center", align = "center",
  padding = 0, gap = 10,
  children = {
    nebula_layout_node({ name = "big1", width = 300, height = 250 }),
    nebula_layout_node({ name = "big2", width = 300, height = 250 }),
    nebula_layout_node({ name = "big3", width = 300, height = 250 }),
  },
})
nebula_layout_solve(root_770, 1200, 770)
local r770 = nebula_layout_collect(root_770)

local root_900 = nebula_layout_node({
  name = "_root", direction = "column", justify = "center", align = "center",
  padding = 0, gap = 10,
  children = {
    nebula_layout_node({ name = "big1", width = 300, height = 250 }),
    nebula_layout_node({ name = "big2", width = 300, height = 250 }),
    nebula_layout_node({ name = "big3", width = 300, height = 250 }),
  },
})
nebula_layout_solve(root_900, 1200, 900)
local r900 = nebula_layout_collect(root_900)

print(string.format("  vh=600: big1.y = %.1f (溢出，clamp)", r600["big1"].y))
print(string.format("  vh=770: big1.y = %.1f (临界点)", r770["big1"].y))
print(string.format("  vh=900: big1.y = %.1f (正常)", r900["big1"].y))

-- ======================================================================
-- 分析 2: 替代方案 — 直接符号化解算
-- 不通过数值采样，而是在 Lua 中直接推导出符号化的线性表达式
-- ======================================================================
print("\n=== 分析 2: 符号化解算可行性 ===")

-- 核心观察：Nebula 的 Flexbox 引擎只有以下操作：
-- 1. 加法/减法（padding, gap, 累加子元素尺寸）
-- 2. 除法（justify center/space_between/space_around 的 free_space 分配）
-- 3. max(0, free_space) — 唯一的非线性操作
-- 4. math.max(cross_max, child_size) — 但只用于 auto 尺寸推断

-- 如果所有子元素都有显式尺寸（Nebula 当前要求叶子节点必须有显式尺寸），
-- 那么 main_total 是一个常数（不依赖视口），
-- free_space = main_avail - main_total - total_gap
-- 其中 main_avail 是视口的线性函数。
-- 所以 free_space 也是视口的线性函数。
-- max(0, free_space) 是一个分段线性函数（在 free_space = 0 处有拐点）。

-- 结论：整个布局结果是视口的分段线性函数，而不是全局线性函数。

print("  Nebula Flexbox 引擎的操作分析：")
print("    · 加法/减法: 线性")
print("    · 除法 (free_space / N): 线性")
print("    · max(0, free_space): 分段线性 ← 唯一非线性源")
print("  结论: 布局结果是视口的 **分段线性函数**")

-- ======================================================================
-- 分析 3: 各方案对比
-- ======================================================================
print("\n=== 分析 3: 方案对比 ===")

print("  方案 A: 数值微扰采样 + 线性插值（PLAN_PHASE3_12.md 原方案）")
print("    优点: 实现简单，不需要修改 layout_engine 内部逻辑")
print("    缺点: 在 clamp 边界处产生误差（场景 6 验证了 65px 误差）")
print("    适用: 子元素总尺寸 << 视口尺寸时 100% 正确")
print("")
print("  方案 B: 符号化解算（在 Lua 中用符号表达式替代数值计算）")
print("    优点: 数学精确，支持分段线性")
print("    缺点: 需要重写 layout_engine，复杂度高，维护成本大")
print("    适用: 所有场景")
print("")
print("  方案 C: 直接在 S2 运行 layout_engine（违反公理 A）")
print("    优点: 100% 正确，支持所有 Flexbox 特性")
print("    缺点: 违反公理 A，引入运行时树遍历")
print("    适用: 不推荐")
print("")
print("  方案 D: 数值采样 + clamp 感知（改进方案 A）")
print("    优点: 保持方案 A 的简洁性，同时处理 clamp 边界")
print("    缺点: 需要在编译期检测 clamp 临界点")
print("    适用: 所有场景（推荐）")

-- ======================================================================
-- 分析 4: 方案 D 详细设计 — clamp 感知的线性插值
-- ======================================================================
print("\n=== 分析 4: 方案 D — clamp 感知的线性插值 ===")

-- 核心思想：
-- 1. 在编译期，检测每个 justify 节点的 clamp 临界点
--    临界点 = main_total + total_gap + padding（即子元素刚好填满主轴的视口尺寸）
-- 2. 在临界点两侧分别采样，得到两组线性系数
-- 3. 在运行期，生成一个 if-else 分支：
--    if viewport > threshold then
--      使用"正常区域"系数
--    else
--      使用"溢出区域"系数（通常 free_space = 0，坐标从 0 开始）
--    end

-- 验证方案 D 的正确性：
print("  验证方案 D 在场景 6 中的正确性：")

-- 临界点 = 770（子元素总高度）
local threshold = 770

-- 溢出区域采样 (vh < 770)
local root_low = nebula_layout_node({
  name = "_root", direction = "column", justify = "center", align = "center",
  padding = 0, gap = 10,
  children = {
    nebula_layout_node({ name = "big1", width = 300, height = 250 }),
    nebula_layout_node({ name = "big2", width = 300, height = 250 }),
    nebula_layout_node({ name = "big3", width = 300, height = 250 }),
  },
})
nebula_layout_solve(root_low, 1200, 500)
local r_low = nebula_layout_collect(root_low)

local root_low2 = nebula_layout_node({
  name = "_root", direction = "column", justify = "center", align = "center",
  padding = 0, gap = 10,
  children = {
    nebula_layout_node({ name = "big1", width = 300, height = 250 }),
    nebula_layout_node({ name = "big2", width = 300, height = 250 }),
    nebula_layout_node({ name = "big3", width = 300, height = 250 }),
  },
})
nebula_layout_solve(root_low2, 1200, 501)
local r_low2 = nebula_layout_collect(root_low2)

-- 正常区域采样 (vh >= 770)
local root_hi = nebula_layout_node({
  name = "_root", direction = "column", justify = "center", align = "center",
  padding = 0, gap = 10,
  children = {
    nebula_layout_node({ name = "big1", width = 300, height = 250 }),
    nebula_layout_node({ name = "big2", width = 300, height = 250 }),
    nebula_layout_node({ name = "big3", width = 300, height = 250 }),
  },
})
nebula_layout_solve(root_hi, 1200, 800)
local r_hi = nebula_layout_collect(root_hi)

local root_hi2 = nebula_layout_node({
  name = "_root", direction = "column", justify = "center", align = "center",
  padding = 0, gap = 10,
  children = {
    nebula_layout_node({ name = "big1", width = 300, height = 250 }),
    nebula_layout_node({ name = "big2", width = 300, height = 250 }),
    nebula_layout_node({ name = "big3", width = 300, height = 250 }),
  },
})
nebula_layout_solve(root_hi2, 1200, 801)
local r_hi2 = nebula_layout_collect(root_hi2)

-- 溢出区域系数
local low_cy_vh = r_low2["big1"].y - r_low["big1"].y
local low_cy_c  = r_low["big1"].y - low_cy_vh * 500
print(string.format("  溢出区域: big1.y = %.4f * vh + %.4f", low_cy_vh, low_cy_c))

-- 正常区域系数
local hi_cy_vh = r_hi2["big1"].y - r_hi["big1"].y
local hi_cy_c  = r_hi["big1"].y - hi_cy_vh * 800
print(string.format("  正常区域: big1.y = %.4f * vh + %.4f", hi_cy_vh, hi_cy_c))

-- 用方案 D 预测 vh=900
local pred_900 = hi_cy_vh * 900 + hi_cy_c
print(string.format("  方案 D 预测 vh=900: big1.y = %.1f", pred_900))
print(string.format("  实际值 vh=900:      big1.y = %.1f", r900["big1"].y))
check(math.abs(pred_900 - r900["big1"].y) < 0.1,
  "方案 D 在正常区域预测正确")

-- 用方案 D 预测 vh=600（溢出区域）
local pred_600 = low_cy_vh * 600 + low_cy_c
print(string.format("  方案 D 预测 vh=600: big1.y = %.1f", pred_600))
print(string.format("  实际值 vh=600:      big1.y = %.1f", r600["big1"].y))
check(math.abs(pred_600 - r600["big1"].y) < 0.1,
  "方案 D 在溢出区域预测正确")

print(string.format("\n=== 验证完成: %d 通过, %d 失败 ===", pass_count, fail_count))
