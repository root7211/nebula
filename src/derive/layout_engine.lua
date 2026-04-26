-- =============================================================================
-- derive/layout_engine.lua
-- Nebula GUI Compiler — Phase 3.1
--
-- 编译期 Flexbox 布局引擎
--
-- 在 Nelua 编译期（Lua 环境）中运行简化的 Flexbox 算法，
-- 将嵌套的布局声明树解算为绝对坐标（pos + size），
-- 然后将结果注入到生成的 Nelua 代码中。
--
-- 支持的布局属性：
--   direction    : "row" | "column"  (默认 "column")
--   justify      : "start" | "center" | "end" | "space_between" | "space_around"
--   align        : "start" | "center" | "end" | "stretch"
--   padding      : number | {top, right, bottom, left}
--   gap          : number  (子元素间距)
--   width/height : number | nil (nil = 自动)
--
-- 公开 API：
--   nebula_layout_node(spec)          -> node table
--   nebula_layout_solve(root, w, h)   -> 递归解算，填充 .resolved_x/y/w/h
--   nebula_layout_collect(root)       -> 收集所有叶子节点的解算结果
--
-- 返回模块标识字符串。
-- =============================================================================

-- ===== 节点构造 =====
-- spec = {
--   name       = "card",           -- 可选，用于调试和引用
--   type_name  = "CardVisual",     -- 可选，关联的 Visual 类型名
--   direction  = "column",
--   justify    = "start",
--   align      = "start",
--   padding    = 16,               -- 或 {top=16, right=16, bottom=16, left=16}
--   gap        = 8,
--   width      = 360,              -- nil = 自动
--   height     = nil,              -- nil = 自动
--   children   = { ... },          -- 子节点列表
-- }
function nebula_layout_node(spec)
  spec = spec or {}

  -- 标准化 padding
  local pad = spec.padding or 0
  local padding
  if type(pad) == "number" then
    padding = { top = pad, right = pad, bottom = pad, left = pad }
  elseif type(pad) == "table" then
    padding = {
      top    = pad.top    or pad[1] or 0,
      right  = pad.right  or pad[2] or 0,
      bottom = pad.bottom or pad[3] or 0,
      left   = pad.left   or pad[4] or 0,
    }
  else
    padding = { top = 0, right = 0, bottom = 0, left = 0 }
  end

  return {
    name       = spec.name or nil,
    type_name  = spec.type_name or nil,
    direction  = spec.direction or "column",
    justify    = spec.justify or "start",
    align      = spec.align or "start",
    padding    = padding,
    gap        = spec.gap or 0,
    width      = spec.width,      -- nil = auto
    height     = spec.height,     -- nil = auto
    children   = spec.children or {},
    -- 解算结果（由 solve 填充）
    resolved_x = 0,
    resolved_y = 0,
    resolved_w = 0,
    resolved_h = 0,
  }
end

-- ===== 三遍 Flexbox 求解器 =====

-- Pass 1: 自底向上计算每个节点的"内容尺寸"（content size）
-- 如果节点有显式 width/height，使用之；否则根据子节点累加。
local function measure_node(node)
  local pad = node.padding
  local is_row = (node.direction == "row")
  local children = node.children

  if #children == 0 then
    -- 叶子节点：必须有显式尺寸
    node.content_w = (node.width  or 0) - pad.left - pad.right
    node.content_h = (node.height or 0) - pad.top  - pad.bottom
    if node.content_w < 0 then node.content_w = 0 end
    if node.content_h < 0 then node.content_h = 0 end
    return
  end

  -- 递归测量子节点
  for _, child in ipairs(children) do
    measure_node(child)
  end

  -- 累加子节点的"外部尺寸"（resolved_w/h 在此阶段先用 content + padding）
  local main_sum = 0
  local cross_max = 0
  local total_gap = node.gap * math.max(0, #children - 1)

  for _, child in ipairs(children) do
    local cw = (child.width  or (child.content_w + child.padding.left + child.padding.right))
    local ch = (child.height or (child.content_h + child.padding.top  + child.padding.bottom))
    child._outer_w = cw
    child._outer_h = ch

    if is_row then
      main_sum  = main_sum + cw
      cross_max = math.max(cross_max, ch)
    else
      main_sum  = main_sum + ch
      cross_max = math.max(cross_max, cw)
    end
  end

  -- 内容区域尺寸
  if is_row then
    node.content_w = node.width  and (node.width  - pad.left - pad.right) or (main_sum + total_gap)
    node.content_h = node.height and (node.height - pad.top  - pad.bottom) or cross_max
  else
    node.content_w = node.width  and (node.width  - pad.left - pad.right) or cross_max
    node.content_h = node.height and (node.height - pad.top  - pad.bottom) or (main_sum + total_gap)
  end
  if node.content_w < 0 then node.content_w = 0 end
  if node.content_h < 0 then node.content_h = 0 end
end

-- Pass 2: 自顶向下分配位置
-- parent_x, parent_y: 父节点内容区域的左上角绝对坐标
-- avail_w, avail_h:   父节点内容区域的可用尺寸
local function layout_node(node, parent_x, parent_y, avail_w, avail_h)
  local pad = node.padding

  -- 确定本节点的外部尺寸
  local outer_w = node.width  or (node.content_w + pad.left + pad.right)
  local outer_h = node.height or (node.content_h + pad.top  + pad.bottom)

  -- 如果父节点给了更大的空间且 align=stretch，扩展交叉轴
  -- （这里简化处理：根节点直接使用 avail 尺寸）
  if avail_w > 0 and not node.width then
    outer_w = avail_w
    node.content_w = outer_w - pad.left - pad.right
  end
  if avail_h > 0 and not node.height then
    outer_h = avail_h
    node.content_h = outer_h - pad.top - pad.bottom
  end

  node.resolved_w = outer_w
  node.resolved_h = outer_h

  -- 内容区域起点
  local cx = node.resolved_x + pad.left
  local cy = node.resolved_y + pad.top
  local cw = node.content_w
  local ch = node.content_h

  local children = node.children
  if #children == 0 then return end

  local is_row = (node.direction == "row")
  local gap = node.gap
  local total_gap = gap * math.max(0, #children - 1)

  -- 计算主轴上子元素的总尺寸
  local main_total = 0
  for _, child in ipairs(children) do
    if is_row then
      main_total = main_total + (child.width or child._outer_w or 0)
    else
      main_total = main_total + (child.height or child._outer_h or 0)
    end
  end

  -- 主轴可用空间
  local main_avail = is_row and cw or ch
  local free_space = main_avail - main_total - total_gap
  if free_space < 0 then free_space = 0 end

  -- justify 计算起始偏移和间距
  local main_offset = 0
  local extra_gap = 0
  local justify = node.justify

  if justify == "center" then
    main_offset = free_space / 2
  elseif justify == "end" then
    main_offset = free_space
  elseif justify == "space_between" then
    if #children > 1 then
      extra_gap = free_space / (#children - 1)
    end
  elseif justify == "space_around" then
    local spacing = free_space / #children
    main_offset = spacing / 2
    extra_gap = spacing
  end
  -- justify == "start": main_offset = 0, extra_gap = 0

  -- 放置子元素
  local cursor = main_offset
  for _, child in ipairs(children) do
    local child_main_size, child_cross_size
    if is_row then
      child_main_size  = child.width  or child._outer_w or 0
      child_cross_size = child.height or child._outer_h or 0
    else
      child_main_size  = child.height or child._outer_h or 0
      child_cross_size = child.width  or child._outer_w or 0
    end

    -- align 交叉轴定位
    local cross_avail = is_row and ch or cw
    local cross_offset = 0
    local align = node.align

    if align == "center" then
      cross_offset = (cross_avail - child_cross_size) / 2
    elseif align == "end" then
      cross_offset = cross_avail - child_cross_size
    elseif align == "stretch" then
      child_cross_size = cross_avail
    end
    -- align == "start": cross_offset = 0

    -- 设置子节点绝对坐标
    if is_row then
      child.resolved_x = cx + cursor
      child.resolved_y = cy + cross_offset
      child.resolved_w = child_main_size
      child.resolved_h = child_cross_size
    else
      child.resolved_x = cx + cross_offset
      child.resolved_y = cy + cursor
      child.resolved_w = child_cross_size
      child.resolved_h = child_main_size
    end

    -- 递归布局子节点
    layout_node(child, child.resolved_x, child.resolved_y,
                child.resolved_w, child.resolved_h)

    cursor = cursor + child_main_size + gap + extra_gap
  end
end

-- ===== 主入口：解算整棵布局树 =====
function nebula_layout_solve(root, viewport_w, viewport_h)
  -- Pass 1: 自底向上测量
  measure_node(root)

  -- 根节点定位到 (0, 0)，尺寸为视口大小（如果未指定）
  root.resolved_x = 0
  root.resolved_y = 0
  root.resolved_w = root.width  or viewport_w
  root.resolved_h = root.height or viewport_h
  root.content_w  = root.resolved_w - root.padding.left - root.padding.right
  root.content_h  = root.resolved_h - root.padding.top  - root.padding.bottom

  -- Pass 2: 自顶向下分配
  layout_node(root, 0, 0, root.resolved_w, root.resolved_h)
end

-- ===== 收集所有命名节点的解算结果 =====
-- 返回 { name -> {x, y, w, h, type_name} }
function nebula_layout_collect(node, results)
  results = results or {}
  if node.name then
    results[node.name] = {
      x         = node.resolved_x,
      y         = node.resolved_y,
      w         = node.resolved_w,
      h         = node.resolved_h,
      type_name = node.type_name,
    }
  end
  for _, child in ipairs(node.children or {}) do
    nebula_layout_collect(child, results)
  end
  return results
end

-- ===== 调试打印 =====
function nebula_layout_dump(node, indent)
  indent = indent or 0
  local prefix = string.rep("  ", indent)
  local name = node.name or "(anon)"
  print(("%s[%s] dir=%s pos=(%.1f, %.1f) size=(%.1f x %.1f)"):format(
    prefix, name, node.direction,
    node.resolved_x, node.resolved_y,
    node.resolved_w, node.resolved_h))
  for _, child in ipairs(node.children or {}) do
    nebula_layout_dump(child, indent + 1)
  end
end

-- =============================================================================
-- ★ Phase 3.12: Clamp 感知的分段线性系数推导
--
-- nebula_layout_derive_segments(root, base_w, base_h)
--
-- 对给定的布局树，在 S1 阶段推导出每个命名节点的分段线性系数。
-- 布局结果是视口的分段线性函数，分段点（临界点）由各容器的
-- max(0, free_space) clamp 操作决定。
--
-- 实现策略：
--   1. 遍历布局树，收集所有容器节点在主轴方向上的 clamp 临界点。
--      临界点 = 子元素总尺寸 + 间距 + padding（即 free_space = 0 时的视口尺寸）。
--   2. 对每个分段（相邻临界点之间的区间），在区间内部进行微扰采样，
--      推导出该区间内的线性系数。
--   3. 返回一个分段描述表，供 app_factory.lua 生成 if-else 更新代码。
--
-- 返回结构：
--   {
--     segments = {
--       { threshold = nil,  coeffs = { name -> {cx_vw,cx_c,cy_vh,cy_c,cw_vw,cw_c,ch_vh,ch_c} } },  -- 第一段（最小视口）
--       { threshold = 770,  coeffs = { ... } },  -- 视口 >= 770 时切换到此段
--       ...
--     }
--   }
-- =============================================================================

-- 辅助：深拷贝布局树（解算会修改节点状态，每次采样前需要新副本）
local function _deep_copy_node(node)
  local copy = {}
  for k, v in pairs(node) do
    if k == "children" then
      copy.children = {}
      for _, child in ipairs(v) do
        table.insert(copy.children, _deep_copy_node(child))
      end
    elseif k == "padding" then
      -- ★ 修复：始终规范化为 table 形式，与 nebula_layout_node 一致
      if type(v) == "number" then
        copy.padding = { top = v, right = v, bottom = v, left = v }
      elseif type(v) == "table" then
        copy.padding = {
          top    = v.top    or v[1] or 0,
          right  = v.right  or v[2] or 0,
          bottom = v.bottom or v[3] or 0,
          left   = v.left   or v[4] or 0,
        }
      else
        copy.padding = { top = 0, right = 0, bottom = 0, left = 0 }
      end
    else
      copy[k] = v
    end
  end
  return copy
end

-- 辅助：规范化 padding（支持数字和 table 两种形式，与 nebula_layout_node 一致）
local function _normalize_padding(pad)
  if type(pad) == "number" then
    return { top = pad, right = pad, bottom = pad, left = pad }
  elseif type(pad) == "table" then
    return {
      top    = pad.top    or pad[1] or 0,
      right  = pad.right  or pad[2] or 0,
      bottom = pad.bottom or pad[3] or 0,
      left   = pad.left   or pad[4] or 0,
    }
  else
    return { top = 0, right = 0, bottom = 0, left = 0 }
  end
end

-- 辅助：收集布局树中所有容器节点在主轴方向上的 clamp 临界点
-- 临界点 = 子元素总尺寸 + 间距 + 对应方向的 padding
local function _collect_thresholds(node, thresholds_w, thresholds_h)
  thresholds_w = thresholds_w or {}
  thresholds_h = thresholds_h or {}

  local children = node.children or {}
  if #children > 0 then
    local is_row = (node.direction == "row")
    -- ★ 修复：规范化 padding，支持数字和 table 两种形式
    local pad = _normalize_padding(node.padding or 0)
    local gap = node.gap or 0
    local total_gap = gap * math.max(0, #children - 1)

    -- 计算子元素在主轴上的固定总尺寸
    local main_total = 0
    local all_fixed = true
    for _, child in ipairs(children) do
      local sz = is_row and child.width or child.height
      if sz then
        main_total = main_total + sz
      else
        all_fixed = false  -- 有 auto 尺寸子元素，临界点不可静态计算
      end
    end

    -- 只有所有子元素都有固定尺寸时，临界点才是确定的
    if all_fixed then
      local main_pad = is_row and (pad.left + pad.right) or (pad.top + pad.bottom)
      local threshold = main_total + total_gap + main_pad
      if threshold > 0 then
        if is_row then
          thresholds_w[threshold] = true
        else
          thresholds_h[threshold] = true
        end
      end
    end

    -- 递归收集子节点的临界点
    for _, child in ipairs(children) do
      _collect_thresholds(child, thresholds_w, thresholds_h)
    end
  end

  return thresholds_w, thresholds_h
end

-- 辅助：在给定视口尺寸下采样，返回所有命名节点的坐标
local function _sample(root_spec, vw, vh)
  local root = _deep_copy_node(root_spec)
  nebula_layout_solve(root, vw, vh)
  return nebula_layout_collect(root)
end

-- 辅助：通过两点采样推导线性系数
-- 在 (sample_w, sample_h) 和 (sample_w+1, sample_h+1) 两点采样
local function _derive_coeffs(root_spec, sample_w, sample_h)
  local r0  = _sample(root_spec, sample_w,     sample_h)
  local rdw = _sample(root_spec, sample_w + 1, sample_h)
  local rdh = _sample(root_spec, sample_w,     sample_h + 1)

  local coeffs = {}
  for name, b in pairs(r0) do
    if name ~= "_root" then
      local dw = rdw[name]
      local dh = rdh[name]
      if dw and dh then
        local cx_vw = dw.x - b.x
        local cy_vh = dh.y - b.y
        local cw_vw = dw.w - b.w
        local ch_vh = dh.h - b.h
        coeffs[name] = {
          cx_vw = cx_vw, cx_c = b.x - cx_vw * sample_w,
          cy_vh = cy_vh, cy_c = b.y - cy_vh * sample_h,
          cw_vw = cw_vw, cw_c = b.w - cw_vw * sample_w,
          ch_vh = ch_vh, ch_c = b.h - ch_vh * sample_h,
          type_name = b.type_name,
        }
      end
    end
  end
  return coeffs
end

-- 主函数：推导分段线性系数
function nebula_layout_derive_segments(root_spec, base_w, base_h)
  base_w = base_w or 800
  base_h = base_h or 600

  -- 1. 收集所有临界点
  local tw, th = _collect_thresholds(root_spec, {}, {})

  -- 2. 将临界点排序为有序列表
  local sorted_w = {}
  for t in pairs(tw) do table.insert(sorted_w, t) end
  table.sort(sorted_w)

  local sorted_h = {}
  for t in pairs(th) do table.insert(sorted_h, t) end
  table.sort(sorted_h)

  -- 3. 构建分段列表
  -- 目前仅处理高度方向的临界点（最常见场景：column 布局溢出）
  -- 宽度方向的临界点处理方式相同，未来可扩展为二维分段
  -- 每个分段由 { threshold_h, threshold_w, coeffs } 描述
  -- threshold = nil 表示最小段（视口尺寸 < 第一个临界点）

  local segments = {}

  -- 确定采样点列表：在每个临界点两侧各取一个采样点
  -- 分段区间: (-∞, t1), [t1, t2), [t2, t3), ..., [tn, +∞)
  -- 在每段内取中点（或临界点 - 1 / 临界点 + 1）采样

  -- 合并宽高临界点，简化为一维处理（以高度为主，宽度类似）
  -- 对于大多数 column 布局，只有高度方向的临界点
  -- 对于 row 布局，只有宽度方向的临界点
  -- 我们分别处理，生成的 if-else 条件同时检查 vw 和 vh

  -- 简化：将所有临界点合并处理
  -- 每个分段的采样点选在该段内部（临界点 - 1 对应上一段，临界点 + 1 对应下一段）

  -- 构建高度分段
  local h_breakpoints = {}
  for _, t in ipairs(sorted_h) do
    table.insert(h_breakpoints, t)
  end

  -- 构建宽度分段
  local w_breakpoints = {}
  for _, t in ipairs(sorted_w) do
    table.insert(w_breakpoints, t)
  end

  -- 如果没有任何临界点，只有一个全局线性段
  if #h_breakpoints == 0 and #w_breakpoints == 0 then
    local coeffs = _derive_coeffs(root_spec, base_w, base_h)
    table.insert(segments, {
      threshold_h = nil,
      threshold_w = nil,
      coeffs = coeffs,
    })
    return {
      segments = segments,
      h_breakpoints = h_breakpoints,
      w_breakpoints = w_breakpoints,
    }
  end

  -- 有临界点时，生成多个分段
  -- 采样策略：在每个分段内，选择一个代表性采样点
  -- 分段 0: 视口 < 第一个临界点，采样点 = (base_w, min(h_breakpoints[1]-1, base_h))
  -- 分段 k: 视口 >= h_breakpoints[k]，采样点 = (base_w, h_breakpoints[k]+1)

  -- 第一段（溢出区域）
  local first_sample_h = base_h
  if #h_breakpoints > 0 and base_h >= h_breakpoints[1] then
    first_sample_h = h_breakpoints[1] - 1
  end
  local first_sample_w = base_w
  if #w_breakpoints > 0 and base_w >= w_breakpoints[1] then
    first_sample_w = w_breakpoints[1] - 1
  end

  local first_coeffs = _derive_coeffs(root_spec, first_sample_w, first_sample_h)
  table.insert(segments, {
    threshold_h = nil,
    threshold_w = nil,
    coeffs = first_coeffs,
  })

  -- 后续分段（每个临界点之后的区域）
  -- 简化：只处理高度临界点（最常见场景）
  -- 宽度临界点的处理方式相同，此处暂不生成二维分段
  for i, t in ipairs(h_breakpoints) do
    local sample_h = t + 1  -- 在临界点之后采样
    local sample_w = base_w
    local coeffs = _derive_coeffs(root_spec, sample_w, sample_h)
    table.insert(segments, {
      threshold_h = t,
      threshold_w = nil,
      coeffs = coeffs,
    })
  end

  -- 宽度临界点分段（独立处理）
  for i, t in ipairs(w_breakpoints) do
    local sample_w = t + 1
    local sample_h = base_h
    local coeffs = _derive_coeffs(root_spec, sample_w, sample_h)
    table.insert(segments, {
      threshold_h = nil,
      threshold_w = t,
      coeffs = coeffs,
    })
  end

  return {
    segments = segments,
    h_breakpoints = h_breakpoints,
    w_breakpoints = w_breakpoints,
  }
end

-- 返回模块标识
return "nebula_layout_engine_v0.2_phase3.12"
