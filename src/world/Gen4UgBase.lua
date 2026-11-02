-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially.  Cartridge-derived data is excluded and is not the
-- copyright holder's to license.
-- THE PLAYER'S SECRET BASE, single player (pokeplatinum
-- src/underground/secret_bases.c, base_decoration.c, pc.c, records.c;
-- src/underground.c "UG"; include/underground.h, include/underground/*.h).
--
-- READ FROM CODE:
--   * THE SAVE (underground.h 55-63): 15 placed goods {x, z, good}, 16
--     boulders {x, z}, the entrance x / z / direction, active; the base
--     record; goods on display stay in the PC (placedGoodSlots, UG 457-498).
--     Index space (UG 1014-1095): 0 the PC at (15, 12), its good the flag
--     rank's PC; 1..15 the goods; 16..31 the boulders (the 2 x 2 Big Boulder).
--   * FLAG RANK (UG 24-28, 1097-1188) from the flags captured -- 0 offline,
--     so Normal: 10 goods, all 16 boulders unremovable, no USE RADAR.
--   * THE DIGGER DRILL (secret_bases.c 1789-1987, 2188-2244): the tile in
--     front and its two side neighbours must all be wall; inside the base
--     area 74, on the entrance 54; common 33 "The Digger Drill was used!",
--     30 frames, 34 "Discovered a small cavern!", 35 / 36 YES/NO, NO -> 56.
--     YES: the drill goes, FLAG_CREATED_SECRET_BASE (0x971), the base is
--     cleared but its record kept, every PC good taken off display, 16
--     boulders at x {10,12,16,18,20} x z {12..22 step 2} without repeats and
--     never (16,12), the entrance facing back at the player; then the player
--     is put in the CLOSED base at (15,23) facing north, and 68.
--   * ENTERING: walking into the entrance (comm_player_manager.c 780 ->
--     SecretBases_CheckForEnterExit 791-872): 41 YES/NO, then 37 with 38
--     "Leave door open" / 39 "Close and decorate". LEAVING: walking onto
--     (15,24): 50 (47 closed) YES/NO; out on the tile in front of the
--     entrance, facing away from it (766-787).
--   * THE ROOM is real map tiles: the Underground matrix's top rows are
--     32 x 32 rooms (map_matrix_002), the player's own base cell (1,0) --
--     x 32..63, z 0..31 (331-343); play area x 10..21, z 12..23; the PC,
--     goods and boulders collide by code (SecretBases_CalculateBaseCollision
--     486-524: each good's 3 x 3 mask at its x, z).
--   * goods are drawn as the Underground area's map props: model = area_build
--     set 2 entry [good] (overlay005/area_data.c), at (x + w/2, z + d/2)
--     (secret_base_props.c 30-52); the entrance is the prop
--     secret_base_entrance_<dir> (map_prop_models 429..432, N S W E).
--   * placed traps show their floor texture to the owner (traps.c 2264-2272:
--     field_effects ug_trap_<name>, member 25 + trap id).
-- INFERRED: the base's room is always cell (1,0) here (the cartridge uses
-- cell (0,0) while the door is closed -- the same 32 x 32 room).

local M = {}

M.ROOM_X, M.ROOM_Z = 32, 0
M.PLAY = { x0 = 10, z0 = 12, x1 = 21, z1 = 23 }
M.PC_X, M.PC_Z = 15, 12
M.EXIT_X, M.EXIT_Z = 15, 24
M.ARRIVE_X, M.ARRIVE_Z = 15, 23
M.DEFAULT_GOOD_X, M.DEFAULT_GOOD_Z = 16, 13
M.FLAG_CREATED, M.FLAG_DECORATED = 0x971, 0x972
M.BOULDER = 6
M.MAX_GOODS = 15
M.GOOD_LIMIT = { [0] = 10, 12, 15, 15, 15 }
M.UNREMOVABLE = { [0] = 16, 15, 11, 6, 0 }
M.ENTRANCE_MODEL = { up = 429, down = 430, left = 431, right = 432 }
M.TRAP_TEXTURE_BASE = 25

-- goods.c sGoodData: { width, depth, 3x3 collision rows } by good id
M.SHAPES = {
  [0] = { 0, 0, "000000000" },
  [1] = { 2, 1, "110000000" },
  [2] = { 2, 1, "110000000" },
  [3] = { 2, 1, "110000000" },
  [4] = { 2, 1, "110000000" },
  [5] = { 2, 1, "110000000" },
  [6] = { 2, 2, "110110000" },
  [7] = { 1, 1, "000000000" },
  [8] = { 1, 1, "000000000" },
  [9] = { 1, 1, "000000000" },
  [10] = { 3, 3, "111111111" },
  [11] = { 2, 2, "110110000" },
  [12] = { 1, 1, "100000000" },
  [13] = { 1, 3, "100100100" },
  [14] = { 3, 1, "111000000" },
  [15] = { 2, 2, "110110000" },
  [16] = { 2, 1, "110000000" },
  [17] = { 1, 1, "100000000" },
  [18] = { 2, 1, "110000000" },
  [19] = { 2, 1, "110000000" },
  [20] = { 2, 1, "110000000" },
  [21] = { 2, 2, "110110000" },
  [22] = { 2, 1, "110000000" },
  [23] = { 2, 1, "110000000" },
  [24] = { 2, 1, "110000000" },
  [25] = { 2, 1, "110000000" },
  [26] = { 1, 1, "100000000" },
  [27] = { 2, 1, "110000000" },
  [28] = { 3, 3, "010000010" },
  [29] = { 1, 1, "100000000" },
  [30] = { 1, 1, "100000000" },
  [31] = { 2, 2, "110110000" },
  [32] = { 2, 2, "110110000" },
  [33] = { 1, 1, "100000000" },
  [34] = { 2, 2, "110110000" },
  [35] = { 2, 2, "110110000" },
  [36] = { 1, 1, "100000000" },
  [37] = { 1, 1, "100000000" },
  [38] = { 2, 3, "110110110" },
  [39] = { 2, 2, "110110000" },
  [40] = { 1, 1, "100000000" },
  [41] = { 1, 1, "100000000" },
  [42] = { 2, 1, "110000000" },
  [43] = { 2, 1, "110000000" },
  [44] = { 2, 1, "110000000" },
  [45] = { 1, 1, "100000000" },
  [46] = { 3, 3, "111111111" },
  [47] = { 1, 2, "100100000" },
  [48] = { 3, 3, "101000101" },
  [49] = { 3, 3, "101000101" },
  [50] = { 3, 3, "101000101" },
  [51] = { 3, 3, "111000101" },
  [52] = { 3, 3, "101001101" },
  [53] = { 3, 3, "101000111" },
  [54] = { 3, 3, "101100101" },
  [55] = { 3, 3, "101000101" },
  [56] = { 1, 1, "000000000" },
  [57] = { 1, 1, "000000000" },
  [58] = { 1, 1, "000000000" },
  [59] = { 1, 1, "000000000" },
  [60] = { 1, 1, "000000000" },
  [61] = { 1, 1, "000000000" },
  [62] = { 1, 1, "000000000" },
  [63] = { 1, 1, "000000000" },
  [64] = { 1, 1, "000000000" },
  [65] = { 1, 1, "000000000" },
  [66] = { 1, 1, "000000000" },
  [67] = { 1, 1, "000000000" },
  [68] = { 1, 1, "000000000" },
  [69] = { 1, 1, "000000000" },
  [70] = { 1, 1, "000000000" },
  [71] = { 1, 1, "000000000" },
  [72] = { 1, 1, "100000000" },
  [73] = { 1, 1, "100000000" },
  [74] = { 1, 1, "100000000" },
  [75] = { 1, 1, "100000000" },
  [76] = { 1, 1, "100000000" },
  [77] = { 2, 2, "110110000" },
  [78] = { 2, 2, "110110000" },
  [79] = { 2, 2, "110110000" },
  [80] = { 2, 2, "110110000" },
  [81] = { 2, 2, "110110000" },
  [82] = { 2, 2, "110110000" },
  [83] = { 2, 2, "110110000" },
  [84] = { 2, 2, "110110000" },
  [85] = { 1, 1, "100000000" },
  [86] = { 1, 1, "100000000" },
  [87] = { 1, 1, "100000000" },
  [88] = { 1, 1, "100000000" },
  [89] = { 2, 2, "110110000" },
  [90] = { 2, 2, "110110000" },
  [91] = { 2, 2, "110110000" },
  [92] = { 1, 1, "100000000" },
  [93] = { 1, 1, "100000000" },
  [94] = { 1, 1, "100000000" },
  [95] = { 1, 1, "100000000" },
  [96] = { 1, 1, "100000000" },
  [97] = { 1, 1, "100000000" },
  [98] = { 1, 1, "100000000" },
  [99] = { 1, 1, "100000000" },
  [100] = { 1, 1, "100000000" },
  [101] = { 1, 1, "100000000" },
  [102] = { 1, 1, "100000000" },
  [103] = { 1, 1, "100000000" },
  [104] = { 1, 1, "100000000" },
  [105] = { 1, 1, "100000000" },
  [106] = { 1, 1, "100000000" },
  [107] = { 1, 1, "100000000" },
  [108] = { 1, 1, "100000000" },
  [109] = { 1, 1, "100000000" },
  [110] = { 1, 1, "100000000" },
  [111] = { 1, 1, "100000000" },
  [112] = { 1, 1, "100000000" },
  [113] = { 1, 1, "100000000" },
  [114] = { 1, 1, "100000000" },
  [115] = { 1, 1, "100000000" },
  [116] = { 1, 1, "100000000" },
  [117] = { 1, 1, "100000000" },
  [118] = { 1, 1, "100000000" },
  [119] = { 1, 1, "100000000" },
  [120] = { 1, 1, "100000000" },
  [121] = { 1, 1, "100000000" },
  [122] = { 1, 1, "100000000" },
  [123] = { 2, 1, "110000000" },
  [124] = { 2, 1, "110000000" },
  [125] = { 2, 1, "110000000" },
  [126] = { 1, 1, "100000000" },
  [127] = { 1, 1, "100000000" },
  [128] = { 1, 1, "100000000" },
  [129] = { 1, 1, "100000000" },
  [130] = { 1, 1, "100000000" },
  [131] = { 1, 1, "100000000" },
  [132] = { 1, 1, "100000000" },
  [133] = { 2, 1, "110000000" },
  [134] = { 1, 1, "100000000" },
  [135] = { 1, 2, "100100000" },
  [136] = { 1, 2, "100100000" },
  [137] = { 1, 2, "100100000" },
  [138] = { 3, 1, "111000000" },
}

local OPP = { up = "down", down = "up", left = "right", right = "left" }
local D = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
M.OPP, M.D = OPP, D

local function W() return require("src.world.Gen4UgWorld") end
local function UG() return require("src.world.Gen4Underground") end

function M.base(save)
  local ug = W().ug(save)
  if not ug then return nil end
  ug.base = ug.base or { active = false, goods = {}, boulders = {} }
  ug.base.goods = ug.base.goods or {}
  ug.base.boulders = ug.base.boulders or {}
  return ug.base
end

-- the Underground record (underground.h 19-35): the fields single player moves
function M.record(save)
  local ug = W().ug(save)
  ug.record = ug.record or {}
  local r = ug.record
  for _, k in ipairs({ "peopleMet", "giftsGiven", "spheresDug", "fossilsDug", "nonFossilsDug",
                       "trapHits", "trapsTriggered", "timesBaseMoved", "capturedFlags",
                       "playersHelped", "giftsReceived", "timesFlagTaken", "flagsRecovered" }) do
    r[k] = r[k] or 0
  end
  return r
end

function M.rank(save)
  local n = M.record(save).capturedFlags or 0
  if n >= 50 then return 4 elseif n >= 10 then return 3 elseif n >= 3 then return 2 elseif n >= 1 then return 1 end
  return 0
end

function M.pcGood(save) return 1 + M.rank(save) end

local function bit(shape, dx, dz)
  local s = shape and shape[3] or "000000000"
  local i = dz * 3 + dx + 1
  return s:sub(i, i) == "1"
end

-- every occupied index's rect: { kind, index, good, x, z, w, d, ref }
function M.objects(save)
  local b = M.base(save)
  local out = { { kind = "pc", index = 0, good = M.pcGood(save), x = M.PC_X, z = M.PC_Z, w = 2, d = 1 } }
  for i, g in ipairs(b.goods) do
    local s = M.SHAPES[g.good] or { 1, 1, "100000000" }
    out[#out + 1] = { kind = "good", index = i, good = g.good, x = g.x, z = g.z, w = s[1], d = s[2], ref = g }
  end
  for i, bo in ipairs(b.boulders) do
    out[#out + 1] = { kind = "boulder", index = 15 + i, good = M.BOULDER, x = bo.x, z = bo.z, w = 2, d = 2, ref = bo }
  end
  return out
end

-- the cells something stands on (SecretBases_CalculateBaseCollision)
function M.solidCells(save, skip)
  local cells = {}
  for _, o in ipairs(M.objects(save)) do
    if not (skip and o.ref == skip) then
      local s = (o.kind == "pc") and { 2, 1, "110000000" } or M.SHAPES[o.good] or { 1, 1, "100000000" }
      for dz = 0, 2 do for dx = 0, 2 do
        if bit(s, dx, dz) then cells[(o.z + dz) * 64 + (o.x + dx)] = { o.x + dx, o.z + dz } end
      end end
    end
  end
  return cells
end

-- what covers a local tile (PUT AWAY / MOVE GOODS)
function M.objectAt(save, x, z)
  for _, o in ipairs(M.objects(save)) do
    if x >= o.x and x < o.x + o.w and z >= o.z and z < o.z + o.d then return o end
  end
  return nil
end

function M.inside(x, z, good)
  local s = M.SHAPES[good] or { 1, 1 }
  return x >= M.PLAY.x0 and z >= M.PLAY.z0 and x + s[1] - 1 <= M.PLAY.x1 and z + s[2] - 1 <= M.PLAY.z1
end

-- BaseDecoration CanPlaceGood (base_decoration.c 997-1020): the whole rect
-- inside, on nothing else, off the PC's front (15..16, 13) and the exit's
-- front (15, 23)
function M.canPlace(save, good, x, z, ignore)
  local s = M.SHAPES[good] or { 1, 1 }
  local w, d = s[1], s[2]
  if not M.inside(x, z, good) then return false end
  for _, o in ipairs(M.objects(save)) do
    if o.ref == nil or o.ref ~= ignore then
      if x < o.x + o.w and o.x < x + w and z < o.z + o.d and o.z < z + d then return false end
    end
  end
  for xx = x, x + w - 1 do for zz = z, z + d - 1 do
    if zz == 13 and (xx == 15 or xx == 16) then return false end
    if zz == 23 and xx == 15 then return false end
  end end
  return true
end

-- PC slot -> the good displaying it
function M.displayed(save)
  local out = {}
  for _, g in ipairs(M.base(save).goods) do if g.pcSlot then out[g.pcSlot] = g end end
  return out
end

function M.bump(save) local b = M.base(save); b.version = (b.version or 0) + 1 end

function M.placeGood(save, pcSlot, x, z)
  local good = UG().goodsPC(save)[pcSlot]
  local b = M.base(save)
  if not good or #b.goods >= M.MAX_GOODS then return false end
  b.goods[#b.goods + 1] = { x = x, z = z, good = good, pcSlot = pcSlot }
  M.bump(save)
  return true
end

function M.removeObject(save, o)
  local b = M.base(save)
  local list = (o.kind == "boulder") and b.boulders or b.goods
  for i, v in ipairs(list) do if v == o.ref then table.remove(list, i) break end end
  M.bump(save)
end

-- a PC slot leaves the PC (RECEIVE GOODS): the others' slots shift down
-- (Underground_RemoveGoodPC, UG 414-455)
function M.pcRemoved(save, slot)
  for _, g in ipairs(M.base(save).goods) do
    if g.pcSlot and g.pcSlot > slot then g.pcSlot = g.pcSlot - 1 end
  end
end

-- SecretBases_CreateBase
function M.create(save, x, z, dir, rand)
  rand = rand or function(n) return math.random(0, n - 1) end
  local b = M.base(save)
  local moving = b.active
  b.goods, b.boulders = {}, {}
  local COLS = { [0] = 10, 12, 16, 18, 20 }
  local seen = { ["16,12"] = true }
  while #b.boulders < 16 do
    local bx, bz = COLS[rand(5)], rand(6) * 2 + 12
    local key = bx .. "," .. bz
    if not seen[key] then seen[key] = true; b.boulders[#b.boulders + 1] = { x = bx, z = bz } end
  end
  b.entranceX, b.entranceZ, b.entranceDir = x, z, dir
  b.active = true
  b.closed = true
  M.bump(save)
  W().setFlag(save, M.FLAG_CREATED)
  if moving then M.record(save).timesBaseMoved = M.record(save).timesBaseMoved + 1 end
  return moving
end

-- SecretBases_ProcessBaseCreateRequest: nil when it may be drilled, else the
-- refusal (common bank)
function M.drillRefusal(save, map, x, z, facing)
  local Spots = require("src.world.Gen4MiningSpots")
  local b = M.base(save)
  if b.active and b.entranceX == x and b.entranceZ == z then return 54 end
  if Spots.inSecretBase(x, z) then return 74 end
  local sx, sz = 1, 0
  if facing == "left" or facing == "right" then sx, sz = 0, 1 end
  for _, c in ipairs({ { x, z }, { x - sx, z - sz }, { x + sx, z + sz } }) do
    if not Spots.isSolid(map, c[1], c[2]) then return 54 end
  end
  return nil
end

function M.inRoom(ow)
  local p = ow and ow.player
  if not (p and require("src.world.Gen4Underground").isUnderground(ow)) then return false end
  return p.cellY >= M.ROOM_Z and p.cellY < M.ROOM_Z + 32 and p.cellX >= M.ROOM_X and p.cellX < M.ROOM_X + 32
end

function M.localOf(x, z) return x - M.ROOM_X, z - M.ROOM_Z end

-- ------------------------------------------------------------- the field --

-- the room's collision and the props, rebuilt when the base or the map changes
function M.apply(Game, ow)
  local save = Game.save
  local map = ow and ow.map
  if not (save and map and map.def) then return end
  local b = M.base(save)
  local held = ow.ugBaseHeld
  local key = tostring(map) .. ":" .. tostring(b.version or 0) .. ":" .. tostring(b.active) .. ":" ..
              #W().placedTraps(save) .. ":" .. tostring(W().ug(save).trapsVersion or 0) .. ":" ..
              tostring(held and (held.v or 0)) .. ":" ..
              tostring(ow.ugDrillHole and (ow.ugDrillHole.x .. "," .. ow.ugDrillHole.z) or "")
  -- a reload of the same map instance drops its patches (Map resets
  -- blockPatch on load): then everything is applied again
  local first = ow.ugBasePatched and ow.ugBasePatched[1]
  if first and map.patchedImpassable and not map:patchedImpassable(first[1], first[2]) then ow.ugBaseKey = nil end
  if ow.ugBaseKey == key then return end
  ow.ugBaseKey = key
  for _, c in ipairs(ow.ugBasePatched or {}) do pcall(map.clearBlock, map, c[1], c[2]) end
  ow.ugBasePatched = {}
  if b.active then
    local cells = M.solidCells(save, held and held.ref)
    -- the exit tile too: stepping onto it is the "Exit the Secret Base?"
    -- question (SecretBases_CheckForEnterExit), never a step
    cells.exit = { M.EXIT_X, M.EXIT_Z }
    for _, c in pairs(cells) do
      local mx, mz = M.ROOM_X + c[1], M.ROOM_Z + c[2]
      pcall(map.setBlock, map, mx, mz, 255, true)
      ow.ugBasePatched[#ow.ugBasePatched + 1] = { mx, mz }
    end
  end
  local def = map.def
  local props = {}
  for _, p in ipairs(def.gen4RuntimeProps or {}) do if not p.ugBase then props[#props + 1] = p end end
  local set = ((Game.data.gen4_mapprops or {}).sets or {})[2]
  local list = set and set.props or {}
  local ground = map.renderer and map.renderer.gen4Ground
  local function height(cx, cz)
    local y = ground and ground.heightAt and ground:heightAt(cx, cz) or 0
    return tonumber(y) or 0
  end
  if b.active then
    for _, o in ipairs(M.objects(save)) do
      local model = list[o.good]
      local moving = held and held.ref ~= nil and held.ref == o.ref
      if model and not moving then
        local mx, mz = M.ROOM_X + o.x, M.ROOM_Z + o.z
        local live = held and held.blink ~= nil and held.blink == o.ref and held.live or nil
        props[#props + 1] = { model = model, ugBase = true, live = live,
          x = (mx + o.w / 2) * 16, y = height(mx, mz), z = (mz + o.d / 2) * 16 }
      end
    end
    if held and held.good and list[held.good] then
      local s = M.SHAPES[held.good] or { 1, 1 }
      local mx, mz = M.ROOM_X + held.x, M.ROOM_Z + held.z
      props[#props + 1] = { model = list[held.good], ugBase = true, live = held.live,
        x = (mx + s[1] / 2) * 16, y = height(mx, mz), z = (mz + s[2] / 2) * 16 }
    end
    local em = M.ENTRANCE_MODEL[b.entranceDir or "down"]
    if em and b.entranceX then
      props[#props + 1] = { model = em, ugBase = true,
        x = b.entranceX * 16 + 8, y = height(b.entranceX, b.entranceZ), z = b.entranceZ * 16 + 8 }
    end
  end
  -- the hole the drill has just opened, before YES / NO (DRILL_STATE_CREATE_ENTRANCE)
  local hole = ow.ugDrillHole
  if hole and M.ENTRANCE_MODEL[hole.dir] then
    props[#props + 1] = { model = M.ENTRANCE_MODEL[hole.dir], ugBase = true,
      x = hole.x * 16 + 8, y = height(hole.x, hole.z), z = hole.z * 16 + 8 }
  end
  for _, t in ipairs(W().placedTraps(save)) do
    props[#props + 1] = { model = M.TRAP_TEXTURE_BASE + t.id, archive = "fldeff", ugBase = true,
      x = t.x * 16 + 8, y = height(t.x, t.z), z = t.z * 16 + 8 }
  end
  def.gen4RuntimeProps = props
end

-- walking into something (comm_player_manager.c 780): the entrance, or the
-- room's exit tile. Answers true when it took the step.
function M.bumped(Game, ow, dir)
  local save = Game.save
  local b = M.base(save)
  local p = ow.player
  if not (b.active and p and D[dir]) then return false end
  local tx, tz = p.cellX + D[dir][1], p.cellY + D[dir][2]
  local UI = require("src.ui.Gen4UgBaseUI")
  if tx == b.entranceX and tz == b.entranceZ then
    UI.enterPrompt(Game, ow)
    return true
  end
  local lx, lz = M.localOf(tx, tz)
  if M.inRoom(ow) and lx == M.EXIT_X and lz == M.EXIT_Z then
    UI.exitPrompt(Game, ow)
    return true
  end
  return false
end

function M.enter(Game, ow, closed)
  local b = M.base(Game.save)
  b.closed = closed and true or false
  pcall(require("src.core.Sound").play, Game.data, "SEQ_SE_DP_KAIDAN2")
  -- the top screen's radar: none in a closed base (secret_bases.c 1745-1749)
  pcall(function() require("src.ui.Gen4UgTopScreen").setRadar(Game, b.closed and "none" or "normal") end)
  ow:startWarpTo("UG", M.ROOM_X + M.ARRIVE_X, M.ROOM_Z + M.ARRIVE_Z, "up")
end

function M.leave(Game, ow)
  local b = M.base(Game.save)
  b.closed = false
  local dir = b.entranceDir or "down"
  pcall(function() require("src.ui.Gen4UgTopScreen").setRadar(Game, "normal") end)
  pcall(require("src.core.Sound").play, Game.data, "SEQ_SE_DP_KAIDAN2")
  ow:startWarpTo("UG", b.entranceX + D[dir][1], b.entranceZ + D[dir][2], dir)
end

-- A facing the PC: from z 13, x 15 or 16, facing north (pc.c 146-178)
function M.facingPC(ow)
  local p = ow.player
  if not (p and M.inRoom(ow)) then return false end
  local lx, lz = M.localOf(p.cellX, p.cellY)
  return p.facing == "up" and lz == 13 and (lx == 15 or lx == 16)
end

-- ------------------------------------------- examining goods (records) --

-- Good_GetInteractMessageID (goods.c): the goods with something written on
-- them -> the records bank entry (UndergroundRecords_Text_SomethingWritten*)
M.INTERACT = {
  [16] = 37, [17] = 37, [18] = 36, [19] = 38, [20] = 34, [21] = 41, [22] = 40,
  [25] = 32, [29] = 39, [30] = 44, [31] = 44, [32] = 44, [38] = 45, [39] = 43,
  [40] = 42, [41] = 32, [46] = 33, [47] = 35,
}
-- records.c sGetRecordEntryFuncs, by entry - 32
M.RECORD_OF = { [0] = "score", "peopleMet", "giftsGiven", "capturedFlags", "spheresDug",
  "fossilsDug", "trapHits", "trapsTriggered", "playersHelped", "giftsReceived",
  "timesFlagTaken", "flagsRecovered", "timesBaseMoved", "capturedFlags" }

-- SecretBases_GetGoodWithCollisionAtCoordinates: a placed good (not the PC,
-- not a boulder) whose collision covers the local tile
function M.goodWithCollisionAt(save, lx, lz)
  for _, g in ipairs(M.base(save).goods) do
    local dx, dz = lx - g.x, lz - g.z
    if dx >= 0 and dx <= 2 and dz >= 0 and dz <= 2 and bit(M.SHAPES[g.good], dx, dz) then return g.good end
  end
  return nil
end

function M.recordValue(save, key)
  if key == "score" then
    local score = 0
    pcall(function() score = require("src.pokemon.Gen4GameRecords").trainerScore(save) end)
    return math.min(999999, tonumber(score) or 0)
  end
  return math.min(999999, tonumber(M.record(save)[key]) or 0)
end

-- SecretBases_CheckForInteractableGood + UndergroundRecords_PrintEntryForDecoration:
-- A at a good that has a record on it. Answers true when it took the press.
function M.examine(Game, ow, fx, fy)
  local save = Game.save
  if not (save and M.base(save).active and M.inRoom(ow)) then return false end
  local lx, lz = M.localOf(fx, fy)
  local good = M.goodWithCollisionAt(save, lx, lz)
  local entry = good and M.INTERACT[good]
  if not entry then return false end
  local value = M.recordValue(save, M.RECORD_OF[entry - 32])
  local UI = require("src.ui.Gen4UgBaseUI")
  UI.say(Game, UI.txt(Game, 640, entry, { [6] = tostring(value) }))
  return true
end

-- --------------------------------------------- floor tools in the base --

-- SecretBases_GetTrapIDFromGoodID
M.TOOL_TRAP = {
  [56] = 11, [57] = 12, [58] = 18, [59] = 19, [60] = 20, [61] = 21, [62] = 22, [63] = 23,
  [64] = 24, [65] = 25, [66] = 26, [67] = 27, [68] = 28, [69] = 29, [70] = 30, [71] = 31,
}

-- SecretBases_GetPlacedGoodAtCoordinates: a placed good whose ORIGIN is the tile
function M.placedGoodAt(save, lx, lz)
  for _, g in ipairs(M.base(save).goods) do
    if g.x == lx and g.z == lz then return g.good end
  end
  return nil
end

-- SecretBases_CheckPlayerTriggeredTool (CPM 714-720): a finished step onto a
-- tool sets its trap off once (playerAffectedByTool until the effect ends);
-- the victim counts a trap triggered (traps.c 1737-1739); when it is over the
-- player steps back off it, facing where they came from (Traps_StepBackFromTool)
function M.stepTool(Game, ow)
  local save = Game.save
  local p = ow and ow.player
  if not (save and p and M.base(save).active and M.inRoom(ow)) or Game.ugToolAffected then return false end
  local lx, lz = M.localOf(p.cellX, p.cellY)
  local good = M.placedGoodAt(save, lx, lz)
  local trap = good and M.TOOL_TRAP[good]
  if not trap then return false end
  Game.ugToolAffected = true
  local dir = p.facing or "up"
  local r = M.record(save)
  r.trapsTriggered = (r.trapsTriggered or 0) + 1
  local trapX, trapZ = p.cellX, p.cellY
  Game.stack:push(require("src.ui.Gen4UgTrapScreen").new(Game, ow, trap, function()
    Game.ugToolAffected = nil
    local back = OPP[dir]
    local BASE = { up = 0, down = 1, left = 2, right = 3 }
    if ow.runner and back and ow.player and ow.player.cellX == trapX and ow.player.cellY == trapZ then
      ow.runner:run({
        { "g4_move", 255, { { action = BASE[back], count = 1 }, { action = 12 + BASE[back], count = 1 } } },
        { "g4_wait_movement" },
      }, { mapId = ow.map.id })
    end
  end))
  return true
end

-- ------------------------------------------- the drill and its smoke --

M.FX = {
  drill = { model = 91, anim = 163 },   -- ov5_021F5894.c: ug_ef_drill + its nsbtp
  smoke = { model = 58, anim = 162 },   -- ov5_021F55CC.c: ug_ef_smoke + its nsbtp
}

local function groundY(map, x, z)
  local okH, HR = pcall(require, "src.world.Gen4HeightRule")
  local list = okH and map and HR.surfaces(map, x, z) or {}
  return (#list > 0) and HR.nearest(list, 0) or 0
end

-- the effects' own clock, one engine tick a step (the field's update and,
-- under the Underground's screens, its animate both advance it)
local function clockOf(ow) return ow and ow.ugFxClock or 0 end
function M.fxTick(ow)
  if ow and ow.ugFx and #ow.ugFx > 0 then ow.ugFxClock = (ow.ugFxClock or 0) + 1 end
end

-- ov5_021F58FC: the drill, one tile in front of the player, at their height;
-- ov5_021F5634: the smoke, standing at (x * 16 + 8, 10, z * 16) and turned to
-- the camera (MTX_Rot33Angles(90, 0, 0) then the inverse camera); each one
-- plays its texture pattern once (Simple3D_HasAnimationReachedEnd)
function M.startFx(ow, kind, x, z)
  local spec = M.FX[kind]
  if not (ow and spec) then return end
  ow.ugFx = ow.ugFx or {}
  -- the drill at the player's own height (MapObject_GetPosPtr), the smoke at 10
  local p = ow.player
  local y = (kind == "smoke") and 10 or groundY(ow.map, p and p.cellX or x, p and p.cellY or z)
  local wx, wz = x * 16 + 8, (kind == "smoke") and z * 16 or z * 16 + 8
  -- The drill stays where ov5_021F58FC puts it (the wall tile's centre): it
  -- is two tiles wide, so its front half shows over the player's own tile,
  -- MEASURED (pt_underground ug5). The smoke's stated spot (the wall tile's
  -- north edge, 10 up, about 14 either way) lies 16 units behind this map's
  -- own rock face, whose depth hides all of it here; INFERRED: it is brought
  -- to the face on the player's side, where it shows.
  local walk = ow.map and ow.map.isWalkableCell and ow.map:isWalkableCell(x, z)
  if kind == "smoke" and p and not walk then
    if p.cellY > z then wz = z * 16 + 16 elseif p.cellY < z then wz = z * 16 end
    if p.cellX > x then wx = x * 16 + 16 elseif p.cellX < x then wx = x * 16 end
  end
  ow.ugFx[#ow.ugFx + 1] = { kind = kind, model = spec.model, anim = spec.anim,
    x = wx, y = y, z = wz, start = clockOf(ow) }
  M.installFx(ow)
end

-- the effects as Gen4GymFx draws them (def.gen4GymFxProvider, chained)
function M.fxList(ow, ground)
  local out = {}
  local list = ow and ow.ugFx or {}
  if #list == 0 and not (ow and ow.ugCursor) then return out end
  local GymFx = require("src.world.Gen4GymFx")
  local Clock = require("src.render.Gen4PropClock")
  local now = clockOf(ow)
  local keep = {}
  for _, e in ipairs(list) do
    local f = Clock.fieldFrame(now - (e.start or now))
    if f < GymFx.frames(e.anim) then
      keep[#keep + 1] = e
      local rot
      if e.kind == "smoke" then
        local pitch = 90
        local cam = ground and ground.camera
        pitch = tonumber(ground and (ground.viewPitch or (cam and cam.pitch))) or pitch
        -- MTX_Rot33Angles(90, 0, 0) then the inverse camera: the quad faces
        -- the view, which looks down at the camera's pitch
        rot = { 90 - pitch, 0, 0 }
      end
      out[#out + 1] = { member = e.model, x = e.x, y = e.y, z = e.z, rot = rot,
                        anims = { { member = e.anim, frame = f } } }
    end
  end
  if ow then ow.ugFx = keep end
  -- the decoration cursor (DecorateCursor, base_decoration.c 1222-1257):
  -- data/ug_base_cur.nsbmd at (x * 16 + 8, 1, z * 16 + 8), unrotated
  local cur = ow and ow.ugCursor
  local model = cur and M.cursorModel(ground)
  if model then
    out[#out + 1] = { model = model, x = (M.ROOM_X + cur.x) * 16 + 8, y = 1, z = (M.ROOM_Z + cur.z) * 16 + 8 }
  end
  return out
end

-- the cursor's model, built once per ground from gen4_ug_top_art's `cursor`
-- (Gen4UgTopArt); nil on a cache without it (the sparkle stands in)
function M.cursorModel(ground)
  local G = package.loaded["src.core.Game"]
  local art = G and G.data and G.data.gen4_ug_top_art
  local rec = art and art.cursor
  if not (rec and ground) then return nil end
  if ground.ugCursorModel ~= nil then return ground.ugCursorModel or nil end
  local copy = { name = rec.name, posScale = rec.posScale, scalingRule = rec.scalingRule, bounds = rec.bounds,
                 nodes = rec.nodes, ops = rec.ops, shade = ground.shade, fog = ground.fog, shapes = {} }
  for i, sh in ipairs(rec.shapes or {}) do
    local c = {}
    for k, v in pairs(sh) do c[k] = v end
    local sprite = sh.imageKey and art.sprites and art.sprites[sh.imageKey]
    c.image = sprite and sprite.path or nil
    c.index = sh.index or (i - 1)
    copy.shapes[i] = c
  end
  local ok, model = pcall(require("src.render.Gen4Model").new, copy)
  ground.ugCursorModel = ok and model or false
  return ground.ugCursorModel or nil
end

function M.setCursor(ow, x, z)
  if not ow then return end
  ow.ugCursor = x and { x = x, z = z } or nil
  if x then M.installFx(ow) end
end

function M.installFx(ow)
  local def = ow and ow.map and ow.map.def
  if not def or def.ugFxInstalled == def.gen4GymFxProvider and def.gen4GymFxProvider then return end
  local prev = def.gen4GymFxProvider
  local mine = function(o, ground)
    local out = M.fxList(o or ow, ground)
    if prev then
      local ok, more = pcall(prev, o, ground)
      if ok then for _, e in ipairs(more or {}) do out[#out + 1] = e end end
    end
    return out
  end
  def.gen4GymFxProvider = mine
  def.ugFxInstalled = mine
end

return M
