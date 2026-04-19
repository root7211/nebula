#!/bin/bash
# =============================================================================
# Nebula GUI Compiler — Phase 0 Build Script
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

echo "[nebula] Building Phase 0 Demo..."

nelua \
  -L "$SCRIPT_DIR/src" \
  --cflags="-I$VENDOR/include" \
  --ldflags="-L$VENDOR/lib -lwgpu_native -lglfw -lm -ldl -Wl,-rpath,$VENDOR/lib" \
  "$SCRIPT_DIR/examples/button_demo.nelua"

echo "[nebula] Build complete: ~/.cache/nelua/button_demo"
echo ""

# 运行指引
if [ -n "$WSL_DISTRO_NAME" ] || [ -n "$WSL_INTEROP" ] || [ -n "$WSLENV" ]; then
  echo "[nebula] WSL2 detected (Vulkan via d3d12 layer)."
  echo ""
  echo "To run:"
  echo "  LD_LIBRARY_PATH=$VENDOR/lib ~/.cache/nelua/button_demo"
  echo ""
  echo "Note: WSLg must be enabled for window display."
else
  echo "To run:"
  echo "  LD_LIBRARY_PATH=$VENDOR/lib ~/.cache/nelua/button_demo"
  echo ""
  echo "If no display available, use Xvfb:"
  echo "  Xvfb :99 -screen 0 1024x768x24 &"
  echo "  DISPLAY=:99 LD_LIBRARY_PATH=$VENDOR/lib ~/.cache/nelua/button_demo"
fi
