#!/usr/bin/env bash
# =============================================================================
# Nebula GUI Compiler — Build Script
#
# 当前仓库状态：Phase 4.2.2 — D-4.1-C Storage Buffer Scalability Benchmark
#
# Usage:
#   ./build.sh [demo_name] [options]
#
# Options:
#   --target=linux|windows|wasm    目标平台 (默认: linux)
#   --display=x11|wayland          Linux 显示协议 (默认: x11)
#
# Examples:
#   ./build.sh form_demo                          # Linux X11 (默认)
#   ./build.sh form_demo --target=linux --display=wayland
#   ./build.sh form_demo --target=windows
#   ./build.sh form_demo --target=wasm
# =============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENDOR="$SCRIPT_DIR/vendor/wgpu-native"

# 默认参数
DEMO_TARGET="button_demo"
NEBULA_TARGET="linux"
NEBULA_DISPLAY="x11"

# 解析参数
for arg in "$@"; do
  case "$arg" in
    --target=*)
      NEBULA_TARGET="${arg#*=}"
      ;;
    --display=*)
      NEBULA_DISPLAY="${arg#*=}"
      ;;
    -*)
      # 忽略其他选项
      ;;
    *)
      DEMO_TARGET="$arg"
      ;;
  esac
done

# 验证 Demo 目标
case "$DEMO_TARGET" in
  button_demo|layout_demo|login_demo|form_demo|dynamic_list_demo|shadow_demo|text_demo|slider_demo|scrollable_demo|dropdown_demo|multiline_editable_demo|slug_bench|cjk_text_demo|dense_text_demo|term_demo|cjk_editor_demo|dense_editor_demo|editor_with_lines_demo)
    ;;
  *)
    echo "[nebula] Error: unknown demo target '$DEMO_TARGET'"
    exit 1
    ;;
esac

echo "[nebula] Building $DEMO_TARGET for $NEBULA_TARGET ($NEBULA_DISPLAY)..."

# 根据目标平台配置编译选项
NELUA_FLAGS="-L $SCRIPT_DIR/src -L $SCRIPT_DIR/assets/generated"
NELUA_FLAGS="$NELUA_FLAGS -D NEBULA_TARGET=$NEBULA_TARGET"

if [ "$NEBULA_TARGET" == "linux" ]; then
  if [ ! -d "$VENDOR" ]; then
    echo "[nebula] Error: vendor/wgpu-native not found for linux build."
    exit 1
  fi
  NELUA_FLAGS="$NELUA_FLAGS -D NEBULA_LINUX_DISPLAY=$NEBULA_DISPLAY"
  CFLAGS="-I$VENDOR/include"
  LDFLAGS="-L$VENDOR/lib -lwgpu_native -lglfw -lm -ldl -Wl,-rpath,$VENDOR/lib"
  # term_demo 需要 libutil (forkpty) + examples/term 搜索路径
  if [ "$DEMO_TARGET" == "term_demo" ]; then
    LDFLAGS="$LDFLAGS -lutil"
    NELUA_FLAGS="$NELUA_FLAGS -L $SCRIPT_DIR/examples/term"
  fi
  
elif [ "$NEBULA_TARGET" == "windows" ]; then
  # Windows 编译配置 (假设在 Windows 环境或使用交叉编译)
  CFLAGS="-I$VENDOR/include"
  LDFLAGS="-L$VENDOR/lib -lwgpu_native -lglfw3 -luser32 -lgdi32 -lshell32"
  
elif [ "$NEBULA_TARGET" == "wasm" ]; then
  # Web (Wasm) 编译配置
  NELUA_FLAGS="$NELUA_FLAGS --cc emcc"
  LDFLAGS="-sUSE_WEBGPU=1 -sUSE_GLFW=3 -sALLOW_MEMORY_GROWTH=1"
  # Wasm 目标通常输出为 .html
  NELUA_FLAGS="$NELUA_FLAGS -o ~/.cache/nelua/$DEMO_TARGET.html"
fi

# 执行编译
nelua $NELUA_FLAGS --cflags="$CFLAGS" --ldflags="$LDFLAGS" "$SCRIPT_DIR/examples/$DEMO_TARGET.nelua"

echo "[nebula] Build complete."
if [ "$NEBULA_TARGET" == "wasm" ]; then
  echo "Output: ~/.cache/nelua/$DEMO_TARGET.html"
else
  echo "Output: ~/.cache/nelua/$DEMO_TARGET"
fi
