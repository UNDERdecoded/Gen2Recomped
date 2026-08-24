def flip(b):
    v=0
    for i in range(8):
        if (b>>i)&1: v|=1<<(7-i)
    return v
def lz3(raw, start=0, limit=0x4000):
    out=bytearray(); i=start; end=min(len(raw), start+limit)
    while i < end:
        b=raw[i]
        if b==0xFF: return bytes(out), i-start+1, True
        if (b>>5)==7:
            if i+1>=end: return bytes(out), i-start, False
            cmd=(b>>2)&7; length=((b&3)<<8)+raw[i+1]+1; i+=2
        else:
            cmd=b>>5; length=(b&31)+1; i+=1
        if cmd==0:
            if i+length>end: return bytes(out), i-start, False
            out+=raw[i:i+length]; i+=length
        elif cmd==1:
            if i>=end: return bytes(out), i-start, False
            out+=bytes([raw[i]])*length; i+=1
        elif cmd==2:
            if i+1>=end: return bytes(out), i-start, False
            a,c=raw[i],raw[i+1]; i+=2
            out+=bytes([a if k%2==0 else c for k in range(length)])
        elif cmd==3:
            out+=bytes(length)
        elif cmd in (4,5,6):
            if i>=end: return bytes(out), i-start, False
            hi=raw[i]
            if hi>=0x80: off=len(out)-(hi&0x7F)-1; i+=1
            else:
                if i+1>=end: return bytes(out), i-start, False
                off=(hi<<8)|raw[i+1]; i+=2
            if off<0: return bytes(out), i-start, False
            for k in range(length):
                src = off-k if cmd==6 else off+k
                v = out[src] if 0<=src<len(out) else 0
                out.append(flip(v) if cmd==5 else v)
        else:
            return bytes(out), i-start, False
        if len(out)>0x4000: return bytes(out), i-start, False
    return bytes(out), end-start, False


# ---------------------------------------------------------------- rendering
#
# Probe tooling for locating assets in an unmapped Gen 2 ROM hack (Pokemon
# Prism).  The point is that a candidate address can be RENDERED and looked at,
# which turns a blind guess into something verifiable -- the same trick the
# project's ROM-ground-truth notes recommend for settling image formats.
#
# Validated against a known answer first: Gold's GameFreakLogoGFX (39:4B81)
# renders "GAMEFRK PRESENTS" at 1bpp, and so does Prism's copy at 27:70EE.
#
#   python3 tools/prism_probe.py raw1 pokeprism.gbc 0x9F0EE 28 out.png
#   python3 tools/prism_probe.py raw2 pokeprism.gbc 0x9C000 512 out.png
#   python3 tools/prism_probe.py lzscan pokeprism.gbc 0x80000 0xD0000
#   python3 tools/prism_probe.py lzshow pokeprism.gbc 0xC3B83 out.png
SHADES = [(255, 255, 255), (170, 170, 170), (85, 85, 85), (0, 0, 0)]


def tiles_1bpp(data, off, n):
    out = []
    for t in range(n):
        b = data[off + t * 8:off + t * 8 + 8]
        if len(b) < 8:
            break
        out.append([((b[y] >> (7 - x)) & 1) * 3 for y in range(8) for x in range(8)])
    return out


def tiles_2bpp(data, off, n):
    out = []
    for t in range(n):
        b = data[off + t * 16:off + t * 16 + 16]
        if len(b) < 16:
            break
        px = []
        for y in range(8):
            lo, hi = b[y * 2], b[y * 2 + 1]
            px += [(((hi >> (7 - x)) & 1) * 2) + ((lo >> (7 - x)) & 1) for x in range(8)]
        out.append(px)
    return out


def sheet(tiles, cols, path, scale=3):
    from PIL import Image
    rows = max(1, (len(tiles) + cols - 1) // cols)
    im = Image.new("RGB", (cols * 8, rows * 8), (255, 0, 255))
    for i, t in enumerate(tiles):
        ox, oy = (i % cols) * 8, (i // cols) * 8
        for y in range(8):
            for x in range(8):
                im.putpixel((ox + x, oy + y), SHADES[t[y * 8 + x]])
    im.resize((im.width * scale, im.height * scale), 0).save(path)


def lzscan(data, lo, hi, minout=640, maxout=0x2000):
    """Offsets whose LZ stream terminates cleanly at a plausible GFX size.

    NOTE: the literal-run prefilter below prunes ~90% of offsets and made the
    scan tractable, but it is also why a sweep of banks 20-33 returned only
    false positives -- a stream that opens with any other command is skipped.
    Drop it (and accept the runtime) before concluding an asset is not there.
    """
    hits = []
    for off in range(lo, min(hi, len(data) - 16)):
        b = data[off]
        if not ((b >> 5) == 0 and (b & 31) >= 6) and (b >> 5) != 7:
            continue
        out, used, ok = lz3(data, off, 0x600)
        if ok and minout <= len(out) <= maxout and len(out) % 16 == 0 and used >= 48:
            hits.append((len(out), off, used))
    hits.sort(reverse=True)
    return hits


if __name__ == "__main__":
    import sys
    mode, path = sys.argv[1], sys.argv[2]
    d = open(path, "rb").read()
    if mode == "raw1":
        sheet(tiles_1bpp(d, int(sys.argv[3], 0), int(sys.argv[4])), 16, sys.argv[5], 6)
    elif mode == "raw2":
        sheet(tiles_2bpp(d, int(sys.argv[3], 0), int(sys.argv[4])), 32, sys.argv[5], 3)
    elif mode == "lzshow":
        out, used, ok = lz3(d, int(sys.argv[3], 0), 0x2000)
        print(f"{len(out)} bytes, {used} consumed, clean={ok}")
        sheet(tiles_2bpp(out, 0, len(out) // 16), 20, sys.argv[4], 3)
    elif mode == "lzscan":
        for size, off, used in lzscan(d, int(sys.argv[3], 0), int(sys.argv[4], 0))[:40]:
            print(f"  {size:5d}B ({size//16:4d} tiles) at 0x{off:06X} "
                  f"bank {off//0x4000:02X}:{(off%0x4000)+0x4000:04X} used={used}")
