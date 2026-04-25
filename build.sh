#!/usr/bin/env bash
# =============================================================================
# Nebula GUI Compiler — Build Script
#
# 当前仓库状态：Phase 3.10.5 — 独立文本标签支持 + 多 Pass 渲染兼容
#
# Usage:
#   ./build.sh                     # 默认构建 button_demo
#   ./build.sh button_demo         # 构建 Phase 3.9 按钮演示（最简入门）
#   ./build.sh layout_demo         # 构建 Phase 3.9 编译期 Flexbox 布局演示
#   ./build.sh login_demo          # 构建 Phase 3.9 登录框演示（文本一等公民）
#   ./build.sh form_demo           # 构建 Phase 3.9 表单演示（文本一等公民）
#   ./build.sh dynamic_list_demo   # 构建 Phase 3.9 动态列表演示（Slot Producer）
#   ./build.sh shadow_demo         # 构建 Phase 3.10.5 阴影演示（已升级到 App 编排体系）
#   ./build.sh text_demo           # 构建 Phase 3.10.5 文本渲染展示（已升级，支持独立文本标签）
#
# 回归测试：
#   bash tools/run_all_tests.sh   # 运行全部回归测试
# =============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENDOR="$SCRIPT_DIR/vendor/wgpu-native"

if [ ! -d "$VENDOR" ]; then
  echo "[nebula] Error: vendor/wgpu-native not found."
  echo "         Please download wgpu-native v29.0.0.0 and extract to vendor/wgpu-native/"
  echo "         See README.md for instructions."
  exit 1
fi

# 解析目标参数（默认 button_demo）
TARGET="${1:-button_demo}"

case "$TARGET" in
  button_demo|layout_demo|login_demo|form_demo|dynamic_list_demo|shadow_demo|text_demo)
    NEEDS_GPU=1
    ;;
  *)
    echo "[nebula] Error: unknown target '$TARGET'"
    echo "         Available targets:"
    echo "           Phase 3.10.5 (最新 API):"
    echo "             button_demo, layout_demo, login_demo, form_demo, dynamic_list_demo"
    echo "           Phase 3.10.5 (新升级):"
    echo "             shadow_demo, text_demo"
    exit 1
    ;;
esac

echo "[nebula] Building $TARGET..."

nelua \
  -L "$SCRIPT_DIR/src" \
  -L "$SCRIPT_DIR/assets/generated" \
  --cflags="-I$VENDOR/include" \
  --ldflags="-L$VENDOR/lib -lwgpu_native -lglfw -lm -ldl -Wl,-rpath,$VENDOR/lib" \
  "$SCRIPT_DIR/examples/$TARGET.nelua"

echo "[nebula] Build complete: ~/.cache/nelua/$TARGET"
echo ""

# 运行指引
echo "To run:"
echo "  LD_LIBRARY_PATH=$VENDOR/lib ~/.cache/nelua/$TARGET"
echo ""
echo "If no display available, use Xvfb:"
echo "  Xvfb :99 -screen 0 1024x768x24 &"
echo "  DISPLAY=:99 LD_LIBRARY_PATH=$VENDOR/lib ~/.cache/nelua/$TARGET"
