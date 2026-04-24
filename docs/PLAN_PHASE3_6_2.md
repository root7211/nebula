# Nebula Phase 3.6.2 鼠标命中测试与光标定位实现方案

**作者**：Manus AI
**日期**：2026-04-24

## 1. 概述

Nebula GUI Compiler 在 Phase 3.6.1 中成功引入了基于编译期定容的 Gap Buffer，彻底解决了文本输入底层存储的性能瓶颈，实现了 O(1) 的插入与删除 [1]。然而，当前的交互体验仍然局限于纯键盘输入。用户无法通过鼠标点击直接将光标定位到指定字符处，也无法进行文本的框选。

本方案旨在为 Phase 3.6.2（鼠标命中测试与光标定位）提供一份完整、可落地的初步实现路径。该方案严格遵循 Nebula 的三大设计哲学：**零运行时开销、形状即渲染、声明意图派生代码**，并确保与现有的 `Frame Arena` 和 `Gap Buffer` 机制无缝集成 [2]。

## 2. 现状分析与技术挑战

目前，Nebula 的文本渲染由 `text_runtime.nelua` 负责。其核心逻辑是在运行时解析 C 字符串，根据 `liberation_sans_ascii_48_metrics.nelua` 中的字形度量（Glyph Metrics）动态构建四边形顶点网格，并上传至 GPU [3]。

在当前的架构中，光标的渲染由 `nebula_cursor.nelua` 辅助完成，它仅仅是根据 `advance` 宽度的累加计算出一个 X 轴偏移量，然后绘制一个闪烁的矩形 [4]。

要实现鼠标命中测试，我们需要解决以下核心挑战：

1.  **单向计算瓶颈**：当前文本系统只有从“字符”到“屏幕坐标”的单向渲染计算（Forward Shaping）。缺失从“屏幕坐标 (X, Y)”反推到“字符索引 (Index)”的反向映射（Hit-testing）。
2.  **解耦排版与渲染**：现有的 `nebula_ascii_text_build_vertices` 函数将字形位置计算和顶点装配紧密耦合在同一个循环中 [3]。命中测试只需要字形的排版位置（Bounding Box），不需要装配顶点。
3.  **零堆分配约束**：存储每个字符的排版信息（如 `x_offset`、`width`）需要额外的内存。在不引入 `malloc` 的前提下，我们必须利用 `Frame Arena` 或在编译期分配这块内存。

## 3. 核心设计：双向映射模型

为了实现鼠标到光标的精准定位，我们需要在 `InputContext` 和 `text_runtime.nelua` 之间建立一个双向映射模型。

### 3.1 排版数据缓存 (Shaping Cache)

由于 `InputContext` 已经拥有了一个编译期定容的 `Gap Buffer`，其最大容量（`max_text_len`）在编译期是已知的。因此，我们可以利用 `nebula_derive` 宏，在 `InputVisual` 的结构体中同步生成一个固定大小的排版数据缓存数组。

```nelua
-- 扩展 InputVisual 定义 (由 nebula_derive 自动生成)
global InputVisual = @record{
  -- ... 其他字段
  gap_buf:  NebulaBuf255,
  flat_buf: [256]uint8,
  
  -- Phase 3.6.2 新增：字符 Advance 缓存
  -- 存储每个字符的累计 X 偏移量，用于 O(log N) 或 O(N) 的命中测试
  advances: [256]float32, 
}
```

### 3.2 提取纯排版逻辑

我们需要在 `text_runtime.nelua` 中新增一个纯排版函数，该函数只计算每个字符的 `Advance`，而不进行任何顶点装配 [3]。

```nelua
-- [text_runtime.nelua]
global function nebula_text_compute_advances(
  text: cstring,
  pixel_height: float32,
  out_advances: *[0]float32,
  max_chars: uint32
): uint32
  if text == nilptr then return 0 end
  local scale = pixel_height / NEBULA_ASCII_PIXEL_HEIGHT
  local pen_x: float32 = 0.0
  local i: uint32 = 0
  local text_len = (@uint32)(strlen(text))
  local text_bytes = (@*[0]uint8)(text)
  
  while i < text_len and i < max_chars do
    local cp = (@cint)(text_bytes[i])
    local glyph: NebulaGeneratedAsciiGlyph
    if nebula_ascii_glyph_for_codepoint(cp, &glyph) then
      out_advances[i] = pen_x
      pen_x = pen_x + glyph.advance * scale
    end
    i = i + 1
  end
  -- 记录最后一个字符结束后的位置，方便判断点击在文本末尾的情况
  if i < max_chars then
    out_advances[i] = pen_x
  end
  return i
end
```

## 4. 命中测试算法实现

命中测试的核心是将鼠标的屏幕坐标 `(mx, my)` 转换为 Gap Buffer 中的逻辑索引。

### 4.1 相对坐标转换

首先，在 `InputContext` 中接收到鼠标点击事件时，需要将全局鼠标坐标转换为相对于文本渲染起始点（`origin_x`）的局部坐标。

```nelua
-- [derive/interaction_factory.lua] 扩展
local local_x = input.mouse_x - self.visual.pos.x - padding_x
```

### 4.2 二分查找定位 (Binary Search)

由于 `advances` 数组中的值是单调递增的，我们可以使用二分查找算法在 O(log N) 的时间复杂度内找到最接近鼠标点击位置的字符索引。考虑到 Nebula 的文本长度通常较短（例如 `[256]uint8`），简单的线性扫描（O(N)）也是完全可以接受的，并且代码体积更小，缓存命中率更高。

我们采用线性扫描结合“过半判定”的策略：当鼠标点击在字符前半部分时，光标定位在该字符前；点击在后半部分时，定位在该字符后。

```nelua
-- [derive/interaction_factory.lua]
-- 为 editable 原语生成 mouse_to_cursor 方法
function InputContext:mouse_to_cursor(local_x: float32): uint16
  local len = self:get_text_len()
  if len == 0 or local_x <= 0.0 then return 0 end
  
  local i: uint16 = 0
  while i < len do
    local current_x = self.visual.advances[i]
    local next_x    = self.visual.advances[i + 1]
    local char_width = next_x - current_x
    
    -- 如果鼠标在当前字符的边界内
    if local_x >= current_x and local_x < next_x then
      -- 过半判定：如果点击在字符的后半段，光标移到下一个位置
      if local_x > current_x + (char_width * 0.5) then
        return i + 1
      else
        return i
      end
    end
    i = i + 1
  end
  
  -- 如果超出所有字符宽度，定位到末尾
  return len
end
```

### 4.3 结合 InputState 与 Gap Buffer

最后，我们需要将命中测试与 `process_text_input` 结合。当检测到鼠标在组件内部发生点击（`just_clicked`）时，触发命中测试，并利用 Gap Buffer 的移动接口将光标同步过去。

```nelua
-- 在 process_text_input 的末尾或 process_input 中添加逻辑
if self.click.just_clicked then
  -- 1. 更新排版缓存
  nebula_text_compute_advances(self:get_text(), self.visual.pixel_height, &self.visual.advances[0], self.visual.gap_buf.capacity)
  
  -- 2. 坐标转换与命中测试
  local padding_x: float32 = 8.0 -- 假设有内边距
  local local_x = input.mouse_x - self.visual.pos.x - padding_x
  local target_index = self:mouse_to_cursor(local_x)
  
  -- 3. 移动 Gap Buffer 光标
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
```

## 5. 阶段演进与验收标准

本方案建议分为两个小的子阶段进行交付，以保证主线的稳定性：

### Phase 3.6.2a：排版数据分离与缓存
*   **目标**：在 `text_runtime.nelua` 中实现 `nebula_text_compute_advances` 函数 [3]。
*   **目标**：修改 `nebula_derive`，为声明了 `editable` 的组件自动注入 `advances` 数组。
*   **验收**：所有现有 Demo（包括 `form_demo.nelua`）正常编译运行，光标渲染逻辑可以平滑切换到读取 `advances` 数组。

### Phase 3.6.2b：鼠标命中与光标同步
*   **目标**：在 `interaction_factory.lua` 中生成 `mouse_to_cursor` 方法。
*   **目标**：在处理 `just_clicked` 事件时，计算局部坐标并同步 Gap Buffer 光标 [4]。
*   **验收**：在 `form_demo.nelua` 中，用户可以通过鼠标点击精准地将光标定位到文本框内的任意字符之间。

## 6. 总结

通过在编译期为文本组件生成定容的排版缓存数组，并将字形排版逻辑与顶点装配逻辑解耦，我们能够在完全不引入堆分配、不违背 Nebula 核心哲学的前提下，实现精准的鼠标命中测试。这一方案将使得 Nebula 的文本输入能力从基础的“键盘打字”跃升为真正的“可交互编辑”，为未来引入文本框选（Selection）奠定了坚实的基础。

## 参考文献

[1] `src/gap_buffer.nelua` - 编译期定容 Gap Buffer 实现。
[2] `docs/PLAN_PHASE3_6.md` - Nebula Phase 3.6 深度思考与架构演进。
[3] `src/text_runtime.nelua` - Nebula 运行时文本渲染与网格装配模块。
[4] `src/nebula_cursor.nelua` - 极简光标渲染辅助模块。
