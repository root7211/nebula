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

-- 返回模块标识
return "nebula_layout_engine_v0.1_phase3.1"
