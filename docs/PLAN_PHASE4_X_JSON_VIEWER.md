# Phase 4.X-J：JSON Viewer 实施方案

**创建日期**：2026-05-02
**前置依赖**：Phase 4.X（DenseText 管线）✅ 已完成
**公理合规**：A（解析=S2 运行时，渲染=S2 帧级）| B（JSON 树=L1，实例数组=L2）| C（DenseText 管线签名编译期确定）

---

## 0. 目标与边界

### 做什么

一个只读 JSON 树形浏览器 `json_viewer_demo.nelua`，具备：

- JSON 文件加载与解析
- 语法着色（key=蓝, string=绿, number=橙, bool=紫, null=灰, 标点=白）
- 树节点折叠/展开（点击 `▶`/`▼` 切换）
- 垂直滚动（鼠标滚轮 + 键盘 ↑↓/PageUp/PageDown）
- 行号显示

### 不做什么

- 编辑功能（不需要 Gap Buffer / Undo / Redo）
- CJK 支持（JSON 数据通常为 ASCII/Latin）
- 水平滚动（长行截断并显示 `…`）
- 搜索/过滤
- App 编排层集成（手动管线驱动，与 dense_text_demo 同模式）

### 为什么现在做

1. **轻量验证**：只读 + DenseText = 最小新增代码量，不触碰编辑/L1 状态等重模块
2. **样本贡献**：为 Phase 4.5 语法糖提供 DenseText + scrollable + 行级点击交互的新样本
3. **折叠交互**：引入"行级命中测试 + 应用层状态切换"模式，这是 scrollable/dropdown 都没覆盖的交互范式

---

## 1. 架构设计

### 数据模型（L1 跨帧持久）

```
JsonNode = record{
  type:        uint8,       -- 0=null,1=bool,2=number,3=string,4=array,5=object
  key_start:   uint32,      -- 在 text_buf 中的 key 起始位置
  key_len:     uint16,
  val_start:   uint32,      -- 在 text_buf 中的 value 起始位置
  val_len:     uint16,
  parent:      int32,       -- 父节点索引（-1=root）
  first_child: int32,       -- 首个子节点索引（-1=叶子）
  next_sibling:int32,       -- 下一个兄弟节点索引（-1=末尾）
  child_count: uint16,      -- 直接子节点数量
  depth:       uint8,       -- 嵌套深度（用于缩进）
  folded:      boolean,     -- 折叠状态
}
```

- `text_buf: [TEXT_BUF_CAP]byte` — 存储所有 key/value 原始文本
- `nodes: [MAX_NODES]JsonNode` — 扁平节点数组，DFS 序
- `node_count: uint32`

### 渲染模型（L2 帧级重建）

每帧遍历可见节点，为每个可见行生成 `DenseCharInstance` 序列：

```
行格式: [行号] [缩进] [▶/▼/空] [key]: [value][,]
```

- 行号栏：固定 6 列，fg=暗灰，bg=深色
- 折叠指示器：`▶`（已折叠）/ `▼`（已展开），fg=黄色
- key：fg=蓝色
- value：按类型着色
- 标点（`{}[],:"`）：fg=白色

### 交互模型

| 输入 | 行为 |
|:-----|:-----|
| 鼠标滚轮 | 垂直滚动（±3 行/格） |
| 键盘 ↑↓ | 垂直滚动（±1 行） |
| PageUp/Down | 垂直滚动（±视口行数） |
| 鼠标左键点击折叠列 | 切换节点折叠状态 |
| Home/End | 滚动到顶部/底部 |

点击折叠的实现：
1. 从 `clickable` 原语获取 `just_clicked` 信号
2. 计算 `clicked_row = floor((mouse_y - origin_y + scroll_offset_y) / cell_h)`
3. 映射 `clicked_row` → `visible_lines[clicked_row]` → `node_index`
4. 检查点击列是否在折叠指示器范围内（`depth * indent_width` 列附近）
5. 若是容器节点（object/array），切换 `nodes[node_index].folded`

---

## 2. 实施步骤

### S1：JSON 解析器（纯数据层，无渲染依赖）

**新增文件**：`src/json_parser.nelua`

| # | 任务 | 描述 |
|:--|:-----|:-----|
| 1.1 | 词法分析 | 逐字节扫描 JSON 文本，识别 `{` `}` `[` `]` `:` `,` `"string"` `number` `true` `false` `null` |
| 1.2 | 递归下降解析 | `parse_value` → `parse_object` / `parse_array` / `parse_string` / `parse_number` / `parse_literal`，构建 `JsonNode` 扁平数组 |
| 1.3 | 文本缓冲区 | key 和 value 的原始文本存入 `text_buf`，节点记录 `(start, len)` 引用 |
| 1.4 | 错误处理 | 解析失败时在节点 0 存储错误信息，UI 层显示 "Parse error at byte N" |

**编译期常量**：
```nelua
local MAX_NODES <comptime> = 4096
local TEXT_BUF_CAP <comptime> = 65536  -- 64KB
local MAX_DEPTH <comptime> = 64
```

**验收**：纯 Nelua 代码，可在 `nelua-lua` 测试中验证解析正确性（不依赖 wgpu）。

### S2：可见行计算 + 折叠逻辑

**新增文件**：`src/json_tree.nelua`

| # | 任务 | 描述 |
|:--|:-----|:-----|
| 2.1 | `json_tree_compute_visible_lines` | 遍历节点数组，跳过 folded 子树，输出 `visible_lines: [MAX_VISIBLE]uint32`（节点索引数组）和 `visible_count` |
| 2.2 | `json_tree_toggle_fold` | 切换节点折叠状态（仅对 object/array 有效） |
| 2.3 | 行格式化 | `json_tree_format_line(node_index, out_buf, out_len)` — 将节点格式化为显示文本（含缩进、折叠符、key:value） |

**编译期常量**：
```nelua
local MAX_VISIBLE <comptime> = 1024   -- 最大可见行缓存
local INDENT_WIDTH <comptime> = 2     -- 每层缩进字符数
local MAX_LINE_LEN <comptime> = 200   -- 单行最大字符数（超出截断 + …）
```

**验收**：同样可在 `nelua-lua` 测试中验证（纯逻辑，无渲染依赖）。

### S3：DenseText 渲染集成 + 交互

**新增文件**：`examples/json_viewer_demo.nelua`

| # | 任务 | 描述 |
|:--|:-----|:-----|
| 3.1 | 管线初始化 | 复用 `nebula_derive_dense_text_visual` 生成 DenseText 管线，init atlas/viewport |
| 3.2 | 帧循环 — 实例数组填充 | 遍历视口内 `visible_lines[scroll_row .. scroll_row+viewport_rows]`，逐行逐字符填充 `DenseCharInstance`，按 token 类型赋色 |
| 3.3 | 滚动 | 读取 `input.scroll_dy` 和键盘 ↑↓/PageUp/PageDown，更新 `scroll_row`（整行滚动） |
| 3.4 | 折叠交互 | 鼠标左键点击 → 计算行号 → 检查折叠列 → `json_tree_toggle_fold` → 重算 visible_lines |
| 3.5 | 行号栏 | 前 6 列固定渲染行号，bg 色深于主区域 |
| 3.6 | 文件加载 | `io.open(filename)` 读取 JSON 文件到静态缓冲区，调用解析器 |

**管线模式**：与 `dense_text_demo` 相同的手动驱动模式（不经过 App 编排层）。

**着色规则**：

| Token 类型 | fg 颜色 (RGBA8) | 说明 |
|:-----------|:---------------|:-----|
| key | `#61AFEF` | 蓝色 |
| string | `#98C379` | 绿色 |
| number | `#D19A66` | 橙色 |
| bool | `#C678DD` | 紫色 |
| null | `#5C6370` | 灰色 |
| punctuation `{}[]:,` | `#ABB2BF` | 浅白 |
| fold indicator `▶▼` | `#E5C07B` | 黄色 |
| line number | `#4B5263` | 暗灰 |
| background | `#282C34` | One Dark 主题 |
| line number bg | `#21252B` | 略深 |

### S4：测试

**新增文件**：`tests/smoke_json_viewer.lua`

| # | 测试项 | 描述 |
|:--|:-------|:-----|
| 4.1 | JSON 解析正确性 | 验证 `{}` / `[]` / 嵌套 / 字符串转义 / 数值 / null/bool |
| 4.2 | 可见行计算 | 全展开/部分折叠/全折叠下的行数正确性 |
| 4.3 | 行格式化 | 缩进层级 / 截断 / 折叠符号 |
| 4.4 | 边界条件 | 空 JSON `{}`、深嵌套（64 层）、大文件（4096 节点边界） |
| 4.5 | 着色 token 映射 | 验证 format_line 输出的 color_buf 与预期匹配 |

---

## 3. 文件清单

| 文件 | 类型 | 行数估算 | 说明 |
|:-----|:-----|:---------|:-----|
| `src/json_parser.nelua` | 新增 | ~200 | 递归下降 JSON 解析器 + 节点树 |
| `src/json_tree.nelua` | 新增 | ~150 | 可见行计算 + 折叠 + 行格式化 + 着色 |
| `examples/json_viewer_demo.nelua` | 新增 | ~180 | Demo 主程序：管线 + 渲染 + 交互 |
| `tests/smoke_json_viewer.lua` | 新增 | ~120 | 冒烟测试 |
| `examples/sample.json` | 新增 | ~50 | 测试用 JSON 文件 |
| `build.sh` | 修改 | +1 | 新增 `json_viewer_demo` 到 case 列表 |
| `README.md` | 修改 | +3 | 更新 demo 列表 + 当前状态 |

**总新增代码**：~650 行 Nelua + ~120 行 Lua 测试

---

## 4. 对 Phase 4.5 语法糖的样本贡献

| 新模式 | 糖化启示 |
|:-------|:---------|
| DenseText + 手动滚动 + 行级点击 | 是否需要 `nebula_annotate` 支持 `scroll_mode="line"` 声明？ |
| 逐行逐字符着色 | `nebula_annotate` 是否需要 `color_scheme` / `highlight_fn` 元数据？ |
| 只读浏览器（无 editable 原语） | 验证语法糖不强制绑定编辑能力 |
| 手动管线驱动 | 语法糖必须允许 opt-out App 编排（escape hatch 验证） |
| 行号栏 + 内容区双区域渲染 | 同一 DenseText 管线内的"逻辑分区"模式，布局糖是否需要支持？ |

---

## 5. 风险与缓解

| 风险 | 影响 | 缓解 |
|:-----|:-----|:-----|
| JSON 解析器栈溢出（深嵌套） | 崩溃 | 迭代式解析 + `MAX_DEPTH=64` 限制 |
| 大 JSON 超出 `MAX_NODES` | 截断显示 | 解析到上限后停止，UI 显示 "Truncated (>4096 nodes)" |
| 单行超长（base64 字段等） | 渲染溢出 | `MAX_LINE_LEN=200` 截断 + `…` 后缀 |
| DenseText 字符数超出 Storage Buffer | GPU 上传失败 | `MAX_CHARS = viewport_rows × MAX_LINE_LEN`，仅渲染可见区域 |

---

## 6. 不做列表

| 项目 | 理由 |
|:-----|:-----|
| JSON 编辑/修改 | 目标是只读浏览器，编辑需要 Gap Buffer 等重依赖 |
| JSON Schema 验证 | 超出范围 |
| 横向滚动 | 长行截断足够，避免增加交互复杂度 |
| JSON Path 搜索/过滤 | 留给后续版本 |
| 多文件/多 Tab | 单文件浏览器 |
| App 编排层集成 | 手动驱动管线，待 4.5 语法糖后再迁移 |
