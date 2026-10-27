# AGENTS.md · 个人 skills 总仓库

> AI 会话进入本仓库的第一入口。这里存放用户的个人 AI 技能（skill），每个 skill 一个子目录。
> 建账 2026-10-19 ｜ 真身即本目录；`~/.agents/skills/` 只是部署位。

## 一、结构约定

- 一个 skill = 一个子目录（如 `project-vault/`），自包含（SKILL.md＋templates＋scripts）。
- 所有 skill 共用本仓库一本账，不各自建 git。
- **开发目录是唯一真身**：改只改这里；安装位（`~/.agents/skills/`）由同步脚本覆盖，不手改。

## 二、改动工作流

1. 改 skill 内容
2. 跑该 skill 的自测（如 `bash project-vault/scripts/selftest.sh`）
3. 同步安装位（如 `bash project-vault/scripts/sync-install.sh`）
4. 提交（走下面的 PR 流程）

## 三、PR 流程（用户说「PR」＝固定流程，不用再问）

1. 有未提交改动先在当前开发分支 commit、push
2. 给出 PR 描述（标题＋改了什么＋自测结果），Markdown 代码块整块给出，供用户粘进 GitHub
3. 用户在 GitHub 网页合并到 main，说「合并了」
4. 切回 main、`git pull` 校验（合并提交进来＋与远端一致）
5. 从最新 main 新建开发分支（默认 `feat/next`）并切过去，后续开发都在新分支
6. 顺手清理：删已合并的旧分支（本地与远端）——远端删除用 `git push origin --delete <分支>`，**必须 `git ls-remote --heads origin` 验证真的没了**再重建推送（教训 2026-10-19：删除命令失败被快进推送掩盖，远端旧分支实际存活，被用户发现）

铁律：**main 上不直接开发**；动手改内容前先确认当前在开发分支上。

## 四、远端

- GitHub 私有仓（地址见 git remote -v；建仓 2026-10-19）
- 推送随 PR 流程走；不自动推，用户说推才推

## 变更记录

| 日期 | 变更内容 | 操作人 |
|---|---|---|
| 2026-10-19 | 建账：project-vault v1.7 入库；确立真身/部署分离与 PR 流程（用户定） | AI · 用户拍板 |
