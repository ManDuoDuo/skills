#!/usr/bin/env bash
# pre-commit.sh — 提交前守门（版本化钩子逻辑，由 .git/hooks/pre-commit 的 shim 调用）
# 三道闸：① 私钥/密钥扫描（铁律"敏感只存指针"的机械执行）
#         ② 断链校验（check-links.sh）
#         ③ 编号对账（check-registry.sh，警告不拦、错误拦）
# 安装：init-vault.sh --git 时自动写入 shim；老库手动装：
#   printf '#!/usr/bin/env bash\nexec bash "$(git rev-parse --show-toplevel)/scripts/pre-commit.sh"\n' > .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
#   ⚠️ "老库"仅指 project-vault 系（有 REGISTRY.md 的库）。非本系的库（wikilink＋无 REGISTRY.md）
#   装了会被第 2/3 道闸卡死——那种库应使用只含私钥扫描的定制钩子。
# 应急绕过：git commit --no-verify（会留在 git 记录里，慎用）。
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail=0

# 1) 私钥/密钥扫描（只扫本次暂存内容）
staged=$(git -c core.quotepath=false diff --cached --name-only --diff-filter=ACM 2>/dev/null || true)
if [ -n "$staged" ]; then
  hits=""
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    if grep -qIE 'BEGIN [A-Z ]*PRIVATE KEY|LTAI[0-9A-Za-z]{12,}|AKIA[0-9A-Z]{16}' "$f" 2>/dev/null; then
      hits="${hits}${f}\n"
    fi
  done <<< "$staged"
  if [ -n "$hits" ]; then
    echo "❌ 暂存内容疑似包含私钥/密钥，拒绝提交："
    printf "$hits"
    echo "铁律：敏感信息只写存放位置。确认误报可用 git commit --no-verify 绕过。"
    fail=1
  fi
fi

# 2) 断链校验
if ! bash scripts/check-links.sh >/dev/null 2>&1; then
  echo "❌ 存在断链，拒绝提交（跑 bash scripts/check-links.sh 看明细）"
  fail=1
fi

# 3) 编号对账（死编号等警告不拦，漂移/悬空才拦）
if ! bash scripts/check-registry.sh >/dev/null 2>&1; then
  echo "❌ 编号对账未过，拒绝提交（跑 bash scripts/check-registry.sh 看明细）"
  fail=1
fi

[ "$fail" = 0 ] && exit 0 || exit 1
