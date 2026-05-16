-- =============================================================================
-- derive/mutation_ast.lua — Nebula GUI Compiler Phase 5.0 S1b
--
-- mutation / compute 受限语法解析器
--
-- 将 mutation/compute 字符串解析为 AST，支持：
--   · 词法分析（tokenizer）
--   · 递归下降语法分析（recursive descent parser）
--   · read_set / write_set 提取
--   · emit — AST 转回 Nelua 代码
--   · 白名单函数校验
--   · 错误定位（行号/列号）
--
-- AST 节点类型：
--   Expr = Literal | BinOp | UnaryOp | FieldAccess | Call | IfExpr
--   Stmt = Assign
-- =============================================================================

local MutationAST = {}

-- 白名单函数
local WHITELIST_FUNCTIONS = {
  ["snprintf"]   = true,
  ["math.floor"] = true,
  ["math.ceil"]  = true,
  ["math.max"]   = true,
  ["math.min"]   = true,
}

-- 禁止的关键字
local FORBIDDEN_KEYWORDS = {
  ["for"] = true, ["while"] = true, ["repeat"] = true,
  ["until"] = true, ["do"] = true, ["end"] = true,
  ["function"] = true, ["return"] = true, ["local"] = true,
  ["break"] = true, ["goto"] = true, ["in"] = true,
}

-- =====================================================================
-- 1. Tokenizer
-- =====================================================================

local TOKEN = {
  IDENT   = "IDENT",
  NUMBER  = "NUMBER",
  STRING  = "STRING",
  BOOL    = "BOOL",
  OP      = "OP",
  DOT     = "DOT",
  EQ      = "EQ",       -- =
  EQEQ    = "EQEQ",     -- ==
  NEQ     = "NEQ",       -- ~=
  LT      = "LT",
  GT      = "GT",
  LTE     = "LTE",
  GTE     = "GTE",
  AND     = "AND",
  OR      = "OR",
  NOT     = "NOT",
  IF      = "IF",
  THEN    = "THEN",
  ELSE    = "ELSE",
  SELF    = "SELF",
  LPAREN  = "LPAREN",
  RPAREN  = "RPAREN",
  COMMA   = "COMMA",
  SEMI    = "SEMI",
  NEWLINE = "NEWLINE",
  EOF     = "EOF",
}

MutationAST.TOKEN = TOKEN

--- Tokenize source string into token list.
--- @param source string
--- @return table tokens [{type, value, line, col}]
--- @return table|nil error {message, line, col}
function MutationAST.tokenize(source)
  local tokens = {}
  local pos = 1
  local line = 1
  local col = 1
  local len = #source

  local function peek(offset)
    return source:sub(pos + (offset or 0), pos + (offset or 0))
  end

  local function advance(n)
    n = n or 1
    for i = 1, n do
      if source:sub(pos, pos) == "\n" then
        line = line + 1
        col = 1
      else
        col = col + 1
      end
      pos = pos + 1
    end
  end

  local function add(type, value, start_line, start_col)
    tokens[#tokens + 1] = {
      type = type,
      value = value,
      line = start_line or line,
      col = start_col or col,
    }
  end

  while pos <= len do
    local ch = source:sub(pos, pos)

    -- skip whitespace (not newline)
    if ch == " " or ch == "\t" or ch == "\r" then
      advance()

    -- newline as statement separator
    elseif ch == "\n" then
      add(TOKEN.NEWLINE, "\n")
      advance()

    -- semicolon as statement separator
    elseif ch == ";" then
      add(TOKEN.SEMI, ";")
      advance()

    -- string literal (double-quoted)
    elseif ch == '"' then
      local sl, sc = line, col
      advance() -- skip opening quote
      local buf = {}
      while pos <= len and source:sub(pos, pos) ~= '"' do
        if source:sub(pos, pos) == "\\" then
          buf[#buf + 1] = source:sub(pos, pos + 1)
          advance(2)
        else
          buf[#buf + 1] = source:sub(pos, pos)
          advance()
        end
      end
      if pos > len then
        return nil, { message = "unterminated string literal", line = sl, col = sc }
      end
      advance() -- skip closing quote
      add(TOKEN.STRING, '"' .. table.concat(buf) .. '"', sl, sc)

    -- number
    elseif ch:match("[0-9]") or (ch == "-" and peek(1):match("[0-9]") and
           (#tokens == 0 or tokens[#tokens].type == TOKEN.OP or
            tokens[#tokens].type == TOKEN.EQ or tokens[#tokens].type == TOKEN.LPAREN or
            tokens[#tokens].type == TOKEN.COMMA)) then
      local sl, sc = line, col
      local start = pos
      if ch == "-" then advance() end
      while pos <= len and source:sub(pos, pos):match("[0-9]") do advance() end
      if pos <= len and source:sub(pos, pos) == "." and peek(1):match("[0-9]") then
        advance() -- skip dot
        while pos <= len and source:sub(pos, pos):match("[0-9]") do advance() end
      end
      add(TOKEN.NUMBER, source:sub(start, pos - 1), sl, sc)

    -- operators and punctuation
    elseif ch == "(" then add(TOKEN.LPAREN, "("); advance()
    elseif ch == ")" then add(TOKEN.RPAREN, ")"); advance()
    elseif ch == "," then add(TOKEN.COMMA, ","); advance()
    elseif ch == "." then add(TOKEN.DOT, "."); advance()
    elseif ch == "+" then add(TOKEN.OP, "+"); advance()
    elseif ch == "*" then add(TOKEN.OP, "*"); advance()
    elseif ch == "/" then add(TOKEN.OP, "/"); advance()
    elseif ch == "%" then add(TOKEN.OP, "%"); advance()
    elseif ch == "-" then add(TOKEN.OP, "-"); advance()
    elseif ch == "~" then
      if peek(1) == "=" then
        add(TOKEN.NEQ, "~="); advance(2)
      else
        return nil, { message = "unexpected character '~'", line = line, col = col }
      end
    elseif ch == "=" then
      if peek(1) == "=" then
        add(TOKEN.EQEQ, "=="); advance(2)
      else
        add(TOKEN.EQ, "="); advance()
      end
    elseif ch == "<" then
      if peek(1) == "=" then
        add(TOKEN.LTE, "<="); advance(2)
      else
        add(TOKEN.LT, "<"); advance()
      end
    elseif ch == ">" then
      if peek(1) == "=" then
        add(TOKEN.GTE, ">="); advance(2)
      else
        add(TOKEN.GT, ">"); advance()
      end

    -- identifiers and keywords
    elseif ch:match("[a-zA-Z_]") then
      local sl, sc = line, col
      local start = pos
      while pos <= len and source:sub(pos, pos):match("[a-zA-Z0-9_]") do advance() end
      local word = source:sub(start, pos - 1)

      if word == "self" then
        add(TOKEN.SELF, "self", sl, sc)
      elseif word == "and" then
        add(TOKEN.AND, "and", sl, sc)
      elseif word == "or" then
        add(TOKEN.OR, "or", sl, sc)
      elseif word == "not" then
        add(TOKEN.NOT, "not", sl, sc)
      elseif word == "if" then
        add(TOKEN.IF, "if", sl, sc)
      elseif word == "then" then
        add(TOKEN.THEN, "then", sl, sc)
      elseif word == "else" then
        add(TOKEN.ELSE, "else", sl, sc)
      elseif word == "true" or word == "false" then
        add(TOKEN.BOOL, word, sl, sc)
      elseif FORBIDDEN_KEYWORDS[word] then
        return nil, {
          message = ("mutation uses disallowed '%s' keyword"):format(word),
          line = sl, col = sc,
        }
      else
        add(TOKEN.IDENT, word, sl, sc)
      end

    else
      return nil, {
        message = ("unexpected character '%s'"):format(ch),
        line = line, col = col,
      }
    end
  end

  add(TOKEN.EOF, "", line, col)
  return tokens, nil
end

-- =====================================================================
-- 2. Parser (recursive descent)
-- =====================================================================

local Parser = {}
Parser.__index = Parser

function Parser.new(tokens)
  return setmetatable({
    tokens = tokens,
    pos    = 1,
    errors = {},
  }, Parser)
end

function Parser:peek()
  return self.tokens[self.pos]
end

function Parser:advance()
  local tok = self.tokens[self.pos]
  self.pos = self.pos + 1
  return tok
end

function Parser:expect(type, value)
  local tok = self:peek()
  if tok.type ~= type or (value and tok.value ~= value) then
    return nil, {
      message = ("expected %s%s, got %s '%s'"):format(
        type, value and (" '" .. value .. "'") or "",
        tok.type, tok.value),
      line = tok.line,
      col = tok.col,
    }
  end
  return self:advance()
end

function Parser:match(type, value)
  local tok = self:peek()
  if tok.type == type and (not value or tok.value == value) then
    return self:advance()
  end
  return nil
end

function Parser:skip_separators()
  while self:peek().type == TOKEN.NEWLINE or self:peek().type == TOKEN.SEMI do
    self:advance()
  end
end

-- Grammar:
--   program    = { statement separator }
--   statement  = assignment
--   assignment = "self" "." IDENT "=" expr
--              | call_stmt  (for top-level function calls like snprintf(...))
--   expr       = or_expr
--   or_expr    = and_expr { "or" and_expr }
--   and_expr   = cmp_expr { "and" cmp_expr }
--   cmp_expr   = add_expr { cmp_op add_expr }
--   add_expr   = mul_expr { ("+" | "-") mul_expr }
--   mul_expr   = unary { ("*" | "/" | "%") unary }
--   unary      = "not" unary | "-" unary | primary
--   primary    = NUMBER | STRING | BOOL | if_expr | field_access | call | "(" expr ")"
--   field_access = "self" "." IDENT
--   call       = IDENT "(" [expr {"," expr}] ")"
--              | IDENT "." IDENT "(" [expr {"," expr}] ")"
--   if_expr    = "if" expr "then" expr "else" expr

function Parser:parse_program()
  local stmts = {}
  self:skip_separators()
  while self:peek().type ~= TOKEN.EOF do
    local stmt, err = self:parse_statement()
    if err then return nil, err end
    stmts[#stmts + 1] = stmt
    self:skip_separators()
  end
  return stmts, nil
end

function Parser:parse_statement()
  local tok = self:peek()

  -- self.X = expr  (assignment)
  if tok.type == TOKEN.SELF then
    return self:parse_assignment()
  end

  -- top-level function call: ident(...) or ident.ident(...)
  if tok.type == TOKEN.IDENT then
    return self:parse_call_statement()
  end

  return nil, {
    message = ("unexpected token '%s' at start of statement"):format(tok.value),
    line = tok.line, col = tok.col,
  }
end

function Parser:parse_assignment()
  local self_tok, err = self:expect(TOKEN.SELF)
  if err then return nil, err end

  _, err = self:expect(TOKEN.DOT)
  if err then return nil, err end

  local name_tok
  name_tok, err = self:expect(TOKEN.IDENT)
  if err then return nil, err end

  _, err = self:expect(TOKEN.EQ)
  if err then return nil, err end

  local value
  value, err = self:parse_expr()
  if err then return nil, err end

  return {
    tag = "Assign",
    target = name_tok.value,
    value = value,
    line = self_tok.line,
    col = self_tok.col,
  }, nil
end

function Parser:parse_call_statement()
  local expr, err = self:parse_call_expr()
  if err then return nil, err end
  if expr.tag ~= "Call" then
    return nil, {
      message = "expected function call statement",
      line = expr.line or 0, col = expr.col or 0,
    }
  end
  return expr, nil
end

function Parser:parse_expr()
  return self:parse_or_expr()
end

function Parser:parse_or_expr()
  local left, err = self:parse_and_expr()
  if err then return nil, err end
  while self:peek().type == TOKEN.OR do
    local op_tok = self:advance()
    local right
    right, err = self:parse_and_expr()
    if err then return nil, err end
    left = { tag = "BinOp", op = "or", left = left, right = right, line = op_tok.line, col = op_tok.col }
  end
  return left, nil
end

function Parser:parse_and_expr()
  local left, err = self:parse_cmp_expr()
  if err then return nil, err end
  while self:peek().type == TOKEN.AND do
    local op_tok = self:advance()
    local right
    right, err = self:parse_cmp_expr()
    if err then return nil, err end
    left = { tag = "BinOp", op = "and", left = left, right = right, line = op_tok.line, col = op_tok.col }
  end
  return left, nil
end

local CMP_OPS = {
  [TOKEN.EQEQ] = "==",
  [TOKEN.NEQ]   = "~=",
  [TOKEN.LT]    = "<",
  [TOKEN.GT]    = ">",
  [TOKEN.LTE]   = "<=",
  [TOKEN.GTE]   = ">=",
}

function Parser:parse_cmp_expr()
  local left, err = self:parse_add_expr()
  if err then return nil, err end
  local op = CMP_OPS[self:peek().type]
  if op then
    local op_tok = self:advance()
    local right
    right, err = self:parse_add_expr()
    if err then return nil, err end
    left = { tag = "BinOp", op = op, left = left, right = right, line = op_tok.line, col = op_tok.col }
  end
  return left, nil
end

function Parser:parse_add_expr()
  local left, err = self:parse_mul_expr()
  if err then return nil, err end
  while self:peek().type == TOKEN.OP and (self:peek().value == "+" or self:peek().value == "-") do
    local op_tok = self:advance()
    local right
    right, err = self:parse_mul_expr()
    if err then return nil, err end
    left = { tag = "BinOp", op = op_tok.value, left = left, right = right, line = op_tok.line, col = op_tok.col }
  end
  return left, nil
end

function Parser:parse_mul_expr()
  local left, err = self:parse_unary()
  if err then return nil, err end
  while self:peek().type == TOKEN.OP and (self:peek().value == "*" or self:peek().value == "/" or self:peek().value == "%") do
    local op_tok = self:advance()
    local right
    right, err = self:parse_unary()
    if err then return nil, err end
    left = { tag = "BinOp", op = op_tok.value, left = left, right = right, line = op_tok.line, col = op_tok.col }
  end
  return left, nil
end

function Parser:parse_unary()
  if self:peek().type == TOKEN.NOT then
    local op_tok = self:advance()
    local operand, err = self:parse_unary()
    if err then return nil, err end
    return { tag = "UnaryOp", op = "not", operand = operand, line = op_tok.line, col = op_tok.col }, nil
  end
  if self:peek().type == TOKEN.OP and self:peek().value == "-" then
    local op_tok = self:advance()
    local operand, err = self:parse_unary()
    if err then return nil, err end
    return { tag = "UnaryOp", op = "-", operand = operand, line = op_tok.line, col = op_tok.col }, nil
  end
  return self:parse_primary()
end

function Parser:parse_primary()
  local tok = self:peek()

  -- Number literal
  if tok.type == TOKEN.NUMBER then
    self:advance()
    return { tag = "Literal", value = tonumber(tok.value), line = tok.line, col = tok.col }, nil
  end

  -- String literal
  if tok.type == TOKEN.STRING then
    self:advance()
    return { tag = "Literal", value = tok.value, line = tok.line, col = tok.col }, nil
  end

  -- Boolean literal
  if tok.type == TOKEN.BOOL then
    self:advance()
    return { tag = "Literal", value = (tok.value == "true"), line = tok.line, col = tok.col }, nil
  end

  -- If expression
  if tok.type == TOKEN.IF then
    return self:parse_if_expr()
  end

  -- self.field
  if tok.type == TOKEN.SELF then
    return self:parse_field_access()
  end

  -- function call: ident(...) or ident.ident(...)
  if tok.type == TOKEN.IDENT then
    return self:parse_call_expr()
  end

  -- parenthesized expression
  if tok.type == TOKEN.LPAREN then
    self:advance()
    local expr, err = self:parse_expr()
    if err then return nil, err end
    _, err = self:expect(TOKEN.RPAREN)
    if err then return nil, err end
    return expr, nil
  end

  return nil, {
    message = ("unexpected token '%s'"):format(tok.value),
    line = tok.line, col = tok.col,
  }
end

function Parser:parse_field_access()
  local self_tok = self:advance() -- consume 'self'
  local _, err = self:expect(TOKEN.DOT)
  if err then return nil, err end
  local name_tok
  name_tok, err = self:expect(TOKEN.IDENT)
  if err then return nil, err end
  return { tag = "FieldAccess", name = name_tok.value, line = self_tok.line, col = self_tok.col }, nil
end

function Parser:parse_call_expr()
  local name_tok = self:advance() -- consume IDENT
  local fn_name = name_tok.value

  -- check for dotted name: math.floor etc.
  if self:peek().type == TOKEN.DOT then
    self:advance()
    local method_tok, err = self:expect(TOKEN.IDENT)
    if err then return nil, err end
    fn_name = fn_name .. "." .. method_tok.value
  end

  -- must have '('
  if self:peek().type ~= TOKEN.LPAREN then
    return nil, {
      message = ("expected '(' after function name '%s'"):format(fn_name),
      line = name_tok.line, col = name_tok.col,
    }
  end
  self:advance() -- consume '('

  -- validate whitelist
  if not WHITELIST_FUNCTIONS[fn_name] then
    return nil, {
      message = ("mutation calls '%s' which is not in whitelist (allowed: snprintf, math.floor, math.ceil, math.max, math.min)"):format(fn_name),
      line = name_tok.line, col = name_tok.col,
    }
  end

  -- parse arguments
  local args = {}
  if self:peek().type ~= TOKEN.RPAREN then
    local arg, err = self:parse_expr()
    if err then return nil, err end
    args[#args + 1] = arg
    while self:peek().type == TOKEN.COMMA do
      self:advance()
      arg, err = self:parse_expr()
      if err then return nil, err end
      args[#args + 1] = arg
    end
  end

  local _, err = self:expect(TOKEN.RPAREN)
  if err then return nil, err end

  return { tag = "Call", fn = fn_name, args = args, line = name_tok.line, col = name_tok.col }, nil
end

function Parser:parse_if_expr()
  local if_tok = self:advance() -- consume 'if'
  local cond, err = self:parse_expr()
  if err then return nil, err end
  _, err = self:expect(TOKEN.THEN)
  if err then return nil, err end
  local then_expr
  then_expr, err = self:parse_expr()
  if err then return nil, err end
  _, err = self:expect(TOKEN.ELSE)
  if err then return nil, err end
  local else_expr
  else_expr, err = self:parse_expr()
  if err then return nil, err end
  return { tag = "IfExpr", cond = cond, then_ = then_expr, else_ = else_expr, line = if_tok.line, col = if_tok.col }, nil
end

-- =====================================================================
-- 3. Public API
-- =====================================================================

--- Parse mutation/compute string into AST statement list.
--- @param source string
--- @return table|nil stmts  Stmt[] on success
--- @return table|nil error  {message, line, col} on failure
function MutationAST.parse(source)
  assert(type(source) == "string", "MutationAST.parse: source must be a string")

  local tokens, tok_err = MutationAST.tokenize(source)
  if not tokens then
    return nil, tok_err
  end

  local parser = Parser.new(tokens)
  local stmts, parse_err = parser:parse_program()
  if not stmts then
    return nil, parse_err
  end

  return stmts, nil
end

--- Extract read set (all FieldAccess names) from AST.
--- @param stmts table Stmt[]
--- @return table set {name -> true}
function MutationAST.read_set(stmts)
  local set = {}

  local function walk(node)
    if not node or type(node) ~= "table" then return end
    if node.tag == "FieldAccess" then
      set[node.name] = true
    elseif node.tag == "BinOp" then
      walk(node.left)
      walk(node.right)
    elseif node.tag == "UnaryOp" then
      walk(node.operand)
    elseif node.tag == "Call" then
      for _, arg in ipairs(node.args) do walk(arg) end
    elseif node.tag == "IfExpr" then
      walk(node.cond)
      walk(node.then_)
      walk(node.else_)
    elseif node.tag == "Assign" then
      walk(node.value)
    end
  end

  for _, stmt in ipairs(stmts) do walk(stmt) end
  return set
end

--- Extract write set (all Assign target names) from AST.
--- @param stmts table Stmt[]
--- @return table set {name -> true}
function MutationAST.write_set(stmts)
  local set = {}
  for _, stmt in ipairs(stmts) do
    if stmt.tag == "Assign" then
      set[stmt.target] = true
    end
  end
  return set
end

--- Emit AST back to Nelua code string.
--- @param stmts table Stmt[]
--- @param indent number indent level (default 0)
--- @return string code
function MutationAST.emit(stmts, indent)
  indent = indent or 0
  local prefix = string.rep("  ", indent)
  local lines = {}

  local function emit_expr(node)
    if node.tag == "Literal" then
      if type(node.value) == "boolean" then
        return node.value and "true" or "false"
      elseif type(node.value) == "string" then
        return node.value  -- already quoted
      else
        return tostring(node.value)
      end
    elseif node.tag == "FieldAccess" then
      return "self." .. node.name
    elseif node.tag == "BinOp" then
      return emit_expr(node.left) .. " " .. node.op .. " " .. emit_expr(node.right)
    elseif node.tag == "UnaryOp" then
      if node.op == "not" then
        return "not " .. emit_expr(node.operand)
      else
        return node.op .. emit_expr(node.operand)
      end
    elseif node.tag == "Call" then
      local args = {}
      for _, a in ipairs(node.args) do args[#args + 1] = emit_expr(a) end
      return node.fn .. "(" .. table.concat(args, ", ") .. ")"
    elseif node.tag == "IfExpr" then
      return "if " .. emit_expr(node.cond) .. " then " .. emit_expr(node.then_) .. " else " .. emit_expr(node.else_)
    end
    return "?"
  end

  for _, stmt in ipairs(stmts) do
    if stmt.tag == "Assign" then
      lines[#lines + 1] = prefix .. "self." .. stmt.target .. " = " .. emit_expr(stmt.value)
    elseif stmt.tag == "Call" then
      lines[#lines + 1] = prefix .. emit_expr(stmt)
    end
  end

  return table.concat(lines, "\n")
end

--- Validate that all function calls are in the whitelist.
--- (Already enforced during parsing, this is for post-parse re-check.)
--- @param stmts table Stmt[]
--- @return boolean ok
--- @return table|nil error {message, line, col}
function MutationAST.validate_whitelist(stmts)
  local err_found = nil

  local function walk(node)
    if err_found then return end
    if not node or type(node) ~= "table" then return end
    if node.tag == "Call" then
      if not WHITELIST_FUNCTIONS[node.fn] then
        err_found = {
          message = ("mutation calls '%s' which is not in whitelist"):format(node.fn),
          line = node.line or 0,
          col = node.col or 0,
        }
        return
      end
      for _, arg in ipairs(node.args) do walk(arg) end
    elseif node.tag == "BinOp" then
      walk(node.left); walk(node.right)
    elseif node.tag == "UnaryOp" then
      walk(node.operand)
    elseif node.tag == "IfExpr" then
      walk(node.cond); walk(node.then_); walk(node.else_)
    elseif node.tag == "Assign" then
      walk(node.value)
    end
  end

  for _, stmt in ipairs(stmts) do walk(stmt) end
  if err_found then return false, err_found end
  return true, nil
end

return MutationAST
