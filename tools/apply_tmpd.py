#!/usr/bin/env python3
# apply_tmpd.py — 把 ksu_persist.sh 里所有设备侧 /data/local/tmp/ 改成 ${TMPD}/
# 用 python 精确文本替换, 避免 shell/sed 的引号与展开问题 (2026-10-03 10:37 被 sed 坑过一次)
import io, re, sys

P = 'ksu_persist.sh'
src = io.open(P, encoding='utf-8').read()

if 'TMPD="${MATISSE_TMPD' in src:
    print('已改过, 退出'); sys.exit(0)

DEF_LINE = 'RUN_TS=$(date +%Y%m%d_%H%M%S)'
if DEF_LINE not in src:
    print('找不到 RUN_TS 定义, 退出'); sys.exit(1)

BLOCK = '''# ── v8.30 (2026-10-03 10:38, BUG #18 结构性修复) ──
# 设备侧所有文件都放**每轮全新的目录**里:
#   ① 内核 SID 的 child 写过的文件会带坏 SELinux 标签(shell 连 ls/rm/adb push 都做不了,
#      restorecon 也修不了), 换目录/换名即可绕开 —— 每轮新目录天然隔离, 不再污染下一轮;
#   ② 弹药 .so/.ko、输出 .out、状态文件(mt49_child_status/root_alive/ksu_done/budget)全在该目录内。
# 调用方用 MATISSE_TMPD 指定; 默认仍是 /data/local/tmp。
TMPD="${MATISSE_TMPD:-/data/local/tmp}"
mkdir -p "$TMPD" 2>/dev/null
'''

# 1) 先插入定义 (含字面量), 再替换其余出现处 —— 顺序很关键, 否则定义行也会被替换
src = src.replace(DEF_LINE, DEF_LINE + '\n' + BLOCK, 1)

# 2) 只替换定义块之外的出现: 先把定义行与注释里的字面量保护起来
PROTECT = '@@TMPD_LITERAL@@'
src = src.replace('TMPD="${MATISSE_TMPD:-/data/local/tmp}"',
                  'TMPD="${MATISSE_TMPD:-' + PROTECT + '}"', 1)
# 注释里的示例路径也保护(它们只是说明)
src = re.sub(r'(#.*?)(/data/local/tmp/)', lambda m: m.group(1) + PROTECT, src)

n_before = src.count('/data/local/tmp/')
src = src.replace('/data/local/tmp/', '${TMPD}/')
src = src.replace(PROTECT, '/data/local/tmp')
n_after = src.count('/data/local/tmp/')

io.open(P, 'w', encoding='utf-8').write(src)
print('替换了 %d 处 (替换后剩余字面量 %d 处, 均应为定义/注释)' % (n_before, n_after))
