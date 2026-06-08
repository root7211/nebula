#!/usr/bin/env bash
# =============================================================================
# Nebula GUI - Windows Demo 运行脚本
#
# Usage:
#   ./run_demo.sh [demo_name]
#
# Examples:
#   ./run_demo.sh button_demo
#   ./run_demo.sh text_demo
#   ./run_demo.sh                    # 列出所有可用 demo
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="$HOME/.cache/nelua"

# 可用的 demo 列表
DEMOS=(
  "button_demo"
  "button_v2_demo"
  "counter_demo"
  "login_demo"
  "layout_demo"
  "text_demo"
  "minimal_editor_demo"
  "json_viewer_demo"
  "highlight_editor_demo"
  "text_editor_demo_v2"
)

# 需要从项目根目录运行的 demo（需要访问 assets/）
NEEDS_ASSETS=(
  "text_demo"
  "minimal_editor_demo"
)

# 如果没有参数，列出所有 demo
if [ $# -eq 0 ]; then
  echo "可用的 Demo 程序："
  echo ""
  for demo in "${DEMOS[@]}"; do
    if [ -f "$CACHE_DIR/${demo}.exe" ]; then
      echo "  ✅ $demo"
    else
      echo "  ❌ $demo (未编译)"
    fi
  done
  echo ""
  echo "使用方法: ./run_demo.sh <demo_name>"
  echo "示例: ./run_demo.sh button_demo"
  exit 0
fi

DEMO_NAME="$1"

# 验证 demo 是否存在
if [ ! -f "$CACHE_DIR/${DEMO_NAME}.exe" ]; then
  echo "错误: ${DEMO_NAME}.exe 不存在"
  echo "请先运行: ./build.sh $DEMO_NAME --target=windows"
  exit 1
fi

# 检查是否需要从项目根目录运行
NEEDS_ROOT=false
for needs_asset_demo in "${NEEDS_ASSETS[@]}"; do
  if [ "$DEMO_NAME" == "$needs_asset_demo" ]; then
    NEEDS_ROOT=true
    break
  fi
done

echo "=== 运行 $DEMO_NAME ==="
echo ""

if [ "$NEEDS_ROOT" = true ]; then
  echo "注意: 此 demo 需要访问 assets/ 目录，从项目根目录运行"
  cd "$SCRIPT_DIR"
  exec "$CACHE_DIR/${DEMO_NAME}.exe"
else
  cd "$CACHE_DIR"
  exec "./${DEMO_NAME}.exe"
fi
