#!/usr/bin/env bash
# selftest.sh — project-vault 回归测试；只操作 mktemp 临时目录
set -uo pipefail
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FAILS=0
export GIT_AUTHOR_NAME=selftest GIT_AUTHOR_EMAIL=selftest@local
export GIT_COMMITTER_NAME=selftest GIT_COMMITTER_EMAIL=selftest@local

assert() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "✅ ${desc}"; else echo "❌ ${desc}"; FAILS=$((FAILS+1)); fi
}
assert_out() {
  local desc="$1" want="$2"; shift 2
  local got
  got="$("$@" 2>&1)"
  if printf '%s\n' "$got" | grep -qF "$want"; then
    echo "✅ ${desc}"
  else
    echo "❌ ${desc}（期望含: ${want}；实际: $(printf '%s\n' "$got" | head -2)）"
    FAILS=$((FAILS+1))
  fi
}
assert_not_out() {
  local desc="$1" unwanted="$2"; shift 2
  local got
  got="$("$@" 2>&1)"
  if printf '%s\n' "$got" | grep -qF "$unwanted"; then
    echo "❌ ${desc}（不应出现: ${unwanted}）"
    FAILS=$((FAILS+1))
  else
    echo "✅ ${desc}"
  fi
}
assert_fail() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "❌ ${desc}（本应失败却成功）"; FAILS=$((FAILS+1)); else echo "✅ ${desc}"; fi
}

INIT="$SKILL_DIR/scripts/init-vault.sh"
V="$WORK/nested/vault"

echo "═══ 1. 建库与完整代码骨架 ═══"
bash "$INIT" "$V" "R&D 终测" "带/斜杠的简介" --git --code backend >/dev/null 2>&1
assert "多级不存在目录建库成功" test -f "$V/AGENTS.md"
assert_out "简介特殊字符原样写入" "带/斜杠的简介" grep -m1 "简介" "$V/说明.md"
assert "项目名 & 原样写入" grep -q "R&D 终测" "$V/AGENTS.md"
assert "版本戳 v2.0" grep -q "project-vault v2.0" "$V/AGENTS.md"
assert "F 归口已生成" test -f "$V/10_需求/功能需求清单.md"
assert "信息台账与私密模板已生成" test -f "$V/40_推进/信息提供状态.md"
assert "占位符无残留" bash -c "! grep -rq '{{PROJECT\|{{DATE\|{{VAULT' '$V' --include='*.md'"
assert "Makefile 真实生成" test -f "$V/backend/Makefile"
assert "后端三层测试真实生成" test -f "$V/backend/apps/web-service/test/e2e/test_health_e2e.py"
assert "前端真实生成" test -f "$V/backend/web/admin/src/App.tsx"
assert "工程归档脚本可执行" test -x "$V/backend/scripts/archive-progress.sh"
assert "默认 dual 当前在 feat/next" bash -c "[ \$(git -C '$V' branch --show-current) = feat/next ]"
assert "main 与 feat/next 均存在" bash -c "git -C '$V' show-ref --verify --quiet refs/heads/main && git -C '$V' show-ref --verify --quiet refs/heads/feat/next"
assert "代码库独立 git" test -d "$V/backend/.git"
assert "外层 git 未跟踪代码库" bash -c "[ \$(git -C '$V' ls-files | grep -c backend) = 0 ]"
assert ".gitignore 排除代码库" grep -qx "backend/" "$V/.gitignore"
assert "新库体检通过" bash "$V/scripts/doctor.sh"

echo "═══ 2. 参数、非空目录与提交失败 ═══"
assert_fail "拒绝 Skill 内建库" bash "$INIT" "$SKILL_DIR/tmp-guard-$$" 测试
ln -s "$SKILL_DIR" "$WORK/skill-link"
assert_fail "拒绝经符号链接进入 Skill" bash "$INIT" "$WORK/skill-link/tmp-symlink-guard-$$" 测试
assert "符号链接防呆未留下目录" test ! -e "$SKILL_DIR/tmp-symlink-guard-$$"
assert_fail "拒绝代码目录 .. 逃逸" bash "$INIT" "$WORK/escape" 测试 --code ../outside
assert "路径逃逸未创建目标" test ! -e "$WORK/escape"
assert_fail "拒绝代码目录绝对路径" bash "$INIT" "$WORK/absolute" 测试 --code /tmp/outside
assert_fail "拒绝未知选项" bash "$INIT" "$WORK/unknown" 测试 --unknown
mkdir -p "$WORK/existing/backend" "$WORK/v2"
echo keep > "$WORK/existing/backend/keep"
assert_fail "已有代码目录不被接管" bash "$INIT" "$WORK/existing" 测试 --code backend
assert "已有代码目录内容不变" grep -q keep "$WORK/existing/backend/keep"
echo "我自己的内容" > "$WORK/v2/STATUS.md"
bash "$INIT" "$WORK/v2" 测试 >/dev/null 2>&1
assert "已有文件不被覆盖" grep -q "我自己的内容" "$WORK/v2/STATUS.md"
S="$WORK/single"
bash "$INIT" "$S" 单分支 --git --branch single >/dev/null 2>&1
assert "single 当前在 main" bash -c "[ \$(git -C '$S' branch --show-current) = main ]"
assert "single 不创建 feat/next" bash -c "! git -C '$S' show-ref --verify --quiet refs/heads/feat/next"
PRE="$WORK/preinit"
mkdir -p "$PRE"
git -C "$PRE" init -q
bash "$INIT" "$PRE" 预初始仓库 --git >/dev/null 2>&1
assert "已有空 git 仓完成首次提交" git -C "$PRE" rev-parse --verify HEAD
assert "已有空 git 仓规范为 main＋feat/next" bash -c "git -C '$PRE' show-ref --verify --quiet refs/heads/main && [ \$(git -C '$PRE' branch --show-current) = feat/next ]"
mkdir -p "$WORK/fakebin"
REAL_GIT="$(command -v git)"
printf '#!/usr/bin/env bash\nfor a in "$@"; do [ "$a" != commit ] || { echo "forced commit failure" >&2; exit 1; }; done\nexec "%s" "$@"\n' "$REAL_GIT" > "$WORK/fakebin/git"
chmod +x "$WORK/fakebin/git"
assert_fail "首次提交失败向调用者返回失败" env PATH="$WORK/fakebin:$PATH" bash "$INIT" "$WORK/commit-fail" 测试 --git
assert "提交失败不伪装完成分支" test ! -e "$WORK/commit-fail/.git/refs/heads/feat/next"

echo "═══ 3. 取号与并发锁 ═══"
assert_out "取号 F1" "F1" bash "$V/scripts/next-id.sh" F
assert_out "取号 F2" "F2" bash "$V/scripts/next-id.sh" F
assert_out "取号 Q1" "Q1" bash "$V/scripts/next-id.sh" Q
assert "REGISTRY 上界同步" grep -q "^F: 2" "$V/REGISTRY.md"
assert_fail "非法前缀被拒绝" bash "$V/scripts/next-id.sh" 'Q|R'
assert_fail "额外参数被拒绝" bash "$V/scripts/next-id.sh" Q extra
mkdir "$V/REGISTRY.md.lock"
assert_fail "锁存在时取号失败" bash "$V/scripts/next-id.sh" Q
assert "失败后锁保留待人工确认" test -d "$V/REGISTRY.md.lock"
rmdir "$V/REGISTRY.md.lock"

echo "═══ 4. 链接解析与剪枝 ═══"
L="$WORK/links"
bash "$INIT" "$L" 链接测试 >/dev/null 2>&1
assert "新库无断链" bash "$L/scripts/check-links.sh"
touch "$L/20_方案/目标 文件.md" "$L/20_方案/括号(终).md" "$L/20_方案/井#号.md"
cat >> "$L/STATUS.md" <<'EOF'
[空格](20_方案/目标%20文件.md) [尖括号](<20_方案/目标 文件.md>)
[括号](20_方案/括号(终).md) [井号](20_方案/井%23号.md) [外部协议](obsidian://open)
`[行内示例](不存在.md)`
```markdown
[围栏示例](不存在.md)
```
EOF
assert "编码空格/尖括号/括号/井号/外部协议通过" bash "$L/scripts/check-links.sh"
echo "[坏](不存在的.md)" > "$L/20_方案/bad.md"
assert_fail "断链能被抓出" bash "$L/scripts/check-links.sh"
echo "[绝对](/tmp/nope.md)" > "$L/20_方案/bad.md"
assert_fail "绝对路径被抓出" bash "$L/scripts/check-links.sh"
echo "[[wiki]]" > "$L/20_方案/bad.md"
assert_out "wikilink 给明确警告" "wikilink" bash "$L/scripts/check-links.sh"
rm "$L/20_方案/bad.md"
mkdir -p "$L/code"
git -C "$L/code" init -q
printf '[[wiki]] [断](无.md)\n' > "$L/code/README.md"
assert "嵌套代码仓不被扫描" bash "$L/scripts/check-links.sh"

echo "═══ 5. 编号对账与边界 ═══"
R="$WORK/registry"
bash "$INIT" "$R" 对账测试 >/dev/null 2>&1
bash "$R/scripts/next-id.sh" Q >/dev/null
bash "$R/scripts/next-id.sh" Q >/dev/null
printf '| Q1 | - | 问题1 | - | 开放 | - |\n| Q2 | - | 问题2 | - | 开放 | - |\n' >> "$R/40_推进/待确认问题清单.md"
echo "AD99 与 Q1A 不是编号；真实引用 Q1" >> "$R/STATUS.md"
assert "字母数字边界不会误报" bash "$R/scripts/check-registry.sh"
assert_out "死编号 Q2 给警告" "Q2" bash "$R/scripts/check-registry.sh"
echo "详见 Q9" >> "$R/STATUS.md"
assert_fail "悬空引用 Q9 被抓出" bash "$R/scripts/check-registry.sh"
mv "$R/40_推进/待确认问题清单.md" "$R/40_推进/问题 清单.md"
sed -i.bak 's|40_推进/待确认问题清单.md|40_推进/问题 清单.md|' "$R/REGISTRY.md" && rm "$R/REGISTRY.md.bak"
assert_not_out "含空格归口路径可解析" "归口文件不存在" bash -c "bash '$R/scripts/check-registry.sh' 2>&1 || true"
sed -i.bak '$d' "$R/STATUS.md" && rm "$R/STATUS.md.bak"
assert "修复悬空后含空格路径通过对账" bash "$R/scripts/check-registry.sh"

echo "═══ 6. 知识日志与工程日志归档 ═══"
A="$WORK/archive"
bash "$INIT" "$A" 归档测试 >/dev/null 2>&1
for i in $(seq 1 60); do echo "- 2026-10-27 第 $i 条" >> "$A/CHANGELOG.md"; done
bash "$A/scripts/archive-changelog.sh" >/dev/null 2>&1
assert "CHANGELOG 保留头2+50条" bash -c "[ \$(wc -l < '$A/CHANGELOG.md' | tr -d ' ') = 52 ]"
assert "归档文件第3行是真实条目" bash -c "head -3 '$A/99_附件/历史/'CHANGELOG-归档-*.md | tail -1 | grep -q '^- '"
assert_fail "非法归档阈值被拒绝" bash "$A/scripts/archive-changelog.sh" 0
printf '# CHANGELOG · 旧库\n> 固定头\n\n- 旧条目1\n' > "$A/CHANGELOG.md"
for i in $(seq 2 61); do echo "- 旧条目$i" >> "$A/CHANGELOG.md"; done
assert_out "旧格式自动规范化并警告" "旧格式" bash "$A/scripts/archive-changelog.sh"
PLOG="$V/backend/进度记录.md"
assert_out "工程日志未超阈值可空跑" "无需归档" bash "$V/backend/scripts/archive-progress.sh"
for i in $(seq 1 60); do echo "- 2026-10-27 工程第 $i 条 ｜AI" >> "$PLOG.tmp"; done
awk -v insert="$PLOG.tmp" '/<!-- PROGRESS_LOG:END -->/ { while ((getline line < insert) > 0) print line; close(insert) } { print }' "$PLOG" > "$PLOG.new" && mv "$PLOG.new" "$PLOG" && rm -f "$PLOG.tmp"
bash "$V/backend/scripts/archive-progress.sh" >/dev/null 2>&1
assert "工程日志保留50条" bash -c "[ \$(sed -n '/PROGRESS_LOG:START/,/PROGRESS_LOG:END/p' '$PLOG' | grep -c '^- ') = 50 ]"
assert "工程顶部接续提示保留" grep -q "新会话接续提示" "$PLOG"
assert "工程归档文件已生成" bash -c "ls '$V/backend/docs/进度历史/'进度记录-归档-*.md >/dev/null"
awk '{ if ($0 == "<!-- PROGRESS_LOG:END -->") print "这不是单行日志"; print }' "$PLOG" > "$PLOG.new" && mv "$PLOG.new" "$PLOG"
assert_fail "多行日志拒绝被强行截断" bash "$V/backend/scripts/archive-progress.sh" 1

echo "═══ 7. 私密信息遮蔽与路径安全 ═══"
printf '密码：dummy-secret\n- 令牌：dummy-token\n| 密码 | dummy-table |\n' > "$V/本地信息/信息模板.md"
assert_not_out "顶格值被遮蔽" "dummy-secret" bash "$V/scripts/private.sh" view 信息模板.md
assert_not_out "列表值被遮蔽" "dummy-token" bash "$V/scripts/private.sh" view 信息模板.md
assert_not_out "表格值被遮蔽" "dummy-table" bash "$V/scripts/private.sh" view 信息模板.md
assert "特殊字符标签可追加" bash "$V/scripts/private.sh" add 信息模板.md '新[标签]'
assert "特殊字符标签可改名" bash "$V/scripts/private.sh" rename 信息模板.md '新[标签]' '改(标签)'
assert "特殊字符标签可删除" bash "$V/scripts/private.sh" rm 信息模板.md '改(标签)'
assert_fail "拒绝相对路径逃逸" bash "$V/scripts/private.sh" view ../STATUS.md
assert_fail "拒绝绝对路径" bash "$V/scripts/private.sh" view /tmp/secret
ln -s "$V/STATUS.md" "$V/本地信息/link.md"
assert_fail "拒绝符号链接文件" bash "$V/scripts/private.sh" view link.md
assert "本地信息默认被 git 忽略" git -C "$V" check-ignore 本地信息/信息模板.md

echo "═══ 8. pre-commit 暂存内容与分支门禁 ═══"
C="$WORK/commit"
bash "$INIT" "$C" 门禁测试 --git >/dev/null 2>&1
printf '%s\n' '-----BEGIN PRIVATE KEY-----' 'x' > "$C/leak.md"
git -C "$C" add leak.md
echo safe > "$C/leak.md"
assert_fail "工作区改安全也掩不住暂存私钥" git -C "$C" commit -q -m x
git -C "$C" reset -q; rm -f "$C/leak.md"
echo safe > "$C/safe.md"; git -C "$C" add safe.md
printf '%s\n' '-----BEGIN PRIVATE KEY-----' > "$C/safe.md"
assert "工作区新秘密不污染安全暂存 blob" git -C "$C" commit -q -m safe
git -C "$C" checkout safe.md
printf 'TOKEN=x\n' > "$C/.env"; git -C "$C" add -f .env
assert_fail "强制暂存敏感文件也被拦" git -C "$C" commit -q -m env
git -C "$C" reset -q; rm -f "$C/.env"
echo "[断](无.md)" >> "$C/STATUS.md"; git -C "$C" add STATUS.md
assert_fail "断链提交被拦" git -C "$C" commit -q -m x
git -C "$C" reset -q; git -C "$C" checkout STATUS.md
echo "- 2026-10-27 正常一行 ｜AI" >> "$C/CHANGELOG.md"; git -C "$C" add CHANGELOG.md
assert "正常提交通过门禁" git -C "$C" commit -q -m ok
git -C "$C" switch -q main
echo "- 2026-10-27 main 直改 ｜AI" >> "$C/CHANGELOG.md"; git -C "$C" add CHANGELOG.md
assert_fail "dual 禁止直接提交 main" git -C "$C" commit -q -m main-direct
git -C "$C" reset -q; git -C "$C" checkout CHANGELOG.md; git -C "$C" switch -q feat/next

echo "═══ 9. 快照与本地远端发布 ═══"
echo "- 2026-10-27 待快照 ｜AI" >> "$C/CHANGELOG.md"
assert_out "有变化时先校验再快照" "已提交" bash "$C/scripts/snapshot.sh"
assert "快照提交带前缀" bash -c "git -C '$C' log -1 --format=%s | grep -q '^快照:'"
assert_out "干净工作区零动作" "无需快照" bash "$C/scripts/snapshot.sh"
git -C "$C" switch -q main
assert_fail "dual 禁止在 main 快照" bash "$C/scripts/snapshot.sh"
git -C "$C" switch -q feat/next
git init -q --bare "$WORK/origin.git"
git -C "$C" remote add origin "$WORK/origin.git"
git -C "$C" push -q -u origin main feat/next
echo "- 2026-10-27 待发布 ｜AI" >> "$C/CHANGELOG.md"
bash "$C/scripts/snapshot.sh" --push >/dev/null
assert_fail "发布需要明确确认" bash "$C/scripts/publish.sh"
assert_out "dual 发布成功" "发布完成" env PROJECT_VAULT_PUBLISH_CONFIRM=1 bash "$C/scripts/publish.sh"
assert "发布后两分支一致" bash -c "[ \$(git -C '$C' rev-parse main) = \$(git -C '$C' rev-parse feat/next) ]"
assert "发布后本地与远端一致" bash -c "[ \$(git -C '$C' rev-parse feat/next) = \$(git -C '$C' rev-parse origin/feat/next) ]"
assert "发布后当前回到 feat/next" bash -c "[ \$(git -C '$C' branch --show-current) = feat/next ]"

echo "═══ 10. 单分支克隆发布与 doctor ═══"
git clone -q --branch feat/next --single-branch "$WORK/origin.git" "$WORK/clone"
assert "克隆初始没有本地 main" bash -c "! git -C '$WORK/clone' show-ref --verify --quiet refs/heads/main"
echo "- 2026-10-27 单分支克隆发布 ｜AI" >> "$WORK/clone/CHANGELOG.md"
assert_fail "克隆未装钩子时快照被阻止" bash "$WORK/clone/scripts/snapshot.sh"
bash "$WORK/clone/scripts/install-hooks.sh" >/dev/null
bash "$WORK/clone/scripts/snapshot.sh" --push >/dev/null
assert_out "单分支克隆可建立 main 并发布" "发布完成" env PROJECT_VAULT_PUBLISH_CONFIRM=1 bash "$WORK/clone/scripts/publish.sh"
assert "单分支克隆发布后分支一致" bash -c "[ \$(git -C '$WORK/clone' rev-parse main) = \$(git -C '$WORK/clone' rev-parse feat/next) ]"
D="$WORK/doctor"
bash "$INIT" "$D" 体检 --git >/dev/null 2>&1
rm "$D/10_需求/功能需求清单.md"
assert_fail "缺少 F 归口被 doctor 抓出" bash "$D/scripts/doctor.sh"
git -C "$D" checkout 10_需求/功能需求清单.md
printf 'TOKEN=x\n' > "$D/.env"; git -C "$D" add -f .env
assert_fail "已跟踪敏感文件被 doctor 抓出" bash "$D/scripts/doctor.sh"
git -C "$D" reset -q; rm -f "$D/.env"
assert "修复后 doctor 通过" bash "$D/scripts/doctor.sh"

printf '\n'
if [ "$FAILS" -gt 0 ]; then
  echo "❌ ${FAILS} 项失败"
  exit 1
else
  echo "✅ 全部通过"
fi
