-- PLATINUM'S BATTLE FACTORY (overlay104 battle_factory.c, battle_factory_helpers.c,
-- frscrcmd_battle_factory.c), the facility half of the Factory's frontier
-- scene script (fr_script member 1, scenes 3 and 4).
--
-- Seven battles a round with rented Pokemon: six on offer, three taken (the
-- app), and after each win one of yours may be traded for one of the team
-- you beat. The sets are the Battle Tower's (pl_btdpm), drawn from pools by
-- round (sLevel50Pools / sOpenLevelPlayerPools), with every six trades past
-- the first moving one more of the six offered up a pool. The opponents
-- come from sBattleFactoryOpponentPools -- the round's normal range, the
-- final range for the seventh -- and draw from the pool their trainer id
-- falls in. Thorton, the Factory Head, is the 21st and 49th in singles.
-- Everyone is level 50, or 100 at Open Level.
--
-- NOT PORTED: the multi challenges (link play), and the Factory app's own
-- screen (the rental list is src/ui/Gen3FactoryScreen.lua's).

local Commands = require("src.script.Commands")
local Logger = require("src.core.Logger")
local VM = require("src.script.Gen4FrontierVM")
local Fr = require("src.script.Gen4FrontierScrCmds")

local B = {}

B.SINGLE, B.DOUBLE, B.MULTI, B.MULTI_WFC = 0, 1, 2, 3
B.PER_ROUND = 7                  -- FACTORY_BATTLES_PER_ROUND
B.SILVER, B.GOLD = 21, 49        -- FACTORY_STREAK_SILVER_BATTLE / _GOLD_BATTLE
B.MAX_ROUNDS = 8                 -- FACTORY_MAX_DISTINCT_ROUNDS
B.OPTIONS = 6                    -- FACTORY_INITIAL_RENTAL_OPTIONS
B.THORTON_SILVER, B.THORTON_GOLD = 309, 310
B.BP_SOLO = { [0] = 0, 5, 5, 5, 5, 7, 7, 8, 9 }
B.BP_WIFI = { [0] = 0, 10, 11, 12, 13, 16, 17, 19, 21 }
B.UPGRADES = { 6, 13, 20, 27, 34 }   -- sTradeCountsNeededForUpgrades

-- sBattleFactoryOpponentPools: { normalMin, normalMax, finalMin, finalMax }
B.OPPONENT_POOLS = {
  { 0, 99, 100, 119 }, { 80, 119, 120, 139 }, { 100, 139, 140, 159 }, { 120, 159, 160, 179 },
  { 140, 179, 180, 199 }, { 160, 199, 200, 219 }, { 180, 219, 220, 239 }, { 200, 299, 200, 299 },
}
-- { trainerIDMax, setIDMin, setIDMax, ivs, canBeUpgraded }
local function pool(t) return { trainerIDMax = t[1], min = t[2], max = t[3], ivs = t[4], up = t[5] } end
B.POOLS_50 = {
  pool { 100, 1, 150, 0, true }, pool { 120, 151, 250, 4, true }, pool { 140, 251, 350, 8, true },
  pool { 160, 351, 486, 12, true }, pool { 180, 487, 622, 16, true }, pool { 200, 623, 758, 20, true },
  pool { 220, 759, 894, 24, true }, pool { 300, 351, 950, 31, false }, pool { 310, 351, 486, 12, false },
  pool { 311, 351, 486, 31, false },
}
B.POOLS_OPEN_OPPONENT = {
  pool { 100, 351, 486, 0, true }, pool { 120, 487, 622, 4, true }, pool { 140, 623, 758, 8, true },
  pool { 160, 759, 894, 12, true }, pool { 180, 351, 950, 16, true }, pool { 200, 351, 950, 20, true },
  pool { 220, 351, 950, 24, true }, pool { 300, 351, 950, 31, false }, pool { 310, 759, 950, 12, false },
  pool { 311, 759, 950, 31, false },
}
B.POOLS_OPEN_PLAYER = {
  pool { 100, 351, 486, 0, true }, pool { 120, 487, 622, 4, true }, pool { 140, 623, 758, 8, true },
  pool { 160, 759, 894, 12, true }, pool { 180, 623, 950, 16, true }, pool { 200, 623, 950, 20, true },
  pool { 220, 623, 950, 24, true }, pool { 300, 351, 950, 31, false }, pool { 310, 759, 950, 12, false },
  pool { 311, 759, 950, 31, false },
}

local function rand(n) return love.math.random(0, n - 1) end
local function rand16() return love.math.random(0, 65535) end
local function BT() return require("src.pokemon.Gen4BattleTower") end

function B.isMulti(t) return t == B.MULTI or t == B.MULTI_WFC end
function B.partySize(t) return B.isMulti(t) and 2 or 3 end
function B.level(f) return (f.isOpenLevel ~= 0) and 100 or 50 end
local function streakKey(f) return f.isOpenLevel * 4 + f.challengeType end

-- the Factory's records (BattleFactorySave, the streak flags, the frontier stats)
function B.record(save)
  save.gen4Factory = save.gen4Factory or {}
  local r = save.gen4Factory
  r.streakActive = r.streakActive or {}
  r.latest = r.latest or {}
  r.trades = r.trades or {}
  r.records = r.records or {}
  r.recordTrades = r.recordTrades or {}
  return r
end

-- BattleFactory_Init
function B.init(save, resuming, challengeType, isOpenLevel)
  local r = B.record(save)
  local f = { save = save, trainerIDs = {}, selected = {}, playerSets = {} }
  if resuming == 0 then
    f.challengeType, f.isOpenLevel, f.currentBattle = challengeType, isOpenLevel, 0
    r.current = nil
    local k = streakKey(f)
    if r.streakActive[k] then
      f.currentStreak, f.tradeCount = r.latest[k] or 0, r.trades[k] or 0
    else
      f.currentStreak, f.tradeCount = 0, 0
    end
  else
    local cur = r.current or {}
    f.challengeType, f.isOpenLevel, f.currentBattle = cur.challengeType or 0, cur.isOpenLevel or 0, cur.currentBattle or 0
    local k = streakKey(f)
    f.currentStreak, f.tradeCount = r.latest[k] or 0, r.trades[k] or 0
  end
  f.currentRound = math.floor(f.currentStreak / B.PER_ROUND)
  return f
end

function B.round(f) return f.currentRound end

-- BattleFactory_GetOpponentTrainerID
function B.opponentTrainerID(challengeType, round, offset)
  if round >= #B.OPPONENT_POOLS then round = #B.OPPONENT_POOLS - 1 end
  if challengeType == B.SINGLE then
    local streak = round * B.PER_ROUND + offset + 1
    if streak == B.SILVER then return B.THORTON_SILVER elseif streak == B.GOLD then return B.THORTON_GOLD end
  end
  local p = B.OPPONENT_POOLS[round + 1]
  local min, spread
  if offset == B.PER_ROUND - 1 or offset == B.PER_ROUND * 2 - 1 then min, spread = p[3], p[4] - p[3]
  else min, spread = p[1], p[2] - p[1] end
  return min + rand16() % spread
end

-- BattleFactory_PickOpponentTrainers: none twice
function B.pickTrainers(challengeType, round, ids, n)
  local i = 0
  while i < n do
    ids[i] = B.opponentTrainerID(challengeType, round, i)
    local dup = false
    for j = 0, i - 1 do if ids[j] == ids[i] then dup = true break end end
    if not dup then i = i + 1 end
  end
end

-- BattleFactory_GetPokemonPoolForTrainer / GetPlayerPoolForRound (the index)
function B.opponentPool(trainerID, isOpenLevel)
  local pools = (isOpenLevel ~= 0) and B.POOLS_OPEN_OPPONENT or B.POOLS_50
  for i, p in ipairs(pools) do if trainerID < p.trainerIDMax then return pools, i end end
  return pools, #pools
end
function B.playerPool(round, isOpenLevel)
  if round >= B.MAX_ROUNDS then round = B.MAX_ROUNDS - 1 end
  return (isOpenLevel ~= 0) and B.POOLS_OPEN_PLAYER or B.POOLS_50, round + 1
end

-- how many of the six offered come from the next pool up, by trades made
function B.upgradable(tradeCount)
  if tradeCount == 0 then return 0 end
  for i, need in ipairs(B.UPGRADES) do if tradeCount <= need then return i - 1 end end
  return #B.UPGRADES
end

-- BattleFactory_SelectPokemonFromPool: set ids and IVs, no species or item
-- twice among themselves or with the excluded ones
function B.selectFromPool(data, excluded, n, pools, pi, tradeCount)
  local sets = data.gen4_battle_tower and data.gen4_battle_tower.sets or {}
  local p, nxt = pools[pi], pools[pi + 1]
  local up = B.upgradable(tradeCount or 0)
  local ids, ivs, picked = {}, {}, {}
  local guard = 0
  while #ids < n and guard < 20000 do
    guard = guard + 1
    local slot = #ids
    local setID, iv
    if slot >= n - up and p.up and nxt then
      setID, iv = nxt.max - rand16() % (nxt.max - nxt.min + 1), nxt.ivs
    else
      setID, iv = p.max - rand16() % (p.max - p.min + 1), p.ivs
    end
    local s = sets[setID]
    local ok = s ~= nil
    for _, q in ipairs(picked) do
      if ok and (q.species == s.species or q.item == s.item) then ok = false end
    end
    for _, e in ipairs(excluded or {}) do
      if ok and (e.species == s.species or e.item == s.item) then ok = false end
    end
    if ok then
      ids[#ids + 1], ivs[#ivs + 1], picked[#picked + 1] = setID, iv, s
    end
  end
  return ids, ivs
end

-- BattleFrontier_LoadFrontierPokemon: entries (a personality of the set's
-- nature, never shiny), as the Tower makes them
function B.entries(data, setIDs, ivs, personalities)
  local sets = data.gen4_battle_tower and data.gen4_battle_tower.sets or {}
  local out = {}
  for i, id in ipairs(setIDs) do
    local otId = rand16() + rand16() * 65536
    local e = BT().monFromSet(sets[id], id, ivs[i], otId, rand16)
    if personalities and personalities[i] then
      e.personality, e.abilityBit = personalities[i], personalities[i] % 2
    end
    out[i] = e
  end
  return out
end

-- the entries as Pokemon at the Factory's level (FrontierPokemon_InitPokemon)
function B.mons(game, f, entries)
  return require("src.script.Gen4BattleTowerCommands").opponentMons(game, entries, B.level(f))
end

-- SetupTrainersAndInitialRentalOptions
function B.newRound(data, f)
  local excluded = {}
  B.pickTrainers(f.challengeType, B.round(f), f.trainerIDs, B.PER_ROUND * 2)
  local pools, pi = B.playerPool(B.round(f), f.isOpenLevel)
  local ids, ivs = B.selectFromPool(data, nil, B.OPTIONS, pools, pi, f.tradeCount)
  f.rentalSets, f.rentals = ids, B.entries(data, ids, ivs)
  -- SwapMonIndices(4) and (5): the upgraded two shuffled in among the rest
  for _, a in ipairs({ 5, 6 }) do
    local b = rand16() % B.OPTIONS + 1
    f.rentalSets[a], f.rentalSets[b] = f.rentalSets[b], f.rentalSets[a]
    f.rentals[a], f.rentals[b] = f.rentals[b], f.rentals[a]
  end
  for i, e in ipairs(f.rentals) do excluded[i] = { species = e.species, item = e.item } end
  local opools, opi = B.opponentPool(f.trainerIDs[f.currentBattle], f.isOpenLevel)
  local oids, oivs = B.selectFromPool(data, excluded, B.partySize(f.challengeType), opools, opi, 0)
  f.opponentSets, f.opponentEntries = oids, B.entries(data, oids, oivs)
  f.playerEntries = f.rentals
  f.opponentParty = nil
end

-- LoadTrainersAndMonsFromSave
function B.fromSave(f)
  local cur = B.record(f.save).current or {}
  for k, v in pairs(cur.trainerIDs or {}) do f.trainerIDs[k] = v end
  f.playerEntries = require("src.script.Gen4BattleTowerCommands").copy(cur.playerEntries or {})
  f.playerSets = require("src.script.Gen4BattleTowerCommands").copy(cur.playerSets or {})
  f.opponentEntries = require("src.script.Gen4BattleTowerCommands").copy(cur.opponentEntries or {})
  f.opponentSets = require("src.script.Gen4BattleTowerCommands").copy(cur.opponentSets or {})
  f.opponentParty = f.opponentEntries
end

-- BattleFactory_AddSelectedRentalsToParty
function B.takeRentals(f)
  f.playerEntries, f.playerSets = {}, {}
  for i = 1, B.partySize(f.challengeType) do
    local slot = (f.selected[i - 1] or (i - 1)) + 1
    f.playerEntries[i] = f.rentals[slot]
    f.playerSets[i] = f.rentalSets[slot]
  end
  f.opponentParty = f.opponentEntries
end

-- BattleFactory_SetupNextOpponent: the beaten team's sets kept for the trade,
-- and the next trainer's team, clear of everything on both sides
function B.nextOpponent(data, f)
  local excluded = {}
  for _, e in ipairs(f.playerEntries or {}) do excluded[#excluded + 1] = { species = e.species, item = e.item } end
  for _, e in ipairs(f.opponentParty or {}) do excluded[#excluded + 1] = { species = e.species, item = e.item } end
  f.beatenSets = {}
  for i, id in ipairs(f.opponentSets or {}) do f.beatenSets[i] = id end
  local opools, opi = B.opponentPool(f.trainerIDs[f.currentBattle], f.isOpenLevel)
  local oids, oivs = B.selectFromPool(data, excluded, B.partySize(f.challengeType), opools, opi, 0)
  f.opponentSets, f.opponentEntries = oids, B.entries(data, oids, oivs)
end

-- BattleFactory_ApplyTrade: selected[0] is yours to give (0xFF to keep), selected[1] theirs
function B.applyTrade(f)
  local give, take = f.selected[0], f.selected[1]
  if give == nil or give == 0xFF or not (f.opponentParty and f.opponentParty[take + 1]) then return false end
  f.playerEntries[give + 1] = f.opponentParty[take + 1]
  f.playerSets[give + 1] = (f.beatenSets or {})[take + 1]
  if f.tradeCount < 9999 then f.tradeCount = f.tradeCount + 1 end
  local R = require("src.pokemon.Gen4GameRecords")
  R.increment(f.save, R.ID.BATTLE_FACTORY_TRADES)
  return true
end

-- BattleFactory_GetEarnedBP
function B.earnedBP(f)
  local t = (f.challengeType == B.SINGLE or f.challengeType == B.DOUBLE) and B.BP_SOLO or B.BP_WIFI
  local bp = t[math.min(f.currentRound, B.MAX_ROUNDS)]
  if f.challengeType == B.SINGLE and (f.currentStreak == B.SILVER or f.currentStreak == B.GOLD) then bp = 20 end
  return bp
end

-- BattleFactory_Save (0 a round, 1 a loss, 2 a quick save)
function B.save(f, kind)
  local r = B.record(f.save)
  local k = streakKey(f)
  local C = require("src.script.Gen4BattleTowerCommands")
  r.current = { challengeType = f.challengeType, isOpenLevel = f.isOpenLevel, currentBattle = f.currentBattle,
    saved = true, trainerIDs = {}, playerEntries = C.copy(f.playerEntries or {}), playerSets = C.copy(f.playerSets or {}),
    opponentEntries = C.copy(f.opponentParty or f.opponentEntries or {}), opponentSets = C.copy(f.opponentSets or {}) }
  for i, v in pairs(f.trainerIDs) do r.current.trainerIDs[i] = v end
  r.trades[k], r.latest[k] = f.tradeCount, f.currentStreak
  if kind ~= 2 then
    local before = r.records[k] or 0
    if f.currentStreak > before then r.records[k] = f.currentStreak end
    if f.currentStreak == before then r.recordTrades[k] = math.max(r.recordTrades[k] or 0, f.tradeCount)
    elseif before < (r.records[k] or 0) then r.recordTrades[k] = f.tradeCount end
    r.streakActive[k] = f.saveStreak and true or nil
  end
end

-- the opponent's most common type, or 0xFF when no type comes up twice
function B.commonType(game, f)
  local counts = {}
  for _, mon in ipairs(B.mons(game, f, f.opponentEntries or {})) do
    local def = require("src.pokemon.Gen4Forms").definition(game.data, mon)
    local t1, t2 = B.typeNumber(game.data, def and def.types and def.types[1]),
                   B.typeNumber(game.data, def and def.types and (def.types[2] or def.types[1]))
    if t1 then counts[t1] = (counts[t1] or 0) + 1 end
    if t2 and t2 ~= t1 then counts[t2] = (counts[t2] or 0) + 1 end
  end
  local best = 0
  -- every slot the cartridge names (18 on retail Platinum and on Renegade,
  -- where slot 9 is FAIRY), not a literal 17
  local slots = (game.data.constants and tonumber(game.data.constants.typeCount)) or 18
  for t = 0, slots - 1 do
    if (counts[best] or 0) < (counts[t] or 0) then best = t end
  end
  return ((counts[best] or 0) <= 1) and 0xFF or best
end
function B.typeNumber(data, t)
  if type(t) == "number" then return t end
  local order = data.constants and data.constants.typeOrder
  for i, name in ipairs(order or {}) do if name == t then return i - 1 end end
  -- the cache's own type names (slot 9: MYSTERY on retail, FAIRY on Renegade)
  local named = data.constants and data.constants.types
  if type(named) == "table" and type(t) == "string" then
    for i = 0, 63 do
      if type(named[i]) == "string" and named[i]:upper() == t:upper() then return i end
    end
  end
  local T = { NORMAL = 0, FIGHTING = 1, FLYING = 2, POISON = 3, GROUND = 4, ROCK = 5, BUG = 6, GHOST = 7,
    STEEL = 8, MYSTERY = 9, FIRE = 10, WATER = 11, GRASS = 12, ELECTRIC = 13, PSYCHIC = 14, ICE = 15,
    DRAGON = 16, DARK = 17 }
  return T[t]
end

-- ------------------------------------------------------------ the lowering --

local F = VM.facility
local emit = VM.emit
F.initbattlefactory = function(ins, s) emit(s, { "fr_bf_init", ins.args[1], ins.args[2], ins.args[3] }) end
F.battlefactory_loadtrainersforround = function(ins, s) emit(s, { "fr_bf_load_round", ins.args[1] }) end
F.freebattlefactory = function(_, s) emit(s, { "fr_bf_free" }) end
F.openbattlefactoryappinitial = function(_, s) emit(s, { "fr_bf_app", 0 }) end
F.openbattlefactoryappfortrade = function(_, s) emit(s, { "fr_bf_app", 1 }) end
F.addselectedrentalstoparty = function(_, s) emit(s, { "fr_bf_take_rentals" }) end
F.battlefactory_setupnextopponent = function(_, s) emit(s, { "fr_bf_next_opponent" }) end
F.battlefactory_applytrade = function(_, s) emit(s, { "fr_bf_trade" }) end
F.battlefactory_setupnextopponentsparty = function(_, s) emit(s, { "fr_bf_opponents_party" }) end
F.callbattlefactoryfunction = function(ins, s)
  emit(s, { "fr_bf_call", ins.args[1], ins.args[2], ins.args[3], ins.args[4] })
end
F.battlefactory_startbattle = function(_, s) emit(s, { "fr_bf_battle" }) end
F.battlefactory_cleanupbattle = function() end
F.battlefactory_checkwonbattle = function(ins, s) emit(s, { "fr_bf_won", ins.args[1] }) end
F.battlefactory_printtrainerintro = function(ins, s) emit(s, { "fr_bf_intro", ins.args[1] }) end
-- the link commands: alone, sent and answered at once
F.battlefactory_sendcommmessage = function(ins, s) emit(s, { "fr_set", ins.args[3], 1 }) end
F.battlefactory_waitforcommresponses = function() end

local function factory(ctx) return ctx.game.gen4BattleFactory end

function Commands.fr_bf_init(ctx, resuming, challengeType, isOpenLevel)
  local v = Fr.value
  ctx.game.gen4BattleFactory = B.init(ctx.save, v(ctx, resuming), v(ctx, challengeType), v(ctx, isOpenLevel))
end
function Commands.fr_bf_free(ctx) ctx.game.gen4BattleFactory = nil end
function Commands.fr_bf_load_round(ctx, resuming)
  local f = factory(ctx)
  if not f then return end
  if Fr.value(ctx, resuming) == 0 then B.newRound(ctx.game.data, f) else B.fromSave(f) end
end
function Commands.fr_bf_take_rentals(ctx)
  local f = factory(ctx)
  if f then B.takeRentals(f) end
end
function Commands.fr_bf_next_opponent(ctx)
  local f = factory(ctx)
  if f then B.nextOpponent(ctx.game.data, f) end
end
function Commands.fr_bf_trade(ctx)
  local f = factory(ctx)
  if f then B.applyTrade(f) end
end
function Commands.fr_bf_opponents_party(ctx)
  local f = factory(ctx)
  if f then f.opponentParty = f.opponentEntries end
end

-- the Factory app: the six to choose three from, or the trade
function Commands.fr_bf_app(ctx, trade)
  local f = factory(ctx)
  if not f then return end
  local game = ctx.game
  local Screen = require("src.ui.Gen3FactoryScreen")
  local runner = ctx.runner
  local result
  local opts
  if tonumber(trade) == 1 then
    opts = { mode = "swap", mons = B.mons(game, f, f.playerEntries), theirs = B.mons(game, f, f.opponentParty or {}) }
  else
    opts = { mode = "select", mons = B.mons(game, f, f.rentals or f.playerEntries or {}) }
  end
  opts.onDone = function(r) result = r; if runner then runner:resume() end end
  game.stack:push(Screen.new(game, opts))
  if runner then runner:yield() end
  f.selected = {}
  if tonumber(trade) == 1 then
    if result and result.give and result.take then
      f.selected[0], f.selected[1] = result.give - 1, result.take - 1
    else
      f.selected[0] = 0xFF
    end
  else
    for i = 1, B.partySize(f.challengeType) do f.selected[i - 1] = ((result and result[i]) or i) - 1 end
  end
end

-- FrontierScrCmd_CallBattleFactoryFunction
function Commands.fr_bf_call(ctx, cmd, a1, a2, dest)
  local f = factory(ctx)
  if not f then Logger.warn("gen4 battle factory: function %s with no factory", tostring(cmd)) return end
  cmd, a1, a2 = tonumber(cmd) or 0, tonumber(a1) or 0, tonumber(a2) or 0
  local game = ctx.game
  local v
  if cmd == 1 then f.isOpenLevel = a1
  elseif cmd == 2 then f.challengeType = a1
  elseif cmd == 3 then v = f.selected[a1] or 0
  elseif cmd == 4 then v = f.currentStreak
  elseif cmd == 5 then if f.currentStreak < 9999 then f.currentStreak = f.currentStreak + 1 end
  elseif cmd == 7 then if game.returnToTitle then game:returnToTitle() end
  elseif cmd == 9 then v = (B.record(ctx.save).current or {}).saved and 1 or 0
  elseif cmd == 10 then B.save(f, 2)
  elseif cmd == 14 then f.currentBattle = f.currentBattle + 1; v = f.currentBattle
  elseif cmd == 15 then local e = (f.opponentEntries or {})[a1 + 1]; v = e and e.species or 0
  elseif cmd == 16 then local e = (f.opponentEntries or {})[a1 + 1]; v = e and e.moves[a2 + 1] or 0
  elseif cmd == 17 then
    local mon = B.mons(game, f, { (f.opponentEntries or {})[a1 + 1] })[1]
    local def = mon and require("src.pokemon.Gen4Forms").definition(game.data, mon)
    v = B.typeNumber(game.data, def and def.types and def.types[1]) or 0
  elseif cmd == 18 then v = B.commonType(game, f)
  elseif cmd == 19 then v = B.round(f)
  elseif cmd == 20 then
    local id = f.trainerIDs[f.currentBattle + a1 * B.PER_ROUND]
    local rec = game.data.gen4_battle_tower and game.data.gen4_battle_tower.trainers[id]
    v = (rec and BT().CLASS_GFX[rec.class]) or BT().GFX_SCHOOL_KID_M
  elseif cmd == 21 then B.save(f, 1)
  elseif cmd == 22 then
    f.saveStreak = true
    if f.currentRound < B.MAX_ROUNDS then f.currentRound = f.currentRound + 1 end
    f.currentBattle = 0
    B.save(f, 0)
  elseif cmd == 23 then v = f.currentBattle
  elseif cmd == 24 or cmd == 26 then v = 0
  elseif cmd == 28 then v = B.isMulti(f.challengeType) and 1 or 0
  elseif cmd == 29 then v = f.challengeType
  elseif cmd == 33 then
    local function trainer(id)
      local rec = id and game.data.gen4_battle_tower and game.data.gen4_battle_tower.trainers[id]
      return rec and { id = id, class = rec.class, party = {} } or nil
    end
    f.opponents = { [0] = trainer(f.trainerIDs[f.currentBattle]), trainer(f.trainerIDs[f.currentBattle + B.PER_ROUND]) }
  elseif cmd == 34 then
    for i, mon in ipairs(B.mons(game, f, f.playerEntries or {})) do
      Commands.g4_buffer(ctx, i - 1, "species", mon.species)
    end
  elseif cmd == 35 then v = B.earnedBP(f)
  elseif cmd == 36 then if f.tradeCount < 9999 then f.tradeCount = f.tradeCount + 1 end
  elseif cmd == 37 then
    v = 0
    if f.challengeType == B.SINGLE then
      if f.currentStreak + 1 == B.SILVER then v = 1 elseif f.currentStreak + 1 == B.GOLD then v = 2 end
    end
  elseif cmd == 39 then
    -- BF_FUNC_CREATE_OPPONENT_MONS: the entries are made already; nothing to rebuild
  elseif cmd == 40 then
    f.playerEntries = f.rentals or f.playerEntries
  elseif cmd == 41 then
    local r = B.record(ctx.save)
    v = r.seenHeadIntro and 1 or 0
    r.seenHeadIntro = true
  end
  -- 0, 6, 8, 11-13, 25 dummies; 27 the link manager; 30-32 the corridor's art
  if v ~= nil then Fr.store(ctx, dest, v) end
end

-- BattleFactory_StartBattle: both sides healed, your rentals against theirs
function Commands.fr_bf_battle(ctx)
  local f = factory(ctx)
  local game = ctx.game
  game.gen4BattleFactoryWon = 0
  if not f then return end
  local C = require("src.script.Gen4BattleTowerCommands")
  local id = f.trainerIDs[f.currentBattle]
  local rec = game.data.gen4_battle_tower and game.data.gen4_battle_tower.trainers[id]
  if not (rec and f.opponentParty and f.opponentParty[1]) then
    Logger.warn("gen4 battle factory: no opponent to battle -- counted as a loss")
    return
  end
  local double = f.challengeType == B.DOUBLE
  local key = C.registerTrainer(game, "GEN4_BATTLE_FACTORY", { id = id, class = rec.class, party = f.opponentParty },
                                double, B.level(f))
  local team = B.mons(game, f, f.playerEntries or {})
  local BattleState = require("src.battle.BattleState")
  local real = ctx.save.party
  require("src.pokemon.PartyAside").hold(ctx.save, real)  -- in the save too (PartyAside)
  ctx.save.party = team
  local ok, battle = pcall(BattleState.newTrainer, game, key, 1)
  if not ok or not battle then
    ctx.save.party = real
    require("src.pokemon.PartyAside").release(ctx.save)
    Logger.warn("gen4 battle factory: could not build the battle: %s", tostring(battle))
    return
  end
  battle.battleTower, battle.canLose, battle.noExp = true, true, true
  if double then
    battle.double = true
    if battle.sendOutSecondPair then battle:sendOutSecondPair() end
  end
  local runner = ctx.runner
  battle.onFinish = function(result)
    ctx.save.party = real
    require("src.pokemon.PartyAside").release(ctx.save)
    game.gen4BattleFactoryWon = (result == "win") and 1 or 0
    if runner then runner:resume() end
  end
  if ctx.overworld and ctx.overworld.pushBattle then ctx.overworld:pushBattle(battle)
  else game.stack:push(battle) end
  if runner then runner:yield() end
end
function Commands.fr_bf_won(ctx, dest) Fr.store(ctx, dest, ctx.game.gen4BattleFactoryWon or 0) end

function Commands.fr_bf_intro(ctx, n)
  local f = factory(ctx)
  local o = f and f.opponents and f.opponents[tonumber(n) or 0]
  if not o then return end
  local Gen4Text = require("src.import.Gen4Text")
  return Commands.show_text(ctx, Gen4Text.label(BT().TRAINER_MESSAGES, o.id * 3))
end

return B
