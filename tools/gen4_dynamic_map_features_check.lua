-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- THE PERSISTED MAP FEATURES -- the slot, the eleven tenants, and the two
-- numbers that are not a boolean.
--
-- Pass 189.  Grades src/world/Gen4DynamicMapFeatures.lua and the nineteen
-- script rows that write or read the slot.
--
-- WHAT THIS CHECK IS FOR, in one sentence each:
--
--   * the cartridge's three dispatch tables are three DIFFERENT sets, and the
--     module records them.  Derived from pokeplatinum's own source, not from
--     the module, so the module cannot grade itself;
--   * `GREAT_MARSH_TRAM_AT_LOCATION` is 5 and `NOT_AT_LOCATION` is 6, which
--     six script sites compare against.  A boolean would be wrong at all six;
--   * Pastoria's gate behaviours pair with the water heights INVERTED, and a
--     reader who straightened them would swap which gates are open;
--   * the 0x59 census in the declined-subject record was wrong twice, and
--     blocking those cells makes Pastoria unfinishable.  Both measured from
--     the cartridge every run.
--
-- Run:  texlua tools/gen4_dynamic_map_features_check.lua <platinum.nds> [pokeplatinum] [arm9.bin]

package.path = (function()
  local here = (arg and arg[0] or ""):gsub("[^/\\]*$", "")
  local root = (here ~= "") and (here .. "../") or "./"
  return root .. "?.lua;./?.lua;" .. package.path
end)()

local ROM  = arg and arg[1]
local PRET = arg and arg[2]
local ARM9 = arg and arg[3]

local fails, checks, reports, skips = 0, 0, 0, 0
local function ok(cond, fmt, ...)
  checks = checks + 1
  if not cond then
    fails = fails + 1
    io.write("FAIL: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
  end
end
local function report(fmt, ...)
  reports = reports + 1
  io.write("REPORT: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
end
local function skip(fmt, ...)
  skips = skips + 1
  io.write("SKIP: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
end
local function section(n) io.write(("\n-- %s\n"):format(n)) end
local function slurp(p)
  if not p then return nil end
  local f = io.open(p, "rb"); if not f then return nil end
  local s = f:read("*a"); f:close(); return s
end

local M        = require("src.world.Gen4DynamicMapFeatures")
local VM       = require("src.script.Gen4ScriptVM")
-- THE HANDLERS LIVE IN THE SHARED REGISTRY, not on the Gen4Commands module:
-- `Gen4Commands.lua` opens `local Commands = require("src.script.Commands")`
-- and writes into that.  Looking them up on the wrong table answers nil for
-- every name, which is a check that fails on a correct tree -- the first draft
-- of section 8 did exactly that.
require("src.script.Gen4Commands")
local Commands = require("src.script.Commands")
local Doors    = require("src.world.Gen4Doors")
local NdsRom   = require("src.import.NdsRom")
local Narc     = require("src.import.NarcArchive")
local Gen4Maps = require("src.import.Gen4Maps")
local Script   = require("src.import.Gen4Script")

-- ---------------------------------------------------------------------------
section("1. the slot")
-- ---------------------------------------------------------------------------

ok(M.BUFFER_BYTES == 32,
   "the persisted buffer is %s bytes; PERSISTED_MAP_FEATURES_BUFFER_SIZE is 32",
   tostring(M.BUFFER_BYTES))
ok(M.COUNT == 11,
   "DYNAMIC_MAP_FEATURES_COUNT is %s, not 11", tostring(M.COUNT))
ok(M.NONE == 0, "DYNAMIC_MAP_FEATURES_NONE must be 0, so that an untouched "
   .. "save holds no feature; it is %s", tostring(M.NONE))

-- THE IDS ARE CONSECUTIVE AND UNIQUE, which is what makes them usable as the
-- index into three parallel tables.  A duplicate would silently alias two
-- features onto one resolver.
do
  local byId, dup = {}, {}
  local NAMES = { "PASTORIA_GYM", "HEARTHOME_GYM", "CANALAVE_GYM",
    "VEILSTONE_GYM", "SUNYSHORE_GYM", "GREAT_MARSH", "PLATFORM_LIFT_ROOM",
    "ETERNA_GYM", "DISTORTION_WORLD", "VILLA" }
  for i, name in ipairs(NAMES) do
    local id = M[name]
    ok(id == i, "%s is %s; the enum puts it at %d", name, tostring(id), i)
    if byId[id] then dup[#dup + 1] = name end
    byId[id] = name
  end
  ok(#dup == 0, "two features share an id: %s", table.concat(dup, ", "))
end

-- THE SLOT CLEARS.  `PersistedMapFeatures_InitWithID` is a whole-record
-- MI_CpuClear8 before the id is stamped, and the clear is the only thing
-- stopping a second feature reading the first one's bytes as its own.
do
  local save = {}
  local b1 = M.initForPastoriaGym(save)
  b1.somethingPastoriaWrote = 7
  local b2 = M.initForCanalaveGym(save)
  ok(b2 ~= nil and b2.somethingPastoriaWrote == nil,
     "a second feature's buffer still carries the first feature's field, so "
     .. "the slot is reused rather than cleared")
  ok(b1 ~= b2,
     "both features were handed the SAME buffer table; a reference kept by "
     .. "the first would then write through into the second's state")
  ok(M.isCurrent(save, M.CANALAVE_GYM) and not M.isCurrent(save, M.PASTORIA_GYM),
     "the slot does not report the feature that stamped it last")
end

-- ...AND A MISMATCHED READ ANSWERS NOTHING.  The cartridge GF_ASSERTs and
-- then hands the buffer over anyway, which on retail hardware means a
-- feature reads another feature's bytes through its own struct.  This port
-- answers nil instead, and every caller has to say what it does about that --
-- so the nil is asserted, not assumed.
do
  local save = {}
  M.initForEternaGym(save)
  ok(M.buffer(save, M.ETERNA_GYM) ~= nil,
     "the feature that stamped the slot cannot read its own buffer")
  ok(M.buffer(save, M.PASTORIA_GYM) == nil,
     "a feature that does NOT hold the slot was handed a buffer; that is the "
     .. "GF_ASSERT this port is supposed to turn into a nil")
  ok(M.pastoriaWaterHeight(save) == nil,
     "the Pastoria water level answered a height while the slot holds Eterna")
  ok(M.tramLocation(save) == nil,
     "the tram answered a location while the slot holds Eterna")
  ok(M.advanceEternaClock({}) == false,
     "the clock advanced on a save whose slot holds no feature at all")
end

-- ---------------------------------------------------------------------------
section("2. the three dispatch tables, derived from the cartridge's source")
-- ---------------------------------------------------------------------------
--
-- `sInitFuncs`, `sFreeFuncs` and `sCheckCollisionFuncs` in
-- dynamic_map_features.c are three arrays of DYNAMIC_MAP_FEATURES_COUNT
-- entries, NULL where the feature has no such function.  They are not the
-- same set and they are not the same three exceptions, which is the fact
-- worth grading: Hearthome has an init and a free and NO collision; the Great
-- Marsh and the platform lift have an init and neither of the others.
if not PRET then
  skip("no pokeplatinum, so the dispatch tables are not re-derived this run")
else
  local src = slurp(PRET .. "/src/dynamic_map_features.c")
  ok(src ~= nil, "no src/dynamic_map_features.c under %s", tostring(PRET))
  if src then
    local function entries(name)
      local body = src:match(name .. "%s*%[[^%]]*%]%s*=%s*{(.-)}%s*;")
      if not body then return nil end
      local out = {}
      for item in body:gmatch("[^,%s][^,]*") do
        local v = item:gsub("%-%-[^\n]*", ""):gsub("%s+", "")
        if v ~= "" then out[#out + 1] = v end
      end
      return out
    end
    local function setOf(list)
      local s = {}
      for i, v in ipairs(list or {}) do
        -- index 0 is DYNAMIC_MAP_FEATURES_NONE, so entry i is feature i - 1
        if v ~= "NULL" then s[i - 1] = true end
      end
      return s
    end
    local function same(a, b, label)
      local diff = {}
      for id = 1, M.COUNT - 1 do
        if (a[id] or false) ~= (b[id] or false) then diff[#diff + 1] = id end
      end
      ok(#diff == 0,
         "the module's %s disagrees with the cartridge at feature id(s) %s",
         label, table.concat(diff, ", "))
    end
    local init = entries("sInitFuncs")
    local free = entries("sFreeFuncs")
    local coll = entries("sCheckCollisionFuncs")
    ok(init and #init == M.COUNT,
       "sInitFuncs has %s entries, not %d", init and #init or "no", M.COUNT)
    ok(free and #free == M.COUNT,
       "sFreeFuncs has %s entries, not %d", free and #free or "no", M.COUNT)
    ok(coll and #coll == M.COUNT,
       "sCheckCollisionFuncs has %s entries, not %d", coll and #coll or "no", M.COUNT)
    same(setOf(init), M.HAS_INIT, "HAS_INIT")
    same(setOf(free), M.HAS_FREE, "HAS_FREE")
    same(setOf(coll), M.HAS_COLLISION, "HAS_COLLISION")
    -- AND THE THREE SETS ARE DIFFERENT, asserted directly: if a later edit
    -- "tidied" them into one table every comparison above would still pass.
    local function count(s) local n = 0; for _ in pairs(s) do n = n + 1 end; return n end
    ok(count(M.HAS_INIT) == 10 and count(M.HAS_FREE) == 7
       and count(M.HAS_COLLISION) == 7,
       "the three tables hold %d/%d/%d features; the cartridge's are 10/7/7",
       count(M.HAS_INIT), count(M.HAS_FREE), count(M.HAS_COLLISION))
    ok(M.HAS_FREE[M.PASTORIA_GYM] ~= true and M.HAS_COLLISION[M.PASTORIA_GYM] == true,
       "Pastoria has a collision function and no free function; the module "
       .. "says free=%s collision=%s",
       tostring(M.HAS_FREE[M.PASTORIA_GYM]), tostring(M.HAS_COLLISION[M.PASTORIA_GYM]))
    ok(M.HAS_FREE[M.HEARTHOME_GYM] == true and M.HAS_COLLISION[M.HEARTHOME_GYM] ~= true,
       "Hearthome has a free function and NO collision function -- the two "
       .. "exceptions are not the same feature, which is why there are three "
       .. "tables; the module says free=%s collision=%s",
       tostring(M.HAS_FREE[M.HEARTHOME_GYM]),
       tostring(M.HAS_COLLISION[M.HEARTHOME_GYM]))
  end

  -- THE BUFFER IS EXACTLY BIG ENOUGH, derived rather than quoted: the
  -- Distortion World's struct is the largest tenant and it fills the 32 bytes
  -- to the byte.
  local dw = slurp(PRET .. "/include/overlay009/ov9_02249960.h")
  if not dw then
    skip("no overlay009 header, so the buffer size is not re-derived")
  else
    local ghosts = tonumber(dw:match("GHOST_PROP_GROUP_MAX_COUNT%s+(%d+)"))
    local plat = tonumber(dw:match("CURRENT_FLOATING_PLATFORM_SIZE%s+(%d+)"))
    ok(ghosts == 24 and plat == 4,
       "the Distortion World bitfield widths read %s and %s, not 24 and 4",
       tostring(ghosts), tostring(plat))
    if ghosts and plat then
      local bits = 1 + ghosts + plat + 3
      local bytes = bits / 8 + 2 * 4 + 4 + 16
      ok(bits == 32,
       "the bitfield is %d bits, so it is not one u32 and the struct's size "
       .. "below is computed from the wrong shape", bits)
      ok(bytes == M.BUFFER_BYTES,
       "DistWorldPersistedData comes to %d bytes and the buffer is %d; the "
       .. "largest tenant filling the slot exactly is what says the slot was "
       .. "sized for these structures", bytes, M.BUFFER_BYTES)
    end
  end
end

-- ---------------------------------------------------------------------------
section("3. Pastoria -- the inverted pairing")
-- ---------------------------------------------------------------------------

ok(M.TILE_UNITS == Gen4Maps.TERRAIN_TILE_UNITS,
   "MAP_OBJECT_TILE_SIZE is %s here and Gen4Maps says a terrain tile is %s; "
   .. "two spellings of one number is this codebase's recurring bug",
   tostring(M.TILE_UNITS), tostring(Gen4Maps.TERRAIN_TILE_UNITS))
ok(M.PASTORIA_WATER_LOW == 0 and M.PASTORIA_WATER_MIDDLE == 32
   and M.PASTORIA_WATER_HIGH == 64,
   "the three water heights are %s/%s/%s, not 0/32/64",
   tostring(M.PASTORIA_WATER_LOW), tostring(M.PASTORIA_WATER_MIDDLE),
   tostring(M.PASTORIA_WATER_HIGH))

-- THE INITIAL BUTTON IS NOT THE ENUM'S ZERO, which is the one thing a cleared
-- buffer would get wrong.
ok(M.PASTORIA_ORANGE_PRESSED == 0 and M.PASTORIA_GREEN_PRESSED == 1
   and M.PASTORIA_BLUE_PRESSED == 2,
   "enum PastoriaGymPressedButton is orange/green/blue = 0/1/2; the module "
   .. "says %s/%s/%s", tostring(M.PASTORIA_ORANGE_PRESSED),
   tostring(M.PASTORIA_GREEN_PRESSED), tostring(M.PASTORIA_BLUE_PRESSED))
do
  local save = {}
  local b = M.initForPastoriaGym(save)
  ok(b ~= nil and b.pressedButton == M.PASTORIA_GREEN_PRESSED,
     "Pastoria initialises to %s; the cartridge writes GREEN (%d), and a "
     .. "merely-cleared buffer would come up ORANGE (%d) -- a different water "
     .. "level and therefore a different gym",
     tostring(b and b.pressedButton), M.PASTORIA_GREEN_PRESSED,
     M.PASTORIA_ORANGE_PRESSED)
  ok(M.pastoriaWaterHeight(save) == M.PASTORIA_WATER_MIDDLE,
     "the initial water height is %s, not MIDDLE (%d)",
     tostring(M.pastoriaWaterHeight(save)), M.PASTORIA_WATER_MIDDLE)
end

-- THE PAIRING, AND THE FACT THAT IT IS INVERTED.
ok(M.PASTORIA_GATE_OPENS_AT[0x56] == M.PASTORIA_WATER_LOW,
   "H_GROUND opens at %s; PastoriaGym_DynamicMapFeaturesCheckCollision blocks "
   .. "it unless the height is PASTORIA_WATER_HEIGHT_LOW",
   tostring(M.PASTORIA_GATE_OPENS_AT[0x56]))
ok(M.PASTORIA_GATE_OPENS_AT[0x57] == M.PASTORIA_WATER_MIDDLE,
   "M_GROUND opens at %s, not MIDDLE", tostring(M.PASTORIA_GATE_OPENS_AT[0x57]))
ok(M.PASTORIA_GATE_OPENS_AT[0x58] == M.PASTORIA_WATER_HIGH,
   "L_GROUND opens at %s; it is the LOW ground behaviour and it pairs with "
   .. "the HIGH water", tostring(M.PASTORIA_GATE_OPENS_AT[0x58]))
-- Stated as the invariant rather than as three rows, so it survives a
-- "correction": high must pair with low and low with high.
ok(M.PASTORIA_GATE_OPENS_AT[0x56] < M.PASTORIA_GATE_OPENS_AT[0x58],
   "the H_GROUND gate opens at a HIGHER water level than the L_GROUND gate, "
   .. "so somebody has straightened the cartridge's inversion out and the "
   .. "gates now open at each other's levels")

if PRET then
  local gym = slurp(PRET .. "/src/overlay008/gym_features.c")
  ok(gym ~= nil, "no overlay008/gym_features.c under %s", tostring(PRET))
  if gym then
    -- re-derived from the function body, in its own order
    local body = gym:match("PastoriaGym_DynamicMapFeaturesCheckCollision%b()%s*\n{(.-)\n}")
    ok(body ~= nil, "could not find PastoriaGym_DynamicMapFeaturesCheckCollision")
    if body then
      local pairs_ = {}
      for which, want in body:gmatch("IsPastoriaGym(%w+)Ground%(tileBehavior%)%)%s*{%s*if%s*%(height%s*!=%s*PASTORIA_WATER_HEIGHT_(%w+)%)") do
        pairs_[which:upper()] = want:upper()
      end
      ok(pairs_.HIGH == "LOW", "the cartridge pairs HIGH ground with %s water",
         tostring(pairs_.HIGH))
      ok(pairs_.MIDDLE == "MIDDLE", "the cartridge pairs MIDDLE ground with %s water",
         tostring(pairs_.MIDDLE))
      ok(pairs_.LOW == "HIGH", "the cartridge pairs LOW ground with %s water",
         tostring(pairs_.LOW))
    end
    -- the plate, as written
    local px, pz, pw, ph = gym:match(
      "DynamicTerrainHeightManager_SetPlate%(PASTORIA_WATER_PLATE_INDEX,%s*(%d+),%s*(%d+),%s*(%d+),%s*(%d+)")
    ok(tonumber(px) == M.PASTORIA_PLATE_X and tonumber(pz) == M.PASTORIA_PLATE_Z
       and tonumber(pw) == M.PASTORIA_PLATE_W and tonumber(ph) == M.PASTORIA_PLATE_H,
       "the water plate is (%s,%s) %sx%s in the cartridge and (%s,%s) %sx%s here",
       tostring(px), tostring(pz), tostring(pw), tostring(ph),
       tostring(M.PASTORIA_PLATE_X), tostring(M.PASTORIA_PLATE_Z),
       tostring(M.PASTORIA_PLATE_W), tostring(M.PASTORIA_PLATE_H))
    -- the behaviour ids, by the enum walk rather than by eye
    local beh = slurp(PRET .. "/include/constants/field/map_tile_behaviors.h")
    if not beh then
      skip("no map_tile_behaviors.h, so the four behaviour ids are not re-derived")
    else
      local ids, nxt = {}, 0
      for line in beh:gmatch("[^\r\n]+") do
        local item = line:gsub("//.*", ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub(",$", "")
        if item:match("^TILE_BEHAVIOR_[%w_]+") and not item:find("enum") then
          local name, rhs = item:match("^([%w_]+)%s*=%s*(.+)$")
          if name then
            nxt = tonumber(rhs) or ids[rhs] or nxt
            ids[name] = nxt
          else
            ids[item] = nxt
          end
          nxt = (ids[name or item] or nxt) + 1
        end
      end
      ok(ids.TILE_BEHAVIOR_PASTORIA_GYM_H_GROUND == M.BEHAVIOUR_PASTORIA_H_GROUND,
         "the enum puts PASTORIA_GYM_H_GROUND at %s and the module says 0x%02X",
         tostring(ids.TILE_BEHAVIOR_PASTORIA_GYM_H_GROUND),
         M.BEHAVIOUR_PASTORIA_H_GROUND)
      ok(ids.TILE_BEHAVIOR_PASTORIA_GYM_M_GROUND == M.BEHAVIOUR_PASTORIA_M_GROUND,
         "M_GROUND is %s, not 0x%02X",
         tostring(ids.TILE_BEHAVIOR_PASTORIA_GYM_M_GROUND),
         M.BEHAVIOUR_PASTORIA_M_GROUND)
      ok(ids.TILE_BEHAVIOR_PASTORIA_GYM_L_GROUND == M.BEHAVIOUR_PASTORIA_L_GROUND,
         "L_GROUND is %s, not 0x%02X",
         tostring(ids.TILE_BEHAVIOR_PASTORIA_GYM_L_GROUND),
         M.BEHAVIOUR_PASTORIA_L_GROUND)
      ok(ids.TILE_BEHAVIOR_DYNAMIC_HEIGHT_COLLISION == M.BEHAVIOUR_DYNAMIC_HEIGHT,
         "DYNAMIC_HEIGHT_COLLISION is %s, not 0x%02X",
         tostring(ids.TILE_BEHAVIOR_DYNAMIC_HEIGHT_COLLISION),
         M.BEHAVIOUR_DYNAMIC_HEIGHT)
      -- the four are consecutive, which is what makes a one-off slip visible
      ok(M.BEHAVIOUR_PASTORIA_M_GROUND == M.BEHAVIOUR_PASTORIA_H_GROUND + 1
         and M.BEHAVIOUR_PASTORIA_L_GROUND == M.BEHAVIOUR_PASTORIA_M_GROUND + 1
         and M.BEHAVIOUR_DYNAMIC_HEIGHT == M.BEHAVIOUR_PASTORIA_L_GROUND + 1,
         "the four behaviours are not consecutive, so one of them has drifted")
    end
  end
end

-- THE BUTTON IS A MODEL UNDER THE PLAYER, and a model that is not one of the
-- three must do nothing rather than pick one.
do
  local save = {}
  M.initForPastoriaGym(save)
  ok(M.pressPastoriaButton(save, 241) == true
     and M.pastoriaWaterHeight(save) == M.PASTORIA_WATER_LOW,
     "pressing the orange button (model 241) left the water at %s, not LOW",
     tostring(M.pastoriaWaterHeight(save)))
  ok(M.pressPastoriaButton(save, 239) == true
     and M.pastoriaWaterHeight(save) == M.PASTORIA_WATER_HIGH,
     "pressing the blue button (model 239) left the water at %s, not HIGH",
     tostring(M.pastoriaWaterHeight(save)))
  local before = M.pastoriaWaterHeight(save)
  ok(M.pressPastoriaButton(save, 77) == false,
     "a model that is not one of the three buttons was accepted; the "
     .. "cartridge's else-arm is GF_ASSERT(FALSE)")
  ok(M.pastoriaWaterHeight(save) == before,
     "a rejected button still moved the water from %s to %s",
     tostring(before), tostring(M.pastoriaWaterHeight(save)))
  -- ...and it does nothing when another feature holds the slot
  local other = {}
  M.initForCanalaveGym(other)
  ok(M.pressPastoriaButton(other, 239) == false,
     "a Pastoria button wrote through a slot holding Canalave")
end

-- THE HITBOX IS ONE TILE, AND THE DOOR SEARCH'S IS THREE.  Asserted together
-- because the second was the obvious thing to copy.
ok(M.BUTTON_HITBOX_OFFSET_X == 0 and M.BUTTON_HITBOX_SIZE_X == 1
   and M.BUTTON_HITBOX_SIZE_Z == 1,
   "the button hitbox is offset %s size %sx%s; PastoriaGym_PressButton builds "
   .. "TerrainCollisionHitbox_Init(x, z, 0, 0, 1, 1)",
   tostring(M.BUTTON_HITBOX_OFFSET_X), tostring(M.BUTTON_HITBOX_SIZE_X),
   tostring(M.BUTTON_HITBOX_SIZE_Z))
ok(Doors.HITBOX_OFFSET_X == -1 and Doors.HITBOX_SIZE_X == 3,
   "the door search's hitbox is offset %s size %s; it is meant to be three "
   .. "tiles starting one west, and the button search is meant to differ "
   .. "from it", tostring(Doors.HITBOX_OFFSET_X), tostring(Doors.HITBOX_SIZE_X))
ok(M.BUTTON_HITBOX_SIZE_X ~= Doors.HITBOX_SIZE_X,
   "the button hitbox and the door hitbox are now the same width, so one of "
   .. "them has been made to borrow the other's and a button beside the "
   .. "player would be pressed")

-- ---------------------------------------------------------------------------
section("4. Canalave -- the bitfield")
-- ---------------------------------------------------------------------------

ok(M.CANALAVE_NUM_PLATFORMS == 24,
   "CANALAVE_GYM_NUM_PLATFORMS is %s, not 24", tostring(M.CANALAVE_NUM_PLATFORMS))
ok(#M.CANALAVE_STARTS_IN_B == 10,
   "%d platforms start in position B; the cartridge's array has ten TRUEs",
   #M.CANALAVE_STARTS_IN_B)
ok(M.canalavePlatformStates() == 0xAD0DC0,
   "the packed platform word is 0x%X, not 0x00AD0DC0",
   M.canalavePlatformStates())
do
  local save = {}
  M.initForCanalaveGym(save)
  local inB = {}
  for i = 0, M.CANALAVE_NUM_PLATFORMS - 1 do
    if M.canalavePlatformInB(save, i) then inB[#inB + 1] = i end
  end
  ok(#inB == 10, "the packed word unpacks to %d platforms in B, not ten", #inB)
  ok(table.concat(inB, ",") == table.concat(M.CANALAVE_STARTS_IN_B, ","),
     "the packed word unpacks to {%s} and the list says {%s}; the pack and "
     .. "the unpack disagree, so one of them has the bit order wrong",
     table.concat(inB, ","), table.concat(M.CANALAVE_STARTS_IN_B, ","))
  -- the bounds the cartridge asserts
  ok(M.canalavePlatformInB(save, 24) == nil
     and M.canalavePlatformInB(save, -1) == nil,
     "a platform index outside 0..23 was answered rather than refused")
end
if PRET then
  -- IN persisted_map_features_init.c, NOT gym_features.c.  The first draft
  -- read it out of the gym file -- where every other Canalave constant lives
  -- -- found nothing, and SKIPPED: a check that cannot find its subject
  -- reports "not run" and looks like a pass at a glance.
  local init = slurp(PRET .. "/src/persisted_map_features_init.c")
  local body = init and init:match(
    "sCanalaveGymPlatformsStartInPositionB%s*%[[^%]]*%]%s*=%s*{(.-)}")
  if not body then
    skip("could not find sCanalaveGymPlatformsStartInPositionB")
  else
    local list, i = {}, 0
    for word in body:gmatch("[A-Z]+") do
      if word == "TRUE" then list[#list + 1] = i end
      i = i + 1
    end
    ok(i == 24, "the cartridge's array has %d entries, not 24", i)
    ok(table.concat(list, ",") == table.concat(M.CANALAVE_STARTS_IN_B, ","),
       "the cartridge starts platforms {%s} in position B and the module says "
       .. "{%s}", table.concat(list, ","),
       table.concat(M.CANALAVE_STARTS_IN_B, ","))
  end
end

-- ---------------------------------------------------------------------------
section("5. Sunyshore -- the room, and the entrance that overrides it")
-- ---------------------------------------------------------------------------

ok(M.SUNYSHORE_NUM_ROOMS == 3,
   "SUNYSHORE_GYM_NUM_ROOMS is %s, not 3", tostring(M.SUNYSHORE_NUM_ROOMS))
do
  -- the per-room rotation, when the player is NOT at the entrance z
  for room = 0, 2 do
    local save = {}
    local b = M.initForSunyshoreGym(save, room, -1)
    ok(b ~= nil and b.roomID == room,
       "room %d did not record its own id (%s)", room, tostring(b and b.roomID))
    ok(b ~= nil and b.rotationState == M.SUNYSHORE_ROOM_ROTATION[room],
       "room %d starts at rotation %s, not %s", room,
       tostring(b and b.rotationState), tostring(M.SUNYSHORE_ROOM_ROTATION[room]))
  end
  -- ...AND THE OVERRIDE, which is the half a constant table would lose.
  for room = 0, 2 do
    local save = {}
    local b = M.initForSunyshoreGym(save, room, M.SUNYSHORE_ROOM_ENTRANCE_Z[room])
    ok(b ~= nil and b.rotationState == 0,
       "room %d entered at its own entrance z (%s) kept rotation %s; the "
       .. "cartridge forces 0", room,
       tostring(M.SUNYSHORE_ROOM_ENTRANCE_Z[room]), tostring(b and b.rotationState))
  end
  -- the override must MATTER for at least one room, or it is untested by
  -- construction: room 2 already starts at 0, so rooms 0 and 1 are the test.
  ok(M.SUNYSHORE_ROOM_ROTATION[0] ~= 0 and M.SUNYSHORE_ROOM_ROTATION[1] ~= 0,
     "rooms 0 and 1 no longer start at a non-zero rotation, so the entrance "
     .. "override above cannot be distinguished from doing nothing")
  -- a bad room must not stamp the slot
  local save = {}
  M.initForEternaGym(save)
  ok(M.initForSunyshoreGym(save, 3, 0) == nil,
     "room 3 was accepted; GF_ASSERT(roomID < SUNYSHORE_GYM_NUM_ROOMS) "
     .. "precedes the write")
  ok(M.isCurrent(save, M.ETERNA_GYM),
     "a refused Sunyshore room still took the slot from Eterna")
end
if PRET then
  local init = slurp(PRET .. "/src/persisted_map_features_init.c")
  local body = init and init:match(
    "PersistedMapFeatures_InitForSunyshoreGym%b()%s*\n{(.-)\n}")
  if not body then
    skip("could not find PersistedMapFeatures_InitForSunyshoreGym")
  else
    local rot, ez = {}, {}
    local room = nil
    for line in body:gmatch("[^\r\n]+") do
      local c = line:match("case%s+(%d+):")
      if c then room = tonumber(c) end
      local r = line:match("rotationState%s*=%s*(%d+)")
      if r and room then rot[room] = tonumber(r) end
      local z = line:match("entranceZ%s*=%s*(%d+)")
      if z and room then ez[room] = tonumber(z) end
    end
    for r = 0, 2 do
      ok(rot[r] == M.SUNYSHORE_ROOM_ROTATION[r],
         "the cartridge gives room %d rotation %s and the module %s", r,
         tostring(rot[r]), tostring(M.SUNYSHORE_ROOM_ROTATION[r]))
      ok(ez[r] == M.SUNYSHORE_ROOM_ENTRANCE_Z[r],
         "the cartridge gives room %d entrance z %s and the module %s", r,
         tostring(ez[r]), tostring(M.SUNYSHORE_ROOM_ENTRANCE_Z[r]))
    end
  end
end

-- ---------------------------------------------------------------------------
section("6. Eterna -- the cap, and the var nobody reads")
-- ---------------------------------------------------------------------------

ok(M.ETERNA_CLOCK_VAR == 0x404B,
   "VAR_ETERNA_GYM_FLOWER_CLOCK_STATE is 0x%X here; the enum walk over "
   .. "generated/vars_flags.txt puts it at 0x404B", M.ETERNA_CLOCK_VAR)
ok(M.ETERNA_CLOCK_VAR >= 0x4000,
   "the clock var is below VARS_START, so the enum walk slipped out of the "
   .. "var block")
do
  local save = {}
  M.initForEternaGym(save)
  local seen = {}
  for step = 1, 8 do
    local advanced, state = M.advanceEternaClock(save)
    seen[#seen + 1] = advanced and state or "refused"
  end
  ok(table.concat(seen, ",") == "1,2,3,4,refused,refused,refused,refused",
     "the clock advanced as %s; the cartridge walks 1,2,3,4 and then refuses "
     .. "for ever (`state >= ETERNA_CLOCK_DEFEATED_GYM_LEADER` returns FALSE)",
     table.concat(seen, ","))
  local b = M.buffer(save, M.ETERNA_GYM)
  ok(b and b.state == M.ETERNA_CLOCK_DEFEATED_GYM_LEADER,
     "the clock settled at %s, not DEFEATED_GYM_LEADER (%d)",
     tostring(b and b.state), M.ETERNA_CLOCK_DEFEATED_GYM_LEADER)
end
if PRET then
  local gym = slurp(PRET .. "/include/overlay008/gym_features.h")
  if gym then
    local body = gym:match("enum EternaClockState%s*{(.-)}")
    local names = {}
    if body then for n in body:gmatch("ETERNA_CLOCK_[%w_]+") do names[#names + 1] = n end end
    ok(#names == 6,
       "enum EternaClockState has %d names; it is five states plus MAX", #names)
    ok(names[5] == "ETERNA_CLOCK_DEFEATED_GYM_LEADER",
       "the fifth EternaClockState is %s, so the cap's value has moved",
       tostring(names[5]))
  end
end

-- ---------------------------------------------------------------------------
section("7. the Great Marsh tram -- five and six")
-- ---------------------------------------------------------------------------

ok(M.MARSH_AT_LOCATION == 5 and M.MARSH_NOT_AT_LOCATION == 6,
   "the tram answers %s/%s; GREAT_MARSH_TRAM_AT_LOCATION is 5 and "
   .. "NOT_AT_LOCATION is 6", tostring(M.MARSH_AT_LOCATION),
   tostring(M.MARSH_NOT_AT_LOCATION))
ok(M.MARSH_AT_LOCATION ~= 1 and M.MARSH_NOT_AT_LOCATION ~= 0,
   "the tram answers a boolean; the six script sites compare against the "
   .. "literal 6, so a boolean never matches and the tram is never summoned")
ok(M.MARSH_MOVEMENT_CALL == 3 and M.MARSH_MOVEMENT_RIDE == 4,
   "the movement types are %s/%s, not 3/4", tostring(M.MARSH_MOVEMENT_CALL),
   tostring(M.MARSH_MOVEMENT_RIDE))

-- THE ONLY CONSTRUCTOR THAT CHECKS FIRST.
do
  local save = {}
  local b = M.initForGreatMarsh(save)
  ok(b ~= nil and b.location == M.MARSH_AREA_5_6,
     "the tram starts at %s, not area 5-6", tostring(b and b.location))
  M.moveTramToLocation(save, M.MARSH_AREA_1_2)
  ok(M.tramLocation(save) == M.MARSH_AREA_1_2, "the tram did not move to 1-2")
  M.initForGreatMarsh(save)
  ok(M.tramLocation(save) == M.MARSH_AREA_1_2,
     "re-running the Great Marsh init reset the tram to %s; "
     .. "PersistedMapFeatures_InitForGreatMarsh initialises ONLY when the "
     .. "slot is not already the marsh's, and all six marsh maps run that "
     .. "init script", tostring(M.tramLocation(save)))
  -- ...and it DOES initialise when another feature holds the slot
  M.initForEternaGym(save)
  M.initForGreatMarsh(save)
  ok(M.tramLocation(save) == M.MARSH_AREA_5_6,
     "after another feature took the slot the marsh init did not rebuild it "
     .. "(location %s)", tostring(M.tramLocation(save)))
end

-- THE THREE ARMS, INCLUDING THE SELF-MOVE.
do
  local cases = {
    { from = 0, dest = 1, want = 1 },
    { from = 0, dest = 2, want = 2 },
    -- the one a "go to the destination" port gets wrong:
    { from = 0, dest = 0, want = 2 },
    { from = 1, dest = 0, want = 0 },
    { from = 1, dest = 2, want = 2 },
    { from = 1, dest = 1, want = 2 },
    { from = 2, dest = 0, want = 0 },
    { from = 2, dest = 1, want = 1 },
    { from = 2, dest = 2, want = 1 },
  }
  for _, c in ipairs(cases) do
    local save = {}
    M.initForGreatMarsh(save)
    M.buffer(save, M.GREAT_MARSH).location = c.from
    local got = M.moveTramToLocation(save, c.dest)
    ok(got == c.want,
       "from area %d asking for %d the tram went to %s; the cartridge's arm "
       .. "for %d tests only against %d and falls through otherwise, so the "
       .. "answer is %d", c.from, c.dest, tostring(got), c.from,
       (c.from == 0) and 1 or 0, c.want)
  end
  -- and the answer a script gets
  local save = {}
  M.initForGreatMarsh(save)
  ok(M.checkTramLocation(save, M.MARSH_AREA_5_6) == M.MARSH_AT_LOCATION,
     "asking where the tram is at its own location answered %s, not 5",
     tostring(M.checkTramLocation(save, M.MARSH_AREA_5_6)))
  ok(M.checkTramLocation(save, M.MARSH_AREA_1_2) == M.MARSH_NOT_AT_LOCATION,
     "asking about a location the tram is not at answered %s, not 6",
     tostring(M.checkTramLocation(save, M.MARSH_AREA_1_2)))
  -- ...and with the slot held by someone else, the honest answer is NOT_AT:
  -- the tram is not where you asked, because there is no tram.
  local other = {}
  M.initForVilla(other)
  ok(M.checkTramLocation(other, M.MARSH_AREA_5_6) == M.MARSH_NOT_AT_LOCATION,
     "with the slot holding the villa the tram answered %s; NOT_AT (6) is the "
     .. "answer that makes the script fetch a tram rather than assume one",
     tostring(M.checkTramLocation(other, M.MARSH_AREA_5_6)))
end
if PRET then
  local h = slurp(PRET .. "/include/constants/great_marsh_tram.h")
  if not h then
    skip("no constants/great_marsh_tram.h, so the five and six are not re-derived")
  else
    local function def(name) return tonumber(h:match(name .. "%s+(%d+)")) end
    ok(def("GREAT_MARSH_TRAM_AT_LOCATION") == M.MARSH_AT_LOCATION,
       "the cartridge's AT_LOCATION is %s and the module says %s",
       tostring(def("GREAT_MARSH_TRAM_AT_LOCATION")), tostring(M.MARSH_AT_LOCATION))
    ok(def("GREAT_MARSH_TRAM_NOT_AT_LOCATION") == M.MARSH_NOT_AT_LOCATION,
       "the cartridge's NOT_AT_LOCATION is %s and the module says %s",
       tostring(def("GREAT_MARSH_TRAM_NOT_AT_LOCATION")),
       tostring(M.MARSH_NOT_AT_LOCATION))
    ok(def("GREAT_MARSH_TRAM_LOCATION_AREA_5_6") == M.MARSH_AREA_5_6,
       "AREA_5_6 is %s, not %s", tostring(def("GREAT_MARSH_TRAM_LOCATION_AREA_5_6")),
       tostring(M.MARSH_AREA_5_6))
    ok(def("GREAT_MARSH_TRAM_MOVEMENT_CALL") == M.MARSH_MOVEMENT_CALL,
       "MOVEMENT_CALL is %s, not %s", tostring(def("GREAT_MARSH_TRAM_MOVEMENT_CALL")),
       tostring(M.MARSH_MOVEMENT_CALL))
  end
end

-- ---------------------------------------------------------------------------
section("8. the nineteen rows")
-- ---------------------------------------------------------------------------

local FAMILY = {
  "initpersistedmapfeaturesforpastoriagym", "presspastoriagymbutton",
  "initpersistedmapfeaturesforhearthomegym", "movehearthomegymdplift",
  "initpersistedmapfeaturesforcanalavegym",
  "initpersistedmapfeaturesforveilstonegym",
  "initpersistedmapfeaturesforsunyshoregym", "presssunyshoregymbutton",
  "initpersistedmapfeaturesforplatformlift", "triggerplatformlift",
  "checkplatformliftnotusedwhenenteredmap",
  "initpersistedmapfeaturesforeternagym", "advanceeternagymclock",
  "initpersistedmapfeaturesforvilla",
  "initpersistedmapfeaturesfordistortionworld",
  "initgreatmarshtram", "movegreatmarshtram", "checkgreatmarshtramlocation",
  "setplayerheightcalculationenabled",
}
do
  local notLowered = {}
  for _, name in ipairs(FAMILY) do
    if VM.lowered(name) ~= true then notLowered[#notLowered + 1] = name end
  end
  table.sort(notLowered)
  ok(#notLowered == 0, "%d row(s) in the family are not lowered: %s",
     #notLowered, table.concat(notLowered, ", "))
end
-- The canary first: the registry must be able to say no, or the five
-- lookups below mean nothing.
ok(Commands["g4_this_handler_does_not_exist"] == nil,
   "the command registry answers something for a name that does not exist, so "
   .. "the five lookups below would pass whatever happened")
for _, name in ipairs({ "g4_map_feature_init", "g4_pastoria_button",
                        "g4_sunyshore_gear_button", "g4_eterna_clock_advance",
                        "g4_marsh_tram" }) do
  ok(type(Commands[name]) == "function", "no handler named %s", name)
end

-- THE SOURCE ORDER OF THE TRAM OPERANDS, which is the one asymmetry a
-- handler can get wrong without anything failing: `check` reads a literal and
-- writes a var, `move` reads a var and takes a literal.  Read out of the VM's
-- own source, because the operand ORDER is not visible from a behavioural
-- test that passes the same number twice.
do
  local src = slurp("src/script/Gen4ScriptVM.lua")
          or slurp("../src/script/Gen4ScriptVM.lua")
  ok(src ~= nil, "could not read Gen4ScriptVM.lua")
  if src then
    ok(src:find('"g4_marsh_tram", "check", ins%.args%[1%], ins%.args%[2%]'),
       "the `check` row does not pass args 1 then 2; the location is the "
       .. "first operand and the destination var the second")
    ok(src:find('"g4_marsh_tram", "move", ins%.args%[1%], ins%.args%[2%]'),
       "the `move` row does not pass args 1 then 2")
    ok(src:find('"g4_map_feature_init", "sunyshore", ins%.args%[1%]'),
       "the Sunyshore init row does not pass its room-id operand")
    -- ...and the twelve rows no longer declare themselves absent
    for _, gone in ipairs({ "the Pastoria Gym water level",
                            "the Canalave Gym sliding floor",
                            "the Sunyshore Gym persisted map feature",
                            "the Eterna Gym persisted map feature" }) do
      ok(not src:find(gone, 1, true),
         "'%s' is still declared as a no-op subject in the VM", gone)
    end
  end
end

-- ---------------------------------------------------------------------------
section("9. collision: the contract, and why there is no resolver")
-- ---------------------------------------------------------------------------
--
-- The resolvers are absent on purpose and the reason is measured in section
-- 10.  What is asserted here is that the WIRING is real: the registry exists,
-- is empty, and `checkCollision` answers "not handled" rather than
-- accidentally answering "open" -- which is a different thing and would make
-- every blocked cell in Sinnoh walkable the day a resolver is added.
ok(type(M.RESOLVERS) == "table", "there is no resolver registry")
ok(type(M.checkCollision) == "function", "there is no checkCollision")
do
  local save = {}
  local handled, colliding = M.checkCollision(save, nil, 0, 0, 0)
  ok(handled == false,
     "with no feature in the slot checkCollision answered handled=%s; NONE "
     .. "must mean 'ask the map'", tostring(handled))
  ok(colliding == nil,
     "an unhandled answer carried a collision verdict (%s) as well; a caller "
     .. "that reads the second value without checking the first would then "
     .. "treat it as 'open'", tostring(colliding))
  for id = 1, M.COUNT - 1 do
    local s = { gen4MapFeature = { id = id, buffer = {} } }
    local h = M.checkCollision(s, nil, 0, 0, 0)
    ok(h == false,
       "feature %d claims to handle collision; no resolver is written yet, so "
       .. "something is answering for it", id)
  end
  local count = 0
  for _ in pairs(M.RESOLVERS) do count = count + 1 end
  ok(count == 0,
     "the resolver registry has %d entr(ies); when the first one lands this "
     .. "check must be rewritten to grade it rather than to assert its "
     .. "absence", count)
end

-- ---------------------------------------------------------------------------
section("10. the cartridge: the 0x59 census, and the gym it would lock")
-- ---------------------------------------------------------------------------

if not ROM then
  skip("no cartridge, so the behaviour census and the reachability "
       .. "measurement are not run")
else
  local rom = NdsRom.open(ROM)
  ok(rom ~= nil, "could not open %s", tostring(ROM))
  local land = rom and Narc.parse(rom:read("/fielddata/land_data/land_data.narc"))
  ok(land ~= nil, "no land_data.narc in the cartridge")
  if land then
    ok(land.count == 666, "land_data has %d chunks, not 666", land.count)
    local WANT = { [0x56] = "H", [0x57] = "M", [0x58] = "L", [0x59] = "DYN" }
    local total, per = {}, {}
    for i = 0, land.count - 1 do
      local L = Gen4Maps.land(land:get(i))
      if L and L.permissions then
        for t = 0, (#L.permissions / 2) - 1 do
          local b = L.permissions:byte(t * 2 + 1)
          if WANT[b] then
            total[b] = (total[b] or 0) + 1
            per[i] = per[i] or {}
            per[i][b] = (per[i][b] or 0) + 1
          end
        end
      end
    end
    -- THE RECORD WAS WRONG TWICE, and these are the corrected numbers.  Named
    -- per gym rather than only as a total, because the total was right in
    -- shape and wrong in size: Sunyshore's figure had been copied from
    -- Canalave's -- 293 twice -- and Pastoria's was 89 short.
    local byGym = {
      canalave  = (per[225] or {})[0x59] or 0,
      pastoria  = ((per[223] or {})[0x59] or 0) + ((per[224] or {})[0x59] or 0),
      sunyshore = ((per[296] or {})[0x59] or 0) + ((per[297] or {})[0x59] or 0)
                  + ((per[298] or {})[0x59] or 0),
    }
    ok(byGym.canalave == 293,
       "Canalave has %d DYNAMIC_HEIGHT_COLLISION cells, not 293", byGym.canalave)
    ok(byGym.pastoria == 445,
       "Pastoria has %d, not 445 (the declined record said 356)", byGym.pastoria)
    ok(byGym.sunyshore == 411,
       "Sunyshore has %d, not 411 (the declined record said 293, which was "
       .. "Canalave's number copied)", byGym.sunyshore)
    ok((total[0x59] or 0) == 1149,
       "the cartridge has %d DYNAMIC_HEIGHT_COLLISION cells, not 1,149 (the "
       .. "declined record said 942)", total[0x59] or 0)
    ok(byGym.canalave + byGym.pastoria + byGym.sunyshore == (total[0x59] or 0),
       "the three gyms account for %d of %d cells, so the behaviour appears "
       .. "somewhere else as well and the blast radius is no longer those "
       .. "three gyms", byGym.canalave + byGym.pastoria + byGym.sunyshore,
       total[0x59] or 0)
    -- the gate counts, which the record got right
    ok((total[0x56] or 0) == 10 and (total[0x57] or 0) == 6
       and (total[0x58] or 0) == 10,
       "the H/M/L gate counts are %d/%d/%d, not 10/6/10",
       total[0x56] or 0, total[0x57] or 0, total[0x58] or 0)
    local gymChunks = 0
    for _ in pairs(per) do gymChunks = gymChunks + 1 end
    ok(gymChunks == 6, "the four behaviours appear in %d chunks, not 6", gymChunks)
    report("0x59 in 6 chunks: Canalave %d, Pastoria %d, Sunyshore %d, total %d",
           byGym.canalave, byGym.pastoria, byGym.sunyshore, total[0x59] or 0)

    -- THE GYMS, BY THE CARTRIDGE'S OWN NAMES, so the chunk numbers above are
    -- not three magic constants.
    if not ARM9 then
      skip("no arm9, so the three gyms are not identified by name")
    else
      local arm9 = slurp(ARM9)
      local Headers = require("src.import.Gen4MapHeaders")
      local names = Gen4Maps.mapNames(rom:read("/fielddata/maptable/mapname.bin"))
      local all = arm9 and Headers.all(arm9, Headers.KNOWN_OFFSET, Headers.KNOWN_COUNT)
      local mats = Narc.parse(rom:read("/fielddata/mapmatrix/map_matrix.narc"))
      ok(all ~= nil and mats ~= nil, "could not read the headers or matrices")
      if all and mats then
        local matrixOf = {}
        for i = 0, mats.count - 1 do
          local m = Gen4Maps.matrix(mats:get(i))
          for _, id in ipairs(m and m.maps or {}) do
            if per[id] then matrixOf[i] = true end
          end
        end
        local found = {}
        for i, h in ipairs(all) do
          if matrixOf[h.matrix] then found[names[i] or "?"] = true end
        end
        for _, want in ipairs({ "C02GYM0101", "C06GYM0101", "C08GYM0101",
                                "C08GYM0102", "C08GYM0103" }) do
          ok(found[want] == true,
             "no map named %s uses a chunk carrying these behaviours; the "
             .. "six chunks are not the three gyms this says they are", want)
        end
      end
    end

    -- THE MEASUREMENT THAT SAYS THE OBVIOUS FIX IS WRONG.
    --
    -- Pastoria, as the stacked 32x64 its 1x2 matrix makes it.  Flood from the
    -- entrance warp -- whose coordinates come from the zone event data, not
    -- from reading the map by eye -- and compare three readings of 0x59.
    local W, H = 32, 64
    local beh, blocked = {}, {}
    for ci, id in ipairs({ 223, 224 }) do
      local L = Gen4Maps.land(land:get(id))
      for t = 0, 1023 do
        local x, z = t % 32, math.floor(t / 32)
        local w = L.permissions:byte(t * 2 + 1) + L.permissions:byte(t * 2 + 2) * 256
        beh[(ci - 1) * 32 * W + z * W + x] = w % 256
        blocked[(ci - 1) * 32 * W + z * W + x] = Gen4Maps.blocks(w)
      end
    end
    local SX, SZ
    if ARM9 then
      local arm9 = slurp(ARM9)
      local Headers = require("src.import.Gen4MapHeaders")
      local Events = require("src.import.Gen4Events")
      local all = arm9 and Headers.all(arm9, Headers.KNOWN_OFFSET, Headers.KNOWN_COUNT)
      local h = all and all[122]        -- header id 121, C06GYM0101
      local arc = Narc.parse(rom:read("/fielddata/eventdata/zone_event.narc"))
      local e = h and arc and Events.parse(arc:get(h.events))
      local warp = e and e.warps and e.warps[1]
      ok(h ~= nil and h.matrix == 111,
         "header 121 names matrix %s, not Pastoria's 111",
         tostring(h and h.matrix))
      ok(e ~= nil and #e.warps == 1,
         "Pastoria's gym has %s warps; the flood below starts from the only "
         .. "one", tostring(e and #e.warps))
      if warp then SX, SZ = warp.x, warp.z end
      -- the leader, who is the thing the flood has to reach
      local leader = e and e.npcs and e.npcs[1]
      ok(leader ~= nil and leader.x == 13 and leader.z == 4,
         "the first object event is at (%s,%s); Crasher Wake stands at (13,4), "
         .. "on an island at the top of the gym",
         tostring(leader and leader.x), tostring(leader and leader.z))
    end
    if not SX then
      skip("no arm9, so the entrance warp is not read and the flood is not run")
    else
      ok(SX == 13 and SZ == 42,
         "Pastoria's entrance warp is at (%d,%d); the flood below assumes the "
         .. "south passage", SX, SZ)
      local GATE = M.PASTORIA_GATE_OPENS_AT

      -- the ten buttons, found by MODEL in the terrain rather than typed in,
      -- and the level each one sets
      local buttonLevel = {}
      local buttonCount = 0
      for ci, id in ipairs({ 223, 224 }) do
        local L = Gen4Maps.land(land:get(id))
        for _, o in ipairs(Gen4Maps.objects(L) or {}) do
          local pressed = M.PASTORIA_BUTTON_MODELS[o.model]
          if pressed then
            local tx = math.floor((o.x + 256) / 16)
            local tz = math.floor((o.z + 256) / 16) + (ci - 1) * 32
            buttonLevel[tz * W + tx] = M.PASTORIA_WATER_FOR_BUTTON[pressed]
            buttonCount = buttonCount + 1
          end
        end
      end
      ok(buttonCount == 10,
         "%d Pastoria buttons are placed in the terrain; there are ten",
         buttonCount)

      -- A SEARCH OVER (CELL, WATER LEVEL), not a flood over cells.
      --
      -- A plain flood cannot answer "is this gym finishable", because the
      -- level changes while you walk: standing on a button is a move in the
      -- state space.  The first draft of this check used a flood and reported
      -- 219 reachable cells with 0x59 blocked, which looked survivable -- the
      -- flood was ignoring the gates, so it was crediting the player with
      -- gates the cartridge keeps shut.  With both rules applied together the
      -- answer is 57 cells and no button at all.
      local function search(waterBlocks, gatesEnforced, startLevel, allowButtons)
        local key = function(i, l) return i .. "@" .. tostring(l) end
        local seen = { [key(SZ * W + SX, startLevel)] = true }
        local q = { { SZ * W + SX, startLevel } }
        local cells, head = {}, 1
        while head <= #q do
          local st = q[head]; head = head + 1
          local i, level = st[1], st[2]
          cells[i] = true
          local sets = allowButtons and buttonLevel[i] or nil
          if sets and sets ~= level and not seen[key(i, sets)] then
            seen[key(i, sets)] = true; q[#q + 1] = { i, sets }
          end
          local x, z = i % W, math.floor(i / W)
          for _, p in ipairs({ { x + 1, z }, { x - 1, z }, { x, z + 1 }, { x, z - 1 } }) do
            local nx, nz = p[1], p[2]
            if nx >= 0 and nx < W and nz >= 0 and nz < H then
              local j = nz * W + nx
              local pass = blocked[j] == false
              if pass and beh[j] == M.BEHAVIOUR_DYNAMIC_HEIGHT then
                pass = not waterBlocks
              elseif pass and gatesEnforced and GATE[beh[j]] then
                pass = (GATE[beh[j]] == level)
              end
              if pass and not seen[key(j, level)] then
                seen[key(j, level)] = true; q[#q + 1] = { j, level }
              end
            end
          end
        end
        local n, reached = 0, 0
        for i in pairs(cells) do
          n = n + 1
          if buttonLevel[i] then reached = reached + 1 end
        end
        return n, reached
      end

      local MID = M.PASTORIA_WATER_MIDDLE
      -- today: the gates are not enforced and 0x59 is ordinary floor
      local todayN, todayB = search(false, false, MID, true)
      -- the cartridge's rules minus the heights
      local gatedN, gatedB = search(false, true, MID, true)
      -- the plain reading of the behaviour's name
      local lockedN, lockedB = search(true, true, MID, true)
      -- and the gates with no button ever pressed, which is the detour's size
      local noPressN = search(false, true, MID, false)

      ok(todayN == 708 and todayB == 10,
         "with 0x59 walkable and the gates ignored -- today's port -- %d cells "
         .. "and %d of ten buttons are reachable, not 708 and 10",
         todayN, todayB)
      ok(gatedN == 708 and gatedB == 10,
         "with the gates enforced and the buttons usable, %d cells and %d "
         .. "buttons are reachable, not 708 and 10 -- the gym must stay "
         .. "finishable", gatedN, gatedB)
      ok(lockedN == 57,
         "with 0x59 blocked as well, %d cells are reachable, not 57", lockedN)
      ok(lockedB == 0,
         "with 0x59 blocked, %d of the ten buttons are reachable; the point of "
         .. "this measurement is that it is NONE -- no button means no way to "
         .. "change the level, so 'dynamic means blocked' is an unfinishable "
         .. "gym rather than a harder one", lockedB)
      ok(lockedN < gatedN / 10,
         "blocking 0x59 leaves %d of %d cells reachable -- not the order-of-"
         .. "magnitude collapse that makes this a lock rather than a puzzle",
         lockedN, gatedN)
      report("Pastoria from its entrance warp (13,42): %d cells today, %d with "
             .. "the gates enforced, %d if 0x59 were blocked (%d of 10 buttons)",
             todayN, gatedN, lockedN, lockedB)

      -- ...AND THE GATES ALONE CHANGE NOTHING, which is why the resolver is
      -- deferred rather than written: 708 either way once the buttons are in
      -- reach, and 686 before one is pressed.
      ok(noPressN == 686,
         "with the gates enforced and no button pressed %d cells are "
         .. "reachable, not 686", noPressN)
      ok(gatedN == todayN,
         "enforcing the gates changed the reachable set (%d vs %d); if that is "
         .. "now true the gates are worth implementing on their own and this "
         .. "pass's reason for deferring them has stopped holding",
         gatedN, todayN)
      ok(noPressN < todayN,
         "the gates do not even cost a cell before a button is pressed (%d = "
         .. "%d), so they are not gating anything and this measurement has "
         .. "stopped meaning what it says", noPressN, todayN)
      report("the H/M/L gates are a %d-cell detour at the initial level and "
             .. "cost nothing once the buttons are reachable; the puzzle is "
             .. "the height arithmetic, not the gates", todayN - noPressN)
    end
  end

  -- THE SIX TRAM SITES, AND WHAT THEY COMPARE AGAINST.  The literal 6 in the
  -- script is the whole reason this module answers 5 and 6, so it is read out
  -- of the cartridge rather than trusted.
  local arc = rom and Narc.parse(rom:read("/fielddata/script/scr_seq.narc"))
  if not arc then
    skip("no scr_seq.narc, so the tram's own script is not read")
  else
    local sites, compared, followed = 0, 0, 0
    for m = 0, arc.count - 1 do
      local bytes = arc:get(m)
      if bytes and #bytes >= 6 then
        local queue, seen, done = {}, {}, {}
        for _, at in ipairs(Script.entries(bytes)) do
          if not seen[at] then seen[at] = true; queue[#queue + 1] = at end
        end
        local i = 1
        while i <= #queue do
          local at = queue[i]; i = i + 1
          local ops = Script.decode(bytes, at)
          for k, op in ipairs(ops) do
            if op.target and not seen[op.target] then
              seen[op.target] = true; queue[#queue + 1] = op.target
            end
            if op.name == "checkgreatmarshtramlocation" and not done[op.at] then
              done[op.at] = true
              sites = sites + 1
              local destVar = op.args and op.args[2]
              for j = k + 1, math.min(k + 3, #ops) do
                if ops[j].name == "comparevartovalue"
                   and ops[j].args and ops[j].args[1] == destVar
                   and ops[j].args[2] == M.MARSH_NOT_AT_LOCATION then
                  compared = compared + 1
                end
                if ops[j].name == "callif" then followed = followed + 1 end
              end
            end
          end
        end
      end
    end
    ok(sites == 6, "the cartridge has %d checkgreatmarshtramlocation sites, "
       .. "not six", sites)
    ok(compared == 6,
       "%d of the %d sites compare their destination var against %d; if this "
       .. "is not all of them the two answers are not what the script tests",
       compared, sites, M.MARSH_NOT_AT_LOCATION)
    ok(followed == 6,
       "%d of the %d sites branch after the compare; a compare nothing acts "
       .. "on would make the answer cosmetic", followed, sites)
    report("all %d tram sites compare against NOT_AT_LOCATION (%d) and branch "
           .. "on it", sites, M.MARSH_NOT_AT_LOCATION)
  end
end

io.write(("\n%d checks, %d failed, %d reported, %d skipped\n")
           :format(checks, fails, reports, skips))
os.exit(fails > 0 and 1 or 0)
