#!/usr/bin/env bash
# 截图：需要 xvfb-run。用法：GODOT=... tools/shot.sh out.png [额外参数...]
# 常用参数：--skip-setup  --shot-hour=21  --layers=heat,reach  --test-busy  --test-suspect  --test-call
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
OUT="$1"; shift
timeout 300 xvfb-run -a -s "-screen 0 1920x1080x24" "$GODOT" --rendering-driver vulkan \
	res://scenes/game.tscn -- --shot="$(realpath -m "$OUT")" --shot-frames=110 "$@" 2>&1 | grep -E "SCRIPT ERROR" -A3
echo "saved $OUT"
