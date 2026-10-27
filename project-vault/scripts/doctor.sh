#!/usr/bin/env bash
# doctor.sh — 只读体检：必备文件、配置、链接、编号、git 隔离与日志防腐
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$ROOT"
TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT
ERRORS=0
WARNINGS=0
error() { echo "❌ $1"; ERRORS=$((ERRORS+1)); }
warn() { echo "⚠️ $1"; WARNINGS=$((WARNINGS+1)); }

for f in AGENTS.md STATUS.md CHANGELOG.md REGISTRY.md vault.conf 00_项目主页.md \
  10_需求/白话全解.md 10_需求/功能需求清单.md \
  30_合规与决策/决策记录.md 40_推进/待确认问题清单.md \
  40_推进/待办与风险.md 40_推进/依赖与对接清单.md \
  40_推进/信息提供状态.md 99_附件/清单.md; do
  [ -f "$f" ] || error "缺少必备文件：$f"
done

MODE="$(sed -nE 's/^BRANCH_MODE=(single|dual)[[:space:]]*$/\1/p' vault.conf 2>/dev/null)"
[ "$MODE" = single ] || [ "$MODE" = dual ] || error "vault.conf 必须有且只有有效的 BRANCH_MODE=single|dual"
[ "$(grep -cE '^BRANCH_MODE=' vault.conf 2>/dev/null)" = 1 ] || error "vault.conf 中 BRANCH_MODE 必须只出现一次"

find . -mindepth 1 -type d -name .git -prune -o \
  -type d -exec test -d '{}/.git' \; -prune -o \
  -type d -name node_modules -prune -o -type d -name 本地信息 -prune -o \
  -name '*.md' -exec grep -H -E '\{\{(PROJECT_NAME|PROJECT_DESC|DATE|VAULT_VERSION)\}\}' '{}' + \
  > "$TMPD/placeholders" 2>/dev/null || true
if [ -s "$TMPD/placeholders" ]; then
  error "发现未替换的生成占位符：$(head -1 "$TMPD/placeholders")"
fi
if grep -q '（待补充' AGENTS.md 2>/dev/null; then
  warn "AGENTS.md 角色上下文尚有待补充项，首次会话应主动问齐"
fi

bash scripts/check-links.sh || ERRORS=$((ERRORS+1))
bash scripts/check-registry.sh || ERRORS=$((ERRORS+1))

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  [ "$(git rev-parse --show-toplevel)" = "$ROOT" ] || error "知识库脚本根目录不是 git 顶层"
  git ls-files > "$TMPD/tracked"
  grep -E '^(本地信息/|\.env$|\.env\.|.*\.(key|pem|p12|pfx)$)' "$TMPD/tracked" | \
    grep -Ev '^\.env(\..*)?\.example$' > "$TMPD/sensitive" || true
  if [ -s "$TMPD/sensitive" ]; then
    error "敏感文件已被 git 跟踪：$(head -1 "$TMPD/sensitive")"
  fi

  find . -mindepth 2 -type d -name .git -prune > "$TMPD/nested"
  while IFS= read -r gitdir; do
    parent="$(dirname "$gitdir")"
    if ! git check-ignore -q -- "$parent/"; then
      error "嵌套代码仓未被外层 .gitignore 排除：${parent#./}"
    fi
  done < "$TMPD/nested"

  HOOK="$(git rev-parse --git-path hooks/pre-commit)"
  [ -x "$HOOK" ] || warn "pre-commit 钩子未安装或不可执行；克隆后运行 bash scripts/install-hooks.sh"
  BRANCH="$(git branch --show-current)"
  [ -n "$BRANCH" ] || warn "当前是 detached HEAD，不允许快照或发布"
  if [ "$MODE" = dual ] && [ "$BRANCH" = main ]; then
    warn "dual 模式当前在 main；编辑前切换到 feat/next"
  fi
fi

if [ -f CHANGELOG.md ]; then
  COUNT=$(($(wc -l < CHANGELOG.md | tr -d ' ') - 2))
  [ "$COUNT" -le 50 ] || warn "CHANGELOG.md 已有 $COUNT 条，请运行 archive-changelog.sh"
fi
if [ -f 进度记录.md ]; then
  LINES=$(wc -l < 进度记录.md | tr -d ' ')
  BYTES=$(wc -c < 进度记录.md | tr -d ' ')
  { [ "$LINES" -le 200 ] && [ "$BYTES" -le 131072 ]; } || warn "进度记录.md 过大（${LINES} 行/${BYTES} 字节），请归档日志并压缩接续提示"
fi

printf '\n体检结果：%s 个错误，%s 个警告\n' "$ERRORS" "$WARNINGS"
[ "$ERRORS" = 0 ]
