-- =============================================================================
-- highlight_factory.lua
-- Nebula GUI Compiler — Phase 4.7-S4
--
-- 编译期语法高亮规则注册 + 运行时扫描函数生成。
--
-- 设计哲学（公理 A — 阶段封闭性）：
--   · S1 阶段：nebula_highlight_rules() 注册关键字列表 + 颜色映射
--   · S1 阶段：nebula_derive_highlighter() 生成 Nelua 扫描函数源码
--   · S2 阶段：生成的函数在运行时逐行扫描文本，输出 per-byte fg_color
--   · 后一阶段不执行前一阶段的操作：规则解析仅在 S1，运行时仅做线性扫描
--
-- 支持的 Token 类型：
--   1. 关键字分组着色（多组关键字，各组独立颜色）
--   2. 行注释（如 --）
--   3. 字符串字面量（单引号 / 双引号）
--   4. 数字字面量（整数 + 浮点 + 0x 十六进制）
--
-- 生成的函数签名：
--   global function nebula_highlight_scan_<name>(
--     line: *[0]uint8, line_len: uint32, default_fg: uint32,
--     out_colors: *[0]uint32
--   ): void
--
-- Producer 用法：
--   在填充 DenseCharInstance 之前，对每行调用扫描函数获取 per-byte 颜色，
--   然后用 out_colors[byte_i] 替代 _fg_normal() 作为 fg_packed 参数。
-- =============================================================================

local VERSION = "nebula_highlight_factory_v0.1_phase4.7-s4"

-- 全局注册表：存放所有 nebula_highlight_rules 注册的规则
nebula_highlight_registry = nebula_highlight_registry or {}

-- =============================================================================
-- nebula_highlight_rules(name, spec)
--
-- 在 S1 编译期注册语法高亮规则。
--
-- 参数：
--   name : string — 规则集名称（如 "nelua", "lua", "json"）
--   spec : table  — 规则定义：
--     keywords            : array of { words = {string...}, color = uint32_hex }
--     line_comment        : string    — 行注释前缀（如 "--"）
--     line_comment_color  : uint32    — 注释颜色（RGBA8 packed）
--     string_color        : uint32    — 字符串字面量颜色
--     number_color        : uint32    — 数字字面量颜色
-- =============================================================================
function nebula_highlight_rules(name, spec)
  assert(type(name) == "string" and #name > 0,
    "nebula_highlight_rules: name must be non-empty string")
  assert(type(spec) == "table",
    "nebula_highlight_rules: spec must be a table")

  -- 验证 keywords 格式
  if spec.keywords then
    assert(type(spec.keywords) == "table",
      "nebula_highlight_rules: keywords must be array of {words={...}, color=N}")
    for i, group in ipairs(spec.keywords) do
      assert(type(group.words) == "table" and #group.words > 0,
        ("nebula_highlight_rules: keywords[%d].words must be non-empty array"):format(i))
      assert(type(group.color) == "number",
        ("nebula_highlight_rules: keywords[%d].color must be a number"):format(i))
    end
  end

  -- 验证行注释
  if spec.line_comment then
    assert(type(spec.line_comment) == "string" and #spec.line_comment > 0,
      "nebula_highlight_rules: line_comment must be non-empty string")
    assert(type(spec.line_comment_color) == "number",
      "nebula_highlight_rules: line_comment_color required when line_comment is set")
  end

  -- 验证字符串颜色
  if spec.string_color then
    assert(type(spec.string_color) == "number",
      "nebula_highlight_rules: string_color must be a number")
  end

  -- 验证数字颜色
  if spec.number_color then
    assert(type(spec.number_color) == "number",
      "nebula_highlight_rules: number_color must be a number")
  end

  nebula_highlight_registry[name] = spec
  print(("[highlight] registered rules: '%s' (%d keyword groups)"):format(
    name, spec.keywords and #spec.keywords or 0))
end

-- =============================================================================
-- 内部辅助：生成关键字匹配代码
-- =============================================================================

-- 判断字符是否为 word 字符（字母/数字/下划线）的 Nelua 表达式
local function _gen_is_word_char(var)
  return ("((%s >= 65 and %s <= 90) or (%s >= 97 and %s <= 122) or (%s >= 48 and %s <= 57) or %s == 95)"):format(
    var, var, var, var, var, var, var)
end

-- 为单个关键字生成匹配代码段
-- 返回: Nelua if 条件表达式（检查从 pos 开始是否匹配该关键字 + 后跟非 word 字符）
local function _gen_keyword_match(keyword)
  local bytes = { string.byte(keyword, 1, #keyword) }
  local conditions = {}
  -- 长度检查
  table.insert(conditions, ("_pos + %d <= line_len"):format(#keyword))
  -- 逐字节匹配
  for j, b in ipairs(bytes) do
    table.insert(conditions, ("line[_pos + %d] == %d"):format(j - 1, b))
  end
  -- 后跟非 word 字符（或行尾）
  table.insert(conditions,
    ("(_pos + %d == line_len or not %s)"):format(
      #keyword,
      _gen_is_word_char(("(@uint32)(line[_pos + %d])"):format(#keyword))))
  return table.concat(conditions, " and ")
end

-- =============================================================================
-- nebula_derive_highlighter(name)
--
-- 生成 Nelua 运行时扫描函数源码。
-- 调用方式：## nebula_derive_highlighter("nelua")
-- 效果：在调用点注入 global function nebula_highlight_scan_<name>(...)
--
-- 返回：Nelua 源代码字符串（由 aster.parse + inject_statement 注入）
-- =============================================================================
function nebula_derive_highlighter(name)
  local spec = nebula_highlight_registry[name]
  assert(spec, "nebula_derive_highlighter: no rules registered for '" .. name .. "'")

  local fn_name = "nebula_highlight_scan_" .. name
  local lines = {}

  -- 函数头
  table.insert(lines, ("global function %s("):format(fn_name))
  table.insert(lines, "  line: *[0]uint8, line_len: uint32, default_fg: uint32,")
  table.insert(lines, "  out_colors: *[0]uint32")
  table.insert(lines, "): void")

  -- 初始化所有字节为默认颜色
  table.insert(lines, "  do")
  table.insert(lines, "    local _i: uint32 = 0")
  table.insert(lines, "    while _i < line_len do")
  table.insert(lines, "      out_colors[_i] = default_fg")
  table.insert(lines, "      _i = _i + 1")
  table.insert(lines, "    end")
  table.insert(lines, "  end")
  table.insert(lines, "  if line_len == 0 then return end")

  -- 主扫描循环
  table.insert(lines, "  local _pos: uint32 = 0")
  table.insert(lines, "  while _pos < line_len do")
  table.insert(lines, "    local _ch: uint32 = (@uint32)(line[_pos])")

  -- ---- 行注释检测 ----
  if spec.line_comment then
    local prefix = spec.line_comment
    local prefix_bytes = { string.byte(prefix, 1, #prefix) }
    local cond_parts = { ("_pos + %d <= line_len"):format(#prefix) }
    for j, b in ipairs(prefix_bytes) do
      table.insert(cond_parts, ("line[_pos + %d] == %d"):format(j - 1, b))
    end
    table.insert(lines, ("    -- line comment: %s"):format(prefix))
    table.insert(lines, ("    if %s then"):format(table.concat(cond_parts, " and ")))
    table.insert(lines, ("      while _pos < line_len do"))
    table.insert(lines, ("        out_colors[_pos] = %d"):format(spec.line_comment_color))
    table.insert(lines, ("        _pos = _pos + 1"))
    table.insert(lines, ("      end"))
    table.insert(lines, ("      return"))  -- 行注释到行尾，直接结束
    table.insert(lines, ("    end"))
  end

  -- ---- 字符串字面量检测 ----
  if spec.string_color then
    -- 双引号字符串
    table.insert(lines, "    -- string literal (double quote)")
    table.insert(lines, "    if _ch == 34 then")  -- '"' = 34
    table.insert(lines, ("      out_colors[_pos] = %d"):format(spec.string_color))
    table.insert(lines, "      _pos = _pos + 1")
    table.insert(lines, "      while _pos < line_len do")
    table.insert(lines, "        local _sc: uint32 = (@uint32)(line[_pos])")
    table.insert(lines, ("        out_colors[_pos] = %d"):format(spec.string_color))
    table.insert(lines, "        if _sc == 92 then")  -- '\\' = 92 (escape)
    table.insert(lines, "          _pos = _pos + 1")
    table.insert(lines, "          if _pos < line_len then")
    table.insert(lines, ("            out_colors[_pos] = %d"):format(spec.string_color))
    table.insert(lines, "          end")
    table.insert(lines, "        elseif _sc == 34 then")  -- closing '"'
    table.insert(lines, "          _pos = _pos + 1")
    table.insert(lines, "          goto _hl_continue")
    table.insert(lines, "        end")
    table.insert(lines, "        _pos = _pos + 1")
    table.insert(lines, "      end")
    table.insert(lines, "      goto _hl_continue")
    table.insert(lines, "    end")

    -- 单引号字符串
    table.insert(lines, "    -- string literal (single quote)")
    table.insert(lines, "    if _ch == 39 then")  -- "'" = 39
    table.insert(lines, ("      out_colors[_pos] = %d"):format(spec.string_color))
    table.insert(lines, "      _pos = _pos + 1")
    table.insert(lines, "      while _pos < line_len do")
    table.insert(lines, "        local _sc: uint32 = (@uint32)(line[_pos])")
    table.insert(lines, ("        out_colors[_pos] = %d"):format(spec.string_color))
    table.insert(lines, "        if _sc == 92 then")
    table.insert(lines, "          _pos = _pos + 1")
    table.insert(lines, "          if _pos < line_len then")
    table.insert(lines, ("            out_colors[_pos] = %d"):format(spec.string_color))
    table.insert(lines, "          end")
    table.insert(lines, "        elseif _sc == 39 then")
    table.insert(lines, "          _pos = _pos + 1")
    table.insert(lines, "          goto _hl_continue")
    table.insert(lines, "        end")
    table.insert(lines, "        _pos = _pos + 1")
    table.insert(lines, "      end")
    table.insert(lines, "      goto _hl_continue")
    table.insert(lines, "    end")
  end

  -- ---- 数字字面量检测 ----
  if spec.number_color then
    -- 数字：当前位置是数字字符且前一个位置是非 word 字符（或行首）
    table.insert(lines, "    -- number literal")
    table.insert(lines, "    if _ch >= 48 and _ch <= 57 then")
    -- 检查前面是否是 word boundary
    table.insert(lines, ("      if _pos == 0 or not %s then"):format(
      _gen_is_word_char("(@uint32)(line[_pos - 1])")))
    -- 扫描整个数字（包括 0x 前缀、小数点、下划线分隔符）
    table.insert(lines, "        while _pos < line_len do")
    table.insert(lines, "          local _nc: uint32 = (@uint32)(line[_pos])")
    table.insert(lines, "          if (_nc >= 48 and _nc <= 57) or (_nc >= 65 and _nc <= 70) or (_nc >= 97 and _nc <= 102) or _nc == 120 or _nc == 88 or _nc == 46 or _nc == 95 then")
    table.insert(lines, ("            out_colors[_pos] = %d"):format(spec.number_color))
    table.insert(lines, "            _pos = _pos + 1")
    table.insert(lines, "          else")
    table.insert(lines, "            break")
    table.insert(lines, "          end")
    table.insert(lines, "        end")
    table.insert(lines, "        goto _hl_continue")
    table.insert(lines, "      end")
    table.insert(lines, "    end")
  end

  -- ---- 关键字匹配 ----
  if spec.keywords and #spec.keywords > 0 then
    -- 先检查是否在 word boundary（前一个字符不是 word char）
    table.insert(lines, "    -- keyword matching (word boundary check)")
    table.insert(lines, ("    if (_pos == 0 or not %s) and %s then"):format(
      _gen_is_word_char("(@uint32)(line[_pos - 1])"),
      _gen_is_word_char("_ch")))

    local first_group = true
    for gi, group in ipairs(spec.keywords) do
      for ki, keyword in ipairs(group.words) do
        local cond = _gen_keyword_match(keyword)
        local prefix = (first_group and ki == 1) and "      if " or "      elseif "
        first_group = false

        table.insert(lines, ("%s%s then"):format(prefix, cond))
        -- 着色整个关键字
        table.insert(lines, "        do")
        table.insert(lines, ("          local _ke: uint32 = _pos + %d"):format(#keyword))
        table.insert(lines, "          while _pos < _ke do")
        table.insert(lines, ("            out_colors[_pos] = %d"):format(group.color))
        table.insert(lines, "            _pos = _pos + 1")
        table.insert(lines, "          end")
        table.insert(lines, "        end")
        table.insert(lines, "        goto _hl_continue")
      end
    end
    table.insert(lines, "      end")  -- close if-elseif chain
    table.insert(lines, "    end")    -- close word boundary check
  end

  -- 默认：跳过当前字节
  table.insert(lines, "    _pos = _pos + 1")
  table.insert(lines, "    ::_hl_continue::")
  table.insert(lines, "  end")  -- while
  table.insert(lines, "end")    -- function

  local source = table.concat(lines, "\n")

  -- 注入到调用点
  local stmts = aster.parse(source, "<highlight:" .. name .. ">")
  for _, s in ipairs(stmts) do
    inject_statement(s)
  end

  -- 编译期日志
  local kw_count = 0
  if spec.keywords then
    for _, g in ipairs(spec.keywords) do kw_count = kw_count + #g.words end
  end
  print(("[highlight] derived scanner: %s (%d keywords, comment=%s, string=%s, number=%s)"):format(
    fn_name, kw_count,
    spec.line_comment and "yes" or "no",
    spec.string_color and "yes" or "no",
    spec.number_color and "yes" or "no"))
end

return VERSION
