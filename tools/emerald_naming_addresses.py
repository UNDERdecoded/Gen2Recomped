"""Identify Emerald naming graphics from its native SpriteSheet table."""
from pathlib import Path
import struct
r = Path('Pokemon - Emerald Version (USA, Europe).gba').read_bytes()
needle = struct.pack('<I',0x08dd3778)
p = 0
while True:
    p = r.find(needle,p)
    if p < 0: break
    print('palette reference',hex(p),[(hex(i),hex(struct.unpack_from('<I',r,i)[0])) for i in range(p-12,p+24,4)])
    p += 1
sizes = [0x1e0,0x1e0,0x280,0x100,0x60,0x60,0x60,0x80,0x80,0x80,0x20,0x20]
for at in range(0,len(r)-104,4):
    if all(struct.unpack_from('<HH',r,at+i*8+4)==(size,i) for i,size in enumerate(sizes)):
        pointers=[struct.unpack_from('<I',r,at+i*8)[0]-0x8000000 for i in range(12)]
        if not all(0<=p<len(r) for p in pointers): continue
        print('sSpriteSheets',hex(at),'graphics', [hex(p) for p in pointers])
        for p in range(pointers[2]-0x2000,pointers[2],4):
            if r[p:p+4]==bytes([0x10,0,6,0]): print('menu candidate',hex(p), 'pal',hex(p-192))
        for p in range(pointers[-1]+32,pointers[-1]+0x500,4):
            if r[p]==0x10 and int.from_bytes(r[p+1:p+4],'little') in (0x800,0x500): print('map candidate',hex(p))
