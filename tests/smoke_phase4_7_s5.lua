-- =============================================================================
-- smoke_phase4_7_s5.lua
-- Nebula GUI Compiler — Phase 4.7-S5 Smoke Test
--
-- Undo/Redo 架构验证：
--   · NebulaKey.Undo / NebulaKey.Redo 枚举值存在
--   · app.nelua Ctrl+Z / Ctrl+Y / Ctrl+Shift+Z 键映射
--   · NebulaUndoEntry record + op 常量
--   · NebulaUndoStack 类型生成（push/can_undo/can_redo/peek/step/clear）
--   · interaction_factory.lua: process_text_input 中的 undo 记录 + undo/redo 处理
--   · gap_buffer_factory.lua 版本号更新
--   · nebula_inject_buffers 自动注入 undo stack
--   · dynamic_context_fields 注入到 Context record
-- =============================================================================

-- 测试基础设施
local pass_count = 0
local fail_count = 0

local function check(desc, cond)
  if cond then
    pass_count = pass_count + 1
    print(("  [PASS] %s"):format(desc))
  else
    fail_count = fail_count + 1
    print(("  [FAIL] %s"):format(desc))
  end
end

-- ---- 读取源文件 ----
local function read_file(path)
  local f = io.open(path, "r")
  assert(f, "cannot open " .. path)
  local s = f:read("*a")
  f:close()
  return s
end

local types_src     = read_file("src/nebula_types.nelua")
local core_src      = read_file("src/nebula_core.nelua")
local app_src       = read_file("src/app.nelua")
local interact_src  = read_file("src/derive/interaction_factory.lua")
local gbf_src       = read_file("src/derive/gap_buffer_factory.lua")

print("=== Phase 4.7-S5: Undo/Redo Architecture ===")
print("")

-- ---- 1. NebulaKey 枚举扩展 ----
print("--- 1. NebulaKey Enum ---")
check("NebulaKey.Undo defined (= 22)",
  types_src:find("Undo%s*=%s*22") ~= nil)
check("NebulaKey.Redo defined (= 23)",
  types_src:find("Redo%s*=%s*23") ~= nil)

-- ---- 2. app.nelua 键映射 ----
print("")
print("--- 2. Key Mapping in app.nelua ---")
check("Ctrl+Z mapped to Undo",
  app_src:find("NebulaKey%.Undo") ~= nil)
check("Ctrl+Y mapped to Redo",
  app_src:find("key == GLFW_KEY_Y then nk = NebulaKey%.Redo") ~= nil or
  app_src:find("key == 89 then nk = NebulaKey%.Redo") ~= nil)
check("Ctrl+Shift+Z mapped to Redo",
  app_src:find("shift_down then") ~= nil and
  app_src:find("NebulaKey%.Redo") ~= nil)
check("GLFW_KEY_Z = 90 used for Ctrl+Z",
  app_src:find("key == 90") ~= nil or app_src:find("key == GLFW_KEY_Z") ~= nil)

-- ---- 3. gap_buffer_factory 版本 + undo stack 生成 ----
print("")
print("--- 3. Undo Stack Type Generation ---")
check("gap_buffer_factory version updated to v0.4",
  gbf_src:find("v0.4_phase4.7_s6") ~= nil)
check("nebula_gen_undo_stack_type function exists",
  gbf_src:find("function nebula_gen_undo_stack_type") ~= nil)
check("NebulaUndoEntry record generated",
  gbf_src:find("NebulaUndoEntry = @record") ~= nil)
check("NEBULA_UNDO_OP_INSERT constant (= 1)",
  gbf_src:find("NEBULA_UNDO_OP_INSERT.*= 1") ~= nil)
check("NEBULA_UNDO_OP_DELETE constant (= 2)",
  gbf_src:find("NEBULA_UNDO_OP_DELETE.*= 2") ~= nil)
check("NEBULA_UNDO_OP_NEWLINE constant (= 3)",
  gbf_src:find("NEBULA_UNDO_OP_NEWLINE.*= 3") ~= nil)
check("NEBULA_UNDO_OP_MERGE_LINE constant (= 4)",
  gbf_src:find("NEBULA_UNDO_OP_MERGE_LINE.*= 4") ~= nil)
check("UndoEntry has op field",
  gbf_src:find("op:%s*uint8") ~= nil)
check("UndoEntry has cursor_pos field",
  gbf_src:find("cursor_pos:%s*uint32") ~= nil)
check("UndoEntry has cursor_row field",
  gbf_src:find("cursor_row:%s*uint32") ~= nil)
check("UndoEntry has data_offset field",
  gbf_src:find("data_offset:%s*uint32") ~= nil)
check("UndoEntry has data_len field",
  gbf_src:find("data_len:%s*uint16") ~= nil)
check("UndoEntry has anchor field",
  gbf_src:find("anchor:%s*uint32") ~= nil)

-- Stack methods
check("UndoStack has :init() method",
  gbf_src:find("function.*UndoStack.*:init%(%)") ~= nil)
check("UndoStack has :push() method",
  gbf_src:find("function.*UndoStack.*:push%(") ~= nil)
check("UndoStack has :can_undo() method",
  gbf_src:find("function.*UndoStack.*:can_undo%(%)") ~= nil)
check("UndoStack has :can_redo() method",
  gbf_src:find("function.*UndoStack.*:can_redo%(%)") ~= nil)
check("UndoStack has :peek_undo() method",
  gbf_src:find("function.*UndoStack.*:peek_undo%(%)") ~= nil)
check("UndoStack has :peek_redo() method",
  gbf_src:find("function.*UndoStack.*:peek_redo%(%)") ~= nil)
check("UndoStack has :step_undo() method",
  gbf_src:find("function.*UndoStack.*:step_undo%(%)") ~= nil)
check("UndoStack has :step_redo() method",
  gbf_src:find("function.*UndoStack.*:step_redo%(%)") ~= nil)
check("UndoStack has :get_data() method",
  gbf_src:find("function.*UndoStack.*:get_data%(") ~= nil)
check("UndoStack has :clear() method",
  gbf_src:find("function.*UndoStack.*:clear%(%)") ~= nil)
check("Push truncates redo history",
  gbf_src:find("self%.count = self%.cursor") ~= nil)
check("Stack prevents duplicate NebulaUndoEntry emission",
  gbf_src:find("_nebula_undo_entry_emitted") ~= nil)

-- ---- 4. interaction_factory: undo recording in process_text_input ----
print("")
print("--- 4. Undo Recording in process_text_input ---")
check("process_text_input references undo_stack:push",
  interact_src:find("undo_stack:push") ~= nil)
check("Insert records UNDO_OP_INSERT",
  interact_src:find("NEBULA_UNDO_OP_INSERT") ~= nil)
check("Delete records UNDO_OP_DELETE",
  interact_src:find("NEBULA_UNDO_OP_DELETE") ~= nil)
check("Undo key handled in process_text_input",
  interact_src:find("NebulaKey%.Undo") ~= nil)
check("Redo key handled in process_text_input",
  interact_src:find("NebulaKey%.Redo") ~= nil)
check("Undo checks can_undo()",
  interact_src:find("undo_stack:can_undo") ~= nil)
check("Redo checks can_redo()",
  interact_src:find("undo_stack:can_redo") ~= nil)
check("Undo peeks entry",
  interact_src:find("undo_stack:peek_undo") ~= nil)
check("Redo peeks entry",
  interact_src:find("undo_stack:peek_redo") ~= nil)
check("Undo steps back",
  interact_src:find("undo_stack:step_undo") ~= nil)
check("Redo steps forward",
  interact_src:find("undo_stack:step_redo") ~= nil)
check("Undo insert reverses with delete_range",
  interact_src:find("Undo insert = delete the inserted bytes") ~= nil)
check("Undo delete reverses with re-insert",
  interact_src:find("Undo delete = re%-insert the deleted bytes") ~= nil)
check("Redo insert re-applies insert",
  interact_src:find("Redo insert = re%-insert the bytes") ~= nil)
check("Redo delete re-applies delete",
  interact_src:find("Redo delete = re%-delete the bytes") ~= nil)
-- Backspace records deleted content
check("Backspace saves deleted bytes for undo",
  interact_src:find("_bs_buf") ~= nil)
-- Delete forward records deleted content
check("Delete forward saves deleted bytes for undo",
  interact_src:find("_df_buf") ~= nil)
-- Cut records deleted content
check("Cut records delete for undo",
  interact_src:find("_cut_buf") ~= nil and interact_src:find("_cut_len") ~= nil)
-- Paste records inserted content
check("Paste records insert for undo",
  interact_src:find("_paste_buf") ~= nil)
-- Selection delete before insert also recorded
check("Selection delete before char insert recorded",
  interact_src:find("_undo_sel_data") ~= nil)

-- ---- 5. editable primitive: dynamic_context_fields + factory ----
print("")
print("--- 5. Editable Primitive Integration ---")
check("editable has dynamic_context_fields function",
  interact_src:find("dynamic_context_fields = function") ~= nil)
check("dynamic_context_fields returns undo_stack field",
  interact_src:find('name = "undo_stack"') ~= nil)
check("editable factory injects undo stack type",
  interact_src:find("nebula_gen_undo_stack_type") ~= nil)
check("editable factory stores _undo_stack_type in reg",
  interact_src:find("_undo_stack_type") ~= nil)

-- ---- 6. nebula_core: dynamic context field injection ----
print("")
print("--- 6. Context Record Dynamic Field Injection ---")
check("nebula_core injects dynamic context fields",
  core_src:find("dynamic_context_fields") ~= nil)
check("nebula_core resolves primitives for dynamic fields",
  core_src:find("resolved_prims") ~= nil)
check("nebula_core calls dynamic_context_fields init",
  core_src:find("Phase 4.7%-S5: 初始化动态 context 字段") ~= nil)

-- ---- 7. nebula_inject_buffers: undo stack injection ----
print("")
print("--- 7. Sugar: nebula_inject_buffers ---")
check("nebula_inject_buffers injects undo stack",
  core_src:find("nebula_gen_undo_stack_type") ~= nil)
check("nebula_inject_buffers prints undo injection message",
  core_src:find('%[sugar%] injected.*undo') ~= nil or
  core_src:find('injected %%s.*undo') ~= nil)

-- ---- 8. Functional: undo stack type generation output ----
print("")
print("--- 8. Functional: Type Generation ---")
-- Actually call the generator and verify output
dofile("src/derive/gap_buffer_factory.lua")
local undo_type, undo_src = nebula_gen_undo_stack_type(64, 2048)
check("Generator returns type name",
  undo_type == "NebulaUndoStack64_2048")
check("Generator returns non-empty source",
  undo_src ~= nil and #undo_src > 0)
check("Generated source contains record definition",
  undo_src:find("global NebulaUndoStack64_2048 = @record") ~= nil)
check("Generated source contains entries array",
  undo_src:find("%[64%]NebulaUndoEntry") ~= nil)
check("Generated source contains data pool",
  undo_src:find("%[2048%]uint8") ~= nil)
check("Generated source contains init method",
  undo_src:find("function NebulaUndoStack64_2048:init") ~= nil)
check("Generated source contains push method",
  undo_src:find("function NebulaUndoStack64_2048:push") ~= nil)

-- Duplicate call returns empty (idempotent)
local undo_type2, undo_src2 = nebula_gen_undo_stack_type(64, 2048)
check("Duplicate generation returns empty source (idempotent)",
  undo_type2 == "NebulaUndoStack64_2048" and (undo_src2 == nil or #undo_src2 == 0))

-- Different params generate different type
local undo_type3, undo_src3 = nebula_gen_undo_stack_type(32, 1024)
check("Different params generate different type",
  undo_type3 == "NebulaUndoStack32_1024" and undo_src3 ~= nil and #undo_src3 > 0)

-- NebulaUndoEntry is only emitted once
check("NebulaUndoEntry emitted exactly once (guard flag)",
  undo_src3:find("NebulaUndoEntry = @record") == nil)  -- second call should NOT re-emit

-- ---- 总结 ----
print("")
print(("============================================"))
print((" Results: %d/%d passed, %d failed"):format(
  pass_count, pass_count + fail_count, fail_count))
print(("============================================"))

if fail_count > 0 then
  print("[REGRESSION DETECTED] Phase 4.7-S5 smoke test FAILED")
  assert(false, "Phase 4.7-S5 smoke test FAILED")
else
  print("[ALL PASS] Phase 4.7-S5 undo/redo architecture validated")
end
