#!/usr/bin/env bash
# snapshot.sh — 库快照：有改动才提交（前缀"快照:"，与人/AI 的正式提交区分），随后跑双校验
# 用法: snapshot.sh   （库内任意位置运行；供人手动或 AI 定时任务调用）
# 供定时任务调用时的属主原则：一个库同一时间只能有一个调度器（防止双快照互踩），
# 属主是谁记在该库 AGENTS.md 变更记录里。
# 无 bash 环境的手工等价：git status 看是否有变化 → 有则 git add -A && git commit -m "快照: <日期>"
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

[ -d .git ] || { echo "ℹ️ 未启用 git，无需快照"; exit 0; }

if [ -z "$(git status --porcelain)" ]; then
  echo "✅ 工作区干净，无需快照"
else
  git add -A
  if git commit -m "快照: $(date '+%Y-%m-%d %H:%M') 自动快照"; then
    echo "📦 已提交快照"
  else
    echo "❌ 快照提交被拒（多半是 pre-commit 门禁拦下，跑 scripts/check-links.sh 与 scripts/check-registry.sh 看明细）"
    exit 1
  fi
fi

echo "── 体检 ──"
bash scripts/check-links.sh
bash scripts/check-registry.sh
