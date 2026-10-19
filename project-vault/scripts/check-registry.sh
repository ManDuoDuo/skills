#!/usr/bin/env bash
# check-registry.sh — 编号系统对账（编号是库的外键，需要体检）
# 三件事：① REGISTRY 上界 ≥ 归口文件实际最大编号（漂移=错误）
#         ② 被引用的编号都已在归口文件登记（悬空引用=错误）
#         ③ 登记的编号在归口文件之外有引用（死编号=警告，不失败）
# 归口路径从 REGISTRY.md 行内 "→ 路径" 解析（唯一来源）；无归口路径的类别只查上界。
# 等价手工步骤：grep 归口文件里的编号、grep 全库引用、肉眼比对三份清单。
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
REG="REGISTRY.md"
[ -f "$REG" ] || { echo "找不到 $REG" >&2; exit 1; }

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT

# 收集全库 md（复用 check-links 的剪枝逻辑：剪掉 .git 与嵌套代码仓库）
find . -mindepth 1 -type d -name .git -prune -o \
     -type d -exec test -d '{}/.git' \; -prune -o \
     -type d -name node_modules -prune -o \
     -name '*.md' -print > "$TMPD/mdfiles"

ERRORS=0
WARNINGS=0

grep -E '^[A-Z]:[[:space:]]*[0-9]+' "$REG" | while IFS= read -r line; do
  prefix="${line%%:*}"
  upper=$(echo "$line" | sed -nE "s/^[A-Z]:[[:space:]]*([0-9]+).*/\1/p")
  home=$(echo "$line" | sed -nE 's/.*→[[:space:]]*([^ ]+\.md).*/\1/p')

  echo "── ${prefix} 类（上界 ${upper}）──"

  if [ -z "$home" ]; then
    echo "  ℹ️ 未设归口文件，跳过对账（定下来后写进 REGISTRY.md）"
    continue
  fi
  if [ ! -f "$home" ]; then
    echo "  ❌ 归口文件不存在: $home"
    echo E >> "$TMPD/errors"; continue
  fi

  # 归口文件里登记的编号
  grep -oE "${prefix}[0-9]+" "$home" | sort -u > "$TMPD/registered" || true
  # 归口文件之外被引用的编号
  : > "$TMPD/ref_outside"
  while IFS= read -r f; do
    [ "$f" = "./$home" ] && continue
    grep -oE "${prefix}[0-9]+" "$f" >> "$TMPD/ref_outside" || true
  done < "$TMPD/mdfiles"
  sort -u "$TMPD/ref_outside" > "$TMPD/seen_outside"
  # 全库出现的编号（含归口文件自身）
  sort -u "$TMPD/registered" "$TMPD/ref_outside" > "$TMPD/seen"

  max_reg=$(sed "s/^${prefix}//" "$TMPD/registered" | sort -n | tail -1)
  max_reg=${max_reg:-0}

  # ① 上界漂移
  if [ "$upper" -lt "$max_reg" ]; then
    echo "  ❌ 上界漂移：REGISTRY 上界 ${upper} < 归口实际最大 ${prefix}${max_reg}（可能手工登记忘了同步上界）"
    echo E >> "$TMPD/errors"
  elif [ "$upper" -gt "$max_reg" ]; then
    echo "  ℹ️ 上界 ${upper} > 实际最大 ${prefix}${max_reg}：可能刚取号未使用，属正常"
  fi

  # ② 悬空引用：被引用但未登记
  dangling=$(comm -23 "$TMPD/seen" "$TMPD/registered")
  if [ -n "$dangling" ]; then
    echo "  ❌ 悬空引用（正文提到但归口文件没有）："
    echo "$dangling" | sed 's/^/     /'
    echo E >> "$TMPD/errors"
  fi

  # ③ 死编号：已登记但归口文件之外无人引用
  dead=$(comm -23 "$TMPD/registered" "$TMPD/seen_outside")
  if [ -n "$dead" ]; then
    echo "  ⚠️ 死编号（登记了但全库无引用，检查是否漏了互链）："
    echo "$dead" | sed 's/^/     /'
    echo W >> "$TMPD/warnings"
  fi

  [ -z "$dangling" ] && [ -z "$dead" ] && [ "$upper" -ge "$max_reg" ] && echo "  ✅ 一致（登记 $(wc -l < "$TMPD/registered" | tr -d ' ') 个）"
done

C_ERR=0; C_WARN=0
[ -f "$TMPD/errors" ] && C_ERR=$(wc -l < "$TMPD/errors" | tr -d ' ')
[ -f "$TMPD/warnings" ] && C_WARN=$(wc -l < "$TMPD/warnings" | tr -d ' ')
echo ""
if [ "$C_ERR" -gt 0 ]; then
  echo "❌ 编号对账发现 ${C_ERR} 类错误、${C_WARN} 类警告"
  exit 1
elif [ "$C_WARN" -gt 0 ]; then
  echo "⚠️ 编号对账通过，有 ${C_WARN} 类警告（死编号不阻塞）"
  exit 0
else
  echo "✅ 编号对账全部一致"
fi
