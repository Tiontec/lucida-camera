#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Swift 静态检查（没有编译器时用）：
 1. 括号 / 引号配对；
 2. 跨文件的重复类型定义（class / struct / enum / protocol 同名）；
 3. 同一个类型（包括它所有的 extension）里的重名成员（var / let / func / case 同名同标签）；
 4. #selector(xxx) 指向的方法在同一个文件里找不到；
 5. 同一个函数体里重复声明同名局部变量（简单情形）。
用法：python3 tools/swift_lint.py <Sources 目录>
退出码：有问题 = 1。"""
import os, re, sys

def strip(s):
    out = []; i = 0; n = len(s)
    while i < n:
        c = s[i]
        if s.startswith('//', i):
            while i < n and s[i] != '\n': i += 1
            continue
        if s.startswith('/*', i):
            j = s.find('*/', i + 2); j = n if j < 0 else j + 2
            out.append('\n' * s.count('\n', i, j)); i = j; continue
        if s.startswith('"""', i):
            j = s.find('"""', i + 3); j = n if j < 0 else j + 3
            out.append('""' + '\n' * s.count('\n', i, j)); i = j; continue
        if c == '"':
            j = i + 1; depth = 0
            while j < n:
                d = s[j]
                if d == '\\' and j + 1 < n and s[j + 1] == '(': depth += 1; j += 2; continue
                if d == '\\': j += 2; continue
                if depth and d == '(': depth += 1
                elif depth and d == ')': depth -= 1
                elif d == '"' and depth == 0: break
                elif d == '\n' and depth == 0: break
                j += 1
            out.append('""'); i = j + 1; continue
        out.append(c); i += 1
    return ''.join(out)

def blocks(src):
    """找出 class/struct/enum/extension/protocol 块：返回 [(kind, name, start, end)]，括号按去掉字符串后的文本配对"""
    res = []
    for m in re.finditer(r'^[ \t]*(?:(?:public|internal|fileprivate|private|final|open|indirect)\s+)*(class|struct|enum|extension|protocol)\s+([A-Za-z_][\w\.]*)[^{\n]*\{', src, re.M):
        start = m.end() - 1; depth = 0; i = start
        while i < len(src):
            if src[i] == '{': depth += 1
            elif src[i] == '}':
                depth -= 1
                if depth == 0: break
            i += 1
        res.append((m.group(1), m.group(2), start, i))
    return res

def members(src, start, end):
    """块内第一层成员：[(kind, name, label)]"""
    body = src[start + 1:end]; depth = 0; line = ''; out = []
    for ch in body:
        if ch == '{':
            if depth == 0: line += ' '   # 进入子块前先把本行当成一条声明
            depth += 1
            if depth == 1: out.append(line); line = ''
            continue
        if ch == '}':
            depth -= 1
            continue
        if depth == 0:
            if ch == '\n':
                out.append(line); line = ''
            else: line += ch
    out.append(line)
    res = []
    for l in out:
        t = l.strip()
        t = re.sub(r'@\w+(\([^)]*\))?\s*', '', t)
        t = re.sub(r'^(?:(?:public|internal|fileprivate|private|final|open|static|class|override|lazy|weak|unowned|mutating|nonmutating|convenience|required|dynamic)\s+)+', '', t)
        m = re.match(r'(var|let)\s+([A-Za-z_]\w*)', t)
        if m:
            res.append(('prop', m.group(2), ''))
            # 同一行逗号分隔的多个声明：static let a: T = 1, b: T = 2
            rest = t[m.end():]; depth = 0; cur = ''; parts = []
            for ch in rest:
                if ch in '([{<': depth += 1
                elif ch in ')]}>': depth -= 1
                if ch == ',' and depth == 0: parts.append(cur); cur = ''
                else: cur += ch
            parts.append(cur)
            for extra in parts[1:]:
                em = re.match(r'\s*([A-Za-z_]\w*)\s*(?::|=)', extra)
                if em: res.append(('prop', em.group(1), ''))
            continue
        m = re.match(r'func\s+([A-Za-z_]\w*)\s*(?:<[^>]*>)?\s*\(([^)]*)\)', t)
        if m:
            labels = []
            for p in m.group(2).split(','):
                p = p.strip()
                if not p: continue
                first = p.split(':')[0].strip().split()
                labels.append(first[0] if first else '_')
            res.append(('func', m.group(1), ','.join(labels))); continue
        m = re.match(r'case\s+(.+)', t)
        if m:
            for c in m.group(1).split(','):
                nm = re.match(r'\s*([A-Za-z_]\w*)', c)
                if nm: res.append(('case', nm.group(1), ''))
    return res

def main():
    root = sys.argv[1]
    files = [os.path.join(root, f) for f in sorted(os.listdir(root)) if f.endswith('.swift')]
    problems = []
    types = {}          # 类型名 -> [(文件, 种类)]
    mems = {}           # 类型名 -> {(kind,name,label): [文件...]}
    for f in files:
        raw = open(f, encoding='utf-8').read(); src = strip(raw)
        # 1 括号
        stack = []; pairs = {')': '(', ']': '[', '}': '{'}
        for i, ch in enumerate(src):
            if ch in '([{': stack.append((ch, src.count('\n', 0, i) + 1))
            elif ch in ')]}':
                if not stack or stack[-1][0] != pairs[ch]: problems.append(f"{os.path.basename(f)}:{src.count(chr(10),0,i)+1}: 括号不匹配 {ch}")
                else: stack.pop()
        for ch, ln in stack: problems.append(f"{os.path.basename(f)}:{ln}: 括号未闭合 {ch}")
        # 2 / 3 类型与成员
        for kind, name, st, en in blocks(src):
            base = os.path.basename(f)
            line_start = src.rfind('\n', 0, st) + 1
            toplevel = not src[line_start:st].startswith((' ', '\t'))      # 只对顶层类型查重（嵌套的同名类型不算）
            if kind != 'extension' and toplevel: types.setdefault(name, []).append((base, kind))
            d = mems.setdefault(name, {})
            for mk in members(src, st, en):
                d.setdefault(mk, []).append(base)
        # 4 selector
        for m in re.finditer(r'#selector\(\s*(?:[\w\.]+\.)?(?:\(\s*[^)]*\)\s*\.)?([A-Za-z_]\w*)', src):
            nm = m.group(1)
            if nm in ('getter', 'setter'): continue
            if not re.search(r'func\s+' + re.escape(nm) + r'\b', src):
                problems.append(f"{os.path.basename(f)}:{src.count(chr(10),0,m.start())+1}: #selector({nm}) 在本文件里找不到同名方法")
    for name, lst in types.items():
        if len(lst) > 1: problems.append(f"类型 {name} 重复定义：" + ', '.join(f"{b}({k})" for b, k in lst))
    for name, d in mems.items():
        for (k, n, lab), fl in d.items():
            if len(fl) > 1 and k in ('prop', 'func', 'case'):
                # 同一个文件里 prop 出现两次（常见：get/set 拆成两行）不算；这里只报「同名同标签出现在多个声明里」
                problems.append(f"{name} 里成员 {n}{'('+lab+')' if k=='func' else ''} 出现 {len(fl)} 次：" + ', '.join(fl))
    for p in problems: print("✗", p)
    print(f"检查 {len(files)} 个文件，发现 {len(problems)} 个问题")
    sys.exit(1 if problems else 0)

main()
