-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE DECORATION CATALOGUE, and what the player owns of it.
--
-- A hundred and twenty-one things, read off gDecorations by
-- RomExtractorGen3:extractDecorations.  Until that stage existed nothing in
-- the port knew a decoration by name or by price, so three separate things
-- were quietly broken and one of them was broken ON PURPOSE:
--
--   * `adddecoration` recorded a number nobody could read back;
--   * `checkdecor` always answered "you do not own one", which is what gates
--     the scripts that hand them out -- so a reward could be given twice, or
--     the branch that thanks you never ran;
--   * `bufferdecorationname` named nothing, so a line with {STR_VAR_1} in it
--     printed a hole;
--   * and both decoration COUNTERS were lowered to a nop, because running a
--     decoration id through the ITEM map sells a MASTER BALL.
--
-- HOW MANY OF ONE THING YOU MAY OWN is answered here now.  The cartridge
-- keeps the inventory as eight fixed arrays inside SaveBlock1 -- ten desks,
-- thirty ornaments, forty dolls and so on -- and extractMauvilleMan reads
-- those eight caps off SetDecorationInventoriesPointers, which hands out a
-- {pointer, size} pair per category.  The eight arrays TILE: each starts
-- where the last ended and the run is 150 slots with no gap, which is what
-- says the sizes were read and not guessed.  A dataset imported before that
-- stage existed carries no caps, and then this says yes to everything --
-- which is the answer it always used to give.

local Gen3Decorations = {}

local function record(data)
  local constants = data and data.constants
  local r = constants and constants.gen3Decorations
  if type(r) == "table" and type(r.list) == "table" then return r end
  return nil
end
Gen3Decorations.record = record

-- One decoration by its cartridge id.  The list is written id-ordered from
-- zero, so the id IS the index minus one; the loop is the fallback for a
-- dataset that ever writes them in another order.
function Gen3Decorations.byId(data, id)
  local r = record(data)
  id = math.floor(tonumber(id) or -1)
  if not r or id < 0 then return nil end
  local direct = r.list[id + 1]
  if direct and direct.id == id then return direct end
  for _, def in ipairs(r.list) do
    if def.id == id then return def end
  end
  return nil
end

function Gen3Decorations.name(data, id)
  local def = Gen3Decorations.byId(data, id)
  return def and def.name or nil
end

function Gen3Decorations.price(data, id)
  local def = Gen3Decorations.byId(data, id)
  return def and tonumber(def.price) or nil
end

-- ------- what the player owns

-- The bucket `adddecoration` has always written into, kept as a COUNT rather
-- than a flag: the cartridge lets you own several of the same thing, and a
-- boolean turned the second BALL POSTER into no poster at all.
local function bag(save, make)
  if not save then return nil end
  if make then
    save.gen3 = save.gen3 or {}
    save.gen3.decorations = save.gen3.decorations or {}
  end
  return save.gen3 and save.gen3.decorations or nil
end
Gen3Decorations.bag = bag

function Gen3Decorations.count(save, id)
  local held = bag(save)
  local value = held and held[math.floor(tonumber(id) or -1)]
  -- an older save wrote `true` for "owned"; read it as one rather than none
  if value == true then return 1 end
  return math.floor(tonumber(value) or 0)
end

function Gen3Decorations.owns(save, id)
  return Gen3Decorations.count(save, id) > 0
end

function Gen3Decorations.give(save, id, howMany)
  id = math.floor(tonumber(id) or -1)
  if id < 0 then return false end
  local held = bag(save, true)
  if not held then return false end
  held[id] = Gen3Decorations.count(save, id) + (math.floor(tonumber(howMany) or 1))
  return true
end

function Gen3Decorations.take(save, id, howMany)
  id = math.floor(tonumber(id) or -1)
  local have = Gen3Decorations.count(save, id)
  if id < 0 or have == 0 then return false end
  local held = bag(save, true)
  local left = have - math.floor(tonumber(howMany) or 1)
  held[id] = left > 0 and left or nil
  return true
end

-- ------- how much room each category has

-- The eight caps, by category, or nil for a dataset that has none.
function Gen3Decorations.capacities(data)
  local r = record(data)
  local caps = r and r.capacity
  if type(caps) ~= "table" or #caps == 0 then return nil end
  return caps
end

function Gen3Decorations.capacityFor(data, category)
  local caps = Gen3Decorations.capacities(data)
  category = math.floor(tonumber(category) or -1)
  if not caps or category < 0 then return nil end
  for _, row in ipairs(caps) do
    if row.category == category then return tonumber(row.size) end
  end
  return nil
end

function Gen3Decorations.categoryOf(data, id)
  local def = Gen3Decorations.byId(data, id)
  return def and tonumber(def.category) or nil
end

-- How many slots of one category the player has filled.  The cartridge stores
-- one id per slot, so owning three of a thing costs three slots, which is why
-- this sums the counts rather than counting the kinds.
function Gen3Decorations.usedIn(data, save, category)
  local r = record(data)
  category = math.floor(tonumber(category) or -1)
  local used = 0
  if not r or category < 0 then return used end
  for _, def in ipairs(r.list) do
    if tonumber(def.category) == category then
      used = used + Gen3Decorations.count(save, def.id)
    end
  end
  return used
end

-- The first free slot in a category, zero-based, or nil when it is full --
-- what the cartridge's GetFirstEmptyDecorSlot answers and what the TRADER
-- asks before he will hand anything over.
function Gen3Decorations.firstEmptySlot(data, save, category)
  local cap = Gen3Decorations.capacityFor(data, category)
  if not cap then return 0 end
  local used = Gen3Decorations.usedIn(data, save, category)
  if used >= cap then return nil end
  return used
end

-- Is there room for one more?  Yes for a dataset with no caps, which is the
-- answer this gave before they were read.
function Gen3Decorations.roomFor(data, save, id)
  local category = Gen3Decorations.categoryOf(data, id)
  if not category then return true end
  return Gen3Decorations.firstEmptySlot(data, save, category) ~= nil
end

-- Everything the player owns, in catalogue order, as { def, count } -- what a
-- DECORATION menu lists.
function Gen3Decorations.held(data, save)
  local r = record(data)
  local out = {}
  if not r then return out end
  for _, def in ipairs(r.list) do
    local n = Gen3Decorations.count(save, def.id)
    if n > 0 then out[#out + 1] = { def = def, count = n } end
  end
  return out
end

-- ---------------------------------------------------------------------------
-- PUTTING ONE OUT, which is the half of this that did not exist.
--
-- Reported from play: "the pc in the secret base room doesnt work".  Its
-- first row is DECORATION, and a DECORATION menu with nothing behind it is
-- most of why the PC felt dead.  Three things were missing and all three are
-- now read off the cartridge rather than invented:
--
--   * HOW BIG a decoration is.  ShowDecorationOnMap (08127D38) switches on
--     the shape byte through a ten-arm jump table and each arm sets its own
--     width and height -- 1x1 through 3x3, plus a 4x2 and a 2x4.
--   * WHAT IT DRAWS WITH.  For eighty-one of the hundred and twenty-one the
--     `tiles` pointer is width*height METATILE ids, written into the map grid
--     512 higher than they are stored (the boundary between the primary and
--     the secondary tileset).  For the forty-five DOLLs and CUSHIONs -- the
--     ones whose permission byte is 4 -- the same pointer is a single OBJECT
--     EVENT graphics id instead, because the cartridge draws those as
--     sprites.  Reading the second kind as the first paints a doll as
--     whatever metatile shares its number.
--   * WHERE IT SITS.  The cartridge stores the position as one byte,
--     (x << 4) | y, and the cell it names is the decoration's BOTTOM-LEFT --
--     the writer lays row r at y - height + 1 + r.  A decoration anchored at
--     its top-left is a decoration standing one to three tiles too low.
--
-- HOW MANY FIT: sixteen in a secret base and twelve in the player's own room,
-- which are the two array lengths the decoration screen is handed
-- (SaveBlock1 + 1AAE and + 271C).  Those are the caps here.
-- ---------------------------------------------------------------------------

Gen3Decorations.PLACES = { base = 16, room = 12 }

function Gen3Decorations.shapeOf(data, id)
  local def = Gen3Decorations.byId(data, id)
  if not def then return nil end
  if def.width and def.height then return def.width, def.height end
  local r = record(data)
  local shape = r and type(r.shapes) == "table"
                and r.shapes[(tonumber(def.shape) or -1) + 1]
  if shape then return shape.width, shape.height end
  return nil
end

-- Is this one drawn as a sprite rather than written into the map?  The
-- permission byte says so and the extractor marks it; the fallback compares
-- against the permission the extractor recorded rather than the literal 4.
function Gen3Decorations.isSprite(data, id)
  local def = Gen3Decorations.byId(data, id)
  if not def then return false end
  if def.sprite ~= nil then return def.sprite == true end
  local r = record(data)
  return r ~= nil and def.permission == r.spritePermission
end

-- CAN YOU WALK ON IT?  The writer blocks every cell a decoration covers
-- except one permission -- a MAT is something you stand on and a desk is
-- something you walk around -- so a port that blocks all of them can wall a
-- player into a corner of their own base with a rug.
function Gen3Decorations.walkable(data, id)
  local def = Gen3Decorations.byId(data, id)
  local r = record(data)
  local pass = r and tonumber(r.passPermission)
  if not (def and pass) then return false end
  return tonumber(def.permission) == pass
end

-- The cells a decoration anchored at (x, y) covers, top row first, each as
-- { x, y, metatile } -- metatile nil for a sprite decoration.
function Gen3Decorations.footprint(data, id, x, y)
  local w, h = Gen3Decorations.shapeOf(data, id)
  x, y = math.floor(tonumber(x) or 0), math.floor(tonumber(y) or 0)
  if not (w and h) then return {} end
  local def = Gen3Decorations.byId(data, id)
  local tiles = def and def.metatiles
  local out = {}
  for row = 0, h - 1 do
    for col = 0, w - 1 do
      out[#out + 1] = { x = x + col, y = y - h + 1 + row,
                        metatile = tiles and tiles[row * w + col + 1] or nil }
    end
  end
  return out
end

-- ------- what is standing where

local function slots(save, where, make)
  if not save then return nil end
  if make then
    save.gen3 = save.gen3 or {}
    save.gen3.decorPlaced = save.gen3.decorPlaced or {}
    save.gen3.decorPlaced[where] = save.gen3.decorPlaced[where] or {}
  end
  local held = save.gen3 and save.gen3.decorPlaced
  return held and held[where] or nil
end

function Gen3Decorations.placed(save, where)
  return slots(save, where) or {}
end

function Gen3Decorations.placedCap(where)
  return Gen3Decorations.PLACES[where] or Gen3Decorations.PLACES.base
end

-- Does anything already own this cell?  Overlap is what the cartridge's
-- placement cursor refuses, and it refuses it per CELL rather than per
-- anchor, so this asks the footprint.
function Gen3Decorations.occupant(data, save, where, cx, cy)
  for index, row in ipairs(Gen3Decorations.placed(save, where)) do
    for _, cell in ipairs(Gen3Decorations.footprint(data, row.id, row.x, row.y)) do
      if cell.x == cx and cell.y == cy then return index, row end
    end
  end
  return nil
end

-- Put one out.  Takes it out of the bag, because that is what the cartridge
-- does: a decoration is either in storage or standing in the room.
function Gen3Decorations.putOut(data, save, where, id, x, y)
  id = math.floor(tonumber(id) or -1)
  if id < 0 or not Gen3Decorations.owns(save, id) then return false, "none" end
  local w, h = Gen3Decorations.shapeOf(data, id)
  if not (w and h) then return false, "shape" end
  local list = slots(save, where, true)
  if not list then return false, "save" end
  if #list >= Gen3Decorations.placedCap(where) then return false, "full" end
  for _, cell in ipairs(Gen3Decorations.footprint(data, id, x, y)) do
    if Gen3Decorations.occupant(data, save, where, cell.x, cell.y) then
      return false, "occupied"
    end
  end
  Gen3Decorations.take(save, id, 1)
  list[#list + 1] = { id = id, x = math.floor(x), y = math.floor(y) }
  return true
end

-- ...and take one back, which returns it to the bag.
function Gen3Decorations.putAway(data, save, where, index)
  local list = slots(save, where)
  local row = list and list[math.floor(tonumber(index) or 0)]
  if not row then return false end
  table.remove(list, index)
  Gen3Decorations.give(save, row.id, 1)
  return true, row.id
end

-- Everything standing in one place, as { index, def, x, y } in the order it
-- was put out.
function Gen3Decorations.standing(data, save, where)
  local out = {}
  for index, row in ipairs(Gen3Decorations.placed(save, where)) do
    local def = Gen3Decorations.byId(data, row.id)
    if def then
      out[#out + 1] = { index = index, id = row.id, def = def,
                        x = row.x, y = row.y }
    end
  end
  return out
end

-- WHICH PLACE a map is.  Only two maps in the game hold decorations -- the
-- secret base you own and the player's own bedroom -- and the base rooms are
-- a whole map group, so this is a question about the id.
-- WHERE A DECORATION CAN BE PUT OUT: a secret base you have claimed, or your
-- own bedroom.  The bedroom is TWO maps -- one per gender -- and until
-- extractHealLocations named them this only ever looked at a single-map
-- constant nothing wrote, so "room" was unreachable and everything bought
-- from the GAME CORNER's prize counter had nowhere to go.
function Gen3Decorations.playerRoom(data, save)
  local c = data and data.constants
  local room = c and c.gen3PlayerRoom
  if type(room) ~= "table" then
    -- an older cache: one map under the name this file used to read
    local single = c and c.gen3PlayerRoomMap
    return single and { single } or nil
  end
  -- the gender the save knows, and both when it does not: you can only ever
  -- be standing in your own
  local gender = tostring((save and save.player or {}).gender or ""):lower()
  if gender == "boy" or gender == "male" then return { room.boy } end
  if gender == "girl" or gender == "female" then return { room.girl } end
  return { room.boy, room.girl }
end

function Gen3Decorations.placeFor(data, save, mapId)
  local SB = require("src.world.Gen3SecretBase")
  local record_ = SB.record(data)
  if SB.isRoom(record_, mapId) and SB.mine(save) then return "base" end
  for _, id in ipairs(Gen3Decorations.playerRoom(data, save) or {}) do
    if id and mapId == id then return "room" end
  end
  return nil
end

return Gen3Decorations
