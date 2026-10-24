-- Eligibility and strict boolean verdict shared by the native GB/GBA renderers.
local Runtime = require("src.mods.Runtime")
local Version = require("src.core.GameVersion")
local M = {}
function M.caught(game, species)
  local dex = game and game.save and game.save.pokedex
  return not not (dex and ((dex.owned and dex.owned[species]) or (dex.caught and dex.caught[species])))
end
function M.visible(battle, battler)
  local gen = Version.generation()
  battler = battler or battle.enemy
  if
    gen > 3
    or not battler
    or battler.isPlayer
    or not battler.mon
    or (battle.kind ~= "wild" and battle.kind ~= "safari")
    or not M.caught(battle.game, battler.mon.species)
  then
    return false
  end
  -- Gold latches the already-caught bit when the encounter starts, then checks
  -- the active species again when drawing (e.g. after Transform).
  if gen == 2 and not battle.caughtMark then
    return false
  end
  if
    gen == 3
    and (
      battle.demo
      or battle.dudeDemo
      or battle.pokedudeDemo
      or battle.firstBattle
      or (battle.ghost and not battle.ghostUnveiled)
    )
  then
    return false
  end
  local default = gen > 1
  if not Runtime.wantsHook("battle.caught_marker_visible") then
    return default
  end
  return Runtime.call("battle.caught_marker_visible", function()
    return default
  end, battle) == true
end
-- Legacy standalone compositors can carry a partial battle fixture.
function M.forBattle(battle, battler)
  local method = battle.caughtMarkerVisible
  if type(method) == "function" then
    return method(battle, battler)
  end
  return M.visible(battle, battler)
end
-- The GBA renderer creates this element for a presented healthbox and retains
-- its verdict until that presentation changes, as in the reference engine.
function M.gbaVisible(battle, battler)
  if not battler or battler.shownStatus or (battle.isDouble and battle:isDouble()) then
    return false
  end
  local old = battler._caughtIcon
  local species = battler.mon and battler.mon.species
  if
    old
    and old.mon == battler.mon
    and old.species == species
    and old.name == battler.name
    and old.status == battler.shownStatus
  then
    return old.show
  end
  local show = M.visible(battle, battler)
  battler._caughtIcon = {
    mon = battler.mon,
    species = species,
    name = battler.name,
    status = battler.shownStatus,
    show = show,
  }
  return show
end
return M
