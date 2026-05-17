# 配置项说明

Nebula 的编译期配置集中在 `src/derive/nebula_config.lua`。所有代码生成器共享这些默认值。

## 覆盖默认配置

在 `require "nebula"` 之后、`nebula_visual` 之前调用 `nebula_config_override`：

```nelua
require "nebula"

## nebula_config_override({
##   DEFAULT_WIN_WIDTH  = 1920,
##   DEFAULT_WIN_HEIGHT = 1080,
##   DEFAULT_CELL_H     = 18.0,
## })

## nebula_visual("MyVisual", { primitives = {"clickable"} })
-- ...
```

只覆盖传入的键，未传入的键保持默认值。传入不存在的键会触发编译期错误。

---

## 可配置项一览

### 1. Window & Layout

| 键 | 默认值 | 说明 |
| :--- | :--- | :--- |
| `DEFAULT_WIN_WIDTH` | 1280 | 默认窗口宽度（像素）。当 `nebula_app` 未指定 width 时使用。 |
| `DEFAULT_WIN_HEIGHT` | 800 | 默认窗口高度（像素）。当 `nebula_app` 未指定 height 时使用。 |
| `DEFAULT_VIEWPORT_WIDTH` | 800 | 默认视口宽度。layout solver 无 root 约束时的回退值。 |
| `DEFAULT_VIEWPORT_HEIGHT` | 600 | 默认视口高度。layout solver 无 root 约束时的回退值。 |
| `DEFAULT_ARENA_SIZE` | 2097152 (2 MB) | Frame Arena 大小（字节）。每帧临时分配的内存池。 |
| `STACK_BATCH_LIMIT` | 128 | 批量绘制栈安全阈值。超过此值使用分批模式，防止 WASM 栈溢出。 |

### 2. Grid & Cell

| 键 | 默认值 | 说明 |
| :--- | :--- | :--- |
| `DEFAULT_CELL_W` | 10.0 | DenseText 默认单元格宽度（像素）。影响等宽网格的水平间距。 |
| `DEFAULT_CELL_H` | 16.0 | DenseText 默认单元格高度（像素）。影响等宽网格的垂直间距。 |
| `DEFAULT_MAX_DENSE_CHARS` | 6000 | DenseText 默认最大字符数。决定 Storage Buffer 大小。 |

### 3. Interaction

| 键 | 默认值 | 说明 |
| :--- | :--- | :--- |
| `SCROLL_SPEED` | 30.0 | 滚轮滚动速度倍率。值越大滚动越快。 |
| `SCROLLBAR_WIDTH` | 10.0 | 滚动条宽度（像素）。 |

### 4. Syntax Highlight

颜色格式为 `0xRRGGBBAA`（packed uint32 RGBA8）。

| 键 | 默认值 | 说明 |
| :--- | :--- | :--- |
| `HL_COLOR_KEYWORD_CONTROL` | `0xC586C0FF` (紫色) | 控制流关键字：if/else/for/while/return 等。 |
| `HL_COLOR_KEYWORD_DECL` | `0x569CD6FF` (蓝色) | 声明关键字：local/global/function/require 等。 |
| `HL_COLOR_KEYWORD_LITERAL` | `0x4EC9B0FF` (青色) | 字面量关键字：true/false/nil/nilptr 等。 |
| `HL_COLOR_KEYWORD_TYPE` | `0x4DC9A0FF` (绿色) | 类型关键字：int32/float32/record/enum 等。 |
| `HL_COLOR_COMMENT` | `0x6A9955FF` (绿色) | 行注释。 |
| `HL_COLOR_STRING` | `0xCE9178FF` (橙色) | 字符串字面量。 |
| `HL_COLOR_NUMBER` | `0xB5CEA8FF` (黄绿) | 数字字面量。 |
| `HL_COLOR_MARKDOWN_MARKER` | `0xDCDCAAFF` (黄色) | Markdown 标记符号。 |

---

## 示例：自定义高对比度配色

```nelua
require "nebula"

## nebula_config_override({
##   HL_COLOR_KEYWORD_CONTROL = 0xFF79C6FF,  -- 粉色
##   HL_COLOR_COMMENT         = 0x8BE9FDFF,  -- 青色
##   HL_COLOR_STRING          = 0xF1FA8CFF,  -- 黄色
## })

## nebula_highlight_builtins({"nelua", "lua"})
-- ...
```
