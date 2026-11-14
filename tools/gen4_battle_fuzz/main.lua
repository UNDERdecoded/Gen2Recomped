-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- tools/gen4_battle_fuzz/main.lua
--
-- A HEADLESS PLATINUM BATTLE FUZZER.
--
-- Plays whole battles to their end through the real BattleState, the real
-- queue, the real menus' input path and the real bag / party screens, with
-- randomised but legal player choices, and reports
--
--   error    a Lua error (with traceback), from update / draw / a screen
--   hang     no turn finished and no menu reached inside the frame budget
--   invalid  HP < 0 / > max / NaN, PP < 0, a nil move, an empty party ...
--   stall    the battle was still going after --max-turns (information only)
--
--   POKEPORT_DATA_DIR=<cache>/data/generated POKEPORT_ASSET_ROOT=<cache> \
--   POKEPORT_IDENTITY=pl_battle \
--     "C:/Program Files/LOVE/lovec.exe" tools/gen4_battle_fuzz \
--        --seed 1 --count 200 --mode all
--
-- Options (also readable from FUZZ_<NAME> environment variables):
--   --seed N         first seed (battle i uses seed N+i-1)            [1]
--   --count N        battles to run                                    [100]
--   --mode M         trainers | doubles | singles | wild | tag | all   [all]
--                    (trainers = every trainer id in the table, in order,
--                     looping; `all` mixes everything by seed)
--   --trainer ID     run just this trainer (with --count seeds)
--   --species ID     force the wild species
--   --anims 0|1      battle animations on (1) or off (0)               [0]
--   --ui U          bottom | field | mixed: which bag/party screens    [mixed]
--   --draw K         also draw the battle every K frames (0 = never)   [0]
--   --max-turns N    turns before a battle is counted as a stall       [300]
--   --hang-frames N  frames without a turn or item use before a hang   [6000]
--   --verbose        one line per battle
--   --trace          print every message the battle prints
--   --stop-on-fail   stop at the first failure
--
-- Exit status is 1 when any error / hang / invalid failure was found.

local ARGS = {}
local function parseArgs(list)
  local i = 1
  while i <= #list do
    local a = list[i]
    local key = a:match("^%-%-(.+)$")
    if key then
      local nxt = list[i + 1]
      if nxt and not nxt:match("^%-%-") then ARGS[key] = nxt; i = i + 2
      else ARGS[key] = true; i = i + 1 end
    else
      i = i + 1
    end
  end
end

local function opt(name, default)
  local v = ARGS[name]
  if v == nil then v = os.getenv("FUZZ_" .. name:upper():gsub("%-", "_")) end
  if v == nil then return default end
  if type(default) == "number" then return tonumber(v) or default end
  return v
end

local function out(fmt, ...)
  io.stdout:write((select("#", ...) > 0 and fmt:format(...) or fmt), "\n")
  io.stdout:flush()
end

-- ---------------------------------------------------------------------------
-- the world the battle needs
-- ---------------------------------------------------------------------------
local Data, Game, BattleState, Pokemon, SaveData, Party, StateStack
local typeNames = {}
local screensSeen
local movesSeen, abilitiesSeen = {}, {}

local keysDown = {}
local fakeInput = setmetatable({}, { __index = function()
  return function() return false end
end })
fakeInput.wasPressed = function(_, k) return keysDown[k] == true end
fakeInput.isDown = function() return false end
fakeInput.wasReleased = function() return false end

-- the move / species / item ids the cache has, sorted for determinism
local moveIds, speciesIds, battleItemIds, ballIds, heldItemIds = {}, {}, {}, {}, {}

local function sortedNumericKeys(t, pred)
  local keys = {}
  for k, v in pairs(t or {}) do
    if type(k) == "number" and (not pred or pred(k, v)) then keys[#keys + 1] = k end
  end
  table.sort(keys)
  return keys
end

local function installAssetRoot()
  local assetRoot = os.getenv("POKEPORT_ASSET_ROOT")
  if not assetRoot then return end
  local Assets = require("src.render.Assets")
  local realImage = Assets.image
  local held = {}
  Assets.image = function(path, ...)
    if type(path) == "string" and not held[path] then
      local f = io.open(assetRoot .. "/" .. path, "rb")
      if f then
        local bytes = f:read("*a"); f:close()
        local okI, img = pcall(love.graphics.newImage,
                               love.filesystem.newFileData(bytes, path))
        if okI then img:setFilter("nearest", "nearest"); held[path] = img end
      end
    end
    return held[path] or realImage(path, ...)
  end
  local realData = Assets.imageData
  local heldData = {}
  Assets.imageData = function(path, ...)
    if type(path) == "string" and not heldData[path] then
      local f = io.open(assetRoot .. "/" .. path, "rb")
      if f then
        local bytes = f:read("*a"); f:close()
        local okD, d = pcall(love.image.newImageData, love.filesystem.newFileData(bytes, path))
        if okD then heldData[path] = d end
      end
    end
    return heldData[path] or realData(path, ...)
  end
end

-- engine warnings / errors the Logger is told about, by format string: a
-- battle that "worked" but logged `battle finished with no healthy party;
-- forcing blackout` is still worth reading about
local warnings = {}
local currentSeed = 0
local function hookLogger()
  local Logger = require("src.core.Logger")
  for _, level in ipairs({ "warn", "error" }) do
    local real = Logger[level]
    Logger[level] = function(fmt, ...)
      local key = level .. ": " .. tostring(fmt)
      local w = warnings[key]
      if not w then
        w = { count = 0, seed = currentSeed, sample = (pcall(string.format, fmt, ...) and string.format(fmt, ...)) or tostring(fmt) }
        warnings[key] = w
      end
      w.count = w.count + 1
      return real(fmt, ...)
    end
  end
end

local function setup()
  require("src.core.GameVersion").set("platinum")
  hookLogger()
  installAssetRoot()
  Data = require("src.core.Data")
  Data:load()
  assert(Data.isGen4Cache, "POKEPORT_DATA_DIR is not a Gen 4 cache")
  require("src.render.Font").load(Data)
  Pokemon = require("src.pokemon.Pokemon")
  SaveData = require("src.core.SaveData")
  BattleState = require("src.battle.BattleState")
  Party = require("src.pokemon.Party")
  StateStack = require("src.core.StateStack")
  Game = require("src.core.Game")
  Game.data = Data
  Game.input = fakeInput
  Game.stack = StateStack
  Game.stack:init()

  moveIds = sortedNumericKeys(Data.moves, function(_, v) return type(v) == "table" and v.name end)
  speciesIds = sortedNumericKeys(Data.pokemon, function(k, v)
    return k >= 1 and k <= 493 and type(v) == "table" and v.baseStats
  end)
  for _, id in ipairs(sortedNumericKeys(Data.items)) do
    local d = Data.items[id]
    if type(d) == "table" and d.name and d.name ~= "" then
      if (d.battleUseCategory or 0) ~= 0 and (d.battlePocket or 0) ~= 0 then
        battleItemIds[#battleItemIds + 1] = id
        if d.pocket == "POKE_BALLS" then ballIds[#ballIds + 1] = id end
      end
      if (d.holdEffect and d.holdEffect ~= 0) or d.pocket == "BERRIES" or d.pocket == "ITEMS" then
        heldItemIds[#heldItemIds + 1] = id
      end
    end
  end
  if #heldItemIds == 0 then
    for _, id in ipairs(sortedNumericKeys(Data.items)) do heldItemIds[#heldItemIds + 1] = id end
  end
end

-- ---------------------------------------------------------------------------
-- random parties
-- ---------------------------------------------------------------------------
local rnd -- a per-battle PRNG so a seed alone reproduces a battle

local function newRng(seed)
  -- xorshift-ish LCG on 31 bits; independent of love.math so a battle's
  -- COMPOSITION is stable even if the engine's own rolls change
  local s = (seed * 2654435761 + 12345) % 2147483647
  if s == 0 then s = 1 end
  return function(a, b)
    s = (s * 48271) % 2147483647
    local r = s / 2147483647
    if not a then return r end
    if not b then a, b = 1, a end
    return a + math.floor(r * (b - a + 1))
  end
end

local function pick(list) return list[rnd(1, #list)] end

local function randomMon(level, opts)
  opts = opts or {}
  local species = opts.species or pick(speciesIds)
  local mon = Pokemon.new(Data, species, level)
  -- random moves from the whole table, so every effect gets reached
  if rnd(1, 100) <= (opts.randomMoves or 70) then
    mon.moves = {}
    local n = rnd(1, 4)
    local used = {}
    for i = 1, n do
      local id
      for _ = 1, 10 do id = pick(moveIds); if not used[id] then break end end
      used[id] = true
      local mdef = Data.moves[id]
      mon.moves[i] = { id = id, pp = Pokemon.maxPP(mdef, nil) }
    end
  end
  mon.abilitySlot = rnd(1, 2)
  if rnd(1, 100) <= 40 then mon.item = pick(heldItemIds) end
  -- a status on the lead now and then
  if rnd(1, 100) <= 10 then mon.status = pick({ "PSN", "BRN", "PAR", "SLP", "FRZ", "TOX" }) end
  if rnd(1, 100) <= 15 then
    mon.hp = math.max(1, math.floor(mon.stats.hp * rnd(1, 100) / 100))
  end
  mon.nickname = nil
  return mon
end

local function randomParty(minSize, around)
  local n = rnd(minSize, 6)
  local party = {}
  for i = 1, n do
    local level
    local r = rnd(1, 100)
    if r <= 55 and around then level = math.max(1, math.min(100, around + rnd(-6, 12)))
    elseif r <= 80 then level = rnd(5, 60)
    elseif r <= 92 then level = rnd(1, 100)
    else level = pick({ 1, 2, 3, 50, 99, 100 }) end
    party[i] = randomMon(level)
  end
  return party
end

local function stockBag(save)
  save.inventory = save.inventory or {}
  for _, id in ipairs(ballIds) do save.inventory[id] = 5 end
  for _, id in ipairs(battleItemIds) do
    if rnd(1, 100) <= 45 then save.inventory[id] = rnd(1, 5) end
  end
  -- always a way to catch and a way to heal
  if ballIds[1] then save.inventory[ballIds[1]] = 20 end
  save.inventory[4] = 20
  save.inventory[17] = 5
end

-- ---------------------------------------------------------------------------
-- invariants
-- ---------------------------------------------------------------------------
local VALID_STATUS = { PSN = true, BRN = true, PAR = true, SLP = true, FRZ = true, TOX = true }

local function badNumber(v)
  return type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge
end

local function checkMon(mon, where, problems)
  if type(mon) ~= "table" then problems[#problems + 1] = where .. ": not a table"; return end
  if mon.stats and mon.stats.hp then
    if badNumber(mon.hp) then problems[#problems + 1] = ("%s: hp is %s"):format(where, tostring(mon.hp))
    elseif mon.hp < 0 then problems[#problems + 1] = ("%s: hp %s < 0"):format(where, mon.hp)
    elseif mon.hp > mon.stats.hp then problems[#problems + 1] = ("%s: hp %s > max %s"):format(where, mon.hp, mon.stats.hp)
    elseif mon.hp % 1 ~= 0 then problems[#problems + 1] = ("%s: fractional hp %s"):format(where, mon.hp) end
    for k, v in pairs(mon.stats) do
      if type(v) == "number" and (badNumber(v) or v < 0) then
        problems[#problems + 1] = ("%s: stat %s = %s"):format(where, tostring(k), tostring(v))
      end
    end
  end
  if mon.status ~= nil and not VALID_STATUS[mon.status] then
    problems[#problems + 1] = ("%s: odd status %s"):format(where, tostring(mon.status))
  end
  if badNumber(mon.level) or mon.level < 1 or mon.level > 100 then
    problems[#problems + 1] = ("%s: level %s"):format(where, tostring(mon.level))
  end
  for i, mv in ipairs(mon.moves or {}) do
    if mv.id == nil or Data.moves[mv.id] == nil then
      problems[#problems + 1] = ("%s: move slot %d has id %s"):format(where, i, tostring(mv.id))
    end
    if badNumber(mv.pp) or mv.pp < 0 then
      problems[#problems + 1] = ("%s: move slot %d pp %s"):format(where, i, tostring(mv.pp))
    end
  end
end

local function checkInvariants(battle, game)
  local problems = {}
  local party = game.save.party
  if type(party) ~= "table" or #party == 0 then
    problems[#problems + 1] = "player party is empty"
  else
    for i, m in ipairs(party) do checkMon(m, "party[" .. i .. "]", problems) end
  end
  for i, m in ipairs(battle.enemyParty or {}) do checkMon(m, "foe[" .. i .. "]", problems) end
  for _, b in battle:activeBattlers() do
    local label = (b.isPlayer and "player " or "foe ") .. tostring(b.name)
    if b.stages then
      for stat, v in pairs(b.stages) do
        if badNumber(v) or v < -6 or v > 6 then
          problems[#problems + 1] = ("%s: stage %s = %s"):format(label, tostring(stat), tostring(v))
        end
      end
    end
    for i, mv in ipairs(b.curMoves or {}) do
      if mv.id == nil or Data.moves[mv.id] == nil then
        problems[#problems + 1] = ("%s: battle move slot %d id %s"):format(label, i, tostring(mv.id))
      end
      if badNumber(mv.pp) or mv.pp < 0 then
        problems[#problems + 1] = ("%s: battle move slot %d pp %s"):format(label, i, tostring(mv.pp))
      end
    end
  end
  return problems
end

-- ---------------------------------------------------------------------------
-- driving screens
-- ---------------------------------------------------------------------------
local function screenId(state)
  return state and (state.screenId or state.name) or nil
end

local function partyIndices(game)
  local list = {}
  for i = 1, #game.save.party do list[#list + 1] = i end
  return list
end

-- the Gen 4 battle bag: use a random battle item (or back out)
local function driveBag(top, battle, game, ctx)
  top.fuzzVisits = (top.fuzzVisits or 0) + 1
  local choices = {}
  for id, n in pairs(game.save.inventory) do
    if n and n > 0 and Data.items[id] and (Data.items[id].battleUseCategory or 0) ~= 0 then
      choices[#choices + 1] = id
    end
  end
  table.sort(choices)
  if #choices == 0 or ctx.itemBudget <= 0 or rnd(1, 100) <= 10 then
    top:close()
    ctx.bagCancels = ctx.bagCancels + 1
    return
  end
  local id
  if ctx.wantBall and #ballIds > 0 and (game.save.inventory[ctx.wantBall] or 0) > 0 then
    id = ctx.wantBall
  else
    id = pick(choices)
  end
  local def = Data.items[id]
  if top.useSelected and not top.refusal then
    -- the field bag in a battle (single-screen presentation)
    ctx.itemBudget = ctx.itemBudget - 1
    ctx.itemUses = ctx.itemUses + 1
    ctx.usedItems[id] = (ctx.usedItems[id] or 0) + 1
    top:useSelected(id)
    return
  end
  ctx.itemBudget = ctx.itemBudget - 1
  ctx.itemUses = ctx.itemUses + 1
  ctx.usedItems[id] = (ctx.usedItems[id] or 0) + 1
  local row = { id = id }
  if def.pocket == "POKE_BALLS" and top.POCKET == nil and top.refusal then
    local okP, G = pcall(require, "src.ui.Gen4BattleBag")
    if okP and G.POCKET then top.pocket = G.POCKET.BALLS end
  end
  local why = top.refusal and top:refusal(row)
  if why then top:close(); return end
  local shim = {
    items = {}, index = 1,
    close = function() top:close() end,
    rebuild = function() if top.build then top:build() end end,
  }
  require("src.ui.BagMenu").useItem(game, battle, id, shim)
end

local function aliveIdx(game, avoidBattlers, battle)
  local standing = {}
  for _, b in battle:activeBattlers() do
    if b.isPlayer then standing[b.mon] = true end
  end
  local list = {}
  for i, m in ipairs(game.save.party) do
    if m.hp > 0 and not Party.isEgg(m) and not standing[m] then list[#list + 1] = i end
  end
  return list
end

local function driveParty(top, battle, game, ctx)
  local mode = top.mode or (top.pickOnly and "useItem") or "switch"
  if screenId(top) ~= "Gen4BattleParty" then
    -- the field party list inside a battle: pick the member directly
    local party = game.save.party
    local good = aliveIdx(game, nil, battle)
    local idx
    if mode == "useItem" then
      idx = pick(partyIndices(game))
      if rnd(1, 100) <= 8 then top:close(); return end
    else
      if not top.forceSwitch and (#good == 0 or rnd(1, 100) <= 15) then top:close(); return end
      if #good > 0 and (top.forceSwitch or rnd(1, 100) <= 85) then idx = pick(good)
      else idx = pick(partyIndices(game)) end
    end
    if os.getenv("FUZZ_DEBUG") then out("   [party] mode=%s forced=%s good=%d idx=%s hp=%s", mode, tostring(top.forceSwitch), #good, tostring(idx), tostring(party[idx] and party[idx].hp)) end
    top:handOff(party[idx])
    return
  end
  local party = game.save.party
  if mode == "learnMove" then
    local slot = rnd(1, 5)
    if top.pop then top:pop() end
    if top.onChoose then top.onChoose(slot <= 4 and slot or nil) end
    return
  end
  if mode == "useItem" then
    local idx = pick(partyIndices(game))
    local mon = party[idx]
    if rnd(1, 100) <= 8 then top:close(); return end
    if top.pop then top:pop() end
    if top.onMove and not Party.isEgg(mon) then
      top.onMove(mon, rnd(1, math.max(1, #mon.moves)))
    elseif top.onSwitch then
      top.onSwitch(mon, top)
    end
    return
  end
  -- switch / forced replacement
  local good = aliveIdx(game, nil, battle)
  local forced = top.forceSwitch
  if not forced and (#good == 0 or rnd(1, 100) <= 15) then top:close(); return end
  local idx
  if #good > 0 and (forced or rnd(1, 100) <= 85) then idx = pick(good)
  else idx = pick(partyIndices(game)) end
  local mon = party[idx]
  if os.getenv("FUZZ_DEBUG") then out("   [bparty] mode=%s forced=%s good=%d idx=%s hp=%s", mode, tostring(forced), #good, tostring(idx), tostring(mon and mon.hp)) end
  if top.handOff then top:handOff(mon)
  elseif top.onSwitch then
    if top.pop then top:pop() end
    top.onSwitch(mon, top)
  end
end

-- anything else on the stack (text boxes, choice boxes, the dex page, ...)
local function driveOverlay(top, ctx)
  ctx.overlayFrames = ctx.overlayFrames + 1
  local f = ctx.overlayFrames
  if f % 6 == 0 then
    local r = rnd(1, 100)
    if r <= 70 then keysDown.a = true
    elseif r <= 80 then keysDown.b = true
    elseif r <= 90 then keysDown.down = true
    else keysDown.up = true end
  end
end

-- ---------------------------------------------------------------------------
-- driving the battle's own menus
-- ---------------------------------------------------------------------------
local function movePower(mv)
  local d = mv and Data.moves[mv.id]
  return d and tonumber(d.power) or 0
end

local function driveBattle(battle, game, ctx)
  local phase = battle.phase
  if phase == "messages" then
    if ctx.frame % 2 == 0 then keysDown.a = true end
    return
  end
  if phase == "menu" then
    ctx.menuFrames = ctx.menuFrames + 1
    local who = battle:choosingBattler()
    if not (who and who.mon) then return end
    local actions = battle:menuActions()
    -- weights: fight / item / party / run (wild only)
    local choice
    local r = rnd(1, 100)
    local wild = battle.kind == "wild"
    local canRun = wild
    if ctx.menuTries > 6 then r = 1 end -- fall back to fight when stuck
    if r <= 62 then choice = "fight"
    elseif r <= 78 then choice = "item"
    elseif r <= 90 then choice = "party"
    elseif canRun then choice = "run"
    else choice = "fight" end
    -- in a wild battle, sometimes commit to throwing balls
    ctx.wantBall = nil
    if choice == "item" and wild and rnd(1, 100) <= 60 and #ballIds > 0 then
      ctx.wantBall = pick(ballIds)
    end
    local idx
    for i, a in ipairs(actions) do if a == choice then idx = i end end
    if not idx then
      for i, a in ipairs(actions) do if a == "fight" then idx = i end end
    end
    ctx.menuTries = ctx.menuTries + 1
    battle.menuIndex = idx or 1
    keysDown.a = true
    ctx.lastChoice = choice
    return
  end
  if phase == "moveSelect" then
    local chooser = battle:menuBattler()
    local moves = chooser.curMoves or {}
    -- prefer damaging moves with PP, but not always
    local best, any = {}, {}
    for i, mv in ipairs(moves) do
      any[#any + 1] = i
      if (mv.pp or 0) > 0 and movePower(mv) > 0 then best[#best + 1] = i end
    end
    local pickFrom = (#best > 0 and rnd(1, 100) <= 70) and best or any
    if #any == 0 then keysDown.b = true; return end
    battle.moveIndex = pick(pickFrom)
    if ctx.moveTries > 12 then keysDown.b = true; ctx.moveTries = 0; ctx.menuTries = 0; return end
    ctx.moveTries = ctx.moveTries + 1
    keysDown.a = true
    return
  end
  if phase == "targetSelect" then
    local list = battle.targetChoices or {}
    battle.targetIndex = rnd(1, math.max(1, #list))
    keysDown.a = true
    return
  end
  if phase == "mimicSelect" then
    local moves = battle.mimicMoves or {}
    battle.mimicIndex = rnd(1, math.max(1, #moves))
    keysDown.a = true
    return
  end
  ctx.unknownPhases[tostring(phase)] = true
  keysDown.a = true
end

-- ---------------------------------------------------------------------------
-- one battle
-- ---------------------------------------------------------------------------
local trainerIds = {}
screensSeen = {}

local function trainerLevelAround(rec)
  local sum, n = 0, 0
  for _, m in ipairs(rec.party or (rec.parties and rec.parties[1]) or {}) do
    sum = sum + (m.level or 1); n = n + 1
  end
  return n > 0 and math.floor(sum / n) or 20
end

local function buildBattle(spec)
  local game = Game
  game.save = SaveData.newGame(game.bootConfig and game:bootConfig() or {})
  game.save.options = game.save.options or {}
  game.save.options.animations = spec.anims
  game.save.options.battleStyle = pick({ "shift", "set" })
  -- which presentation: the bottom-screen battle bag / party (stowed=false)
  -- or the single-screen strip with the field bag and party
  local ui = spec.ui
  if ui == "bottom" or (ui == "mixed" and rnd(1, 100) <= 50) then
    game.save.options.secondScreenStowed = false
  else
    game.save.options.secondScreenStowed = true
  end
  game.save.options.textSpeed = "fast"
  local around = spec.around
  local minParty = spec.double and 2 or 1
  game.save.party = randomParty(minParty, around)
  -- the lead must be able to fight, the way a real save's lead can
  if spec.leadHealthy ~= false then
    game.save.party[1].hp = math.max(1, game.save.party[1].hp)
  end
  stockBag(game.save)
  local battle
  if spec.kind == "wild" then
    battle = BattleState.newWild(game, spec.species, spec.level)
    if spec.double then
      battle:makeWildDouble(Pokemon.new(Data, spec.second, math.max(1, math.min(100, spec.level + rnd(-3, 3)))))
    end
  else
    battle = BattleState.newTrainer(game, spec.trainer, 1)
    if spec.double then battle.double = true end
    if spec.tag then
      local allyRec = Data.trainers[spec.ally]
      local ok, party = pcall(BattleState.buildTrainerParty, game, spec.ally, 1, allyRec.parties[1])
      if ok and party then
        battle:setAlly({ name = allyRec.name or "ALLY", party = party, class = allyRec.class, trainerId = spec.ally })
        battle.double = true
      end
    end
    if battle.trainer and battle.trainer.doubleBattle then battle.double = true end
    if spec.trainerB then battle:addOpponentTrainer(spec.trainerB) end
    if battle.sendOutSecondPair then battle:sendOutSecondPair() end
  end
  return battle
end

local function describe(spec)
  if spec.kind == "wild" then
    return ("wild species=%s lv=%s%s"):format(spec.species, spec.level, spec.double and " double" or "")
  end
  return ("trainer=%s%s%s"):format(spec.trainer, spec.double and " double" or "",
    spec.tag and (" tag-ally=" .. tostring(spec.ally)) or "")
end

local function fieldDump(battle, game)
  local parts = {}
  for p = 0, 3 do
    local b = battle:battlerAt(p)
    parts[#parts + 1] = ("pos%d=%s"):format(p, b and ("%s %d/%d"):format(tostring(b.name), b.mon.hp, b.mon.stats.hp) or "empty")
  end
  local mons = {}
  for i, m in ipairs(game.save.party) do mons[#mons + 1] = ("%d:%s %d/%d"):format(i, tostring(m.species), m.hp, m.stats.hp) end
  local foes = {}
  for i, m in ipairs(battle.enemyParty or {}) do foes[#foes + 1] = ("%d:%s %d/%d"):format(i, tostring(m.species), m.hp, m.stats.hp) end
  return ("field: %s | party: %s | foe party: %s | pending=%s double=%s"):format(
    table.concat(parts, ", "), table.concat(mons, ", "), table.concat(foes, ", "),
    tostring(battle.pendingReplacements and #battle.pendingReplacements), tostring(battle:isDouble()))
end

local function drawBattle(battle, canvas)
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 1)
  local ok, err = xpcall(battle.draw, debug.traceback, battle)
  love.graphics.setCanvas()
  return ok, err
end

local function runOne(spec, seed, cfg)
  local result = { seed = seed, desc = describe(spec) }
  rnd = newRng(seed)
  currentSeed = seed
  love.math.setRandomSeed(seed)
  math.randomseed(seed)
  -- the harness's stack starts empty for every battle
  while Game.stack:top() do Game.stack:pop() end

  local okB, battle = xpcall(buildBattle, debug.traceback, spec)
  if not okB then
    result.status = "error"; result.where = "build"; result.err = battle
    return result
  end
  if battle.dead then
    result.status = "skip"; return result
  end
  local finishedWith
  local realPerform = battle.performMove
  battle.performMove = function(self, user, target, moveInst, ...)
    if type(moveInst) == "table" and moveInst.id ~= nil then
      movesSeen[moveInst.id] = (movesSeen[moveInst.id] or 0) + 1
    elseif os.getenv("FUZZ_DEBUG") then
      local keys = {}
      for k, v in pairs(moveInst or {}) do keys[#keys + 1] = tostring(k) .. "=" .. tostring(v) end
      out("   [dbg] performMove without an id: %s user=%s\n%s", table.concat(keys, ","), tostring(user and user.name), debug.traceback("", 2))
    end
    return realPerform(self, user, target, moveInst, ...)
  end
  if os.getenv("FUZZ_DEBUG") then
    local realChoose, realResolve = battle.chooseAction, battle.resolveTurn
    battle.chooseAction = function(self, a)
      local who = self:choosingBattler()
      out("   [dbg] chooseAction by %s pos=%s: id=%s special=%s", tostring(who and who.name), tostring(who and who.position),
          tostring(a and a.id), tostring(a and a.special))
      return realChoose(self, a)
    end
    battle.resolveTurn = function(self, a)
      out("   [dbg] resolveTurn first: id=%s special=%s pending: %s", tostring(a and a.id), tostring(a and a.special),
          tostring(self.pendingActions and (self.pendingActions[0] and "L" or "-") .. (self.pendingActions[2] and "R" or "-")))
      return realResolve(self, a)
    end
    local realBide = battle.continueBide
    battle.continueBide = function(self, user, target)
      out("   [dbg] continueBide user=%s pos=%s bideTurns=%s", tostring(user.name), tostring(user.position), tostring(user.bideTurns))
      for p = 0, 3 do
        local b = self:battlerAt(p)
        out("   [dbg]   pos%d %s bide=%s", p, b and b.name or "-", b and tostring(b.bideTurns) or "-")
      end
      return realBide(self, user, target)
    end
  end
  local realFinish = battle.finish
  battle.finish = function(self, ...)
    finishedWith = self.result or "run"
    return realFinish(self, ...)
  end
  battle.onFinish = function(r) finishedWith = finishedWith or r end
  local ctx = {
    frame = 0, menuFrames = 0, menuTries = 0, moveTries = 0, overlayFrames = 0,
    itemBudget = 12, itemUses = 0, bagCancels = 0, usedItems = {},
    unknownPhases = {}, lastChoice = "-",
  }
  local trace = cfg.trace and {} or nil
  if cfg.trace then
    local orig = battle.startMessage
    battle.startMessage = function(self, item)
      out("   [msg] %s", (tostring(item and item.text):gsub("[\n\v]", " / ")))
      return orig(self, item)
    end
  end
  local okS, errS = xpcall(function() Game.stack:push(battle) end, debug.traceback)
  if not okS then
    result.status = "error"; result.where = "enter"; result.err = errS
    return result
  end
  local lastTurn, lastProgress, lastItems = -1, 0, 0
  local frame = 0
  local lastPhase
  while not finishedWith do
    frame = frame + 1
    ctx.frame = frame
    keysDown = {}
    local top = Game.stack:top()
    local okF, errF = xpcall(function()
      if top == battle then
        driveBattle(battle, Game, ctx)
        if battle.phase ~= "menu" then ctx.menuTries = 0 end
        if battle.phase ~= "moveSelect" then ctx.moveTries = 0 end
      elseif top ~= nil then
        local sid = screenId(top)
        local dname = tostring(sid or StateStack.describe(top))
        screensSeen[dname] = (screensSeen[dname] or 0) + 1
        local isBag = sid and (sid:find("BagMenu$") or sid:find("BattleBag$"))
        if isBag then
          if (top.fuzzVisits or 0) == 0 or frame % 5 == 0 then driveBag(top, battle, Game, ctx) end
        elseif sid and (sid:find("PartyMenu$") or sid:find("BattleParty$")) then
          driveParty(top, battle, Game, ctx)
        elseif sid and sid:find("NamingScreen") then
          if top.close then top:close(rnd(1, 2) == 1 and "FUZZ" or nil)
          else Game.stack:pop() end
        else
          driveOverlay(top, ctx)
        end
      else
        error("the state stack is empty with the battle unfinished")
      end
      top = Game.stack:top()
      if top and top.update then top:update(1 / 60) end
      if cfg.draw > 0 and frame % cfg.draw == 0 and Game.stack:top() == battle then
        local okD, errD = drawBattle(battle, cfg.canvas)
        if not okD then error("draw: " .. tostring(errD), 0) end
      end
    end, debug.traceback)
    if not okF then
      result.status = "error"; result.where = "frame " .. frame; result.err = errF
      result.phase = battle.phase
      break
    end
    -- progress tracking: a turn counted, or a fresh menu, resets the hang clock
    local progress = (battle.turnCount or 0) * 4 + (battle.phase == "menu" and 1 or 0)
    local sig = tostring(battle.turnCount) .. tostring(battle.phase == "menu" and ctx.lastChoice or "")
    if (battle.turnCount or 0) ~= lastTurn then lastTurn = battle.turnCount or 0; lastProgress = frame end
    if ctx.itemUses ~= lastItems then lastItems = ctx.itemUses; lastProgress = frame end
    lastPhase = battle.phase
    if frame - lastProgress > cfg.hangFrames then
      result.status = "hang"
      result.dump = fieldDump(battle, Game)
      result.where = ("frame %d phase=%s top=%s queue=%d current=%s turn=%s"):format(
        frame, tostring(battle.phase), StateStack.describe(Game.stack:top()),
        #(battle.queue or {}), tostring(battle.current and (battle.current.text or battle.current.kind or "item")),
        tostring(battle.turnCount))
      break
    end
    if frame % 20 == 0 or finishedWith then
      local problems = checkInvariants(battle, Game)
      if #problems > 0 then
        result.status = "invalid"; result.err = table.concat(problems, "\n  ")
        break
      end
    end
    if (battle.turnCount or 0) > cfg.maxTurns then
      result.status = "stall"; break
    end
    if frame > cfg.maxTurns * 3000 then result.status = "hang"; result.where = "absolute frame budget"; break end
  end
  result.frames = frame
  result.turns = battle.turnCount or 0
  result.itemUses = ctx.itemUses
  if not result.status then
    local problems = checkInvariants(battle, Game)
    if #problems > 0 then result.status = "invalid"; result.err = table.concat(problems, "\n  ")
    else result.status = "ok"; result.outcome = finishedWith end
  end
  result.unknownPhases = next(ctx.unknownPhases) and ctx.unknownPhases or nil
  result.usedItems = ctx.usedItems
  return result
end

-- ---------------------------------------------------------------------------
-- choosing what to fight
-- ---------------------------------------------------------------------------
local function trainerRecord(id)
  local rec = Data.trainers[id]
  if rec and type(rec.parties) == "table" and type(rec.parties[1]) == "table" and rec.parties[1][1] then
    return rec
  end
end

local function isDoubleTrainer(rec)
  return (rec.doubleBattle or (tonumber(rec.battleType) or 0) ~= 0) and true or false
end

local function makeSpec(i, seed, mode, cfg)
  rnd = newRng(seed * 7919 + 17)
  local spec = { anims = cfg.anims, ui = cfg.ui }
  local m = mode
  if m == "all" then
    local r = rnd(1, 100)
    m = (r <= 40) and "wild" or (r <= 85) and "trainers" or (r <= 93) and "tag" or "doubles"
  end
  if cfg.trainer then m = "trainers" end
  if m == "wild" then
    spec.kind = "wild"
    spec.species = cfg.species or pick(speciesIds)
    local r = rnd(1, 100)
    spec.level = (r <= 70) and rnd(2, 40) or (r <= 90) and rnd(1, 100) or pick({ 1, 2, 3, 100 })
    spec.around = spec.level
    if cfg.wildDouble and rnd(1, 100) <= 8 then spec.double = true; spec.second = pick(speciesIds) end
    return spec
  end
  spec.kind = "trainer"
  if cfg.trainer then
    spec.trainer = cfg.trainer
  elseif mode == "trainers" then
    -- walk the table so every trainer is visited, in order
    spec.trainer = trainerIds[((i - 1) % #trainerIds) + 1]
  else
    local pool = {}
    for _, id in ipairs(trainerIds) do
      local rec = Data.trainers[id]
      if m == "doubles" and isDoubleTrainer(rec) then pool[#pool + 1] = id
      elseif m == "singles" and not isDoubleTrainer(rec) then pool[#pool + 1] = id
      elseif m == "tag" then pool[#pool + 1] = id end
    end
    if #pool == 0 then pool = trainerIds end
    spec.trainer = pick(pool)
  end
  local rec = Data.trainers[spec.trainer]
  spec.double = isDoubleTrainer(rec)
  spec.around = trainerLevelAround(rec)
  if m == "tag" then
    spec.tag = true
    spec.double = true
    spec.ally = pick(trainerIds)
    local rec2 = Data.trainers[spec.ally]
    if rec2 and #(rec2.parties[1] or {}) < 1 then spec.tag = nil end
  end
  return spec
end

-- ---------------------------------------------------------------------------
-- main
-- ---------------------------------------------------------------------------
local function summarise(err)
  -- the first line of the message, with addresses / numbers normalised, plus
  -- the first src/ frame of the traceback: what groups failures by root cause
  local first = (tostring(err):match("^[^\n]*") or ""):gsub("0x%x+", "0x?")
  local frame = tostring(err):match("(src/[%w_/%.]+:%d+)") or ""
  return first .. "  @" .. frame
end

function love.load(argv)
  parseArgs(argv or {})
  local ok, err = xpcall(function()
    setup()
    local cfg = {
      anims = opt("anims", 0) ~= 0,
      ui = opt("ui", "mixed"),
      draw = opt("draw", 0),
      maxTurns = opt("max-turns", 300),
      hangFrames = opt("hang-frames", 6000),
      verbose = ARGS.verbose ~= nil,
      trace = ARGS.trace ~= nil,
      trainer = ARGS.trainer and tonumber(ARGS.trainer) or nil,
      species = ARGS.species and tonumber(ARGS.species) or nil,
      wildDouble = ARGS["wild-double"] ~= nil,
    }
    if cfg.draw > 0 then cfg.canvas = love.graphics.newCanvas(256, 192) end
    local seed0 = opt("seed", 1)
    local count = opt("count", 100)
    local mode = opt("mode", "all")
    local stopOnFail = ARGS["stop-on-fail"] ~= nil

    for _, id in ipairs(sortedNumericKeys(Data.trainers)) do
      if trainerRecord(id) then trainerIds[#trainerIds + 1] = id end
    end
    out("fuzz: %d moves, %d species, %d trainers, %d battle items (%d balls)",
        #moveIds, #speciesIds, #trainerIds, #battleItemIds, #ballIds)
    out("fuzz: seed=%d count=%d mode=%s anims=%s draw=%d", seed0, count, mode, tostring(cfg.anims), cfg.draw)

    local tally = { ok = 0, error = 0, hang = 0, invalid = 0, stall = 0, skip = 0 }
    local groups, groupOrder = {}, {}
    local outcomes, usedItems = {}, {}
    local totalFrames, totalTurns = 0, 0
    local started = love.timer.getTime()
    for i = 1, count do
      local seed = seed0 + i - 1
      local spec = makeSpec(i, seed, mode, cfg)
      local before = {}
      for k, w in pairs(warnings) do before[k] = w.count end
      local result = runOne(spec, seed, cfg)
      for k, w in pairs(warnings) do
        if w.count > (before[k] or 0) and (k:find("forcing blackout") or k:find("unknown move") or k:find("battle")) then
          out("   note: seed=%d %s -> %s", seed, result.desc, w.sample:gsub("%s+", " "):sub(1, 120))
        end
      end
      tally[result.status] = (tally[result.status] or 0) + 1
      totalFrames = totalFrames + (result.frames or 0)
      totalTurns = totalTurns + (result.turns or 0)
      if result.outcome then outcomes[result.outcome] = (outcomes[result.outcome] or 0) + 1 end
      for id, n in pairs(result.usedItems or {}) do usedItems[id] = (usedItems[id] or 0) + n end
      if cfg.verbose or (result.status ~= "ok" and result.status ~= "skip" and result.status ~= "stall") then
        out("[%4d] seed=%d %s -> %s%s (%d turns, %d frames)", i, seed, result.desc, result.status,
            result.outcome and (" " .. result.outcome) or "", result.turns or 0, result.frames or 0)
      end
      if result.status == "error" or result.status == "invalid" or result.status == "hang" then
        local key = result.status .. ": " .. summarise(result.err or result.where or "")
        local g = groups[key]
        if not g then
          g = { count = 0, first = result, key = key }
          groups[key] = g; groupOrder[#groupOrder + 1] = key
        end
        g.count = g.count + 1
        g.seeds = g.seeds or {}
        if #g.seeds < 8 then g.seeds[#g.seeds + 1] = ("%d(%s)"):format(seed, result.desc) end
        if result.err then out("%s", tostring(result.err)) end
        if result.where then out("   where: %s", result.where) end
        if result.dump then out("   %s", result.dump) end
        if stopOnFail then break end
      end
      if result.unknownPhases then
        for p in pairs(result.unknownPhases) do out("   note: unknown phase %s (seed %d)", p, seed) end
      end
    end
    local elapsed = love.timer.getTime() - started
    out("")
    out("==== summary ====")
    out("battles: %d  ok=%d error=%d hang=%d invalid=%d stall=%d skip=%d", tally.ok + tally.error + tally.hang + tally.invalid + tally.stall + tally.skip,
        tally.ok, tally.error, tally.hang, tally.invalid, tally.stall, tally.skip)
    out("turns: %d  frames: %d  time: %.1fs", totalTurns, totalFrames, elapsed)
    local oc = {}
    for k, v in pairs(outcomes) do oc[#oc + 1] = k .. "=" .. v end
    table.sort(oc)
    out("outcomes: %s", table.concat(oc, " "))
    local nItems = 0
    for _ in pairs(usedItems) do nItems = nItems + 1 end
    out("distinct battle items used: %d", nItems)
    local nMoves, missing = 0, {}
    for _, id in ipairs(moveIds) do
      if movesSeen[id] then nMoves = nMoves + 1
      else missing[#missing + 1] = tostring(Data.moves[id].name or id) end
    end
    out("moves executed: %d of %d%s", nMoves, #moveIds,
        (#missing > 0 and #missing <= 40) and ("  never: " .. table.concat(missing, ", ")) or "")
    local sn = {}
    for k, v in pairs(screensSeen) do sn[#sn + 1] = k .. "=" .. v end
    table.sort(sn)
    out("overlay frames by screen: %s", table.concat(sn, " "))
    for _, key in ipairs(groupOrder) do
      local g = groups[key]
      out("FAILURE x%d  %s", g.count, key)
      out("   seeds: %s", table.concat(g.seeds, ", "))
    end
    local wkeys = {}
    for k in pairs(warnings) do wkeys[#wkeys + 1] = k end
    table.sort(wkeys)
    local noise = { "bad cry def", "in%-world 3D", "SecondScreen", "no glyph" }
    local shown = 0
    for _, k in ipairs(wkeys) do
      local w = warnings[k]
      local skip = false
      for _, n in ipairs(noise) do if w.sample:find(n) or k:find(n) then skip = true end end
      if not skip then
        if shown == 0 then out("engine warnings during the run:") end
        shown = shown + 1
        out("   x%d (first at seed %d) %s", w.count, w.seed, (w.sample:gsub("%s+", " "):sub(1, 220)))
      end
    end
    local failed = tally.error + tally.hang + tally.invalid
    love.event.quit(failed > 0 and 1 or 0)
  end, debug.traceback)
  if not ok then
    out("FUZZER FAILED:\n%s", tostring(err))
    love.event.quit(2)
  end
end

function love.draw() end
