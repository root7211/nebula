#!/usr/bin/env python3
# patch_gap_buffer.py — Phase 3.6.3: 向 gap_buffer.nelua 插入 delete_range 方法

with open('/home/ubuntu/nebula/src/gap_buffer.nelua', 'r', encoding='utf-8') as f:
    lines = f.readlines()

# 找到 "return type_name, table.concat(lines, "\n")" 这一行的行号
insert_before = None
for i, line in enumerate(lines):
    if 'return type_name, table.concat(lines, "\\n")' in line:
        insert_before = i
        break

if insert_before is None:
    print("ERROR: 未找到插入点 'return type_name, table.concat'")
    exit(1)

print(f"找到插入点：第 {insert_before + 1} 行")

delete_range_code = '''  -- ★ Phase 3.6.3: delete_range — 删除逻辑区间 [sel_start, sel_end) 内的字符（O(N)）
  --
  -- 算法：
  --   1. 先将光标移动到 sel_start（通过 move_cursor_left/right，O(|delta|)）
  --   2. 再连续调用 delete_after() 共 (sel_end - sel_start) 次（O(K)，K = 选区长度）
  --
  -- 参数：
  --   sel_start : uint32 — 选区起始逻辑索引（含）
  --   sel_end   : uint32 — 选区结束逻辑索引（不含）
  --
  -- 调用后：光标位于 sel_start，选区内容已删除，gap 扩大 K 个字节。
  table.insert(lines, ("-- [gap_buffer] %s: delete_range (Phase 3.6.3)"):format(type_name))
  table.insert(lines, ("function %s:delete_range(sel_start: uint32, sel_end: uint32): void"):format(type_name))
  table.insert(lines,  "  if sel_start >= sel_end then return end")
  -- 步骤 1：将光标移动到 sel_start
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
  -- 步骤 2：连续删除 (sel_end - sel_start) 个字符（delete_after = gap_end++）
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
'''

# 在 insert_before 行之前插入
new_lines = lines[:insert_before] + [delete_range_code] + lines[insert_before:]

with open('/home/ubuntu/nebula/src/gap_buffer.nelua', 'w', encoding='utf-8') as f:
    f.writelines(new_lines)

print("delete_range 插入成功！")

# 验证
with open('/home/ubuntu/nebula/src/gap_buffer.nelua', 'r', encoding='utf-8') as f:
    result = f.read()

if 'delete_range' in result:
    print("验证通过：delete_range 已存在于文件中")
else:
    print("ERROR: 验证失败")
