"""Stage 1: sample a GB sprite to native resolution, extract palette +
silhouette (light-only flood fill), write sprite_data.json.
Usage: python3 sprite_extract.py <sprite.png>"""
import json
from collections import deque, Counter
from PIL import Image

import sys
SRC = sys.argv[1] if len(sys.argv) > 1 else 'sprite.png'
img = Image.open(SRC).convert('RGB')
W, H = img.size
sx, sy = W // 64, H // 48          # 8x8 blocks
assert sx * 64 == W and sy * 48 == H, (W, H)

# sample block centers -> 64x48
px = img.load()
grid = [[px[x * sx + sx // 2, y * sy + sy // 2] for x in range(64)] for y in range(48)]

# palette
counts = Counter(c for row in grid for c in row)
pal = sorted(counts, key=lambda c: -counts[c])
print('palette:', [(('#%02x%02x%02x' % c), counts[c]) for c in pal])
idx = {c: i for i, c in enumerate(pal)}

lum = lambda c: 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]

# flood fill "outside" from border pixels, blocked by the dark outline
outside = [[False] * 64 for _ in range(48)]
q = deque()
for x in range(64):
    for y in (0, 47):
        if lum(grid[y][x]) > 60 and not outside[y][x]:
            outside[y][x] = True; q.append((x, y))
for y in range(48):
    for x in (0, 63):
        if lum(grid[y][x]) > 60 and not outside[y][x]:
            outside[y][x] = True; q.append((x, y))
while q:
    x, y = q.popleft()
    for nx, ny in ((x+1,y),(x-1,y),(x,y+1),(x,y-1)):
        if 0 <= nx < 64 and 0 <= ny < 48 and not outside[ny][nx] and lum(grid[ny][nx]) > 60:
            outside[ny][nx] = True; q.append((nx, ny))

n_out = sum(r.count(True) for r in outside)
print('outside pixels:', n_out, '(doc says 218)')

# per-band outside count for sanity vs the doc's silhouette table
for r in range(6):
    band = sum(outside[y][x] for y in range(r*8, r*8+8) for x in range(64))
    print(f'  r{r+1}: {band}')

# ascii mask (o = outside)
for y in range(48):
    print(''.join('o' if outside[y][x] else '.' for x in range(64)))

rows = []
for y in range(48):
    rows.append(''.join('.' if outside[y][x] else '%x' % idx[grid[y][x]] for x in range(64)))

json.dump({'pal': ['#%02x%02x%02x' % c for c in pal], 'rows': rows},
          open('sprite_data.json', 'w'))
print('wrote sprite_data.json')
