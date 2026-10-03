#!/usr/bin/env bash
# round_with_sampler.sh — 单轮「真实 R + 消费者线程状态采样」封装
# v3 (2026-10-03 10:42): **每轮一个全新的设备工作目录** (BUG #18 结构性修复)
#   内核 SID 的 child 写过的文件会带坏 SELinux 标签 ⇒ shell 连 ls/rm/adb push 都做不了,
#   restorecon 也修不了; 但换目录/换名完全正常 ⇒ 每轮新建 /data/local/tmp/mt_<TS>/,
#   弹药、输出、状态文件、采样时间线全部落在里面, 天然隔离, 不再污染下一轮。
#
# 用法: bash tools/round_with_sampler.sh
#   env: SETTLE=240 REBOOT=1 JOYOSE=1 SAMPLES=500
#        MATISSE_C_WINDOW=45 MATISSE_SKIP_E5=0 MATISSE_C_FIRST=0 HUNT_ALLOW_KO=1
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"; cd "$REPO" || exit 1
ADB="${ADB:-$REPO/platform-tools_r33.0.2-windows/platform-tools/adb.exe}"
export ANDROID_ADB_LOG_PATH="$REPO/.adb/adb.log"
# BUG #14: Git-Bash/MSYS 会把参数里的 /data/local/tmp/... 自动转成 Windows 路径 ⇒ push/pull 静默失败
export MSYS_NO_PATHCONV=1
BASH_BIN="${BASH_BIN:-/usr/bin/bash}"
SETTLE=${SETTLE:-100}   # v5 (2026-10-03 11:30 用户要求): 开机 settle 240s -> 100s
SAMPLES=${SAMPLES:-500}
TS="$(date +%Y%m%d_%H%M%S)"; OUT="$REPO/logs_raw/sampler_$TS"
# ── v4 (2026-10-03 11:0x, 按用户口径对齐) ──
# 路径**保持 /data/local/tmp 不变**(exploit 内部把 root_alive.txt / mt49_child_status.txt /
# ksu_done.txt 的路径写死在 /data/local/tmp, 换目录脚本就永远看不到标记 —— 上一版吃过这个亏),
# **只给弹药换名字**绕开被内核 SID 写坏标签的文件(shell 连 mv/rm/stat 都被 SELinux 拒, 实测)。
#   preload.so          -> preload_v3.so
#   kernelsu_gki209.ko  -> ko_v330.ko   (KSU 3.3.0 空 __versions 版, 配对设备的 ksud 3.3.0)
TMPD="/data/local/tmp"
PRE_DEV="$TMPD/preload_v4.so"   # v8.46: 二进制已打补丁 — gate 命中时以 root 执行 sh /data/local/tmp/ksu_go.sh &
KO_DEV="$TMPD/ko_v330.ko"
SAMP_DEV="$TMPD/rps_v3.sh"
TL_DEV="$TMPD/timeline_v3.txt"
mkdir -p "$OUT"
OUT_W="$(cygpath -w "$OUT" 2>/dev/null || echo "$OUT")"   # v8.37 BUG #19: pull 的本地目标必须用 Windows 路径
say(){ printf '[sampler %s] %s\n' "$(date +%H:%M:%S)" "$*"; }
ash(){ "$ADB" shell "$1" 2>/dev/null | tr -d '\r'; }

# 0) 建立本轮设备工作目录
ash "mkdir -p $TMPD" >/dev/null
say "本轮设备工作目录: $TMPD"

# 1) 推送采样器 (到本轮目录, 不用被污染的旧路径)
say "推送采样器"
if ! "$ADB" push tools/round_proc_sampler.sh "$SAMP_DEV" 2>&1 | tail -1; then
  say "!! push 失败"; exit 3
fi
if [ "$(ash "ls $SAMP_DEV 2>/dev/null | wc -l")" != "1" ]; then
  say "!! 设备上没有采样器脚本, 中止"; exit 3
fi
say "采样器已就位 ($(ash "cat $SAMP_DEV 2>/dev/null | wc -l") 行)"

# ── v8.38 (2026-10-03 11:42, 采纳对面 AI 的关键指正) ──
# `/sys/fs/pstore/console-ramoops-0` 是**单槽**环形缓冲: 只留最后一次死亡。
# 崩 → 我们 adb reboot → 新 boot ⇒ **那次干净重启把上一轮 panic 现场覆盖掉** ✗
# ⇒ 昨晚 30 次 panic 一份没留下的真因不是"读不到", 是被我们下一次重启盖掉。
# 纪律: **重启之前, 第一件事就是抢 pstore**。 (且目录 o+r 缺失 ⇒ ls 永远被拒,
#       必须按文件名直读 —— 实测 console-ramoops-0 可读到 262KB。)
# v8.40 (2026-10-03 12:11): 原来写成"设备在线才抢" ⇒ 崩机瞬间设备正在重启, 就整段跳过了 ✗
# (12:07 那次 C 崩机的 pstore 因此没抢到)。改成**无条件调用会等设备的抢取脚本**。
say "★ 重启前先抢 pstore（单槽缓冲, 晚了就没了）"
bash "$REPO/tools/pstore_grab.sh" "pre_reboot_$TS" 2>&1 | sed 's/^/    /' | tail -10
# 2) (可选) 重启取 fresh boot
if [ "${REBOOT:-1}" = "1" ]; then
  # BUG #17: 上一轮遗留的 exploit(/system/bin/sleep 180, R child 轮询最长 2h)与采样器会被
  # ksu_persist.sh 的取证步判为「残留进程」而拒绝开火 —— 开火前先清干净。
  ash "pkill -9 -f round_proc_sampler 2>/dev/null; sleep 2; echo cleaned" >/dev/null   # v8.51: 不再 pkill sleep/preload —— PSELECT_HOLD 的持毒进程被 SIGKILL 会同样触发 mm teardown panic (手机 AI 实证)
  say "已清理残留; 现存 sleep 进程=$(ash 'ps -A -o NAME | grep -c "^sleep"')"
  BID_BEFORE=$(ash "cat /proc/sys/kernel/random/boot_id")
  say "重启取 fresh boot; 重启前 boot=${BID_BEFORE:0:8}"
  "$ADB" reboot >/dev/null 2>&1; sleep 30
  for i in $(seq 1 60); do [ "$("$ADB" get-state 2>/dev/null | tr -d '\r')" = "device" ] && break; sleep 5; done
  for i in $(seq 1 18); do
    BID_NOW=$(ash "cat /proc/sys/kernel/random/boot_id")
    [ -n "$BID_NOW" ] && [ "$BID_NOW" != "$BID_BEFORE" ] && { say "重启成功: boot=${BID_NOW:0:8}"; break; }
    [ "$i" = "6" ] && { say "  adb reboot 未生效, 改用 adb shell reboot"; ash "reboot" >/dev/null 2>&1; }
    [ "$i" = "12" ] && { say "  仍未生效, 再发一次 adb reboot"; "$ADB" reboot >/dev/null 2>&1; }
    sleep 10
  done
  # 重启后重建工作目录并重推采样器 (新 boot 的 /data/local/tmp 是干净的)
  ash "mkdir -p $TMPD" >/dev/null
  "$ADB" push tools/round_proc_sampler.sh "$SAMP_DEV" >/dev/null 2>&1
fi

# 2b) 等系统完全开机 + 等 settle
say "等待系统完全开机 ..."
for i in $(seq 1 60); do
  [ "$(ash 'getprop sys.boot_completed' | tr -d ' \r')" = "1" ] && break
  sleep 10
done
say "等 settle (uptime>=$SETTLE) ..."
while :; do
  up=$(ash "cat /proc/uptime" | awk '{print int($1)}'); case "$up" in ''|*[!0-9]*) sleep 15; continue;; esac
  [ "$up" -ge "$SETTLE" ] && break
  ash "input keyevent 224; settings put system screen_off_timeout 2147483647" >/dev/null
  sleep 30
done
say "settle OK (uptime=${up}s)"
ash "input keyevent 224; settings put system screen_off_timeout 2147483647; settings put global stay_on_while_plugged_in 7; dumpsys deviceidle disable" >/dev/null
if [ "${JOYOSE:-1}" = "1" ]; then
  ash "am force-stop com.xiaomi.joyose" >/dev/null
  say "已 force-stop joyose (进程数=$(ash 'ps -A -o NAME | grep -c joyose'))"
fi

# 3) 起采样器(延迟 15s 避开坚化里的 am kill-all) → 立刻开火
# ── v7 (2026-10-03 11:40, 用户指出"尸检没弄好"的真正原因) ──
# 这行原本直接 `rm -f $TMPD/R1.out` ⇒ **把上一轮的爆炸现场(exploit stdout 到崩溃瞬间)删掉** ✗。
# 实测: 11:37:0x 还能 pull 到 R1.out, 11:37:29 就没了(正好是新一轮走到这行)。
# 现在: 删之前先把上一轮的现场**抢救到笔记本**(scene_<TS>/), 尸检才有东西可看。
SCENE="$REPO/logs_raw/scene_$TS"; mkdir -p "$SCENE"; SCENE_W="$(cygpath -w "$SCENE" 2>/dev/null || echo "$SCENE")"
RESCUED=0
for n in R1 R2 R3 C1 C2 C3 C4 C5 E5a E5b E5R1; do
  if [ "$(ash "ls $TMPD/$n.out 2>/dev/null | wc -l")" = "1" ]; then
    "$ADB" pull "$TMPD/$n.out" "$SCENE_W/$n.out" >/dev/null 2>&1 && RESCUED=$((RESCUED+1))
  fi
done
if [ "$RESCUED" -gt 0 ]; then
  say "抢救上一轮现场: $RESCUED 个 .out -> $SCENE"
  for f in "$SCENE"/R1.out "$SCENE"/C1.out; do
    [ -s "$f" ] || continue
    say "  --- $(basename "$f") 上次最后 3 行 ---"
    tail -3 "$f" | sed 's/\x1b\[[0-9;]*m//g' | while IFS= read -r L; do [ -n "$L" ] && say "      $L"; done
  done
fi
say "启动采样器(采 ${SAMPLES}s) 并开火 R ..."
ash "rm -f $TL_DEV $TMPD/R1.out" >/dev/null
ash "setsid sh -c 'sleep 15; sh $SAMP_DEV $TL_DEV $SAMPLES' >/dev/null 2>&1 &" >/dev/null
sleep 2
say "采样器已安排(15s 后启动)"
MATISSE_ADB=1 MATISSE_WINDOW="${MATISSE_WINDOW:-20}" MATISSE_SETTLE=0 MATISSE_NO_GIT=1 \
  MATISSE_TMPD="$TMPD" \
  MATISSE_C_WINDOW="${MATISSE_C_WINDOW:-}" MATISSE_R_WINDOW="${MATISSE_R_WINDOW:-}" \
  MATISSE_C_BLIND="${MATISSE_C_BLIND:-0}" HUNT_ALLOW_KO="${HUNT_ALLOW_KO:-1}" \
  MATISSE_SKIP_E5="${MATISSE_SKIP_E5:-1}" MATISSE_C_FIRST="${MATISSE_C_FIRST:-1}" \
  MATISSE_SKIP_E5R="${MATISSE_SKIP_E5R:-1}" \
  MATISSE_PRELOAD_DEV="$PRE_DEV" MATISSE_KO_DEV="$KO_DEV" \
  $BASH_BIN ksu_persist.sh 1 2>&1 | tail -30

# 4) 取回证据
# 4) 取回证据  ── v6 (2026-10-03 11:38, 用户指出"尸检没弄好") ──
# 旧版在**设备已经掉线的那一刻**就 pull ⇒ 拿到的全是 36 字节 `adb.exe: no devices` ✗,
# 而真正有用的现场(exploit stdout 的最后几行)重启后仍在 /data/local/tmp 且 shell 可读 ✓。
say "尸检: 等设备回来再取现场 ..."
for i in $(seq 1 40); do [ "$("$ADB" get-state 2>/dev/null | tr -d '\r')" = "device" ] && break; sleep 8; done
"$ADB" pull "$TL_DEV" "$OUT_W/proc_timeline.txt" >/dev/null 2>&1
GOT=0
for n in R1 R2 R3 C1 C2 C3 C4 C5 E5a E5b E5R1; do
  if [ "$(ash "ls $TMPD/$n.out 2>/dev/null | wc -l")" = "1" ]; then
    "$ADB" pull "$TMPD/$n.out" "$OUT_W/$n.out" >/dev/null 2>&1 && GOT=$((GOT+1))
  fi
done
ash "cat $TMPD/mt49_child_status.txt" > "$OUT/child_status.txt" 2>/dev/null
ash "cat $TMPD/root_alive.txt" > "$OUT/root_alive.txt" 2>/dev/null
ash "cat $TMPD/ksu_done.txt" > "$OUT/ksu_done.txt" 2>/dev/null
"$ADB" pull "$TMPD/ksu_go.log" "$OUT_W/ksu_go.log" >/dev/null 2>&1
ash "grep -cE '^(ksu|kernelsu)' /proc/modules" > "$OUT/ksu_count.txt" 2>/dev/null
ash "getprop ro.boot.bootreason" > "$OUT/bootreason.txt" 2>/dev/null
say "尸检: 取回 $GOT 个 .out"
for f in "$OUT"/R1.out "$OUT"/C1.out; do
  [ -s "$f" ] || continue
  say "  --- $(basename "$f") 爆炸瞬间最后 4 行 ---"
  tail -4 "$f" | sed 's/\x1b\[[0-9;]*m//g' | while IFS= read -r L; do [ -n "$L" ] && say "      $L"; done
done

# 5) 小结
say "===== 小结 ====="
say "设备工作目录: $TMPD | 本地证据: $OUT"
# ── v8.32 (2026-10-03 11:0x, 采纳只读审计第 2 条建议) ──
# 拉回来的任何字段只要命中 adb 错误文本 ⇒ **整轮证据作废**(绝不落成 YES)。
# 09:55 那次 13 个文件全是 36 字节 `adb.exe: no devices/emulators found`,
# 而 CARD.md 的判据字段还照着它写了结论 —— 同族缺陷第 4 次复发, 这次从入口掐死。
INVALID=0
for f in "$OUT"/*.txt "$OUT"/*.out; do
  [ -f "$f" ] || continue
  if head -c 200 "$f" 2>/dev/null | grep -qE 'adb\.exe:|no devices|Permission denied'; then
    say "!! 证据文件 $(basename "$f") 是设备错误文本 ⇒ 本轮证据无效 (INVALID)"
    INVALID=1
  fi
done
[ "$INVALID" = "1" ] && say "===== 本轮结论: EVIDENCE-INVALID (不得记为成功) =====" \
                     || say "===== 本轮证据可读 (仍需逐项判据) ====="
[ -s "$OUT/proc_timeline.txt" ] && say "timeline 行数: $(wc -l < "$OUT/proc_timeline.txt")" || say "!! timeline 空"
say "门槛: $(head -1 "$OUT/child_status.txt" 2>/dev/null)"
say "ksu=$(cat "$OUT/ksu_count.txt" 2>/dev/null) root_alive=[$(head -1 "$OUT/root_alive.txt" 2>/dev/null)]"
