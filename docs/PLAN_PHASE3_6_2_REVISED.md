# Nebula Phase 3.6.2 架构批判与最优方案修订

**作者**：Manus AI
**日期**：2026-04-24

## 1. 架构批判：初步方案中的“坏味道”

在重新审视之前提交的《Phase 3.6.2 鼠标命中测试与光标定位实现方案》（`PLAN_PHASE3_6_2.md`）后，我发现其中一个核心决策虽然能工作，但在架构层面上存在明显的“坏味道”，甚至与 Nebula 的核心哲学发生了冲突。

### 1.1 致命的缺陷：状态与渲染的混淆

初步方案建议在 `InputVisual`（组件的持久状态 Record）中注入一个编译期定容的 `advances: [256]float32` 数组，用于缓存排版数据，以供鼠标命中测试使用。

这个决策违背了《Phase 3.6 深度思考：在极致哲学下重构文本编辑架构》中确立的核心公理：**状态与渲染的严格解耦** [1]。

*   **Gap Buffer 属于持久层（State）**：它存储的是纯粹的逻辑文本数据（Unicode/ASCII 字符），跨帧存活，其存在不依赖于任何渲染上下文（如字体大小、缩放比例、屏幕坐标）。
*   **排版数据属于临时层（Render）**：`advances`（字符的屏幕 X 坐标）是**排版引擎**根据当前帧的字体、字号、屏幕缩放比例计算出的**瞬时结果**。

将属于渲染层的排版缓存硬塞进属于持久层的 `InputVisual` 中，会导致以下严重后果：

1.  **数据冗余与不一致**：如果窗口缩放或字体大小改变，`advances` 缓存立即失效。我们必须在 `process_text_input` 中手动调用排版函数来更新它，这使得逻辑状态（Gap Buffer）和渲染状态（Advances）被强行绑定在一起。
2.  **内存浪费**：如果一个表单有 10 个输入框，每个输入框都会在 Record 中永久占用 `256 * 4 = 1024` 字节的内存，即使它们当前并未获得焦点或根本没有被渲染。

### 1.2 违背“单向数据流”

在 GUI 框架中，标准的数据流是：`输入 -> 更新状态 (State) -> 排版 (Layout) -> 渲染 (Render)`。

命中测试（Hit-testing）本质上是排版阶段的逆操作。正确的做法是利用**上一帧的排版结果**（或者在当前帧实时计算）来进行反向映射，而不是将排版结果写回持久状态中。

## 2. 破局之道：回归 Frame Arena

既然排版数据是瞬时的、帧级别的，Nebula 早就为这种场景准备了完美的武器：**Frame Arena** [2]。

《Nebula 设计哲学冲突分析：Phase 3.3 的张力与妥协》明确指出，Arena Allocation 是 Nebula 在维持“零运行时开销”的同时支持动态场景的核心机制 [3]。

### 2.1 重新定位排版数据

我们不需要在 `InputVisual` 中永久存储 `advances` 数组。相反，当需要进行鼠标命中测试时，我们有两条更优雅的路径：

**路径 A：即时排版（Just-in-Time Shaping）**
由于文本输入框的字符数量极少（通常 < 256），且计算 `advance` 只需要查表和简单的浮点乘加运算（无堆分配、无复杂排版规则），我们在处理鼠标点击事件时，**直接在栈上（或 Arena 中）实时计算一遍排版数据**即可。

**路径 B：复用渲染层的排版结果**
如果未来引入了复杂的多行文本排版（Text Layout），排版开销变大，我们可以在渲染阶段将排版结果（如每个字符的 Bounding Box）写入 `Frame Arena`。下一帧处理输入时，直接从 Arena 中读取这些临时数据进行命中测试。

对于 Phase 3.6.2 的单行输入框，**路径 A（即时排版）是绝对的最优解**。它代码最少，不增加任何持久内存开销，且性能完全可控。

## 3. 修订后的最优实现方案

基于上述批判，我们对 Phase 3.6.2 的实现方案进行如下修订。

### 3.1 纯净的排版函数（不变）

我们仍然需要将排版逻辑从 `text_runtime.nelua` 的顶点装配中剥离出来，但它的用途变了：它不再用于填充持久缓存，而是作为命中测试的**即时计算工具**。

```nelua
-- [text_runtime.nelua]
global function nebula_text_compute_advances(
  text: cstring,
  pixel_height: float32,
  out_advances: *[0]float32,
  max_chars: uint32
): uint32
  -- (实现与原方案相同，略)
end
```

### 3.2 无状态的命中测试方法

在 `interaction_factory.lua` 中生成的 `mouse_to_cursor` 方法不再依赖 `self.visual.advances`，而是要求调用者传入临时计算好的 `advances` 数组。

```nelua
-- [derive/interaction_factory.lua]
-- 为 editable 原语生成 mouse_to_cursor 方法
function InputContext:mouse_to_cursor(local_x: float32, advances: *[0]float32, len: uint16): uint16
  if len == 0 or local_x <= 0.0 then return 0 end
  
  local i: uint16 = 0
  while i < len do
    local current_x = advances[i]
    local next_x    = advances[i + 1]
    local char_width = next_x - current_x
    
    if local_x >= current_x and local_x < next_x then
      -- 过半判定 (Half-char Heuristic)
      if local_x > current_x + (char_width * 0.5) then
        return i + 1
      else
        return i
      end
    end
    i = i + 1
  end
  return len
end
```

### 3.3 栈上分配，即时计算，用完即弃

在处理鼠标点击事件时，我们在栈上分配一个临时的 `advances` 数组（或者从 `Frame Arena` 中分配），计算排版，执行命中测试，然后直接丢弃。

这完美保持了 `InputVisual` 的纯洁性。

```nelua
-- [derive/interaction_factory.lua]
-- 在 process_text_input 中处理鼠标点击
if self.click.just_clicked then
  local len = self:get_text_len()
  if len > 0 then
    -- 1. 栈上分配临时数组（因为 max_text_len 在编译期已知，例如 256）
    -- 这里使用 Nelua 的栈分配特性，零堆分配，极速
    local temp_advances: [256 + 1]float32 
    
    -- 2. 即时计算排版
    nebula_text_compute_advances(self:get_text(), self.visual.pixel_height, &temp_advances[0], 256)
    
    -- 3. 坐标转换与命中测试
    local padding_x: float32 = 8.0 -- 假设内边距
    local local_x = input.mouse_x - self.visual.pos.x - padding_x
    local target_index = self:mouse_to_cursor(local_x, &temp_advances[0], len)
    
    -- 4. 移动 Gap Buffer 光标 (逻辑同原方案)
    local current_cursor = self.visual.gap_buf:cursor()
    while current_cursor < target_index do
      self.visual.gap_buf:move_cursor_right()
      current_cursor = current_cursor + 1
    end
    while current_cursor > target_index do
      self.visual.gap_buf:move_cursor_left()
      current_cursor = current_cursor - 1
    end
  end
end
```

## 4. 结论与架构收益

修订后的方案（即时排版 + 栈上分配）才是 Nebula 架构下的真正最优解。

| 评估维度 | 初步方案（持久缓存） | 修订方案（即时计算） | 胜出者 |
| :--- | :--- | :--- | :--- |
| **内存占用** | 每个输入框永久占用 `N*4` 字节 | 零持久内存占用，仅在点击瞬间占用少量栈内存 | **修订方案** |
| **架构解耦** | 状态层（Gap Buffer）被渲染层（Advances）污染 | 状态与渲染严格隔离，单向数据流 | **修订方案** |
| **响应式支持** | 窗口缩放时缓存失效，需手动维护一致性 | 每次点击使用当前最新的渲染参数，天然响应式 | **修订方案** |
| **CPU 开销** | 极低（直接查缓存） | 极低（256 次循环内的查表乘加，耗时可忽略） | **平局** |

通过摒弃在持久状态中缓存渲染数据的诱惑，我们不仅写出了更少的代码，还捍卫了 Nebula "声明意图"和"状态解耦"的核心哲学。这为未来 Phase 3.6.3 引入更复杂的多行排版和 Frame Arena 集成指明了正确的方向。

## 参考文献

[1] `docs/PLAN_PHASE3_6.md` - Nebula Phase 3.6 深度思考：在极致哲学下重构文本编辑架构。
[2] `src/nebula_arena.nelua` - Frame Arena 分配器设计与实现。
[3] `docs/PHILOSOPHY_ANALYSIS_PHASE3_3.md` - Nebula 设计哲学冲突分析：Phase 3.3 的张力与妥协。
