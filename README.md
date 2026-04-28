# Nebula GUI Compiler

**Nebula** 是一个用编译期元编程把"声明意图"翻译成"等价手写代码"的 GUI 编译器。

Nebula 的目标是成为一个**工业级 GUI 基础设施**，它结合了：
- **Qt 的跨平台能力**：源码级支持 Linux (X11/Wayland), Windows, Web。
- **ImGui 的开发效率**：零样板代码，极简的 API 调用。
- **SwiftUI 的声明式体验**：纯声明式的 UI 描述，编译期自动推导布局与交互。

它的核心主张是**阶段封闭性**：
> 每个操作必须归属于其输入最早全部可知的阶段。后一阶段不得执行前一阶段的操作，前一阶段的输出是后一阶段的不可变输入。

---

### 当前状态：Phase 4.2.2 (Slug 生产级化) 进行中

**Phase 3.6.2 至 Phase 4.2.1 已全部合入主线**，全量回归测试全部通过。

- **Phase 4.2.1 (已完成)**：交付了跨平台 PAL 骨架，支持 Linux/Windows/Web。
- **Phase 4.1 (已完成)**：引入了 Slug 文本渲染引擎，实现基于贝塞尔曲线的纯数学矢量渲染。
- **Phase 4.2.2 (进行中)**：正在清算 Slug 内核债务，支持任意旋转、缩放及全量 Latin 字符。

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

| Phase | 名称 | 目标 | 状态 |
| :--- | :--- | :--- | :--- |
| **4.2.1** | 跨平台 PAL 骨架 | 三端源码级对齐 | **已完成** |
| **4.2.2** | Slug 渲染内核生产级化 | 清算债务，支持任意仿射变换 | **进行中** |
| 4.2.3 | HarfBuzz + CJK 集成 | 7000 常用中文字符支持 | 规划中 |
| **4.3** | **可编程原语注册表** | **允许开发者注入自定义交互逻辑** | 规划中 |
| 4.4 | 高级组件库 | 实现 scrollable, editable 等标准组件 | 规划中 |
| 4.5 | 文本编辑器原型 | 验证 Era II 工业级能力 | 规划中 |
| 5.0 | 工业化发布 | 自动化 CI/CD 与包管理支持 | 规划中 |

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
