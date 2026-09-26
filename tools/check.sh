#!/usr/bin/env bash
# 语法检查：逐个编译 scripts/ 下所有 GDScript，只输出真正的错误。
# 用法：GODOT=/path/to/godot tools/check.sh
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --import >/dev/null 2>&1 || true
fail=0
for f in $(find scripts -name "*.gd" | sort); do
	out=$(timeout 60 "$GODOT" --headless --check-only --script "res://$f" 2>&1 \
		| grep -E "SCRIPT ERROR|Parse Error" \
		| grep -vE "Identifier not found: (GameState|Data|DevTools)|Failed to compile depended scripts" | head -5)
	if [ -n "$out" ]; then
		echo "== $f"; echo "$out"; fail=1
	fi
done
[ $fail -eq 0 ] && echo "check: OK" || { echo "check: FAILED"; exit 1; }
