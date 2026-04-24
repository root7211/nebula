#!/usr/bin/env python3
# patch_interaction_factory.py — Phase 3.6.3: 向 interaction_factory.lua 注入选区支持

with open('/home/ubuntu/nebula/src/derive/interaction_factory.lua', 'r', encoding='utf-8') as f:
    content = f.read()

# ============================================================
# 1. 在 nebula_gen_text_buffer 的 process_text_input 中，
#    在 just_clicked 分支后插入选区清除逻辑，
#    并在键盘处理中插入 Shift+方向键选区扩展逻辑
# ============================================================

# 找到 just_clicked 分支，在其后插入 selection_anchor 重置
old_just_clicked = '''  table.insert(lines,  "  -- ★ Phase 3.6.2: mouse click → hit-test → cursor sync")
  table.insert(lines,  "  if self.click.just_clicked then")
  table.insert(lines, ("    local target = self:mouse_to_cursor(input.mouse_x, self.visual.pixel_height)"))
  table.insert(lines,  "    self:sync_cursor_to(target)")
  table.insert(lines,  "    changed = true")
  table.insert(lines,  "  end")'''

new_just_clicked = '''  table.insert(lines,  "  -- ★ Phase 3.6.2: mouse click → hit-test → cursor sync")
  table.insert(lines,  "  -- ★ Phase 3.6.3: Shift+Click 扩展选区；普通点击重置 anchor")
  table.insert(lines,  "  if self.click.just_clicked then")
  table.insert(lines, ("    local target = self:mouse_to_cursor(input.mouse_x, self.visual.pixel_height)"))
  table.insert(lines,  "    if not input.mod_shift then")
  table.insert(lines,  "      -- 普通点击：重置 anchor 到新光标位置（清除选区）")
  table.insert(lines,  "      self.selection_anchor = target")
  table.insert(lines,  "    end")
  table.insert(lines,  "    -- Shift+Click：保持原 anchor，仅移动光标（扩展选区）")
  table.insert(lines,  "    self:sync_cursor_to(target)")
  table.insert(lines,  "    self.is_dragging = input.mouse_left_down")
  table.insert(lines,  "    changed = true")
  table.insert(lines,  "  end")
  -- ★ Phase 3.6.3: 鼠标拖拽 → 实时更新光标（anchor 保持不动）
  table.insert(lines,  "  -- ★ Phase 3.6.3: drag → update cursor, keep anchor")
  table.insert(lines,  "  if self.is_dragging and input.mouse_left_down and not self.click.just_clicked then")
  table.insert(lines,  "    local drag_target = self:mouse_to_cursor(input.mouse_x, self.visual.pixel_height)")
  table.insert(lines,  "    self:sync_cursor_to(drag_target)")
  table.insert(lines,  "    changed = true")
  table.insert(lines,  "  end")
  table.insert(lines,  "  if not input.mouse_left_down then self.is_dragging = false end")'''

if old_just_clicked in content:
    content = content.replace(old_just_clicked, new_just_clicked)
    print("✓ just_clicked 分支更新成功")
else:
    print("ERROR: 未找到 just_clicked 分支")

# ============================================================
# 2. 在 process_text_input 的键盘处理中，
#    在 Left/Right/Home/End 处理之后插入 Shift 变体处理
# ============================================================

old_key_end = '''  table.insert(lines,  "  elseif k == NebulaKey.Home then")
  table.insert(lines,  "    self.visual.gap_buf:move_cursor_home()")
  table.insert(lines,  "    changed = true")
  table.insert(lines,  "  elseif k == NebulaKey.End then")
  table.insert(lines,  "    self.visual.gap_buf:move_cursor_end()")
  table.insert(lines,  "    changed = true")
  table.insert(lines,  "  end")'''

new_key_end = '''  table.insert(lines,  "  elseif k == NebulaKey.Home then")
  table.insert(lines,  "    self.selection_anchor = self.visual.gap_buf:cursor()")
  table.insert(lines,  "    self.visual.gap_buf:move_cursor_home()")
  table.insert(lines,  "    changed = true")
  table.insert(lines,  "  elseif k == NebulaKey.End then")
  table.insert(lines,  "    self.selection_anchor = self.visual.gap_buf:cursor()")
  table.insert(lines,  "    self.visual.gap_buf:move_cursor_end()")
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

if old_key_end in content:
    content = content.replace(old_key_end, new_key_end)
    print("✓ 键盘 Shift 变体处理插入成功")
else:
    print("ERROR: 未找到键盘 Home/End 处理块")

# ============================================================
# 3. 在字符输入和删除操作前，插入"先清空选区"逻辑
#    找到字符输入循环，在其前插入选区删除逻辑
# ============================================================

old_char_input = '''  table.insert(lines,  "  -- 字符输入：O(1) 插入")
  table.insert(lines,  "  local i: uint8 = 0")
  table.insert(lines,  "  while i < input.char_count do")
  table.insert(lines,  "    local cp = input.char_input[i]")
  table.insert(lines,  "    if cp >= 0x20 and cp <= 0x7E then")
  table.insert(lines,  "      if self.visual.gap_buf:insert_char((@uint8)(cp)) then")
  table.insert(lines,  "        changed = true")
  table.insert(lines,  "      end")
  table.insert(lines,  "    end")
  table.insert(lines,  "    i = i + 1")'''

new_char_input = '''  -- ★ Phase 3.6.3: 辅助函数内联——检查是否有活动选区
  table.insert(lines,  "  -- ★ Phase 3.6.3: 字符输入前先清空选区（如有）")
  table.insert(lines,  "  local function has_selection(ctx_self: auto): boolean")
  table.insert(lines,  "    return ctx_self.selection_anchor ~= ctx_self.visual.gap_buf:cursor()")
  table.insert(lines,  "  end")
  table.insert(lines,  "  -- 字符输入：O(1) 插入")
  table.insert(lines,  "  local i: uint8 = 0")
  table.insert(lines,  "  while i < input.char_count do")
  table.insert(lines,  "    local cp = input.char_input[i]")
  table.insert(lines,  "    if cp >= 0x20 and cp <= 0x7E then")
  table.insert(lines,  "      -- 有选区时先删除选区内容，再插入新字符")
  table.insert(lines,  "      if self.selection_anchor ~= self.visual.gap_buf:cursor() then")
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
  table.insert(lines,  "    i = i + 1")'''

if old_char_input in content:
    content = content.replace(old_char_input, new_char_input)
    print("✓ 字符输入选区清除逻辑插入成功")
else:
    print("ERROR: 未找到字符输入循环")

# ============================================================
# 4. 在 Backspace/Delete 处理中，插入"有选区时删除选区"逻辑
# ============================================================

old_backspace = '''  table.insert(lines,  "  if k == NebulaKey.Backspace then")
  table.insert(lines,  "    if self.visual.gap_buf:delete_before() then changed = true end")
  table.insert(lines,  "  elseif k == NebulaKey.Delete then")
  table.insert(lines,  "    if self.visual.gap_buf:delete_after() then changed = true end")'''

new_backspace = '''  table.insert(lines,  "  if k == NebulaKey.Backspace then")
  table.insert(lines,  "    -- ★ Phase 3.6.3: 有选区时删除选区，否则删除前一字符")
  table.insert(lines,  "    if self.selection_anchor ~= self.visual.gap_buf:cursor() then")
  table.insert(lines,  "      local cur = (@uint32)(self.visual.gap_buf:cursor())")
  table.insert(lines,  "      local anc = self.selection_anchor")
  table.insert(lines,  "      local sel_s = cur < anc and cur or anc")
  table.insert(lines,  "      local sel_e = cur < anc and anc or cur")
  table.insert(lines,  "      self.visual.gap_buf:delete_range(sel_s, sel_e)")
  table.insert(lines,  "      self.selection_anchor = (@uint32)(self.visual.gap_buf:cursor())")
  table.insert(lines,  "      changed = true")
  table.insert(lines,  "    elseif self.visual.gap_buf:delete_before() then")
  table.insert(lines,  "      self.selection_anchor = (@uint32)(self.visual.gap_buf:cursor())")
  table.insert(lines,  "      changed = true")
  table.insert(lines,  "    end")
  table.insert(lines,  "  elseif k == NebulaKey.Delete then")
  table.insert(lines,  "    -- ★ Phase 3.6.3: 有选区时删除选区，否则删除后一字符")
  table.insert(lines,  "    if self.selection_anchor ~= self.visual.gap_buf:cursor() then")
  table.insert(lines,  "      local cur = (@uint32)(self.visual.gap_buf:cursor())")
  table.insert(lines,  "      local anc = self.selection_anchor")
  table.insert(lines,  "      local sel_s = cur < anc and cur or anc")
  table.insert(lines,  "      local sel_e = cur < anc and anc or cur")
  table.insert(lines,  "      self.visual.gap_buf:delete_range(sel_s, sel_e)")
  table.insert(lines,  "      self.selection_anchor = (@uint32)(self.visual.gap_buf:cursor())")
  table.insert(lines,  "      changed = true")
  table.insert(lines,  "    elseif self.visual.gap_buf:delete_after() then")
  table.insert(lines,  "      changed = true")
  table.insert(lines,  "    end")'''

if old_backspace in content:
    content = content.replace(old_backspace, new_backspace)
    print("✓ Backspace/Delete 选区删除逻辑更新成功")
else:
    print("ERROR: 未找到 Backspace/Delete 处理块")

# ============================================================
# 5. 在 Left/Right 普通移动时重置 anchor
# ============================================================

old_left_right = '''  table.insert(lines,  "  elseif k == NebulaKey.Left then")
  table.insert(lines,  "    self.visual.gap_buf:move_cursor_left()")
  table.insert(lines,  "    changed = true")
  table.insert(lines,  "  elseif k == NebulaKey.Right then")
  table.insert(lines,  "    self.visual.gap_buf:move_cursor_right()")
  table.insert(lines,  "    changed = true")'''

new_left_right = '''  table.insert(lines,  "  elseif k == NebulaKey.Left then")
  table.insert(lines,  "    self.visual.gap_buf:move_cursor_left()")
  table.insert(lines,  "    self.selection_anchor = (@uint32)(self.visual.gap_buf:cursor())")
  table.insert(lines,  "    changed = true")
  table.insert(lines,  "  elseif k == NebulaKey.Right then")
  table.insert(lines,  "    self.visual.gap_buf:move_cursor_right()")
  table.insert(lines,  "    self.selection_anchor = (@uint32)(self.visual.gap_buf:cursor())")
  table.insert(lines,  "    changed = true")'''

if old_left_right in content:
    content = content.replace(old_left_right, new_left_right)
    print("✓ Left/Right anchor 重置逻辑更新成功")
else:
    print("ERROR: 未找到 Left/Right 处理块")

# ============================================================
# 6. 在 nebula_gen_text_buffer 函数中注入 selection_anchor 和 is_dragging 字段
#    找到 get_text 方法的生成代码前，注入字段声明
# ============================================================

old_get_text_comment = '''  -- -------------------------------------------------------------------------
  -- ★ Phase 3.6.2: get_text(out, max) -> uint16
  --
  -- 将 Gap Buffer 内容展平到调用方提供的栈上缓冲区。
  -- 不再写入 visual.flat_buf（修复 L1/L2 渗透，公理 B）。
  -- 调用方负责声明临时缓冲区，函数返回后缓冲区随调用帧消亡。
  -- -------------------------------------------------------------------------'''

new_get_text_comment = '''  -- -------------------------------------------------------------------------
  -- ★ Phase 3.6.3: 注入选区状态字段到 InputContext（L1 持久层）
  --
  -- selection_anchor : uint32 — 选区固定端（鼠标按下时的光标位置）
  --   · 与 gap_buf.gap_start（活动端）共同定义选区 [min, max)
  --   · 当 anchor == cursor 时，无活动选区
  --   · 初始值为 0（与 gap_start 初始值一致，表示无选区）
  --
  -- is_dragging : boolean — 鼠标拖拽选区进行中标志
  --   · 在 just_clicked 时置 true，mouse_left_released 时置 false
  --   · 拖拽期间每帧更新光标（anchor 保持不动）
  -- -------------------------------------------------------------------------
  table.insert(lines, ("-- [editable/selection] %s: selection state fields (Phase 3.6.3)"):format(ctx))
  table.insert(lines, ("function %s:init_selection(): void"):format(ctx))
  table.insert(lines,  "  self.selection_anchor = 0")
  table.insert(lines,  "  self.is_dragging      = false")
  table.insert(lines,  "end")
  -- ★ Phase 3.6.3: has_selection() — 检查是否有活动选区
  table.insert(lines, ("-- [editable/selection] %s: has_selection (Phase 3.6.3)"):format(ctx))
  table.insert(lines, ("function %s:has_selection(): boolean"):format(ctx))
  table.insert(lines,  "  return self.selection_anchor ~= (@uint32)(self.visual.gap_buf:cursor())")
  table.insert(lines,  "end")
  -- ★ Phase 3.6.3: get_selection() — 返回规范化选区 [sel_start, sel_end)
  table.insert(lines, ("-- [editable/selection] %s: get_selection (Phase 3.6.3)"):format(ctx))
  table.insert(lines, ("function %s:get_selection(sel_start: *uint32, sel_end: *uint32): void"):format(ctx))
  table.insert(lines,  "  local cur = (@uint32)(self.visual.gap_buf:cursor())")
  table.insert(lines,  "  local anc = self.selection_anchor")
  table.insert(lines,  "  $sel_start = cur < anc and cur or anc")
  table.insert(lines,  "  $sel_end   = cur < anc and anc or cur")
  table.insert(lines,  "end")
  -- ★ Phase 3.6.3: clear_selection() — 清除选区（anchor 同步到当前光标）
  table.insert(lines, ("-- [editable/selection] %s: clear_selection (Phase 3.6.3)"):format(ctx))
  table.insert(lines, ("function %s:clear_selection(): void"):format(ctx))
  table.insert(lines,  "  self.selection_anchor = (@uint32)(self.visual.gap_buf:cursor())")
  table.insert(lines,  "end")
  -- -------------------------------------------------------------------------
  -- ★ Phase 3.6.2: get_text(out, max) -> uint16
  --
  -- 将 Gap Buffer 内容展平到调用方提供的栈上缓冲区。
  -- 不再写入 visual.flat_buf（修复 L1/L2 渗透，公理 B）。
  -- 调用方负责声明临时缓冲区，函数返回后缓冲区随调用帧消亡。
  -- -------------------------------------------------------------------------'''

if old_get_text_comment in content:
    content = content.replace(old_get_text_comment, new_get_text_comment)
    print("✓ selection_anchor/is_dragging 字段注入成功")
else:
    print("ERROR: 未找到 get_text 注释块")

# ============================================================
# 7. 更新版本号
# ============================================================
content = content.replace(
    'return "nebula_interaction_factory_v0.5_phase3.6.2"',
    'return "nebula_interaction_factory_v0.6_phase3.6.3"'
)
print("✓ 版本号更新为 v0.6_phase3.6.3")

with open('/home/ubuntu/nebula/src/derive/interaction_factory.lua', 'w', encoding='utf-8') as f:
    f.write(content)

print("\n✅ interaction_factory.lua 写入完成")
