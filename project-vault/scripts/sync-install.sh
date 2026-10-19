#!/usr/bin/env bash
# sync-install.sh — 把开发目录的 project-vault 同步到 AI 工具的技能安装位
# 用法: bash scripts/sync-install.sh
# 规矩：开发目录是唯一真身（改只改这里），安装位只是部署产物。
# 标准流程：改开发目录 → bash scripts/selftest.sh → bash scripts/sync-install.sh
set -euo pipefail

DEV="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL="$HOME/.agents/skills/project-vault"

mkdir -p "$(dirname "$INSTALL")"
# --delete 让安装位与真身严格一致（删掉开发目录已移除的文件）
rsync -a --delete --exclude='.git' "$DEV/" "$INSTALL/"
echo "✅ 已同步：$DEV → $INSTALL"
diff -rq --exclude=.git "$DEV" "$INSTALL" >/dev/null && echo "✅ 校验：两边一致"
