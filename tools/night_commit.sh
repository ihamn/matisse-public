#!/usr/bin/env bash
# night_commit.sh — 夜跑证据归档 + 精选提交（配合 ksu_persist.sh 的 MATISSE_NO_GIT=1）
#
# 背景 (2026-10-03 01:03 夜跑审计):
#   脚本每轮会产出 ~1-5MB 的原始 .out (R1_raw.out / C*_raw.out ...)。若每轮都推 gitee,
#   一夜会灌几十~几百 MB 且每轮变慢。本脚本只保留:
#     - 每个 ksu_hunt_* 目录的 CARD.md (判据卡, 小)
#     - 顶层 ksu_console_*.log (每轮完整控制台, 中等; 是判据/时序的唯一文字记录)
#     - **有 R 落地 / C 开枪 / root 证据**的目录的全部 *_raw.out (这些是稀有的关键样本)
#     - 最近 KEEP_DIRS 个目录的 *_raw.out (兜底)
#   其余大文件删除后提交推送。任何一轮若疑似拿到 root, 该目录永不裁剪。
set -u
cd "$(dirname "$0")/.." || exit 1
KEEP_DIRS=${KEEP_DIRS:-6}
PRUNE=${PRUNE:-1}

mapfile -t DIRS < <(ls -1dt logs_raw/ksu_hunt_* 2>/dev/null || true)
kept=0; pruned=0
for i in "${!DIRS[@]}"; do
  d="${DIRS[$i]}"; [ -d "$d" ] || continue
  keep=0
  [ "$i" -lt "$KEEP_DIRS" ] && keep=1
  if grep -qlE 'R_LANDED|mid-burst landing|C 落地|ROOT-ALIVE|Uid:[[:space:]]*0|C 击|开火 C' "$d"/*.out "$d"/CARD.md 2>/dev/null; then keep=1; fi
  if [ "$keep" = "0" ] && [ "$PRUNE" = "1" ]; then
    n=$(find "$d" -name '*_raw.out' 2>/dev/null | wc -l | tr -d ' ')
    find "$d" -name '*_raw.out' -delete 2>/dev/null
    pruned=$((pruned+n))
  else
    kept=$((kept+1))
  fi
done
sz=$(du -sh logs_raw 2>/dev/null | cut -f1)
echo "[night_commit] 目录 $((${#DIRS[@]})) 个: 保留 $kept, 裁剪 $pruned 个 .out / logs_raw 现 $sz"

git add -A >/dev/null 2>&1
git commit -q -m "night archive $(date '+%m-%d %H:%M'): 保留 CARD+console+关键 .out, 裁剪 $pruned 个原始 .out (logs_raw=$sz)" || echo "[night_commit] 无变更"
for i in 1 2 3; do
  git pull -q --rebase origin master 2>/dev/null
  if git push -q origin master 2>/dev/null; then echo "[night_commit] 已推送"; exit 0; fi
  sleep 5
done
echo "[night_commit] !! 推送失败（可能离线），证据仍在本地"
