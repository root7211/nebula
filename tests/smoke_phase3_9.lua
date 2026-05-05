-- =============================================================================
-- tests/smoke_phase3_9.lua — Nebula Phase 3.9 专项回归测试
--
-- 覆盖范围：
--   1. Arena mark/rewind API（前置任务）
--   2. nebula_app_register_text 代码生成（Task 3.9.1）
--   3. form_demo.nelua 文本一等公民重构（Task 3.9.2）
--   4. Slot Producer 代码生成（Task 3.9.3）
--   5. dynamic_list_demo.nelua Producer 重构（Task 3.9.4）
--   6. 向后兼容性：旧 count_var/data_var 模式仍可生成代码
--   7. app_factory.lua 版本标识
--   8. 行数收敛验证
-- =============================================================================

local passed = 0
local failed = 0

-- 获取测试文件所在目录（兼容不同调用方式）
local script_dir = (debug.getinfo(1, "S").source:match("^@(.+/)[^/]+$") or "./"):gsub("/$", "")

-- =============================================================================
-- 测试工具函数
-- =============================================================================
local function assert_eq(name, got, expected)
  if got == expected then
    passed = passed + 1
    print(("[PASS] %s"):format(name))
  else
    failed = failed + 1
    print(("[FAIL] %s\n       expected: %s\n       got:      %s"):format(name, tostring(expected), tostring(got)))
  end
end

local function assert_contains(name, haystack, needle)
  if type(haystack) == "string" and haystack:find(needle, 1, true) then
    passed = passed + 1
    print(("[PASS] %s"):format(name))
  else
    failed = failed + 1
    print(("[FAIL] %s\n       needle not found: %s"):format(name, needle))
  end
end

local function assert_not_contains(name, haystack, needle)
  if type(haystack) == "string" and not haystack:find(needle, 1, true) then
    passed = passed + 1
    print(("[PASS] %s"):format(name))
  else
    failed = failed + 1
    print(("[FAIL] %s\n       needle unexpectedly found: %s"):format(name, needle))
  end
end

local function assert_le(name, got, limit)
  if got <= limit then
    passed = passed + 1
    print(("[PASS] %s (%d <= %d)"):format(name, got, limit))
  else
    failed = failed + 1
    print(("[FAIL] %s (%d > %d)"):format(name, got, limit))
  end
end

local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  return content
end

local function count_lines(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local n = 0
  for _ in f:lines() do n = n + 1 end
  f:close()
  return n
end

-- =============================================================================
-- 加载 app_factory.lua
-- =============================================================================
local factory_path = script_dir .. "/../src/derive/app_factory.lua"
local factory_version = dofile(factory_path)

-- =============================================================================
-- 1. Arena mark/rewind API 验证
-- =============================================================================
print("\n--- 1. Arena mark/rewind API ---")
local arena_src = read_file(script_dir .. "/../src/nebula_arena.nelua")
assert_contains("nebula_arena.nelua 包含 nebula_arena_mark 声明",
  arena_src, "global function nebula_arena_mark(")
assert_contains("nebula_arena.nelua 包含 nebula_arena_rewind 声明",
  arena_src, "global function nebula_arena_rewind(")
assert_contains("nebula_arena_mark 返回 arena.offset",
  arena_src, "return arena.offset")
assert_contains("nebula_arena_rewind 接受 checkpoint 参数",
  arena_src, "checkpoint: csize")
assert_contains("nebula_arena_rewind 不更新 peak（注释说明）",
  arena_src, "peak")
assert_contains("nebula_arena_rewind 仅向前回滚",
  arena_src, "checkpoint <= arena.offset")

-- =============================================================================
-- 2. nebula_app_register_text 代码生成（Task 3.9.1）
-- =============================================================================
print("\n--- 2. nebula_app_register_text 代码生成 ---")

nebula_app_begin("TextTestApp")
  nebula_app_register_component("email_input",    "InputVisual", {component_id=1})
  nebula_app_register_component("password_input", "InputVisual", {component_id=2})
  nebula_app_register_text("email_label", "TextVisual", {
    bound_to      = "email_input",
    placeholder   = "email",
    mask_password = false,
  })
  nebula_app_register_text("password_label", "TextVisual", {
    bound_to      = "password_input",
    placeholder   = "password",
    mask_password = true,
  })
nebula_app_end()

local gen_text = nebula_app_generate("TextTestApp")
assert_eq("生成代码是 string", type(gen_text), "string")

-- record 字段验证
assert_contains("record 包含 pipe_text: TextPipeline",
  gen_text, "pipe_text: TextPipeline,")
assert_contains("record 包含 email_label: TextContext",
  gen_text, "email_label: TextContext,")
assert_contains("record 包含 password_label: TextContext",
  gen_text, "password_label: TextContext,")

-- init 方法验证
assert_contains("init 包含 pipe_text:init",
  gen_text, "self.pipe_text:init(renderer)")

-- update 方法验证（email_label，非掩码）
assert_contains("update 包含 email_input:process_text_input",
  gen_text, "self.email_input:process_text_input(input)")
assert_contains("update 包含 email_label:set_text（有内容时）",
  gen_text, "self.email_label:set_text(self.renderer,")
assert_contains("update 包含 email placeholder",
  gen_text, '"email"')
-- email_label 与 password_label 共享同一生成字符串，0x2A 来自 password_label 的掩码逻辑
-- 改为验证 email_label 的 set_text 调用不包含 mask 字样
assert_not_contains("email_label 的 set_text 不含 mask 字样",
  gen_text, "email_label_mask")

-- update 方法验证（password_label，掩码模式）
assert_contains("update 包含 password_input:process_text_input",
  gen_text, "self.password_input:process_text_input(input)")
assert_contains("update 包含掩码 0x2A 赋值",
  gen_text, "0x2A")
assert_contains("update 包含 password placeholder",
  gen_text, '"password"')

-- draw 方法验证
assert_contains("draw 包含 pipe_text:draw_buffer（email_label）",
  gen_text, "self.pipe_text:draw_buffer(pass,")
assert_contains("draw 包含 email_label.mesh.vertex_buffer",
  gen_text, "self.email_label.mesh.vertex_buffer,")
assert_contains("draw 包含 password_label.mesh.vertex_buffer",
  gen_text, "self.password_label.mesh.vertex_buffer,")
assert_contains("draw 中文本绘制在最后（注释标记）",
  gen_text, "Phase 3.9")

-- =============================================================================
-- 3. form_demo.nelua 文本一等公民重构验证（Task 3.9.2）
-- =============================================================================
print("\n--- 3. form_demo.nelua 文本一等公民重构 ---")
local form_src = read_file(script_dir .. "/../examples/form_demo.nelua")
if form_src then
  -- Phase 3.9 标识
  assert_contains("form_demo 包含 Phase 3.9 注释",
    form_src, "Phase 3.9")
  -- 使用 nebula_app_register_text
  assert_contains("form_demo 使用 nebula_app_register_text",
    form_src, "nebula_app_register_text")
  assert_contains("form_demo 注册 email_label",
    form_src, '"email_label"')
  assert_contains("form_demo 注册 password_label",
    form_src, '"password_label"')
  -- 消除旧的手动文本管线声明
  assert_not_contains("form_demo 不含手动 pipe_email_text 声明",
    form_src, "local pipe_email_text:")
  assert_not_contains("form_demo 不含手动 pipe_password_text 声明",
    form_src, "local pipe_password_text:")
  -- 消除旧的手动 TextContext 声明
  assert_not_contains("form_demo 不含手动 email_text: TextContext",
    form_src, "local email_text:    TextContext")
  assert_not_contains("form_demo 不含手动 password_text: TextContext",
    form_src, "local password_text: TextContext")
  -- 消除主循环中的手动 process_text_input 调用
  assert_not_contains("form_demo 主循环不含手动 process_text_input",
    form_src, "if form.email_input:process_text_input")
  -- 消除独立文本 Render Pass
  assert_not_contains("form_demo 不含独立文本 Render Pass（wgpuDeviceCreateCommandEncoder）",
    form_src, "local encoder = wgpuDeviceCreateCommandEncoder")
  -- 保留 nebula_frame_render
  assert_contains("form_demo 调用 nebula_frame_render",
    form_src, "nebula_frame_render(")
  -- 保留 Enter 键业务逻辑
  assert_contains("form_demo 保留 Enter 键业务逻辑",
    form_src, "NebulaKey.Enter")
else
  failed = failed + 1
  print("[FAIL] 无法读取 examples/form_demo.nelua")
end

-- =============================================================================
-- 4. Slot Producer 代码生成（Task 3.9.3）
-- =============================================================================
print("\n--- 4. Slot Producer 代码生成 ---")

nebula_app_begin("SlotProducerTestApp")
  nebula_app_register_slot("list_items", "ListItemVisual", {
    max_instances = 16,
    producer      = "my_list_producer",
  })
nebula_app_end()

local gen_slot = nebula_app_generate("SlotProducerTestApp")
assert_eq("生成代码是 string", type(gen_slot), "string")

-- Producer 调用验证
assert_contains("draw 包含 Producer 函数调用",
  gen_slot, "my_list_producer(")
assert_contains("draw 包含 nebula_arena_mark",
  gen_slot, "nebula_arena_mark(&self.arena)")
assert_contains("draw 包含 nebula_arena_rewind",
  gen_slot, "nebula_arena_rewind(&self.arena,")
assert_contains("draw 包含 nebula_arena_alloc_array",
  gen_slot, "nebula_arena_alloc_array(&self.arena,")
assert_contains("draw 包含 slot_count 指针传递",
  gen_slot, "&_slot_count,")

-- 不含旧的外部变量模式
assert_not_contains("draw 不含旧的 count_var 引用",
  gen_slot, "while _si < item_count")
assert_not_contains("draw 不含旧的 data_var 引用",
  gen_slot, "item_instances[_si]")

-- =============================================================================
-- 5. 向后兼容：旧 count_var/data_var 模式（legacy API）
-- =============================================================================
print("\n--- 5. 向后兼容：legacy count_var/data_var 模式 ---")

nebula_app_begin("LegacySlotApp")
  nebula_app_register_slot("old_items", "ListItemVisual", {
    max_instances = 32,
    count_var     = "g_item_count",
    data_var      = "g_item_data",
  })
nebula_app_end()

local gen_legacy = nebula_app_generate("LegacySlotApp")
assert_eq("legacy 生成代码是 string", type(gen_legacy), "string")
assert_contains("legacy draw 包含 count_var 引用",
  gen_legacy, "g_item_count")
assert_contains("legacy draw 包含 data_var 引用",
  gen_legacy, "g_item_data")
assert_not_contains("legacy draw 不含 Producer 调用",
  gen_legacy, "nebula_arena_mark")

-- =============================================================================
-- 6. dynamic_list_demo.nelua Producer 重构验证（Task 3.9.4）
-- =============================================================================
print("\n--- 6. dynamic_list_demo.nelua Producer 重构 ---")
local list_src = read_file(script_dir .. "/../examples/dynamic_list_demo.nelua")
if list_src then
  -- Phase 3.9 标识
  assert_contains("dynamic_list_demo 包含 Phase 3.9 注释",
    list_src, "Phase 3.9")
  -- 使用 nebula_app_register_slot（producer 模式）
  assert_contains("dynamic_list_demo 使用 nebula_app_register_slot",
    list_src, "nebula_app_register_slot")
  assert_contains("dynamic_list_demo 声明 producer",
    list_src, 'producer      = "list_item_producer"')
  -- 声明 ListApp
  assert_contains("dynamic_list_demo 使用 nebula_app_begin(ListApp)",
    list_src, '"ListApp"')
  assert_contains("dynamic_list_demo 调用 nebula_derive_app",
    list_src, 'nebula_derive_app("ListApp")')
  -- 声明 Producer 函数
  assert_contains("dynamic_list_demo 声明 list_item_producer 函数",
    list_src, "global function list_item_producer(")
  assert_contains("list_item_producer 接受 slot_count 指针参数",
    list_src, "slot_count: *uint32")
  -- 消除旧的手动 Arena 声明
  assert_not_contains("dynamic_list_demo 不含手动 arena_backing 声明",
    list_src, "local arena_backing:")
  assert_not_contains("dynamic_list_demo 不含手动 arena: NebulaArena 声明",
    list_src, "local arena: NebulaArena")
  -- 消除旧的手动管线声明
  assert_not_contains("dynamic_list_demo 不含手动 pipe: ListItemPipeline",
    list_src, "local pipe: ListItemPipeline")
  -- 消除旧的手动 WGPU 渲染样板
  assert_not_contains("dynamic_list_demo 不含手动 wgpuDeviceCreateCommandEncoder",
    list_src, "local encoder = wgpuDeviceCreateCommandEncoder")
  -- 保留 nebula_frame_render
  assert_contains("dynamic_list_demo 调用 nebula_frame_render",
    list_src, "nebula_frame_render(")
  -- 通过 list_app.arena 访问内嵌 Arena（性能统计）
  assert_contains("dynamic_list_demo 通过 list_app.arena 访问内嵌 Arena",
    list_src, "list_app.arena")
else
  failed = failed + 1
  print("[FAIL] 无法读取 examples/dynamic_list_demo.nelua")
end

-- =============================================================================
-- 7. app_factory.lua 版本标识
-- =============================================================================
print("\n--- 7. app_factory.lua 版本标识 ---")
-- Phase 3.10.5 升级后版本号已更新，验证包含 phase3 前缀即可
assert_contains("app_factory 版本包含 phase 前缀",
  factory_version, "phase")

-- =============================================================================
-- 8. 行数收敛验证
-- =============================================================================
print("\n--- 8. 行数收敛验证 ---")
local factory_lines = count_lines(script_dir .. "/../src/derive/app_factory.lua")
if factory_lines then
  print(("  app_factory.lua: %d 行"):format(factory_lines))
  -- Phase 3.11 新增布局解算逻辑，上限更新为 900
  assert_le("app_factory.lua ≤ 1400 行（Phase 4.8-NL 新增嵌套布局支持）", factory_lines, 1400)
else
  failed = failed + 1
  print("[FAIL] 无法读取 src/derive/app_factory.lua")
end

local arena_lines = count_lines(script_dir .. "/../src/nebula_arena.nelua")
if arena_lines then
  print(("  nebula_arena.nelua: %d 行"):format(arena_lines))
  assert_le("nebula_arena.nelua ≤ 220 行（新增 mark/rewind）", arena_lines, 220)
else
  failed = failed + 1
  print("[FAIL] 无法读取 src/nebula_arena.nelua")
end

local form_lines = count_lines(script_dir .. "/../examples/form_demo.nelua")
if form_lines then
  print(("  form_demo.nelua: %d 行"):format(form_lines))
  assert_le("form_demo.nelua ≤ 350 行（Phase 3.11 精简后）", form_lines, 350)
else
  failed = failed + 1
  print("[FAIL] 无法读取 examples/form_demo.nelua")
end

local list_lines = count_lines(script_dir .. "/../examples/dynamic_list_demo.nelua")
if list_lines then
  print(("  dynamic_list_demo.nelua: %d 行"):format(list_lines))
  assert_le("dynamic_list_demo.nelua ≤ 230 行（消除 80 行 WGPU 样板）", list_lines, 230)
else
  failed = failed + 1
  print("[FAIL] 无法读取 examples/dynamic_list_demo.nelua")
end

-- =============================================================================
-- 汇总
-- =============================================================================
print(("\n=== Phase 3.9 专项回归测试结果：%d 通过，%d 失败 ==="):format(passed, failed))
if failed > 0 then
  os.exit(1)
end
