# Nebula 架构审计与整改方案

**创建日期**：2026-05-15
**审计范围**：全代码库（运行时 / 编译期代码生成 / 平台绑定 / 示例 / 测试 / 构建系统）
**基准状态**：Era III | 77/77 回归全绿 | PR #15 合入后

---

## 0. 审计方法论

本次审计覆盖以下维度：

1. **公理合规性** — 对照 Axiom A（阶段封闭）/ B（生命周期三层）/ C（形即渲染）逐条检查
2. **正确性与安全性** — GPU 资源管理、内存边界、错误路径
3. **可扩展性** — 新增管线/组件/平台的改动半径
4. **代码质量** — 重复度、耦合度、魔法数字
5. **工程化** — 测试覆盖、CI 可靠性、构建系统

每个问题标注 **P0**（影响正确性/安全性）、**P1**（影响可维护性/可扩展性）、**P2**（技术债）、**P3**（工程化缺口）。

---

## 1. 问题清单

### 1.1 P0 — 正确性与安全性

| # | 问题 | 文件 | 位置 | 描述 | 修复方案 |
|:--|:-----|:-----|:-----|:-----|:---------|
| P0-1 | GPU 资源泄漏：init 失败路径 | `renderer.nelua` | L169-234 | `NebulaRenderer:init` 渐进式获取 instance→surface→adapter→device，中途失败不释放已获取资源。如 adapter 失败时 instance+surface 泄漏。 | 引入 `goto cleanup` 模式或 defer 链，失败时逆序释放已获取资源。 |
| P0-2 | GPU 资源泄漏：render target | `renderer.nelua` | L891-895 | `nebula_create_render_target` 中 view 创建失败时已创建的 texture 未释放。对比 `nebula_upload_texture`（L761）有正确释放。 | view 创建失败时调用 `wgpuTextureRelease(out_texture)` 后再 return false。 |
| P0-3 | deinit nilptr 守卫不一致 | `pipeline_factory.lua` | L726-732 | `gen_pipeline_standard_instanced` 的 deinit 无 nilptr 检查；`gen_pipeline_shadow`（L477-511）和 `gen_pipeline_dense_text`（L1131-1138）有检查。partial init 后 deinit 会 crash。 | 统一所有管线 deinit 生成器，emit `if X ~= nilptr then release(X) end` 模式。 |
| P0-4 | 搜索替换越界 | `app.nelua` | L652-669 | `nebula_search_replace_current` 逐字符 `insert_char` 不检查 gap buffer 容量。替换串比搜索串长且 buffer 接近满时溢出。 | 替换前检查 `buf.gap_size >= (replace_len - search_len)`，不足时中止并设 overflow 标记。 |
| P0-5 | 高亮数组越界 | `nebula_builtins.nelua` | L293 (生成代码) | `hl_colors: [1024]uint32` 与 flatten buffer 共用 1024 上限，highlight dispatch 存在 off-by-one 溢出可能。 | flatten 上限改为 `1023`，highlight dispatch 的 `line_len` 参数取 `min(actual_len, 1023)`。 |
| P0-6 | Slug 顶点栈溢出 | `nebula_core.nelua` | L1177, L1324 | 编译期生成 `[max_vertices]NebulaSlugVertex`，max_chars=256 时为 120KB 栈分配，超出 WASM 默认栈（64KB）。 | 改为 L0 堆分配（App Record 字段）或设 `max_chars` 上限并 assert。 |

### 1.2 P1 — 架构性问题

| # | 问题 | 文件 | 描述 | 修复方案 |
|:--|:-----|:-----|:-----|:---------|
| P1-1 | God Module | `nebula_core.nelua` (2375行) | 类型系统、注解注册表、WGSL 生成、管线分发、交互分发、状态机生成、全部 sugar API 混在一个文件。 | 拆分为 `nebula_types.nelua`（类型+枚举）、`nebula_derive.nelua`（派生引擎）、`nebula_sugar.nelua`（sugar API）、`nebula_registry.nelua`（注册表）。 |
| P1-2 | 编辑器逻辑侵入框架（违反 Axiom B） | `app.nelua` L551-689 | ~140 行编辑器专属代码（搜索/替换状态、文件路径、修改标记、`nebula_editor_update_title` 等）定义在框架层。非编辑器应用被迫携带。 | 提取为 `nebula_editor.nelua` 模块，通过 `require` 按需引入。框架层仅保留 input 收集和 frame render。 |
| P1-3 | wgpu 绑定 48 处条件编译 | `wgpu_bindings.nelua` (1121行) | native/WASM 结构体大量重复定义。`WGPUShaderStage` 类型宽度不同（uint64 vs uint32），布局错误难以发现。 | 拆分为 `wgpu_types_shared.nelua` + `wgpu_types_native.nelua` + `wgpu_types_wasm.nelua`。共享类型定义一次，平台差异隔离到专属文件。 |
| P1-4 | ~~管线类型无扩展点~~ | `pipeline_factory.lua` | ~~硬编码 if/elseif/else 分发 5 种管线。~~ | ✅ 已修复：引入 `NEBULA_PIPELINES` 注册表 + `nebula_register_pipeline()` API，数据驱动分发。新增管线类型仅需 1 行注册调用。 |
| P1-5 | app_factory 线性膨胀 | `app_factory.lua` | 6 种组件类别 × 5 个 gen_app_* 函数。每新增一种类别需修改 5 个函数。 | **Deferred**：改动半径大（5 个 gen_app_* 函数 × 6 种类别各有不同逻辑），需分步实施。待组件类别数量进一步增长时再抽象 ComponentCategory 接口。 |
| P1-6 | WGPU 句柄类型擦除 | `wgpu_bindings_shared.nelua` L22-39 | 18 种 GPU 句柄全部 alias 到 `@pointer`，传错类型编译不报错。 | **Deferred**：Nelua 的 `<cimport, nodecl>` 要求类型与 C ABI 兼容，record 包装会破坏所有 C FFI 互操作。需要语言层面支持 distinct pointer 类型。 |
| P1-7 | 每帧仅消费一个按键 | `app.nelua` L180-186 | char queue 全量消费，但 key queue 每帧只弹出一个。高重复率按键场景下输入滞后。 | 改为 key queue 也全量消费，将 `key_pressed` 改为 `key_queue_snapshot: [N]NebulaKey` + `key_count`，或循环处理直到队列空。 |
| P1-8 | Surface 重配置代码重复 | `app.nelua` L317-337 / L433-454 | `nebula_frame_render` 与 `nebula_frame_render_multipass` 中 surface resize + config 逻辑完全相同（~20 行）。 | 提取为 `_nebula_reconfigure_surface(renderer, width, height)` 共享函数。 |
| P1-9 | multiline_editable 420 行单体函数 | `interaction_factory.lua` L433-852 | cursor 移动逻辑 8 方向 × 2（plain + shift）= 16 段近似代码。`_emit_ml_cursor_move` helper 存在但为死代码。 | 复用 `_emit_ml_cursor_move`，通过参数控制是否更新 sel_anchor。删除死代码。 |

### 1.3 P2 — 代码质量与技术债

| # | 问题 | 涉及文件 | 描述 | 修复方案 |
|:--|:-----|:---------|:-----|:---------|
| P2-1 | UTF-8 解码重复 4 次 | `text_runtime.nelua` ×3, `nebula_apps.nelua` ×1 | 相同的 `b0 < 0x80 / 0xE0 / 0xF0` 分支逻辑。 | 提取 `nebula_utf8_decode(bytes, i, len) -> (codepoint, byte_len)` 共享函数。 |
| P2-2 | WASM RenderPassAttachment 重复 6 次 | `pipeline_factory.lua` | shadow 管线 3 pass × WASM/native 分支。 | 提取 `_emit_render_pass_attachment(target_view, wasm_mode)` Lua helper。 |
| P2-3 | C stdlib 声明重复 4 次 | 3× `font_preprocessor*.nelua`, `nebula_arena.nelua` | `fopen/fclose/malloc/free/memset` 各自独立声明。 | 创建 `src/cstdlib_bindings.nelua`，统一声明后 require 引入。 |
| P2-4 | `printf`/`snprintf` 重复声明 | `app.nelua` L548, `renderer.nelua` L28 | 两文件独立声明相同函数。 | 合并到共享绑定模块。 |
| P2-5 | `_extract_base` 逻辑内联 3 次 | `app_factory.lua` L173/L227/L283 | helper 函数已存在（L38）但 3 处未使用。 | 统一调用 `_extract_base()`。 |
| P2-6 | ButtonVisual 重复 8 次 | 8 个 example 文件 | 相同的 record 字段 + 状态机 + derive 调用。 | 创建 `examples/common/button_visual.nelua` 共享定义，各 demo require 引入。 |
| P2-7 | WASM 主循环样板重复 6 次 | 6 个 example 文件 | 15-20 行相同的全局变量 + frame callback。 | 提供 `nebula_wasm_main(app, renderer)` 宏，一行生成 WASM 主循环。 |
| P2-8 | 魔法数字散落 | 全代码库 | `18.0`（行高）、`124`（pipe）、`1280×800`（窗口）、高亮 RGBA 值等无常量名。 | 创建 `src/nebula_constants.nelua`（运行时）和 `src/derive/nebula_config.lua`（编译期），集中定义所有常量。 |
| P2-9 | 主题双色彩表示 | `nebula_theme.nelua` L21-100 | uint32 packed RGBA 与 `Color{r,g,b,a}` float 混用。 | 统一为 `NebulaColor` record，提供 `to_packed() -> uint32` 和 `to_float() -> Color` 转换。 |
| P2-10 | 主题无运行时切换 | `nebula_theme.nelua` | 100 个独立函数返回硬编码色值，无 theme struct。 | 引入 `NebulaTheme` record 包含所有色值字段，全局 `_nebula_active_theme` 指针，函数改为读取 active theme 字段。 |
| P2-11 | 回调 callback 类型擦除 | `wgpu_bindings.nelua` L416-448 | `WGPURequestAdapterCallbackInfo.callback` 类型为 `pointer`，签名错误编译不报错。 | 定义 typed function pointer 别名。 |
| P2-12 | dropdown hack: y=-1000 隐藏 | `dropdown_demo.nelua` L287-298 | 无 visibility/enabled 标志，用屏幕外坐标模拟隐藏。 | 框架层新增 `visible: boolean` 字段，draw 时跳过 visible=false 的组件。 |

### 1.4 P3 — 测试与工程化

| # | 问题 | 涉及 | 描述 | 修复方案 |
|:--|:-----|:-----|:-----|:---------|
| P3-1 | 冒烟测试仅文本匹配 | `tests/smoke_*.lua` (58个) | 全部用 `src:find()` 正则匹配源码，验证代码"存在"而非"正确"。 | 分层：L1 保留现有 smoke test；L2 新增编译期生成代码快照测试（golden file）；L3 新增运行时行为测试（headless + assert）。 |
| P3-2 | Sugar API 零测试覆盖 | `nebula_visual` / `nebula_app` / `init_themed` | 新 API 无专项冒烟测试。 | 新增 `tests/smoke_sugar_api.lua`，覆盖 sugar API 生成的代码结构。 |
| P3-3 | 无视觉回归测试 | CI headless-render | headless job 运行独立 C 测试，不测试实际 demo 渲染输出。 | 引入 golden image 比对：headless 渲染 → 截图 → pixelmatch 与基线比较。 |
| P3-4 | Windows CI 吞错误 | `.github/workflows/ci.yml` L158 | `\|\| true` 掩盖链接失败。 | 改为 `\|\| echo "::warning::Windows link failed"` 并设 `continue-on-error: true`，让 CI 显示警告而非静默通过。 |
| P3-5 | Nelua commit hash 重复 6 次 | `.github/workflows/ci.yml` | 同一 hash `a58450563e2d` 出现 6 处。 | 提取为 workflow-level `env.NELUA_VERSION` 变量，或创建 composite action。 |
| P3-6 | 静态分析仅覆盖 4 个 demo | `.github/workflows/ci.yml` L257 | cppcheck 只扫描 button/form/slider/dropdown，复杂 demo（editor/code_browser）排除在外。 | 扩展到全部生成 C 代码的 demo，或至少覆盖 top-5 复杂 demo。 |
| P3-7 | build.sh 32 项手动白名单 | `build.sh` L50 | 新 demo 必须手动加入 case 语句。 | 改为自动发现 `examples/*.nelua`，或使用 Makefile/manifest 文件。 |
| P3-8 | macOS 声明未实现 | `renderer.nelua`, `glfw_bindings.nelua` | `setup_wgpu.sh` 列出 macOS 支持，但 surface 创建和 native 绑定无 macOS 分支。 | 要么实现 macOS 路径（CocoaWindow + MetalLayer），要么从 setup_wgpu.sh 移除 macOS 声明并在 README 注明。 |
| P3-9 | 旧 API 示例未迁移 | 24 个 example | 24/34 demo 用旧 API（手动 init/cleanup），与新 sugar API 不一致。 | 分批迁移：先迁移 5 个基础 demo（button/login/form/layout/slider），验证 sugar API 完整性后迁移剩余。 |
| P3-10 | WASM 剪贴板未适配 | `glfw_bindings.nelua` L168-169 | `glfwGet/SetClipboardString` 无 WASM 条件编译守卫。Emscripten 环境下静默失败。 | 添加 `## if NEBULA_TARGET ~= 'wasm'` 守卫，WASM 下提供 stub 或 navigator.clipboard 异步桥接。 |

---

## 2. 实施计划

### 第一梯队：安全修复（P0 全部）

**目标**：消除所有正确性与安全性风险。零行为变更，仅修复错误路径。

| 任务 | 来源 | 文件 | 预计改动量 | 验收标准 |
|:-----|:-----|:-----|:-----------|:---------|
| T1.1 GPU init 失败路径修复 | P0-1 | `renderer.nelua` | ~30 行 | init 任意步骤失败后，前序资源全部释放；手动测试各失败点 |
| T1.2 render target 泄漏修复 | P0-2 | `renderer.nelua` | ~3 行 | view 创建失败时 texture 被释放 |
| T1.3 deinit nilptr 守卫统一 | P0-3 | `pipeline_factory.lua` | ~15 行 | 所有 5 种管线 deinit 均有 nilptr 检查 |
| T1.4 搜索替换容量检查 | P0-4 | `app.nelua` | ~10 行 | 替换操作前检查 gap 空间，不足时中止 |
| T1.5 高亮数组边界修复 | P0-5 | `nebula_builtins.nelua` | ~5 行 | flatten 上限与 hl_colors 大小一致，无越界 |
| T1.6 Slug 顶点栈改堆 | P0-6 | `nebula_core.nelua` | ~20 行 | Slug 顶点数组改为 App Record 字段（L0 堆分配），WASM 不再栈溢出 |

**验收**：77/77 回归全绿 + 新增 P0 修复专项冒烟测试

---

### 第二梯队：架构拆分（P1-1 ~ P1-3）

**目标**：降低核心模块复杂度，建立清晰的模块边界。

| 任务 | 来源 | 改动半径 | 验收标准 |
|:-----|:-----|:---------|:---------|
| T2.1 拆分 nebula_core.nelua | P1-1 | 新增 3 文件，原文件保留为 facade | 各子模块可独立 require；全量编译通过 |
| T2.2 提取编辑器模块 | P1-2 | 新增 `nebula_editor.nelua`，app.nelua 减 ~140 行 | 非编辑器 demo 编译产物不含搜索/替换代码 |
| T2.3 拆分 wgpu_bindings | P1-3 | 新增 2 文件（shared + platform） | 条件编译块从 48 降至 <5 |

**验收**：77/77 回归全绿 + 模块行数均 <800 行

---

### 第三梯队：扩展性改造（P1-4 ~ P1-9）

**目标**：建立数据驱动的扩展机制，降低新增功能的改动半径。

| 任务 | 来源 | 描述 | 验收标准 |
|:-----|:-----|:-----|:---------|
| T3.1 管线注册表 | P1-4 | `NEBULA_PIPELINES` 数据驱动分发，对标 `NEBULA_PRIMITIVES` | 新增一种管线类型仅需 1 个文件 + 1 行注册 |
| T3.2 ComponentCategory 抽象 | P1-5 | gen_app_* 改为遍历注册 category | 新增组件类别仅需实现接口，无需改 gen_app_* |
| T3.3 WGPU 句柄类型安全 | P1-6 | 17 种句柄改为 distinct record | 传错类型编译报错 |
| T3.4 Key queue 全量消费 | P1-7 | key queue 改为 per-frame batch | 高重复率按键无滞后 |
| T3.5 Surface 重配置提取 | P1-8 | 共享 helper 函数 | 代码重复消除 |
| T3.6 multiline cursor 重构 | P1-9 | 复用 `_emit_ml_cursor_move`，删除死代码 | interaction_factory 减 ~100 行 |

**验收**：77/77 回归全绿 + 新增管线/组件的 demo 验证

---

### 第四梯队：技术债清理（P2）

**目标**：消除代码重复，统一约定。

| 批次 | 任务 | 来源 |
|:-----|:-----|:-----|
| B1 共享绑定 | 创建 `cstdlib_bindings.nelua`，统一 printf/malloc/fopen 声明 | P2-3, P2-4 |
| B2 UTF-8 统一 | 提取 `nebula_utf8_decode` 共享函数 | P2-1 |
| B3 代码生成 helper | 提取 WASM RenderPassAttachment + `_extract_base` 复用 | P2-2, P2-5 |
| B4 主题系统升级 | 引入 `NebulaTheme` record，统一色彩表示，支持运行时切换 | P2-9, P2-10 |
| B5 常量集中化 | 创建 `nebula_constants.nelua` + `nebula_config.lua` | P2-8 |
| B6 示例共享 | 创建 `examples/common/` 目录，提取 ButtonVisual 等共享定义 | P2-6, P2-7 |
| B7 框架增强 | 组件 visible 标志 + 回调类型安全 | P2-11, P2-12 |

---

### 第五梯队：工程化强化（P3）

**目标**：提升测试覆盖与 CI 可靠性。

| 批次 | 任务 | 来源 |
|:-----|:-----|:-----|
| C1 测试分层 | L2 golden file 测试 + L3 headless 行为测试 | P3-1, P3-2, P3-3 |
| C2 CI 改进 | Nelua hash 提取为变量 + Windows 改 warning + 静态分析扩展 | P3-4, P3-5, P3-6 |
| C3 构建系统 | build.sh 自动发现 demo + WASM 剪贴板适配 | P3-7, P3-10 |
| C4 示例迁移 | 分批迁移 24 个旧 API demo 到 sugar API | P3-9 |
| C5 平台声明对齐 | macOS 实现或移除声明 | P3-8 |

---

## 3. 优先级排序原则

1. **安全性不可妥协**：P0 全部在第一梯队完成
2. **拆分先于扩展**：先降复杂度（T2），再加扩展机制（T3）
3. **每个梯队独立可验收**：每个梯队完成后全量回归必须绿色
4. **不破坏公理**：所有改动必须维持 Axiom A/B/C 合规

---

## 4. 不做列表

| 排除项 | 理由 |
|:-------|:-----|
| 重写 wgpu_bindings 为自动生成 | 投入产出比过低，手动维护 + 拆分足够 |
| 引入第三方测试框架 | Lua 内建 assert 够用，保持零依赖 |
| 支持多窗口 | 超出当前架构范围，留给 Era IV |
| 动画系统 | 属于新功能而非架构修复，独立规划 |
| Rope/Piece Table | Gap Buffer 当前足够，超大文件支持为独立 Phase |

---

## 5. 维护指南

- 本文档随整改进展更新，每完成一个梯队将对应条目标记为 ✅
- 新发现的架构问题追加到对应 P 级别表格中
- 整改完成后本文档移至"归档"区，在 `STATUS.md` 中更新状态
