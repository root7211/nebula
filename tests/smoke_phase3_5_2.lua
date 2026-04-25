-- =============================================================================
-- tests/smoke_phase3_5_2.lua
-- Nebula GUI Compiler — Phase 3.5.2 回归测试
--
-- 测试目标：
--   · nebula_app_begin / nebula_app_register_component / nebula_app_register_slot /
--     nebula_app_end API 的正确性
--   · nebula_app_generate(app_name) 生成的代码正确性：
--       - <App> record 包含所有 Context 和共享 Pipeline
--       - <App>:init 初始化所有管线并调用 update_viewport
--       - <App>:update 按注册顺序显式调用每个组件的 update
--       - <App>:draw 按类型分组，生成 upload + draw_instanced 批量绘制代码
--       - 动态插槽的数据收集代码正确嵌入
-- =============================================================================

-- 设置正确的模块搜索路径
local script_dir = debug.getinfo(1, "S").source:match("^@(.+)/[^/]+$") or "."
package.path = script_dir .. "/../src/?.lua;" ..
               script_dir .. "/../src/derive/?.lua;" ..
               package.path

-- 加载 app_factory 模块
local app_factory_ver = require "derive.app_factory"

-- =============================================================================
-- 测试工具
-- =============================================================================
local pass_count = 0
local fail_count = 0

local function assert_eq(desc, actual, expected)
  if actual == expected then
    print("[PASS] " .. desc)
    pass_count = pass_count + 1
  else
    print("[FAIL] " .. desc)
    print("       expected: " .. tostring(expected))
    print("       actual:   " .. tostring(actual))
    fail_count = fail_count + 1
  end
end

local function assert_contains(desc, haystack, needle)
  if type(haystack) == "string" and haystack:find(needle, 1, true) then
    print("[PASS] " .. desc)
    pass_count = pass_count + 1
  else
    print("[FAIL] " .. desc)
    print("       pattern '" .. needle .. "' not found in:")
    print("       " .. tostring(haystack):sub(1, 200))
    fail_count = fail_count + 1
  end
end

local function assert_not_contains(desc, haystack, needle)
  if type(haystack) == "string" and not haystack:find(needle, 1, true) then
    print("[PASS] " .. desc)
    pass_count = pass_count + 1
  else
    print("[FAIL] " .. desc)
    print("       pattern '" .. needle .. "' should NOT be found")
    fail_count = fail_count + 1
  end
end

-- =============================================================================
-- 测试 1: 版本号
-- =============================================================================
-- 版本号随 Phase 演进，仅验证包含 phase3 前缀
assert_contains("app_factory 版本号包含 phase3 前缀", app_factory_ver, "phase3")

-- =============================================================================
-- 测试 2: 基础 API — 注册和生成 LoginApp
-- =============================================================================
nebula_app_begin("LoginApp")
  nebula_app_register_component("card", "CardVisual")
  nebula_app_register_component("email_input", "InputVisual", {component_id=1, has_text_buf=true})
  nebula_app_register_component("password_input", "InputVisual", {component_id=2, has_text_buf=true})
  nebula_app_register_component("login_btn", "ButtonVisual")
nebula_app_end()

local source = nebula_app_generate("LoginApp")
assert_eq("nebula_app_generate 返回字符串", type(source), "string")

-- record 定义
assert_contains("生成 LoginApp record", source, "global LoginApp = @record{")
assert_contains("包含 renderer 字段", source, "renderer: *NebulaRenderer,")
assert_contains("包含 vw/vh 字段", source, "vw: float32,")
assert_contains("包含 card Context", source, "card: CardContext,")
assert_contains("包含 email_input Context", source, "email_input: InputContext,")
assert_contains("包含 password_input Context", source, "password_input: InputContext,")
assert_contains("包含 login_btn Context", source, "login_btn: ButtonContext,")

-- 共享 Pipeline（CardVisual, InputVisual, ButtonVisual 各一个）
assert_contains("包含 CardPipeline", source, "pipe_card: CardPipeline,")
assert_contains("包含 InputPipeline", source, "pipe_input: InputPipeline,")
assert_contains("包含 ButtonPipeline", source, "pipe_button: ButtonPipeline,")

-- init 方法
assert_contains("生成 init 方法", source, "function LoginApp:init(renderer: *NebulaRenderer, vw: float32, vh: float32): boolean")
assert_contains("init 初始化 CardPipeline", source, "self.pipe_card:init(renderer")
assert_contains("init 初始化 InputPipeline", source, "self.pipe_input:init(renderer")
assert_contains("init 初始化 ButtonPipeline", source, "self.pipe_button:init(renderer")
assert_contains("init 调用 update_viewport", source, "update_viewport(renderer, vw, vh)")
assert_contains("init 返回 true", source, "return true")

-- update 方法
assert_contains("生成 update 方法", source, "function LoginApp:update(input: *NebulaInputState, dt: float32): void")
assert_contains("update 调用 card:update", source, "self.card:update(input, dt)")
assert_contains("update 调用 email_input:update", source, "self.email_input:update(input, dt)")
assert_contains("update 调用 password_input:update", source, "self.password_input:update(input, dt)")
assert_contains("update 调用 login_btn:update", source, "self.login_btn:update(input, dt)")

-- draw 方法
assert_contains("生成 draw 方法", source, "function LoginApp:draw(pass: WGPURenderPassEncoder): void")
assert_contains("draw 使用 to_uniforms", source, ":to_uniforms(self.vw, self.vh)")
assert_contains("draw 调用 upload", source, ":upload(self.renderer,")
assert_contains("draw 调用 draw_instanced", source, ":draw_instanced(pass, _count)")

-- InputVisual 有两个静态组件，应该在同一批次中
assert_contains("InputVisual 批次包含 email_input", source, "self.email_input:to_uniforms(self.vw, self.vh)")
assert_contains("InputVisual 批次包含 password_input", source, "self.password_input:to_uniforms(self.vw, self.vh)")

-- =============================================================================
-- 测试 3: 动态插槽支持
-- =============================================================================
nebula_app_begin("ListApp")
  nebula_app_register_component("header", "CardVisual")
  nebula_app_register_slot("items", "ListItemVisual", {
    max_instances = 256,
    count_var     = "item_count",
    data_var      = "item_instances",
  })
nebula_app_end()

local list_source = nebula_app_generate("ListApp")
assert_eq("ListApp 生成字符串", type(list_source), "string")
assert_contains("ListApp 包含 header Context", list_source, "header: CardContext,")
assert_contains("ListApp 包含 ListItemPipeline", list_source, "pipe_listitem: ListItemPipeline,")
assert_contains("ListApp init 包含 ListItemPipeline 初始化", list_source, "self.pipe_listitem:init(renderer")
assert_contains("动态插槽 count_var 引用", list_source, "item_count")
assert_contains("动态插槽 data_var 引用", list_source, "item_instances")
assert_contains("动态插槽遍历循环", list_source, "while _si < item_count")
assert_contains("动态插槽数据收集", list_source, "_batch[_count] = item_instances[_si]")

-- =============================================================================
-- 测试 4: max_instances 计算
-- =============================================================================
-- LoginApp: InputVisual 有 2 个静态组件，max_instances 应为 2
assert_contains("InputPipeline max_instances=2", source, "self.pipe_input:init(renderer, 2)")
-- ButtonVisual 有 1 个静态组件，max_instances 应为 1
assert_contains("ButtonPipeline max_instances=1", source, "self.pipe_button:init(renderer, 1)")
-- CardVisual 有 1 个静态组件，max_instances 应为 1
assert_contains("CardPipeline max_instances=1", source, "self.pipe_card:init(renderer, 1)")

-- ListApp: ListItemVisual 有 0 个静态 + 256 个插槽，max_instances 应为 256
assert_contains("ListItemPipeline max_instances=256", list_source, "self.pipe_listitem:init(renderer, 256)")

-- =============================================================================
-- 测试 5: 错误处理
-- =============================================================================
local ok1, err1 = pcall(function()
  nebula_app_generate("NonExistentApp")
end)
assert_eq("未注册 App 应报错", ok1, false)
assert_contains("错误信息包含 app 名", err1, "NonExistentApp")

local ok2, err2 = pcall(function()
  nebula_app_register_component("orphan", "SomeVisual")
end)
assert_eq("在 begin/end 外注册组件应报错", ok2, false)

-- =============================================================================
-- 测试 6: 多次注册不同 App 互不干扰
-- =============================================================================
nebula_app_begin("AppA")
  nebula_app_register_component("btn_a", "ButtonVisual")
nebula_app_end()

nebula_app_begin("AppB")
  nebula_app_register_component("card_b", "CardVisual")
nebula_app_end()

local src_a = nebula_app_generate("AppA")
local src_b = nebula_app_generate("AppB")

assert_contains("AppA 包含 btn_a", src_a, "btn_a: ButtonContext,")
assert_not_contains("AppA 不包含 card_b", src_a, "card_b")
assert_contains("AppB 包含 card_b", src_b, "card_b: CardContext,")
assert_not_contains("AppB 不包含 btn_a", src_b, "btn_a")

-- =============================================================================
-- 结果汇总
-- =============================================================================
print(("=== Phase 3.5.2 回归测试结果：%d 通过，%d 失败 ==="):format(pass_count, fail_count))
if fail_count > 0 then os.exit(1) end
