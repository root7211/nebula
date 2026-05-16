-- =============================================================================
-- derive/nebula_config.lua — Centralized compile-time configuration
--
-- ★ P2-8: 魔法数字集中化（编译期 Lua 侧）
--
-- 所有编译期代码生成器共享的默认值集中定义于此。
-- 各 factory 通过 require("nebula_config") 引入后使用 NEBULA_CONFIG.xxx 访问。
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

-- 默认窗口尺寸（当 nebula_app spec.layout 省略时使用）
NEBULA_CONFIG.DEFAULT_WIN_WIDTH  = 1280
NEBULA_CONFIG.DEFAULT_WIN_HEIGHT = 800

-- 默认视口尺寸（layout solver 无 root 约束时的回退值）
NEBULA_CONFIG.DEFAULT_VIEWPORT_WIDTH  = 800
NEBULA_CONFIG.DEFAULT_VIEWPORT_HEIGHT = 600

-- 默认 Arena 大小（字节）
NEBULA_CONFIG.DEFAULT_ARENA_SIZE = 2 * 1024 * 1024  -- 2 MB

-- 批量绘制栈安全阈值（超过此值使用分批模式）
NEBULA_CONFIG.STACK_BATCH_LIMIT = 128

-- =============================================================================
-- 2. Grid & Cell
-- =============================================================================

-- DenseText 默认单元格尺寸（像素）
NEBULA_CONFIG.DEFAULT_CELL_W = 10.0
NEBULA_CONFIG.DEFAULT_CELL_H = 16.0

-- DenseText 默认最大字符数
NEBULA_CONFIG.DEFAULT_MAX_DENSE_CHARS = 6000

-- =============================================================================
-- 3. Interaction
-- =============================================================================

-- 滚轮滚动速度倍率
NEBULA_CONFIG.SCROLL_SPEED = 30.0

-- 滚动条宽度（像素）
NEBULA_CONFIG.SCROLLBAR_WIDTH = 10.0

-- =============================================================================
-- 4. Syntax Highlight — One Dark 配色方案
--
-- 颜色格式：0xRRGGBBAA（packed uint32 RGBA8）
-- =============================================================================

NEBULA_CONFIG.HL_COLOR_KEYWORD_CONTROL  = 0xC586C0FF  -- 紫色：控制流关键字
NEBULA_CONFIG.HL_COLOR_KEYWORD_DECL     = 0x569CD6FF  -- 蓝色：声明关键字
NEBULA_CONFIG.HL_COLOR_KEYWORD_LITERAL  = 0x4EC9B0FF  -- 青色：字面量关键字
NEBULA_CONFIG.HL_COLOR_KEYWORD_TYPE     = 0x4DC9A0FF  -- 绿色：类型关键字
NEBULA_CONFIG.HL_COLOR_COMMENT          = 0x6A9955FF  -- 绿色：行注释
NEBULA_CONFIG.HL_COLOR_STRING           = 0xCE9178FF  -- 橙色：字符串字面量
NEBULA_CONFIG.HL_COLOR_NUMBER           = 0xB5CEA8FF  -- 黄绿：数字字面量
NEBULA_CONFIG.HL_COLOR_MARKDOWN_MARKER  = 0xDCDCAAFF  -- 黄色：Markdown 标记

return NEBULA_CONFIG
