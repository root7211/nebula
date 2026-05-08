#!/usr/bin/env bash
# =============================================================================
# Nebula GUI Compiler — WASM Build Script
#
# 编译指定 demo 为 WebAssembly，输出完整的 .html + .js + .wasm + .data
# 可直接在支持 WebGPU 的浏览器中运行。
#
# Usage:
#   ./build_wasm.sh [demo_name]    # 默认: button_v2_demo
#   ./build_wasm.sh button_demo
#   ./build_wasm.sh text_editor_demo_v3
#
# 前置条件:
#   - Emscripten SDK (emcc) 已安装并在 PATH 中
#   - Nelua 已安装
#
# 输出:
#   build/wasm/<demo_name>.html   — 主入口（可直接用 HTTP server 服务）
#   build/wasm/<demo_name>.js     — Emscripten JS 胶水
#   build/wasm/<demo_name>.wasm   — WebAssembly 二进制
#   build/wasm/<demo_name>.data   — 预加载资产包
# =============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_TARGET="${1:-button_v2_demo}"
BUILD_DIR="$SCRIPT_DIR/build/wasm"

# 验证工具链
if ! command -v emcc &>/dev/null; then
  echo "[error] emcc not found. Please install Emscripten SDK:"
  echo "        https://emscripten.org/docs/getting_started/downloads.html"
  exit 1
fi

if ! command -v nelua &>/dev/null; then
  echo "[error] nelua not found. Please install Nelua:"
  echo "        https://nelua.io/installing/"
  exit 1
fi

echo "[nebula-wasm] Building $DEMO_TARGET..."
echo "[nebula-wasm] Emscripten: $(emcc --version | head -1)"

# 创建输出目录
mkdir -p "$BUILD_DIR"

# Nelua 编译参数
NELUA_FLAGS="-L $SCRIPT_DIR/src -L $SCRIPT_DIR/assets/generated"
NELUA_FLAGS="$NELUA_FLAGS --add-path $SCRIPT_DIR --add-path $SCRIPT_DIR/examples --add-path $SCRIPT_DIR/assets/generated"
NELUA_FLAGS="$NELUA_FLAGS -D NEBULA_TARGET=wasm"
NELUA_FLAGS="$NELUA_FLAGS --cc emcc"

# 额外搜索路径
EXTRA_FLAGS=""
if [ "$DEMO_TARGET" = "json_viewer_demo" ] || [ "$DEMO_TARGET" = "json_viewer_demo_v2" ]; then
  EXTRA_FLAGS="-L $SCRIPT_DIR/examples/json_viewer"
fi
if [ "$DEMO_TARGET" = "term_demo" ] || [ "$DEMO_TARGET" = "term_demo_v2" ]; then
  echo "[error] Terminal demos require PTY, not supported on WASM target."
  exit 1
fi

# Emscripten 编译/链接选项
# -sUSE_WEBGPU=1         — 启用 WebGPU JS bindings（替代 wgpu-native）
# -sUSE_GLFW=3           — 使用 Emscripten 内置 GLFW3 实现
# -sALLOW_MEMORY_GROWTH=1 — 允许 WASM 线性内存动态增长
# -sASSERTIONS=1         — 开发时保留断言（发布时改为 0）
# -sSTACK_SIZE=1048576   — 1MB 栈（足够 Nebula 的栈分配 arena）
# --preload-file          — 打包 assets 到 .data 文件（模拟 fopen/fread）
# --shell-file            — 自定义 HTML 模板
EMCC_FLAGS=""
EMCC_FLAGS="$EMCC_FLAGS -sUSE_WEBGPU=1"
EMCC_FLAGS="$EMCC_FLAGS -sUSE_GLFW=3"
EMCC_FLAGS="$EMCC_FLAGS -sALLOW_MEMORY_GROWTH=1"
EMCC_FLAGS="$EMCC_FLAGS -sASSERTIONS=1"
EMCC_FLAGS="$EMCC_FLAGS -sSTACK_SIZE=4194304"
EMCC_FLAGS="$EMCC_FLAGS -sASYNCIFY"
EMCC_FLAGS="$EMCC_FLAGS -sASYNCIFY_STACK_SIZE=65536"
EMCC_FLAGS="$EMCC_FLAGS -sEXIT_RUNTIME=0"
EMCC_FLAGS="$EMCC_FLAGS -sINVOKE_RUN=1"
EMCC_FLAGS="$EMCC_FLAGS --preload-file $SCRIPT_DIR/assets/generated@/assets/generated"
EMCC_FLAGS="$EMCC_FLAGS --shell-file $SCRIPT_DIR/web/shell.html"
EMCC_FLAGS="$EMCC_FLAGS -O2"

# 输出路径
OUTPUT="$BUILD_DIR/${DEMO_TARGET}.html"

echo "[nebula-wasm] Compiling with Nelua + Emscripten..."
nelua $NELUA_FLAGS $EXTRA_FLAGS \
  --cflags="" \
  --ldflags="$EMCC_FLAGS" \
  -o "$OUTPUT" \
  "$SCRIPT_DIR/examples/${DEMO_TARGET}.nelua"

echo ""
echo "[nebula-wasm] Build complete!"
echo "  Output:  $BUILD_DIR/"
ls -lh "$BUILD_DIR/${DEMO_TARGET}"* 2>/dev/null || true
echo ""
echo "[nebula-wasm] To run locally:"
echo "  cd $BUILD_DIR && python3 -m http.server 8000"
echo "  Open: http://localhost:8000/${DEMO_TARGET}.html"
echo ""
echo "[nebula-wasm] Note: Requires a browser with WebGPU support (Chrome 113+)"
