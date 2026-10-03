#!/usr/bin/env bash
# dbg_autopsy.sh — 复现 autopsy.sh 里"检测 .out 是否存在"的那一行, 查出为何返回 0
set -u
REPO="/c/Users/<user>/Desktop/matisse"
ADB="$REPO/platform-tools_r33.0.2-windows/platform-tools/adb.exe"
export ANDROID_ADB_LOG_PATH="$REPO/.adb/adb.log"
export MSYS_NO_PATHCONV=1
TMPD="${MATISSE_TMPD:-/data/local/tmp}"
echo "TMPD=[$TMPD]  ADB=[$ADB]"
ash(){ "$ADB" shell "$1" 2>/dev/null | tr -d '\r'; }
echo "--- 形态1: 直接调用 ---"
echo "  ls 输出: [$(ash "ls $TMPD/R1.out 2>/dev/null")]"
echo "  wc -l : [$(ash "ls $TMPD/R1.out 2>/dev/null | wc -l")]"
echo "--- 形态2: 脚本里的写法(比较) ---"
if [ "$(ash "ls $TMPD/R1.out 2>/dev/null | wc -l")" = "1" ]; then echo "  判定=存在 ✓"; else echo "  判定=不存在 ✗"; fi
echo "--- 形态3: 循环里(变量插值) ---"
for n in R1 C1; do
  v="$(ash "ls $TMPD/$n.out 2>/dev/null | wc -l")"
  echo "  n=$n  raw=[$v]  等值测试: $([ "$v" = "1" ] && echo YES || echo NO)"
done
echo "--- 形态4: 换用 test -s 的等价探测(ls | grep -c) ---"
for n in R1 C1; do
  v="$(ash "ls $TMPD/$n.out 2>/dev/null | grep -c .")"
  echo "  n=$n  grep -c=[$v]"
done
echo "--- 形态5: 直接用 sh -c 在设备侧判断 ---"
for n in R1 C1; do
  v="$(ash "[ -f $TMPD/$n.out ] && echo yes || echo no")"
  echo "  n=$n  device-side test=[$v]"
done
