#!/usr/bin/env bash
# install-hooks.sh — 显式安装 project-vault pre-commit shim；保留其他自定义钩子
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$ROOT"
[ "$(git rev-parse --show-toplevel 2>/dev/null)" = "$ROOT" ] || { echo "❌ 脚本根目录不是 git 顶层" >&2; exit 1; }
HOOK="$(git rev-parse --git-path hooks/pre-commit)"
if [ -e "$HOOK" ]; then
  if grep -q 'scripts/pre-commit.sh' "$HOOK" && [ -x "$HOOK" ]; then
    echo "✅ project-vault pre-commit 已安装"
    exit 0
  fi
  echo "❌ 已有自定义 pre-commit，未覆盖：$HOOK" >&2
  exit 1
fi
mkdir -p "$(dirname "$HOOK")"
printf '#!/usr/bin/env bash\nexec bash "$(git rev-parse --show-toplevel)/scripts/pre-commit.sh"\n' > "$HOOK"
chmod +x "$HOOK"
echo "✅ 已安装 project-vault pre-commit：$HOOK"
