#!/usr/bin/env bash
# =============================================================================
# run_all_tests.sh
# Nebula GUI Compiler — Phase 3.9 Full Regression Test Suite
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
echo " Nebula Phase 3.9 — Full Regression Suite"
echo "============================================"

# ---- Part 1: Lua 冒烟测试（纯编译期逻辑验证） ----
echo ""
echo "=== Part 1: Lua Smoke Tests ==="

# Phase 3.3.x 测试（Phase 3.7 更新：验证废弃路径已删除）
run_test "smoke_arena (Phase 3.3.1 — Frame Arena allocator)" \
  nelua-lua tests/smoke_arena.lua

run_test "smoke_phase3_3_2 (Phase 3.3.2 — Storage Buffer infrastructure)" \
  nelua-lua tests/smoke_phase3_3_2.lua

run_test "smoke_phase3_3_3 (Phase 3.3.3 — Phase 3.7: 验证废弃函数已删除)" \
  nelua-lua tests/smoke_phase3_3_3.lua

run_test "smoke_phase3_3_4 (Phase 3.3.4 — Phase 3.7: 验证 standard_instanced 路径)" \
  nelua-lua tests/smoke_phase3_3_4.lua

# Phase 3.4.x 新增测试
run_test "smoke_phase3_4_1 (Phase 3.4.1 — Keyboard event collection)" \
  nelua-lua tests/smoke_phase3_4_1.lua

run_test "smoke_phase3_4_2 (Phase 3.4.2 — Text buffer logic)" \
  nelua-lua tests/smoke_phase3_4_2.lua

run_test "smoke_phase3_4_3 (Phase 3.4.3 — Cursor renderer)" \
  nelua-lua tests/smoke_phase3_4_3.lua

run_test "smoke_phase3_4_4 (Phase 3.4.4 — Login demo upgrade)" \
  nelua-lua tests/smoke_phase3_4_4.lua

# Phase 3.5.x 新增测试（Phase 3.7 更新：版本号断言已更新）
run_test "smoke_phase3_5_1 (Phase 3.5.1 / Phase 3.7 — 版本号 & 废弃路径验证)" \
  nelua-lua tests/smoke_phase3_5_1.lua

run_test "smoke_phase3_5_2 (Phase 3.5.2 — App factory & explicit orchestration)" \
  nelua-lua tests/smoke_phase3_5_2.lua

run_test "smoke_phase3_5_3 (Phase 3.5.3 — Toggleable primitive & orthogonal state)" \
  nelua-lua tests/smoke_phase3_5_3.lua

run_test "smoke_phase3_5_4 (Phase 3.5.4 — form_demo integration & full regression)" \
  nelua-lua tests/smoke_phase3_5_4.lua

# Phase 3.6.x 新增测试
run_test "smoke_phase3_6_1 (Phase 3.6.1 — compile-time fixed-capacity Gap Buffer)" \
  nelua-lua tests/smoke_phase3_6_1.lua

run_test "smoke_phase3_6_2 (Phase 3.6.2 — mouse hit-test & cursor sync)" \
  nelua-lua tests/smoke_phase3_6_2.lua

run_test "smoke_phase3_6_3 (Phase 3.6.3 — text selection & drag support)" \
  nelua-lua tests/smoke_phase3_6_3.lua

# Phase 3.7 专项测试（管线生成器收敛与死代码清理）
run_test "smoke_phase3_7 (Phase 3.7 — 管线收敛 & 死代码清理专项验证)" \
  nelua-lua tests/smoke_phase3_7.lua

# Phase 3.8 专项测试（渲染循环封装 & FrameArena 内嵌）
run_test "smoke_phase3_8 (Phase 3.8 — nebula_frame_render & FrameArena 内嵌验证)" \
  nelua-lua tests/smoke_phase3_8.lua

# Phase 3.9 专项测试（文本一等公民 & Slot Producer 重构）
run_test "smoke_phase3_9 (Phase 3.9 — 文本一等公民 & Slot Producer 重构验证)" \
  nelua-lua tests/smoke_phase3_9.lua

# ---- Part 2: 编译回归测试（Nelua → C → 二进制） ----
echo ""
echo "=== Part 2: Compilation Regression Tests ==="

# Phase 3.9 核心 Demo 编译回归（最新 API）
run_test "compile button_demo (Phase 3.9 — 按钮演示)" \
  bash build.sh button_demo

run_test "compile layout_demo (Phase 3.9 — 编译期 Flexbox 布局)" \
  bash build.sh layout_demo

run_test "compile login_demo (Phase 3.9 — 文本一等公民登录框)" \
  bash build.sh login_demo

run_test "compile form_demo (Phase 3.9 — 文本一等公民表单)" \
  bash build.sh form_demo

run_test "compile dynamic_list_demo (Phase 3.9 — Slot Producer)" \
  bash build.sh dynamic_list_demo

# 暂缓升级的 Demo（等待框架支持）
run_test "compile shadow_demo (Phase 2.5 — 暂缓升级，等待多 Pass 框架支持)" \
  bash build.sh shadow_demo

run_test "compile text_demo (Phase 3.2.5 — 暂缓升级，等待独立标签支持)" \
  bash build.sh text_demo

# ---- 总结 ----
echo ""
echo "============================================"
echo " Results: $PASS/$TOTAL passed, $FAIL failed"
echo "============================================"

if [ "$FAIL" -gt 0 ]; then
  echo "[REGRESSION DETECTED] $FAIL test(s) failed!"
  exit 1
else
  echo "[ALL PASS] Phase 3.9 regression suite complete."
  exit 0
fi
