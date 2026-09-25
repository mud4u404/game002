#!/usr/bin/env bash
# 导出网页版到 docs/（GitHub Pages 从 docs/ 目录发布）
# 用法：GODOT=/path/to/godot tools/export_web.sh
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
mkdir -p web
"$GODOT" --headless --export-release "Web" web/index.html
for f in web/index.*; do
	cp "$f" docs/
done
touch docs/.nojekyll
echo "网页版已导出到 docs/"
