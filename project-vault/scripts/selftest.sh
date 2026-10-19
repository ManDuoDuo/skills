#!/usr/bin/env bash
# selftest.sh — project-vault 回归测试（本 Skill 的 CI）
# 任何人改 scripts/ 或 templates/ 后必跑：bash scripts/selftest.sh
# 全部在 mktemp 临时目录里造库测试，不碰任何真实库。
set -uo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FAILS=0
# 测试环境的 git 身份（macOS bash 3.2 + 无全局配置的机器上，脚本内 commit 需要它）
export GIT_AUTHOR_NAME=selftest GIT_AUTHOR_EMAIL=selftest@local
export GIT_COMMITTER_NAME=selftest GIT_COMMITTER_EMAIL=selftest@local

assert() { # assert <描述> <命令...>
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "✅ ${desc}"; else echo "❌ ${desc}"; FAILS=$((FAILS+1)); fi
}
assert_out() { # assert_out <描述> <期望子串> <命令...>
  local desc="$1" want="$2"; shift 2
  local got
  got="$("$@" 2>&1)"
  if echo "$got" | grep -qF "$want"; then echo "✅ ${desc}"; else echo "❌ ${desc}（期望含: ${want}；实际: $(echo "$got" | head -2)）"; FAILS=$((FAILS+1)); fi
}
assert_fail() { # assert_fail <描述> <命令...>（期望非零退出）
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "❌ ${desc}（本应失败却成功）"; FAILS=$((FAILS+1)); else echo "✅ ${desc}"; fi
}

INIT="$SKILL_DIR/scripts/init-vault.sh"
V="$WORK/vault"

echo "═══ 1. 建库 ═══"
bash "$INIT" "$V" "R&D 终测" "带/斜杠的简介" --git --code backend >/dev/null 2>&1
assert "空目录建库成功" test -f "$V/AGENTS.md"
assert_out "简介特殊字符原样写入" "带/斜杠的简介" grep -m1 "简介" "$V/说明.md"
assert "项目名 & 原样写入" grep -q "R&D 终测" "$V/AGENTS.md"
assert "版本戳已写入" grep -q "project-vault v" "$V/AGENTS.md"
assert "占位符无残留" bash -c "! grep -rq '{{PROJECT\|{{DATE\|{{VAULT' '$V' --include='*.md'"
assert "收尾提示含备份提醒" bash -c "bash '$INIT' '$WORK/v2' 测试 2>&1 | grep -q '备份'"

echo "═══ 2. 双层 git 隔离 ═══"
assert "代码库独立 git" test -d "$V/backend/.git"
assert "外层 git 未跟踪代码库" bash -c "[ \$(git -C '$V' ls-files | grep -c backend) = 0 ]"
assert ".gitignore 排除代码库" grep -qx "backend/" "$V/.gitignore"

echo "═══ 3. 非空目录保护 ═══"
echo "我自己的内容" > "$WORK/v2/STATUS.md" 2>/dev/null || { mkdir -p "$WORK/v2"; echo "我自己的内容" > "$WORK/v2/STATUS.md"; }
bash "$INIT" "$WORK/v2" 测试 >/dev/null 2>&1
assert "已有文件不被覆盖" grep -q "我自己的内容" "$WORK/v2/STATUS.md"

echo "═══ 4. 防呆 ═══"
assert_fail "拒绝在 Skill 自身目录内建库" bash "$INIT" "$SKILL_DIR/tmp-guard-$$" 测试

echo "═══ 5. 取号与并发锁 ═══"
assert_out "取号 Q1" "Q1" bash "$V/scripts/next-id.sh" Q
assert_out "取号 Q2" "Q2" bash "$V/scripts/next-id.sh" Q
assert "REGISTRY 上界同步" grep -q "^Q: 2" "$V/REGISTRY.md"
mkdir "$V/REGISTRY.md.lock"
assert_fail "锁存在时取号失败" bash "$V/scripts/next-id.sh" Q
assert "失败后锁保留待人工确认" test -d "$V/REGISTRY.md.lock"
rmdir "$V/REGISTRY.md.lock"

echo "═══ 6. 断链校验 ═══"
assert "新库无断链" bash "$V/scripts/check-links.sh"
echo "[坏](不存在的.md)" >> "$V/STATUS.md"
assert_fail "断链能被抓出" bash "$V/scripts/check-links.sh"
git -C "$V" checkout STATUS.md 2>/dev/null || { sed -i.bak '$d' "$V/STATUS.md" && rm -f "$V/STATUS.md.bak"; }
printf '# 代码库文档\n[[wiki]] [断](无.md)\n' > "$V/backend/README.md"
assert "代码子仓库不被扫描" bash "$V/scripts/check-links.sh"

echo "═══ 7. 归档与旧格式兼容 ═══"
for i in $(seq 1 60); do echo "- 2026-10-19 第 $i 条" >> "$V/CHANGELOG.md"; done
bash "$V/scripts/archive-changelog.sh" >/dev/null 2>&1
assert "归档后保留 52 行（头2+50条）" bash -c "[ \$(wc -l < '$V/CHANGELOG.md' | tr -d ' ') = 52 ]"
assert "归档文件第 3 行是真实条目" bash -c "head -3 '$V/99_附件/历史/'CHANGELOG-归档-*.md | tail -1 | grep -q '^- '"
printf '# CHANGELOG · 旧库\n> 固定头\n\n- 旧条目1\n' > "$V/CHANGELOG.md"
for i in $(seq 2 61); do echo "- 旧条目$i" >> "$V/CHANGELOG.md"; done
assert_out "v1.0 旧格式自动规范化并警告" "旧格式" bash "$V/scripts/archive-changelog.sh"

echo "═══ 8. 编号对账 ═══"
W="$WORK/vreg"
bash "$INIT" "$W" 对账测试 >/dev/null 2>&1
assert "干净库对账通过" bash "$W/scripts/check-registry.sh"
printf '| Q1 | - | 问题1 | - | 开放 | - |\n| Q2 | - | 问题2 | - | 开放 | - |\n' >> "$W/40_推进/待确认问题清单.md"
echo "详见 Q1 与 Q9" >> "$W/STATUS.md"
assert_fail "悬空引用 Q9 被抓出" bash "$W/scripts/check-registry.sh"
assert_out "死编号 Q2 给警告" "Q2" bash "$W/scripts/check-registry.sh"
assert_out "上界漂移（上界0 < 实际Q2）被抓出" "漂移" bash "$W/scripts/check-registry.sh"

echo "═══ 9. 提交门禁（pre-commit）═══"
assert "钩子 shim 已安装且可执行" test -x "$V/.git/hooks/pre-commit"
printf '%s\n' '-----BEGIN PRIVATE KEY-----' 'x' > "$V/leak.md"
git -C "$V" add leak.md
assert_fail "含私钥提交被拦" git -C "$V" -c user.email=t@t -c user.name=t commit -q -m x
git -C "$V" reset -q; rm -f "$V/leak.md"
echo "[断](无.md)" >> "$V/STATUS.md"; git -C "$V" add STATUS.md
assert_fail "断链提交被拦" git -C "$V" -c user.email=t@t -c user.name=t commit -q -m x
git -C "$V" reset -q; git -C "$V" checkout STATUS.md
echo "- 2026-10-19 正常一行 ｜AI" >> "$V/CHANGELOG.md"; git -C "$V" add CHANGELOG.md
assert "正常提交通过门禁" git -C "$V" -c user.email=t@t -c user.name=t commit -q -m ok

echo "═══ 10. 自动快照（snapshot.sh）═══"
assert "snapshot.sh 随库拷贝" test -f "$V/scripts/snapshot.sh"
# 进场不假设干净（此前场景有归档遗留）：先测"有变化→自动快照"这条主路径
assert_out "有变化时自动快照" "快照" bash "$V/scripts/snapshot.sh"
assert "快照提交带前缀（区分正式提交）" bash -c "git -C '$V' log -1 --format=%s | grep -q '^快照:'"
assert "快照后工作区干净" bash -c "[ -z \"\$(git -C '$V' status --porcelain)\" ]"
assert_out "干净工作区零动作" "无需快照" bash "$V/scripts/snapshot.sh"

echo ""
if [ "$FAILS" -gt 0 ]; then
  echo "❌ ${FAILS} 项失败"
  exit 1
else
  echo "✅ 全部通过"
fi
