-- =============================================================================
-- smoke_phase4_7_s7.lua
-- Nebula GUI Compiler — Phase 4.7-S7 Smoke Test
--
-- 文本编辑器原型验收：
--   · text_editor_demo.nelua 存在
--   · build.sh 包含 text_editor_demo 目标
--   · NebulaKey.Save 枚举值存在
--   · app.nelua Ctrl+S (key==83) 键映射到 Save
--   · glfwSetWindowTitle 绑定存在
--   · nebula_annotate 存储 max_lines 字段
--   · 集成 S1-S6 所有能力（语法高亮、行号、Undo/Redo、File I/O）
--   · 命令行参数解析（argc/argv）
-- =============================================================================

local pass_count = 0
local fail_count = 0

local function check(desc, cond)
  if cond then
    pass_count = pass_count + 1
    print(("  [PASS] %s"):format(desc))
  else
    fail_count = fail_count + 1
    print(("  [FAIL] %s"):format(desc))
  end
end

-- ---- 读取源文件 ----
local function read_file(path)
  local f = io.open(path, "r")
  assert(f, "cannot open " .. path)
  local content = f:read("*a")
  f:close()
  return content
end

local demo_src   = read_file("examples/text_editor_demo.nelua")
local core_src   = read_file("src/nebula_core.nelua")
local app_src    = read_file("src/app.nelua")
local glfw_src   = read_file("src/glfw_bindings.nelua")
local build_src  = read_file("build.sh")

-- =============================================================================
-- Part 1: 文件结构
-- =============================================================================
print("=== Part 1: File Structure ===")

check("text_editor_demo.nelua exists",
  demo_src and #demo_src > 100)

check("build.sh includes text_editor_demo target",
  build_src:find("text_editor_demo") ~= nil)

-- =============================================================================
-- Part 2: NebulaKey.Save 枚举
-- =============================================================================
print("\n=== Part 2: NebulaKey.Save ===")

check("NebulaKey enum contains Save = 24",
  core_src:find("Save%s*=%s*24") ~= nil)

check("app.nelua maps Ctrl+S (key==83) to NebulaKey.Save",
  app_src:find("key == 83") ~= nil and app_src:find("NebulaKey%.Save") ~= nil)

-- =============================================================================
-- Part 3: glfwSetWindowTitle 绑定
-- =============================================================================
print("\n=== Part 3: GLFW Bindings ===")

check("glfwSetWindowTitle binding exists",
  glfw_src:find("glfwSetWindowTitle") ~= nil)

-- =============================================================================
-- Part 4: nebula_annotate 存储 max_lines
-- =============================================================================
print("\n=== Part 4: nebula_annotate stores max_lines ===")

check("nebula_annotate stores max_lines field",
  core_src:find("max_lines%s*=%s*spec%.max_lines") ~= nil)

-- =============================================================================
-- Part 5: S1-S6 集成验证
-- =============================================================================
print("\n=== Part 5: S1-S6 Integration ===")

-- S1: CJK multiline editable (UTF-8 aware)
check("S1 integration: multiline_editable primitive declared",
  demo_src:find('primitives.*multiline_editable') ~= nil)

check("S1 integration: NebulaMultiBuf256_256 buffer type (via nebula_editor_visual or direct)",
  demo_src:find("NebulaMultiBuf256_256") ~= nil or
  demo_src:find("max_lines%s*=%s*256") ~= nil)

-- S2: DenseText App 编排
check("S2 integration: DenseText visuals declared",
  demo_src:find("EditAreaDenseVisual") ~= nil and
  demo_src:find("LineNumDenseVisual") ~= nil)

check("S2 integration: Producer functions",
  demo_src:find("fill_line_nums") ~= nil and
  demo_src:find("fill_edit_area") ~= nil)

-- S3: 行号显示
check("S3 integration: line number rendering (builtin or manual)",
  demo_src:find("LINENUM_COLS") ~= nil or
  demo_src:find("nebula_builtin_line_nums") ~= nil or
  demo_src:find("nebula_fill_line_nums") ~= nil)

-- S4: 语法高亮
check("S4 integration: nebula_highlight_rules declared",
  demo_src:find("nebula_highlight_rules") ~= nil)

check("S4 integration: nebula_derive_highlighter called",
  demo_src:find("nebula_derive_highlighter") ~= nil)

check("S4 integration: nebula_highlight_scan_nelua used in producer",
  demo_src:find("nebula_highlight_scan_nelua") ~= nil)

-- S5: Undo/Redo
check("S5 integration: undo_stack referenced",
  demo_src:find("undo_stack") ~= nil)

-- S6: File I/O
check("S6 integration: load_file called",
  demo_src:find("load_file") ~= nil)

check("S6 integration: save_file called",
  demo_src:find("save_file") ~= nil)

check("S6 integration: Ctrl+S triggers save",
  demo_src:find("NebulaKey%.Save") ~= nil)

-- =============================================================================
-- Part 6: 命令行参数（注：argc/argv 解析已移至 build.sh 外部）
-- =============================================================================
print("\n=== Part 6: Command-Line Arguments ===")

check("file path stored in _editor_file_path",
  demo_src:find("_editor_file_path") ~= nil)

check("_editor_has_file flag used",
  demo_src:find("_editor_has_file") ~= nil)

-- =============================================================================
-- Part 7: 窗口标题更新
-- =============================================================================
print("\n=== Part 7: Window Title ===")

check("glfwSetWindowTitle called for dynamic title update",
  demo_src:find("glfwSetWindowTitle") ~= nil)

check("title shows modification indicator [+]",
  demo_src:find("%[%+%]") ~= nil or demo_src:find("mod_mark") ~= nil)

check("title shows cursor position (Ln/Col)",
  demo_src:find("Ln") ~= nil and demo_src:find("Col") ~= nil)

-- =============================================================================
-- Part 8: 语法糖 API
-- =============================================================================
print("\n=== Part 8: Sugar API ===")

check("uses nebula_visual or nebula_inject_buffers (Phase 4.5 S1→S3)",
  demo_src:find("nebula_visual") ~= nil or demo_src:find("nebula_inject_buffers") ~= nil)

check("uses nebula_component or nebula_visual (Phase 4.5)",
  demo_src:find("nebula_component") ~= nil or demo_src:find("nebula_visual") ~= nil)

check("uses nebula_app (Phase 4.5 S2)",
  demo_src:find('nebula_app%("TextEditorApp"') ~= nil)

check("uses nebula_init (unified lifecycle)",
  demo_src:find("nebula_init") ~= nil)

check("uses nebula_should_close (unified lifecycle)",
  demo_src:find("nebula_should_close") ~= nil)

-- =============================================================================
-- Part 9: 修改检测
-- =============================================================================
print("\n=== Part 9: Modified State ===")

check("_editor_modified flag declared",
  demo_src:find("_editor_modified") ~= nil)

check("modified state tracked via undo_stack.cursor",
  demo_src:find("undo_stack%.cursor") ~= nil)

check("save resets modified flag",
  demo_src:find("_editor_modified = false") ~= nil)

-- =============================================================================
-- Part 10: Sugar Optimization
-- =============================================================================
print("\n=== Part 10: Sugar Optimization ===")

check("nebula_theme.nelua module exists",
  read_file("src/nebula_theme.nelua") ~= nil)

check("demo uses nebula_theme (via require 'nebula' or require 'nebula_theme')",
  demo_src:find('require "nebula"') ~= nil or demo_src:find('require "nebula_theme"') ~= nil)

check("demo uses nebula_theme color functions",
  demo_src:find("nebula_theme_fg_normal") ~= nil and
  demo_src:find("nebula_theme_bg_normal") ~= nil)

check("nebula_editor_visual or nebula_visual macro exists in nebula_core",
  core_src:find("function nebula_editor_visual") ~= nil or core_src:find("function nebula_visual") ~= nil)

check("demo uses nebula_editor_visual or nebula_visual (sugar)",
  demo_src:find("nebula_editor_visual") ~= nil or demo_src:find("nebula_visual") ~= nil)

check("nebula_builtin_line_nums macro exists in nebula_core",
  core_src:find("function nebula_builtin_line_nums") ~= nil)

check("demo uses nebula_builtin_line_nums (sugar)",
  demo_src:find("nebula_builtin_line_nums") ~= nil)

check("demo uses nebula_theme_editor_colors or init_themed for init",
  demo_src:find("nebula_theme_editor_colors") ~= nil or demo_src:find("init_themed") ~= nil)

check("no manual _fg_normal/_bg_normal color functions in demo",
  demo_src:find("local function _fg_normal") == nil and
  demo_src:find("local function _bg_normal") == nil)

-- ---- 总结 ----
print("")
print(("--- smoke_phase4_7_s7 结果: %d 通过, %d 失败 ---"):format(pass_count, fail_count))
if fail_count > 0 then
  os.exit(1)
end
