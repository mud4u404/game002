#!/usr/bin/env bash
# 无界面平衡模拟：机器人玩家组建编组并派所有警情，4 倍速跑约一个游戏日。
# 用法：GODOT=/path/to/godot tools/sim.sh [帧数，默认 12000] [其他参数，如 --seed=11 --no-station]
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
FRAMES="${1:-12000}"
shift || true
timeout 900 "$GODOT" --headless --fixed-fps 30 res://scenes/game.tscn -- \
	--speed=4 --quit-frames="$FRAMES" --print-every=2000 --bot "$@" 2>&1 \
	| grep -E "^\[sim\]|SCRIPT ERROR|ERROR: .*\.gd"
