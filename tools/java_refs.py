#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Java 引用检查（没有 android.jar 时用）：
 1. 括号配对；
 2. `类名.成员`（静态引用）：成员必须在该工程类里声明（方法 / 字段 / 嵌套类型 / 枚举常量）；
 3. `new 类名(...).成员(`；
 4. 声明为 DualPrefs / SettingsStore 的变量上访问的字段 / 方法是否存在。
 用法：python3 tools/java_refs.py <java 源码目录>"""
import os, re, sys

def strip(s):
    t = re.sub(r'"(?:\\.|[^"\\])*"', '""', s)
    t = re.sub(r"'(?:\\.|[^'\\])'", "''", t)
    t = re.sub(r'//[^\n]*', '', t)
    t = re.sub(r'/\*.*?\*/', lambda m: '\n' * m.group(0).count('\n'), t, flags=re.S)
    return t

root = sys.argv[1]
srcs = {}
for dp, dn, fn in os.walk(root):
    for f in fn:
        if f.endswith('.java'):
            srcs[f[:-5]] = strip(open(os.path.join(dp, f), encoding='utf-8').read())
problems = []
# 1 括号
for name, s in srcs.items():
    if s.count('{') != s.count('}') or s.count('(') != s.count(')') or s.count('[') != s.count(']'):
        problems.append(f"{name}.java: 括号不配平 {{ {s.count('{')}/{s.count('}')}  ( {s.count('(')}/{s.count(')')}")

def class_body(s, cname):
    m = re.search(r'\b(?:class|interface|enum)\s+' + re.escape(cname) + r'\b[^{]*\{', s)
    if not m: return None
    i = m.end(); depth = 1
    while i < len(s) and depth:
        if s[i] == '{': depth += 1
        elif s[i] == '}': depth -= 1
        i += 1
    return s[m.end():i - 1]

# 成员表：顶层类 + 嵌套类型
members = {}
def collect(cname, body):
    ms = set()
    for m in re.finditer(r'(?:^|[;{}\s])(?:(?:public|private|protected|static|final|abstract|synchronized|native|volatile|transient)\s+)*(?:<[^>]+>\s+)?[A-Za-z_][\w<>\[\],\.\? ]*\s+(\w+)\s*(?=[\(=;,])', body):
        ms.add(m.group(1))
    for m in re.finditer(r'\b(?:class|interface|enum)\s+(\w+)', body): ms.add(m.group(1))
    # 枚举常量
    for m in re.finditer(r'\b(\w+)\s*\(', body): ms.add(m.group(1))
    # 一行多个字段：int a, b, c;
    for m in re.finditer(r'(?:^|\n)\s*(?:(?:public|private|protected|static|final)\s+)*[A-Za-z_][\w<>\[\]\.]*\s+([\w ,=\.\-\+\"\'\(\)0-9]+);', body):
        for part in re.split(r',(?![^()]*\))', m.group(1)):
            nm = re.match(r'\s*(\w+)', part)
            if nm: ms.add(nm.group(1))
    members[cname] = ms
for name, s in srcs.items():
    b = class_body(s, name)
    if b is None: continue
    collect(name, b)
    for m in re.finditer(r'\b(?:static\s+)?(?:final\s+)?(?:class|interface|enum)\s+(\w+)', b):
        nb = class_body(b, m.group(1))
        if nb is not None: collect(name + '.' + m.group(1), nb); members.setdefault(m.group(1), set()).update(members[name + '.' + m.group(1)])
members['DualPrefs'] = members.get('DualPrefs', set())

proj = set(srcs.keys())
for name, s in srcs.items():
    # 2 静态引用 Type.member
    for m in re.finditer(r'(?<![\w\.])([A-Z][A-Za-z0-9]*)\.([A-Za-z_]\w*)', s):
        t, mem = m.group(1), m.group(2)
        if t not in proj or t not in members: continue
        if mem in members[t] or mem in ('class', 'this', 'super'): continue
        problems.append(f"{name}.java:{s.count(chr(10),0,m.start())+1}: {t}.{mem} —— {t} 里找不到")
    # 3 new Type(...).member
    for m in re.finditer(r'new\s+([A-Z]\w*)\s*\([^()]*\)\s*\.\s*(\w+)', s):
        t, mem = m.group(1), m.group(2)
        if t in members and t in proj and mem not in members[t]:
            problems.append(f"{name}.java:{s.count(chr(10),0,m.start())+1}: new {t}(..).{mem} —— 找不到")
    # 4 变量上的字段 / 方法（DualPrefs、SettingsStore）
    for typ in ('DualPrefs', 'SettingsStore'):
        for v in set(re.findall(r'\b' + typ + r'\s+(\w+)\s*[,;=\)]', s)):
            for m in re.finditer(r'(?<![\w\.])' + re.escape(v) + r'\.([A-Za-z_]\w*)', s):
                mem = m.group(1)
                if mem not in members.get(typ, set()):
                    problems.append(f"{name}.java:{s.count(chr(10),0,m.start())+1}: {v}.{mem} —— {typ} 里找不到")
for p in problems: print("✗", p)
print(f"Java 引用检查：{len(srcs)} 个文件，{len(problems)} 个可疑引用")
sys.exit(1 if problems else 0)
