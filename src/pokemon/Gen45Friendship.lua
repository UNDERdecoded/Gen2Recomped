-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- GEN 4 / GEN 5 FRIENDSHIP CHANGES OUTSIDE THE WALK CYCLE.
--
-- READ FROM pokeplatinum src/pokemon.c Pokemon_UpdateFriendship and
-- pokeheartgold src/pokemon.c MonApplyFriendshipMod (identical tables):
--
--   event                      <100  <200  rest
--   LEVEL_UP (battle level)      5     3     2
--   VITAMIN (unused here)        5     3     2
--   BATTLE_ITEM                  1     1     0
--   LEAGUE (Pt only: Gym Leader / Elite Four / Champion, every party mon)
--                                3     2     1
--   LEARN_TMHM                   1     1     0
--   WALK (Gen4Friendship.lua)    1     1     1
--   FAINT (own faint, foe < 30 levels above)          -1  -1  -1
--   POISON_SURVIVE (field poison down to 1 HP)        -5  -5 -10
--   FAINT_HIGH (foe 30+ levels above)                 -5  -5 -10
--   CONTEST_WIN                  3     2     1
--
-- and a POSITIVE change gets +1 for a Luxury Ball, +1 when the egg location
-- is the current location, then x150/100 (rounded down) for a Soothe Bell
-- (HOLD_EFFECT_FRIENDSHIP_UP). Eggs are skipped. Clamped 0..255.
--
-- The ITEM path (vitamins, berries, herbs, Rare Candy -- item_use_pokemon.c
-- UpdatePokemonFriendship) uses the item's own three deltas and applies the
-- Soothe Bell FIRST, then the two +1s; at 255 a gain (and at 0 a loss) does
-- nothing.
--
-- Black / White: the same table and order (INFERRED: standard Gen 5 rules,
-- not read from code); the League bonus is not applied there.

local M = {}

M.TABLE = {
  LEVEL_UP = { 5, 3, 2 }, VITAMIN = { 5, 3, 2 }, BATTLE_ITEM = { 1, 1, 0 },
  LEAGUE = { 3, 2, 1 }, LEARN_TMHM = { 1, 1, 0 }, WALK = { 1, 1, 1 },
  FAINT = { -1, -1, -1 }, POISON_SURVIVE = { -5, -5, -10 },
  FAINT_HIGH = { -5, -5, -10 }, CONTEST_WIN = { 3, 2, 1 },
}
-- BLACK'S OWN TABLE (READ: arm9 0x0209E45C, applied by 0x0201B850 with the
-- same Luxury Ball / egg location / Soothe Bell x150/100 bonuses):
--   0 {5,4,3}  1 {0,0,0}  2 {5,4,3}  3 {2,2,1}  4 {-1,-1,-1}
--   5 {-5,-5,-10}  6 {4,3,2}  7 {1,1,0}
-- Battle (ov93 0x21BA238) raises 0 on a level-up and 4 / 5 on fainting
-- (5 with the foe far above) -- so a Gen 5 level-up is +5/+4/+3, not
-- Gen 4's +5/+3/+2. Row 3 is THE WALK: the field step (ov21 0x218AB9C)
-- counts to 128 and then gives every party mon, each on a coin flip (the
-- top bit of a random, 0x0201B7EC), row 3 = +2/+2/+1 (Gen4Friendship.step).
-- Rows 6 and 7 are a field script (ov10) and the party menu (ov91).
M.BW_TABLE = { LEVEL_UP = { 5, 4, 3 }, FAINT = { -1, -1, -1 }, FAINT_HIGH = { -5, -5, -10 },
  LEARN_TMHM = { 1, 1, 0 }, VITAMIN = { 5, 4, 3 }, WALK = { 2, 2, 1 } }
local function bwRow(event)
  local ok, GVm = pcall(require, "src.core.GameVersion")
  if ok and GVm.isGen5 and GVm.isGen5() then return M.BW_TABLE[event] end
  return nil
end

-- the engine's older reason names (Evolution.changeHappiness callers)
M.ALIAS = { LEVELUP = "LEVEL_UP", WALKING = "WALK", FAINTED = "FAINT",
  POISONFAINT = "POISON_SURVIVE", CARELESSTRAINER = "FAINT_HIGH", STRONGFOE = "FAINT_HIGH",
  LEARNMOVE = "LEARN_TMHM", GYMBATTLE = "LEAGUE", XITEM = "BATTLE_ITEM" }

M.LUXURY_BALL, M.SOOTHE_BELL, M.HATCHED = 11, 218, 120

-- Platinum's TrainerIsGymLeaderE4OrChampion (trainer class ids from
-- generated/trainer_classes.txt): Roark 62, Byron 64, Aaron 65, Bertha 66,
-- Flint 67, Lucian 68, Cynthia 69, Gardenia 74, Wake 75, Maylene 76,
-- Fantina 77, Candice 78, Volkner 79. HeartGold / SoulSilver never fire the
-- event (no MonApplyFriendshipMod(.., LEAGUE) call in pokeheartgold).
M.PT_LEAGUE_CLASSES = { [62] = true, [64] = true, [65] = true, [66] = true, [67] = true,
  [68] = true, [69] = true, [74] = true, [75] = true, [76] = true, [77] = true,
  [78] = true, [79] = true }

local function GV() return require("src.core.GameVersion") end
function M.applies()
  local ok, v = pcall(GV)
  return ok and (v.isGen4() or v.isGen5()) or false
end
local function gameData()
  local G = package.loaded["src.core.Game"]
  return G and G.data
end
local function isEgg(mon)
  return mon.isEgg or mon.egg or false
end
local function itemNum(mon)
  local v = mon and (mon.item or mon.heldItem)
  return tonumber(v) or tonumber(tostring(v or ""):match("(%d+)%s*$")) or 0
end
function M.holdsSootheBell(data, mon)
  local id = itemNum(mon)
  if id == 0 then return false end
  if id == M.SOOTHE_BELL then return true end
  local items = data and data.items
  local def = items and (items[id] or items[mon.item])
  return def ~= nil and def.holdEffect == "FRIENDSHIP_UP"
end
local function inLuxuryBall(mon)
  return tonumber(mon.ball) == M.LUXURY_BALL or mon.ball == "LUXURY_BALL"
end
-- the egg location against where the player stands, compared by location
-- name the way Gen4Friendship's walk does
function M.atEggLocation(data, mon)
  if mon.eggLocation == nil then return false end
  local G = package.loaded["src.core.Game"]
  local ow = G and G.overworld
  local def = ow and ow.map and ow.map.def
  if not (data and def) then return false end
  local rec = data.gen4_area_popup
  local function label(mapId)
    local d = data.maps and data.maps[mapId]
    local row = d and rec and rec.headers and rec.headers[tonumber(d.header) or -1]
    return row and row.text
  end
  local here = label(def.id or (ow.map and ow.map.id))
  return here ~= nil and label(mon.eggLocation) == here
end

local function tier(h) return h < 100 and 1 or (h < 200 and 2 or 3) end
M.tier = tier

-- HEARTGOLD / SOULSILVER'S MOOD (MON_DATA_MOOD, -127..127; the walking
-- Pokemon reads it, src/world/HgssFollowMon.lua). READ FROM pokeheartgold
-- src/pokemon_mood.c and its callers: level up in battle +40 (beside the
-- friendship event), a TM / HM taught +40, fainting -80 (-100 with the foe
-- 30+ levels above), field poison survived -50; an item that moves
-- friendship moves the mood by ItemIdGetMoodEffect -- Rare Candy +40,
-- vitamins +8, Energy Powder / Heal Powder -20, Energy Root -30, Revival
-- Herb -40, X items / Guard Spec. / Dire Hit +10. Eggs are skipped.
M.HGSS_MOOD = { LEVEL_UP = 40, LEARN_TMHM = 40, FAINT = -80, FAINT_HIGH = -100, POISON_SURVIVE = -50 }
M.HGSS_ITEM_MOOD = { [50] = 40, [34] = -20, [35] = -30, [36] = -20, [37] = -40,
  [45] = 8, [46] = 8, [47] = 8, [48] = 8, [49] = 8, [52] = 8 }
for id = 55, 62 do M.HGSS_ITEM_MOOD[id] = 10 end
local function isHgss()
  local ok, GV = pcall(GV)
  return ok and GV.family and GV.family() == "hgss" or false
end
function M.addMood(mon, by)
  if type(mon) ~= "table" or isEgg(mon) then return end
  local m = (tonumber(mon.hgssMood) or 0) + (tonumber(by) or 0)
  mon.hgssMood = math.max(-127, math.min(127, m))
end
-- battle_system.c: a battle item that worked moves the mood unconditionally;
-- only the X items, Guard Spec. and Dire Hit are left to it (the medicines
-- already moved it through the item path above)
function M.battleItemMood(battle, mon, itemId)
  if not isHgss() then return end
  local id = tonumber(itemId) or tonumber(tostring(itemId or ""):match("(%d+)%s*$"))
  if not (id and id >= 55 and id <= 62) then return end
  mon = mon or (battle and battle.player and battle.player.mon)
  M.addMood(mon, M.HGSS_ITEM_MOOD[id])
end

-- after an item has been used on `mon` (ApplyItemEffectOnMonMood): only an
-- item that carries a friendship step for the band the mon was in
function M.itemMood(data, mon, itemId, before, deltas)
  if not isHgss() or type(mon) ~= "table" then return end
  local by = M.HGSS_ITEM_MOOD[tonumber(itemId) or -1]
  if not by then return end
  local t = tier(tonumber(before) or tonumber(mon.happiness) or 0)
  if type(deltas) == "table" and (tonumber(deltas[t]) or 0) == 0 then return end
  M.addMood(mon, by)
end

-- Pokemon_UpdateFriendship (without the walk's coin flip). Returns the change.
function M.update(data, mon, event)
  if type(mon) ~= "table" or isEgg(mon) or not mon.species then return 0 end
  data = data or gameData()
  event = M.ALIAS[event] or event
  local row = bwRow(event) or M.TABLE[event]
  if not row then return 0 end
  local h = tonumber(mon.happiness)
  if h == nil then
    local def = data and data.pokemon and data.pokemon[mon.species]
    h = tonumber(def and (def.baseFriendship or def.friendship)) or 70
  end
  local change = row[tier(h)]
  if M.HGSS_MOOD[event] and isHgss() then M.addMood(mon, M.HGSS_MOOD[event]) end
  if change > 0 and inLuxuryBall(mon) then change = change + 1 end
  if change > 0 and M.atEggLocation(data, mon) then change = change + 1 end
  if change > 0 and M.holdsSootheBell(data, mon) then change = math.floor(change * 150 / 100) end
  local new = math.max(0, math.min(255, h + change))
  mon.happiness = new
  return new - h
end

-- UpdatePokemonFriendship (an item's delta for the mon's band)
function M.itemDelta(data, mon, change, now)
  data = data or gameData()
  now = tonumber(now) or tonumber(mon.happiness) or 0
  change = tonumber(change) or 0
  if now >= 255 and change > 0 then return now end
  if now <= 0 and change < 0 then return now end
  if change > 0 then
    if M.holdsSootheBell(data, mon) then change = math.floor(change * 150 / 100) end
    if inLuxuryBall(mon) then change = change + 1 end
    if M.atEggLocation(data, mon) then change = change + 1 end
  end
  return math.max(0, math.min(255, now + change))
end

-- the battle-faint rule (battle_script.c BattleScript_UpdateFriendship): the
-- foe's level (the higher of two in a double) 30+ above the fainting mon is
-- the large loss
function M.faint(data, mon, foeLevel)
  local own = tonumber(mon and mon.level) or 0
  foeLevel = tonumber(foeLevel) or 0
  local event = (foeLevel > own and foeLevel - own >= 30) and "FAINT_HIGH" or "FAINT"
  return M.update(data, mon, event)
end

-- battle_main.c: after a win against a Gym Leader / Elite Four / Champion
-- class, every party mon (eggs skipped) -- Platinum only
function M.leagueWin(data, save, trainerClass)
  local fam = (pcall(GV) and GV().family and GV().family()) or nil
  if fam ~= "platinum" then return false end
  if not M.PT_LEAGUE_CLASSES[tonumber(trainerClass) or -1] then return false end
  for _, mon in ipairs((save and save.party) or {}) do M.update(data, mon, "LEAGUE") end
  return true
end

-- BattleSys_New: the bonus is paid as the battle is SET UP (win or lose),
-- for either opposing trainer of a Gym Leader / Elite Four / Champion class
function M.battleEntered(battle)
  if not (battle and battle.kind == "trainer" and M.applies()) then return false end
  local save = battle.game and battle.game.save
  for _, t in ipairs({ battle.trainer or false, battle.trainerB or false }) do
    if t and M.leagueWin(battle.data, save, t.class) then return true end
  end
  return false
end

return M
