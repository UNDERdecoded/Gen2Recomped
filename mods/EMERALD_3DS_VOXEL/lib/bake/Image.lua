-- The subset of Pillow (12.x) the Emerald 3DS voxel generators use, with
-- Pillow's own arithmetic, so a port computes the same bytes.
--
-- An image: { mode = "RGBA"|"RGB"|"L", width, height, size = {w, h},
--             bands = 4|3|1, buf }.
-- buf is flat, 0-based: channel c of pixel (x, y) is buf[(y*w + x)*bands + c].
-- It is an FFI uint8_t[] whenever the FFI is there (JIT on or off: a table
-- costs 8 bytes per channel, and with the JIT off -- Android -- the GC
-- work on table pixels outweighs cdata's slower interpreted indexing), else
-- a plain Lua table (Image.NO_FFI = true forces tables): both index alike.
--
-- Coordinates are Pillow's (0-based, boxes are {x0, y0, x1, y1} with x1/y1
-- exclusive).  Colours:
--   * as arguments: a number for L; {r, g, b} / {r, g, b, a} tables for
--     RGB/RGBA (a missing alpha is 255, as Pillow's)
--   * get(x, y) returns the channels as multiple values (no allocation);
--     getpixel(x, y) returns a table like Pillow's tuple (or the L value)
--   * getdata() returns a 1-based array of PACKED pixels: L -> v,
--     RGB -> r*65536 + g*256 + b, RGBA -> r*2^24 + g*2^16 + b*2^8 + a
--     (Image.rgb(r, g, b) / Image.rgba(...) pack, Image.unpack_rgb(v) ...)
--   * histogram() returns a 1-based array: Python's histogram()[i] is [i + 1]
--
-- See ARCHITECTURE.md for the Pillow -> Lua table of names.

local V = ...
local bit = require("bit")
local band, bor, rshift, lshift = bit.band, bit.bor, bit.rshift, bit.lshift
local floor, min, max = math.floor, math.min, math.max
local schar, sbyte, concat = string.char, string.byte, table.concat

local ok_ffi, ffi = pcall(require, "ffi")
if not ok_ffi then ffi = nil end

local Image = {}
Image.__index = Image

Image.NEAREST = 0
local BANDS = { RGBA = 4, RGB = 3, L = 1 }

-- the backing store: FFI when there is one (see the header), tables otherwise
local function use_ffi()
  return ffi ~= nil and not Image.NO_FFI
end

local function alloc(n)
  if use_ffi() then
    return ffi.new("uint8_t[?]", max(n, 1))
  end
  local t = {}
  for i = 0, n - 1 do t[i] = 0 end
  return t
end
Image._alloc = alloc

local function make(mode, w, h, buf)
  local bands = BANDS[mode]
  if not bands then error("Image: unsupported mode " .. tostring(mode), 2) end
  local img = setmetatable({ mode = mode, width = w, height = h, size = { w, h }, bands = bands }, Image)
  img.buf = buf or alloc(w * h * bands)
  return img
end
Image._make = make

-- ── packing helpers ─────────────────────────────────────────────────────
function Image.rgb(r, g, b) return r * 65536 + g * 256 + b end
function Image.rgba(r, g, b, a) return r * 16777216 + g * 65536 + b * 256 + a end
function Image.unpack_rgb(v) return floor(v / 65536), floor(v / 256) % 256, v % 256 end
function Image.unpack_rgba(v)
  return floor(v / 16777216), floor(v / 65536) % 256, floor(v / 256) % 256, v % 256
end
-- an RGBA packed value's RGB part (Python's px[:3])
function Image.rgba_to_rgb(v) return floor(v / 256) end

local function color_bytes(mode, color)
  -- Pillow's colour argument -> the bands' bytes
  if color == nil then
    if mode == "RGBA" then return 0, 0, 0, 0 end
    return 0, 0, 0, 0
  end
  if type(color) == "number" then
    if mode == "L" then return color, 0, 0, 0 end
    -- an int colour on a multiband image is packed little-endian (Pillow)
    return color % 256, floor(color / 256) % 256, floor(color / 65536) % 256,
      mode == "RGBA" and floor(color / 16777216) % 256 or 0
  end
  local a = color[4]
  if a == nil then a = 255 end
  if mode == "L" then return color[1], 0, 0, 0 end
  return color[1], color[2], color[3], a
end

-- ── construction ─────────────────────────────────────────────────────────

-- Image.new(mode, w, h, color) -- Python Image.new(mode, (w, h), color)
function Image.new(mode, w, h, color)
  if type(w) == "table" then color = h; w, h = w[1], w[2] end
  local img = make(mode, w, h)
  local c0, c1, c2, c3 = color_bytes(mode, color)
  if c0 ~= 0 or c1 ~= 0 or c2 ~= 0 or c3 ~= 0 then
    local buf, bands = img.buf, img.bands
    local cs = { c0, c1, c2, c3 }
    for i = 0, w * h - 1 do
      local o = i * bands
      for c = 0, bands - 1 do buf[o + c] = cs[c + 1] end
    end
  end
  return img
end

-- Image.frombytes(mode, w, h, bytes)
function Image.frombytes(mode, w, h, data)
  if type(w) == "table" then data = h; w, h = w[1], w[2] end
  local img = make(mode, w, h)
  local n = w * h * img.bands
  if #data < n then error("ValueError: not enough image data", 2) end
  local buf = img.buf
  if use_ffi() then
    ffi.copy(buf, data, n)
  else
    for i = 0, n - 1 do buf[i] = sbyte(data, i + 1) end
  end
  return img
end

function Image:tobytes()
  local n = self.width * self.height * self.bands
  if n == 0 then return "" end
  local buf = self.buf
  if type(buf) == "cdata" then return ffi.string(buf, n) end
  local parts = {}
  local chunk = {}
  for i = 0, n - 1, 4096 do
    local m = min(4096, n - i)
    for k = 1, m do chunk[k] = buf[i + k - 1] end
    for k = m + 1, #chunk do chunk[k] = nil end
    parts[#parts + 1] = schar(unpack(chunk, 1, m))
  end
  return concat(parts)
end

function Image:copy()
  local n = self.width * self.height * self.bands
  local img = make(self.mode, self.width, self.height)
  local src, dst = self.buf, img.buf
  if type(src) == "cdata" and type(dst) == "cdata" then
    ffi.copy(dst, src, n)
  else
    for i = 0, n - 1 do dst[i] = src[i] end
  end
  return img
end

-- ── pixels ───────────────────────────────────────────────────────────────

function Image:get(x, y)
  local b = self.bands
  local o = (y * self.width + x) * b
  local buf = self.buf
  if b == 4 then return buf[o], buf[o + 1], buf[o + 2], buf[o + 3] end
  if b == 3 then return buf[o], buf[o + 1], buf[o + 2] end
  return buf[o]
end

function Image:put(x, y, r, g, b_, a)
  local b = self.bands
  local o = (y * self.width + x) * b
  local buf = self.buf
  buf[o] = r
  if b >= 3 then buf[o + 1] = g; buf[o + 2] = b_ end
  if b == 4 then buf[o + 3] = a end
end

-- packed reads: RGB(A) images -> r*65536+g*256+b (alpha dropped), L -> v
function Image:getrgb(x, y)
  local b = self.bands
  local o = (y * self.width + x) * b
  local buf = self.buf
  if b == 1 then return buf[o] end
  return buf[o] * 65536 + buf[o + 1] * 256 + buf[o + 2]
end

function Image:getalpha(x, y)
  return self.buf[(y * self.width + x) * 4 + 3]
end

local function check_xy(img, x, y)
  if x < 0 or y < 0 or x >= img.width or y >= img.height then
    error("IndexError: image index out of range", 3)
  end
end

-- getpixel((x, y)): a table {r, g, b[, a]} or the L value
function Image:getpixel(x, y)
  if type(x) == "table" then x, y = x[1], x[2] end
  check_xy(self, x, y)
  if self.bands == 1 then return self:get(x, y) end
  return { self:get(x, y) }
end

-- putpixel((x, y), value): value a number (L) or a {r, g, b[, a]} table
function Image:putpixel(x, y, value)
  if type(x) == "table" then value = y; x, y = x[1], x[2] end
  check_xy(self, x, y)
  local c0, c1, c2, c3 = color_bytes(self.mode, value)
  self:put(x, y, c0, c1, c2, c3)
end

-- load(): Pillow's PixelAccess.  Here the image is its own accessor: use
-- img:get(x, y) / img:put(x, y, ...) (or getpixel / putpixel).
function Image:load() return self end

-- getdata(): 1-based array of packed pixels (see the header)
function Image:getdata()
  local out = {}
  local buf, b = self.buf, self.bands
  local n = self.width * self.height
  if b == 1 then
    for i = 0, n - 1 do out[i + 1] = buf[i] end
  elseif b == 3 then
    for i = 0, n - 1 do
      local o = i * 3
      out[i + 1] = buf[o] * 65536 + buf[o + 1] * 256 + buf[o + 2]
    end
  else
    for i = 0, n - 1 do
      local o = i * 4
      out[i + 1] = buf[o] * 16777216 + buf[o + 1] * 65536 + buf[o + 2] * 256 + buf[o + 3]
    end
  end
  return out
end

-- putdata(seq): packed values as getdata gives them (row major, 1-based)
function Image:putdata(seq)
  local buf, b = self.buf, self.bands
  local n = min(#seq, self.width * self.height)
  for i = 0, n - 1 do
    local v = seq[i + 1]
    if b == 1 then
      buf[i] = v
    elseif type(v) == "table" then
      local o = i * b
      buf[o], buf[o + 1], buf[o + 2] = v[1], v[2], v[3]
      if b == 4 then buf[o + 3] = v[4] or 255 end
    elseif b == 3 then
      local o = i * 3
      buf[o], buf[o + 1], buf[o + 2] = floor(v / 65536), floor(v / 256) % 256, v % 256
    else
      local o = i * 4
      buf[o], buf[o + 1], buf[o + 2], buf[o + 3] =
        floor(v / 16777216), floor(v / 65536) % 256, floor(v / 256) % 256, v % 256
    end
  end
end

-- ── geometry ─────────────────────────────────────────────────────────────

-- crop({x0, y0, x1, y1}): outside the image reads as zero (Pillow)
function Image:crop(box)
  local x0, y0, x1, y1 = box[1], box[2], box[3], box[4]
  local w, h = max(0, x1 - x0), max(0, y1 - y0)
  local out = make(self.mode, w, h)
  local b = self.bands
  local sw, sh = self.width, self.height
  local src, dst = self.buf, out.buf
  local cx0, cx1 = max(x0, 0), min(x1, sw)
  if cx1 <= cx0 then return out end
  local run = (cx1 - cx0) * b
  local fast = type(src) == "cdata" and type(dst) == "cdata"
  for y = max(y0, 0), min(y1, sh) - 1 do
    local so = (y * sw + cx0) * b
    local do_ = ((y - y0) * w + (cx0 - x0)) * b
    if fast then
      ffi.copy(dst + do_, src + so, run)
    else
      for i = 0, run - 1 do dst[do_ + i] = src[so + i] end
    end
  end
  return out
end

-- paste(im, box, mask) / paste(colour, box, mask)
--   box: {x, y} or {x0, y0, x1, y1} (nil: {0, 0}); mask: an L or RGBA image
--   (its alpha), blended as Pillow's paste: out = DIV255(out*(255-m) + in*m)
--   over every band, alpha included.
local function div255(a)
  local t = a + 128
  return rshift(rshift(t, 8) + t, 8)
end
Image._div255 = div255

function Image:paste(im, box, mask)
  if type(im) ~= "table" or getmetatable(im) ~= Image then
    -- a colour: fill the box
    local x0, y0, x1, y1
    if box == nil then x0, y0, x1, y1 = 0, 0, self.width, self.height
    elseif #box == 2 then error("paste: a colour needs a 4-tuple box", 2)
    else x0, y0, x1, y1 = box[1], box[2], box[3], box[4] end
    local fill = Image.new(self.mode, x1 - x0, y1 - y0, im)
    return self:paste(fill, { x0, y0 }, mask)
  end
  local dx, dy = 0, 0
  if box ~= nil then dx, dy = box[1], box[2] end
  if box ~= nil and #box == 4 and (box[3] - box[1] ~= im.width or box[4] - box[2] ~= im.height) then
    error("ValueError: images do not match", 2)
  end
  if im.mode ~= self.mode then
    im = im:convert(self.mode)
  end
  local b = self.bands
  local W, H = self.width, self.height
  local w, h = im.width, im.height
  -- clip to the destination
  local sx0, sy0 = 0, 0
  local x0, y0, x1, y1 = dx, dy, dx + w, dy + h
  if x0 < 0 then sx0 = -x0; x0 = 0 end
  if y0 < 0 then sy0 = -y0; y0 = 0 end
  if x1 > W then x1 = W end
  if y1 > H then y1 = H end
  if x1 <= x0 or y1 <= y0 then return end
  local src, dst = im.buf, self.buf
  local run = (x1 - x0) * b
  if mask == nil then
    local fast = type(src) == "cdata" and type(dst) == "cdata" and src ~= dst
    for y = y0, y1 - 1 do
      local so = ((y - y0 + sy0) * w + sx0) * b
      local do_ = (y * W + x0) * b
      if fast then
        ffi.copy(dst + do_, src + so, run)
      elseif src == dst and do_ > so then
        for i = run - 1, 0, -1 do dst[do_ + i] = src[so + i] end
      else
        for i = 0, run - 1 do dst[do_ + i] = src[so + i] end
      end
    end
    return
  end
  -- masked: the mask is read at the same place as the source (Pillow)
  local mb, mstep, mw = mask.buf, 1, mask.width
  local moff = 0
  if mask.mode == "RGBA" then mstep, moff = 4, 3
  elseif mask.mode ~= "L" then error("ValueError: bad transparency mask", 2) end
  if mask.width ~= w or mask.height ~= h then error("ValueError: images do not match", 2) end
  for y = y0, y1 - 1 do
    local sy = y - y0 + sy0
    for x = x0, x1 - 1 do
      local sx = x - x0 + sx0
      local m = mb[(sy * mw + sx) * mstep + moff]
      local so = (sy * w + sx) * b
      local do_ = (y * W + x) * b
      if m == 255 then
        for c = 0, b - 1 do dst[do_ + c] = src[so + c] end
      elseif m ~= 0 then
        local im_ = 255 - m
        for c = 0, b - 1 do
          dst[do_ + c] = div255(dst[do_ + c] * im_ + src[so + c] * m)
        end
      end
    end
  end
end

-- resize((w, h), Image.NEAREST): Pillow's nearest picks source
-- floor((x + 0.5) * sw / w)
function Image:resize(w, h, resample)
  if type(w) == "table" then resample = h; w, h = w[1], w[2] end
  if resample ~= nil and resample ~= Image.NEAREST then
    error("Image.resize: only NEAREST is ported", 2)
  end
  local out = make(self.mode, w, h)
  local b, sw, sh = self.bands, self.width, self.height
  local src, dst = self.buf, out.buf
  for y = 0, h - 1 do
    local sy = floor((y + 0.5) * sh / h)
    for x = 0, w - 1 do
      local sx = floor((x + 0.5) * sw / w)
      local so, do_ = (sy * sw + sx) * b, (y * w + x) * b
      for c = 0, b - 1 do dst[do_ + c] = src[so + c] end
    end
  end
  return out
end

-- ── modes and bands ──────────────────────────────────────────────────────

-- convert(mode): RGBA->RGB drops alpha; RGB->RGBA alpha 255; L->RGB(A)
-- replicates; RGB(A)->L is ITU-R 601-2 luma as Pillow (L24, rounded)
function Image:convert(mode)
  if mode == self.mode then return self:copy() end
  local out = make(mode, self.width, self.height)
  local n = self.width * self.height
  local src, dst = self.buf, out.buf
  local sb, db = self.bands, out.bands
  if db == 1 then
    for i = 0, n - 1 do
      local o = i * sb
      if sb == 1 then dst[i] = src[o]
      else
        -- ((r*19595 + g*38470 + b*7471 + 0x8000) >> 16)
        dst[i] = rshift(src[o] * 19595 + src[o + 1] * 38470 + src[o + 2] * 7471 + 0x8000, 16)
      end
    end
  else
    for i = 0, n - 1 do
      local so, do_ = i * sb, i * db
      if sb == 1 then
        local v = src[so]
        dst[do_], dst[do_ + 1], dst[do_ + 2] = v, v, v
      else
        dst[do_], dst[do_ + 1], dst[do_ + 2] = src[so], src[so + 1], src[so + 2]
      end
      if db == 4 then dst[do_ + 3] = (sb == 4) and src[so + 3] or 255 end
    end
  end
  return out
end

local CHANNEL = { R = 0, G = 1, B = 2, A = 3, L = 0 }

-- getchannel("A") / getchannel(index): an L image
function Image:getchannel(which)
  local c = type(which) == "number" and which or CHANNEL[which]
  if self.mode == "RGB" and which == "A" then error("ValueError: no such channel", 2) end
  local out = make("L", self.width, self.height)
  local n, b = self.width * self.height, self.bands
  local src, dst = self.buf, out.buf
  for i = 0, n - 1 do dst[i] = src[i * b + c] end
  return out
end

-- split(): one L image per band, as a 1-based array
function Image:split()
  local out = {}
  for c = 0, self.bands - 1 do out[c + 1] = self:getchannel(c) end
  return out
end

-- point(fn): the same 256-entry table on every band, as Pillow builds it
-- from a function; results are clipped to 0..255 (and truncated)
function Image:point(fn)
  local lut = {}
  for v = 0, 255 do
    local r = fn(v)
    if type(r) == "boolean" then r = r and 1 or 0 end
    r = floor(r)
    lut[v] = r < 0 and 0 or (r > 255 and 255 or r)
  end
  local out = make(self.mode, self.width, self.height)
  local src, dst = self.buf, out.buf
  for i = 0, self.width * self.height * self.bands - 1 do dst[i] = lut[src[i]] end
  return out
end

-- getbbox(): {x0, y0, x1, y1} of the non-zero pixels, or nil.  RGBA asks
-- its alpha alone (Pillow's alpha_only=True default); RGB any band.
function Image:getbbox()
  local w, h, b = self.width, self.height, self.bands
  local buf = self.buf
  local x0, y0, x1, y1 = w, h, -1, -1
  for y = 0, h - 1 do
    local row = y * w
    for x = 0, w - 1 do
      local o = (row + x) * b
      local on
      if b == 4 then on = buf[o + 3] ~= 0
      elseif b == 3 then on = buf[o] ~= 0 or buf[o + 1] ~= 0 or buf[o + 2] ~= 0
      else on = buf[o] ~= 0 end
      if on then
        if x < x0 then x0 = x end
        if x > x1 then x1 = x end
        if y < y0 then y0 = y end
        y1 = y
      end
    end
  end
  if x1 < 0 then return nil end
  return { x0, y0, x1 + 1, y1 + 1 }
end

-- histogram(): 256 counts per band, band after band, 1-based
function Image:histogram()
  local b = self.bands
  local out = {}
  for i = 1, 256 * b do out[i] = 0 end
  local buf = self.buf
  for i = 0, self.width * self.height - 1 do
    local o = i * b
    for c = 0, b - 1 do
      local k = c * 256 + buf[o + c] + 1
      out[k] = out[k] + 1
    end
  end
  return out
end

-- filter(ImageFilter.MinFilter(n)) / MaxFilter: rank filters over an n x n
-- window, the edges replicated (Pillow expands the image by n//2 first)
function Image:filter(f)
  if f.kind ~= "rank" then error("Image.filter: only MinFilter/MaxFilter are ported", 2) end
  local n = f.size
  local m = floor(n / 2)
  local w, h, b = self.width, self.height, self.bands
  local out = make(self.mode, w, h)
  local src, dst = self.buf, out.buf
  local pick = f.pick
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      for c = 0, b - 1 do
        local best
        for j = -m, m do
          local yy = y + j
          if yy < 0 then yy = 0 elseif yy >= h then yy = h - 1 end
          for i = -m, m do
            local xx = x + i
            if xx < 0 then xx = 0 elseif xx >= w then xx = w - 1 end
            local v = src[(yy * w + xx) * b + c]
            if best == nil or (pick == "min" and v < best) or (pick == "max" and v > best) then best = v end
          end
        end
        dst[(y * w + x) * b + c] = best
      end
    end
  end
  return out
end

function Image:save()
  error("Image.save: the bake writes no pictures (a preview/debug path was reached)", 2)
end

-- ── ImageFilter ──────────────────────────────────────────────────────────
local ImageFilter = {}
function ImageFilter.MinFilter(size) return { kind = "rank", size = size or 3, pick = "min" } end
function ImageFilter.MaxFilter(size) return { kind = "rank", size = size or 3, pick = "max" } end
Image.ImageFilter = ImageFilter

-- ── ImageChops ───────────────────────────────────────────────────────────
-- Same mode required; the result is the size of the overlap (Pillow).
local ImageChops = {}
Image.ImageChops = ImageChops

local function chop2(a, b, f)
  if a.mode ~= b.mode then error("ValueError: images do not match", 3) end
  local w, h = min(a.width, b.width), min(a.height, b.height)
  local out = make(a.mode, w, h)
  local bands = a.bands
  local pa, pb, po = a.buf, b.buf, out.buf
  local aw, bw = a.width, b.width
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local oa, ob, oo = (y * aw + x) * bands, (y * bw + x) * bands, (y * w + x) * bands
      for c = 0, bands - 1 do po[oo + c] = f(pa[oa + c], pb[ob + c]) end
    end
  end
  return out
end

local function clip(v)
  if v < 0 then return 0 end
  if v > 255 then return 255 end
  return v
end

function ImageChops.lighter(a, b) return chop2(a, b, function(x, y) return x > y and x or y end) end
function ImageChops.darker(a, b) return chop2(a, b, function(x, y) return x < y and x or y end) end
function ImageChops.difference(a, b) return chop2(a, b, function(x, y) return x > y and x - y or y - x end) end
-- (in1 * in2) / 255, integer division (Chops.c)
function ImageChops.multiply(a, b) return chop2(a, b, function(x, y) return floor(x * y / 255) end) end
-- clip((in1 - in2) / scale + offset), truncated like C's (int)
function ImageChops.subtract(a, b, scale, offset)
  scale, offset = scale or 1.0, offset or 0
  return chop2(a, b, function(x, y)
    local v = (x - y) / scale + offset
    v = v >= 0 and floor(v) or -floor(-v)
    return clip(v)
  end)
end
function ImageChops.add(a, b, scale, offset)
  scale, offset = scale or 1.0, offset or 0
  return chop2(a, b, function(x, y)
    local v = (x + y) / scale + offset
    v = v >= 0 and floor(v) or -floor(-v)
    return clip(v)
  end)
end
function ImageChops.invert(a)
  local out = make(a.mode, a.width, a.height)
  local src, dst = a.buf, out.buf
  for i = 0, a.width * a.height * a.bands - 1 do dst[i] = 255 - src[i] end
  return out
end

-- ── PNG ──────────────────────────────────────────────────────────────────
-- Image.open(bytes, inflate): decode a PNG (8-bit RGBA/RGB/L/LA/palette,
-- 1/2/4-bit palette and grey, no interlace) to RGBA/RGB/L like Pillow's
-- convert-free open would hand the generators.  `inflate` is
-- love.data.decompress("string", "zlib", ...) (or love.image is used when
-- `Image.decode_with_love` is set and available).
local function py_u32be(s, i)
  local a, b, c, d = sbyte(s, i, i + 3)
  return ((a * 256 + b) * 256 + c) * 256 + d
end

local function paeth(a, b, c)
  local p = a + b - c
  local pa, pb, pc = math.abs(p - a), math.abs(p - b), math.abs(p - c)
  if pa <= pb and pa <= pc then return a end
  if pb <= pc then return b end
  return c
end

function Image.open(data, inflate)
  if data:sub(1, 8) ~= "\137PNG\r\n\26\n" then error("Image.open: not a PNG", 2) end
  local pos = 9
  local w, h, depth, ctype, interlace
  local idat, palette, trns = {}, nil, nil
  while pos <= #data do
    local len = py_u32be(data, pos)
    local kind = data:sub(pos + 4, pos + 7)
    local body = data:sub(pos + 8, pos + 7 + len)
    pos = pos + 12 + len
    if kind == "IHDR" then
      w, h = py_u32be(body, 1), py_u32be(body, 5)
      depth, ctype, interlace = sbyte(body, 9), sbyte(body, 10), sbyte(body, 13)
    elseif kind == "PLTE" then palette = body
    elseif kind == "tRNS" then trns = body
    elseif kind == "IDAT" then idat[#idat + 1] = body
    elseif kind == "IEND" then break end
  end
  if interlace ~= 0 then error("Image.open: interlaced PNGs are not supported", 2) end
  local raw = inflate(concat(idat))
  local chans = ({ [0] = 1, [2] = 3, [3] = 1, [4] = 2, [6] = 4 })[ctype]
  local bpp = math.max(1, floor(chans * depth / 8))
  local stride = floor((w * chans * depth + 7) / 8)
  local prev, rows = {}, {}
  for i = 0, stride - 1 do prev[i] = 0 end
  local p = 1
  for y = 0, h - 1 do
    local ft = sbyte(raw, p); p = p + 1
    local cur = {}
    for i = 0, stride - 1 do
      local x = sbyte(raw, p + i)
      local a = i >= bpp and cur[i - bpp] or 0
      local b = prev[i]
      local c = i >= bpp and prev[i - bpp] or 0
      if ft == 1 then x = x + a
      elseif ft == 2 then x = x + b
      elseif ft == 3 then x = x + floor((a + b) / 2)
      elseif ft == 4 then x = x + paeth(a, b, c) end
      cur[i] = x % 256
    end
    p = p + stride
    rows[y] = cur
    prev = cur
  end
  local function sample(row, x)
    if depth == 8 then return row[x] end
    local per = 8 / depth
    local byte = row[floor(x / per)]
    local shift = 8 - depth * (x % per + 1)
    return rshift(byte, shift) % (2 ^ depth)
  end
  local mode = (ctype == 0 and not trns) and "L" or ((ctype == 2 and not trns) and "RGB" or "RGBA")
  local img = make(mode, w, h)
  for y = 0, h - 1 do
    local row = rows[y]
    for x = 0, w - 1 do
      if ctype == 6 then
        local o = x * 4
        img:put(x, y, row[o], row[o + 1], row[o + 2], row[o + 3])
      elseif ctype == 2 then
        local o = x * 3
        if mode == "RGB" then img:put(x, y, row[o], row[o + 1], row[o + 2])
        else img:put(x, y, row[o], row[o + 1], row[o + 2], 255) end
      elseif ctype == 4 then
        local o = x * 2
        img:put(x, y, row[o], row[o], row[o], row[o + 1])
      elseif ctype == 3 then
        local i = sample(row, x)
        local a = 255
        if trns and i < #trns then a = sbyte(trns, i + 1) end
        img:put(x, y, sbyte(palette, i * 3 + 1), sbyte(palette, i * 3 + 2), sbyte(palette, i * 3 + 3), a)
      else
        local v = sample(row, x)
        if depth < 8 then v = floor(v * 255 / (2 ^ depth - 1)) end
        if mode == "L" then img:put(x, y, v) else img:put(x, y, v, v, v, 255) end
      end
    end
  end
  return img
end

return Image
