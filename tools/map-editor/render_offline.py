#!/usr/bin/env python3
"""Rasterise the map editor's 3D mesh OUTSIDE LOVE, so it can be looked at.

WHY THIS EXISTS. The 3D viewport shipped four times without ever drawing a
frame, and every one of those times the tests passed: the matrices were right,
the silhouette was right, the mesh topology was right. What was wrong was a
redeclared shader attribute, and then the drawing being read as a footprint
instead of an elevation -- neither of which any unit test could see, because
both are only visible in the PICTURE.

So this draws the picture. tools/map-editor/dump_mesh.lua builds a small
synthetic map through the real mesher and writes the vertex and index lists;
this rasterises them with the same camera the viewport uses, z-buffered and
textured, and writes a PNG.

    luajit tools/map-editor/dump_mesh.lua      # writes /tmp/mesh.txt
    python3 tools/map-editor/render_offline.py # writes /tmp/view_*.png

A fence must come out as pickets with daylight between them, a wall as a solid
volume, a terrace as a plateau with sides. If it does not, the picture says so
in a way a passing test suite did not."""
import math, struct, zlib, sys

verts, idx = [], []
with open("/tmp/mesh.txt") as f:
    head = f.readline().split()
    n = int(head[1])
    for _ in range(n):
        verts.append([float(x) for x in f.readline().split()])
    assert f.readline().strip() == "--"
    for line in f:
        line = line.strip()
        if line: idx.append(int(line))

# The room fixture's atlas (tools/map-editor/dump_mesh.lua / room.lua):
# tile 0 is floorboards, tile 1 an outlined furniture block.
AW = AH = 128
atlas = [1.0] * (AW * AH)
for y in range(8):
    for x in range(8):
        atlas[y * AW + x] = 0.86 if y % 2 == 0 else 0.66
for y in range(8):
    for x in range(8, 16):
        edge = (x == 8 or x == 15 or y == 0 or y == 7)
        atlas[y * AW + x] = 0.12 if edge else 0.55

def norm(x, y, z):
    d = math.sqrt(x*x + y*y + z*z)
    return (0,0,0) if d < 1e-9 else (x/d, y/d, z/d)

def camera(angle_deg, yaw, dist, fx, fy, fz, w, h):
    pitch = math.radians(max(1.5, min(88.5, angle_deg)))
    sp, cp = math.sin(pitch), math.cos(pitch)
    sy, cy = math.sin(yaw), math.cos(yaw)
    f = (-sp*sy, -cp, -sp*cy)
    ex, ey, ez = fx - f[0]*dist, fy - f[1]*dist, fz - f[2]*dist
    fwd = norm(fx-ex, fy-ey, fz-ez)
    s = norm(-fwd[2], 0, fwd[0])
    u = (s[1]*fwd[2]-s[2]*fwd[1], s[2]*fwd[0]-s[0]*fwd[2], s[0]*fwd[1]-s[1]*fwd[0])
    view = [s[0],u[0],-fwd[0],0, s[1],u[1],-fwd[1],0, s[2],u[2],-fwd[2],0,
            -(s[0]*ex+s[1]*ey+s[2]*ez), -(u[0]*ex+u[1]*ey+u[2]*ez),
            (fwd[0]*ex+fwd[1]*ey+fwd[2]*ez), 1]
    fov, near, far = math.radians(45), 4.0, 20000.0
    fy_ = 1/math.tan(fov/2)
    proj = [0]*16
    proj[0] = fy_/(w/h); proj[5] = fy_
    proj[10] = (far+near)/(near-far); proj[11] = -1
    proj[14] = (2*far*near)/(near-far)
    out = [0]*16
    for c in range(4):
        for r in range(4):
            out[c*4+r] = sum(proj[k*4+r]*view[c*4+k] for k in range(4))
    return out

W, H = 726, 470
FLIP = False

# FRAME WHATEVER WAS DUMPED. The camera used to be a fixed distance over a
# fixed point, which was right for the 4x4-block room fixture and silently
# wrong for anything else: the 8x8 outdoor scene rendered as one wall filling
# the frame, and the picture looked like a bug in the mesher rather than a
# camera parked inside the geometry. A rasteriser you cannot trust to be
# LOOKING at the thing is worse than no rasteriser.
_bx = [min(v[0] for v in verts), max(v[0] for v in verts)]
_by = [min(v[1] for v in verts), max(v[1] for v in verts)]
_bz = [min(v[2] for v in verts), max(v[2] for v in verts)]
FX, FY, FZ = (sum(_bx) / 2, sum(_by) / 2, sum(_bz) / 2)
DIST = max(_bx[1] - _bx[0], _bz[1] - _bz[0], 32) * 1.5
print(f"mesh x {_bx[0]:.0f}..{_bx[1]:.0f}  y {_by[0]:.0f}..{_by[1]:.0f}  "
      f"z {_bz[0]:.0f}..{_bz[1]:.0f}   camera dist {DIST:.0f}")

def render(angle, yaw, path, label, dist=None, fx=None, fz=None):
    dist = DIST if dist is None else dist
    fx = FX if fx is None else fx
    fz = FZ if fz is None else fz
    m = camera(angle, yaw, dist, fx, FY, fz, W, H)
    zbuf = [1e30]*(W*H)
    fb = [(14,16,22)]*(W*H)
    def project(v):
        x, y, z = v[0], v[1], v[2]
        cx = m[0]*x+m[4]*y+m[8]*z+m[12]
        cy = m[1]*x+m[5]*y+m[9]*z+m[13]
        cz = m[2]*x+m[6]*y+m[10]*z+m[14]
        cw = m[3]*x+m[7]*y+m[11]*z+m[15]
        if cw <= 1e-6: return None
        sy = (1-cy/cw)/2*H
        if FLIP: sy = H - sy
        return ((cx/cw+1)/2*W, sy, cz/cw, v[3], v[4], v[5])
    drawn = 0
    for t in range(0, len(idx), 3):
        p = [project(verts[idx[t+k]-1]) for k in range(3)]
        if any(q is None for q in p): continue
        xs = [q[0] for q in p]; ys = [q[1] for q in p]
        minx, maxx = max(0,int(min(xs))), min(W-1,int(max(xs))+1)
        miny, maxy = max(0,int(min(ys))), min(H-1,int(max(ys))+1)
        if minx > maxx or miny > maxy: continue
        (x0,y0,z0,u0,v0,c0),(x1,y1,z1,u1,v1,c1),(x2,y2,z2,u2,v2,c2) = p
        den = (y1-y2)*(x0-x2)+(x2-x1)*(y0-y2)
        if abs(den) < 1e-9: continue
        drawn += 1
        for py in range(miny, maxy+1):
            for pxx in range(minx, maxx+1):
                l0 = ((y1-y2)*(pxx-x2)+(x2-x1)*(py-y2))/den
                l1 = ((y2-y0)*(pxx-x2)+(x0-x2)*(py-y2))/den
                l2 = 1-l0-l1
                if l0 < -1e-4 or l1 < -1e-4 or l2 < -1e-4: continue
                z = l0*z0+l1*z1+l2*z2
                i = py*W+pxx
                if z >= zbuf[i]: continue
                u = l0*u0+l1*u1+l2*u2
                v = l0*v0+l1*v1+l2*v2
                ax = min(AW-1, max(0, int(u*AW)))
                ay = min(AH-1, max(0, int(v*AH)))
                tex = atlas[ay*AW+ax]
                shade = (l0*c0+l1*c1+l2*c2)/255.0
                g = max(0, min(255, int(tex*shade*255)))
                zbuf[i] = z
                fb[i] = (g, g, int(g*0.96))
    raw = b"".join(b"\x00" + b"".join(bytes(fb[y*W+x]) for x in range(W)) for y in range(H))
    def chunk(tag, d):
        c = struct.pack(">I", len(d)) + tag + d
        return c + struct.pack(">I", zlib.crc32(tag+d) & 0xffffffff)
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))
    open(path, "wb").write(png)
    print(f"{label}: {drawn} triangles rasterised -> {path}")

render(35,   0.61, "/tmp/room_user.png",  "USER  pitch 35 yaw 0.61")
FLIP = True
render(35,   0.61, "/tmp/room_flip.png",  "USER, vertically flipped")
render(1.5,  0.0,  "/tmp/room_top.png",   "TOP   pitch 1.5")
render(88.5, 0.0,  "/tmp/room_front.png", "FRONT pitch 88.5")
