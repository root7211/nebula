-- verify_linearity.lua
-- 验证 Nebula Flexbox 布局引擎在不同视口尺寸下的线性性
-- 即：组件坐标/尺寸是否真的是视口宽高的线性函数

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

local function approx_eq(a, b, tol)
  return math.abs(a - b) < (tol or 0.01)
end

-- 辅助函数：对给定布局树，在三个视口下采样并验证线性性
local function verify_linear(test_name, build_tree_fn)
  local base_w, base_h = 800, 600
  local test_w, test_h = 1200, 900  -- 大幅偏离基准
  local delta = 1  -- 微扰量

  -- 基准采样
  local root0 = build_tree_fn()
  nebula_layout_solve(root0, base_w, base_h)
  local r0 = nebula_layout_collect(root0)

  -- 宽度微扰采样
  local root_dw = build_tree_fn()
  nebula_layout_solve(root_dw, base_w + delta, base_h)
  local r_dw = nebula_layout_collect(root_dw)

  -- 高度微扰采样
  local root_dh = build_tree_fn()
  nebula_layout_solve(root_dh, base_w, base_h + delta)
  local r_dh = nebula_layout_collect(root_dh)

  -- 目标视口采样（真实值）
  local root_t = build_tree_fn()
  nebula_layout_solve(root_t, test_w, test_h)
  local r_t = nebula_layout_collect(root_t)

  -- 对每个命名节点，计算线性系数并预测目标视口下的值
  for name, b in pairs(r0) do
    if name ~= "_root" then
      local dw = r_dw[name]
      local dh = r_dh[name]
      local t  = r_t[name]

      -- 计算系数
      local cx_vw = (dw.x - b.x) / delta
      local cx_c  = b.x - cx_vw * base_w
      local cy_vh = (dh.y - b.y) / delta
      local cy_c  = b.y - cy_vh * base_h
      local cw_vw = (dw.w - b.w) / delta
      local cw_c  = b.w - cw_vw * base_w
      local ch_vh = (dh.h - b.h) / delta
      local ch_c  = b.h - ch_vh * base_h

      -- 线性预测
      local pred_x = cx_vw * test_w + cx_c
      local pred_y = cy_vh * test_h + cy_c
      local pred_w = cw_vw * test_w + cw_c
      local pred_h = ch_vh * test_h + ch_c

      -- 误差
      local err_x = math.abs(pred_x - t.x)
      local err_y = math.abs(pred_y - t.y)
      local err_w = math.abs(pred_w - t.w)
      local err_h = math.abs(pred_h - t.h)
      local max_err = math.max(err_x, err_y, err_w, err_h)

      local detail = string.format(
        "  pred=(%.2f,%.2f,%.2f,%.2f) actual=(%.2f,%.2f,%.2f,%.2f) max_err=%.4f",
        pred_x, pred_y, pred_w, pred_h, t.x, t.y, t.w, t.h, max_err)

      check(max_err < 0.1,
        string.format("[%s] %s linearity (max_err=%.4f)", test_name, name, max_err))
      if max_err >= 0.1 then
        print(detail)
      end
    end
  end
end

-- ======================================================================
-- 场景 1: 简单 column 布局，固定子元素高度，justify=center, align=center
-- ======================================================================
print("=== 场景 1: column + center + 固定子元素 ===")
verify_linear("S1", function()
  return nebula_layout_node({
    name = "_root", direction = "column", justify = "center", align = "center",
    padding = 32, gap = 16,
    children = {
      nebula_layout_node({ name = "card", width = 480, height = 320 }),
      nebula_layout_node({ name = "btn",  width = 200, height = 44 }),
    },
  })
end)

-- ======================================================================
-- 场景 2: row 布局，space_between
-- ======================================================================
print("\n=== 场景 2: row + space_between ===")
verify_linear("S2", function()
  return nebula_layout_node({
    name = "_root", direction = "row", justify = "space_between", align = "center",
    padding = 16, gap = 0,
    children = {
      nebula_layout_node({ name = "left",   width = 100, height = 40 }),
      nebula_layout_node({ name = "center", width = 200, height = 40 }),
      nebula_layout_node({ name = "right",  width = 100, height = 40 }),
    },
  })
end)

-- ======================================================================
-- 场景 3: 嵌套布局 (column > row > items)
-- ======================================================================
print("\n=== 场景 3: 嵌套 column > row ===")
verify_linear("S3", function()
  return nebula_layout_node({
    name = "_root", direction = "column", justify = "center", align = "center",
    padding = 20, gap = 10,
    children = {
      nebula_layout_node({ name = "header", width = 400, height = 50 }),
      nebula_layout_node({
        name = "body", direction = "row", justify = "space_around", align = "center",
        width = 400, height = 200, gap = 8,
        children = {
          nebula_layout_node({ name = "sidebar", width = 120, height = 180 }),
          nebula_layout_node({ name = "content", width = 260, height = 180 }),
        },
      }),
      nebula_layout_node({ name = "footer", width = 400, height = 40 }),
    },
  })
end)

-- ======================================================================
-- 场景 4: stretch 交叉轴（auto width 子元素）
-- ======================================================================
print("\n=== 场景 4: column + stretch (auto width) ===")
verify_linear("S4", function()
  return nebula_layout_node({
    name = "_root", direction = "column", justify = "start", align = "stretch",
    padding = 16, gap = 8,
    children = {
      nebula_layout_node({ name = "bar1", height = 40 }),  -- width = auto (stretch)
      nebula_layout_node({ name = "bar2", height = 60 }),
      nebula_layout_node({ name = "bar3", height = 40 }),
    },
  })
end)

-- ======================================================================
-- 场景 5: space_around
-- ======================================================================
print("\n=== 场景 5: column + space_around ===")
verify_linear("S5", function()
  return nebula_layout_node({
    name = "_root", direction = "column", justify = "space_around", align = "center",
    padding = 0, gap = 0,
    children = {
      nebula_layout_node({ name = "a", width = 100, height = 50 }),
      nebula_layout_node({ name = "b", width = 100, height = 50 }),
      nebula_layout_node({ name = "c", width = 100, height = 50 }),
    },
  })
end)

-- ======================================================================
-- 场景 6: max(0, free_space) 截断边界 — 子元素总尺寸超过视口
-- 这是线性性可能被破坏的关键场景
-- ======================================================================
print("\n=== 场景 6: 子元素总尺寸接近/超过视口（clamp 边界） ===")
verify_linear("S6", function()
  return nebula_layout_node({
    name = "_root", direction = "column", justify = "center", align = "center",
    padding = 0, gap = 10,
    children = {
      nebula_layout_node({ name = "big1", width = 300, height = 250 }),
      nebula_layout_node({ name = "big2", width = 300, height = 250 }),
      nebula_layout_node({ name = "big3", width = 300, height = 250 }),
    },
  })
end)

-- ======================================================================
-- 场景 7: 混合固定/auto 尺寸 + 嵌套 stretch
-- ======================================================================
print("\n=== 场景 7: 混合固定/auto + 嵌套 stretch ===")
verify_linear("S7", function()
  return nebula_layout_node({
    name = "_root", direction = "column", justify = "start", align = "stretch",
    padding = 32, gap = 16,
    children = {
      nebula_layout_node({
        name = "row1", direction = "row", justify = "space_between", align = "center",
        height = 50, gap = 8,
        children = {
          nebula_layout_node({ name = "r1a", width = 100, height = 40 }),
          nebula_layout_node({ name = "r1b", width = 100, height = 40 }),
        },
      }),
      nebula_layout_node({ name = "main_area", height = 300 }),
      nebula_layout_node({ name = "status_bar", height = 30 }),
    },
  })
end)

print(string.format("\n=== 线性性验证完成: %d 通过, %d 失败 ===", pass_count, fail_count))
if fail_count > 0 then
  print("[WARNING] 存在非线性场景，线性插值方案在这些场景下会产生误差！")
end
