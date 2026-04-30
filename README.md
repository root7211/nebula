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

**Era II 进行中 | 39/39 回归测试全绿 | 深度审计缺口 #1 #2 #3 #5 #6 已修复 + Phase 4.2.2-fix GPU deinit 完成（2026-04-30）**

### 最近完成

| 里程碑 | 内容 | 关键 commit |
| :--- | :--- | :--- |
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
| 4 | **4.2.2** | **D-4.1-C benchmark 未执行** | ❌ 待评估 | 需在 10000 字符规模下测试 Storage Buffer 性能退化。阻塞 4.2.3 CJK 启动决策 |
| ~~5~~ | **4.X** | ~~剪贴板 API 未绑定~~ | ✅ 已修复 | `glfw_bindings.nelua` 已绑定 `glfwGetClipboardString` / `glfwSetClipboardString`；`editable` 原语支持 Ctrl+C/V/X/A 剪贴板操作 |
| ~~6~~ | **4.X** | ~~Unicode char callback 无消费者~~ | ✅ 已修复 | `editable` 原语已扩展为接受全 Unicode 可打印字符（UTF-8 编码插入），Ctrl+C/V/X/A 快捷键已集成 |

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
| **4.2.2** | Slug 渲染内核生产级化 | **D-4.1-A/B 已完成**，D-4.1-C 待评估，**GPU deinit 已修复** | 79 |
| **4.3** | 可编程原语注册表 | **S1+S2+S3+TaskD 已完成** | **90** |
| **4.4** | 高级组件库 | **S1+S2+S3 已完成** | **81** |
| 4.2.3 | HarfBuzz + CJK 集成 | 规划中 | 82 |
| 4.X | 高密度文本 + 输入补全 | 规划中 | — |
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
│   └── multiline_editable_demo.nelua  # 多行编辑器
├── tests/                        # 测试套件 (38 项)
├── tools/                        # 构建与测试工具
├── assets/                       # 字体/纹理预处理产物
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
| [`PLAN_PHASE4_3.md`](docs/PLAN_PHASE4_3.md) | 可编程原语注册表设计 |
| [`PLAN_PHASE4_3_TASK_D.md`](docs/PLAN_PHASE4_3_TASK_D.md) | process_body 公理校验补丁（从公理 A+B 推导） |
| [`PLAN_PHASE4_2_3_CJK.md`](docs/PLAN_PHASE4_2_3_CJK.md) | HarfBuzz + CJK 集成规划（待实施） |
| [`PLAN_PHASE4_X_DENSE_TEXT.md`](docs/PLAN_PHASE4_X_DENSE_TEXT.md) | 高密度文本 + 输入系统规划（待实施） |
| [`TEXT_EDITOR_ROADMAP.md`](docs/TEXT_EDITOR_ROADMAP.md) | 文本编辑器长期愿景 |
| [`ROADMAP_INDUSTRY_RESEARCH.md`](docs/ROADMAP_INDUSTRY_RESEARCH.md) | 行业对标研究 (Zed/GPUI, Vello/Piet) |
| [`WASM_TARGET_ANALYSIS.md`](docs/WASM_TARGET_ANALYSIS.md) | WebAssembly 目标可行性分析 |
