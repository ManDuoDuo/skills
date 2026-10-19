#!/usr/bin/env bash
# init-vault.sh — 把目标文件夹初始化为 project-vault 项目知识库
# 用法: init-vault.sh <目标目录> <项目名> ["一句话简介"] [--git] [--code <代码库目录名>]
# 无 bash 环境时，按 SKILL.md §4 Step 2 的手工等价步骤执行同样的事。
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATES="$SKILL_DIR/templates"

TARGET="${1:?用法: init-vault.sh <目标目录> <项目名> [\"简介\"] [--git] [--code 目录名]}"
NAME="${2:?缺少项目名}"
shift 2
DESC="（待补充：一句话说明这个项目是什么）"
USE_GIT=0
CODE_DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --git)  USE_GIT=1 ;;
    --code) shift; CODE_DIR="${1:?--code 需要一个目录名}" ;;
    *)      DESC="$1" ;;
  esac
  shift
done

# 防呆：目标目录不得位于 Skill 自身目录内。曾有测试初始化把残留写进 templates/，
# 残留文件随后被当成模板拷进每个新库。（检查必须先于 mkdir，否则拒绝时仍留下空目录）
TARGET_ABS="$(cd "$(dirname "$TARGET")" && pwd)/$(basename "$TARGET")"
case "$TARGET_ABS" in
  "$SKILL_DIR"|"$SKILL_DIR"/*)
    echo "拒绝：目标目录在 Skill 自身目录内，不应被初始化：$TARGET_ABS" >&2
    exit 1 ;;
esac

mkdir -p "$TARGET"

DATE="$(date +%Y-%m-%d)"

# sed 替换串转义：\ / & 三个字符在 sed replacement 里是特殊字符，
# 项目名或简介里带"文档/代码混合"、"R&D"这类写法时直接替换会炸
esc() { printf '%s' "$1" | sed -e 's/[\\/&]/\\&/g'; }
NAME_E="$(esc "$NAME")"
DESC_E="$(esc "$DESC")"

# 生成器版本：写进产物的版本戳（AGENTS.md 头部），改格式约定时务必同步升版
VAULT_VERSION="v1.7"

# 1) 复制模板：.tmpl 文件替换占位符并去掉后缀；普通文件（如 90_模板/）原样拷贝
#    _code/ 是代码库专用模板，只在 --code 时使用，不拷进知识库
cd "$TEMPLATES"
find . -type f -not -path './_code/*' | while read -r tmpl; do
  rel="${tmpl#./}"
  case "$rel" in
    *.tmpl) dest="$TARGET/${rel%.tmpl}" ;;
    *)      dest="$TARGET/$rel" ;;
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
    *)
      cp "$tmpl" "$dest" ;;
  esac
  echo "生成: $dest"
done

# 2) 空目录（git 不跟踪空目录，放 .gitkeep）
mkdir -p "$TARGET/10_需求/原文" "$TARGET/20_方案" "$TARGET/99_附件/历史"
touch "$TARGET/10_需求/原文/.gitkeep" "$TARGET/20_方案/.gitkeep" "$TARGET/99_附件/历史/.gitkeep"

# 3) 拷贝日常脚本（不拷贝 init-vault.sh / selftest.sh 自身）
mkdir -p "$TARGET/scripts"
for s in next-id.sh check-links.sh check-registry.sh archive-changelog.sh pre-commit.sh snapshot.sh; do
  [ -e "$TARGET/scripts/$s" ] || cp "$SKILL_DIR/scripts/$s" "$TARGET/scripts/$s"
done
chmod +x "$TARGET"/scripts/*.sh

# 4) 可选代码库骨架（结构说明见 references/代码库结构.md）
if [ -n "$CODE_DIR" ]; then
  CODE="$TARGET/$CODE_DIR"
  if [ -e "$CODE" ]; then
    echo "跳过（已存在）: $CODE"
  else
    # 分层骨架目录（空目录放 .gitkeep）
    for d in \
      apps/web-service/app/api apps/web-service/app/service apps/web-service/app/model \
      apps/web-service/app/schema apps/web-service/app/core apps/web-service/app/exception \
      apps/web-service/app/constants \
      apps/web-service/migrations/versions \
      apps/web-service/test/unit apps/web-service/test/integration apps/web-service/test/e2e \
      packages web docker docs scripts keys; do
      mkdir -p "$CODE/$d"
      [ "$d" = keys ] || touch "$CODE/$d/.gitkeep"  # keys/ 被代码库 .gitignore 忽略，放了 .gitkeep 也进不了 git
    done
    # 代码库自己的 AGENTS.md / .gitignore / 进度记录
    sed -e "s/{{PROJECT_NAME}}/$NAME_E/g" \
        -e "s/{{PROJECT_DESC}}/$DESC_E/g" \
        -e "s/{{DATE}}/$DATE/g" \
        "$TEMPLATES/_code/AGENTS.md.tmpl" > "$CODE/AGENTS.md"
    cp "$TEMPLATES/_code/.gitignore.tmpl" "$CODE/.gitignore"
    printf '# %s 工程进度记录\n\n> 新会话接续提示：骨架刚生成，尚未开始开发。\n\n' "$NAME" > "$CODE/进度记录.md"
    # 知识库 .gitignore 排除代码库（双层 git 互不嵌套的关键）
    # 用整行精确匹配（-x）：模板里有注释行 `# backend/`，模糊匹配会误判为已存在
    grep -qxF "$CODE_DIR/" "$TARGET/.gitignore" 2>/dev/null || printf '\n# 代码库（独立 git 仓库）\n%s/\n' "$CODE_DIR" >> "$TARGET/.gitignore"
    # 在项目主页登记（CODE_DIR 过 esc：sed 替换串里 & | \ 是特殊字符，目录名带这些会炸）
    if grep -q '^（有代码时在此登记' "$TARGET/00_项目主页.md"; then
      CODE_DIR_E="$(esc "$CODE_DIR")"
      sed -i.bak "s|^（有代码时在此登记.*|- 代码库：\`$CODE_DIR_E/\`（独立 git 仓库，工程规则见其 AGENTS.md，工程进度见其 进度记录.md）|" "$TARGET/00_项目主页.md"
      rm -f "$TARGET/00_项目主页.md.bak"
    fi
    if [ "$USE_GIT" = "1" ]; then
      git -C "$CODE" init -q
      git -C "$CODE" add -A
      git -C "$CODE" commit -q -m "代码库骨架（project-vault 生成）" || true
    fi
    echo "代码库骨架: ${CODE}（独立 git 仓库，结构说明见 references/代码库结构.md）"
  fi
fi

# 5) 可选 git（.gitignore 已在 step 1 由模板无条件生成）
if [ "$USE_GIT" = "1" ]; then
  if [ ! -d "$TARGET/.git" ]; then
    git -C "$TARGET" init -q
  fi
  # 提交门禁：shim 调版本化的 scripts/pre-commit.sh（逻辑随库演进，shim 不用变）
  if [ ! -e "$TARGET/.git/hooks/pre-commit" ]; then
    printf '#!/usr/bin/env bash\nexec bash "$(git rev-parse --show-toplevel)/scripts/pre-commit.sh"\n' > "$TARGET/.git/hooks/pre-commit"
    chmod +x "$TARGET/.git/hooks/pre-commit"
  fi
  git -C "$TARGET" add -A
  git -C "$TARGET" commit -q -m "建库（project-vault 初始化）" || true
  echo "git: 已初始化并完成首次提交（含 pre-commit 提交门禁）"
fi

echo ""
echo "完成：$TARGET 已初始化为 $NAME 的项目知识库（project-vault ${VAULT_VERSION}）。"
echo "下一步：任何 AI 会话打开该文件夹，说'读 AGENTS.md，我开始发材料了'。"
echo "提醒：本地 git 只防误改、不防盘坏——建议尽快配远端私有仓或定期备份。"
