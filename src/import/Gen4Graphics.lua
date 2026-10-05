-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Gen 4 (Platinum) graphics: Nitro containers, palettes, tiles, tilemaps and
-- the LZ77 the cartridge wraps most of them in.
--
-- Every later stage needs this, which is why it comes before maps and items.
-- A DS graphic is not a blob at an address the way a Gen 1-3 one is; it is a
-- small tagged container, and there are four of them that matter:
--
--   NCLR  "RLCN"  palette   -- section TTLP, BGR555 colours
--   NCGR  "RGCN"  tiles     -- section RAHC, 8x8 tiles, 4bpp or 8bpp
--   NSCR  "RCSN"  tilemap   -- section NRCS, u16 per cell
--   NCER  "RECN"  cells     -- section CEBK, sprite assembly (not parsed here)
--
-- THE MAGICS ARE STORED REVERSED, exactly as NarcArchive's chunk tags are:
-- the file tagged NCLR begins with the bytes "RLCN".  Both spellings appear
-- in circulation, so this compares the four bytes that are actually there.
--
-- WHAT WAS MEASURED RATHER THAN ASSUMED.
--
--   * Section layout is found by WALKING from headerSize for sectionCount
--     chunks, never by fixed offset -- both fields exist because they vary.
--   * The bit depth is confirmed by ARITHMETIC, not by trusting the enum:
--     a 4bpp tile is 32 bytes, so tilesX * tilesY * 32 == dataSize settles
--     it.  pokegra's sprite sheets are 20x10 tiles and 6400 bytes, which is
--     4bpp exactly.
--   * The colour count is dataSize / 2 rather than read from the depth
--     field, which is the one field here whose meaning did not survive
--     inspection: a 16-colour Platinum palette carries 4 where the published
--     tables say 3.  Since the byte count is unambiguous and self-checking,
--     nothing needs the enum to be right.
--   * tilesX / tilesY are 0xFFFF on an UNSIZED graphic -- every party icon
--     is one.  Those get their shape from the NCER cell bank, or from the
--     caller; `tiles` is always correct because it comes from the byte
--     count.  Reading 0xFFFF as a width produces a 65535-tile-wide image and
--     an out-of-memory rather than a wrong picture, which at least fails
--     loudly, but it still has to be handled.
--
-- VALIDATION.  The parser was run against the cartridge and the result
-- looked at, not just counted: all 540 party icons in
-- /poketool/icongra/pl_poke_icon.narc render as recognisable Pokemon in the
-- right colours.  The LZ was checked on every compressed member of four
-- graphics archives -- 125 of 125 decompress to exactly their declared size
-- and every one of them turns out to be a valid Nitro container (48 NCGR,
-- 27 NSCR, 23 NCER, 23 NANR).
--
-- THE BATTLE SPRITES NEED TWO MORE THINGS, and both of them look like the
-- other one when you only have one.  pokegra and otherpoke are ENCRYPTED
-- (see decryptSprite) and they are also stored as LINEAR BITMAPS rather than
-- as 8x8 tiles (see `bitmap`).  Decrypt without un-tiling and you get real
-- Pokemon colours smeared into horizontal bands, which reads as "the cipher
-- is nearly right"; un-tile without decrypting and you get noise, which reads
-- as "the layout is fine, the cipher is wrong".  Neither is a clue about the
-- other, and chasing either one alone goes nowhere.

local Gen4Graphics = {}

local byte, sub, floor = string.byte, string.sub, math.floor
local min = math.min
local char, concat = string.char, table.concat

local function u16(s, at)
  local a, b = byte(s, at, at + 1)
  if not b then return nil end
  return a + b * 256
end

local function u32(s, at)
  local a, b, c, d = byte(s, at, at + 3)
  if not d then return nil end
  return a + b * 256 + c * 65536 + d * 16777216
end

-- The archives whose NCGR tile data is encrypted.  Measured, not guessed:
-- these four sit at byte entropy ~7.98 raw and drop to ~0.9 once decrypted,
-- while the trainer sprites in trfgra/trbgra are already 4.8-5.3 raw and are
-- NOT encrypted -- they are merely linear, which is a separate thing.
Gen4Graphics.ENCRYPTED = {
  ["/poketool/pokegra/pl_pokegra.narc"] = true,
  ["/poketool/pokegra/pokegra.narc"] = true,
  ["/poketool/pokegra/otherpoke.narc"] = true,
  ["/poketool/pokegra/pl_otherpoke.narc"] = true,
}

-- pokegra's stride: six members per species -- four NCGR (back female, back
-- male, front female, front male) then two NCLR (normal, shiny).
Gen4Graphics.POKEGRA_STRIDE = 6
Gen4Graphics.POKEGRA_FRONT = 3
Gen4Graphics.POKEGRA_PALETTE = 4
Gen4Graphics.POKEGRA_SHINY = 5

-- ---------------------------------------------------------------------------
-- LZ77, Nitro type 0x10
-- ---------------------------------------------------------------------------

-- A member whose first byte is 0x10 is compressed and the next three bytes
-- are the DECOMPRESSED size, little-endian.  Then flag bytes, each covering
-- eight slots from the high bit down: a clear bit copies one literal byte, a
-- set bit is a two-byte back-reference of (hi >> 4) + 3 bytes from
-- ((hi & 0xF) << 8 | lo) + 1 back.
--
-- The back-reference may overlap what it is still writing -- a run of one
-- byte repeated is spelled as a distance of 1 -- so this copies one byte at a
-- time rather than slicing, which would read the pre-copy state and quietly
-- produce the wrong bytes on exactly the runs that compress best.
function Gen4Graphics.isCompressed(data)
  if type(data) ~= "string" or #data <= 4 or byte(data, 1) ~= 0x10 then return false end
  -- THE SIZE MUST BE NON-ZERO, and the check is not pedantry.  Platinum's four
  -- NFGR fonts begin `10 00 00 00` -- 0x10 is the font's own data offset, not a
  -- compression tag -- so a test on the first byte alone accepts them, reads a
  -- declared output size of ZERO, and returns an empty string.  Not an error and
  -- not garbage: the file simply vanishes, and the caller sees a zero-length
  -- member rather than a misread one.  A real LZ member never declares zero,
  -- because there would be nothing to decompress.
  local a, b, c = byte(data, 2, 4)
  return (a + b * 256 + c * 65536) > 0
end

function Gen4Graphics.decompress(data)
  if not Gen4Graphics.isCompressed(data) then return data end
  local a, b, c = byte(data, 2, 4)
  local size = a + b * 256 + c * 65536
  local out, n, p = {}, 0, 5
  local len = #data
  while n < size and p <= len do
    local flags = byte(data, p); p = p + 1
    for bit = 7, 0, -1 do
      if n >= size then break end
      if floor(flags / 2 ^ bit) % 2 == 1 then
        local hi, lo = byte(data, p, p + 1)
        if not lo then return nil, "LZ stream ends inside a back-reference" end
        p = p + 2
        local count = floor(hi / 16) + 3
        local dist = (hi % 16) * 256 + lo + 1
        if dist > n then return nil, "LZ back-reference points before the start" end
        for _ = 1, count do
          n = n + 1
          out[n] = out[n - dist]
          if n >= size then break end
        end
      else
        local v = byte(data, p)
        if not v then return nil, "LZ stream ends inside a literal" end
        p = p + 1
        n = n + 1
        out[n] = string.char(v)
      end
    end
  end
  if n < size then return nil, ("LZ produced %d of %d bytes"):format(n, size) end
  return table.concat(out, "", 1, size)
end

-- ---------------------------------------------------------------------------
-- The battle-sprite cipher
-- ---------------------------------------------------------------------------

-- pokegra and otherpoke XOR their tile data with a keystream from the same
-- linear congruential generator the series uses everywhere else:
--
--   key = the FIRST halfword of the data
--   for each halfword:  plain = cipher ~ key;  key = (key * 0x41C64E6D + 0x6073) % 2^16
--
-- Only the low 16 bits of the state ever matter, because the output is the
-- low 16 bits and an LCG's low bits depend on nothing above them -- so this
-- keeps the state in 16 bits and never needs 32-bit arithmetic Lua 5.1 would
-- make awkward.
--
-- The first halfword being the key is the same statement as "the first
-- halfword of the picture is transparent", since anything XORed with itself
-- is zero.  Every sprite in the cartridge begins with blank pixels, so this
-- is self-seeding and there is no table of keys anywhere.
--
-- HOW THIS WAS FOUND, because the wrong way round wasted real time.  The
-- published constants were tried first and appeared to fail, then all eight
-- combinations of seed/direction/key-half failed, then a brute force over all
-- 65,536 seeds failed.  Every one of those was scored against MEMBER 0 of
-- pl_pokegra -- which is a placeholder that decrypts to noise no matter what
-- you do to it.  The algorithm had been right the whole time and the test
-- subject was the problem.
--
-- What settled it was not another guess: assume the leading plaintext is
-- zero, read the leading ciphertext AS the keystream, and solve the
-- recurrence k[i+1] = (k[i]*A + C) mod 2^16 for A and C from the values
-- themselves.  34 of 38 sprites gave A = 0x4E6D and C = 0x6073 -- which is
-- exactly the published LCG -- and the four that disagreed are the ones whose
-- first tile is not blank, so the "keystream" read from them included
-- picture.  Solving beats searching when the unknown is small.
function Gen4Graphics.decryptSprite(pixels)
  if type(pixels) ~= "string" or #pixels < 2 then return pixels end
  local key = byte(pixels, 1) + byte(pixels, 2) * 256
  local out, n = {}, 0
  for i = 1, #pixels - 1, 2 do
    local lo, hi = byte(pixels, i, i + 1)
    local v = lo + hi * 256
    -- XOR of two 16-bit values, arithmetically: see Gen4Text.xor16 for why
    -- this is not the `bit` library.
    local r, place, a, b = 0, 1, v, key
    for _ = 1, 16 do
      local x, y = a % 2, b % 2
      if x ~= y then r = r + place end
      a, b, place = floor(a / 2), floor(b / 2), place * 2
    end
    n = n + 1
    out[n] = string.char(r % 256, floor(r / 256))
    key = (key * 0x41C64E6D + 0x6073) % 65536
  end
  return table.concat(out)
end

-- ---------------------------------------------------------------------------
-- The container
-- ---------------------------------------------------------------------------

-- Decompresses first when needed, so callers never have to ask.
function Gen4Graphics.container(data)
  data = Gen4Graphics.decompress(data)
  if type(data) ~= "string" or #data < 16 then
    return nil, "not a Nitro container: too short"
  end
  local magic = sub(data, 1, 4)
  local headerSize, count = u16(data, 13), u16(data, 15)
  if not (headerSize and count) or headerSize < 16 or count == 0 then
    return nil, ("not a Nitro container: magic %q"):format(magic)
  end
  local sections, at = {}, headerSize + 1
  for _ = 1, count do
    if at + 8 > #data + 1 then break end
    local tag = sub(data, at, at + 3)
    local size = u32(data, at + 4)
    if not size or size < 8 then break end
    -- `at` is the tag; `body` is where this section's own fields start.
    sections[tag] = { at = at, size = size, body = at + 8 }
    at = at + size
  end
  return { magic = magic, data = data, sections = sections }
end

-- ---------------------------------------------------------------------------
-- NCLR: palettes
-- ---------------------------------------------------------------------------

-- BGR555 -> three 0-255 INTEGER channels.  The 5-bit value is scaled by
-- *255/31 rather than shifted left by three, so that 31 comes out as a true
-- 255 and the brightest colour in the cartridge is the brightest colour on
-- screen; shifting leaves white at 248 and every image slightly dim.
--
-- Rounded to integers rather than left as the division's float: these are
-- channel values, callers format them with %d and hand them to image writers
-- that want bytes, and under Lua 5.3+ a float silently fails an integer
-- conversion instead of quietly truncating.
local function ch(x) return floor(x * 255 / 31 + 0.5) end
local function bgr555(v)
  return ch(v % 32), ch(floor(v / 32) % 32), ch(floor(v / 1024) % 32)
end
Gen4Graphics.bgr555 = bgr555

-- Returns a flat array of { r, g, b } and the colours-per-palette the file
-- declares, so a caller can slice it into sub-palettes.
function Gen4Graphics.palette(data)
  local c = Gen4Graphics.container(data)
  if not c then return nil, "not a palette" end
  local s = c.sections.TTLP
  if not s then return nil, "NCLR has no TTLP section" end
  local size = u32(c.data, s.body + 8)
  local perPalette = u32(c.data, s.body + 12)
  local at = s.body + 16
  -- !! THE STATED SIZE IS A VRAM ALLOCATION, NOT THE DATA LENGTH, and trusting
  -- it reads past the end of the section.
  --
  -- The move-effect palettes are the case that proves it: every one of the 39
  -- members of wepltt.narc states 480 bytes -- fifteen full banks -- inside a
  -- TTLP section of FIFTY-SIX. The loop ran to 239 entries, walked off the
  -- section, and only stopped when the file ended, so about twenty real colours
  -- were followed by five made of whatever came next. Clamped to what the
  -- section actually holds, which is the one number that cannot be a promise
  -- about VRAM.
  --
  -- Exactly the same trap as Gen 2's sprite_header length byte, which is the
  -- VRAM allocation and not the sheet size. Two generations, one mistake.
  local room = floor(((s.size or 16) - 16) / 2)
  local stated = floor((size or 0) / 2)
  local count = (room < stated) and room or stated
  if count < 0 then count = 0 end
  -- A COMPRESSED PALETTE (a PMCP section, nitro's `-pcmp`) says itself how
  -- many 16-colour palettes it holds and which slot each goes to, and its
  -- TTLP size may be written INVERTED (`-invertsize`: 0x200 - size). The
  -- Poffin Case's background.NCLR states 160 bytes for eleven palettes; read
  -- by the size it came out five palettes long, and the case's screens
  -- composed with the wrong colours or none. With a PMCP the slot list is
  -- the authority, each palette placed at its slot.
  local pm = c.sections.PMCP
  if pm then
    local n = u16(c.data, pm.body) or 0
    local listAt = pm.body + (u32(c.data, pm.body + 4) or 8) - 0
    -- a PMCP palette is sixteen colours at 4bpp and 256 at 8bpp (depth 4,
    -- an extended palette): the credits' memories are the latter, and read
    -- sixteen at a time they came out in their first sixteen colours only
    local per = (u32(c.data, s.body) == 4) and 256 or 16
    local out = {}
    for k = 0, n - 1 do
      local slot = u16(c.data, listAt + k * 2)
      if slot == nil or (k + 1) * per > room then break end
      for i = 0, per - 1 do
        local v = u16(c.data, at + (k * per + i) * 2)
        if v then
          local r, g, b = bgr555(v)
          out[slot * per + i + 1] = { r, g, b }
        end
      end
    end
    -- slots that no palette fills stay black rather than holes, so `#` and
    -- ipairs over the result behave as they do for an ordinary file
    local top = 0
    for i in pairs(out) do if i > top then top = i end end
    for i = 1, top do out[i] = out[i] or { 0, 0, 0 } end
    if top > 0 then return out, perPalette end
  end
  local out = {}
  for i = 0, count - 1 do
    local v = u16(c.data, at + i * 2)
    if not v then break end
    local r, g, b = bgr555(v)
    out[i + 1] = { r, g, b }
  end
  return out, perPalette
end

-- ---------------------------------------------------------------------------
-- NCGR: tiles
-- ---------------------------------------------------------------------------

local UNSIZED = 0xFFFF

function Gen4Graphics.tiles(data)
  local c = Gen4Graphics.container(data)
  if not c then return nil, "not a tile sheet" end
  local s = c.sections.RAHC
  if not s then return nil, "NCGR has no RAHC section" end
  local tilesY, tilesX = u16(c.data, s.body), u16(c.data, s.body + 2)
  local depth = u32(c.data, s.body + 4)
  local size = u32(c.data, s.body + 16)
  local offset = u32(c.data, s.body + 20)
  if not (size and offset) then return nil, "NCGR header is truncated" end

  -- Believe the arithmetic over the enum.  32 bytes per 4bpp tile, 64 per
  -- 8bpp; when the sheet declares a size, that settles it outright.
  -- THE LAYOUT FLAG, at the field's low byte.  0 means the data is 8x8 tiles
  -- in reading order; 1 means it is a LINEAR BITMAP, row after row, with no
  -- tiling at all.  Measured across every NCGR in the cartridge: 3,872 tiled
  -- against 4,160 linear, and the split is not arbitrary -- every sprite
  -- archive (pokegra, otherpoke, and the trainer sheets trfgra/trbgra) is
  -- linear, while fonts, icons and backgrounds are tiled.
  local layout = u16(c.data, s.body + 12) or 0
  local bitmap = (layout % 256) == 1

  local bpp = (depth == 4) and 8 or 4
  if tilesX and tilesY and tilesX ~= UNSIZED and tilesY ~= UNSIZED then
    if tilesX * tilesY * 32 == size then bpp = 4
    elseif tilesX * tilesY * 64 == size then bpp = 8 end
  end
  local perTile = (bpp == 8) and 64 or 32

  return {
    tilesX = (tilesX ~= UNSIZED) and tilesX or nil,
    tilesY = (tilesY ~= UNSIZED) and tilesY or nil,
    bitmap = bitmap,
    bpp = bpp,
    count = floor(size / perTile),
    perTile = perTile,
    -- `offset` is relative to the START OF THE SECTION'S FIELDS, which is
    -- what `body` already is -- adding the 8-byte tag/size header a second
    -- time shifts every sheet eight bytes into itself.  That produces a
    -- picture, not a crash: recognisable shapes displaced by a quarter tile,
    -- which is exactly the kind of wrong that survives a glance.
    pixels = sub(c.data, s.body + offset, s.body + offset + size - 1),
  }
end

-- ---------------------------------------------------------------------------
-- NSCR: tilemaps
-- ---------------------------------------------------------------------------

-- Each cell is one u16: tile index in the low 10 bits, then horizontal flip,
-- vertical flip, and a 4-bit sub-palette.
function Gen4Graphics.tilemap(data)
  local c = Gen4Graphics.container(data)
  if not c then return nil, "not a tilemap" end
  local s = c.sections.NRCS
  if not s then return nil, "NSCR has no NRCS section" end
  local w, h = u16(c.data, s.body), u16(c.data, s.body + 2)
  local size = u32(c.data, s.body + 8)
  local cells, at = {}, s.body + 12

  -- !! NOT EVERY TILEMAP IS TWO BYTES A CELL.
  --
  -- Reported from play: "14. The trainer card is the Game Boy one, not
  -- Platinum's".  It was, because the port could not compose Platinum's:
  -- `trainer_card_front` came out 6,760 opaque pixels of 65,536, a
  -- scattering of blocks, and the screen fell back to drawing a box and
  -- some text.
  --
  -- An AFFINE background's map is ONE BYTE A CELL -- a bare tile number,
  -- with no flip bits and no sub-palette, because an affine layer is
  -- always 256-colour.  Read two bytes at a time it yields half as many
  -- cells as the map has and tile numbers built out of two neighbours.
  --
  -- THE MAP SAYS WHICH IT IS AND NEEDS NO GUESS.  Its own declared width
  -- and height give the cell count, and the data size is either that or
  -- twice it.  Measured over the 63 tilemaps in the fifteen UI archives:
  -- 59 are two bytes a cell, 4 are one, and NOT ONE is neither -- so the
  -- rule decides every case rather than most of them.
  --
  -- Both symptoms of reading them wrong came from this one thing and
  -- pointed at it together: on exactly those four the declared size
  -- disagreed with the cell count, AND the tile ids ran past the end of
  -- the sheet -- `trainer_card_front` asked for tile 978 of a 240-tile
  -- sheet. Read a byte at a time its highest is 226.
  local expected = floor((w or 0) / 8) * floor((h or 0) / 8)
  local wide = not (expected > 0 and size == expected)

  if wide then
    for i = 0, floor((size or 0) / 2) - 1 do
      local v = u16(c.data, at + i * 2)
      if not v then break end
      cells[i + 1] = {
        tile = v % 1024,
        flipX = floor(v / 1024) % 2 == 1,
        flipY = floor(v / 2048) % 2 == 1,
        palette = floor(v / 4096) % 16,
      }
    end
  else
    for i = 0, (size or 0) - 1 do
      -- `at` is already a 1-based index, the same one `u16` takes above.
      local v = byte(c.data, at + i)
      if not v then break end
      -- No flip and no sub-palette: an affine layer has neither, and a
      -- palette of 0 is what `compose` already means by "the whole of it".
      cells[i + 1] = { tile = v, flipX = false, flipY = false, palette = 0 }
    end
  end

  return { width = w, height = h, cells = cells, affine = (not wide) or nil }
end

-- ---------------------------------------------------------------------------
-- Pixels
-- ---------------------------------------------------------------------------

-- Expand a tile sheet into a width x height grid of palette INDICES (0 is
-- the transparent one by convention and is left as 0 rather than resolved,
-- because only the caller knows whether it wants a hole or a colour).
--
-- `widthTiles` is required for an unsized sheet and ignored otherwise.
function Gen4Graphics.indices(sheet, widthTiles)
  if not sheet then return nil end
  local tx = sheet.tilesX or widthTiles
  if not tx or tx < 1 then return nil, "tile sheet has no width; pass one" end
  local w = tx * 8
  local px, data, four = {}, sheet.pixels, sheet.bpp == 4

  -- A linear sheet is simply pixels in reading order, so there is no tile
  -- walk at all -- and running the tile walk over one produces a picture in
  -- the right colours sheared into horizontal bands, which looks far more
  -- like a broken decrypt than like a layout mistake.
  if sheet.bitmap then
    local per = four and 2 or 1
    local h = floor(#data * per / w)
    for i = 1, w * h do px[i] = 0 end
    for i = 0, #data - 1 do
      local v = byte(data, i + 1)
      if four then
        px[i * 2 + 1] = v % 16
        px[i * 2 + 2] = floor(v / 16)
      else
        px[i + 1] = v
      end
    end
    return px, w, h
  end

  local ty = math.ceil(sheet.count / tx)
  local h = ty * 8
  for i = 1, w * h do px[i] = 0 end
  for t = 0, sheet.count - 1 do
    local bx, by = (t % tx) * 8, floor(t / tx) * 8
    local base = t * sheet.perTile
    for i = 0, sheet.perTile - 1 do
      local v = byte(data, base + i + 1)
      if not v then break end
      if four then
        -- Two pixels per byte, LOW nibble first -- the other way round
        -- mirrors every tile horizontally, which looks like a flip-flag bug.
        local p = i * 2
        local x1, y1 = bx + p % 8, by + floor(p / 8)
        px[y1 * w + x1 + 1] = v % 16
        local x2, y2 = bx + (p + 1) % 8, by + floor((p + 1) / 8)
        px[y2 * w + x2 + 1] = floor(v / 16)
      else
        local x1, y1 = bx + i % 8, by + floor(i / 8)
        px[y1 * w + x1 + 1] = v
      end
    end
  end
  return px, w, h
end

-- ---------------------------------------------------------------------------
-- Composition: NSCR + NCGR + NCLR -> one finished screen
-- ---------------------------------------------------------------------------

-- A background is never one file.  The tilemap says which tile goes where and
-- with which sub-palette, the tile sheet holds the 8x8 pieces, and the palette
-- holds the colours.  Composing them is what turns three archive members into
-- a picture, and it is the step that was missing while Gen 4 assets could be
-- decoded but not looked at.
--
-- Returns { width, height, rgba }, rgba being width * height * 4 bytes.
-- Palette entry 0 is transparent, as everywhere else on the hardware.
-- STAMP one tilemap into another at a TILE offset, which is `Bg_LoadToTilemapRect`
-- and is the thing this file could not express.
--
-- A Gen 4 screen is very often NOT one tilemap.  The Pokedex's entry page is
-- four of them laid into one 32x24 grid over a single tile sheet -- and because
-- the composer here made one picture per tilemap, each of the four came out as
-- its own fragment drawn with a BORROWED sheet and a BORROWED palette, which is
-- why 275 of the 282 pictures under `pokedex/` are under 400 bytes and every
-- one of them is blank.  The parts were all there; nothing put them together.
--
-- Cells are copied as they are -- a cell carries its own tile index, flip bits
-- and sub-palette -- so the result composes exactly like any other tilemap.
-- Anything that would land outside the base is dropped rather than wrapped: a
-- rect that does not fit is a wrong offset, and wrapping would hide it.
function Gen4Graphics.stamp(base, patch, tileX, tileY)
  if not (base and patch and base.cells and patch.cells) then return base end
  local bw = floor((base.width or 0) / 8)
  local bh = floor((base.height or 0) / 8)
  local pw = floor((patch.width or 0) / 8)
  local ph = floor((patch.height or 0) / 8)
  if bw == 0 or bh == 0 or pw == 0 then return base end
  for row = 0, ph - 1 do
    for col = 0, pw - 1 do
      local cell = patch.cells[row * pw + col + 1]
      local x, y = (tileX or 0) + col, (tileY or 0) + row
      if cell and x >= 0 and x < bw and y >= 0 and y < bh then
        base.cells[y * bw + x + 1] = cell
      end
    end
  end
  return base
end

-- A blank 32x24 canvas, for a screen whose first tilemap is smaller than the
-- screen.  Cell zero of a Gen 4 tile sheet is transparent by convention and
-- `compose` skips colour index 0 anyway, so an empty cell draws nothing.
function Gen4Graphics.canvas(tilesWide, tilesHigh)
  local cells = {}
  for i = 1, tilesWide * tilesHigh do
    cells[i] = { tile = 0, flipX = false, flipY = false, palette = 0 }
  end
  return { width = tilesWide * 8, height = tilesHigh * 8, cells = cells }
end

-- `firstTile` is WHERE THE SHEET WAS LOADED, not an offset into the picture,
-- and leaving it out is what made the Poke Ball step of the intro a field of
-- one repeated tile with a hole in the middle.
--
-- A tilemap's cells index VRAM, not the member they were shipped beside.  The
-- intro's ball is sixteen tiles (member 32/33/34, 512 bytes each) and its
-- tilemap (member 40) points at tiles 32..47, because the app loads those
-- sixteen at tile 32 of the background's character base.  Composed without
-- that base every ball cell fell past the end of a 16-tile sheet and came out
-- transparent, while the 736 cells that hold tile 0 -- the empty ones -- all
-- drew the sheet's own tile 0 instead.  The picture was the exact inverse of
-- the ball: a repeated glyph everywhere and a 48x48 hole where the ball goes.
--
-- Nothing else in that archive needs it and that was checked rather than
-- assumed: the five backdrops run to tile 121 and the figures' tilemap to 127,
-- both inside their own 128-tile sheets.  Only the ball is loaded high.
-- grayscalePalette(palette, count) -> the same palette, greyed the DS's way
--
-- `BattleAnimUtil_ConvertColorsToGrayscale` is one line of pret:
--   `y = RGB_TO_GRAYSCALE(r, g, b)` = `(r * 76 + g * 151 + b * 29) >> 8`
-- on FIVE-BIT channels, written back as `(y << 10) | (y << 5) | y`. The weights sum
-- to 256, so white stays white and nothing can overflow.
--
-- THE FIVE BITS MATTER, which is why this converts back down before weighting and
-- up again after. `palette` has already expanded each channel to eight bits
-- (`round(v * 255 / 31)`), and weighting the expanded values then re-rounding gives
-- a slightly different grey from the cartridge's -- a difference of one or two
-- levels on most colours, which is exactly the kind of thing that makes a port
-- "nearly" right in a way nothing can measure. The expansion is invertible over
-- 0..31, so going back is exact rather than approximate.
--
-- `count` is how many ENTRIES to grey and defaults to the cartridge's own scope:
-- `PALETTE_SIZE * BATTLE_BG_PALETTE_MON_SPRITE` is 16 * 8 = 128, sub-palettes 0 to
-- 7, which leaves the Pokemon-sprite palette at slot 8 and the effect
-- background's at slot 9 in colour.
Gen4Graphics.GRAYSCALE_SCOPE = 128

function Gen4Graphics.grayscalePalette(palette, count)
  if type(palette) ~= "table" then return nil end
  count = count or Gen4Graphics.GRAYSCALE_SCOPE
  local out = {}
  for i, colour in pairs(palette) do
    if i > count or type(colour) ~= "table" then
      out[i] = colour
    else
      local r = floor((colour[1] or 0) * 31 / 255 + 0.5)
      local g = floor((colour[2] or 0) * 31 / 255 + 0.5)
      local b = floor((colour[3] or 0) * 31 / 255 + 0.5)
      local y = floor((r * 76 + g * 151 + b * 29) / 256)
      local v = ch(y)
      out[i] = { v, v, v }
    end
  end
  return out
end

-- coversScreen(image, width, height) -> true when every pixel of the window has ink
--
-- A composed picture leaves colour-0 pixels transparent, which is what the hardware
-- does for every background layer but the bottom one -- so a whole-screen operation
-- on a layer, such as blending its palette toward white, is only reproducible as a
-- whole-screen quad where the layer HAS no holes.
--
-- The window defaults to the DS's own 256x192 and not to the whole image, because a
-- background is 512x256 and half of it is off the screen until something scrolls.
-- `rgba` is four bytes a pixel with alpha last, so this is one byte per pixel.
--
-- IT LIVES HERE RATHER THAN IN THE EXTRACTOR so that it can be tested: the extractor
-- cannot be loaded outside the engine (it reaches the logger and the image writer),
-- and a rule that only the extractor knows is a rule no check can call.
function Gen4Graphics.coversScreen(image, width, height)
  if not (image and image.rgba and image.width and image.height) then return false end
  width = min(width or 256, image.width)
  height = min(height or 192, image.height)
  for y = 0, height - 1 do
    local row = y * image.width
    for x = 0, width - 1 do
      if byte(image.rgba, (row + x) * 4 + 4) == 0 then return false end
    end
  end
  return true
end

-- paletteAtSlot(palette, slot) -> a sparse palette for `compose`
--
-- WHY THIS EXISTS AT ALL. A 4bpp background's tilemap cell carries a four-bit
-- SUB-PALETTE index, and `compose` reads colour `cell.palette * 16 + value`. A
-- sheet whose palette member holds one sixteen-colour palette is therefore only
-- composable if that palette sits where the cells say it does -- and the game
-- decides where that is when it loads it, not the archive.
--
-- The move-animation effect backgrounds are the case that needs it:
-- `PaletteData_LoadBufferFromFileStart(..., PLTT_DEST(BATTLE_BG_PALETTE_EFFECT))`
-- puts their sixteen colours in SLOT 9, and 64,866 of the 115,712 cells in those
-- tilemaps name sub-palette 9. Composed with the palette at slot 0 every one of
-- those cells reads past the end of a sixteen-entry table and comes out
-- transparent: all 81 of the effect backgrounds compose to an empty picture,
-- which is exactly what happened the first time.
--
-- THE OTHER 50,846 CELLS NAME SLOT 0, and this leaves them transparent, which is
-- deliberate: nothing loads a slot-0 palette for that layer, so on the hardware
-- those cells show whatever the battle backdrop left in the main BG palette's
-- first sixteen entries. 11,708 of them point at a tile with ink in it (tiles 1,
-- 24 and 26). Painting those in some invented colour would be this port drawing
-- art the cartridge does not, so they are dropped and the count is recorded.
function Gen4Graphics.paletteAtSlot(palette, slot)
  if type(palette) ~= "table" then return nil end
  local out = {}
  local base = (tonumber(slot) or 0) * 16
  for i = 1, 16 do out[base + i] = palette[i] end
  if next(out) == nil then return nil end
  return out
end

-- A PALETTE AS ONE STRING, so the cache can carry every screen's colours
-- without carrying 33,904 Lua tables.
--
-- WHY THE CACHE NEEDS THEM AT ALL.  A composed screen picture cannot contain
-- a colour that appears nowhere but in TEXT, and Platinum's text is drawn at
-- runtime out of a sub-palette the app's own C code names -- TEXT_COLOR(1, 2,
-- 0) on BG palette 3 for the bag, on BG palette 15 for the trainer card.  So
-- every screen that prints anything had to have its ink written down by hand,
-- and a hand-written colour is a colour that can be wrong without anything
-- noticing.  Published here, it is the cartridge's.
--
-- WHY HEX AND NOT A TABLE.  146 distinct palettes across the fifteen UI
-- archives, 129 of them full 256-colour banks: 33,904 colours in all.  As
-- nested `{ r, g, b }` that is about 850 KB of Lua source; as six hex digits
-- a colour it is about 200 KB, and it decodes with one `tonumber` per
-- channel.  The cache is a file the importer writes and the game reads, not
-- a thing anyone hand-edits, so the compact form costs nothing.
--
-- The string is RRGGBB per colour, in palette order, with NO separator.
function Gen4Graphics.paletteHex(colours)
  if type(colours) ~= "table" then return nil end
  local parts = {}
  for i = 1, #colours do
    local c = colours[i]
    if type(c) ~= "table" then return nil end
    parts[i] = ("%02x%02x%02x"):format(c[1] % 256, c[2] % 256, c[3] % 256)
  end
  if #parts == 0 then return nil end
  return table.concat(parts)
end

-- ...and back, one SUB-PALETTE at a time, as the 0-1 triples LOVE draws with.
--
-- `slot` is the sixteen-colour bank the cartridge names, so slot 15 is colours
-- 240..255.  Returns a 1..16 array -- NOT the sparse 241..256 shape
-- `paletteAtSlot` builds, which exists to be handed to `compose` at an offset.
-- A caller wanting entry 1 of the bank asks for `[2]`, because the cartridge's
-- index 0 is the transparent one and is kept so the indices line up with
-- TEXT_COLOR's own numbering.
function Gen4Graphics.slotFromHex(hex, slot)
  if type(hex) ~= "string" then return nil end
  local base = ((tonumber(slot) or 0) * 16) * 6
  if base + 96 > #hex then return nil end
  local out = {}
  for i = 0, 15 do
    local at = base + i * 6
    out[i + 1] = {
      tonumber(hex:sub(at + 1, at + 2), 16) / 255,
      tonumber(hex:sub(at + 3, at + 4), 16) / 255,
      tonumber(hex:sub(at + 5, at + 6), 16) / 255,
    }
  end
  return out
end

function Gen4Graphics.compose(map, sheet, palette, firstTile)
  if not (map and sheet and palette) then return nil, "compose needs a tilemap, tiles and a palette" end

  local w, h = map.width, map.height
  -- NSCR records its size in pixels, but a few members leave it at zero and
  -- let the cell count speak instead.  Fall back rather than return nothing.
  if not w or w == 0 or not h or h == 0 then
    local cells = #map.cells
    w = 256
    h = floor(cells / (w / 8)) * 8
    if h == 0 then return nil, "tilemap has no size and no cells" end
  end

  -- WHERE CELL n GOES, WHICH IS NOT SIMPLY "n cells across".
  --
  -- The DS lays a background's screen data out in 32x32-ENTRY BLOCKS, one per
  -- 256x256 pixels, in reading order -- so a 512x256 map is TWO blocks side by
  -- side and its first 1024 cells are the WHOLE LEFT HALF, not the top two
  -- rows of the full width.  Reading it as one 64-wide grid interleaves the
  -- halves every 32 cells, and the result is a picture chopped into 256-pixel
  -- strips stacked in the wrong order.
  --
  -- Reported from play: the battle backdrop drew "flat horizontal bands with a
  -- black stripe through the middle". Platinum's outdoor backdrops ARE
  -- horizontal gradients -- that part is the cartridge's own art -- but the
  -- stripe was this: the transparent bottom of each half landing in the middle
  -- of the picture. pl_batt_bg member 2 states it twice over, and neither
  -- statement needs the art to read:
  --   * block 0 row 0 is tiles 576,1,2..31 and block 1 row 0 is 31,30..1,576 --
  --     the same run mirrored, with the H-flip bit set on 607 of block 1's
  --     cells and on NONE of block 0's. A 512-wide backdrop is a 256-wide
  --     gradient beside its own mirror, which is what makes the scroll seamless.
  --   * every blank cell starts at ROW 20 OF EACH BLOCK -- one clean horizontal
  --     boundary at y 160, where the platforms and battlers take over. Read
  --     linearly the blanks span rows 10 through 31, which is the stripe.
  --
  -- 199 of the cartridge's 983 tilemaps move because of this, so it was never
  -- only the backdrop: the town map, the box screens, the title demo and the
  -- Frontier backgrounds are all in the list.
  --
  -- ONLY AT THE HARDWARE'S OWN BG SIZES, which above 256x256 are exactly
  -- 512x256, 256x512 and 512x512. Everything else stays linear, and the
  -- restriction is deliberate rather than cautious:
  --   * ten members state sizes the hardware has no BG for at all (352x192,
  --     384x144, 448x192, 320x72, 256x400, 256x488, 256x504). Those are laid
  --     out by software and splitting them would scramble screens that work.
  --   * two more state 1024x1024, which is not a text BG size either. THE
  --     BLOCK RULE IS NOT VERIFIED THERE and both readings happen to fill the
  --     same top half (8,192 cells, exactly half the grid), so extrapolating
  --     would be a guess dressed as a rule. Left linear until something proves
  --     otherwise.
  -- Measured over the cartridge's 983 tilemaps: 201 compose differently now
  -- (131 at 512x256, 68 at 512x512, 2 at 1024x1024 -- the last of which this
  -- restriction puts back), ten are a single block column and so unchanged by
  -- arithmetic, and ten are the odd sizes above.
  local cols = floor(w / 8)
  local blockCols = nil
  if (w == 256 or w == 512) and (h == 256 or h == 512)
     and (w > 256 or h > 256) then
    blockCols = floor(w / 256)
  end
  local four = sheet.bpp == 4
  local perTile = sheet.perTile or (four and 32 or 64)
  local data = sheet.pixels
  -- `palette` is the flat array Gen4Graphics.palette returns: one { r, g, b }
  -- per entry, sub-palettes laid end to end in sixteens.
  local colours = palette
  -- `next` RATHER THAN `#`, because a palette may legitimately be SPARSE. A
  -- background loaded into sub-palette slot n has its sixteen colours at
  -- n * 16 + 1 .. n * 16 + 16 and nothing at all below that -- see
  -- `paletteAtSlot` -- and `#` on such a table is not defined to be anything
  -- useful. What the guard is actually for is a palette member that decoded to
  -- nothing, and an empty table is still caught.
  if type(colours) ~= "table" or next(colours) == nil then
    return nil, "palette has no colours"
  end

  local out = {}
  local blank = char(0, 0, 0, 0)
  for i = 1, w * h do out[i] = blank end

  for index = 1, #map.cells do
    local cell = map.cells[index]
    local cx, cy
    if blockCols then
      -- 1024 entries per block; within one, 32 cells to a row.
      local n = index - 1
      local block = floor(n / 1024)
      local k = n % 1024
      cx = (block % blockCols) * 256 + (k % 32) * 8
      cy = floor(block / blockCols) * 256 + floor(k / 32) * 8
    else
      cx = ((index - 1) % cols) * 8
      cy = floor((index - 1) / cols) * 8
    end
    if cy < h and cx < w then
      local base = (cell.tile - (firstTile or 0)) * perTile
      -- A cell may point past the end of a sheet that was cut short, or below
      -- the base the sheet was loaded at; leave those transparent instead of
      -- reading whatever follows -- or, for a negative index, whatever
      -- precedes.
      if base >= 0 and base + perTile <= #data then
        local shift = four and (cell.palette * 16) or 0
        for y = 0, 7 do
          local sy = cell.flipY and (7 - y) or y
          for x = 0, 7 do
            local sx = cell.flipX and (7 - x) or x
            local value
            if four then
              local at = base + sy * 4 + floor(sx / 2)
              local pair = byte(data, at + 1) or 0
              if sx % 2 == 0 then value = pair % 16 else value = floor(pair / 16) end
            else
              value = byte(data, base + sy * 8 + sx + 1) or 0
            end
            if value ~= 0 then
              local colour = colours[shift + value + 1]
              if colour then
                out[(cy + y) * w + cx + x + 1] =
                  char(colour[1], colour[2], colour[3], 255)
              end
            end
          end
        end
      end
    end
  end

  return { width = w, height = h, rgba = concat(out) }
end

-- Compose straight from an archive group (see Gen4Archives.groups): the group
-- names the members, this fetches and decodes them.  `fallbackMap` supplies a
-- tilemap for groups that share one rather than carrying their own -- battle
-- backgrounds all reuse member 2, for instance.
function Gen4Graphics.composeGroup(narc, group, fallbackMap)
  if not group then return nil, "no group" end
  local function fetch(member)
    if member == nil then return nil end
    local raw = narc:get(member)
    if not raw then return nil end
    if Gen4Graphics.isCompressed(raw) then raw = Gen4Graphics.decompress(raw) end
    return raw
  end

  local tileData = fetch(group.NCGR)
  local palData = fetch(group.NCLR)
  local mapData = fetch(group.NSCR) or fallbackMap
  if not tileData then return nil, "group has no tile sheet" end
  if not palData then return nil, "group has no palette" end
  if not mapData then return nil, "group has no tilemap" end

  local sheet = Gen4Graphics.tiles(tileData)
  local palette = Gen4Graphics.palette(palData)
  local map = Gen4Graphics.tilemap(mapData)
  return Gen4Graphics.compose(map, sheet, palette)
end

return Gen4Graphics
