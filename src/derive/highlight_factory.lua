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

-- ★ P2-8: 加载编译期配置常量（高亮颜色）
local _cfg = require("nebula_config")

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

-- =============================================================================
-- nebula_highlight_select(langs)
--
-- 生成运行时分发函数 nebula_highlight_dispatch()，根据 _editor_highlight_id
-- 调用对应语言的扫描函数。同时生成 nebula_highlight_detect_ext() 根据文件扩展名
-- 返回语言 ID。
--
-- 参数：
--   langs : array of { name = string, exts = {string...} }
--     name: 已注册的高亮规则名称（必须已调用 nebula_derive_highlighter）
--     exts: 文件扩展名列表（不含点号，如 {"lua", "luau"}）
--
-- 生成的函数：
--   global function nebula_highlight_dispatch(
--     id: uint32, line: *[0]uint8, line_len: uint32,
--     default_fg: uint32, out_colors: *[0]uint32): void
--
--   global function nebula_highlight_detect_ext(
--     path: *[0]uint8, path_len: uint32): uint32
--     返回: 语言 ID（0 = 无高亮，1 = 第一种语言，...）
-- =============================================================================
function nebula_highlight_select(langs)
  assert(type(langs) == "table" and #langs > 0,
    "nebula_highlight_select: langs must be non-empty array")

  -- 验证所有语言已注册
  for i, lang in ipairs(langs) do
    assert(type(lang.name) == "string",
      ("nebula_highlight_select: langs[%d].name must be string"):format(i))
    assert(nebula_highlight_registry[lang.name],
      ("nebula_highlight_select: no rules registered for '%s'"):format(lang.name))
    assert(type(lang.exts) == "table" and #lang.exts > 0,
      ("nebula_highlight_select: langs[%d].exts must be non-empty array"):format(i))
  end

  local lines = {}

  -- ---- 生成 dispatch 函数 ----
  table.insert(lines, "global function nebula_highlight_dispatch(")
  table.insert(lines, "  id: uint32, line: *[0]uint8, line_len: uint32,")
  table.insert(lines, "  default_fg: uint32, out_colors: *[0]uint32")
  table.insert(lines, "): void")
  for i, lang in ipairs(langs) do
    local fn = "nebula_highlight_scan_" .. lang.name
    if i == 1 then
      table.insert(lines, ("  if id == %d then"):format(i))
    else
      table.insert(lines, ("  elseif id == %d then"):format(i))
    end
    table.insert(lines, ("    %s(line, line_len, default_fg, out_colors)"):format(fn))
  end
  table.insert(lines, "  else")
  -- id == 0 或未知：用默认颜色填充
  table.insert(lines, "    local _i: uint32 = 0")
  table.insert(lines, "    while _i < line_len do")
  table.insert(lines, "      out_colors[_i] = default_fg")
  table.insert(lines, "      _i = _i + 1")
  table.insert(lines, "    end")
  table.insert(lines, "  end")
  table.insert(lines, "end")

  -- ---- 生成 detect_ext 函数 ----
  -- 策略：从 path 末尾找最后一个 '.' 后的子串，逐字节比较
  table.insert(lines, "")
  table.insert(lines, "global function nebula_highlight_detect_ext(")
  table.insert(lines, "  path: *[0]uint8, path_len: uint32")
  table.insert(lines, "): uint32")
  table.insert(lines, "  -- find last '.'")
  table.insert(lines, "  local dot_pos: int32 = -1")
  table.insert(lines, "  local _pi: int32 = (@int32)(path_len) - 1")
  table.insert(lines, "  while _pi >= 0 do")
  table.insert(lines, "    if path[(@uint32)(_pi)] == 46 then dot_pos = _pi; break end")
  table.insert(lines, "    _pi = _pi - 1")
  table.insert(lines, "  end")
  table.insert(lines, "  if dot_pos < 0 then return 0 end")
  table.insert(lines, "  local ext_start: uint32 = (@uint32)(dot_pos + 1)")
  table.insert(lines, "  local ext_len: uint32 = path_len - ext_start")

  -- 为每种语言的每个扩展名生成匹配分支
  local first = true
  for i, lang in ipairs(langs) do
    for _, ext in ipairs(lang.exts) do
      local prefix = first and "  if " or "  elseif "
      first = false
      -- 长度检查 + 逐字节匹配
      local cond_parts = { ("ext_len == %d"):format(#ext) }
      for j = 1, #ext do
        table.insert(cond_parts,
          ("path[ext_start + %d] == %d"):format(j - 1, string.byte(ext, j)))
      end
      table.insert(lines, ("%s%s then return %d"):format(prefix, table.concat(cond_parts, " and "), i))
    end
  end
  table.insert(lines, "  end")
  table.insert(lines, "  return 0")
  table.insert(lines, "end")

  local source = table.concat(lines, "\n")
  local stmts = aster.parse(source, "<highlight_select>")
  for _, s in ipairs(stmts) do
    inject_statement(s)
  end

  -- 编译期日志
  local ext_list = {}
  for _, lang in ipairs(langs) do
    table.insert(ext_list, lang.name .. "={" .. table.concat(lang.exts, ",") .. "}")
  end
  print(("[highlight] select: %d languages [%s]"):format(#langs, table.concat(ext_list, ", ")))
end

-- =============================================================================
-- ★ Phase 4.9 L1: nebula_highlight_init(name, spec)
--
-- Sugar: 合并 nebula_highlight_rules(name, spec) + nebula_derive_highlighter(name)
-- 为单个语言完成规则注册 + 扫描函数生成。
-- =============================================================================
function nebula_highlight_init(name, spec)
  nebula_highlight_rules(name, spec)
  nebula_derive_highlighter(name)
end

-- =============================================================================
-- ★ Phase 4.9 L1: nebula_highlight_pack(langs)
--
-- Sugar: 一次性注册多种语言的高亮规则 + 生成扫描函数 + 生成分发/检测函数。
--
-- 用法（替代 ~130 行手写）：
--   ## nebula_highlight_pack({
--     { name="nelua", exts={"nelua"}, keywords={...}, line_comment="--", ... },
--     { name="lua",   exts={"lua","luau"}, keywords={...}, ... },
--   })
--
-- 每个条目的字段：
--   name              : string    — 语言名（必须）
--   exts              : {string}  — 扩展名列表（必须）
--   keywords          : array     — 关键字分组（同 nebula_highlight_rules）
--   line_comment      : string?   — 行注释前缀
--   line_comment_color: number?   — 注释颜色
--   string_color      : number?   — 字符串颜色
--   number_color      : number?   — 数字颜色
-- =============================================================================
function nebula_highlight_pack(langs)
  assert(type(langs) == "table" and #langs > 0,
    "nebula_highlight_pack: langs must be non-empty array")

  local select_list = {}

  for i, lang in ipairs(langs) do
    assert(type(lang.name) == "string" and #lang.name > 0,
      ("nebula_highlight_pack: langs[%d].name must be non-empty string"):format(i))
    assert(type(lang.exts) == "table" and #lang.exts > 0,
      ("nebula_highlight_pack: langs[%d].exts must be non-empty array"):format(i))

    -- 提取 rules spec（排除 name 和 exts 字段）
    local spec = {}
    for k, v in pairs(lang) do
      if k ~= "name" and k ~= "exts" then
        spec[k] = v
      end
    end

    -- 注册规则 + 生成扫描函数
    nebula_highlight_init(lang.name, spec)

    -- 收集 select 列表
    table.insert(select_list, { name = lang.name, exts = lang.exts })
  end

  -- 生成运行时分发 + 扩展名检测
  nebula_highlight_select(select_list)

  print(("[highlight] pack: %d languages registered + derived + selected"):format(#langs))
end

-- =============================================================================
-- ★ Phase 4.9.1: NEBULA_BUILTIN_LANGS + nebula_highlight_builtins
--
-- 内置语言包：6 种常用语言的高亮规则数据表。
-- nebula_highlight_builtins({"nelua", "c", "python"}) 替代 ~35 行手写 pack 调用。
--
-- 逃逸路径：用户仍可用 nebula_highlight_pack 或 nebula_highlight_rules 覆盖。
-- =============================================================================

local NEBULA_BUILTIN_LANGS = {
  nelua = {
    exts = {"nelua"},
    keywords = {
      {words={"if","else","elseif","then","end","for","while","do",
              "repeat","until","return","break","goto","in","switch",
              "case","continue","defer"},                              color=_cfg.HL_COLOR_KEYWORD_CONTROL},
      {words={"local","global","function","require","record","enum",
              "union","type"},                                         color=_cfg.HL_COLOR_KEYWORD_DECL},
      {words={"true","false","nil","nilptr"},                          color=_cfg.HL_COLOR_KEYWORD_LITERAL},
      {words={"int8","int16","int32","int64","uint8","uint16","uint32",
              "uint64","float32","float64","boolean","cstring","cint",
              "csize","pointer","void","auto","byte","isize","usize"}, color=_cfg.HL_COLOR_KEYWORD_TYPE},
    },
    line_comment       = "--",
    line_comment_color = _cfg.HL_COLOR_COMMENT,
    string_color       = _cfg.HL_COLOR_STRING,
    number_color       = _cfg.HL_COLOR_NUMBER,
  },
  lua = {
    exts = {"lua", "luau"},
    keywords = {
      {words={"if","else","elseif","then","end","for","while","do",
              "repeat","until","return","break","goto","in"},          color=_cfg.HL_COLOR_KEYWORD_CONTROL},
      {words={"local","function","require","not","and","or"},          color=_cfg.HL_COLOR_KEYWORD_DECL},
      {words={"true","false","nil"},                                   color=_cfg.HL_COLOR_KEYWORD_LITERAL},
    },
    line_comment       = "--",
    line_comment_color = _cfg.HL_COLOR_COMMENT,
    string_color       = _cfg.HL_COLOR_STRING,
    number_color       = _cfg.HL_COLOR_NUMBER,
  },
  c = {
    exts = {"c", "h", "cpp", "hpp", "cc", "cxx"},
    keywords = {
      {words={"if","else","for","while","do","switch","case","default",
              "break","continue","return","goto"},                     color=_cfg.HL_COLOR_KEYWORD_CONTROL},
      {words={"struct","enum","union","typedef","extern","static",
              "const","volatile","inline","register","sizeof","include",
              "define","ifdef","ifndef","endif","pragma"},              color=_cfg.HL_COLOR_KEYWORD_DECL},
      {words={"int","char","float","double","void","long","short",
              "unsigned","signed","size_t","uint8_t","uint16_t",
              "uint32_t","uint64_t","int8_t","int16_t","int32_t",
              "int64_t","bool","NULL"},                                 color=_cfg.HL_COLOR_KEYWORD_LITERAL},
    },
    line_comment       = "//",
    line_comment_color = _cfg.HL_COLOR_COMMENT,
    string_color       = _cfg.HL_COLOR_STRING,
    number_color       = _cfg.HL_COLOR_NUMBER,
  },
  python = {
    exts = {"py", "pyw"},
    keywords = {
      {words={"if","elif","else","for","while","break","continue",
              "return","pass","raise","try","except","finally","with",
              "as","yield","assert"},                                  color=_cfg.HL_COLOR_KEYWORD_CONTROL},
      {words={"def","class","import","from","lambda","global",
              "nonlocal","del","and","or","not","is","in"},            color=_cfg.HL_COLOR_KEYWORD_DECL},
      {words={"True","False","None","self","cls"},                     color=_cfg.HL_COLOR_KEYWORD_LITERAL},
      {words={"int","float","str","bool","list","dict","tuple","set",
              "bytes","range","print","len","type","isinstance","super",
              "property","staticmethod","classmethod","enumerate",
              "zip","map","filter"},                                   color=_cfg.HL_COLOR_KEYWORD_TYPE},
    },
    line_comment       = "#",
    line_comment_color = _cfg.HL_COLOR_COMMENT,
    string_color       = _cfg.HL_COLOR_STRING,
    number_color       = _cfg.HL_COLOR_NUMBER,
  },
  json = {
    exts = {"json", "jsonc"},
    keywords = {
      {words={"true","false","null"},                                  color=_cfg.HL_COLOR_KEYWORD_LITERAL},
    },
    string_color = _cfg.HL_COLOR_STRING,
    number_color = _cfg.HL_COLOR_NUMBER,
  },
  markdown = {
    exts = {"md", "mdx", "markdown"},
    keywords = {
      {words={"TODO","FIXME","NOTE","HACK","XXX"},                    color=_cfg.HL_COLOR_MARKDOWN_MARKER},
    },
    line_comment       = "#",
    line_comment_color = _cfg.HL_COLOR_KEYWORD_DECL,
    string_color       = _cfg.HL_COLOR_STRING,
    number_color       = _cfg.HL_COLOR_NUMBER,
  },
}

function nebula_highlight_builtins(lang_names)
  assert(type(lang_names) == "table" and #lang_names > 0,
    "nebula_highlight_builtins: lang_names must be non-empty array")

  local pack = {}
  for _, name in ipairs(lang_names) do
    local def = NEBULA_BUILTIN_LANGS[name]
    if not def then
      error("[nebula_highlight_builtins] unknown language: " .. name ..
            "\n  available: nelua, lua, c, python, json, markdown")
    end
    local entry = {}
    for k, v in pairs(def) do entry[k] = v end
    entry.name = name
    table.insert(pack, entry)
  end
  nebula_highlight_pack(pack)
end

return VERSION
