#!/usr/bin/env python3
"""粗略的 Swift 语法检查：去掉字符串 / 注释后检查 () [] {} 是否配对。不是编译器，只能抓括号 / 引号错误。"""
import sys, re
def check(path):
    s = open(path, encoding='utf-8').read()
    out = []; i = 0; n = len(s); stack = []; line = 1; errs = []
    pairs = {')': '(', ']': '[', '}': '{'}
    while i < n:
        c = s[i]
        if c == '\n': line += 1
        if s.startswith('//', i):
            while i < n and s[i] != '\n': i += 1
            continue
        if s.startswith('/*', i):
            j = s.find('*/', i + 2); j = n if j < 0 else j + 2
            line += s.count('\n', i, j); i = j; continue
        if s.startswith('"""', i):
            j = s.find('"""', i + 3); j = n if j < 0 else j + 3
            line += s.count('\n', i, j); i = j; continue
        if c == '"':
            j = i + 1; depth = 0
            while j < n:
                d = s[j]
                if d == '\\' and j + 1 < n and s[j+1] == '(':
                    depth += 1; j += 2; continue
                if d == '\\': j += 2; continue
                if depth and d == '(': depth += 1
                elif depth and d == ')': depth -= 1
                elif d == '"' and depth == 0: break
                elif d == '\n' and depth == 0: errs.append((line, '字符串没有闭合')); break
                j += 1
            i = j + 1; continue
        if c in '([{': stack.append((c, line))
        elif c in ')]}':
            if not stack or stack[-1][0] != pairs[c]: errs.append((line, '多余或不匹配的 ' + c))
            else: stack.pop()
        i += 1
    for c, l in stack: errs.append((l, '未闭合的 ' + c))
    return errs
bad = False
for p in sys.argv[1:]:
    e = check(p)
    print(('✗ ' if e else '✓ ') + p + ('' if not e else '  ' + str(e[:5])))
    bad = bad or bool(e)
sys.exit(1 if bad else 0)
