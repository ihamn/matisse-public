#!/usr/bin/env bash
# round_proc_sampler.sh - 开火轮中的消费者线程状态采样器 (零内核写入, 只读 /proc)
# 目的: 区分「消费者被饿死(假设A)」vs「sched_setattr 内核里卡住(假设B)」
# 用法(设备/shell域):  sh round_proc_sampler.sh <输出文件> [总采样秒数]
#   建议开火前 1 秒启动, 它自己等 exploit 进程出现并采样到进程退出
set -u
OUT=${1:-/data/local/tmp/round_proc_timeline.txt}
DUR=${2:-40}
: > "$OUT"
N=$(( DUR * 10 ))
PID=""
for i in $(seq 1 $N); do
  if [ -z "$PID" ] || [ ! -d /proc/$PID ]; then
    PID=$(pgrep -f 'sleep 180' 2>/dev/null | head -1)
    [ -n "$PID" ] && echo "#$(date +%s%3N) found exploit pid=$PID" >> "$OUT"
  fi
  if [ -n "$PID" ] && [ -d /proc/$PID ]; then
    TS=$(date +%s%3N)
    for t in /proc/$PID/task/*; do
      [ -d "$t" ] || continue
      TID=$(basename "$t")
      ST=$(awk '{print $3}' "$t/stat" 2>/dev/null)
      WC=$(cat "$t/wchan" 2>/dev/null)
      SW=$(grep -m1 nr_switches "$t/sched" 2>/dev/null | tr -s ' ' | cut -d: -f2 | tr -d ' ')
      echo "$TS pid=$PID tid=$TID state=$ST wchan=$WC nrs=$SW" >> "$OUT"
    done
  fi
  sleep 0.1
done
echo "# done, lines=$(wc -l < \"$OUT\")" >> "$OUT"
