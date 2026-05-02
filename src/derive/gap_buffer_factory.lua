-- =============================================================================
-- derive/gap_buffer_factory.lua
-- Nebula GUI Compiler — Phase 3.6
--
-- 编译期泛型宏：nebula_gen_gap_buffer_type(N)
--
-- 从 gap_buffer.nelua 的 ##[[ ]] 块中提取，作为独立 Lua 模块加载。
-- 这样所有 require "nebula_core" 的文件都能在编译期使用此函数，
-- 无需手动 require "gap_buffer"。
--
-- ★ BUG-6 注意：此文件中的 nebula_gen_gap_buffer_type() 必须与
--   gap_buffer.nelua 中的实现保持同步。修改任一文件时，请同步更新另一个。
--
-- 用法（在 .nelua 文件的编译期块中）：
--   ##[[ local _buf_type, _buf_src = nebula_gen_gap_buffer_type(255) ]]
--   ##[[ for _, _s in ipairs(aster.parse(_buf_src, "<gap_buffer:255>")) do inject_statement(_s) end ]]
-- =============================================================================

function nebula_gen_gap_buffer_type(capacity)
  assert(type(capacity) == "number" and capacity > 0 and capacity <= 65535,
    ("nebula_gen_gap_buffer_type: capacity must be 1..65535, got %s"):format(tostring(capacity)))
  local type_name = ("NebulaBuf%d"):format(capacity)
  -- 防止重复生成同一容量的类型
  if _nebula_gap_buf_types and _nebula_gap_buf_types[type_name] then
    return type_name, ""
  end
  _nebula_gap_buf_types = _nebula_gap_buf_types or {}
  _nebula_gap_buf_types[type_name] = true
  local lines = {}
  table.insert(lines, ("-- [gap_buffer] %s (capacity=%d)"):format(type_name, capacity))
  table.insert(lines, ("global %s = @record{"):format(type_name))
  table.insert(lines, ("  buf:       [%d]uint8,"):format(capacity + 1))
  table.insert(lines, ("  gap_start: uint16,"))
  table.insert(lines, ("  gap_end:   uint16,"))
  table.insert(lines, ("  capacity:  uint16,"))
  table.insert(lines, "}")
  table.insert(lines, "")
  table.insert(lines, ("function %s:init()"):format(type_name))
  table.insert(lines, ("  self.gap_start = 0"))
  table.insert(lines, ("  self.gap_end   = %d"):format(capacity))
  table.insert(lines, ("  self.capacity  = %d"):format(capacity))
  table.insert(lines, ("  self.buf[0]    = 0"))
  table.insert(lines, "end")
  table.insert(lines, "")
  table.insert(lines, ("function %s:len(): uint16"):format(type_name))
  table.insert(lines, ("  return self.capacity - (self.gap_end - self.gap_start)"))
  table.insert(lines, "end")
  table.insert(lines, "")
  table.insert(lines, ("function %s:is_full(): boolean"):format(type_name))
  table.insert(lines, ("  return self.gap_start == self.gap_end"))
  table.insert(lines, "end")
  table.insert(lines, "")
  table.insert(lines, ("function %s:cursor(): uint16"):format(type_name))
  table.insert(lines, ("  return self.gap_start"))
  table.insert(lines, "end")
  table.insert(lines, "")
  table.insert(lines, ("function %s:insert_char(ch: uint8): boolean"):format(type_name))
  table.insert(lines, ("  if self:is_full() then return false end"))
  table.insert(lines, ("  self.buf[self.gap_start] = ch"))
  table.insert(lines, ("  self.gap_start = self.gap_start + 1"))
  table.insert(lines, ("  return true"))
  table.insert(lines, "end")
  table.insert(lines, "")
  table.insert(lines, ("function %s:delete_before(): boolean"):format(type_name))
  table.insert(lines, ("  if self.gap_start == 0 then return false end"))
  table.insert(lines, ("  self.gap_start = self.gap_start - 1"))
  table.insert(lines, ("  return true"))
  table.insert(lines, "end")
  table.insert(lines, "")
  table.insert(lines, ("function %s:delete_after(): boolean"):format(type_name))
  table.insert(lines, ("  if self.gap_end >= self.capacity then return false end"))
  table.insert(lines, ("  self.gap_end = self.gap_end + 1"))
  table.insert(lines, ("  return true"))
  table.insert(lines, "end")
  table.insert(lines, "")
  table.insert(lines, ("function %s:move_cursor_left(): boolean"):format(type_name))
  table.insert(lines, ("  if self.gap_start == 0 then return false end"))
  table.insert(lines, ("  self.gap_end   = self.gap_end   - 1"))
  table.insert(lines, ("  self.buf[self.gap_end] = self.buf[self.gap_start - 1]"))
  table.insert(lines, ("  self.gap_start = self.gap_start - 1"))
  table.insert(lines, ("  return true"))
  table.insert(lines, "end")
  table.insert(lines, "")
  table.insert(lines, ("function %s:move_cursor_right(): boolean"):format(type_name))
  table.insert(lines, ("  if self.gap_end >= self.capacity then return false end"))
  table.insert(lines, ("  self.buf[self.gap_start] = self.buf[self.gap_end]"))
  table.insert(lines, ("  self.gap_start = self.gap_start + 1"))
  table.insert(lines, ("  self.gap_end   = self.gap_end   + 1"))
  table.insert(lines, ("  return true"))
  table.insert(lines, "end")
  table.insert(lines, "")
  table.insert(lines, ("function %s:move_cursor_home()"):format(type_name))
  table.insert(lines, ("  while self.gap_start > 0 do"))
  table.insert(lines, ("    self.gap_end   = self.gap_end   - 1"))
  table.insert(lines, ("    self.buf[self.gap_end] = self.buf[self.gap_start - 1]"))
  table.insert(lines, ("    self.gap_start = self.gap_start - 1"))
  table.insert(lines, ("  end"))
  table.insert(lines, "end")
  table.insert(lines, "")
  table.insert(lines, ("function %s:move_cursor_end()"):format(type_name))
  table.insert(lines, ("  while self.gap_end < self.capacity do"))
  table.insert(lines, ("    self.buf[self.gap_start] = self.buf[self.gap_end]"))
  table.insert(lines, ("    self.gap_start = self.gap_start + 1"))
  table.insert(lines, ("    self.gap_end   = self.gap_end   + 1"))
  table.insert(lines, ("  end"))
  table.insert(lines, "end")
  table.insert(lines, "")
  table.insert(lines, ("function %s:flatten(out: *[0]uint8, max_out: uint16): uint16"):format(type_name))
  table.insert(lines, ("  local n: uint16 = 0"))
  table.insert(lines, ("  local i: uint16 = 0"))
  table.insert(lines, ("  while i < self.gap_start and n < max_out do"))
  table.insert(lines, ("    out[n] = self.buf[i]"))
  table.insert(lines, ("    i = i + 1"))
  table.insert(lines, ("    n = n + 1"))
  table.insert(lines, ("  end"))
  table.insert(lines, ("  i = self.gap_end"))
  table.insert(lines, ("  while i < self.capacity and n < max_out do"))
  table.insert(lines, ("    out[n] = self.buf[i]"))
  table.insert(lines, ("    i = i + 1"))
  table.insert(lines, ("    n = n + 1"))
  table.insert(lines, ("  end"))
  table.insert(lines, ("  out[n] = 0"))
  table.insert(lines, ("  return n"))
  table.insert(lines, "end")
  table.insert(lines, "")
  table.insert(lines, ("function %s:clear()"):format(type_name))
  table.insert(lines, ("  self.gap_start = 0"))
  table.insert(lines, ("  self.gap_end   = self.capacity"))
  table.insert(lines, "end")
  table.insert(lines, "")
  table.insert(lines, ("-- [gap_buffer] %s: delete_range (Phase 3.6.3)"):format(type_name))
  table.insert(lines, ("function %s:delete_range(sel_start: uint32, sel_end: uint32): void"):format(type_name))
  table.insert(lines,  "  if sel_start >= sel_end then return end")
  table.insert(lines,  "  while self.gap_start > (@uint16)(sel_start) do")
  table.insert(lines,  "    self.gap_end   = self.gap_end   - 1")
  table.insert(lines,  "    self.buf[self.gap_end] = self.buf[self.gap_start - 1]")
  table.insert(lines,  "    self.gap_start = self.gap_start - 1")
  table.insert(lines,  "  end")
  table.insert(lines,  "  while self.gap_start < (@uint16)(sel_start) do")
  table.insert(lines,  "    self.buf[self.gap_start] = self.buf[self.gap_end]")
  table.insert(lines,  "    self.gap_start = self.gap_start + 1")
  table.insert(lines,  "    self.gap_end   = self.gap_end   + 1")
  table.insert(lines,  "  end")
  table.insert(lines,  "  local k: uint32 = sel_end - sel_start")
  table.insert(lines,  "  local j: uint32 = 0")
  table.insert(lines,  "  while j < k do")
  table.insert(lines,  "    if self.gap_end < self.capacity then")
  table.insert(lines,  "      self.gap_end = self.gap_end + 1")
  table.insert(lines,  "    end")
  table.insert(lines,  "    j = j + 1")
  table.insert(lines,  "  end")
  table.insert(lines,  "end")
  table.insert(lines, "")
  -- ★ Phase 4.7-S1: UTF-8 aware cursor movement and deletion
  -- These methods handle multi-byte UTF-8 characters as atomic units.
  -- ASCII (1 byte) degrades to identical behavior as byte-level methods.
  -- CJK characters (3 bytes in UTF-8) are skipped as a whole.

  -- move_cursor_left_char: move left by one UTF-8 character (skip continuation bytes)
  table.insert(lines, ("-- [gap_buffer] %s: move_cursor_left_char (Phase 4.7-S1 — UTF-8 aware)"):format(type_name))
  table.insert(lines, ("function %s:move_cursor_left_char(): boolean"):format(type_name))
  table.insert(lines,  "  if self.gap_start == 0 then return false end")
  table.insert(lines,  "  self:move_cursor_left()")
  table.insert(lines,  "  while self.gap_start > 0 and (self.buf[self.gap_end] & 0xC0) == 0x80 do")
  table.insert(lines,  "    self:move_cursor_left()")
  table.insert(lines,  "  end")
  table.insert(lines,  "  return true")
  table.insert(lines,  "end")
  table.insert(lines, "")

  -- move_cursor_right_char: move right by one UTF-8 character (skip continuation bytes)
  table.insert(lines, ("-- [gap_buffer] %s: move_cursor_right_char (Phase 4.7-S1 — UTF-8 aware)"):format(type_name))
  table.insert(lines, ("function %s:move_cursor_right_char(): boolean"):format(type_name))
  table.insert(lines,  "  if self.gap_end >= self.capacity then return false end")
  table.insert(lines,  "  self:move_cursor_right()")
  table.insert(lines,  "  while self.gap_end < self.capacity and (self.buf[self.gap_end] & 0xC0) == 0x80 do")
  table.insert(lines,  "    self:move_cursor_right()")
  table.insert(lines,  "  end")
  table.insert(lines,  "  return true")
  table.insert(lines,  "end")
  table.insert(lines, "")

  -- delete_char_before: delete one full UTF-8 character before cursor
  table.insert(lines, ("-- [gap_buffer] %s: delete_char_before (Phase 4.7-S1 — UTF-8 aware)"):format(type_name))
  table.insert(lines, ("function %s:delete_char_before(): boolean"):format(type_name))
  table.insert(lines,  "  if self.gap_start == 0 then return false end")
  table.insert(lines,  "  self.gap_start = self.gap_start - 1")
  table.insert(lines,  "  while self.gap_start > 0 and (self.buf[self.gap_start] & 0xC0) == 0x80 do")
  table.insert(lines,  "    self.gap_start = self.gap_start - 1")
  table.insert(lines,  "  end")
  table.insert(lines,  "  return true")
  table.insert(lines,  "end")
  table.insert(lines, "")

  -- delete_char_after: delete one full UTF-8 character after cursor
  table.insert(lines, ("-- [gap_buffer] %s: delete_char_after (Phase 4.7-S1 — UTF-8 aware)"):format(type_name))
  table.insert(lines, ("function %s:delete_char_after(): boolean"):format(type_name))
  table.insert(lines,  "  if self.gap_end >= self.capacity then return false end")
  table.insert(lines,  "  self.gap_end = self.gap_end + 1")
  table.insert(lines,  "  while self.gap_end < self.capacity and (self.buf[self.gap_end] & 0xC0) == 0x80 do")
  table.insert(lines,  "    self.gap_end = self.gap_end + 1")
  table.insert(lines,  "  end")
  table.insert(lines,  "  return true")
  table.insert(lines,  "end")
  table.insert(lines, "")

  -- char_count: count UTF-8 characters (not bytes) in the buffer
  table.insert(lines, ("-- [gap_buffer] %s: char_count (Phase 4.7-S1 — UTF-8 character count)"):format(type_name))
  table.insert(lines, ("function %s:char_count(): uint16"):format(type_name))
  table.insert(lines,  "  local count: uint16 = 0")
  table.insert(lines,  "  local i: uint16 = 0")
  table.insert(lines,  "  while i < self.gap_start do")
  table.insert(lines,  "    if (self.buf[i] & 0xC0) ~= 0x80 then count = count + 1 end")
  table.insert(lines,  "    i = i + 1")
  table.insert(lines,  "  end")
  table.insert(lines,  "  i = self.gap_end")
  table.insert(lines,  "  while i < self.capacity do")
  table.insert(lines,  "    if (self.buf[i] & 0xC0) ~= 0x80 then count = count + 1 end")
  table.insert(lines,  "    i = i + 1")
  table.insert(lines,  "  end")
  table.insert(lines,  "  return count")
  table.insert(lines,  "end")
  table.insert(lines, "")

  -- ★ Phase 4.X: extract_range — 提取 [sel_start, sel_end) 范围的字节到输出缓冲区
  table.insert(lines, ("-- [gap_buffer] %s: extract_range (Phase 4.X — clipboard support)"):format(type_name))
  table.insert(lines, ("function %s:extract_range(sel_start: uint32, sel_end: uint32, out: *[0]uint8, max_out: uint32): uint32"):format(type_name))
  table.insert(lines,  "  if sel_start >= sel_end then return 0 end")
  table.insert(lines,  "  local n: uint32 = 0")
  table.insert(lines,  "  local idx: uint32 = sel_start")
  table.insert(lines,  "  while idx < sel_end and n < max_out do")
  table.insert(lines,  "    -- Map logical index to physical buffer position")
  table.insert(lines,  "    local phys: uint16")
  table.insert(lines,  "    if (@uint16)(idx) < self.gap_start then")
  table.insert(lines,  "      phys = (@uint16)(idx)")
  table.insert(lines,  "    else")
  table.insert(lines,  "      phys = self.gap_end + ((@uint16)(idx) - self.gap_start)")
  table.insert(lines,  "    end")
  table.insert(lines,  "    out[n] = self.buf[phys]")
  table.insert(lines,  "    n = n + 1")
  table.insert(lines,  "    idx = idx + 1")
  table.insert(lines,  "  end")
  table.insert(lines,  "  return n")
  table.insert(lines,  "end")
  table.insert(lines, "")
  return type_name, table.concat(lines, "\n")
end

-- =============================================================================
-- ★ Phase 4.4 S3: nebula_gen_multiline_buffer_type(chars_per_line, max_lines)
--
-- 编译期泛型宏：生成 NebulaMultiBuf{N}_{L} 类型，包含：
--   · L 个 NebulaBuf{N}（每行一个 Gap Buffer）
--   · line_count: uint32   — 当前行数
--   · cursor_row: uint32   — 光标所在行
--   · cursor_col: uint32   — 光标所在列
--
-- 操作方法：
--   · init()                       — 初始化（单空行）
--   · get_line(i) -> *NebulaBuf{N} — 获取第 i 行的 buffer
--   · current_line() -> *NebulaBuf{N} — 获取光标所在行的 buffer
--   · insert_newline() -> boolean  — 在光标处插入新行
--   · delete_line(row) -> boolean  — 删除指定行（合并到上一行）
--   · move_cursor_up() -> boolean  — 光标上移一行
--   · move_cursor_down() -> boolean — 光标下移一行
--   · flatten_lines(out, max_out, line_height, base_y) -> uint32
--                                  — 展平所有行到输出（用于渲染）
--
-- 用法（在 .nelua 文件的编译期块中）：
--   ##[[ local _mb_type, _mb_src = nebula_gen_multiline_buffer_type(128, 32) ]]
--   ##[[ for _, _s in ipairs(aster.parse(_mb_src, "<multiline_buffer>")) do inject_statement(_s) end ]]
-- =============================================================================
_nebula_multiline_buf_types = _nebula_multiline_buf_types or {}

function nebula_gen_multiline_buffer_type(chars_per_line, max_lines)
  assert(type(chars_per_line) == "number" and chars_per_line > 0 and chars_per_line <= 65535,
    ("nebula_gen_multiline_buffer_type: chars_per_line must be 1..65535, got %s"):format(tostring(chars_per_line)))
  assert(type(max_lines) == "number" and max_lines > 0 and max_lines <= 65535,
    ("nebula_gen_multiline_buffer_type: max_lines must be 1..65535, got %s"):format(tostring(max_lines)))

  -- 先确保行 buffer 类型存在
  local line_type_name, line_type_src = nebula_gen_gap_buffer_type(chars_per_line)

  local type_name = ("NebulaMultiBuf%d_%d"):format(chars_per_line, max_lines)
  if _nebula_multiline_buf_types[type_name] then
    return type_name, "", line_type_name
  end
  _nebula_multiline_buf_types[type_name] = true

  local L = {}
  table.insert(L, ("-- [multiline_buffer] %s (chars_per_line=%d, max_lines=%d)"):format(type_name, chars_per_line, max_lines))
  table.insert(L, ("global %s = @record{"):format(type_name))
  table.insert(L, ("  lines:       [%d]%s,"):format(max_lines, line_type_name))
  table.insert(L,  "  line_count:  uint32,")
  table.insert(L,  "  cursor_row:  uint32,")
  table.insert(L,  "  cursor_col:  uint32,")
  table.insert(L,  "  max_lines:   uint32,")
  table.insert(L,  "  chars_per_line: uint16,")
  table.insert(L, "}")
  table.insert(L, "")

  -- init: 创建单空行
  table.insert(L, ("function %s:init()"):format(type_name))
  table.insert(L, "  self.line_count = 1")
  table.insert(L, "  self.cursor_row = 0")
  table.insert(L, "  self.cursor_col = 0")
  table.insert(L, ("  self.max_lines = %d"):format(max_lines))
  table.insert(L, ("  self.chars_per_line = %d"):format(chars_per_line))
  table.insert(L, ("  self.lines[0]:init()"):format())
  -- 初始化剩余行（未使用标记——line_count 控制可见行）
  table.insert(L, ("  local i: uint32 = 1"):format())
  table.insert(L, ("  while i < %d do"):format(max_lines))
  table.insert(L, ("    self.lines[i]:init()"):format())
  table.insert(L, ("    i = i + 1"):format())
  table.insert(L, "  end")
  table.insert(L, "end")
  table.insert(L, "")

  -- get_line: 安全获取行
  table.insert(L, ("function %s:get_line(i: uint32): *%s"):format(type_name, line_type_name))
  table.insert(L, "  return &self.lines[i]")
  table.insert(L, "end")
  table.insert(L, "")

  -- current_line: 获取光标所在行
  table.insert(L, ("function %s:current_line(): *%s"):format(type_name, line_type_name))
  table.insert(L, "  return &self.lines[self.cursor_row]")
  table.insert(L, "end")
  table.insert(L, "")

  -- insert_newline: 在光标处分割当前行，创建新行
  -- 将光标后的内容移到新行，当前行保留光标前的内容
  table.insert(L, ("function %s:insert_newline(): boolean"):format(type_name))
  table.insert(L, ("  if self.line_count >= %d then return false end"):format(max_lines))
  table.insert(L, "  -- 移动后续行腾出空间")
  table.insert(L, "  local j: uint32 = self.line_count")
  table.insert(L, "  while j > self.cursor_row + 1 do")
  table.insert(L, "    self.lines[j]:clear()")
  table.insert(L, ("    -- 从上一行复制内容到这一行"):format())
  table.insert(L, "    local prev = &self.lines[j - 1]")
  table.insert(L, "    local dst = &self.lines[j]")
  table.insert(L, "    local tmp: [256]uint8")
  table.insert(L, "    local n = prev:flatten(&tmp[0], 255)")
  table.insert(L, "    -- 逐字符插入到 dst")
  table.insert(L, "    local ci: uint16 = 0")
  table.insert(L, "    while ci < n do")
  table.insert(L, "      dst:insert_char(tmp[ci])")
  table.insert(L, "      ci = ci + 1")
  table.insert(L, "    end")
  table.insert(L, "    j = j - 1")
  table.insert(L, "  end")
  table.insert(L, "  -- 新行（cursor_row + 1）：从当前行的光标位置后截取")
  table.insert(L, "  local new_row = self.cursor_row + 1")
  table.insert(L, "  self.lines[new_row]:clear()")
  table.insert(L, "  -- 将当前行光标后的内容展平，插入新行")
  table.insert(L, "  local cur_line = &self.lines[self.cursor_row]")
  table.insert(L, "  local tmp2: [256]uint8")
  table.insert(L, "  local total = cur_line:flatten(&tmp2[0], 255)")
  table.insert(L, "  local after_cursor = total - (@uint16)(self.cursor_col)")
  table.insert(L, "  -- 清除当前行光标后的内容")
  table.insert(L, "  -- 简化方案：清空当前行，重新插入光标前的内容")
  table.insert(L, "  local saved: [256]uint8")
  table.insert(L, "  local saved_count: uint16 = 0")
  table.insert(L, "  local si: uint16 = 0")
  table.insert(L, "  while si < (@uint16)(self.cursor_col) and si < total do")
  table.insert(L, "    saved[saved_count] = tmp2[si]")
  table.insert(L, "    saved_count = saved_count + 1")
  table.insert(L, "    si = si + 1")
  table.insert(L, "  end")
  table.insert(L, "  cur_line:clear()")
  table.insert(L, "  local ri: uint16 = 0")
  table.insert(L, "  while ri < saved_count do")
  table.insert(L, "    cur_line:insert_char(saved[ri])")
  table.insert(L, "    ri = ri + 1")
  table.insert(L, "  end")
  table.insert(L, "  -- 新行：插入光标后的内容")
  table.insert(L, "  local ni: uint16 = (@uint16)(self.cursor_col)")
  table.insert(L, "  while ni < total do")
  table.insert(L, "    self.lines[new_row]:insert_char(tmp2[ni])")
  table.insert(L, "    ni = ni + 1")
  table.insert(L, "  end")
  table.insert(L, "  self.line_count = self.line_count + 1")
  table.insert(L, "  self.cursor_row = new_row")
  table.insert(L, "  self.cursor_col = 0")
  table.insert(L, "  return true")
  table.insert(L, "end")
  table.insert(L, "")

  -- merge_line_up: 将当前行内容合并到上一行（Backspace 在行首时）
  table.insert(L, ("function %s:merge_line_up(): boolean"):format(type_name))
  table.insert(L, "  if self.cursor_row == 0 then return false end")
  table.insert(L, "  local prev_row = self.cursor_row - 1")
  table.insert(L, "  local prev_line = &self.lines[prev_row]")
  table.insert(L, "  local cur_line = &self.lines[self.cursor_row]")
  table.insert(L, "  -- 记录合并点（上一行末尾）")
  table.insert(L, "  local merge_col = prev_line:len()")
  table.insert(L, "  -- 将当前行内容追加到上一行")
  table.insert(L, "  local tmp: [256]uint8")
  table.insert(L, "  local n = cur_line:flatten(&tmp[0], 255)")
  table.insert(L, "  local ci: uint16 = 0")
  table.insert(L, "  while ci < n do")
  table.insert(L, "    prev_line:insert_char(tmp[ci])")
  table.insert(L, "    ci = ci + 1")
  table.insert(L, "  end")
  table.insert(L, "  -- 上移后续行")
  table.insert(L, "  local ri: uint32 = self.cursor_row")
  table.insert(L, "  while ri + 1 < self.line_count do")
  table.insert(L, "    self.lines[ri]:clear()")
  table.insert(L, "    local next_line = &self.lines[ri + 1]")
  table.insert(L, "    local t2: [256]uint8")
  table.insert(L, "    local n2 = next_line:flatten(&t2[0], 255)")
  table.insert(L, "    local ci2: uint16 = 0")
  table.insert(L, "    while ci2 < n2 do")
  table.insert(L, "      self.lines[ri]:insert_char(t2[ci2])")
  table.insert(L, "      ci2 = ci2 + 1")
  table.insert(L, "    end")
  table.insert(L, "    ri = ri + 1")
  table.insert(L, "  end")
  table.insert(L, "  self.lines[self.line_count - 1]:clear()")
  table.insert(L, "  self.line_count = self.line_count - 1")
  table.insert(L, "  self.cursor_row = prev_row")
  table.insert(L, "  self.cursor_col = merge_col")
  table.insert(L, "  -- 将光标移到合并点")
  table.insert(L, "  local move_i: uint16 = 0")
  table.insert(L, "  while move_i < merge_col do")
  table.insert(L, "    prev_line:move_cursor_right()")
  table.insert(L, "    move_i = move_i + 1")
  table.insert(L, "  end")
  table.insert(L, "  return true")
  table.insert(L, "end")
  table.insert(L, "")

  -- sync_line_cursor: 从当前行的 gap buffer 光标位置同步到 cursor_col
  -- （必须在 move_cursor_up/down 之前定义，Nelua 要求方法在使用前声明）
  table.insert(L, ("function %s:sync_line_cursor(): void"):format(type_name))
  table.insert(L, "  self.cursor_col = (@uint32)(self.lines[self.cursor_row]:cursor())")
  table.insert(L, "end")
  table.insert(L, "")

  -- apply_line_cursor: 将 cursor_col 应用到当前行的 gap buffer
  -- ★ Phase 4.7-S1: 使用 UTF-8 aware move_cursor_right_char 而非 byte-level move
  table.insert(L, ("function %s:apply_line_cursor(): void"):format(type_name))
  table.insert(L, "  local line = &self.lines[self.cursor_row]")
  table.insert(L, "  -- 先移到行首")
  table.insert(L, "  line:move_cursor_home()")
  table.insert(L, "  -- 再移到 cursor_col 位置（字节偏移）")
  table.insert(L, "  while line:cursor() < (@uint16)(self.cursor_col) and line.gap_end < line.capacity do")
  table.insert(L, "    line:move_cursor_right()")
  table.insert(L, "  end")
  table.insert(L, "end")
  table.insert(L, "")

  -- move_cursor_up: 光标上移一行
  table.insert(L, ("function %s:move_cursor_up(): boolean"):format(type_name))
  table.insert(L, "  if self.cursor_row == 0 then return false end")
  table.insert(L, "  -- 同步当前行 gap buffer 光标")
  table.insert(L, "  self:sync_line_cursor()")
  table.insert(L, "  self.cursor_row = self.cursor_row - 1")
  table.insert(L, "  -- clamp cursor_col 到新行长度")
  table.insert(L, "  local line_len = self.lines[self.cursor_row]:len()")
  table.insert(L, "  if self.cursor_col > (@uint32)(line_len) then")
  table.insert(L, "    self.cursor_col = (@uint32)(line_len)")
  table.insert(L, "  end")
  table.insert(L, "  -- 将新行的 gap buffer 光标移到 cursor_col")
  table.insert(L, "  self:apply_line_cursor()")
  table.insert(L, "  return true")
  table.insert(L, "end")
  table.insert(L, "")

  -- move_cursor_down: 光标下移一行
  table.insert(L, ("function %s:move_cursor_down(): boolean"):format(type_name))
  table.insert(L, "  if self.cursor_row + 1 >= self.line_count then return false end")
  table.insert(L, "  self:sync_line_cursor()")
  table.insert(L, "  self.cursor_row = self.cursor_row + 1")
  table.insert(L, "  local line_len = self.lines[self.cursor_row]:len()")
  table.insert(L, "  if self.cursor_col > (@uint32)(line_len) then")
  table.insert(L, "    self.cursor_col = (@uint32)(line_len)")
  table.insert(L, "  end")
  table.insert(L, "  self:apply_line_cursor()")
  table.insert(L, "  return true")
  table.insert(L, "end")
  table.insert(L, "")

  -- flatten_lines: 展平所有行为文本（用于渲染和调试）
  table.insert(L, ("function %s:flatten_lines(out: *[0]uint8, max_out: uint16): uint16"):format(type_name))
  table.insert(L, "  local total: uint16 = 0")
  table.insert(L, "  local row: uint32 = 0")
  table.insert(L, "  while row < self.line_count and total < max_out do")
  table.insert(L, "    if row > 0 and total < max_out then")
  table.insert(L, "      out[total] = 10  -- newline")
  table.insert(L, "      total = total + 1")
  table.insert(L, "    end")
  table.insert(L, "    local tmp: [256]uint8")
  table.insert(L, "    local n = self.lines[row]:flatten(&tmp[0], 255)")
  table.insert(L, "    local ci: uint16 = 0")
  table.insert(L, "    while ci < n and total < max_out do")
  table.insert(L, "      out[total] = tmp[ci]")
  table.insert(L, "      total = total + 1")
  table.insert(L, "      ci = ci + 1")
  table.insert(L, "    end")
  table.insert(L, "    row = row + 1")
  table.insert(L, "  end")
  table.insert(L, "  out[total] = 0")
  table.insert(L, "  return total")
  table.insert(L, "end")
  table.insert(L, "")

  -- clear: 清空所有行
  table.insert(L, ("function %s:clear(): void"):format(type_name))
  table.insert(L, "  local i: uint32 = 0")
  table.insert(L, "  while i < self.line_count do")
  table.insert(L, "    self.lines[i]:clear()")
  table.insert(L, "    i = i + 1")
  table.insert(L, "  end")
  table.insert(L, "  self.line_count = 1")
  table.insert(L, "  self.cursor_row = 0")
  table.insert(L, "  self.cursor_col = 0")
  table.insert(L, "end")
  table.insert(L, "")

  -- 行 buffer 类型定义必须在多行类型之前（dependency ordering）
  return type_name, line_type_src .. "\n" .. table.concat(L, "\n") .. "\n", line_type_name
end

return "nebula_gap_buffer_factory_v0.2_phase4.4_s3"
