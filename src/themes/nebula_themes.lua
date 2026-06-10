-- =============================================================================
-- nebula_themes.lua
-- Phase 6.2 — 语义化主题 Token 系统
-- =============================================================================

local THEMES = {}

-- Material Dark 主题
THEMES.material_dark = {
  -- 语义 token
  primary    = {r=0.40, g=0.63, b=0.95, a=1.0},  -- #669CF2
  on_primary = {r=0.08, g=0.13, b=0.22, a=1.0},
  surface    = {r=0.12, g=0.12, b=0.14, a=1.0},
  on_surface = {r=0.90, g=0.90, b=0.92, a=1.0},
  outline    = {r=0.30, g=0.30, b=0.34, a=1.0},
  error      = {r=0.95, g=0.26, b=0.21, a=1.0},
  
  -- 组件默认值
  button = {
    default  = { bg={r=0.40, g=0.63, b=0.95, a=1.0}, radius=8,  border_width=0 },
    hovered  = { bg={r=0.46, g=0.68, b=1.00, a=1.0}, radius=8 },
    pressed  = { bg={r=0.34, g=0.58, b=0.90, a=1.0}, radius=8 },
  },
  card = {
    default = { bg={r=0.12, g=0.12, b=0.14, a=1.0}, radius=12 },
    hovered = { bg={r=0.14, g=0.14, b=0.16, a=1.0}, radius=12 },
  },
}

-- Nord 主题
THEMES.nord = {
  primary    = {r=0.53, g=0.75, b=0.82, a=1.0},  -- Nord 8
  on_primary = {r=0.18, g=0.20, b=0.25, a=1.0},  -- Nord 0
  surface    = {r=0.23, g=0.26, b=0.32, a=1.0},  -- Nord 1
  on_surface = {r=0.92, g=0.94, b=0.95, a=1.0},  -- Nord 6
  outline    = {r=0.35, g=0.38, b=0.46, a=1.0},  -- Nord 3
  error      = {r=0.75, g=0.38, b=0.42, a=1.0},  -- Nord 11
  
  button = {
    default  = { bg={r=0.53, g=0.75, b=0.82, a=1.0}, radius=6, border_width=0 },
    hovered  = { bg={r=0.58, g=0.78, b=0.85, a=1.0}, radius=6 },
    pressed  = { bg={r=0.48, g=0.72, b=0.79, a=1.0}, radius=6 },
  },
  card = {
    default = { bg={r=0.23, g=0.26, b=0.32, a=1.0}, radius=10 },
    hovered = { bg={r=0.26, g=0.29, b=0.35, a=1.0}, radius=10 },
  },
}

-- Dracula 主题
THEMES.dracula = {
  primary    = {r=0.74, g=0.58, b=0.98, a=1.0},  -- Purple
  on_primary = {r=0.17, g=0.13, b=0.21, a=1.0},
  surface    = {r=0.17, g=0.13, b=0.21, a=1.0},  -- Background
  on_surface = {r=0.95, g=0.95, b=0.95, a=1.0},  -- Foreground
  outline    = {r=0.27, g=0.23, b=0.31, a=1.0},
  error      = {r=1.00, g=0.34, b=0.40, a=1.0},  -- Red
  
  button = {
    default  = { bg={r=0.74, g=0.58, b=0.98, a=1.0}, radius=8, border_width=0 },
    hovered  = { bg={r=0.79, g=0.63, b=1.00, a=1.0}, radius=8 },
    pressed  = { bg={r=0.69, g=0.53, b=0.93, a=1.0}, radius=8 },
  },
  card = {
    default = { bg={r=0.17, g=0.13, b=0.21, a=1.0}, radius=12 },
    hovered = { bg={r=0.20, g=0.16, b=0.24, a=1.0}, radius=12 },
  },
}

return THEMES
