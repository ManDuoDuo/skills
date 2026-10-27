#!/usr/bin/env bash
# archive-progress.sh — 只归档 PROGRESS_LOG 标记区内的单行日志，保留滚动接续提示
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
FILE="$ROOT/进度记录.md"
MAX="${1:-50}"
[ $# -le 1 ] && case "$MAX" in *[!0-9]*|""|0) false ;; *) true ;; esac || { echo "用法: archive-progress.sh [正整数 MAX=50]" >&2; exit 2; }
[ -f "$FILE" ] || { echo "找不到 $FILE" >&2; exit 1; }
START='<!-- PROGRESS_LOG:START -->'
END='<!-- PROGRESS_LOG:END -->'
[ "$(grep -Fxc "$START" "$FILE")" = 1 ] && [ "$(grep -Fxc "$END" "$FILE")" = 1 ] || { echo "日志标记必须各出现一次" >&2; exit 1; }
START_LINE="$(grep -n -F -m1 "$START" "$FILE" | cut -d: -f1)"
END_LINE="$(grep -n -F -m1 "$END" "$FILE" | cut -d: -f1)"
[ "$START_LINE" -lt "$END_LINE" ] || { echo "日志标记顺序错误" >&2; exit 1; }
awk -v s="$START_LINE" -v e="$END_LINE" 'NR>s && NR<e && $0 !~ /^- / { exit 1 }' "$FILE" || { echo "标记区只允许单行 - 条目，拒绝截断多行内容" >&2; exit 1; }
awk -v e="$END_LINE" 'NR>e && $0 !~ /^[[:space:]]*$/ { exit 1 }' "$FILE" || { echo "结束标记后不得追加内容；新日志必须放在标记区内" >&2; exit 1; }
COUNT=$((END_LINE - START_LINE - 1))
if [ "$COUNT" -le "$MAX" ]; then
  echo "进度日志共 ${COUNT} 条，未超 ${MAX}，无需归档"
  exit 0
fi
CUT=$((COUNT - MAX))
DIR="$ROOT/docs/进度历史"
mkdir -p "$DIR"
ARC="$DIR/进度记录-归档-$(date +%Y%m%d-%H%M%S)-$$.md"
{
  printf '# 工程进度归档\n\n> 当前进度见 [进度记录.md](../../进度记录.md)。\n'
  sed -n "$((START_LINE + 1)),$((START_LINE + CUT))p" "$FILE"
} > "$ARC"
TMP="$(mktemp "$ROOT/.progress.XXXXXX")"
trap 'rm -f "$TMP"' EXIT
awk -v s="$START_LINE" -v e="$END_LINE" -v cut="$CUT" '
  NR<=s || NR>=e { print; next }
  { entry++; if (entry>cut) print }
' "$FILE" > "$TMP"
mv "$TMP" "$FILE"
echo "已归档最旧 $CUT 条 → $ARC"
echo "进度记录.md 现保留最新 $MAX 条"
