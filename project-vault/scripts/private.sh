#!/usr/bin/env bash
# private.sh — 本地信息/ 的遮蔽操作入口；真实值永不回显，也不经命令行传入
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DIR="$ROOT/本地信息"

usage() { echo "用法: private.sh view|add|insert|rename|rm <文件名> [参数...]" >&2; exit 2; }
[ $# -ge 2 ] || usage
CMD="$1"
FILE="$2"
case "$FILE" in ""|"."|".."|*/*|*\\*|*:*|*$'\n'*|*$'\r'*)
  echo "文件名只能是 本地信息/ 下的单层普通文件名" >&2; exit 2 ;;
esac
[ ! -L "$DIR" ] || { echo "拒绝：本地信息/ 不能是指向其他位置的符号链接" >&2; exit 1; }
PATHNAME="$DIR/$FILE"
[ -f "$PATHNAME" ] && [ ! -L "$PATHNAME" ] || { echo "文件不存在或不是普通文件：$FILE" >&2; exit 1; }

valid_label() {
  case "$1" in ""|*：*|*:*|*'|'*|*$'\n'*|*$'\r'*) return 1 ;; *) return 0 ;; esac
}
mask() {
  awk '{
    if ($0 ~ /^[ \t]*\|/) { print "|（表格行已遮蔽；请改用标签：值格式）|"; next }
    if (match($0, /^[ \t]*[^#>|：: \t][^：:]*[：:][ \t]*/)) {
      label = substr($0, 1, RLENGTH)
      value = substr($0, RLENGTH + 1)
      if (value == "" || value ~ /^(（|\(|见|\*\*\*)/) print $0
      else print label "***"
    } else print $0
  }' "$1"
}
temp_for() {
  TMP="$(mktemp "$DIR/.private.XXXXXX")"
  trap 'rm -f "$TMP"' EXIT
}

case "$CMD" in
  view)
    [ $# -eq 2 ] || usage
    mask "$PATHNAME"
    ;;
  add)
    shift 2
    [ $# -gt 0 ] || usage
    for label in "$@"; do valid_label "$label" || { echo "非法标签：$label" >&2; exit 2; }; done
    for label in "$@"; do printf '%s：\n' "$label" >> "$PATHNAME"; done
    echo "已追加（遮蔽预览）："
    mask "$PATHNAME" | tail -n "$#"
    ;;
  insert)
    [ $# -eq 4 ] || usage
    ANCHOR="$3"; LABEL="$4"
    [ -n "$ANCHOR" ] && valid_label "$LABEL" || { echo "锚点不能为空，标签必须合法" >&2; exit 2; }
    temp_for
    awk -v a="$ANCHOR" -v l="$LABEL" '{ print } index($0, a) > 0 && !done { print l "："; done = 1 }' "$PATHNAME" > "$TMP"
    mv "$TMP" "$PATHNAME"
    echo "已插入（遮蔽预览）："
    mask "$PATHNAME" | grep -F "$LABEL" || true
    ;;
  rename)
    [ $# -eq 4 ] || usage
    OLD="$3"; NEW="$4"
    valid_label "$OLD" && valid_label "$NEW" || { echo "标签不合法" >&2; exit 2; }
    temp_for
    awk -v old="$OLD" -v new="$NEW" '{
      indent=$0; sub(/[^ \t].*$/, "", indent)
      body=substr($0, length(indent)+1)
      if (index(body, old "：") == 1 || index(body, old ":") == 1) {
        sep=substr(body, length(old)+1, 1)
        print indent new sep substr(body, length(old)+2)
      } else print $0
    }' "$PATHNAME" > "$TMP"
    mv "$TMP" "$PATHNAME"
    echo "已改名（遮蔽预览）："
    mask "$PATHNAME" | grep -F "$NEW" || true
    ;;
  rm)
    [ $# -eq 3 ] || usage
    LABEL="$3"; valid_label "$LABEL" || { echo "标签不合法" >&2; exit 2; }
    temp_for
    awk -v label="$LABEL" '{
      indent=$0; sub(/[^ \t].*$/, "", indent)
      body=substr($0, length(indent)+1)
      if (index(body, label "：") == 1 || index(body, label ":") == 1) next
      print $0
    }' "$PATHNAME" > "$TMP"
    mv "$TMP" "$PATHNAME"
    echo "已删除标签（如存在）：$LABEL"
    ;;
  *) usage ;;
esac
