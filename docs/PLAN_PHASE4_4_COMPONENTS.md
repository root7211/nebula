# Phase 4.4 — 高级组件库 实施计划

**目标**：基于 Phase 4.3 的可编程原语注册表，实现三个标准高级组件，验证 Era II 工业级能力。
**前置依赖**：Phase 4.3 S2 已完成（register_primitive + 参数校验 + slider_demo）。
**评分**：81/100（DX=10, 工业化=10, 下游解锁=8）

---

## 1. 总体策略

Phase 4.4 的核心目标不是"写三个组件"，而是**验证 register_primitive API 在真实组件场景下的组合能力**。选择的三个组件分别覆盖三种不同的复杂度模式：

| 组件 | 复杂度模式 | 验证点 |
|:---|:---|:---|
| **Scrollable** | 容器 + 运行时裁剪 | 原语叠加（hoverable + clickable + draggable），超出 AABB 的子元素裁剪逻辑 |
| **Dropdown** | 弹出层 + 生命周期 | 跨组件状态传播（选中项 → 文本标签），弹出层 z-order 与点击外部关闭 |
| **Multiline Editable** | 持久状态 + 复杂输入 | L1/L2 边界（多行 gap buffer vs 单行），键盘导航（上下左右/home/end） |

### 分阶段交付（S1 → S2 → S3）

- **S1**：scrollable_demo — 最简容器组件，验证容器+裁剪+自定义原语组合
- **S2**：dropdown_demo — 弹出层组件，验证跨组件通信与状态传播
- **S3**：multiline_demo — 多行文本编辑，验证 L1 持久状态 + 复杂键盘输入

每阶段独立可编译、有测试、可 demo。

---

## 2. S1：Scrollable 组件

### 2.1 组件设计

```
ScrollableVisual = @record{
  pos:    Vec2,
  size:   Vec2,
  ...
  -- 运行时状态（通过原语注入）
  scroll_y: float32       -- 当前滚动偏移（像素）
  content_height: float32 -- 内容总高度（由外部设定）
  view_height: float32    -- 可视区域高度（= self.visual.size.y）
}
```

**交互原语**：
- `hoverable` — 内置，高亮滚动条
- `clickable` — 内置，点击滚动条轨道跳转
- `scrollable` — **新注册原语**，处理滚轮事件 + 拖拽滚动

**`scrollable` 原语规格**：
```lua
nebula_register_primitive("scrollable", {
  dependencies = {"hoverable"},
  context_fields = {
    {name="scroll_offset_y", type="float32"},
    {name="max_scroll", type="float32"},
    {name="is_dragging_bar", type="boolean"},
    {name="drag_start_y", type="float32"},
    {name="drag_start_offset", type="float32"},
  },
  state_transitions = {
    {guard="self.is_dragging_bar", target="DraggingBar", priority=40},
  },
  process_body = function(spec, lines)
    -- 1. 鼠标滚轮（需要在 NebulaInputState 中新增 mouse_scroll_y）
    -- 2. 滚动条拖拽：click.just_clicked 在滚动条区域 → 开始拖拽
    -- 3. clamp scroll_offset_y 到 [0, max_scroll]
  end,
})
```

### 2.2 裁剪策略

WebGPU 没有原生裁剪。两种方案：

**方案 A（推荐 — S1 选择）**：Scissor Rect
- `renderPass.setScissorRect(x, y, width, height)` — GPU 硬件裁剪，零额外开销
- 每个 Scrollable 组件在 `nebula_frame_render` 中设置 scissor rect
- 子组件的顶点坐标仍然在世界空间，scissor 负责裁剪

**方案 B（后续优化）**：Shader Clip
- 在 fragment shader 中丢弃 `clip_rect` 外的片元
- 需要修改 `shader_compose.lua`，侵入性较大

S1 先用方案 A，后续如有嵌套裁剪需求再考虑方案 B。

### 2.3 NebulaInputState 扩展

当前 `NebulaInputState` 缺少 `mouse_scroll_y` 字段。需要：

1. 在 `nebula_core.nelua` 的 `NebulaInputState` record 中添加 `mouse_scroll_y: float32`
2. 在 GLFW scroll callback 中填充该字段
3. 每帧 `nebula_collect_input` 结束后重置为 0

### 2.4 交付物

| 文件 | 类型 | 说明 |
|:---|:---|:---|
| `examples/scrollable_demo.nelua` | 新建 | 一个 scrollable 容器 + 内部多个按钮/文本 |
| `tests/smoke_phase4_4_s1.lua` | 新建 | scrollable 原语注册 + 编译期验证 |
| `src/nebula_core.nelua` | 修改 | NebulaInputState 新增 mouse_scroll_y |
| `tools/run_all_tests.sh` | 修改 | 集成新测试 |

### 2.5 验证标准

- [ ] `nelua -c` 编译 scrollable_demo.nelua 通过
- [ ] smoke_phase4_4_s1.lua 全量通过
- [ ] 全量回归测试 30+N/30+N 全绿
- [ ] scrollable 原语注册无冲突（与 hoverable/clickable 组合）

---

## 3. S2：Dropdown 组件

### 3.1 组件设计

```
DropdownVisual = @record{
  pos:    Vec2,
  size:   Vec2,
  ...
  -- 选项列表（编译期定容，类似 Gap Buffer 思路）
  items:     NebulaDropdownItems  -- 编译期生成的定容数组
  item_count: uint32
  selected:  uint32               -- 当前选中项索引
  is_open:   boolean              -- 下拉是否展开
}
```

**交互原语组合**：
- 主按钮：`hoverable` + `clickable` — 点击展开/收起
- 下拉列表：每项 `hoverable` + `clickable` — 选中后收起
- **新原语 `dropdown_manager`** — 管理展开/收起 + 选中状态 + 点击外部关闭

### 3.2 弹出层问题

Dropdown 是第一个需要"弹出层"的组件。在当前架构中：

- 所有组件共享一个 render pass → 绘制顺序 = 注册顺序
- 下拉列表需要绘制在其他组件之上

**S2 方案**：在 `nebula_app_register_component` 中引入 `z_order` 字段（默认 0，dropdown 列表 = 1）。
`nebula_frame_render` 按 z_order 稳定排序后再绘制。这需要修改 `app_factory.lua`。

### 3.3 交付物

| 文件 | 类型 | 说明 |
|:---|:---|:---|
| `examples/dropdown_demo.nelua` | 新建 | 单个下拉选择器，3-5 个选项 |
| `tests/smoke_phase4_4_s2.lua` | 新建 | dropdown 原语 + z_order 测试 |
| `src/derive/app_factory.lua` | 修改 | 支持 z_order 排序 |
| `tools/run_all_tests.sh` | 修改 | 集成新测试 |

### 3.4 验证标准

- [ ] `nelua -c` 编译 dropdown_demo.nelua 通过
- [ ] smoke_phase4_4_s2.lua 全量通过
- [ ] 全量回归测试全绿
- [ ] z_order 排序不影响已有 demo 的编译结果

---

## 4. S3：Multiline Editable 组件

### 4.1 组件设计

这是 Phase 4.4 最复杂的组件，直接为 Phase 4.7（文本编辑器原型）铺路。

**核心挑战**：
1. **数据结构**：单行用 `NebulaBuf255`（Gap Buffer），多行需要 `NebulaLineArray`（固定行数 × 每行 Gap Buffer）
2. **光标系统**：从 `(byte_offset)` 升级为 `(line, col)` 二元组
3. **键盘导航**：上/下箭头、Home/End、Page Up/Down
4. **滚动集成**：多行文本自然需要 scrollable（与 S1 衔接）

**交互原语组合**：
- `hoverable` + `clickable` + `focusable` + `editable` — 复用现有单行能力
- **新原语 `multiline_nav`** — 上下箭头 + Home/End + 换行处理

### 4.2 数据结构方案

```lua
-- 编译期生成：NebulaMultilineBuffer<N, L>
-- N = 每行最大字符数，L = 最大行数
-- 内部：L 个 NebulaBuf<N> + line_count: uint32 + cursor_line: uint32 + cursor_col: uint32
```

预生成钩子（类似 `nebula_gen_gap_buffer_type`）：
```lua
nebula_gen_multiline_buffer_type(max_chars_per_line, max_lines)
```

### 4.3 交付物

| 文件 | 类型 | 说明 |
|:---|:---|:---|
| `examples/multiline_demo.nelua` | 新建 | 多行文本编辑器 |
| `tests/smoke_phase4_4_s3.lua` | 新建 | multiline 原语 + 数据结构测试 |
| `src/derive/gap_buffer_factory.lua` | 修改 | 新增 `nebula_gen_multiline_buffer_type` |
| `src/derive/interaction_factory.lua` | 修改 | 注册 `multiline_nav` 原语 |
| `tools/run_all_tests.sh` | 修改 | 集成新测试 |

### 4.4 验证标准

- [ ] `nelua -c` 编译 multiline_demo.nelua 通过
- [ ] smoke_phase4_4_s3.lua 全量通过
- [ ] 全量回归测试全绿
- [ ] multiline_nav 与 editable 无上下文字段冲突

---

## 5. 风险与应对

| 风险 | 影响 | 应对 |
|:---|:---|:---|
| NebulaInputState 扩展破坏已有 demo | 高 | 新增字段放在 record 末尾，零初始化不影响旧 demo |
| z_order 修改 app_factory 影响现有 7 个 demo | 中 | z_order 默认 0，排序是稳定排序，现有 demo 行为不变 |
| 多行 Gap Buffer 编译期生成复杂度 | 中 | S3 可以先用固定 16 行 × 256 字符的"穷人方案"，不做通用生成器 |
| scissor rect 嵌套（scrollable 内嵌 scrollable） | 低 | S1 不支持嵌套，仅单层裁剪；后续如需要再引入 clip stack |

---

## 6. 时间估算

| 阶段 | 预估工作量 | 交付物 |
|:---|:---|:---|
| **S1** | 1 session | scrollable_demo + 原语 + 测试 + mouse_scroll_y 扩展 |
| **S2** | 1 session | dropdown_demo + 原语 + z_order + 测试 |
| **S3** | 1-2 sessions | multiline_demo + 多行 buffer + 键盘导航 + 测试 |

**总计**：3-4 sessions，每 session 独立可 commit + push。

---

## 7. 下一步行动

从 **S1（Scrollable）** 开始。第一个任务：
1. 在 `nebula_core.nelua` 中给 `NebulaInputState` 添加 `mouse_scroll_y: float32`
2. 在 GLFW scroll callback 中填充它
3. 注册 `scrollable` 原语
4. 写 scrollable_demo.nelua
5. 写 smoke_phase4_4_s1.lua
6. 集成到 run_all_tests.sh
7. 全量回归测试
8. commit + push
