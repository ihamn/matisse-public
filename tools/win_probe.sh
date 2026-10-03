#!/system/bin/sh
# win_probe.sh — 成功后的只读探测（绝不写内核、绝不重启）
echo "=== 1) 模块状态 ==="
grep -E '^(ksu|kernelsu)' /proc/modules
echo "--- /sys/module/kernelsu ---"
ls -d /sys/module/kernelsu 2>/dev/null && echo "sysfs 节点存在 ✓"
cat /sys/module/kernelsu/version 2>/dev/null || true
echo "=== 2) KSU 的目录与 root 入口 ==="
ls -la /data/adb/ksu/ 2>&1 | head -10
echo "--- bin ---"
ls -la /data/adb/ksu/bin/ 2>&1 | head -10
echo "=== 3) 逐个探测 su/ksu 可执行文件 ==="
for f in /data/adb/ksu/bin/su /data/adb/ksu/bin/ksu /system/bin/su /debug_ramdisk/su /data/adb/ksud; do
  if [ -e "$f" ]; then
    echo "$f : 存在 -> $(ls -la "$f" | awk '{print $1, $3, $5}')"
  else
    echo "$f : 不存在"
  fi
done
echo "=== 4) 尝试用 KSU 的 root 通道（只读 id）==="
for f in /data/adb/ksu/bin/su /data/adb/ksu/bin/ksu; do
  if [ -x "$f" ]; then
    echo "--- $f -c id ---"
    "$f" -c id 2>&1 | head -3
  fi
done
echo "=== 5) 当前 shell 身份（对照）==="
id
echo "=== 6) 设备状态 ==="
cat /proc/sys/kernel/random/boot_id | cut -c1-8
cat /proc/uptime | cut -d. -f1
getenforce
uname -n
echo "=== done ==="
