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

**Era II 进行中 | 49/49 回归测试全绿 | Phase 4.X 实施中（2026-05-02）**

### 最近完成

| 里程碑 | 内容 | 关键 commit |
| :--- | :--- | :--- |
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
| 4.5 | 注册原语语法糖 | 规划中 | — |
| 4.6 | Indirect Drawing | 规划中 | 78 |
| 4.7 | 文本编辑器原型 | 规划中 | — |
| 5.0 | 生态与 CI/CD | 规划中 | — |

> 重要度评分基于五个维度加权综合评分（满分 100），详见 [`docs/PHASE_IMPORTANCE_SCORECARD.md`](docs/PHASE_IMPORTANCE_SCORECARD.md)。

---

## 核心哲学：三大公理

Nebula 的设计由三条正交公理驱动（详见 [`docs/ARCHITECTURE_GRAND_PLAN.md`](docs/ARCHITECTURE_GRAND_PLAN.md)）：

1. **公理 A（阶段封闭性）**：严格划分 S0（预处理）、S1（编译）、S2（运行）阶段。
2. **公理 B（生命周期三层）**：明确 L0（永久）、L1（持久）、L2（帧级）数据存活周期。
3. **公理 C（形即渲染）**：Visual 类型在编译期确定性映射到管线签名。

---

## 愿景：50 行实现工业级文本编辑器

当路线图全部完成后，一个功能完备的文本编辑器将是这样的：

```nelua
require "nebula"

##[[
  nebula_annotate("EditorVisual", {
    primitives = {"multiline_editable", "scrollable_y", "clipboard_aware"}
  })
]]
## nebula_derive("EditorVisual")

##[[
  nebula_app_begin("TextEditorApp")
    nebula_app_register_component("editor", "EditorVisual", { layout = { flex_grow = 1 } })
  nebula_app_end()
]]
## nebula_derive_app("TextEditorApp")

local function main()
  local renderer: NebulaRenderer
  local app:      TextEditorApp
  if not nebula_init(&renderer, &app) then return 1 end
  while not nebula_should_close() do
    nebula_frame_render(&renderer, &app)
  end
  return 0
end
main()
```

**50 行，零样板，零 WGPU 调用，零 Pipeline 初始化。**

---

## 构建与运行

```bash
chmod +x build.sh
./build.sh form_demo
LD_LIBRARY_PATH=vendor/wgpu-native/lib ~/.cache/nelua/form_demo
# 或运行终端模拟器
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
│   ├── nebula_core.nelua         # 框架核心模块
│   ├── app.nelua                 # App 编排 + GLFW 事件循环
│   ├── renderer.nelua            # WebGPU 渲染器
│   ├── text_runtime.nelua        # 文本渲染运行时
│   ├── gap_buffer.nelua          # 单行 Gap Buffer
│   ├── nebula_cursor.nelua       # 光标系统
│   ├── nebula_arena.nelua        # Frame Arena 分配器
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
│       └── axiom_validator.lua       # 公理合规校验
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
│   ├── term_demo.nelua          # 终端模拟器原型（PTY + ANSI + Dense Text）
│   └── term/                    # 终端模拟器子模块
│       ├── pty_bindings.nelua   # POSIX PTY C FFI 绑定
│       ├── ansi_parser.nelua    # ANSI/VT100 转义序列状态机
│       └── term_buffer.nelua    # 终端单元格缓冲区
├── tests/                        # 测试套件 (49 项)
├── tools/                        # 构建与测试工具（含 font_preprocessor_cjk）
├── assets/                       # 字体/纹理预处理产物（含 CJK shaping 表）
├── vendor/                       # 第三方依赖 (wgpu-native, GLFW)
└── docs/                         # 架构文档与设计参考
```

---

## 文档索引

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
| [`PLAN_ERA2_MASTER.md`](docs/PLAN_ERA2_MASTER.md) | Era II 总体实施规划 |
| [`REPORT_PHASE4_2_2_BENCH.md`](docs/REPORT_PHASE4_2_2_BENCH.md) | Phase 4.2.2 Storage Buffer 基准测试报告 |
| [`TEXT_EDITOR_ROADMAP.md`](docs/TEXT_EDITOR_ROADMAP.md) | 文本编辑器长期愿景 |
| [`ROADMAP_INDUSTRY_RESEARCH.md`](docs/ROADMAP_INDUSTRY_RESEARCH.md) | 行业对标研究 (Zed/GPUI, Vello/Piet) |
| [`WASM_TARGET_ANALYSIS.md`](docs/WASM_TARGET_ANALYSIS.md) | WebAssembly 目标可行性分析 |
