# Nebula GUI Compiler — Phase 2.4 开发计划

## 1. 目标与背景

在 Phase 2.3 中，我们成功实现了 `<T>Uniforms`、`<T>Shader` 和 `<T>Pipeline` 的自动派生，彻底消除了渲染管线的硬编码。然而，在当前的 `login_demo` 和 `button_demo` 中，交互逻辑（鼠标悬停、点击、焦点切换）仍然是手动编写的。

**Phase 2.4 的核心目标**是：将交互原语（Interaction Primitives）的检测与状态机触发逻辑纳入 `nebula_derive` 的自动生成范围，实现真正的"声明式交互"。

### 当前痛点（以 `login_demo` 为例）

开发者需要为每个组件手动编写碰撞检测和状态机触发代码：

```nelua
-- 手写碰撞检测与状态转换
if mx >= card.visual.pos.x and mx < card.visual.pos.x + card.visual.size.x
   and my >= card.visual.pos.y and my < card.visual.pos.y + card.visual.size.y then
  if mouse_left_pressed then button_sm:fire("press")
  else button_sm:fire("hover") end
else
  button_sm:fire("leave")
end
```

这种方式不仅繁琐，而且容易出错，且无法复用。

## 2. 核心设计：交互原语自动派生

我们将通过解析 `nebula_annotate` 中声明的 `primitives`（如 `hoverable`, `clickable`, `focusable`），在编译期自动生成对应的交互处理代码。

### 2.1 统一输入状态 (`InputState`)

引入一个全局的输入状态结构，统一管理鼠标、键盘和焦点信息：

```nelua
global InputState = @record{
  mouse_x: float32,
  mouse_y: float32,
  mouse_left_down: boolean,
  mouse_left_pressed: boolean,
  mouse_left_released: boolean,
  focused_id: uint32, -- 当前获得焦点的组件 ID
}
```

### 2.2 自动生成的交互方法

对于声明了交互原语的组件，`nebula_derive` 将自动生成以下方法：

#### 1. 碰撞检测 (`hit_test`)

根据组件的 `pos` 和 `size`（未来可扩展支持 `radius` 圆角精确检测），自动生成内联的碰撞检测函数：

```nelua
function ButtonContext:hit_test(x: float32, y: float32): boolean
  local v = &self.visual
  return x >= v.pos.x and x < v.pos.x + v.size.x and
         y >= v.pos.y and y < v.pos.y + v.size.y
end
```

#### 2. 输入处理 (`process_input`)

根据声明的 `primitives`，自动生成状态机触发逻辑：

```nelua
function ButtonContext:process_input(input: *InputState, sm: *ButtonStateMachine)
  local hovered = self:hit_test(input.mouse_x, input.mouse_y)
  
  -- 处理 clickable 原语
  if hovered then
    if input.mouse_left_pressed then
      sm:fire("press")
    elseif not input.mouse_left_down then
      sm:fire("hover")
    end
  else
    sm:fire("leave")
  end
end
```

## 3. 实施步骤 (Sub-phases)

### Sub-phase 2.4.1: 引入 `InputState` 与基础结构
- 在 `src/nebula_core.nelua` 中定义 `InputState` 记录。
- 更新 `renderer.nelua` 或新增 `app.nelua`，提供统一的输入收集机制（从 GLFW 事件映射到 `InputState`）。

### Sub-phase 2.4.2: 开发 `interaction_factory.lua`
- 新增 `src/derive/interaction_factory.lua` 模块。
- 实现 `gen_hit_test()`：生成基于 AABB 的碰撞检测代码。
- 实现 `gen_process_input()`：根据 `primitives` 列表（`hoverable`, `clickable`, `focusable`）生成对应的状态机触发逻辑。

### Sub-phase 2.4.3: 集成到 `nebula_derive`
- 修改 `src/nebula_core.nelua`，在 `nebula_derive` 中调用 `interaction_factory`。
- 将生成的 `hit_test` 和 `process_input` 方法注入到 `<T>Context` 中。

### Sub-phase 2.4.4: 迁移 Examples 与验收
- 重构 `button_demo` 和 `login_demo`，移除手写的碰撞检测和状态触发代码。
- 改为在主循环中更新 `InputState`，并统一调用各组件的 `process_input`。
- **验收标准**：`login_demo` 的主循环代码行数显著减少，且交互行为（悬停、点击、焦点切换）与之前完全一致。

## 4. 预期收益

完成 Phase 2.4 后，Nebula GUI Compiler 将具备完整的"声明式视觉 + 声明式交互"能力。开发者只需在 `nebula_annotate` 中声明组件的视觉属性和交互原语，框架即可自动完成从 Uniform 布局、着色器组合、渲染管线创建到事件分发和状态流转的全套底层工作。这将为 Phase 3（多组件布局与复杂应用）奠定坚实的基础。
