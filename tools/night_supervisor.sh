#!/usr/bin/env bash
# night_supervisor.sh — 夜跑监督者: 无论内层循环因何退出, 都自动拉起, 直到真的成功。
#
# 为什么需要 (2026-10-03 01:05 夜跑 BUG#4): 内层 tools/loop_single_rounds.sh 曾因
# 「设备重启中读不到 boot_id」被误判成 load 门拒而 exit(已修), 但教训是: 无人值守时
# **任何一次意外退出都等于整夜结束**。所以外面再套一层: 退出即重启, 只在「已成功」时停。
#
# 成功判据 (与内层一致, 直接问设备, 不看退出码):
#   /proc/modules 出现 ksu|kernelsu  -> 成功
#   root_alive.txt 非空 或 某 sleep 进程 /proc/<pid>/status 的 Uid 全 0 -> 拿到 root, 也停
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO" || exit 1
ADB="${ADB:-$REPO/platform-tools_r33.0.2-windows/platform-tools/adb.exe}"
export ANDROID_ADB_LOG_PATH="$REPO/.adb/adb.log"
say(){ printf '[super %s] %s\n' "$(date +%H:%M:%S)" "$*"; }

succeeded(){ # 0=已成功/已拿到 root
  local km ra u0
  km=$("$ADB" shell "grep -cE '^(ksu|kernelsu)' /proc/modules" 2>/dev/null | tr -dc '0-9'); km=${km:-0}
  [ "$km" -ge 1 ] && { say "检测到 ksu 模块 ($km 条) — 成功"; return 0; }
  ra=$("$ADB" shell "cat /data/local/tmp/root_alive.txt 2>/dev/null | head -1" 2>/dev/null | tr -d '\r')
  [ -n "$ra" ] && { say "检测到 root_alive=[$ra] — 拿到 root"; return 0; }
  u0=$("$ADB" shell "for p in \$(pgrep -x sleep); do awk '\$1==\"Uid:\" && \$2==0 && \$3==0 {print \"HIT \" FILENAME}' /proc/\$p/status 2>/dev/null; done" 2>/dev/null | tr -d '\r')
  [ -n "$u0" ] && { say "检测到 /proc Uid=0 ($u0) — 拿到 root"; return 0; }
  return 1
}

n=0
while :; do
  n=$((n+1))
  say "第 $n 次拉起内层循环 (MAX_ATTEMPTS=$MAX_ATTEMPTS RROUNDS=$RROUNDS SETTLE=$SETTLE)"
  START=$(date +%s)
  MAX_ATTEMPTS="${MAX_ATTEMPTS:-9999}" SETTLE="${SETTLE:-120}" LOADMAX="${LOADMAX:-20}" \
    RROUNDS="${RROUNDS:-2}" SPACING_R="${SPACING_R:-150}" \
    MATISSE_CBUDGET="${MATISSE_CBUDGET:-5}" MATISSE_CGAP="${MATISSE_CGAP:-15}" \
    MATISSE_R_DRAIN="${MATISSE_R_DRAIN:-260}" MATISSE_NO_GIT="${MATISSE_NO_GIT:-1}" \
    bash tools/loop_single_rounds.sh
  rc=$?
  ELAPSED=$(( $(date +%s) - START ))
  say "内层循环退出 rc=$rc (存活 ${ELAPSED}s)"
  sleep 15
  if succeeded; then say "已成功 — 监督者停止, 不再拉起 (等人工接手)"; exit 0; fi
  # v2 (2026-10-03 02:48 审计): 防"热循环" —— 若内层循环因**持续性错误**秒退(例如 adb/设备
  # 长时间不可用), 原先会每 20 秒反复拉起, 刷屏且毫无意义。连续 3 次存活 <60s 就退避 5 分钟。
  if [ "$ELAPSED" -lt 60 ]; then
    FAST=$(( ${FAST:-0} + 1 ))
    if [ "$FAST" -ge 3 ]; then
      say "!! 内层循环连续 $FAST 次在 60s 内退出 (疑似持续性错误) — 退避 300s 后再试"
      sleep 300; FAST=0; continue
    fi
  else
    FAST=0
  fi
  say "未成功 — 20s 后自动拉起 (无人值守保护)"
  sleep 20
done
