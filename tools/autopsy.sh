#!/usr/bin/env bash
# autopsy.sh — 崩溃/落地尸检：等设备回来后，把**爆炸现场**完整取回
#
# 为什么需要它（2026-10-03 用户指出）:
#   之前的封装在**设备已经掉线的那一刻**去 pull，只能抓到 36 字节的 `adb.exe: no devices`；
#   而真正有用的现场 —— exploit 写到崩溃瞬间的 stdout(`R1.out`/`C1.out`/`E5a.out`)——
#   **重启后仍在 /data/local/tmp/** 且 **shell 可读**(实测 grep C1.out 成功)。
#   pstore/dmesg/dropbox/tombstones 对 shell **全部被拒**(无 root 读不到)，所以它们是"有则抓、无则记"。
#
# 用法: bash tools/autopsy.sh [标签]
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"; cd "$REPO" || exit 1
ADB="${ADB:-$REPO/platform-tools_r33.0.2-windows/platform-tools/adb.exe}"
export ANDROID_ADB_LOG_PATH="$REPO/.adb/adb.log"
export MSYS_NO_PATHCONV=1
TMPD="${MATISSE_TMPD:-/data/local/tmp}"
TAG="${1:-$(date +%Y%m%d_%H%M%S)}"
OUT="$REPO/logs_raw/autopsy_$TAG"
# v8.37 (2026-10-03 11:42, BUG #19): MSYS_NO_PATHCONV=1 会**连本地目标路径一起禁掉转换**
#   ⇒ db pull <dev> /c/Users/... 写不出文件 ⇒ 证据目录永远是空的(实测 trace 实证)。
#   设备路径保持 POSIX(靠该变量保护), **本地目标必须转成 Windows 形式**。
OUT_W="$(cygpath -w "$OUT" 2>/dev/null || echo "$OUT")"
mkdir -p "$OUT"
say(){ printf '[autopsy %s] %s\n' "$(date +%H:%M:%S)" "$*"; }
ash(){ "$ADB" shell "$1" 2>/dev/null | tr -d '\r'; }

# 1) 等设备回来（panic 后通常 30-90s）
say "等设备回来 ..."
for i in $(seq 1 40); do
  [ "$("$ADB" get-state 2>/dev/null | tr -d '\r')" = "device" ] && { say "设备回来了 (第 $i 次等待)"; break; }
  sleep 8
done
if [ "$("$ADB" get-state 2>/dev/null | tr -d '\r')" != "device" ]; then say "!! 设备仍未回来, 尸检中止"; exit 1; fi
for i in $(seq 1 30); do [ "$(ash 'getprop sys.boot_completed')" = "1" ] && break; sleep 5; done

# 2) 现场快照（全是只读）
say "抓现场快照 ..."
{
  echo "=== autopsy $TAG  $(date) ==="
  echo "--- boot_id / bootreason / uptime ---"
  ash "cat /proc/sys/kernel/random/boot_id"
  ash "getprop ro.boot.bootreason"
  ash "cat /proc/uptime"
  echo "--- uname / cmdline / enforce ---"
  ash "uname -a"
  ash "cat /proc/cmdline"
  ash "getenforce"
  echo "--- loadavg / meminfo(摘要) / modules 数 ---"
  ash "cat /proc/loadavg"
  ash "grep -E 'MemTotal|MemAvailable' /proc/meminfo"
  ash "wc -l < /proc/modules"
  echo "--- ksu 相关 ---"
  ash "grep -E '^(ksu|kernelsu)' /proc/modules"
  echo "--- root/KSU 标记 ---"
  echo -n "root_alive: ";  ash "cat $TMPD/root_alive.txt 2>/dev/null | head -1"
  echo -n "ksu_done:   ";  ash "cat $TMPD/ksu_done.txt 2>/dev/null | head -1"
  echo -n "child_status: "; ash "cat $TMPD/mt49_child_status.txt 2>/dev/null | head -1"
  echo -n "su exists: ";  ash "ls $TMPD/su 2>/dev/null || echo no"
  echo "--- 无 root 时读不到的证据(记录其可读性) ---"
  echo -n "pstore(直读): "; ash "cat /sys/fs/pstore/console-ramoops-0 2>/dev/null | wc -c"
  echo -n "dmesg:  "; ash "dmesg 2>&1 | head -1"
  echo -n "dropbox:"; ash "ls /data/system/dropbox 2>&1 | head -2"
} > "$OUT/snapshot.txt" 2>&1
say "快照已写: $OUT/snapshot.txt"

# 3) 爆炸现场：exploit 的 stdout（重启后仍在, shell 可读）
say "取回 .out 现场 ..."
GOT=0
for n in R1 R2 R3 R4 R5 R6 C1 C2 C3 C4 C5 E5a E5b E5R1; do
  if [ "$(ash "ls $TMPD/$n.out 2>/dev/null | wc -l")" = "1" ]; then
    "$ADB" pull "$TMPD/$n.out" "$OUT_W/$n.out" >/dev/null 2>&1 && GOT=$((GOT+1))
  fi
done
say "取回 $GOT 个 .out 文件"
"$ADB" pull "$TMPD/proc_timeline.txt" "$OUT_W/proc_timeline.txt" >/dev/null 2>&1
"$ADB" pull "$TMPD/ksu_go.log" "$OUT_W/ksu_go.log" >/dev/null 2>&1
[ -f "$OUT/ksu_go.log" ] && say "!! 找到 ksu_go.log —— ksud late-load 尝试过! 内容:" && tail -12 "$OUT/ksu_go.log" | while IFS= read -r L; do say "  ksu_go| $L"; done

# 4) 就地打印每个 .out 的**最后几行**（这才是"爆炸瞬间"）
for f in "$OUT"/*.out; do
  [ -f "$f" ] || continue
  sz=$(wc -c < "$f")
  if head -c 60 "$f" 2>/dev/null | grep -qE 'adb\.exe:|no devices'; then
    say "  $(basename "$f"): ${sz}B — 是 adb 错误文本 ⇒ 该文件无效"
    continue
  fi
  say "  $(basename "$f"): ${sz}B — 最后 5 行:"
  tail -5 "$f" | sed 's/\x1b\[[0-9;]*m//g' | while IFS= read -r L; do say "      $L"; done
done
say "抢一份 pstore(单槽, 重启即覆盖) ..."
bash "$REPO/tools/pstore_grab.sh" "autopsy_$TAG" 2>&1 | sed 's/^/    /' | tail -10
say "尸检完成: $OUT"
