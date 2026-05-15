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

  -- ★ Phase 4.7-S6: C stdio FFI bindings (emitted once)
  if not _nebula_stdio_emitted then
    _nebula_stdio_emitted = true
    table.insert(L, "-- [file_io] C stdio FFI bindings (Phase 4.7-S6)")
    table.insert(L, "global FILE <cimport, nodecl> = @record{}")
    table.insert(L, 'global function fopen(path: cstring, mode: cstring): *FILE <cimport, nodecl> end')
    table.insert(L, 'global function fclose(fp: *FILE): int32 <cimport, nodecl> end')
    table.insert(L, 'global function fread(buf: pointer, size: csize, count: csize, fp: *FILE): csize <cimport, nodecl> end')
    table.insert(L, 'global function fwrite(buf: pointer, size: csize, count: csize, fp: *FILE): csize <cimport, nodecl> end')
    table.insert(L, 'global function fseek(fp: *FILE, offset: clong, whence: int32): int32 <cimport, nodecl> end')
    table.insert(L, 'global function ftell(fp: *FILE): clong <cimport, nodecl> end')
    table.insert(L, "")
  end

  -- ★ Phase 4.7-S6: save_file — 将多行缓冲区内容保存到文件
  -- 使用 flatten_lines 序列化后一次性写入
  table.insert(L, ("-- [file_io] %s:save_file (Phase 4.7-S6)"):format(type_name))
  table.insert(L, ("function %s:save_file(path: cstring): boolean"):format(type_name))
  table.insert(L, '  local fp = fopen(path, "wb")')
  table.insert(L, "  if fp == nilptr then return false end")
  -- 分配足够大的临时缓冲区来装所有行
  -- max_out = max_lines * (chars_per_line + 1) 保证足够
  local max_flat = max_lines * (chars_per_line + 1)
  if max_flat > 65535 then max_flat = 65535 end
  table.insert(L, ("  local tmp: [%d]uint8"):format(max_flat))
  table.insert(L, ("  local n = self:flatten_lines(&tmp[0], %d)"):format(max_flat - 1))
  table.insert(L, "  if n > 0 then")
  table.insert(L, "    local written = fwrite(&tmp[0], 1, (@csize)(n), fp)")
  table.insert(L, "    if written ~= (@csize)(n) then")
  table.insert(L, "      fclose(fp)")
  table.insert(L, "      return false  -- ★ 审计修复：fwrite 写入不完整（磁盘满/权限错误）")
  table.insert(L, "    end")
  table.insert(L, "  end")
  table.insert(L, "  -- 末尾添加换行符（POSIX convention）")
  table.insert(L, "  local nl: uint8 = 10")
  table.insert(L, "  local nl_written = fwrite(&nl, 1, 1, fp)")
  table.insert(L, "  if nl_written ~= 1 then")
  table.insert(L, "    fclose(fp)")
  table.insert(L, "    return false")
  table.insert(L, "  end")
  table.insert(L, "  fclose(fp)")
  table.insert(L, "  return true")
  table.insert(L, "end")
  table.insert(L, "")

  -- ★ Phase 4.7-S6: load_file — 从文件加载内容到多行缓冲区
  -- 流程：fread 整个文件 → 按 \n 分行 → clear() → 逐字节 insert_char
  table.insert(L, ("-- [file_io] %s:load_file (Phase 4.7-S6)"):format(type_name))
  table.insert(L, ("function %s:load_file(path: cstring): boolean"):format(type_name))
  table.insert(L, '  local fp = fopen(path, "rb")')
  table.insert(L, "  if fp == nilptr then return false end")
  -- 获取文件大小
  table.insert(L, "  fseek(fp, 0, 2)  -- SEEK_END")
  table.insert(L, "  local file_size = ftell(fp)")
  table.insert(L, "  fseek(fp, 0, 0)  -- SEEK_SET")
  table.insert(L, ("  if file_size <= 0 then"))
  table.insert(L, "    fclose(fp)")
  table.insert(L, "    self:clear()")
  table.insert(L, "    return true")
  table.insert(L, "  end")
  -- 限制可读取的最大字节数
  table.insert(L, ("  local max_bytes: clong = %d"):format(max_flat))
  table.insert(L, "  if file_size > max_bytes then file_size = max_bytes end")
  table.insert(L, ("  local buf: [%d]uint8"):format(max_flat))
  table.insert(L, "  local read_n = fread(&buf[0], 1, (@csize)(file_size), fp)")
  table.insert(L, "  fclose(fp)")
  -- 清空当前内容
  table.insert(L, "  self:clear()")
  table.insert(L, "  self.lines[0]:clear()")
  -- 按字节遍历，遇到 \n 就 insert_newline
  table.insert(L, "  local row: uint32 = 0")
  table.insert(L, "  local bi: csize = 0")
  table.insert(L, "  while bi < read_n do")
  table.insert(L, "    local ch = buf[bi]")
  table.insert(L, "    if ch == 10 then  -- newline")
  table.insert(L, ("      if row + 1 < %d then"):format(max_lines))
  table.insert(L, "        row = row + 1")
  table.insert(L, "        self.line_count = self.line_count + 1")
  table.insert(L, "        self.lines[row]:clear()")
  table.insert(L, "      end")
  table.insert(L, "    elseif ch ~= 13 then  -- skip CR (handle CRLF)")
  table.insert(L, "      self.lines[row]:insert_char(ch)")
  table.insert(L, "    end")
  table.insert(L, "    bi = bi + 1")
  table.insert(L, "  end")
  -- 如果文件以换行结尾，最后一个空行是多余的——去掉它
  -- （除非文件只有一个换行）
  table.insert(L, "  -- Strip trailing empty line from POSIX newline")
  table.insert(L, "  if self.line_count > 1 and self.lines[self.line_count - 1]:len() == 0 then")
  table.insert(L, "    -- Check if last byte was newline")
  table.insert(L, "    if read_n > 0 and buf[read_n - 1] == 10 then")
  table.insert(L, "      self.line_count = self.line_count - 1")
  table.insert(L, "    end")
  table.insert(L, "  end")
  -- 重置光标到文件开头
  table.insert(L, "  self.cursor_row = 0")
  table.insert(L, "  self.cursor_col = 0")
  table.insert(L, "  self.lines[0]:move_cursor_home()")
  table.insert(L, "  return true")
  table.insert(L, "end")
  table.insert(L, "")

  -- 行 buffer 类型定义必须在多行类型之前（dependency ordering）
  return type_name, line_type_src .. "\n" .. table.concat(L, "\n") .. "\n", line_type_name
end

-- =============================================================================
-- ★ Phase 4.7-S5: nebula_gen_undo_stack_type(max_entries, max_data_bytes)
--
-- 编译期泛型宏：生成 NebulaUndoStack{E}_{D} 类型，包含：
--   · entries: [E]NebulaUndoEntry — 环形缓冲区的 undo 操作记录
--   · data:    [D]uint8           — 操作关联的文本数据池
--   · head/tail/cursor            — 环形缓冲区指针
--
-- 每个 NebulaUndoEntry 记录一个原子编辑操作：
--   · op:          uint8  — 操作类型 (1=insert, 2=delete, 3=newline, 4=merge_line)
--   · cursor_pos:  uint32 — 操作前的光标字节位置
--   · cursor_row:  uint32 — 操作前的光标行
--   · cursor_col:  uint32 — 操作前的光标列
--   · data_offset: uint32 — data[] 中的起始偏移
--   · data_len:    uint16 — 数据长度（字节）
--   · anchor:      uint32 — 操作前的 selection_anchor
--
-- 设计原则：
--   · 零堆分配：所有数据在编译期定容的栈/全局数组中
--   · 环形覆盖：超出容量时自动覆盖最旧的条目
--   · Redo 支持：cursor 指向当前位置，新编辑操作截断 redo 历史
-- =============================================================================
_nebula_undo_stack_types = _nebula_undo_stack_types or {}

function nebula_gen_undo_stack_type(max_entries, max_data_bytes)
  max_entries    = max_entries    or 512
  max_data_bytes = max_data_bytes or 16384
  assert(type(max_entries) == "number" and max_entries > 0 and max_entries <= 65535,
    ("nebula_gen_undo_stack_type: max_entries must be 1..65535, got %s"):format(tostring(max_entries)))
  assert(type(max_data_bytes) == "number" and max_data_bytes > 0 and max_data_bytes <= 65535,
    ("nebula_gen_undo_stack_type: max_data_bytes must be 1..65535, got %s"):format(tostring(max_data_bytes)))

  local type_name = ("NebulaUndoStack%d_%d"):format(max_entries, max_data_bytes)
  if _nebula_undo_stack_types[type_name] then
    return type_name, ""
  end
  _nebula_undo_stack_types[type_name] = true

  local L = {}

  -- NebulaUndoEntry (shared record, only emitted once)
  if not _nebula_undo_entry_emitted then
    _nebula_undo_entry_emitted = true
    table.insert(L, "-- [undo] NebulaUndoEntry (Phase 4.7-S5)")
    table.insert(L, "global NebulaUndoEntry = @record{")
    table.insert(L, "  op:          uint8,")   -- 1=insert, 2=delete, 3=newline, 4=merge_line
    table.insert(L, "  cursor_pos:  uint32,")  -- gap_buf cursor (byte offset) before op
    table.insert(L, "  cursor_row:  uint32,")  -- multiline cursor_row before op
    table.insert(L, "  cursor_col:  uint32,")  -- multiline cursor_col before op
    table.insert(L, "  data_offset: uint32,")  -- offset into data pool
    table.insert(L, "  data_len:    uint16,")  -- bytes of associated data
    table.insert(L, "  anchor:      uint32,")  -- selection_anchor before op
    table.insert(L, "}")
    table.insert(L, "")
    -- Op constants
    table.insert(L, "global NEBULA_UNDO_OP_INSERT:     uint8 <comptime> = 1")
    table.insert(L, "global NEBULA_UNDO_OP_DELETE:     uint8 <comptime> = 2")
    table.insert(L, "global NEBULA_UNDO_OP_NEWLINE:    uint8 <comptime> = 3")
    table.insert(L, "global NEBULA_UNDO_OP_MERGE_LINE: uint8 <comptime> = 4")
    table.insert(L, "")
  end

  table.insert(L, ("-- [undo] %s (max_entries=%d, max_data=%d)"):format(type_name, max_entries, max_data_bytes))
  table.insert(L, ("global %s = @record{"):format(type_name))
  table.insert(L, ("  entries: [%d]NebulaUndoEntry,"):format(max_entries))
  table.insert(L, ("  data:    [%d]uint8,"):format(max_data_bytes))
  table.insert(L,  "  count:   uint32,")       -- number of valid entries (including redo)
  table.insert(L,  "  cursor:  uint32,")       -- current position (entries before cursor = undo-able)
  table.insert(L,  "  data_used: uint32,")     -- bytes used in data pool
  table.insert(L, ("  max_entries: uint32,"))
  table.insert(L, ("  max_data:    uint32,"))
  table.insert(L,  "}")
  table.insert(L, "")

  -- init
  table.insert(L, ("function %s:init()"):format(type_name))
  table.insert(L, "  self.count     = 0")
  table.insert(L, "  self.cursor    = 0")
  table.insert(L, "  self.data_used = 0")
  table.insert(L, ("  self.max_entries = %d"):format(max_entries))
  table.insert(L, ("  self.max_data    = %d"):format(max_data_bytes))
  table.insert(L, "end")
  table.insert(L, "")

  -- push: record a new undo entry (truncates any redo history)
  table.insert(L, ("function %s:push(op: uint8, cursor_pos: uint32, cursor_row: uint32, cursor_col: uint32, anchor: uint32, buf: *[0]uint8, buf_len: uint16): void"):format(type_name))
  table.insert(L, "  -- Truncate redo history: new edit invalidates future entries")
  table.insert(L, "  self.count = self.cursor")
  table.insert(L, "  -- Reclaim data pool space from truncated entries")
  table.insert(L, "  if self.count == 0 then")
  table.insert(L, "    self.data_used = 0")
  table.insert(L, "  end")
  table.insert(L, ("  -- If stack is full, shift out oldest entry"))
  table.insert(L, ("  if self.count >= %d then"):format(max_entries))
  table.insert(L,  "    -- Simple strategy: reset stack (rare edge case for small stacks)")
  table.insert(L,  "    self.count     = 0")
  table.insert(L,  "    self.cursor    = 0")
  table.insert(L,  "    self.data_used = 0")
  table.insert(L,  "  end")
  table.insert(L, ("  -- Check data pool space"))
  table.insert(L, ("  if self.data_used + (@uint32)(buf_len) > %d then"):format(max_data_bytes))
  table.insert(L,  "    -- Data pool full: reset stack")
  table.insert(L,  "    self.count     = 0")
  table.insert(L,  "    self.cursor    = 0")
  table.insert(L,  "    self.data_used = 0")
  table.insert(L,  "  end")
  table.insert(L,  "  -- Write entry")
  table.insert(L,  "  local idx = self.cursor")
  table.insert(L,  "  self.entries[idx].op          = op")
  table.insert(L,  "  self.entries[idx].cursor_pos  = cursor_pos")
  table.insert(L,  "  self.entries[idx].cursor_row  = cursor_row")
  table.insert(L,  "  self.entries[idx].cursor_col  = cursor_col")
  table.insert(L,  "  self.entries[idx].data_offset = self.data_used")
  table.insert(L,  "  self.entries[idx].data_len    = buf_len")
  table.insert(L,  "  self.entries[idx].anchor      = anchor")
  table.insert(L,  "  -- Copy data")
  table.insert(L,  "  local di: uint32 = 0")
  table.insert(L,  "  while di < (@uint32)(buf_len) do")
  table.insert(L,  "    self.data[self.data_used + di] = buf[di]")
  table.insert(L,  "    di = di + 1")
  table.insert(L,  "  end")
  table.insert(L,  "  self.data_used = self.data_used + (@uint32)(buf_len)")
  table.insert(L,  "  self.cursor = self.cursor + 1")
  table.insert(L,  "  self.count  = self.cursor")
  table.insert(L,  "end")
  table.insert(L, "")

  -- can_undo / can_redo
  table.insert(L, ("function %s:can_undo(): boolean"):format(type_name))
  table.insert(L,  "  return self.cursor > 0")
  table.insert(L,  "end")
  table.insert(L, "")
  table.insert(L, ("function %s:can_redo(): boolean"):format(type_name))
  table.insert(L,  "  return self.cursor < self.count")
  table.insert(L,  "end")
  table.insert(L, "")

  -- peek_undo: get the entry that would be undone (cursor - 1)
  table.insert(L, ("function %s:peek_undo(): *NebulaUndoEntry"):format(type_name))
  table.insert(L,  "  return &self.entries[self.cursor - 1]")
  table.insert(L,  "end")
  table.insert(L, "")

  -- peek_redo: get the entry that would be redone (cursor)
  table.insert(L, ("function %s:peek_redo(): *NebulaUndoEntry"):format(type_name))
  table.insert(L,  "  return &self.entries[self.cursor]")
  table.insert(L,  "end")
  table.insert(L, "")

  -- get_data: get pointer to data for an entry
  table.insert(L, ("function %s:get_data(entry: *NebulaUndoEntry): *[0]uint8"):format(type_name))
  table.insert(L,  "  return (@*[0]uint8)(&self.data[entry.data_offset])")
  table.insert(L,  "end")
  table.insert(L, "")

  -- step_undo: move cursor back (caller handles buffer restoration)
  table.insert(L, ("function %s:step_undo(): void"):format(type_name))
  table.insert(L,  "  self.cursor = self.cursor - 1")
  table.insert(L,  "end")
  table.insert(L, "")

  -- step_redo: move cursor forward (caller handles buffer re-apply)
  table.insert(L, ("function %s:step_redo(): void"):format(type_name))
  table.insert(L,  "  self.cursor = self.cursor + 1")
  table.insert(L,  "end")
  table.insert(L, "")

  -- clear
  table.insert(L, ("function %s:clear()"):format(type_name))
  table.insert(L,  "  self.count     = 0")
  table.insert(L,  "  self.cursor    = 0")
  table.insert(L,  "  self.data_used = 0")
  table.insert(L,  "end")
  table.insert(L, "")

  return type_name, table.concat(L, "\n")
end

return "nebula_gap_buffer_factory_v0.4_phase4.7_s6"
