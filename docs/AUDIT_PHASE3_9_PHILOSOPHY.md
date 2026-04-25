# Nebula Phase 3.9 设计哲学合规性审计报告

**审计人**：Manus AI
**日期**：2026-04-26
**审计范围**：`src/` 全部 6,987 行框架代码、`src/derive/` 全部 6 个编译期生成器、`examples/` 全部 9 个 Demo、`tests/` 全部 18 个冒烟测试、`tools/run_all_tests.sh` 回归套件
**审计依据**：`ARCHITECTURE_GRAND_PLAN.md`（三大公理、元规则 Π、五条红线、八大原语）

---

## 0. 审计结论摘要

经过对项目最新代码的逐文件审计，**核心框架代码（src/）在 Phase 3.9 中已高度合规**，八大原语中的 5 个已完整落地（原语 1、2、3、4、5），2 个部分落地（原语 6、8），1 个尚未启动（原语 7）。但 **examples/ 目录存在严重的"架构时间分裂"问题**——9 个 Demo 中仅 2 个使用了最新的 Phase 3.9 API，其余 7 个仍停留在 Phase 2.1 至 Phase 3.4.4 的旧架构上，构成了对三大公理和第五条红线的系统性违反。

| 维度 | 合规状态 | 详情 |
| :--- | :--- | :--- |
| 核心框架（src/） | **高度合规** | 三大公理无硬性违反；五条红线仅 text_runtime.nelua 中 malloc/free 需关注 |
| 已升级 Demo（2 个） | **完全合规** | form_demo、dynamic_list_demo 严格遵循 Phase 3.9 API |
| 旧 Demo（7 个） | **系统性违反** | 手动 WGPU 样板、绕过 App 编排、文本二等公民 |
| 测试套件 | **部分过时** | smoke_phase3_4_4.lua 编码了旧架构期望；编译回归测试锚定旧 Demo |

---

## 1. 核心框架代码审计

### 1.1 公理 A（编译期最大化原则）

> 任何能在编译期确定的事实，必须在编译期确定。

**审计结果：合规。**

核心框架的六个编译期生成器（`app_factory.lua`、`pipeline_factory.lua`、`shader_compose.lua`、`interaction_factory.lua`、`gap_buffer_factory.lua`、`layout_engine.lua`）均在 Nelua 宏展开阶段完成全部代码生成。运行时不存在虚函数分发、字符串查表或 `if reg.has_xxx then` 风格的特性开关。

`nebula_app_register_text` 和 `nebula_app_register_slot` 在编译期将文本联动逻辑和 Producer 函数名静态绑定到生成的 `update` / `draw` 代码中，运行时无分支判断。

**唯一瑕疵**：`interaction_factory.lua` 中 toggleable 原语的注入仍采用字符串后处理（第 457–460 行的 `source:sub` + 拼接），而非总纲领原语 6 所要求的统一 `NEBULA_PRIMITIVES` 注册表。这不构成公理 A 的违反（生成的代码本身是编译期确定的），但增加了维护脆弱性。

### 1.2 公理 B（生命周期严格分层原则）

> 只存在 L1（持久层，跨帧存活）和 L2（帧级层，单帧瞬时）两种内存生命周期。

**审计结果：合规。**

Phase 3.9 已完成以下关键修复：

| 修复项 | 状态 | 说明 |
| :--- | :--- | :--- |
| `flat_buf: [256]uint8` 从 Visual Record 中移除 | 已完成 | `get_text(out, max)` 改为接受调用方提供的栈上缓冲区（interaction_factory.lua 第 387–395 行） |
| `FrameArena` 内嵌于 App | 已完成 | `app_factory.lua` 自动在 `<App>` record 中注入 `arena: NebulaArena` 和 `_arena_backing` |
| `mark()` / `rewind()` 局部回收 | 已完成 | `nebula_arena.nelua` 第 177–195 行实现了检查点机制 |
| Slot Producer 数据托管 | 已完成 | `NebulaSlotView` 的实例数据完全在 FrameArena 中分配，每帧随 Arena 重置而销毁 |

**需关注**：`text_runtime.nelua` 中使用了 `malloc` / `free`（第 88、96、146 行）用于加载字体纹理图集的临时像素缓冲区。这属于一次性初始化操作（非帧级循环），且在上传到 GPU 后立即释放，因此不构成对公理 B 的违反。但它触碰了红线 1（"永不引入 GC"的延伸——避免堆分配），建议未来 Phase 4.1 中迁移到栈上定容缓冲区或 Arena 临时分配。

### 1.3 公理 C（形即渲染原则）

> 每一个 Visual 类型必须拥有一条专属的、按字段精确组合而成的渲染管线。

**审计结果：合规。**

Phase 3.7 已将管线生成器收敛为三条显式具名路径：

| 路径 | 触发条件 | 文件位置 |
| :--- | :--- | :--- |
| `gen_pipeline_standard_instanced` | 所有标准 Visual（默认路径） | pipeline_factory.lua 第 444 行 |
| `gen_pipeline_textured_vertex` | `text_mode == "ascii_sdf"` | pipeline_factory.lua 第 50 行 |
| `gen_pipeline_shadow` | `has_shadow == true` | pipeline_factory.lua 第 154 行 |

旧的 `gen_pipeline_simple` 和 `gen_pipeline_instanced` 已在 Phase 3.7 中删除（第 648–649 行有明确注释）。`shader_compose.lua` 中旧的 `nebula_compose_shader`（红色占位符）和 `nebula_compose_instanced_shader` 也已删除（第 3 行注释确认）。

### 1.4 五条红线审查

| 红线 | 状态 | 审查说明 |
| :--- | :--- | :--- |
| 1. 永不引入 GC | **合规** | 无 Lua 运行时参与；`text_runtime.nelua` 的 malloc/free 属一次性初始化 |
| 2. 永不引入运行时反射 | **合规** | 所有类型信息在编译期消解为静态字段访问 |
| 3. 永不让 L1 依赖 L2 | **合规** | `flat_buf` 已修复；Arena reset 后 L1 完全可用 |
| 4. 永不允许通用渲染器复活 | **合规** | 三条显式具名管线路径，无通用分发 |
| 5. 永不让 demo 写 50 行渲染样板 | **框架层合规，Demo 层违反** | 见第 2 节 |

### 1.5 八大原语落地状态

| 原语 | 名称 | 状态 | 说明 |
| :--- | :--- | :--- | :--- |
| 1 | 唯一管线生成器 | **已完成** | Phase 3.7 收敛为 3 条路径 |
| 2 | L1/L2 严格分区器 | **已完成** | `flat_buf` 已修复，`get_text` 改为栈上缓冲区 |
| 3 | 编译期 Text 一等公民 | **已完成** | `nebula_app_register_text` 在 Phase 3.9 落地 |
| 4 | 插槽即 Arena Producer | **已完成** | `nebula_app_register_slot` + Producer 模式在 Phase 3.9 落地 |
| 5 | 渲染循环 `nebula_frame_render` | **已完成** | Phase 3.8 落地，Phase 3.9 扩展支持文本渲染 |
| 6 | 原语统一注册中心 | **部分完成** | hoverable/clickable/focusable/editable 已统一生成；toggleable 仍用字符串后处理注入 |
| 7 | Layout 即 App Position 源 | **未启动** | `nebula_app_attach_layout` 仅存在于总纲领文档中，代码中无实现 |
| 8 | FrameArena 全局单例 | **部分完成** | Arena 已内嵌于 App 并自动管理；但 `text_runtime.nelua` 的初始化分配未迁移 |

---

## 2. Demo 层审计

### 2.1 合规 Demo（2 个）

**form_demo.nelua** 和 **dynamic_list_demo.nelua** 完全遵循 Phase 3.9 API：

- 使用 `nebula_app_begin` / `nebula_app_end` / `nebula_derive_app` 声明式编排
- 使用 `nebula_frame_render` 封装渲染循环，主循环仅 2–3 行
- 无手动 WGPU 样板代码（无 `wgpuDeviceCreateCommandEncoder`、无 `wgpuSurfaceGetCurrentTexture`）
- 文本组件通过 `nebula_app_register_text` 纳入一等公民编排
- 动态列表通过 `nebula_app_register_slot` + Producer 函数托管

### 2.2 违规 Demo（7 个）

以下 7 个 Demo 存在不同程度的设计哲学违反：

| Demo | 停留阶段 | 违反的公理/红线 | 具体问题 |
| :--- | :--- | :--- | :--- |
| **button_demo.nelua** | Phase 2.4 | 红线 5、公理 A | 手动 WGPU 渲染循环（~50 行样板）；未使用 `nebula_derive_app` / `nebula_frame_render` |
| **simple_rect_demo.nelua** | Phase 2.4 | 红线 5、公理 A | 同上；最原始的单矩形 Demo，完全手动 |
| **shadow_demo.nelua** | Phase 2.5 | 红线 5 | 4-Pass 阴影渲染手动编排；`nebula_frame_render` 的单 Pass 模型无法覆盖 |
| **layout_demo.nelua** | Phase 3.1 | 红线 5、公理 A | 手动 WGPU 渲染循环；虽使用编译期 Flexbox 布局，但未接入 App 编排 |
| **text_demo.nelua** | Phase 3.2.5 | 红线 5 | 手动 WGPU 渲染循环 + 7 处手动 `draw_buffer` 调用；纯文本展示 Demo |
| **login_demo.nelua** | Phase 3.4.4 | 红线 5、张力 4 | 手动 WGPU 渲染循环 + 手动 `process_text_input` / `set_text` / `draw_buffer`；文本仍是二等公民 |
| **uniform_layout_test.nelua** | Phase 2.1 | 无直接违反 | 纯编译期测试，无渲染循环；但作为 Demo 已无展示价值 |

### 2.3 Demo 层的核心问题

**问题 1：架构时间分裂（Architectural Time Fracture）**。9 个 Demo 横跨 Phase 2.1 至 Phase 3.9 共 8 个不同的架构时代。新开发者打开 `examples/` 目录时，会看到至少 3 种完全不同的编程范式，无法判断哪个是"正确的"写法。这直接违反了总纲领第 7 节所描述的"Nebula 该有的样子"——开发者应该只看到一种范式。

**问题 2：测试套件锚定旧架构**。`tools/run_all_tests.sh` 的 Part 2（编译回归测试）仍然编译所有 7 个旧 Demo，并且 `tests/smoke_phase3_4_4.lua` 显式断言 `login_demo.nelua` 中存在手动 `process_text_input` 和 `draw_buffer` 调用。这意味着如果将 login_demo 升级到 Phase 3.9 API，现有测试会**反向失败**。测试套件本身成为了阻碍架构演进的锚。

**问题 3：shadow_demo 的特殊性**。shadow_demo 使用 4-Pass 多 Pass 阴影渲染（3 个离屏 Pass + 1 个 Surface Pass），这与 `nebula_frame_render` 的单 Pass 模型在架构上不兼容。总纲领中 `gen_pipeline_shadow` 被保留为显式具名的特殊路径，但 `app_factory.lua` 和 `nebula_frame_render` 尚未提供多 Pass 编排能力。这是一个已知的架构缺口，而非 Demo 层的问题。

---

## 3. 综合评估与建议

### 3.1 框架层评估

Nebula 的核心框架代码在 Phase 3.9 中达到了**高度的哲学合规性**。三大公理无硬性违反，五条红线在框架层面全部守住。八大原语中的 5 个已完整落地，为开发者提供了声明式、零样板的编程体验。剩余的 2 个部分落地原语（原语 6 和原语 8）属于"可改进但不阻塞"的技术债务，1 个未启动原语（原语 7：Layout-App 桥接）属于路线图中 Phase 3.11 的规划工作。

### 3.2 Demo 层建议

Demo 层是当前项目中**最大的哲学债务来源**。建议采取以下行动：

**优先级 1（立即执行）——清理与重写**：

| 行动 | 目标 Demo | 说明 |
| :--- | :--- | :--- |
| 删除 | simple_rect_demo.nelua | 功能被 button_demo 完全覆盖，无独立展示价值 |
| 删除 | uniform_layout_test.nelua | 纯编译期测试，应迁移到 `tests/` 目录作为 Lua 冒烟测试 |
| 重写 | button_demo.nelua | 使用 `nebula_derive_app` + `nebula_frame_render`，作为最简单的入门 Demo |
| 重写 | layout_demo.nelua | 使用 `nebula_derive_app` + `nebula_frame_render` + 编译期 Flexbox 布局 |
| 重写 | login_demo.nelua | 参照 form_demo，使用 `nebula_app_register_text` 实现文本一等公民 |

**优先级 2（需框架支持）——暂时保留**：

| 行动 | 目标 Demo | 说明 |
| :--- | :--- | :--- |
| 保留并标注 | shadow_demo.nelua | 等待 `nebula_frame_render` 支持多 Pass 编排后再升级 |
| 保留并标注 | text_demo.nelua | 等待 `nebula_app_register_text` 支持独立文本展示（非绑定到 editable 组件）后再升级 |

**优先级 3（同步更新）——测试套件**：

- 更新 `tools/run_all_tests.sh` 中的编译回归测试，移除已删除 Demo 的编译目标
- 重写 `tests/smoke_phase3_4_4.lua`，使其断言新版 login_demo 使用 Phase 3.9 API
- 更新 `build.sh` 中的目标列表和注释

### 3.3 text_runtime.nelua 的 malloc/free

建议在 Phase 4.1（Unicode 全量支持）中将字体纹理加载改为使用栈上定容缓冲区或 Arena 临时分配，彻底消除运行时堆分配。当前的 malloc/free 用法属于一次性初始化，风险可控，不阻塞当前工作。

---

## 4. 审计数据汇总

### 4.1 代码规模

| 模块 | 文件数 | 总行数 | 说明 |
| :--- | :--- | :--- | :--- |
| 核心运行时（src/*.nelua） | 10 | 4,430 | renderer、nebula_core、app、arena、text_runtime 等 |
| 编译期生成器（src/derive/*.lua） | 6 | 2,557 | app_factory、pipeline_factory、shader_compose 等 |
| Demo（examples/*.nelua） | 9 | ~2,100 | 2 个合规 + 7 个违规 |
| 测试（tests/*.lua） | 18 | ~1,200 | Lua 冒烟测试 |

### 4.2 公理违反统计

| 公理 | 框架层违反数 | Demo 层违反数 |
| :--- | :--- | :--- |
| 公理 A（编译期最大化） | 0 | 5 个 Demo 未使用编译期 App 编排 |
| 公理 B（生命周期分层） | 0 | 0（旧 Demo 虽手动但未混淆 L1/L2） |
| 公理 C（形即渲染） | 0 | 0（每个 Visual 仍有专属管线） |
| 红线 5（50 行样板） | 0 | 6 个 Demo 包含手动 WGPU 渲染循环 |

---

## 参考文献

[1] `docs/ARCHITECTURE_GRAND_PLAN.md` — Nebula 架构总纲领，定义了三大公理、元规则 Π、五条红线与八大原语。
[2] `docs/REPORT_PHASE3_9_COMPLIANCE.md` — Phase 3.9 计划的合规性审查报告。
[3] `docs/DESIGN_PHASE1.md` — Phase 1 设计原则（零运行时开销、命名约定即契约）。
[4] `src/derive/pipeline_factory.lua` — Phase 3.7 管线生成器，三条显式具名路径。
[5] `src/derive/interaction_factory.lua` — 交互原语代码生成器，toggleable 字符串后处理。
[6] `src/derive/app_factory.lua` — Phase 3.9 App 编排工厂，文本一等公民与 Slot Producer。
[7] `src/text_runtime.nelua` — 文本运行时，含 malloc/free 用于字体纹理加载。
[8] `tools/run_all_tests.sh` — 回归测试套件，编译回归部分锚定旧 Demo。
