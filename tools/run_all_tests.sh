#!/usr/bin/env bash
# =============================================================================
# run_all_tests.sh
# Nebula GUI Compiler — Phase 3.2.5 Full Regression Test Suite
#
# 运行所有 Lua 冒烟测试和编译回归测试。
#
# Usage:
#   bash tools/run_all_tests.sh
# =============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

PASS=0
FAIL=0
TOTAL=0

run_test() {
  local desc="$1"
  shift
  TOTAL=$((TOTAL + 1))
  echo ""
  echo "--- [$TOTAL] $desc ---"
  if "$@" 2>&1; then
    PASS=$((PASS + 1))
    echo "[PASS] $desc"
  else
    FAIL=$((FAIL + 1))
    echo "[FAIL] $desc"
  fi
}

echo "============================================"
echo " Nebula Phase 3.2.5 — Full Regression Suite"
echo "============================================"

# ---- Part 1: Lua 冒烟测试（纯编译期逻辑验证） ----
echo ""
echo "=== Part 1: Lua Smoke Tests ==="
run_test "smoke_phase3_2_2 (pipeline_factory textured path)" \
  nelua-lua tools/smoke_phase3_2_2.lua

run_test "smoke_phase3_2_3 (shader_compose SDF text)" \
  nelua-lua tools/smoke_phase3_2_3.lua

run_test "smoke_phase3_2_4 (TextVisual derive engine)" \
  nelua-lua tools/smoke_phase3_2_4.lua

run_test "verify_p2_4 (interaction_factory)" \
  nelua-lua tools/verify_p2_4.lua

# ---- Part 2: 编译回归测试（Nelua → C → 二进制） ----
echo ""
echo "=== Part 2: Compilation Regression Tests ==="
run_test "compile text_demo (Phase 3.2.5)" \
  bash build.sh text_demo

run_test "compile button_demo (Phase 2.4)" \
  bash build.sh button_demo

run_test "compile login_demo (Phase 2.4)" \
  bash build.sh login_demo

run_test "compile simple_rect_demo (Phase 2.4)" \
  bash build.sh simple_rect_demo

run_test "compile shadow_demo (Phase 2.5)" \
  bash build.sh shadow_demo

run_test "compile layout_demo (Phase 3.1)" \
  bash build.sh layout_demo

run_test "compile uniform_layout_test (Phase 2.1)" \
  bash build.sh uniform_layout_test

# ---- 总结 ----
echo ""
echo "============================================"
echo " Results: $PASS/$TOTAL passed, $FAIL failed"
echo "============================================"

if [ "$FAIL" -gt 0 ]; then
  echo "[REGRESSION DETECTED] $FAIL test(s) failed!"
  exit 1
else
  echo "[ALL PASS] Phase 3.2.5 regression suite complete."
  exit 0
fi
