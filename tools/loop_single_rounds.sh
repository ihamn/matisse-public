#!/usr/bin/env bash
# ============================================================
# loop_single_rounds.sh — 「每 boot 只打 1 发 R」的自动循环
#
# 纪律来源（今晚实测）：
#   - 同 boot 第 2 发 R 会 panic（WINDOW=20 也崩）→ 每发之间必须重启
#   - WINDOW=60 会秒崩 → 固定 WINDOW=20
#   - miss 签名 = "window closed mid-burst ... ti=0" + mt25=0 + mt19b@2001x ms
#     （护栏拒绝盲写的自保行为，安全）
#   - R 是竞态，命中率约 40~50%（8 个样本：3 中 5 miss；传输层无关，已证伪）
#
# 命中后：ksu_persist.sh 会在同一个 boot 内自动继续 E5 → C → ksud late-load。
#
# 用法:
#   MAX_ATTEMPTS=3 bash tools/loop_single_rounds.sh      # 最多 3 个 boot
#   SETTLE=240 MAX_ATTEMPTS=5 bash tools/loop_single_rounds.sh
#   ADB=/path/to/adb bash tools/loop_single_rounds.sh
# ============================================================
set -u
: "${MAX_ATTEMPTS:=3}"
: "${SETTLE:=240}"
: "${WINDOW:=20}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO" || exit 1
if [ -z "${ADB:-}" ]; then
  ADB=$(command -v adb || true)
  [ -n "$ADB" ] || ADB="$REPO/platform-tools_r33.0.2-windows/platform-tools/adb.exe"
fi
export ANDROID_ADB_LOG_PATH="${ANDROID_ADB_LOG_PATH:-$REPO/.adb/adb.log}"
say(){ printf '[loop %s] %s\n' "$(date +%H:%M:%S)" "$*"; }

# ── 1 分钟心跳 (用户 2026-10-02 要求: 每 1 分钟都能在 DSH 里看到播报) ──
STATUS="$REPO/.adb/loop_status.txt"
mkdir -p "$(dirname "$STATUS")" 2>/dev/null
printf '0|%s|启动中|0\n' "$MAX_ATTEMPTS" > "$STATUS"
set_phase(){ printf '%s|%s|%s|%s\n' "${a:-0}" "$MAX_ATTEMPTS" "$1" "${MISS:-0}" > "$STATUS" 2>/dev/null; }
heartbeat(){ local aa mm ph ms up
  while :; do
    sleep 60
    IFS='|' read -r aa mm ph ms < "$STATUS" 2>/dev/null || true
    up=$("$ADB" shell cat /proc/uptime 2>/dev/null | awk '{print int($1)}' | tr -d '\r')
    printf '[hb %s] 第 %s/%s 个 boot | 阶段=%s | 设备 uptime=%ss | 累计 miss=%s 发\n' \
      "$(date +%H:%M:%S)" "${aa:-?}" "${mm:-?}" "${ph:-?}" "${up:-读不到}" "${ms:-?}"
  done; }
heartbeat & HB_PID=$!
trap 'kill "$HB_PID" 2>/dev/null' EXIT INT TERM

wait_device(){ local i st tries
  # v5 (2026-10-03 00:59 夜跑加固): 原来只等 40*10s=400s 就 exit 9 —— 无人值守时手机若彻底卡死,
  # 整夜就白跑。现在: 等 30 分钟, 期间 adb 自愈 (offline -> reconnect, 每 3 分钟重启 adb server)。
  tries=${WAIT_DEV_TRIES:-180}
  for i in $(seq 1 "$tries"); do
    st=$("$ADB" get-state 2>/dev/null | tr -d '\r')
    [ "$st" = "device" ] && return 0
    case "$st" in
      offline|unauthorized|recovery|sideload) "$ADB" reconnect >/dev/null 2>&1 ;;
    esac
    if [ $((i % 18)) -eq 0 ]; then
      say "  设备 $((i*10))s 未回来 (state=${st:-无}) — 重启 adb server 自愈"
      "$ADB" kill-server >/dev/null 2>&1; sleep 2; "$ADB" start-server >/dev/null 2>&1
    fi
    sleep 10
  done
  return 1; }
wait_settle(){ local up u lo l1
  # v7 (2026-10-03 01:44 夜跑 BUG#6): **开机后屏幕默认是熄的** (实测 uptime=62s 时
  # mWakefulness=Asleep), 而熄屏会让 Android 进 suspend/doze, 改变内核定时器与调度行为 ->
  # 破坏竞态时序。ksu_persist.sh 只在开火前 2 秒唤醒, settle 的 240 秒全程仍是熄屏。
  # 这里从设备一上线就持续唤醒 + 拉长超时。
  wake_screen(){ "$ADB" shell "dumpsys power 2>/dev/null | grep -q 'mWakefulness=Awake' || input keyevent 224; settings put system screen_off_timeout 2147483647" >/dev/null 2>&1; }
  # v8 (2026-10-03 02:10 有界实验): 手机现在停在锁屏、系统几乎全空闲 → 大核集群可能进深度 idle。
  # exploit 把 consumer 钉在 CPU6, 若集群处于深度 idle, 唤醒/上膛时序会变。所以给**兄弟核 CPU7**
  # 挂一条 nice -n 19 的最低优先级忙循环: 只负责把大核集群"焐"在活跃态, 不抢 CPU6 的 consumer。
  # 可用 LIGHT_LOAD=0 关掉; 每轮开火后 stop_keepalive 清掉。
  start_keepalive(){ [ "${LIGHT_LOAD:-1}" = "1" ] || return 0
    "$ADB" shell "nohup nice -n 19 taskset -c 7 sh -c 'while :; do :; done' >/dev/null 2>&1 &" >/dev/null 2>&1; }
  stop_keepalive(){ [ "${LIGHT_LOAD:-1}" = "1" ] || return 0
    "$ADB" shell "for p in \$(pgrep -f 'while :; do :; done'); do kill -9 \$p 2>/dev/null; done" >/dev/null 2>&1; }
  while :; do
    wake_screen
    up=$("$ADB" shell cat /proc/uptime 2>/dev/null | awk '{print int($1)}' | tr -d '\r')
    case "$up" in ''|*[!0-9]*) say "  读不到 uptime, 等 15s"; sleep 15; continue ;; esac
    if [ "$up" -lt "$SETTLE" ]; then
      say "  开机仅 ${up}s < ${SETTLE}s, 等 settle (屏幕已唤醒)"; sleep 30; continue
    fi
    # v2: 光等 uptime 不够 —— MIUI 刚开机的 1min load 常在 25-30, 会被 ksu_persist.sh 的
    # load>25 体检门拒(exit 6, 不消耗开火)。这里也等 load 降下来 (默认 <=20)。
    lo=$("$ADB" shell cat /proc/loadavg 2>/dev/null | tr -d '\r')
    l1=${lo%%.*}
    case "$l1" in ''|*[!0-9]*) l1=999 ;; esac
    if [ "$l1" -gt "${LOADMAX:-20}" ]; then
      say "  load1=${l1} > ${LOADMAX:-20} (MIUI 开机高峰), 继续等 load 降"; sleep 30; continue
    fi
    say "  settle OK (uptime ${up}s, load1 ${l1}, 屏幕=$("$ADB" shell "dumpsys power 2>/dev/null | grep -m1 -o 'mWakefulness=[A-Za-z]*'" | tr -d '\r'), 用户=$("$ADB" shell "dumpsys user 2>/dev/null | grep -m1 -o 'State: [A-Z_]*'" | tr -d '\r'))"
    return 0
  done; }

MISS=0
# v2 修复 (2026-10-02 20:48 实战): 不能假设"当前 boot 是干净的"!
# 那一发正好打在已开过火的 boot 上(20:07 用过的 17df2a96) => 同 boot 第 2 发 => 崩。
# 因此持久记录"最后一次开火时的 boot_id"; 若当前 boot 已经开过火, 先重启。
FIRED_BOOT_FILE="$REPO/.adb/last_fired_boot.txt"
cur_boot(){ "$ADB" shell cat /proc/sys/kernel/random/boot_id 2>/dev/null | tr -d '\r' | head -1; }

for a in $(seq 1 "$MAX_ATTEMPTS"); do
  say "================ 第 $a/$MAX_ATTEMPTS 次尝试 ================"
  CB=$(cur_boot)
  if [ -n "$CB" ]; then
    LAST=$(cat "$FIRED_BOOT_FILE" 2>/dev/null | tr -d ' \r\n' || true)
    if [ "$CB" = "$LAST" ]; then
      say "当前 boot $CB 已经开过火 (记录在 $FIRED_BOOT_FILE) — 必须先重启, 否则是同 boot 第 2 发(已验证会崩)"
      SKIP_REBOOT=0
    elif [ "$a" -gt 1 ] && [ "${SKIP_REBOOT:-0}" != "1" ]; then
      say "按纪律每 bot 1 发: 第 $a 轮前先重启"
    fi
  fi
  if [ "$a" -gt 1 ] && [ "${SKIP_REBOOT:-0}" != "1" ]; then
    set_phase "重启中(取 fresh boot)"
    say "重启手机取 fresh boot (同 boot 第 2 发已验证会 panic)"
    "$ADB" reboot 2>/dev/null
    sleep 35
  fi
  if [ "$a" = "1" ] && [ "${SKIP_REBOOT:-0}" != "1" ]; then
    LAST=$(cat "$FIRED_BOOT_FILE" 2>/dev/null | tr -d ' \r\n' || true)
    if [ -n "$CB" ] && [ "$CB" = "$LAST" ]; then
      set_phase "重启中(本 boot 已用过)"
      say "重启手机: 当前 boot 已经开过火, 必须换 boot"
      "$ADB" reboot 2>/dev/null
      sleep 35
    fi
  fi
  SKIP_REBOOT=0
  set_phase "等设备回来"
  # v5: 不因为等不到设备就退出 —— 夜跑必须自己扛住 (手机彻底卡死时只能等人工, 但我们继续等)。
  while ! wait_device; do
    say "!! 设备 30 分钟内未回来 (state=$("$ADB" get-state 2>/dev/null | tr -d '\r'))"
    say "   若手机黑屏卡死, 可能需要人工长按电源键; 循环继续等待, 不退出"
    set_phase "等设备(疑似卡死)"
    sleep 60
  done
  set_phase "等 settle(uptime>=$SETTLE)"
  wait_settle
  start_keepalive
  if [ "${LIGHT_LOAD:-1}" = "1" ]; then say "keep-alive: CPU7 忙循环已挂 (防大核集群深度 idle)"; else say "keep-alive: 已禁用 (LIGHT_LOAD=0)"; fi
  set_phase "开火中(R1)"
  say "开火 1 发: mt87 / WINDOW=${WINDOW} / 本 boot 第 1 发"
  cur_boot > "$FIRED_BOOT_FILE" 2>/dev/null   # 开火前先记账, 崩了也算已用过
  # RROUNDS>1 = 允许同一 boot 内多打几发 R (用户 2026-10-02 23:15 要求「3 次抽奖」)。
  # 代价明确: 同 boot 第 2 发有崩机前科(今晚 2/2), 且崩机会毁掉已拿到的落地;
  # 收益: 每 boot 的 R 抽奖次数从 1 提到 RROUNDS, 单位时间落地机会显著上升。
  if [ "${RROUNDS:-1}" -gt 1 ]; then
    say "本轮 RROUNDS=${RROUNDS} (同 boot 多打; 间隔 ${SPACING_R:-150}s; MAXFAIL=${RROUNDS})"
    MATISSE_ADB=1 MATISSE_WINDOW="$WINDOW" MATISSE_SETTLE="$SETTLE" \
      MATISSE_ALLOW_MULTI_ROUND=1 MATISSE_SPACING="${SPACING_R:-150}" \
      MATISSE_MAXFAIL="${RROUNDS}" bash ksu_persist.sh "${RROUNDS}"
  else
    MATISSE_ADB=1 MATISSE_WINDOW="$WINDOW" MATISSE_SETTLE="$SETTLE" bash ksu_persist.sh 1
  fi
  rc=$?
  stop_keepalive
  say "ksu_persist.sh 退出码 = $rc"
  # v3: 不要用退出码判成功 —— 脚本末尾多半以 0 退出(即使 KSU 没装上)。
  # 成功判据 = 设备 /proc/modules 出现 ksu/kernelsu。
  KM=$("$ADB" shell "grep -cE '^(ksu|kernelsu)' /proc/modules" 2>/dev/null | tr -dc '0-9'); KM=${KM:-0}
  if [ "$KM" -ge 1 ]; then
    say "★★★ 设备 /proc/modules 已出现 ksu/kernelsu ($KM 条) — 成功, 循环结束 ★★★"
    exit 0
  fi
  # v4 (2026-10-03 00:55 无人值守加固): 一旦拿到 root 就**立刻停手、绝不重启** ——
  # 否则循环的下一轮重启会把刚拿到的 uid 0 毁掉。判据用 9/08 那两种可靠证据。
  RA_TXT=$("$ADB" shell "cat /data/local/tmp/root_alive.txt 2>/dev/null | head -1" 2>/dev/null | tr -d '\r')
  U0=$("$ADB" shell "for p in \$(pgrep -x sleep); do awk '\$1==\"Uid:\" && \$2==0 && \$3==0 {print \"HIT \" FILENAME}' /proc/\$p/status 2>/dev/null; done" 2>/dev/null | tr -d '\r')
  if [ -n "$RA_TXT" ] || [ -n "$U0" ]; then
    say "★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★"
    say "★ 已拿到 root! root_alive=[$RA_TXT] /proc=[$U0]"
    say "★ 停手保护: 不再开火、不重启, 等人工接手 (ksud / pstore / 持久化)"
    say "★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★"
    exit 0
  fi
  case "$rc" in
    6) # v6 (2026-10-03 01:05 夜跑 BUG#4): 原来这里会把「设备重启中/读不到 boot_id」误判成
       #    「load 门拒」并 exit —— 而设备崩机重启恰恰是最常见的情况, 结果整夜循环自己死掉。
       #    现在: 只有「设备可读 且 boot 未变」才算真的没开火(等 load 降后重试, 不消耗轮次);
       #    其余(读不到 = 重启中 / boot 已变)一律算已消耗, 继续下一轮, **永不退出**。
       CB2=$(cur_boot); LASTF=$(cat "$FIRED_BOOT_FILE" 2>/dev/null | tr -d ' \r\n')
       if [ -n "$CB2" ] && [ "$CB2" = "$LASTF" ]; then
         say "退出码 6 = load 门拒 (boot 未变 $CB2, 未消耗开火) — 等 3 分钟后重试同一 boot"
         sleep 180
         continue
       fi
       SKIP_REBOOT=1; MISS=$((MISS+1))
       say "退出码 6 = 设备重启中或 boot 已变 (last=${LASTF:-无} now=${CB2:-读不到}) — 算一次消耗, 继续下一轮(不退出)"
       ;;
    *) MISS=$((MISS+1))
       say "本轮未拿到 KSU (退出码 $rc, R/C/E5 的判据见上方日志) — 重启后进入下一轮" ;;
  esac
  # v9 (2026-10-03 02:40): 冷却间隔。动机: 环境导致的 0 落地期里, 每一轮都只是给手机
  # 多加一次非正常关机 (今晚已 ~37 次 panic), 磨损是实打实的而收益≈0。
  # COOLDOWN=0 可关闭。设 180s 约把轮次率降 25%, 但显著减少单位时间内的 unclean shutdown。
  if [ "${COOLDOWN:-0}" -gt 0 ]; then
    say "冷却 ${COOLDOWN}s (降低设备磨损; COOLDOWN=0 可关)"
    sleep "$COOLDOWN"
  fi
done
say "达到上限 $MAX_ATTEMPTS 个 boot，仍未落地（累计 miss $MISS 发）。按纪律：停手，隔一段时间再来。"
exit 5
