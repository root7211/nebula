#!/bin/bash
# =============================================================================
# Nebula GUI Compiler — Phase 0 Build Script
#
# Usage:
#   ./build.sh               # 默认构建 button_demo
#   ./build.sh button_demo   # 构建 button_demo
#   ./build.sh login_demo    # 构建 login_demo
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
  button_demo|login_demo|simple_rect_demo)
    NEEDS_GPU=1
    ;;
  uniform_layout_test)
    NEEDS_GPU=0
    ;;
  *)
    echo "[nebula] Error: unknown target '$TARGET'"
    echo "         Available targets: button_demo, login_demo, simple_rect_demo, uniform_layout_test"
    exit 1
    ;;
esac

echo "[nebula] Building $TARGET..."

if [ "$NEEDS_GPU" = "1" ]; then
  nelua \
    -L "$SCRIPT_DIR/src" \
    --cflags="-I$VENDOR/include" \
    --ldflags="-L$VENDOR/lib -lwgpu_native -lglfw -lm -ldl -Wl,-rpath,$VENDOR/lib" \
    "$SCRIPT_DIR/examples/$TARGET.nelua"
else
  # 纯编译期 / 运行期测试：不链接 wgpu/glfw
  nelua \
    -L "$SCRIPT_DIR/src" \
    "$SCRIPT_DIR/examples/$TARGET.nelua"
fi

echo "[nebula] Build complete: ~/.cache/nelua/$TARGET"
echo ""

# 运行指引
if [ -n "$WSL_DISTRO_NAME" ] || [ -n "$WSL_INTEROP" ] || [ -n "$WSLENV" ]; then
  echo "[nebula] WSL2 detected (Vulkan via d3d12 layer)."
  echo ""
  echo "To run:"
  echo "  LD_LIBRARY_PATH=$VENDOR/lib ~/.cache/nelua/$TARGET"
  echo ""
  echo "Note: WSLg must be enabled for window display."
else
  echo "To run:"
  echo "  LD_LIBRARY_PATH=$VENDOR/lib ~/.cache/nelua/$TARGET"
  echo ""
  echo "If no display available, use Xvfb:"
  echo "  Xvfb :99 -screen 0 1024x768x24 &"
  echo "  DISPLAY=:99 LD_LIBRARY_PATH=$VENDOR/lib ~/.cache/nelua/$TARGET"
fi
