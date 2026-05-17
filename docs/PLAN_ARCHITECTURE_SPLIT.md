# Nebula 架构拆分方案

**创建日期**：2026-05-17
**基准状态**：Era III | 77/77 回归全绿 | nebula_core.nelua 2277 行
**审计基准**：`docs/PLAN_ARCHITECTURE_AUDIT.md`

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

### `nebula_core.nelua` 内部结构

```
L001-L094   平台检测（NEBULA_TARGET / NEBULA_LINUX_DISPLAY）—— 编译期 ## 块
L096-L103   require "nebula_types" + require "nebula_constants"（已拆分 ✅）
L104-L1568  ★ 编译期推导引擎（约 1465 行）
  L107-L138     nebula_registry + nebula_annotate
  L140-L479     shape parser + Uniform 布局生成器
  L481-L644     WGSL 着色器生成器（+ shader_compose / pipeline_factory / interaction_factory 加载）
  L646-L1170    nebula_derive 核心：gen_state_enum/machine/context + 注入
  L1172-L1314   nebula_derive_text_visual / nebula_derive_slug_text_visual
  L1316-L1372   nebula_derive_dense_text_visual
  L1374-L1539   nebula_derive（主入口，分发到上述各路径）
  L1541-L1568   nebula_derive_app
L1570-L1952 ★ 语法糖 API（约 383 行）
  L1582-L1616   nebula_auto_states
  L1618-L1665   nebula_inject_buffers
  L1667-L1717   nebula_component
  L1719-L1782   nebula_editor_visual
  L1784-L1942   nebula_visual（L2 层）
L1954-L2277 ★ Builtin 注册表 + nebula_app（约 324 行）
  L1962-L1962   _nebula_builtins = _nebula_builtins or {}
  L1964-L2268   nebula_app（一站式 App 声明糖）
L2269-L2277   空白
```

### 模块依赖关系

```
nebula_core.nelua
  ├── derive/shader_compose.lua      (L497)
  ├── derive/pipeline_factory.lua     (L502)
  ├── derive/interaction_factory.lua  (L507)
  ├── derive/layout_engine.lua        (L512)
  ├── derive/app_factory.lua          (L517)
  ├── derive/axiom_validator.lua      (L522)
  ├── derive/gap_buffer_factory.lua   (L527)
  └── derive/highlight_factory.lua    (L532)

nebula_sugar.nelua（待创建）
  ├── nebula_core.nelua              (require "nebula_core" — nebula_annotate/derive)
  ├── derive/app_factory.lua          (nebula_app_begin/end/register_component/...)
  └── derive/nebula_config.lua        (DEFAULT_WIN_WIDTH 等)

nebula_builtins.nelua
  ├── nebula_core.nelua              (require "nebula_core" — nebula_component, nebula_register_builtin)
  └── nebula_sugar.nelua             (无直接依赖)

nebula_apps.nelua
  ├── nebula_core.nelua              (require "nebula_core" — 框架 API)
  └── nebula_apps.nelua 自生成代码     (nebula_editor_main, nebula_terminal_main)

nebula.nelua（统一入口）
  ├── cstdlib_bindings.nelua
  ├── nebula_core.nelua
  ├── nebula_sugar.nelua              (新增)
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
| L481-L608 | `nebula_gen_wgsl_shader` / `detect_shader_features` | 着色器生成 |
| L610-L644 | `nebula_gen_wgsl_shader_from_fields` | 手动字段着色器 |
| L646-L1116 | `gen_state_enum` / `gen_state_machine` / `gen_context_for` / `gen_update_for` | 代码生成 helpers |
| L1048-L1170 | `gen_text_context_for` + `nebula_derive_text_visual` | 文本 Visual 派生 |
| L1172-L1314 | `nebula_derive_slug_text_visual` | Slug 文本派生 |
| L1316-L1372 | `nebula_derive_dense_text_visual` | DenseText 派生 |
| L1374-L1539 | `nebula_derive`（主入口） | 统一派生入口 |
| L1541-L1568 | `nebula_derive_app` | App 派生入口 |

**依赖的 derive/*.lua 模块**：
- `derive/shader_compose.lua`
- `derive/pipeline_factory.lua`
- `derive/interaction_factory.lua`
- `derive/layout_engine.lua`
- `derive/app_factory.lua`
- `derive/axiom_validator.lua`
- `derive/gap_buffer_factory.lua`
- `derive/highlight_factory.lua`

**对外暴露的 API**：
```
nebula_registry          (全局表)
nebula_annotate          (注册 Visual 规格)
nebula_derive            (生成 State + SM + Context + Pipeline)
nebula_derive_app        (生成 App record + init/update/draw)
nebula_derive_text_visual
nebula_derive_slug_text_visual
nebula_derive_dense_text_visual
nebula_gen_uniform_layout
nebula_gen_wgsl_shader
```

### 2.2 `nebula_sugar.nelua`（约 390 行）

**职责**：高层语法糖 API。为开发者提供声明式、低样板代码的接口。

**包含内容**（从 `nebula_core.nelua` 提取 L1570-L2277）：

| 行号范围 | 内容 | 说明 |
|:---|:---|:---|
| L1570-L1578 | `NEBULA_THEME_DEFAULTS` | 编译期主题表 |
| L1582-L1616 | `nebula_auto_states` | 从 primitives 推导 states |
| L1618-L1665 | `nebula_inject_buffers` | 前置 buffer 类型注入 |
| L1667-L1717 | `nebula_component` | 合并 annotate + derive |
| L1719-L1782 | `nebula_editor_visual` | 编辑器 Visual 自动生成 |
| L1784-L1942 | `nebula_visual` | L2 层 Visual 声明糖 |
| L1954-L1962 | `_nebula_builtins` 注册表 | Builtin Producer 工厂 |
| L1964-L2268 | `nebula_app` | 一站式 App 声明糖 |

**依赖**：
- `require "nebula_core"`（访问 `nebula_annotate` / `nebula_derive` / `nebula_derive_app`）
- `derive/app_factory.lua`（访问 `nebula_app_begin/end` 等注册 API）
- `derive/nebula_config.lua`（DEFAULT_WIN_WIDTH 等常量）

**对外暴露的 API**：
```
NEBULA_THEME_DEFAULTS
nebula_auto_states
nebula_inject_buffers
nebula_component        (L1 Sugar)
nebula_editor_visual
nebula_visual           (L2 Sugar)
nebula_app              (L2 App Sugar)
nebula_register_builtin
_nebula_builtins
```

### 2.3 `nebula_core.nelua`（约 100 行，Facade）

**职责**：统一加载入口。向后兼容——任何 `require "nebula_core"` 的代码不受影响。

**新内容**：
```lua
-- =============================================================================
-- nebula_core.nelua — 统一加载入口（Facade）
-- =============================================================================

-- 平台检测（编译期 ## 块）
##[[ ... NEBULA_TARGET 检测 ... ]]

-- 已提取的模块
require "nebula_types"
require "nebula_constants"

-- 编译期推导引擎
require "nebula_derive_engine"

-- 语法糖 API
require "nebula_sugar"
```

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
| V3 | 复制当前 `nebula_core.nelua` 到 `nebula_derive_engine.nelua` 和 `nebula_sugar.nelua` | 文件就位 |

### 第二阶段：nebula_core 拆分

| 任务 | 内容 | 验收 |
|:---|:---|:---|
| S1 | 从 `nebula_core.nelua` 提取 L104-L1568 → `nebula_derive_engine.nelua` | 文件独立可编译 |
| S2 | 从 `nebula_core.nelua` 提取 L1570-L2277 → `nebula_sugar.nelua` | 文件独立可编译 |
| S3 | 重写 `nebula_core.nelua` 为 Facade（加载 types + constants + derive_engine + sugar） | require 链正确 |
| S4 | 更新 `nebula.nelua` 加载顺序 | `nebula_core` → `nebula_sugar` → `nebula_builtins` |
| S5 | 77/77 回归测试全绿 | **必须通过** |
| S6 | 32 demo 全部编译通过 | **必须通过** |
| S7 | CI 全量通过 | **必须通过** |

### 第三阶段：清理与验证

| 任务 | 内容 | 验收 |
|:---|:---|:---|
| C1 | 更新文档索引中的文件路径引用 | 文档一致性 |
| C2 | 更新 `build.sh` 中的文件列表 | 构建系统正确 |
| C3 | 更新 CI 静态分析覆盖范围 | 覆盖新文件 |
| C4 | 各子模块行数均 <800 行 | 复杂度达标 |

---

## 6. 拆分后的项目结构

```
src/
├── nebula.nelua                    # 统一入口（1 行 require）
├── nebula_core.nelua               # Facade（~100 行）← 拆分后
├── nebula_derive_engine.nelua      # ★ 编译期推导引擎（~1465 行）← 新增
├── nebula_sugar.nelua              # ★ 语法糖 API（~390 行）← 新增
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
    ├── app_factory.lua             # App 编排
    ├── pipeline_factory.lua        # 管线生成
    ├── shader_compose.lua          # 着色器组合
    ├── interaction_factory.lua     # 交互原语
    ├── layout_engine.lua           # 布局引擎
    ├── axiom_validator.lua         # 公理校验
    ├── gap_buffer_factory.lua      # Buffer 生成
    ├── highlight_factory.lua       # 语法高亮
    ├── dirty_map.lua               # ★ Phase 5.0 dirty bit
    ├── omniscient_graph.lua        # ★ Phase 5.0 全知图
    ├── binding_factory.lua         # ★ Phase 5.0 绑定生成
    ├── mutation_ast.lua            # ★ Phase 5.0 AST 解析
    ├── effect_model.lua            # ★ Phase 5.0 Effect 模型
    └── event_router.lua            # ★ Phase 5.0 事件路由
```

---

## 7. 风险评估与缓解

| 风险 | 影响 | 概率 | 缓解措施 |
|:---|:---|:---|:---|
| require 循环依赖 | 编译失败 | 低 | 严格单向依赖：core → derive_engine → sugar |
| ## 块中的全局变量跨文件不可见 | 功能失效 | 中 | `nebula_registry` 等全局变量保留在 derive_engine 中，sugar 通过 require 访问 |
| nebula_app 中引用 derive_engine 内部函数 | 编译错误 | 低 | 在 sugar 中显式 require "nebula_derive_engine" |
| CI 编译时间增加 | 性能退化 | 低 | Facade 模式增加 1 层 require，Nelua 编译期开销可忽略 |
| 文档路径失效 | 开发者困惑 | 低 | 拆分完成后同步更新所有文档引用 |

---

## 8. 不做列表

| 排除项 | 理由 |
|:---|:---|
| 重写 wgpu_bindings 为自动生成 | 投入产出比过低，P1-6 Deferred 验证后再决策 |
| 拆分 derive/*.lua 模块 | 已经是独立文件，职责清晰 |
| 拆分 nebula_builtins.nelua | 554 行，单一职责（Producer 生成），无需拆分 |
| 拆分 app.nelua（除非 V1 验证有残留） | 624 行，职责为 App 编排 + 事件循环，合理 |
| 引入宏系统或模板引擎 | 超出当前架构范围，留给 Era IV |

---

## 9. 验收标准

### 文件行数目标

| 文件 | 当前行数 | 目标行数 | 阈值 |
|:---|:---|:---|:---|
| `nebula_core.nelua` | 2277 | ~100 | <200 |
| `nebula_derive_engine.nelua` | — | ~1465 | <1600 |
| `nebula_sugar.nelua` | — | ~390 | <500 |
| `app.nelua` | 624 | ≤624 | <800 |

### 功能目标

- [ ] 77/77 回归测试全绿
- [ ] 32 demo 全部编译通过
- [ ] CI 全量通过（smoke/compile-linux/compile-windows/compile-wasm/headless-render/static-analysis）
- [ ] `require "nebula_core"` 向后兼容（所有现有代码无需修改）
- [ ] `require "nebula"` 统一入口不受影响

### 架构目标

- [ ] 所有核心文件 <800 行
- [ ] 依赖方向清晰：`nebula.nelua` → `nebula_core.nelua` → `nebula_derive_engine.nelua` / `nebula_sugar.nelua`
- [ ] 无循环依赖
- [ ] 每个模块有明确的职责描述（文件头部注释）
