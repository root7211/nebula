# Phase 4.4 实施方案：可编程 GUI 编译器与自定义原语

**目标**：将 Nebula 从“提供预设组件的工具库”升维为“生成组件的元系统”。通过暴露 `nebula_register_primitive` API，允许界面开发者在 S1 编译期安全地注入自定义交互逻辑，实现“宏观原语 + 正交修饰”的组合模式，彻底解决复杂组件（如多行文本编辑器）的扩展性问题。

## 1. 架构背景与张力

在 Phase 3.10 中，我们引入了 `NEBULA_PRIMITIVES` 统一注册表，消除了 Monkey-patch，实现了框架内部原语的统一管理。然而，当前的 `process_input` 生成逻辑（`interaction_factory.lua`）仍然硬编码了 `hoverable`、`clickable`、`focusable` 的状态机转换逻辑。

**张力 T9（扩展性张力）**：界面开发者无法在不修改框架源码的情况下，创建新的交互原语（如 `draggable`、`scrollable` 或 `multiline_editable`）。这违背了“开箱即用”的 DX 诉求，也限制了 Nebula 生态的繁荣。

为了消除这一张力，我们需要将原语注册的能力下放给界面开发者，并提供一套安全的编译期静态契约机制。

## 2. 实施路径

### 2.1 S1 阶段：重构 `interaction_factory.lua`

我们需要彻底移除 `nebula_gen_process_input` 中对特定原语名称的硬编码判断，将其重构为完全由元数据驱动的生成管线。

1.  **状态机转换解耦**：将 `hoverable`、`clickable`、`focusable` 的状态机转换逻辑从 `nebula_gen_process_input` 的主干中剥离，移入各自原语的 `inline_process` 或 `extra_source_hook` 中。
2.  **引入 `inline_process` 元数据**：在 `NEBULA_PRIMITIVES` 的结构中新增 `inline_process` 字段，允许原语直接提供一段 Nelua 代码字符串，框架会将其按依赖顺序编织到 `process_input` 的函数体中。

### 2.2 暴露 `nebula_register_primitive` API

在 `nebula_core.nelua` 中，向界面开发者暴露一个简化的 Lua API，用于在 `nebula_annotate` 之前注册自定义原语。

**API 签名**：
```lua
function nebula_register_primitive(name, spec)
```

**参数 `spec` 结构**：
*   `dependencies` (table): 依赖的其他原语名称列表。
*   `context_fields` (table): 需要注入到 `<T>Context` 的状态字段，格式为 `{ {name="val", type="float32"} }`。
*   `inline_process` (string): 注入到 `process_input` 中的 Nelua 业务逻辑代码。
*   `static_asserts` (table): 编译期静态契约断言，用于检查 Context 中是否存在特定的字段或方法。

**示例：界面开发者注册 `draggable_value` 原语**：
```lua
##[[
nebula_register_primitive("draggable_value", {
  dependencies = { "clickable" },
  context_fields = {
    { name = "value", type = "float32" },
    { name = "is_dragging", type = "boolean" }
  },
  inline_process = [[
    if self.click.just_clicked then
      self.is_dragging = true
    elseif not input.mouse_left_down then
      self.is_dragging = false
    end
    if self.is_dragging then
      self.value = self.value + input.mouse_dx * 0.01
    end
  ]]
})
]]
```

### 2.3 编译期静态契约与公理校验扩展

为了保证自定义原语的安全性，我们需要在 Phase 4.0 引入的公理校验器（`axiom_validator.lua`）中增加对自定义原语的校验规则。

1.  **字段冲突检测**：校验不同原语注入的 `context_fields` 是否存在同名但类型不同的字段。
2.  **静态契约断言**：如果一个修饰原语（如 `clipboard_aware`）依赖宏观原语（如 `multiline_editable`）的数据结构，它可以通过 `static_asserts` 声明契约。校验器会在 S1 阶段检查目标 Context 是否确实包含了所需的字段（如 `gap_buf`）。
3.  **沙箱隔离**：确保 `inline_process` 中的代码只能访问 `self` 和 `input`，不能调用非法的全局函数或分配 L2 内存（维护公理 B）。

### 2.4 官方宏观原语库扩展

基于新的注册机制，框架将内置以下高级宏观原语，作为“可编程 GUI 编译器”的最佳实践范例：

1.  `multiline_editable`：封装多行 Gap Buffer/Rope，处理多行排版与 Y 轴命中测试。
2.  `scrollable_y` / `scrollable_x`：正交修饰原语，注入滚动偏移量，并在 S1 阶段修改 Vertex Shader 实现裁剪。
3.  `clipboard_aware`：正交修饰原语，拦截 Ctrl+C/V 事件并与操作系统的剪贴板 API 交互。

## 3. 验收标准

1.  **硬编码消除**：`interaction_factory.lua` 中不再包含任何针对 `hoverable`、`clickable` 等具体原语名称的 `if` 分支。
2.  **DX 验证**：界面开发者能够使用 `nebula_register_primitive` 成功创建一个包含自定义状态和逻辑的 `slider` 组件，且无需修改框架源码。
3.  **契约校验**：当界面开发者错误地组合了不兼容的原语（如将 `clipboard_aware` 应用于没有文本缓冲区的组件）时，公理校验器能在 S1 阶段抛出清晰的语义错误，而不是晦涩的 C 语言编译错误。
4.  **回归测试**：现有的 `form_demo.nelua` 在新的原语生成管线下，编译结果与之前完全一致（字节级对齐），全量回归测试 100% 通过。
