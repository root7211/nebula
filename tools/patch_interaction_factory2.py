#!/usr/bin/env python3
# patch_interaction_factory2.py — Phase 3.6.3: 修复剩余的 4 处 patch

with open('/home/ubuntu/nebula/src/derive/interaction_factory.lua', 'r', encoding='utf-8') as f:
    content = f.read()

# ============================================================
# 1. 修复字符输入循环：插入选区清除逻辑
# ============================================================
old_char = '''  -- 字符输入：O(1) 插入
  table.insert(lines,  "  local i: uint8 = 0")
  table.insert(lines,  "  while i < input.char_count do")
  table.insert(lines,  "    local cp = input.char_input[i]")
  table.insert(lines,  "    if cp >= 0x20 and cp <= 0x7E then")
  table.insert(lines,  "      if self.visual.gap_buf:insert_char((@uint8)(cp)) then")
  table.insert(lines,  "        changed = true")
  table.insert(lines,  "      end")
  table.insert(lines,  "    end")
  table.insert(lines,  "    i = i + 1")
  table.insert(lines,  "  end")'''

new_char = '''  -- ★ Phase 3.6.3: 字符输入前先清空选区（如有）
  table.insert(lines,  "  local i: uint8 = 0")
  table.insert(lines,  "  while i < input.char_count do")
  table.insert(lines,  "    local cp = input.char_input[i]")
  table.insert(lines,  "    if cp >= 0x20 and cp <= 0x7E then")
  table.insert(lines,  "      -- ★ Phase 3.6.3: 有选区时先删除选区内容，再插入新字符")
  table.insert(lines,  "      if self.selection_anchor ~= (@uint32)(self.visual.gap_buf:cursor()) then")
  table.insert(lines,  "        local cur = (@uint32)(self.visual.gap_buf:cursor())")
  table.insert(lines,  "        local anc = self.selection_anchor")
  table.insert(lines,  "        local sel_s = cur < anc and cur or anc")
  table.insert(lines,  "        local sel_e = cur < anc and anc or cur")
  table.insert(lines,  "        self.visual.gap_buf:delete_range(sel_s, sel_e)")
  table.insert(lines,  "        self.selection_anchor = (@uint32)(self.visual.gap_buf:cursor())")
  table.insert(lines,  "      end")
  table.insert(lines,  "      if self.visual.gap_buf:insert_char((@uint8)(cp)) then")
  table.insert(lines,  "        self.selection_anchor = (@uint32)(self.visual.gap_buf:cursor())")
  table.insert(lines,  "        changed = true")
  table.insert(lines,  "      end")
  table.insert(lines,  "    end")
  table.insert(lines,  "    i = i + 1")
  table.insert(lines,  "  end")'''

if old_char in content:
    content = content.replace(old_char, new_char)
    print("✓ 字符输入选区清除逻辑插入成功")
else:
    print("ERROR: 未找到字符输入循环")

# ============================================================
# 2. 修复 Left/Right/Home/End：插入 anchor 重置 + Shift 变体
# ============================================================
old_nav = '''  table.insert(lines,  "  elseif k == NebulaKey.Left then")
  table.insert(lines,  "    self.visual.gap_buf:move_cursor_left()")
  table.insert(lines,  "  elseif k == NebulaKey.Right then")
  table.insert(lines,  "    self.visual.gap_buf:move_cursor_right()")
  table.insert(lines,  "  elseif k == NebulaKey.Home then")
  table.insert(lines,  "    self.visual.gap_buf:move_cursor_home()")
  table.insert(lines,  "  elseif k == NebulaKey.End then")
  table.insert(lines,  "    self.visual.gap_buf:move_cursor_end()")
  table.insert(lines,  "  end")'''

new_nav = '''  table.insert(lines,  "  elseif k == NebulaKey.Left then")
  table.insert(lines,  "    self.visual.gap_buf:move_cursor_left()")
  table.insert(lines,  "    self.selection_anchor = (@uint32)(self.visual.gap_buf:cursor())")
  table.insert(lines,  "    changed = true")
  table.insert(lines,  "  elseif k == NebulaKey.Right then")
  table.insert(lines,  "    self.visual.gap_buf:move_cursor_right()")
  table.insert(lines,  "    self.selection_anchor = (@uint32)(self.visual.gap_buf:cursor())")
  table.insert(lines,  "    changed = true")
  table.insert(lines,  "  elseif k == NebulaKey.Home then")
  table.insert(lines,  "    self.visual.gap_buf:move_cursor_home()")
  table.insert(lines,  "    self.selection_anchor = (@uint32)(self.visual.gap_buf:cursor())")
  table.insert(lines,  "    changed = true")
  table.insert(lines,  "  elseif k == NebulaKey.End then")
  table.insert(lines,  "    self.visual.gap_buf:move_cursor_end()")
  table.insert(lines,  "    self.selection_anchor = (@uint32)(self.visual.gap_buf:cursor())")
  table.insert(lines,  "    changed = true")
  -- ★ Phase 3.6.3: Shift 组合键变体——扩展选区（不重置 anchor）
  table.insert(lines,  "  elseif k == NebulaKey.ShiftLeft then")
  table.insert(lines,  "    self.visual.gap_buf:move_cursor_left()")
  table.insert(lines,  "    changed = true")
  table.insert(lines,  "  elseif k == NebulaKey.ShiftRight then")
  table.insert(lines,  "    self.visual.gap_buf:move_cursor_right()")
  table.insert(lines,  "    changed = true")
  table.insert(lines,  "  elseif k == NebulaKey.ShiftHome then")
  table.insert(lines,  "    self.visual.gap_buf:move_cursor_home()")
  table.insert(lines,  "    changed = true")
  table.insert(lines,  "  elseif k == NebulaKey.ShiftEnd then")
  table.insert(lines,  "    self.visual.gap_buf:move_cursor_end()")
  table.insert(lines,  "    changed = true")
  table.insert(lines,  "  end")'''

if old_nav in content:
    content = content.replace(old_nav, new_nav)
    print("✓ Left/Right/Home/End + Shift 变体插入成功")
else:
    print("ERROR: 未找到导航键处理块")

# ============================================================
# 3. 在 get_text_len 之前注入 selection 辅助方法
# ============================================================
old_get_text_len = '''  -- -------------------------------------------------------------------------
  -- get_text_len：直接从 Gap Buffer 读取文本长度（无变化）
  -- -------------------------------------------------------------------------
  table.insert(lines, ("-- [editable/gap_buffer] %s: get_text_len"):format(ctx))'''

new_get_text_len = '''  -- -------------------------------------------------------------------------
  -- ★ Phase 3.6.3: 选区辅助方法注入
  --
  -- selection_anchor : uint32 — 选区固定端（L1 持久状态，注入到 InputContext）
  -- is_dragging      : boolean — 鼠标拖拽选区进行中标志
  -- has_selection()  — 检查是否有活动选区
  -- get_selection()  — 返回规范化选区 [sel_start, sel_end)
  -- clear_selection() — 清除选区（anchor 同步到当前光标）
  -- -------------------------------------------------------------------------
  table.insert(lines, ("-- [editable/selection] %s: has_selection (Phase 3.6.3)"):format(ctx))
  table.insert(lines, ("function %s:has_selection(): boolean"):format(ctx))
  table.insert(lines,  "  return self.selection_anchor ~= (@uint32)(self.visual.gap_buf:cursor())")
  table.insert(lines,  "end")
  table.insert(lines, ("-- [editable/selection] %s: get_selection (Phase 3.6.3)"):format(ctx))
  table.insert(lines, ("function %s:get_selection(sel_start: *uint32, sel_end: *uint32): void"):format(ctx))
  table.insert(lines,  "  local cur = (@uint32)(self.visual.gap_buf:cursor())")
  table.insert(lines,  "  local anc = self.selection_anchor")
  table.insert(lines,  "  $sel_start = cur < anc and cur or anc")
  table.insert(lines,  "  $sel_end   = cur < anc and anc or cur")
  table.insert(lines,  "end")
  table.insert(lines, ("-- [editable/selection] %s: clear_selection (Phase 3.6.3)"):format(ctx))
  table.insert(lines, ("function %s:clear_selection(): void"):format(ctx))
  table.insert(lines,  "  self.selection_anchor = (@uint32)(self.visual.gap_buf:cursor())")
  table.insert(lines,  "end")
  -- -------------------------------------------------------------------------
  -- get_text_len：直接从 Gap Buffer 读取文本长度（无变化）
  -- -------------------------------------------------------------------------
  table.insert(lines, ("-- [editable/gap_buffer] %s: get_text_len"):format(ctx))'''

if old_get_text_len in content:
    content = content.replace(old_get_text_len, new_get_text_len)
    print("✓ selection 辅助方法注入成功")
else:
    print("ERROR: 未找到 get_text_len 注释块")

with open('/home/ubuntu/nebula/src/derive/interaction_factory.lua', 'w', encoding='utf-8') as f:
    f.write(content)

print("\n✅ interaction_factory.lua 第二轮 patch 完成")
