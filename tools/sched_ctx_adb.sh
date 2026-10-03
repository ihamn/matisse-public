#!/usr/bin/env bash
# [DEPRECATED] 引号坑: 外层双引号会让 $i 提前展开; 已被 tools/sched_probe_device.sh 取代, 勿用
# sched_ctx_adb.sh - 零内核写入: 对比 adb 侧起进程的调度上下文 (笔记本上跑)
# 用法: bash sched_ctx_adb.sh
set -u
echo '==== 1) adb 侧 sleep 的 cgroup/调度上下文 ===='
adb shell 'setsid sh -c "exec sleep 300" >/dev/null 2>&1 & sleep 1; for p in $(pgrep -x sleep); do echo "-- adb sleep pid=$p"; cat /proc/$p/cgroup; grep -E "Cpus_allowed_list|Mems_allowed_list" /proc/$p/status; grep -E "uclamp|se.avg" /proc/$p/sched | head -8; done'
echo
echo '==== 2) 父进程(adbd / shizuku_server) 的 cgroup ===='
adb shell 'for n in adbd shizuku_server; do p=$(pidof $n 2>/dev/null | cut -d" " -f1); [ -n "$p" ] && { echo "-- $n pid=$p"; cat /proc/$p/cgroup; }; done'
echo
echo '==== 3) 唤醒延迟微基准 (200 x sleep 0.001, 秒) ===='
adb shell 'time sh -c "i=0; while [ $i -lt 200 ]; do sleep 0.001; i=$((i+1)); done" 2>&1 | tail -3'
echo
echo '==== 4) 清理 ===='
adb shell 'pkill -f "sleep 300" 2>/dev/null; echo cleaned'
