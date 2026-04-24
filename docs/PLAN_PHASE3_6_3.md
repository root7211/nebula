# Nebula Phase 3.6.3 核心设计：文本选区与修饰键支持

## 1. 目标与范围

Phase 3.6.3 的目标是在 Phase 3.6.2 的基础上，补全文本编辑组件的选区（Selection）功能。

**核心交付物**：
1. 支持通过鼠标拖拽（Drag）创建选区。
2. 支持通过 `Shift + 左右方向键` / `Shift + Home/End` 扩展选区。
3. 选区状态下的文本删除（Backspace/Delete）与覆盖输入（输入字符时替换选区内容）。
4. 选区高亮背景的渲染（形即渲染）。

**不在本阶段范围内的功能**：
- 跨行文本选区（属于多行文本排版，留待后续阶段）。
- 剪贴板支持（Ctrl+C / Ctrl+V，需要接入系统 API，留待后续）。

## 2. 状态模型（L1 持久状态）

根据**公理 B（L1/L2 严格分层）**，选区状态是跨帧存活的，必须作为 L1 状态存储。

在现有的 Gap Buffer 结构中，我们已经有了 `gap_start` 和 `gap_end`。但选区（Selection）需要两个锚点：
- **`cursor_pos`**：当前活动光标位置（即 `gap_start`）。
- **`selection_anchor`**：选区的起始锚点（如果不存在选区，则等于 `cursor_pos`）。

### 2.1 数据结构变更

由于 Gap Buffer 本身是一个底层数据结构，它不应该关心"选区"这种交互层概念。因此，`selection_anchor` 应该作为 `InputVisual`（或由 `interaction_factory` 派生的 Context）的状态。

**变更点 1：`InputVisual` 无需修改**
根据原语 2，`InputVisual` 仅声明意图，交互状态应由 Context 维护。由于我们目前将状态混写在 Visual 中，未来（Phase 3.9）会分离，但在当前阶段，我们可以在生成 `InputContext` 时注入 `selection_anchor`。

实际上，为了保持简单，我们可以直接在生成的 Context 中维护：

```nelua
-- 在 interaction_factory.lua 生成的 InputContext 中：
global InputContext = @record{
  visual: InputVisual,
  click:  ClickableState,
  focus:  FocusableState,
  
  -- 新增选区锚点（uint32，表示字符索引）
  selection_anchor: uint32,
  -- 标记当前是否正在拖拽以创建选区
  is_dragging: boolean,
}
```

### 2.2 选区区间计算

任何时候，有效的选区区间为 `[min(cursor, anchor), max(cursor, anchor)]`。
当 `cursor == anchor` 时，表示没有选区。

## 3. 交互模型（输入处理）

### 3.1 键盘修饰键（Shift）支持

当前 `NebulaInputState` 缺乏对修饰键（Modifier Keys）的感知。我们需要扩展输入收集层。

**变更点 2：扩展 `NebulaInputState`**

```nelua
-- src/nebula_core.nelua
global NebulaInputState = @record{
  -- ... 现有字段 ...
  key_pressed: NebulaKey,
  
  -- ★ Phase 3.6.3 新增修饰键状态
  mod_shift:   boolean,
  mod_ctrl:    boolean,
  mod_alt:     boolean,
}
```

在 `src/app.nelua` 的 `nebula_collect_input` 中，通过 GLFW 获取修饰键状态：
```nelua
input.mod_shift = (glfwGetKey(window, GLFW_KEY_LEFT_SHIFT) == GLFW_PRESS) or 
                  (glfwGetKey(window, GLFW_KEY_RIGHT_SHIFT) == GLFW_PRESS)
-- ctrl / alt 同理
```

### 3.2 键盘事件处理逻辑

在 `interaction_factory.lua` 生成的 `process_text_input` 中：

1. **方向键移动**：
   - 如果按下了 `Shift`，移动 `cursor`（通过 Gap Buffer API），但**不更新** `selection_anchor`。
   - 如果未按下 `Shift`，移动 `cursor`，并将 `selection_anchor` 同步为新的 `cursor`（清除选区）。

2. **字符输入与删除**：
   - 在执行输入或删除前，先检查是否存在选区（`cursor ~= anchor`）。
   - 如果存在选区，先执行**选区删除**（将选区内的字符从 Gap Buffer 中移除），然后将 `anchor` 同步为 `cursor`。
   - 然后再执行常规的字符插入。

### 3.3 鼠标拖拽处理逻辑

在 `process_text_input` 中：

1. **`just_clicked`（鼠标按下）**：
   - 命中测试获取目标位置 `target`。
   - 如果按下了 `Shift`，仅更新 `cursor` 为 `target`（`anchor` 保持不变，实现 Shift+Click 选区扩展）。
   - 如果未按下 `Shift`，更新 `cursor` 和 `anchor` 均为 `target`。
   - 设置 `is_dragging = true`。

2. **`mouse_left_down` 且 `is_dragging == true`（鼠标拖拽）**：
   - 每帧执行命中测试获取 `target`。
   - 仅更新 `cursor` 为 `target`（`anchor` 保持不变）。

3. **`mouse_left_released`（鼠标释放）**：
   - 设置 `is_dragging = false`。

## 4. 渲染模型（形即渲染）

根据**公理 C（形即渲染）**，选区高亮必须通过管线渲染，而不是作为"文本组件的特例"。

### 4.1 选区高亮的几何表示

选区本质上是一个**带颜色的矩形**，位于文本内容之下，背景框之上。
它的坐标和宽度可以通过 `nebula_text_compute_advances` 轻易计算出：

```
left_x  = advances[min(cursor, anchor)]
right_x = advances[max(cursor, anchor)]
width   = right_x - left_x
```

### 4.2 渲染管线集成

为了保持"零运行时分发"，我们不需要引入新的管线，而是复用现有的基础形状管线（如 `RectPipeline` 或 `CardPipeline`），或者直接在 `InputVisual` 的派生代码中注入选区矩形的绘制指令。

**变更点 3：在 `app_factory.lua` 的编排层注入选区渲染**

在生成的 `draw` 方法中，如果 `cursor ~= anchor`，则在绘制文本之前，绘制一个蓝色的高亮矩形：

```nelua
-- 伪代码：在生成的 draw 方法中
if self.email_input.selection_anchor ~= self.email_input.visual.gap_buf:cursor_pos() then
  local start_idx = min(cursor, anchor)
  local end_idx   = max(cursor, anchor)
  
  -- 栈上即时排版（与命中测试复用同一逻辑）
  local tmp_adv: [257]float32
  nebula_text_compute_advances(text, pixel_height, &tmp_adv[0], 256)
  
  local sel_x = tmp_adv[start_idx]
  local sel_w = tmp_adv[end_idx] - sel_x
  
  -- 构造一个临时 RectVisual 实例并绘制
  local sel_rect = RectVisual{
    pos = self.email_input.visual.pos + Vec2{x = sel_x, y = 0},
    size = Vec2{x = sel_w, y = pixel_height},
    color = Color{r=0.2, g=0.4, b=0.8, a=0.5} -- 选区高亮色
  }
  -- 通过共享的 RectPipeline 绘制
  pipe_rect:draw_single(pass, &sel_rect)
end
```

## 5. 实施步骤与验收标准

| 步骤 | 任务 | 验收标准 |
|---|---|---|
| 1 | 扩展 `NebulaInputState` | 支持 `mod_shift` 字段，并在 `nebula_collect_input` 中正确填充。 |
| 2 | 更新 `interaction_factory.lua` | `InputContext` 包含 `selection_anchor` 和 `is_dragging`。 |
| 3 | 实现 Gap Buffer 选区删除 | 新增 `delete_range(start, end)` 方法，支持 O(N) 批量删除。 |
| 4 | 实现键盘与鼠标选区逻辑 | Shift+方向键、鼠标拖拽、Shift+Click 均能正确更新 `cursor` 和 `anchor`。 |
| 5 | 选区文本覆盖与删除 | 存在选区时，输入字符或按 Backspace/Delete 会先清空选区内容。 |
| 6 | 实现选区高亮渲染 | 选中部分显示蓝色半透明背景，形即渲染，无额外堆分配。 |
| 7 | 测试覆盖 | 编写 `smoke_phase3_6_3.lua`，覆盖上述所有交互逻辑。 |

## 6. 架构合规性检查

- **公理 A（编译期最大化）**：选区逻辑完全在编译期生成，无运行时动态类型检查。
- **公理 B（L1/L2 分层）**：选区状态（锚点、拖拽标记）存活于 L1，排版数据（`tmp_adv`）即时计算于栈上（L2），无渗透。
- **公理 C（形即渲染）**：选区高亮作为标准几何体送入管线，而非作为文本管线的 hardcode 特例。
