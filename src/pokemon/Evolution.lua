-- Evolution handling (engine/pokemon/evos_moves.asm semantics):
-- level evolutions trigger after battles once the level is reached,
-- stone evolutions on item use, and trade evolutions when a link trade
-- completes (src/link/Protocol.lua TradeSession:apply).
--
-- Method dispatch runs through the merged evolution_methods registry:
-- a record's check(game, mon, evo, trigger) answers whether that
-- evolutions[] row fires for the trigger ({ kind = "levelup" | "item" |
-- "trade" | "manual" | <mod>, item = id?, ... }), wrapped by the
-- evolution.check hook so a mod can cancel or force any evolution.

local Music = require("src.core.Music")
local Runtime = require("src.mods.Runtime")
local Screens = require("src.ui.Screens")
local Stats = require("src.pokemon.Stats")
local TextBox = require("src.render.TextBox")
local Strings = require("src.core.Strings")

local Evolution = {}

Evolution.METHODS = {
  LEVEL = {
    check = function(game, mon, evo, trigger)
      return trigger.kind == "levelup" and mon.level >= (evo.level or 0)
    end,
    describe = function(evo)
      return Strings("Level %d", evo.level or 0)
    end,
  },
  ITEM = {
    check = function(game, mon, evo, trigger)
      return trigger.kind == "item" and trigger.item == evo.item
    end,
    describe = function(evo, data)
      return (data and data.items[evo.item] or {}).name or evo.item
    end,
    consumesItem = true,
  },
  TRADE = {
    check = function(game, mon, evo, trigger)
      return trigger.kind == "trade"
    end,
    describe = function() return "Trade" end,
  },
  -- Gen2 EVOLVE_HAPPINESS (engine/pokemon/evolve.asm): the mon's happiness
  -- byte must have reached HAPPINESS_TO_EVOLVE, and TR_MORNDAY / TR_NITE
  -- additionally gate on the clock the way GSC's time-of-day bands do.
  HAPPINESS = {
    check = function(game, mon, evo, trigger)
      if trigger.kind ~= "levelup" then return false end
      if (mon.happiness or 0) < Evolution.HAPPINESS_TO_EVOLVE then
        return false
      end
      if not evo.timeOfDay then return true end
      local night = Evolution.isNight()
      if evo.timeOfDay == "NITE" then return night end
      return not night   -- TR_MORNDAY: morn or day
    end,
    describe = function(evo)
      if evo.timeOfDay == "NITE" then return Strings("Happiness (night)") end
      if evo.timeOfDay == "MORNDAY" then return Strings("Happiness (day)") end
      return Strings("Happiness")
    end,
  },
  -- Gen2 EVOLVE_STAT (TYROGUE): a level gate plus an attack/defense
  -- comparison of the mon's own current stats.
  STAT = {
    check = function(game, mon, evo, trigger)
      if trigger.kind ~= "levelup" then return false end
      if mon.level < (evo.level or 0) then return false end
      local atk = mon.stats and mon.stats.attack or 0
      local def = mon.stats and mon.stats.defense or 0
      if evo.compare == "ATK_LT_DEF" then return atk < def end
      if evo.compare == "ATK_GT_DEF" then return atk > def end
      if evo.compare == "ATK_EQ_DEF" then return atk == def end
      return false
    end,
    describe = function(evo)
      return Strings("Level %d", evo.level or 0)
    end,
  },
}

-- HAPPINESS_TO_EVOLVE / BASE_HAPPINESS (constants/pokemon_data_constants.asm)
Evolution.HAPPINESS_TO_EVOLVE = 220
Evolution.BASE_HAPPINESS = 70

-- GSC time-of-day bands (constants/time_constants.asm): MORN 4-9, DAY
-- 10-17, NITE 18-3.  The port has no in-game clock, so the wall clock is
-- what GSC's RTC would have been.
function Evolution.isNight()
  local hour = tonumber(os.date("%H")) or 12
  return hour >= 18 or hour < 4
end

-- ChangeHappiness (engine/pokemon/mon_stats.asm): the delta depends on the
-- mon's current happiness band (<100 / <200 / rest).  Only the events the
-- port can actually observe are listed.
local HAPPINESS_CHANGES = {
  LEVELUP = { 5, 3, 2 },
  WALKING = { 2, 2, 1 },
  USEDITEM = { 5, 3, 2 },
  FAINT = { -1, -1, -1 },
}

function Evolution.changeHappiness(mon, reason)
  if not mon then return end
  local row = HAPPINESS_CHANGES[reason]
  if not row then return end
  local h = mon.happiness
  if h == nil then return end   -- Gen1 mons carry no happiness byte
  local band = h < 100 and 1 or h < 200 and 2 or 3
  mon.happiness = math.max(0, math.min(255, h + row[band]))
end

function Evolution.registerInto(registry, _, owner)
  for id, record in pairs(Evolution.METHODS) do
    registry:register(id, record, owner)
  end
end

-- Single dispatch point over the merged registry, wrapped by the
-- evolution.check hook.  Returns species, evo for the first matching
-- evolutions[] row, or nil.
function Evolution.pendingFor(game, mon, trigger)
  trigger = trigger or { kind = "manual" }
  local data = game.data
  local def = data.pokemon[mon.species]
  local methods = data.evolution_methods or Evolution.METHODS
  for _, evo in ipairs(def.evolutions or {}) do
    local method = methods[evo.method]
    if method and method.check then
      local should
      if Runtime.wantsHook("evolution.check") then
        should = Runtime.call("evolution.check", function(g, m, e, t)
          return method.check(g, m, e, t)
        end, game, mon, evo, trigger)
      else
        should = method.check(game, mon, evo, trigger)
      end
      if should then return evo.species, evo end
    end
  end
  return nil
end

-- Find a pending level evolution for a mon (nil if none).  Frozen v1
-- shim: callers pass a plain data table, so it stays a hookless LEVEL
-- check; game-holding callers use pendingFor.
function Evolution.pendingLevelEvo(data, mon)
  local def = data.pokemon[mon.species]
  for _, evo in ipairs(def.evolutions) do
    if evo.method == "LEVEL" and mon.level >= evo.level then
      return evo.species
    end
  end
  return nil
end

-- Mutate the mon into the new species (stats, HP delta, dex flags).
-- via is the evolution method id when the caller knows it.
function Evolution.apply(game, mon, newSpecies, via)
  local newDef = game.data.pokemon[newSpecies]
  assert(newDef, "evolve into unknown species " .. tostring(newSpecies))
  local fromSpecies = mon.species
  local hpLost = mon.stats.hp - mon.hp
  mon.species = newSpecies
  mon.stats = Stats.calc(newDef, mon.level, mon.dvs, mon.statExp)
  mon.hp = math.max(1, mon.stats.hp - hpLost)
  if game.save.pokedex then
    game.save.pokedex.seen[newSpecies] = true
    game.save.pokedex.owned[newSpecies] = true
  end
  Runtime.emit("pokemon.evolved", {
    mon = mon, fromSpecies = fromSpecies, toSpecies = newSpecies, via = via,
  })
end

-- After the "evolved into" text, Gen1 re-runs the level-up learn check on
-- the EVOLVED species (engine/pokemon/evos_moves.asm EvolveMon calls the
-- LearnMoveFromLevelUp predef, engine/pokemon/learn_move.asm) -- a mon
-- evolving at exactly a learnset level gains that move (GYARADOS learns
-- BITE at 20, so MAGIKARP->GYARADOS @20 learns BITE, @21 does not) (#12).
-- Mirrors the rare-candy learn loop in src/ui/BagMenu.lua so a full move
-- list opens the forget prompt.  mon.species is already the new species
-- (Evolution.apply ran before the congrats text).  onDone runs once the
-- learn list is exhausted, replacing the caller's direct onDone.
function Evolution.learnEvolutionMoves(game, mon, onDone)
  local Experience = require("src.battle.Experience")
  local def = game.data.pokemon[mon.species]
  -- movesLearnedAt uses entry.level == level (exact Gen1 rule); do NOT use
  -- Pokemon.movesAtLevel (<= level), which would over-grant older moves.
  local moves = Experience.movesLearnedAt(def, mon.level)
  local i = 0
  local function nextStep()
    i = i + 1
    local moveId = moves[i]
    if not moveId then
      if onDone then onDone() end
      return
    end
    for _, mv in ipairs(mon.moves) do
      if mv.id == moveId then return nextStep() end
    end
    local mdef = game.data.moves[moveId]
    if not mdef then return nextStep() end
    local name = mon.nickname or def.name
    if #mon.moves < 4 then
      table.insert(mon.moves, { id = moveId, pp = mdef.pp })
      Runtime.emit("pokemon.move_learned", { mon = mon, moveId = moveId })
      game.stack:push(TextBox.new(game,
        Strings("%s learned\n%s!", name, mdef.name), nextStep))
    else
      -- LearnMoveFromLevelUp with a full moveset: the forget UI
      Screens.push(game, "MoveLearnMenu", mon, moveId, nextStep)
    end
  end
  nextStep()
end

-- Play the evolution movie (flashing forms), then apply + text.
-- Headless (no real graphics) falls back to the plain text flow.
function Evolution.evolve(game, mon, newSpecies, onDone, via)
  if love.image and love.image.newImageData then
    -- forward `via` so EvolutionState can keep trade evolutions
    -- non-cancelable (LINK_STATE_TRADING) while others accept B (#213)
    Screens.push(game, "EvolutionState", mon, newSpecies, onDone, via)
    return
  end
  Music.play(game.data, Music.special(game.data, "evolution"))
  local oldName = mon.nickname or game.data.pokemon[mon.species].name
  Evolution.apply(game, mon, newSpecies, via)
  local msg = Strings("What?\n%s is\nevolving!\fCongratulations!\nYour %s\nevolved into\n%s!",
                      oldName, oldName, game.data.pokemon[newSpecies].name)
  game.stack:push(TextBox.new(game, msg, function()
    Music.restoreMap(game.data)
    -- re-run the evolved species' level-up learn check before onDone
    -- (evos_moves.asm EvolveMon -> learn_move.asm LearnMoveFromLevelUp, #12)
    Evolution.learnEvolutionMoves(game, mon, onDone)
  end))
end

-- Entry point for mods whose methods fire outside the vanilla moments
-- (location or time triggers): runs pendingFor with the caller's trigger
-- and, on a match, plays the standard evolve movie.  Returns the target
-- species or nil.
function Evolution.request(game, mon, trigger, onDone)
  local species, evo = Evolution.pendingFor(game, mon, trigger)
  if not species then
    if onDone then onDone() end
    return nil
  end
  Evolution.evolve(game, mon, species, onDone, evo and evo.method)
  return species
end

-- After-battle hook: evolve mons that leveled this battle and still
-- qualify (queued one at a time, party order).  Gen1 EvolveAfterBattle
-- only considers mons that gained a level during the fight -- a B-cancel
-- means "not this time", and the next offer waits for the next level-up
-- (or Rare Candy / stone, which call Evolution.evolve directly).
-- leveledUp is a set of party mon tables; nil/empty yields no evolutions.
function Evolution.checkParty(game, onDone, leveledUp)
  local pending = {}
  if leveledUp then
    for _, mon in ipairs(game.save.party) do
      if leveledUp[mon] then
        local target, evo = Evolution.pendingFor(game, mon, { kind = "levelup" })
        if target then
          table.insert(pending, { mon = mon, to = target, via = evo and evo.method })
        end
      end
    end
  end
  local i = 0
  local function nextOne()
    i = i + 1
    local p = pending[i]
    if not p then
      if onDone then onDone() end
      return
    end
    Evolution.evolve(game, p.mon, p.to, nextOne, p.via)
  end
  nextOne()
  return #pending
end

return Evolution
