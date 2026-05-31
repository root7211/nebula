#!/usr/bin/env bash
# =============================================================================
# Nebula Codegen Inspector — Phase 5.2 R3.3
#
# Dumps the compile-time generated Nelua source for a demo's sugar expansion,
# by triggering `print_source()` at the end of S1 (semantic analysis only —
# no GPU link required). Two uses:
#
#   1. Inspection: see exactly what `nebula_visual` / `nebula_app` / builtins
#      expand to (the sugar is otherwise a black box).
#   2. CI gate (--verify): confirm a demo's sugar expansion passes semantic
#      analysis AND populated a non-empty source cache. Catches sugar-layer
#      codegen regressions faster than a full compile+link.
#
# Usage:
#   tools/nebula_codegen.sh <demo> [--target=all|visual|app|builtin]
#                                  [--name=<entry>] [--output=FILE] [--verify]
#
#   <demo>    demo name (e.g. button_v2_demo) or path to a .nelua file
#   --target  which category to dump (default: all)
#   --name    dump only the entry with this name (e.g. ButtonApp)
#   --output  write extracted source to FILE instead of stdout
#   --verify  exit non-zero if analysis fails or no source was generated
#
# Examples:
#   tools/nebula_codegen.sh button_v2_demo
#   tools/nebula_codegen.sh text_editor_demo_v3 --target=app --output=/tmp/gen.nelua
#   tools/nebula_codegen.sh minimal_editor_demo --verify
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="$SCRIPT_DIR/vendor/wgpu-native"

DEMO=""
TARGET="all"
NAME=""
OUTPUT=""
VERIFY=0

for arg in "$@"; do
  case "$arg" in
    --target=*) TARGET="${arg#*=}" ;;
    --name=*)   NAME="${arg#*=}" ;;
    --output=*) OUTPUT="${arg#*=}" ;;
    --verify)   VERIFY=1 ;;
    -*)         echo "[codegen] unknown option: $arg" >&2; exit 2 ;;
    *)          DEMO="$arg" ;;
  esac
done

if [ -z "$DEMO" ]; then
  echo "[codegen] error: no demo specified" >&2
  echo "usage: tools/nebula_codegen.sh <demo> [--target=all|visual|app|builtin] [--name=<entry>] [--output=FILE] [--verify]" >&2
  exit 2
fi

# Resolve demo file: accept bare name or path.
if [ -f "$DEMO" ]; then
  DEMO_FILE="$(cd "$(dirname "$DEMO")" && pwd)/$(basename "$DEMO")"
elif [ -f "$SCRIPT_DIR/examples/$DEMO.nelua" ]; then
  DEMO_FILE="$SCRIPT_DIR/examples/$DEMO.nelua"
else
  echo "[codegen] error: demo not found: $DEMO" >&2
  exit 2
fi
DEMO_BASE="$(basename "$DEMO_FILE" .nelua)"

# Map --target to print_source mode argument.
case "$TARGET" in
  all|visual|app|builtin) MODE="$TARGET" ;;
  *) echo "[codegen] error: invalid --target '$TARGET' (all|visual|app|builtin)" >&2; exit 2 ;;
esac

# Build the print_source call (with optional name filter).
if [ -n "$NAME" ]; then
  PS_CALL="## print_source(\"$MODE\", \"$NAME\")"
else
  PS_CALL="## print_source(\"$MODE\")"
fi

# Per-demo extra search paths (mirror build.sh).
EXTRA_FLAGS=""
case "$DEMO_BASE" in
  json_viewer_demo|json_viewer_demo_v2)
    EXTRA_FLAGS="-L $SCRIPT_DIR/examples/json_viewer" ;;
  code_browser_demo)
    EXTRA_FLAGS="-L $SCRIPT_DIR/examples/code_browser" ;;
  term_demo|term_demo_v2)
    EXTRA_FLAGS="-L $SCRIPT_DIR/examples/term" ;;
esac

# Build a temp copy of the demo with print_source appended, so the dump runs
# after every sugar call in the demo has populated the cache. We never touch
# the original source.
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
TMP_DEMO="$TMP_DIR/${DEMO_BASE}_codegen.nelua"
cp "$DEMO_FILE" "$TMP_DEMO"
printf '\n%s\n' "$PS_CALL" >> "$TMP_DEMO"

# Run S1 semantic analysis only (no link). Capture combined stdout+stderr.
ANALYZE_LOG="$TMP_DIR/analyze.log"
set +e
nelua --analyze \
  -L "$SCRIPT_DIR/src" -L "$SCRIPT_DIR/assets/generated" \
  $EXTRA_FLAGS \
  -D NEBULA_TARGET=linux -D NEBULA_LINUX_DISPLAY=x11 \
  --cflags="-I$VENDOR/include" \
  "$TMP_DEMO" > "$ANALYZE_LOG" 2>&1
ANALYZE_RC=$?
set -e

# Extract the marked source blocks. The markers (nebula_sugar.nelua):
#   [nebula] ===== Generated source for <cat> "<key>" =====
#   <source>
#   [nebula] ============================================
EXTRACTED="$TMP_DIR/extracted.nelua"
awk '
  /^\[nebula\] ===== Generated source for / { insblk=1; print; next }
  /^\[nebula\] =============/ { if (insblk) { print; insblk=0 }; next }
  insblk { print }
' "$ANALYZE_LOG" > "$EXTRACTED"

BLOCK_COUNT=$(grep -c '^\[nebula\] ===== Generated source for ' "$EXTRACTED" || true)

if [ "$VERIFY" -eq 1 ]; then
  # Verify mode: analysis must pass AND at least one source block must exist.
  if [ "$ANALYZE_RC" -ne 0 ]; then
    echo "::error::[codegen] $DEMO_BASE — semantic analysis FAILED (sugar expansion produced invalid code)"
    echo "--- analyzer output (tail) ---" >&2
    tail -20 "$ANALYZE_LOG" >&2
    exit 1
  fi
  if [ "$BLOCK_COUNT" -eq 0 ]; then
    echo "::error::[codegen] $DEMO_BASE — no generated source found (cache empty; sugar may not have run)"
    exit 1
  fi
  echo "[codegen] $DEMO_BASE — OK ($BLOCK_COUNT generated source block(s), analysis clean)"
  exit 0
fi

# Dump mode: emit extracted source.
if [ "$ANALYZE_RC" -ne 0 ]; then
  echo "[codegen] warning: analysis exited $ANALYZE_RC — output may be incomplete" >&2
fi
if [ "$BLOCK_COUNT" -eq 0 ]; then
  echo "[codegen] warning: no generated source found for $DEMO_BASE (target=$TARGET${NAME:+ name=$NAME})" >&2
fi

if [ -n "$OUTPUT" ]; then
  cp "$EXTRACTED" "$OUTPUT"
  echo "[codegen] wrote $BLOCK_COUNT block(s) to $OUTPUT"
else
  cat "$EXTRACTED"
fi
