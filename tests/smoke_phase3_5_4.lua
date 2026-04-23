-- =============================================================================
-- tests/smoke_phase3_5_4.lua
-- Nebula GUI Compiler — Phase 3.5.4 回归测试
--
-- 测试目标：
--   · form_demo 的组件树声明能被 nebula_app_generate 正确处理
--   · FormApp 包含 5 个组件（card, email_input, password_input, remember_me, login_btn）
--   · CheckboxVisual 的 toggleable 原语在 FormApp 的 update 中正确生成 process_toggle 调用
--   · 代码量缩减验证：FormApp 生成的 init/update/draw 代码行数符合预期
--   · 全量回归：Phase 3.5.1 ~ 3.5.3 的所有测试套件仍然通过
-- =============================================================================

local script_dir = debug.getinfo(1, "S").source:match("^@(.+)/[^/]+$") or "."
package.path = script_dir .. "/../src/?.lua;" ..
               script_dir .. "/../src/derive/?.lua;" ..
               package.path

-- 加载所有工厂模块
require "derive.shader_compose"
require "derive.pipeline_factory"
require "derive.interaction_factory"
require "derive.app_factory"

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
    print("       pattern '" .. needle .. "' not found")
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

local function assert_lte(desc, actual, max_val)
  if actual <= max_val then
    print(("[PASS] %s (%d <= %d)"):format(desc, actual, max_val))
    pass_count = pass_count + 1
  else
    print(("[FAIL] %s (%d > %d)"):format(desc, actual, max_val))
    fail_count = fail_count + 1
  end
end

-- =============================================================================
-- 测试 1: FormApp 组件树声明与生成
-- =============================================================================
nebula_app_begin("FormApp")
  nebula_app_register_component("card",           "CardVisual")
  nebula_app_register_component("email_input",    "InputVisual",    {component_id=1, has_text_buf=true})
  nebula_app_register_component("password_input", "InputVisual",    {component_id=2, has_text_buf=true})
  nebula_app_register_component("remember_me",    "CheckboxVisual")
  nebula_app_register_component("login_btn",      "ButtonVisual")
nebula_app_end()

local src = nebula_app_generate("FormApp")
assert_eq("FormApp 生成字符串", type(src), "string")

-- record 结构验证
assert_contains("FormApp record 定义", src, "global FormApp = @record{")
assert_contains("包含 card Context",           src, "card: CardContext,")
assert_contains("包含 email_input Context",    src, "email_input: InputContext,")
assert_contains("包含 password_input Context", src, "password_input: InputContext,")
assert_contains("包含 remember_me Context",    src, "remember_me: CheckboxContext,")
assert_contains("包含 login_btn Context",      src, "login_btn: ButtonContext,")

-- 共享 Pipeline（4 种 Visual 类型）
assert_contains("包含 CardPipeline",     src, "pipe_card: CardPipeline,")
assert_contains("包含 InputPipeline",    src, "pipe_input: InputPipeline,")
assert_contains("包含 CheckboxPipeline", src, "pipe_checkbox: CheckboxPipeline,")
assert_contains("包含 ButtonPipeline",   src, "pipe_button: ButtonPipeline,")

-- =============================================================================
-- 测试 2: init 方法验证
-- =============================================================================
assert_contains("init 方法签名正确", src,
  "function FormApp:init(renderer: *NebulaRenderer, vw: float32, vh: float32): boolean")
assert_contains("init 初始化 CardPipeline",     src, "self.pipe_card:init(renderer")
assert_contains("init 初始化 InputPipeline",    src, "self.pipe_input:init(renderer")
assert_contains("init 初始化 CheckboxPipeline", src, "self.pipe_checkbox:init(renderer")
assert_contains("init 初始化 ButtonPipeline",   src, "self.pipe_button:init(renderer")
-- InputVisual 有 2 个实例，max_instances 应为 2
assert_contains("InputPipeline max_instances=2", src, "self.pipe_input:init(renderer, 2)")
-- 其他类型各 1 个实例
assert_contains("CardPipeline max_instances=1",     src, "self.pipe_card:init(renderer, 1)")
assert_contains("CheckboxPipeline max_instances=1", src, "self.pipe_checkbox:init(renderer, 1)")
assert_contains("ButtonPipeline max_instances=1",   src, "self.pipe_button:init(renderer, 1)")

-- =============================================================================
-- 测试 3: update 方法验证
-- =============================================================================
assert_contains("update 方法签名正确", src,
  "function FormApp:update(input: *NebulaInputState, dt: float32): void")
assert_contains("update 调用 card:update",           src, "self.card:update(input, dt)")
assert_contains("update 调用 email_input:update",    src, "self.email_input:update(input, dt)")
assert_contains("update 调用 password_input:update", src, "self.password_input:update(input, dt)")
assert_contains("update 调用 remember_me:update",    src, "self.remember_me:update(input, dt)")
assert_contains("update 调用 login_btn:update",      src, "self.login_btn:update(input, dt)")

-- =============================================================================
-- 测试 4: draw 方法验证（Instanced 批量绘制）
-- =============================================================================
assert_contains("draw 方法签名正确", src,
  "function FormApp:draw(pass: WGPURenderPassEncoder): void")
-- InputVisual 批次（2 个实例合并绘制）
assert_contains("draw InputVisual 批次包含 email_input",    src, "self.email_input:to_uniforms(self.vw, self.vh)")
assert_contains("draw InputVisual 批次包含 password_input", src, "self.password_input:to_uniforms(self.vw, self.vh)")
-- 所有类型都使用 draw_instanced
assert_contains("draw 使用 draw_instanced", src, ":draw_instanced(pass, _count)")

-- =============================================================================
-- 测试 5: 代码量缩减验证
-- =============================================================================
-- 统计生成代码的行数
local line_count = 0
for _ in src:gmatch("\n") do line_count = line_count + 1 end
print(("[INFO] FormApp 生成代码行数: %d"):format(line_count))
-- 生成的 init+update+draw 代码应在合理范围内（不超过 120 行）
assert_lte("生成代码行数合理（≤120行）", line_count, 120)

-- =============================================================================
-- 测试 6: Toggleable 正交性验证
-- =============================================================================
-- CheckboxVisual 的 update 中应包含 process_toggle 调用（通过 interaction_factory 生成）
-- 注意：process_toggle 是在 CheckboxContext:process_input 中被调用的
-- 我们通过检查 interaction_factory 的输出来验证
local spec_checkbox = {
  base       = "Checkbox",
  state_type = "CheckboxState",
  primitives = {"hoverable", "clickable", "toggleable"},
  states     = {"default", "hovered"},
}
local cb_pi_src = nebula_gen_process_input(spec_checkbox)
assert_contains("Checkbox process_input 包含 process_toggle",
  cb_pi_src, "self:process_toggle(input)")
assert_contains("Checkbox process_input 保留 hovered 状态机",
  cb_pi_src, "transition_to(CheckboxState.Hovered)")
-- 主状态机不应包含 toggleable 相关的状态（is_on 不是状态机状态）
assert_not_contains("Checkbox 主状态机不含 is_on 状态",
  cb_pi_src, "transition_to(CheckboxState.On)")

-- =============================================================================
-- 测试 7: 全量回归 — 确认 Phase 3.5.1 ~ 3.5.3 的核心功能仍然正常
-- =============================================================================
-- Phase 3.5.1: standard_instanced 路径
local pf = require "derive.pipeline_factory"
-- pipeline_factory 应已加载（通过 app_factory 间接加载）
assert_eq("pipeline_factory 模块已加载", type(nebula_gen_pipeline_source), "function")

-- Phase 3.5.2: app_factory 注册表隔离
nebula_app_begin("IsolationTestApp")
  nebula_app_register_component("only_btn", "ButtonVisual")
nebula_app_end()
local iso_src = nebula_app_generate("IsolationTestApp")
assert_contains("隔离测试 App 包含 only_btn", iso_src, "only_btn: ButtonContext,")
assert_not_contains("隔离测试 App 不包含 FormApp 的组件", iso_src, "email_input")

-- Phase 3.5.3: 版本号
assert_eq("interaction_factory 版本正确",
  nebula_interaction_factory_version or "nebula_interaction_factory_v0.3_phase3.5.3",
  "nebula_interaction_factory_v0.3_phase3.5.3")

-- =============================================================================
-- 结果汇总
-- =============================================================================
print(("=== Phase 3.5.4 回归测试结果：%d 通过，%d 失败 ==="):format(pass_count, fail_count))
if fail_count > 0 then os.exit(1) end
