#!/usr/bin/env bash
# snapshot.sh — 先体检再保存工作区；默认不推送，--push 需用户明确授权
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$ROOT"
PUSH=0
case "${1:-}" in "" ) ;; --push) PUSH=1 ;; *) echo "用法: snapshot.sh [--push]" >&2; exit 2 ;; esac
[ $# -le 1 ] || { echo "用法: snapshot.sh [--push]" >&2; exit 2; }

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "ℹ️ 未启用 git，无需快照"; exit 0; }
[ "$(git rev-parse --show-toplevel)" = "$ROOT" ] || { echo "❌ 脚本根目录不是 git 顶层，拒绝跨仓快照" >&2; exit 1; }
MODE="$(sed -nE 's/^BRANCH_MODE=(single|dual)[[:space:]]*$/\1/p' vault.conf)"
[ -n "$MODE" ] || { echo "❌ vault.conf 缺少有效 BRANCH_MODE" >&2; exit 1; }
BRANCH="$(git branch --show-current)"
[ -n "$BRANCH" ] || { echo "❌ detached HEAD 不允许快照" >&2; exit 1; }
if [ "$MODE" = dual ] && [ "$BRANCH" != feat/next ]; then
  echo "❌ dual 模式只允许在 feat/next 快照；main 只通过 publish.sh 更新" >&2
  exit 1
fi

HOOK="$(git rev-parse --git-path hooks/pre-commit)"
[ -x "$HOOK" ] || { echo "❌ 提交门禁未安装；先运行 bash scripts/install-hooks.sh" >&2; exit 1; }
bash scripts/doctor.sh
if [ -z "$(git status --porcelain)" ]; then
  echo "✅ 工作区干净，无需快照"
else
  git add -A
  git commit -m "快照: $(date '+%Y-%m-%d %H:%M')"
  echo "📦 已提交到 $BRANCH"
fi

if [ "$PUSH" = 1 ]; then
  git remote get-url origin >/dev/null 2>&1 || { echo "❌ --push 需要已配置 origin" >&2; exit 1; }
  git push origin "$BRANCH"
  git fetch origin "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH"
  [ "$(git rev-parse HEAD)" = "$(git rev-parse "refs/remotes/origin/$BRANCH")" ] || {
    echo "❌ $BRANCH 与 origin/$BRANCH 不一致" >&2
    exit 1
  }
  echo "✅ $BRANCH 与 origin/$BRANCH 一致"
else
  echo "ℹ️ 未推送（需要用户明确授权后使用 --push）"
fi
