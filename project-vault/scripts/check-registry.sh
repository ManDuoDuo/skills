#!/usr/bin/env bash
# check-registry.sh — 上界漂移/悬空引用为错误，归口外无引用为警告
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$ROOT"
REG="REGISTRY.md"
[ -f "$REG" ] || { echo "找不到 $REG" >&2; exit 1; }
TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT

find . -mindepth 1 -type d -name .git -prune -o \
     -type d -exec test -d '{}/.git' \; -prune -o \
     -type d -name node_modules -prune -o \
     -type d -name 本地信息 -prune -o \
     -name '*.md' -print > "$TMPD/mdfiles"
strip_code() { sed -e '/^[[:space:]]*```/,/^[[:space:]]*```/d' -e '/^[[:space:]]*~~~/,/^[[:space:]]*~~~/d' -e 's/`[^`]*`//g' "$1"; }
extract_ids() {
  LC_ALL=C awk -v prefix="$1" '
    { text=$0; pos=1
      while (pos <= length(text)) {
        found=index(substr(text,pos), prefix)
        if (!found) break
        start=pos+found-1
        before=(start>1 ? substr(text,start-1,1) : "")
        if (before != "" && before ~ /[A-Za-z0-9]/) { pos=start+length(prefix); continue }
        cursor=start+length(prefix)
        while (substr(text,cursor,1) ~ /[0-9]/) cursor++
        if (cursor == start+length(prefix)) { pos=start+length(prefix); continue }
        after=substr(text,cursor,1)
        if (after == "" || after !~ /[A-Za-z0-9]/) print substr(text,start,cursor-start)
        pos=cursor
      }
    }'
}

grep -E '^[A-Z]:[[:space:]]*[0-9]+' "$REG" | while IFS= read -r line; do
  prefix="${line%%:*}"
  upper="$(printf '%s\n' "$line" | sed -nE "s/^[A-Z]:[[:space:]]*([0-9]+).*/\1/p")"
  case "$line" in
    *→*) home="$(printf '%s\n' "$line" | sed -E 's/.*→[[:space:]]*//; s/[[:space:]]*$//')" ;;
    *) home="" ;;
  esac
  echo "── ${prefix} 类（上界 ${upper}）──"
  if [ -z "$home" ] || [ "${home##*.}" != md ]; then
    echo "  ℹ️ 未设归口文件，跳过对账"
    continue
  fi
  if [ ! -f "$home" ]; then
    echo "  ❌ 归口文件不存在：$home"
    echo E >> "$TMPD/errors"
    continue
  fi

  strip_code "$home" | extract_ids "$prefix" | sort -u > "$TMPD/registered"
  : > "$TMPD/ref_outside"
  while IFS= read -r f; do
    [ "$f" = "./$home" ] && continue
    strip_code "$f" | extract_ids "$prefix" >> "$TMPD/ref_outside"
  done < "$TMPD/mdfiles"
  sort -u "$TMPD/ref_outside" > "$TMPD/seen_outside"
  sort -u "$TMPD/registered" "$TMPD/ref_outside" > "$TMPD/seen"
  max_reg="$(sed "s/^${prefix}//" "$TMPD/registered" | sort -n | tail -1)"
  max_reg="${max_reg:-0}"

  if [ "$upper" -lt "$max_reg" ]; then
    echo "  ❌ 上界漂移：REGISTRY ${upper} < 归口实际最大 ${prefix}${max_reg}"
    echo E >> "$TMPD/errors"
  elif [ "$upper" -gt "$max_reg" ]; then
    echo "  ℹ️ 上界 ${upper} > 实际最大 ${prefix}${max_reg}：可能刚取号未使用"
  fi

  dangling="$(comm -23 "$TMPD/seen" "$TMPD/registered")"
  if [ -n "$dangling" ]; then
    echo "  ❌ 悬空引用（正文提到但归口文件没有）："
    printf '%s\n' "$dangling" | sed 's/^/     /'
    echo E >> "$TMPD/errors"
  fi
  dead="$(comm -23 "$TMPD/registered" "$TMPD/seen_outside")"
  if [ -n "$dead" ]; then
    echo "  ⚠️ 死编号（归口外无引用，仅警告；最多列 10 个）："
    printf '%s\n' "$dead" | head -10 | sed 's/^/     /'
    echo W >> "$TMPD/warnings"
  fi
  if [ -z "$dangling" ] && [ "$upper" -ge "$max_reg" ]; then
    echo "  ✅ 上界与引用一致（登记 $(wc -l < "$TMPD/registered" | tr -d ' ') 个）"
  fi
done

C_ERR=0; C_WARN=0
[ -f "$TMPD/errors" ] && C_ERR=$(wc -l < "$TMPD/errors" | tr -d ' ')
[ -f "$TMPD/warnings" ] && C_WARN=$(wc -l < "$TMPD/warnings" | tr -d ' ')
printf '\n'
if [ "$C_ERR" -gt 0 ]; then
  echo "❌ 编号对账发现 ${C_ERR} 类错误、${C_WARN} 类警告"
  exit 1
elif [ "$C_WARN" -gt 0 ]; then
  echo "⚠️ 编号对账通过，有 ${C_WARN} 类警告（不阻塞）"
else
  echo "✅ 编号对账全部一致"
fi
