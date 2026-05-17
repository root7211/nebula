# Nebula 架构拆分方案 v2（修正版）

**创建日期**：2026-05-17
**修正日期**：2026-05-17
**基准状态**：Era III | 77/77 回归全绿 | nebula_core.nelua 2277 行
**审计基准**：`docs/PLAN_ARCHITECTURE_AUDIT.md`
**修正依据**：v1 版本经代码级交叉验证后发现 4 处错误，本版逐一修正。

---

## v2 修正摘要

| # | 问题 | 严重度 | 修正内容 |
|:--|:---|:---|:---|
| F1 | `NEBULA_THEME_DEFAULTS` 归属错误 | **严重** | 实际定义在 L763（derive engine 区域），v1 错误标注为 sugar L1570-L1578。已修正：明确归属 derive engine，并从 sugar 内容表中移除。 |
| F2 | Sugar 对 `app_factory.lua` 的依赖描述不准确 | **中等** | Sugar 并非直接 `require` app_factory，而是通过 derive engine 加载后的全局函数间接访问。已修正依赖图，标注为"全局函数（由 derive engine 加载）"。 |
| F3 | Phase 5.0 传递依赖未体现 | **轻微** | `app_factory.lua` 通过 `pcall(require, ...)` 延迟加载 4 个 Phase 5.0 模块（omniscient_graph / binding_factory / mutation_ast / effect_model），以及 dirty_map / event_router 的加载路径未说明。已补充到依赖图。 |
| F4 | S4 步骤与 Facade 设计冗余 | **轻微** | Facade 已 `require "nebula_sugar"`，`nebula.nelua` 无需重复 require。已统一为 Facade 负责，删除 S4 冗余步骤。 |

---

## 0. 已完成拆分回顾

| 文件 | 行数 | 状态 | 对应问题 |
|:---|:---|:---|:---|
| `nebula_types.nelua` | 139 | ✅ 已提取 | P1-1 部分 |
| `nebula_constants.nelua` | — | ✅ 已提取 | P2-8 |
| `cstdlib_bindings.nelua` | — | ✅ 已提取 | P2-3, P2-4 |
| `nebula_editor.nelua` | 349 | ✅ 已提取 | P1-2 部分 |
| `wgpu_bindings_shared.nelua` | 216 | ✅ 已提取 | P1-3 部分 |
| `wgpu_bindings_native.nelua` | — | ✅ 已提取 | P1-3 部分 |
| `wgpu_bindings_wasm.nelua` | — | ✅ 已提取 | P1-3 部分 |

---

## 1. 当前问题清单

### 待拆分模块

| # | 当前文件 | 行数 | 问题 | 严重度 |
|:--|:---|:---|:---|:---|
| T1 | `nebula_core.nelua` | 2277 | God Module：编译期推导引擎 + 语法糖 API + Builtin 注册表混在一起 | **P1** |
| T2 | `app.nelua` | 624 | 编辑器专属逻辑可能仍有残留（需验证） | **P1** |
| T3 | `wgpu_bindings_shared.nelua` | 216 | 18 种 GPU 句柄全部 alias 到 `@pointer`（P1-6 Deferred） | **P1-Deferred** |

### `nebula_core.nelua` 内部结构（经代码验证）

```
L001-L094   平台检测（NEBULA_TARGET / NEBULA_LINUX_DISPLAY）—— 编译期 ## 块
L096-L103   require "nebula_types" + require "nebula_constants"（已拆分 ✅）
L104-L1568  ★ 编译期推导引擎（约 1465 行）
  L107-L138     nebula_registry + nebula_annotate
  L108-L119     WGSL_TYPE_MAP / TYPE_SIZE_MAP / LERP_FN_MAP
  L140-L479     shape parser + Uniform 布局生成器
  L481-L534     derive/*.lua 模块加载（8 个 require + assert）
  L535-L644     WGSL 着色器生成器
  L646-L758     gen_state_enum / gen_state_machine 前半部
  L760-L798     ★ NEBULA_THEME_DEFAULTS（编译期主题默认值表）  ← v2 修正：属于 derive engine
  L799-L1170    gen_context_for / gen_update_for（使用 NEBULA_THEME_DEFAULTS）
  L1172-L1314   nebula_derive_text_visual / nebula_derive_slug_text_visual
  L1316-L1372   nebula_derive_dense_text_visual
  L1374-L1539   nebula_derive（主入口，分发到上述各路径）
  L1541-L1568   nebula_derive_app
L1570-L1952 ★ 语法糖 API（约 383 行）
  L1570-L1573   Phase 4.5 节头注释
  L1574-L1616   nebula_auto_states
  L1618-L1665   nebula_inject_buffers
  L1667-L1717   nebula_component
  L1719-L1782   nebula_editor_visual
  L1784-L1942   nebula_visual（L2 层）
  L1944-L1952   nebula_editor_init_helper（stub）
L1954-L2277 ★ Builtin 注册表 + nebula_app（约 324 行）
  L1954-L1962   _nebula_builtins = _nebula_builtins or {}
  L1964-L2268   nebula_app（一站式 App 声明糖）
L2269-L2277   空白
```

### 模块依赖关系（v2 修正：区分直接/间接依赖，补充 Phase 5.0 传递依赖）

```
nebula_derive_engine.nelua（新建）
  ├── [直接 require] derive/shader_compose.lua      (L497)
  ├── [直接 require] derive/pipeline_factory.lua     (L502)
  ├── [直接 require] derive/interaction_factory.lua  (L507)
  │     └── 定义全局: NEBULA_PRIMITIVES, nebula_resolve_primitives
  ├── [直接 require] derive/layout_engine.lua        (L512)
  ├── [直接 require] derive/app_factory.lua          (L517)
  │     ├── 定义全局: nebula_app_begin, nebula_app_end, nebula_app_generate,
  │     │            nebula_state, nebula_bind, nebula_on,
  │     │            nebula_app_register_component, nebula_app_register_dense_text, ...
  │     ├── [延迟 pcall require] derive/omniscient_graph.lua   ← Phase 5.0
  │     ├── [延迟 pcall require] derive/binding_factory.lua    ← Phase 5.0
  │     ├── [延迟 pcall require] derive/mutation_ast.lua       ← Phase 5.0
  │     └── [延迟 pcall require] derive/effect_model.lua       ← Phase 5.0
  ├── [直接 require] derive/axiom_validator.lua      (L522)
  ├── [直接 require] derive/gap_buffer_factory.lua   (L527)
  └── [直接 require] derive/highlight_factory.lua    (L532)
  注：derive/dirty_map.lua 由 omniscient_graph.lua 内部加载
      derive/event_router.lua 由 binding_factory.lua 内部加载

nebula_sugar.nelua（新建）
  ├── [间接依赖] nebula_derive_engine.nelua 的全局函数：
  │     · nebula_annotate, nebula_derive, nebula_derive_app     (来自 derive engine 自身)
  │     · nebula_resolve_primitives, NEBULA_PRIMITIVES          (来自 interaction_factory.lua)
  │     · nebula_app_begin, nebula_app_end, nebula_state,       (来自 app_factory.lua)
  │       nebula_bind, nebula_on, nebula_app_generate
  │     · NEBULA_THEME_DEFAULTS                                 (来自 derive engine 自身)
  └── [间接依赖] Nelua 内置: aster.parse(), inject_statement()

  ★ 重要：nebula_sugar 不需要自行 require 任何 derive/*.lua 模块。
    所有依赖的全局函数在 derive engine 加载时已注入全局空间。
    唯一的约束是加载顺序：derive_engine 必须先于 sugar 被 require。

nebula_core.nelua（重写为 Facade）
  ├── 平台检测 ## 块（L001-L094）
  ├── require "nebula_types"
  ├── require "nebula_constants"
  ├── require "nebula_derive_engine"    ← 必须在 sugar 之前
  └── require "nebula_sugar"

nebula.nelua（统一入口，无需修改 sugar 行）
  ├── cstdlib_bindings.nelua
  ├── nebula_core.nelua          ← Facade 内部已加载 derive_engine + sugar
  ├── nebula_builtins.nelua
  ├── nebula_apps.nelua
  ├── glfw_bindings.nelua
  ├── wgpu_bindings.nelua
  ├── renderer.nelua
  ├── app.nelua
  ├── text_runtime.nelua
  ├── nebula_cursor.nelua
  ├── nebula_arena.nelua
  └── nebula_theme.nelua
```

---

## 2. 拆分方案：nebula_core.nelua → 3 个文件

### 2.1 `nebula_derive_engine.nelua`（约 1465 行）

**职责**：编译期推导引擎核心。负责将 Visual 声明转换为 Nelua 运行时代码。

**包含内容**（从 `nebula_core.nelua` 提取 L104-L1568）：

| 行号范围 | 内容 | 说明 |
|:---|:---|:---|
| L107-L138 | `nebula_registry` + `nebula_annotate` | 注解注册表 |
| L108-L119 | `WGSL_TYPE_MAP` / `TYPE_SIZE_MAP` / `LERP_FN_MAP` | 类型映射表 |
| L140-L176 | `nebula_parse_shape` + `collect_all_props` | Shape 解析器 |
| L195-L234 | `nebula_gen_wgsl_uniform` / `nebula_calc_uniform_size` | Phase 0 WGSL API |
| L247-L384 | `nebula_gen_uniform_layout` | std140 布局推导 |
| L399-L479 | `nebula_gen_uniform_layout_from_fields` | 手动字段布局 |
| L481-L534 | 8 个 `derive/*.lua` 模块的 require + assert | 模块加载 |
| L535-L608 | `nebula_gen_wgsl_shader` / `detect_shader_features` | 着色器生成 |
| L610-L644 | `nebula_gen_wgsl_shader_from_fields` | 手动字段着色器 |
| L646-L758 | `gen_state_enum` / `gen_state_machine` | 状态枚举+状态机生成 |
| **L760-L798** | **`NEBULA_THEME_DEFAULTS`** | **★ v2 修正：编译期主题默认值表，被 L884/L907 的 `gen_context_for` 使用，必须留在 derive engine** |
| L799-L1116 | `gen_context_for` / `gen_update_for` | Context + Update 代码生成（读取 NEBULA_THEME_DEFAULTS） |
| L1048-L1170 | `gen_text_context_for` + `nebula_derive_text_visual` | 文本 Visual 派生 |
| L1172-L1314 | `nebula_derive_slug_text_visual` | Slug 文本派生 |
| L1316-L1372 | `nebula_derive_dense_text_visual` | DenseText 派生 |
| L1374-L1539 | `nebula_derive`（主入口） | 统一派生入口 |
| L1541-L1568 | `nebula_derive_app` | App 派生入口 |

**依赖的 derive/*.lua 模块**（直接 require，8 个）：
- `derive/shader_compose.lua`
- `derive/pipeline_factory.lua`
- `derive/interaction_factory.lua`
- `derive/layout_engine.lua`
- `derive/app_factory.lua`
- `derive/axiom_validator.lua`
- `derive/gap_buffer_factory.lua`
- `derive/highlight_factory.lua`

**传递依赖**（由 app_factory.lua 延迟加载，4 个）：
- `derive/omniscient_graph.lua` → 内部加载 `derive/dirty_map.lua`
- `derive/binding_factory.lua` → 内部加载 `derive/event_router.lua`
- `derive/mutation_ast.lua`
- `derive/effect_model.lua`

**对外暴露的 API**：
```
nebula_registry              (全局表)
nebula_annotate              (注册 Visual 规格)
nebula_derive                (生成 State + SM + Context + Pipeline)
nebula_derive_app            (生成 App record + init/update/draw)
nebula_derive_text_visual
nebula_derive_slug_text_visual
nebula_derive_dense_text_visual
nebula_gen_uniform_layout
nebula_gen_wgsl_shader
NEBULA_THEME_DEFAULTS        (★ v2 修正：归属 derive engine)

-- 以下由 require 的 derive/*.lua 模块注入全局空间：
NEBULA_PRIMITIVES            (来自 interaction_factory.lua)
nebula_resolve_primitives    (来自 interaction_factory.lua)
nebula_app_begin / _end / _generate  (来自 app_factory.lua)
nebula_state / nebula_bind / nebula_on  (来自 app_factory.lua)
```

### 2.2 `nebula_sugar.nelua`（约 707 行）

**职责**：高层语法糖 API + Builtin 注册表 + nebula_app 一站式声明。为开发者提供声明式、低样板代码的接口。

**包含内容**（从 `nebula_core.nelua` 提取 L1570-L2268）：

| 行号范围 | 内容 | 说明 |
|:---|:---|:---|
| L1570-L1573 | Phase 4.5 节头注释 | 区域标识 |
| L1574-L1616 | `nebula_auto_states` | 从 primitives 推导 states |
| L1618-L1665 | `nebula_inject_buffers` | 前置 buffer 类型注入 |
| L1667-L1717 | `nebula_component` | 合并 annotate + derive |
| L1719-L1782 | `nebula_editor_visual` | 编辑器 Visual 自动生成 |
| L1784-L1942 | `nebula_visual` | L2 层 Visual 声明糖 |
| L1944-L1952 | `nebula_editor_init_helper` | stub 标记函数 |
| L1954-L1962 | `_nebula_builtins` 注册表 | Builtin Producer 工厂 |
| L1964-L2268 | `nebula_app` | 一站式 App 声明糖（含 Phase 5.0 states/bindings/events） |

**依赖关系**（★ v2 修正：全部为间接依赖，通过全局函数访问）：

```
nebula_sugar.nelua 使用的全局函数（全部由 nebula_derive_engine 加载后可用）：
  · nebula_annotate(type_name, spec)         — derive engine L107
  · nebula_derive(type_name)                 — derive engine L1384
  · nebula_derive_app(app_name)              — derive engine L1561
  · nebula_resolve_primitives(prims)         — interaction_factory.lua L914
  · NEBULA_PRIMITIVES[name]                  — interaction_factory.lua L157
  · NEBULA_THEME_DEFAULTS[state]             — derive engine L763
  · nebula_app_begin(app_name)               — app_factory.lua
  · nebula_app_end()                         — app_factory.lua
  · nebula_app_register_component(...)       — app_factory.lua
  · nebula_app_register_dense_text(...)      — app_factory.lua
  · nebula_app_set_root_layout(...)          — app_factory.lua
  · nebula_state(name, config)               — app_factory.lua L433
  · nebula_bind(target, config)              — app_factory.lua L453
  · nebula_on(target, event_type, config)    — app_factory.lua L479

注意：sugar 不需要自行 require 任何模块。
     唯一硬约束：require "nebula_derive_engine" 必须在 require "nebula_sugar" 之前执行。
     Facade（nebula_core.nelua）通过 require 顺序保证此约束。
```

**对外暴露的 API**：
```
nebula_auto_states
nebula_inject_buffers
nebula_component        (L1 Sugar)
nebula_editor_visual
nebula_visual           (L2 Sugar)
nebula_editor_init_helper (stub)
nebula_register_builtin
_nebula_builtins
nebula_app              (L2 App Sugar)
```

### 2.3 `nebula_core.nelua`（约 100 行，Facade）

**职责**：统一加载入口。向后兼容——任何 `require "nebula_core"` 的代码不受影响。

**新内容**：
```lua
-- =============================================================================
-- nebula_core.nelua — 统一加载入口（Facade）
--
-- v2: 此文件仅负责平台检测 + 按序加载子模块。
-- 任何 require "nebula_core" 的代码行为不变。
-- =============================================================================

-- 平台检测（编译期 ## 块）
##[[ ... NEBULA_TARGET 检测 (L001-L094 原样保留) ... ]]

-- 已提取的基础模块
require "nebula_types"
require "nebula_constants"

-- 编译期推导引擎（必须先于 sugar 加载，sugar 依赖其注入的全局函数）
require "nebula_derive_engine"

-- 语法糖 API + Builtin 注册表
require "nebula_sugar"
```

**★ v2 修正**：`nebula.nelua` 统一入口**不需要修改**。原来的 `require "nebula_core"` 行为不变——Facade 内部已按正确顺序加载了 derive_engine 和 sugar。无需在 `nebula.nelua` 中额外添加 `require "nebula_sugar"` 行。

---

## 3. 拆分方案：app.nelua 编辑器逻辑提取

### 3.1 现状验证

`nebula_editor.nelua`（349 行）已存在，需要验证 `app.nelua` 中是否仍有残留的编辑器逻辑。

**检查清单**：
- [ ] 搜索 `app.nelua` 中的 `search`/`replace`/`file_path`/`modified` 关键词
- [ ] 搜索 `nebula_editor_update_title` 引用
- [ ] 搜索编辑器专属键盘处理（Ctrl+S/Ctrl+F/Ctrl+H）

**如果仍存在残留**：
- 提取到 `nebula_editor.nelua`（已存在，需合并）
- `app.nelua` 仅保留：input 收集、frame render、事件循环

---

## 4. 拆分方案：wgpu_bindings 句柄类型安全（P1-6 Deferred）

**当前**：18 种 GPU 句柄全部 alias 到 `@pointer`。

**目标**：改为 `@record{_handle: pointer}` 增强类型安全。

**阻塞原因**：`<cimport, nodecl>` 约束下改为 distinct record 可能破坏 C FFI ABI。

**前置条件**：本地 Nelua 编译验证可行性后再实施。

---

## 5. 实施步骤

### 第一阶段：准备与验证

| 任务 | 内容 | 验收 |
|:---|:---|:---|
| V1 | 验证 `app.nelua` 编辑器逻辑残留 | 确认是否需进一步提取 |
| V2 | 本地编译验证 P1-6（wgpu 句柄类型）可行性 | 记录结论 |
| V3 | 复制当前 `nebula_core.nelua` 作为备份 | 回滚保障 |

### 第二阶段：nebula_core 拆分

| 任务 | 内容 | 验收 |
|:---|:---|:---|
| S1 | 从 `nebula_core.nelua` 提取 L104-L1568 → `nebula_derive_engine.nelua`（含 NEBULA_THEME_DEFAULTS） | 文件独立可编译 |
| S2 | 从 `nebula_core.nelua` 提取 L1570-L2268 → `nebula_sugar.nelua`（不含 NEBULA_THEME_DEFAULTS） | 文件独立可编译（在 derive engine 之后加载时） |
| S3 | 重写 `nebula_core.nelua` 为 Facade（平台检测 + require types + constants + derive_engine + sugar） | require 链正确 |
| S4 | ~~更新 `nebula.nelua` 加载顺序~~ **v2 删除**：Facade 已处理加载顺序，`nebula.nelua` 无需修改 | — |
| S5 | 77/77 回归测试全绿 | **必须通过** |
| S6 | 32 demo 全部编译通过 | **必须通过** |
| S7 | CI 全量通过 | **必须通过** |

### 第三阶段：清理与验证

| 任务 | 内容 | 验收 |
|:---|:---|:---|
| C1 | 更新文档索引中的文件路径引用 | 文档一致性 |
| C2 | 更新 `build.sh` 中的文件列表 | 构建系统正确 |
| C3 | 更新 CI 静态分析覆盖范围 | 覆盖新文件 |
| C4 | 各子模块行数均 <800 行（derive_engine 除外，<1600） | 复杂度达标 |

---

## 6. 拆分后的项目结构

```
src/
├── nebula.nelua                    # 统一入口（无需修改）
├── nebula_core.nelua               # Facade（~100 行）← 拆分后
├── nebula_derive_engine.nelua      # ★ 编译期推导引擎（~1465 行）← 新增
│                                   #   含 NEBULA_THEME_DEFAULTS（v2 修正）
├── nebula_sugar.nelua              # ★ 语法糖 API + Builtin + nebula_app（~707 行）← 新增
├── nebula_types.nelua              # 类型定义（139 行）
├── nebula_constants.nelua          # 运行时常量
├── nebula_builtins.nelua           # 预置 Producer 工厂
├── nebula_apps.nelua               # 应用模板（554 行）
├── nebula_editor.nelua             # 编辑器模块（349 行）
├── nebula_arena.nelua              # Frame Arena
├── nebula_cursor.nelua             # 光标系统
├── nebula_theme.nelua              # 主题颜色
├── renderer.nelua                  # 渲染器
├── app.nelua                       # App 编排 + 事件循环（624 行）
├── text_runtime.nelua              # 文本运行时
├── gap_buffer.nelua                # Gap Buffer
├── glfw_bindings.nelua             # GLFW 绑定
├── wgpu_bindings.nelua             # WebGPU 绑定入口（15 行）
├── wgpu_bindings_shared.nelua      # 平台共享绑定（216 行）
├── wgpu_bindings_native.nelua      # Native 平台绑定
├── wgpu_bindings_wasm.nelua        # WASM 平台绑定
├── cstdlib_bindings.nelua          # C stdlib 绑定
├── harfbuzz_bindings.nelua         # HarfBuzz 绑定
├── stb_truetype_bindings.nelua     # stb_truetype 绑定
└── derive/
    ├── nebula_config.lua           # 编译期配置
    ├── app_factory.lua             # App 编排（内部延迟加载 Phase 5.0 模块）
    ├── pipeline_factory.lua        # 管线生成
    ├── shader_compose.lua          # 着色器组合
    ├── interaction_factory.lua     # 交互原语（定义 NEBULA_PRIMITIVES）
    ├── layout_engine.lua           # 布局引擎
    ├── axiom_validator.lua         # 公理校验
    ├── gap_buffer_factory.lua      # Buffer 生成
    ├── highlight_factory.lua       # 语法高亮
    ├── omniscient_graph.lua        # Phase 5.0 全知图（由 app_factory 延迟加载）
    ├── dirty_map.lua               # Phase 5.0 dirty bit（由 omniscient_graph 加载）
    ├── binding_factory.lua         # Phase 5.0 绑定生成（由 app_factory 延迟加载）
    ├── event_router.lua            # Phase 5.0 事件路由（由 binding_factory 加载）
    ├── mutation_ast.lua            # Phase 5.0 AST 解析（由 app_factory 延迟加载）
    └── effect_model.lua            # Phase 5.0 Effect 模型（由 app_factory 延迟加载）
```

---

## 7. 风险评估与缓解

| 风险 | 影响 | 概率 | 缓解措施 |
|:---|:---|:---|:---|
| require 循环依赖 | 编译失败 | 低 | 严格单向依赖：Facade → derive_engine → sugar。无反向调用（已验证：derive engine L104-L1568 中无任何对 sugar 函数的引用） |
| ## 块中的全局变量跨文件不可见 | 功能失效 | **低**（v2 降级） | Nelua 编译期 Lua 共享全局空间，require 加载顺序保证可见性。`NEBULA_THEME_DEFAULTS` 已确认留在 derive engine 中（v2 修正） |
| sugar 中调用 app_factory 全局函数但未加载 | 编译错误 | 低 | Facade 保证 derive_engine 先于 sugar 加载；derive_engine require app_factory 时注入全局函数 |
| CI 编译时间增加 | 性能退化 | 低 | Facade 模式增加 1 层 require，Nelua 编译期开销可忽略 |
| 文档路径失效 | 开发者困惑 | 低 | 拆分完成后同步更新所有文档引用（第三阶段 C1） |
| Phase 5.0 延迟加载路径断裂 | 5.0 功能失效 | 低 | app_factory.lua 使用 pcall + fallback dofile 双路径加载，与拆分无关 |

---

## 8. 不做列表

| 排除项 | 理由 |
|:---|:---|
| 重写 wgpu_bindings 为自动生成 | 投入产出比过低，P1-6 Deferred 验证后再决策 |
| 拆分 derive/*.lua 模块 | 已经是独立文件，职责清晰 |
| 拆分 nebula_builtins.nelua | 554 行，单一职责（Producer 生成），无需拆分 |
| 拆分 app.nelua（除非 V1 验证有残留） | 624 行，职责为 App 编排 + 事件循环，合理 |
| 引入宏系统或模板引擎 | 超出当前架构范围，留给 Era IV |
| 进一步拆分 nebula_derive_engine（<1600 行） | 内部逻辑高度耦合（gen 函数相互调用），强行拆分会引入大量跨文件全局函数传递。如果未来超过 2000 行再考虑 |

---

## 9. 验收标准

### 文件行数目标

| 文件 | 当前行数 | 目标行数 | 阈值 |
|:---|:---|:---|:---|
| `nebula_core.nelua` | 2277 | ~100 | <200 |
| `nebula_derive_engine.nelua` | — | ~1465 | <1600 |
| `nebula_sugar.nelua` | — | ~707 | <800 |
| `app.nelua` | 624 | ≤624 | <800 |

### 功能目标

- [ ] 77/77 回归测试全绿
- [ ] 32 demo 全部编译通过
- [ ] CI 全量通过（smoke/compile-linux/compile-windows/compile-wasm/headless-render/static-analysis）
- [ ] `require "nebula_core"` 向后兼容（所有现有代码无需修改）
- [ ] `require "nebula"` 统一入口不受影响

### 架构目标

- [ ] derive_engine <1600 行，其余核心文件 <800 行
- [ ] 依赖方向清晰：`nebula.nelua` → `nebula_core.nelua`(Facade) → `nebula_derive_engine.nelua` → `nebula_sugar.nelua`
- [ ] 无循环依赖（已验证：derive engine 不引用任何 sugar 函数）
- [ ] 每个模块有明确的职责描述（文件头部注释）
- [ ] 全局函数的定义源头在注释中有明确标注

---

## 附录：v1 → v2 变更详细对照

### F1：NEBULA_THEME_DEFAULTS 归属

```diff
  # Section 2.1 nebula_derive_engine.nelua 内容表
+ | L760-L798 | NEBULA_THEME_DEFAULTS | 编译期主题默认值表，被 gen_context_for 使用 |

  # Section 2.2 nebula_sugar.nelua 内容表
- | L1570-L1578 | NEBULA_THEME_DEFAULTS | 编译期主题表 |
+ | L1570-L1573 | Phase 4.5 节头注释 | 区域标识 |
```

**根因**：v1 作者将 L1570 的 Phase 4.5 注释头与 L763 的 NEBULA_THEME_DEFAULTS 混淆。NEBULA_THEME_DEFAULTS 实际在 L763，属于 derive engine 的 gen_state_machine/gen_context_for 逻辑块内部，且被 L884/L907 的初始化代码生成直接读取。

### F2：依赖图间接依赖标注

```diff
  nebula_sugar.nelua（待创建）
-   ├── nebula_core.nelua              (require "nebula_core" — nebula_annotate/derive)
-   ├── derive/app_factory.lua          (nebula_app_begin/end/register_component/...)
-   └── derive/nebula_config.lua        (DEFAULT_WIN_WIDTH 等常量)
+   ├── [间接依赖] nebula_derive_engine 的全局函数（通过 Facade 加载顺序保证可用）
+   └── [间接依赖] Nelua 内置: aster.parse(), inject_statement()
+   注：sugar 不直接 require 任何文件，全部通过全局空间访问
```

### F3：Phase 5.0 传递依赖补充

```diff
  nebula_derive_engine.nelua
    ├── derive/app_factory.lua          (L517)
+   │     ├── [延迟 pcall require] derive/omniscient_graph.lua
+   │     ├── [延迟 pcall require] derive/binding_factory.lua
+   │     ├── [延迟 pcall require] derive/mutation_ast.lua
+   │     └── [延迟 pcall require] derive/effect_model.lua
+   注：dirty_map.lua 由 omniscient_graph 加载，event_router.lua 由 binding_factory 加载
```

### F4：S4 步骤删除

```diff
  # Section 5 实施步骤 - 第二阶段
- | S4 | 更新 `nebula.nelua` 加载顺序 | `nebula_core` → `nebula_sugar` → `nebula_builtins` |
+ | S4 | （已删除）Facade 已处理加载顺序，nebula.nelua 无需修改 |
```
