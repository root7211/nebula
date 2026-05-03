#!/usr/bin/env bash
# =============================================================================
# setup_wgpu.sh — 下载 wgpu-native v29.0.0.0 到 vendor/wgpu-native
#
# Usage:
#   bash setup_wgpu.sh              # 自动检测平台
#   bash setup_wgpu.sh linux-x86_64 # 手动指定
#
# 支持平台: linux-x86_64, linux-aarch64, macos-x86_64, macos-aarch64, windows-x86_64
# =============================================================================
set -e

VERSION="v29.0.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
VENDOR_DIR="$PROJECT_DIR/vendor/wgpu-native"

# 自动检测平台
detect_platform() {
  local os arch
  case "$(uname -s)" in
    Linux*)  os="linux" ;;
    Darwin*) os="macos" ;;
    MINGW*|MSYS*|CYGWIN*) os="windows" ;;
    *) echo "[error] Unsupported OS: $(uname -s)"; exit 1 ;;
  esac
  case "$(uname -m)" in
    x86_64|amd64)  arch="x86_64" ;;
    aarch64|arm64) arch="aarch64" ;;
    *) echo "[error] Unsupported arch: $(uname -m)"; exit 1 ;;
  esac
  echo "${os}-${arch}"
}

PLATFORM="${1:-$(detect_platform)}"
FILENAME="wgpu-${PLATFORM}-release.zip"
URL="https://github.com/gfx-rs/wgpu-native/releases/download/${VERSION}/${FILENAME}"

echo "[wgpu] Target: ${PLATFORM}"
echo "[wgpu] Version: ${VERSION}"
echo "[wgpu] URL: ${URL}"

# 清理旧的 vendor/wgpu-native（可能是符号链接或旧版本）
if [ -L "$VENDOR_DIR" ]; then
  echo "[wgpu] Removing old symlink: $VENDOR_DIR"
  rm "$VENDOR_DIR"
elif [ -d "$VENDOR_DIR" ]; then
  # 检查是否已经是正确版本
  if [ -f "$VENDOR_DIR/wgpu-native-meta/wgpu-native-git-tag" ]; then
    EXISTING=$(cat "$VENDOR_DIR/wgpu-native-meta/wgpu-native-git-tag" 2>/dev/null || echo "unknown")
    if [ "$EXISTING" = "$VERSION" ]; then
      echo "[wgpu] Already at ${VERSION} — skip download"
      exit 0
    fi
    echo "[wgpu] Existing version: ${EXISTING} → upgrading to ${VERSION}"
  fi
  rm -rf "$VENDOR_DIR"
fi

# 下载
TMPFILE="$(mktemp /tmp/wgpu-native-XXXXXX.zip)"
echo "[wgpu] Downloading..."
curl -L -o "$TMPFILE" "$URL"

# 解压
mkdir -p "$VENDOR_DIR"
unzip -o "$TMPFILE" -d "$VENDOR_DIR"
rm "$TMPFILE"

# 验证
if [ ! -f "$VENDOR_DIR/include/webgpu/webgpu.h" ]; then
  echo "[error] webgpu.h not found after extraction"
  exit 1
fi

INSTALLED=$(cat "$VENDOR_DIR/wgpu-native-meta/wgpu-native-git-tag" 2>/dev/null || echo "unknown")
echo "[wgpu] Installed: ${INSTALLED}"
echo "[wgpu] Location: ${VENDOR_DIR}"

# 运行结构体尺寸验证
echo ""
echo "[wgpu] Verifying struct sizes..."
VERIFY_SRC="$VENDOR_DIR/_verify_sizes.c"
cat > "$VERIFY_SRC" << 'CEOF'
#include <stdio.h>
#include <stddef.h>
#include "webgpu/webgpu.h"
int main() {
    int ok = 1;
    #define CHECK(type, expect) do { \
        if (sizeof(type) != expect) { \
            printf("  [FAIL] sizeof(%s) = %zu, expected %zu\n", #type, sizeof(type), (size_t)expect); \
            ok = 0; \
        } else { \
            printf("  [OK]   sizeof(%s) = %zu\n", #type, sizeof(type)); \
        } \
    } while(0)
    CHECK(WGPUBindGroupLayoutEntry, 120);
    CHECK(WGPUBindGroupEntry, 56);
    CHECK(WGPUBufferDescriptor, 48);
    CHECK(WGPURenderPassColorAttachment, 72);
    CHECK(WGPUSurfaceConfiguration, 64);
    CHECK(WGPURenderPipelineDescriptor, 168);
    CHECK(WGPUTextureDescriptor, 80);
    CHECK(WGPUVertexAttribute, 32);
    CHECK(WGPUVertexBufferLayout, 40);
    CHECK(WGPUSamplerDescriptor, 64);
    if (ok) printf("\n  All struct sizes match wgpu-native %s — bindings OK\n", "v29.0.0.0");
    else    printf("\n  [ERROR] Size mismatch detected — bindings need update!\n");
    return ok ? 0 : 1;
}
CEOF

if gcc -I"$VENDOR_DIR/include" "$VERIFY_SRC" -o "$VENDOR_DIR/_verify_sizes" 2>/dev/null; then
  "$VENDOR_DIR/_verify_sizes"
  rm -f "$VENDOR_DIR/_verify_sizes" "$VERIFY_SRC"
else
  echo "  [skip] gcc not available, cannot verify (sizes should be correct for ${VERSION})"
  rm -f "$VERIFY_SRC"
fi

echo ""
echo "[wgpu] Done. You can now build:"
echo "  ./build.sh button_demo"
