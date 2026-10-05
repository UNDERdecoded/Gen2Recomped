-- PLATINUM'S SHARD MOVE TUTORS, the data half (pokeplatinum
-- src/overlay005/scrcmd_move_tutor.c).
--
-- Two tables, compiled into OVERLAY 5 and read from it:
--
--   sTeachableMoves[38]  12 bytes each: u16 move, u8 red/blue/yellow/green
--                        shard cost, pad, u32 TutorLocation (0 Route 212,
--                        1 Survival Area, 2 Snowpoint City)
--   sSpeciesLearnsetsByTutor[505]   5 bytes each (38 bits, little-endian
--                        bit order within a byte): which of the 38 a moveset
--                        can learn. Movesets 1..493 are the species; 494..505
--                        the forms (Deoxys A/D/S, Wormadam Sandy/Trash,
--                        Giratina Origin, Shaymin Sky, Rotom Heat/Wash/Frost/
--                        Fan/Mow) -- MOVESET_FORM_* in constants/forms.h.
--
-- Found by content rather than by address: the first entry is Dive at 2 red,
-- 4 blue, 2 yellow on Route 212 (res/pokemon/move_tutors.json), and the masks
-- follow the move table directly.
--
-- Written to the cache module `gen4_move_tutor`.

local Gen4MoveTutor = {}

Gen4MoveTutor.OVERLAY = 5
Gen4MoveTutor.COUNT = 38
Gen4MoveTutor.STRIDE = 12
Gen4MoveTutor.MOVESETS = 505
Gen4MoveTutor.MASK_BYTES = 5
Gen4MoveTutor.SIGNATURE = string.char(0x23, 0x01, 2, 4, 2, 0)   -- Dive, 2/4/2/0

function Gen4MoveTutor.parse(ov)
  if type(ov) ~= "string" then return nil, "no overlay" end
  local at = ov:find(Gen4MoveTutor.SIGNATURE, 1, true)
  if not at then return nil, "sTeachableMoves not found in overlay 5" end
  local base = at - 1
  local function u8(o) return ov:byte(o + 1) end
  local moves = {}
  for i = 0, Gen4MoveTutor.COUNT - 1 do
    local o = base + i * Gen4MoveTutor.STRIDE
    moves[i + 1] = {
      move = u8(o) + u8(o + 1) * 256,
      red = u8(o + 2), blue = u8(o + 3), yellow = u8(o + 4), green = u8(o + 5),
      location = u8(o + 8),
    }
  end
  local masks = {}
  local mbase = base + Gen4MoveTutor.COUNT * Gen4MoveTutor.STRIDE
  for m = 1, Gen4MoveTutor.MOVESETS do
    local o = mbase + (m - 1) * Gen4MoveTutor.MASK_BYTES
    local hex = {}
    for k = 0, Gen4MoveTutor.MASK_BYTES - 1 do hex[#hex + 1] = ("%02x"):format(u8(o + k) or 0) end
    masks[m] = table.concat(hex)
  end
  return { moves = moves, masks = masks }
end

function Gen4MoveTutor.extract(rom)
  local ov = rom and rom:overlay(Gen4MoveTutor.OVERLAY)
  return Gen4MoveTutor.parse(ov)
end

-- -------------------------------------------------------------- runtime --

-- Pokemon_ReadMovesetMaskByte's form arms: the moveset a mon learns from.
local FORM_MOVESETS = {
  [386] = { [1] = 494, [2] = 495, [3] = 496 },          -- Deoxys
  [413] = { [1] = 497, [2] = 498 },                     -- Wormadam
  [487] = { [1] = 499 },                                -- Giratina
  [492] = { [1] = 500 },                                -- Shaymin
  [479] = { [1] = 501, [2] = 502, [3] = 503, [4] = 504, [5] = 505 },  -- Rotom
}

function Gen4MoveTutor.moveset(mon)
  local species = tonumber(mon and mon.species) or 0
  local form = tonumber(mon and mon.form) or 0
  local f = FORM_MOVESETS[species]
  return (f and f[form]) or species
end

-- Can moveset `m` learn tutor move number `i` (1-based)?
function Gen4MoveTutor.canLearn(rec, m, i)
  local hex = rec and rec.masks and rec.masks[m]
  if not hex then return false end
  local byteIndex = math.floor((i - 1) / 8)
  local bit = (i - 1) % 8
  local b = tonumber(hex:sub(byteIndex * 2 + 1, byteIndex * 2 + 2), 16) or 0
  return math.floor(b / 2 ^ bit) % 2 == 1
end

local function knows(mon, move)
  for _, mv in ipairs((mon and mon.moves) or {}) do
    local id = type(mv) == "table" and (mv.id or mv.move) or mv
    if tonumber(id) == move then return true end
  end
  return false
end

-- The moves this mon could learn HERE and does not know, in table order
-- (ScrCmd_ShowMoveTutorMoveSelectionMenu); with no mon, every move here.
function Gen4MoveTutor.learnable(rec, mon, location)
  local out = {}
  if not rec then return out end
  local m = mon and Gen4MoveTutor.moveset(mon)
  for i, row in ipairs(rec.moves) do
    if row.location == location then
      if not mon or (Gen4MoveTutor.canLearn(rec, m, i) and not knows(mon, row.move)) then
        out[#out + 1] = row.move
      end
    end
  end
  return out
end

function Gen4MoveTutor.row(rec, move)
  for _, row in ipairs((rec and rec.moves) or {}) do
    if row.move == move then return row end
  end
  return nil
end

Gen4MoveTutor.SHARDS = { red = 72, blue = 73, yellow = 74, green = 75 }

return Gen4MoveTutor
