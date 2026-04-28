# Nebula GUI Compiler

**Nebula** 是一个用编译期元编程把"声明意图"翻译成"等价手写代码"的 GUI 编译器。

Nebula 的目标是成为一个**工业级 GUI 基础设施**，它结合了：
- **Qt 的跨平台能力**：源码级支持 Linux (X11/Wayland), Windows, Web。
- **ImGui 的开发效率**：零样板代码，极简的 API 调用。
- **SwiftUI 的声明式体验**：纯声明式的 UI 描述，编译期自动推导布局与交互。

它的核心主张是**阶段封闭性**：
> 每个操作必须归属于其输入最早全部可知的阶段。后一阶段不得执行前一阶段的操作，前一阶段的输出是后一阶段的不可变输入。

---

### 当前状态：Phase 4.4 S2（Dropdown 下拉选择器）已完成

**Phase 3.6.2 至 Phase 4.4 S2 已全部合入主线，34/34 回归测试全绿。

- **Phase 4.3 S1 (已完成)**：`interaction_factory.lua` 完全元数据驱动重构——`nebula_gen_process_input` 消除所有硬编码原语分支，状态机转换由 `state_transitions` 元数据 priority 排序自动拼装。新增 `nebula_register_primitive(name, spec)` 公开 API。
- **Phase 4.3 S2 (已完成)**：`register_primitive` API 端到端验证——新增 `draggable_value` 原语 DX demo（slider_demo.nelua）、67 条专项测试（smoke_phase4_3.lua）、参数校验（依赖存在性 / context_fields / state_transitions / process_body 格式检查）。
- **Phase 4.4 S1 (已完成)**：Scrollable 容器组件——新增 `scrollable` 自定义原语（依赖 hoverable，5 个 context 字段）、scrollable_demo.nelua（8 个子按钮 + scissor rect 裁剪 + 手动渲染循环）、`wgpuRenderPassEncoderSetScissorRect` 绑定、32 条专项测试。
- **Phase 4.2.2 D-4.1-A/B (已完成)**：自适应 Band 分割 + 等价子集哈希合并 + Jacobian 逆矩阵 SlugDilate sub-pixel 膨胀。
- **Phase 4.2.2 D-4.1-C (待评估)**：Storage Buffer vs 纹理 benchmark。
- **Phase 4.2.1 (已完成)**：跨平台 PAL 骨架（Linux/Windows/Web）。
- **Phase 4.1 (已完成)**：Slug 文本渲染引擎（贝塞尔曲线纯数学矢量渲染）。

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

## 架构路线图

| Phase | 名称 | 目标 | 状态 | 重要度 |
| :--- | :--- | :--- | :--- | :--- |
| **4.2.1** | 跨平台 PAL 骨架 | 三端源码级对齐 | **已完成** | 83/100 |
| **4.2.2** | Slug 渲染内核生产级化 | 清算债务，支持任意仿射变换 | **D-4.1-A/B 已完成** | 79/100 |
| 4.2.3 | HarfBuzz + CJK 集成 | 7000 常用中文字符支持 | 规划中 | 82/100 |
| **4.3** | **可编程原语注册表** | **允许开发者注入自定义交互逻辑** | **S2 已完成** | **90/100** |
| **4.4** | **高级组件库** | **实现 multiline_editable, scrollable 等** | **S2 已完成** | **81/100** |
| 4.5 | 注册原语语法糖 | 基于 4.4 真实用例提炼重复模式，简化 DX | 规划中 | 待评分 |
| 4.6 | Indirect Drawing | GPU 端实例剔除与间接绘制 | 规划中 | 78/100 |
| 4.7 | 文本编辑器原型 | 验证 Era II 工业级能力 | 规划中 | 待评分 |
| 5.0 | 工业化发布 | 自动化 CI/CD 与包管理支持 | 规划中 | 待评分 |

> 重要度评分基于五个维度加权综合评分（满分 100），详见 [`docs/PHASE_IMPORTANCE_SCORECARD.md`](docs/PHASE_IMPORTANCE_SCORECARD.md)。

---

## 核心哲学：三大公理

Nebula 的设计由三条正交公理驱动（详见 [`docs/ARCHITECTURE_GRAND_PLAN.md`](docs/ARCHITECTURE_GRAND_PLAN.md)）：

1. **公理 A（阶段封闭性）**：严格划分 S0（预处理）、S1（编译）、S2（运行）阶段。
2. **公理 B（生命周期三层）**：明确 L0（永久）、L1（持久）、L2（帧级）数据存活周期。
3. **公理 C（形即渲染）**：Visual 类型在编译期确定性映射到管线签名。

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
