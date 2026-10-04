-- Cartridge-specific wild initialization. Gold/Silver's sleep assignment is
-- not limited to Headbutt; Crystal added that guard and expanded the lists.
local Wild = {}
local times = {MORN="morn",MORNING="morn",DAY="day",NITE="nite",NIGHT="nite"}

function Wild.initialize(battle, opts)
  if not require("src.pokemon.Gen2Breeding").isVanilla() then return end
  local rules = battle.data.field and battle.data.field.gen2TreeMons
  if not rules then return end
  opts = opts or {}
  local ow = battle.game.overworld
  local tod = opts.timeOfDay or (ow and ow.timeOfDay and ow:timeOfDay())
    or require("src.world.OverworldController").clockTimeOfDay()
  local list = rules.sleeping and rules.sleeping[times[tod] or "day"]
  if (opts.tree or not rules.sleepOnlyTrees) and list and list[battle.enemy.mon.species]
     and (rules.sleepTurns or 0) > 0 then
    battle.enemy.mon.status = "SLP"
    battle.enemy.sleepTurns = rules.sleepTurns
    battle.silentEnemyIntro = opts.tree and rules.silentSleepingTrees or false
  end
end

return Wild
