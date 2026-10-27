#!/usr/bin/env bash
# init-vault.sh — 把目标文件夹初始化为 project-vault 项目知识库
# 用法: init-vault.sh <目标目录> <项目名> ["简介"] [--git] [--branch single|dual] [--code <目录名>]
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TEMPLATES="$SKILL_DIR/templates"
VAULT_VERSION="v2.0"

usage() {
  echo "用法: init-vault.sh <目标目录> <项目名> [\"简介\"] [--git] [--branch single|dual] [--code 目录名]" >&2
  exit 2
}

[ $# -ge 2 ] || usage
TARGET="$1"
NAME="$2"
shift 2
DESC="（待补充：一句话说明这个项目是什么）"
DESC_SET=0
USE_GIT=0
BRANCH_MODE="dual"
CODE_DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --git) USE_GIT=1 ;;
    --branch)
      shift
      [ $# -gt 0 ] || usage
      BRANCH_MODE="$1"
      ;;
    --code)
      shift
      [ $# -gt 0 ] || usage
      CODE_DIR="$1"
      ;;
    -*) echo "未知选项：$1" >&2; usage ;;
    *)
      [ "$DESC_SET" = 0 ] || { echo "只能提供一个简介" >&2; usage; }
      DESC="$1"
      DESC_SET=1
      ;;
  esac
  shift
done

[ -n "$TARGET" ] && [ -n "$NAME" ] || usage
case "$BRANCH_MODE" in single|dual) ;; *) echo "--branch 只接受 single 或 dual" >&2; exit 2 ;; esac
case "$TARGET$NAME$DESC" in *$'\n'*|*$'\r'*) echo "目标、项目名和简介不能含换行" >&2; exit 2 ;; esac
if [ -n "$CODE_DIR" ]; then
  case "$CODE_DIR" in
    ""|"."|".."|".git"|*/*|*\\*|*:*|*$'\n'*|*$'\r'*)
      echo "--code 只接受安全的单层目录名，不能含路径分隔符、冒号或 ..：$CODE_DIR" >&2
      exit 2 ;;
  esac
  if [ -e "$TARGET/$CODE_DIR" ]; then
    echo "拒绝：代码目录已存在，初始化不会覆盖或接管它：$TARGET/$CODE_DIR" >&2
    exit 1
  fi
fi

normalize_path() {
  local input rest part stack
  case "$1" in /*) input="$1" ;; *) input="$PWD/$1" ;; esac
  rest="${input#/}"
  stack=""
  while [ -n "$rest" ]; do
    part="${rest%%/*}"
    case "$rest" in */*) rest="${rest#*/}" ;; *) rest="" ;; esac
    case "$part" in
      ""|".") ;;
      "..") stack="${stack%/*}" ;;
      *) stack="$stack/$part" ;;
    esac
  done
  printf '%s\n' "${stack:-/}"
}

TARGET_LEX="$(normalize_path "$TARGET")"
case "$TARGET_LEX" in
  "$SKILL_DIR"|"$SKILL_DIR"/*)
    echo "拒绝：目标目录在 Skill 自身目录内：$TARGET_LEX" >&2
    exit 1 ;;
esac
PROBE="$TARGET"
while [ ! -e "$PROBE" ]; do
  PARENT="$(dirname "$PROBE")"
  [ "$PARENT" != "$PROBE" ] || break
  PROBE="$PARENT"
done
if [ -e "$PROBE" ]; then
  [ -d "$PROBE" ] || { echo "目标路径的已有上级不是目录：$PROBE" >&2; exit 1; }
  PROBE_ABS="$(cd "$PROBE" && pwd -P)"
  case "$PROBE_ABS" in
    "$SKILL_DIR"|"$SKILL_DIR"/*)
      echo "拒绝：目标经符号链接进入 Skill 自身目录：$PROBE_ABS" >&2
      exit 1 ;;
  esac
fi

mkdir -p "$TARGET"
TARGET_ABS="$(cd "$TARGET" && pwd -P)"
case "$TARGET_ABS" in
  "$SKILL_DIR"|"$SKILL_DIR"/*)
    echo "拒绝：目标实际路径在 Skill 自身目录内：$TARGET_ABS" >&2
    exit 1 ;;
esac
TARGET="$TARGET_ABS"

if [ -f "$TARGET/vault.conf" ]; then
  EXISTING_MODE="$(sed -nE 's/^BRANCH_MODE=(single|dual)[[:space:]]*$/\1/p' "$TARGET/vault.conf")"
  [ -n "$EXISTING_MODE" ] || { echo "已有 vault.conf 无有效 BRANCH_MODE，拒绝静默改写" >&2; exit 1; }
  BRANCH_MODE="$EXISTING_MODE"
fi

DATE="$(date +%Y-%m-%d)"
esc_slash() { printf '%s' "$1" | sed -e 's/[\\/&]/\\&/g'; }
esc_pipe() { printf '%s' "$1" | sed -e 's/[\\|&]/\\&/g'; }
NAME_E="$(esc_slash "$NAME")"
DESC_E="$(esc_slash "$DESC")"

cd "$TEMPLATES"
find . -type f -not -path './_code/*' | while read -r tmpl; do
  rel="${tmpl#./}"
  case "$rel" in
    *.tmpl) dest="$TARGET/${rel%.tmpl}" ;;
    *) dest="$TARGET/$rel" ;;
  esac
  if [ -e "$dest" ]; then
    echo "跳过（已存在）: $dest"
    continue
  fi
  mkdir -p "$(dirname "$dest")"
  case "$rel" in
    *.tmpl)
      sed -e "s/{{PROJECT_NAME}}/$NAME_E/g" \
          -e "s/{{PROJECT_DESC}}/$DESC_E/g" \
          -e "s/{{VAULT_VERSION}}/$VAULT_VERSION/g" \
          -e "s/{{DATE}}/$DATE/g" \
          "$tmpl" > "$dest" ;;
    *) cp "$tmpl" "$dest" ;;
  esac
  echo "生成: $dest"
done

sed -i.bak -E "s/^BRANCH_MODE=.*/BRANCH_MODE=$BRANCH_MODE/" "$TARGET/vault.conf"
rm -f "$TARGET/vault.conf.bak"
mkdir -p "$TARGET/10_需求/原文" "$TARGET/20_方案" "$TARGET/99_附件/历史" "$TARGET/本地信息"
touch "$TARGET/10_需求/原文/.gitkeep" "$TARGET/20_方案/.gitkeep" "$TARGET/99_附件/历史/.gitkeep"
if [ ! -e "$TARGET/本地信息/信息模板.md" ]; then
  printf '# 本地信息（仅本机）\n\n项目：\n环境：\n' > "$TARGET/本地信息/信息模板.md"
fi

mkdir -p "$TARGET/scripts"
for s in next-id.sh check-links.sh check-registry.sh archive-changelog.sh pre-commit.sh install-hooks.sh snapshot.sh publish.sh doctor.sh private.sh; do
  [ -e "$TARGET/scripts/$s" ] || cp "$SKILL_DIR/scripts/$s" "$TARGET/scripts/$s"
  chmod +x "$TARGET/scripts/$s"
done

if [ -n "$CODE_DIR" ]; then
  CODE="$TARGET/$CODE_DIR"
  for d in packages docker docs scripts keys apps/web-service/app/model/association; do
    mkdir -p "$CODE/$d"
    [ "$d" = keys ] || touch "$CODE/$d/.gitkeep"
  done
  cd "$TEMPLATES/_code"
  find . -type f | while read -r tmpl; do
    rel="${tmpl#./}"
    case "$rel" in *.tmpl) dest="$CODE/${rel%.tmpl}" ;; *) dest="$CODE/$rel" ;; esac
    mkdir -p "$(dirname "$dest")"
    case "$rel" in
      *.tmpl)
        sed -e "s/{{PROJECT_NAME}}/$NAME_E/g" \
            -e "s/{{PROJECT_DESC}}/$DESC_E/g" \
            -e "s/{{VAULT_VERSION}}/$VAULT_VERSION/g" \
            -e "s/{{DATE}}/$DATE/g" \
            "$tmpl" > "$dest" ;;
      *) cp "$tmpl" "$dest" ;;
    esac
  done
  chmod +x "$CODE/scripts/"*.sh

  grep -qxF "$CODE_DIR/" "$TARGET/.gitignore" 2>/dev/null || printf '\n# 代码库（独立 git 仓库）\n%s/\n' "$CODE_DIR" >> "$TARGET/.gitignore"
  if grep -q '^（有代码时在此登记' "$TARGET/00_项目主页.md"; then
    CODE_DIR_E="$(esc_pipe "$CODE_DIR")"
    sed -i.bak "s|^（有代码时在此登记.*|- 活跃代码库：\`$CODE_DIR_E/\`（独立 git 仓库，工程规则见其 AGENTS.md，工程进度见其 进度记录.md）|" "$TARGET/00_项目主页.md"
    rm -f "$TARGET/00_项目主页.md.bak"
  fi
  if [ "$USE_GIT" = 1 ]; then
    git -C "$CODE" init -q -b main
    git -C "$CODE" add -A
    git -C "$CODE" commit -q -m "代码库骨架（project-vault 生成）"
  fi
  echo "代码库骨架: ${CODE}（独立目录，工程命令见其 Makefile）"
fi

if [ "$USE_GIT" = 1 ]; then
  if [ ! -e "$TARGET/.git" ]; then
    git -C "$TARGET" init -q -b main
  fi
  GIT_TOP="$(git -C "$TARGET" rev-parse --show-toplevel)"
  [ "$GIT_TOP" = "$TARGET" ] || { echo "拒绝：目标位于另一个 git 仓库内，不能静默嵌套：$GIT_TOP" >&2; exit 1; }
  INITIAL_COMMIT=0
  if ! git -C "$TARGET" rev-parse --verify HEAD >/dev/null 2>&1; then
    INITIAL_COMMIT=1
    [ "$(git -C "$TARGET" branch --show-current)" = main ] || git -C "$TARGET" symbolic-ref HEAD refs/heads/main
  fi

  bash "$TARGET/scripts/doctor.sh"
  if [ "$INITIAL_COMMIT" = 1 ]; then
    git -C "$TARGET" add -A
    git -C "$TARGET" commit -q -m "建库（project-vault 初始化）"
  else
    echo "已有 git 仓库：生成内容未自动提交，请检查后按用户授权提交"
  fi

  HOOK_REL="$(git -C "$TARGET" rev-parse --git-path hooks/pre-commit)"
  case "$HOOK_REL" in /*) HOOK="$HOOK_REL" ;; *) HOOK="$TARGET/$HOOK_REL" ;; esac
  if [ ! -e "$HOOK" ]; then
    bash "$TARGET/scripts/install-hooks.sh"
  else
    echo "保留已有 pre-commit 钩子：$HOOK"
  fi

  if [ "$BRANCH_MODE" = dual ]; then
    git -C "$TARGET" show-ref --verify --quiet refs/heads/main || { echo "dual 模式需要本地 main 分支" >&2; exit 1; }
    if ! git -C "$TARGET" show-ref --verify --quiet refs/heads/feat/next; then
      git -C "$TARGET" switch -q -c feat/next main
    else
      git -C "$TARGET" switch -q feat/next
    fi
  fi
  bash "$TARGET/scripts/doctor.sh"
  echo "git: 已初始化（BRANCH_MODE=${BRANCH_MODE}），提交门禁已安装"
fi

printf '\n完成：%s 已初始化为 %s 的项目知识库（project-vault %s）。\n' "$TARGET" "$NAME" "$VAULT_VERSION"
echo "下一步：任何 AI 会话打开该文件夹，说'读 AGENTS.md，我开始发材料了'。"
echo "提醒：本地 git 只防误改、不防盘坏——建议尽快配远端私有仓或定期备份。"
