#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Swift 引用检查：`类型.成员` 里的成员是不是真的存在（只检查工程自己定义的类型），以及 `st.成员`（st = DualSettings.shared）。
用法：python3 tools/swift_refs.py <Sources 目录>"""
import os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import importlib.util
spec = importlib.util.spec_from_file_location('lint', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'swift_lint.py'))
src_lint = open(spec.origin, encoding='utf-8').read().replace('\nmain()\n', '\n')
ns = {}; exec(compile(src_lint, 'swift_lint', 'exec'), ns)
strip, blocks, members = ns['strip'], ns['blocks'], ns['members']

root = sys.argv[1]
files = sorted(f for f in os.listdir(root) if f.endswith('.swift'))
db = {}   # 类型 -> 成员名集合（含嵌套类型名、枚举 case）
srcs = {}
for f in files:
    s = strip(open(os.path.join(root, f), encoding='utf-8').read()); srcs[f] = s
    for kind, name, st, en in blocks(s):
        short = name.split('.')[-1]
        d = db.setdefault(short, {'kind': kind, 'm': set()})
        for k, n, lab in members(s, st, en): d['m'].add(n)
    # 嵌套类型名也算成员
    for kind, name, st, en in blocks(s):
        for k2, n2, st2, en2 in blocks(s[st+1:en]):
            db.setdefault(name.split('.')[-1], {'kind': kind, 'm': set()})['m'].add(n2.split('.')[-1])
universal = {'self', 'init', 'Type', 'description', 'hashValue', 'allCases', 'rawValue', 'none', 'some'}
problems = []
for f, s in srcs.items():
    for m in re.finditer(r'\b([A-Z][A-Za-z0-9_]*)\.([a-zA-Z_]\w*)', s):
        t, mem = m.group(1), m.group(2)
        if t not in db: continue
        if mem in universal: continue
        if mem in db[t]['m']: continue
        # 枚举里 .case 和隐式成员等：只对 enum / struct / class 报
        line = s.count('\n', 0, m.start()) + 1
        problems.append(f"{f}:{line}: {t}.{mem} —— {t} 里找不到成员 {mem}")
# st.xxx
ds = db.get('DualSettings', {'m': set()})['m']
for f, s in srcs.items():
    if not re.search(r'(let|var)\s+st\s*=\s*DualSettings\.shared', s): continue
    for m in re.finditer(r'\bst\.([a-zA-Z_]\w*)', s):
        if m.group(1) not in ds:
            problems.append(f"{f}:{s.count(chr(10),0,m.start())+1}: st.{m.group(1)} —— DualSettings 里找不到")
for p in problems: print("✗", p)
print(f"引用检查：{len(files)} 个文件，{len(problems)} 个可疑引用")
sys.exit(1 if problems else 0)
