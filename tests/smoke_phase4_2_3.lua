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
-- 1. harfbuzz_bindings.nelua 存在性检查
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

check("harfbuzz_bindings.nelua exists", file_exists("src/harfbuzz_bindings.nelua"))

-- =============================================================================
-- 2. harfbuzz_bindings.nelua API 覆盖验证
-- =============================================================================
local hb_src = read_file("src/harfbuzz_bindings.nelua")
if hb_src then
  -- 核心类型
  check("hb_bindings: hb_blob_t type",     hb_src:find("hb_blob_t"))
  check("hb_bindings: hb_face_t type",     hb_src:find("hb_face_t"))
  check("hb_bindings: hb_font_t type",     hb_src:find("hb_font_t"))
  check("hb_bindings: hb_buffer_t type",   hb_src:find("hb_buffer_t"))
  check("hb_bindings: hb_glyph_info_t",    hb_src:find("hb_glyph_info_t"))
  check("hb_bindings: hb_glyph_position_t", hb_src:find("hb_glyph_position_t"))
  check("hb_bindings: hb_glyph_extents_t", hb_src:find("hb_glyph_extents_t"))
  check("hb_bindings: hb_feature_t",       hb_src:find("hb_feature_t"))

  -- Blob API
  check("hb_bindings: hb_blob_create",     hb_src:find("hb_blob_create"))
  check("hb_bindings: hb_blob_destroy",    hb_src:find("hb_blob_destroy"))

  -- Face API
  check("hb_bindings: hb_face_create",     hb_src:find("hb_face_create"))
  check("hb_bindings: hb_face_destroy",    hb_src:find("hb_face_destroy"))
  check("hb_bindings: hb_face_get_upem",   hb_src:find("hb_face_get_upem"))

  -- Font API
  check("hb_bindings: hb_font_create",     hb_src:find("hb_font_create"))
  check("hb_bindings: hb_font_destroy",    hb_src:find("hb_font_destroy"))
  check("hb_bindings: hb_font_set_scale",  hb_src:find("hb_font_set_scale"))
  check("hb_bindings: hb_font_get_glyph_extents", hb_src:find("hb_font_get_glyph_extents"))

  -- Buffer API
  check("hb_bindings: hb_buffer_create",   hb_src:find("hb_buffer_create"))
  check("hb_bindings: hb_buffer_destroy",  hb_src:find("hb_buffer_destroy"))
  check("hb_bindings: hb_buffer_add_utf32", hb_src:find("hb_buffer_add_utf32"))
  check("hb_bindings: hb_buffer_set_direction", hb_src:find("hb_buffer_set_direction"))
  check("hb_bindings: hb_buffer_set_script", hb_src:find("hb_buffer_set_script"))
  check("hb_bindings: hb_buffer_set_language", hb_src:find("hb_buffer_set_language"))
  check("hb_bindings: hb_buffer_get_glyph_infos", hb_src:find("hb_buffer_get_glyph_infos"))
  check("hb_bindings: hb_buffer_get_glyph_positions", hb_src:find("hb_buffer_get_glyph_positions"))

  -- Shape API
  check("hb_bindings: hb_shape",           hb_src:find("hb_shape"))

  -- Language/Tag helpers
  check("hb_bindings: hb_language_from_string", hb_src:find("hb_language_from_string"))
  check("hb_bindings: hb_tag_from_string", hb_src:find("hb_tag_from_string"))

  -- Direction constants
  check("hb_bindings: HB_DIRECTION_LTR",   hb_src:find("HB_DIRECTION_LTR"))
  check("hb_bindings: HB_DIRECTION_RTL",   hb_src:find("HB_DIRECTION_RTL"))

  -- Script constants
  check("hb_bindings: HB_SCRIPT_HAN",      hb_src:find("HB_SCRIPT_HAN"))
  check("hb_bindings: HB_SCRIPT_LATIN",    hb_src:find("HB_SCRIPT_LATIN"))

  -- 公理 A 合规：linklib harfbuzz
  check("hb_bindings: linklib harfbuzz",    hb_src:find("linklib 'harfbuzz'"))
  check("hb_bindings: cinclude hb.h",       hb_src:find("hb%.h"))

  -- 不应包含运行时代码
  check("hb_bindings: no main() (S0 only)", not hb_src:find("function main"))
else
  for _ = 1, 35 do
    fail = fail + 1
    print("[FAIL] harfbuzz_bindings.nelua not readable")
  end
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
