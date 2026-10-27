#!/usr/bin/env bash
# archive-changelog.sh — CHANGELOG.md 超过 MAX 条时，把最旧部分归档到 99_附件/历史/
# 用法: archive-changelog.sh [MAX=50]
# CHANGELOG.md 格式约定（模板保证）：第 1 行标题、第 2 行说明，第 3 行起每行一条日志。
# 等价手工步骤见 SKILL.md §5.4。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
FILE="$ROOT/CHANGELOG.md"
DIR="$ROOT/99_附件/历史"
MAX="${1:-50}"
[ $# -le 1 ] && case "$MAX" in *[!0-9]*|""|0) false ;; *) true ;; esac || { echo "用法: archive-changelog.sh [正整数 MAX=50]" >&2; exit 2; }

[ -f "$FILE" ] || { echo "找不到 $FILE" >&2; exit 1; }

# 版本兼容：v1.0 时代的模板以空行分隔固定头与条目（v1.1 起删除，见 SKILL.md 变更记录）。
# 旧库拿新脚本跑会 off-by-one（空行被当一条日志归走）。检测到即自动规范化并警告。
if [ "$(sed -n '3p' "$FILE")" = "" ] && [ "$(wc -l < "$FILE" | tr -d ' ')" -ge 4 ]; then
  echo "⚠️ 检测到 v1.0 旧格式（第 3 行空行），已自动规范化（删除该空行）。建议检查本库 AGENTS.md 的版本戳，其他格式约定可能同样过时"
  sed -i.bak '3d' "$FILE" && rm -f "$FILE.bak"
fi

total=$(wc -l < "$FILE" | tr -d ' ')
entries=$((total - 2))
if [ "$entries" -le "$MAX" ]; then
  echo "CHANGELOG.md 共 ${entries} 条，未超 ${MAX}，无需归档"
  exit 0
fi

cut=$((entries - MAX))
mkdir -p "$DIR"
ARC="$DIR/CHANGELOG-归档-$(date +%Y%m%d-%H%M%S).md"

# 归档文件 = 固定头 + 最旧 cut 条
head -n 2 "$FILE" > "$ARC"
sed -n "3,$((2 + cut))p" "$FILE" >> "$ARC"

# CHANGELOG = 固定头 + 最新 MAX 条
{
  head -n 2 "$FILE"
  sed -n "$((3 + cut)),\$p" "$FILE"
} > "$FILE.new"
mv "$FILE.new" "$FILE"

echo "已归档最旧 $cut 条 → $ARC"
echo "CHANGELOG.md 现保留最新 $MAX 条"
