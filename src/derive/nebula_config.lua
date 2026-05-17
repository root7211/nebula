-- =============================================================================
-- derive/nebula_config.lua — Centralized compile-time configuration
--
-- ★ P2-8: 魔法数字集中化（编译期 Lua 侧）
--
-- 所有编译期代码生成器共享的默认值集中定义于此。
-- 各 factory 通过 require("nebula_config") 引入后使用 NEBULA_CONFIG.xxx 访问。
--
-- 用户可通过 nebula_config_override() 在自己的代码中覆盖默认值，
-- 无需修改框架源码。详见 docs/guide/configuration.md。
--
-- 分区规则：
--   1. Window & Layout  — 默认窗口/视口尺寸
--   2. Grid & Cell      — DenseText 网格单元默认值
--   3. Interaction      — 交互原语默认参数
--   4. Syntax Highlight — One Dark 配色方案
-- =============================================================================

local NEBULA_CONFIG = {}

-- =============================================================================
-- 1. Window & Layout
-- =============================================================================

--- 默认窗口宽度（像素）。当 nebula_app 的 spec 未指定 width 时使用。
NEBULA_CONFIG.DEFAULT_WIN_WIDTH  = 1280

--- 默认窗口高度（像素）。当 nebula_app 的 spec 未指定 height 时使用。
NEBULA_CONFIG.DEFAULT_WIN_HEIGHT = 800

--- 默认视口宽度（像素）。layout solver 无 root 约束时的回退值。
NEBULA_CONFIG.DEFAULT_VIEWPORT_WIDTH  = 800

--- 默认视口高度（像素）。layout solver 无 root 约束时的回退值。
NEBULA_CONFIG.DEFAULT_VIEWPORT_HEIGHT = 600

--- Frame Arena 默认大小（字节）。每帧临时分配的内存池。
NEBULA_CONFIG.DEFAULT_ARENA_SIZE = 2 * 1024 * 1024  -- 2 MB

--- 批量绘制栈安全阈值。超过此值使用分批模式，防止 WASM 栈溢出。
NEBULA_CONFIG.STACK_BATCH_LIMIT = 128

-- =============================================================================
-- 2. Grid & Cell
-- =============================================================================

--- DenseText 默认单元格宽度（像素）。影响等宽网格的水平间距。
NEBULA_CONFIG.DEFAULT_CELL_W = 10.0

--- DenseText 默认单元格高度（像素）。影响等宽网格的垂直间距。
NEBULA_CONFIG.DEFAULT_CELL_H = 16.0

--- DenseText 默认最大字符数。决定 Storage Buffer 大小。
NEBULA_CONFIG.DEFAULT_MAX_DENSE_CHARS = 6000

-- =============================================================================
-- 3. Interaction
-- =============================================================================

--- 滚轮滚动速度倍率。值越大滚动越快。
NEBULA_CONFIG.SCROLL_SPEED = 30.0

--- 滚动条宽度（像素）。
NEBULA_CONFIG.SCROLLBAR_WIDTH = 10.0

-- =============================================================================
-- 4. Syntax Highlight — One Dark 配色方案
--
-- 颜色格式：0xRRGGBBAA（packed uint32 RGBA8）
-- =============================================================================

--- 控制流关键字颜色（紫色）：if/else/for/while/return 等。
NEBULA_CONFIG.HL_COLOR_KEYWORD_CONTROL  = 0xC586C0FF

--- 声明关键字颜色（蓝色）：local/global/function/require 等。
NEBULA_CONFIG.HL_COLOR_KEYWORD_DECL     = 0x569CD6FF

--- 字面量关键字颜色（青色）：true/false/nil/nilptr 等。
NEBULA_CONFIG.HL_COLOR_KEYWORD_LITERAL  = 0x4EC9B0FF

--- 类型关键字颜色（绿色）：int32/float32/record/enum 等。
NEBULA_CONFIG.HL_COLOR_KEYWORD_TYPE     = 0x4DC9A0FF

--- 行注释颜色（绿色）。
NEBULA_CONFIG.HL_COLOR_COMMENT          = 0x6A9955FF

--- 字符串字面量颜色（橙色）。
NEBULA_CONFIG.HL_COLOR_STRING           = 0xCE9178FF

--- 数字字面量颜色（黄绿色）。
NEBULA_CONFIG.HL_COLOR_NUMBER           = 0xB5CEA8FF

--- Markdown 标记符号颜色（黄色）：#/*/- 等。
NEBULA_CONFIG.HL_COLOR_MARKDOWN_MARKER  = 0xDCDCAAFF

-- =============================================================================
-- nebula_config_override(overrides)
--
-- 允许用户在自己的代码中覆盖默认配置值，无需修改框架源码。
--
-- 用法（在 require "nebula" 之后、nebula_visual 之前调用）：
--   ## nebula_config_override({ DEFAULT_WIN_WIDTH = 1920, DEFAULT_CELL_H = 18.0 })
--
-- 只覆盖传入的键，未传入的键保持默认值。
-- 传入不存在的键会触发编译期错误，防止拼写错误。
-- =============================================================================
function nebula_config_override(overrides)
  for k, v in pairs(overrides) do
    if NEBULA_CONFIG[k] == nil then
      error(("[nebula_config] unknown config key: '%s'. See docs/guide/configuration.md for available keys."):format(k))
    end
    NEBULA_CONFIG[k] = v
  end
end

return NEBULA_CONFIG
