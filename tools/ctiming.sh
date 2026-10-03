#!/system/bin/sh
# ctiming.sh — 打印每个 C*.out 的时序判据 (由笔记本侧 push 执行, 避免 shell 引号问题)
for i in 1 2 3 4 5; do
  f=/data/local/tmp/C$i.out
  [ -f "$f" ] || continue
  echo "===== C$i ====="
  grep -aE 'mt61:|mt19b: sched attempt=0|mt19b: sched attempt=4|mt25: futex trigger 0|mt25: futex trigger 5|mt66:|mt51: mid-burst|ROOT-SEN|after setres|finit_module' "$f" 2>/dev/null | head -8
done
echo "===== 落地判据 ====="
echo -n "root_alive.txt: "; cat /data/local/tmp/root_alive.txt 2>/dev/null | head -1; echo
echo -n "ksu in /proc/modules: "; grep -cE '^(ksu|kernelsu)' /proc/modules 2>/dev/null
echo -n "child status: "; cat /data/local/tmp/mt49_child_status.txt 2>/dev/null | head -1; echo
echo -n "hostname: "; uname -n
echo "===== R 轮时序 (对照) ====="
grep -aE 'mt19b: sched attempt=0|mt51: mid-burst|mt66:' /data/local/tmp/R1.out 2>/dev/null | head -4
