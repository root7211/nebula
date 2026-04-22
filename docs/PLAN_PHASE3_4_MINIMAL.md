# Phase 3.4 详细规划：键盘输入与基础单行 Input 组件

**作者**：Manus AI
**日期**：2026-04-23

基于对 Nebula 核心哲学（“编译期推导”、“零运行时开销”）的坚守，本规划对 Phase 3.4 进行了**极简主义裁剪**。我们剥离了与“文本编辑器”相关的过度设计（如 Gap Buffer、选区高亮、多行排版），专注于实现 GUI 框架不可或缺的基础能力：**键盘事件流转与单行文本输入框**。

---

## 1. 设计哲学与裁剪原则

在早期的《文本编辑器技术路线图》中，曾计划引入动态的 `Gap Buffer` 和复杂的排版解耦。但对于一个专注于 UI 渲染的框架而言，这会导致代码库急剧膨胀，且偏离了 Nebula 静态推导的初衷。

**裁剪原则：**
1. **只做框架必需**：GUI 框架必须能处理登录框、搜索框，因此单行文本输入是底线。
2. **拒绝复杂数据结构**：不引入 Gap Buffer。单行输入框的字符数通常 < 100，直接使用定长字符数组（`[256]uint8`）即可，插入/删除的 `memmove` 开销在微小数据量下完全可以忽略。
3. **复用现有设施**：直接复用 `app.nelua` 的统一输入收集层，复用 `interaction_factory.lua` 的焦点链模型 [1] [2]。

---

## 2. 核心目标与技术方案

### 2.1 键盘事件收集层（扩展 `app.nelua`）
当前的 `NebulaInputState` 仅包含鼠标状态和 `focused_id` [3]。我们需要将其扩展为能够捕获单帧内键盘事件的快照。

**技术方案：**
*   在 `app.nelua` 中注册 `glfwSetKeyCallback` 和 `glfwSetCharCallback`。
*   将回调产生的数据缓冲到一个全局环形队列中。
*   在每帧的 `nebula_collect_input` 中，将队列中的事件提取到 `NebulaInputState` 的新字段中：
    *   `char_input`: 本帧输入的 Unicode 字符数组（用于文本输入）。
    *   `key_pressed`: 本帧按下的控制键枚举（如 Backspace, Enter, Left, Right）。

### 2.2 单行文本输入组件（`InputVisual` 与 `InputContext`）
现有的 `login_demo.nelua` 已经展示了 `InputVisual` 的外壳（拥有 Hover 和 Focus 状态），但没有实际的文本内容 [4]。

**技术方案：**
*   **状态存储**：在派生的 `InputContext` 中新增 `text_buffer: [256]uint8`、`text_len: uint32` 和 `cursor_pos: uint32`。
*   **输入处理**：在 `process_input` 中，如果当前组件拥有焦点（`input.focused_id == self.component_id`），则消费 `NebulaInputState` 中的字符和控制键。
*   **渲染集成**：`InputContext` 内部组合一个 `TextContext`（Phase 3.2 产物）。每当文本内容改变时，调用 `TextContext:set_text()` 重建网格。由于是单行短文本，全量重建网格的性能损耗在可接受范围内。

### 2.3 光标渲染（极简方案）
无需实现复杂的排版坐标解耦。

**技术方案：**
*   在调用 `TextContext:set_text()` 时，利用现有的字形度量数据（Advance），累加计算出 `cursor_pos` 处的 X 坐标偏移。
*   将此偏移量作为一个单独的 Uniform 传递给着色器，或者在 `InputContext:to_uniforms` 中附加一个表示光标位置和闪烁状态的矩形数据。

---

## 3. 子阶段实施计划

| 子阶段 | 标题 | 核心交付物 |
| :--- | :--- | :--- |
| **3.4.1** | 键盘事件收集基础设施 | 扩展 `glfw_bindings.nelua` 补充键盘常量；修改 `app.nelua` 接入 GLFW 回调；更新 `NebulaInputState` 结构。 |
| **3.4.2** | `InputContext` 文本缓冲区逻辑 | 在 `interaction_factory.lua` 中扩展 `focusable` 原语，生成对 `char_input` 和 `Backspace/Arrow` 的处理逻辑。 |
| **3.4.3** | 极简光标渲染 | 在 `InputPipeline` 中附加一条画线的逻辑，通过 `glfwGetTime()` 实现简单的闪烁频率。 |
| **3.4.4** | `login_demo` 升级与回归测试 | 将 `login_demo.nelua` 升级为真正可输入的登录框；补充相应的冒烟测试断言。 |

---

## 4. 结论

通过这种极简主义的裁剪，Phase 3.4 的工作量被压缩到了原本的 20% 左右。它不仅满足了 GUI 框架对基础表单输入的刚性需求，还完美保持了 Nebula 现有的架构纯洁性。

真正的多行文本编辑器、Gap Buffer 和选区高亮，被明确划定为**框架外部的独立应用项目**，不再占用 Nebula 核心演进的时间。

## 参考文献
[1] `src/app.nelua` - 统一输入收集层。
[2] `src/derive/interaction_factory.lua` - 交互原语派生工厂。
[3] `src/nebula_core.nelua` - 核心类型与输入状态定义。
[4] `examples/login_demo.nelua` - 包含焦点流转基础的登录框演示。
