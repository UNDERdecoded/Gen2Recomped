-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- PLATINUM'S SEAL CASE: the twelve Ball Capsules (pokeplatinum
-- src/ball_seal_info.c, include/struct_defs/seal_case.h). READ FROM CODE.
--
--   SealCase { BallCapsule capsules[CAPSULE_NUM = 12]; SealCounts seals }
--   BallCapsule { BallSeal seals[SEALS_PER_CAPSULE = 8] }, BallSeal { type,
--   x, y } -- type 0 is an empty slot (SEAL_DUMMY), x / y the seal's spot on
--   the touch screen (the ball's centre is (190, 70), radius 60).
--
-- In the port: save.gen4SealCapsules[1..12] = { seals = { [1..8] = { type, x,
-- y } } } beside the loose counts save.gen4Seals (Gen4Seals), and on a
-- Pokemon mon.ballCapsule (MON_DATA_BALL_CAPSULE_ID, 1-based, 0 = none) and
-- mon.ballCapsuleSeals (MON_DATA_BALL_CAPSULE, a copy of the capsule).

local C = {}

C.CAPSULES = 12
C.SEALS = 8
C.CENTER_X, C.CENTER_Y, C.RADIUS = 190, 70, 60

local function blank()
  local seals = {}
  for i = 1, C.SEALS do seals[i] = { type = 0, x = 0, y = 0 } end
  return { seals = seals }
end
C.blank = blank

-- SealCase_GetCapsuleById (1-based here), made on first use
function C.capsule(save, i)
  save.gen4SealCapsules = save.gen4SealCapsules or {}
  local list = save.gen4SealCapsules
  i = math.floor(tonumber(i) or 1)
  if type(list[i]) ~= "table" or type(list[i].seals) ~= "table" then list[i] = blank() end
  for k = 1, C.SEALS do
    local s = list[i].seals[k]
    if type(s) ~= "table" then list[i].seals[k] = { type = 0, x = 0, y = 0 } end
  end
  return list[i]
end

-- BallCapsule_Copy
function C.copy(cap)
  local out = blank()
  for k = 1, C.SEALS do
    local s = cap and cap.seals and cap.seals[k] or {}
    out.seals[k] = { type = tonumber(s.type) or 0, x = tonumber(s.x) or 0, y = tonumber(s.y) or 0 }
  end
  return out
end

-- SealCase_CountSealOccurrenceInUse: how many of seal `id` sit on capsules
function C.inUse(save, id)
  local list = type(save) == "table" and save.gen4SealCapsules
  if type(list) ~= "table" then return 0 end
  id = tonumber(id)
  local n = 0
  for i = 1, C.CAPSULES do
    local cap = list[i]
    for k = 1, C.SEALS do
      local s = cap and cap.seals and cap.seals[k]
      if s and tonumber(s.type) == id then n = n + 1 end
    end
  end
  return n
end

-- SealIsOnCapsule
function C.onCapsule(cap, id)
  for k = 1, C.SEALS do
    local s = cap and cap.seals and cap.seals[k]
    if s and tonumber(s.type) == id then return true end
  end
  return false
end

-- CapsuleManager_AnySealsOnCapsule
function C.anySeals(cap)
  for k = 1, C.SEALS do
    local s = cap and cap.seals and cap.seals[k]
    if s and (tonumber(s.type) or 0) ~= 0 then return true end
  end
  return false
end

-- SealAnim_GetDistance (FX_Sqrt of the squared distance, truncated)
function C.distance(x1, y1, x2, y2)
  local dx, dy = x1 - x2, (y1 - y2) * -1
  return math.floor(math.sqrt(dx * dx + dy * dy))
end

-- GiveOrTakeSeal2: a seal back into the case from a capsule (the in-use
-- total alone is checked, and the count capped at 99)
function C.giveBack(save, id, q)
  local Seals = require("src.import.Gen4Seals")
  q = q or 1
  local loose = Seals.caseCount(save, id)
  if q < 0 then
    if loose + q < 0 then return false end
  elseif C.inUse(save, id) + q > Seals.MAX_PER_TYPE then
    return false
  end
  save.gen4Seals = save.gen4Seals or {}
  save.gen4Seals[id] = math.min(Seals.MAX_PER_TYPE, loose + q)
  return true
end

return C
