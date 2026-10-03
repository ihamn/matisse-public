#!/data/data/com.termux/files/usr/bin/bash
# [DEPRECATED] 引号坑: 外层双引号会让 $i 提前展开; 已被 tools/sched_probe_device.sh 取代, 勿用
# sched_ctx_rish.sh - 零内核写入: 对比 rish(Shizuku) 侧起进程的调度上下文 (手机上跑, 需 Shizuku 在线)
set -u
cd /data/data/com.termux/files/home
echo '==== 1) rish 侧 sleep 的 cgroup/调度上下文 ===='
./rish -c 'setsid sh -c "exec sleep 300" >/dev/null 2>&1 & sleep 1; for p in $(pgrep -x sleep); do echo "-- rish sleep pid=$p"; cat /proc/$p/cgroup; grep -E "Cpus_allowed_list|Mems_allowed_list" /proc/$p/status; grep -E "uclamp|se.avg" /proc/$p/sched | head -8; done'
echo
echo '==== 2) Shizuku server 的 cgroup (用 rish 的 uid 查) ===='
./rish -c 'for p in $(pgrep -f shizuku_server); do echo "-- shizuku_server pid=$p"; cat /proc/$p/cgroup; done'
echo
echo '==== 3) 唤醒延迟微基准 (200 x sleep 0.001, 秒) ===='
./rish -c 'time sh -c "i=0; while [ $i -lt 200 ]; do sleep 0.001; i=$((i+1)); done" 2>&1 | tail -3'
echo
echo '==== 4) 清理 ===='
./rish -c 'pkill -f "sleep 300" 2>/dev/null; echo cleaned'
