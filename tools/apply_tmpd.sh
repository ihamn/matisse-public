#!/usr/bin/env bash
# apply_tmpd.sh — 把 ksu_persist.sh 里 48 处 /data/local/tmp/ 改成每轮可换的 ${TMPD}/
set -e
cd /c/Users/<user>/Desktop/matisse
cp ksu_persist.sh /tmp/ksu_v829.bak

# 幂等: 若已经改过就退出
if grep -q 'TMPD=' ksu_persist.sh; then
  echo "已经改过 (TMPD 已存在), 跳过替换"
else
  sed -i 's#/data/local/tmp/#${TMPD}/#g' ksu_persist.sh
  echo "替换完成, 现存 \${TMPD}/ 出现次数: $(grep -o '\${TMPD}/' ksu_persist.sh | wc -l)"
fi

# 插入 TMPD 定义 (在 RUN_TS= 那一行之后)
if ! grep -q '^TMPD=' ksu_persist.sh; then
  LN=$(grep -n '^RUN_TS=' ksu_persist.sh | head -1 | cut -d: -f1)
  [ -n "$LN" ] || { echo "找不到 RUN_TS 行"; exit 1; }
  python3 - "$LN" <<'PY'
import sys
ln = int(sys.argv[1])
p = 'ksu_persist.sh'
lines = open(p, encoding='utf-8').read().split('\n')
block = [
 '# ── v8.30 (2026-10-03 10:35, BUG #18 结构性修复) ──',
 '# 设备侧所有文件都放**每轮全新的目录**里:',
 '#   ① 内核 SID 的 child 写过的文件会带坏 SELinux 标签(shell 连 ls/rm/adb push 都做不了,',
 '#      restorecon 也修不了), 换目录/换名即可绕开 —— 每轮新目录天然隔离, 不再污染下一轮;',
 '#   ② 弹药 .so/.ko、输出 .out、状态文件(mt49_child_status/root_alive/ksu_done/budget)都在该目录内。',
 '# 调用方用 MATISSE_TMPD 指定; 默认仍是 /data/local/tmp。',
 'TMPD="${MATISSE_TMPD:-/data/local/tmp}"',
 'mkdir -p "$TMPD" 2>/dev/null',
]
lines[ln:ln] = block
open(p, 'w', encoding='utf-8').write('\n'.join(lines))
print('TMPD 定义已插入')
PY
fi

echo "--- 定义确认 ---"
grep -n '^TMPD=\|MATISSE_TMPD' ksu_persist.sh | head -4
echo "--- 裸路径残留数 (应为 1, 即定义里的字面量) ---"
grep -c '/data/local/tmp/' ksu_persist.sh || true
echo "--- 语法 ---"
bash -n ksu_persist.sh && echo "bash -n OK"
