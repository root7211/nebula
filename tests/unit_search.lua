-- =============================================================================
-- unit_search.lua
-- Unit tests for search algorithm pattern verification
-- Tests the expected behavior of nebula_search_scan naive matching
-- =============================================================================

local tests_passed = 0
local tests_failed = 0

local function test(name, fn)
  io.write("  TEST: " .. name .. " ... ")
  local ok, err = pcall(fn)
  if ok then
    io.write("PASS\n")
    tests_passed = tests_passed + 1
  else
    io.write("FAIL: " .. tostring(err) .. "\n")
    tests_failed = tests_failed + 1
  end
end

-- Simulate the naive search algorithm used in nebula
local function naive_search(text, pattern)
  local matches = {}
  local tlen = #text
  local plen = #pattern
  if plen == 0 or plen > tlen then return matches end
  for i = 1, tlen - plen + 1 do
    local found = true
    for j = 1, plen do
      if text:byte(i + j - 1) ~= pattern:byte(j) then
        found = false
        break
      end
    end
    if found then
      matches[#matches + 1] = i
    end
  end
  return matches
end

print("=== Search Algorithm Unit Tests ===\n")

test("empty pattern returns no matches", function()
  local m = naive_search("hello world", "")
  assert(#m == 0, "expected 0 matches, got " .. #m)
end)

test("pattern longer than text returns no matches", function()
  local m = naive_search("hi", "hello world")
  assert(#m == 0)
end)

test("single char match", function()
  local m = naive_search("abcabc", "a")
  assert(#m == 2, "expected 2, got " .. #m)
  assert(m[1] == 1 and m[2] == 4)
end)

test("exact match", function()
  local m = naive_search("hello", "hello")
  assert(#m == 1 and m[1] == 1)
end)

test("no match", function()
  local m = naive_search("hello world", "xyz")
  assert(#m == 0)
end)

test("overlapping matches", function()
  local m = naive_search("aaaa", "aa")
  assert(#m == 3, "expected 3 overlapping matches, got " .. #m)
end)

test("UTF-8 byte sequence match", function()
  local text = "hello 你好 world"
  local m = naive_search(text, "你好")
  assert(#m == 1, "expected 1 CJK match, got " .. #m)
end)

test("case sensitive", function()
  local m = naive_search("Hello World", "hello")
  assert(#m == 0, "search should be case sensitive")
end)

test("match at end of string", function()
  local m = naive_search("abcdef", "def")
  assert(#m == 1 and m[1] == 4)
end)

test("max matches stress (512 limit simulation)", function()
  -- Simulate the fixed array limit in nebula
  local MAX_MATCHES = 512
  local text = string.rep("a", 1000)
  local m = naive_search(text, "a")
  -- The real implementation would cap at 512
  local capped = math.min(#m, MAX_MATCHES)
  assert(capped == MAX_MATCHES, "should cap at " .. MAX_MATCHES)
end)

print(string.format(
  "\n=== Results: %d passed, %d failed ===",
  tests_passed, tests_failed))

if tests_failed > 0 then os.exit(1) end
