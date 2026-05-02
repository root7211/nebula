#!/usr/bin/env bash
# =============================================================================
# run_all_tests.sh
# Nebula GUI Compiler — Full Regression Test Suite
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
echo " Nebula — Full Regression Suite"
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

# ★ Phase 3.10.5 专项测试（独立文本标签 & 多 Pass 渲染兼容）
run_test "smoke_phase3_10_5 (Phase 3.10.5 — 独立文本标签 & 多 Pass 渲染兼容验证)" \
  nelua-lua tests/smoke_phase3_10_5.lua

# ★ Phase 3.11 专项测试（Layout-App 统一注册 & 30 行愿景）
run_test "smoke_phase3_11 (Phase 3.11 — Layout-App 统一注册 & 30 行愿景验证)" \
  nelua-lua tests/smoke_phase3_11.lua

# ★ Phase 3.12 专项测试（响应式重排 — Clamp 感知分段插值）
run_test "smoke_phase3_12 (Phase 3.12 — 响应式重排 & Clamp 感知分段插值验证)" \
  nelua-lua tests/smoke_phase3_12.lua

# ★ Phase 4.3 专项测试（可编程原语注册表 — register_primitive API 验证）
run_test "smoke_phase4_3 (Phase 4.3 — 可编程原语注册表 & 参数校验)" \
  nelua-lua tests/smoke_phase4_3.lua

# ★ Phase 4.4 S1: scrollable 原语注册 + scissor rect API 验证
run_test "smoke_phase4_4_s1 (Phase 4.4 S1 — scrollable 原语注册 & 滚动逻辑验证)" \
  nelua-lua tests/smoke_phase4_4_s1.lua

# ★ Phase 4.4 S2: dropdown_manager 原语注册 + 跨组件状态验证
run_test "smoke_phase4_4_s2 (Phase 4.4 S2 — dropdown_manager 原语注册 & 下拉交互验证)" \
  nelua-lua tests/smoke_phase4_4_s2.lua

# ★ Phase 4.4 S3: multiline_editable 原语注册 + NebulaMultiBuf 类型生成验证
run_test "smoke_phase4_4_s3 (Phase 4.4 S3 — multiline_editable 原语注册 & NebulaMultiBuf 验证)" \
  nelua-lua tests/smoke_phase4_4_s3.lua

# ★ Phase 4.3 S3: 字段冲突检测 + static_asserts 编译期契约校验
run_test "smoke_phase4_3_s3 (Phase 4.3 S3 — 字段冲突检测 & static_asserts 契约校验)" \
  nelua-lua tests/smoke_phase4_3_s3.lua

# ★ Phase 4.3 Task D: process_body 公理校验（引用域闭合 + 分支覆盖增强）
run_test "smoke_phase4_3_s4 (Phase 4.3 Task D — process_body 公理校验)" \
  nelua-lua tests/smoke_phase4_3_s4.lua

# ★ Phase 4.X: 输入系统补全（剪贴板 API + Unicode 扩展 + Ctrl+C/V/X/A）
run_test "smoke_phase4_x_input (Phase 4.X — 剪贴板 + Unicode 输入 + extract_range)" \
  nelua-lua tests/smoke_phase4_x_input.lua

# ★ Phase 4.2.3 S0: HarfBuzz 绑定 + CJK 字形预处理管线验证
run_test "smoke_phase4_2_3 (Phase 4.2.3 S0 — HarfBuzz 绑定 + CJK shaping tables)" \
  nelua-lua tests/smoke_phase4_2_3.lua

# ★ Phase 4.2.2 D-4.1-C: Storage Buffer 可扩展性基准审计
run_test "smoke_phase4_2_2_bench (Phase 4.2.2 D-4.1-C — Storage Buffer scalability audit)" \
  nelua-lua tests/smoke_phase4_2_2_bench.lua

# ★ Phase 4.2.3 S1: GB2312 一级 3755 字 shaping 表验证
run_test "smoke_phase4_2_3_s1 (Phase 4.2.3 S1 — GB2312 L1 3755 字 shaping 表完整性)" \
  nelua-lua tests/smoke_phase4_2_3_s1.lua

# ★ Phase 4.2.3 S2: CJK 运行时排版函数验证
run_test "smoke_phase4_2_3_s2 (Phase 4.2.3 S2 — CJK 运行时排版 + 混排 + 公理合规)" \
  nelua-lua tests/smoke_phase4_2_3_s2.lua

# ★ 交互原语运行时行为验证（BUG-4/5/6 回归守护）
run_test "verify_interaction_behavior (Runtime — 交互原语行为验证 & 回归守护)" \
  nelua-lua tests/verify_interaction_behavior.lua

# ---- Part 2: Compilation Regression Tests (Nelua → C → 二进制) ----
echo ""
echo "=== Part 2: Compilation Regression Tests ==="

# Phase 3.9 核心 Demo 编译回归（最新 API）
run_test "compile button_demo (Phase 3.9 — 按钮演示)" \
  nelua -c -L src -L assets/generated --add-path . --add-path examples --add-path assets/generated \
  --cflags="-I./vendor/wgpu-native/include" \
  --ldflags="-L./vendor/wgpu-native/lib -lwgpu_native -lglfw -lm -ldl -Wl,-rpath,./vendor/wgpu-native/lib" \
  examples/button_demo.nelua -o ~/.cache/nelua/button_demo

run_test "compile layout_demo (Phase 3.9 — 编译期 Flexbox 布局)" \
  nelua -c -L src -L assets/generated --add-path . --add-path examples --add-path assets/generated \
  --cflags="-I./vendor/wgpu-native/include" \
  --ldflags="-L./vendor/wgpu-native/lib -lwgpu_native -lglfw -lm -ldl -Wl,-rpath,./vendor/wgpu-native/lib" \
  examples/layout_demo.nelua -o ~/.cache/nelua/layout_demo

run_test "compile login_demo (Phase 3.9 — 文本一等公民登录框)" \
  nelua -c -L src -L assets/generated --add-path . --add-path examples --add-path assets/generated \
  --cflags="-I./vendor/wgpu-native/include" \
  --ldflags="-L./vendor/wgpu-native/lib -lwgpu_native -lglfw -lm -ldl -Wl,-rpath,./vendor/wgpu-native/lib" \
  examples/login_demo.nelua -o ~/.cache/nelua/login_demo

run_test "compile form_demo (Phase 3.9 — 文本一等公民表单)" \
  nelua -c -L src -L assets/generated --add-path . --add-path examples --add-path assets/generated \
  --cflags="-I./vendor/wgpu-native/include" \
  --ldflags="-L./vendor/wgpu-native/lib -lwgpu_native -lglfw -lm -ldl -Wl,-rpath,./vendor/wgpu-native/lib" \
  examples/form_demo.nelua -o ~/.cache/nelua/form_demo

run_test "compile dynamic_list_demo (Phase 3.9 — Slot Producer)" \
  nelua -c -L src -L assets/generated --add-path . --add-path examples --add-path assets/generated \
  --cflags="-I./vendor/wgpu-native/include" \
  --ldflags="-L./vendor/wgpu-native/lib -lwgpu_native -lglfw -lm -ldl -Wl,-rpath,./vendor/wgpu-native/lib" \
  examples/dynamic_list_demo.nelua -o ~/.cache/nelua/dynamic_list_demo

# ★ Phase 3.10.5 新升级的 Demo
run_test "compile shadow_demo (Phase 3.10.5 — 阴影已升级到 App 编排体系)" \
  nelua -c -L src -L assets/generated --add-path . --add-path examples --add-path assets/generated \
  --cflags="-I./vendor/wgpu-native/include" \
  --ldflags="-L./vendor/wgpu-native/lib -lwgpu_native -lglfw -lm -ldl -Wl,-rpath,./vendor/wgpu-native/lib" \
  examples/shadow_demo.nelua -o ~/.cache/nelua/shadow_demo

run_test "compile text_demo (Phase 3.10.5 — 独立文本标签已支持)" \
  nelua -c -L src -L assets/generated --add-path . --add-path examples --add-path assets/generated \
  --cflags="-I./vendor/wgpu-native/include" \
  --ldflags="-L./vendor/wgpu-native/lib -lwgpu_native -lglfw -lm -ldl -Wl,-rpath,./vendor/wgpu-native/lib" \
  examples/text_demo.nelua -o ~/.cache/nelua/text_demo

# ★ Phase 4.3 新增：slider_demo 编译回归（可编程原语 register_primitive DX 验证）
run_test "compile slider_demo (Phase 4.3 — 可编程原语 register_primitive DX 验证)" \
  nelua -c -L src -L assets/generated --add-path . --add-path examples --add-path assets/generated \
  --cflags="-I./vendor/wgpu-native/include" \
  --ldflags="-L./vendor/wgpu-native/lib -lwgpu_native -lglfw -lm -ldl -Wl,-rpath,./vendor/wgpu-native/lib" \
  examples/slider_demo.nelua -o ~/.cache/nelua/slider_demo

# ★ Phase 4.4 S1 新增：scrollable_demo 编译回归（scrollable 原语 + scissor rect 裁剪）
run_test "compile scrollable_demo (Phase 4.4 S1 — scrollable 原语 + container + scissor rect)" \
  nelua -c -L src -L assets/generated --add-path . --add-path examples --add-path assets/generated \
  --cflags="-I./vendor/wgpu-native/include" \
  --ldflags="-L./vendor/wgpu-native/lib -lwgpu_native -lglfw -lm -ldl -Wl,-rpath,./vendor/wgpu-native/lib" \
  examples/scrollable_demo.nelua -o ~/.cache/nelua/scrollable_demo

# ★ Phase 4.4 S2 新增：dropdown_demo 编译回归（dropdown_manager 原语 + 弹出层交互）
run_test "compile dropdown_demo (Phase 4.4 S2 — dropdown_manager 原语 + 弹出层选择器)" \
  nelua -c -L src -L assets/generated --add-path . --add-path examples --add-path assets/generated \
  --cflags="-I./vendor/wgpu-native/include" \
  --ldflags="-L./vendor/wgpu-native/lib -lwgpu_native -lglfw -lm -ldl -Wl,-rpath,./vendor/wgpu-native/lib" \
  examples/dropdown_demo.nelua -o ~/.cache/nelua/dropdown_demo

# ★ Phase 4.4 S3 新增：multiline_editable_demo 编译回归（multiline_editable 原语 + NebulaMultiBuf）
run_test "compile multiline_editable_demo (Phase 4.4 S3 — multiline_editable 原语 + 多行文本编辑)" \
  nelua -c -L src -L assets/generated --add-path . --add-path examples --add-path assets/generated \
  --cflags="-I./vendor/wgpu-native/include" \
  --ldflags="-L./vendor/wgpu-native/lib -lwgpu_native -lglfw -lm -ldl -Wl,-rpath,./vendor/wgpu-native/lib" \
  examples/multiline_editable_demo.nelua -o ~/.cache/nelua/multiline_editable_demo

# ★ Phase 4.2.2 D-4.1-C: slug_bench 编译回归（Storage Buffer benchmark）
run_test "compile slug_bench (Phase 4.2.2 D-4.1-C — Storage Buffer scalability benchmark)" \
  nelua -c -L src -L assets/generated --add-path . --add-path examples --add-path assets/generated \
  --cflags="-I./vendor/wgpu-native/include" \
  --ldflags="-L./vendor/wgpu-native/lib -lwgpu_native -lglfw -lm -ldl -Wl,-rpath,./vendor/wgpu-native/lib" \
  examples/slug_bench.nelua -o ~/.cache/nelua/slug_bench

# ★ Phase 4.2.3 S2: cjk_text_demo 编译回归（CJK + ASCII 混排 Slug 渲染）
run_test "compile cjk_text_demo (Phase 4.2.3 S2 — CJK + ASCII mixed text Slug rendering)" \
  nelua -c -L src -L assets/generated --add-path . --add-path examples --add-path assets/generated \
  --cflags="-I./vendor/wgpu-native/include" \
  --ldflags="-L./vendor/wgpu-native/lib -lwgpu_native -lglfw -lm -ldl -Wl,-rpath,./vendor/wgpu-native/lib" \
  examples/cjk_text_demo.nelua -o ~/.cache/nelua/cjk_text_demo

# ★ Phase 4.2.2 D-4.1-C: Storage Buffer 基础设施静态分析测试
run_test "smoke_phase4_2_2_bench (Phase 4.2.2 D-4.1-C — Storage Buffer infrastructure audit)" \
  nelua-lua tests/smoke_phase4_2_2_bench.lua

# ---- 总结 ----
echo ""
echo "============================================"
echo " Results: $PASS/$TOTAL passed, $FAIL failed"
echo "============================================"

if [ "$FAIL" -gt 0 ]; then
  echo "[REGRESSION DETECTED] $FAIL test(s) failed!"
  exit 1
else
  echo "[ALL PASS] Full regression suite complete."
  exit 0
fi
