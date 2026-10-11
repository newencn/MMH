#!/usr/bin/env bash
#
# 把本地定制分支同步到上游最新基线。
#
# ── 为什么需要它 ──
#
# MMH 上游开发非常快（2026-09 有 244 个提交，2026-10 前 9 天就有 82 个）。
# 攒着不 rebase 会让冲突数量指数上升，所以必须**频繁**同步。
#
# ── 分支模型 ──
#
#   main                    ← 永远干净，只跟随 upstream/main（只做 --ff-only）
#     └─ feat/budget-calendar   ← 我们的定制，长期存在
#
# 冲突全部落在定制分支上，main 永远不会有冲突 —— 这就是 main 必须保持干净的原因。
#
# 用法：
#   bash scripts/sync-upstream.sh                    # 同步默认分支
#   bash scripts/sync-upstream.sh feat/xxx           # 同步指定分支
#   DRY_RUN=1 bash scripts/sync-upstream.sh          # 只看会同步到什么
#
set -euo pipefail

BRANCH="${1:-feat/budget-calendar}"
UPSTREAM_REMOTE="${UPSTREAM_REMOTE:-upstream}"
UPSTREAM_BRANCH="${UPSTREAM_BRANCH:-main}"
DRY_RUN="${DRY_RUN:-0}"

cd "$(dirname "$0")/.."

say() { printf '\033[36m▸ %s\033[0m\n' "$1"; }
ok()  { printf '\033[32m✅ %s\033[0m\n' "$1"; }
warn(){ printf '\033[33m⚠️  %s\033[0m\n' "$1"; }
die() { printf '\033[31m❌ %s\033[0m\n' "$1" >&2; exit 1; }

# ── 前置检查 ───────────────────────────────────────────────
[ -d .git ] || die "当前目录不是 git 仓库"
git remote get-url "$UPSTREAM_REMOTE" >/dev/null 2>&1 \
  || die "未配置 remote「$UPSTREAM_REMOTE」。执行：git remote add $UPSTREAM_REMOTE https://github.com/frankluise5220/MMH.git"
[ -f .git/shallow ] && die "这是浅克隆，rebase 会失败。先执行：git fetch --unshallow $UPSTREAM_REMOTE"

# 工作区必须干净，否则 rebase 会带着未提交改动一起动
if ! git diff-index --quiet HEAD -- 2>/dev/null; then
  die "工作区有未提交改动，请先 commit 或 stash"
fi

ORIGINAL_BRANCH="$(git rev-parse --abbrev-ref HEAD)"

say "1/4 拉取上游 ($UPSTREAM_REMOTE/$UPSTREAM_BRANCH)"
git fetch "$UPSTREAM_REMOTE" --tags
NEW_HEAD="$(git rev-parse --short "$UPSTREAM_REMOTE/$UPSTREAM_BRANCH")"

if [ "$DRY_RUN" = "1" ]; then
  say "DRY RUN：上游最新为 $NEW_HEAD"
  git log --oneline -5 "$UPSTREAM_REMOTE/$UPSTREAM_BRANCH" | sed 's/^/    /'
  echo
  say "我们的分支 $BRANCH 落后上游 $(git rev-list --count "$BRANCH..$UPSTREAM_REMOTE/$UPSTREAM_BRANCH" 2>/dev/null || echo '?') 个提交"
  exit 0
fi

say "2/4 快进 main（--ff-only，有分叉就报错而不是悄悄合并）"
git checkout main
if ! git merge --ff-only "$UPSTREAM_REMOTE/$UPSTREAM_BRANCH"; then
  git checkout "$ORIGINAL_BRANCH"
  die "main 与上游分叉了！说明有人往 main 提交过东西。请检查后手动处理。"
fi
ok "main 已快进到 $NEW_HEAD"

say "3/4 把 $BRANCH rebase 到新基线"
git checkout "$BRANCH"
BEHIND="$(git rev-list --count "$BRANCH..$UPSTREAM_REMOTE/$UPSTREAM_BRANCH" 2>/dev/null || echo 0)"
if [ "$BEHIND" = "0" ]; then
  ok "$BRANCH 已是最新，无需 rebase"
else
  echo "    落后 $BEHIND 个提交，开始 rebase…"
  if ! git rebase main; then
    warn "rebase 遇到冲突，已停在冲突处。"
    echo
    echo "    解决步骤："
    echo "      1. 编辑冲突文件（冲突标记 <<<<<<< ======= >>>>>>>）"
    echo "      2. git add <文件>"
    echo "      3. git rebase --continue"
    echo "    放弃本次 rebase：git rebase --abort"
    exit 1
  fi
  ok "$BRANCH 已 rebase 到 $NEW_HEAD"
fi

say "4/4 完成"
echo "    当前分支：$(git rev-parse --abbrev-ref HEAD)"
echo "    上游版本：$(git describe --tags --abbrev=0 "$UPSTREAM_REMOTE/$UPSTREAM_BRANCH" 2>/dev/null || echo '(无标签)')"
echo
warn "若已推送到自己的 fork，现在需要：git push --force-with-lease origin $BRANCH"
echo "    （定制分支可以 force-push；但给上游的 PR 分支不要这样做）"
