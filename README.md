# Nebula GUI Compiler

**Nebula** 是一个用编译期元编程把"声明意图"翻译成"等价手写代码"的 GUI 编译器。

Nebula 的目标是成为一个**工业级 GUI 基础设施**，它结合了：
- **Qt 的跨平台能力**：源码级支持 Linux (X11/Wayland), Windows, Web。
- **ImGui 的开发效率**：零样板代码，极简的 API 调用。
- **SwiftUI 的声明式体验**：纯声明式的 UI 描述，编译期自动推导布局与交互。

核心主张是**阶段封闭性**：
> 每个操作必须归属于其输入最早全部可知的阶段。后一阶段不得执行前一阶段的操作，前一阶段的输出是后一阶段的不可变输入。

---

## 当前状态

**Era III | Code Browser Demo + CI 全量覆盖 32 demo | 编辑器 19 行极限形态 | wgpu-native v29（2026-05-13）**

### 最近完成

| 里程碑 | 内容 | 关键 commit |
| :--- | :--- | :--- |
| **Code Browser Demo** | Monaco 风格代码浏览器——文件树面板（DenseText + POSIX C FFI + 懒加载扫描）+ 语法高亮编辑器（6 语言）+ 搜索/替换；可移植 `NebulaDirIter` C helper API（绕过 `struct dirent` 布局差异）；路径缓存溢出安全修复；CI 全量覆盖 32 demo + C 单元测试 | `df52377` |
| **Phase 5.0 Slot Layout** | `nebula_app_register_slot` 新增 `layout` 声明（direction/gap/padding/item_size/scroll_var）；`app_factory.lua` 编译期生成单态化定位循环（常量内联，零运行时分支）；Producer 不再手算坐标——框架自动覆写 pos/size；`dynamic_list_v2_demo.nelua` 验证通过；19/19 冒烟测试全绿 | — |
| **wgpu-native v29 绑定修正** | 恢复 `WGPUBindGroupLayoutEntry.bindingArraySize` + `WGPUVertexAttribute/WGPUVertexBufferLayout.nextInChain`；`WGPUShaderStage` uint32→uint64；所有 demo 编译通过 | — |
| **Era III 模块化拆分** | 5 个 builtin Producer 工厂 (`nebula_builtin_*`) 从 `nebula_core` 提取到 `nebula_builtins.nelua`；`nebula_editor_main` / `nebula_terminal_main` 提取到 `nebula_apps.nelua`；内置 `_nebula_builtins` 编译期注册表替代 if-else 分发链；`nebula_core` 净减少 930 行 → 497 行；24/24 demo 编译通过 | `634a362` |
| **Phase 4.9.1 终态收尾** | 7 项 sugar 改进全落地——`dense=N` 自动生成 DenseText + `builtin` 自动绑定 Producer + layout 字段提升 + children/row 简写 + cell 默认值 + `auto_editor_name` 推断 + editor_main 默认参数 + `text_editor_demo_v3.nelua`（19 行，原 886 行压缩 46.6x）+ 77/77 回归全绿 | `77973d0` |
| **Phase 4.6 语法统一化** | `nebula_main()` 泛用生成器（S1）+ builtin 隐含默认 dense（S2）+ nebula_app spec 缓存消除参数重复（S3）+ term_demo_v2: 489→16 行 (30.6x) + button_v2_demo: 147→18 行 (8.2x) + 77/77 回归全绿 | `849cec7` |
| ~~Terminal v2 方案~~ | `docs/PLAN_TERM_DEMO_V2.md` — sugar 化终端模拟器设计（489→55 行，8.9x），验证 nebula_app/dense/terminal_main 体系的通用性，新增 `nebula_terminal_main` 终端专用主循环模板 | `3bd1722` |
| **Phase 4.9 50 行终态收敛** | 5 层 Sugar 系统——L1 `nebula_highlight_pack`（多语言高亮一键注册）+ L2 `nebula_builtin_status_bar/search_bar/edit_area`（Producer 自动生成）+ L3 搜索交互内置（框架级全局变量 + `nebula_search_*` 辅助函数）+ L4 `nebula_editor_update_title` 等框架内建辅助 + L5 `nebula_editor_main`（主循环一行生成）+ `text_editor_demo_v2.nelua`（85 行，原 885 行压缩 10.4x）+ 77/77 回归全绿 | `67e16c6` |
| **Phase 4.8-S6 集成验收** | S1-S5 + NL 全功能协同验证——110 条集成冒烟测试覆盖 9 个维度（源文件完整性/S1 选区+剪贴板/S2 搜索+替换/S3 状态栏/S4 多语言高亮/S5 自动缩进/NL 嵌套布局/架构完整性/编译产物）+ text_editor_demo 871 行完整编辑器 + 76/76 回归全绿 | `c512367` |
| **Phase 4.8-S2 搜索与替换** | 固定布局方案（`flex_basis=24` 搜索栏始终占位，Producer 切换渲染内容）+ `Ctrl+F` 搜索 / `Ctrl+H` 替换 / `F3` 下一匹配 / `Escape` 关闭 + 朴素 O(n*m) 字符串匹配 + `MatchPos[512]` 固定数组（公理 B: 零堆分配）+ 匹配高亮（当前匹配亮黄 / 其他暗黄）+ `search_replace_current` / `search_replace_all` + 搜索栏激活时键盘事件拦截 + 53 条冒烟测试 + 75/75 回归全绿 | `c512367` |
| **Phase 4.8-S5 自动缩进 + Tab 处理** | `NebulaKey.ShiftTab` 枚举 + Tab 插入 4 空格 + Shift+Tab 移除至多 4 前导空格（`delete_range`）+ Enter 自动保持缩进（计算前导空格）+ `{`/`:` 结尾额外增加 4 空格缩进 + 30 条冒烟测试 + 74/74 回归全绿 | — |
| **Phase 4.8-S4 多语言语法高亮** | 6 种语言高亮规则（nelua/lua/c/python/json/markdown）+ `nebula_highlight_select` 编译期多语言注册 + `nebula_highlight_dispatch` 运行时分发 + `nebula_highlight_detect_ext` 文件扩展名自动检测（15 种扩展名映射）+ `_editor_highlight_id` 状态管理 + 47 条冒烟测试 + 73/73 回归全绿 | — |
| **Phase 4.8-S3 状态栏 + 光标行高亮** | 底部状态栏（`flex_basis=24` 固定高度 DenseText 组件）——显示文件名 + 修改标记 + 行列号 + 总行数 + 编码(UTF-8) + 行尾符(LF) + `fill_status_bar` Producer + `StatusBarDenseVisual` 声明 + `nebula_theme_bg_status/fg_status/fg_status_accent` 主题色 + 光标行高亮（`fill_edit_area` 中 `is_cursor_line` → `nebula_theme_bg_cursor_line`）+ 31 条冒烟测试 + 72/72 回归全绿 | — |
| **Phase 4.8-NL 嵌套布局支持** | `layout.container` 声明式嵌套容器实现——`nebula_app_register_layout_node` 纯布局容器注册（无 GPU 管线）+ `_build_container_node` 递归构建 + `_solve_layout` 拓扑感知挂载（`_layout_seq` 维持注册顺序）+ layout_engine 交叉轴自动拉伸修复（对齐 CSS Flexbox `align-items:stretch` 默认行为）+ `nebula_app()` sugar 识别无 type 组件为容器 + 51 条冒烟测试 + 71/71 回归全绿 | `b32547b` |
| **Phase 4.8-S1 选区 + 剪贴板** | 选区可视化（Shift+Arrow/Home/End 扩展选区）+ 系统剪贴板（Ctrl+C/V/X/A）+ 选区覆盖删除 + 正常移动重置锚点 + Producer 选区背景渲染 + `nebula_theme_bg_selected()` + 32 条冒烟测试 + 70/70 回归全绿 | `a09ecdf` |
| **Phase 4.5-S3 语法糖深化** | L2 层 API：`require "nebula"`（统一入口）+ `nebula_visual()`（从 primitives 自动推导 record 字段）+ `init_themed()`（NEBULA_THEME_DEFAULTS 编译期主题表驱动默认颜色）+ `nebula_frame_begin()`（帧循环整合）+ `button_v2_demo.nelua`（30 行极限形态，原 147 行压缩 ~5x）+ 52 条冒烟测试 + 70/70 回归全绿 | `d615c5d` |
| **Phase 4.7-S7-fix multiline_editable 修复** | multiline_editable 原语完整重写——字符输入直接操作 multi_buf（绕过 editable 的 gap_buf）、Enter 调用 `insert_newline()`、Backspace 调用 `merge_line_up()`、新增 Left/Right/Home/End/Delete 完整键盘支持 + `wgpu_bindings.nelua` TextureFormat 枚举值和 BindGroupLayoutEntry 布局修正（v29） | `856f326` |
| **Phase 4.7-S7 文本编辑器原型** | `text_editor_demo.nelua` — S1-S6 全集成验收（CJK 编辑 + DenseText 渲染 + 行号 + 语法高亮 + Undo/Redo + File I/O + Ctrl+S 保存 + 窗口标题状态显示）+ `NebulaKey.Save` + `glfwSetWindowTitle` 绑定 + `nebula_annotate` 存储 `max_lines` 修复 + **语法糖优化**：`nebula_theme`（内置暗色主题）+ `nebula_editor_visual`（自动生成 Visual record）+ `nebula_builtin_line_nums`（内置行号 Producer）+ 68/68 回归测试全绿 | — |
| **Phase 4.7-S6 File I/O** | `load_file(path)` / `save_file(path)` 方法生成（C stdio FFI 绑定）+ CRLF 处理 + 空文件 + POSIX 换行末尾 + roundtrip 验证 + 66/66 回归测试全绿 | `91560be` |
| **Phase 4.7-S5 Undo/Redo** | 编译期 `NebulaUndoStack` 类型生成 + `NebulaKey.Undo`/`Redo` 枚举 + Ctrl+Z/Y/Shift+Z 键映射 + `process_text_input` 全操作记录 + `nebula_inject_buffers` 自动注入 undo stack | `457fd62` |
| **Phase 4.5-S2 混合管线自动编排** | `nebula_app()` 的 `components` 数组自动检测 Visual 的 `text_mode`，dense 管线自动路由到 `nebula_app_register_dense_text`（消除 `dense_texts` 分离声明）+ highlight_sugar_demo（全糖化语法高亮编辑器，编排样板从 ~80 行→~15 行）+ 33 条冒烟测试 | — |
| **Phase 4.7-S4 语法高亮架构** | `highlight_factory.lua` 编译期模块（`nebula_highlight_rules` 规则注册 + `nebula_derive_highlighter` 扫描函数生成）+ 4 种 token 着色（关键字分组 + 行注释 + 字符串字面量 + 数字字面量）+ highlight_editor_demo（Nelua 语法高亮编辑器）+ 30 条冒烟测试 + 62/62 回归测试全绿 | — |
| **Phase 4.5 S1 语法糖 API** | `nebula_component`（合并 annotate+derive，自动推导 states/transitions）+ `nebula_inject_buffers`（自动注入 buffer 类型）+ `nebula_app`（一站式 App 编排）+ `nebula_auto_states`（从 primitives 推导状态枚举）+ button_sugar_demo + multiline_sugar_demo + 45 条冒烟测试 | — |
| **Phase 4.7-S3 行号显示** | flex_grow/flex_basis 布局支持 + 多列 DenseText 布局（行号栏固定宽度 + 编辑区弹性宽度）+ editor_with_lines_demo（双 DenseText 管线并排）+ 55/55 回归测试全绿 | `c4a7743` |
| **Phase 4.7-S2 DenseText 接入 App 编排** | `nebula_app_register_dense_text` API + Producer 模式 + App 自动管理 DenseText 管线生命周期（init/draw/deinit）+ dense_editor_demo（DenseText + multiline_editable + App 编排三者整合）+ 28 条冒烟测试 | — |
| **Phase 4.7-S1 CJK multiline 升级** | UTF-8 aware gap buffer（move_cursor_left_char 等 5 个新方法）+ CJK 显示宽度函数 + cjk_editor_demo + 43 条冒烟测试，editable 原语全面升级为 char-aware | — |
| **wgpu-native v29.0.0.0 绑定对齐** | 12 个结构体布局修复（新增字段、类型宽度、字段顺序），14/14 demo 编译通过，42/42 结构体尺寸验证 OK | `f051974` |
| **Phase 4.X-J JSON Viewer** | 只读 JSON 树形浏览器——递归下降解析器（4096 节点/64KB）+ One Dark 语法着色（key/string/number/bool/null）+ 折叠/展开 + 垂直滚动 + 行号（双 DenseText 管线）+ json_viewer_demo + 28 条冒烟测试 + 60/60 回归测试全绿 | `f9d4c10` |
| **Phase 4.7→4.5 调序方案** | 先做 4.7-S1~S4（编辑器前置）积累 4 个新 demo 样本，再设计 4.5 语法糖，避免过早固化 API | — |
| **Phase 4.X Terminal Emulator** | 终端模拟器原型——PTY + ANSI 解析器 + Dense Text 渲染，term_demo 编译运行通过 | `21ee560` |
| **Phase 4.X Step 1-5** | 高密度文本渲染通道——着色器组合 + 管线生成 + Record 定义 + 派生入口 + 辅助函数 + dense_text_demo（120×50 = 6000 字符网格）+ 65 条冒烟测试 | — |
| **Phase 4.2.3-S2** | CJK 运行时排版——零 HarfBuzz 依赖，O(log N) 表查找，CJK+ASCII 混排 Slug 渲染，cjk_text_demo | `a6336e5` |
| **Phase 4.2.3-S1** | GB2312 一级 3755 字 shaping 表生成（v3 直接 API，102.7 KB，3755/3755 映射成功，0 .notdef） | `c1cd8ee` |
| **交互原语行为验证** | 40 条运行时行为断言 + BUG-4/5/6 回归守护（Direction A） | `c424005` |
| **全代码库审计修复** | 修复 10 项问题（2 高危 BUG + 4 中危 BUG + 2 低危 BUG + 2 内存安全），43/43 回归 + 6 demo 编译验证通过 | `8647048` |
| **Phase 4.2.2 D-4.1-C** | Storage Buffer scalability benchmark PASSED — 1K=1.41ms, 5K=1.45ms, 10K=1.45ms, 退化+2.5%<20%阈值 | `ebd7333` |
| **Phase 4.2.3-S0** | HarfBuzz 绑定 + CJK shaping 预处理（zh-CN-common 20 字验证） | `afab95e` |
| **Phase 4.2.2-fix** | GPU 资源 deinit — 修复 ~40+ GPU 对象泄漏，公理 B 合规 | `2b2d9cb` |
| **Phase 4.3 S1-S3 + Task D** | 可编程原语注册表 + axiom_validator v2.0 三层防御 | `1fdc182` |
| **Phase 4.4 S1-S3** | 高级组件库 | `b9fee31` |

### 深度审计：已发现的未完成工作

> 以下基于 2026-04-30 对照规划文档的逐条代码审计。已标记为"已完成"的 Phase 中，存在以下结构性缺口。

| # | 来源 Phase | 缺口 | 状态 | 详情 |
|:--|:-----------|:-----|:-----|:-----|
| ~~1~~ | **4.3 S3** | ~~沙箱隔离~~ | ✅ 已修复 | Task D 实现 `axiom_validator` v2.0 三层防御（Proxy + Token 扫描 + NEBULA_INTRINSICS 白名单 + Trace），已在 `nebula_derive_app` 中接入编译流程 |
| ~~2~~ | **4.3 S3** | ~~契约校验未接入编译流程~~ | ✅ 已修复 | `nebula_validate_static_asserts()` + `nebula_validate_process_body()` 均已接入 `app_factory.lua:940-944` |
| ~~3~~ | **4.4 S1-S3** | ~~高级原语未内置到框架注册表~~ | ✅ 已修复 | `scrollable`、`dropdown_manager`、`multiline_editable` 已内置到 `interaction_factory.lua` 的 `NEBULA_PRIMITIVES`，用户只需在 `nebula_annotate` 中声明 `primitives = {...}` 即可使用，无需手动注册 |
| ~~4~~ | **4.2.2** | ~~D-4.1-C benchmark 未执行~~ | ✅ PASSED | `slug_bench.nelua` WSL2+llvmpipe Vulkan 运行时通过：1K=1.41ms/帧, 5K=1.45ms/帧, 10K=1.45ms/帧，退化+2.5% 远低于 20% 阈值。Storage Buffer 路径在 CJK 规模下完全可行。commit `ebd7333` |
| ~~5~~ | **4.X** | ~~剪贴板 API 未绑定~~ | ✅ 已修复 | `glfw_bindings.nelua` 已绑定 `glfwGetClipboardString` / `glfwSetClipboardString`；`editable` 原语支持 Ctrl+C/V/X/A 剪贴板操作 |
| ~~6~~ | **4.X** | ~~Unicode char callback 无消费者~~ | ✅ 已修复 | `editable` 原语已扩展为接受全 Unicode 可打印字符（UTF-8 编码插入），Ctrl+C/V/X/A 快捷键已集成 |

### 全代码库审计修复（2026-05-02）

> 基于 ~8,900 行核心代码 + ~3,200 行示例的全面审查，发现并修复以下问题（commit `8647048`）：

| # | 严重度 | 文件 | 问题 | 修复 |
|:--|:-------|:-----|:-----|:-----|
| ~~BUG-1~~ | **高** | `app.nelua` | WASM 帧回调将 renderer 指针误传为 app 指针 | ✅ 新增独立 `_nebula_ml_app` 全局指针 |
| ~~BUG-2~~ | **高** | `pipeline_factory.lua` | Shadow 管线 deinit() 无条件释放可能未初始化的 GPU 句柄 | ✅ 全部 21 个 release 调用加 nilptr 守卫 |
| ~~BUG-3~~ | **中** | `app_factory.lua` | `comp.prims` 从未填充，Phase 4.3 公理校验不触发 | ✅ register_component 从 nebula_registry 查询并填充 |
| ~~BUG-4~~ | **中** | `scrollable_demo.nelua` | hit-test 在滚动偏移应用之前执行 | ✅ 偏移应用移至 app:update() 之前 |
| ~~BUG-5~~ | **中** | `dropdown_demo.nelua` | 隐藏项过渡帧 hit-test 错位 | ✅ 位置更新移至业务逻辑之前 |
| ~~BUG-6~~ | **低** | `gap_buffer.nelua` | 与 factory 版本缺少 extract_range 方法 | ✅ 同步方法 + 交叉引用注释 |
| ~~MEM-1~~ | **高** | `renderer.nelua` | 重复 init() 泄漏 GPU 句柄 | ✅ init() 头部加重复初始化检测 |
| ~~MEM-2~~ | **中** | `text_runtime.nelua` | malloc/free 违反零堆设计 | ✅ 改为模块级静态缓冲区 |
| ~~MEM-3~~ | **中** | `app_factory.lua` | `_batch[N]` 栈分配可能溢出 WASM 栈 | ✅ 增加 128 实例上限 |
| ~~MEM-4~~ | **低** | `axiom_validator.lua` | 布尔笛卡尔 2^N 爆炸 | ✅ 阈值降至 2^6 + single-flip 覆盖 |

### Phase 4.3 — 可编程原语注册表（90/100）

- **S1**：`interaction_factory.lua` 完全元数据驱动——消除所有硬编码原语分支，暴露 `nebula_register_primitive(name, spec)` 公开 API
- **S2**：`draggable_value` 自定义原语端到端验证（slider_demo），67 条专项测试
- **S3**：字段冲突检测 + `static_asserts` 编译期契约校验
- **Task D**：`axiom_validator` v2.0 三层防御——① Proxy 类型感知 + 分支覆盖穷举 ② Token 扫描兜底 ③ NEBULA_INTRINSICS 白名单。已在 `nebula_derive_app` 编译流程中接入 `nebula_validate_process_body` + `nebula_validate_static_asserts`（`app_factory.lua:940-944`）
- ✅ 三种高级原语（scrollable/dropdown_manager/multiline_editable）已内置到 `NEBULA_PRIMITIVES` 注册表（缺口 #3 已修复）

### Phase 4.4 — 高级组件库（81/100）

- **S1**：`scrollable` 原语 + scissor rect 裁剪 + scrollable_demo
- **S2**：`dropdown_manager` 原语 + 弹出层 z-order 管理 + dropdown_demo
- **S3**：`multiline_editable` 原语 + `NebulaMultiBuf{N,L}` 编译期泛型类型 + multiline_editable_demo
- ✅ 三个高级原语已内置到框架注册表，用户声明即用（缺口 #3 已修复）

### Phase 4.X — 高密度文本渲染通道（85/100）

- **Step 1**：`nebula_compose_dense_text_shader` — Instanced + SDF Atlas WGSL 着色器（Storage Buffer per-char 数据，unpack4x8unorm 颜色解包）
- **Step 2**：`gen_pipeline_dense_text` — 管线代码生成（init/update_atlas/update_viewport/upload/draw/deinit 六方法）
- **Step 3**：`DenseCharInstance`（32B）+ `DenseTextUniforms`（16B）+ `nebula_pack_rgba8` 辅助
- **Step 4**：`nebula_derive_dense_text_visual` 派生入口 + `text_mode="dense"` 分发
- **Step 5**：`nebula_dense_grid_fill_instance` 等宽网格辅助函数 + `dense_text_demo`（120×50 = 6000 字符）+ 65 条冒烟测试
- ✅ 方案 B（Instanced）：256 KB Storage Buffer（vs 方案 A 的 1.125 MB vertex buffer），内存效率高 4.4 倍
- ✅ 公理合规：A（16B uniform，无运行时泄漏）+ B（L0 deinit 释放）+ C（atlas_dense 编译期签名）

---

## 架构路线图

### Era I：形即渲染 — 已完成

| Phase | 名称 | 核心成就 | 重要度 |
| :--- | :--- | :--- | :--- |
| **1** | `nebula_derive()` 编译期生成器 | 声明意图→编译期推导的核心范式 | **91** |
| **2** | 形即渲染（WGSL 管线生成） | shader_compose + pipeline_factory + interaction_factory | **89** |
| **3.1–3.4** | 多组件布局、文本、键盘输入 | layout_engine + SDF 文本 + Gap Buffer + Input 组件 | 87 |
| **3.5** | App 编排与全面 Instancing | nebula_app_begin/end + 30 行愿景 | **91** |
| **3.6** | Gap Buffer 文本编辑 | 编译期定容 Gap Buffer + 光标 + 选区 | 75 |
| **3.7** | 管线生成器收敛 | 消除双脑渲染，统一至单一路径 | 75 |
| **3.8** | 渲染循环封装 + FrameArena | nebula_frame_render 单函数 | 76 |
| **3.9** | 文本一等公民 + Slot Producer | register_text + 万项动态列表 | 85 |
| **3.10** | 原语注册中心 | NEBULA_PRIMITIVES 元数据驱动 | 68 |
| **3.11** | Layout-App 统一注册 | 单次声明驱动全部生成 | 77 |
| **3.12** | 响应式重排 | 编译期多视口采样 + 运行时线性插值 | 71 |
| **4.0** | 编译期公理校验器 | axiom_validator 公理→可执行约束 | 75 |
| **4.1** | Slug 文本渲染引擎 | 无纹理纯数学矢量文本渲染 | **89** |
| **4.2.1** | 跨平台 PAL 骨架 | Linux/Windows/Web 源码级对齐 | 83 |

### Era II：全功能框架 — 进行中

| Phase | 名称 | 状态 | 重要度 |
| :--- | :--- | :--- | :--- |
| **4.2.2** | Slug 渲染内核生产级化 | **D-4.1-A/B/C 已完成**，benchmark 代码+静态分析就绪，**GPU deinit 已修复** | 79 |
| **4.3** | 可编程原语注册表 | **S1+S2+S3+TaskD 已完成** | **90** |
| **4.4** | 高级组件库 | **S1+S2+S3 已完成** | **81** |
| 4.2.3 | HarfBuzz + CJK 集成 | **S0+S1+S2 已完成**（绑定 + 预处理 + shaping 表 + 运行时排版） | 82 |
| 4.X | 高密度文本渲染通道 | **Step 1-5 已完成**（着色器 + 管线 + Record + 派生 + 辅助函数 + demo + 测试） | 85 |
| 4.X-T | 终端模拟器原型 | **已完成**（PTY + ANSI 解析器 + Dense Text 渲染 + term_demo） | 78 |
| 4.X-J | JSON Viewer | **已完成**（递归下降解析器 + One Dark 着色 + 折叠/展开 + 滚动 + 行号 + json_viewer_demo） | 82 |
| 4.7-S1 | CJK multiline editable | **已完成**（UTF-8 gap buffer + CJK 显示宽度 + cjk_editor_demo） | 85 |
| 4.7-S2 | DenseText 接入 App 编排 | **已完成**（`nebula_app_register_dense_text` + Producer 模式 + dense_editor_demo） | 86 |
| 4.7-S3 | 行号显示（独立 DenseText 列） | **已完成**（flex_grow/flex_basis + 多列 DenseText + editor_with_lines_demo） | 84 |
| 4.5 | 注册原语语法糖 | **S1+S2+S3 已完成**（S1: `nebula_component` + `nebula_inject_buffers` + `nebula_app` + `nebula_auto_states`；S2: 混合管线自动编排 + highlight_sugar_demo；S3: `nebula_visual` + `init_themed` + `nebula_frame_begin` + `require "nebula"` + button_v2_demo 30 行极限形态） | — |
|| 4.7-S4 | 语法高亮架构 | **已完成**（`highlight_factory.lua` + 编译期规则注入 + 运行时 per-char 着色 + highlight_editor_demo） | 85 |
|| 4.8-S1 | 选区可视化 + 系统剪贴板 | **已完成**（Shift+Arrow/Home/End + Ctrl+C/V/X/A + 选区覆盖删除 + Producer 选区渲染） | 86 |
|| 4.8-NL | 嵌套布局支持 | **已完成**（`layout.container` 声明式嵌套容器 + ref 拓扑 + 交叉轴自动拉伸 + 51 条冒烟测试） | 88 |
|| 4.8-S3 | 状态栏 + 光标行高亮 | **已完成**（底部固定高度状态栏 + 文件名/行列号/行数/编码/行尾符 + `fill_status_bar` Producer + 光标行高亮 + 31 条冒烟测试） | 80 |
|| 4.8-S4 | 多语言语法高亮 | **已完成**（6 语言规则 + `nebula_highlight_select` + `nebula_highlight_dispatch` + 扩展名自动检测 + 47 条冒烟测试） | 82 |
|| 4.8-S5 | 自动缩进 + Tab 处理 | **已完成**（Tab 4 空格 + Shift+Tab 反缩进 + Enter 自动保持/增加缩进 + 30 条冒烟测试） | 79 |
| **4.9** | **50 行终态收敛** | **已完成**（5 层 Sugar：L1 highlight pack + L2 Producer 自动生成 + L3 搜索交互内置 + L4 框架辅助 + L5 主循环生成，885→85 行，10.4x 压缩） | **88** |
| **4.9.1** | **语法打磨终态** | **已完成**（7 项改进：dense=N + builtin 绑定 + layout 提升 + children/row + cell 默认值 + auto_editor_name + editor_main 默认，886→19 行，46.6x 压缩） | **90** |
| **4.X-T2** | Terminal Emulator v2 | **已完成**（`nebula_terminal_main` + builtin="term_grid" + spec 缓存，489→16 行，30.6x 压缩） | 80 |
| **4.6** | **语法统一化** | **已完成**（S1: `nebula_main()` + S2: builtin 隐含 dense + S3: spec 缓存，button 18 行，term 16 行，editor 19 行） | **85** |
| 4.6-I | Indirect Drawing | 规划中（文档预研，等待组件数>100 触发） | 78 |
| 4.7 | 文本编辑器原型 | **S1-S7 已完成**（S7: text_editor_demo 全集成验收） | — |
| **4.X-CB** | **Code Browser** | **已完成**（文件树 + 语法高亮编辑器 + POSIX FFI + 懒加载目录扫描 + `code_browser_demo`） | 83 |
| 5.0 | 生态与 CI/CD | **进行中**（CI 全量覆盖 32 demo + C 单元测试 + GitHub Pages 部署） | — |

> 重要度评分基于五个维度加权综合评分（满分 100），详见 [`docs/PHASE_IMPORTANCE_SCORECARD.md`](docs/PHASE_IMPORTANCE_SCORECARD.md)。

---

## 核心哲学：三大公理

Nebula 的设计由三条正交公理驱动（详见 [`docs/ARCHITECTURE_GRAND_PLAN.md`](docs/ARCHITECTURE_GRAND_PLAN.md)）：

1. **公理 A（阶段封闭性）**：严格划分 S0（预处理）、S1（编译）、S2（运行）阶段。
2. **公理 B（生命周期三层）**：明确 L0（永久）、L1（持久）、L2（帧级）数据存活周期。
3. **公理 C（形即渲染）**：Visual 类型在编译期确定性映射到管线签名。

---

## 愿景：19 行实现完整文本编辑器 ✅ 已达成

`text_editor_demo_v3`（19 行）验证了终极形态——完整的文本编辑器（语法高亮 + 选区 + 搜索替换 + 行号 + 状态栏 + Undo/Redo + File I/O + 自动缩进），原 886 行压缩 46.6x：

```nelua
require "nebula"
## cinclude "<stdio.h>" -- snprintf for title update
## nebula_highlight_builtins({"nelua", "lua", "c", "python", "json", "markdown"})
## nebula_visual("EditorBgVisual", {
##   primitives = {"multiline_editable"}, max_text_len = 256, max_lines = 256, component_id = 1,
## })
## nebula_app("TextEditorApp", {
##   components = {
##     { name = "editor",      type = "EditorBgVisual" },
##     { name = "search_bar",  builtin = "search_bar", flex_basis = 24 },
##     { name = "editor_body", row = true, flex_grow = 1,
##       children = { "line_nums", "edit_area" } },
##     { name = "line_nums",   builtin = "line_nums", flex_basis = 50 },
##     { name = "edit_area",   builtin = "edit_area", flex_grow = 1 },
##     { name = "status_bar",  builtin = "status_bar", flex_basis = 24 },
##   },
## })
## nebula_editor_main("TextEditorApp")
```

> **Sugar 能力**：`builtin="line_nums"` 自动绑定 Producer + 隐含默认 dense 值 | layout 字段提升 + children/row 简写 | `auto_editor_name` 自动推断 | `nebula_editor_main` 默认参数 | `nebula_main()` 泛用 main 生成器 | nebula_app spec 缓存供下游 sugar 读取

### 最小编辑器（minimal_editor_demo，39 行）

`minimal_editor_demo` 验证了文档愿景。框架代码仅 11 行：

```nelua
require "nebula"

## nebula_visual("EditorVisual", {
##   primitives   = {"multiline_editable"},
##   max_text_len = 256,
##   max_lines    = 256,
##   component_id = 1,
## })
## nebula_app("EditorApp", {
##   components = {
##     { name = "editor", type = "EditorVisual" },
##   },
## })
```

> **auto-dense 机制**：`nebula_visual` 检测到 `multiline_editable` 时自动生成伴生 DenseText 渲染管线和默认 Producer，无需手动注册。`nebula_app` 自动路由到 DenseText 管线。`init_themed` 自动初始化 multiline_editable 的附带字段（cursor、buffer、pixel_height 等）。

完整示例见 `examples/minimal_editor_demo.nelua`。

### 已达成：button_v2_demo（18 行）

```nelua
require "nebula"

## nebula_visual("ButtonVisual", { primitives = {"clickable"} })
## nebula_app("ButtonApp", { components = {{ name="btn", type="ButtonVisual" }} })

## local function on_init(app)
##   return { app .. ".btn:init_themed(Vec2{x=300,y=250}, Vec2{x=200,y=60}, 12.0)" }
## end
## local function on_frame(app)
##   return { "if " .. app .. ".btn.click.just_clicked then printf(\"clicked!\\n\") end" }
## end
##
## nebula_main("ButtonApp", {
##   title = "Button V2 Demo", width = 800, height = 600,
##   bg_r = 0.09, bg_g = 0.09, bg_b = 0.10,
##   on_init = on_init, on_frame = on_frame,
## })
```

---

## 三层 API（分层可逃逸）

```
L2 (Visual) : nebula_visual + init_themed + nebula_frame_begin  ← Phase 4.5-S3
L1 (Sugar)  : nebula_component + nebula_app                     ← Phase 4.5 S1-S2
L0 (Raw)    : nebula_annotate + nebula_derive                   ← 最初的 raw API
```

每层可独立使用，高层出问题时随时降到低层，不需要重写。三层可在同一项目中混用。

| Demo | L0 (Raw) | L1 (Sugar) | L2 (Visual) | 压缩比 |
|:-----|:---------|:-----------|:------------|:-------|
| button | 147 行 | 141 行 | **18 行** | **8.2x** |
| multiline_sugar | — | 153 行 | ~20 行 | 8x |
| highlight_sugar | — | 386 行 | ~120 行 | 3x |
| minimal_editor | — | — | **39 行** | — |
| text_editor | — | 885 行 | **19 行** | **46.6x** |
| terminal | 489 行 | — | **16 行** | **30.6x** |

---

## 构建与运行

```bash
chmod +x build.sh

# 最小编辑器（文档愿景验证）
./build.sh minimal_editor_demo
LD_LIBRARY_PATH=vendor/wgpu-native/lib ~/.cache/nelua/minimal_editor_demo

# 完整文本编辑器 v3（19 行终态）
./build.sh text_editor_demo_v3
LD_LIBRARY_PATH=vendor/wgpu-native/lib ~/.cache/nelua/text_editor_demo_v3

# 完整文本编辑器（支持文件打开、语法高亮、行号）
./build.sh text_editor_demo
LD_LIBRARY_PATH=vendor/wgpu-native/lib ~/.cache/nelua/text_editor_demo
# 或打开文件编辑
LD_LIBRARY_PATH=vendor/wgpu-native/lib ~/.cache/nelua/text_editor_demo path/to/file.nelua
# 终端模拟器 v2（16 行 sugar 化终态）
./build.sh term_demo_v2
LD_LIBRARY_PATH=vendor/wgpu-native/lib ~/.cache/nelua/term_demo_v2

# 终端模拟器 v1（489 行原始版本）
./build.sh term_demo
LD_LIBRARY_PATH=vendor/wgpu-native/lib ~/.cache/nelua/term_demo
```

全量回归测试：
```bash
bash tools/run_all_tests.sh
```

---

## 项目结构

```
nebula/
├── src/                          # 核心框架
│   ├── nebula.nelua              # ★ Phase 4.5-S3 统一入口模块（1 行 require 替代 ~10 行）
│   ├── nebula_core.nelua         # 框架核心（derive 引擎 + nebula_visual + init_themed + nebula_app + nebula_main）
│   ├── nebula_builtins.nelua     # 预置 Producer 工厂（line_nums / status_bar / search_bar / edit_area / term_grid）
│   ├── nebula_apps.nelua          # 应用模板（nebula_editor_main + nebula_terminal_main）
│   ├── app.nelua                 # App 编排 + GLFW 事件循环 + nebula_frame_begin
│   ├── renderer.nelua            # WebGPU 渲染器
│   ├── text_runtime.nelua        # 文本渲染运行时
│   ├── gap_buffer.nelua          # 单行 Gap Buffer
│   ├── nebula_cursor.nelua       # 光标系统
│   ├── nebula_arena.nelua        # Frame Arena 分配器
│   ├── nebula_theme.nelua        # ★ 内置暗色主题颜色包（One Dark 风格）
│   ├── wgpu_bindings.nelua       # WebGPU C 绑定
│   ├── glfw_bindings.nelua       # GLFW C 绑定
│   ├── harfbuzz_bindings.nelua   # HarfBuzz C 绑定（Phase 4.2.3-S0）
│   ├── stb_truetype_bindings.nelua
│   └── derive/                   # S1 编译期元编程引擎
│       ├── interaction_factory.lua   # 原语注册表 + 交互代码生成
│       ├── gap_buffer_factory.lua    # Gap Buffer / MultiBuf 类型生成
│       ├── pipeline_factory.lua      # GPU 管线生成
│       ├── shader_compose.lua        # WGSL 着色器组合
│       ├── layout_engine.lua         # 编译期 Flexbox 布局
│       ├── app_factory.lua           # App 编排代码生成
│       ├── axiom_validator.lua       # 公理合规校验
│       └── highlight_factory.lua     # ★ Phase 4.7-S4 语法高亮规则 + 扫描函数生成
├── examples/                     # 演示程序
│   ├── button_demo.nelua         # 按钮组件
│   ├── login_demo.nelua          # 登录表单
│   ├── form_demo.nelua           # 多组件表单
│   ├── layout_demo.nelua         # Flexbox 布局
│   ├── text_demo.nelua           # 文本渲染
│   ├── shadow_demo.nelua         # 阴影效果
│   ├── dynamic_list_demo.nelua   # 万项动态列表
│   ├── slider_demo.nelua         # 可编程原语 (draggable_value)
│   ├── scrollable_demo.nelua     # 滚动容器
│   ├── dropdown_demo.nelua       # 下拉选择器
│   ├── multiline_editable_demo.nelua  # 多行编辑器
│   ├── slug_bench.nelua          # Storage Buffer 可扩展性基准
│   ├── cjk_text_demo.nelua      # CJK + ASCII 混排 Slug 渲染
│   ├── dense_text_demo.nelua    # 高密度文本网格（120×50 = 6000 chars）
│   ├── cjk_editor_demo.nelua   # CJK + ASCII 混排多行编辑器（Phase 4.7-S1）
│   ├── dense_editor_demo.nelua  # DenseText + App 编排编辑器（Phase 4.7-S2）
│   ├── editor_with_lines_demo.nelua # 行号栏 + 编辑区多列布局（Phase 4.7-S3）
│   ├── highlight_editor_demo.nelua # ★ Phase 4.7-S4 语法高亮编辑器（关键字+注释+字符串+数字）
│   ├── button_sugar_demo.nelua  # ★ Phase 4.5 语法糖重写（nebula_component + nebula_app）
│   ├── multiline_sugar_demo.nelua # ★ Phase 4.5 全糖化（inject_buffers + component + app）
│   ├── highlight_sugar_demo.nelua # ★ Phase 4.5-S2 全糖化语法高亮编辑器（混合管线自动编排）
│   ├── text_editor_demo.nelua   # ★ Phase 4.7-S7 文本编辑器原型（S1-S6 全集成验收）
│   ├── text_editor_demo_v2.nelua # ★ Phase 4.9 终态收敛（85 行，5 层 Sugar，10.4x 压缩）
│   ├── text_editor_demo_v3.nelua # ★ Phase 4.9.1 终态（19 行，46.6x 压缩，全部 sugar 内联）
│   ├── button_v2_demo.nelua    # ★ Phase 4.6-S1 nebula_main() 验证（18 行，8.2x 压缩）
│   ├── json_viewer_demo.nelua   # ★ Phase 4.X-J JSON 树形浏览器（折叠/展开 + 语法着色）
│   ├── json_viewer/             # JSON Viewer 子模块
│   │   ├── json_parser.nelua    # 递归下降 JSON 解析器
│   │   ├── json_tree.nelua      # 可见行计算 + 折叠 + 格式化 + 着色
│   │   └── sample.json          # 测试数据
│   ├── term_demo.nelua          # 终端模拟器原型 v1（PTY + ANSI + Dense Text，489 行）
│   ├── term_demo_v2.nelua       # ★ Phase 4.6-S3 sugar 化终端模拟器（16 行，30.6x 压缩）
│   └── term/                    # 终端模拟器子模块
│       ├── pty_bindings.nelua   # POSIX PTY C FFI 绑定
│       ├── ansi_parser.nelua    # ANSI/VT100 转义序列状态机
│       └── term_buffer.nelua    # 终端单元格缓冲区
├── tests/                        # 测试套件 (77 项回归全绿)
├── tools/                        # 构建与测试工具（含 font_preprocessor_cjk）
├── assets/                       # 字体/纹理预处理产物（含 CJK shaping 表）
├── vendor/                       # 第三方依赖 (wgpu-native, GLFW)
└── docs/                         # 架构文档与设计参考
```

---

## 文档索引
| [`PLAN_PHASE4_9_1_SYNTAX.md`](docs/PLAN_PHASE4_9_1_SYNTAX.md) | ★ Phase 4.9.1 — 语法打磨终态（886→19 行，46.6x） |
| [`PLAN_SYNTAX_UNIFICATION.md`](docs/PLAN_SYNTAX_UNIFICATION.md) | ★ Phase 4.6 — 语法统一化（nebula_main + builtin 默认 dense + spec 缓存） |
| [`PLAN_TERM_DEMO_V2.md`](docs/PLAN_TERM_DEMO_V2.md) | ★ Terminal Emulator v2 — sugar 化终端模拟器方案（489→16 行，30.6x） |

| 文档 | 内容 |
| :--- | :--- |
| [`ARCHITECTURE_GRAND_PLAN.md`](docs/ARCHITECTURE_GRAND_PLAN.md) | 三大公理 + 两纪元路线图 + 50 行愿景 |
| [`PHASE_IMPORTANCE_SCORECARD.md`](docs/PHASE_IMPORTANCE_SCORECARD.md) | 各 Phase 五维量化评分 |
| [`DESIGN_PHASE1.md`](docs/DESIGN_PHASE1.md) | Phase 1 设计哲学：编译期推导范式 |
| [`PLAN_PHASE2.md`](docs/PLAN_PHASE2.md) | Phase 2 总体设计：形即渲染 |
| [`PLAN_PHASE3.md`](docs/PLAN_PHASE3.md) | Phase 3 总体设计：多组件系统 |
| [`PLAN_PHASE3_6.md`](docs/PLAN_PHASE3_6.md) | Gap Buffer 生命周期设计（架构参考） |
| [`PLAN_PHASE4_1.md`](docs/PLAN_PHASE4_1.md) | Slug 渲染引擎设计 |
| [`PLAN_PHASE4_1_IMPL.md`](docs/PLAN_PHASE4_1_IMPL.md) | Slug 渲染引擎实现详情 |
| [`PLAN_PHASE4_3.md`](docs/PLAN_PHASE4_3.md) | 可编程原语注册表设计 |
| [`PLAN_PHASE4_3_TASK_D.md`](docs/PLAN_PHASE4_3_TASK_D.md) | process_body 公理校验补丁（从公理 A+B 推导） |
| [`PLAN_PHASE4_2_3_CJK.md`](docs/PLAN_PHASE4_2_3_CJK.md) | HarfBuzz + CJK 集成规划 |
| [`PLAN_PHASE4_X_DENSE_TEXT.md`](docs/PLAN_PHASE4_X_DENSE_TEXT.md) | 高密度文本 + 输入系统规划（待实施） |
| [`PLAN_PHASE4_X_JSON_VIEWER.md`](docs/PLAN_PHASE4_X_JSON_VIEWER.md) | JSON Viewer 实施方案（DenseText + 折叠 + 着色） |
| [`PLAN_PHASE4_7_BEFORE_4_5.md`](docs/PLAN_PHASE4_7_BEFORE_4_5.md) | Phase 4.7→4.5 调序方案（先积累样本再提炼语法糖） |
|| [`PLAN_PHASE4_5_S3_SUGAR.md`](docs/PLAN_PHASE4_5_S3_SUGAR.md) | Phase 4.5-S3 语法糖深化实施方案（nebula_visual + init_themed + frame_begin） |
| [`PLAN_PHASE4_8_EDITOR.md`](docs/PLAN_PHASE4_8_EDITOR.md) | Phase 4.8 编辑器功能规划 |
| [`PLAN_PHASE4_9_FIFTY_LINES.md`](docs/PLAN_PHASE4_9_FIFTY_LINES.md) | ★ Phase 4.9 — 50 行终态收敛方案（5 层 Sugar 架构 + 公理合规性分析） |
|| [`PLAN_NESTED_LAYOUT.md`](docs/PLAN_NESTED_LAYOUT.md) | ★ 嵌套布局实施方案（layout.container 声明式嵌套容器，公理合规性分析） |
|| [`PLAN_ERA2_MASTER.md`](docs/PLAN_ERA2_MASTER.md) | Era II 总体实施规划 |
| [`REPORT_PHASE4_2_2_BENCH.md`](docs/REPORT_PHASE4_2_2_BENCH.md) | Phase 4.2.2 Storage Buffer 基准测试报告 |
| [`TEXT_EDITOR_ROADMAP.md`](docs/TEXT_EDITOR_ROADMAP.md) | 文本编辑器长期愿景 |
| [`ROADMAP_INDUSTRY_RESEARCH.md`](docs/ROADMAP_INDUSTRY_RESEARCH.md) | 行业对标研究 (Zed/GPUI, Vello/Piet) |
| [`WASM_TARGET_ANALYSIS.md`](docs/WASM_TARGET_ANALYSIS.md) | WebAssembly 目标可行性分析 |
