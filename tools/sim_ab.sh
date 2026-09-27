#!/usr/bin/env bash
# 平衡 A/B 对照：同一代码、多个随机种子，并行跑 A、B 两组，输出每组末行与均值。
# 用法：GODOT=/path/to/godot tools/sim_ab.sh "<A 组参数>" "<B 组参数>" [帧数，默认 30000] [种子，默认 "11 22 33"]
# 例：tools/sim_ab.sh "--no-station" "" 30000
set -uo pipefail
cd "$(dirname "$0")/.."
A_ARGS="${1:-}"
B_ARGS="${2:-}"
FRAMES="${3:-30000}"
SEEDS="${4:-11 22 33}"
OUT="$(mktemp -d)"
for s in $SEEDS; do
	# shellcheck disable=SC2086
	tools/sim.sh "$FRAMES" --seed="$s" $A_ARGS | grep '^\[sim\]' | tail -1 > "$OUT/A_$s" &
	# shellcheck disable=SC2086
	tools/sim.sh "$FRAMES" --seed="$s" $B_ARGS | grep '^\[sim\]' | tail -1 > "$OUT/B_$s" &
done
wait
python3 - "$OUT" $SEEDS <<'PY'
import re, sys, os
out, seeds = sys.argv[1], sys.argv[2:]
keys = ["money", "safety", "opinion", "total", "failed", "station", "event"]
avg = {}
for g in ("A", "B"):
	rows = []
	for s in seeds:
		line = open(os.path.join(out, f"{g}_{s}")).read().strip()
		print(f"{g} seed={s}: {line}")
		rows.append({k: float(m.group(1)) for k in keys for m in [re.search(rf"\b{k}=([-\d.]+)", line)] if m})
	avg[g] = {k: sum(r.get(k, 0.0) for r in rows) / max(len(rows), 1) for k in keys}
print()
print("| | " + " | ".join(keys) + " |")
print("|---|" + "---|" * len(keys))
for g in ("A", "B"):
	print(f"| {g} 均值 | " + " | ".join(f"{avg[g][k]:.1f}" for k in keys) + " |")
a, b = avg["A"], avg["B"]
print(f"\nB/A money = {b['money'] / max(a['money'], 1) * 100:.1f}%  safety {b['safety'] - a['safety']:+.1f}  opinion {b['opinion'] - a['opinion']:+.1f}")
PY
rm -rf "$OUT"
