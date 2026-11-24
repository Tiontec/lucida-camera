#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
页面文案生成器（Claude B）：把 tools/content_src/ 里的 updates.json / about.json / donate.json
生成两端共用的常量文件（运行时不读 json）：
  iOS     : ios/Rebuild/Sources/ContentData.swift
  Android : android/app/src/main/java/com/lucida/camera/ContentData.java
用法：python3 tools/gen_content.py <工程根目录>   （根目录是 iOS 或安卓工程本身，或者同时包含 ios/ 和 android/ 两个文件夹）
改文案：改 content_src 里的 json，再运行本脚本。
"""
import json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "content_src")

def load(name):
    return json.load(open(os.path.join(SRC, name), encoding="utf-8"))

def clean(s):
    """去掉除 <br> 外的标签，<br> 换成换行"""
    s = re.sub(r"<br\s*/?>", "\n", s)
    s = re.sub(r"</?[a-zA-Z][^>]*>", "", s)
    return s.strip()

def split_item(raw):
    """<b>标题</b>正文 → (标题, 正文)；没有粗体前缀 → ('', 正文)"""
    m = re.match(r"^\s*<b>(.+?)</b>(.*)$", raw, re.S)
    if m:
        return clean(m.group(1)).rstrip("：:"), clean(m.group(2))
    return "", clean(raw)

def updates():
    out = []
    for e in load("updates.json"):
        items = [split_item(x) for x in e.get("items", [])]
        group = e.get("group", "old")          # "new" = 新版本记录（默认展开）；"old" = 旧版记录 11.x（默认折叠）
        assert group in ("new", "old"), group
        out.append((e["v"], e["d"], group, items))
    return out

def swift_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'

def gen_swift():
    up = updates(); ab = load("about.json"); dn = load("donate.json")
    L = []; w = L.append
    w("// 自动生成，请勿手改 —— 改 tools/content_src 下的 json 后运行 tools/gen_content.py。")
    w("import Foundation")
    w("")
    w("struct UpdateItem { let title: String; let body: String }")
    w("struct UpdateEntry { let version: String; let date: String; let group: String; let items: [UpdateItem] }")
    w("struct AboutSection { let heading: String; let paragraph: String }")
    w("")
    w("enum ContentData {")
    w("    /// 更新记录，新的在前（来源 updates.json）")
    w("    static let updates: [UpdateEntry] = [")
    for v, d, grp, items in up:
        w("        UpdateEntry(version: %s, date: %s, group: %s, items: [" % (swift_str(v), swift_str(d), swift_str(grp)))
        for t, b in items:
            w("            UpdateItem(title: %s, body: %s)," % (swift_str(t), swift_str(b)))
        w("        ]),")
    w("    ]")
    w("")
    w("    static let aboutTitle = %s" % swift_str(ab["title"]))
    w("    static let aboutVerPrefix = %s" % swift_str(ab["verPrefix"]))
    w("    static let aboutSections: [AboutSection] = [")
    for s in ab["sections"]:
        w("        AboutSection(heading: %s, paragraph: %s)," % (swift_str(s["h"]), swift_str(s["p"])))
    w("    ]")
    w("    static let devName = %s" % swift_str(ab["dev"]["name"]))
    w("    static let devSub = %s" % swift_str(ab["dev"]["sub"]))
    w("")
    h = dn["hero"]; m = dn["modal"]
    w("    static let donateHeroTitle = %s" % swift_str(h["title"]))
    w("    static let donateHeroSub = %s" % swift_str(h["sub"]))
    w("    static let donateFoot = %s" % swift_str(dn["foot"]))
    w("    static let donateEn = %s" % swift_str(m["en"]))
    w("    static let donateModalTitle = %s" % swift_str(m["title"]))
    w("    static let donateLead = %s" % swift_str(m["lead"]))
    w("    static let donateQuote = %s" % swift_str(m["quote"]))
    w("    static let donateScan = %s" % swift_str(m["scan"]))
    w("    static let donateChips: [String] = [%s]" % ", ".join(swift_str(c) for c in m["chips"]))
    w("    static let donateSave = %s" % swift_str(m["save"]))
    w("}")
    return "\n".join(L) + "\n"

def jstr(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'

def gen_java():
    up = updates(); ab = load("about.json"); dn = load("donate.json")
    L = []; w = L.append
    w("package com.lucida.camera;")
    w("")
    w("import java.util.ArrayList;")
    w("import java.util.List;")
    w("")
    w("/** 自动生成，请勿手改 —— 改 tools/content_src 下的 json 后运行 tools/gen_content.py。 */")
    w("final class ContentData {")
    w("    private ContentData() {}")
    w("")
    w("    static final class UpdateItem { final String title, body; UpdateItem(String t, String b) { title = t; body = b; } }")
    w("    static final class UpdateEntry { final String version, date, group; final List<UpdateItem> items;")
    w("        UpdateEntry(String v, String d, String g, List<UpdateItem> i) { version = v; date = d; group = g; items = i; } }")
    w("    static final class Section { final String heading, paragraph; Section(String h, String p) { heading = h; paragraph = p; } }")
    w("")
    w("    /** 更新记录，新的在前（来源 updates.json） */")
    w("    static final List<UpdateEntry> UPDATES = buildUpdates();")
    w("    private static List<UpdateEntry> buildUpdates() {")
    w("        List<UpdateEntry> all = new ArrayList<UpdateEntry>();")
    for v, d, grp, items in up:
        w("        {")
        w("            List<UpdateItem> it = new ArrayList<UpdateItem>();")
        for t, b in items:
            w("            it.add(new UpdateItem(%s, %s));" % (jstr(t), jstr(b)))
        w("            all.add(new UpdateEntry(%s, %s, %s, it));" % (jstr(v), jstr(d), jstr(grp)))
        w("        }")
    w("        return all;")
    w("    }")
    w("")
    w("    static final String ABOUT_TITLE = %s;" % jstr(ab["title"]))
    w("    static final String ABOUT_VER_PREFIX = %s;" % jstr(ab["verPrefix"]))
    w("    static final List<Section> ABOUT_SECTIONS = new ArrayList<Section>();")
    w("    static {")
    for s in ab["sections"]:
        w("        ABOUT_SECTIONS.add(new Section(%s, %s));" % (jstr(s["h"]), jstr(s["p"])))
    w("    }")
    w("    static final String DEV_NAME = %s;" % jstr(ab["dev"]["name"]))
    w("    static final String DEV_SUB = %s;" % jstr(ab["dev"]["sub"]))
    w("")
    h = dn["hero"]; m = dn["modal"]
    w("    static final String DONATE_HERO_TITLE = %s;" % jstr(h["title"]))
    w("    static final String DONATE_HERO_SUB = %s;" % jstr(h["sub"]))
    w("    static final String DONATE_FOOT = %s;" % jstr(dn["foot"]))
    w("    static final String DONATE_EN = %s;" % jstr(m["en"]))
    w("    static final String DONATE_MODAL_TITLE = %s;" % jstr(m["title"]))
    w("    static final String DONATE_LEAD = %s;" % jstr(m["lead"]))
    w("    static final String DONATE_QUOTE = %s;" % jstr(m["quote"]))
    w("    static final String DONATE_SCAN = %s;" % jstr(m["scan"]))
    w("    static final String[] DONATE_CHIPS = {%s};" % ", ".join(jstr(c) for c in m["chips"]))
    w("    static final String DONATE_SAVE = %s;" % jstr(m["save"]))
    w("}")
    return "\n".join(L) + "\n"

def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    outs = []
    # 单个工程：根目录本身就是 iOS 或安卓工程
    if os.path.isdir(os.path.join(root, "Rebuild/Sources")): outs.append((os.path.join(root, "Rebuild/Sources/ContentData.swift"), gen_swift))
    if os.path.isdir(os.path.join(root, "app/src/main/java/com/lucida/camera")): outs.append((os.path.join(root, "app/src/main/java/com/lucida/camera/ContentData.java"), gen_java))
    # 合并目录：根目录下有 ios/ 和 android/
    if os.path.isdir(os.path.join(root, "ios/Rebuild/Sources")): outs.append((os.path.join(root, "ios/Rebuild/Sources/ContentData.swift"), gen_swift))
    if os.path.isdir(os.path.join(root, "android/app/src/main/java/com/lucida/camera")): outs.append((os.path.join(root, "android/app/src/main/java/com/lucida/camera/ContentData.java"), gen_java))
    if not outs:
        print("在 %s 下没找到 iOS 或安卓工程目录" % root); sys.exit(1)
    for p, g in outs:
        open(p, "w", encoding="utf-8").write(g())
        print("写入", p)

if __name__ == "__main__":
    main()
