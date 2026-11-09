-- The Minish Cap importer.
--
-- Runs in the import worker (or headless in a test).  Reads the player's own
-- cartridge and writes everything the runtime needs into `root` through
-- Store (CacheFs for a cache-relative root).  Nothing it writes is ever part
-- of the repository.
--
-- WHAT IT WRITES (all flat in root):
--   manifest.lua       areas, rooms, exits, entity lists, palette groups,
--                      songs, sprite index, text index -- the structure
--   pal.bin            the global palette bank (gGlobalGfxAndPalettes)
--   coll.bin           tileType -> collision, tileType -> actTile, special
--   ts_AA_T.bin        an area tileset as loaded into BG VRAM (48 KiB)
--   tiles_AA.bin       metatile subtiles + tile types, bottom and top
--   room_AA_RR.bin     a room's two layer maps (+ collision / special maps)
--   spr_NNN.lua/.bin   sprite animations, frames, OAM lists / 4bpp tiles
--   text.lua           every message, raw bytes (control codes kept)
--   audio.bin          the M4A image: songs, voicegroups, samples
--   scripts.bin        the script bytecode region
--   complete.txt       written last: "<cacheVersion> <sha1>"
--
-- RESUMABLE: steps.lua records finished steps; a re-run skips them.  A
-- finished cache with the same version is left alone (idempotent).

local bit = require("bit")
local band, rshift = bit.band, bit.rshift
local Layout = require("src.zelda.tmc.Layout")
local Rom = require("src.zelda.tmc.Rom")
local Store = require("src.zelda.tmc.Store")

local Extract = {}

Extract.CACHE_VERSION = 4
Extract.MARKER = "complete.txt"

local function hex2(n) return string.format("%02x", n) end

local function sha1hex(data)
  local ok, hash = pcall(function()
    return love and love.data and love.data.encode("string", "hex", love.data.hash("sha1", data))
  end)
  if ok and hash then return hash end
  return nil -- no hasher outside LOVE; detection already checked the header
end

-- ---------------------------------------------------------------------------
-- Global tables
-- ---------------------------------------------------------------------------
local function extractPalettes(rom, store, manifest)
  local groups, maxPal = {}, 0
  for g = 1, Layout.PALETTE_GROUP_COUNT - 1 do
    local p = rom:ptr(Layout.gPaletteGroups + 4 * g)
    local list = {}
    if p then
      for _ = 1, 32 do
        local pal = rom:u16(p)
        local dest = rom:u8(p + 2)
        local cnt = rom:u8(p + 3)
        local n = band(cnt, 0x0F)
        if n == 0 then n = 16 end
        list[#list + 1] = { pal, dest, n }
        if pal + n > maxPal then maxPal = pal + n end
        p = p + 4
        if band(cnt, 0x80) == 0 then break end
      end
    end
    groups[g] = list
  end
  manifest.paletteGroups = groups
  manifest.paletteCount = maxPal
  assert(store:write("pal.bin", rom:str(Layout.gGlobalGfxAndPalettes, maxPal * 32)))
end

local function extractCollision(rom, store, manifest)
  local typeColl = rom:ptr(Layout.PTR_TYPE_COLLISION)
  local actTile = rom:ptr(Layout.PTR_ACT_TILE)
  local special = rom:ptr(Layout.PTR_SPECIAL_COLLISION)
  assert(typeColl and actTile and special, "collision tables not found")
  local blob = rom:str(typeColl, Layout.TILE_TYPE_COUNT)
    .. rom:str(actTile, Layout.TILE_TYPE_COUNT)
    .. rom:str(special, Layout.SPECIAL_TILE_COUNT)
  local masksAt = #blob
  blob = blob .. rom:str(Layout.COLLISION_MASKS, 8 * 32)
  local lookupAt = #blob
  blob = blob .. rom:str(Layout.COLLISION_SHAPE_LOOKUP, Layout.COLLISION_SHAPE_TYPES * 0x60)
  manifest.collision = {
    typeCollision = 0, actTile = Layout.TILE_TYPE_COUNT,
    special = 2 * Layout.TILE_TYPE_COUNT, count = Layout.TILE_TYPE_COUNT,
    masks = masksAt, shapeLookup = lookupAt,
  }
  assert(store:write("coll.bin", blob))
end

-- gMapBottom / gMapTop live in EWRAM; MapDataDefinition.dest points into
-- them.  Area 0's tile list starts tiles_bottom, tiles_top (dest = layer +
-- 0x7004), which pins both bases without hard-coding RAM addresses.
local function layerBases(rom)
  local tp = rom:ptr(Layout.gAreaTiles)
  local defs = rom:mapDefs(tp)
  return defs[1].dest - Layout.LAYER_SUBTILES, defs[2].dest - Layout.LAYER_SUBTILES
end

local function classify(dest, bottom, top)
  if dest >= bottom and dest < bottom + Layout.LAYER_SIZE then return "bottom", dest - bottom end
  if dest >= top and dest < top + Layout.LAYER_SIZE then return "top", dest - top end
  if dest >= Layout.VRAM_BG and dest < Layout.VRAM_BG + 0x18000 then return "vram", dest - Layout.VRAM_BG end
  return "other", dest
end

local function pad(s, n)
  if #s >= n then return s:sub(1, n) end
  return s .. string.rep("\0", n - #s)
end

-- a plausible EntityData list: known kinds, ends with $FF within 64 records
local KINDS = { [3] = true, [4] = true, [6] = true, [7] = true, [8] = true, [9] = true }
function Extract.looksLikeEntityList(rom, p)
  for i = 0, 63 do
    local q = p + 16 * i
    if not rom:valid(q + 15) then return false end
    local k = rom:u8(q)
    if k == 0xFF then return i > 0 end
    if not KINDS[band(k, 0x0F)] then return false end
  end
  return false
end

-- ---------------------------------------------------------------------------
-- One area
-- ---------------------------------------------------------------------------
local function extractArea(rom, store, area, bottomBase, topBase)
  local hp = rom:ptr(Layout.gAreaRoomHeaders + 4 * area)
  if not hp then return nil end
  local info = { rooms = {}, tilesets = {}, roomCount = 0 }

  -- metadata
  local md = Layout.gAreaMetadata + 4 * area
  info.flags = rom:u8(md)
  info.location = rom:u8(md + 1)
  info.flagBank = rom:u8(md + 2)
  info.bgm = rom:u8(md + 3)

  -- room headers
  local headers, maxTs = {}, -1
  for r = 0, Layout.MAX_ROOMS - 1 do
    local p = hp + 10 * r
    if rom:u16(p) == 0xFFFF then break end
    local h = {
      x = rom:u16(p), y = rom:u16(p + 2),
      w = rom:u16(p + 4), h = rom:u16(p + 6),
      ts = rom:u16(p + 8),
    }
    headers[r] = h
    info.roomCount = r + 1
    if h.ts < 64 and h.ts > maxTs then maxTs = h.ts end
  end

  -- tilesets: BG VRAM image + palette group
  local tsTable = rom:ptr(Layout.gAreaTileSets + 4 * area)
  if tsTable then
    for t = 0, maxTs do
      local tp = rom:ptr(tsTable + 4 * t)
      if tp then
        local vram = {}
        local palGroups = {}
        for _, d in ipairs(rom:mapDefs(tp)) do
          if d.paletteGroup then
            palGroups[#palGroups + 1] = d.paletteGroup
          else
            local kind, off = classify(d.dest, bottomBase, topBase)
            if kind == "vram" then
              local data = rom:mapDefData(d)
              if data then vram[#vram + 1] = { off, data } end
            end
          end
        end
        -- assemble 48 KiB of character memory
        table.sort(vram, function(a, b) return a[1] < b[1] end)
        local parts, at = {}, 0
        for _, v in ipairs(vram) do
          local off, data = v[1], v[2]
          if off >= Layout.VRAM_BG_SIZE then break end
          if off > at then parts[#parts + 1] = string.rep("\0", off - at); at = off end
          if off < at then data = data:sub(at - off + 1); off = at end
          data = data:sub(1, Layout.VRAM_BG_SIZE - off)
          parts[#parts + 1] = data
          at = off + #data
        end
        if at < Layout.VRAM_BG_SIZE then parts[#parts + 1] = string.rep("\0", Layout.VRAM_BG_SIZE - at) end
        local name = "ts_" .. hex2(area) .. "_" .. t .. ".bin"
        assert(store:write(name, table.concat(parts)))
        info.tilesets[t] = { file = name, paletteGroups = palGroups }
      end
    end
  end

  -- metatiles: subtiles + tile types for both layers
  local tilesPtr = rom:ptr(Layout.gAreaTiles + 4 * area)
  if tilesPtr then
    local sec = { bottom = {}, top = {} }
    for _, d in ipairs(rom:mapDefs(tilesPtr)) do
      local layer, off = classify(d.dest, bottomBase, topBase)
      if sec[layer] then
        if off == Layout.LAYER_SUBTILES then sec[layer].sub = rom:mapDefData(d)
        elseif off == Layout.LAYER_TILETYPES then sec[layer].types = rom:mapDefData(d) end
      end
    end
    local blob = pad(sec.bottom.sub or "", 0x4000) .. pad(sec.top.sub or "", 0x4000)
      .. pad(sec.bottom.types or "", 0x1000) .. pad(sec.top.types or "", 0x1000)
    info.tiles = "tiles_" .. hex2(area) .. ".bin"
    assert(store:write(info.tiles, blob))
  end

  -- rooms
  local mapsTable = rom:ptr(Layout.gAreaRoomMaps + 4 * area)
  local exitTable = rom:ptr(Layout.gExitLists + 4 * area)
  local propTable = rom:ptr(Layout.gAreaTable + 4 * area)
  for r = 0, info.roomCount - 1 do
    local h = headers[r]
    local room = { x = h.x, y = h.y, w = h.w, h = h.h, ts = h.ts }
    if h.ts < 64 and mapsTable then
      local mp = rom:ptr(mapsTable + 4 * r)
      if mp then
        local parts, at, sections = {}, 0, {}
        for _, d in ipairs(rom:mapDefs(mp)) do
          local layer, off = classify(d.dest, bottomBase, topBase)
          local key
          if layer == "bottom" and off == Layout.LAYER_MAPDATA then key = "bottom"
          elseif layer == "top" and off == Layout.LAYER_MAPDATA then key = "top"
          elseif layer == "bottom" and off == Layout.LAYER_COLLISION then key = "collBottom"
          elseif layer == "top" and off == Layout.LAYER_COLLISION then key = "collTop"
          elseif layer == "other" and d.dest ~= 0 then
            key = sections.special1 and "special2" or "special1"
            sections[key .. "Dest"] = d.dest
          end
          if key then
            local data = rom:mapDefData(d) or ""
            sections[key] = { at, #data }
            parts[#parts + 1] = data
            at = at + #data
          end
        end
        room.file = "room_" .. hex2(area) .. "_" .. hex2(r) .. ".bin"
        room.sections = sections
        assert(store:write(room.file, table.concat(parts)))
      end
    end
    -- exits
    if exitTable then
      local lp = rom:ptr(exitTable + 4 * r)
      if lp then
        local exits = {}
        for i = 0, 63 do
          local t = rom:transition(lp + 20 * i)
          if t.warpType == 0xFFFF then break end
          exits[#exits + 1] = t
        end
        room.exits = exits
      end
    end
    -- entity lists: [0] [1] entities, [2] enemies, [3] tile entities
    if propTable then
      local pp = rom:ptr(propTable + 4 * r)
      if pp then
        room.entities = {}
        for k = 0, 2 do
          local lp = rom:ptr(pp + 4 * k)
          if lp then room.entities[k] = rom:entityList(lp) end
        end
        local tp = rom:ptr(pp + 12)
        if tp then
          local te = {}
          for i = 0, 63 do
            local q = tp + 8 * i
            local ty = rom:u8(q)
            if ty == 0 then break end
            te[#te + 1] = { type = ty, flag = rom:u8(q + 1), a = rom:u8(q + 2), b = rom:u8(q + 3),
                            pos = rom:u16(q + 4), c = rom:u8(q + 6), d = rom:u8(q + 7) }
          end
          room.tileEntities = te
        end
        -- the room's state-change / init code lives at [4..7]; it is code, so
        -- only its presence is recorded (the runtime ports the ones it needs)
        room.code = {}
        for k = 4, 7 do room.code[k] = rom:ptr(pp + 4 * k) or 0 end
        -- [8..] are the extra entity lists that room code and scripts load
        -- by address (LoadRoomEntityList); keep every one that parses as a
        -- clean list, keyed by its cartridge address
        -- raw property pointers [8..15]: NPCStruct lists for the delayed
        -- entity load manager, tile tables, rails (read by address later)
        room.props = {}
        for k = 8, 15 do
          local raw = rom:u32(pp + 4 * k)
          if rom:valid(raw) then room.props[k] = raw end
        end
        room.extraLists = {}
        for k = 8, 63 do
          local raw = rom:u32(pp + 4 * k)
          if raw ~= 0 and not rom:valid(raw) then break end
          if raw ~= 0 and Extract.looksLikeEntityList(rom, raw) then
            room.extraLists[#room.extraLists + 1] = raw
            info.entityLists = info.entityLists or {}
            info.entityLists[raw] = rom:entityList(raw)
          end
        end
      end
    end
    info.rooms[r] = room
  end
  return info
end

-- ---------------------------------------------------------------------------
-- Sprites
-- ---------------------------------------------------------------------------
local function extractSprite(rom, store, i, minFrames)
  local p = Layout.gSpritePtrs + 16 * i
  local animTable = rom:ptr(p)
  local frameTable = rom:ptr(p + 4)
  local gfx = rom:ptr(p + 8)
  if not (frameTable or animTable) then return nil end
  local spr = { anims = {}, frames = {}, objs = {} }
  local maxFrame = -1
  if animTable then
    -- animation tables have no length; item sprites (322/323) are indexed
    -- by item id and leave holes, so null entries are skipped and the
    -- table ends at the first word that is neither null nor a pointer
    for a = 0, 255 do
      local ap = rom:u32(animTable + 4 * a)
      if ap == 0 then goto nextAnim end
      if not rom:valid(ap) then break end
      local keys = {}
      local q = ap
      for _ = 1, 64 do
        local f, dur, fl, fl2 = rom:u8(q), rom:u8(q + 1), rom:u8(q + 2), rom:u8(q + 3)
        keys[#keys + 1] = { f, dur, fl, fl2 }
        if f ~= 0xFF and f > maxFrame then maxFrame = f end
        q = q + 4
        if band(fl2, 0x80) ~= 0 then
          keys.loopBack = rom:u8(q)
          break
        end
      end
      spr.anims[a] = keys
      ::nextAnim::
    end
  end
  if maxFrame < 0 then maxFrame = 0 end
  -- the HUD and menus draw frames no animation names (sprite 322's button
  -- labels at $92 + text, digits, quest art)
  if minFrames and maxFrame < minFrames then maxFrame = minFrames end
  -- frame obj lists: gFrameObjLists + u32[sprite] -> u32[frame] offsets
  local base = Layout.gFrameObjLists
  local tabOff = rom:u32(base + 4 * i)
  local gfxTiles = 0
  for f = 0, maxFrame do
    -- swap-gfx sprites carry a frame table (tiles to copy per frame);
    -- fixed-gfx sprites do not, their OAM lists index the fixed block
    if frameTable then
      local q = frameTable + 4 * f
      if rom:valid(q + 3) then
        local fr = { rom:u8(q), rom:u8(q + 1), rom:u16(q + 2) }
        spr.frames[f] = fr
        if fr[1] > 0 and fr[3] + fr[1] > gfxTiles then gfxTiles = fr[3] + fr[1] end
      end
    end
    if tabOff < 0x200000 then
      local lo = rom:u32(base + tabOff + 4 * f)
      if lo < 0x200000 then
        local op = base + lo
        local n = rom:u8(op)
        local list = {}
        if n > 0 and n < 64 then
          for k = 0, n - 1 do
            local r = op + 1 + 5 * k
            list[#list + 1] = { rom:s8(r), rom:s8(r + 1), rom:u8(r + 2), rom:u8(r + 3), rom:u8(r + 4) }
          end
        end
        spr.objs[f] = list
      end
    end
  end
  if gfx and gfxTiles > 0 then
    spr.gfx = "spr_" .. string.format("%03x", i) .. ".bin"
    assert(store:write(spr.gfx, rom:str(gfx, gfxTiles * 32)))
  end
  local name = "spr_" .. string.format("%03x", i) .. ".lua"
  assert(store:writeTable(name, spr))
  return name
end

-- ---------------------------------------------------------------------------
-- NPC definitions, fixed object graphics, object palettes
-- ---------------------------------------------------------------------------
local function npcDef(rom, p)
  local b0, hitbox, g = rom:u8(p), rom:u8(p + 1), rom:u16(p + 2)
  local s0, s1 = rom:u16(p + 4), rom:u16(p + 6)
  return {
    type = band(b0, 3), hitbox = hitbox,
    gfx = band(g, 0x3FF), gfxType = band(rshift(g, 10), 3),
    palette = band(s0, 0x3FF), shadow = band(rshift(s0, 12), 3),
    sprite = band(s1, 0x3FF), priority = band(rshift(s1, 10), 7), draw = band(rshift(s1, 13), 7),
  }
end

local function extractNpcs(rom, store, manifest)
  local defs = {}
  for i = 0, Layout.NPC_COUNT - 1 do
    local p = Layout.gNPCDefinitions + 8 * i
    local d = npcDef(rom, p)
    if d.type == 2 then
      local sub = rom:ptr(p + 4)
      local forms = {}
      if sub then
        for k = 0, 31 do
          local f = npcDef(rom, sub + 8 * k)
          if f.type == 0 or f.type == 2 then break end
          forms[k] = f
        end
      end
      defs[i] = { type = 2, forms = forms }
    else
      defs[i] = d
    end
  end
  manifest.npcDefs = defs

  -- fixed gfx blocks, decompressed, one blob
  local parts, at, index = {}, 0, {}
  for i = 1, Layout.FIXED_GFX_COUNT - 1 do
    local v = rom:u32(Layout.gFixedTypeGfxData + 4 * i)
    local off = band(v, 0xFFFFFC)
    local size = band(rshift(v, 24), 0x7F) * 0x200
    local src = Layout.gGlobalGfxAndPalettes + off
    local data
    if band(v, 1) ~= 0 then
      local ok, d = pcall(rom.lz77, rom, src)
      data = ok and d or nil
    elseif rom:valid(src) and size > 0 then
      data = rom:str(src, size)
    end
    if data and #data > 0 then
      index[i] = { at, #data }
      parts[#parts + 1] = data
      at = at + #data
    end
  end
  manifest.fixedGfx = index
  assert(store:write("fixed.bin", table.concat(parts)))

  -- object palettes 0x16+: offset into the palette bank | count << 24
  local pparts, pat, pidx = {}, 0, {}
  for i = 0, Layout.OBJ_PALETTE_COUNT - 1 do
    local v = rom:u32(Layout.gObjPalettes + 4 * i)
    local n = band(rshift(v, 24), 0x0F)
    if n == 0 then n = 1 end
    local data = rom:str(Layout.gGlobalGfxAndPalettes + band(v, 0xFFFFFF), n * 32)
    pidx[0x16 + i] = { pat, n }
    pparts[#pparts + 1] = data
    pat = pat + #data
  end
  manifest.objPalettes = pidx
  assert(store:write("objpal.bin", table.concat(pparts)))
end

-- ---------------------------------------------------------------------------
-- Kinstones: what each fusion / piece is, the shared fusions, world events
-- ---------------------------------------------------------------------------
local function extractKinstones(rom, store, manifest)
  local ev = {}
  for i = 0, Layout.KINSTONE_EVENT_COUNT - 1 do
    local p = Layout.gKinstoneWorldEvents + 8 * i
    ev[i] = { objPalette = rom:u8(p), gfxPiece = rom:u8(p + 1), gfxFull = rom:u8(p + 2),
              subtask = rom:u8(p + 3), worldEvent = rom:u8(p + 4), shape = rom:u8(p + 5),
              bubble = rom:u8(p + 6), marker = rom:u8(p + 7) }
  end
  local shared = {}
  for i = 0, Layout.SHARED_FUSION_COUNT - 1 do shared[#shared + 1] = rom:u8(Layout.SharedFusions + i) end
  local world = {}
  for i = 0, Layout.WORLD_EVENT_COUNT - 1 do
    local p = Layout.gWorldEvents + 20 * i
    world[i] = { type = rom:u8(p), entity = rom:u8(p + 1), area = rom:u8(p + 2), room = rom:u8(p + 3),
                 scrollX = rom:u16(p + 4), scrollY = rom:u16(p + 6), x = rom:u16(p + 8), y = rom:u16(p + 10),
                 condition = rom:u8(p + 16), bank = rom:u8(p + 17), flag = rom:u16(p + 18) }
  end
  manifest.kinstones = { events = ev, shared = shared, world = world }
end

-- ---------------------------------------------------------------------------
-- Tileset managers: region lists and the graphics blocks they swap in
-- ---------------------------------------------------------------------------
local function extractTileSwaps(rom, store, manifest)
  local out = {}
  for _, def in ipairs(Layout.TILE_SWAPS) do
    local slots = {}
    for si, addr in ipairs(def.slots) do
      local regions = {}
      local p = addr
      for _ = 1, 32 do
        local g = rom:u16(p)
        if g == 0xFF then break end
        regions[#regions + 1] = { g, rom:u16(p + 2), rom:u16(p + 4), rom:u16(p + 6), rom:u16(p + 8) }
        p = p + 10
      end
      slots[si] = regions
    end
    local parts, at, groups = {}, 0, {}
    for gi = 0, def.groups - 1 do
      local blocks = {}
      for k = 0, def.per - 1 do
        local q = def.infos + (gi * def.per + k) * 8
        local off, dest = rom:u32(q), rom:u32(q + 4)
        local bytes = rom:str(Layout.gGlobalGfxAndPalettes + off, Layout.SWAP_BLOCK)
        blocks[#blocks + 1] = { at, #bytes, dest - Layout.VRAM_BG }
        parts[#parts + 1] = bytes
        at = at + #bytes
      end
      groups[gi] = blocks
    end
    local pals
    if def.palettes then
      pals = {}
      for gi = 0, def.groups - 1 do pals[gi] = rom:u8(def.palettes + gi) end
    end
    local file = string.format("swap_%02x_%02x.bin", def.area, def.room)
    assert(store:write(file, table.concat(parts)))
    out[def.area * 256 + def.room] = { file = file, slots = slots, groups = groups, palettes = pals }
  end
  manifest.tileSwaps = out
end

-- ---------------------------------------------------------------------------
-- UI graphics, item metadata, object/enemy definitions, drop tables
-- ---------------------------------------------------------------------------
-- one gfx group (LoadGfxGroup) as a list of {dest, bytes}
local function gfxGroup(rom, group)
  local out = {}
  local p = rom:ptr(Layout.gGfxGroups + 4 * group)
  if not p then return out end
  for _ = 1, 16 do
    local a, dest, size = rom:u32(p), rom:u32(p + 4), rom:u32(p + 8)
    local ctrl = band(rshift(a, 24), 0xF)
    local src = Layout.gGlobalGfxAndPalettes + band(a, 0xFFFFFF)
    -- LoadGfxGroup (common.c): 7 always, $D ends the group, $E only for
    -- languages past English, $F for every language but Japanese, any
    -- other value only for that language (USA = 1, English)
    if ctrl == 0xD then break end
    if ctrl == 0x7 or ctrl == 0xF or ctrl == Layout.LANGUAGE then
      local bytes
      if band(size, 0x80000000) ~= 0 then
        local ok, d = pcall(rom.lz77, rom, src)
        bytes = ok and d or ""
      else
        bytes = rom:str(src, band(size, 0x7FFFFFFF))
      end
      out[#out + 1] = { dest = dest, bytes = bytes }
    end
    if band(a, 0x80000000) == 0 then break end
    p = p + 12
  end
  return out
end
Extract.gfxGroup = gfxGroup

local function defEntry(rom, p) -- ObjectDefinition / NPCDefinition
  local b0, hitbox, g = rom:u8(p), rom:u8(p + 1), rom:u16(p + 2)
  local s0, s1 = rom:u16(p + 4), rom:u16(p + 6)
  return { type = band(b0, 3), hitbox = hitbox, gfx = band(g, 0x3FF), gfxType = band(rshift(g, 10), 3),
           palette = band(s0, 0x3FF), shadow = band(rshift(s0, 12), 3),
           sprite = band(s1, 0x3FF), priority = band(rshift(s1, 10), 7), draw = band(rshift(s1, 13), 7) }
end

local function s8(v) return v >= 128 and v - 256 or v end

local function enemyEntry(rom, p)
  local hb = rom:ptr(p + 4)
  local box
  if hb and rom:valid(hb + 7) then
    box = { x = s8(rom:u8(hb)), y = s8(rom:u8(hb + 1)), w = rom:u8(hb + 6), h = rom:u8(hb + 7) }
  end
  local fl = rom:u8(p + 10)
  local sp = rom:u16(p + 12)
  if sp >= 0x8000 then sp = sp - 0x10000 end
  return { gfx = rom:u16(p), palette = rom:u16(p + 2), hitbox = box, sprite = rom:u16(p + 8),
           priority = band(fl, 7), collision = band(rshift(fl, 3), 1), draw = band(rshift(fl, 4), 3),
           shadow = band(rshift(fl, 6), 3), health = rom:u8(p + 11), speed = sp,
           damageType = rom:u8(p + 14), collisionMask = rom:u8(p + 15) }
end

local function droptables(rom, at, n)
  local out = {}
  for i = 0, n - 1 do
    local row = {}
    for k = 0, 15 do
      local v = rom:u16(at + i * 32 + k * 2)
      if v >= 0x8000 then v = v - 0x10000 end
      row[k] = v
    end
    out[i] = row
  end
  return out
end

local function extractTileActs(rom, manifest)
  local map, maxIdx = {}, -1
  for i = 0, 0x3FF do
    local p = Layout.gUnk_080046A4 + 4 * i
    local key = rom:u16(p)
    if key == 0 then break end
    local idx = rom:u16(p + 2)
    map[key] = idx
    if idx > maxIdx then maxIdx = idx end
  end
  local entries = {}
  for i = 0, maxIdx do
    local p = Layout.gUnk_080047F6 + 8 * i
    entries[i] = { mask = rom:u16(p), obj = rom:u8(p + 2), objType = rom:u8(p + 3),
                   unk = rom:u16(p + 4), tile = rom:u16(p + 6) }
  end
  local probes, boxes = {}, {}
  for i = 0, 17 do
    probes[i] = { s8(rom:u8(Layout.gUnk_08129072 + 2 * i)), s8(rom:u8(Layout.gUnk_08129072 + 2 * i + 1)) }
  end
  for i = 0, 0x3F do
    local p = Layout.gUnk_08129096 + 4 * i
    boxes[i] = { s8(rom:u8(p)), s8(rom:u8(p + 1)), rom:u8(p + 2), rom:u8(p + 3) }
  end
  manifest.tileActs = { map = map, entries = entries }
  manifest.sword = { probes = probes, boxes = boxes }
end

-- OAM-only sprite (index past the sprite table): frames 0-31 from
-- gFrameObjLists, used by objects that set frameIndex directly
local function extractOamSprite(rom, store, i)
  local base = Layout.gFrameObjLists
  local tabOff = rom:u32(base + 4 * i)
  if tabOff >= 0x200000 then return nil end
  local spr = { anims = {}, frames = {}, objs = {}, oamOnly = true }
  local any = false
  -- menus draw frames far past 31 (DrawDirect($1FB, $22)); an empty
  -- frame draws nothing and later ones can still exist
  for f = 0, 255 do
    local lo = rom:u32(base + tabOff + 4 * f)
    if lo >= 0x200000 then break end
    local op = base + lo
    local n = rom:u8(op)
    if n > 64 then break end
    local list = {}
    for k = 0, n - 1 do
      local r = op + 1 + 5 * k
      list[#list + 1] = { rom:s8(r), rom:s8(r + 1), rom:u8(r + 2), rom:u8(r + 3), rom:u8(r + 4) }
    end
    spr.objs[f] = list
    any = true
  end
  if not any then return nil end
  local name = "spr_" .. string.format("%03x", i) .. ".lua"
  assert(store:writeTable(name, spr))
  return name
end

local function extractProjectiles(rom, manifest)
  local defs = {}
  local function entry(p)
    local fl = rom:u8(p + 10)
    local hb = rom:ptr(p + 4)
    local box
    if hb and rom:valid(hb + 7) then
      box = { x = s8(rom:u8(hb)), y = s8(rom:u8(hb + 1)), w = rom:u8(hb + 6), h = rom:u8(hb + 7) }
    end
    return { gfx = rom:u16(p), palette = rom:u16(p + 2), hitbox = box, sprite = band(rom:u16(p + 8), 0xFFF),
             priority = band(fl, 7), draw = band(rshift(fl, 4), 3), speed = rom:u16(p + 12),
             damageType = rom:u8(p + 14), collisionMask = rom:u8(p + 15) }
  end
  for i = 0, Layout.PROJECTILE_COUNT - 1 do
    local p = Layout.gProjectileDefinitions + 16 * i
    if rom:u16(p) == 0xFFFF then
      local sub, forms = rom:ptr(p + 4), {}
      if sub then
        for k = 0, 7 do
          local q = sub + 16 * k
          if rom:u16(q) == 0xFFFF or not rom:ptr(q + 4) then break end
          forms[k] = entry(q)
        end
      end
      defs[i] = { multi = true, forms = forms }
    else
      defs[i] = entry(p)
    end
  end
  manifest.projectileDefs = defs
end

local function extractBgAnims(rom, store, manifest)
  local parts, at, out = {}, 0, {}
  for area = 0, 0x8F do
    local lp = rom:ptr(Layout.gUnk_080B755C + 4 * area)
    if lp then
      local list = {}
      for i = 0, 7 do
        local idx = rom:u16(lp + 2 * i)
        if idx == 0xFFFF then break end
        local fp = rom:ptr(Layout.gUnk_080B7278 + 4 * idx)
        if not fp then break end
        local frames = {}
        for k = 0, 31 do
          local q = fp + 8 * k
          local gp = rom:u32(q)
          local timer = rom:u32(q + 4)
          if gp == 0 then frames.loop = band(timer, 0xFF) break end
          local g = rom:ptr(q)
          if not g then break end
          local patches = {}
          for n = 0, 7 do
            local e = g + 8 * n
            local vram, size, fl = rom:u16(e), rom:u8(e + 2), rom:u8(e + 3)
            local src = Layout.gGlobalGfxAndPalettes + rom:u32(e + 4)
            if band(fl, 0x10) == 0 and size > 0 then
              local bytes = rom:str(src, size * 32)
              patches[#patches + 1] = { vram, at, #bytes }
              parts[#parts + 1] = bytes
              at = at + #bytes
            else
              patches.palette = true
            end
            if band(fl, 0x80) == 0 then break end
          end
          frames[#frames + 1] = { timer = math.max(1, band(timer, 0xFF)), patches = patches }
        end
        list[#list + 1] = frames
      end
      if #list > 0 then out[area] = list end
    end
  end
  assert(store:write("bganim.bin", table.concat(parts)))
  manifest.bgAnims = out
end

-- Menus and screens (Ppu.lua): every gfx group as LoadGfxGroup would load
-- it (gfxgroups.bin + {dest, offset, size} per group), and the menu code's
-- own tables (Layout.MENU_DATA ranges) into menudata.bin
local function extractMenus(rom, store, manifest)
  local parts, at, groups = {}, 0, {}
  for g = 0, Layout.GFX_GROUP_COUNT - 1 do
    local list = {}
    for _, it in ipairs(gfxGroup(rom, g)) do
      list[#list + 1] = { it.dest, at, #it.bytes }
      parts[#parts + 1] = it.bytes
      at = at + #it.bytes
    end
    groups[g] = list
  end
  assert(store:write("gfxgroups.bin", table.concat(parts)))
  manifest.gfxGroups = groups
  local data, idx, pos = {}, {}, 0
  for name, r in pairs(Layout.MENU_DATA) do
    local bytes = rom:str(r[1], r[2])
    idx[name] = { r[1], pos, #bytes }
    data[#data + 1] = bytes
    pos = pos + #bytes
  end
  assert(store:write("menudata.bin", table.concat(data)))
  manifest.menuData = idx
  for i = Layout.SPRITE_COUNT, Layout.OAM_SPRITE_LAST do
    local ok, name = pcall(extractOamSprite, rom, store, i)
    if ok and name then manifest.sprites[i] = name end
  end
  -- kinstone piece graphics (gUnk_080CA06C: offset, bit 31 = LZ77; 16
  -- tiles each, sub_080A4418)
  local kparts, kat, kidx = {}, 0, {}
  for i = 0, 63 do
    local t = rom:u32(Layout.gUnk_080CA06C + 4 * i)
    local off = band(t, 0x7FFFFFFF)
    if off < 0x800000 then
      local src = Layout.gGlobalGfxAndPalettes + off
      local bytes
      if band(t, 0x80000000) ~= 0 then
        local okz, d = pcall(rom.lz77, rom, src)
        bytes = okz and d or ""
      else
        bytes = rom:str(src, 0x200)
      end
      kidx[i] = { kat, #bytes }
      kparts[#kparts + 1] = bytes
      kat = kat + #bytes
    end
  end
  assert(store:write("kinstonegfx.bin", table.concat(kparts)))
  manifest.kinstoneGfx = kidx
  -- sprite 0 has no graphics, only OAM shapes (DrawDirect(0, 1) = one 8x8
  -- piece for digits)
  if not manifest.sprites[0] then
    local ok0, name0 = pcall(extractOamSprite, rom, store, 0)
    if ok0 and name0 then manifest.sprites[0] = name0 end
  end
  -- sprite 322 (items, button labels): its whole frame table
  local ok, name = pcall(extractSprite, rom, store, 0x142, 0xBF)
  if ok and name then manifest.sprites[0x142] = name end
end
Extract.extractMenus = extractMenus

local function extractUi(rom, store, manifest)
  extractBgAnims(rom, store, manifest)
  extractProjectiles(rom, manifest)
  for i = Layout.SPRITE_COUNT, Layout.OAM_SPRITE_LAST do
    if not manifest.sprites[i] then
      local ok, name = pcall(extractOamSprite, rom, store, i)
      if ok and name then manifest.sprites[i] = name end
    end
  end
  extractTileActs(rom, manifest)
  assert(store:write("font.bin", rom:str(Layout.FONT_GLYPHS, Layout.FONT_GLYPH_COUNT * 64)))
  -- HUD: BG0 characters (gfx group 16 -> $0600C000) and the rupee digits
  local hud = ""
  for _, it in ipairs(gfxGroup(rom, 16)) do
    if it.dest == 0x0600C000 then hud = it.bytes end
  end
  assert(store:write("hud.bin", hud))
  assert(store:write("digits.bin", rom:str(Layout.RUPEE_DIGITS, 0x500)))
  local hearts = {}
  for i = 0, 19 do hearts[i] = rom:u16(Layout.gUnk_080C8F2C + 2 * i) end
  -- the common OBJ VRAM the field loads (LoadGfxGroups: 16, 23, item gfx 25, 27)
  local objStr = string.rep("\0", 0x4000)
  for _, g in ipairs({ 16, 23, 25, 27 }) do
    for _, it in ipairs(gfxGroup(rom, g)) do
      local off = it.dest - 0x06010000
      if off >= 0 and off + #it.bytes <= #objStr then
        objStr = objStr:sub(1, off) .. it.bytes .. objStr:sub(off + #it.bytes + 1)
      end
    end
  end
  assert(store:write("objvram.bin", objStr))
  local items = {}
  for i = 0, Layout.ITEM_COUNT - 1 do
    local p = Layout.gItemMetaData + 8 * i
    items[i] = { slot = rom:u8(p), unk1 = rom:u8(p + 1), param = rom:u8(p + 2), flags = rom:u8(p + 3),
                 text = rom:u8(p + 5) * 256 + rom:u8(p + 4), gfx = rom:u8(p + 6), unk7 = rom:u8(p + 7) }
  end
  manifest.ui = { hearts = hearts, hudPalette = 12 }
  manifest.itemMeta = items

  local objs = {}
  for i = 0, Layout.OBJECT_COUNT - 1 do
    local p = Layout.gObjectDefinitions + 8 * i
    local d = defEntry(rom, p)
    if d.type == 2 then
      local sub, forms = rom:ptr(p + 4), {}
      if sub then
        for k = 0, 0xFF do
          local f = defEntry(rom, sub + 8 * k)
          if f.type == 2 or f.type == 3 then break end
          forms[k] = f
        end
      end
      objs[i] = { type = 2, forms = forms }
    else
      objs[i] = d
    end
  end
  manifest.objectDefs = objs

  local ens = {}
  for i = 0, Layout.ENEMY_COUNT - 1 do
    local p = Layout.gEnemyDefinitions + 16 * i
    if rom:u16(p) == 0xFFFF then
      local sub, forms = rom:ptr(p + 4), {}
      if sub then
        for k = 0, 15 do
          local q = sub + 16 * k
          if rom:u16(q) == 0xFFFF or not rom:ptr(q + 4) then break end
          forms[k] = enemyEntry(rom, q)
        end
      end
      ens[i] = { multi = true, forms = forms }
    else
      ens[i] = enemyEntry(rom, p)
    end
  end
  manifest.enemyDefs = ens

  local map = {}
  for i = 0, 0x6F do map[i] = rom:u8(Layout.DeathFx_EnemyDroptables + i) end
  local slotItems, areaSel = {}, {}
  for i = 0, 15 do slotItems[i] = rom:u8(Layout.gUnk_080FE1B4 + i) end
  for i = 0, 22 do areaSel[i] = rom:u8(Layout.gUnk_080FE1C6 + i) end
  -- gUnk_080FE1DD[3][$40]: the piece a red/blue/green Kinstone drop becomes
  local pieces = {}
  for c = 0, 2 do
    local row = {}
    for i = 0, 0x3F do row[i] = rom:u8(0x080FE1DD + c * 0x40 + i) end
    pieces[c] = row
  end
  assert(store:write("colmtx.bin", rom:str(Layout.gCollisionMtx, Layout.COLLISION_MTX_SIZE)))
  local ranges = {}
  for i = 0, Layout.ENEMY_COUNT - 1 do ranges[i] = { rom:u8(Layout.gUnk_080D3D94 + 2 * i), rom:u8(Layout.gUnk_080D3D94 + 2 * i + 1) } end
  manifest.enemyRanges = ranges
  manifest.drops = { kinstonePieces = pieces, enemy = droptables(rom, Layout.gEnemyDroptables, 18),
                     area = droptables(rom, Layout.gAreaDroptables, 19),
                     enemyMap = map, slotItems = slotItems, areaSelect = areaSel }
end

-- ---------------------------------------------------------------------------
-- Text
-- ---------------------------------------------------------------------------
-- control codes and how many argument bytes follow (tools/src/tmc_strings)
local ARGS = { [1] = 1, [2] = 1, [3] = 2, [4] = 1, [5] = 1, [6] = 1, [7] = 2,
               [8] = 1, [9] = 1, [0x0C] = 1, [0x0F] = 1 }

function Extract.readMessage(rom, p)
  local o = p - Layout.ROM_BASE
  local data, i = rom.data, o + 1
  local limit = math.min(#data, i + 4096)
  while i <= limit do
    local c = data:byte(i)
    if c == 0 then break end
    local n = ARGS[c]
    if n then
      local a = data:byte(i + 1) or 0
      if c == 4 and a == 0x10 then n = 2
      elseif c == 5 and a ~= 0xFF then n = 2 end
      i = i + 1 + n
    else
      i = i + 1
    end
  end
  return data:sub(o + 1, i - 1)
end

local function extractText(rom, store, manifest)
  local t = Layout.TEXT_TABLE
  local groups = math.floor(rom:u32(t) / 4)
  local text = {}
  local count = 0
  for g = 0, groups - 1 do
    local gb = t + rom:u32(t + 4 * g)
    local n = math.floor(rom:u32(gb) / 4)
    local msgs = {}
    for m = 0, math.min(n, 256) - 1 do
      local s = Extract.readMessage(rom, gb + rom:u32(gb + 4 * m))
      if s ~= "" then msgs[m] = s; count = count + 1 end
    end
    text[g] = msgs
  end
  manifest.textGroups = groups
  manifest.textCount = count
  assert(store:writeTable("text.lua", text))
end

-- ---------------------------------------------------------------------------
-- Audio: every song header, and one image spanning them and their
-- voicegroups and samples (src/core/M4ASynth plays straight off it)
-- ---------------------------------------------------------------------------
local function extractAudio(rom, store, manifest)
  local songs, lo, hi = {}, nil, 0
  local function span(p, n)
    if not lo or p < lo then lo = p end
    if p + n > hi then hi = p + n end
  end
  for i = 0, Layout.SONG_MAX - 1 do
    local p = Layout.gSongTable + 8 * i
    local h = rom:ptr(p)
    if not h then break end
    local nt = rom:u8(h)
    local def = { player = rom:u16(p + 4), tracks = {} }
    if nt > 0 and nt <= 16 then
      def.priority = rom:u8(h + 2)
      def.reverb = rom:u8(h + 3)
      def.voicegroup = rom:ptr(h + 4)
      for k = 0, nt - 1 do
        local tp = rom:ptr(h + 8 + 4 * k)
        if tp then def.tracks[#def.tracks + 1] = tp; span(tp, 1) end
      end
      span(h, 8 + 4 * nt)
      if def.voicegroup then span(def.voicegroup, 12 * 128) end
    end
    songs[i] = def
  end
  -- samples precede the songs; take the cartridge's sound bank from the
  -- first programmable-wave sample to the last track byte.  The voicegroups
  -- point into it; M4ASynth refuses (does not crash on) anything outside.
  local first = lo or 0
  for _, def in pairs(songs) do
    local vg = def.voicegroup
    if vg then
      for k = 0, 127 do
        local q = vg + 12 * k
        if not rom:valid(q + 12) then break end
        local w = rom:u32(q + 4)
        if rom:valid(w) and w < first then first = w end
      end
    end
  end
  hi = math.min(hi + 0x10000, Layout.ROM_BASE + rom.size)
  manifest.audio = { base = first, size = hi - first, songs = songs }
  assert(store:write("audio.bin", rom:str(first, hi - first)))
end

-- ---------------------------------------------------------------------------
-- Entry point
-- ---------------------------------------------------------------------------
local function readSteps(store)
  return store:readTable("steps.lua") or {}
end

function Extract.isReady(root)
  local ok, store = pcall(Store.new, root)
  if not ok then return false end
  local m = store:read(Extract.MARKER)
  if not m then return false end
  local v = tonumber(m:match("^(%d+)"))
  return v == Extract.CACHE_VERSION
end

function Extract.run(romPath, root, progress, opts)
  progress = progress or function() end
  opts = opts or {}
  -- the foundation's import passes ctx.bytes (the verified ROM, always
  -- present) and a romPath that may be nil (Android inbox, dropped file)
  local rom
  if type(romPath) == "table" then rom = romPath
  elseif type(opts.bytes) == "string" then rom = Rom.new(opts.bytes)
  else rom = assert(Rom.open(romPath)) end
  if not Layout.detect(rom.data:sub(1, 0x200)) then
    return false, "not The Minish Cap (USA): header game code is not BZME"
  end
  local store = Store.new(root)
  -- ctx.fresh: the worker cleared the cache subtree; start from scratch
  if opts.fresh then opts.force = true end
  if not opts.force and Extract.isReady(root) then
    progress(1, "Minish Cap: already imported")
    return true
  end
  if opts.bulk then
    local okc, CacheFs = pcall(require, "src.import.CacheFs")
    if okc and CacheFs then CacheFs.bulkWrites = true end
  end

  local steps = opts.force and {} or readSteps(store)
  local manifest = store:readTable("manifest_partial.lua") or {}
  manifest.version = Extract.CACHE_VERSION
  manifest.gameCode = Layout.GAME_CODE
  manifest.sha1 = manifest.sha1 or sha1hex(rom.data)
  manifest.areas = manifest.areas or {}
  manifest.sprites = manifest.sprites or {}

  local function done(step)
    steps[step] = true
    store:writeTable("manifest_partial.lua", manifest)
    store:writeTable("steps.lua", steps)
  end

  local total = Layout.AREA_COUNT + 6
  local n = 0
  local function tick(label)
    n = n + 1
    progress(math.min(0.99, n / total), label)
  end

  if not steps.palettes then extractPalettes(rom, store, manifest); done("palettes") end
  tick("Minish Cap: palettes")
  if not steps.collision then extractCollision(rom, store, manifest); done("collision") end
  tick("Minish Cap: collision")

  local bottomBase, topBase = layerBases(rom)
  for area = 0, Layout.AREA_COUNT - 1 do
    local key = "area" .. area
    if not steps[key] then
      local ok, info = pcall(extractArea, rom, store, area, bottomBase, topBase)
      if ok then
        manifest.areas[area] = info or false
      else
        manifest.areas[area] = false
        manifest.errors = manifest.errors or {}
        manifest.errors[#manifest.errors + 1] = "area " .. area .. ": " .. tostring(info)
      end
      done(key)
    end
    tick("Minish Cap: area " .. area)
  end

  if not steps.sprites then
    for i = 0, Layout.SPRITE_COUNT - 1 do
      local ok, name = pcall(extractSprite, rom, store, i)
      if ok and name then manifest.sprites[i] = name end
    end
    done("sprites")
  end
  tick("Minish Cap: sprites")
  if not steps.npcs then extractNpcs(rom, store, manifest); done("npcs") end
  if not steps.kinstones then extractKinstones(rom, store, manifest); done("kinstones") end
  if not steps.tileSwaps then extractTileSwaps(rom, store, manifest); done("tileSwaps") end
  if not steps.ui then extractUi(rom, store, manifest); done("ui") end
  if not steps.menus then extractMenus(rom, store, manifest); done("menus") end
  if not steps.text then extractText(rom, store, manifest); done("text") end
  tick("Minish Cap: text")
  if not steps.audio then extractAudio(rom, store, manifest); done("audio") end
  tick("Minish Cap: music")
  if not steps.entities then
    manifest.entityRegion = { base = Layout.ENTITY_LO, size = Layout.ENTITY_HI - Layout.ENTITY_LO }
    assert(store:write("entities.bin", rom:str(Layout.ENTITY_LO, Layout.ENTITY_HI - Layout.ENTITY_LO)))
    done("entities")
  end
  if not steps.scripts then
    manifest.scripts = { base = Layout.SCRIPT_LO, size = Layout.SCRIPT_HI - Layout.SCRIPT_LO }
    assert(store:write("scripts.bin", rom:str(Layout.SCRIPT_LO, Layout.SCRIPT_HI - Layout.SCRIPT_LO)))
    done("scripts")
  end
  tick("Minish Cap: scripts")

  assert(store:writeTable("manifest.lua", manifest))
  if opts.bulk then
    local okc, CacheFs = pcall(require, "src.import.CacheFs")
    if okc and CacheFs then CacheFs.bulkWrites = false end
  end
  -- the marker stays on the synced path, written last
  assert(store:write(Extract.MARKER, Extract.CACHE_VERSION .. " " .. (manifest.sha1 or "?") .. "\n"))
  store:remove("steps.lua")
  store:remove("manifest_partial.lua")
  progress(1, "Minish Cap: done")
  return true
end

return Extract
