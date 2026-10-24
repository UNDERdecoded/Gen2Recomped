-- Native party STATUS1 equality, separate from active-battler bitmask tests.
local M = {}
local STATUS = {
  PSN = 8,
  POISON = 8,
  BRN = 16,
  BURN = 16,
  FRZ = 32,
  FREEZE = 32,
  PAR = 64,
  PARALYSIS = 64,
  TOX = 128,
  TOXIC = 128,
}
local function word(mon)
  if type(mon.status) == "number" then
    return mon.status % 4294967296
  end
  local status = tostring(mon.status or ""):upper()
  if status == "SLP" or status == "SLEEP" then
    return math.floor(tonumber(mon.sleepTurns or mon.sleep) or 7) % 8
  end
  if status == "PSN" and mon._gen3Toxic then
    return 128
  end
  return STATUS[status] or 0
end
function M.matches(vm, which, wanted)
  local enemy = which == 1
  if require("src.core.GameVersion").get() == "emerald" then
    local b = which == 1 and vm.user or vm.target
    enemy = b and b.position % 2 == 1
  end
  local battle = vm.battle
  local party = enemy and battle.enemyParty
    or not enemy and (battle.playerParty or battle.game and battle.game.save and battle.game.save.party)
    or {}
  for i = 1, 6 do
    local mon = party and party[i]
    local def = mon and battle.data and battle.data.pokemon and battle.data.pokemon[mon.species]
    local species = mon
      and not (mon.isBadEgg == true or mon.isBadEgg == 1)
      and (tonumber(mon.species) or tonumber(def and def.index))
    -- MON_DATA_SPECIES uses the underlying species, not the normal egg flag.
    if
      species
      and species ~= 0
      and species ~= 412
      and (tonumber(mon.hp) or 0) > 0
      and word(mon) == (tonumber(wanted) or 0) % 4294967296
    then
      return true
    end
  end
  return false
end
function M.install(ai)
  ai.OPS.if_status_in_party = function(vm, args)
    if M.matches(vm, args[1], args[2]) then
      return args[#args]
    end
  end
end
return M
