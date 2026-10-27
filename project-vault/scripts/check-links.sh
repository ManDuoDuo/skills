#!/usr/bin/env bash
# check-links.sh — 校验 Markdown 内联相对链接；剥离代码示例并剪枝嵌套仓库
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$ROOT"
TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT

strip_code() { sed -e '/^[[:space:]]*```/,/^[[:space:]]*```/d' -e '/^[[:space:]]*~~~/,/^[[:space:]]*~~~/d' -e 's/`[^`]*`//g' "$1"; }
find . -mindepth 1 -type d -name .git -prune -o \
     -type d -exec test -d '{}/.git' \; -prune -o \
     -type d -name node_modules -prune -o \
     -type d -name 本地信息 -prune -o \
     -name '*.md' -print > "$TMPD/mdfiles"

: > "$TMPD/errors"
: > "$TMPD/wiki"
while IFS= read -r f; do
  strip_code "$f" | grep -q '\[\[' && printf '%s\n' "$f" >> "$TMPD/wiki"
  strip_code "$f" | awk '
    function emit_link(text,   i,c,depth,start) {
      for (i=1; i<=length(text)-1; i++) {
        if (substr(text,i,2) != "](") continue
        start=i+2; depth=1
        for (i=start; i<=length(text); i++) {
          c=substr(text,i,1)
          if (c=="\\") { i++; continue }
          if (c=="(") depth++
          else if (c==")") { depth--; if (depth==0) break }
        }
        if (depth==0) print substr(text,start,i-start)
      }
    }
    { emit_link($0) }
  ' | while IFS= read -r raw; do
    case "$raw" in
      '<'*) target="$(printf '%s\n' "$raw" | sed -nE 's/^<([^>]*)>.*/\1/p')" ;;
      *) target="$raw" ;;
    esac
    target="$(printf '%s\n' "$target" | sed -E 's/[[:space:]]+"[^"]*"[[:space:]]*$//; s/\\([() ])/\\1/g')"
    case "$target" in
      /*|~/*|[A-Za-z]:[\\/]*)
        printf '%s -> 禁止使用绝对路径：%s\n' "$f" "$target" >> "$TMPD/errors"
        continue ;;
    esac
    if printf '%s\n' "$target" | grep -qE '^[A-Za-z][A-Za-z0-9+.-]*:'; then continue; fi
    target="${target%%#*}"
    [ -n "$target" ] || continue
    decoded="$(printf '%s\n' "$target" | sed -e 's/%20/ /g' -e 's/%23/#/g' -e 's/%25/%/g' -e 's/%28/(/g' -e 's/%29/)/g' -e 's/%2F/\//g' -e 's/%2f/\//g')"
    [ -e "$(dirname "$f")/$decoded" ] || printf '%s -> %s\n' "$f" "$raw" >> "$TMPD/errors"
  done
done < "$TMPD/mdfiles"

if [ -s "$TMPD/wiki" ]; then
  echo "⚠️ 发现 wikilink 语法（应改为标准相对链接）："
  sort -u "$TMPD/wiki"
fi
if [ -s "$TMPD/errors" ]; then
  echo "❌ 发现断链或违规链接："
  sort -u "$TMPD/errors"
  exit 1
fi
echo "✅ 无断链"
