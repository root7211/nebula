-- tests/golden_gen_extended.lua
-- 扩展 golden file 覆盖：shader_compose, layout_engine, interaction_factory 额外函数
-- 与 golden_gen.lua 互补，不修改原有文件
--
-- 用法: nelua-lua tests/golden_gen_extended.lua

package.path = "./src/?.lua;" .. "./src/derive/?.lua;" .. package.path
require "derive.interaction_factory"
require "derive.shader_compose"
require "derive.layout_engine"

os.execute("mkdir -p tests/golden")

-- 工具函数：写入 golden file
local function write(name, content)
  local f = io.open("tests/golden/" .. name .. ".golden", "w")
  f:write(content)
  f:close()
end

-- 工具函数：截断到前 N 行（用于大型 WGSL 输出）
local function first_n_lines(s, n)
  local lines = {}
  local count = 0
  for line in s:gmatch("([^\n]*)\n?") do
    count = count + 1
    if count > n then break end
    table.insert(lines, line)
  end
  return table.concat(lines, "\n")
end

-- 收集 print 输出的辅助函数
local function capture_print(fn)
  local captured = {}
  local old_print = print
  print = function(...)
    local args = {...}
    local parts = {}
    for i = 1, select("#", ...) do
      parts[i] = tostring(args[i])
    end
    table.insert(captured, table.concat(parts, "\t"))
  end
  fn()
  print = old_print
  return table.concat(captured, "\n")
end

local generated = {}

-- =====================================================================
-- 1. interaction_factory: nebula_gen_hit_test
-- =====================================================================
do
  local spec = { base = "Button" }
  local out = nebula_gen_hit_test(spec)
  write("hit_test_button", out)
  table.insert(generated, { name = "hit_test_button", size = #out })
end

do
  local spec = { base = "Slider" }
  local out = nebula_gen_hit_test(spec)
  write("hit_test_slider", out)
  table.insert(generated, { name = "hit_test_slider", size = #out })
end

-- =====================================================================
-- 2. interaction_factory: nebula_gen_toggle_state
-- =====================================================================
do
  local spec = { base = "Checkbox" }
  local out = nebula_gen_toggle_state(spec)
  write("toggle_state_checkbox", out)
  table.insert(generated, { name = "toggle_state_checkbox", size = #out })
end

-- =====================================================================
-- 3. shader_compose: nebula_compose_shader_instanced (basic, no radius/border)
-- =====================================================================
do
  local opts = {
    struct_name = "ButtonUniforms",
    wgsl_struct = "struct ButtonUniforms {\n  pos: vec2<f32>,\n  size: vec2<f32>,\n  bg_color: vec4<f32>,\n}\n",
    has_radius = false,
    has_border = false,
  }
  local result = nebula_compose_shader_instanced(opts)
  local out = first_n_lines(result.source, 50)
  write("shader_instanced_basic", out)
  table.insert(generated, { name = "shader_instanced_basic", size = #out })
end

-- =====================================================================
-- 4. shader_compose: nebula_compose_shader_instanced (with radius + border)
-- =====================================================================
do
  local opts = {
    struct_name = "CardUniforms",
    wgsl_struct = "struct CardUniforms {\n  pos: vec2<f32>,\n  size: vec2<f32>,\n  bg_color: vec4<f32>,\n  border_color: vec4<f32>,\n  border_width: f32,\n  radius: f32,\n}\n",
    has_radius = true,
    has_border = true,
  }
  local result = nebula_compose_shader_instanced(opts)
  local out = first_n_lines(result.source, 50)
  write("shader_instanced_radius_border", out)
  table.insert(generated, { name = "shader_instanced_radius_border", size = #out })
end

-- =====================================================================
-- 5. shader_compose: nebula_compose_text_shader
-- =====================================================================
do
  local opts = {
    struct_name = "TextUniforms",
    wgsl_struct = "struct TextUniforms {\n  viewport: vec2<f32>,\n  text_color: vec4<f32>,\n}\n",
  }
  local result = nebula_compose_text_shader(opts)
  local out = first_n_lines(result.source, 50)
  write("shader_text", out)
  table.insert(generated, { name = "shader_text", size = #out })
end

-- =====================================================================
-- 6. shader_compose: nebula_compose_dense_text_shader
-- =====================================================================
do
  local result = nebula_compose_dense_text_shader({})
  local out = first_n_lines(result.source, 50)
  write("shader_dense_text", out)
  table.insert(generated, { name = "shader_dense_text", size = #out })
end

-- =====================================================================
-- 7. shader_compose: nebula_compose_shadow_shaders (no radius)
-- =====================================================================
do
  local opts = {
    struct_name = "ShadowUniforms",
    wgsl_struct = "struct ShadowUniforms {\n  pos: vec2<f32>,\n  size: vec2<f32>,\n}\n",
    has_radius = false,
  }
  local result = nebula_compose_shadow_shaders(opts)
  -- Capture shadow_mask_source (first 40 lines) — most regression-prone
  local out = first_n_lines(result.shadow_mask_source, 40)
  write("shader_shadow_mask_norect", out)
  table.insert(generated, { name = "shader_shadow_mask_norect", size = #out })
end

-- =====================================================================
-- 8. layout_engine: simple column layout
-- =====================================================================
do
  local root = nebula_layout_node({
    name = "root",
    direction = "column",
    padding = 16,
    gap = 8,
    width = 400,
    height = 300,
    children = {
      nebula_layout_node({ name = "header", width = 368, height = 40 }),
      nebula_layout_node({ name = "body",   width = 368, height = 200 }),
      nebula_layout_node({ name = "footer", width = 368, height = 20 }),
    },
  })
  nebula_layout_solve(root, 400, 300)
  local out = capture_print(function()
    nebula_layout_dump(root)
  end)
  write("layout_column_simple", out)
  table.insert(generated, { name = "layout_column_simple", size = #out })
end

-- =====================================================================
-- 9. layout_engine: row layout with flex_grow
-- =====================================================================
do
  local root = nebula_layout_node({
    name = "row_root",
    direction = "row",
    padding = 10,
    gap = 5,
    width = 500,
    height = 100,
    children = {
      nebula_layout_node({ name = "sidebar", width = 80, height = 80 }),
      nebula_layout_node({ name = "content", height = 80, flex_grow = 1 }),
      nebula_layout_node({ name = "aside",   width = 60, height = 80 }),
    },
  })
  nebula_layout_solve(root, 500, 100)
  local out = capture_print(function()
    nebula_layout_dump(root)
  end)
  write("layout_row_flex", out)
  table.insert(generated, { name = "layout_row_flex", size = #out })
end

-- =====================================================================
-- 10. layout_engine: nested layout
-- =====================================================================
do
  local root = nebula_layout_node({
    name = "app",
    direction = "column",
    padding = 8,
    gap = 4,
    width = 320,
    height = 240,
    children = {
      nebula_layout_node({ name = "toolbar", width = 304, height = 32 }),
      nebula_layout_node({
        name = "main",
        direction = "row",
        gap = 4,
        width = 304,
        height = 188,
        children = {
          nebula_layout_node({ name = "nav",    width = 60, height = 188 }),
          nebula_layout_node({ name = "editor", height = 188, flex_grow = 1 }),
        },
      }),
    },
  })
  nebula_layout_solve(root, 320, 240)
  local out = capture_print(function()
    nebula_layout_dump(root)
  end)
  write("layout_nested", out)
  table.insert(generated, { name = "layout_nested", size = #out })
end

-- =====================================================================
-- Summary
-- =====================================================================
print("Extended golden files written:")
for _, g in ipairs(generated) do
  print(("  %-40s %d chars"):format(g.name, g.size))
end
print(("Total: %d golden files"):format(#generated))
