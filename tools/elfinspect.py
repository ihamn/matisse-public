#!/usr/bin/env python3
# elfinspect.py — 纯静态读 ELF 段表, 对比两个 KernelSU 模块的 __versions / __kcrctab 等
# (2026-10-03: 用来实证「空 __versions 段」与「未修补版」的差别 —— 这是 finit_module 可能失败的关键)
import struct, sys, os

def sections(path):
    with open(path, 'rb') as f:
        d = f.read()
    if d[:4] != b'\x7fELF':
        return None, None, None
    is64 = d[4] == 2
    le = d[5] == 1
    e = '<' if le else '>'
    if is64:
        e_shoff, = struct.unpack_from(e + 'Q', d, 0x28)
        e_shentsize, e_shnum, e_shstrndx = struct.unpack_from(e + 'HHH', d, 0x3a)
    else:
        e_shoff, = struct.unpack_from(e + 'I', d, 0x20)
        e_shentsize, e_shnum, e_shstrndx = struct.unpack_from(e + 'HHH', d, 0x2e)
    secs = []
    for i in range(e_shnum):
        off = e_shoff + i * e_shentsize
        if is64:
            name, typ, flags, addr, offset, size = struct.unpack_from(e + 'IIQQQQ', d, off)
        else:
            name, typ, flags, addr, offset, size = struct.unpack_from(e + 'IIIIII', d, off)
        secs.append((name, typ, flags, addr, offset, size))
    # shstrtab
    sh = secs[e_shstrndx]
    strtab = d[sh[4]:sh[4] + sh[5]]
    out = {}
    for name, typ, flags, addr, offset, size in secs:
        end = strtab.find(b'\0', name)
        nm = strtab[name:end].decode('latin1')
        out[nm] = dict(type=typ, size=size, addr=addr, offset=offset)
    return out, len(secs), d

def report(path):
    print('=' * 78)
    print('文件: %s  (%d 字节)' % (path, os.path.getsize(path)))
    secs, n, d = sections(path)
    if secs is None:
        print('  不是 ELF'); return
    print('  段数: %d' % n)
    for k in ('__versions', '__kcrctab', '__kcrctab_gpl', '__ksymtab', '__ksymtab_gpl',
              '.modinfo', '__ksymtab_strings', '.gnu.linkonce.this_module', '.text'):
        if k in secs:
            s = secs[k]
            print('  %-32s size=%-8d type=%d' % (k, s['size'], s['type']))
        else:
            print('  %-32s (不存在)' % k)
    # modinfo 内容(modinfo 段里能看到 vermagic / name / srcversion)
    if '.modinfo' in secs:
        s = secs['.modinfo']
        blob = d[s['offset']:s['offset'] + s['size']]
        for line in blob.split(b'\0'):
            if line.startswith((b'vermagic=', b'name=', b'srcversion=', b'depends=')):
                print('    modinfo: %s' % line.decode('latin1'))
    return secs

if __name__ == '__main__':
    for p in sys.argv[1:]:
        report(p)
