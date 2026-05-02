-- =============================================================================
-- tests/smoke_phase4_2_3_s2.lua
-- Nebula GUI Compiler — Phase 4.2.3-S2 验证测试
--
-- 验证 CJK 运行时排版函数的正确性：
--   1. text_runtime.nelua 包含 CJK 运行时函数声明
--   2. nebula_cjk_glyph_lookup 二分查找函数存在
--   3. nebula_cjk_text_compute_advances 排版函数存在
--   4. nebula_cjk_slug_text_build_vertices 顶点生成函数存在
--   5. cjk_text_demo.nelua 演示程序存在且结构正确
--   6. build.sh 包含 cjk_text_demo 目标
--   7. text_runtime 引入 cjk_shaping_tables
--   8. UTF-8 解码逻辑存在
--   9. ASCII fallback 路径存在
--  10. 公理 A 合规：S2 代码无 hb_* / stbtt_* 调用
--  11. 公理 B 合规：排版输出为 L2 帧级数据
-- =============================================================================

local passed = 0
local failed = 0

local function check(name, cond)
  if cond then
    passed = passed + 1
    print(("[PASS] %s"):format(name))
  else
    failed = failed + 1
    print(("[FAIL] %s"):format(name))
  end
end

local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  return content
end

print("============================================")
print(" Nebula — Phase 4.2.3-S2 Verification")
print("============================================")

-- =========================================================================
-- 1. text_runtime.nelua CJK 函数声明
-- =========================================================================
print("\n=== 1. CJK runtime functions in text_runtime.nelua ===")

local tr = read_file("src/text_runtime.nelua")
check("S2: text_runtime.nelua exists", tr ~= nil)
check("S2: requires cjk_shaping_tables",
  tr and tr:find('require "cjk_shaping_tables"') ~= nil)

-- =========================================================================
-- 2. nebula_cjk_glyph_lookup 存在性
-- =========================================================================
print("\n=== 2. nebula_cjk_glyph_lookup ===")

check("S2: nebula_cjk_glyph_lookup declared",
  tr and tr:find("global function nebula_cjk_glyph_lookup") ~= nil)
check("S2: uses NEBULA_CJK_CODEPOINTS for binary search",
  tr and tr:find("NEBULA_CJK_CODEPOINTS") ~= nil)
check("S2: binary search pattern (lo <= hi)",
  tr and tr:find("while lo <= hi") ~= nil)
check("S2: returns int32 (-1 for not found)",
  tr and tr:find("return %-1") ~= nil)

-- =========================================================================
-- 3. nebula_cjk_text_compute_advances 存在性
-- =========================================================================
print("\n=== 3. nebula_cjk_text_compute_advances ===")

check("S2: nebula_cjk_text_compute_advances declared",
  tr and tr:find("global function nebula_cjk_text_compute_advances") ~= nil)
check("S2: UTF-8 decoding (0xE0 / 0xF0 masks)",
  tr and tr:find("0xE0") ~= nil and tr:find("0xF0") ~= nil)
check("S2: CJK scale from NEBULA_CJK_UPEM",
  tr and tr:find("NEBULA_CJK_UPEM") ~= nil)
check("S2: ASCII fallback via NEBULA_SLUG_GLYPHS",
  tr and tr:find("NEBULA_SLUG_GLYPHS") ~= nil)
check("S2: advance sentinel (末尾哨兵)",
  tr and tr:find("out_advances%[count%]") ~= nil)

-- =========================================================================
-- 4. nebula_cjk_slug_text_build_vertices 存在性
-- =========================================================================
print("\n=== 4. nebula_cjk_slug_text_build_vertices ===")

check("S2: nebula_cjk_slug_text_build_vertices declared",
  tr and tr:find("global function nebula_cjk_slug_text_build_vertices") ~= nil)
check("S2: CJK placeholder path (curve_count=0)",
  tr and tr:find("CJK placeholder") ~= nil or tr:find("curve_count=0") ~= nil)
check("S2: NebulaSlugVertex output",
  tr and tr:find("NebulaSlugVertex") ~= nil)
check("S2: out_width/out_height return parameters",
  tr and tr:find("out_width") ~= nil and tr:find("out_height") ~= nil)
check("S2: ASCII Slug fallback path in vertex builder",
  tr and tr:find("NEBULA_SLUG_FIRST_CODEPOINT") ~= nil)

-- =========================================================================
-- 5. cjk_text_demo.nelua 存在性
-- =========================================================================
print("\n=== 5. CJK text demo ===")

local demo = read_file("examples/cjk_text_demo.nelua")
check("S2: cjk_text_demo.nelua exists", demo ~= nil)
check("S2: demo requires text_runtime",
  demo and demo:find('require "text_runtime"') ~= nil)
check("S2: demo uses nebula_cjk_slug_text_build_vertices",
  demo and demo:find("nebula_cjk_slug_text_build_vertices") ~= nil)
check("S2: demo uses nebula_cjk_glyph_lookup",
  demo and demo:find("nebula_cjk_glyph_lookup") ~= nil)
check("S2: demo uses nebula_cjk_text_compute_advances",
  demo and demo:find("nebula_cjk_text_compute_advances") ~= nil)
check("S2: demo uses SlugTextPipeline",
  demo and demo:find("SlugTextPipeline") ~= nil)
check("S2: demo has CJK UTF-8 content (你好)",
  demo and (demo:find("\\xE4\\xBD\\xA0") ~= nil or demo:find("\xE4\xBD\xA0") ~= nil))
check("S2: demo has ASCII text (fallback test)",
  demo and demo:find("ASCII") ~= nil)
check("S2: demo has mixed content (中英混排)",
  demo and (demo:find("\\xE4\\xB8\\xAD\\xE8\\x8B\\xB1") ~= nil or demo:find("\xE4\xB8\xAD\xE8\x8B\xB1") ~= nil))
check("S2: demo has dynamic frame counter",
  demo and demo:find("frame_count") ~= nil)

-- =========================================================================
-- 6. build.sh 包含 cjk_text_demo
-- =========================================================================
print("\n=== 6. Build script ===")

local build = read_file("build.sh")
check("S2: build.sh includes cjk_text_demo target",
  build and build:find("cjk_text_demo") ~= nil)

-- =========================================================================
-- 7. 公理 A 合规：S2 运行时代码无 HarfBuzz/stbtt 调用
-- =========================================================================
print("\n=== 7. Axiom A compliance (S2 runtime) ===")

-- text_runtime.nelua 中不应有 hb_shape, hb_buffer, stbtt_GetCodepointHMetrics 等
-- 注意：require 的头文件绑定不算，我们检查的是函数调用
check("S2: no hb_shape() call in text_runtime",
  tr and not tr:find("hb_shape%("))
check("S2: no hb_buffer_create() call in text_runtime",
  tr and not tr:find("hb_buffer_create%("))
check("S2: no hb_font_create() call in text_runtime",
  tr and not tr:find("hb_font_create%("))
check("S2: no stbtt_GetCodepointHMetrics in text_runtime",
  tr and not tr:find("stbtt_GetCodepointHMetrics"))
check("S2: no require 'harfbuzz' in text_runtime",
  tr and not tr:find("require.-harfbuzz"))

-- =========================================================================
-- 8. 公理 B 合规：L0/L1/L2 分层
-- =========================================================================
print("\n=== 8. Axiom B compliance ===")

-- CJK shaping 表是 L0（编译期常量）
local tables = read_file("assets/generated/cjk_shaping_tables.nelua")
check("S2: CJK tables are <const> (L0 permanent)",
  tables and tables:find("<const>") ~= nil)

-- 排版函数输出为栈分配数组（L2 帧级）
check("S2: advances output is caller-provided array (L2)",
  tr and tr:find("out_advances: %*%[0%]float32") ~= nil)
check("S2: vertices output is caller-provided array (L2)",
  tr and tr:find("out_vertices: %*%[0%]NebulaSlugVertex") ~= nil)

-- =========================================================================
-- 9. 数据完整性交叉验证
-- =========================================================================
print("\n=== 9. Cross-validation ===")

-- CJK shaping 表仍然完整
check("S2: CJK table has 3755 entries",
  tables and tables:find("NEBULA_CJK_GLYPH_COUNT <const> = 3755") ~= nil)
check("S2: CJK UPEM = 1000",
  tables and tables:find("NEBULA_CJK_UPEM <const> = 1000") ~= nil)

-- Slug ASCII 表仍然完整
local slug = read_file("assets/generated/liberation_sans_slug_metrics.nelua")
check("S2: ASCII Slug metrics still present",
  slug and slug:find("NEBULA_SLUG_GLYPH_COUNT") ~= nil)

-- =========================================================================
-- 汇总
-- =========================================================================
print(string.format(
  "\n============================================\n Results: %d/%d passed, %d failed\n============================================",
  passed, passed + failed, failed))

if failed > 0 then
  print("[REGRESSION DETECTED]")
  os.exit(1)
else
  print("[ALL PASS] Phase 4.2.3-S2 verification complete.")
end
