-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- INTERIORS: the cartridge's pre-rendered 512x512 room maps (RomMap.roomBg2 /
-- roomBg1, loader 0x0807FF10), drawn with the tilesets and palette the room
-- header and entrance name (RomMap.roomHeader / entrances, as the SNES
-- Dungeon_LoadHeader), and blocked by the dungeon tile-attribute table
-- (RomMap.dungAttr*, the SNES attributes_for_tile). Pure logic; the game
-- makes images with View.fill.
--
-- Doors (round 4b): the way in is the cartridge's overworld door check
-- (RomMap.owDoorTab*/owEnt*, the GBA's 0x0808BB88): the 16x16 tile in front
-- of Link must show a door tile pair, then its position and area name the
-- entrance. The way out is the SNES TileBehavior_Entrance: tile attribute
-- 0x8E/0x8F under Link while he walks down; where he reappears outside is
-- the cartridge's exit table (I.exitFor, round 5). Room to room (round 5):
-- the layout/quadrant flags give the camera area, walking out of it is a
-- quadrant or room transition (I.edge / I.cross), doorways are opened from
-- the door lists, stairs from the stair objects (I.staircase). STILL OURS
-- or missing (docs/zelda/alttp.md): in-room layer stairs and BG1
-- collision, locked doors, the walkable set of attribute values (WALKABLE)
-- covers the values met so far; room objects (chests, pots) do nothing yet.

local bit = require("bit")
local band, rshift = bit.band, bit.rshift
local O = require("src.zelda.alttp.Overworld")

local I = {}
I.__index = I
local STEP_DIRS = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

-- the overworld door (top-left world pixel) of an entrance number, from the
-- cartridge's overworld entrance table; nil when no overworld door names it
function I.doorOf(data, entrance)
  local idx = data.roomIdx
  if not (idx and idx.owEntId) then return nil end
  for i = #idx.owEntId, 1, -1 do
    if idx.owEntId[i] == entrance then
      local area = idx.owEntArea[i]
      local pos = idx.owEntPos[i]
      local q, r = math.floor(pos / 4096), pos % 4096
      local sb, rr = math.floor(r / 1024), r % 1024
      local lx = (q % 2) * 64 + (sb % 2) * 32 + rr % 32
      local ly = math.floor(q / 2) * 64 + math.floor(sb / 2) * 32 + math.floor(rr / 32)
      local ox, oy = O.screenOrigin(area)
      return { world = (area >= 0x40) and "dw" or "lw", x = ox + lx * 8, y = oy + ly * 8,
               area = area, index = i - 1 }
    end
  end
end

-- the overworld door Link is walking up into: the 16x16 tile containing
-- (x, y + 7) as the cartridge's Overworld_UseEntrance computes it. Returns
-- the entrance number or nil.
-- `ahead` (0-3) looks that many 16 px rows further up (OURS: the game
-- passes 1 while Link walks up -- house doors keep him one tile short).
function I.owEntrance(data, ow, world, x, y, ahead, opened)
  for k = 0, ahead or 0 do
    -- round 18: the doorstep allowance (ours) never reaches over a wall a
    -- bomb has not opened yet (secret 0x86 still under its tile: the
    -- cartridge's Link cannot get to that cave's door tile)
    if k > 0 and I.owBombWall(data, ow, world, x + 16, y + 7 - 16 * (k - 1)) then return nil end
    local e = I.owEntranceAt(data, ow, world, x, y - 16 * k, opened)
    if e then return e end
  end
end

-- round 18: is the 16x16 tile at world (x, y) a wall hiding a bomb cave
-- (overworld secret 0x86) that still shows its own tile, not map16 0xDB4 /
-- 0xDB5 (Overworld_BombTile)? Its left neighbour counts too (0xDB5 goes
-- one tile right of the secret).
function I.owBombWall(data, ow, world, x, y)
  local idx = data.roomIdx
  if not (idx and idx.owSecrets and idx.map16) then return false end
  for _, dx in ipairs({ 0, -16 }) do
    local wx, wy = math.floor((x + dx) / 16) * 16, math.floor(y / 16) * 16
    local s = O.screenAt(world, wx, wy)
    if s then
      local area = ow:area(s)
      local pos = math.floor((wy - area.y) / 16) * 128 + math.floor((wx - area.x) / 16) * 2
      for _, sc in ipairs(idx.owSecrets[area.parent + 1] or {}) do
        if sc.pos == pos and sc.type == 0x86 then
          local w = data:mapWord(data:mapNumber("bg2", s), O.cellIndex((wx % 512) / 8, (wy % 512) / 8))
          return not (idx.map16[0xDB4] and w == idx.map16[0xDB4][1])
        end
      end
    end
  end
  return false
end

-- THE BIG DOOR RULE (round 7, the GBA's 0x0808C044 = SNES
-- Overworld_HandleEntrances): Link facing up at the 16x16 tile under (x,
-- y + 7); its top-right map8 cell (& 0x7FF) 0x149 or 0x169 -- or the next
-- tile's top-left cell 0x549 / 0x569 (h-flipped), the door block then
-- starting one tile left of Link's -- is a closed big door, which opens (0x0808BE18; 0x169 only
-- while the story byte RAM +0x165E is 2 or less, i.e. during the escape).
-- Returns the door's left tile x, y (world px) and its kind (0x149/0x169).
function I.owBigDoor(data, ow, world, x, y, escaping)
  local wx, wy = math.floor(x / 16) * 16, math.floor((y + 7) / 16) * 16
  local function cell(px, py)
    local s = O.screenAt(world, px, py)
    if not s then return 0 end
    return band(data:mapWord(data:mapNumber("bg2", s), O.cellIndex((px % 512) / 8, (py % 512) / 8)), 0x7FF)
  end
  local function ok(v) return v == 0x149 or (v == 0x169 and escaping) end
  local tr = cell(wx + 8, wy)
  if ok(tr) then return wx, wy, tr end
  local nl = cell(wx + 16, wy)
  if ok(nl - 0x400) then return wx - 16, wy, nl - 0x400 end   -- SNES: pos -= 2
  return nil
end
-- the key an opened big door is remembered by (area * 65536 + the door
-- position the entrance table uses), for the tile under (x, y + 7)
function I.owDoorKey(data, ow, world, x, y)
  local wx, wy = math.floor(x / 16) * 16, math.floor((y + 7) / 16) * 16
  local screen = O.screenAt(world, wx, wy)
  if not screen then return nil end
  local area = ow:area(screen)
  local tx, ty = (wx - area.x) / 8, (wy - area.y) / 8
  local q = (tx >= 64 and 1 or 0) + (ty >= 64 and 2 or 0)
  local cx, cy = tx % 64, ty % 64
  return area.parent * 65536 + q * 4096 + (math.floor(cy / 32) * 2 + math.floor(cx / 32)) * 1024 + (cy % 32) * 32 + cx % 32
end
I.owBigDoorAhead = function(data, ow, world, x, y, ahead, escaping)
  for k = 0, ahead or 0 do
    local bx, by, kind = I.owBigDoor(data, ow, world, x, y - 16 * k, escaping)
    if bx then return bx, by, kind end
  end
end

function I.owEntranceAt(data, ow, world, x, y, opened)
  local idx = data.roomIdx
  if not (idx and idx.owEntId) then return nil end
  -- round 17 (the GBA's 0x0808BEE0 -> 0x0808BB88, traced): the entrance
  -- tile is the 16x16 tile under (link_x + 16, link_y + 7) -- the GBA
  -- recomputes the position with x - (base - 0x10) after its big-door
  -- tests, so it is the tile RIGHT of Link's own column (the door tables'
  -- positions sit 8-16 px right of the walkable passage under them; the
  -- Eastern Palace's stairs end one tile left of its door tile). One
  -- exception kept by the GBA: area 0x18 (Kakariko) with link_x == 0x288
  -- and link_y <= 0x917 keeps Link's own column (entrance 0x43's door).
  local wy = math.floor((y + 7) / 16) * 16
  local wx = math.floor((x + 16) / 16) * 16
  do
    local s0 = O.screenAt(world, x, wy)
    local a0 = s0 and ow:area(s0)
    if a0 and a0.parent == 0x18 and x == 0x288 and y <= 0x917 then wx = math.floor(x / 16) * 16 end
  end
  local screen = O.screenAt(world, wx, wy)
  if not screen then return nil end
  local area = ow:area(screen)
  local tx, ty = (wx - area.x) / 8, (wy - area.y) / 8
  -- the door tile pair: the 16x16 tile's bottom two map8 words
  local function word(cx, cy)
    local s = O.screenAt(world, area.x + cx * 8, area.y + cy * 8)
    local lx, ly = (cx % 64), (cy % 64)
    return band(data:mapWord(data:mapNumber("bg2", s), O.cellIndex(lx, ly)), 0x1FF)
  end
  local a, b = word(tx, ty + 1), word(tx + 1, ty + 1)
  local pair = false
  for i = 1, #idx.owDoorTab0 do
    if idx.owDoorTab0[i] == a and idx.owDoorTab1[i] == b then pair = true break end
  end
  local q = (tx >= 64 and 1 or 0) + (ty >= 64 and 2 or 0)
  local cx, cy = tx % 64, ty % 64
  local pos = q * 4096 + (math.floor(cy / 32) * 2 + math.floor(cx / 32)) * 1024 + (cy % 32) * 32 + cx % 32
  local areaId = area.parent
  for i = #idx.owEntId, 1, -1 do
    if idx.owEntPos[i] == pos and idx.owEntArea[i] == areaId then
      -- round 7: a big gate (the castle's front door) has no door tile pair
      -- while it is closed; once the cartridge's big-door rule has opened it
      -- (I.owBigDoor, Game:updateGate) its position is entered as a door
      if pair or (opened and opened[areaId * 65536 + pos]) then return idx.owEntId[i] end
    end
  end
  return nil
end

-- SNES dungeon tile types Link may stand on: 0x00 floor, 0x09 shallow water,
-- 0x0D spikes, 0x1C-0x1F layer/ledge markers, 0x22 stairs, 0x3A/0x3B star
-- tiles, 0x40/0x48 grass, 0x4B warp, 0x80-0xBF door and transition codes.
local WALKABLE = { [0x00] = true, [0x09] = true, [0x0D] = true, [0x1C] = true, [0x1D] = true,
                   [0x1E] = true, [0x1F] = true, [0x22] = true, [0x3A] = true, [0x3B] = true,
                   [0x40] = true, [0x48] = true, [0x4B] = true,
                   [0x3D] = true, [0x3E] = true, [0x3F] = true }   -- round 6: south in-room stairs
for v = 0x80, 0xBF do WALKABLE[v] = true end
WALKABLE[0x60] = true   -- round 16: the rupee floor's rupees (tiledetect_misc_tiles 0x2200)
-- round 17: floor switches (0x23 / 0x24, TileBehavior_NothingOW indoors)
WALKABLE[0x23], WALKABLE[0x24] = true, true
I.WALKABLE = WALKABLE

-- 512-entry attribute table for an aux tileset (SNES attributes_for_tile)
function I.attributes(idx, aux)
  local a = {}
  for i = 1, 0x140 do a[i - 1] = idx.attrBase[i] end
  local mid = idx.attrAux[aux + 1] or idx.attrAux[1]
  for i = 1, 0x80 do a[0x13F + i] = mid[i] end
  for i = 1, 0x40 do a[0x1BF + i] = idx.attrTail[i] end
  return a
end

-- entrance: cartridge entrance number (RomMap.entrances). The way back out
-- is the overworld door of this entrance (or, for an entrance with no door
-- of its own such as Link's bed, of another entrance into the same room).
function I.new(data, entrance, memory)
  local idx = data.roomIdx
  -- round 12: `entrance` may also be a starting point record (idx.startPoints,
  -- the same format); its room's entrance stands in for the door
  local sp = type(entrance) == "table" and entrance or nil
  local ent = sp or assert(idx.entrances[entrance + 1], "no such entrance")
  local room = ent.room
  local hdr = idx.headers[room + 1]
  local self = setmetatable({ data = data, room = room, entrance = ent, entranceId = (not sp) and entrance or nil,
                              memory = memory }, I)
  local door = (not sp) and I.doorOf(data, entrance) or nil
  if not door then
    for e = 0, #idx.entrances - 1 do
      if idx.entrances[e + 1].room == room then
        door = I.doorOf(data, e)
        if door then break end
      end
    end
  end
  if door then
    -- Link steps out just below the 16x16 door tile, facing down (used only
    -- when the cartridge's exit table has no entry, see I.exitFor)
    self.outside = { world = door.world, x = door.x, y = door.y + 20 }
  end
  self:loadRoom(room, ent.main)
  -- Link's spawn from the entrance (world pixels -> room pixels)
  self.spawn = { ent.x % 512, ent.y % 512, 0 }
  self.qx, self.qy = math.floor(self.spawn[1] / 256), math.floor(self.spawn[2] / 256)
  return self
end

-- the next room of a dungeon (room-to-room transitions and stairs keep the
-- entrance's main tileset, as the SNES/GBA do; the header gives the rest)
function I:loadRoom(room, main)
  local data, idx = self.data, self.data.roomIdx
  local hdr = assert(idx.headers[room + 1], "no such room")
  self.room = room
  -- round 6: what the player changed in this room (opened doors, chests)
  self.memory = self.memory or {}
  local mem = self.memory[room] or { doors = {}, chests = {} }
  self.memory[room] = mem
  self.mem, self.opened = mem, mem.doors
  self.main, self.aux = main, hdr[3]
  self.palSet = hdr[2]
  self.palMain = idx.palSets[self.palSet * 4 + 1]
  local t = data.t
  local mt = t.mainTilesets[self.main + 1]
  local at = t.auxTilesets[self.aux + 1]
  self.sheets = { mt[1], mt[2], mt[3] }
  for k = 1, 4 do self.sheets[3 + k] = (at[k] ~= 0xFF) and at[k] or mt[3 + k] end
  self.sheets[8] = mt[8]
  self.bg2 = idx.bg2[room + 1]
  self.bg1 = idx.bg1[room + 1]
  self.bg3 = idx.bg3 and idx.bg3[room + 1]
  self.hdr = hdr
  self.layout = band(idx.layout and idx.layout[room + 1] or 0, 0x1C)
  -- Round 11: the two attribute tables as the GBA builds them
  -- (Dungeon_LoadBasicAttribute at 0x0808273C): the upper level (RAM
  -- 0x0200CBA0, SNES dung_bg2_attr_table) from the map loaded to 0x02018000
  -- (bg2), the lower level (0x0200DBA0, dung_bg1_attr_table) from the map at
  -- 0x0201A000 (our "bg3"); attribute = table[word & 0x3FF], and 0x10-0x1B
  -- (slopes) take the word's flip bits ((word & 0xC00) >> 10).
  local attr = I.attributes(idx, self.aux)
  -- round 16: the GBA draws the doors and the state objects (push blocks,
  -- rupee floors, large blocks, bomb floors, Blind's light) over the
  -- pre-rendered maps BEFORE it builds the attribute tables
  -- (RoomObjects.lua); the tables read the drawn words
  self.patch, self.patch1, self.patch3 = {}, {}, {}
  self.loading = true
  require("src.zelda.alttp.RoomObjects").load(self)
  self:predrawDoors()
  local function layerAttrs(n, patch)
    local a2, g2 = {}, {}
    for c = 0, 4095 do
      local w = patch[c] or (n and data:roomWord(n, O.cellIndex(c % 64, math.floor(c / 64)))) or 0
      local v = attr[band(w, 0x3FF)] or 0
      if v >= 0x10 and v < 0x1C then v = bit.bor(v, rshift(band(w, 0xC00), 10)) end
      a2[c] = v
      g2[c] = not WALKABLE[v]
    end
    return a2, g2
  end
  self.attrs, self.grid = layerAttrs(self.bg2, self.patch)
  self.attrsLo, self.gridLo = layerAttrs(self.bg3 or self.bg2, self.bg3 and self.patch3 or self.patch)
  self.lower = self.lower or false
  self.locks, self.chests = {}, {}
  -- bug round: map words the player changed (opened chests, lifted pots;
  -- round 11: opened doors, also on the lower layer's map); round 16: the
  -- patches start with the objects drawn at load (above)
  -- the object attributes (SNES Dungeon_LoadObjectAttribute; OURS: stairs
  -- are written on both tables, the SNES writes the table of the object's
  -- layer), then the doors (Dungeon_LoadDoorAttribute, round 11)
  for pass = 1, 2 do
    self:markStairs()
    self.attrs, self.attrsLo = self.attrsLo, self.attrs
    self.grid, self.gridLo = self.gridLo, self.grid
  end
  self:markInroomStairs()
  self:loadDoorAttributes()
  self:markChests()
  self:markPots()
  self.loading = nil
end

-- Round 6: in-room stairs between the two levels, as the SNES
-- Dungeon_LoadObjectAttribute writes them. North stairs (dung_stairs_table_1:
-- subtype-2 objects 0x31 "Stairs [N](layer)" -> 0x1E, 0x32 -> 0x1D) and south
-- stairs (dung_stairs_table_2: subtype-3 0x1B -> 0x3F, 0x1C -> 0x3E, 0x1D wet
-- -> 0x3D); the low nibble's kind: 0x?F room+16, 0x?E swaps the level,
-- 0x?D keeps it (kind_of_in_room_staircase). Cells are relative to the
-- object's map8 position: sides walls, the middle two columns of rows 1-2
-- the stair value on both tables; the top row floor on the upper table
-- (north) or the lower (south), the bottom row the other way round.
local NORTH = { [0x31] = 0x1E, [0x32] = 0x1D }
local SOUTH = { [0x1B] = 0x3F, [0x1C] = 0x3E, [0x1D] = 0x3D }
function I:markInroomStairs()
  local list = self.data.roomIdx.specials and self.data.roomIdx.specials[self.room + 1]
  self.stairKind = nil
  if not list then return end
  local function put(tab, grid, c, r, v)
    if c < 0 or r < 0 or c > 63 or r > 63 then return end
    local cell = r * 64 + c
    tab[cell] = v
    grid[cell] = not WALKABLE[v]
  end
  for _, o in ipairs(list) do
    local v = (o.s == 2 and NORTH[o.id]) or (o.s == 3 and SOUTH[o.id])
    if v then
      -- round 11: kind_of_in_room_staircase (room-global: 0 = 0x?F, 1 = 0x?E,
      -- 2 = 0x?D, the last one wins here; the SNES takes its first category)
      self.stairKind = 0x0F - band(v, 0x0F)
      local up, upG, lo, loG = self.attrs, self.grid, self.attrsLo, self.gridLo
      -- north: row 0 on the upper table, row 3 on the lower; south swapped
      local t0, g0, t3, g3 = up, upG, lo, loG
      if o.s == 3 then t0, g0, t3, g3 = lo, loG, up, upG end
      put(t0, g0, o.x, o.y, 0x02); put(t0, g0, o.x + 1, o.y, 0); put(t0, g0, o.x + 2, o.y, 0); put(t0, g0, o.x + 3, o.y, 0x02)
      put(t3, g3, o.x, o.y + 3, 0x02); put(t3, g3, o.x + 1, o.y + 3, 0); put(t3, g3, o.x + 2, o.y + 3, 0); put(t3, g3, o.x + 3, o.y + 3, 0x02)
      for r = 1, 2 do
        for _, tg in ipairs({ { up, upG }, { lo, loG } }) do
          put(tg[1], tg[2], o.x, o.y + r, 0x01); put(tg[1], tg[2], o.x + 3, o.y + r, 0x01)
          put(tg[1], tg[2], o.x + 1, o.y + r, v); put(tg[1], tg[2], o.x + 2, o.y + r, v)
        end
      end
    end
  end
end

-- Round 6: chests (subtype-3 0x19, big 0x31) and the cell lock (0x18, a
-- big-key lock) get attribute 0x58 + n in object order (SNES
-- Dungeon_LoadObjectAttribute; big chests 2x2 cells wider); a chest's
-- contents are the room's n-th entry of the cartridge chest table.
function I:markChests()
  local idx = self.data.roomIdx
  local list = idx.specials and idx.specials[self.room + 1]
  if not list then return end
  local items = {}
  for _, c in ipairs(idx.chests or {}) do
    if c.room == self.room then items[#items + 1] = c end
  end
  local n, k = 0, 0
  local order = {}
  for _, o in ipairs(list) do if o.s == 3 and (o.id == 0x19 or o.id == 0x31) then order[#order + 1] = o end end
  for _, o in ipairs(list) do if o.s == 3 and o.id == 0x18 then order[#order + 1] = o end end
  for _, o in ipairs(list) do
    if o.s == 3 and o.id == 0x17 then self.cell = { x = o.x, y = o.y } end
  end
  for _, o in ipairs(order) do
    local v = 0x58 + n
    local w = (o.id == 0x31) and 4 or 2
    local entry = { x = o.x, y = o.y, w = w, attr = v, lock = o.id == 0x18, cells = {} }
    if not entry.lock then k = k + 1; entry.item = items[k] and items[k].item end
    -- r19 (Dungeon_LoadAttribute's chest loop): a chest drawn on the lower
    -- layer (BG1, dung_line_ptrs_row0 0x4000) marks the lower table; a big
    -- chest (flag 0x8000) marks XY(0..1, 0), then XY(0..3, 1) and XY(0..3, 2)
    -- -- its third row is where Link stands under it (A9's big chest)
    local A, Gd = self.attrs, self.grid
    -- (the cell lock 0x18 stays on the upper table: the castle's cell, as before)
    if o.layer == 2 and not entry.lock then A, Gd = self.attrsLo, self.gridLo end
    entry.lower = o.layer == 2 and not entry.lock
    local shape = (w == 4) and { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 }, { 2, 1 }, { 3, 1 }, { 0, 2 }, { 1, 2 }, { 2, 2 }, { 3, 2 } }
                  or { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }
    for _, d in ipairs(shape) do
      local cell = (o.y + d[2]) * 64 + o.x + d[1]
      A[cell] = v; Gd[cell] = true
      entry.cells[#entry.cells + 1] = cell
    end
    self.chests[#self.chests + 1] = entry
    n = n + 1
    if self.mem and self.mem.chests[n] then self:openChest(entry) end
  end
end

-- BUG ROUND: POTS. The subtype-3 object 0x2F (zelda3 RoomDraw_SinglePot)
-- is a manipulable object: its 2x2 cells get attribute 0x70 + its number
-- (SNES dung_replacement_tile_state 0x1111), the attribute Link's lift
-- (Dungeon_LiftAndReplaceLiftable) looks for. Lifting puts the cartridge's
-- floor words (RoomDraw_SinglePot's replacement tiles) in its place; what
-- was under it is the room's secrets entry at its tilemap position * 2
-- (+0x2000 on the BG1 layer; RevealPotItem).
-- r22 (cartridge): every room load draws the room's pots again (a lifted
-- pot comes back); what a pot hid comes out once per palace visit
-- (pots_revealed_in_room, one bit per secrets entry, cleared only by
-- Dungeon_LoadEntrance: here self.revealed, which lives as long as this
-- Interior, made at each entrance); a key (secret 8) is not in those bits:
-- its key sprite vanishes once the room's key flag is set (Sprite_E4_SmallKey
-- reads dung_savegame_state_bits; here mem.potKey, set on pick-up). A pot
-- switch (0x88) shows again under the lifted pot each time.
function I:markPots()
  local list = self.data.roomIdx.specials and self.data.roomIdx.specials[self.room + 1]
  self.pots = {}
  if not list then return end
  local oldPots = self.mem.pots or {}
  self.mem.pots = {}
  local n = 0
  -- round 16: pots, large blocks and bomb floors share the SNES misc-object
  -- numbering (dung_misc_objs_index, attribute 0x70 + its number), in the
  -- object list's order; the push blocks follow (RoomObjects.markAttrs)
  local g, miscK = 0, 0
  for _, o in ipairs(list) do
    if o.s == 3 and (o.id == 0x2C or o.id == 0x47) then
      for _ = 1, 4 do
        miscK = miscK + 1
        if self.misc and self.misc[miscK] then self.misc[miscK].n = g end
        g = g + 1
      end
    end
    if o.s == 3 and o.id == 0x2F and n < 16 then
      local p = { x = o.x, y = o.y, attr = 0x70 + band(g, 15), index = n, layer = o.layer, cells = {},
                  pos = (o.y * 64 + o.x) * 2 + (o.layer == 2 and 0x2000 or 0) }
      for r = 0, 1 do for c = 0, 1 do
        local cell = (o.y + r) * 64 + o.x + c
        p.cells[#p.cells + 1] = cell
        self.attrs[cell] = p.attr; self.grid[cell] = true
        self.attrsLo[cell] = p.attr; self.gridLo[cell] = true
      end end
      self.pots[#self.pots + 1] = p
      n = n + 1
      g = g + 1
      -- r22: a save from before round 22 lists lifted pots: one that hid
      -- the room's key means the key was taken
      if oldPots[n] then
        for _, sc in ipairs(self.data.roomIdx.secrets and self.data.roomIdx.secrets[self.room + 1] or {}) do
          if sc.pos == p.pos and sc.item == 8 then self.mem.potKey = true end
        end
      end
    end
  end
  require("src.zelda.alttp.RoomObjects").markAttrs(self, g)
end

-- the pot at a room pixel, or nil
function I:potAt(x, y)
  local a = self:attrAt(x, y)
  if not a or a < 0x70 or a > 0x7F then return nil end
  for _, p in ipairs(self.pots or {}) do if p.attr == a and not p.lifted then return p end end
end

-- the pot's 4 map words (UL LL UR LR) as the room shows them
function I:potWords(p)
  local n = (p.layer == 2) and self.bg1 or self.bg2
  local w = {}
  for k, d in ipairs({ { 0, 0 }, { 0, 1 }, { 1, 0 }, { 1, 1 } }) do
    w[k] = self.data:roomWord(n, O.cellIndex(p.x + d[1], p.y + d[2]))
  end
  return w
end

-- 16x16 colour indices (0 = clear) of 4 map words UL LL UR LR, from the
-- room's own tiles: the lifted pot's picture (Carry.lua)
function I:wordsPixels(words)
  local out = {}
  local data = self.data
  for k, d in ipairs({ { 0, 0 }, { 0, 1 }, { 1, 0 }, { 1, 1 } }) do
    local w = words[k] or 0
    local t = band(w, 0x3FF)
    local slot = math.floor(t / 64)
    local raw = slot < 8 and data:sheet(self.sheets[slot + 1]) or ""
    local hf, vf = band(w, 0x400) ~= 0, band(w, 0x800) ~= 0
    local pal = rshift(w, 12) * 16
    for y = 0, 7 do
      local sy = vf and (7 - y) or y
      for x = 0, 7 do
        local sx = hf and (7 - x) or x
        local b = raw:byte((t % 64) * 32 + sy * 4 + math.floor(sx / 2) + 1) or 0
        local c = (sx % 2 == 0) and band(b, 15) or rshift(b, 4)
        out[(d[2] * 8 + y) * 16 + d[1] * 8 + x] = (c ~= 0) and (pal + c) or 0
      end
    end
  end
  return out
end

function I:removePot(p)
  p.lifted = true
  local it = self.data.t and self.data.t.items
  local patch = (p.layer == 2) and self.patch1 or self.patch
  if it then
    patch[p.y * 64 + p.x] = it.potHole[1]
    patch[(p.y + 1) * 64 + p.x] = it.potHole[2]
    patch[p.y * 64 + p.x + 1] = it.potHole[3]
    patch[(p.y + 1) * 64 + p.x + 1] = it.potHole[4]
  end
  for _, cell in ipairs(p.cells) do
    self.attrs[cell] = 0; self.grid[cell] = false
    self.attrsLo[cell] = 0; self.gridLo[cell] = false
  end
end

-- lift a pot: returns the secret byte under it (0 / nil = nothing)
function I:liftPot(p)
  self:removePot(p)
  self.mem.pots = self.mem.pots or {}
  self.mem.pots[p.index + 1] = true
  for k, sc in ipairs(self.data.roomIdx.secrets and self.data.roomIdx.secrets[self.room + 1] or {}) do
    if sc.pos == p.pos then
      if sc.item == 0x88 then self:potSwitch(p) end
      -- r22: RevealPotItem's bits (once per palace visit) and the key flag
      local d = sc.item or 0
      if d ~= 0 and d < 0x80 and d ~= 8 then
        self.revealed = self.revealed or {}
        local bits = self.revealed[self.room] or {}
        self.revealed[self.room] = bits
        if bits[k] then return nil end
        bits[k] = true
      end
      if d == 8 and self.mem.potKey then return nil end
      return sc.item
    end
  end
  return nil
end

-- round 17: secret 0x88 under a pot is a floor switch (SNES RevealPotItem:
-- the replacement words 0x0D0B / 0x0D1B / 0x4D0B / 0x4D1B, UL LL UR LR);
-- Dungeon_Store2x2 gives all four cells the LR word's attribute
-- (attributes_for_tile[LR & 0x3FF]: 0x23, the switch), which the room's
-- switch tags read (Palace.roomTags). Kept with the lifted pot.
I.POT_SWITCH = { 0x310B, 0x311B, 0x350B, 0x351B }   -- the GBA's words (0x080929E8)
function I:potSwitch(p)
  p.switch = true
  local patch = (p.layer == 2) and self.patch1 or self.patch
  local at = I.attributes(self.data.roomIdx, self.aux)
  local v = at[band(I.POT_SWITCH[4], 0x3FF)] or 0
  for k, d in ipairs({ { 0, 0 }, { 0, 1 }, { 1, 0 }, { 1, 1 } }) do
    local cell = (p.y + d[2]) * 64 + p.x + d[1]
    patch[cell] = I.POT_SWITCH[k]
    self.attrs[cell] = v; self.grid[cell] = not WALKABLE[v]
    self.attrsLo[cell] = v; self.gridLo[cell] = not WALKABLE[v]
  end
end

-- the chest (or lock) Link faces: (x, y) a point just in front of him
function I:chestAt(x, y)
  local a = self:attrAt(x, y)
  -- r19: the chests' 0x58 + n marks are on the upper table (markChests);
  -- Link on the lower level (A9's big chest stands in the sunken floor)
  -- reads them there too
  if not a or a < 0x58 or a > 0x67 then
    local t = self.lower and self.attrs or self.attrsLo
    a = t[math.floor(y / 8) * 64 + math.floor(x / 8)]
  end
  if not a or a < 0x58 or a > 0x67 then return nil end
  for i, c in ipairs(self.chests) do if c.attr == a then return c, i end end
end

-- open a chest / lock: its cells become floor on both levels (the chest
-- stays solid as furniture on the SNES; the cell lock opens the way)
function I:openChest(c)
  c.opened = true
  -- bug round: the opened chest's picture (SNES OpenChestForItem /
  -- OpenBigChest: the object tile table's open-chest words, column-major)
  local it = self.data.t and self.data.t.items
  -- r19: a lower-layer chest's picture is on the lower map (patch1)
  local patch = (c.lower and self.patch1) or self.patch
  if it and not c.lock then
    if c.w == 4 then
      for col = 0, 3 do for row = 0, 2 do
        patch[(c.y + row) * 64 + c.x + col] = it.bigChestOpen[col * 3 + row + 1]
      end end
    else
      local o = it.chestOpen
      patch[c.y * 64 + c.x] = o[1]
      patch[(c.y + 1) * 64 + c.x] = o[2]
      patch[c.y * 64 + c.x + 1] = o[3]
      patch[(c.y + 1) * 64 + c.x + 1] = o[4]
    end
  end
  for _, cell in ipairs(c.cells) do
    if c.lock then
      self.attrs[cell] = 0; self.grid[cell] = false
      self.attrsLo[cell] = 0; self.gridLo[cell] = false
    elseif c.lower then
      self.attrsLo[cell] = 0x01
    else
      self.attrs[cell] = 0x01
    end
  end
end

-- Round 10: entering a room through a shutter (SNES
-- Dungeon_CheckAdjacentRoomsForOpenDoors: a trapdoor 0x44 on the door Link
-- comes through starts up, dung_flag_trapdoors_down = 0; the transition's
-- end, Dungeon_InterRoomTrans_State15, puts the trapdoors down). Returns the
-- shutters opened for the entry: the closed ones whose cells lie within
-- 40 px of Link's body along the way he walks in.
function I:entryShutters(lx, ly, dir)
  local out = {}
  local s = I.STEP[dir]
  if not s then return out end
  for _, l in ipairs(self.locks) do
    if l.kind == "shutter" and not l.open then
      local near = false
      for _, cell in ipairs(l.cells) do
        local cx, cy = (cell % 64) * 8, math.floor(cell / 64) * 8
        for k = 0, 40, 4 do
          local bx, by = lx + s[1] * k, ly + s[2] * k
          if cx + 8 > bx and cx < bx + 16 and cy + 8 > by + 8 and cy < by + 24 then near = true break end
        end
        if near then break end
      end
      if near then self:openLock(l); l.entry = dir; out[#out + 1] = l end
    end
  end
  return out
end

-- Stair attributes, as the SNES writes them after drawing a room
-- (dungeon.c, the loops over dung_inter_starcases): the stair objects
-- (Extract.roomStairs) sorted into the SNES categories, numbered from 0x30
-- (down stairs restart at 0x34 + the low bits), each writing its pairs of
-- cells (WriteAttr2 = two cells side by side, from column + 1).
-- category: { object ids }, rows written as { row, value } (value -1 = the
-- stair number t)
local STAIR_CATS = {
  { ids = { [0x12D] = true }, rows = { { 2, 0 }, { 0, 0x26 }, { 1, -1 } } },
  { ids = { [0x138] = true }, up40 = true, rows = { { 0, 0x5E }, { 2, 0x5E }, { 3, 0x5E }, { 1, -1 } } },
  { ids = { [0x13A] = true }, up40 = true, rows = { { 0, 0x5F }, { 2, 0x5F }, { 3, 0x5F }, { 1, -1 } } },
  { ids = { [0x21E] = true }, rows = { { 0, 0x38 }, { 2, 0 }, { 3, 0 }, { 1, -1 } } },
  { ids = { [0x220] = true }, rows = { { 0, 0 }, { 1, 0 }, { 2, -1 }, { 3, 0x39 } } },
  { ids = { [0x12E] = true, [0x12F] = true }, down = true, rows = { { 2, -1 }, { 3, 0x26 } } },
  { ids = { [0x139] = true }, up40 = true, rows = { { 0, 0x5E }, { 1, -1 }, { 2, 0x5E }, { 3, 0x5E } } },
  { ids = { [0x13B] = true }, up40 = true, rows = { { 0, 0x5F }, { 1, -1 }, { 2, 0x5F }, { 3, 0x5F } } },
  { ids = { [0x21F] = true }, rows = { { 0, 0x38 }, { 1, -1 }, { 2, 0 }, { 3, 0 } } },
  { ids = { [0x221] = true, [0x229] = true }, rows = { { 0, 0 }, { 1, 0 }, { 2, -1 }, { 3, 0x39 } } },
}
function I:markStairs()
  local list = self.data.roomIdx.stairs and self.data.roomIdx.stairs[self.room + 1]
  if not list then return end
  local t = 0x30
  self.stairCells = {}
  for _, cat in ipairs(STAIR_CATS) do
    if cat.down then t = bit.bor(band(t, 7), 0x34) end
    for _, s in ipairs(list) do
      if cat.ids[s[1]] then
        local j = band(s[2] - (cat.up40 and 0x40 or 0), 0xFFF)
        for _, rv in ipairs(cat.rows) do
          local v = rv[2] == -1 and t or rv[2]
          for c = 1, 2 do
            local cell = band(j + rv[1] * 64 + c, 0xFFF)
            self.attrs[cell] = v
            self.grid[cell] = false
            self.stairCells[#self.stairCells + 1] = cell
          end
        end
        t = t + 1
      end
    end
  end
end

-- Round 11: DOORS, the cartridge's way (SNES RoomDraw_Door_North/South/West/
-- East + RoomDraw_FlagDoorsAndGetFinalType, then Dungeon_LoadDoorAttribute /
-- Dungeon_LoadSingleDoorAttribute; the GBA's 0x08082ADC writes the same
-- cells, its kTileAttrsByDoor is RomMap.doorAttrsByType). A door word of the
-- room's list (RomMap.roomDoors) takes a door slot (layer-toggle 0x16,
-- palace-toggle 0x14 and ExitToOw 0x12 markers on the north / south walls
-- take none); a north / west door at position 6-11 also draws its mirror on
-- the other side of the inner wall in slot | 8. High-range doors (type >=
-- 0x40) and the lower-layer kinds (0x04 / 0x0C south, waterfall tunnels)
-- are "prioritized": their attributes go on the lower level's table. A
-- locked door's slot holds 0xF0 + slot on its middle cells (rows 1-2) until
-- it opens; an open door writes its doorway attribute pairs (alpha: the
-- regular kinds, beta: the long ones).
local XY = function(x, y) return y * 64 + x end
local BETA = { [0x0C] = true, [0x10] = true, [4] = true, [2] = true, [8] = true }
-- Round 16: the two-way shutters 0x18 and the trap shutters 0x48 / 0x4A
-- are the cartridge's: drawn closed at load (the GBA's pre-rendered maps and
-- door drawers), opened by the entry (Dungeon_CheckAdjacentRoomsForOpenDoors)
-- and the room tags; 0x48 / 0x4A and 0x36 / 0x38 take their final type per
-- drawer (RoomDraw_HighRangeDoor_North / OneSidedLowerShutters_South /
-- HighRangeDoor_West / OneSidedLowerShutters_East, OneSidedShutters_North /
-- Door_Draw_Helper4 / NormalRangedDoors_West / OneSidedShutters_East).
-- The invisible door 0x1A is drawn as a regular door, open
-- (RoomDraw_FlagDoorsAndGetFinalType).
local OPEN_ALWAYS = { [0x1A] = true }
-- round 18: 0x1E is the big-key door (kDoorType_1E, Dungeon_ProcessTorchesAndDoors)
local LOCKED = { [0x1C] = "key", [0x1E] = "bigkey", [0x44] = "shutter", [0x42] = "shutter", [0x18] = "shutter",
  -- r19: the stair masks 0x20-0x26 (kDoorType_StairMaskLocked0-3, a key block
  -- over stairs) open with a small key like 0x1C (Dungeon_ProcessTorchesAndDoors:
  -- door_type >= 0x1C && < 0x2C && != 0x2A takes a key); the stairs' own
  -- attributes come back when it opens (DrawCompletelyOpenDoor)
  [0x20] = "key", [0x22] = "key", [0x24] = "key", [0x26] = "key" }
I.LOCKED = LOCKED
local FINAL = {
  [0] = { [0x36] = 0x18, [0x38] = 0x00, [0x48] = 0x40, [0x4A] = 0x44 },
  [1] = { [0x1E] = 0x00, [0x36] = 0x00, [0x38] = 0x18, [0x48] = 0x44, [0x4A] = 0x40 },
  [2] = { [0x36] = 0x18, [0x38] = 0x00, [0x48] = 0x44, [0x4A] = 0x40 },
  [3] = { [0x36] = 0x00, [0x38] = 0x18, [0x48] = 0x40, [0x4A] = 0x44 },
}
function I.finalType(dir, t)
  local f = FINAL[dir] and FINAL[dir][band(t, 0xFE)]
  return f or t
end
-- door types the generic drawers do not draw (special drawers, markers)
local NODRAW = {
  [0] = { [0x06] = true, [0x08] = true, [0x12] = true, [0x14] = true, [0x16] = true, [0x30] = true, [0x32] = true },
  [1] = { [0x04] = true, [0x06] = true, [0x08] = true, [0x0A] = true, [0x0C] = true, [0x0E] = true, [0x10] = true,
          [0x12] = true, [0x14] = true, [0x16] = true, [0x32] = true },
  [2] = { [0x06] = true, [0x08] = true, [0x12] = true, [0x14] = true, [0x16] = true, [0x30] = true, [0x32] = true },
  [3] = { [0x06] = true, [0x08] = true, [0x12] = true, [0x14] = true, [0x16] = true, [0x30] = true, [0x32] = true },
}

-- the slots of this room's door list
function I:doorSlots()
  local idx = self.data.roomIdx
  local list = idx.doors and idx.doors[self.room + 1] or {}
  local slots, cur = {}, 0
  local exits, toggleFloor, togglePalace = {}, {}, {}
  local function flag(dir, t, dsto, di)
    local s = { dir = dir, type = I.finalType(dir, t), orig = t, addr = dsto, index = di, slot = cur }
    slots[cur] = s
    cur = cur + 1
    return s
  end
  local function mirror(dir, t, dsto, di, prio)
    local bak = cur
    cur = bit.bor(cur, 8)
    local s = flag(dir, t, dsto, di)
    if prio then s.addr = bit.bor(s.addr, 0x1000) end
    s.mirror = true
    cur = bak
  end
  local P = { [0] = idx.doorPosUp, idx.doorPosDown, idx.doorPosLeft, idx.doorPosRight }
  if not idx.doorPosLeft then return slots, exits, toggleFloor, togglePalace end
  for di, w in ipairs(list) do
    local dir, pos, t = band(w, 3), band(rshift(w, 4), 15), rshift(w, 8)
    local a = P[dir] and P[dir][pos + 1]
    if a then
      local dsto = rshift(a, 1)
      if dir == 0 then
        if t == 0x16 then toggleFloor[#toggleFloor + 1] = dsto - 0x7F
        elseif t == 0x14 then togglePalace[#togglePalace + 1] = dsto - 0x7F
        elseif t == 0x12 then exits[#exits + 1] = dsto
        elseif t ~= 0x30 then
          if t >= 0x40 then
            if pos >= 6 and t ~= 0x46 then mirror(1, t, rshift(idx.doorPosDown[pos - 5], 1), di, true) end
            local s = flag(0, t, dsto, di); s.addr = bit.bor(s.addr, 0x1000)
          else
            if (t < 0x20 or t > 0x26) and pos >= 6 then
              mirror(1, t, rshift(idx.doorPosDown[pos - 5], 1), di, t == 8)
            end
            local s = flag(0, t, dsto, di)
            if t == 8 then s.addr = bit.bor(s.addr, 0x1000) end
          end
        end
      elseif dir == 1 then
        if t == 0x16 then toggleFloor[#toggleFloor + 1] = dsto + XY(1, 4)
        elseif t == 0x14 then togglePalace[#togglePalace + 1] = dsto + XY(1, 4)
        elseif t == 0x12 then exits[#exits + 1] = dsto
        elseif t >= 0x40 then local s = flag(1, t, dsto, di); s.addr = bit.bor(s.addr, 0x1000)
        elseif t == 0x0C or t == 4 then flag(1, t, bit.bor(dsto, 0x1000), di)
        else
          local s = flag(1, t, dsto, di)
          if t == 8 then s.addr = bit.bor(s.addr, 0x1000) end
        end
      elseif dir == 2 then
        if t == 0x16 then toggleFloor[#toggleFloor + 1] = dsto + XY(-2, 1)
        elseif t == 0x14 then togglePalace[#togglePalace + 1] = dsto + XY(-2, 1)
        elseif t >= 0x40 then
          if pos >= 6 then mirror(3, t, rshift(idx.doorPosRight[pos - 5], 1), di, true) end
          local s = flag(2, t, dsto, di); s.addr = bit.bor(s.addr, 0x1000)
        else
          if pos >= 6 then mirror(3, t, rshift(idx.doorPosRight[pos - 5], 1), di, t == 8) end
          local s = flag(2, t, dsto, di)
          if t == 8 then s.addr = bit.bor(s.addr, 0x1000) end
        end
      else
        if t == 0x16 then toggleFloor[#toggleFloor + 1] = dsto + XY(4, 1)
        elseif t == 0x14 then togglePalace[#togglePalace + 1] = dsto + XY(4, 1)
        else
          local s = flag(3, t, dsto, di)
          if t >= 0x40 or t == 8 then s.addr = bit.bor(s.addr, 0x1000) end
        end
      end
    end
  end
  return slots, exits, toggleFloor, togglePalace
end

-- the attribute writes of an open door slot ({ cell (bit 0x1000 = lower
-- table), value } pairs), as Dungeon_LoadSingleDoorAttribute's alpha / beta
local function pairs2(out, j, v)
  out[#out + 1] = { j, band(v, 0xFF) }
  out[#out + 1] = { j + 1, rshift(band(v, 0xFF00), 8) }
end
function I:doorWrites(s, exits)
  local t, out = band(s.type, 0xFE), {}
  local attr = (self.data.roomIdx.doorAttrs or {})[rshift(t, 1) + 1] or 0x8080
  local dir, j0 = s.dir, s.addr
  local isExit = false
  for _, e in ipairs(exits) do if e == band(j0, 0xFFF) then isExit = true end end
  local beta = BETA[t] or t >= 0x40
  if t >= 0x20 and t <= 0x26 then return out end
  if not beta then
    if dir == 0 then
      if isExit then attr = 0x8E8E end
      local j = band(j0, bit.bnot(0x7C0))
      for r = 0, 6 do pairs2(out, j + XY(1, r), attr) end
      pairs2(out, j + XY(1, 7), 0)
    elseif dir == 1 then
      if t == 0x0A or t == 0x0E or isExit then attr = 0x8E8E end
      for r = 1, 5 do pairs2(out, j0 + XY(1, r), attr) end
    elseif dir == 2 then
      local j = band(j0, bit.bnot(0x1F))
      for r = 1, 2 do
        pairs2(out, j + XY(0, r), attr + 0x101); pairs2(out, j + XY(2, r), attr + 0x101)
        pairs2(out, j + XY(4, r), band(attr + 0x101, 0xFF))
      end
    else
      for r = 1, 2 do
        pairs2(out, j0 + XY(2, r), attr + 0x101); pairs2(out, j0 + XY(4, r), attr + 0x101)
        pairs2(out, j0 + XY(0, r), band(attr + 0x101, 0xFF00))
      end
    end
  else
    if dir == 0 then
      local j = band(j0, bit.bnot(0x7C0))
      for r = 0, 9 do pairs2(out, j + XY(1, r), attr) end
    elseif dir == 1 then
      if t == 0x0C or t == 0x10 or t == 4 or isExit then attr = 0x8E8E end
      for r = 1, 8 do pairs2(out, j0 + XY(1, r), attr) end
    elseif dir == 2 then
      local j = band(j0, bit.bnot(0x1F))
      for r = 1, 2 do for c = 0, 6, 2 do pairs2(out, j + XY(c, r), attr + 0x101) end end
    else
      for r = 1, 2 do for c = 0, 6, 2 do pairs2(out, j0 + 1 + XY(c, r), attr + 0x101) end end
    end
  end
  return out
end

-- one attribute write: cell bit 0x1000 picks the lower table
function I:setAttr(c, v)
  local cell = band(c, 0xFFF)
  local tab, grid = self.attrs, self.grid
  if band(c, 0x1000) ~= 0 then tab, grid = self.attrsLo, self.gridLo end
  tab[cell] = v
  grid[cell] = not WALKABLE[v]
end
function I:getAttr(c)
  local tab = (band(c, 0x1000) ~= 0) and self.attrsLo or self.attrs
  return tab[band(c, 0xFFF)]
end

function I:loadDoorAttributes()
  local slots, exits, toggleFloor, togglePalace = self:doorSlots()
  self.doorSlotList = slots
  local byIndex = {}
  for k = 0, 15 do
    local s = slots[k]
    if s then
      local t = band(s.type, 0xFE)
      local kind = LOCKED[t]
      if not kind and not OPEN_ALWAYS[t] and ((t >= 0x20 and t <= 0x3E and t ~= 0x30) or (t > 0x40 and t ~= 0x46)) then
        kind = (t >= 0x40) and "shutter" or "other"
      end
      local openW = self:doorWrites(s, exits)
      if not kind then
        for _, wv in ipairs(openW) do self:setAttr(wv[1], wv[2]) end
      else
        local lock = byIndex[s.index]
        if not lock then
          lock = { kind = kind, dir = s.dir, index = s.index, type = t, cells = {}, openW = {}, closeW = {},
                   base = {}, slots = {} }
          byIndex[s.index] = lock
          self.locks[#self.locks + 1] = lock
          local col, row = band(s.addr, 63), band(rshift(s.addr, 6), 63)
          lock.x, lock.y = col * 8 + 16, row * 8 + 16
        end
        lock.slots[#lock.slots + 1] = s
        local m = band(0xF0 + k, 0xFF)
        local j = s.addr
        for _, c in ipairs({ j + XY(1, 1), j + XY(2, 1), j + XY(1, 2), j + XY(2, 2) }) do
          lock.closeW[#lock.closeW + 1] = { c, m }
        end
        for _, wv in ipairs(openW) do lock.openW[#lock.openW + 1] = wv end
      end
    end
  end
  for _, lock in ipairs(self.locks) do
    local seen = {}
    for _, list in ipairs({ lock.closeW, lock.openW }) do
      for _, wv in ipairs(list) do
        local c = wv[1]
        if not seen[c] then
          seen[c] = true
          lock.base[#lock.base + 1] = { c, self:getAttr(c) }
          lock.cells[#lock.cells + 1] = band(c, 0xFFF)
        end
      end
    end
    if (self.opened and self.opened[lock.index]) or self:adjacentOpened(lock) then self:openLock(lock)
    else self:closeLock(lock) end
  end
  -- Dungeon_LoadSingleDoorTileAttribute: the layer / palace toggle marks on
  -- a doorway (0x80-0x8F -> 0x90-0x9F / 0xA0-0xAF)
  for pass, list in ipairs({ toggleFloor, togglePalace }) do
    local orv = pass == 1 and 0x10 or 0x20
    for _, j in ipairs(list) do
      local lo = band(self.attrs[band(j, 0xFFF)] or 0, 0xF0) ~= 0x80
      local base = lo and 0x1000 or 0
      for _, c in ipairs({ j, j + 1, j + 64, j + 65 }) do
        local cc = bit.bor(band(c, 0xFFF), base)
        self:setAttr(cc, bit.bor(self:getAttr(cc) or 0, orv))
      end
    end
  end
end

-- Round 11: a door slot's picture (the SNES door drawers RoomDraw_Door_*,
-- the GBA's pointer tables RomMap.doorTiles*): the 12 map words for door
-- type t in the slot's direction -- north / south 4 columns of 3 rows (south
-- from row 1), west / east 3 columns of 4 (east from column 1) -- on the
-- room's map; the high-range doors (>= 0x40) put their inner part on the
-- lower layer's map (SNES dung_bg1 = the GBA's 0x0201A000, our "bg3").
-- `clear` takes the slot's words off again (the pre-rendered map shows the
-- closed door). Round 14: the door's outer row (north: the top row, south:
-- the bottom one) or column (west: the left one, east: the right one) also
-- goes to the high-priority map (our "bg1", the GBA's 0x0201C000), as the
-- GBA's door drawers write it (0x08084CB0 / 0x08084F28 / 0x08085080 /
-- 0x08085128: the word to 0x02018000 and, for that row or column, to
-- 0x0201C000 at the same cell); Link passes under it (Layers.lua).
function I:drawDoor(s, t, clear)
  local tabs = self.data.roomIdx.doorTiles
  local w = tabs and tabs[s.dir] and tabs[s.dir][rshift(t, 1) + 1]
  if not w then return end
  local j = band(s.addr, 0xFFF)
  local tt = band(s.type, 0xFE)
  local high = tt >= 0x40
  self.patch3 = self.patch3 or {}
  self.patch1 = self.patch1 or {}
  -- round 16: what the GBA's door drawers write at load (r16/py/
  -- doorsurvey.py over every room): special doors (NODRAW) and the
  -- high-range north / west / east doors draw nothing (pre-rendered; a north
  -- one's mirror on the south side does), the south high-range door writes
  -- its three rows to the lower map only, the stair-mask doors 0x24 / 0x26
  -- (Door_Up_StairMaskLocked) two rows to the lower map
  if self.loading and (NODRAW[s.dir][tt] or (high and s.dir ~= 1)) then return end
  if s.dir == 0 and (tt == 0x24 or tt == 0x26) then
    for i = 0, 3 do for r = 0, 1 do
      local cell = j + r * 64 + i
      if cell >= 0 and cell < 4096 then self.patch3[cell] = (not clear) and w[i * 3 + r + 1] or nil end
    end end
    return
  end
  local function put(layer, c, r, v, outer)
    local cell = j + r * 64 + c
    if cell < 0 or cell > 4095 then return end
    local p = (layer == 3) and self.patch3 or self.patch
    if clear then p[cell] = nil else p[cell] = v end
    if outer then
      if clear then self.patch1[cell] = nil else self.patch1[cell] = v end
    end
  end
  if s.dir == 0 then
    for i = 0, 3 do for r = 0, 2 do put((high and r > 0) and 3 or 2, i, r, w[i * 3 + r + 1], r == 0) end end
  elseif s.dir == 1 then
    for i = 0, 3 do for r = 0, 2 do put(high and 3 or 2, i, r + 1, w[i * 3 + r + 1], r == 2 and not high) end end
  elseif s.dir == 2 then
    for i = 0, 2 do for r = 0, 3 do put((high and i > 0) and 3 or 2, i, r, w[i * 4 + r + 1], i == 0) end end
  else
    for i = 0, 2 do for r = 0, 3 do put((high and i < 2) and 3 or 2, i + 1, r, w[i * 4 + r + 1], i == 2) end end
  end
end
-- Round 16: every door's picture at load, before the attribute tables (the
-- GBA's door drawers run in the room loader 0x0807FF10 through 0x0807FBC4,
-- over the pre-rendered maps): its final type, or the opened picture when
-- the room remembers it open; locks are drawn again by open/closeLock
function I:predrawDoors()
  local slots = self:doorSlots()
  for k = 0, 15 do
    local s = slots[k]
    if s then
      local t = band(s.type, 0xFE)
      if not (t >= 0x20 and t <= 0x22) then
        local drawT = (t == 0x1A) and 0 or t
        if self.opened and self.opened[s.index] and t ~= 0x1A then drawT = self:openType(t) end
        self:drawDoor(s, drawT)
      end
    end
  end
end
-- the type an opened door is drawn as (kDoorTypeRemap)
function I:openType(t)
  local rm = self.data.roomIdx.doorRemap
  return (rm and rm[rshift(band(t, 0xFE), 1) + 1]) or t
end

-- Round 11: a key door the player opened from the room next door (SNES
-- Dungeon_CheckAdjacentRoomsForOpenDoors marks it in
-- dung_door_opened_incl_adjacent): a lock on the room's outer wall is open
-- when the neighbour behind that wall remembers an opened door facing it in
-- the same column (north / south) or row (west / east). OURS: the pairing by
-- column / row (the SNES pairs the door slots through its adjacent-door
-- table).
local OPPOSITE = { [0] = 1, [1] = 0, [2] = 3, [3] = 2 }
function I:adjacentOpened(lock)
  if (lock.kind ~= "key" and lock.kind ~= "bigkey") or not self.memory then return false end
  local idx = self.data.roomIdx
  local P = { [0] = idx.doorPosUp, idx.doorPosDown, idx.doorPosLeft, idx.doorPosRight }
  for _, s in ipairs(lock.slots or {}) do
    local col, row = band(s.addr, 63), band(rshift(s.addr, 6), 63)
    local nb
    if s.dir == 0 and row < 8 then nb = self.room - 16
    elseif s.dir == 1 and row > 52 then nb = self.room + 16
    elseif s.dir == 2 and col < 8 then nb = self.room - 1
    elseif s.dir == 3 and col > 52 then nb = self.room + 1 end
    local mem = nb and self.memory[nb]
    if mem and mem.doors then
      for di, w in ipairs(idx.doors[nb + 1] or {}) do
        local d, pos = band(w, 3), band(rshift(w, 4), 15)
        local a = P[d] and P[d][pos + 1]
        if mem.doors[di] and d == OPPOSITE[s.dir] and a then
          local j = rshift(a, 1)
          if (s.dir <= 1 and j % 64 == col) or (s.dir >= 2 and math.floor(j / 64) % 64 == row) then return true end
        end
      end
    end
  end
  return false
end

-- open a locked door (key door or shutter): its doorway attributes and
-- (round 11) the opened door's picture
function I:openLock(lock)
  lock.open = true
  for _, b in ipairs(lock.base) do self:setAttr(b[1], b[2]) end
  for _, wv in ipairs(lock.openW) do self:setAttr(wv[1], wv[2]) end
  -- r19: an opened stair mask (0x20-0x26) runs DrawCompletelyOpenDoor: the
  -- wall spiral stairs get 0x5E / 0x5F, 0x30 + n, then two rows of floor 0
  -- (the cells the mask held are the stairs' third and fourth rows)
  if lock.type and lock.type >= 0x20 and lock.type <= 0x26 then
    for _, b in ipairs(lock.base) do
      if b[2] == 0x5E or b[2] == 0x5F then self:setAttr(b[1], 0) end
    end
  end
  for _, s in ipairs(lock.slots or {}) do self:drawDoor(s, self:openType(s.type)) end
end

-- close it (a trapdoor going down; a locked door at load): the slot marks
-- and the closed picture
function I:closeLock(lock)
  lock.open = false
  for _, b in ipairs(lock.base) do self:setAttr(b[1], b[2]) end
  for _, wv in ipairs(lock.closeW) do self:setAttr(wv[1], wv[2]) end
  -- r15: the closed picture is drawn, as the GBA room loader's door drawers
  -- do (0x08084CB0...): the pre-rendered map does not always hold it (room
  -- 0x11's key door showed an open doorway)
  for _, s in ipairs(lock.slots or {}) do self:drawDoor(s, s.type) end
end

function I:attrAt(x, y)
  local t = self.lower and self.attrsLo or self.attrs
  return t[math.floor(y / 8) * 64 + math.floor(x / 8)]
end

function I:palette()
  local pal = {}
  for i = 0, 255 do pal[i] = 0 end
  local src = 0x400 + self.data.roomIdx.dungPal[self.palMain + 1]
  for i = 0, 95 do pal[0x20 + i] = self.data:blobColor(src + i) end
  -- r15: BG palettes 0-1 are the HUD's (Palette_Load_HUD); some lower maps
  -- (bg3 fills, e.g. rooms 0x0B / 0x21) use palette 1
  if self.data.ui then
    local hp = require("src.zelda.alttp.Hud").palette(self.data, 0)
    for i = 1, 0x1F do if i % 16 ~= 0 then pal[i] = hp[i] end end
  end
  return pal
end

-- Round 11: a layer-toggle doorway under Link (attributes 0x90-0x9F and
-- 0xA8-0xAF, SNES TileBehavior_LayerToggleShutterDoor /
-- _LayerAndDungeonToggleShutterDoor -> room_transitioning_flags & 1): an
-- inter-room transition from here swaps his level
-- The SNES latches the flag while Link walks over the toggle cells and keeps
-- it while he stays in the doorway; here (OURS) the cells between Link and
-- the room's edge he leaves by, along his path (32 px back, 64 on), are checked.
local function isToggle(a) return a and ((a >= 0x90 and a <= 0x9F) or (a >= 0xA8 and a <= 0xAF)) end
function I:layerToggleAt(lx, ly, dir)
  local s = dir and STEP_DIRS[dir] or { 0, 0 }
  for k = (dir and -32 or 0), (dir and 64 or 0), 4 do
    for _, p in ipairs({ { 8, 16 }, { 8, 23 }, { 0, 16 }, { 15, 16 }, { 8, 8 } }) do
      local x, y = lx + p[1] + s[1] * k, ly + p[2] + s[2] * k
      if x >= 0 and y >= 0 and x < 512 and y < 512 and isToggle(self:attrAt(x, y)) then return true end
    end
  end
  return false
end

-- TileBehavior_Entrance: the attribute 0x8E/0x8F under (x, y)
function I:isExit(x, y)
  local a = self:attrAt(x, y)
  return a == 0x8E or a == 0x8F
end

-- The camera area: the room's layout (RomMap.layoutQuadFlags, the SNES
-- kLayoutQuadrantFlags[layout | quadrant_y | quadrant_x]) says per axis whether
-- Link's half of the room joins the other half (the camera scrolls across all
-- 512 px) or is a quadrant of its own (the camera stays in its 256 px).
function I:area()
  local flags = self.data.roomIdx.quadFlags
  local f = flags and flags[self.layout + self.qy * 2 + self.qx + 1] or 0
  -- the SNES sets quadrant_fullsize_x/y = 2 (the full 512 px) when the bit
  -- is clear: layout 0 (all bits set) is four separate quadrants
  local openX = band(f, self.qx == 1 and 2 or 1) == 0
  local openY = band(f, self.qy == 1 and 8 or 4) == 0
  local x0, x1 = 0, 512
  if not openX then x0 = self.qx * 256; x1 = x0 + 256 end
  local y0, y1 = 0, 512
  if not openY then y0 = self.qy * 256; y1 = y0 + 256 end
  return x0, y0, x1, y1
end

function I:camera(lx, ly, W, H)
  local x0, y0, x1, y1 = self:area()
  local cx = math.max(x0, math.min(x1 - W, lx + 8 - W / 2))
  local cy = math.max(y0, math.min(y1 - H, ly + 12 - H / 2))
  return math.floor(cx), math.floor(cy)
end

-- Off the room's edge the edge cell's state continues (a doorway in the
-- outer wall stays open so Link can walk through it to the next room).
function I:blocked(x, y)
  local tx = math.max(0, math.min(63, math.floor(x / 8)))
  local ty = math.max(0, math.min(63, math.floor(y / 8)))
  local g = self.lower and self.gridLo or self.grid
  return g[ty * 64 + tx] == true
end

-- Has Link left his camera area? Returns the direction ("up", "down",
-- "left", "right") and whether it leaves the room (an inter-room
-- transition, SNES Dungeon_StartInterRoomTrans_*) or only the quadrant (an
-- intra-room transition). Link's point is his centre (x + 8, y + 12).
function I:edge(lx, ly)
  local cx, cy = lx + 8, ly + 12
  -- inside an open (512 px) axis, Link's quadrant follows him across the
  -- middle line (the SNES updates link_quadrant_x/y as the camera crosses)
  local x0, y0, x1, y1 = self:area()
  if x1 - x0 == 512 and cx >= 0 and cx < 512 then self.qx = cx >= 256 and 1 or 0 end
  if y1 - y0 == 512 and cy >= 0 and cy < 512 then self.qy = cy >= 256 and 1 or 0 end
  x0, y0, x1, y1 = self:area()
  if cy < y0 then return "up", y0 == 0 end
  if cy >= y1 then return "down", y1 == 512 end
  if cx < x0 then return "left", x0 == 0 end
  if cx >= x1 then return "right", x1 == 512 end
end

local STEP = { up = { 0, -1, -16 }, down = { 0, 1, 16 }, left = { -1, 0, -1 }, right = { 1, 0, 1 } }
I.STEP = STEP

-- Cross into the next quadrant or room. Returns the pixel shift of Link's
-- coordinates (non-zero when the room changed: the new room's map is 512 px
-- away in the dungeon's 16x16 room grid).
function I:cross(dir, leavesRoom, lx, ly)
  local s = STEP[dir]
  if s[1] ~= 0 then self.qx = 1 - self.qx end
  if s[2] ~= 0 then self.qy = 1 - self.qy end
  if not leavesRoom then return 0, 0 end
  local to = band(self.room + s[3], 0x1FF)
  -- round 8: teleport doors (SNES kDoorType_WarpRoomDoor 0x46, attribute
  -- 0x89 in its doorway): leaving west through one goes to header byte 12,
  -- east to byte 13 (dung_hdr_travel_destinations[3]/[4], dungeon.c
  -- 0x82xxxx edge transitions), not to the room next door. The castle's
  -- 0x50/0x52 <-> 0x01 (the way down to the cell block) are such doors.
  local warp = self:warpDoor(dir, ly)
  if warp then
    local b = (dir == "left") and self.hdr[13] or self.hdr[14]
    if b then to = bit.bor(band(self.room, 0x100), b) end
  end
  self.warped = warp and to or nil
  self:loadRoom(to, self.main)
  return -s[1] * 512, -s[2] * 512
end

-- a warp door (type 0x46) on the left/right wall in Link's rows
function I:warpDoor(dir, ly)
  if dir ~= "left" and dir ~= "right" then return false end
  local idx = self.data.roomIdx
  local list = idx.doors and idx.doors[self.room + 1]
  if not (list and idx.doorPosLeft) then return false end
  for _, w in ipairs(list) do
    local d, pos, t = band(w, 3), band(rshift(w, 4), 15), rshift(w, 8)
    if t == 0x46 and ((d == 2 and dir == "left") or (d == 3 and dir == "right")) then
      local a = (d == 2 and idx.doorPosLeft or idx.doorPosRight)[pos + 1]
      if a then
        local row = math.floor(rshift(a, 1) / 64)
        local doorY = (row + 2) * 8
        if not ly or math.abs((ly % 512) + 12 - doorY) <= 24 then return true end
      end
    end
  end
  return false
end

-- SNES Dungeon_DetectStaircase: Link moving up or down onto a stair tile
-- (attribute 0x26, 0x38, 0x39, 0x5E, 0x5F) whose tile below is 0x30-0x37;
-- the room is header byte 10 + (that & 3) (dung_hdr_travel_destinations).
local STAIR = { [0x26] = true, [0x38] = true, [0x39] = true, [0x5E] = true, [0x5F] = true }
function I:staircase(lx, ly, dir)
  if dir ~= "up" and dir ~= "down" then return nil end
  local px = band(lx, 0x1F8) / 8
  -- kBuggyLookup[link_direction >> 1]: up +0, down +8 and two rows lower
  local py = band(ly + (dir == "up" and 0 or 8), 0x1F8) / 8 + (dir == "down" and 2 or 0)
  local tab = self.lower and self.attrsLo or self.attrs
  local at = tab[py * 64 + px]
  if not STAIR[at] then return nil end
  local a2 = tab[(py + 1) * 64 + px] or 0
  -- round 11: the south straight stairs (object 0x229 / 0x221: the number
  -- row ABOVE the 0x39 row) never match the SNES detection walking down;
  -- the cartridge's Link walks on through the stair passage and leaves by
  -- the room's bottom edge (Dungeon_StartInterRoomTrans_Down, room + 16).
  -- OURS: the 0x39 row starts that transition at once, to the header's
  -- destination for the stair number above it (the room below for 0x51)
  if at == 0x39 and dir == "down" and band(a2, 0xF8) ~= 0x30 then
    a2 = tab[(py - 1) * 64 + px] or 0
  end
  if band(a2, 0xF8) ~= 0x30 then return nil end
  -- round 6: the stair's level in the next room (header bytes 7-8, SNES
  -- dung_hdr_*_plane: 2 bits per stair after the hole's; >= 2 = lower)
  local n = band(a2, 3)
  local planes = (n < 3) and rshift(self.hdr[8] or 0, 2 * (n + 1)) or (self.hdr[9] or 0)
  return self.hdr[11 + n], at, band(planes, 3) >= 2
end

-- Round 9: where Link lands after spiral stairs. The SNES keeps his
-- position (the two rooms' spiral stairs line up) and walks him out of the
-- destination's stair, facing down. Here: the spiral stair (0x5E/0x5F
-- cells) of this room nearest to Link's x; Link stands on its two middle
-- columns just below its last row. Returns { x, y } or nil. OURS: the
-- landing walk (SpiralStairs_FindLandingSpot) is not stepped frame by frame.
function I:spiralLanding(lx, lower)
  local best, bd
  -- round 11: the level is the header plane's (the stairs' destination
  -- level); with the cartridge's two tables the round-10 rule (the upper
  -- table first) put Link on 0x02's upper level, which has no floor. The
  -- stair is looked for on that level's table first.
  local order = { self.attrs, self.attrsLo }
  if lower then order = { self.attrsLo, self.attrs } end
  for li, tab in ipairs(order) do
    for cell = 0, 4095 do
      local v = tab[cell]
      if (v == 0x5E or v == 0x5F) and tab[cell + 64] ~= v and tab[cell - 64] == v and tab[cell + 1] == v then
        local cx, cy = cell % 64, math.floor(cell / 64)
        local x = cx * 8
        local d = math.abs(x - lx)
        if not bd or d < bd then best, bd = { x, (cy + 1) * 8 - 6, nil }, d end
      end
    end
    if best and lower ~= nil then return best end
  end
  return best
end

-- Round 9: after straight stairs, Link stands past the destination's stairs
-- with attribute `want` (0x39 when he went up: above them; 0x38 when he
-- went down: below them), in the stair column nearest his x.
-- Returns { x, y, facing } or nil.
function I:straightLanding(lx, want)
  local best, bd
  for _, tab in ipairs({ self.attrs, self.attrsLo }) do
    for cell = 0, 4094 do
      if tab[cell] == want and tab[cell + 1] == want and tab[cell - 1] ~= want then
        local cx, cy = cell % 64, math.floor(cell / 64)
        local x = cx * 8
        local d = math.abs(x - lx)
        if not bd or d < bd then
          bd = d
          if want == 0x39 then best = { x, cy * 8 - 32, 0 } else best = { x, (cy + 3) * 8 - 8, 2 } end
        end
      end
    end
  end
  return best
end

-- Where Link appears outside when he leaves room `room` by an exit door.
-- The cartridge's exit table (RomMap.exitRooms, searched from the end as the
-- SNES Overworld_LoadExitData does) for dungeons and Link's house; any other
-- room 0x100-0x17F sends Link back where he came in (`cached`, the overworld
-- spot when he entered), 16 px higher below room 0x124
-- (LoadCachedEntranceProperties). Returns { world, x, y, camX, camY } or nil.
function I.exitFor(data, room, cached)
  if room ~= 0x104 and room >= 0x100 and room < 0x180 then
    if not cached then return nil end
    return { world = cached.world, x = cached.x, y = cached.y - (room < 0x124 and 0x10 or 0) }
  end
  local ex = data.roomIdx and data.roomIdx.exits
  if not ex then return nil end
  for k = #ex.rooms, 1, -1 do
    if ex.rooms[k] == room then
      local scr = ex.screens[k]
      return { world = scr >= 0x40 and "dw" or "lw", x = ex.x[k], y = ex.y[k], screen = scr,
               camX = ex.scrollX[k], camY = ex.scrollY[k],
               normalDoor = ex.normalDoor and ex.normalDoor[k] or 0,
               fancyDoor = ex.fancyDoor and ex.fancyDoor[k] or 0 }
    end
  end
end

-- 0-based colour indices for "bg2" | "bg1"
-- r15: tiles 0x1B0-0x1CF are the animated tiles (AnimTiles.lua, frame 0);
-- `cells` (optional) collects their cells as flat { tx, ty, word } triples
function I:decodeLayer(layer, cells)
  local n = (layer == "bg1" and self.bg1) or (layer == "bg3" and self.bg3) or self.bg2
  local tiles = {}
  local data = self.data
  local AT = require("src.zelda.alttp.AnimTiles")
  local anim = AT.dungFrames(data, self.main)[0]
  local function tile(t)
    local hit = tiles[t]
    if hit then return hit end
    if t >= AT.DUNG_BASE and t < AT.DUNG_BASE + AT.COUNT then
      hit = anim[t - AT.DUNG_BASE]
      tiles[t] = hit
      return hit
    end
    local slot = math.floor(t / 64)
    hit = {}
    if slot < 8 then
      local raw = data:sheet(self.sheets[slot + 1])
      local o = (t % 64) * 32
      for i = 0, 31 do
        local b = raw:byte(o + i + 1) or 0
        hit[i * 2 + 1] = band(b, 15)
        hit[i * 2 + 2] = rshift(b, 4)
      end
    end
    tiles[t] = hit
    return hit
  end
  local out = {}
  local patch = (layer == "bg1" and self.patch1) or (layer == "bg3" and self.patch3) or (layer ~= "bg1" and layer ~= "bg3" and self.patch) or nil
  for ty = 0, 63 do
    for tx = 0, 63 do
      local w = (patch and patch[ty * 64 + tx]) or data:roomWord(n, O.cellIndex(tx, ty))
      local tn = band(w, 0x3FF)
      local px = tile(tn)
      if cells and tn >= AT.DUNG_BASE and tn < AT.DUNG_BASE + AT.COUNT then
        cells[#cells + 1] = tx; cells[#cells + 1] = ty; cells[#cells + 1] = w
      end
      local hf, vf = band(w, 0x400) ~= 0, band(w, 0x800) ~= 0
      local pal = rshift(w, 12) * 16
      for y = 0, 7 do
        local sy = vf and (7 - y) or y
        local row = (ty * 8 + y) * 512 + tx * 8
        for x = 0, 7 do
          local c = px[sy * 8 + (hf and (7 - x) or x) + 1] or 0
          out[row + x] = (c ~= 0) and (pal + c) or 0
        end
      end
    end
  end
  return out
end

-- Round 6: SNES in-room stairs. Link walking up or down onto 0x1D-0x1F
-- (north stairs, Module07_08) or 0x3D-0x3F (south stairs, Module07_10) under
-- his feet starts the climb. Returns { south, kind } (kind 0x0F/0x0E/0x0D)
function I:inroomStair(lx, ly, dir)
  if dir ~= "up" and dir ~= "down" then return nil end
  local a = self:attrAt(lx + 8, ly + (dir == "up" and 14 or 22))
  if not a then return nil end
  if a >= 0x1D and a <= 0x1F then return { south = false, kind = a - 0x10 } end
  if a >= 0x3D and a <= 0x3F then return { south = true, kind = a - 0x30 } end
end

return I
