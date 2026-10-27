#!/usr/bin/env bash
# publish.sh — 显式确认后：feat/next → main → 推送 → 回合同步 feat/next
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$ROOT"
[ "${PROJECT_VAULT_PUBLISH_CONFIRM:-}" = 1 ] || {
  echo "❌ 发布只接受用户明确口令；确认后设置 PROJECT_VAULT_PUBLISH_CONFIRM=1 执行" >&2
  exit 1
}
[ "$(git rev-parse --show-toplevel 2>/dev/null)" = "$ROOT" ] || { echo "❌ 脚本根目录不是 git 顶层" >&2; exit 1; }
[ "$(sed -nE 's/^BRANCH_MODE=(single|dual)[[:space:]]*$/\1/p' vault.conf)" = dual ] || { echo "❌ 仅 dual 模式支持发布" >&2; exit 1; }
[ "$(git branch --show-current)" = feat/next ] || { echo "❌ 发布必须从 feat/next 开始" >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "❌ 有未提交修改；请先按授权快照或提交" >&2; exit 1; }
git remote get-url origin >/dev/null 2>&1 || { echo "❌ 未配置 origin" >&2; exit 1; }
HOOK="$(git rev-parse --git-path hooks/pre-commit)"
[ -x "$HOOK" ] || { echo "❌ 提交门禁未安装；先运行 bash scripts/install-hooks.sh" >&2; exit 1; }

bash scripts/doctor.sh
git fetch origin "+refs/heads/main:refs/remotes/origin/main" "+refs/heads/feat/next:refs/remotes/origin/feat/next"
[ "$(git rev-parse feat/next)" = "$(git rev-parse refs/remotes/origin/feat/next)" ] || {
  echo "❌ feat/next 与远端不一致；先按授权拉齐" >&2
  exit 1
}

finish() {
  if [ "$(git branch --show-current 2>/dev/null)" != feat/next ]; then
    git switch feat/next >/dev/null 2>&1 || echo "⚠️ 未能自动返回 feat/next；请检查 main 是否有未完成合并" >&2
  fi
}
trap finish EXIT

if git show-ref --verify --quiet refs/heads/main; then
  git switch main
else
  git switch -c main refs/remotes/origin/main
fi
git pull --ff-only origin main
git merge --no-ff feat/next -m "发布: $(date '+%Y-%m-%d %H:%M')"
bash scripts/doctor.sh
git push origin main
git switch feat/next
git merge --ff-only main
git push origin feat/next
git fetch origin "+refs/heads/main:refs/remotes/origin/main" "+refs/heads/feat/next:refs/remotes/origin/feat/next"
[ "$(git rev-parse main)" = "$(git rev-parse refs/remotes/origin/main)" ] || { echo "❌ main 与远端不一致" >&2; exit 1; }
[ "$(git rev-parse feat/next)" = "$(git rev-parse refs/remotes/origin/feat/next)" ] || { echo "❌ feat/next 与远端不一致" >&2; exit 1; }
[ "$(git rev-parse main)" = "$(git rev-parse feat/next)" ] || { echo "❌ 两个分支未指向同一发布内容" >&2; exit 1; }
echo "✅ 发布完成：main 与 feat/next 均已同步，当前在 feat/next"
