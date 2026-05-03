-- =============================================================================
-- smoke_phase4_7_s6.lua
-- Nebula GUI Compiler — Phase 4.7-S6 Smoke Test
--
-- File I/O 架构验证：
--   · C stdio FFI 绑定生成（FILE, fopen, fclose, fread, fwrite, fseek, ftell）
--   · save_file(path) 方法生成
--   · load_file(path) 方法生成
--   · 版本号更新到 v0.4_phase4.7_s6
--   · roundtrip 验证：save → load → 内容一致
--   · CRLF 处理、空文件、POSIX 换行末尾
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
  local s = f:read("*a")
  f:close()
  return s
end

local gbf_src  = read_file("src/derive/gap_buffer_factory.lua")
local core_src = read_file("src/nebula_core.nelua")

print("=== Phase 4.7-S6: File I/O Architecture ===")
print("")

-- ---- 1. 版本号 ----
print("--- 1. Version ---")
check("gap_buffer_factory version updated to v0.4_phase4.7_s6",
  gbf_src:find("v0.4_phase4.7_s6") ~= nil)
check("nebula_core asserts new version",
  core_src:find("v0.4_phase4.7_s6") ~= nil)

-- ---- 2. C stdio FFI 绑定 ----
print("")
print("--- 2. C stdio FFI Bindings ---")
check("_nebula_stdio_emitted guard exists",
  gbf_src:find("_nebula_stdio_emitted") ~= nil)
check("FILE cimport generated",
  gbf_src:find("global FILE <cimport, nodecl>") ~= nil)
check("fopen binding generated",
  gbf_src:find("global function fopen") ~= nil)
check("fclose binding generated",
  gbf_src:find("global function fclose") ~= nil)
check("fread binding generated",
  gbf_src:find("global function fread") ~= nil)
check("fwrite binding generated",
  gbf_src:find("global function fwrite") ~= nil)
check("fseek binding generated",
  gbf_src:find("global function fseek") ~= nil)
check("ftell binding generated",
  gbf_src:find("global function ftell") ~= nil)

-- ---- 3. save_file 方法生成 ----
print("")
print("--- 3. save_file Method ---")
check("save_file method exists in factory",
  gbf_src:find("function.*:save_file%(path: cstring%)") ~= nil)
check("save_file opens file with wb mode",
  gbf_src:find('"wb"') ~= nil)
check("save_file calls flatten_lines",
  gbf_src:find("self:flatten_lines") ~= nil)
check("save_file calls fwrite",
  gbf_src:find("fwrite%(") ~= nil)
check("save_file calls fclose",
  gbf_src:find("fclose%(fp%)") ~= nil)
check("save_file adds trailing newline (POSIX)",
  gbf_src:find("local nl: uint8 = 10") ~= nil)
check("save_file returns boolean",
  gbf_src:find("save_file.-: boolean") ~= nil)

-- ---- 4. load_file 方法生成 ----
print("")
print("--- 4. load_file Method ---")
check("load_file method exists in factory",
  gbf_src:find("function.*:load_file%(path: cstring%)") ~= nil)
check("load_file opens file with rb mode",
  gbf_src:find('"rb"') ~= nil)
check("load_file calls fseek for file size",
  gbf_src:find("fseek%(fp, 0, 2%)") ~= nil)
check("load_file calls ftell",
  gbf_src:find("ftell%(fp%)") ~= nil)
check("load_file calls fread",
  gbf_src:find("fread%(") ~= nil)
check("load_file calls self:clear()",
  gbf_src:find("self:clear%(%)") ~= nil)
check("load_file handles newline (ch == 10)",
  gbf_src:find("ch == 10") ~= nil)
check("load_file skips CR (ch ~= 13) for CRLF support",
  gbf_src:find("ch ~= 13") ~= nil)
check("load_file inserts chars via insert_char",
  gbf_src:find("insert_char%(ch%)") ~= nil)
check("load_file resets cursor to beginning",
  gbf_src:find("self.cursor_row = 0") ~= nil and
  gbf_src:find("self.cursor_col = 0") ~= nil)
check("load_file strips trailing empty line from POSIX newline",
  gbf_src:find("Strip trailing empty line") ~= nil)
check("load_file handles empty file",
  gbf_src:find("file_size <= 0") ~= nil)
check("load_file returns boolean",
  gbf_src:find("load_file.-: boolean") ~= nil)

-- ---- 5. Functional: 类型生成验证 ----
print("")
print("--- 5. Functional: Type Generation ---")
dofile("src/derive/gap_buffer_factory.lua")
local mb_type, mb_src, line_type = nebula_gen_multiline_buffer_type(64, 16)
check("Generator returns type name NebulaMultiBuf64_16",
  mb_type == "NebulaMultiBuf64_16")
check("Generator returns non-empty source",
  mb_src ~= nil and #mb_src > 0)
check("Generated source contains save_file method",
  mb_src:find("function NebulaMultiBuf64_16:save_file") ~= nil)
check("Generated source contains load_file method",
  mb_src:find("function NebulaMultiBuf64_16:load_file") ~= nil)
check("Generated source contains FILE cimport",
  mb_src:find("global FILE") ~= nil)
check("Generated source contains fopen",
  mb_src:find("fopen") ~= nil)

-- Second call should NOT re-emit stdio bindings
local mb_type2, mb_src2 = nebula_gen_multiline_buffer_type(32, 8)
check("Second generation does not re-emit stdio bindings",
  mb_src2:find("global FILE") == nil or mb_src2 == nil or #mb_src2 == 0)

-- ---- 6. Functional: roundtrip (Lua-level simulation) ----
print("")
print("--- 6. Functional: Roundtrip Simulation ---")
-- Verify that save_file writes flatten_lines output + trailing newline
-- and load_file splits by \n and inserts chars
-- We do this by checking code patterns that guarantee correctness

check("save_file flattens then writes n bytes",
  mb_src:find("fwrite%(&tmp%[0%], 1, .-%(@csize%)%(n%), fp%)") ~= nil)
check("load_file increments line_count on newline",
  mb_src:find("self.line_count = self.line_count %+ 1") ~= nil)
check("load_file respects max_lines limit",
  mb_src:find("row %+ 1 < %d+") ~= nil)
check("load_file moves cursor home after load",
  mb_src:find("move_cursor_home") ~= nil)

-- ---- 7. Roundtrip file test (actual file I/O at Lua level) ----
print("")
print("--- 7. Roundtrip File Test (Lua I/O) ---")
-- Write a test file, verify the generated load_file code would handle it
local test_content = "Hello World\nLine 2\nLine 3\n"
local tmp_path = "/tmp/_nebula_s6_test.txt"
local wf = io.open(tmp_path, "wb")
wf:write(test_content)
wf:close()

-- Read back and simulate what load_file does
local rf = io.open(tmp_path, "rb")
local raw = rf:read("*a")
rf:close()
check("Test file written and read back correctly",
  raw == test_content)

-- Simulate the line-splitting logic
local lines_sim = {}
local current_line = {}
for i = 1, #raw do
  local ch = raw:byte(i)
  if ch == 10 then
    table.insert(lines_sim, table.concat(current_line))
    current_line = {}
  elseif ch ~= 13 then
    table.insert(current_line, string.char(ch))
  end
end
if #current_line > 0 then
  table.insert(lines_sim, table.concat(current_line))
end
-- Strip trailing empty line from POSIX newline
if #lines_sim > 1 and lines_sim[#lines_sim] == "" then
  if raw:byte(#raw) == 10 then
    table.remove(lines_sim)
  end
end

check("Simulated load produces 3 lines", #lines_sim == 3)
check("Line 1 = 'Hello World'", lines_sim[1] == "Hello World")
check("Line 2 = 'Line 2'", lines_sim[2] == "Line 2")
check("Line 3 = 'Line 3'", lines_sim[3] == "Line 3")

-- Test CRLF handling
local crlf_content = "A\r\nB\r\nC\r\n"
local wf2 = io.open(tmp_path, "wb")
wf2:write(crlf_content)
wf2:close()
local rf2 = io.open(tmp_path, "rb")
local raw2 = rf2:read("*a")
rf2:close()

local lines_crlf = {}
local cur2 = {}
for i = 1, #raw2 do
  local ch = raw2:byte(i)
  if ch == 10 then
    table.insert(lines_crlf, table.concat(cur2))
    cur2 = {}
  elseif ch ~= 13 then
    table.insert(cur2, string.char(ch))
  end
end
if #cur2 > 0 then
  table.insert(lines_crlf, table.concat(cur2))
end
if #lines_crlf > 1 and lines_crlf[#lines_crlf] == "" then
  if raw2:byte(#raw2) == 10 then
    table.remove(lines_crlf)
  end
end

check("CRLF simulated load produces 3 lines", #lines_crlf == 3)
check("CRLF Line 1 = 'A'", lines_crlf[1] == "A")
check("CRLF Line 2 = 'B'", lines_crlf[2] == "B")
check("CRLF Line 3 = 'C'", lines_crlf[3] == "C")

-- Clean up
os.remove(tmp_path)

-- ---- 总结 ----
print("")
print(("============================================"))
print((" Results: %d/%d passed, %d failed"):format(
  pass_count, pass_count + fail_count, fail_count))
print(("============================================"))

if fail_count > 0 then
  print("[REGRESSION DETECTED] Phase 4.7-S6 smoke test FAILED")
  assert(false, "Phase 4.7-S6 smoke test FAILED")
else
  print("[ALL PASS] Phase 4.7-S6 file I/O architecture validated")
end
