-- =============================================================================
-- derive/builtin_factory.lua
-- Nebula GUI Compiler — Phase 5.2 R4
--
-- Builtin Producer AST 代码生成器（Builtin Factory）
--
-- ★ Phase 5.2 R4：用 AST 拼接替代字符串模板
--
-- 设计哲学（公理 A — 阶段封闭性）：
--   · S1 阶段：builtin spec → AST 节点树 → Nelua 源码字符串
--   · 生成的源码通过 aster.parse + inject_statement 注入编译流程
--   · AST 节点是纯数据结构，无副作用；emit 是纯函数
--
-- 为何用 AST 替代字符串模板：
--   · 字符串模板中 %s 占位符过多，修改一处需同步 4+ 个 format 参数
--   · AST 节点可组合、可复用、可测试——每个节点独立可验证
--   · 错误定位：AST 节点携带语义信息，比匿名 %s 更易调试
--
-- 公开 API：
--   NEBULA_BUILTIN_SPECS               -> table   (内置 builtin 规格注册表)
--   nebula_builtin_emit(name, opts)     -> string  (从 spec + opts 生成 Nelua 源码)
--   nebula_register_builtin_spec(name, spec) -> void (注册自定义 builtin spec)
--
-- AST 节点类型：
--   lit(s)           — 原样字面量
--   ref(...)         — 变量引用（自动拼接 . 分隔符）
--   line(...)        — 一行语句（多个片段拼接）
--   block(indent, stmts) — 缩进块
--   while_lt(var, limit, body) — while var < limit do ... end
--   if_then(cond, then_body, else_body) — if ... then ... else ... end
--   func(name, params, ret, body) — 函数定义
--
-- opts 字段（由 nebula_builtins.nelua 传入）：
--   editor_name   : string  — 编辑器组件名
--   cell_w        : number  — 单元格宽度
--   cell_h        : number  — 单元格高度
--   cols          : number  — 列数
--   rows          : number  — 行数
--   editor_state  : string  — (可选) App Record 模式下的 editor state 字段名
--   comp_name     : string  — (term_grid 专用) 组件名
-- =============================================================================

local VERSION = "nebula_builtin_factory_v1.0_phase5.2-r4"

-- =============================================================================
-- Section 1: AST Node Constructors
-- =============================================================================

-- lit(s) — raw literal string fragment
local function lit(s) return { kind = "lit", value = s } end

-- ref(...) — variable reference: ref("app", "editor") → "app.editor"
local function ref(...)
  local parts = {...}
  return { kind = "ref", parts = parts }
end

-- line(...) — a single statement line composed of fragments
local function line(...)
  local fragments = {...}
  return { kind = "line", fragments = fragments }
end

-- block(indent, stmts) — indented block of statements
local function block(indent, stmts)
  return { kind = "block", indent = indent, stmts = stmts }
end

-- while_lt(var, limit, body) — while var < limit do body end
local function while_lt(var, limit, body)
  return { kind = "while_lt", var = var, limit = limit, body = body }
end

-- if_then(cond, then_body, else_body) — if cond then ... [else ...] end
local function if_then(cond, then_body, else_body)
  return { kind = "if_then", cond = cond, then_body = then_body, else_body = else_body }
end

-- if_then_elseif(cond, then_body, elseif_branches, else_body)
local function if_then_elseif(cond, then_body, elseif_branches, else_body)
  return { kind = "if_then_elseif", cond = cond, then_body = then_body,
           elseif_branches = elseif_branches, else_body = else_body }
end

-- for_range(var, start, stop, body) — for var = start, < stop do body end
local function for_range(var, start, stop, body)
  return { kind = "for_range", var = var, start = start, stop = stop, body = body }
end

-- func(name, params, ret, body) — global function definition
-- params: array of {name, type} pairs
local function func(name, params, ret, body)
  return { kind = "func", name = name, params = params, ret = ret, body = body }
end

-- raw(s) — multi-line raw source, emitted as-is
local function raw(s) return { kind = "raw", value = s } end

-- =============================================================================
-- Section 2: AST Emitter — Converts AST nodes to Nelua source strings
-- =============================================================================

local emit  -- forward declaration

local function emit_fragment(node)
  if type(node) == "string" then return node end
  if node.kind == "lit" then return node.value end
  if node.kind == "ref" then return table.concat(node.parts, ".") end
  error("[builtin_factory] unknown fragment kind: " .. tostring(node.kind))
end

local function emit_fragments(fragments)
  local parts = {}
  for _, f in ipairs(fragments) do
    parts[#parts + 1] = emit_fragment(f)
  end
  return table.concat(parts)
end

local function make_indent(level)
  return string.rep("  ", level)
end

-- emit(node, indent_level) → string
function emit(node, indent)
  indent = indent or 0
  local pad = make_indent(indent)

  if node.kind == "lit" or node.kind == "ref" then
    return pad .. emit_fragment(node)

  elseif node.kind == "raw" then
    -- Raw source: prefix each line with current indent
    local lines = {}
    for ln in node.value:gmatch("([^\n]*)\n?") do
      if ln ~= "" then
        lines[#lines + 1] = pad .. ln
      end
    end
    return table.concat(lines, "\n")

  elseif node.kind == "line" then
    return pad .. emit_fragments(node.fragments)

  elseif node.kind == "block" then
    local lines = {}
    for _, stmt in ipairs(node.stmts) do
      lines[#lines + 1] = emit(stmt, indent + node.indent)
    end
    return table.concat(lines, "\n")

  elseif node.kind == "while_lt" then
    local lines = {}
    lines[#lines + 1] = pad .. "while " .. emit_fragment(node.var) ..
                         " < " .. emit_fragment(node.limit) .. " do"
    for _, stmt in ipairs(node.body) do
      lines[#lines + 1] = emit(stmt, indent + 1)
    end
    lines[#lines + 1] = pad .. "end"
    return table.concat(lines, "\n")

  elseif node.kind == "while_and" then
    local conds = {}
    for _, c in ipairs(node.conditions) do
      conds[#conds + 1] = emit_fragment(c)
    end
    local lines = {}
    lines[#lines + 1] = pad .. "while " .. table.concat(conds, " and ") .. " do"
    for _, stmt in ipairs(node.body) do
      lines[#lines + 1] = emit(stmt, indent + 1)
    end
    lines[#lines + 1] = pad .. "end"
    return table.concat(lines, "\n")

  elseif node.kind == "if_then" then
    local lines = {}
    lines[#lines + 1] = pad .. "if " .. emit_fragment(node.cond) .. " then"
    for _, stmt in ipairs(node.then_body) do
      lines[#lines + 1] = emit(stmt, indent + 1)
    end
    if node.else_body and #node.else_body > 0 then
      lines[#lines + 1] = pad .. "else"
      for _, stmt in ipairs(node.else_body) do
        lines[#lines + 1] = emit(stmt, indent + 1)
      end
    end
    lines[#lines + 1] = pad .. "end"
    return table.concat(lines, "\n")

  elseif node.kind == "if_then_elseif" then
    local lines = {}
    lines[#lines + 1] = pad .. "if " .. emit_fragment(node.cond) .. " then"
    for _, stmt in ipairs(node.then_body) do
      lines[#lines + 1] = emit(stmt, indent + 1)
    end
    if node.elseif_branches then
      for _, br in ipairs(node.elseif_branches) do
        lines[#lines + 1] = pad .. "elseif " .. emit_fragment(br.cond) .. " then"
        for _, stmt in ipairs(br.body) do
          lines[#lines + 1] = emit(stmt, indent + 1)
        end
      end
    end
    if node.else_body and #node.else_body > 0 then
      lines[#lines + 1] = pad .. "else"
      for _, stmt in ipairs(node.else_body) do
        lines[#lines + 1] = emit(stmt, indent + 1)
      end
    end
    lines[#lines + 1] = pad .. "end"
    return table.concat(lines, "\n")

  elseif node.kind == "for_range" then
    local lines = {}
    lines[#lines + 1] = pad .. "for " .. node.var .. " = " ..
                         emit_fragment(node.start) .. ", < " ..
                         emit_fragment(node.stop) .. " do"
    for _, stmt in ipairs(node.body) do
      lines[#lines + 1] = emit(stmt, indent + 1)
    end
    lines[#lines + 1] = pad .. "end"
    return table.concat(lines, "\n")

  elseif node.kind == "func" then
    local param_strs = {}
    for _, p in ipairs(node.params) do
      param_strs[#param_strs + 1] = p[1] .. ": " .. p[2]
    end
    local lines = {}
    local ret_str = node.ret and (": " .. node.ret) or ""
    lines[#lines + 1] = "global function " .. node.name .. "("
    lines[#lines + 1] = "  " .. table.concat(param_strs, ", ")
    lines[#lines + 1] = ")" .. ret_str
    for _, stmt in ipairs(node.body) do
      lines[#lines + 1] = emit(stmt, 1)
    end
    lines[#lines + 1] = "end"
    return table.concat(lines, "\n")

  else
    error("[builtin_factory] unknown node kind: " .. tostring(node.kind))
  end
end

-- while_and(conditions, body) — while c1 and c2 and ... do body end
local function while_and(conditions, body)
  return { kind = "while_and", conditions = conditions, body = body }
end

-- =============================================================================
-- Section 3: Builtin Specs — AST builders for each builtin Producer
-- =============================================================================

-- Helper: resolve editor state variable references
-- When editor_state is set (App Record mode), refs go through app.es.xxx
-- otherwise they use global variables
local function state_ref(opts, field, global_name)
  local es = opts.editor_state
  if es then
    return ("app.%s.%s"):format(es, field)
  else
    return global_name
  end
end

-- Helper: standard function params for all Producers
local PRODUCER_PARAMS = {
  {"app", "auto"},
  {"instances", "*[0]DenseCharInstance"},
  {"count", "*uint32"},
  {"max", "uint32"},
}

-- ---------------------------------------------------------------------------
-- 3.1  line_nums — 行号 Producer
-- ---------------------------------------------------------------------------
local function build_line_nums(opts)
  local editor_name = opts.editor_name or opts.comp_name
  local cell_w = tostring(opts.cell_w or 10.0)
  local cell_h = tostring(opts.cell_h or 16.0)
  local rows   = opts.rows or 50
  local fname  = "nebula_fill_line_nums_" .. editor_name
  local layout_x = "app.dense_layout_line_nums_x"
  local layout_y = "app.dense_layout_line_nums_y"

  local body = {
    line(lit("local editor = &app." .. editor_name)),
    line(lit("local mb = &editor.visual.multi_buf")),
    line(lit("local origin_x: float32 = " .. layout_x)),
    line(lit("local origin_y: float32 = " .. layout_y .. " + 4.0")),
    line(lit("local idx: uint32 = 0")),
    line(lit(("local scroll_row: uint32 = (@uint32)(editor.scroll_offset_y / (%s + 2.0))"):format(cell_h))),
    line(lit(("local visible_rows: uint32 = %d"):format(rows))),
    line(lit("local LINE_NUM_DIGITS: uint32 = 7")),
    line(lit("local row: uint32 = 0")),
    while_lt(lit("row"), lit("visible_rows"), {
      -- guard: also check idx < max (emitted as raw for exact match)
      raw(
        "    local buf_row = row + scroll_row\n" ..
        "    local is_cursor_line = (buf_row == editor.cursor_row)\n" ..
        "    local bg = is_cursor_line and nebula_theme_bg_cursor_line() or nebula_theme_bg_linenum()"
      ),
      if_then(lit("buf_row < mb.line_count"), {
        -- line number digits computation
        raw(
          "      local num = buf_row + 1\n" ..
          "      -- 动态计算行号位数（支持最多 9999999 行）\n" ..
          "      local digits: [7]uint32\n" ..
          "      local divisor: uint32 = 1000000\n" ..
          "      local leading_zero: boolean = true\n" ..
          "      local di: uint32 = 0"
        ),
        while_lt(lit("di"), lit("LINE_NUM_DIGITS"), {
          raw(
            "        local d: uint32 = (num / divisor) % 10\n" ..
            "        if d > 0 then leading_zero = false end\n" ..
            "        digits[di] = leading_zero and d == 0 and di < (LINE_NUM_DIGITS - 1) and 32 or (48 + d)\n" ..
            "        divisor = divisor / 10\n" ..
            "        di = di + 1"
          ),
        }),
        -- emit digit chars
        raw("      local nc: uint32 = 0"),
        while_and({lit("nc < LINE_NUM_DIGITS"), lit("idx < max")}, {
          raw(("        nebula_dense_grid_fill_instance(&instances[idx], row, nc, digits[nc], origin_x, origin_y, %s, %s, nebula_theme_fg_linenum(), bg)"):format(cell_w, cell_h)),
          raw("        idx = idx + 1; nc = nc + 1"),
        }),
        -- separator pipe
        if_then(lit("idx < max"), {
          raw(("        nebula_dense_grid_fill_instance(&instances[idx], row, LINE_NUM_DIGITS, NEBULA_CHAR_PIPE, origin_x, origin_y, %s, %s, nebula_theme_fg_separator(), bg)"):format(cell_w, cell_h)),
          raw("        idx = idx + 1"),
        }),
      }, {
        -- empty line: tilde + spaces + pipe
        raw("      local nc: uint32 = 0"),
        while_and({lit("nc < LINE_NUM_DIGITS"), lit("idx < max")}, {
          raw(("        nebula_dense_grid_fill_instance(&instances[idx], row, nc, nc == 0 and NEBULA_CHAR_TILDE or NEBULA_CHAR_SPACE, origin_x, origin_y, %s, %s, nebula_theme_fg_linenum(), nebula_theme_bg_linenum())"):format(cell_w, cell_h)),
          raw("        idx = idx + 1; nc = nc + 1"),
        }),
        if_then(lit("idx < max"), {
          raw(("        nebula_dense_grid_fill_instance(&instances[idx], row, LINE_NUM_DIGITS, NEBULA_CHAR_PIPE, origin_x, origin_y, %s, %s, nebula_theme_fg_separator(), nebula_theme_bg_linenum())"):format(cell_w, cell_h)),
          raw("        idx = idx + 1"),
        }),
      }),
      raw("    row = row + 1"),
    }),
    line(lit("$count = idx")),
  }

  return fname, func(fname, PRODUCER_PARAMS, "void", body)
end

-- ---------------------------------------------------------------------------
-- 3.2  status_bar — 状态栏 Producer
-- ---------------------------------------------------------------------------
local function build_status_bar(opts)
  local editor_name = opts.editor_name or opts.comp_name
  local cell_w = tostring(opts.cell_w or 10.0)
  local cell_h = tostring(opts.cell_h or 16.0)
  local cols   = opts.cols or 128
  local fname  = "nebula_fill_status_bar_" .. editor_name
  local layout_x = "app.dense_layout_status_bar_x"
  local layout_y = "app.dense_layout_status_bar_y"

  local modified_ref  = state_ref(opts, "modified",  "_editor_modified")
  local has_file_ref  = state_ref(opts, "has_file",  "_editor_has_file")
  local file_path_ref = state_ref(opts, "file_path", "_editor_file_path")

  local body = {
    raw('require "nebula_editor"'),
    line(lit("local editor = &app." .. editor_name)),
    line(lit("local origin_x: float32 = " .. layout_x)),
    line(lit("local origin_y: float32 = " .. layout_y .. " + 4.0")),
    line(lit("local bg = nebula_theme_bg_status()")),
    line(lit("local fg = nebula_theme_fg_status()")),
    line(lit("local idx: uint32 = 0")),
    line(lit(("local STATUS_COLS: uint32 = %d"):format(cols))),
    line(lit("local buf: [256]uint8")),
    line(lit("local row_1 = (@int32)(editor.cursor_row + 1)")),
    line(lit("local col_1 = (@int32)(editor.cursor_col + 1)")),
    line(lit("local lines = (@int32)(editor.visual.multi_buf.line_count)")),
    line(lit(('local mod_str: cstring = %s and " [+]" or ""'):format(modified_ref))),
    line(lit("local file_str: cstring")),
    if_then(lit(has_file_ref), {
      raw(
        "    local last_slash: int32 = -1\n" ..
        "    local fi: uint32 = 0"
      ),
      while_and({lit(file_path_ref .. "[fi] ~= 0"), lit("fi < 4095")}, {
        raw(("      if %s[fi] == NEBULA_CHAR_SLASH then last_slash = (@int32)(fi) end"):format(file_path_ref)),
        raw("      fi = fi + 1"),
      }),
      raw("    local start: uint32 = last_slash >= 0 and (@uint32)(last_slash + 1) or 0"),
      raw(("    file_str = (@cstring)(&%s[start])"):format(file_path_ref)),
    }, {
      raw('    file_str = "[untitled]"'),
    }),
    raw(
      '  local slen = snprintf((@cstring)(&buf[0]), 255,\n' ..
      '    " %%s%%s  |  Ln %%d, Col %%d  |  %%d lines  |  UTF-8  |  LF",\n' ..
      '    file_str, mod_str, row_1, col_1, lines)\n' ..
      '  if slen < 0 then slen = 0 end\n' ..
      '  if slen > 255 then slen = 255 end\n' ..
      '  local str_len: uint32 = (@uint32)(slen)'
    ),
    -- fill loop
    raw("  local col: uint32 = 0"),
    while_and({lit("col < STATUS_COLS"), lit("idx < max")}, {
      raw(
        "    local ch: uint32 = 32\n" ..
        "    if col < str_len then ch = (@uint32)(buf[col]) end"
      ),
      raw(("    nebula_dense_grid_fill_instance(&instances[idx], 0, col, ch, origin_x, origin_y, %s, %s, fg, bg)"):format(cell_w, cell_h)),
      raw("    idx = idx + 1; col = col + 1"),
    }),
    line(lit("$count = idx")),
  }

  return fname, func(fname, PRODUCER_PARAMS, "void", body)
end

-- ---------------------------------------------------------------------------
-- 3.3  search_bar — 搜索栏 Producer
-- ---------------------------------------------------------------------------
local function build_search_bar(opts)
  local editor_name = opts.editor_name or opts.comp_name
  local cell_w = tostring(opts.cell_w or 10.0)
  local cell_h = tostring(opts.cell_h or 16.0)
  local cols   = opts.cols or 128
  local fname  = "nebula_fill_search_bar_" .. editor_name
  local layout_x = "app.dense_layout_search_bar_x"
  local layout_y = "app.dense_layout_search_bar_y"

  local search_active  = state_ref(opts, "search_active",  "_search_active")
  local search_replace = state_ref(opts, "search_replace", "_search_replace")
  local search_buf     = state_ref(opts, "search_buf",     "_search_buf")
  local search_len     = state_ref(opts, "search_len",     "_search_len")
  local search_cursor  = state_ref(opts, "search_cursor",  "_search_cursor")
  local replace_buf    = state_ref(opts, "replace_buf",    "_replace_buf")
  local replace_len    = state_ref(opts, "replace_len",    "_replace_len")
  local search_current = state_ref(opts, "search_current", "_search_current")
  local search_match_count = state_ref(opts, "search_match_count", "_search_match_count")

  local body = {
    raw('require "nebula_editor"'),
    line(lit("local origin_x: float32 = " .. layout_x)),
    line(lit("local origin_y: float32 = " .. layout_y .. " + 4.0")),
    line(lit("local bg = nebula_theme_bg_status()")),
    line(lit("local fg = nebula_theme_fg_status()")),
    line(lit("local fg_label = nebula_theme_fg_search_label()")),
    line(lit("local idx: uint32 = 0")),
    line(lit(("local SB_COLS: uint32 = %d"):format(cols))),
    -- inactive: hide search bar
    if_then(lit("not " .. search_active), {
      raw(
        "    local hide_bg = nebula_theme_bg_normal()\n" ..
        "    local col: uint32 = 0"
      ),
      while_and({lit("col < SB_COLS"), lit("idx < max")}, {
        raw(("      nebula_dense_grid_fill_instance(&instances[idx], 0, col, 32, origin_x, origin_y, %s, %s, hide_bg, hide_bg)"):format(cell_w, cell_h)),
        raw("      idx = idx + 1; col = col + 1"),
      }),
    }, {
      -- active: show search/replace
      raw("    local buf: [256]uint8\n    local slen: int32 = 0"),
      if_then(lit(search_replace), {
        -- replace mode
        raw(
          "      local repl_str: [256]uint8\n" ..
          "      local ri: uint32 = 0"
        ),
        while_and({lit("ri < " .. replace_len), lit("ri < 255")}, {
          raw(("        repl_str[ri] = %s[ri]; ri = ri + 1"):format(replace_buf)),
        }),
        raw(
          "      repl_str[ri] = 0\n" ..
          "      local qstr: [256]uint8\n" ..
          "      local qi: uint32 = 0"
        ),
        while_and({lit("qi < " .. search_len), lit("qi < 255")}, {
          raw(("        qstr[qi] = %s[qi]; qi = qi + 1"):format(search_buf)),
        }),
        raw(
          "      qstr[qi] = 0\n" ..
          ("      slen = snprintf((@cstring)(&buf[0]), 255,\n") ..
          ('        " Replace: %%s -> %%s  [%%d/%%d]",\n') ..
          ("        (@cstring)(&qstr[0]), (@cstring)(&repl_str[0]),\n") ..
          ("        (@int32)(%s + 1), (@int32)(%s))"):format(search_current, search_match_count)
        ),
      }, {
        -- find mode
        raw(
          "      local qstr: [256]uint8\n" ..
          "      local qi: uint32 = 0"
        ),
        while_and({lit("qi < " .. search_len), lit("qi < 255")}, {
          raw(("        qstr[qi] = %s[qi]; qi = qi + 1"):format(search_buf)),
        }),
        raw(
          "      qstr[qi] = 0\n" ..
          ("      slen = snprintf((@cstring)(&buf[0]), 255,\n") ..
          ('        " Find: %%s  [%%d/%%d]",\n') ..
          ("        (@cstring)(&qstr[0]),\n") ..
          ("        (@int32)(%s + 1), (@int32)(%s))"):format(search_current, search_match_count)
        ),
      }),
      -- common post-format
      raw(
        "    if slen < 0 then slen = 0 end\n" ..
        "    if slen > 255 then slen = 255 end\n" ..
        "    local str_len: uint32 = (@uint32)(slen)\n" ..
        "    local label_end: uint32 = 0"
      ),
      if_then(lit(search_replace), {
        raw("      label_end = 10"),
      }, {
        raw("      label_end = 7"),
      }),
      -- fill loop
      raw("    local col: uint32 = 0"),
      while_and({lit("col < SB_COLS"), lit("idx < max")}, {
        raw(
          "      local ch: uint32 = 32\n" ..
          "      local cell_fg = fg\n" ..
          "      if col < str_len then\n" ..
          "        ch = (@uint32)(buf[col])\n" ..
          "        if col < label_end then cell_fg = fg_label end\n" ..
          "      end\n" ..
          "      local cell_bg = bg\n" ..
          ("      local cursor_pos = label_end + %s\n"):format(search_cursor) ..
          "      if col == cursor_pos then\n" ..
          "        cell_bg = nebula_theme_bg_cursor()\n" ..
          "        cell_fg = nebula_theme_fg_cursor()\n" ..
          "      end"
        ),
        raw(("      nebula_dense_grid_fill_instance(&instances[idx], 0, col, ch, origin_x, origin_y, %s, %s, cell_fg, cell_bg)"):format(cell_w, cell_h)),
        raw("      idx = idx + 1; col = col + 1"),
      }),
    }),
    line(lit("$count = idx")),
  }

  return fname, func(fname, PRODUCER_PARAMS, "void", body)
end

-- ---------------------------------------------------------------------------
-- 3.4  edit_area — 编辑区 Producer（语法高亮 + 选区 + 搜索匹配 + 光标行）
-- ---------------------------------------------------------------------------
local function build_edit_area(opts)
  local editor_name = opts.editor_name or opts.comp_name
  local cell_w = tostring(opts.cell_w or 10.0)
  local cell_h = tostring(opts.cell_h or 16.0)
  local cols   = opts.cols or 120
  local rows   = opts.rows or 50
  local fname  = "nebula_fill_edit_area_" .. editor_name
  local layout_x = "app.dense_layout_edit_area_x"
  local layout_y = "app.dense_layout_edit_area_y"

  local highlight_id   = state_ref(opts, "highlight_id",       "_editor_highlight_id")
  local search_active  = state_ref(opts, "search_active",      "_search_active")
  local search_len     = state_ref(opts, "search_len",         "_search_len")
  local search_matches = state_ref(opts, "search_matches",     "_search_matches")
  local search_match_count = state_ref(opts, "search_match_count", "_search_match_count")
  local search_current = state_ref(opts, "search_current",     "_search_current")

  local body = {
    raw('require "nebula_editor"'),
    line(lit("local editor = &app." .. editor_name)),
    line(lit("local mb = &editor.visual.multi_buf")),
    line(lit("local origin_x: float32 = " .. layout_x)),
    line(lit("local origin_y: float32 = " .. layout_y .. " + 4.0")),
    line(lit("local idx: uint32 = 0")),
    line(lit(("local scroll_row: uint32 = (@uint32)(editor.scroll_offset_y / (%s + 2.0))"):format(cell_h))),
    line(lit(("local visible_rows: uint32 = %d"):format(rows))),
    line(lit("local hl_colors: [NEBULA_LINE_BUF_SIZE]uint32")),
    line(lit(("local EDIT_COLS: uint32 = %d"):format(cols))),
    -- selection bounds
    raw(
      "  -- selection bounds\n" ..
      "  local sel_active: boolean = (editor.sel_anchor_row ~= editor.cursor_row) or (editor.sel_anchor_col ~= editor.cursor_col)\n" ..
      "  local sel_sr: uint32 = 0\n" ..
      "  local sel_sc: uint32 = 0\n" ..
      "  local sel_er: uint32 = 0\n" ..
      "  local sel_ec: uint32 = 0"
    ),
    if_then(lit("sel_active"), {
      if_then(lit("editor.sel_anchor_row < editor.cursor_row or (editor.sel_anchor_row == editor.cursor_row and editor.sel_anchor_col < editor.cursor_col)"), {
        raw(
          "      sel_sr = editor.sel_anchor_row; sel_sc = editor.sel_anchor_col\n" ..
          "      sel_er = editor.cursor_row; sel_ec = editor.cursor_col"
        ),
      }, {
        raw(
          "      sel_sr = editor.cursor_row; sel_sc = editor.cursor_col\n" ..
          "      sel_er = editor.sel_anchor_row; sel_ec = editor.sel_anchor_col"
        ),
      }),
    }),
    -- main row loop
    raw("  local row: uint32 = 0"),
    while_lt(lit("row"), lit("visible_rows"), {
      raw(
        "    local buf_row = row + scroll_row\n" ..
        "    local is_cursor_line = (buf_row == editor.cursor_row)\n" ..
        "    local bg = is_cursor_line and nebula_theme_bg_cursor_line() or nebula_theme_bg_normal()"
      ),
      if_then(lit("buf_row < mb.line_count"), {
        -- flatten line + highlight
        raw(
          "      local line = mb:get_line(buf_row)\n" ..
          "      local flat: [1024]uint8\n" ..
          "      local line_len = line:flatten(&flat[0], 1023)\n" ..
          "      -- ★ P0-5 fix: 限制 line_len 上限为 1023，防止 hl_colors 越界\n" ..
          "      if line_len > 1023 then line_len = 1023 end\n" ..
          ("      nebula_highlight_dispatch(%s, &flat[0], (@uint32)(line_len), nebula_theme_fg_normal(), &hl_colors[0])\n"):format(highlight_id) ..
          "      local cursor_byte: int32 = -1\n" ..
          "      if is_cursor_line then cursor_byte = (@int32)(editor.cursor_col) end\n" ..
          "      local byte_i: uint32 = 0\n" ..
          "      local col: uint32 = 0"
        ),
        -- inner col loop (text content)
        while_and({lit("col < EDIT_COLS"), lit("idx < max")}, {
          raw(
            "        local ch: uint32 = 32\n" ..
            "        local fg = nebula_theme_fg_normal()\n" ..
            "        local this_bg = bg\n" ..
            "        if byte_i < line_len then\n" ..
            "          ch = (@uint32)(flat[byte_i])\n" ..
            "          fg = hl_colors[byte_i]\n" ..
            "          if ch >= 0xC0 and ch <= 0xDF then ch = 0x3F; byte_i = byte_i + 1\n" ..
            "          elseif ch >= 0xE0 and ch <= 0xEF then ch = 0x3F; byte_i = byte_i + 2\n" ..
            "          elseif ch >= 0xF0 then ch = 0x3F; byte_i = byte_i + 3 end\n" ..
            "          byte_i = byte_i + 1\n" ..
            "        end"
          ),
          -- selection highlight
          if_then(lit("sel_active"), {
            raw(
              "          local in_sel: boolean = false\n" ..
              "          if buf_row > sel_sr and buf_row < sel_er then\n" ..
              "            in_sel = true\n" ..
              "          elseif buf_row == sel_sr and buf_row == sel_er then\n" ..
              "            local prev_byte = byte_i > 0 and (byte_i - 1) or 0\n" ..
              "            if prev_byte >= sel_sc and prev_byte < sel_ec then in_sel = true end\n" ..
              "          elseif buf_row == sel_sr then\n" ..
              "            local prev_byte = byte_i > 0 and (byte_i - 1) or 0\n" ..
              "            if prev_byte >= sel_sc then in_sel = true end\n" ..
              "          elseif buf_row == sel_er then\n" ..
              "            local prev_byte = byte_i > 0 and (byte_i - 1) or 0\n" ..
              "            if prev_byte < sel_ec then in_sel = true end\n" ..
              "          end\n" ..
              "          if in_sel then this_bg = nebula_theme_bg_selected() end"
            ),
          }),
          -- cursor highlight
          raw(
            "        if cursor_byte >= 0 and (@uint32)(cursor_byte) == byte_i - 1 then\n" ..
            "          this_bg = nebula_theme_bg_cursor(); fg = nebula_theme_fg_cursor()\n" ..
            "        end"
          ),
          -- search match highlight
          if_then(lit(search_active .. " and " .. search_len .. " > 0"), {
            raw(
              "          local prev_b: uint32 = byte_i > 0 and (byte_i - 1) or 0\n" ..
              "          local mi: uint32 = 0"
            ),
            while_lt(lit("mi"), lit(search_match_count), {
              raw(
                ("            local mp = %s[mi]\n"):format(search_matches) ..
                ("            if mp.row == buf_row and prev_b >= mp.col and prev_b < mp.col + %s then\n"):format(search_len) ..
                ("              if mi == %s then\n"):format(search_current) ..
                "                this_bg = nebula_theme_bg_search_current()\n" ..
                "              else\n" ..
                "                this_bg = nebula_theme_bg_search_match()\n" ..
                "              end\n" ..
                "            end\n" ..
                "            mi = mi + 1"
              ),
            }),
          }),
          raw(("        nebula_dense_grid_fill_instance(&instances[idx], row, col, ch, origin_x, origin_y, %s, %s, fg, this_bg)"):format(cell_w, cell_h)),
          raw("        idx = idx + 1; col = col + 1"),
        }),
        -- trailing spaces after text
        while_and({lit("col < EDIT_COLS"), lit("idx < max")}, {
          raw(
            "        local this_bg = bg\n" ..
            "        if sel_active then\n" ..
            "          if buf_row > sel_sr and buf_row < sel_er then\n" ..
            "            this_bg = nebula_theme_bg_selected()\n" ..
            "          elseif buf_row == sel_sr and buf_row ~= sel_er and byte_i >= sel_sc then\n" ..
            "            this_bg = nebula_theme_bg_selected()\n" ..
            "          end\n" ..
            "        end\n" ..
            "        if cursor_byte >= 0 and byte_i == line_len and col == byte_i then this_bg = nebula_theme_bg_cursor() end"
          ),
          raw(("        nebula_dense_grid_fill_instance(&instances[idx], row, col, 32, origin_x, origin_y, %s, %s, nebula_theme_fg_normal(), this_bg)"):format(cell_w, cell_h)),
          raw("        idx = idx + 1; col = col + 1"),
        }),
      }, {
        -- empty row
        raw("      local col: uint32 = 0"),
        while_and({lit("col < EDIT_COLS"), lit("idx < max")}, {
          raw(("        nebula_dense_grid_fill_instance(&instances[idx], row, col, 32, origin_x, origin_y, %s, %s, nebula_theme_fg_normal(), nebula_theme_bg_normal())"):format(cell_w, cell_h)),
          raw("        idx = idx + 1; col = col + 1"),
        }),
      }),
      raw("    row = row + 1"),
    }),
    line(lit("$count = idx")),
  }

  return fname, func(fname, PRODUCER_PARAMS, "void", body)
end

-- ---------------------------------------------------------------------------
-- 3.5  term_grid — 终端网格 Producer
-- ---------------------------------------------------------------------------
local function build_term_grid(opts)
  local comp_name = opts.comp_name
  local cell_w = opts.cell_w or 12.0
  local cell_h = opts.cell_h or 18.0
  local rows   = opts.rows or 24
  local cols   = opts.cols or 80
  local fname  = "nebula_fill_term_grid_" .. comp_name

  local body = {
    line(lit("local tb = _nebula_term_buf")),
    line(lit("if tb == nilptr then $count = 0; return end")),
    line(lit(("local origin_x: float32 = app.dense_layout_%s_x"):format(comp_name))),
    line(lit(("local origin_y: float32 = app.dense_layout_%s_y"):format(comp_name))),
    line(lit(("local cell_w: float32 = %.1f"):format(cell_w))),
    line(lit(("local cell_h: float32 = %.1f"):format(cell_h))),
    line(lit(("local GRID_ROWS: int32 = %d"):format(rows))),
    line(lit(("local GRID_COLS: int32 = %d"):format(cols))),
    line(lit("local idx: uint32 = 0")),
    for_range("row", lit("0"), lit("GRID_ROWS"), {
      for_range("col", lit("0"), lit("GRID_COLS"), {
        raw("      if idx >= max then break end"),
        raw(
          "      local cell = tb:get_cell(row, col)\n" ..
          "      nebula_dense_grid_fill_instance(\n" ..
          "        &instances[idx],\n" ..
          "        (@uint32)(row), (@uint32)(col),\n" ..
          "        cell.codepoint,\n" ..
          "        origin_x, origin_y,\n" ..
          "        cell_w, cell_h,\n" ..
          "        cell.fg, cell.bg)\n" ..
          "      idx = idx + 1"
        ),
      }),
    }),
    -- cursor rendering
    raw(
      "  -- 光标渲染（反色块）\n" ..
      "  if _nebula_term_cursor_visible and\n" ..
      "     tb.cursor_row >= 0 and tb.cursor_row < GRID_ROWS and\n" ..
      "     tb.cursor_col >= 0 and tb.cursor_col < GRID_COLS then\n" ..
      "    local cr = tb.cursor_row\n" ..
      "    local cc = tb.cursor_col\n" ..
      "    local cell = tb:get_cell(cr, cc)\n" ..
      "    local cursor_fg = cell.bg\n" ..
      "    local cursor_bg = cell.fg\n" ..
      "    if cursor_fg == cursor_bg then\n" ..
      "      cursor_fg = TERM_DEFAULT_BG\n" ..
      "      cursor_bg = TERM_DEFAULT_FG\n" ..
      "    end\n" ..
      "    local cursor_idx = (@uint32)(cr) * (@uint32)(GRID_COLS) + (@uint32)(cc)\n" ..
      "    if cursor_idx < idx then\n" ..
      "      nebula_dense_grid_fill_instance(\n" ..
      "        &instances[cursor_idx],\n" ..
      "        (@uint32)(cr), (@uint32)(cc),\n" ..
      "        cell.codepoint,\n" ..
      "        origin_x, origin_y,\n" ..
      "        cell_w, cell_h,\n" ..
      "        cursor_fg, cursor_bg)\n" ..
      "    end\n" ..
      "  end"
    ),
    line(lit("$count = idx")),
  }

  return fname, func(fname, PRODUCER_PARAMS, "void", body)
end

-- =============================================================================
-- Section 4: Public API
-- =============================================================================

-- Registry of builtin spec builders
local NEBULA_BUILTIN_SPECS = {
  line_nums  = build_line_nums,
  status_bar = build_status_bar,
  search_bar = build_search_bar,
  edit_area  = build_edit_area,
  term_grid  = build_term_grid,
}

--- nebula_builtin_emit(name, opts) → fname, source_string
--- Generates Nelua source code for the named builtin with given options.
local function nebula_builtin_emit(name, opts)
  local builder = NEBULA_BUILTIN_SPECS[name]
  if not builder then
    error(("[builtin_factory] unknown builtin: %q"):format(tostring(name)))
  end
  local fname, ast_node = builder(opts)
  local source = emit(ast_node, 0)
  return fname, source
end

--- nebula_register_builtin_spec(name, builder_fn)
--- Register a custom builtin spec builder.
--- builder_fn(opts) → fname, ast_node
local function nebula_register_builtin_spec(name, builder_fn)
  assert(type(name) == "string", "builtin name must be string")
  assert(type(builder_fn) == "function", "builder must be function")
  assert(not NEBULA_BUILTIN_SPECS[name],
    ("[builtin_factory] builtin %q already registered"):format(name))
  NEBULA_BUILTIN_SPECS[name] = builder_fn
end

-- Export public API to global scope (for use by nebula_builtins.nelua preprocessor)
_G.NEBULA_BUILTIN_SPECS = NEBULA_BUILTIN_SPECS
_G.nebula_builtin_emit = nebula_builtin_emit
_G.nebula_register_builtin_spec = nebula_register_builtin_spec
_G.nebula_builtin_ast_emit = emit

return VERSION
