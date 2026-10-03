#!/usr/bin/env bash
# win_loop.sh — 自动连抽：反复跑"单轮封装"，直到**真正完成**（模块进内核 / ksu_done 出现）或达到轮数上限
#
# 为什么需要它 (2026-10-03): 用户不想手动一轮轮盯。每轮 = 重启 → settle(100s) → R → (E5) → C(45s) → 只读等待。
# 每条"达成"判据都必须是**设备实测**, 且命中 adb 错误文本一律作废：
#   ① /proc/modules 出现 kernelsu (纯数字 ≥1)
#   ② /data/local/tmp/ksu_done.txt 存在(子进程 finit 成功才会写)
#   ③ /data/local/tmp/su 存在(模块起来后 KSU 会装 su)
# 命中即**停手**(不再开火/不再重启), 并提示用户打开 KSU 管理器 v3.3.0 做持久化。
#
# 用法: bash tools/win_loop.sh [最大轮数=8]
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"; cd "$REPO" || exit 1
ADB="${ADB:-$REPO/platform-tools_r33.0.2-windows/platform-tools/adb.exe}"
export ANDROID_ADB_LOG_PATH="$REPO/.adb/adb.log"
export MSYS_NO_PATHCONV=1
MAX="${1:-8}"
TMPD="${MATISSE_TMPD:-/data/local/tmp}"
say(){ printf '[winloop %s] %s\n' "$(date +%H:%M:%S)" "$*"; }
ash(){ "$ADB" shell "$1" 2>/dev/null | tr -d '\r'; }

check_win(){
  local k d s
  k=$(ash "grep -cE '^(ksu|kernelsu)' /proc/modules 2>/dev/null"); k=${k:-0}
  case "$k" in ''|*[!0-9]*) k=0;; esac
  d=$(ash "ls $TMPD/ksu_done.txt 2>/dev/null | wc -l"); d=${d:-0}
  s=$(ash "ls $TMPD/su 2>/dev/null | wc -l"); s=${s:-0}
  say "  判据: kernelsu=$k ksu_done=$d su=$s"
  if [ "$k" -ge 1 ]; then say "★★★ 模块已在内核 (kernelsu=$k) ★★★"; return 0; fi
  if [ "$d" = "1" ]; then say "★★★ ksu_done.txt 出现(finit 成功) ★★★"; return 0; fi
  if [ "$s" = "1" ]; then say "★★★ su 已安装 ★★★"; return 0; fi
  return 1
}

for r in $(seq 1 "$MAX"); do
  say "======== 第 $r/$MAX 轮 ========"
  # 每轮单发：R -> E5(285s退场) -> C(45s窗口, KO_LATE 机制) -> 只读等待
  # v8.50 (2026-10-03 15:32): 回退 v8.49 的 R 窗口放宽!! 日志里的历史教训写着:
#   '不要放宽窗口(W60 已实测 panic), 也不要同 boot 打第 2 发(已实测崩)'
#   ⇒ R 的超窗 = 护栏自保(已知安全, 设备多数存活), 放宽反而拆掉安全阀(15:27 跑满 45s 后崩机 ✗)。
#   C 的 45s 是今天验证过的(20s 时 C1..C5 全部被掐), 保留 ✓。
  MATISSE_CBUDGET=1 MATISSE_SKIP_E5=0 MATISSE_C_FIRST=0 MATISSE_C_WINDOW=45 HUNT_ALLOW_KO=1 \
    MATISSE_SKIP_E5R=1 SETTLE=100 SAMPLES=400 \
    bash "$REPO/tools/round_with_sampler.sh" 2>&1 | tail -40
  say "第 $r 轮结束, 检查达成判据 ..."
  if check_win; then
    say "★★★★★★★★ 达成, 停手 ★★★★★★★★"
    say "下一步(人工): 打开 KSU 管理器 v3.3.0 看是否转绿; 需要时把 $TMPD/ksu_done.txt 与 R1.out 交给分析侧"
    exit 0
  fi
  say "未达成, 继续下一轮"
  sleep 20
done
say "已跑满 $MAX 轮仍未达成, 停手 (证据在 logs_raw/ 下)"
exit 1
