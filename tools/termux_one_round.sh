#!/data/data/com.termux/files/usr/bin/bash
# termux_one_round.sh — 手机侧「打一轮」入口（Termux + Shizuku/rish）
#
# 设计前提（用户 2026-10-03 明确要求）:
#   * 手机上**不能**"先重启再继续跑" ⇒ 本脚本**只在当前 boot 内跑完一轮就结束**, 绝不自己 reboot
#   * 重启由**用户自己**决定; 重启后再跑一次本脚本即可
#   * 不做跨 boot 状态机（没必要）
#
# 一轮 = R(20s 安全阀) → 退场 285s → E5 → C(45s 窗口, 单发) → 落地后只读等待 ksud 装载
# 成功判据（一律设备实测, 出现 adb/rish 错误文本即作废）:
#   /proc/modules 出现 kernelsu(纯数字≥1)  或  /data/local/tmp/ksu_go.log 里 late-load rc=0/modules:1
#
# 用法:  bash ~/matisse/tools/termux_one_round.sh
#        bash ~/matisse/tools/termux_one_round.sh --force     # 即使本 boot 已是 root 也再打一轮

set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"; cd "$REPO" || exit 1
FORCE=0; [ "${1:-}" = "--force" ] && FORCE=1
TS="$(date +%Y%m%d_%H%M%S)"
LOGD="$REPO/logs_raw"; mkdir -p "$LOGD"
LOG="$LOGD/termux_round_$TS.log"
say(){ printf '[one-round %s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "$LOG"; }
notify(){ command -v termux-notification >/dev/null 2>&1 && termux-notification -t "matisse 提权" -c "$1" >/dev/null 2>&1 || true; }

say "日志: $LOG"
say "设备: $(uname -r) | boot=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null | cut -c1-8) | 已运行 $(cut -d. -f1 /proc/uptime 2>/dev/null)s"

# ── 0) 本 boot 是否已经是 root（模块在 ⇒ 什么都不用做）──
if [ "$FORCE" != "1" ] && grep -qE '^(ksu|kernelsu)' /proc/modules 2>/dev/null; then
  say "★ 本 boot 已加载 kernelsu ⇒ 无需再打（KSU 管理器应显示越狱模式）"
  notify "本 boot 已是 root（kernelsu 在内核里）"
  exit 0
fi

# ── 1) 传输层：手机本地用 rish(Shizuku, shell 身份)；没有就提示用手动方式 ──
RISH=""
for c in "$HOME/rish" "$HOME/rish/rish" "/sdcard/Download/rish" "/storage/emulated/0/Download/rish" "/data/local/tmp/rish"; do
  [ -f "$c" ] && RISH="$c" && break
done
[ -z "$RISH" ] && RISH=$(find "$HOME" -maxdepth 3 -name rish -type f 2>/dev/null | head -1)
if [ -z "$RISH" ]; then
  say "!! 没找到 rish —— Shizuku App 里『使用此应用』先启动, 再从中复制 rish 到 ~/"
  say "   (Shizuku 必须在运行中; 冻结/未启动都会让 rish 失败)"
  notify "缺少 rish: 请先启动 Shizuku 并复制 rish 到 ~/"
  exit 2
fi
chmod +x "$RISH" 2>/dev/null
RISH_DIR="$(dirname "$RISH")"
say "找到 rish: $RISH"
# 探测可用模式（与 ksu_persist.sh 内部同逻辑, 这里先做一次快速自检）
RM=""
for m in stdin c args; do
  case "$m" in
    c)    O=$( (cd "$RISH_DIR" && timeout 20 ./rish -c 'echo OK_$(id -u)' </dev/null) 2>&1 ) ;;
    args) O=$( (cd "$RISH_DIR" && timeout 20 ./rish 'echo OK_$(id -u)') 2>&1 ) ;;
    *)    O=$( (cd "$RISH_DIR" && echo 'echo OK_$(id -u)' | timeout 20 ./rish) 2>&1 ) ;;
  esac
  printf '%s' "$O" | grep -q 'OK_' && { RM="$m"; break; }
done
if [ -z "$RM" ]; then
  say "!! rish 探测失败 —— 请确认 Shizuku 正在运行（未被冻结）, 再重跑"
  say "   最后输出: $(printf '%s' "${O:-}" | head -c 160)"
  notify "rish 探测失败: 请启动/解冻 Shizuku 后重跑"
  exit 2
fi
say "rish 可用（模式=$RM, 身份 uid=$(printf '%s' "$O" | grep -o 'OK_[0-9]*' | cut -d_ -f2)）"

# ── 2) 清掉上一轮可能残留的只读采样器（绝不 pkill 持毒进程 —— HOLD 期它们是 init_cred 持有者, SIGKILL 会 panic）──
( cd "$RISH_DIR" && timeout 25 ./rish -c 'pkill -9 -f round_proc_sampler 2>/dev/null; echo clean_ok' </dev/null ) >/dev/null 2>&1 || true

# ── 3) 跑一轮（成功配方：HOLD + 单发 C + C 45s + R 20s 安全阀 + KO 武装）──
say "开始打一轮（预计 8-12 分钟，期间手机会有概率崩机重启；崩机属已知结构风险）"
MATISSE_ADB=0 \
MATISSE_CBUDGET=1 MATISSE_SKIP_E5=0 MATISSE_C_FIRST=0 MATISSE_C_WINDOW=45 \
HUNT_ALLOW_KO=1 MATISSE_R_DRAIN=285 \
bash "$REPO/ksu_persist.sh" 2>&1 | tee -a "$LOG"

# ── 4) 判定（只看实测；手机上直接用本机 /proc 读, 不需要 rish）──
KN=$(grep -cE '^(ksu|kernelsu)' /proc/modules 2>/dev/null); KN=${KN:-0}
LOGK=$(cat /data/local/tmp/ksu_go.log 2>/dev/null | head -20)
say "判据: kernelsu=$KN"
if [ "$KN" -ge 1 ] || printf '%s' "$LOGK" | grep -qE 'late-load rc=0|modules: 1'; then
  say "★★★★★★★★ 成功：kernelsu 已在内核 ⇒ 打开 KSU 管理器应显示越狱模式 ★★★★★★★★"
  say "（提示：LKM late-load 是每 boot 一次；本次开机别重启即可一直用 ✓）"
  notify "提权成功：kernelsu 已加载 ✓"
  exit 0
fi
say "本轮未成功 ✗ —— 按你的流程：**手动重启手机**后再跑一次本脚本即可（脚本不会自己重启 ✓）"
printf '%s' "$LOGK" | sed 's/^/    ksu_go.log| /' | tail -12 | tee -a "$LOG"
notify "本轮未成功；重启手机后再跑一次脚本"
exit 1
