#!/system/bin/sh
# sched_probe_device.sh — 在**手机侧**运行，比较「起进程的路径」带来的调度上下文差异。
# 零内核写入：只读 /proc 与 cgroup 文件；只起一个 sleep 300 子进程并在结束时清掉。
# 用法（两条路径跑同一个文件，结果才可比）：
#   adb shell sh /data/local/tmp/sched_probe_device.sh            # adb 路径
#   ./rish -c 'sh /data/local/tmp/sched_probe_device.sh'          # rish 路径（Termux 内）
# 注意: 微基准的 $i 必须用单引号保护, 否则被外层 shell 提前展开成空 (ASK2 脚本的坑)。

echo "==== A. 探针自身 ===="
echo "pid=$$ uid=$(id -u) domain=$(cat /proc/self/attr/current 2>/dev/null)"
echo "-- cgroup --"; cat /proc/self/cgroup 2>/dev/null
echo "-- 允许的 CPU/内存 --"; grep -E "Cpus_allowed_list|Mems_allowed_list" /proc/self/status 2>/dev/null
echo "-- 调度: 优先级/nice/policy --"
awk '{print "priority=" $18 " nice=" $19 " num_threads=" $20 " rt_priority=" $39 " policy=" $41}' /proc/self/stat 2>/dev/null
echo "-- sched 统计 --"; grep -E "se.avg.(load_avg|util_avg|runnable_avg)|nr_switches|wait_sum|iowait_sum" /proc/self/sched 2>/dev/null | head -8
echo "-- uclamp (若内核暴露) --"; grep -i uclamp /proc/self/sched 2>/dev/null | head -4

echo
echo "==== B. 父进程链 ===="
P=$$; i=0
while [ "$i" -lt 6 ]; do
  PP=$(awk '{print $4}' /proc/$P/stat 2>/dev/null)
  [ -z "$PP" ] && break
  NM=$(cat /proc/$PP/comm 2>/dev/null)
  CG=$(tr '\n' ' ' < /proc/$PP/cgroup 2>/dev/null)
  echo "  ppid=$PP comm=$NM cgroup=$CG"
  [ "$PP" = "1" ] && break
  P=$PP; i=$((i+1))
done

echo
echo "==== C. 子进程 (sleep 300) 的上下文 ===="
setsid sh -c 'exec sleep 300' >/dev/null 2>&1 &
sleep 1
for p in $(pgrep -x sleep 2>/dev/null); do
  CL=$(tr '\0' ' ' < /proc/$p/cmdline 2>/dev/null)
  case "$CL" in *sleep*300*) ;; *) continue ;; esac
  echo "-- sleep pid=$p cmdline=[$CL]"
  cat /proc/$p/cgroup 2>/dev/null
  grep -E "Cpus_allowed_list|Mems_allowed_list" /proc/$p/status 2>/dev/null
  awk '{print "  priority=" $18 " nice=" $19 " policy=" $41}' /proc/$p/stat 2>/dev/null
  grep -E "se.avg.load_avg|se.avg.util_avg" /proc/$p/sched 2>/dev/null
done

echo
echo "==== D. cgroup 权重/uclamp 文件 ===="
U=$(awk -F: '/^0::/{print $3}' /proc/self/cgroup 2>/dev/null)
echo "  unified cgroup 路径: [$U]"
for D in "/sys/fs/cgroup$U" "/sys/fs/cgroup"; do
  echo "-- $D"
  for f in cpu.weight cpu.max cpu.uclamp.min cpu.uclamp.max cpuset.cpus cpuset.cpus.effective; do
    [ -f "$D/$f" ] && echo "   $f = $(cat $D/$f 2>/dev/null)"
  done
done

echo
echo "==== E. 唤醒延迟微基准: 2000 x sleep 0.001 (用 /proc/uptime, 10ms 分辨率) ===="
S=$(cut -d' ' -f1 /proc/uptime)
sh -c 'i=0; while [ "$i" -lt 2000 ]; do sleep 0.001; i=$((i+1)); done'
E=$(cut -d' ' -f1 /proc/uptime)
awk -v s="$S" -v e="$E" 'BEGIN{printf "  2000 次 sleep 0.001 用时: %.0f ms (基线 2000ms, 差值=调度/唤醒开销)\n", (e-s)*1000}'

echo
echo "==== F. 清理 ===="
pkill -f "sleep 300" 2>/dev/null
echo "  cleaned: $(pgrep -x sleep 2>/dev/null | wc -l) sleep 残留"
