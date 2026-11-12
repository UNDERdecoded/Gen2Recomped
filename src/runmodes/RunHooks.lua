-- RUN HOOKS: the engine seams the run modes ride, in one place.
--
-- The engine calls these at a handful of shared choke points (every family
-- goes through them):
--
--   BattleState.newWild      -> RunHooks.wildSpecies (randomizer), RunHooks.wildStart
--   Commands.give_pokemon    -> RunHooks.giftSpecies (starter randomizer)
--   BattleState:onFaint      -> RunHooks.fainted
--   BattleState:storeCaughtMon -> RunHooks.caught
--   BattleState:finish       -> RunHooks.battleEnd
--   OverworldState:update    -> RunHooks.tick
--
-- Every one returns at once when the save has no run modes, so a normal
-- save pays one table read.  The Nuzlocke rules themselves are the
-- NUZLOCKE mod's (mods/NUZLOCKE): it wraps the `runmodes.*` hooks /
-- listens to the `runmodes.*` events fired here.  Without the mod a
-- Nuzlocke save still loads and plays; its encounters are simply not judged.

local RunModes = require("src.runmodes.RunModes")
local Runtime = require("src.mods.Runtime")

local RunHooks = {}

-- callers that are not "a wild encounter" for the run (catch tutorials,
-- link battles, Pal Park) wrap themselves in RunHooks.quiet(fn)
local quietDepth = 0
function RunHooks.quiet(fn, ...)
  quietDepth = quietDepth + 1
  local results = { pcall(fn, ...) }
  quietDepth = quietDepth - 1
  if not results[1] then error(results[2], 0) end
  return unpack(results, 2, table.maxn(results))
end
function RunHooks.isQuiet() return quietDepth > 0 end

-- scripted single wild battles (legendaries, gifts in battle form, Snorlax)
-- run under staticDepth: not randomized, but still an encounter for the run
local staticDepth = 0
function RunHooks.static(fn, ...)
  staticDepth = staticDepth + 1
  local results = { pcall(fn, ...) }
  staticDepth = staticDepth - 1
  if not results[1] then error(results[2], 0) end
  return unpack(results, 2, table.maxn(results))
end

local function generation(game)
  local g = game and game.data and game.data.constants and tonumber(game.data.constants.gen)
  if g then return g end
  local ok, GV = pcall(require, "src.core.GameVersion")
  if ok and GV and GV.generation then
    local okG, g = pcall(GV.generation)
    if okG then return tonumber(g) end
  end
end

local function mapIdOf(game)
  local map = game and game.overworld and game.overworld.map
  return (map and map.id) or (game and game.save and game.save.player and game.save.player.map)
end
RunHooks.mapIdOf = mapIdOf

-- the Nuzlocke "area": the region-map section (Route 101 is eleven map ids
-- and one section; a cave's floors share one), else the map id
function RunHooks.area(game)
  local mapId = mapIdOf(game)
  local def = mapId ~= nil and game.data and game.data.maps and game.data.maps[mapId]
  local sec = type(def) == "table" and def.regionMapSection or nil
  if sec ~= nil and sec ~= "" then return "sec:" .. tostring(sec) end
  return "map:" .. tostring(mapId)
end

-- ------------------------------------------------------------- randomizer --
-- (species, opts) for a wild battle about to be built.  Roamers, scripted
-- statics, demos and link battles keep theirs.
function RunHooks.wildSpecies(game, species, opts)
  local save = game and game.save
  if not (save and save.runModes) then return species, opts end
  RunHooks.sync(game)
  if quietDepth > 0 then return species, opts end
  if staticDepth > 0 then
    -- a scripted static: only under GIFT & STATIC POKeMON, never a legend
    local new = RunHooks.staticSpecies(game, species, "static")
    if new ~= species and opts and opts.form ~= nil then
      local copy = {}
      for k, v in pairs(opts) do copy[k] = v end
      copy.form = nil
      opts = copy
    end
    return new, opts
  end
  if opts and (opts.roamer or opts.battleType == "roaming") then return species, opts end
  if not RunModes.on(save, "randomWild") then return species, opts end
  local Randomizer = require("src.runmodes.Randomizer")
  -- one pick per encounter: the save's counter advances (and is saved with
  -- it, so a reload replays the same sequence); never the same species twice
  -- running
  local rm = save.runModes
  local n = (tonumber(rm.wildCount) or 0) + 1
  local new = Randomizer.wild(save, game.data, species, mapIdOf(game), generation(game), n, rm.lastWild)
  rm.wildCount = n
  rm.lastWild = new
  if new ~= species and opts and opts.form ~= nil then
    local copy = {}
    for k, v in pairs(opts) do copy[k] = v end
    copy.form = nil
    opts = copy
  end
  return new, opts
end

local STARTERS = {
  [1] = { "BULBASAUR", "CHARMANDER", "SQUIRTLE" },
  [2] = { "SPECIES_152", "SPECIES_155", "SPECIES_158", "CHIKORITA", "CYNDAQUIL", "TOTODILE" },
  [3] = { "TREECKO", "TORCHIC", "MUDKIP", "BULBASAUR", "CHARMANDER", "SQUIRTLE" },
  [4] = { 387, 390, 393, 152, 155, 158 },
  [5] = { 495, 498, 501 },
}
RunHooks.STARTERS = STARTERS

-- the running game's own starter trio
function RunHooks.gameStarters(game)
  local data = game and game.data
  local pokemon = data and data.pokemon or {}
  local gen = generation(game)
  if gen == 3 and data and data.constants and data.constants.gen3Starters
     and type(data.constants.gen3Starters.species) == "table" then
    return data.constants.gen3Starters.species
  end
  local okV, GV = pcall(require, "src.core.GameVersion")
  local id = okV and GV.get and GV.get() or ""
  if id == "heartgold" or id == "soulsilver" then return { 152, 155, 158 } end
  local list = STARTERS[gen or 0] or {}
  for i = 1, #list, 3 do
    if pokemon[list[i]] ~= nil then return { list[i], list[i + 1], list[i + 2] } end
  end
  return {}
end

-- the starter set (in its own order) holding `species`, or nil
function RunHooks.starterSet(gen, species, data)
  local list = STARTERS[gen or 0]
  if gen == 3 and data and data.constants and data.constants.gen3Starters
     and type(data.constants.gen3Starters.species) == "table" then
    local own = data.constants.gen3Starters.species
    for _, s in ipairs(own) do if s == species then return own end end
  end
  if not list then return nil end
  for i, s in ipairs(list) do
    if s == species then
      local base = math.floor((i - 1) / 3) * 3
      return { list[base + 1], list[base + 2], list[base + 3] }
    end
  end
  return nil
end

local function ownsNothing(save)
  for _, m in ipairs(save.party or {}) do if m then return false end end
  return true
end

-- the species a scripted gift becomes: the FIRST mon a randomized-starters
-- save is given, when it is one of the game's starters (the rival's var and
-- the script's branches keep the original -- only the mon changes)
function RunHooks.giftSpecies(game, species, opts)
  local save = game and game.save
  if not (save and save.runModes) or (opts and opts.egg) then return species end
  RunHooks.sync(game)
  local gen = generation(game)
  local set = RunHooks.starterSet(gen, species, game.data)
  if not (set and ownsNothing(save)) then
    -- any other gift: GIFT & STATIC POKeMON (src/runmodes/RandomOptions.lua)
    return RunHooks.staticSpecies(game, species, "gift")
  end
  if not RunModes.on(save, "randomStarters") then return species end
  local new = require("src.runmodes.Randomizer").starter(save, game.data, species, set, gen)
  if new ~= species then save.runModes.starterFrom = species; save.runModes.starter = new end
  return new
end

-- the evolution line from `species`: { species, stage 2, stage 3 } (first
-- branch; every dataset's spelling of the target)
local function chain(pokemon, species)
  local out, seen = { species }, { [species] = true }
  local cur = species
  for _ = 1, 3 do
    local rec = pokemon[cur]
    local evo = type(rec) == "table" and type(rec.evolutions) == "table" and rec.evolutions[1]
    local nextSp = type(evo) == "table" and (evo.species or evo.target or evo.into) or nil
    if nextSp == nil or nextSp == 0 or pokemon[nextSp] == nil or seen[nextSp] then break end
    out[#out + 1] = nextSp
    seen[nextSp] = true
    cur = nextSp
  end
  return out
end
RunHooks._chain = chain

-- original starter-line species -> its randomized counterpart (by stage),
-- for a randomized-starters save; nil when nothing maps
local lineCache = setmetatable({}, { __mode = "k" })
function RunHooks.starterLines(game)
  local save = game and game.save
  if not (save and save.runModes and RunModes.on(save, "randomStarters")) then return nil end
  local data = game.data
  local pokemon = data and data.pokemon
  if not pokemon then return nil end
  local key = tostring(save.runModes.seed)
  local hit = lineCache[save]
  if hit and hit.key == key and hit.data == data then return hit.map end
  local gen = generation(game)
  local Randomizer = require("src.runmodes.Randomizer")
  local map = {}
  local sets = { RunHooks.gameStarters(game) }
  for _, set in ipairs(sets) do
    if pokemon[set[1]] ~= nil then
      for _, original in ipairs(set) do
        if map[original] == nil and pokemon[original] ~= nil then
          local new = Randomizer.starter(save, data, original, set, gen)
          if new ~= original then
            local a, b = chain(pokemon, original), chain(pokemon, new)
            for i, sp in ipairs(a) do
              if map[sp] == nil then map[sp] = b[math.min(i, #b)] end
            end
          end
        end
      end
    end
  end
  lineCache[save] = { key = key, data = data, map = map }
  return map
end

-- a trainer's party under randomized starters: the rival (and anyone else
-- carrying a starter line) brings the randomized counterpart, evolved to
-- the same stage -- so the rival still counters the player's pick.
function RunHooks.trainerParty(game, party, oppClass, partyIndex)
  if type(party) ~= "table" then return party end
  local save = game and game.save
  if save and save.runModes then RunHooks.sync(game) end
  local map = RunHooks.starterLines(game)
  local RandomOptions = require("src.runmodes.RandomOptions")
  local facility = RunHooks.facilityClass(oppClass)
  local teams = not facility and RandomOptions.on(save, "trainerTeams")
  local moves = not facility and RandomOptions.on(save, "startMoves")
  local held = not facility and RandomOptions.on(save, "heldItems") and (generation(game) or 1) >= 2
  if (not map or next(map) == nil) and not teams and not moves and not held then return party end
  map = map or {}
  local Pokemon = require("src.pokemon.Pokemon")
  local key = tostring(oppClass) .. "#" .. tostring(partyIndex or 1)
  for i, mon in ipairs(party) do
    local to = type(mon) == "table" and map[mon.species]
    if to == nil and teams and type(mon) == "table" then
      to = RunHooks.trainerSpecies(game, mon.species, key, i)
      if to == mon.species then to = nil end
    end
    if to ~= nil then
      local ok, fresh = pcall(Pokemon.new, game.data, to, mon.level)
      if ok and type(fresh) == "table" then
        fresh.item, fresh.heldItem = mon.item, mon.heldItem
        fresh.nickname = nil
        party[i] = fresh
      end
    end
    mon = party[i]
    if type(mon) == "table" then
      if moves then RunHooks.randomizeMoves(game, mon, "trainer", key, i) end
      if held then
        local RandomData = require("src.runmodes.RandomData")
        local rng = RandomData.Rng(save.runModes.seed, "trainerheld", key, i)
        if (mon.item ~= nil and mon.item ~= 0) or rng.float() < 0.3 then
          mon.item = RandomData.pickHeld(game.data, save.runModes, "trainer", key, i) or mon.item
          mon.heldItem = nil
        end
      end
    end
  end
  return party
end

-- the species a starter-select screen should SHOW for `species` (the screen
-- keeps its own choice, so the script's starter var stays vanilla)
function RunHooks.shownStarter(game, species)
  local map = RunHooks.starterLines(game)
  return (map and map[species]) or species
end

-- the species a lab SCRIPT should show / name (Gen 1 Oak's lab dex entry
-- and received text, Gen 2 Elm's pokepic and name buffer): the randomized
-- counterpart, but only while the party holds at most the starter -- the
-- choosing moment -- so later text naming a starter species is untouched
function RunHooks.introShown(game, species)
  local save = game and game.save
  if species == nil or not (save and save.runModes) then return species end
  if #(save.party or {}) > 1 then return species end
  return RunHooks.shownStarter(game, species)
end

-- ------------------------------------------------------------- nuzlocke --
local function rulesLive(game)
  local save = game and game.save
  return save and save.runModes and RunModes.provider ~= nil and RunModes.nuzlocke(save)
    and not save.runModes.runOver
end
RunHooks.rulesLive = rulesLive

local function isLink(battle)
  return battle and (battle.kind == "link" or battle.link or battle.linkMulti
    or battle.isDemo or battle.oldManDemo or battle.dudeDemo)
end

-- a wild battle was just built.  The rules decide whether its mon may be
-- caught; a refused one dodges every ball (battle.noCatch, the engine's
-- own can't-be-caught path) with the Nuzlocke line.
function RunHooks.wildStart(game, battle, species, opts)
  if game and game.save and game.save.runModes and quietDepth == 0 and not isLink(battle) then
    RunHooks.wildExtras(game, battle, species)
  end
  if not rulesLive(game) or quietDepth > 0 or isLink(battle) or battle.dead then return end
  local ctx = { game = game, battle = battle, species = species, area = RunHooks.area(game),
                static = staticDepth > 0, roamer = opts and (opts.roamer ~= nil) or false }
  local verdict = Runtime.call("runmodes.wild_start", function() return { catchable = true } end, ctx)
  if type(verdict) == "table" and verdict.catchable == false then
    battle.noCatch = true
    battle.runNoCatch = verdict.reason or "NUZLOCKE: only the first\nPOKéMON in an area!"
  end
end

-- a player battler fainted: under the rules it is dead, at once (a revive
-- later in the battle does not save it)
function RunHooks.fainted(battle, battler)
  local game = battle and battle.game
  if not rulesLive(game) or isLink(battle) or quietDepth > 0 then return end
  if not (battler and battler.isPlayer and type(battler.mon) == "table") then return end
  local mon = battler.mon
  if mon[RunModes.DEAD] then return end
  local inParty = false
  for _, m in ipairs(game.save.party or {}) do if m == mon then inParty = true break end end
  if not inParty then return end -- a rental / a borrowed partner
  mon[RunModes.DEAD] = true
  Runtime.emit("runmodes.died", { game = game, mon = mon, battle = battle, cause = "battle" })
end

function RunHooks.caught(battle, mon)
  local game = battle and battle.game
  if not rulesLive(game) or isLink(battle) or quietDepth > 0 then return end
  Runtime.emit("runmodes.caught", { game = game, battle = battle, mon = mon, area = RunHooks.area(game) })
end

function RunHooks.battleEnd(battle, result)
  local game = battle and battle.game
  if not rulesLive(game) or isLink(battle) or quietDepth > 0 then return end
  Runtime.emit("runmodes.battle_end", { game = game, battle = battle, result = result,
                                        area = RunHooks.area(game) })
end

-- the overworld's frame: the rules move the dead out of the party here,
-- where nothing mid-battle can be holding them
function RunHooks.tick(game)
  local save = game and game.save
  -- the full randomizer's data side follows the live save (cheap when
  -- nothing changed; puts the dataset back when the save has no runModes)
  RunHooks.sync(game)
  if not (save and save.runModes) then return end
  if not rulesLive(game) then return end
  Runtime.emit("runmodes.tick", { game = game })
end

-- ------------------------------------------------------- full randomizer --
-- (src/runmodes/RandomOptions.lua for the switches, RandomData.lua for the
-- data side).  Every hook below is a no-op unless its option is on.

local syncWarned = false
function RunHooks.sync(game)
  local ok, res = pcall(function() return require("src.runmodes.RandomData").sync(game) end)
  if not ok and not syncWarned then
    syncWarned = true
    pcall(function() require("src.core.Logger").warn("randomizer sync failed: %s", tostring(res)) end)
  end
  return ok and res
end

-- the Battle Tower / editor pseudo-classes: their parties are not the
-- game's trainers and stay as built
function RunHooks.facilityClass(oppClass)
  local BS = package.loaded["src.battle.BattleState"]
  if oppClass == nil then return false end
  if BS and (oppClass == BS.BATTLE_TOWER_CLASS or oppClass == BS.EDITOR_TRAINER_CLASS) then return true end
  return false
end

RunHooks.LEGEND_BST = 580

-- a gift (`tag` "gift") or scripted static (`tag` "static") species under
-- GIFT & STATIC POKeMON; legends (base stat total 580+) keep theirs
function RunHooks.staticSpecies(game, species, tag)
  local save = game and game.save
  if species == nil or not (save and save.runModes) then return species end
  if not require("src.runmodes.RandomOptions").on(save, "statics") then return species end
  local pokemon = game.data and game.data.pokemon
  if not (pokemon and pokemon[species]) then return species end
  local Randomizer = require("src.runmodes.Randomizer")
  local b = Randomizer._bst(pokemon[species])
  if b <= 0 or b >= RunHooks.LEGEND_BST then return species end
  local pool = Randomizer.pool(pokemon, generation(game))
  local h = RunModes.hash(save.runModes.seed, "static", tag, tostring(mapIdOf(game)), tostring(species))
  return Randomizer._pickNear(pool, b, h, { [species] = true }, 20) or species
end

-- a trainer's slot `i` species under TRAINER POKeMON
function RunHooks.trainerSpecies(game, species, key, i)
  local save = game and game.save
  local pokemon = game and game.data and game.data.pokemon
  if species == nil or not (pokemon and pokemon[species] and save and save.runModes) then return species end
  local Randomizer = require("src.runmodes.Randomizer")
  local pool = Randomizer.pool(pokemon, generation(game))
  local h = RunModes.hash(save.runModes.seed, "trainer", key, i, tostring(species))
  return Randomizer._pickNear(pool, Randomizer._bst(pokemon[species]), h, nil, 20) or species
end

-- four random moves into `mon` (in place: a battler may already hold the
-- moves table), at least one of them an attack
function RunHooks.randomizeMoves(game, mon, ...)
  local save = game and game.save
  if type(mon) ~= "table" or not (save and save.runModes) then return end
  local RandomData = require("src.runmodes.RandomData")
  local list = RandomData.randomMoves(game.data, save.runModes, ...)
  if not list or #list == 0 then return end
  local mv = type(mon.moves) == "table" and mon.moves or {}
  for j = #mv, 1, -1 do mv[j] = nil end
  local Pokemon = require("src.pokemon.Pokemon")
  for _, id in ipairs(list) do
    local d = game.data.moves and game.data.moves[id]
    mv[#mv + 1] = { id = id, pp = Pokemon.maxPP(d) }
  end
  mon.moves = mv
end

-- a wild battle was built: STARTING MOVES and (Gen 2) HELD ITEMS
function RunHooks.wildExtras(game, battle, species)
  local save = game and game.save
  local mon = battle and not battle.dead and battle.enemy and battle.enemy.mon
  if type(mon) ~= "table" then return end
  local RandomOptions = require("src.runmodes.RandomOptions")
  local rm = save.runModes
  local area = tostring(mapIdOf(game))
  if RandomOptions.on(save, "startMoves") then
    RunHooks.randomizeMoves(game, mon, "wild", area, tostring(mon.species), tonumber(rm.wildCount) or 0)
  end
  if RandomOptions.on(save, "heldItems") and generation(game) == 2 and mon.item == nil then
    local RandomData = require("src.runmodes.RandomData")
    local rng = RandomData.Rng(rm.seed, "wildheld2", area, tostring(mon.species), tonumber(rm.wildCount) or 0)
    if rng.float() < 0.2 then mon.item = RandomData.pickHeld(game.data, rm, "wild2", tostring(mon.species)) end
  end
end

-- a mart's stock under MART ITEMS: the same length, POKe BALLS / POTIONS and
-- protected items kept, the rest random (no repeats), stable per mart
local martOut = setmetatable({}, { __mode = "k" })
local ESSENTIAL = { POKEBALL = true, POTION = true }
function RunHooks.martStock(game, stock)
  if type(stock) ~= "table" or martOut[stock] then return stock end
  local save = game and game.save
  if not (save and save.runModes) then return stock end
  if not require("src.runmodes.RandomOptions").on(save, "martItems") then return stock end
  RunHooks.sync(game)
  local RandomData = require("src.runmodes.RandomData")
  local data = game.data
  local sig = {}
  for i, id in ipairs(stock) do sig[i] = tostring(id) end
  local key = table.concat(sig, ",")
  local out, used = {}, {}
  for i, id in ipairs(stock) do
    local it = data.items and data.items[id]
    local keep = type(id) == "table" or not it or RandomData.protectedItem(data, id)
      or ESSENTIAL[RandomData._norm(it.name or id)]
    local new = id
    if not keep then
      for try = 1, 8 do
        new = RandomData.pickItem(data, save.runModes, id, "mart", key, i, try)
        if not used[new] then break end
      end
    end
    used[new] = true
    out[i] = new
  end
  martOut[out] = true
  return out
end

-- an item a script hands over (a gift, an item ball run by script) under
-- FIELD ITEMS & GIFTS; key items, HMs and story items are never touched
function RunHooks.giftItem(game, id)
  local save = game and game.save
  if id == nil or quietDepth > 0 or not (save and save.runModes) then return id end
  if not require("src.runmodes.RandomOptions").on(save, "fieldItems") then return id end
  RunHooks.sync(game)
  local data = game.data
  if not (data and data.items and data.items[id]) then return id end
  return require("src.runmodes.RandomData").pickItem(data, save.runModes, id, "gift", tostring(mapIdOf(game)))
end

-- the move relearner's list under MOVE RELEARNER: a random list per species
-- and five-level band, minus what the mon knows
function RunHooks.relearnable(mon, list, game)
  local RandomData = require("src.runmodes.RandomData")
  game = game or RandomData.game or rawget(_G, "Game")
  local save = game and game.save
  if type(mon) ~= "table" or not (save and save.runModes) then return list end
  if not require("src.runmodes.RandomOptions").on(save, "relearner") then return list end
  local info = RandomData.moveInfo(game.data)
  if #info.all == 0 then return list end
  local known = {}
  for _, mv in ipairs(mon.moves or {}) do
    local id = type(mv) == "table" and (mv.id or mv.move) or mv
    if id ~= nil then known[id] = true end
  end
  local rng = RandomData.Rng(save.runModes.seed, "relearn", tostring(mon.species),
    math.floor((tonumber(mon.level) or 1) / 5))
  local out, seen = {}, {}
  local n = 6 + rng.int(5)
  for k = 1, n * 3 do
    if #out >= n then break end
    local id = (k % 2 == 1) and info.attacks[rng.int(#info.attacks)] or info.all[rng.int(#info.all)]
    if id ~= nil and not known[id] and not seen[id] then
      seen[id] = true
      out[#out + 1] = id
    end
  end
  return out
end

return RunHooks
