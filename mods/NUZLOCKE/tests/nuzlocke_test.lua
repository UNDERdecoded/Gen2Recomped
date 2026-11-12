-- NUZLOCKE: the rules through the engine's runmodes.* seams, save/load,
-- run over, and two Soul Link partners over the world relay.
--
--   python tools/run_lua_check.py mods/NUZLOCKE/tests/nuzlocke_test.lua
--   POKEPORT_DATA_DIR=G:/Gen2Recomped/platinum/data/generated python tools/run_lua_check.py mods/NUZLOCKE/tests/nuzlocke_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Runtime = require("src.mods.Runtime")
local RunModes = require("src.runmodes.RunModes")
local RunHooks = require("src.runmodes.RunHooks")
local SaveSerializer = require("src.core.SaveSerializer")
-- the game the dataset is (G:/Gen2Recomped/<game>/data/generated)
do
  local dir = os.getenv("POKEPORT_DATA_DIR") or ""
  local id = dir:gsub("\\", "/"):match("([%w_]+)/data/generated/?$")
  if id and id ~= "Gen2Recomped" then pcall(require("src.core.GameVersion").set, id) end
end
local Data = require("src.core.Data")
local okData = pcall(Data.load, Data)
if not okData then Data = T.fixtures.fresh() end

-- vanilla first: nothing registered, a Nuzlocke save is inert
RunModes.provider = nil
local run = T.sdk.loadMod("mods/NUZLOCKE", { data = Data })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
T.check(RunModes.provider ~= nil, "the mod registers itself as the rules provider")
local Rules = RunModes.provider.rules
local Handshake = require("src.link.Handshake")
T.check(Handshake._rulesOnly(run.loader, "NUZLOCKE"), "the mod passes the run_rules online check")

-- a fake Game: a stack and a save
local function newStack()
  local st = { items = {} }
  function st:push(s) self.items[#self.items + 1] = s end
  function st:pop() return table.remove(self.items) end
  function st:top() return self.items[#self.items] end
  return st
end
local function newGame(choice)
  local save = { party = {}, boxes = { {}, {} }, player = { name = "RED", map = "ROUTE_1" },
                 inventory = { POKE_BALL = 5 } }
  RunModes.apply(save, choice)
  return { save = save, data = Data, stack = newStack(), maps = {} }
end
local function mon(species, hp) return { species = species, level = 5, hp = hp or 20, stats = { hp = 20 }, moves = {} } end

-- the engine seams, driven as BattleState drives them
local function wild(game, species, area, opts)
  game.overworld = { map = { id = area } }
  game.save.player.map = area
  local battle = { game = game, kind = "wild" }
  if opts and opts.static then
    RunHooks.static(RunHooks.wildStart, game, battle, species, opts)
  else
    RunHooks.wildStart(game, battle, species, opts)
  end
  return battle
end
local function catch(battle, m)
  table.insert(battle.game.save.party, m)
  RunHooks.caught(battle, m)
  RunHooks.battleEnd(battle, "caught")
end

-- ItemEffects.isBall needs the dataset's ball ids; fall back to a known one
local okE, ItemEffects = pcall(require, "src.inventory.ItemEffects")
local ballId = "POKE_BALL"
for id, def in pairs(Data.items or {}) do
  if okE and ItemEffects.isBall(id, def) then ballId = id break end
end

-- ------------------------------------------------------------ one per area --
local g = newGame({ nuzlocke = true, seed = 5 })
g.save.inventory = { [ballId] = 5 }
local b1 = wild(g, "PIDGEY", "R1")
T.check(not b1.noCatch, "the first encounter in an area may be caught")
catch(b1, mon("PIDGEY"))
local b2 = wild(g, "RATTATA", "R1")
T.check(b2.noCatch == true, "the second encounter there dodges every ball")
T.check(type(b2.runNoCatch) == "string", "with the Nuzlocke line")
local st = wild(g, "SNORLAX", "R1", { static = true })
T.check(not st.noCatch, "a static is always catchable")
local b3 = wild(g, "SPEAROW", "R2")
RunHooks.battleEnd(b3, "run")
T.eq(g.save.runModes.areas["map:R2"].state, "missed", "fleeing spends the area")
T.check(wild(g, "SPEAROW", "R2").noCatch, "and a missed area stays closed")
local g0 = newGame({ nuzlocke = true, seed = 5 })
g0.save.inventory = {}
local b0 = wild(g0, "PIDGEY", "R1")
RunHooks.battleEnd(b0, "run")
T.check(g0.save.runModes.areas["map:R1"] == nil, "an encounter before the first ball does not count")

-- ------------------------------------------------------------ death --
local pidgey = g.save.party[1]
local starter = mon("CHARMANDER")
table.insert(g.save.party, 1, starter)
RunHooks.fainted({ game = g, kind = "trainer" }, { isPlayer = true, mon = pidgey })
T.check(pidgey.nuzDead == true, "a fainted POKéMON is dead at once")
pidgey.hp = 20 -- a whiteout heal does not save it
RunHooks.fainted({ game = g, kind = "link" }, { isPlayer = true, mon = starter })
T.check(not starter.nuzDead, "a link battle faint does not count")
RunHooks.tick(g)
T.eq(#g.save.party, 1, "the dead leave the party on the next overworld frame")
T.eq(#g.save.runModes.graveyard, 1, "into the graveyard")
T.check(g.save.runModes.graveyard[1].mon == pidgey, "kept, not deleted")
-- the notice screen
T.check(g.stack:top() ~= nil, "the player is told")
g.stack.items = {}

-- ------------------------------------------------------------ save / load --
local encoded = SaveSerializer.encode(g.save)
local back = SaveSerializer.decode(encoded)
T.eq(back.runModes.areas["map:R1"].state, "caught", "the area record survives save/load")
T.eq(#back.runModes.graveyard, 1, "the graveyard survives save/load")
local g2 = { save = back, data = Data, stack = newStack() }
T.check(wild(g2, "ZUBAT", "R1").noCatch, "a reloaded run still refuses the used area")

-- ------------------------------------------------------------ run over --
RunHooks.fainted({ game = g, kind = "wild" }, { isPlayer = true, mon = starter })
RunHooks.tick(g)
T.eq(#g.save.party, 0, "the last POKéMON is gone")
local top = g.stack:top()
T.check(top and top.opts and top.opts.title == "RUN OVER", "RUN OVER is shown")
T.check(g.save.runModes.runOver == true, "the run is marked over")
T.check(g.save.party ~= nil and g.save.player.name == "RED", "the save itself is untouched")
-- PLAY ON, NO RULES
top.opts.rows[1].run(top)
T.eq(#g.save.party, 2, "every fallen POKéMON comes back")
T.check(not g.save.party[1].nuzDead, "no longer flagged dead")
T.check(not RunModes.nuzlocke(g.save), "the rules are off now")
local after = wild(g, "ODDISH", "R1")
T.check(not after.noCatch, "and no area is refused any more")

-- a normal save is never touched
local plain = { save = { party = { mon("EEVEE", 0) }, player = { name = "B" } }, data = Data, stack = newStack() }
RunHooks.fainted({ game = plain, kind = "wild" }, { isPlayer = true, mon = plain.save.party[1] })
RunHooks.tick(plain)
T.eq(#plain.save.party, 1, "a normal save keeps a fainted POKéMON")
T.check(plain.save.party[1].nuzDead == nil, "and never flags it")
T.check(plain.stack:top() == nil, "and shows nothing")

-- ------------------------------------------------------------ soul link --
local SoulLink = run.mod and run.loader.exports.NUZLOCKE and run.loader.exports.NUZLOCKE._lib and nil
local L = run.loader.exports.NUZLOCKE._lib
local SL = getmetatable(L.link).__index
local Svc = require("src.online.SoulLinkService")
local function chan()
  local c = { inbox = {}, out = {} }
  function c:send(m) self.out[#self.out + 1] = m end
  function c:poll() local m = self.inbox; self.inbox = {}; return m end
  return c
end
-- a member's view: what it sends lands in the service's inbox for it
local function member(svc, pid, name)
  local toSvc, toMe = chan(), chan()
  svc.open(toSvc, { pid = pid, name = name })
  local view = { closed = false }
  function view:send(m) toSvc.inbox[#toSvc.inbox + 1] = m end
  function view:poll()
    local out = toSvc.out; toSvc.out = {}; return out
  end
  return view
end
local function meet(save, area, m)
  Rules.wildStart(save.runModes, { area = area, species = m and m.species, hasBall = true })
  if m then Rules.caught(save.runModes, area, m) end
end
local function party(name, area)
  local save = { party = {}, boxes = { {} }, player = { name = name } }
  RunModes.apply(save, { soulLink = true, seed = 77 })
  Rules.ensure(save.runModes)
  local m = mon("X" .. name)
  meet(save, area, m)
  save.party[1] = m
  save.party[2] = mon("Y" .. name)
  meet(save, "R9", save.party[2])
  return save
end
local svc = Svc.new()
local sa, sb = party("A", "R5"), party("B", "R5")
local function sl(save, name)
  return setmetatable({ env = { save = function() return save end, now = function() return 0 end,
    name = function() return name end, game = function() return "red" end,
    kill = function(match, cause) return Rules.killWhere(save, match, cause, 0) end },
    ch = nil, partnerPid = nil }, { __index = SL })
end
local A, B = sl(sa, "A"), sl(sb, "B")
local function pump(n) for _ = 1, (n or 4) do svc.update(); A:pump(); B:pump() end end
A:attach(member(svc, 1, "A"))
B:attach(member(svc, 2, "B"))
pump()
T.check(sa.runModes.soul.partner and sa.runModes.soul.partner.name == "B", "A is bound to B")
T.check(sb.runModes.soul.partner and sb.runModes.soul.partner.name == "A", "B is bound to A")
-- A's R5 mon dies
sa.party[1].nuzDead = true
local res = Rules.sweep(sa, 0)
for _, e in ipairs(res.buried) do A:died(e.mon, e.cause) end
pump()
T.check(sb.party[1].nuzDead == true, "its partner's pair dies too")
T.check(not sb.party[2].nuzDead, "the other pair lives")
T.eq(#sa.runModes.soul.outbox, 0, "the partner acked the death")
-- offline: B misses R6 while A is away, A catches there later
B.ch = nil; B.partnerPid = nil
B:areaResult("R6", "missed")
T.eq(#sb.runModes.soul.outbox, 1, "an event waits in the save while offline")
local saved = SaveSerializer.decode(SaveSerializer.encode(sb))
for k, v in pairs(saved) do sb[k] = v end
B:attach(member(svc, 3, "B"))
pump(6)
T.eq(#sb.runModes.soul.outbox, 0, "it is delivered after reconnecting (and a reload)")
local late = mon("ZA")
sa.party[#sa.party + 1] = late
meet(sa, "R6", late)
A:areaResult("R6", "caught", late)
T.check(late.nuzDead == true, "catching where the partner missed breaks the pair")
-- a stranger's run is ignored
local sc = party("C", "R5")
local C = sl(sc, "C")
C:attach(member(svc, 4, "C"))
pump()
T.eq(sa.runModes.soul.partner.name, "B", "a third run does not steal the partner")
-- a resend never kills twice
local before = #sb.runModes.graveyard
B:handle({ type = "sl_ev", id = sa.runModes.soul.runId .. ":1", kind = "death", area = "R9" }, A.partnerPid and 1 or 1)
T.eq(#sb.runModes.graveyard, before, "a repeated event id is ignored")

-- a static / a pre-ball catch is free: no pair
local free = mon("FREE")
Rules.caught(sa.runModes, "R77", free)
T.check(free.soulPair == nil, "a catch with no counted encounter is not paired")

-- two DIFFERENT games: paired by encounter order, misses included
do
  local svc2 = Svc.new()
  local function save2(name)
    local s = { party = {}, boxes = { {} }, player = { name = name } }
    RunModes.apply(s, { soulLink = true, seed = 3 })
    Rules.ensure(s.runModes)
    return s
  end
  local red, crystal = save2("R"), save2("C")
  local function slg(save, name, game)
    return setmetatable({ env = { save = function() return save end, now = function() return 0 end,
      name = function() return name end, game = function() return game end,
      kill = function(match, cause) return Rules.killWhere(save, match, cause, 0) end },
      ch = nil, partnerPid = nil }, { __index = SL })
  end
  local R, C = slg(red, "R", "red"), slg(crystal, "C", "crystal")
  R:attach(member(svc2, 1, "R")); C:attach(member(svc2, 2, "C"))
  local function pump2() for _ = 1, 6 do svc2.update(); R:pump(); C:pump() end end
  pump2()
  -- encounter 1: both catch (different areas, different games)
  local r1, c1 = mon("PIDGEY"), mon("SENTRET")
  red.party[1] = r1; meet(red, "map:ROUTE_1", r1); R:areaResult("map:ROUTE_1", "caught", r1)
  crystal.party[1] = c1; meet(crystal, "sec:29", c1); C:areaResult("sec:29", "caught", c1)
  pump2()
  T.eq(r1.soulIdx, 1, "Red's first encounter is number 1")
  T.eq(c1.soulIdx, 1, "Crystal's first encounter is number 1")
  -- encounter 2: Red misses, Crystal catches -> Crystal's dies
  Rules.wildStart(red.runModes, { area = "map:ROUTE_2", hasBall = true })
  local rec = Rules.battleEnd(red.runModes, "map:ROUTE_2", "run")
  R:areaResult("map:ROUTE_2", "missed", nil, rec.idx)
  local c2 = mon("HOOTHOOT")
  crystal.party[2] = c2; meet(crystal, "sec:30", c2); C:areaResult("sec:30", "caught", c2)
  pump2()
  T.check(c2.nuzDead == true, "across games, a miss breaks the pair by encounter order")
  T.check(not c1.nuzDead, "and the first pair lives")
  -- encounter 1's death crosses games too
  r1.nuzDead = true
  for _, e in ipairs(Rules.sweep(red, 0).buried) do R:died(e.mon, e.cause) end
  pump2()
  T.check(c1.nuzDead == true, "a death crosses games by encounter order")
end

-- the save opts in; nothing about a normal save's link party changes
local Protocol = require("src.link.Protocol")
local okP, packed = pcall(Protocol.packParty, sb.party)
if okP then T.eq(#packed, 1, "the dead pair stays off a link battle") end

run.release()
T.finish("NUZLOCKE")
