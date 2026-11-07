-- BLACK AND WHITE'S FIELD, IN THE SHAPE THE GEN 4 RENDERER READS.
--
-- The user's ask was that Gen 5 use Platinum's camera and its controls, which
-- means the Unova field has to come out as the tables Gen4Ground draws --
-- gen4_terrain, its matrices and chunks, map defs cut from a shared grid --
-- rather than as a third renderer. That is possible because the formats agree
-- where it matters:
--
--   * every chunk's model is an NSBMD (all 649 of /a/0/0/8 pack through
--     Gen4ModelPack and pass its round-trip check), and
--   * each zone names ONE texture set by its area field, /a/0/1/4 (Striaton's
--     three chunks wear 39 textures, every one of them in set 6, its area).
--
-- PERMISSIONS are translated tile by tile into the Gen 4 word the engine walks
-- on: the behaviour in the low byte, bit 15 for "blocked". In a WB chunk each
-- tile is 8 bytes, and an interior shows which are which -- a 13 x 15 room's
-- floor is byte 4 = 0x00 / byte 6 = 0x80, its walls 0x01 / 0x81, its counters
-- 0xD4 / 0x01: byte 4 is the behaviour and bit 0 of byte 6 the collision.
-- (Bytes 0..3 vary with slopes and are not read yet; the ground's height comes
-- from the model, as it does where a Gen 4 chunk has no BDHC.)
--
-- Map ids are "Z<zone>" and carry the zone's place name from system bank 89.
-- The camera is Black and White's own: the zone header's +0x1C bits 9..15
-- index /a/0/6/0 (see THE CAMERAS below), carried on the def as gen5Camera.

local M = require("src.import.Gen5Maps")
local Nsbmd = require("src.import.Gen4Nsbmd")
local Pack = require("src.import.Gen4ModelPack")
local Models = require("src.import.Gen4Models")
local Terrain = require("src.import.Gen4Terrain")
local Gen4Maps = require("src.import.Gen4Maps")
local Graphics = require("src.import.Gen4Graphics")

local F = {}

F.PATH = {
  zones = "/a/0/1/2", matrices = "/a/0/0/9", chunks = "/a/0/0/8",
  textures = "/a/0/1/4", events = "/a/1/2/5",
}
F.CHUNK = 32
F.NO_CHUNK = 0xFFFF
F.HeightValues = require("src.import.Gen5Heights")

-- permissions(raw WB section) -> 1024 Gen 4 permission words, little-endian
function F.permissions(raw)
  if type(raw) ~= "string" or #raw < 4 + F.CHUNK * F.CHUNK * 8 then return nil end
  local out = {}
  for t = 0, F.CHUNK * F.CHUNK - 1 do
    local at = 4 + t * 8
    local behaviour = raw:byte(at + 5)
    local blocked = raw:byte(at + 7) % 2 == 1
    local word = behaviour + (blocked and 0x8000 or 0)
    out[t + 1] = string.char(word % 256, math.floor(word / 256))
  end
  return table.concat(out)
end

-- A GC CHUNK'S SECOND LAYER IS A SECOND FLOOR. Its 8-byte tiles have the
-- first layer's shape (after the same 4-byte 32 x 32 header), and where the
-- two differ the second is the deck over the first: Pinwheel Forest's bridge
-- (Z155 (71..76, 50..53)) is river (0x3D) and bank wall in layer one and flat
-- open ground at the approach's height in layer two. Read from layer one
-- alone, the forest's north half -- the last grunt, the Dragon Skull -- could
-- not be reached. The engine walks one grid, so a tile takes layer two's
-- record where layer one is solid or water and layer two is open ground: the
-- deck is walked, and the river under it is not surfed (not modelled).
-- Drayden's gym keeps layer one (F.LAYERS_APART): its statues' walkways are
-- opened and closed by the gym's own code.
local BW_WATER = { [0x3D] = true, [0x3F] = true, [0x41] = true }
F.LAYERS_APART = { [121] = true }
function F.mergeLayers(raw, layer2)
  if type(raw) ~= "string" or type(layer2) ~= "string"
     or #raw < 4 + F.CHUNK * F.CHUNK * 8 or #layer2 < 4 + F.CHUNK * F.CHUNK * 8 then return raw end
  local out, changed = { raw:sub(1, 4) }, 0
  for t = 0, F.CHUNK * F.CHUNK - 1 do
    local at = 4 + t * 8
    local a, b = raw:sub(at + 1, at + 8), layer2:sub(at + 1, at + 8)
    local aShut = a:byte(7) % 2 == 1 or BW_WATER[a:byte(5)]
    local bOpen = b:byte(7) % 2 == 0 and not BW_WATER[b:byte(5)]
    -- ...AND ONLY WHERE LAYER TWO IS A RAISED SURFACE: a height (bytes 2-3) or
    -- a slope (bytes 0-1). Layer two also repeats the ground with its low
    -- walls left out, and taking that opened them: the Dreamyard's wall south
    -- of its raised floor (row 19) was walked through. Where it is raised it
    -- wins even over open ground beneath -- the deck the Dreamyard's stairs
    -- climb to (x 30..39, y 5..14) sits over ground the single grid cannot
    -- also keep, and the stairs must arrive on the deck: layer two carries the
    -- whole flight (x 35..36, y 8..11), layer one only its foot.
    -- ...OR a deck over WATER, or over a solid tile at ANOTHER height:
    -- Pinwheel Forest's bridge is layer-two ground with no height of its own
    -- laid over the river and its banks (height 0x2D) -- the way to Castelia.
    -- A solid tile at the SAME height is a real wall layer two leaves out.
    local bRaised = (b:byte(1) + b:byte(2) + b:byte(3) + b:byte(4)) ~= 0
    local over = BW_WATER[a:byte(5)]
                 or (a:byte(7) % 2 == 1 and (a:byte(3) ~= b:byte(3) or a:byte(4) ~= b:byte(4)))
    if bOpen and (bRaised or over) and a ~= b then
      out[#out + 1] = b; changed = changed + 1
    else out[#out + 1] = a end
  end
  out[#out + 1] = raw:sub(4 + F.CHUNK * F.CHUNK * 8 + 1)
  return table.concat(out), changed
end

-- bigGrid(raw WB section) -> a whole map's grid for a chunk wider than 32
-- (its header's width / height), or nil for an ordinary 32 x 32 one: the
-- blocks in the shape the rails write (0xFF blocked), the behaviours, and the
-- flat tiles' heights
-- (`values`: Gen5Heights' table, what each tile's height value means)
function F.bigGrid(raw, values)
  if type(raw) ~= "string" or #raw < 4 then return nil end
  local w = raw:byte(1) + raw:byte(2) * 256
  local h = raw:byte(3) + raw:byte(4) * 256
  if w == F.CHUNK and h == F.CHUNK then return nil end
  if w < 1 or h < 1 or #raw < 4 + w * h * 8 then return nil end
  local blocks, behav, heights = {}, {}, {}
  for t = 0, w * h - 1 do
    local at = 4 + t * 8
    local blocked = raw:byte(at + 7) % 2 == 1
    blocks[t + 1] = blocked and "\255\0" or "\0\0"
    behav[t + 1] = string.char(raw:byte(at + 5))
    if raw:byte(at + 1) == 0 and raw:byte(at + 2) == 0 then
      local y = raw:byte(at + 3) + raw:byte(at + 4) * 256
      if values then y = values[y] or 0 elseif y >= 0x8000 then y = y - 0x10000 end
      if y ~= 0 then heights[(t % w) .. "," .. math.floor(t / w)] = y end
    end
  end
  return { width = w, height = h, blocks = table.concat(blocks), behaviorCells = table.concat(behav),
           heights = heights }
end

-- (SUPERSEDED for the maps' heights: the u16 below NAMES a height rather
-- than being one -- src/import/Gen5Heights.lua -- and the map loop reads it
-- through that table; this raw reader is kept for its callers.)
-- HEIGHTS, from the same 8-byte tile records: bytes 0-1 are 0 on a flat
-- tile, and then bytes 2-3 are its height in world units (16 to a tile),
-- signed. Striaton's ground is 0 with ledges at 24; the Trio Badge gym's
-- dais is 14 on exactly its 7 x 6 tiles; Nacrene's raised streets are 120.
-- A non-zero bytes 0-1 (3% of tiles: the stairs and slopes, 0x0008 on the
-- gym's front step) is a sloped surface whose encoding is not read yet, so
-- those tiles are left out and take their neighbours' height.
-- heights(raw) -> { [tile + 1] = height } for the flat, non-zero tiles
function F.heights(raw)
  if type(raw) ~= "string" or #raw < 4 + F.CHUNK * F.CHUNK * 8 then return nil end
  local out = {}
  for t = 0, F.CHUNK * F.CHUNK - 1 do
    local at = 4 + t * 8
    if raw:byte(at + 1) == 0 and raw:byte(at + 2) == 0 then
      local h = raw:byte(at + 3) + raw:byte(at + 4) * 256
      if h >= 0x8000 then h = h - 0x10000 end
      if h ~= 0 then out[t + 1] = h end
    end
  end
  return out
end

-- the Gen 4 matrix shape (Gen4Maps.matrix) of a BW matrix
local function gen4Matrix(m, id)
  if not m then return nil end
  local maps, headers = {}, nil
  for i = 1, m.width * m.height do maps[i] = m.chunks[i] or F.NO_CHUNK end
  if m.zones then
    headers = {}
    for i = 1, m.width * m.height do headers[i] = m.zones[i] or 0 end
  end
  return { width = m.width, height = m.height, maps = maps, headers = headers,
           name = ("matrix_%03d"):format(id) }
end

-- BUILDINGS. A WB chunk's third section places them: u32 count, then per
-- building fx32 x, y, z, a u16 rotation (0 / 0x4000 / 0x8000 / 0xC000 --
-- the four quarter turns, nothing else occurs in 2,320 placements) and a u16
-- that is the building's id, big-endian (F.placements). The id is not an index into one
-- archive: it names a building IN THE AREA'S PACK, /a/2/2/9 outdoors (52
-- packs, "AB") and /a/2/3/0 indoors (64). A pack is a table of entries: the
-- first half are each building's record, opening with its id, and the second
-- half are the models in the same order; the models carry no textures, which
-- are the pack's own set in /a/1/7/6 (outdoor) or /a/1/7/7 (indoor), one per
-- pack.
--
-- WHICH PACK. Of the 19 outdoor zones whose placed ids fit exactly one pack,
-- 18 are pack = floor(area / 4) -- every outdoor area is 4k + 2, the texture
-- sets coming four to a place (a season each) -- and no zone-header or area
-- field predicts the pack better. The rule is used and the one zone it does
-- not explain is reported, not papered over.
--
-- Indoors it is an offset: areas 216..236 are indoor packs 6..26 (every zone
-- whose ids fit one pack, e.g. 217 -> 7, 219 -> 9, 248 -> 38), so the 210s up
-- are pack = area - 210; an area below that is an outdoor-style place (a cave,
-- a gate) and takes the outdoor rule.
function F.packFor(area)
  if area >= 210 then return "indoor", area - 210 end
  return "outdoor", math.floor(area / 4)
end
F.BUILDING_PACKS = { outdoor = "/a/2/2/9", indoor = "/a/2/3/0" }
F.BUILDING_TEXTURES = { outdoor = "/a/1/7/6", indoor = "/a/1/7/7" }
F.PLACEMENT_BYTES = 16

function F.placements(raw)
  if type(raw) ~= "string" or #raw < 4 then return {} end
  local n = raw:byte(1) + raw:byte(2) * 256 + raw:byte(3) * 65536 + raw:byte(4) * 16777216
  if 4 + n * F.PLACEMENT_BYTES ~= #raw then return {} end
  local function s32(o)
    local a, b, c, d = raw:byte(o + 1, o + 4)
    local v = a + b * 256 + c * 65536 + d * 16777216
    return v >= 2147483648 and v - 4294967296 or v
  end
  local out = {}
  for i = 0, n - 1 do
    local o = 4 + i * F.PLACEMENT_BYTES
    local rot = raw:byte(o + 13) + raw:byte(o + 14) * 256
    -- Z IS STORED NEGATED (north positive): read as it stands, Nuvema's
    -- living-room furniture stood half a chunk south of its own floor (the
    -- floor spans z -250..-72, the pieces 120..232) and Striaton's gym a
    -- block away from its door; negated, both sit where the doors and walls
    -- say. The rotation is used as stored.
    -- THE ID IS BIG-ENDIAN over bytes 14..15 (READ FROM CODE, ov21
    -- 0x0218B974 / 0x0218BA04: `b[0xE] << 8 | b[0xF]`): 92 of Black's 2,584
    -- placements name a record past 255 (byte 14 = 1), which byte 15 alone
    -- turned into another building
    out[i + 1] = { model = raw:byte(o + 15) * 256 + raw:byte(o + 16), x = s32(o) / 4096, y = s32(o + 4) / 4096, z = -s32(o + 8) / 4096,
                   rotY = rot / 65536 * 360, gen5 = true }
  end
  return out
end

-- pack(bytes) -> { ids = { [i] = id }, models = { [i] = BMD0 bytes } }
function F.pack(bytes)
  if type(bytes) ~= "string" or bytes:sub(1, 2) ~= "AB" then return nil end
  local function u32(o) local a, b, c, d = bytes:byte(o + 1, o + 4); return a + b * 256 + c * 65536 + d * 16777216 end
  local n = bytes:byte(3) + bytes:byte(4) * 256
  local ids, models = {}, {}
  for i = 0, n - 1 do
    local a, e = u32(4 + i * 4), u32(4 + (i + 1) * 4)
    if a < e and e <= #bytes then
      local seg = bytes:sub(a + 1, e)
      -- a record opens with a u16 id and a u16 of its own (non-zero on the
      -- animated props: the Center's healing machine is 00 00 07 00). Read
      -- as one u32 those ids came out as 458752 and the like, and every
      -- animated building -- the healing machine, the Center's screen, its
      -- PCs -- went undrawn
      if seg:sub(1, 4) == "BMD0" then models[#models + 1] = seg else ids[#ids + 1] = u32(a) % 65536 end
    end
  end
  return { ids = ids, models = models }
end

-- packs(rom, kind, save) -> { [pack] = { label, path, models = { [id + 1] = packed } } }
function F.buildingPacks(rom, kind, save)
  local Narc = require("src.import.NarcArchive")
  local packBytes, texBytes = rom:read(F.BUILDING_PACKS[kind]), rom:read(F.BUILDING_TEXTURES[kind])
  local packs, texArc = packBytes and Narc.parse(packBytes), texBytes and Narc.parse(texBytes)
  local out, models, shapes = {}, 0, 0
  if not packs then return out, 0, 0 end
  for p = 0, packs.count - 1 do
    local pk = F.pack(packs:get(p))
    local tb = texArc and texArc:get(p)
    if tb and Graphics.isCompressed(tb) then tb = Graphics.decompress(tb) end
    local textures = tb and Models.parse(tb)
    local set = { label = ("%s buildings %d"):format(kind, p), path = F.BUILDING_PACKS[kind], models = {} }
    for i, bmd in ipairs(pk and pk.models or {}) do
      local id = pk.ids[i]
      local parsed = Nsbmd.parse(bmd)
      local model = parsed and parsed.models and parsed.models[1]
      local packed = model and Pack.pack(model)
      if packed and id then
        local written = {}
        for _, shape in ipairs(packed.shapes) do
          local name = shape.texture
          if name and textures then
            if written[name] == nil then
              written[name] = false
              local index, palette
              for k, t in ipairs(textures.textures) do if t.name == name then index = k end end
              for k, pl in ipairs(textures.palettes or {}) do if pl.name == shape.palette then palette = k end end
              local image = index and Models.decode(textures, tb, index, palette or 1)
              local saved = image and save.image(("models/bw_%s/%02d/%d_%s"):format(kind, p, id, name:gsub("[^%w_%-]", "_")),
                                                 image, { texture = name, palette = shape.palette })
              written[name] = saved and saved.path or false
            end
            shape.image = written[name] or nil
          end
          shapes = shapes + 1
        end
        packed.member = id
        set.models[id + 1] = packed
        models = models + 1
      end
    end
    -- ...and the buildings' animations, out of the same records
    -- (src/import/Gen5BuildingAnim.lua)
    pcall(require("src.import.Gen5BuildingAnim").attach, set, packs:get(p), textures, tb, save, kind, p)
    out[p] = set
  end
  return out, models, shapes
end

-- CHARACTERS (Gen5Overworld): every sprite id's model member made into a
-- sheet, keyed SPRITE_G4_<member> as Platinum's are. The frame order was read
-- off the sheets themselves: a 12-frame-plus sheet (the player's has 32) is
-- three a direction -- stand, step, step -- up, down, left, right, the run
-- after; fewer than that stand still.
--
-- AN 8-FRAME SHEET (the Pokemon) IS TWO A SIDE: up, down, left, right.
--
-- A 7-FRAME SHEET (65 of the people, and the 9-frame gym leaders with two poses
-- after them) IS NOT 7 = 2+2+3 WITH A RIGHT FRAME. Frames 4, 5 and 6 are ALL
-- THE WEST SIDE -- stand, step, the other step -- and the east side is those
-- three mirrored; up and down have one step each, whose other foot is the same
-- frame mirrored. Measured over the sheets: frame 6 matches frame 4 as drawn, not
-- frame 4 mirrored, on every asymmetric one. Reported from play as trainers
-- "walking backwards" -- frame 6 is a west frame, and Striaton's first trainer
-- walks east. `mirrorRight` / `mirrorStep` are read by SpriteRenderer.facingFrames.
function F.facingsFor(frames)
  if frames >= 12 then
    return { up = { 0, 1, 2 }, down = { 3, 4, 5 }, left = { 6, 7, 8 }, right = { 9, 10, 11 } }
  elseif frames == 8 then
    return { up = { 0, 1, 1 }, down = { 2, 3, 3 }, left = { 4, 5, 5 }, right = { 6, 7, 7 } }
  elseif frames >= 7 then
    return { up = { 0, 1, 1 }, down = { 2, 3, 3 }, left = { 4, 5, 6 }, right = { 4, 5, 6 },
             mirrorRight = true, mirrorStep = true }
  end
  return nil
end

function F.characters(rom, save)
  local O = require("src.import.Gen5Overworld")
  local Narc = require("src.import.NarcArchive")
  local tb, mb = rom:read(O.TABLE), rom:read(O.MODELS)
  local table_ = tb and O.table(Narc.parse(tb):get(0)) or {}
  local arc = mb and Narc.parse(mb)
  local sprites, done, written = {}, {}, 0
  for _, member in pairs(table_) do
    if arc and not done[member] and member < arc.count then
      done[member] = true
      local b = arc:get(member)
      local btx = b and ((b:sub(1, 4) == "BTX0") and b or O.btx(b))
      local sheet = btx and Models.sheet(btx, { color0Transparent = true })
      if sheet then
        local key = ("SPRITE_G4_%03d"):format(member)
        local entry = save.image(("overworld/bw_%03d"):format(member), sheet, { member = member })
        if entry then
          local facings = F.facingsFor(sheet.frames)
          sprites[key] = { id = key, image = entry.path, frames = sheet.frames, frameWidth = sheet.frameWidth,
            frameHeight = sheet.frameHeight, walker = sheet.frames > 1, trueColor = true,
            facings = facings, source = ("ROM:/a/0/4/9[%d]"):format(member) }
          written = written + 1
        end
      end
    end
  end
  return sprites, table_, written
end

-- build(x) -> tables; `x` is RomExtractorGen5 (archive(), string(), rom)
-- `save` = { image = function(rel, image, extra), binary = function(rel, bytes) }
function F.build(x, save)
  local rom = x.rom
  local Narc = require("src.import.NarcArchive")
  local function arc(p) local b = rom:read(p); return b and Narc.parse(b) end
  local zoneArc, mxArc, chunkArc, texArc = arc(F.PATH.zones), arc(F.PATH.matrices), arc(F.PATH.chunks), arc(F.PATH.textures)
  local zones = M.zones(zoneArc:get(0))
  local report = {}

  -- chunks: packed models and translated permissions
  local blob = Terrain.newBlob()
  local terrainChunks, permissions, lands, refused, heightsOf = {}, {}, {}, {}, {}
  -- what each tile's height value means (src/import/Gen5Heights.lua)
  local heightTable = F.HeightValues.build(rom) or {}
  -- NG ("no grid") chunks: no permissions, and a model at posScale 512 --
  -- eight times a WB chunk's 64 -- so each spans 4,096 units, 256 tiles.
  -- A matrix made only of them is a RAIL map (Gen5Field's rails below).
  local ngChunks, rawPerms = {}, {}
  -- the chunks of Drayden's gym (zone 121), whose second layer is the
  -- statues' walkways that Gen5DragonGym opens and closes: kept apart
  -- (F.mergeLayers)
  local gimmickChunks = {}
  for id, z in pairs(zones) do
    local m = F.LAYERS_APART[id] and M.matrix(mxArc:get(z.matrix)) or nil
    for _, c in ipairs(m and m.chunks or {}) do gimmickChunks[c] = true end
  end
  -- BLACK CITY / WHITE FOREST: their RD chunks with the pieces laid over
  -- them (src/import/Gen5DynamicCity.lua) -- permissions and buildings
  local cityChunks = {}
  do
    local City = require("src.import.Gen5DynamicCity")
    local rdChunks, any = {}, false
    for c = 0, chunkArc.count - 1 do
      local b = chunkArc:get(c)
      if b and b:sub(1, 2) == "RD" then
        local ch = M.chunk(b)
        if ch and ch.permissions then rdChunks[c] = ch.permissions; any = true end
      end
    end
    if any then
      local mats = {}
      for i = 0, mxArc.count - 1 do mats[i] = M.matrix(mxArc:get(i)) end
      local packArc = arc(F.BUILDING_PACKS.outdoor)
      local okC, built, lines = pcall(City.build, rom, { matrices = mats, rdChunks = rdChunks,
        packIds = function(mid)
          for _, z in pairs(zones) do
            if z.matrix == mid then
              local kind, p = F.packFor(z.area)
              local pk = kind == "outdoor" and packArc and p < packArc.count and F.pack(packArc:get(p))
              if pk then
                local ids = {}
                for _, id in ipairs(pk.ids) do ids[id] = true end
                return ids
              end
            end
          end
        end })
      if okC then cityChunks = built or {}; report.dynamicCity = lines
      else report.dynamicCity = { "failed: " .. tostring(built) } end
    end
  end
  for c = 0, chunkArc.count - 1 do
    local chunk = M.chunk(chunkArc:get(c))
    if chunk and cityChunks[c] then chunk.permissions = cityChunks[c].permissions end
    if chunk and chunk.kind == "GC" and chunk.layer2 and not gimmickChunks[c] then
      local merged, n = F.mergeLayers(chunk.permissions, chunk.layer2)
      chunk.permissions = merged
      if n and n > 0 then report.gcDecks = (report.gcDecks or 0) + n end
    end
    if chunk and chunk.permissions then rawPerms[c] = chunk.permissions end
    local set = chunk and Nsbmd.parse(chunk.model)
    local model = set and set.models and set.models[1]
    local packed = model and Pack.pack(model)
    if packed and Pack.verify(model, packed) then
      local perms = chunk.permissions and F.permissions(chunk.permissions) or nil
      permissions[c] = perms
      heightsOf[c] = chunk.permissions and F.heights(chunk.permissions) or nil
      lands[c] = { permissions = perms or string.rep("\0\128", F.CHUNK * F.CHUNK) }
      if chunk.kind == "NG" then ngChunks[c] = true end
      local objects = F.placements(chunk.buildings)
      for _, o in ipairs(cityChunks[c] and cityChunks[c].objects or {}) do objects[#objects + 1] = o end
      terrainChunks[c] = Terrain.append(blob, { packed = packed, permissions = perms,
                                                objects = objects })
    else
      refused[c] = chunk and chunk.kind or "unparsed"
    end
  end
  local geometry, heights, perms = Terrain.finish(blob)

  -- matrices, in both shapes the Gen 4 code reads
  local matrices, gen4Matrices, layouts, grids = {}, {}, {}, {}
  local function chunkFor(id) return id and id ~= F.NO_CHUNK and lands[id] or nil end
  for i = 0, mxArc.count - 1 do
    local m = M.matrix(mxArc:get(i))
    local g4 = gen4Matrix(m, i)
    if g4 then
      gen4Matrices[i] = g4
      grids[i] = Terrain.grid(g4)
      local def = Gen4Maps.mapDef(g4, chunkFor)
      if def then def.name = g4.name; layouts[i] = def end
    end
  end

  -- texture sets, with the palette each texture is worn with
  local pairing = {}
  for _, entry in pairs(terrainChunks) do
    for _, shape in ipairs(entry.shapes or {}) do
      if shape.texture and shape.palette then
        pairing[shape.texture] = pairing[shape.texture] or {}
        pairing[shape.texture][shape.palette] = (pairing[shape.texture][shape.palette] or 0) + 1
      end
    end
  end
  local sets, setsBuilt = {}, 0
  for s = 0, texArc.count - 1 do
    local bytes = texArc:get(s)
    if bytes and Graphics.isCompressed(bytes) then bytes = Graphics.decompress(bytes) end
    local parsed = bytes and Models.parse(bytes)
    local list = parsed and Terrain.textures(parsed, bytes, pairing)
    if list then
      local entry = { textures = {} }
      for _, tex in ipairs(list) do
        local safe = tostring(tex.name):gsub("#", "__"):gsub("[^%w_%-]", "_")
        local saved = save.image(("terrain/tex/%03d/%s"):format(s, safe), tex.image,
                                 { texture = tex.texture, palette = tex.palette })
        if saved then entry.textures[tex.name] = saved end
      end
      sets[s] = entry
      setsBuilt = setsBuilt + 1
    end
  end

  -- THE CAMERAS: /a/0/6/0 is one table of 44-byte records (38 in Black),
  -- read at index * 44 by the field camera (0x0218E260). Decoded:
  --   00 u32 distance (world units)   04 u16 pitch (0x25D8 = 53.2 degrees,
  --   not negated as Platinum's is)   12 u16 the half field of view (0x0E38
  --   = 20 degrees)   20 VecFx32 look-at offset (the default lifts it 4)
  -- The default's distance and FOV give 1.1 pixels a unit, the scale
  -- Platinum's rows give. NOT DECODED: the near / far planes (the u16 at
  -- 0x1A -- 0x40 on the default -- is taken as far = that x 16, near 16).
  local cameras = {}
  local camBytes = rom:read("/a/0/6/0")
  local camArc = camBytes and Narc.parse(camBytes)
  local camTable = camArc and camArc:get(0)
  if camTable then
    local function cu16(o) return camTable:byte(o + 1) + camTable:byte(o + 2) * 256 end
    local function cs32(o)
      local v = cu16(o) + cu16(o + 2) * 65536
      return (v >= 2147483648 and v - 4294967296 or v) / 4096
    end
    for i = 0, math.floor(#camTable / 44) - 1 do
      local o = i * 44
      cameras[i] = { id = ("bw_%d"):format(i), family = "bw",
        distance = cu16(o) + cu16(o + 2) * 65536,
        pitch = cu16(o + 4) * 360 / 65536, projection = "perspective",
        halfFov = cu16(o + 0x12) * 360 / 65536,
        near = 16, far = math.max(cu16(o + 0x1A), 32) * 16,
        offset = { x = cs32(o + 0x20), y = cs32(o + 0x24), z = cs32(o + 0x28) } }
    end
  end

  -- THE RAILS (Black and White's non-grid ground: Castelia's ring, the
  -- bridges, Victory Road). The chain, read off the field code:
  --   zone -> a packed u16 table in the ARM9 right after the 11-entry rail
  --     zone list (low 11 bits the zone, high 5 an index; 0x0209E026 in
  --     Black, found by the list 28, 249, 214 that opens it)
  --   -> /a/1/0/9[index] = { u16 rail file, u16 camera area } (0x021BB278)
  --   -> /a/0/7/9[rail file]: a header of u32 offsets and four sections of
  --     records, named in the cartridge's own bytes -- POINTS ("RE_POINT_n",
  --     112 bytes: four line slots, four direction keys, four widths, fx32
  --     x / y / z), LINES ("RE_LINE_n", 72 bytes: point a, point b, then
  --     shape / camera references), 36-byte line shapes (section C; type 3
  --     and 5 / 6 seen) and 36-byte curve records (section D; type 1 = a
  --     circle about the fx32 centre that follows -- Castelia's plaza).
  -- Positions are world units; an NG chunk's model is posScale 512, eight
  -- times a WB chunk's, which is why the points run past a 32-tile chunk.
  -- Extracted here as data only: nothing walks on it yet.
  local rails = {}
  do
    local arm9 = rom:arm9()
    local key = string.char(0x1C, 0x00, 0xF9, 0x00, 0xD6, 0x00)
    local at = arm9 and arm9:find(key, 1, true)
    local railArc = rom:read("/a/0/7/9") and Narc.parse(rom:read("/a/0/7/9"))
    local mapArc = rom:read("/a/1/0/9") and Narc.parse(rom:read("/a/1/0/9"))
    if at and railArc and mapArc then
      local function au16(o) return arm9:byte(o) + arm9:byte(o + 1) * 256 end
      local tableAt = at + 22
      local function ru32(d, o) return d:byte(o + 1) + d:byte(o + 2) * 256 + d:byte(o + 3) * 65536 + d:byte(o + 4) * 16777216 end
      local function rs32(d, o) local v = ru32(d, o) return v >= 2147483648 and v - 4294967296 or v end
      local function name(d, o, n) return (d:sub(o + 1, o + n):gsub("[%z ]+$", "")) end
      local files = {}
      local function railFile(f)
        if files[f] ~= nil then return files[f] end
        local d = railArc:get(f)
        if not d or #d < 0x1C then files[f] = false return false end
        local h = {} for k = 0, 6 do h[k] = ru32(d, k * 4) end
        local out = { file = f, points = {}, lines = {}, shapes = {}, curves = {} }
        for i = 0, math.floor((h[3] - h[2]) / 0x70) - 1 do
          local o = h[2] + i * 0x70
          local pt = { lines = {}, keys = {}, widths = {}, name = name(d, o + 0x40, 0x30) }
          for k = 0, 3 do
            local l = ru32(d, o + k * 4)
            pt.lines[k + 1] = l ~= 0xFFFF and l or false
            pt.keys[k + 1] = ru32(d, o + 0x10 + k * 4)
            pt.widths[k + 1] = ru32(d, o + 0x20 + k * 4)
          end
          pt.x, pt.y, pt.z = rs32(d, o + 0x30) / 4096, rs32(d, o + 0x34) / 4096, rs32(d, o + 0x38) / 4096
          out.points[i] = pt
        end
        for i = 0, math.floor((h[4] - h[3]) / 0x48) - 1 do
          local o = h[3] + i * 0x48
          local raw = {} for k = 0, 5 do raw[k + 1] = ru32(d, o + k * 4) end
          out.lines[i] = { a = raw[1], b = raw[2], raw = raw, name = name(d, o + 0x18, 0x30) }
        end
        for i = 0, math.floor((h[5] - h[4]) / 0x24) - 1 do
          local o = h[4] + i * 0x24
          local raw = {} for k = 0, 8 do raw[k + 1] = rs32(d, o + k * 4) end
          out.shapes[i] = raw
        end
        for i = 0, math.floor((h[6] - h[5]) / 0x24) - 1 do
          local o = h[5] + i * 0x24
          local kind = ru32(d, o)
          out.curves[i] = { kind = kind, cx = rs32(d, o + 4) / 4096, cy = rs32(d, o + 8) / 4096, cz = rs32(d, o + 12) / 4096 }
        end
        files[f] = out
        return out
      end
      for k = 0, 19 do
        local v = au16(tableAt + k * 2)
        local zone, index = v % 2048, math.floor(v / 2048)
        local m = mapArc:get(index)
        if m and #m >= 4 then
          local f = m:byte(1) + m:byte(2) * 256
          local area = m:byte(3) + m:byte(4) * 256
          local rf = f ~= 0xFFFF and railFile(f) or nil
          if rf then rails[zone] = { index = index, file = f, cameraArea = area ~= 0xFFFF and area or nil, data = rf } end
        end
      end
    end
  end

  -- WHICH MATRICES ARE ALL NG: drawn at eight times the chunk size, and
  -- their map defs sized to match (after the defs are built)
  local ngScale = {}
  for i, g4 in pairs(gen4Matrices) do
    local any, all = false, true
    for _, c in ipairs(g4.maps or {}) do
      if c ~= F.NO_CHUNK then any = true; if not ngChunks[c] then all = false end end
    end
    if any and all then ngScale[i] = 8 end
  end

  -- map defs and the per-map terrain record, one per zone
  local names = x:bank(89)
  local maps, headers, terrainMaps = {}, {}, {}
  local extentsByMatrix = {}
  for id, z in pairs(zones) do
    local mapId = ("Z%03d"):format(id)
    local layout, g4 = layouts[z.matrix], gen4Matrices[z.matrix]
    headers[id] = { id = id, internalName = mapId, matrix = z.matrix, area = z.area,
                    scripts = z.scripts, initScripts = z.initScripts, messages = z.messages,
                    encounters = z.encounters, events = z.events, family = "bw" }
    if layout and g4 then
      local grid, region = layout, nil
      if g4.headers then
        extentsByMatrix[z.matrix] = extentsByMatrix[z.matrix] or Gen4Maps.extents(g4) or {}
        region = extentsByMatrix[z.matrix][id]
        local cut = region and Gen4Maps.crop(layout, region.x, region.y, region.width, region.height)
        if cut then grid = cut end
      end
      maps[mapId] = {
        id = mapId, header = id, layout = z.matrix,
        label = names and names[z.nameIndex] or mapId,
        width = grid.width, height = grid.height,
        blocks = grid.blocks, behaviorCells = grid.behaviorCells,
        borderBlock = grid.borderBlock, blockPx = 16, generation = 4, gen5 = true,
        tileset = require("src.import.Gen4Tileset").ID,
        originX = grid.originX or (region and region.x) or 0,
        originY = grid.originY or (region and region.y) or 0,
        encounters = z.encounters, events = z.events, messages = z.messages,
        music = z.music, objects = {}, warps = {}, signs = {}, coordEvents = {},
        gen5Camera = cameras[z.camera or 0] or cameras[0],
        gen5Rail = rails[id] and { file = rails[id].file, cameraArea = rails[id].cameraArea } or nil,
        gen5NoGrid = ngScale[z.matrix] and true or nil,
        -- the zone's field permissions (Gen5FieldRules.allowBike ...)
        gen5Flags = z.fieldFlags,
      }
      -- the heights, as the per-tile override Gen4Ground:heightsAt reads first
      -- (the tile's flat value NAMES a height: src/import/Gen5Heights.lua;
      -- a 0 is written only beside a raised tile, so the floor next to a
      -- table does not take the table's height from Gen4Ground's neighbours)
      local def, edits, n = maps[mapId], {}, 0
      local zeros = {}
      -- SLOPES: a tile whose value names no flat height is a stair or a hill
      -- (its plane is in the slope table this port does not read yet).
      -- Recorded so Gen4Ground:heightAtPixel can ramp across it between the
      -- flat tiles at its ends, instead of the player holding the top's height
      -- down the whole flight and dropping at the bottom.
      local slopes, nSlopes = {}, 0
      for ly = 0, def.height - 1 do
        for lx = 0, def.width - 1 do
          local mx, my = def.originX + lx, def.originY + ly
          local cx, cy = math.floor(mx / F.CHUNK), math.floor(my / F.CHUNK)
          local cid = cx < g4.width and cy < g4.height and g4.maps[cy * g4.width + cx + 1]
          local raw = cid and rawPerms[cid]
          local v = raw and F.HeightValues.valueAt(raw, (my % F.CHUNK) * F.CHUNK + (mx % F.CHUNK))
          local h = v and heightTable[v]
          if h and h ~= 0 then edits[lx .. "," .. ly] = h; n = n + 1
          elseif h then zeros[#zeros + 1] = { lx, ly }
          elseif raw and F.HeightValues.isSlope(raw, (my % F.CHUNK) * F.CHUNK + (mx % F.CHUNK)) then
            slopes[lx .. "," .. ly] = true; nSlopes = nSlopes + 1
          end
        end
      end
      for _, z in ipairs(zeros) do
        local x, y = z[1], z[2]
        if edits[(x - 1) .. "," .. y] or edits[(x + 1) .. "," .. y] or edits[x .. "," .. (y - 1)] or edits[x .. "," .. (y + 1)] then
          edits[x .. "," .. y] = 0; n = n + 1
        end
      end
      if n > 0 then def.gen4HeightEdits = edits end
      if nSlopes > 0 then def.gen5SlopeTiles = slopes end
      -- A 64 x 64 CHUNK: the permission section's header is its width and
      -- height (u16 each), 32 x 32 on every chunk but one -- chunk 120, the
      -- Pokemon League's grounds (zone 136, a 1 x 1 matrix), which is 64 x 64.
      -- Read as 32 x 32 the map ended at row 31 while its spawn (19, 49) and
      -- the entrance trigger (31, 48) lie below, and the player stood off
      -- the map unable to move. Its model spans 1,024 units: chunk scale 2.
      if g4.width == 1 and g4.height == 1 then
        local raw = rawPerms[g4.maps[1]]
        local big = raw and F.bigGrid(raw, heightTable)
        if big then
          def.width, def.height = big.width, big.height
          def.blocks, def.behaviorCells = big.blocks, big.behaviorCells
          def.gen4HeightEdits = next(big.heights) and big.heights or nil
          def.gen5ChunkScale = big.width / F.CHUNK
        end
      end
      local outdoors = g4.headers ~= nil
      local kind, pack = F.packFor(z.area)
      terrainMaps[mapId] = { texture = z.area, area = z.area, areaLight = 0, outdoors = outdoors,
                             buildingKind = kind, buildingPack = pack }
    end
  end

  -- the people, and every zone's events on its map
  local sprites, spriteTable, spriteCount = F.characters(rom, save)
  local function spriteFor(id)
    local member = spriteTable[id]
    local key = member and ("SPRITE_G4_%03d"):format(member)
    return (key and sprites[key]) and key or nil, member and ("bw_%03d"):format(member) or nil
  end
  local Events = require("src.import.Gen5Events")
  local evArc = arc(F.PATH.events)
  local npcs, placed = 0, 0
  for mapId, def in pairs(maps) do
    local z = zones[def.header]
    local ev = z and evArc and Events.parse(evArc:get(z.events))
    if ev then
      Events.attach(def, ev, spriteFor)
      for _, o in ipairs(def.objects) do npcs = npcs + 1; if o.sprite then placed = placed + 1 end end
    end
  end
  report.sprites, report.npcs, report.npcsWithSprite = spriteCount, npcs, placed
  -- CASTELIA GYM'S HONEY WALLS (zone 29's seven sprite-0 objects, script
  -- 2000): made passable, because the wall's own rule is not the object's --
  -- its centre lets the player through once its switches are down
  -- (src/world/Gen5CasteliaGym.lua, overlays 37 and 38).
  for _, def in pairs(maps) do
    if def.header == 29 then
      for _, o in ipairs(def.objects or {}) do if o.gen5Gimmick then o.passable = true end end
    end
  end
  -- WHITE SHOWS WHITE FOREST WHERE BLACK SHOWS BLACK CITY: the cartridge
  -- swaps zone 0 for 424 and 294 for 295 on every zone lookup while the
  -- save's city byte is 1 (src/import/Gen5DynamicCity.lua), so a White
  -- import sends the warps that lead to Black City to White Forest (the Black
  -- Gate's to Z424, with the same warp numbers)
  if x.version == "white" then
    local remap = require("src.import.Gen5DynamicCity").remap(rom)
    local n = 0
    for _, def in pairs(maps) do
      for _, w in ipairs(def.warps or {}) do
        local to = w.destHeader and remap[w.destHeader]
        if to and maps[("Z%03d"):format(to)] then
          w.destHeader, w.destMap = to, ("Z%03d"):format(to)
          n = n + 1
        end
      end
    end
    report.cityRemap = n
  end

  -- ONE MAP, SEVERAL TEXTURE SETS. A zone cut out of a shared matrix keeps
  -- the bounding box of its cells, and the box takes in its neighbours' chunks
  -- -- Route 1's holds Accumula's gate, whose shapes wear `out38_*` and
  -- `bgate02_*` from Accumula's set, not Route 1's. Gen4Ground draws a map
  -- with one set, so such a map gets a MERGED set: every zone's set whose cells
  -- lie in the box, the map's own first so a shared name keeps its own picture.
  local merged, mergedCount = {}, 0
  for mapId, rec in pairs(terrainMaps) do
    local def = maps[mapId]
    local g4 = def and gen4Matrices[def.layout]
    if g4 and g4.headers then
      local x0, y0 = math.floor(def.originX / F.CHUNK), math.floor(def.originY / F.CHUNK)
      local x1 = math.floor((def.originX + def.width - 1) / F.CHUNK)
      local y1 = math.floor((def.originY + def.height - 1) / F.CHUNK)
      local areas, order = {}, { rec.texture }
      areas[rec.texture] = true
      -- one chunk of margin: the camera sees past the box's edge
      for cy = math.max(0, y0 - 1), math.min(g4.height - 1, y1 + 1) do
        for cx = math.max(0, x0 - 1), math.min(g4.width - 1, x1 + 1) do
          local zid = g4.headers[cy * g4.width + cx + 1]
          local z = zid and zones[zid]
          if z and not areas[z.area] then areas[z.area] = true; order[#order + 1] = z.area end
        end
      end
      if #order > 1 then
        local key = 10000 + def.header
        local entry = { textures = {}, merged = order }
        for _, area in ipairs(order) do
          for name, tex in pairs((sets[area] or {}).textures or {}) do
            if entry.textures[name] == nil then entry.textures[name] = tex end
          end
        end
        merged[key] = entry
        rec.texture = key
        mergedCount = mergedCount + 1
      end
    end
  end
  for k, v in pairs(merged) do sets[k] = v end
  report.mergedSets = mergedCount

  local terrain = {
    source = "ROM:" .. tostring(x.version) .. " (/a/0/0/8 + /a/0/0/9 + /a/0/1/4)",
    chunkTiles = Terrain.CHUNK_TILES, tileUnits = Terrain.TILE_UNITS,
    chunkUnits = Terrain.CHUNK_UNITS, pixelsPerUnit = Terrain.PIXELS_PER_UNIT,
    chunks = terrainChunks, matrices = grids, maps = terrainMaps, sets = sets,
    refused = refused,
  }
  terrain.chunkFile = save.binary("terrain/chunks.bin", geometry)
  terrain.heightFile = save.binary("terrain/heights.bin", heights)
  terrain.permissionFile = save.binary("terrain/permissions.bin", perms)
  terrain.chunkBytes, terrain.heightBytes, terrain.permissionBytes = #geometry, #heights, #perms

  local outdoorPacks, outModels, outShapes = F.buildingPacks(rom, "outdoor", save)
  local indoorPacks, inModels, inShapes = F.buildingPacks(rom, "indoor", save)
  report.buildingModels, report.buildingShapes = outModels + inModels, outShapes + inShapes

  -- how many placements find their building in the pack their map names
  local found, missing = 0, 0
  for mapId, rec in pairs(terrainMaps) do
    local def, packs = maps[mapId], rec.buildingKind == "outdoor" and outdoorPacks or indoorPacks
    local set = packs[rec.buildingPack]
    local grid = def and grids[def.layout]
    if grid and def then
      local x0, y0 = math.floor(def.originX / F.CHUNK), math.floor(def.originY / F.CHUNK)
      local x1 = math.floor((def.originX + def.width - 1) / F.CHUNK)
      local y1 = math.floor((def.originY + def.height - 1) / F.CHUNK)
      for cy = y0, math.min(y1, grid.height - 1) do
        for cx = x0, math.min(x1, grid.width - 1) do
          local entry = terrainChunks[grid.land[cy * grid.width + cx + 1]]
          for _, o in ipairs(entry and entry.objects or {}) do
            if set and set.models[o.model + 1] then found = found + 1 else
              missing = missing + 1
              report.missingByKind = report.missingByKind or {}
              report.missingByKind[rec.buildingKind] = (report.missingByKind[rec.buildingKind] or 0) + 1
            end
          end
        end
      end
    end
  end
  report.placementsFound, report.placementsMissing = found, missing

  local count = function(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
  report.zones, report.maps, report.chunks = count(zones), count(maps), count(terrainChunks)
  report.refused, report.sets, report.layouts = count(refused), setsBuilt, count(layouts)
  -- THE SEAMS: zones cut from one matrix that touch edge to edge are joined
  -- the way Gen 4's are (RomExtractorGen4.linkRegions: `connections` keyed
  -- north/south/west/east, offset = the difference of their origins), so
  -- Route 1's north edge hands the player to Accumula without a warp.
  -- A RAIL MAP'S GRID. NG chunks carry no permissions and are 2,048 units
  -- square (Gen4Ground: a node translation places each in its cell), so a
  -- 2 x 3 matrix is 4,096 x 6,144 -- Skyarrow's rails run to z 4,852 inside
  -- it. The grid is sized to that, every cell blocked, and each
  -- rail line is RASTERISED in as walkable ground: a straight run between its
  -- points, or an arc about its curve record's centre (type 1), as wide as
  -- the points' widths for that line (taken as half-widths in world units --
  -- Castelia's ring is 144, the bridge 16). An approximation of BW's rail
  -- walking on the engine's grid: the corridor is right, the analogue
  -- movement along it is not modelled.
  --
  -- ENTITIES ON THE RAILS, on every map that has rail data -- the no-grid
  -- rail maps and the ordinary ones that still place some events by rail
  -- (Castelia's Z030, Icirrus, Opelucid, the League, Village Bridge,
  -- Celestial Tower): <line, along, across> to a tile of the map. A line's
  -- sixth word is its step count (Castelia's arc from point 2 to 3 is
  -- ~477 units over 30), `along` the step from its first point, and
  -- `across` whole tiles to the side -- positive to the RIGHT of the
  -- line's direction, as a door at +7 on one side and -6 on the other
  -- both stand inside the ring street's 9-tile half-width.
  local function railTile(data, def)
    local ox, oy = def.originX or 0, def.originY or 0
    local toTile = function(li, along, across)
      local line = data.lines[li]
      local a, b = line and data.points[line.a], line and data.points[line.b]
      if not (a and b) then return nil end
      local n = math.max(line.raw[6] or 1, 1)
      local t = math.min(math.max((along + 0.5) / n, 0), 1)
      local x, z, tx, tz
      local curve = data.curves[li]
      if curve and curve.kind == 1 then
        local ra = math.sqrt((a.x - curve.cx) ^ 2 + (a.z - curve.cz) ^ 2)
        local rb = math.sqrt((b.x - curve.cx) ^ 2 + (b.z - curve.cz) ^ 2)
        local ta = math.atan2(a.z - curve.cz, a.x - curve.cx)
        local tb = math.atan2(b.z - curve.cz, b.x - curve.cx)
        local d = tb - ta
        if d > math.pi then d = d - 2 * math.pi elseif d < -math.pi then d = d + 2 * math.pi end
        local th = ta + d * t
        local r = ra + (rb - ra) * t
        x, z = curve.cx + r * math.cos(th), curve.cz + r * math.sin(th)
        local sg = d >= 0 and 1 or -1
        tx, tz = -math.sin(th) * sg, math.cos(th) * sg
      else
        x, z = a.x + (b.x - a.x) * t, a.z + (b.z - a.z) * t
        local len = math.max(math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2), 1e-6)
        tx, tz = (b.x - a.x) / len, (b.z - a.z) / len
      end
      -- right of travel, x east and z south: (-tz, tx)
      x, z = x - tz * across * 16, z + tx * across * 16
      return math.floor(x / 16), math.floor(z / 16)
    end
    return function(li, along, across)
      local x, y = toTile(li, along, across)
      if x then return x - ox, y - oy end
    end
  end
  -- HYBRID MAPS: an ordinary grid map whose rails run on past its
  -- permissions -- Castelia's central plaza Z030 is one 32 x 32 chunk with
  -- the plaza's grid in the north, and its rails start at the plaza's south
  -- edge (row 18.5) and carry on to row 44 over the chunk's own model. Its
  -- grid is grown to take the rails, keeping every cell the cartridge gave,
  -- and the rail corridors are opened the same way. (Only maps cut at the
  -- matrix's corner, whose rail frame is the map's.)
  for id, def in pairs(maps) do
    local rail = rails[def.header]
    local hybrid = not def.gen5NoGrid and rail and rail.data and def.blocks
                   and (def.originX or 0) == 0 and (def.originY or 0) == 0
    -- ...AND ONLY WHERE THE RAILS LEAVE THE GRID. Z030's run to row 44 of a
    -- 32-row map; Icirrus Gym's (Z114) stay inside its 78 x 78, and opening
    -- them there cut through the walls the gym's rotating bridges span --
    -- the puzzle walked straight past. Inside the grid the cartridge's own
    -- cells stand.
    if hybrid then
      local beyond = false
      for _, pt in pairs(rail.data.points or {}) do
        if pt.x / 16 >= (def.width or 0) or pt.z / 16 >= (def.height or 0) then beyond = true end
      end
      hybrid = beyond
    end
    if not (def.gen5NoGrid or hybrid) then rail = nil end
    if def.gen5NoGrid or hybrid then
      local data = rail and rail.data
      -- THE CHUNK SIZE IS NOT THE SAME ON EVERY RAIL MAP. Castelia's ring
      -- (x 382-1,156, z 479-1,216) lies on chunk 636's street at the normal
      -- 512 units; Skyarrow's rails run to z 4,852 on a 2 x 3 matrix, which
      -- only fits chunks of 2,048 (four of a WB chunk's). No header field
      -- has been found that says which, so the rails decide: a map whose
      -- rails reach past twice the matrix's normal size takes the large
      -- chunk (gen5ChunkScale, read by Gen4Ground).
      local baseX, baseZ = def.width * 16, def.height * 16
      local reach = 0
      for _, pt in pairs(data and data.points or {}) do
        reach = math.max(reach, pt.x / baseX, pt.z / baseZ)
      end
      local k = reach > 2 and 4 or 1
      if hybrid then k = 1 else def.gen5ChunkScale = k end
      local maxX, maxZ = baseX * k, baseZ * k
      for _, pt in pairs(data and data.points or {}) do
        if pt.x + 256 > maxX then maxX = pt.x + 256 end
        if pt.z + 256 > maxZ then maxZ = pt.z + 256 end
      end
      local w, h = math.ceil(maxX / 16), math.ceil(maxZ / 16)
      local open, heights = {}, {}
      local function mark(x, z, half, y)
        local r = math.max(half, 8)
        for ty = math.floor((z - r) / 16), math.floor((z + r) / 16) do
          for tx = math.floor((x - r) / 16), math.floor((x + r) / 16) do
            if tx >= 0 and ty >= 0 and tx < w and ty < h then
              local cx, cz = tx * 16 + 8, ty * 16 + 8
              if (cx - x) ^ 2 + (cz - z) ^ 2 <= r * r then
                open[ty * w + tx] = true
                -- the rail's own height: Skyarrow's deck is 223 units up
                if y and y ~= 0 then heights[tx .. "," .. ty] = math.floor(y + 0.5) end
              end
            end
          end
        end
        -- ...and always the cell the point is in: a one-tile rail (16 wide)
        -- reaches no other centre, so a diagonal run -- Dragonspiral's
        -- spiral floors -- left cells touching only at their corners, which
        -- no walker can cross
        local tx, ty = math.floor(x / 16), math.floor(z / 16)
        if tx >= 0 and ty >= 0 and tx < w and ty < h then
          open[ty * w + tx] = true
          if y and y ~= 0 then heights[tx .. "," .. ty] = math.floor(y + 0.5) end
        end
      end
      local function widthAt(pt, line)
        for k = 1, 4 do if pt.lines[k] == line then return pt.widths[k] end end
        return 16
      end
      for li, line in pairs(data and data.lines or {}) do
        local a, b = data.points[line.a], data.points[line.b]
        if a and b then
          local half = math.max(widthAt(a, li), widthAt(b, li))
          local curve = data.curves[li]
          if curve and curve.kind == 1 then
            local ra = math.sqrt((a.x - curve.cx) ^ 2 + (a.z - curve.cz) ^ 2)
            local rb = math.sqrt((b.x - curve.cx) ^ 2 + (b.z - curve.cz) ^ 2)
            local ta = math.atan2(a.z - curve.cz, a.x - curve.cx)
            local tb = math.atan2(b.z - curve.cz, b.x - curve.cx)
            local d = tb - ta
            if d > math.pi then d = d - 2 * math.pi elseif d < -math.pi then d = d + 2 * math.pi end
            local n = math.max(8, math.ceil(math.abs(d) * math.max(ra, rb) / 4))
            for i = 0, n do
              local t = i / n
              local r, th = ra + (rb - ra) * t, ta + d * t
              mark(curve.cx + r * math.cos(th), curve.cz + r * math.sin(th), half, a.y + (b.y - a.y) * t)
            end
          else
            local len = math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
            local n = math.max(1, math.ceil(len / 4))
            for i = 0, n do
              local t = i / n
              mark(a.x + (b.x - a.x) * t, a.z + (b.z - a.z) * t, half, a.y + (b.y - a.y) * t)
            end
          end
        end
      end
      -- CORNERS: two rail cells meeting only diagonally (a ring's run where
      -- the line crosses a cell corner -- Dragonspiral's entrance segment
      -- to its first ring) get one side cell opened, so the walk the rail
      -- describes is one a grid walker can take
      for pass = 1, 2 do
        for ty = 0, h - 2 do
          for tx = 0, w - 2 do
            local a, b = open[ty * w + tx], open[(ty + 1) * w + tx + 1]
            local c, d = open[ty * w + tx + 1], open[(ty + 1) * w + tx]
            if a and b and not c and not d then open[ty * w + tx + 1] = true end
            if c and d and not a and not b then open[ty * w + tx] = true end
          end
        end
      end
      local blocks, behav = {}, {}
      local oldW, oldH, oldBlocks, oldBehav = def.width, def.height, def.blocks, def.behaviorCells
      if hybrid then w, h = math.max(w, oldW), math.max(h, oldH) end
      for i = 0, w * h - 1 do
        local tx, ty = i % w, math.floor(i / w)
        if open[i] then blocks[#blocks + 1] = "\0\0"; behav[#behav + 1] = "\0"
        elseif hybrid and tx < oldW and ty < oldH then
          local j = ty * oldW + tx
          blocks[#blocks + 1] = oldBlocks:sub(j * 2 + 1, j * 2 + 2)
          behav[#behav + 1] = oldBehav and oldBehav:sub(j + 1, j + 1) or "\0"
        else blocks[#blocks + 1] = "\255\0"; behav[#behav + 1] = "\255" end
      end
      def.width, def.height = w, h
      def.blocks, def.behaviorCells = table.concat(blocks), table.concat(behav)
      if next(heights) or not hybrid then def.gen4HeightEdits = next(heights) and heights or nil end
    end
  end
  for _, def in pairs(maps) do
    local rail = rails[def.header]
    if rail and rail.data then
      report.railPlaced = (report.railPlaced or 0) + Events.placeOnRails(def, railTile(rail.data, def))
    end
  end
  -- RAILS INSIDE AN ORDINARY GRID (Icirrus Gym, Z114: its rails stay in
  -- its 64 x 64): each chain of lines is a track. One that STARTS at a
  -- trigger is a ride the trigger's script starts (0x195 <n>, gated by the
  -- gym's switches) -- kept as `gen5RailTracks`, start and end cell; one
  -- that does not is a walkway over the gaps (the gym's bridges, 48 and 96
  -- units up), opened as ground along its lines.
  for _, def in pairs(maps) do
    local rail = rails[def.header]
    local data = rail and rail.data
    if data and not def.gen5NoGrid and def.blocks and (def.originX or 0) == 0 and (def.originY or 0) == 0
       and def.width and def.height then
      local inside = true
      for _, pt in pairs(data.points or {}) do
        if pt.x / 16 >= def.width or pt.z / 16 >= def.height then inside = false end
      end
      if inside then
        local blocksBefore = def.blocks
        local lineOf, seen, chains, order = {}, {}, {}, {}
        for li, line in pairs(data.lines or {}) do
          lineOf[line.a] = lineOf[line.a] or {}; table.insert(lineOf[line.a], li)
          lineOf[line.b] = lineOf[line.b] or {}; table.insert(lineOf[line.b], li)
          order[#order + 1] = li
        end
        table.sort(order)
        for _, li in ipairs(order) do
          if not seen[li] then
            local chain, stack, pts = {}, { li }, {}
            while #stack > 0 do
              local l = table.remove(stack)
              if not seen[l] then
                seen[l] = true; chain[#chain + 1] = l
                local line = data.lines[l]
                for _, p in ipairs({ line.a, line.b }) do
                  pts[p] = (pts[p] or 0) + 1
                  for _, o in ipairs(lineOf[p] or {}) do if not seen[o] then stack[#stack + 1] = o end end
                end
              end
            end
            local ends = {}
            for p, n in pairs(pts) do if n == 1 then ends[#ends + 1] = p end end
            table.sort(ends)
            chains[#chains + 1] = { lines = chain, a = ends[1], b = ends[2] }
          end
        end
        local function cellOf(p) local pt = data.points[p]; return math.floor(pt.x / 16), math.floor(pt.z / 16) end
        local function triggerNear(x, y)
          for _, c in ipairs(def.coordEvents or {}) do
            if math.abs(c.x - x) <= 1 and math.abs(c.y - y) <= 1 then return true end
          end
        end
        local tracks, opened, w = {}, 0, def.width
        local blocks, behav = {}, {}
        for i = 1, #def.blocks, 2 do blocks[#blocks + 1] = def.blocks:sub(i, i + 1) end
        for i = 1, #(def.behaviorCells or "") do behav[i] = def.behaviorCells:sub(i, i) end
        for _, ch in ipairs(chains) do
          if ch.a and ch.b then
            local ax, ay = cellOf(ch.a)
            local bx, by = cellOf(ch.b)
            if triggerNear(ax, ay) then
              tracks[#tracks + 1] = { x = ax, y = ay, toX = bx, toY = by }
            else
              for _, l in ipairs(ch.lines) do
                local line = data.lines[l]
                local p, q = data.points[line.a], data.points[line.b]
                local steps = math.max(1, math.ceil(math.sqrt((q.x - p.x) ^ 2 + (q.z - p.z) ^ 2) / 4))
                for k = 0, steps do
                  local t = k / steps
                  local cx, cz = math.floor((p.x + (q.x - p.x) * t) / 16), math.floor((p.z + (q.z - p.z) * t) / 16)
                  local i = cz * w + cx
                  if cx >= 0 and cz >= 0 and cx < w and cz < def.height and blocks[i + 1] ~= "\0\0" then
                    blocks[i + 1] = "\0\0"; behav[i + 1] = "\0"; opened = opened + 1
                  end
                end
              end
            end
          end
        end
        if opened > 0 then def.blocks, def.behaviorCells = table.concat(blocks), table.concat(behav) end
        if #tracks > 0 then def.gen5RailTracks = tracks end
        -- Opelucid Gym's dragons: which of these lines its switches shut
        -- (Gen5DragonGym), and the heights the statues carry them at
        local gym = require("src.world.Gen5DragonGym").import(def, data, rom, blocksBefore)
        if gym then report.dragonGym = #gym.statues end
      end
    end
  end
  -- ...AND THE GATES: Icirrus Gym's overlay (45 in Black) lets ride n start
  -- only while switch group a stands at b -- eight u16 pairs, (0,0) (0,1)
  -- (1,0) (1,1) (2,0) (2,0) (2,1) (2,1); a group's state is its switch's
  -- var, 0x4001 + a (the switch scripts flip 0x4001 / 0x4002 / 0x4003)
  do
    local key = string.char(0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 1, 0, 1, 0, 2, 0, 0, 0)
    for o = 30, 60 do
      local ok, b = pcall(function() return rom:overlay(o) end)
      local at = ok and b and b:find(key, 1, true)
      if at then
        local gates = {}
        for n = 0, 7 do
          local p = at - 1 + n * 4
          gates[n] = { group = b:byte(p + 1) + b:byte(p + 2) * 256, state = b:byte(p + 3) + b:byte(p + 4) * 256 }
        end
        for _, def in pairs(maps) do if def.header == 114 then def.gen5RailGates = gates; report.railGates = "ov" .. o end end
        break
      end
    end
  end
  -- NIMBASA GYM'S ROLLER COASTER (zone 63; overlay 39 in Black). Its
  -- platforms are islands, and the cars between them are the only way
  -- across. Three tables in the gym's overlay, found by the first's bytes:
  --   track of each dock  00 00 00 01 01 02 02 03 03  (nine docks)
  --   +0x1C  per track, 4 bytes: the dock pair the track joins with its
  --          switch at 0, then at 1 (0xFF: none) -- track 0 takes the
  --          middle island to the entrance, or to the next island up
  --   +0x4C  the nine docks, u16 x / u16 y tiles: (14,39) (22,39) (16,27)
  --          (16,15) (41,40) (49,40) (34,8) (22,8) (5,39)
  -- Stepping on a dock rides its track; 0x180 <n> (the four floor switches)
  -- turns track n's switch over.
  do
    local key = string.char(0, 0, 0, 1, 1, 2, 2, 3, 3)
    for o = 30, 60 do
      local ok, b = pcall(function() return rom:overlay(o) end)
      local at = ok and b and b:find(key, 1, true)
      if at and #b >= at + 0x4C + 36 then
        local base = at - 1
        local function u16(p) return b:byte(p + 1) + b:byte(p + 2) * 256 end
        local coaster = { docks = {}, track = {}, pairs = {} }
        for d = 0, 8 do
          coaster.track[d] = b:byte(base + d + 1)
          coaster.docks[d] = { x = u16(base + 0x4C + d * 4), y = u16(base + 0x4E + d * 4) }
        end
        for t = 0, 3 do
          local p = base + 0x1C + t * 4
          coaster.pairs[t] = { [0] = { b:byte(p + 1), b:byte(p + 2) }, [1] = { b:byte(p + 3), b:byte(p + 4) } }
        end
        local sane = coaster.docks[0].x < 64 and coaster.docks[8].y < 64
        for _, def in pairs(maps) do
          if sane and def.header == 63 then def.gen5Coaster = coaster; report.coaster = "ov" .. o end
        end
        if sane then break end
      end
    end
  end
  -- DRIFTVEIL GYM'S LIFTS (zone 97; overlay 43 in Black). Clay's mine is
  -- three levels stacked on the same tiles -- heights 50, 40 and 30 in
  -- tiles -- over his own floor at -59, which is what the permission grid
  -- itself describes. Two tables in the gym's overlay, found by the first
  -- lift's bytes (5 x 3 at height 50 << 16):
  --   six lifts, 24 bytes: u32 x, z, width, height, fx height a, b -- the
  --          lift moves between its two heights (flag 0x0A + i set: at the
  --          lower, clear: at the upper -- the panels' scripts say so)
  --   eight strips (+0x90), 20 bytes: u32 x, z, width, height, fx height --
  --          the walkways of each level
  do
    local key = string.char(5, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0x32, 0)
    for o = 30, 60 do
      local ok, b = pcall(function() return rom:overlay(o) end)
      local at = ok and b and b:find(key, 1, true)
      if at and at > 9 and #b >= at - 9 + 0x90 + 8 * 20 then
        local base = at - 9
        local function s32(p)
          local v = b:byte(p + 1) + b:byte(p + 2) * 256 + b:byte(p + 3) * 65536 + b:byte(p + 4) * 16777216
          return v >= 2147483648 and v - 4294967296 or v
        end
        local lifts, strips = {}, {}
        for i = 0, 5 do
          local p = base + i * 24
          lifts[i + 1] = { x = s32(p), z = s32(p + 4), w = s32(p + 8), h = s32(p + 12),
                           a = math.floor(s32(p + 16) / 65536), b = math.floor(s32(p + 20) / 65536), flag = 0x0A + i }
        end
        for i = 0, 7 do
          local p = base + 0x90 + i * 20
          strips[i + 1] = { x = s32(p), z = s32(p + 4), w = s32(p + 8), h = s32(p + 12), level = math.floor(s32(p + 16) / 65536) }
        end
        local sane = lifts[1].x < 32 and strips[1].w < 32 and strips[1].level > 0
        if sane then
          -- WHERE THE LIFTS STAND ON ARRIVAL: the zone has no init scripts;
          -- the overlay runs one of its scripts on entry (Black's entry 14:
          -- the arrival lift, then `24 000A, 23 000B, 24 000C, 23 000D,
          -- 23 000E, 24 000F`). Read as that run of set / clear flags on the
          -- lifts' own flags, wherever it sits in the zone's script file.
          local initial = {}
          local z97 = zones[97]
          local sarc = arc("/a/0/5/7")
          local sd = z97 and sarc and sarc:get(z97.scripts)
          if sd then
            for p = 1, #sd - 24 do
              local run, ok = {}, true
              for k = 0, 5 do
                local op = sd:byte(p + k * 4) + sd:byte(p + k * 4 + 1) * 256
                local fl = sd:byte(p + k * 4 + 2) + sd:byte(p + k * 4 + 3) * 256
                if (op ~= 0x23 and op ~= 0x24) or fl ~= 0x0A + k then ok = false break end
                run[fl] = op == 0x23
              end
              if ok then initial = run break end
            end
          end
          for _, def in pairs(maps) do
            if def.header == 97 then
              def.gen5Lifts = { lifts = lifts, strips = strips, start = 50, initial = initial }
              report.lifts = "ov" .. o
            end
          end
          break
        end
      end
    end
  end
  -- MISTRALTON GYM'S CANNONS (zone 108; overlay 41 in Black). Skyla's gym
  -- is islands, and a cannon fires the player from one to the next. Two
  -- tables in the overlay, found by the first landing record (id 9, (15, 2,
  -- 19), index 0) with the cannons 0x118 bytes before it:
  --   ten cannons, fx32 x / height / z (cannon 0 at (15.5, 0, 28.5) -- in
  --          the wall between the entrance and the next island)
  --   per cannon, four 20-byte landings by the direction it is fired --
  --          0 up, 1 down, 2 right, 3 left: <id, x, height, z, index>, id
  --          -1 for none (cannon 0: up to (15, 19), down to (15, 35))
  -- A press into the wall a cannon stands in fires it that way (the
  -- overlay's own test; OverworldController.checkGen4EntranceWarp).
  do
    local key = string.char(9, 0, 0, 0, 15, 0, 0, 0, 2, 0, 0, 0, 19, 0, 0, 0, 0, 0, 0, 0)
    for o = 30, 60 do
      local ok, b = pcall(function() return rom:overlay(o) end)
      local at = ok and b and b:find(key, 1, true)
      if at and at > 0x118 and #b >= at - 1 + 10 * 0x50 then
        local land, cbase = at - 1, at - 1 - 0x118
        local function s32(p)
          local v = b:byte(p + 1) + b:byte(p + 2) * 256 + b:byte(p + 3) * 65536 + b:byte(p + 4) * 16777216
          return v >= 2147483648 and v - 4294967296 or v
        end
        local cannons = {}
        for c = 0, 9 do
          local p = cbase + c * 12
          local entry = { x = s32(p) / 65536, height = s32(p + 4) / 65536, z = s32(p + 8) / 65536, landings = {} }
          for slot = 0, 3 do
            local q = land + c * 0x50 + slot * 0x14
            if s32(q) >= 0 then
              entry.landings[slot + 1] = { x = s32(q + 4), height = s32(q + 8), z = s32(q + 12) }
            end
          end
          cannons[c + 1] = entry
        end
        if cannons[1].x > 0 and cannons[1].x < 32 then
          for _, def in pairs(maps) do
            if def.header == 108 then def.gen5Cannons = cannons; report.cannons = "ov" .. o end
          end
          break
        end
      end
    end
  end
  local linker = { }
  require("src.import.RomExtractorGen4").linkRegions(linker, maps)
  report.seams = linker.regionLinkReport
  local railFiles = {}
  for _, r in pairs(rails) do railFiles[r.file] = r.data end
  report.rails = 0 for _ in pairs(rails) do report.rails = report.rails + 1 end
  return {
    rails = railFiles,
    maps = maps, headers = headers, layouts = layouts, matrices = gen4Matrices,
    permissions = permissions, terrain = terrain, zones = zones,
    sprites = sprites, spriteTable = spriteTable,
    models = { source = "ROM:" .. tostring(x.version) .. " (/a/2/2/9, /a/2/3/0 + /a/1/7/6, /a/1/7/7)",
               sets = { bwOutdoor = { packs = outdoorPacks }, bwIndoor = { packs = indoorPacks } } },
  }, report
end

return F
