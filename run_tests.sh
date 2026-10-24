#!/usr/bin/env bash
# 无头跑测试。用法： bash run_tests.sh [--import]
#
# 加了 --import 会先让 Godot 重新扫描资源与全局类名。
# 只要新增/改名了带 class_name 的脚本，或新增了美术资源，就必须带上 --import，
# 否则全局类名缓存是旧的，会报 "Identifier ... not declared in the current scope"。

set -u
GODOT="${GODOT:-/d/Godet/Godot_v4.7.2-stable_win64_console.exe}"
PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${TMPDIR:-/tmp}/elementrift_test_out.txt"

if [ "${1:-}" = "--import" ]; then
	echo "### 重新扫描资源与全局类名 ###"
	"$GODOT" --headless --path "$PROJ" --import 2>&1 \
		| grep -iE "^(ERROR|SCRIPT ERROR)" | grep -v "scenes/main.tscn" | head -20
fi

"$GODOT" --headless --audio-driver Dummy --path "$PROJ" \
	--quit-after 400 res://tests/test_runner.tscn > "$OUT" 2>&1
code=$?

grep -E "^(ALL PASS|FAILED)" "$OUT" || echo "(没有结果汇总行 —— 可能是解析错误或挂死，见下方)"

# 断言失败
fails=$(grep -cE "^  FAIL" "$OUT" || true)
# 脚本错误：GDScript 的运行时错误会中断当前函数、但外层用例可能仍然跑到 finish()，
# 于是汇总行会报 ALL PASS。所以必须把 SCRIPT ERROR 单独当成失败，否则会假绿。
# 「resources still in use at exit」是 preload 的场景在进程退出时仍被持有导致的正常提示，不算失败
errs=$(grep -E "^SCRIPT ERROR|Parse Error|^ERROR:" "$OUT" \
	| grep -vc "resources still in use at exit" || true)

if [ "$fails" -gt 0 ]; then
	echo "--- 断言失败 ($fails) ---"
	grep -E "^  FAIL" "$OUT" | head -25
fi
if [ "$errs" -gt 0 ]; then
	echo "--- 脚本错误 ($errs) ---"
	grep -E "^SCRIPT ERROR|Parse Error|^ERROR:" "$OUT" | sort -u | head -25
fi

if [ "$fails" -gt 0 ] || [ "$errs" -gt 0 ]; then
	echo "(完整输出: $OUT)"
	exit 1
fi
echo "(完整输出: $OUT)"
exit $code
