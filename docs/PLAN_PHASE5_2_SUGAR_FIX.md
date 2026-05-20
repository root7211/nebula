# Phase 5.2：语法糖体系修复

**创建日期**：2026-05-17
**基准文档**：语法糖全面审计报告
**相关文档**：`PLAN_PHASE5_1_ECOSYSTEM_CICD.md`（Phase 5.1 生态规划）

---

## 0. 动机

Phase 5.0 完成了全知图编译期端到端路径，标志着 Nebula 核心架构收敛。但语法糖体系（L0/L1/L2 三层 API）存在严重的可用性问题：

| 问题 | 影响 | 严重程度 |
| :--- | :--- | :--- |
| 三层 API 混用，无推荐写法 | 新开发者不知该用哪层 | **高** |
| 隐式行为过多，全局状态污染 | 多 App/多 Visual 时行为不可预测 | **高** |
| Builtin 字符串模板脆弱 | 修改一处需同步 4+ 个模板 | **中** |
| 无生成代码预览 | 调试困难，sugar 变黑盒 | **高** |
| 业务逻辑泄漏到框架模板 | `nebula_editor_main` 包含搜索/替换键盘处理 | **中** |
| Phase 5.0 状态绑定未融入 sugar | L2 写法无法使用 `nebula_state`/`nebula_bind` | **低** |

Phase 5.2 的核心命题是：**让 Nebula 的 API 从"能工作"升级为"好用且可维护"。**

---

## 1. 总体策略

### 修复原则

1. **向后兼容**：所有现有 demo 无需修改即可编译通过。修复是"增强"而非"重写"。
2. **渐进式**：每个梯队独立可验证，不依赖后续梯队完成。
3. **单一路径**：明确 L2 为推荐写法，L0/L1 为高级/逃逸路径，文档和 demo 统一使用 L2。
4. **透明化**：sugar 必须是可调试的——任何生成代码都可以被开发者看到和理解。

### 梯队划分

```
R1 API 统一与文档     → 明确推荐写法 + 降级指南 + 统一 demo
R2 全局状态消除       → 消除 _NEBULA_AUTO_DENSE / _nebula_last_app_spec 等风险
R3 生成代码预览       → #print_source 指令 + 错误定位改进
R4 Builtin AST 重构   → 字符串模板 → AST 拼接
R5 sugar 深度完善     → Phase 5.0 状态绑定融入 L2 + 组合式 sugar
```

---

## 2. 第一梯队（R1）：API 统一与文档

**目标**：让新开发者打开 README 就能知道"我该用什么写法"。

**预计产出**：修改 3 个文件 + 新增 2 个文件

### Step 1.1：明确推荐写法

**文件**：`README.md`（修改）

| 子任务 | 内容 | 验收 |
| :--- | :--- | :--- |
| 1.1.1 | 在 README 顶部明确标注推荐 API | "推荐使用 `require 'nebula'` + `nebula_visual` + `nebula_app` 声明式写法" |
| 1.1.2 | 提供最小示例（<20 行） | 按钮 + 文本编辑器的最小可运行代码 |
| 1.1.3 | 标注 L0/L1 为高级用法 | "如需精细控制，可使用 L0 Raw API（详见 `docs/guide/advanced-api.md`）" |

**验收标准**：新开发者按照 README 能在 5 分钟内写出并运行第一个 demo。

### Step 1.2：API 降级指南

**文件**：`docs/guide/api-escape-hatch.md`（新增）

| 子任务 | 内容 | 验收 |
| :--- | :--- | :--- |
| 1.2.1 | L2 → L1 降级路径 | 当 `nebula_visual` 无法满足需求时，如何切换到 `nebula_component` + `nebula_derive` |
| 1.2.2 | L1 → L0 降级路径 | 当 `nebula_app` 无法满足需求时，如何切换到 `nebula_app_begin/end` + `nebula_derive_app` |
| 1.2.3 | 三层 API 字段映射表 | 同一功能在三层的不同写法对照表 |
| 1.2.4 | 常见问题 FAQ | "如何添加自定义字段？" "如何访问生成的 Pipeline？" 等 |

**验收标准**：指南中包含 3 个完整的降级示例，每个示例可直接编译运行。

### Step 1.3：Demo 统一

**文件**：`examples/` 目录（修改）

| 子任务 | 内容 | 验收 |
| :--- | :--- | :--- |
| 1.3.1 | `button_demo.nelua` 重写为 L2 写法 | 使用 `nebula_visual` + `nebula_app`，<30 行 |
| 1.3.2 | `form_demo.nelua` 重写为 L2 写法 | 展示多组件布局的声明式写法 |
| 1.3.3 | 保留 L0 写法 demo 但添加注释头 | `text_editor_demo.nelua` 顶部标注"本 demo 使用 L0 Raw API，仅供高级用户参考" |
| 1.3.4 | 新增 `counter_demo.nelua` | Phase 5.0 状态绑定的 L2 写法演示 |

**验收标准**：所有标注为"推荐"的 demo 均可编译通过，回归测试全绿。

### Step 1.4：nebula_config 默认值文档化

**文件**：`src/derive/nebula_config.lua`（修改）

| 子任务 | 内容 | 验收 |
| :--- | :--- | :--- |
| 1.4.1 | 每个默认值添加 `///` 文档注释 | 说明用途、影响范围、推荐修改方式 |
| 1.4.2 | 新增 `nebula_config_override` 函数 | 允许用户在代码中覆盖默认值（而非修改框架源码） |
| 1.4.3 | 文档列出所有可配置项 | 在 `docs/guide/configuration.md` 中列出 |

**验收标准**：用户可通过 `nebula_config_override({ DEFAULT_WIN_WIDTH = 1920 })` 覆盖默认值。

---

## 3. 第二梯队（R2）：全局状态消除

**目标**：消除编译期全局状态的相互污染风险。

**预计产出**：修改 2 个文件 + 新增 0 个文件

### Step 2.1：消除 `_NEBULA_AUTO_DENSE` 全局污染

**文件**：`src/nebula_core.nelua`（修改）

| 子任务 | 内容 | 验收 |
| :--- | :--- | :--- |
| 2.1.1 | `_NEBULA_AUTO_DENSE` 改为 per-visual 存储 | 使用 `nebula_registry[type_name]._auto_dense` 替代全局 |
| 2.1.2 | `nebula_app` 中读取 `nebula_registry[c.type]._auto_dense` | 不再依赖全局变量 |
| 2.1.3 | 向后兼容：如果 `_NEBULA_AUTO_DENSE` 仍存在，仍读取（迁移期双路径） | 现有 demo 不破坏 |

**当前问题代码**（`nebula_core.nelua` 约 1920 行）：
```lua
-- 写入
_NEBULA_AUTO_DENSE = _NEBULA_AUTO_DENSE or {}
_NEBULA_AUTO_DENSE[type_name] = { dense_name = dense_name, ... }

-- 读取（nebula_app 中）
if _NEBULA_AUTO_DENSE and _NEBULA_AUTO_DENSE[c.type] then ...
```

**修复后**：
```lua
-- 写入：存储到 visual 的 registry 中
local reg = nebula_registry[type_name]
reg._auto_dense = { dense_name = dense_name, ... }

-- 读取：从 visual 的 registry 中读取
local c_reg = nebula_registry[c.type]
if c_reg and c_reg._auto_dense then ...
```

**验收标准**：同一文件中调用两次 `nebula_visual("multiline_editable")` 不互相覆盖。

### Step 2.2：消除 `_nebula_last_app_spec` 全局污染

**文件**：`src/nebula_core.nelua`（修改）

| 子任务 | 内容 | 验收 |
| :--- | :--- | :--- |
| 2.2.1 | `_nebula_last_app_spec` 改为 `nebula_app_registry[app_name]._spec` | 每个 App 独立存储自己的 spec |
| 2.2.2 | `nebula_terminal_main` 改为接收 `app_name` 参数后从 registry 读取 | 不再依赖最后一个 spec |
| 2.2.3 | 向后兼容：如果未传入 `app_name`，仍使用 `_nebula_last_app_name`（迁移期双路径） | 现有 demo 不破坏 |

**当前问题代码**（`nebula_core.nelua` 约 2000 行）：
```lua
-- nebula_app 中写入
_nebula_last_app_spec = spec
_nebula_last_app_name = app_name

-- nebula_terminal_main 中读取
local cached = _nebula_last_app_spec or {}
```

**修复后**：
```lua
-- nebula_app 中写入
local reg = nebula_app_registry[app_name]
reg._spec = spec

-- nebula_terminal_main 中读取
local app_name = opts.app_name or _nebula_last_app_name
local cached = (app_name and nebula_app_registry[app_name] and nebula_app_registry[app_name]._spec) or {}
```

**验收标准**：同一文件中声明两个 App + 两个 Terminal，各自 spec 不互相污染。

### Step 2.3：消除 `_NEBULA_AUTO_DENSE_PRODUCERS` 全局污染

**文件**：`src/nebula_core.nelua`（修改）

| 子任务 | 内容 | 验收 |
| :--- | :--- | :--- |
| 2.3.1 | 同 2.1，存储到 App registry 中 | `reg._auto_dense_producers = {}` |
| 2.3.2 | `nebula_app_end` 时处理 auto-dense producers | 在 App 生成前注入 |
| 2.3.3 | 向后兼容 | 现有 demo 不破坏 |

**验收标准**：多 App 场景下 auto-dense Producer 不互相干扰。

---

## 4. 第三梯队（R3）：生成代码预览

**目标**：让 sugar 透明化——任何开发者都能看到生成的代码。

**预计产出**：修改 2 个文件 + 新增 1 个文件

### Step 3.1：`## print_source` 指令

**文件**：`src/nebula_core.nelua`（修改）

| 子任务 | 内容 | 验收 |
| :--- | :--- | :--- |
| 3.1.1 | 新增 `## print_source("app", "MyApp")` | 打印 `MyApp` 的生成代码到 stdout |
| 3.1.2 | 新增 `## print_source("visual", "ButtonVisual")` | 打印 `ButtonVisual` 的生成代码 |
| 3.1.3 | 新增 `## print_source("builtin", "line_nums", "editor")` | 打印指定 builtin 的 Producer 代码 |
| 3.1.4 | 新增 `## print_source("all")` | 打印所有已注册的生成代码 |

**使用方式**：
```lua
require "nebula"

## nebula_visual("ButtonVisual", { primitives = {"clickable"} })
## nebula_app("ButtonApp", {
##   components = {{ name="btn", type="ButtonVisual" }},
## })

-- ★ 查看生成的代码
## print_source("app", "ButtonApp")

local function main(): int32
  -- ...
```

**编译输出示例**：
```
[nebula] ===== Generated source for app "ButtonApp" =====
function ButtonApp:update(input: *NebulaInputState, dt: float32): void
  nebula_arena_reset(&self.arena)
  self.btn:update(input, dt)
  -- ★ Phase 5.0 S2: 输入路由 + 事件 handler
  ...
end
===========================================================
```

**验收标准**：`## print_source` 输出的代码可通过 `nelua -c` 编译验证（即生成的代码是合法的 Nelua）。

### Step 3.2：错误定位改进

**文件**：`src/nebula_core.nelua`（修改）

| 子任务 | 内容 | 验收 |
| :--- | :--- | :--- |
| 3.2.1 | `aster.parse` 的标签改为源码位置 | `<nebula_visual:EditorBgVisual at examples/text_editor_demo_v3.nelua:12>` |
| 3.2.2 | 新增错误上下文输出 | 当生成代码出错时，打印出错的代码片段 |
| 3.2.3 | 新增 `## print_error_context` 自动触发 | 编译失败时自动打印错误上下文 |

**验收标准**：编译错误信息指向用户源码行号，而非 `<nebula_visual:...>` 匿名标签。

### Step 3.3：CLI 工具：`nebula-codegen`

**文件**：`tools/nebula_codegen.nelua`（新增）

| 子任务 | 内容 | 验收 |
| :--- | :--- | :--- |
| 3.3.1 | 命令行工具：`nebula-codegen examples/button_demo.nelua` | 输出所有生成代码到 stdout |
| 3.3.2 | `--target=app|visual|builtin` 过滤 | 只输出指定类型的生成代码 |
| 3.3.3 | `--output=file` 导出到文件 | 方便 IDE 语法高亮和搜索 |
| 3.3.4 | `--verify` 验证模式 | 生成的代码通过 `nelua -c` 编译检查 |

**验收标准**：CLI 工具可在 CI 中运行，确保生成代码始终合法。

---

## 5. 第四梯队（R4）：Builtin AST 重构

**目标**：用 AST 拼接替代字符串模板，提升 builtin 的可维护性。

**预计产出**：修改 1 个文件 + 新增 1 个文件

### Step 4.1：新增 `builtin_factory.lua`

**文件**：`src/derive/builtin_factory.lua`（新增）

| 子任务 | 内容 | 验收 |
| :--- | :--- | :--- |
| 4.1.1 | 定义 Builtin AST 数据结构 | `BuiltinNode = { kind, params, body }` |
| 4.1.2 | 实现 `emit_builtin(node)` 代码生成器 | AST → Nelua 源码 |
| 4.1.3 | 实现 `line_nums` 的 AST 定义 | 替代 `nebula_builtin_line_nums` 的字符串模板 |
| 4.1.4 | 实现 `status_bar` 的 AST 定义 | 替代 `nebula_builtin_status_bar` 的字符串模板 |
| 4.1.5 | 实现 `search_bar` 的 AST 定义 | 替代 `nebula_builtin_search_bar` 的字符串模板 |
| 4.1.6 | 实现 `edit_area` 的 AST 定义 | 替代 `nebula_builtin_edit_area` 的字符串模板 |

**Builtin AST 设计**：
```lua
-- 示例：line_nums 的 AST 定义
local line_nums = {
  kind = "producer",
  name = "nebula_fill_line_nums",
  params = { "app", "instances", "count", "max" },
  body = {
    { kind = "let", name = "editor", value = ast_ref("app", editor_name) },
    { kind = "let", name = "mb", value = ast_field(ast_ref("editor"), "visual.multi_buf") },
    { kind = "while", condition = ast_lt(ast_ref("row"), ast_ref("visible_rows")),
      body = {
        -- ... 循环体
      }
    },
    { kind = "assign", target = ast_deref("count"), value = ast_ref("idx") },
  },
}
```

**验收标准**：AST 生成的代码与当前字符串模板生成的代码 100% 一致（通过 diff 验证）。

### Step 4.2：渐进式迁移

**文件**：`src/nebula_builtins.nelua`（修改）

| 子任务 | 内容 | 验收 |
| :--- | :--- | :--- |
| 4.2.1 | Phase 1：先用 AST 生成 `line_nums` | 最简单，风险最低 |
| 4.2.2 | Phase 2：生成 `status_bar` | 增加条件分支 |
| 4.2.3 | Phase 3：生成 `search_bar` | 增加字符串格式化 |
| 4.2.4 | Phase 4：生成 `edit_area` | 最复杂（选区/搜索高亮/语法着色） |

**迁移策略**：
- 每个 builtin 迁移后运行 `tools/nebula_codegen.nelua --verify` 验证
- 保留旧的字符串模板函数作为 fallback，迁移期间双路径并行
- 全部迁移完成后删除旧函数

**验收标准**：4 个 builtin 全部使用 AST 生成，回归测试 77/77 全绿。

---

## 6. 第五梯队（R5）：sugar 深度完善

**目标**：让 L2 sugar API 成为完整的、自包含的开发者接口。

**预计产出**：修改 2 个文件 + 新增 1 个文件

### Step 5.1：Phase 5.0 状态绑定融入 L2 sugar

**文件**：`src/nebula_core.nelua`（修改）

| 子任务 | 内容 | 验收 |
| :--- | :--- | :--- |
| 5.1.1 | `nebula_app()` 的 `states` 字段完善 | 支持 `{ name, type, default }` |
| 5.1.2 | `nebula_app()` 的 `bindings` 字段完善 | 支持 `{ target, depends, compute }` |
| 5.1.3 | `nebula_app()` 的 `events` 字段完善 | 支持 `{ target, event_type, mutation }` |
| 5.1.4 | 新增 `counter_demo.nelua` | L2 写法的完整状态绑定演示 |

**目标写法**：
```lua
require "nebula"

## nebula_visual("CounterVisual", { primitives = {"clickable"} })

## nebula_app("CounterApp", {
##   components = {{ name = "btn", type = "CounterVisual" }},
##   states = {
##     { name = "count", type = "int32", default = 0 },
##   },
##   bindings = {
##     { target = "label", depends = {"count"}, compute = "self.label = self.count * 2" },
##   },
##   events = {
##     { target = "btn", event_type = "click", mutation = "self.count = self.count + 1" },
##   },
## })
```

**验收标准**：`counter_demo.nelua` 编译通过且可运行，点击按钮时状态正确更新。

### Step 5.2：移除 `nebula_editor_main` 中的业务逻辑

**文件**：`src/nebula_apps.nelua`（修改）

| 子任务 | 内容 | 验收 |
| :--- | :--- | :--- |
| 5.2.1 | 移除 Ctrl+S/Ctrl+F/Ctrl+H 键盘处理 | 这些是业务逻辑，不应在框架模板中 |
| 5.2.2 | 替换为通用的 `on_frame` 回调机制 | 用户通过回调注入自己的业务逻辑 |
| 5.2.3 | 保留框架级职责（init/frame_render/deinit） | 模板只负责生命周期管理 |
| 5.2.4 | 更新 `text_editor_demo_v3.nelua` | 展示如何使用新回调机制 |

**新模板设计**：
```lua
## nebula_app_main("TextEditorApp", {
##   title = "Nebula Editor",
##   width = 900, height = 640,
##   on_init = function(app)
##     -- 用户自定义初始化
##     return { "app.editor:init_themed(...)" }
##   end,
##   on_frame = function(app)
##     -- 用户自定义每帧逻辑
##     return {
##       "if app.editor.click.just_clicked then ... end",
##       "if input.key_pressed == NebulaKey.Save then ... end",
##     }
##   end,
## })
```

**验收标准**：`text_editor_demo_v3.nelua` 使用新模板后功能不变，回归测试全绿。

### Step 5.3：组合式 sugar 基础

**文件**：`src/nebula_core.nelua`（修改）

| 子任务 | 内容 | 验收 |
| :--- | :--- | :--- |
| 5.3.1 | 新增 `nebula_component_template(name, spec)` | 定义可复用的组件模板 |
| 5.3.2 | `nebula_app()` 支持 `use = { template_name }` | 引用预定义模板 |
| 5.3.3 | 新增 `search_bar_template` 内置模板 | 搜索栏的标准配置 |
| 5.3.4 | 新增 `status_bar_template` 内置模板 | 状态栏的标准配置 |

**目标写法**：
```lua
## nebula_component_template("StandardSearchBar", {
##   type = "DenseTextVisual",
##   builtin = "search_bar",
##   flex_basis = 24,
##   cell_w = 10.0,
##   cell_h = 16.0,
## })

## nebula_app("MyApp", {
##   components = {
##     { use = "StandardSearchBar", name = "search" },
##     { name = "editor", type = "EditorVisual" },
##   },
## })
```

**验收标准**：模板可在多个 App 间复用，修改模板定义后所有引用处自动更新。

---

## 7. 不做列表（明确排除）

| 项目 | 理由 |
| :--- | :--- |
| 完全删除 L0/L1 API | 它们是合法的逃逸路径，删除会破坏向后兼容 |
| 重写全部代码生成器 | 渐进式重构风险更低，且当前生成器功能正确 |
| 添加 IDE 插件 | 超出 Nebula 框架职责，留给社区或后续 |
| 热重载支持 | 需要 Nelua 编译器层面的支持，非框架可独立完成 |
| 完整的类型推导系统 | compute/mutation 字符串的类型安全留给 Phase 6.0 |

---

## 8. 风险与缓解

| 风险 | 影响 | 缓解 |
| :--- | :--- | :--- |
| AST 重构后生成的代码与模板不一致 | 功能回归 | 每个 builtin 迁移后用 diff 验证 100% 一致 |
| 消除全局状态时引入新 bug | 编译失败 | 迁移期间保持双路径并行，测试通过后再删除旧路径 |
| `print_source` 输出格式不稳定 | 开发者困惑 | 固定输出格式，并在文档中明确说明 |
| 移除 `nebula_editor_main` 业务逻辑破坏现有 demo | 用户不满 | 保留旧函数为 deprecated，提供迁移指南 |

---

## 9. 里程碑与验收标准

### 里程碑 1：API 统一完成（R1）

- [ ] README 顶部明确标注推荐 API
- [ ] `docs/guide/api-escape-hatch.md` 包含 3 个完整降级示例
- [ ] `button_demo.nelua`、`form_demo.nelua` 重写为 L2 写法
- [x] 新增 `counter_demo.nelua`（Phase 5.0 状态绑定演示）

### 里程碑 2：全局状态消除完成（R2）

- [x] `_NEBULA_AUTO_DENSE` 改为 per-visual registry 存储
- [x] `_nebula_last_app_spec` 改为 per-app registry 存储
- [x] `_NEBULA_AUTO_DENSE_PRODUCERS` 改为 per-app registry 存储
- [ ] 多 App/多 Visual 场景测试通过
- [ ] 回归测试 77/77 全绿

### 里程碑 3：生成代码预览可用（R3）

- [ ] `## print_source("app", "MyApp")` 输出合法 Nelua 代码
- [ ] 编译错误指向用户源码行号
- [ ] `tools/nebula_codegen.nelua` CLI 工具可用
- [ ] CI 中新增代码验证步骤

### 里程碑 4：Builtin AST 重构完成（R4）

- [x] `builtin_factory.lua` 实现完整
- [x] 4 个 builtin 全部使用 AST 生成
- [x] 生成的代码与旧模板 100% 一致（diff 验证）
- [x] 回归测试 77/77 全绿

### 里程碑 5：sugar 深度完善完成（R5）

- [x] `counter_demo.nelua` 使用 L2 状态绑定写法
- [x] `nebula_editor_main` 业务逻辑移除，替换为回调机制
- [ ] `nebula_component_template` 可用
- [ ] 所有 demo 统一为 L2 写法

---

## 10. 与 Phase 5.1 的关系

Phase 5.2 与 Phase 5.1（生态与 CI/CD）是**正交且互补**的关系：

| Phase 5.1 | Phase 5.2 | 协同点 |
| :--- | :--- | :--- |
| CI/CD 强化 | 生成代码预览 | `nebula-codegen --verify` 集成到 CI |
| 文档工程 | API 统一与降级指南 | `docs/guide/` 下的教程使用统一 L2 写法 |
| WASM 生态 | sugar 深度完善 | Playground 展示 L2 sugar 的简洁性 |
| 包管理支持 | Builtin AST 重构 | AST 生成的 builtin 代码更易于分发 |
| 社区治理 | 全局状态消除 | 消除隐式行为，降低社区贡献门槛 |

**建议实施顺序**：R1 → R2 → R3 → R4 → R5，可与 Phase 5.1 的 S1/S2 梯队并行推进。

---

## 11. 综合重要度评分

| 维度 | 得分 | 评分理由 |
| :--- | :--- | :--- |
| **A. 架构奠基性** | **7** | 不引入新核心抽象，但消除全局状态污染提升了架构稳定性 |
| **B. 公理合规性** | **8** | 生成代码预览让 sugar 透明化，使开发者能验证公理合规性 |
| **C. 开发者体验** | **10** | API 统一、降级指南、错误定位改进是 DX 最大的单次跃升 |
| **D. 工业化就绪度** | **9** | AST 重构和透明化调试是工业级框架的必要基础设施 |
| **E. 下游解锁度** | **8** | 解锁了社区贡献（降低入门门槛）和 IDE 集成（生成代码预览） |
| **综合分** | **83** | `(7×0.30 + 8×0.20 + 10×0.20 + 9×0.15 + 8×0.15) × 10` |

**排名对比**：Phase 5.2（83 分）略高于 Phase 5.1（82 分），在综合排名中位于第 8-9 位。

---

## 12. 立即可执行的下一步

**R1.1**：在 README 顶部添加推荐 API 说明 + 最小示例。

具体操作：
1. 修改 `README.md`，在 "构建与运行" 之前添加 "快速开始" 章节
2. 展示 `require "nebula"` + `nebula_visual` + `nebula_app` 的最小按钮示例
3. 标注 L0/L1 为高级用法，链接到降级指南
