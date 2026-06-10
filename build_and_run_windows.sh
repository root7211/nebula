#!/usr/bin/env bash
# Nebula Windows 快速构建和运行脚本

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_NAME="${1:-button_demo}"

echo "======================================"
echo "Nebula Windows Quick Build & Run"
echo "======================================"
echo ""
echo "Demo: $DEMO_NAME"
echo ""

# 检查依赖
if [ ! -f "$SCRIPT_DIR/vendor/wgpu-native/lib/wgpu_native.dll" ]; then
    echo "Error: wgpu-native not found. Please run tools/setup_wgpu.sh windows-x86_64"
    exit 1
fi

if [ ! -f "$SCRIPT_DIR/vendor/glfw/lib/glfw3.dll" ]; then
    echo "Error: GLFW not found. Please download and install to vendor/glfw/"
    exit 1
fi

# 构建
echo "Building..."
"$SCRIPT_DIR/build.sh" "$DEMO_NAME" --target=windows

# 检查构建结果
EXE_PATH="$HOME/.cache/nelua/${DEMO_NAME}.exe"
if [ ! -f "$EXE_PATH" ]; then
    echo "Error: Build failed, executable not found"
    exit 1
fi

echo ""
echo "✓ Build successful!"
echo "  Executable: $EXE_PATH"
echo "  Size: $(ls -lh "$EXE_PATH" | awk '{print $5}')"
echo ""

# 复制 DLL
echo "Copying runtime dependencies..."
cp "$SCRIPT_DIR/vendor/wgpu-native/lib/wgpu_native.dll" "$HOME/.cache/nelua/" 2>/dev/null || true
cp "$SCRIPT_DIR/vendor/glfw/lib/glfw3.dll" "$HOME/.cache/nelua/" 2>/dev/null || true

echo "✓ DLL files copied"
echo ""
echo "======================================"
echo "Ready to run!"
echo "======================================"
echo ""
echo "Run with:"
echo "  $EXE_PATH"
echo ""
echo "Note: GUI requires a local desktop environment."
echo "      SSH/remote sessions may not display graphics."
echo ""
