#!/usr/bin/env bash
# night_commit.sh — 夜跑证据【本地】裁剪（公开版: 不提交、不推送）
#
# 作用: 每轮产出 ~1-5MB 原始 .out 会迅速占满磁盘, 本脚本只保留:
#   - 每个 ksu_hunt_* 目录的 CARD.md (判据卡, 小)
#   - 顶层 ksu_console_*.log (每轮完整控制台, 是判据/时序的唯一文字记录)
#   - 有 R 落地 / C 开枪 / root 证据的目录的全部 *_raw.out (关键样本, 永不裁剪)
#   - 最近 KEEP_DIRS 个目录的 *_raw.out (兜底)
# 其余大文件删除。**不做任何 git 操作**（公开版没有远端仓库）。
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
# 公开版: 只做本地裁剪, 不做任何 git 提交/推送。
echo "[night_commit] 本地裁剪完成 (logs_raw=$sz)"
