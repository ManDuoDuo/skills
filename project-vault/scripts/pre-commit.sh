#!/usr/bin/env bash
# pre-commit.sh — 分支保护、暂存内容安全扫描、链接与编号门禁
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$ROOT"
fail=0

mode="$(sed -nE 's/^BRANCH_MODE=(single|dual)[[:space:]]*$/\1/p' vault.conf 2>/dev/null)"
branch="$(git branch --show-current 2>/dev/null || true)"
if [ "$mode" = dual ] && [ "$branch" = main ]; then
  echo "❌ dual 模式禁止直接提交 main；请切换到 feat/next，正式发布走 scripts/publish.sh"
  fail=1
fi

while IFS= read -r -d '' f; do
  case "$f" in
    本地信息/*|.env|.env.*|*.key|*.pem|*.p12|*.pfx)
      case "$f" in .env.example|.env.*.example) ;; *)
        echo "❌ 敏感文件不应进入暂存区：$f"
        fail=1
        continue
      ;; esac
      ;;
  esac
  if git cat-file blob ":$f" 2>/dev/null | grep -qIE 'BEGIN [A-Z ]*PRIVATE KEY|LTAI[0-9A-Za-z]{12,}|AKIA[0-9A-Z]{16}' 2>/dev/null; then
    echo "❌ 暂存 blob 疑似包含私钥/密钥：$f"
    fail=1
  fi
done < <(git -c core.quotepath=false diff --cached --name-only --diff-filter=ACM -z 2>/dev/null)

if ! bash scripts/check-links.sh >/dev/null 2>&1; then
  echo "❌ 存在断链或违规链接，拒绝提交（跑 bash scripts/check-links.sh 看明细）"
  fail=1
fi
if ! bash scripts/check-registry.sh >/dev/null 2>&1; then
  echo "❌ 编号对账未过，拒绝提交（跑 bash scripts/check-registry.sh 看明细）"
  fail=1
fi

[ "$fail" = 0 ] && exit 0 || exit 1
