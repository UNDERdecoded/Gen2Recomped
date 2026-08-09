"""Stages 3+5: reference voxel builder (mirrors the JS in the HTML),
hidden-face culling, and isometric painter previews for verification.
Run after sprite_extract.py in the same directory."""
import json
from PIL import Image, ImageDraw

data = json.load(open('sprite_data.json'))
rows = data['rows']
WHITE, GREY, DARK, BLACK = 0, 1, 2, 3
PAL = [(0xff, 0xff, 0xff), (0xaa, 0xaa, 0xaa), (0x55, 0x55, 0x55), (0x00, 0x00, 0x00),
       (0xb7, 0xc7, 0x8d), (0xb1, 0xc1, 0x87), (0xd9, 0xd3, 0xc2)]
GROUND1, GROUND2, PATH = 4, 5, 6

inside = lambda x, y: 0 <= x < 64 and 0 <= y < 48 and rows[y][x] != '.'
col = lambda x, y: int(rows[y][x])

D = 26                      # wall depth in voxels
vox = {}

def interior_color(sx, sy):
    """side faces shouldn't be solid outline-black: sample inward past the outline"""
    c = col(sx, sy)
    if c != BLACK:
        return c
    step = 1 if sx < 32 else -1
    for d in range(1, 4):
        nx = sx + step * d
        if inside(nx, sy) and col(nx, sy) != BLACK:
            return col(nx, sy)
    return c

# ---- walls: sprite rows 16..47 extruded straight back --------------------
for sy in range(16, 48):
    y = 47 - sy
    for sx in range(64):
        if not inside(sx, sy):
            continue
        front, mid = col(sx, sy), interior_color(sx, sy)
        for z in range(D):
            vox[(sx, y, z)] = front if (z == 0 or z == D - 1) else mid

# ---- awning ledge: rows 24..31 protrude 2 front and back -----------------
for sy in range(24, 32):
    y = 47 - sy
    for sx in range(64):
        if inside(sx, sy):
            c = col(sx, sy)
            for z in (-2, -1, D, D + 1):
                vox[(sx, y, z)] = c

# ---- recess panes: delete the front voxel of every non-black pixel -------
RECESS = [(16, 23, 17, 23), (32, 39, 17, 23), (40, 47, 17, 23),   # gable windows
          (32, 39, 33, 39), (40, 47, 33, 39),                      # ground windows
          (19, 28, 34, 45)]                                        # door interior
for x0, x1, y0, y1 in RECESS:
    for sy in range(y0, y1 + 1):
        for sx in range(x0, x1 + 1):
            if inside(sx, sy) and col(sx, sy) != BLACK:
                vox.pop((sx, 47 - sy, 0), None)

# ---- roof: flat top over x16..47, DIAGONAL sloped ends (1 down per 2 out)
ROOF_Z0, ROOF_Z1 = -4, 29
ROOF_X0, ROOF_X1 = -4, 67
YTOP = 35

def T(x):                              # elevation profile = the sprite's / \ taper
    if x < 16: return YTOP - ((16 - x + 1) // 2)
    if x > 47: return YTOP - ((x - 47 + 1) // 2)
    return YTOP                        # [2,1]/[3,1]: horizontal, flat

def roof_sy(z):
    df, db = z - ROOF_Z0, ROOF_Z1 - z
    if db <= 6: return db              # back rows 0..6 (rim + courses)
    if df <= 8: return 15 - df         # front rows 15..7 (fascia + rim)
    return 5 + ((df - 9) % 4)          # middle: cycle rows 5..8 (course rhythm)

def roof_col(x, z):
    sy = roof_sy(z)
    if 0 <= x < 64 and inside(x, sy):
        return col(x, sy)              # real sprite pixels: slats on ends, courses on top
    if x < 16: return WHITE if x % 3 == 1 else DARK
    if x > 47: return WHITE if x % 3 == 2 else DARK
    return GREY

for x in range(ROOF_X0, ROOF_X1 + 1):
    t = T(x)
    for z in range(ROOF_Z0, ROOF_Z1 + 1):
        outer = x in (ROOF_X0, ROOF_X1) or z in (ROOF_Z0, ROOF_Z1)
        for y in range(t - 3, t + 1):
            if y == t:
                c = BLACK if outer else roof_col(x, z)
            elif outer:
                c = GREY if y == t - 1 else BLACK
            else:
                c = DARK
            vox[(x, y, z)] = c

# trim wall corners that would poke above the sloped ends
for x in range(0, 64):
    t = T(x)
    if t < 31:
        for y in range(t + 1, 32):
            for z in range(0, D):
                vox.pop((x, y, z), None)

# ---- ground plate + path -------------------------------------------------
for x in range(-10, 75):
    for z in range(-12, 39):
        vox[(x, -1, z)] = GROUND1 if (x + z) & 1 else GROUND2
for x in range(17, 31):
    for z in range(-12, 0):
        vox[(x, -1, z)] = PATH

# ---- cull to shell -------------------------------------------------------
shell = []
for (x, y, z), c in vox.items():
    if all((x + dx, y + dy, z + dz) in vox for dx, dy, dz in
           ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1))):
        continue
    shell.append((x, y, z, c))
print('voxels:', len(vox), 'shell:', len(shell))

# ---- isometric preview (front = -z, so mirror z for the render) ----------
S = 4
ZM = 40
pts = []
for x, y, z, c in shell:
    pts.append((x, y, ZM - z, c))
pts.sort(key=lambda p: (p[0] + p[2], p[1]))

def P(x, y, z):
    return (2 * (x - z) * S + 1250, ((x + z) - 2 * y) * S + 300)

img = Image.new('RGB', (1800, 900), (0xca, 0xdc, 0x9f))
dr = ImageDraw.Draw(img)
has = {(x, y, z) for x, y, z, c in pts}
def shade(c, f):
    r, g, b = PAL[c]
    return (int(r * f), int(g * f), int(b * f))
for x, y, z, c in pts:
    if (x, y + 1, z) not in has:   # top
        dr.polygon([P(x, y + 1, z), P(x + 1, y + 1, z), P(x + 1, y + 1, z + 1), P(x, y + 1, z + 1)], fill=shade(c, 1.0))
    if (x + 1, y, z) not in has:   # right (+x)
        dr.polygon([P(x + 1, y, z), P(x + 1, y + 1, z), P(x + 1, y + 1, z + 1), P(x + 1, y, z + 1)], fill=shade(c, 0.62))
    if (x, y, z + 1) not in has:   # toward viewer (original -z front)
        dr.polygon([P(x, y, z + 1), P(x + 1, y, z + 1), P(x + 1, y + 1, z + 1), P(x, y + 1, z + 1)], fill=shade(c, 0.82))
img.save('preview_front.png')

# second angle: from the back-right, no mirror
pts2 = sorted(((x, y, z, c) for x, y, z, c in shell), key=lambda p: (p[0] + p[2], p[1]))
img2 = Image.new('RGB', (1800, 900), (0xca, 0xdc, 0x9f))
dr2 = ImageDraw.Draw(img2)
has2 = {(x, y, z) for x, y, z, c in pts2}
for x, y, z, c in pts2:
    if (x, y + 1, z) not in has2:
        dr2.polygon([P(x, y + 1, z), P(x + 1, y + 1, z), P(x + 1, y + 1, z + 1), P(x, y + 1, z + 1)], fill=shade(c, 1.0))
    if (x + 1, y, z) not in has2:
        dr2.polygon([P(x + 1, y, z), P(x + 1, y + 1, z), P(x + 1, y + 1, z + 1), P(x + 1, y, z + 1)], fill=shade(c, 0.62))
    if (x, y, z + 1) not in has2:
        dr2.polygon([P(x, y, z + 1), P(x + 1, y, z + 1), P(x + 1, y + 1, z + 1), P(x, y + 1, z + 1)], fill=shade(c, 0.82))
img2.save('preview_back.png')
print('previews written')
