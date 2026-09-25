#!/usr/bin/env python3
"""极简 SVG 预览器（零 transform 的扁平 SVG：rect + path 实色填充）。

用途：在没有真机/渲染器的情况下，把生成的图标/字形栅格化成 PNG 自检几何是否正确。
用法：python3 svg-preview.py <in.svg> <out.png> [size] [--bg RRGGBB] [--scale S] [--pen W] [--pen-color RRGGBB]

坐标按 1 viewBox 单位 = 1 内部像素解析（本文件只做几何自检，不做通用 SVG 渲染），
所以 size 只是画布边长，放大看细节用 --scale S（S 倍缩放，输出仍按 size/2 降采样）。

--pen W 模拟 **ArkUI 的默认画笔**：`DrawingPainter::DrawPath` 对每个 Path 固定做两遍绘制
（先 brush 填色、再 pen 描边），`SetPen()` 只在 `strokeWidth(0)` 时才返回 false；不写 strokeWidth
时 pen 用默认值 `STROKE_WIDTH_DEFAULT = 1.0_vp` + `GetStrokeValue(Color::BLACK)`。W 的单位是
viewBox 单位（1vp 在 24 单位 / 30vp 的品牌标里 ≈ 0.8 单位）。加了这个参数就能复现「同一字形被
画两遍、外面多一圈黑边」的重影；不加就是 strokeWidth(0) 修好之后应有的干净结果。
"""
import math
import re
import struct
import sys
import zlib

TOKEN = re.compile(r'([MmLlHhVvCcSsQqTtAaZz])|(-?\d*\.?\d+(?:[eE][-+]?\d+)?)')


def parse_path(d, steps=24):
    """→ [[ (x,y), ... ], ...] 子路径折线（贝塞尔按固定步数离散）。"""
    toks = [m.group(0) for m in TOKEN.finditer(d)]
    subpaths, current = [], []
    x = y = 0.0
    start = (0.0, 0.0)
    i = 0
    cmd = 'M'

    def curve(p0, c1, c2, p1, n=steps):
        pts = []
        for k in range(1, n + 1):
            t = k / n
            u = 1 - t
            pts.append((
                u ** 3 * p0[0] + 3 * u * u * t * c1[0] + 3 * u * t * t * c2[0] + t ** 3 * p1[0],
                u ** 3 * p0[1] + 3 * u * u * t * c1[1] + 3 * u * t * t * c2[1] + t ** 3 * p1[1],
            ))
        return pts

    while i < len(toks):
        if re.match(r'[A-Za-z]', toks[i]):
            cmd = toks[i]
            i += 1
            if cmd in 'Zz':
                if current:
                    current.append(start)
                    subpaths.append(current)
                    current = []
                x, y = start
                continue
        rel = cmd.islower()
        up = cmd.upper()
        take = {'M': 2, 'L': 2, 'H': 1, 'V': 1, 'C': 6, 'S': 4, 'Q': 4, 'T': 2, 'A': 7}[up]
        a = [float(v) for v in toks[i:i + take]]
        i += take
        if up == 'M':
            if current:
                subpaths.append(current)
            px, py = (x + a[0], y + a[1]) if rel else (a[0], a[1])
            x, y = px, py
            start = (px, py)
            current = [(x, y)]
            cmd = 'l' if rel else 'L'
        elif up == 'L':
            x, y = (x + a[0], y + a[1]) if rel else (a[0], a[1])
            current.append((x, y))
        elif up == 'H':
            x = x + a[0] if rel else a[0]
            current.append((x, y))
        elif up == 'V':
            y = y + a[0] if rel else a[0]
            current.append((x, y))
        elif up == 'C':
            c1 = (x + a[0], y + a[1]) if rel else (a[0], a[1])
            c2 = (x + a[2], y + a[3]) if rel else (a[2], a[3])
            p = (x + a[4], y + a[5]) if rel else (a[4], a[5])
            current += curve((x, y), c1, c2, p)
            x, y = p
        elif up == 'S':
            c2 = (x + a[0], y + a[1]) if rel else (a[0], a[1])
            p = (x + a[2], y + a[3]) if rel else (a[2], a[3])
            current += curve((x, y), (x, y), c2, p)
            x, y = p
        elif up == 'Q':
            c = (x + a[0], y + a[1]) if rel else (a[0], a[1])
            p = (x + a[2], y + a[3]) if rel else (a[2], a[3])
            c1 = (x + 2 / 3 * (c[0] - x), y + 2 / 3 * (c[1] - y))
            c2 = (p[0] + 2 / 3 * (c[0] - p[0]), p[1] + 2 / 3 * (c[1] - p[1]))
            current += curve((x, y), c1, c2, p)
            x, y = p
        elif up == 'A':
            rx, ry, rot, large, sweep, ex, ey = a
            px, py = (x + ex, y + ey) if rel else (ex, ey)
            current += arc(x, y, rx, ry, rot, large, sweep, px, py)
            x, y = px, py
    if current:
        subpaths.append(current)
    return subpaths


def arc(x1, y1, rx, ry, rot, large, sweep, x2, y2, steps=20):
    if rx == 0 or ry == 0 or (x1 == x2 and y1 == y2):
        return [(x2, y2)]
    phi = math.radians(rot)
    cp, sp = math.cos(phi), math.sin(phi)
    dx, dy = (x1 - x2) / 2, (y1 - y2) / 2
    x1p = cp * dx + sp * dy
    y1p = -sp * dx + cp * dy
    lam = x1p ** 2 / rx ** 2 + y1p ** 2 / ry ** 2
    if lam > 1:
        s = math.sqrt(lam)
        rx, ry = rx * s, ry * s
    num = rx ** 2 * ry ** 2 - rx ** 2 * y1p ** 2 - ry ** 2 * x1p ** 2
    den = rx ** 2 * y1p ** 2 + ry ** 2 * x1p ** 2
    co = math.sqrt(max(num / den, 0)) * (-1 if large == sweep else 1)
    cxp = co * rx * y1p / ry
    cyp = -co * ry * x1p / rx
    cx = cp * cxp - sp * cyp + (x1 + x2) / 2
    cy = sp * cxp + cp * cyp + (y1 + y2) / 2
    def ang(ux, uy, vx, vy):
        dot = ux * vx + uy * vy
        n = math.hypot(ux, uy) * math.hypot(vx, vy)
        a = math.acos(max(-1, min(1, dot / n)))
        return -a if ux * vy - uy * vx < 0 else a
    t1 = ang(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
    dt = ang((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
    if sweep == 0 and dt > 0:
        dt -= 2 * math.pi
    elif sweep == 1 and dt < 0:
        dt += 2 * math.pi
    pts = []
    for k in range(1, steps + 1):
        t = t1 + dt * k / steps
        px, py = rx * math.cos(t), ry * math.sin(t)
        pts.append((cp * px - sp * py + cx, sp * px + cp * py + cy))
    return pts


def rect_poly(x, y, w, h, rx):
    if rx <= 0:
        return [[(x, y), (x + w, y), (x + w, y + h), (x, y + h)]]
    rx = min(rx, w / 2, h / 2)
    pts = []
    for cx, cy, a0 in ((x + w - rx, y + rx, -math.pi / 2), (x + w - rx, y + h - rx, 0),
                       (x + rx, y + h - rx, math.pi / 2), (x + rx, y + rx, math.pi)):
        for k in range(13):
            t = a0 + math.pi / 2 * k / 12
            pts.append((cx + rx * math.cos(t), cy + rx * math.sin(t)))
    return [pts]


def hex_rgb(text):
    return tuple(int(text[i:i + 2], 16) for i in (1, 3, 5))


def rasterize(svg, size, bg=(255, 255, 255), scale=1.0):
    svg = re.sub(r'<defs>[\s\S]*?</defs>', '', svg)
    shapes = []
    for m in re.finditer(r'<(rect|path)\b([^>]*?)/>', svg):
        attrs = m.group(2)
        fill = re.search(r'\sfill="([^"]+)"', attrs)
        fill = fill.group(1) if fill else 'none'
        if fill == 'none':
            continue
        op = re.search(r'\sfill-opacity="([\d.]+)"', attrs)
        alpha = float(op.group(1)) if op else 1.0
        if m.group(1) == 'rect':
            num = lambda k, d=0.0: float(re.search(r'\s%s="([\d.]+)"' % k, attrs).group(1)) if re.search(r'\s%s="([\d.]+)"' % k, attrs) else d
            polys = rect_poly(num('x'), num('y'), num('width'), num('height'), num('rx'))
        else:
            polys = parse_path(re.search(r'\sd="([^"]+)"', attrs).group(1))
        if scale != 1.0:
            polys = [[(x * scale, y * scale) for x, y in poly] for poly in polys]
        shapes.append((polys, hex_rgb(fill), alpha))
    fg = bytearray(size * size * 3)
    for i in range(0, len(fg), 3):
        fg[i], fg[i + 1], fg[i + 2] = bg
    mask = bytearray(size * size)
    for polys, color, alpha in shapes:
        edges = []
        for poly in polys:
            for i in range(len(poly)):
                (x1, y1), (x2, y2) = poly[i], poly[(i + 1) % len(poly)]
                if y1 != y2:
                    edges.append((x1, y1, x2, y2))
        if not edges:
            continue
        for row in range(size):
            yc = row + 0.5
            xs = []
            for (x1, y1, x2, y2) in edges:
                if (y1 <= yc < y2) or (y2 <= yc < y1):
                    t = (yc - y1) / (y2 - y1)
                    xs.append((x1 + t * (x2 - x1), 1 if y2 > y1 else -1))
            if not xs:
                continue
            xs.sort()
            wind = 0
            for i in range(len(xs) - 1):
                wind += xs[i][1]
                if wind == 0:
                    continue
                x0 = max(0, int(math.ceil(xs[i][0] - 0.5)))
                x1 = min(size, int(math.ceil(xs[i + 1][0] - 0.5)))
                for col in range(x0, x1):
                    at = (row * size + col) * 3
                    mask[row * size + col] = 1
                    for c in range(3):
                        base = fg[at + c]
                        fg[at + c] = int(round(color[c] * alpha + base * (1 - alpha)))
    return fg, mask


def box_width(svg, size):
    """viewBox 宽度 → 1 个 viewBox 单位等于多少内部像素。"""
    m = re.search(r'viewBox="[\d.]+ [\d.]+ ([\d.]+) [\d.]+"', svg)
    if m is None:
        m = re.search(r'\swidth="([\d.]+)"', svg)
    return size / float(m.group(1)) if m else 1.0


def paint_pen(fg, mask, size, radius, color):
    """按 ArkUI 的语义把「默认黑色画笔」再描一遍：覆盖形状边界两侧各 radius 像素。"""
    offs = [(dx, dy)
            for dy in range(-int(math.ceil(radius)), int(math.ceil(radius)) + 1)
            for dx in range(-int(math.ceil(radius)), int(math.ceil(radius)) + 1)
            if dx * dx + dy * dy <= radius * radius]

    def dilate(grid):
        out = bytearray(size * size)
        for y in range(size):
            row = y * size
            for x in range(size):
                if not grid[row + x]:
                    continue
                for dx, dy in offs:
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < size and 0 <= ny < size:
                        out[ny * size + nx] = 1
        return out

    grown = dilate(mask)
    holes = dilate(bytearray(0 if v else 1 for v in mask))
    for i in range(size * size):
        if grown[i] and holes[i]:  # 形状边界两侧 radius 以内 = 画笔覆盖范围
            at = i * 3
            fg[at] = color[0]
            fg[at + 1] = color[1]
            fg[at + 2] = color[2]


def write_png(path, fg, size, box=2):
    out = size // box
    rows = []
    for y in range(out):
        line = bytearray([0])
        for x in range(out):
            acc = [0, 0, 0]
            for dy in range(box):
                for dx in range(box):
                    at = ((y * box + dy) * size + (x * box + dx)) * 3
                    for c in range(3):
                        acc[c] += fg[at + c]
            n = box * box
            line += bytes(v // n for v in acc)
        rows.append(bytes(line))
    raw = b''.join(rows)

    def chunk(tag, data):
        return (struct.pack('>I', len(data)) + tag + data
                + struct.pack('>I', zlib.crc32(tag + data) & 0xFFFFFFFF))

    png = b'\x89PNG\r\n\x1a\n'
    png += chunk(b'IHDR', struct.pack('>IIBBBBB', out, out, 8, 2, 0, 0, 0))
    png += chunk(b'IDAT', zlib.compress(raw, 9))
    png += chunk(b'IEND', b'')
    with open(path, 'wb') as fh:
        fh.write(png)
    return out


if __name__ == '__main__':
    src, dst = sys.argv[1], sys.argv[2]
    rest = [a for a in sys.argv[3:] if not a.startswith('--')]
    size = int(rest[0]) if rest else 512
    text = open(src).read()
    bg = hex_rgb(sys.argv[sys.argv.index('--bg') + 1]) if '--bg' in sys.argv else (255, 255, 255)
    scale = float(sys.argv[sys.argv.index('--scale') + 1]) if '--scale' in sys.argv else 1.0
    fg, mask = rasterize(text, size, bg, scale)
    if '--pen' in sys.argv:
        width = float(sys.argv[sys.argv.index('--pen') + 1])
        hexc = sys.argv[sys.argv.index('--pen-color') + 1] if '--pen-color' in sys.argv else '#000000'
        paint_pen(fg, mask, size, width * scale, hex_rgb(hexc))
    write_png(dst, fg, size)
    print('wrote', dst)
