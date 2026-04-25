#!/usr/bin/env bash
# =============================================================================
# Nebula GUI Compiler — Build Script
#
# 当前仓库状态：Phase 3.9 — 文本一等公民 + Slot Producer 重构
#
# Usage:
#   ./build.sh                     # 默认构建 button_demo
#   ./build.sh form_demo           # 构建 Phase 3.9 表单演示（文本一等公民）
#   ./build.sh dynamic_list_demo   # 构建 Phase 3.9 动态列表演示（Slot Producer）
#   ./build.sh login_demo          # 构建 Phase 3.4.4 登录框演示
#   ./build.sh text_demo           # 构建 Phase 3.2.5 文本渲染展示
#   ./build.sh shadow_demo         # 构建 Phase 2.5 阴影演示
#   ./build.sh layout_demo         # 构建 Phase 3.1 布局演示
#   ./build.sh uniform_layout_test # 构建 Phase 2.1 Uniform 布局测试（无 GPU）
#
# 回归测试：
#   bash tools/run_all_tests.sh   # 运行全部 28 项回归测试
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
  button_demo|login_demo|simple_rect_demo|shadow_demo|layout_demo|text_demo|dynamic_list_demo|form_demo)
    NEEDS_GPU=1
    ;;
  uniform_layout_test)
    NEEDS_GPU=0
    ;;
  *)
    echo "[nebula] Error: unknown target '$TARGET'"
    echo "         Available targets: button_demo, login_demo, simple_rect_demo, shadow_demo,"
    echo "                            layout_demo, text_demo, dynamic_list_demo, form_demo,"
    echo "                            uniform_layout_test"
    exit 1
    ;;
esac

echo "[nebula] Building $TARGET..."

if [ "$NEEDS_GPU" = "1" ]; then
  nelua \
    -L "$SCRIPT_DIR/src" \
    -L "$SCRIPT_DIR/assets/generated" \
    --cflags="-I$VENDOR/include" \
    --ldflags="-L$VENDOR/lib -lwgpu_native -lglfw -lm -ldl -Wl,-rpath,$VENDOR/lib" \
    "$SCRIPT_DIR/examples/$TARGET.nelua"
else
  # 纯编译期 / 运行期测试：不链接 wgpu/glfw
  nelua \
    -L "$SCRIPT_DIR/src" \
    -L "$SCRIPT_DIR/assets/generated" \
    "$SCRIPT_DIR/examples/$TARGET.nelua"
fi

echo "[nebula] Build complete: ~/.cache/nelua/$TARGET"
echo ""

# 运行指引
echo "To run:"
echo "  LD_LIBRARY_PATH=$VENDOR/lib ~/.cache/nelua/$TARGET"
echo ""
echo "If no display available, use Xvfb:"
echo "  Xvfb :99 -screen 0 1024x768x24 &"
echo "  DISPLAY=:99 LD_LIBRARY_PATH=$VENDOR/lib ~/.cache/nelua/$TARGET"
