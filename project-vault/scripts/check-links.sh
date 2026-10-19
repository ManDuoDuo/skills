#!/usr/bin/env bash
# check-links.sh — 扫描库内所有 .md 的相对链接，报告断链
# 用法: check-links.sh   （在库内任意目录运行均可，自动定位库根）
# 扫描前会剥掉行内代码（`...`）与围栏代码块，避免文档里的"链接写法示例"被误报。
# 已知边界：链接中的 URL 编码空格（%20）不做解码；锚点（#xxx）只检查文件存在不检查标题。
# 等价手工步骤见 SKILL.md §5.2。
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

# 剥掉行内代码与围栏代码块，输出"可扫描文本"
strip_code() {
  sed -e '/^```/,/^```/d' -e 's/`[^`]*`//g' "$1"
}

MD_FILES=$(mktemp)
trap 'rm -f "$TMP" "$MD_FILES"' EXIT
# 剪掉 .git 目录本身，以及任何含嵌套 .git 的子目录（代码子仓库，见 SKILL.md §2.4）：
# find 不读 .gitignore，代码库自己的文档用什么链接语法是它的自由，不该混进知识库的校验结果。
# mindepth 1 避免把库根本身（也含 .git）剪掉。
find . -mindepth 1 -type d -name .git -prune -o \
     -type d -exec test -d '{}/.git' \; -prune -o \
     -type d -name node_modules -prune -o \
     -name '*.md' -print > "$MD_FILES"

# 1) 警告 wikilink 私有语法（本库约定用标准相对链接）
WIKI=""
while IFS= read -r f; do
  strip_code "$f" | grep -q '\[\[' && WIKI="$WIKI$f\n"
done < "$MD_FILES"
[ -n "$WIKI" ] && printf "⚠️ 发现 wikilink 语法（应改为标准相对链接）:\n$WIKI\n"

# 2) 逐个检查相对链接目标
while IFS= read -r f; do
  strip_code "$f" | grep -oE '\]\(([^)]+)\)' | sed -E 's/^\]\(//; s/\)$//' | while IFS= read -r link; do
    target="${link%%#*}"                       # 去锚点
    case "$target" in
      http*|https*|mailto:*|tel:*|/*|'<'*) continue ;;  # 外链、协议、绝对路径跳过
    esac
    [ -z "$target" ] && continue
    [ -e "$(dirname "$f")/$target" ] || echo "$f -> $link" >> "$TMP"
  done
done < "$MD_FILES"

if [ -s "$TMP" ]; then
  echo "❌ 发现断链："
  sort -u "$TMP"
  exit 1
else
  echo "✅ 无断链"
fi
