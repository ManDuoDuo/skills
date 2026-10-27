#!/usr/bin/env bash
# next-id.sh — 从 REGISTRY.md 取一个编号并同步上界
# 用法: next-id.sh <Q|R|E|D|F>   输出如: Q7
# 等价手工步骤见 SKILL.md §5.1（读上界 → +1 → 写回 → 使用，同一轮完成）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
REG="$ROOT/REGISTRY.md"
PREFIX="${1:?用法: next-id.sh <Q|R|E|D|F>}"
[ $# -eq 1 ] || { echo "用法: next-id.sh <Q|R|E|D|F>" >&2; exit 2; }
case "$PREFIX" in Q|R|E|D|F) ;; *) echo "编号前缀只接受 Q/R/E/D/F" >&2; exit 2 ;; esac

[ -f "$REG" ] || { echo "找不到 $REG" >&2; exit 1; }
grep -qE "^${PREFIX}:[[:space:]]*[0-9]+" "$REG" || { echo "REGISTRY.md 中没有 ${PREFIX} 类编号" >&2; exit 1; }

# 并发锁：mkdir 是原子操作，全平台通用（macOS 没有 flock）。
# 两个会话同时取号时后到者直接失败，防止重号。
LOCK="$REG.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
  echo "另一个取号正在进行（锁: ${LOCK}）。若确认没有并发（上次会话异常退出残留），删除该目录后重试" >&2
  exit 1
fi
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT

cur=$(sed -nE "s/^${PREFIX}:[[:space:]]*([0-9]+).*/\1/p" "$REG")
next=$((cur + 1))

# macOS 与 GNU sed 兼容的原地写法
sed -i.bak -E "s/^${PREFIX}:[[:space:]]*[0-9]+/${PREFIX}: ${next}/" "$REG"
rm -f "$REG.bak"

echo "${PREFIX}${next}"
