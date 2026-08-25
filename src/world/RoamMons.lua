-- Roaming legendaries: whether one steps out in front of you.
--
-- Gen2Commands already owns where the beasts ARE -- InitRoamMons plants them
-- and UpdateRoamMons hops them from route to route -- and the Pokegear map
-- draws that. What was never here is the other half: the check that turns an
-- ordinary step in the grass into a beast. Without it the whole feature is a
-- marker on a map. You can stand on Route 42 with Raikou's icon sitting on
-- Route 42 and walk for an hour, and nothing can happen, because nothing in
-- the encounter path ever reads save.g2Roam.
--
-- This is CheckEncounterRoamMon (engine/overworld/wildmons.asm), which the
-- cartridge calls from inside ChooseWildEncounter:
--
--     ChooseWildEncounter:
--         call LoadWildMonDataPointer
--         jp nc, .nowildbattle          ; this map has no wild table
--         call CheckEncounterRoamMon
--         jp c, .startwildbattle        ; a beast, already staged
--         ...                           ; otherwise the normal slot roll
--
-- and CheckEncounterRoamMon itself:
--
--     push hl
--     call CheckOnWater
--     jr z, .DontEncounterRoamMon       ; never while surfing
--     call CopyCurrMapDE
--     call Random
--     cp 100                            ; 100/256
--     jr nc, .DontEncounterRoamMon
--     and %00000011                     ; three quarters of that
--     jr z, .DontEncounterRoamMon       ; -> 75/256, about 29.3%
--     dec a                             ; slot 0, 1 or 2
--     <compare THAT slot's map group + number with yours>
--
-- Two things about that are easy to get wrong and are the reason this is a
-- module rather than four lines inlined at the call site.
--
-- ONE ROLL PICKS ONE SLOT. It does not ask "is any beast here?" -- it picks a
-- slot first and only then looks at where that one is. So three beasts on
-- your map are no more likely to appear than one; each encounter is 75/256
-- to consider a beast at all and then 1/3 to consider the beast you want.
--
-- THE SLOT INDEX IS PART OF THE ODDS. Crystal's InitRoamMons fills slots 1
-- and 2 (Raikou, Entei) and leaves slot 3 as GROUP_N_A -- its Suicune is the
-- scripted Kimono chain, not a roamer -- and the cartridge still rolls 0..2
-- uniformly. A third of Crystal's roamer rolls therefore land on an empty
-- slot and come to nothing, which is real cartridge behaviour and not a bug
-- to tidy away. Reordering this list, or packing Crystal down to two slots,
-- would quietly make Crystal's beasts 50% more common than the cartridge's.

local RoamMons = {}

-- wRoamMon1/2/3, in the cartridge's order. Gold and Silver fill all three;
-- Crystal fills the first two.
local SLOTS = { "RAIKOU", "ENTEI", "SUICUNE" }
RoamMons.SLOTS = SLOTS

-- InitRoamMons: `ld a, 40 / ld [wRoamMon1Level], a` -- every beast, every
-- version.
RoamMons.LEVEL = 40

-- `cp 100` -- a is 0..255, so this passes 100 times in 256.
local ROAM_ROLL = 100

local function released(save)
  if type(save) ~= "table" then return nil end
  if not save.g2RoamReleased then return nil end
  local roam = save.g2Roam
  if type(roam) ~= "table" then return nil end
  return roam
end

-- The live entry for one beast, or nil when it is not roaming (never
-- released, already caught, retired by a version change).
function RoamMons.entry(save, name)
  local roam = released(save)
  local info = roam and roam[name]
  if type(info) ~= "table" or info.active == false then return nil end
  return info
end

-- CheckEncounterRoamMon. `mapId` is the map the player is standing on;
-- `onWater` is CheckOnWater. Returns the beast's name and its save entry, or
-- nil for "no beast this time".
--
-- `rng` takes the engine's (lo, hi) inclusive form; the cartridge's `Random`
-- is a byte, hence 0..255.
function RoamMons.check(save, mapId, onWater, rng)
  if onWater then return nil end            -- call CheckOnWater / jr z
  local roam = released(save)
  if not roam then return nil end
  if mapId == nil then return nil end
  rng = rng or (love and love.math and love.math.random) or math.random

  local a = rng(0, 255)
  if a >= ROAM_ROLL then return nil end     -- cp 100 / jr nc
  a = a % 4                                 -- and %00000011
  if a == 0 then return nil end             -- jr z
  local name = SLOTS[a]                     -- dec a, then index the slot

  local info = name and roam[name]
  if type(info) ~= "table" or info.active == false then return nil end
  -- The cartridge compares map GROUP and NUMBER; the port keys maps by id,
  -- which is the same statement. UpdateRoamMons stores the id it hopped to,
  -- so both sides of this are already normalised.
  if info.mapId ~= mapId then return nil end
  return name, info
end

-- What to hand the battle: species, level, and the HP the beast was left
-- with. `hp` of 0 or nil is InitRoamMons' "generate new stats" -- a fresh,
-- full-health beast -- which is also what a beast you have never met has.
function RoamMons.encounterFor(name, info)
  if type(info) ~= "table" then return nil end
  return {
    species = info.speciesId,
    level = tonumber(info.level) or RoamMons.LEVEL,
    roamer = name,
    roamerHP = tonumber(info.hp) or 0,
  }
end

-- Write a beast's remaining HP back after it flees, the way the cartridge
-- keeps wRoamMon1HP: chip it down over several meetings and the last one is
-- easier. Clamped so a fainted-but-not-caught beast cannot be stored at 0,
-- which would read back as "generate new stats" and heal it.
function RoamMons.remember(save, name, hp)
  local info = RoamMons.entry(save, name)
  if not info then return false end
  hp = math.floor(tonumber(hp) or 0)
  info.hp = math.max(1, hp)
  return true
end

-- Off the map for good: caught, or knocked out. The cartridge clears the
-- slot's map group to GROUP_N_A, which both stops UpdateRoamMons hopping it
-- and makes CheckEncounterRoamMon's comparison fail forever. Dropping the
-- entry is the same statement here, and it also takes the icon off the
-- Pokegear map, which is what the cartridge does too.
function RoamMons.retire(save, name)
  local roam = released(save)
  if not (roam and roam[name]) then return false end
  roam[name] = nil
  return true
end

return RoamMons
