#!/usr/bin/env bash
# Windows 构建测试脚本
set -e

echo "======================================"
echo "Nebula Windows Build Test"
echo "======================================"
echo ""

# 测试的 demo 列表（排除需要 POSIX 的）
DEMOS=(
    "button_demo"
    "button_v2_demo"
    "login_demo"
    "layout_demo"
    "text_demo"
    "minimal_editor_demo"
)

SUCCESS_COUNT=0
FAIL_COUNT=0
TOTAL=${#DEMOS[@]}

for demo in "${DEMOS[@]}"; do
    echo "----------------------------------------"
    echo "Building: $demo"
    echo "----------------------------------------"
    
    # 清除旧的缓存
    rm -f ~/.cache/nelua/${demo}.c ~/.cache/nelua/${demo}.exe
    
    # 尝试构建
    if ./build.sh "$demo" --target=windows > /tmp/build_${demo}.log 2>&1; then
        # 检查是否生成了可执行文件
        if [ -f ~/.cache/nelua/${demo}.exe ]; then
            SIZE=$(ls -lh ~/.cache/nelua/${demo}.exe | awk '{print $5}')
            echo "✓ SUCCESS - Generated ${demo}.exe ($SIZE)"
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        else
            echo "✗ FAIL - No executable generated"
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
    else
        echo "✗ FAIL - Build error"
        tail -20 /tmp/build_${demo}.log
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
    echo ""
done

echo "======================================"
echo "Test Results"
echo "======================================"
echo "Total:   $TOTAL"
echo "Success: $SUCCESS_COUNT"
echo "Failed:  $FAIL_COUNT"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
    echo "✓ All tests passed!"
    echo ""
    echo "To run the demos, copy DLL files:"
    echo "  cp ~/nebula/vendor/wgpu-native/lib/wgpu_native.dll ~/.cache/nelua/"
    echo "  cp ~/nebula/vendor/glfw/lib/glfw3.dll ~/.cache/nelua/"
    echo ""
    echo "Then run: ~/.cache/nelua/<demo_name>.exe"
    exit 0
else
    echo "✗ Some tests failed"
    exit 1
fi
