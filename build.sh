#!/usr/bin/env bash
# =============================================================================
# Nebula GUI Compiler — Build Script
#
# 当前仓库状态：Phase 5.4 — 声明式动画系统完成 | 149/149 断言全绿
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
  button_demo|layout_demo|login_demo|login_v2_demo|form_demo|dynamic_list_demo|dynamic_list_v2_demo|shadow_demo|text_demo|slider_demo|scrollable_demo|dropdown_demo|multiline_editable_demo|slug_bench|cjk_text_demo|dense_text_demo|term_demo|term_demo_v2|cjk_editor_demo|dense_editor_demo|editor_with_lines_demo|button_sugar_demo|multiline_sugar_demo|json_viewer_demo|json_viewer_demo_v2|highlight_editor_demo|highlight_sugar_demo|text_editor_demo|button_v2_demo|minimal_editor_demo|text_editor_demo_v2|text_editor_demo_v3|text_editor_demo_v4|counter_demo|counter_binding_demo|code_browser_demo|gradient_demo)
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
  # term_demo / term_demo_v2 需要 libutil (forkpty) + examples/term 搜索路径
  if [ "$DEMO_TARGET" == "term_demo" ] || [ "$DEMO_TARGET" == "term_demo_v2" ]; then
    LDFLAGS="$LDFLAGS -lutil"
    NELUA_FLAGS="$NELUA_FLAGS -L $SCRIPT_DIR/examples/term"
  fi
  if [ "$DEMO_TARGET" == "json_viewer_demo" ] || [ "$DEMO_TARGET" == "json_viewer_demo_v2" ]; then
    NELUA_FLAGS="$NELUA_FLAGS -L $SCRIPT_DIR/examples/json_viewer"
  fi
  if [ "$DEMO_TARGET" == "code_browser_demo" ]; then
    NELUA_FLAGS="$NELUA_FLAGS -L $SCRIPT_DIR/examples/code_browser"
    CFLAGS="$CFLAGS -I$SCRIPT_DIR/examples/code_browser"
  fi
  
elif [ "$NEBULA_TARGET" == "windows" ]; then
  # Windows 编译配置 (MinGW)
  # 转换 MSYS 路径为 Windows 路径
  VENDOR_WIN=$(cygpath -w "$SCRIPT_DIR/vendor/wgpu-native" 2>/dev/null || echo "$SCRIPT_DIR/vendor/wgpu-native" | sed 's|^/c/|C:/|')
  GLFW_DIR_WIN=$(cygpath -w "$SCRIPT_DIR/vendor/glfw" 2>/dev/null || echo "$SCRIPT_DIR/vendor/glfw" | sed 's|^/c/|C:/|')
  if [ ! -d "$SCRIPT_DIR/vendor/wgpu-native" ]; then
    echo "[nebula] Error: vendor/wgpu-native not found for windows build."
    exit 1
  fi
  if [ ! -d "$SCRIPT_DIR/vendor/glfw" ]; then
    echo "[nebula] Error: vendor/glfw not found for windows build."
    exit 1
  fi
  CFLAGS="-I$VENDOR_WIN/include -I$GLFW_DIR_WIN/include"
  LDFLAGS="-L$VENDOR_WIN/lib -L$GLFW_DIR_WIN/lib -lwgpu_native -lglfw3 -lopengl32 -lgdi32 -luser32 -lshell32 -ladvapi32 -lws2_32 -luserenv -lbcrypt -lntdll -Wl,--stack,8388608"
  # term_demo 在 Windows 上不支持 (需要 POSIX PTY)
  if [ "$DEMO_TARGET" == "term_demo" ] || [ "$DEMO_TARGET" == "term_demo_v2" ]; then
    echo "[nebula] Warning: term_demo requires POSIX PTY, not supported on Windows"
    exit 1
  fi
  if [ "$DEMO_TARGET" == "json_viewer_demo" ] || [ "$DEMO_TARGET" == "json_viewer_demo_v2" ]; then
    NELUA_FLAGS="$NELUA_FLAGS -L $SCRIPT_DIR/examples/json_viewer"
  fi
  if [ "$DEMO_TARGET" == "code_browser_demo" ]; then
    NELUA_FLAGS="$NELUA_FLAGS -L $SCRIPT_DIR/examples/code_browser"
    CODE_BROWSER_WIN=$(cygpath -w "$SCRIPT_DIR/examples/code_browser" 2>/dev/null || echo "$SCRIPT_DIR/examples/code_browser" | sed 's|^/c/|C:/|')
    CFLAGS="$CFLAGS -I$CODE_BROWSER_WIN"
  fi
  
elif [ "$NEBULA_TARGET" == "wasm" ]; then
  # Web (Wasm) 编译配置 — 推荐使用 build_wasm.sh 获得完整体验
  NELUA_FLAGS="$NELUA_FLAGS --cc emcc"
  CFLAGS=""
  LDFLAGS="-sUSE_WEBGPU=1 -sUSE_GLFW=3 -sALLOW_MEMORY_GROWTH=1 -sSTACK_SIZE=1048576 -sEXIT_RUNTIME=0"
  LDFLAGS="$LDFLAGS --preload-file $SCRIPT_DIR/assets/generated@/assets/generated"
  LDFLAGS="$LDFLAGS --shell-file $SCRIPT_DIR/web/shell.html"
  LDFLAGS="$LDFLAGS -O2"
  # 输出到 build/wasm/
  mkdir -p "$SCRIPT_DIR/build/wasm"
  NELUA_FLAGS="$NELUA_FLAGS -o $SCRIPT_DIR/build/wasm/$DEMO_TARGET.html"
fi

# 执行编译
nelua $NELUA_FLAGS --cflags="$CFLAGS" --ldflags="$LDFLAGS" "$SCRIPT_DIR/examples/$DEMO_TARGET.nelua"

echo "[nebula] Build complete."
if [ "$NEBULA_TARGET" == "wasm" ]; then
  echo "Output: $SCRIPT_DIR/build/wasm/$DEMO_TARGET.html"
else
  echo "Output: ~/.cache/nelua/$DEMO_TARGET"
fi
