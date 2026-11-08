-- src/import/Gen5MusicalData.lua -- THE POKEMON MUSICAL, FROM THE CARTRIDGE.
--
-- Everything Nimbasa's Musical Theater reads, decoded from Black / White
-- (nothing typed in from a guide). The facility's code lives in overlays 10
-- (musical_event.c, musical_dressup_sys.c, musical_stage_sys.c,
-- musical_program.c, scrcmd_musical.c), 112 (musical_system.c,
-- mus_item_data.c, mus_poke_draw.c), 131/132 (the stage) and 133 (the
-- dress-up, dup_fitting.c) -- the debug file names the overlays carry.
--
--   /a/0/4/5  member 101: THE PROPS' DATA (ov112 0x021F4F14 loads it whole;
--             0x021F4F54 = 12 bytes a prop): [0] the texture's size code
--             (0x22 32x32, 0x32 64x32, 0x23 32x64), [4] / [5] s8 x / y
--             offset, [6] the positions it may go (bit 0 ears, 1 head,
--             2 eyes, 3 face, 4 body, 5 waist, 6 hand, 7 back), [8] its kind
--             (0 ears .. 6 hand; 0x021F5158), [9] its TYPE (0 cool, 1 cute,
--             2 elegant, 3 quirky; 0x021F5140 -- what the scoring counts),
--             [10] the hand animation it appeals with.
--             members 0..99: each prop's texture (BTX0, "itemNN" + palette)
--   system bank 79  the props' names (prop n = entry n + 3; 0x05D kind 1),
--             bank 282 the same with an article (kind 8), bank 75 the
--             Musical's words (4 cool .. 9 balanced; 0x05D kinds 3 / 4 / 7)
--   /a/1/1/1 .. /a/1/1/4  THE FOUR SHOWS (Stardom, Forest Stroll, A Sweet
--             Soiree, Exciting Nimbasa): member 0 the program (ov10
--             0x02157028 reads it): [1..4] the four types' weights, [5] the
--             bonus pool (/ 5, dealt out at random in 5s), [6] the show's id,
--             then six performers of 0x2C bytes from +0xC: u16 species, u32
--             personality, u16 name, u16 the points the player needs before
--             they appear, then eight props { u16 prop (0x1FE / 0x1FF none),
--             u8 position, pad }. The songs are SEQ_BGM_MSL_01 .. 04.
--             member 2: THE SHOW'S SCRIPT (sta_act_script.c, ov132): 14
--             u32 offsets, one script thread each (0x021FAD0C starts thread k
--             at base + [k * 4]); thread 0 the stage (lights, curtain, song),
--             2..5 the four performers (-1 in a command = the thread's own,
--             0x021FB1F4), the rest share thread 0's. A command is a u16
--             opcode (54 of them, table 0x021FDD14, VM arm9 0x0201121C) and
--             u32 arguments, each read by arm9 0x0201134C (M.SCRIPT_ARGS: the
--             count of those reads in each handler). READ: 0 end, 1 <n> wait
--             n frames (+0x14), 3 <n> yield one frame (a pause point), 47 <n>
--             a label (reads and runs on). By the ov112 sta_act_poke calls
--             they make (READ): 11 <who, ?, x, y, z, ?> sets the position
--             (0x021F8054, work +0x18, fx32), 12 <who, frames, dx, dy, dz, ?>
--             moves it from the current one (0x021F8044 / 8054), 10 <who,
--             0 / 1> the mirror flag (0x021F812C, +0x54), 13 / 14 <who> stop /
--             start its animation (0x021F80B0 / 80A0), 39 <who, hand> the
--             held prop's appeal flag (0x021F8140 for each in the mask),
--             16 <who, frames, hops, height, wait> hops of `frames` each
--             (task 0x021FB8CC, sin offset), 38 <who, frames, start, delta,
--             wait> a turn in degrees to start + delta (task 0x021FBA14), 28
--             <light, kind> / 29 <light> a spotlight made / removed, 30
--             <light, frames, x, y, z> moved to a point, 31 <light, who,
--             frames, x, y, z> riding a performer at that offset; a last
--             `wait` of 1 (12 / 16 / 38) holds the thread for the move.
--   /a/0/4/8  (kept as `species`, no longer used for eligibility: field code
--             reads it, ov10 0x0216E280 opens arc 0x30 -- see Gen5Musical.eligible)
--             member 0: one 28-byte row per species / form (799): u16
--             species, u8 1 when it can play Dress Up (Koffing's row is 0).
--   arm9 0x0200A544: the save's new-game props (15 of them).
--   ov10 0x0216FF14: the fans' thresholds (ten u16, 12000 down to 0) and
--             0x0216FF28 the props fans give, 40 for each of 7 shows.
--
--   /a/0/5/2  THE MUSICAL'S OWN POKEMON (musical_mcss.c, ov112): the battle
--             sprites' layout, 20 members a species (Gen5MonAnim reads it:
--             +2 parts, +4 cells, +5 / +7 animations, +6 multi-cells, +18
--             palette), READ: ov112 0x021F5550 stores arc 0x34 before the
--             seven file-id getters (arm9 0x0202D09C ..). Its +8 member is
--             { u32 n; n x 0x38-byte part records; then 20-byte ANCHOR
--             records to the end: s32 OAM (the n-th OAM of the cell bank,
--             counted cell by cell), s32 id, s32 x, s32 y, s32 rot }. READ:
--             the draw loop 0x021F5C80.. hands each record's id (+4) to the
--             poke draw's callback 0x021F546C with the OAM's transformed
--             position and its rotation plus rot << 11 (a u16 angle: rot / 32
--             of a turn); ids 7..15 fill the nine equip points (id - 7, 0x38
--             bytes each from work +0x14 -- the outfit's nine positions,
--             ears / ears / head / eyes / face / body / waist / hand / hand,
--             that order INFERRED from Pikachu: 7 / 8 ride its ears' cells,
--             14 / 15 its arms'), id 4 / 5 two more points (work +0x20C /
--             +0x218; on the one-OAM cells the multi-cell's base / centre
--             nodes show: 4 the feet, 5 the middle). The anchors here are taken in the first frame of
--             multi-cell animation 0 (the Dress Up's standing pose).
--   (NOT /a/0/4/8 +16 -> /a/0/4/9: that archive's members are 4x4-compressed
--             BTX0 strips -- "t4x4hero", "t4x4flip", 32 frames -- with six
--             BMD0 rocks / bones / grass first, not the Musical's; INFERRED
--             a field / Entralink sprite table, not read further.)
--
-- build(x) -> the record constants.gen5Musical (merged by Gen5Facilities).

local Narc = require("src.import.NarcArchive")

local M = {}

M.PATH = { props = "/a/0/4/5", species = "/a/0/4/8",
           shows = { "/a/1/1/1", "/a/1/1/2", "/a/1/1/3", "/a/1/1/4" } }
M.BANK = { propNames = 79, propNamesA = 282, words = 75 }
M.PROP_COUNT = 100
-- arm9 0x0200A57C .. 0x0200A5EE (the block's init): the props a new save owns
M.START_PROPS = { 0x30, 0x46, 0x53, 0x4B, 0x00, 0x01, 0x0A, 0x1C, 0x08, 0x3B, 0x3F, 0x42, 0x10, 0x59, 0x4C }
-- ov10 0x0215D83A: the fans' overworld sprites by show type (0x16A kind 0)
M.FAN_SPRITE = { [0] = 0x18, 0x0F, 0x2D, 0x0C }
M.SONGS = { [0] = "SEQ_BGM_MSL_01", "SEQ_BGM_MSL_02", "SEQ_BGM_MSL_03", "SEQ_BGM_MSL_04" }

local function u16(s, o) return (s:byte(o + 1) or 0) + (s:byte(o + 2) or 0) * 256 end
local function u32(s, o) return u16(s, o) + u16(s, o + 2) * 65536 end
local function s8(v) return v >= 128 and v - 256 or v end

local function member(rom, path, m)
  local bytes = rom:read(path)
  local arc = bytes and Narc.parse(bytes)
  return arc and arc:get(m), arc
end

function M.props(rom, names)
  local d = member(rom, M.PATH.props, 101)
  if not d or #d < M.PROP_COUNT * 12 then return nil end
  local out = {}
  for i = 0, M.PROP_COUNT - 1 do
    local o = i * 12
    local size = d:byte(o + 1)
    out[i] = {
      size = size, width = math.floor(size / 16) == 3 and 64 or 32, height = size % 16 == 3 and 64 or 32,
      dx = s8(d:byte(o + 5)), dy = s8(d:byte(o + 6)), mask = d:byte(o + 7), flag7 = d:byte(o + 8),
      kind = d:byte(o + 9), type = d:byte(o + 10), appeal = d:byte(o + 11),
      name = names and names[i + 3] or ("Prop " .. i),
    }
  end
  return out
end

function M.show(rom, path, index)
  local d = member(rom, path, 0)
  if not d or #d < 12 + 6 * 0x2C then return nil end
  local show = { index = index, path = path, kind = d:byte(1), weights = {}, bonus = d:byte(6),
                 id = d:byte(7), performers = {}, song = M.SONGS[index] }
  for t = 0, 3 do show.weights[t] = d:byte(2 + t) end
  for k = 0, 5 do
    local o = 12 + k * 0x2C
    local p = { species = u16(d, o), personality = u32(d, o + 2), name = u16(d, o + 6),
                threshold = u16(d, o + 8), props = {} }
    for s = 0, 7 do
      local prop = u16(d, o + 12 + s * 4)
      if prop < 0x1FE then p.props[#p.props + 1] = { id = prop, pos = d:byte(o + 12 + s * 4 + 3) } end
    end
    show.performers[k] = p
  end
  return show
end

function M.species(rom)
  local d = member(rom, M.PATH.species, 0)
  if not d or #d < 4 then return nil end
  local n = u16(d, 0)
  local out = {}
  for i = 0, n - 1 do
    local o = 4 + i * 28
    local sp = u16(d, o)
    if sp > 0 and out[sp] == nil then out[sp] = d:byte(o + 3) == 1 end
  end
  return out
end

-- the fans' tables, found in overlay 10 by the thresholds' shape
function M.fanTables(rom)
  local ov10 = rom.overlay and rom:overlay(10)
  if not ov10 then return nil end
  local key = string.char(0xE0, 0x2E, 0x40, 0x1F, 0x7C, 0x15, 0xAC, 0x0D, 0xD0, 0x07, 0xE8, 0x03)
  local at = ov10:find(key, 1, true)
  if not at then return nil end
  local o = at - 1
  local thresholds = {}
  for i = 0, 9 do thresholds[i] = u16(ov10, o + i * 2) end
  local gifts = {}
  for s = 0, 6 do
    gifts[s] = {}
    for k = 0, 39 do gifts[s][k + 1] = ov10:byte(o + 20 + s * 40 + k + 1) end
  end
  return { thresholds = thresholds, gifts = gifts }
end

-- the props' pictures (BTX0 members 0..99), as PNGs when the extractor can save
function M.images(rom, saveImage)
  if not saveImage then return nil end
  local Models = require("src.import.Gen4Models")
  local bytes = rom:read(M.PATH.props)
  local arc = bytes and Narc.parse(bytes)
  if not arc then return nil end
  local out = {}
  for i = 0, M.PROP_COUNT - 1 do
    local b = arc:get(i)
    local okP, parsed = pcall(Models.parse, b)
    if okP and parsed and parsed.textures and parsed.textures[1] then
      local name = parsed.textures[1].name
      local pal = Models.paletteIndexByName and Models.paletteIndexByName(parsed, name .. "_pl") or 1
      local okD, image = pcall(Models.decode, parsed, b, 1, pal or 1)
      if okD and image then
        out[i] = saveImage(("bw_musical/prop_%02d"):format(i), image, { member = i })
      end
    end
  end
  return out
end

-- ------------------------------------------------- the show's script --

-- (1-based byte readers)
local function rawU16(d, at) return (d:byte(at) or 0) + (d:byte(at + 1) or 0) * 256 end
local function rawU32(d, at) return rawU16(d, at) + rawU16(d, at + 2) * 65536 end
local function rawS32(d, at) local v = rawU32(d, at) if v >= 2147483648 then v = v - 4294967296 end return v end

M.SCRIPT_ARGS = { [0] = 0, 1, 1, 1, 1, 1, 3, 3, 1, 2, 2, 6, 6, 1, 1, 2, 5, 4, 2, 1, 1, 1, 5, 2, 1, 5, 2, 10, 2, 1,
                  5, 6, 5, 2, 0, 3, 1, 0, 5, 2, 2, 1, 1, 0, 0, 0, 2, 1, 1, 0, 2, 2, 3, 1 }
M.SCRIPT_THREADS = 14

function M.decodeScript(d)
  if type(d) ~= "string" or #d < M.SCRIPT_THREADS * 4 then return nil end
  local out = { threads = {}, frames = 0 }
  local starts = {}
  for k = 0, M.SCRIPT_THREADS - 1 do starts[k] = rawU32(d, k * 4 + 1) end
  local cache = {}
  for k = 0, M.SCRIPT_THREADS - 1 do
    local at = starts[k]
    if not cache[at] then
      local list, p = {}, at
      while p + 2 <= #d do
        local op = rawU16(d, p + 1)
        local n = M.SCRIPT_ARGS[op]
        if not n then break end
        local cmd = { op }
        for i = 1, n do cmd[i + 1] = rawS32(d, p + 3 + (i - 1) * 4) end
        list[#list + 1] = cmd
        p = p + 2 + 4 * n
        if op == 0 then break end
      end
      cache[at] = list
    end
    out.threads[k] = cache[at]
  end
  for _, cmd in ipairs(out.threads[0] or {}) do
    if cmd[1] == 1 then out.frames = out.frames + cmd[2] elseif cmd[1] == 3 then out.frames = out.frames + 1 end
  end
  return out
end

function M.choreography(rom, path)
  return M.decodeScript((member(rom, path, 2)))
end

-- ------------------------------------------------------- the poses --

M.PATH.poses = "/a/0/5/2"
M.POSE_CANVAS, M.POSE_OX, M.POSE_OY = 160, 80, 120


-- the cell bank's OAMs counted cell by cell -> { [global] = { cell, j } }:
-- the drawn ones only (Gen5MonAnim.parseCells drops the hidden), the count
-- the records keep -- Pikachu's, Bulbasaur's and Mewtwo's base / centre
-- records land on their one-OAM cross cells only so
local function oamIndex(cells)
  if not cells then return nil end
  local out, g = {}, 0
  for i = 0, (cells.count or 0) - 1 do
    for j = 1, #(cells.cells[i] and cells.cells[i].oam or {}) do out[g] = { cell = i, j = j } g = g + 1 end
  end
  return out
end

-- the anchor records at the end of member +8
function M.anchorRecords(bytes)
  if type(bytes) ~= "string" or #bytes < 4 then return nil end
  local n = rawU32(bytes, 1)
  local at = 4 + n * 0x38
  if n > 64 or at > #bytes then return nil end
  local out = {}
  while at + 20 <= #bytes do
    out[#out + 1] = { oam = rawS32(bytes, at + 1), id = rawS32(bytes, at + 5), x = rawS32(bytes, at + 9),
                      y = rawS32(bytes, at + 13), rot = rawS32(bytes, at + 17) }
    at = at + 20
  end
  return out
end

-- one species' pose, ANIMATED: multi-cell animation 0 played through its
-- loop (Gen5MonAnim.machine; at most M.POSE_TICKS ticks), each distinct
-- frame drawn once with its own nine points -- a prop rides its body part as
-- the part moves (READ: the callback 0x021F546C refreshes the points from
-- the drawn OAMs every frame). Fields: ox / oy / width / height (one frame's
-- box, the origin in it), image + anchors / base / centre (frame 1),
-- frames[i].anchors (/ base / centre), runs = { { f, ticks } .. } the
-- loop's order, loop (its length), strip (the frames in a grid of
-- `cols` columns, when there is more than one)
M.POSE_TICKS = 1200
function M.pose(arc, species, saveImage)
  local A = require("src.import.Gen5MonAnim")
  local set = A.load(arc, species, "front")
  if not set then return nil end
  local base = species * A.STRIDE
  local okR, recs = pcall(M.anchorRecords, A.inflate(arc:get(base + 8)))
  local oams = oamIndex(set.cells)
  local machine = A.machine(set, 0)
  if not (machine and okR and recs and oams) then return nil end
  local C, OX, OY = M.POSE_CANVAS, M.POSE_OX, M.POSE_OY
  -- the base / centre markers (the one-OAM cells ids 4 / 5 name, a cross)
  -- are points, not drawn (INFERRED: the musical never shows them)
  local marker = {}
  for _, r in ipairs(recs) do
    local where = oams[r.oam]
    if where and (r.id == 4 or r.id == 5) then marker[where.cell] = true end
  end
  -- where an OAM of a cell sits: the part showing that cell, its node offset
  -- and its rotation (the record's x / y are cell space: they repeat the
  -- centre of the marker OAM it names, a plain 16 x 16 one)
  local function points(state)
    local out = { anchors = {} }
    local function place(cellIndex, lx, ly)
      for _, s in ipairs(state) do
        if s.cell == cellIndex then
          local c, sn = math.cos(s.rot), math.sin(s.rot)
          local t = s.top
          return c * s.sx * lx - sn * s.sy * ly + s.tx + t.tx, sn * s.sx * lx + c * s.sy * ly + s.ty + t.ty, s.rot
        end
      end
    end
    for _, r in ipairs(recs) do
      local where = oams[r.oam]
      if where and r.id >= 4 and r.id <= 15 then
        local x, y, rot = place(where.cell, r.x, r.y)
        if x then
          local p = { x = x, y = y, rot = (rot or 0) + r.rot / 32 * 2 * math.pi }
          if r.id >= 7 then out.anchors[r.id - 7] = out.anchors[r.id - 7] or p
          elseif r.id == 4 then out.base = out.base or p
          elseif r.id == 5 then out.centre = out.centre or p end
        end
      end
    end
    return out
  end
  local ticks = machine.loops and math.max(1, math.min(machine.loopTicks or 1, M.POSE_TICKS)) or 1
  local frames, byKey, runs, rasters = {}, {}, {}, {}
  local x0, y0, x1, y1
  for _ = 1, ticks do
    local state = machine.state()
    local key = {}
    for i, st in ipairs(state) do
      key[i] = ("%d,%.4f,%.4f,%.4f,%d,%d,%d,%d"):format(st.cell, st.rot, st.sx, st.sy, st.tx, st.ty, st.top.tx, st.top.ty)
    end
    key = table.concat(key, ";")
    local f = byKey[key]
    if not f then
      local shown = {}
      for _, st in ipairs(state) do if not marker[st.cell] then shown[#shown + 1] = st end end
      local px = A.render(set, shown, C, C, OX, OY, rasters)
      for i, v in pairs(px) do
        if v % 16 ~= 0 then
          local x, y = i % C, math.floor(i / C)
          x0 = (not x0 or x < x0) and x or x0; x1 = (not x1 or x > x1) and x or x1
          y0 = (not y0 or y < y0) and y or y0; y1 = (not y1 or y > y1) and y or y1
        end
      end
      local pt = points(state)
      pt.px = px
      frames[#frames + 1] = pt
      f = #frames
      byKey[key] = f
    end
    local last = runs[#runs]
    if last and last[1] == f then last[2] = last[2] + 1 else runs[#runs + 1] = { f, 1 } end
    machine.tick()
  end
  if not x0 then return nil end
  local W, H = x1 - x0 + 1, y1 - y0 + 1
  local pose = { ox = OX - x0, oy = OY - y0, width = W, height = H, anchors = frames[1].anchors,
                 base = frames[1].base, centre = frames[1].centre, frames = {}, runs = runs, loop = ticks }
  for i, fr in ipairs(frames) do pose.frames[i] = { anchors = fr.anchors, base = fr.base, centre = fr.centre } end
  if saveImage then
    local pal = set.normalPalette or set.palette
    local function crop(px, out, ox, oy, stride)
      for y = 0, H - 1 do
        local from, to = (y + y0) * C + x0, (y + oy) * stride + ox
        for x = 0, W - 1 do out[to + x] = px[from + x] end
      end
    end
    -- THE GRID IS ALLOCATED UP FRONT: filled a frame at a time it is out of
    -- order, so a plain table rehashes its way up to a few million slots, once
    -- per species -- which was 15% of a Black import without the JIT.
    local okNew, newTable = pcall(require, "table.new")
    local function canvas(size) return okNew and newTable(size, 1) or {} end
    local one = {}
    crop(frames[1].px, one, 0, 0, W)
    pose.image = saveImage(("bw_musical/poke_%03d"):format(species),
      { width = W, height = H, rgba = A.rgba(one, W, H, pal) }, { ox = pose.ox, oy = pose.oy })
    if #frames > 1 then
      local cols = math.min(#frames, 16)
      local rows = math.ceil(#frames / cols)
      local sw, sh = cols * W, rows * H
      local grid = canvas(sw * sh)
      for i, fr in ipairs(frames) do crop(fr.px, grid, ((i - 1) % cols) * W, math.floor((i - 1) / cols) * H, sw) end
      pose.cols = cols
      pose.strip = saveImage(("bw_musical/poke_%03d_anim"):format(species),
        { width = sw, height = sh, rgba = A.rgba(grid, sw, sh, pal) }, { frames = #frames })
    end
  end
  return pose
end

function M.poses(rom, saveImage, eligible)
  local bytes = rom:read(M.PATH.poses)
  local arc = bytes and Narc.parse(bytes)
  if not arc then return nil end
  local out, n = {}, 0
  for sp = 1, 649 do
    if not eligible or eligible[sp] ~= false then
      local ok, pose = pcall(M.pose, arc, sp, saveImage)
      if ok and pose then out[sp] = pose n = n + 1 end
    end
  end
  return out, n
end

function M.build(x)
  local rom = x.rom
  local names, namesA, words = {}, {}, {}
  if x.string then
    for i = 0, M.PROP_COUNT + 2 do
      names[i] = x:string(M.BANK.propNames, i)
      namesA[i] = x:string(M.BANK.propNamesA, i)
    end
    for i = 0, 23 do words[i] = x:string(M.BANK.words, i) end
  end
  local props = M.props(rom, names)
  if not props then return nil end
  local rec = {
    source = "ROM:/a/0/4/5 (props) + /a/1/1/1-4 (shows) + /a/0/4/8 + ov10/arm9 tables",
    props = props, words = words, startProps = M.START_PROPS, fanSprite = M.FAN_SPRITE,
    shows = {}, species = M.species(rom),
  }
  for i = 0, M.PROP_COUNT - 1 do props[i].nameA = namesA[i + 3] end
  for i, path in ipairs(M.PATH.shows) do
    rec.shows[i - 1] = M.show(rom, path, i - 1)
    if rec.shows[i - 1] then rec.shows[i - 1].script = M.choreography(rom, path) end
  end
  local fans = M.fanTables(rom)
  if fans then rec.fanThresholds, rec.fanGifts = fans.thresholds, fans.gifts end
  local saveImage = x.saveImage and function(rel, image, extra) return x:saveImage(rel, image, extra) end
  rec.images = M.images(rom, saveImage)
  rec.poses = M.poses(rom, saveImage)
  return rec
end

return M
