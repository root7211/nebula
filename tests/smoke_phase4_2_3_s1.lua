-- smoke_phase4_2_3_s1.lua
-- Nebula — Phase 4.2.3-S1 验证测试
--
-- 验证 GB2312 一级 3755 字 shaping 表的完整性和正确性。
--
-- 检查项：
--   1. 生成文件存在且包含 S1 头标记
--   2. GLYPH_COUNT = 3755, UPEM = 1000, KERN_PAIR_COUNT = 0
--   3. 所有 3755 条目存在且 glyph_id 非零
--   4. codepoint 按升序排列（支持二分查找）
--   5. S0 原始 20 字子集仍然存在（向后兼容）
--   6. 表文件大小 < 4 MB（内嵌限制）
--   7. 无 HarfBuzz 运行时符号（公理 A 合规）
--   8. advance 值合理（CJK 等宽 = UPEM）
--   9. 预处理器源码包含 GB2312 字符集声明
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

local function file_size(path)
  local f = io.open(path, "rb")
  if not f then return 0 end
  local size = f:seek("end")
  f:close()
  return size
end

print("============================================")
print(" Nebula — Phase 4.2.3-S1 Verification")
print("============================================")

-- =========================================================================
-- 1. 生成文件存在且包含 S1 头标记
-- =========================================================================
print("\n=== 1. Generated file existence & header ===")

local shaping = read_file("assets/generated/cjk_shaping_tables.nelua")
check("S1: cjk_shaping_tables.nelua exists", shaping ~= nil)
check("S1: header contains 'Phase 4.2.3-S1'", shaping and shaping:find("Phase 4.2.3%-S1") ~= nil)
check("S1: header contains 'GB2312'", shaping and shaping:find("GB2312") ~= nil)
check("S1: header contains '3755'", shaping and shaping:find("3755") ~= nil)

-- =========================================================================
-- 2. 全局常量正确
-- =========================================================================
print("\n=== 2. Global constants ===")

check("S1: GLYPH_COUNT = 3755",
  shaping and shaping:find("NEBULA_CJK_GLYPH_COUNT <const> = 3755") ~= nil)
check("S1: UPEM = 1000",
  shaping and shaping:find("NEBULA_CJK_UPEM <const> = 1000") ~= nil)
check("S1: KERN_PAIR_COUNT = 0",
  shaping and shaping:find("NEBULA_CJK_KERN_PAIR_COUNT <const> = 0") ~= nil)

-- =========================================================================
-- 3. 所有 3755 条目存在且 glyph_id 非零
-- =========================================================================
print("\n=== 3. Entry completeness ===")

local entry_count = 0
local zero_glyph_count = 0
if shaping then
  for _ in shaping:gmatch("codepoint=0x%x%x%x%x") do
    entry_count = entry_count + 1
  end
  for _ in shaping:gmatch("glyph_id=0[,%s]") do
    zero_glyph_count = zero_glyph_count + 1
  end
end
check("S1: exactly 3755 glyph entries", entry_count == 3755)
check("S1: zero .notdef entries (all glyph_id > 0)", zero_glyph_count == 0)

-- =========================================================================
-- 4. codepoint 按升序排列
-- =========================================================================
print("\n=== 4. Codepoint sort order ===")

local codepoints = {}
if shaping then
  for hex in shaping:gmatch("codepoint=0x(%x%x%x%x)") do
    codepoints[#codepoints + 1] = tonumber(hex, 16)
  end
end
local is_sorted = true
for i = 2, #codepoints do
  if codepoints[i] <= codepoints[i-1] then
    is_sorted = false
    break
  end
end
check("S1: codepoints strictly ascending (binary search ready)", is_sorted)
check("S1: first codepoint in CJK range (>= 0x4E00)",
  #codepoints > 0 and codepoints[1] >= 0x4E00)
check("S1: last codepoint in CJK range (<= 0x9FFF)",
  #codepoints > 0 and codepoints[#codepoints] <= 0x9FFF)

-- =========================================================================
-- 5. S0 原始 20 字子集存在（向后兼容）
-- =========================================================================
print("\n=== 5. S0 backward compatibility ===")

local s0_chars = {
  0x4F60, 0x597D, 0x4E16, 0x754C, 0x4EBA,  -- 你好世界人
  0x5927, 0x5B66, 0x4E2D, 0x56FD, 0x7684,  -- 大学中国的
  0x662F, 0x4E0D, 0x4E86, 0x6211, 0x4EEC,  -- 是不了我们
  0x8FD9, 0x4E2A, 0x6709, 0x5728, 0x4E3A,  -- 这个有在为
}
local s0_present = 0
local cp_set = {}
for _, cp in ipairs(codepoints) do cp_set[cp] = true end
for _, cp in ipairs(s0_chars) do
  if cp_set[cp] then s0_present = s0_present + 1 end
end
check("S1: all 20 S0 core chars present in S1 table", s0_present == 20)

-- =========================================================================
-- 6. 表文件大小 < 4 MB
-- =========================================================================
print("\n=== 6. File size limit ===")

local size = file_size("assets/generated/cjk_shaping_tables.nelua")
check("S1: file size < 4 MB", size > 0 and size < 4 * 1024 * 1024)
check("S1: file size < 1 MB (expected ~424 KB)", size > 0 and size < 1024 * 1024)
print(("  (actual: %.1f KB)"):format(size / 1024))

-- =========================================================================
-- 7. 无 HarfBuzz 运行时符号（公理 A 合规）
-- =========================================================================
print("\n=== 7. Axiom A compliance ===")

check("S1: no hb_shape in generated tables",
  shaping and not shaping:find("hb_shape"))
check("S1: no hb_font in generated tables",
  shaping and not shaping:find("hb_font"))
check("S1: no hb_buffer in generated tables",
  shaping and not shaping:find("hb_buffer"))
check("S1: no require 'harfbuzz' in generated tables",
  shaping and not shaping:find("require.*harfbuzz"))

-- =========================================================================
-- 8. advance 值合理性
-- =========================================================================
print("\n=== 8. Advance value sanity ===")

local advances = {}
if shaping then
  for adv in shaping:gmatch("advance=(%d+)") do
    advances[#advances + 1] = tonumber(adv)
  end
end
-- CJK 等宽：advance 应该都是 UPEM (1000)
local all_1000 = true
for _, adv in ipairs(advances) do
  if adv ~= 1000 then all_1000 = false; break end
end
check("S1: all CJK advances = 1000 (fullwidth monospaced)", all_1000)
check("S1: advance count matches entry count", #advances == 3755)

-- =========================================================================
-- 9. 预处理器源码检查
-- =========================================================================
print("\n=== 9. Preprocessor source ===")

local preprocessor = read_file("tools/font_preprocessor_cjk.nelua")
check("S1: preprocessor exists", preprocessor ~= nil)
check("S1: preprocessor declares CHARSET_SIZE = 3755",
  preprocessor and preprocessor:find("CHARSET_SIZE.*3755") ~= nil)
check("S1: preprocessor uses hb_font_get_nominal_glyph (direct API)",
  preprocessor and preprocessor:find("hb_font_get_nominal_glyph") ~= nil)
check("S1: preprocessor uses hb_font_get_glyph_h_advance",
  preprocessor and preprocessor:find("hb_font_get_glyph_h_advance") ~= nil)

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
  print("[ALL PASS] Phase 4.2.3-S1 verification complete.")
end
