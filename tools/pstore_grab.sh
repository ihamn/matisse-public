#!/usr/bin/env bash
# pstore_grab.sh — 抢在内核环形缓冲被覆盖之前，把"上一次死亡"的现场落盘
#
# 为什么必须先做这件事（2026-10-03 由对面 AI 指出，已实测证实）:
#   /sys/fs/pstore/console-ramoops-0 是**单槽**环形缓冲 —— 只保留**最后一次死亡**。
#   我们的循环是「崩 → adb reboot → 新 boot → 再开火」⇒ 那次干净重启**立刻把上一轮 panic 现场覆盖** ✗
#   ⇒ 昨晚 30 次 panic 一份都没留下 —— 不是读不到，是被我们自己下一次重启盖掉了。
#   正确顺序: **崩 → 先读 pstore 落盘 → 才允许重启**。
#
# 另一个关键事实（实测）:
#   /sys/fs/pstore 目录权限是 dr-xr-x--- system log ⇒ 没有 o+r ⇒ `ls`(列目录) **永远被拒**，
#   所以过去用 `ls` 当"能不能读"的探针是错的 ✗。**按固定文件名直接 cat 是允许的** ✓
#   (实测 console-ramoops-0 读到 262,132 字节)。
#
# 用法: bash tools/pstore_grab.sh [标签]
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"; cd "$REPO" || exit 1
ADB="${ADB:-$REPO/platform-tools_r33.0.2-windows/platform-tools/adb.exe}"
export ANDROID_ADB_LOG_PATH="$REPO/.adb/adb.log"
export MSYS_NO_PATHCONV=1      # 保护设备侧 POSIX 路径; 本地目标用 cygpath 转 Windows
TAG="${1:-$(date +%Y%m%d_%H%M%S)}"
OUT="$REPO/logs_raw/pstore"
mkdir -p "$OUT"
OUT_W="$(cygpath -w "$OUT" 2>/dev/null || echo "$OUT")"
say(){ printf '[pstore %s] %s\n' "$(date +%H:%M:%S)" "$*"; }
ash(){ "$ADB" shell "$1" 2>/dev/null | tr -d '\r'; }

[ "$("$ADB" get-state 2>/dev/null | tr -d '\r')" = "device" ] || { say "设备不在线, 无法取 pstore"; exit 1; }

say "直读 pstore（不用 ls 探针）..."
GOT=0
for f in console-ramoops-0 pmsg-ramoops-0 dmesg-ramoops-0 console-ramoops; do
  n=$(ash "cat /sys/fs/pstore/$f 2>/dev/null | wc -c")
  case "$n" in ''|*[!0-9]*) n=0;; esac
  if [ "$n" -gt 64 ]; then
    "$ADB" shell "cat /sys/fs/pstore/$f 2>/dev/null" > "$OUT/${TAG}_$f.txt" 2>/dev/null
    sz=$(wc -c < "$OUT/${TAG}_$f.txt" 2>/dev/null || echo 0)
    say "  $f: 设备 ${n}B -> 本地 ${sz}B"
    GOT=$((GOT+1))
  else
    say "  $f: 设备 ${n}B (空/不存在, 跳过)"
  fi
done
[ "$GOT" -gt 0 ] || { say "!! 没有取到任何 pstore 内容"; exit 1; }

# 死因抽取：pc / Call trace / Kernel Offset / panic / BUG / watchdog
F="$OUT/${TAG}_console-ramoops-0.txt"
[ -s "$F" ] || F=$(ls -S "$OUT"/${TAG}_*.txt 2>/dev/null | head -1)
say "死因抽取 ($(basename "$F")):"
for pat in 'Kernel panic' 'Unable to handle' 'Internal error' 'BUG:' 'Call trace' 'pc :' 'Kernel Offset' 'watchdog' 'SError' 'Undefined instruction' 'sysrq' 'Restarting system'; do
  c=$(grep -c -F "$pat" "$F" 2>/dev/null); c=${c:-0}
  [ "$c" -gt 0 ] && say "  [$pat] × $c"
done
say "--- pc : / Call trace / Kernel Offset 原文 ---"
grep -n -E 'pc :|Call trace|Kernel Offset|Kernel panic|Unable to handle|Internal error|BUG:' "$F" 2>/dev/null | head -12 | while IFS= read -r L; do say "  $L"; done
say "最后 3 行:"; tail -3 "$F" 2>/dev/null | while IFS= read -r L; do say "  $L"; done
say "完成: $OUT/${TAG}_*.txt"
