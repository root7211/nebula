-- =============================================================================
-- smoke_phase3_10_5.lua
-- Nebula GUI Compiler — Phase 3.10.5 专项回归测试
--
-- 验证内容：
--   1. nebula_app_register_text 支持 mode="static" 独立文本标签
--   2. nebula_app_register_text 支持 mode="dynamic" 动态文本标签（updater 函数）
--   3. nebula_app_register_shadow 注册阴影组件
--   4. gen_app_pre_pass 生成 draw_pre_pass 方法
--   5. gen_app_surface_pass 生成 draw_surface_pass 方法
--   6. app_factory.lua 版本标识已更新为 v0.4_phase3.10.5
--   7. 行数收敛验证（app_factory.lua 扩展后仍在合理范围内）
--   8. 向后兼容：旧 bound 模式（Phase 3.9 API）仍然正常工作
-- =============================================================================

local script_dir = debug.getinfo(1, "S").source:match("^@(.+)/[^/]+$") or "."

-- 加载 app_factory
local factory_version = dofile(script_dir .. "/../src/derive/app_factory.lua")

-- ---- 辅助函数 ----
local passed = 0
local failed = 0

local function assert_eq(desc, got, expected)
  if got == expected then
    passed = passed + 1
    print(("[PASS] %s"):format(desc))
  else
    failed = failed + 1
    print(("[FAIL] %s\n       expected: %s\n       got:      %s"):format(desc, tostring(expected), tostring(got)))
  end
end

local function assert_contains(desc, haystack, needle)
  if type(haystack) == "string" and haystack:find(needle, 1, true) then
    passed = passed + 1
    print(("[PASS] %s"):format(desc))
  else
    failed = failed + 1
    print(("[FAIL] %s\n       needle not found: %s"):format(desc, needle))
  end
end

local function assert_not_contains(desc, haystack, needle)
  if type(haystack) == "string" and not haystack:find(needle, 1, true) then
    passed = passed + 1
    print(("[PASS] %s"):format(desc))
  else
    failed = failed + 1
    print(("[FAIL] %s\n       unexpected needle found: %s"):format(desc, needle))
  end
end

local function assert_le(desc, got, limit)
  if type(got) == "number" and got <= limit then
    passed = passed + 1
    print(("[PASS] %s (%d ≤ %d)"):format(desc, got, limit))
  else
    failed = failed + 1
    print(("[FAIL] %s (%s > %d)"):format(desc, tostring(got), limit))
  end
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
-- 1. mode="static" 独立文本标签
-- =============================================================================
print("\n--- 1. mode='static' 独立文本标签 ---")

nebula_app_begin("StaticLabelApp")
  nebula_app_register_component("bg", "CardVisual")
  nebula_app_register_text("title_label", "TextVisual", {
    mode = "static",
  })
  nebula_app_register_text("subtitle_label", "TextVisual", {
    mode = "static",
  })
nebula_app_end()

local gen_static = nebula_app_generate("StaticLabelApp")
assert_eq("static 生成代码是 string", type(gen_static), "string")

-- record 中应包含 TextContext 字段
assert_contains("static: record 包含 title_label TextContext",
  gen_static, "title_label: TextContext")
assert_contains("static: record 包含 subtitle_label TextContext",
  gen_static, "subtitle_label: TextContext")

-- update 中不应生成 process_text_input（static 模式）
assert_not_contains("static: update 不含 process_text_input",
  gen_static, "process_text_input")

-- update 中应有 static 注释
assert_contains("static: update 包含 [static] 注释",
  gen_static, "[static]")

-- draw 中应包含 draw_buffer 调用
assert_contains("static: draw 包含 title_label draw_buffer",
  gen_static, "self.title_label.mesh.vertex_count")

-- pre_pass 和 surface_pass 应为空实现（无阴影组件）
assert_contains("static: draw_pre_pass 方法存在",
  gen_static, "function StaticLabelApp:draw_pre_pass")
assert_contains("static: draw_surface_pass 方法存在",
  gen_static, "function StaticLabelApp:draw_surface_pass")
assert_not_contains("static: draw_pre_pass 无阴影调用",
  gen_static, "draw_shadow")

-- =============================================================================
-- 2. mode="dynamic" 动态文本标签（updater 函数）
-- =============================================================================
print("\n--- 2. mode='dynamic' 动态文本标签 ---")

nebula_app_begin("DynamicLabelApp")
  nebula_app_register_component("bg", "CardVisual")
  nebula_app_register_text("fps_label", "TextVisual", {
    mode    = "dynamic",
    updater = "get_fps_string",
  })
  nebula_app_register_text("time_label", "TextVisual", {
    mode    = "dynamic",
    updater = "get_time_string",
  })
nebula_app_end()

local gen_dynamic = nebula_app_generate("DynamicLabelApp")
assert_eq("dynamic 生成代码是 string", type(gen_dynamic), "string")

-- update 中应包含 updater 调用
assert_contains("dynamic: update 包含 get_fps_string 调用",
  gen_dynamic, "get_fps_string(&self.arena)")
assert_contains("dynamic: update 包含 get_time_string 调用",
  gen_dynamic, "get_time_string(&self.arena)")

-- update 中应包含 arena mark/rewind（局部内存管理）
assert_contains("dynamic: update 包含 nebula_arena_mark",
  gen_dynamic, "nebula_arena_mark")
assert_contains("dynamic: update 包含 nebula_arena_rewind",
  gen_dynamic, "nebula_arena_rewind")

-- update 中不应包含 process_text_input（dynamic 模式不绑定 editable）
assert_not_contains("dynamic: update 不含 process_text_input",
  gen_dynamic, "process_text_input")

-- draw 中应包含 draw_buffer 调用
assert_contains("dynamic: draw 包含 fps_label draw_buffer",
  gen_dynamic, "self.fps_label.mesh.vertex_count")

-- =============================================================================
-- 3. nebula_app_register_shadow 注册阴影组件
-- =============================================================================
print("\n--- 3. nebula_app_register_shadow 阴影组件注册 ---")

nebula_app_begin("ShadowApp")
  nebula_app_register_shadow("shadow_btn", "ShadowButtonVisual", {
    blur_radius = 12.0,
    win_w = 960,
    win_h = 640,
  })
nebula_app_end()

local gen_shadow = nebula_app_generate("ShadowApp")
assert_eq("shadow 生成代码是 string", type(gen_shadow), "string")

-- record 中应包含 ShadowButtonContext 和 ShadowButtonPipeline
assert_contains("shadow: record 包含 shadow_btn Context",
  gen_shadow, "shadow_btn: ShadowButtonContext")
assert_contains("shadow: record 包含 ShadowButtonPipeline",
  gen_shadow, "pipe_shadowbutton: ShadowButtonPipeline")

-- init 中应包含 pipe_shadowbutton:init(renderer, 960, 640)
assert_contains("shadow: init 包含 pipe_shadowbutton:init",
  gen_shadow, "self.pipe_shadowbutton:init(renderer, 960, 640)")

-- draw_pre_pass 中应包含 draw_shadow 调用
assert_contains("shadow: draw_pre_pass 包含 draw_shadow",
  gen_shadow, "draw_shadow")
assert_contains("shadow: draw_pre_pass 包含 blur_radius 12.0",
  gen_shadow, "12.0")

-- draw_surface_pass 中应包含 draw_composite 和 draw 调用
assert_contains("shadow: draw_surface_pass 包含 draw_composite",
  gen_shadow, "draw_composite")
assert_contains("shadow: draw_surface_pass 包含 draw(pass)",
  gen_shadow, "pipe_shadowbutton:draw(pass)")

-- =============================================================================
-- 4. 向后兼容：旧 bound 模式（Phase 3.9 API）
-- =============================================================================
print("\n--- 4. 向后兼容：旧 bound 模式 ---")

nebula_app_begin("BoundTextApp")
  nebula_app_register_component("input_box", "InputVisual")
  nebula_app_register_text("input_label", "TextVisual", {
    bound_to = "input_box",
    placeholder = "请输入...",
  })
nebula_app_end()

local gen_bound = nebula_app_generate("BoundTextApp")
assert_eq("bound 生成代码是 string", type(gen_bound), "string")

-- update 中应包含 process_text_input（bound 模式）
assert_contains("bound: update 包含 process_text_input",
  gen_bound, "process_text_input")

-- update 中应包含 placeholder
assert_contains("bound: update 包含 placeholder",
  gen_bound, "请输入...")

-- draw 中应包含 draw_buffer
assert_contains("bound: draw 包含 input_label draw_buffer",
  gen_bound, "self.input_label.mesh.vertex_count")

-- =============================================================================
-- 5. 混合模式：同一 App 中同时使用 static + bound + shadow
-- =============================================================================
print("\n--- 5. 混合模式：static + bound + shadow 共存 ---")

nebula_app_begin("MixedApp")
  nebula_app_register_component("card", "CardVisual")
  nebula_app_register_component("input_box", "InputVisual")
  nebula_app_register_text("page_title", "TextVisual", {
    mode = "static",
  })
  nebula_app_register_text("input_label", "TextVisual", {
    bound_to = "input_box",
    placeholder = "Enter text",
  })
  nebula_app_register_shadow("card_shadow", "ShadowButtonVisual", {
    blur_radius = 8.0,
    win_w = 800,
    win_h = 600,
  })
nebula_app_end()

local gen_mixed = nebula_app_generate("MixedApp")
assert_eq("mixed 生成代码是 string", type(gen_mixed), "string")

-- record 应包含所有字段
assert_contains("mixed: record 包含 page_title",
  gen_mixed, "page_title: TextContext")
assert_contains("mixed: record 包含 input_label",
  gen_mixed, "input_label: TextContext")
assert_contains("mixed: record 包含 card_shadow",
  gen_mixed, "card_shadow: ShadowButtonContext")

-- update 应同时包含 static 注释和 bound 的 process_text_input
assert_contains("mixed: update 包含 [static] 注释",
  gen_mixed, "[static]")
assert_contains("mixed: update 包含 process_text_input",
  gen_mixed, "process_text_input")

-- draw_pre_pass 应包含 draw_shadow
assert_contains("mixed: draw_pre_pass 包含 draw_shadow",
  gen_mixed, "draw_shadow")

-- draw_surface_pass 应包含 draw_composite
assert_contains("mixed: draw_surface_pass 包含 draw_composite",
  gen_mixed, "draw_composite")

-- =============================================================================
-- 6. app_factory.lua 版本标识
-- =============================================================================
print("\n--- 6. app_factory.lua 版本标识 ---")
-- ★ Phase 3.12 升级：版本号已更新
assert_contains("app_factory 版本包含 phase 前缀",
  factory_version:sub(1, 26), "nebula_app_factory_v0.7_ph")  -- 兼容 Phase 3.12+

-- =============================================================================
-- 7. 行数收敛验证
-- =============================================================================
print("\n--- 7. 行数收敛验证 ---")
local factory_lines = count_lines(script_dir .. "/../src/derive/app_factory.lua")
if factory_lines then
  print(("  app_factory.lua: %d 行"):format(factory_lines))
  assert_le("app_factory.lua ≤ 1100 行（Phase 4.2.2-fix 新增 deinit）", factory_lines, 1100)
else
  failed = failed + 1
  print("[FAIL] 无法读取 src/derive/app_factory.lua")
end

local app_nelua_lines = count_lines(script_dir .. "/../src/app.nelua")
if app_nelua_lines then
  print(("  app.nelua: %d 行"):format(app_nelua_lines))
  assert_le("app.nelua ≤ 520 行（Phase 4.X: Ctrl+C/V/X/A 剪贴板快捷键）", app_nelua_lines, 520)  -- ★ Phase 3.12 升级
else
  failed = failed + 1
  print("[FAIL] 无法读取 src/app.nelua")
end

-- =============================================================================
-- 汇总
-- =============================================================================
print(("\n=== Phase 3.10.5 专项回归测试结果：%d 通过，%d 失败 ==="):format(passed, failed))
if failed > 0 then
  os.exit(1)
end
