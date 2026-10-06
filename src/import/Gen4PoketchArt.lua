-- PLATINUM'S POKETCH SPRITES AND APP BACKGROUND TILES, as each app loads them
-- (src/applications/poketch/<app>/graphics.c), from /graphic/poketch.narc.
--
-- WHY THIS EXISTS BESIDE Gen4Screens' poketch sheets. That pass assembles each
-- app's cells against the app's OWN tile file -- but five apps (stopwatch,
-- counter, pedometer, kitchen timer, alarm clock) load `digits.NCGR` at OBJ tile
-- 0 and their own sheet at tile POKETCH_DIGITS_NCGR_NUM_TILES (80) after it, and
-- their cells address that combined VRAM. Assembled alone they come out as
-- digit fragments; the friendship checker's sheet sits after six 16-tile mon
-- icon slots the same way. Here every cell is assembled against the VRAM the
-- app actually builds, and keeps its origin, so a sprite is placed where
-- `PoketchAnimation_AnimationData.translation` says.
--
-- COLOURS: every app loads the LCD theme's first row (PoketchGraphics_
-- LoadActivePalette(0, 0) -> OBJ row 0), and the app-counter load leaves
-- generic_bg_tiles.NCLR rows 0..2 in OBJ rows 0..2, so an OAM entry's own
-- palette field picks a row of that file. Theme 0 is what is written; the
-- watch's colour changer remaps theme 0 to the chosen theme at draw time.
--
-- Pictures: `<set>_<cell>` (e.g. stopwatch_12) with originX/originY = the
-- cell's top-left relative to its translation point, and `<app>_bgtiles`,
-- the app's BG tile sheet 32 tiles wide in row 0, for the BG patches apps
-- write at run time (the stopwatch's button, the calculator's keys...).
-- Data (`gen4_poketch_ink`): anims[set][seq + 1] = { mode, frames = { {cell,
-- duration, x, y, rot} } } -- NANR element types 0 (index), 1 (SRT: the
-- analog watch's 420 hand angles) and 2 (translate) -- and the tilemaps apps
-- copy BG rectangles out of.

local Gen4PoketchArt = {}

Gen4PoketchArt.PATH = "/graphic/poketch.narc"
Gen4PoketchArt.DIGIT_TILES = 80          -- POKETCH_DIGITS_NCGR_NUM_TILES
Gen4PoketchArt.ICON_TILES = 16           -- POKE_ICON_SIZE

-- set -> { cell bank, anim bank, { { NCGR, first tile }, ... } }
-- Only the stopwatch's cells address the combined VRAM directly; the counter,
-- pedometer, kitchen timer and alarm clock load theirs after the digits too
-- but cancel the offset with PoketchAnimation_SetSpriteCharNo(80), and the
-- friendship checker's hearts likewise with SetSpriteCharNo(16 * 6) -- so
-- those cells are assembled against their own sheet alone.
local DIGITS = { "digits.NCGR.lz", 0 }
local function after(name) return { DIGITS, { name, Gen4PoketchArt.DIGIT_TILES } } end
local function alone(name) return { { name, 0 } } end
Gen4PoketchArt.SETS = {
  digits = alone("digits.NCGR.lz"),
  stopwatch = after("stopwatch.NCGR.lz"),
  counter = alone("counter.NCGR.lz"),
  pedometer = alone("pedometer.NCGR.lz"),
  kitchen_timer = alone("kitchen_timer.NCGR.lz"),
  alarm_clock = alone("alarm_clock.NCGR.lz"),
  analog_watch = alone("analog_watch.NCGR.lz"),
  backlight_toggle = alone("backlight_toggle.NCGR.lz"),
  calendar = alone("calendar.NCGR.lz"),
  coin_toss = alone("coin_toss.NCGR.lz"),
  color_changer = alone("color_changer.NCGR.lz"),
  daycare_checker = alone("daycare_checker.NCGR.lz"),
  dowsing_machine = alone("dowsing_machine.NCGR.lz"),
  link_searcher = alone("link_searcher.NCGR.lz"),
  map = alone("map.NCGR.lz"),
  matchup_checker = alone("matchup_checker.NCGR.lz"),
  memo_pad = alone("memo_pad.NCGR.lz"),
  move_tester = alone("move_tester.NCGR.lz"),
  party_status = alone("party_status.NCGR.lz"),
  roulette = alone("roulette.NCGR.lz"),
  trainer_counter = alone("trainer_counter.NCGR.lz"),
  friendship_checker = alone("friendship_checker.NCGR.lz"),
}

-- BG tile sheets apps patch their own tilemap from at run time.
Gen4PoketchArt.BG_TILES = {
  stopwatch = "stopwatch_bg_tiles.NCGR.lz",
  calculator = "calculator_bg_tiles.NCGR.lz",
  kitchen_timer = "kitchen_timer_bg_tiles.NCGR.lz",
  alarm_clock = "alarm_clock_bg_tiles.NCGR.lz",
  watch = "watch_bg_tiles.NCGR.lz",
  calendar = "calendar_bg_tiles.NCGR.lz",
  memo_pad = "memo_pad_bg_tiles.NCGR.lz",
  generic = "generic_bg_tiles.NCGR.lz",
  party_status = "party_status_bg_tiles.NCGR.lz",
  move_tester = "move_tester_bg_tiles.NCGR.lz",
  roulette = "roulette_bg_tiles.NCGR.lz",
  daycare_checker = "daycare_checker_bg_tiles.NCGR.lz",
  matchup_checker = "matchup_checker_bg_tiles.NCGR.lz",
  counter = "counter_bg_tiles.NCGR.lz",
  pedometer = "pedometer_bg_tiles.NCGR.lz",
  dowsing_machine = "dowsing_machine_bg_tiles.NCGR.lz",
  trainer_counter = "trainer_counter_bg_tiles.NCGR.lz",
  map = "map_bg_tiles.NCGR.lz",
}

-- key -> { NSCR, NCGR }: the digital watch's digit strip (40 x 9 tiles, four
-- columns a digit) uses solid generic BG tiles 1 and 2, not watch decoration
-- tiles or the OBJ digit sheet.
Gen4PoketchArt.COMPOSE = {
  digital_watch_digits = { "digital_watch_digits.NSCR.lz", "generic_bg_tiles.NCGR.lz" },
}

-- This 40x9 software strip stores a compact 32-column block followed by
-- an 8-column block, each nine rows high. It is not ordinary row-major data.
function Gen4PoketchArt.digitalWatchMap(map)
  if map.layout=="linear_watch_digits" then return map end
  local out={};for key,value in pairs(map) do out[key]=value end
  out.cells={};out.layout="linear_watch_digits"
  for y=0,8 do
    for x=0,39 do
      local at=x<32 and (y*32+x+1) or (288+y*8+x-32+1)
      out.cells[y*40+x+1]=map.cells[at]
    end
  end
  return out
end

-- Tilemaps whose cells the runtime copies (32 x n entries, row-major).
Gen4PoketchArt.TILEMAPS = {
  "calculator.NSCR.lz", "digital_watch.NSCR.lz", "digital_watch_digits.NSCR.lz",
  "stopwatch.NSCR.lz", "kitchen_timer.NSCR.lz", "alarm_clock.NSCR.lz",
  "calendar.NSCR.lz", "memo_pad.NSCR.lz", "move_tester.NSCR.lz",
  "daycare_checker.NSCR.lz", "matchup_checker.NSCR.lz", "roulette.NSCR.lz",
  "counter.NSCR.lz", "pedometer.NSCR.lz", "analog_watch.NSCR.lz",
}

local floor = math.floor

local function opener(rom, path)
  local G = require("src.import.Gen4Graphics")
  local A = require("src.import.Gen4Archives")
  local bytes = rom:read(path)
  if not bytes then return nil end
  local narc = require("src.import.NarcArchive").parse(bytes)
  return function(name)
    local i = type(name) == "number" and name or A.find(path, name)
    local b = i and narc:get(i)
    if b and G.isCompressed(b) then b = G.decompress(b) end
    return b
  end
end

-- The OBJ VRAM one app builds: each sheet's 4bpp bytes at its first tile.
local function vram(member, G, loads)
  local parts, size = {}, 0
  for _, load in ipairs(loads) do
    local sheet = G.tiles(member(load[1]))
    if not sheet then return nil end
    local at = load[2] * 32
    if at > size then parts[#parts + 1] = string.rep("\0", at - size); size = at end
    parts[#parts + 1] = sheet.pixels
    size = size + #sheet.pixels
  end
  local pixels = table.concat(parts)
  return { bpp = 4, perTile = 32, count = floor(#pixels / 32), pixels = pixels }
end

local function u16(s, at) local a, b = s:byte(at, at + 1); return b and a + b * 256 end
local function u32(s, at) local a, b, c, d = s:byte(at, at + 3); return d and a + b * 256 + c * 65536 + d * 16777216 end
local function s16(v) return v and (v >= 32768 and v - 65536 or v) end

-- A NANR with every element type the Poketch uses. Gen4CellAnim stops at SRT
-- (the analog watch's hands are SRT), so the three record shapes are read here:
--   0  u16 cell
--   1  u16 cell, u16 rotZ, fx32 sx, fx32 sy, s16 x, s16 y
--   2  u16 cell, u16 pad, s16 x, s16 y
-- Sequence: u16 frames, u16 loopStart, u16 elementType, u16 kind,
-- u32 playbackMode (1 forward, 2 forward loop, 3 reverse, 4 reverse loop),
-- u32 frame offset.
function Gen4PoketchArt.anims(data, G)
  local c = data and G.container(data)
  local s = c and c.sections.KNBA
  if not s then return nil end
  local d, f = c.data, s.body
  local nseq, seqOff, frameOff, resOff = u16(d, f), u32(d, f + 4), u32(d, f + 8), u32(d, f + 12)
  local out = {}
  for q = 0, nseq - 1 do
    local at = f + seqOff + q * 16
    local n, loopStart, etype, mode, first = u16(d, at), u16(d, at + 2), u16(d, at + 4), u32(d, at + 8), u32(d, at + 12)
    local frames = {}
    for k = 0, n - 1 do
      local fa = f + frameOff + first + k * 8
      local r, dur = f + resOff + u32(d, fa), u16(d, fa + 4)
      local fr = { cell = u16(d, r), duration = dur }
      if etype == 1 then
        fr.rot = u16(d, r + 2); fr.x = s16(u16(d, r + 12)); fr.y = s16(u16(d, r + 14))
        local sx, sy = u32(d, r + 4), u32(d, r + 8)
        if sx and sx >= 2 ^ 31 then sx = sx - 2 ^ 32 end
        if sy and sy >= 2 ^ 31 then sy = sy - 2 ^ 32 end
        fr.sx, fr.sy = sx and sx / 4096, sy and sy / 4096
      elseif etype == 2 then
        fr.x = s16(u16(d, r + 4)); fr.y = s16(u16(d, r + 6))
      end
      frames[k + 1] = fr
    end
    out[q + 1] = { mode = mode, loopStart = loopStart, frames = frames }
  end
  return out
end

-- AFFINE DOUBLE-SIZE OAM ENTRIES (attr0 bits 8 and 9 both set): the hardware
-- shows a 2w x 2h box at the entry's (x, y) with the w x h picture CENTRED in
-- it. The mon icons (poke_icon: 32x32 at -32,-32, i.e. centred on the point)
-- and the analog watch's hands are authored that way. Gen4Cells reads the
-- position as the picture's corner, so the entries are moved by (w/2, h/2)
-- here, which puts every such picture where the screen shows it.
function Gen4PoketchArt.centreDoubleSize(data, bank, G)
  local c = data and G.container(data)
  local s = c and c.sections.KBEC
  if not (s and bank) then return bank end
  local d, body = c.data, s.body
  local count, attributes, cellDataOffset = u16(d, body), u16(d, body + 2) or 0, u32(d, body + 4) or 24
  local stride = (attributes % 2 == 1) and 16 or 8
  local recordsAt = body + cellDataOffset
  local oamAt = recordsAt + count * stride
  for i, cell in ipairs(bank.cells) do
    local at = recordsAt + (i - 1) * stride
    local oamCount, oamOffset = u16(d, at), u32(d, at + 4)
    local k = 0
    for j = 0, (oamCount or 0) - 1 do
      local a0 = u16(d, oamAt + oamOffset + j * 6)
      local affine, double = floor(a0 / 256) % 2 == 1, floor(a0 / 512) % 2 == 1
      if not (double and not affine) then          -- the entries Gen4Cells kept
        k = k + 1
        local o = cell.oam[k]
        if o and affine and double then
          o.x, o.y = o.x + o.width / 2, o.y + o.height / 2
          cell.affine = true
        end
      end
    end
  end
  return bank
end

function Gen4PoketchArt.images(rom)
  local G = require("src.import.Gen4Graphics")
  local Cells = require("src.import.Gen4Cells")
  local member = opener(rom, Gen4PoketchArt.PATH)
  if not member then return nil, "poketch.narc missing" end
  local pal = G.palette(member("generic_bg_tiles.NCLR"))
  if not pal then return nil, "poketch palette unreadable" end
  local out = {}
  for set, loads in pairs(Gen4PoketchArt.SETS) do
    local sheet = vram(member, G, loads)
    local ncer = member(set .. "_cell.NCER.lz")
    local bank = sheet and Gen4PoketchArt.centreDoubleSize(ncer, Cells.parse(ncer, G), G)
    if bank then
      for i, cell in ipairs(bank.cells) do
        local pic = Cells.assemble(cell, sheet, pal, bank, G)
        if pic then
          pic.originX, pic.originY = Cells.extent(cell)
          out[("%s_%02d"):format(set, i - 1)] = pic
        end
      end
    end
  end
  -- Tilemaps composed over the BG sheet the app loads under them.
  for key, pair in pairs(Gen4PoketchArt.COMPOSE) do
    local sheet, map = G.tiles(member(pair[2])), G.tilemap(member(pair[1]))
    if map and key=="digital_watch_digits" then map=Gen4PoketchArt.digitalWatchMap(map) end
    if sheet and map then out[key] = G.compose(map, sheet, pal) end
  end
  for app, name in pairs(Gen4PoketchArt.BG_TILES) do
    local sheet = G.tiles(member(name))
    if sheet then
      local rows = math.ceil(sheet.count / 32)
      local cells = {}
      for i = 0, rows * 32 - 1 do cells[i + 1] = { tile = i < sheet.count and i or 0, palette = 0 } end
      out[app .. "_bgtiles"] = G.compose({ width = 256, height = rows * 8, cells = cells }, sheet, pal)
    end
  end
  return out
end

function Gen4PoketchArt.data(rom)
  local G = require("src.import.Gen4Graphics")
  local member = opener(rom, Gen4PoketchArt.PATH)
  if not member then return nil end
  local out = { anims = {}, tilemaps = {} }
  for set in pairs(Gen4PoketchArt.SETS) do
    out.anims[set] = Gen4PoketchArt.anims(member(set .. "_anim.NANR.lz"), G)
  end
  for _, name in ipairs(Gen4PoketchArt.TILEMAPS) do
    local map = G.tilemap(member(name))
    if map and name=="digital_watch_digits.NSCR.lz" then map=Gen4PoketchArt.digitalWatchMap(map) end
    if map then
      local list = {}
      for i, c in ipairs(map.cells) do
        list[i] = c.tile + (c.flipX and 0x400 or 0) + (c.flipY and 0x800 or 0) + (c.palette or 0) * 0x1000
      end
      out.tilemaps[(name:gsub("%.NSCR%.lz$", ""))] = { width = floor((map.width or 256) / 8), cells = list, layout=map.layout }
    end
  end
  -- the LCD themes: generic_bg_tiles.NCLR, two rows (normal, backlight) per theme
  local pal = G.palette(member("generic_bg_tiles.NCLR"))
  if pal then
    out.themes = {}
    for i, c in ipairs(pal) do out.themes[i] = { c[1], c[2], c[3] } end
  end
  return out
end

return Gen4PoketchArt
