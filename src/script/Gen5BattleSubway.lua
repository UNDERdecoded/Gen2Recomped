-- src/script/Gen5BattleSubway.lua -- BLACK AND WHITE'S BATTLE SUBWAY, RUN.
--
-- The Gear Station's platforms (Z067 Single, Z068 Super Single, Z069 Double,
-- Z070 Super Double, Z071 Multi, Z072 Super Multi, Z073 Wi-Fi), the train
-- car (Z075) and the end-of-line station (Z076) are driven by the cartridge's
-- own scripts: the receptionists (shared file 882, scripts 10330-10349), the
-- car (zone script 150) and the station (152). Everything they ask of the
-- facility goes through one command, 0x15A <function, a, b, dest> (ov21
-- 0x021CA5C4: a switch over ~120 function ids), plus 0x157 / 0x158 / 0x159
-- (clear, make and free the challenge's work, ov21 0x021C9924 / 0x021C9934 /
-- 0x021C9B24). This is that switch, function for function, over:
--
--   save.gen5Subway   the two save blocks the handler reads (0x39 play data,
--                     0x3A score data): per line the current streak (+8), the
--                     best (+0x1A), the trains begun (+0x2C, "stage"), the
--                     score flags (+4: bit 4.. cleared lines, 10, 1 ...), and
--                     the suspended challenge (mode, car, members, trainers,
--                     partner) for "Rest". BP are the shared frontier BP
--                     (Gen4BattleTower.addBP), so the exchange counters read
--                     the same purse.
--   game.gen5Subway   the challenge's work (0x7EC bytes on the cartridge):
--                     line, members, streak (+0xE), the flag word (+0xC: bit 0
--                     train cleared, bits 1-2 boss, 5-7 partner type), the 14
--                     trainer ids (+0x32), the opponents built for this car
--                     (+0x88, 0x120 each) and the Multi partner's three teams.
--
-- The tables (trainer ranges, BP, sprites, regulations, IVs) come from the
-- ROM through src/import/Gen5Subway.lua, as constants.gen5Subway. Wireless /
-- Wi-Fi functions answer as a cartridge with no partner in reach does: the
-- scripts take their "communication failed / not available" branches.
--
-- Loaded by Gen4ScriptVM (its last lines call `install` with the lowering
-- table).

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end
local Logger = require("src.core.Logger")

local M = {}

local function G4() return require("src.script.Gen4Commands") end
local function valueOf(ctx, n) return G4().valueOf(ctx, n) end
local function getVar(ctx, n) return G4().getVar(ctx.save, n) end
local function store(ctx, dest, value)
  dest = tonumber(dest)
  if dest and dest >= 0x4000 then G4().setVar(ctx.save, dest, math.floor(tonumber(value) or 0) % 65536) end
end

-- play modes (BSWAY_MODE_*): 0 Single, 1 Double, 2 Multi, 3 Multi with a
-- friend, 4 Wi-Fi, 5..8 the Super lines of 0..3
M.SINGLE, M.DOUBLE, M.MULTI, M.COMM_MULTI, M.WIFI = 0, 1, 2, 3, 4
M.S_SINGLE, M.S_DOUBLE, M.S_MULTI, M.S_COMM_MULTI = 5, 6, 7, 8
-- ov21 0x021CBCC4: the platform's line by zone (zone - 0x43)
M.ZONE_MODE = { [67] = 0, [68] = 5, [69] = 1, [70] = 6, [71] = 2, [72] = 7, [73] = 4 }
-- ov21 0x021CA270: the team size by mode
M.MEMBERS = { [0] = 3, 4, 2, 2, 3, 3, 4, 2, 2 }
-- ov21 0x021CBC94: the regulation by mode (20 Single, 21 Double, 22 Multi)
M.REGULATION = { [0] = "single", "double", "multi", "multi", "single", "single", "double", "multi", "multi" }
-- ov21 0x021DAD36: the score flag a cleared line sets (11 = none: Wi-Fi)
M.CLEAR_FLAG = { [0] = 4, 5, 6, 6, 11, 7, 8, 9, 9 }
-- ov21 0x021C9E04: the row of the BP table by mode
M.BP_ROW = { [0] = 0, 2, 4, 4, 6, 1, 3, 5, 5 }
M.SEVEN = 7

function M.isSuper(mode) return (tonumber(mode) or 0) >= 5 end
function M.isMulti(mode) mode = tonumber(mode) return mode == 2 or mode == 3 or mode == 7 or mode == 8 end

function M.rec(data)
  local r = data and data.constants and data.constants.gen5Subway
  return type(r) == "table" and r or nil
end

-- ------------------------------------------------------------- the save --

function M.score(save)
  save.gen5Subway = save.gen5Subway or {}
  local s = save.gen5Subway
  s.flags = s.flags or {}
  s.streak = s.streak or {}   -- [mode + 1]
  s.best = s.best or {}
  s.stage = s.stage or {}
  s.play = s.play or {}
  return s
end
local function sget(t, mode) return tonumber(t[(tonumber(mode) or 0) + 1]) or 0 end
local function sset(t, mode, v) t[(tonumber(mode) or 0) + 1] = math.max(0, math.floor(tonumber(v) or 0)) end

function M.flag(save, bit, op)
  local f = M.score(save).flags
  bit = tonumber(bit) or 0
  if bit >= 11 then return 0 end
  if op == 1 then f[bit + 1] = true elseif op == 2 then f[bit + 1] = nil end
  return f[bit + 1] and 1 or 0
end

function M.bp(save) return require("src.pokemon.Gen4BattleTower").bp(save) end
function M.addBP(save, n) return require("src.pokemon.Gen4BattleTower").addBP(save, n) end

-- 0x200DB80: the train index of a line, stage - 1 (never below 0)
function M.stageIndex(save, mode) return math.max(0, sget(M.score(save).stage, mode) - 1) end

-- the play data's car (param 1) -- 0..7 within the train
local function play(save) return M.score(save).play end
local function car(save) return tonumber(play(save).car) or 0 end

-- ------------------------------------------------------------- the work --

local function work(ctx) return ctx.game and ctx.game.gen5Subway end

-- 0x158 <kind, mode> (ov21 0x021C9934): kind 0 a new challenge on `mode`,
-- 1 the one "Rest" saved
function M.create(ctx, kind, mode)
  local save = ctx.save
  local s, p = M.score(save), play(save)
  local w = { mode = 0, count = 3, members = {}, species = {}, items = {}, streak = 0,
              cleared = false, boss = 0, partnerType = 0, bits = {}, trainers = {},
              opponents = {}, partners = {}, select = nil, result = nil }
  p.rested = false
  if (tonumber(kind) or 0) == 0 then
    w.mode = tonumber(mode) or 0
    w.count = M.MEMBERS[w.mode] or 3
    for i = 1, 4 do w.members[i] = 0xFF end
    for i = 1, 14 do w.trainers[i] = 0xFFFF end
    s.play = { mode = w.mode, car = 0 }
    p = s.play
    if sget(s.stage, w.mode) ~= 0 then w.streak = sget(s.streak, w.mode) end
  else
    w.mode = tonumber(p.mode) or 0
    w.count = M.MEMBERS[w.mode] or 3
    for i = 1, 4 do w.members[i] = (p.members or {})[i] or 0xFF end
    for i = 1, 14 do w.trainers[i] = (p.trainers or {})[i] or 0xFFFF end
    if M.isMulti(w.mode) then
      w.partnerType = tonumber(p.partnerType) or 0
      if type(p.partnerTeam) == "table" then w.partners[w.partnerType] = M.copy(p.partnerTeam) end
    end
    M.loadMembers(ctx, w)
    -- 0x021CA258: the streak is the train and the car
    if sget(s.stage, w.mode) ~= 0 then
      w.streak = math.min(0xFFFF, M.stageIndex(save, w.mode) * M.SEVEN + car(save))
    end
  end
  ctx.game.gen5Subway = w
  Logger.info("bw subway: challenge work made (kind %s, line %d, streak %d)", tostring(kind), w.mode, w.streak)
  return w
end

function M.copy(t)
  if type(t) ~= "table" then return t end
  local c = {}
  for k, v in pairs(t) do c[k] = M.copy(v) end
  return c
end

-- species and items of the entered members (0x021C9C54 / 0x021C9F44)
function M.loadMembers(ctx, w)
  local party = ctx.save.party or {}
  w.species, w.items = {}, {}
  for i = 1, w.count do
    local mon = party[(w.members[i] or 0xFF) + 1]
    w.species[i] = mon and tonumber(mon.species) or 0
    w.items[i] = mon and tonumber(mon.item) or 0
  end
end

-- ------------------------------------------------------------ trainers --

local function rand16() return love and love.math and love.math.random(0, 65535) or math.random(0, 65535) end

-- ov21 0x021CBD90: the trainer for train `round`, car `n` (0..6); `second`
-- picks Emmet's half of the Multi bosses
function M.trainerFor(rec, mode, round, n, second)
  local super = M.isSuper(mode)
  local boss
  if n == 6 then
    if not super and round == 2 then boss = 0 elseif super and round == 6 then boss = 1 end
  end
  local base = mode % 5
  if boss then
    if base == 0 then return 306 + boss end
    if base == 1 then return 308 + boss end
    if base == 2 or base == 3 then return boss * 2 + (second and 310 or 311) end
    return 0
  end
  local R = rec.ranges
  local range
  if not super then
    if round >= 3 then return 0 end
    range = (n < 6) and R.normal[round + 1] or R.normalLast[round + 1]
    if not range then return 0 end
  elseif round < 4 then
    range = (n < 6) and R.super[round + 1] or R.superLast[round + 1]
  else
    return R.superLate[1] + rand16() % 100
  end
  return range[1] + rand16() % (range[2] - range[1] + 1)
end

-- 0x13C (ov21 0x021C9E8C): the train's trainers, none twice -- fourteen on a
-- Multi line, a pair per car
function M.chooseTrainers(ctx, w)
  local rec = M.rec(ctx.game.data)
  if not rec then return end
  local round = math.floor(w.streak / M.SEVEN)
  local multi = M.isMulti(w.mode)
  if multi and (tonumber(w.partnerRound) or 0) > round then round = w.partnerRound end
  local count = multi and 14 or 7
  for k = 0, count - 1 do
    local id
    for _ = 1, 1000 do
      id = multi and M.trainerFor(rec, w.mode, round, math.floor(k / 2), k % 2 == 1)
                 or M.trainerFor(rec, w.mode, round, k, false)
      local dup = false
      for j = 1, k do if w.trainers[j] == id then dup = true break end end
      if not dup then break end
    end
    w.trainers[k + 1] = id
  end
  Logger.info("bw subway: train %d trainers %s", round + 1, table.concat(w.trainers, ",", 1, count))
end

-- the trainer's IVs (ov10 0x0216883C)
function M.ivsFor(rec, id)
  for _, band in ipairs(rec.ivBands or {}) do if id < band[1] then return band[2] end end
  return rec.ivTop or 31
end

local function rand32() return rand16() + rand16() * 65536 end

-- ov10 0x02168924: `count` sets from the trainer's list, no species twice
-- (nor one in `avoidSpecies`), no item twice while fewer than 50 picks have
-- been thrown out for it; then the IVs and one OT id for the team
function M.buildTeam(data, id, count, avoidSpecies, avoidItems)
  local rec = M.rec(data)
  local tr = rec and rec.trainers[id]
  if not (tr and tr.sets and #tr.sets > 0) then return nil end
  local picked, fails = {}, 0
  for _ = 1, 10000 do
    if #picked >= count then break end
    local setId = tr.sets[rand16() % #tr.sets + 1]
    local cur = rec.sets[setId]
    local bad = cur == nil
    if cur then
      for _, sid in ipairs(picked) do if rec.sets[sid].species == cur.species then bad = true end end
      for _, sp in ipairs(avoidSpecies or {}) do if sp == cur.species then bad = true end end
      if not bad and fails < 50 then
        local clash = false
        for _, sid in ipairs(picked) do
          local it = rec.sets[sid].item
          if it ~= 0 and it == cur.item then clash = true end
        end
        for _, it in ipairs(avoidItems or {}) do if it ~= 0 and it == cur.item then clash = true end end
        if clash then fails = fails + 1 bad = true end
      end
    end
    if not bad then picked[#picked + 1] = setId end
  end
  local ivs = M.ivsFor(rec, id)
  local otId = rand32()
  local out = {}
  for i, setId in ipairs(picked) do
    local mon = M.monFromSet(data, rec.sets[setId], ivs, otId)
    if fails >= 50 and rec.reservedItems then mon.item = rec.reservedItems[i] end
    mon.subwaySet = setId
    out[i] = mon
  end
  return out
end

-- ov10 0x021684E8: one set as a level-50 Pokemon
function M.monFromSet(data, s, ivs, otId)
  local Pokemon = require("src.pokemon.Pokemon")
  local Stats = require("src.pokemon.Stats")
  local mon = Pokemon.new(data, s.species, 50, nil, (s.form or 0) ~= 0 and s.form or nil)
  local pid = rand32()
  mon.personality, mon.otId, mon.shiny = pid, otId, false
  -- Black / White keep the nature apart from the personality
  local order = data.constants and data.constants.natureOrder
  mon.nature = order and order[(s.nature or 0) + 1] or s.nature
  mon.item = (s.item ~= 0) and s.item or nil
  mon.ivs = { hp = ivs, attack = ivs, defense = ivs, speed = ivs, spatk = ivs, spdef = ivs }
  local flagged = 0
  for k = 0, 5 do if math.floor((s.evFlags or 0) / 2 ^ k) % 2 == 1 then flagged = flagged + 1 end end
  local ev = flagged > 0 and math.min(255, math.floor(510 / flagged)) or 0
  local function e(k) return math.floor((s.evFlags or 0) / 2 ^ k) % 2 == 1 and ev or 0 end
  mon.evs = { hp = e(0), attack = e(1), defense = e(2), speed = e(3), spatk = e(4), spdef = e(5) }
  mon.happiness = 255
  mon.moves = {}
  for _, id in ipairs(s.moves) do
    if id ~= 0 then
      local md = data.moves and data.moves[id]
      mon.moves[#mon.moves + 1] = { id = id, pp = md and md.pp or 0 }
      if id == 218 then mon.happiness = 0 end   -- Frustration
    end
  end
  -- the second ability on an odd personality, when the species has one
  local def = require("src.pokemon.Gen4Forms").definition(data, mon)
  mon.abilitySlot = (pid % 2 == 1 and def and def.abilities and def.abilities[2]) and 2 or 1
  if def then
    mon.stats = Stats.calc(def, 50, mon.ivs, nil, mon.evs, mon.nature)
    mon.hp = mon.stats.hp
  end
  return mon
end

-- 0x133 (ov21 0x021CA05C): the car's opponent(s), built; on a Multi line the
-- second avoids the first's species and items
function M.buildOpponents(ctx, w)
  local data = ctx.game.data
  local n = car(ctx.save)
  w.opponents = {}
  if M.isMulti(w.mode) then
    local a = M.opponent(data, w.trainers[n * 2 + 1], w.count)
    w.opponents[1] = a
    local sp, it = {}, {}
    for i, mon in ipairs(a and a.party or {}) do sp[i] = mon.species; it[i] = mon.item or 0 end
    w.opponents[2] = M.opponent(data, w.trainers[n * 2 + 2], w.count, sp, it)
  else
    w.opponents[1] = M.opponent(data, w.trainers[n + 1], w.count)
  end
end

function M.opponent(data, id, count, avoidSpecies, avoidItems)
  local rec = M.rec(data)
  if not (rec and id and rec.trainers[id]) then return nil end
  return { id = id, class = rec.trainers[id].class, name = (rec.names or {})[id] or "?",
           party = M.buildTeam(data, id, count, avoidSpecies, avoidItems) or {} }
end

-- 0x14F (ov21 0x021CA338): the Multi partner's three teams -- Hilda for a
-- boy, Hilbert for a girl, focused on attack / defense / balance -- each
-- avoiding the player's species and items
function M.buildPartners(ctx, w)
  local girl = (ctx.save.player and (ctx.save.player.gender == "girl" or ctx.save.player.form == "girl")) and true or false
  local first = girl and 300 or 303
  w.partnerFirst = first
  for t = 0, 2 do
    w.partners[t] = M.opponent(ctx.game.data, first + t, w.count, w.species, w.items)
  end
end

-- ---------------------------------------------------------------- battle --

-- a facility trainer as a trainer record the battle builder reads
local function register(game, key, who, double)
  local G = require("src.script.Gen4BattleTowerCommands")
  game.data.trainers[key] = {
    id = key, index = who.class, class = who.class, name = who.name,
    className = G.className(game, who.class), source = "ROM:/a/2/1/5",
    parties = { G.prebuilt(who.party, 50) }, partyNames = { who.name }, baseMoney = 0,
    doubleBattle = double or nil, pic = G.trainerPic(game, who.class),
  }
  return key
end

-- the player's team (0x021CBD08): the entered members, as copies, at level
-- 50 (Gen4BattleTowerCommands.playerTeam's "level down" rule)
function M.playerTeam(game, w)
  local G = require("src.script.Gen4BattleTowerCommands")
  local slots = {}
  for i = 1, w.count do slots[i - 1] = w.members[i] end
  return G.playerTeam(game, { size = w.count, slots = slots })
end

function M.lineLabel(rec, id, k)
  return require("src.import.Gen5Text").label("system", rec.lineBank or 184, id * 3 + k)
end

-- 0x135 (ov10 0x0216C640 -> 0x0216E8CC): the car's battle
function M.battle(ctx, w)
  local game = ctx.game
  local rec = M.rec(game.data)
  local foe = w.opponents[1]
  if not (foe and #foe.party > 0) then
    Logger.warn("bw subway: no opponent built -- counted as a loss")
    w.result = 0
    return
  end
  local BattleState = require("src.battle.BattleState")
  local multi = M.isMulti(w.mode)
  local double = multi or w.mode % 5 == M.DOUBLE
  -- a Multi train's first foe is not itself a double trainer: built as one,
  -- the battle sends out two of the player's own before the partner
  -- (setAlly below) can take the right-hand place
  local key = register(game, "GEN5_SUBWAY", foe, double and not multi)
  local keyB = multi and w.opponents[2] and register(game, "GEN5_SUBWAY_B", w.opponents[2], true) or nil
  local ally
  local partner = multi and w.partners[w.partnerType]
  if partner and #partner.party > 0 then
    local pkey = register(game, "GEN5_SUBWAY_PARTNER", partner, true)
    local ok, party = pcall(BattleState.buildTrainerParty, game, pkey, 1, game.data.trainers[pkey].parties[1])
    if ok and type(party) == "table" and party[1] then
      ally = { party = party, name = partner.name, trainer = pkey, pic = game.data.trainers[pkey].pic }
    end
  end
  local real = ctx.save.party
  local team = M.playerTeam(game, w)
  local Aside = require("src.pokemon.PartyAside")
  Aside.hold(ctx.save, real)
  ctx.save.party = team
  local ok, battle = pcall(BattleState.newTrainer, game, key, 1)
  if not ok or not battle then
    ctx.save.party = real
    Aside.release(ctx.save)
    Logger.warn("bw subway: could not build the battle: %s", tostring(battle))
    w.result = 0
    return
  end
  battle.battleTower, battle.canLose, battle.noExp = true, true, true
  local lose = rec and game.data.text[M.lineLabel(rec, foe.id, 2)]
  if type(lose) == "string" and lose ~= "" then battle.endBattleText = (lose:gsub("[\n\r]+$", "")) end
  if double then
    battle.double = true
    if ally then battle:setAlly(ally) end
    if keyB then battle:addOpponentTrainer(keyB) end
    if battle.sendOutSecondPair then battle:sendOutSecondPair() end
  end
  local runner = ctx.runner
  battle.onFinish = function(result)
    ctx.save.party = real
    Aside.release(ctx.save)
    w.result = (result == "win") and 1 or 0
    Logger.info("bw subway: car %d against %s (%d) -- %s", car(ctx.save) + 1, foe.name, foe.id, tostring(result))
    ctx.lastBattleResult = result
    if runner then runner:resume() end
  end
  if ctx.overworld and ctx.overworld.pushBattle then ctx.overworld:pushBattle(battle)
  else game.stack:push(battle) end
  if runner then runner:yield() end
end

-- the trainer's line before the battle, over its object (0x140 / 0x160:
-- ov10 0x0216C6E8 prints system bank 184 entry id * 3)
function M.introLine(ctx, w, n)
  local rec = M.rec(ctx.game.data)
  local who = w.opponents[(tonumber(n) or 0) + 1]
  if not (rec and who) then return end
  local label = M.lineLabel(rec, who.id, 0)
  local text = ctx.game.data.text[label]
  if type(text) == "string" and text ~= "" then
    Commands.show_text(ctx, label)
  end
end

-- ------------------------------------------------------ the team choice --

-- 0x1BA <regulation, dest> -- the party or the Battle Box: 0 the party
-- passes, 1 the Battle Box, 2 cancelled, 3 not enough eligible Pokemon. No
-- Battle Box here, so the party is checked
function M.eligible(ctx, regKey)
  local rec = M.rec(ctx.game.data)
  local reg = rec and rec.regulations and rec.regulations[regKey]
  local banned = {}
  for _, sp in ipairs(reg and reg.banned or {}) do banned[sp] = true end
  local Party = require("src.pokemon.Party")
  local kinds, n = {}, 0
  for _, mon in ipairs(ctx.save.party or {}) do
    local sp = tonumber(mon.species) or 0
    if not Party.isEgg(mon) and not banned[sp] and not kinds[sp] then kinds[sp] = true n = n + 1 end
  end
  return n >= (reg and reg.count or 3), banned, reg
end

-- 0x12C (ov10 0x0216C538): choose the team, the regulation's count, no
-- banned species, none twice, no item twice
function M.chooseTeam(ctx, w)
  local _, banned, reg = M.eligible(ctx, M.REGULATION[w.mode])
  local runner = ctx.runner
  w.select = nil
  if os.getenv and os.getenv("BW_SUBWAY_AUTOPICK") then
    -- the harness: the first eligible members, as a player would enter them
    local picked, seen = {}, {}
    for i, mon in ipairs(ctx.save.party or {}) do
      local sp = tonumber(mon.species) or 0
      if not banned[sp] and not seen[sp] and #picked < w.count then picked[#picked + 1] = i seen[sp] = true end
    end
    w.select = #picked == w.count and picked or false
    Logger.info("bw subway: team entered %s", table.concat(picked, ","))
    return
  end
  local PM = require("src.ui.Gen4PartyMenu")
  ctx.game.stack:push(PM.new(ctx.game, { select = {
    count = w.count, banlist = banned, unique = true,
    onDone = function(slots) w.select = slots or false; if runner then runner:resume() end end,
  } }))
  if runner then runner:yield() end
  local _ = reg
end

-- ---------------------------------------------------------- the switch --

local F = {}
M.F = F

-- general functions (0x00-0x2D): no work needed
F[0x00] = function(ctx) -- the platform's line
  -- the loaded zone (the overworld's map first: the save's own field names
  -- it only once the game is saved)
  local ow = ctx.overworld
  local def = ow and ow.map and ow.map.def
  local mapId = (ow and ow.map and ow.map.id) or (ctx.save and ctx.save.player and (ctx.save.player.map or ctx.save.player.mapId))
  def = def or (mapId and ctx.game.data.maps and ctx.game.data.maps[mapId])
  local zone = tonumber(def and def.header) or tonumber(tostring(mapId or ""):match("%d+")) or 0
  return M.ZONE_MODE[zone] or 0
end
F[0x01] = function() return nil end                      -- a reset (Save and quit)
F[0x03] = function(ctx) return play(ctx.save).rested and 1 or 0 end   -- play data bit 1
F[0x02] = function(ctx) M.score(ctx.save).play = {} return nil end    -- clear the play data
F[0x04] = function() return nil end   -- the player's spot, kept as the continue point
F[0x05] = function(ctx) Commands.clear_flag(ctx, ("FLAG_G4_%04X"):format(0x966)) return nil end
F[0x06] = function(ctx, a) return math.min(9999, sget(M.score(ctx.save).streak, a)) end
F[0x07] = function(ctx) -- an unsaved challenge abandoned: the line's train count reset
  local s = M.score(ctx.save)
  local mode = tonumber(s.play.mode) or 0
  s.play.car = 0
  sset(s.stage, mode, 0)
  return mode
end
F[0x08] = function(ctx) return car(ctx.save) + 1 end
F[0x0B] = function(ctx) return car(ctx.save) + 1 end
F[0x0C] = function(ctx) -- the player's own overworld sprite
  local girl = ctx.save.player and (ctx.save.player.gender == "girl" or ctx.save.player.form == "girl")
  return girl and 4 or 1
end
F[0x0D] = function() return nil end                      -- an object's draw flag
F[0x0E] = function(ctx, a)                                -- line cleared?
  local bit = M.CLEAR_FLAG[tonumber(a) or 0] or 11
  if bit == 11 then return 1 end
  return M.flag(ctx.save, bit, 0)
end
F[0x0F] = function(ctx, a)
  local bit = M.CLEAR_FLAG[tonumber(a) or 0] or 11
  if bit ~= 11 then M.flag(ctx.save, bit, 1) end
  return nil
end
F[0x10] = function(ctx) return M.flag(ctx.save, 10, 0) end
F[0x11] = function(ctx) M.flag(ctx.save, 10, 1) return nil end
F[0x12] = function() return nil end                      -- the car's scenery
F[0x13] = function() return nil end                      -- train doors / motion
F[0x14] = function() return nil end
F[0x15] = function(ctx) return tonumber(play(ctx.save).mode) or 0 end
F[0x16] = function(_, a) return M.isMulti(a) and 1 or 0 end
F[0x17] = function() return nil end
F[0x18] = function() return nil end
F[0x19] = function(ctx, a)                                -- does object a exist?
  local ow = ctx.overworld
  local id = tonumber(a)
  for _, o in ipairs(ow and ow.map and ow.map.def and ow.map.def.objects or {}) do
    if o.localId == id and not o.hidden then return 1 end
  end
  return 0
end
F[0x1A] = function() return 0 end
F[0x1B] = function() return 1 end                        -- Wi-Fi rank
F[0x1C] = function() return 0 end
F[0x1D] = function() return 0 end
F[0x1E] = function(ctx, a) return M.stageIndex(ctx.save, a) end
F[0x1F] = function(ctx) -- the Multi partner's sprite (the other gender)
  local girl = ctx.save.player and (ctx.save.player.gender == "girl" or ctx.save.player.form == "girl")
  return girl and 1 or 4
end
F[0x22] = function() return nil end
F[0x23] = function() return nil end
F[0x24] = function() return nil end
F[0x25] = function() return nil end
F[0x26] = function(ctx, a) return sget(M.score(ctx.save).stage, a) ~= 0 and 1 or 0 end
F[0x27] = function() return 0 end
F[0x28] = function() return 0 end
F[0x29] = function() return 0 end
F[0x2A] = function() return 0 end
F[0x2B] = function() return 0 end
F[0x2C] = function(ctx, a) -- a yes / no with the cursor on NO when a = 1 (0 = yes)
  local runner = ctx.runner
  local Gen4YesNo = Commands.g4_yes_no or Commands.yes_no
  if os.getenv and os.getenv("BW_SUBWAY_NO") then return 1 end
  if Gen4YesNo and runner then
    local dest = 0x8141
    local ok = pcall(Gen4YesNo, ctx, dest)
    if ok then return getVar(ctx, dest) end
  end
  return 1
end
F[0x2D] = function(ctx) Commands.set_flag(ctx, ("FLAG_G4_%04X"):format(0x966)) return nil end

-- the record app / Wi-Fi (0x64-0x71)
F[0x64] = function(ctx, a) M.flag(ctx.save, 1, (tonumber(a) or 0) == 0 and 2 or 1) return nil end
F[0x65] = function(ctx) return M.flag(ctx.save, 1, 0) end
F[0x67] = function() return 0 end
F[0x68] = function() return 0 end
F[0x69] = function() return 0 end
F[0x6B] = function() return 0 end
F[0x6C] = function(ctx, a) play(ctx.save).p11 = tonumber(a) or 0 return nil end
F[0x6D] = function(ctx) return tonumber(play(ctx.save).p11) or 0 end
F[0x6F] = function() return nil end
F[0x70] = function() return 0 end
F[0x71] = function() return 0 end
F[0xC8] = function() return 0 end
F[0xC9] = function() return nil end
F[0xCA] = function() return nil end
F[0xCB] = function() return 0 end
F[0x1F5] = function() return nil end

-- the challenge's work (0x12C on): nothing happens without it
local W = {}
M.W = W
W[0x12C] = function(ctx, w) M.chooseTeam(ctx, w) return nil end
W[0x12D] = function(ctx, w) -- the team, read back (0x021C9F44): 1 entered, 0 cancelled
  if type(w.select) ~= "table" or #w.select < w.count then return 0 end
  for i = 1, w.count do w.members[i] = w.select[i] - 1 end
  M.loadMembers(ctx, w)
  return 1
end
W[0x12F] = function(ctx, w) -- the train done? (7 cars)
  if w.cleared then return 1 end
  if car(ctx.save) >= M.SEVEN then w.cleared = true return 1 end
  return 0
end
W[0x130] = function(ctx, w) -- LOST (0x021C9D70): the streak stands as it was
  local s = M.score(ctx.save)
  sset(s.streak, w.mode, w.streak)
  if w.streak > sget(s.best, w.mode) then sset(s.best, w.mode, w.streak) end
  sset(s.stage, w.mode, 0)
  s.play.car = 0
  return nil
end
W[0x131] = function(ctx, w) -- the train WON (0x021C9FFC)
  local s = M.score(ctx.save)
  sset(s.streak, w.mode, w.streak)
  if w.streak > sget(s.best, w.mode) then sset(s.best, w.mode, w.streak) end
  sset(s.stage, w.mode, math.min(0xFFFE, sget(s.stage, w.mode) + 1))
  s.play.car = 0
  return nil
end
local function suspend(ctx, w, rested) -- 0x132 / 0x141 (0x021C9BCC / 0x021C9CAC)
  local p = play(ctx.save)
  p.mode = w.mode
  if not rested then p.car = 0 end
  p.members = {}
  for i = 1, 4 do p.members[i] = w.members[i] end
  p.trainers = {}
  for i = 1, 14 do p.trainers[i] = w.trainers[i] end
  p.rested = rested and true or false
  if M.isMulti(w.mode) then
    p.partnerType = w.partnerType
    p.partnerTeam = M.copy(w.partners[w.partnerType])
  end
end
W[0x132] = function(ctx, w) suspend(ctx, w, true) return nil end
W[0x133] = function(ctx, w) M.buildOpponents(ctx, w) return nil end
W[0x134] = function(ctx, w, a) -- the opponent's overworld sprite
  local rec = M.rec(ctx.game.data)
  local who = w.opponents[(tonumber(a) or 0) + 1]
  if not (rec and who) then return 10 end
  return (rec.classSprite or {})[who.class] or rec.defaultSprite or 10
end
W[0x135] = function(ctx, w) M.battle(ctx, w) return nil end
W[0x136] = function(_, w) return w.mode end
W[0x137] = function(_, w, a) w.boss = (tonumber(a) or 0) % 4 return nil end
W[0x138] = function(_, w) return w.boss end
W[0x139] = function(ctx, w) -- the BP for the train (0x021C9DB0)
  local rec = M.rec(ctx.game.data)
  local bp
  if w.mode == M.WIFI then
    bp = 5
  else
    local idx = math.min(9, math.max(0, M.stageIndex(ctx.save, w.mode) - 0))
    -- 0x200DB80 is stage - 1, then the handler takes one more off (0..9)
    idx = math.min(9, math.max(0, sget(M.score(ctx.save).stage, w.mode) - 1 - 1))
    if w.boss ~= 0 then
      bp = M.isSuper(w.mode) and (rec and rec.superBossBp or 30) or (rec and rec.bossBp or 10)
    else
      local row = rec and rec.bp and rec.bp[(M.BP_ROW[w.mode] or 0) + 1]
      bp = row and row[idx + 1] or 3
    end
  end
  if bp == 0 then bp = 1 end
  M.addBP(ctx.save, bp)
  Logger.info("bw subway: %d BP (line %d, train %d) -- %d now", bp, w.mode, sget(M.score(ctx.save).stage, w.mode), M.bp(ctx.save))
  return bp
end
W[0x13A] = function(_, w, a) w.partnerType = (tonumber(a) or 0) % 8 return nil end
W[0x13C] = function(ctx, w) M.chooseTrainers(ctx, w) return nil end
W[0x13F] = function() return nil end
W[0x140] = function(ctx, w, a) M.introLine(ctx, w, a) return nil end
W[0x141] = function(ctx, w) suspend(ctx, w, false) return nil end
W[0x142] = function(ctx) Commands.set_flag(ctx, ("FLAG_G4_%04X"):format(0x966)) return nil end
W[0x144] = function(ctx, _, a) play(ctx.save).box = tonumber(a) or 0 return nil end
W[0x145] = function() return nil end                     -- the friend Multi line
W[0x146] = function(ctx) local m = tonumber(play(ctx.save).mode) or 0 return (m >= 5 and m <= 8) and 1 or 0 end
W[0x149] = function() return nil end                     -- the station's setup
W[0x14A] = function(_, w, a) w.bits[8] = tonumber(a) or 0 return nil end
W[0x14B] = function(_, w) return w.bits[8] or 0 end
W[0x14C] = function(_, w) return w.result or 0 end       -- the battle won?
W[0x14D] = function(_, w) w.cleared, w.boss = false, 0 return nil end   -- a new train (0x021CA048)
W[0x14E] = function() return nil end
W[0x14F] = function(ctx, w) M.buildPartners(ctx, w) return nil end
W[0x150] = function(_, w, a) return w.species[(tonumber(a) or 0) + 1] or 0 end
W[0x151] = function(_, w, a) w.bits[9] = tonumber(a) or 0 return nil end
W[0x152] = function(_, w) return w.bits[9] or 0 end
W[0x154] = function() return nil end
W[0x155] = function(_, w) return ({ single = 20, double = 21, multi = 22 })[M.REGULATION[w.mode]] or 20 end
W[0x157] = function() return nil end
W[0x158] = function() return 0 end
W[0x159] = function() return nil end
W[0x15A] = function() return nil end
W[0x15B] = function() return nil end
W[0x15D] = function(ctx, w) -- the line's end: car and train count back to 0
  local s = M.score(ctx.save)
  s.play.car = 0
  sset(s.stage, tonumber(s.play.mode) or w.mode, 0)
  return nil
end
W[0x15E] = function() return nil end
W[0x15F] = function(ctx, w, a) -- the trainer of the car (a: which of a pair)
  local n = car(ctx.save)
  if M.isMulti(w.mode) then return w.trainers[n * 2 + (tonumber(a) or 0) + 1] or 0 end
  return w.trainers[n + 1] or 0
end
W[0x160] = function(ctx, w, a) M.introLine(ctx, w, a) return nil end
W[0x161] = function() return nil end
W[0x162] = function(_, w, a) w.bits[12] = tonumber(a) or 0 return nil end
W[0x163] = function(_, w) return w.bits[12] or 0 end
W[0x164] = function(ctx) return tonumber(play(ctx.save).box) or 0 end
W[0x165] = function(ctx, w) -- one car won: car + 1, streak + 1
  local p = play(ctx.save)
  p.car = math.min(255, car(ctx.save) + 1)
  w.streak = math.min(0xFFFF, w.streak + 1)
  return math.min(9999, w.streak)
end
W[0x166] = function(_, w) return math.min(9999, w.streak) end
W[0x167] = function(ctx, w) -- a train begun: the line's count from 1
  local s = M.score(ctx.save)
  if sget(s.stage, w.mode) == 0 then
    sset(s.stage, w.mode, 1)
    s.play.car = 0
    w.streak = 0
  end
  return nil
end
-- the friend's DS (0x190-0x1A0): nobody there
for id = 0x190, 0x1A0 do W[id] = function() return 0 end end
W[0x19B] = function(ctx) return F[0x0C](ctx) end
W[0x19C] = function(ctx) return F[0x1F](ctx) end

-- ---------------------------------------------------------- commands --

function Commands.g5_subway(ctx, fn, a, b, dest)
  fn = tonumber(fn) or -1
  local av, bv = valueOf(ctx, a), valueOf(ctx, b)
  local value
  local f = F[fn]
  if f then
    value = f(ctx, av, bv)
  else
    local w = work(ctx)
    local h = W[fn]
    if not w then
      Logger.warn("bw subway: function 0x%X with no challenge work", fn)
    elseif h then
      value = h(ctx, w, av, bv)
    else
      Logger.info("bw subway: function 0x%X is not modelled", fn)
    end
  end
  if os.getenv and os.getenv("BW_SUBWAY_TRACE") then
    print(("[subway] 0x%03X(%s,%s) -> %s"):format(fn, tostring(av), tostring(bv), tostring(value)))
  end
  if value ~= nil then store(ctx, dest, value) end
end
Commands.meta = Commands.meta or {}
Commands.meta.g5_subway = { foreground = true, blocking = true }

function Commands.g5_subway_init(ctx) local _ = ctx end
function Commands.g5_subway_create(ctx, kind, mode)
  M.create(ctx, tonumber(kind) or 0, valueOf(ctx, mode))
end
function Commands.g5_subway_free(ctx) if ctx.game then ctx.game.gen5Subway = nil end end

-- 0x1BA <regulation, dest>: the party (0) or the Battle Box (1), 2
-- cancelled, 3 nothing eligible
function Commands.g5_subway_team_source(ctx, reg, dest)
  local key = ({ [20] = "single", [21] = "double", [22] = "multi" })[valueOf(ctx, reg)] or "single"
  local ok = M.eligible(ctx, key)
  store(ctx, dest, ok and 0 or 3)
end

-- 0x067 <object, xVar, zVar>: an object's tile (0xFF the player), in the
-- zone's own coordinates as the scripts compare them
function Commands.g5_object_pos(ctx, object, xVar, zVar)
  local ow = ctx.overworld
  local id = valueOf(ctx, object)
  local x, y
  if id == 0xFF then
    local p = ctx.save.player or {}
    x, y = p.x, p.y
  elseif ow and ow.npcs then
    for _, npc in pairs(ow.npcs) do
      if npc.def and npc.def.localId == id then x, y = npc.x, npc.y end
    end
  end
  local ox, oy = 0, 0
  local okO, a, b = pcall(G4().mapOrigin, ctx)
  if okO then ox, oy = tonumber(a) or 0, tonumber(b) or 0 end
  store(ctx, xVar, (tonumber(x) or 0) + ox)
  store(ctx, zVar, (tonumber(y) or 0) + oy)
end

-- 0x13B <var>: wireless play on? Never here -- except the Poke Transfer Lab,
-- whose transfer is local in this port (src/world/Gen5PokeTransfer.lua)
--
-- THE MULTI PLATFORMS (Z071 Multi, Z072 Super Multi): the receptionist's
-- "with a friend" choice (file 882, S05E0 at 1504) asks this first.  The
-- port runs the friend's train there and then (src/online/SubwayMulti.lua:
-- leader / join, the code, two Pokemon each, car after car, each player's
-- streak and BP), answers 0, and steps over the "wireless is off" line the
-- script would say next, so the counter's own farewell closes it.
M.MULTI_ZONES = { Z071 = false, Z072 = true }   -- zone -> Super line

local function skipWirelessOffLine(ctx)
  local sc, pc = ctx.script, ctx.pc
  if type(sc) ~= "table" or not pc then return nil end
  local r1, r2 = sc[pc + 1], sc[pc + 2]
  if not (type(r1) == "table" and r1[1] == "g4_compare_var_value" and tonumber(r1[3]) == 0
          and type(r2) == "table" and r2[1] == "g4_jump_if") then return nil end
  for k = pc + 3, math.min(#sc, pc + 6) do
    local r = sc[k]
    if type(r) == "table" and r[1] == "g4_common" then return k + 1 end
    if type(r) == "table" and r[1] == "g4_call" and type(sc[k + 1]) == "table" and sc[k + 1][1] == "jump"
       and type(sc[k + 2]) == "table" and sc[k + 2][1] == "label" then
      return k + 2
    end
  end
  return nil
end

function M.friendTrain(ctx, super)
  local okL, LinkRooms = pcall(require, "src.online.LinkRooms")
  if not (okL and ctx.game and ctx.game.stack and LinkRooms.available()) then return nil end
  local MultiBattle = require("src.online.MultiBattle")
  local o = MultiBattle.withDefaults({ super = super, askRole = true })
  local summary
  LinkRooms.await(ctx, function(done)
    local lobby = require("src.online.SubwayMulti").run(ctx.game, nil, o, function(sum)
      summary = sum
      done(sum)
    end)
    if MultiBattle.onLobby then pcall(MultiBattle.onLobby, lobby) end
  end)
  M.lastFriendTrain = summary
  return summary
end

function Commands.g5_subway_wireless(ctx, dest)
  local here = ctx.overworld and ctx.overworld.map and ctx.overworld.map.id
  if here and M.MULTI_ZONES[here] ~= nil then
    local summary = M.friendTrain(ctx, M.MULTI_ZONES[here])
    if summary then
      store(ctx, dest, 0)
      return skipWirelessOffLine(ctx)
    end
  end
  local okT, T = pcall(require, "src.world.Gen5PokeTransfer")
  store(ctx, dest, (okT and T.isLab(here)) and 1 or 0)
end

-- 0x137 <var>: the save the "Saving..." boxes stand over; 1 = written
function Commands.g5_subway_save(ctx, dest)
  local ok = Commands.g4_try_save_game and pcall(Commands.g4_try_save_game, ctx, dest)
  if not ok then store(ctx, dest, 1) end
end

function M.install(L)
  L.bwsubway = function(ins, s)
    s.out[#s.out + 1] = { "g5_subway", ins.args[1], ins.args[2], ins.args[3], ins.args[4] }
  end
  L.bwsubwayinit = function(_, s) s.out[#s.out + 1] = { "g5_subway_init" } end
  L.bwsubwaycreate = function(ins, s) s.out[#s.out + 1] = { "g5_subway_create", ins.args[1], ins.args[2] } end
  L.bwsubwayfree = function(_, s) s.out[#s.out + 1] = { "g5_subway_free" } end
  L.bwteamsource = function(ins, s) s.out[#s.out + 1] = { "g5_subway_team_source", ins.args[1], ins.args[2] } end
  L.bwobjectpos = function(ins, s) s.out[#s.out + 1] = { "g5_object_pos", ins.args[1], ins.args[2], ins.args[3] } end
  L.bwsavegame = function(ins, s) s.out[#s.out + 1] = { "g5_subway_save", ins.args[1] } end
  L.bwwirelessoff = function(ins, s) s.out[#s.out + 1] = { "g5_subway_wireless", ins.args[1] } end
end

return M
