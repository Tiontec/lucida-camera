#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""澄影图标处理（可复现）：
  1. 原图（玻璃圆角方形，四角是纯黑）→ 从四角泛洪找出黑色角落 → 用最近的玻璃边缘颜色补上 → 不透明完整方形
  2. 方形 → 超椭圆圆角透明蒙版（开屏用，背景交给 LaunchBG）
  3. 开屏图：透明画布 + 图标 + 「澄影」（Noto Sans CJK SC Bold 渲染）
用法：python3 tools/make_icons.py <原图路径> [工程根目录（合并目录或单工程）]
不给根目录则只生成预览到 /home/claude/icons/
输出：iOS AppIcon/icon-1024.png、iOS LaunchIcon/launch-icon.png、安卓 mipmap-*/ic_launcher.png、drawable-nodpi/launch_icon.png
"""
import os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage

FONT = "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc"
DARK = 40          # 亮度低于它的算「黑」（只从四角连通的暗区里取，不会误伤玻璃内部）

def fill_black_corners(img):
    """img: RGB uint8 方形。返回：补好的 RGB。
    做法：只有「从角落连通」的暗区才算黑角；黑角内用周围玻璃颜色做归一化高斯卷积（平滑延续，不会产生条纹）；
    黑角边缘外扩 2 像素一并重画，去掉原图圆角上的深色毛边。"""
    a = np.asarray(img).astype(np.float32)
    lum = a.mean(axis=2)
    dark = lum < DARK
    lab, n = ndimage.label(dark)
    corners = {lab[0, 0], lab[0, -1], lab[-1, 0], lab[-1, -1]} - {0}
    black = np.isin(lab, list(corners)) if corners else np.zeros_like(dark)
    # 过渡带：黑角外缘 2 像素也当成要重画（毛边）
    black_wide = ndimage.binary_dilation(black, iterations=2)
    good = (~black_wide).astype(np.float32)
    sigma = 28.0
    num = np.stack([ndimage.gaussian_filter(a[..., c] * good, sigma) for c in range(3)], axis=2)
    den = ndimage.gaussian_filter(good, sigma)[..., None] + 1e-6
    smooth = num / den
    out = a.copy()
    out[black_wide] = smooth[black_wide]
    print(f"  角落黑色像素：{int(black.sum())} 个（占 {black.mean()*100:.2f}%），过渡带后 {int(black_wide.sum())} 个")
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGB")

def squircle_mask(size, n=5.0, ss=4):
    """超椭圆（近似 iOS 圆角）蒙版，4 倍超采样抗锯齿"""
    big = size * ss
    y, x = np.mgrid[0:big, 0:big].astype(np.float32)
    cx = cy = (big - 1) / 2.0
    r = (big - 1) / 2.0
    inside = (np.abs((x - cx) / r) ** n + np.abs((y - cy) / r) ** n) <= 1.0
    m = Image.fromarray((inside * 255).astype(np.uint8), "L")
    return m.resize((size, size), Image.LANCZOS)

def with_squircle(sq_img):
    m = squircle_mask(sq_img.size[0])
    out = sq_img.convert("RGBA"); out.putalpha(m)
    return out

def launch_image(icon_rgba, W, H, icon_size, icon_top, text_size, text_center_y, text="澄影"):
    canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ic = icon_rgba.resize((icon_size, icon_size), Image.LANCZOS)
    canvas.alpha_composite(ic, ((W - icon_size) // 2, icon_top))
    d = ImageDraw.Draw(canvas)
    font = ImageFont.truetype(FONT, text_size, index=0)
    bbox = d.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    d.text(((W - tw) / 2 - bbox[0], text_center_y - th / 2 - bbox[1]), text, font=font, fill=(255, 255, 255, 255))
    return canvas

def write_assets(root, full, rounded):
    """把图标写进工程：root 可以是合并目录（含 ios/ 与 android/），也可以是单个工程。"""
    ios_base = next((b for b in [os.path.join(root, "ios/Rebuild/Resources/Assets.xcassets"),
                                  os.path.join(root, "Rebuild/Resources/Assets.xcassets")] if os.path.isdir(b)), None)
    and_base = next((b for b in [os.path.join(root, "android/app/src/main/res"),
                                  os.path.join(root, "app/src/main/res")] if os.path.isdir(b)), None)
    out = []
    if ios_base:
        # 1) App 图标：不透明完整方形（iOS 自己会裁圆角）
        p = os.path.join(ios_base, "AppIcon.appiconset/icon-1024.png")
        full.convert("RGB").save(p); out.append(p)
        # 2) 开屏图：透明画布 + 圆角图标 + 「澄影」，背景交给 LaunchBG（深色，与相机界面衔接）
        ls = launch_image(rounded, 720, 870, icon_size=420, icon_top=110, text_size=92, text_center_y=700)
        p = os.path.join(ios_base, "LaunchIcon.imageset/launch-icon.png")
        ls.save(p); out.append(p)
    if and_base:
        # 3) 安卓 launcher：各密度的不透明方形（老系统不做圆角蒙版，所以直接用补好角的方形）
        sizes = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
        for dens, px in sizes.items():
            d = os.path.join(and_base, f"mipmap-{dens}"); os.makedirs(d, exist_ok=True)
            p = os.path.join(d, "ic_launcher.png")
            full.convert("RGB").resize((px, px), Image.LANCZOS).save(p); out.append(p)
        # 4) 安卓开屏：与 iOS 同一套设计，尺寸 480×580
        os.makedirs(os.path.join(and_base, "drawable-nodpi"), exist_ok=True)
        ls = launch_image(rounded, 480, 580, icon_size=280, icon_top=70, text_size=60, text_center_y=470)
        p = os.path.join(and_base, "drawable-nodpi/launch_icon.png")
        ls.save(p); out.append(p)
    return out

def main():
    if len(sys.argv) < 2:
        print(__doc__); sys.exit(1)
    src = sys.argv[1]
    root = sys.argv[2] if len(sys.argv) > 2 else None
    raw = Image.open(src).convert("RGB")
    print("原图", raw.size)
    sq = raw.resize((1024, 1024), Image.LANCZOS)          # 1197x1210 → 1024 方形（横向略压 1%，肉眼看不出）
    full = fill_black_corners(sq)
    rounded = with_squircle(full)
    os.makedirs("/home/claude/icons", exist_ok=True)
    full.save("/home/claude/icons/full_square_1024.png")
    rounded.save("/home/claude/icons/rounded_1024.png")
    if root:
        for p in write_assets(root, full, rounded):
            print("写入", p)

if __name__ == "__main__":
    main()
