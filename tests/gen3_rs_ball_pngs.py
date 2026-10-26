"""Independent RGBA check of fresh native RS PNGs against raw cartridge tiles.

Requires Pillow for PNG decoding. Prints only numeric/hash evidence; no art is
written. Usage: python tests/gen3_rs_ball_pngs.py ROM manifest.json QA_PROFILE.
"""
from pathlib import Path
import hashlib,json,re,struct,sys
from PIL import Image
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from gen3_discover import Rom,lz77_at
rom=Path(sys.argv[1]).read_bytes();manifest=json.loads(Path(sys.argv[2]).read_text());profile=Path(sys.argv[3])
assert manifest['version']in ('ruby','sapphire')
assert re.fullmatch(r'gen2recomp-qa-(?:ruby|sapphire)-[0-9]+',profile.name)
reader=Rom(rom);b=manifest['stageOverrides']['BALL_ANIM']
def palette(raw):
 return [bytes(((c&31)*255//31,((c>>5)&31)*255//31,((c>>10)&31)*255//31,255))for c in struct.unpack('<16H',raw)]
def tile(dst,width,raw,pal,tid,cx,cy):
 for y in range(8):
  for x in range(8):
   value=raw[tid*32+y*4+x//2];index=(value>>(4*(x%2)))&15
   if index:
    offset=((cy+y)*width+cx+x)*4;dst[offset:offset+4]=pal[index]
balls=bytearray(192*48*4);opened=lz77_at(reader,b['OPEN_FRAME'])
for i in range(12):
 gp=struct.unpack_from('<I',rom,b['SHEETS']+i*8)[0]-0x08000000;pp=struct.unpack_from('<I',rom,b['PALETTES']+i*8)[0]-0x08000000
 raw=bytearray(lz77_at(reader,gp));pal=palette(lz77_at(reader,pp))
 if i not in (6,10,11):raw[256:384]=opened
 for frame in range(3):
  for t in range(4):tile(balls,48,raw,pal,frame*4+t,frame*16+t%2*8,i*16+t//2*8)
particles=bytearray(8*64*4);raw=lz77_at(reader,b['PARTICLES']);pal=palette(lz77_at(reader,b['PARTICLE_PALETTE']))
for t in range(8):tile(particles,64,raw,pal,t,t*8,0)
checks=[]
for name,expected,size in [('balls',balls,(48,192)),('ball_particles',particles,(64,8))]:
 p=profile/manifest['version']/'assets/generated/battle'/(name+'.png')
 with Image.open(p)as image:
  assert image.size==size;actual=image.convert('RGBA').tobytes()
 assert actual==expected,(name,'native PNG differs from raw cartridge tiles')
 checks.append(dict(file=name+'.png',sha256=hashlib.sha256(p.read_bytes()).hexdigest(),width=size[0],height=size[1],cartridgeDecodedRGBAExact=True,opaquePixels=sum(a>0 for a in actual[3::4])))
print(json.dumps(dict(status='pass',edition=manifest['version'],identity=profile.name,cartridgeSHA1=hashlib.sha1(rom).hexdigest(),art=checks)))
