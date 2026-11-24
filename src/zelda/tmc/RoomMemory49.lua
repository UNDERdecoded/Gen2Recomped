-- Round 49: the room tracker -- killed enemies stay gone in the eight most
-- recently visited rooms (src/code_08049CD4.c, src/room.c, src/enemyUtils.c).
--
-- CARTRIDGE BEHAVIOUR:
--   * gRoomMemory[8] = { area, room, unk_02 (age), enemyBits }.
--     ClearRoomMemory (new game / continue) fills it with $FF.
--   * UpdateRoomTracker (sub_08052EA0, every room init): the room's entry if
--     it is there, else AddCurrentRoom takes the oldest entry (the largest
--     age; bits cleared); UpdateCurrentRoom ages every younger entry by 1
--     and makes this one age 0.
--   * sub_0804B058 (the room's property-2 list, loaded once TABIDACHI is
--     set): entry i < $20 of kind ENEMY is skipped when bit i is set
--     (EnemyEnableRespawn); a spawned one gets idx = i | $80.
--   * The generic death (enemyUtils.c, CreateDeathFx path) calls
--     EnemyDisableRespawn: idx & $80 -> bit (idx & $1F) set in the current
--     room's entry.
-- The port spawned list 2 afresh on every visit: an enemy beaten in a room
-- was back as soon as Link stepped out and in again (an Armos interior and
-- back, a door and back), which the cartridge does not do.
local bit = require("bit")
local band, bor, lshift, rshift = bit.band, bit.bor, bit.lshift, bit.rshift

local M = {}
M.SLOTS = 8

local function mem(f)
  if not f._roomMem then -- ClearRoomMemory
    local t = {}
    for i = 1, M.SLOTS do t[i] = { area = 0xFF, room = 0xFF, age = 0xFFFF, bits = 0xFFFFFFFF } end
    f._roomMem = t
  end
  return f._roomMem
end
M.mem = mem

local function touch(t, rm) -- UpdateCurrentRoom
  for _, r in ipairs(t) do if r.age < rm.age then r.age = r.age + 1 end end
  rm.age = 0
end

-- UpdateRoomTracker
function M.enter(f)
  local r = f.room
  if not r then return nil end
  local t = mem(f)
  for _, rm in ipairs(t) do
    if rm.area == r.area and rm.room == r.room then touch(t, rm) f._roomMemCur = rm return rm end
  end
  local rm = t[1] -- AddCurrentRoom: the oldest (first one on a tie)
  for i = 2, #t do if t[i].age > rm.age then rm = t[i] end end
  rm.area, rm.room, rm.age, rm.bits = r.area, r.room, 0xFFFF, 0
  touch(t, rm)
  f._roomMemCur = rm
  return rm
end

-- sub_0804B058 (property 2)
function M.loadList(f, list)
  if not list then return end
  local rm = f._roomMemCur
  for i, d in ipairs(list) do
    local idx = i - 1
    local tracked = idx < 0x20 and band(d.kind or 0, 0xF) == 3
    if not (tracked and rm and band(rshift(rm.bits, idx), 1) ~= 0) then
      local n0 = #f.entities
      f:loadEntityList(nil, { d })
      if tracked then
        for j = n0 + 1, #f.entities do local e = f.entities[j] if e and e.enemy then e.rmIdx = idx end end
      end
    end
  end
end

-- EnemyDisableRespawn
function M.killed(f, e)
  local rm = f._roomMemCur
  if not (rm and e.rmIdx) or e.rmMarked then return end
  e.rmMarked = true
  rm.bits = bor(rm.bits, lshift(1, band(e.rmIdx, 0x1F)))
end

return M
