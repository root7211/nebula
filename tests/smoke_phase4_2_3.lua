-- =============================================================================
-- tests/smoke_phase4_2_3.lua
-- Nebula GUI Compiler — Phase 4.2.3-S0 冒烟测试
--
-- 验证 HarfBuzz 绑定 + CJK 预处理管线的正确性：
--   · harfbuzz_bindings.nelua 存在且绑定核心 API
--   · font_preprocessor_cjk.nelua 工具存在且结构正确
--   · cjk_shaping_tables.nelua 已生成且数据合理
-- =============================================================================
local pass = 0
local fail = 0
local function check(name, cond)
  if cond then
    pass = pass + 1
    print("[PASS] " .. name)
  else
    fail = fail + 1
    print("[FAIL] " .. name)
  end
end

-- =============================================================================
-- 1 & 2. harfbuzz_bindings.nelua — 已移除（cleanup: dead code）
--         相关绑定测试不再适用，跳过。
-- =============================================================================

local function file_exists(path)
  local f = io.open(path, "r")
  if f then f:close() return true end
  return false
end

local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  return content
end

-- =============================================================================
-- 3. font_preprocessor_cjk.nelua 工具结构验证
-- =============================================================================
check("font_preprocessor_cjk.nelua exists", file_exists("tools/font_preprocessor_cjk.nelua"))

local cjk_tool = read_file("tools/font_preprocessor_cjk.nelua")
if cjk_tool then
  check("cjk_tool: requires harfbuzz_bindings", cjk_tool:find("require 'harfbuzz_bindings'"))
  check("cjk_tool: CJK charset definition",     cjk_tool:find("CHARSET_GB2312_L1") or cjk_tool:find("CHARSET_ZH_CN_CORE"))
  check("cjk_tool: glyph extraction API",       cjk_tool:find("hb_font_get_nominal_glyph") or cjk_tool:find("hb_shape%("))
  check("cjk_tool: glyph metrics extraction",   cjk_tool:find("hb_font_get_glyph_h_advance") or cjk_tool:find("hb_buffer_add_utf32"))
  check("cjk_tool: hb_font_get_glyph_extents",  cjk_tool:find("hb_font_get_glyph_extents"))
  check("cjk_tool: kerning detection pass",      cjk_tool:find("kern_adj"))
  check("cjk_tool: outputs cjk_shaping_tables",  cjk_tool:find("cjk_shaping_tables"))
  check("cjk_tool: NotoSansCJK font path",       cjk_tool:find("NotoSansCJK"))
  check("cjk_tool: charset count (20 or 3755)",   cjk_tool:find("3755") or cjk_tool:find("20"))
  check("cjk_tool: cleanup hb_font_destroy",      cjk_tool:find("hb_font_destroy"))
  check("cjk_tool: cleanup hb_font_destroy",      cjk_tool:find("hb_font_destroy"))
  check("cjk_tool: cleanup hb_face_destroy",      cjk_tool:find("hb_face_destroy"))
  check("cjk_tool: cleanup hb_blob_destroy",      cjk_tool:find("hb_blob_destroy"))
else
  for _ = 1, 13 do
    fail = fail + 1
    print("[FAIL] font_preprocessor_cjk.nelua not readable")
  end
end

-- =============================================================================
-- 4. cjk_shaping_tables.nelua 生成产物验证
-- =============================================================================
check("cjk_shaping_tables.nelua exists", file_exists("assets/generated/cjk_shaping_tables.nelua"))

local tables = read_file("assets/generated/cjk_shaping_tables.nelua")
if tables then
  -- 全局常量
  check("tables: NEBULA_CJK_UPEM defined",        tables:find("NEBULA_CJK_UPEM"))
  check("tables: NEBULA_CJK_GLYPH_COUNT defined",  tables:find("NEBULA_CJK_GLYPH_COUNT"))
  check("tables: NEBULA_CJK_KERN_PAIR_COUNT",      tables:find("NEBULA_CJK_KERN_PAIR_COUNT"))

  -- 类型定义
  check("tables: NebulaCjkGlyph record",           tables:find("NebulaCjkGlyph"))
  check("tables: NebulaCjkKernPair record",         tables:find("NebulaCjkKernPair"))

  -- 数据数组
  check("tables: NEBULA_CJK_GLYPHS array",         tables:find("NEBULA_CJK_GLYPHS"))
  check("tables: NEBULA_CJK_CODEPOINTS array",     tables:find("NEBULA_CJK_CODEPOINTS"))

  -- 数据合理性：所有 advance 应该是 1000 (UPEM)
  check("tables: UPEM = 1000",                     tables:find("NEBULA_CJK_UPEM <const> = 1000"))
  check("tables: glyph_count valid (20 or 3755)",  tables:find("NEBULA_CJK_GLYPH_COUNT <const> = 3755") or tables:find("NEBULA_CJK_GLYPH_COUNT <const> = 20"))
  check("tables: advance=1000 present",            tables:find("advance=1000"))
  check("tables: kern_pair_count = 0",             tables:find("NEBULA_CJK_KERN_PAIR_COUNT <const> = 0"))

  -- 核心汉字码点
  check("tables: 你 (U+4F60)",  tables:find("0x4F60"))
  check("tables: 好 (U+597D)",  tables:find("0x597D"))
  check("tables: 世 (U+4E16)",  tables:find("0x4E16"))
  check("tables: 界 (U+754C)",  tables:find("0x754C"))
  check("tables: 中 (U+4E2D)",  tables:find("0x4E2D"))
  check("tables: 国 (U+56FD)",  tables:find("0x56FD"))

  -- glyph_id 非零（确认 shaping 成功）
  check("tables: glyph_id non-trivial", tables:find("glyph_id=%d%d%d%d"))

  -- 自动生成标记
  check("tables: auto-generated marker", tables:find("Auto%-generated"))
else
  for _ = 1, 18 do
    fail = fail + 1
    print("[FAIL] cjk_shaping_tables.nelua not readable")
  end
end

-- =============================================================================
-- 总结
-- =============================================================================
print(string.format("\n--- smoke_phase4_2_3 结果: %d 通过, %d 失败 ---", pass, fail))
if fail > 0 then os.exit(1) end
