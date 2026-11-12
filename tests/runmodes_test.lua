-- RUN MODES (src/runmodes): the per-save field, the seeded randomizer, the
-- engine seams, and the online filters.
--
--   python tools/run_lua_check.py tests/runmodes_test.lua
--   POKEPORT_DATA_DIR=G:/Gen2Recomped/<game>/data/generated python tools/run_lua_check.py tests/runmodes_test.lua
--
-- Without POKEPORT_DATA_DIR the randomizer checks run on the fixture dataset.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local T = require("tests.harness")

local RunModes = require("src.runmodes.RunModes")
local Randomizer = require("src.runmodes.Randomizer")
local RunHooks = require("src.runmodes.RunHooks")
local SaveSerializer = require("src.core.SaveSerializer")
-- the game the dataset is (G:/Gen2Recomped/<game>/data/generated)
do
  local dir = os.getenv("POKEPORT_DATA_DIR") or ""
  local id = dir:gsub("\\", "/"):match("([%w_]+)/data/generated/?$")
  if id and id ~= "Gen2Recomped" then pcall(require("src.core.GameVersion").set, id) end
end
local Data = require("src.core.Data")
local okLoad, loadErr = pcall(Data.load, Data)
T.check(okLoad, "dataset loads (" .. tostring(loadErr) .. ")")
local GameVersion = require("src.core.GameVersion")
local gen = tonumber(Data.constants and Data.constants.gen) or GameVersion.generation() or 1

-- ------------------------------------------------------------ the field --
local plain = { party = {}, player = { name = "RED" } }
T.check(RunModes.get(plain) == RunModes.OFF, "a save without runModes reads OFF")
T.check(not RunModes.any(plain), "no mode on an old save")
T.check(not RunModes.nuzlocke(plain), "no nuzlocke on an old save")
T.check(RunModes.summary(plain) == nil, "no hello summary on an old save")
T.check(not pcall(function() RunModes.OFF.nuzlocke = true end), "OFF is read-only")
RunModes.apply(plain, { nuzlocke = false, randomWild = false })
T.check(plain.runModes == nil, "an all-off choice writes nothing")

local s = { party = {}, player = { name = "RED" } }
RunModes.apply(s, { soulLink = true, randomWild = true })
T.check(s.runModes.nuzlocke and s.runModes.soulLink, "Soul Link implies Nuzlocke")
T.check(type(s.runModes.seed) == "number", "a seed is rolled")
T.eq(RunModes.describe(s), "SOUL LINK + RANDOM WILD", "describe")
T.same(RunModes.summary(s), { nuzlocke = true, soulLink = true, randomWild = true }, "hello summary")

-- pending choice -> SaveData.newGame
local SaveData = require("src.core.SaveData")
RunModes.setPending({ nuzlocke = true, seed = 1234 })
local fresh = SaveData.newGame({})
T.check(fresh.runModes and fresh.runModes.nuzlocke and fresh.runModes.seed == 1234,
  "SaveData.newGame takes the NEW GAME choice")
T.check(RunModes.pending == nil, "the pending choice is consumed once")
local vanilla = SaveData.newGame({})
T.check(vanilla.runModes == nil, "a NEW GAME with nothing chosen has no runModes field")

-- ------------------------------------------------------------ randomizer --
local pokemon = Data.pokemon or {}
local pool = Randomizer.pool(pokemon, gen)
T.check(#pool > 0, ("the species pool is not empty (gen %d, %d species)"):format(gen, #pool))
local someWild
for id in pairs(pokemon) do
  local d = Randomizer._dexOf(id, pokemon[id])
  if d and d >= 10 and d <= 100 and Randomizer._bst(pokemon[id]) > 0 then someWild = id break end
end
T.check(someWild ~= nil, "found a wild species to replace")
local A = { runModes = { randomWild = true, randomStarters = true, seed = 42 } }
local B = { runModes = { randomWild = true, seed = 43 } }
local first = Randomizer.wild(A, Data, someWild, "ROUTE_1", gen)
T.eq(Randomizer.wild(A, Data, someWild, "ROUTE_1", gen), first, "same seed, same slot -> same species")
local decoded = SaveSerializer.decode(SaveSerializer.encode({ runModes = A.runModes }))
T.eq(Randomizer.wild(decoded, Data, someWild, "ROUTE_1", gen), first, "the pick survives a save/load")
local differs = false
for i = 1, 20 do
  if Randomizer.wild(B, Data, someWild, "MAP_" .. i, gen) ~= Randomizer.wild(A, Data, someWild, "MAP_" .. i, gen) then
    differs = true break
  end
end
T.check(differs, "another seed gives other species")
T.eq(Randomizer.wild({}, Data, someWild, "ROUTE_1", gen), someWild, "randomizer off -> unchanged")
T.check(pokemon[first] ~= nil, "the replacement is a species of this dataset")
local b0, b1 = Randomizer._bst(pokemon[someWild]), Randomizer._bst(pokemon[first])
T.check(math.abs(b1 - b0) <= b0 * 0.45 + 60, ("strength band kept (%d -> %d)"):format(b0, b1))

-- every encounter is its own pick: varied, never twice running, and the
-- same sequence again after a reload (the counter is in the save)
do
  local vg = { save = { runModes = { randomWild = true, seed = 77 }, party = {}, player = { map = "R1" } },
               data = Data }
  local snapshot = SaveSerializer.decode(SaveSerializer.encode(vg.save))
  local seq, distinct, repeats = {}, {}, 0
  for i = 1, 40 do
    seq[i] = (RunHooks.wildSpecies(vg, someWild, nil))
    distinct[seq[i]] = true
    if i > 1 and seq[i] == seq[i - 1] then repeats = repeats + 1 end
  end
  local nd = 0 for _ in pairs(distinct) do nd = nd + 1 end
  T.check(nd >= 15, ("40 encounters of one species on one map give many species (%d distinct)"):format(nd))
  T.eq(repeats, 0, "never the same species twice in a row")
  T.eq(vg.save.runModes.wildCount, 40, "the save counts its randomized encounters")
  local most = 0
  local counts = {}
  for _, sp in ipairs(seq) do counts[sp] = (counts[sp] or 0) + 1; most = math.max(most, counts[sp]) end
  T.check(most <= 8, ("no species dominates (most frequent: %d of 40)"):format(most))
  local again = { save = snapshot, data = Data }
  local same = true
  for i = 1, 40 do if (RunHooks.wildSpecies(again, someWild, nil)) ~= seq[i] then same = false break end end
  T.check(same, "a reload replays the same encounters")
  -- a band is a real choice: every pick stays near the original's strength
  local b0 = Randomizer._bst(pokemon[someWild])
  local far = 0
  for sp in pairs(distinct) do
    if math.abs(Randomizer._bst(pokemon[sp]) - b0) > math.max(0.6 * b0, 120) then far = far + 1 end
  end
  T.eq(far, 0, "every pick keeps the strength band")
end

-- starters: three distinct, stable
local set = RunHooks.STARTERS[gen] or {}
local starters = {}
for i = 1, 3 do if pokemon[set[i]] then starters[#starters + 1] = set[i] end end
if #starters == 3 then
  local picks, seen = {}, {}
  for i, sp in ipairs(starters) do
    picks[i] = Randomizer.starter(A, Data, sp, starters, gen)
    seen[picks[i]] = true
  end
  local n = 0 for _ in pairs(seen) do n = n + 1 end
  T.eq(n, 3, "the three starters come out distinct")
  T.eq(Randomizer.starter(A, Data, starters[2], starters, gen), picks[2], "starter pick is stable")
  T.eq(Randomizer.starter({}, Data, starters[2], starters, gen), starters[2], "starters off -> unchanged")
end

-- ------------------------------------------------------------ engine seams --
local fakeGame = { save = { runModes = { randomWild = true, seed = 7 }, party = {}, player = { map = "ROUTE_1" } },
                   data = Data }
local r1 = RunHooks.wildSpecies(fakeGame, someWild, nil)
T.check(pokemon[r1] ~= nil, "wildSpecies picks a species")
T.eq(RunHooks.quiet(function() return (RunHooks.wildSpecies(fakeGame, someWild, nil)) end), someWild,
  "a quiet battle (tutorial / link / Pal Park) keeps its species")
T.eq(RunHooks.static(function() return (RunHooks.wildSpecies(fakeGame, someWild, nil)) end), someWild,
  "a scripted static keeps its species")
T.eq((RunHooks.wildSpecies(fakeGame, someWild, { roamer = "gen4" })), someWild, "a roamer keeps its species")
T.eq((RunHooks.wildSpecies({ save = { party = {} }, data = Data }, someWild, nil)), someWild,
  "a normal save is untouched")
local _, o2 = RunHooks.wildSpecies(fakeGame, someWild, { form = 2 })
if r1 ~= someWild then T.check(o2.form == nil, "a replaced species drops the slot's form") end

if #starters == 3 then
  local g2 = { save = { runModes = { randomStarters = true, seed = 9 }, party = {} }, data = Data }
  local given = RunHooks.giftSpecies(g2, starters[1])
  T.eq(given, Randomizer.starter(g2.save, Data, starters[1], starters, gen), "the first gift (the starter) is randomized")
  g2.save.party[1] = { species = given }
  T.eq(RunHooks.giftSpecies(g2, starters[1]), starters[1], "a later gift is not")
  T.eq(RunHooks.giftSpecies({ save = { party = {} }, data = Data }, starters[1]), starters[1],
    "a normal save's starter is untouched")
end

-- the rival / trainers follow the randomized starters, stage for stage
do
  local g3 = { save = { runModes = { randomStarters = true, seed = 21 }, party = {} }, data = Data }
  local trio = RunHooks.gameStarters(g3)
  if #trio == 3 and pokemon[trio[1]] then
    local map = RunHooks.starterLines(g3)
    local base = trio[2]
    local want = Randomizer.starter(g3.save, Data, base, trio, gen)
    T.eq(map[base], want, "a starter maps to the same pick the player is given")
    local line = RunHooks._chain(pokemon, base)
    local newLine = RunHooks._chain(pokemon, want)
    if #line >= 2 then
      T.eq(map[line[2]], newLine[math.min(2, #newLine)], "its evolution maps to the pick's same stage")
    end
    local Pokemon = require("src.pokemon.Pokemon")
    local okP, rivalMon = pcall(Pokemon.new, Data, line[#line], 40)
    if okP then
      local party = RunHooks.trainerParty(g3, { rivalMon })
      T.eq(party[1].species, map[line[#line]], "a trainer's starter-line mon becomes the counterpart")
      T.eq(party[1].level, 40, "at the same level")
    end
    local other = RunHooks.trainerParty(g3, { { species = someWild, level = 9 } })
    T.eq(other[1].species, someWild, "other species are untouched")
    T.eq(RunHooks.shownStarter(g3, base), want, "the starter screen shows the pick")
    local plainG = { save = { party = {} }, data = Data }
    T.eq(RunHooks.shownStarter(plainG, base), base, "a normal save's screen is unchanged")
    T.eq(RunHooks.trainerParty(plainG, { { species = base, level = 5 } })[1].species, base,
      "a normal save's rival is unchanged")
    g3.save.party = { {}, {} }
    T.eq(RunHooks.introShown(g3, base), base, "lab text is mapped only while choosing")
  end
end

-- the randomizer is the engine's own: OPTIONS rows, no mod loaded
do
  T.check(RunModes.provider == nil, "no mod is loaded in this suite")
  local og = { save = { party = {}, player = { name = "RED", map = "ROUTE_1" }, options = {} },
               data = Data, stack = { top = function() end, push = function() end, pop = function() end } }
  local okR, rows = pcall(function() return require("src.ui.OptionsMenu").buildRows(og) end)
  T.check(okR, "OPTIONS rows build (" .. tostring(not okR and rows or "") .. ")")
  local byId = {}
  for _, r in ipairs(okR and rows or {}) do byId[r.id] = r end
  T.check(byId.randomWild and byId.randomStarters, "OPTIONS has RANDOM WILD and RANDOM STARTERS")
  T.check(byId.runModes == nil, "no NUZLOCKE row on a normal save")
  if byId.randomWild then
    T.eq(byId.randomWild.value(og), "OFF", "RANDOM WILD starts OFF on an old save")
    byId.randomWild.step(og, 1)
    T.eq(byId.randomWild.value(og), "ON", "RANDOM WILD turns ON from OPTIONS")
    T.check(type(og.save.runModes.seed) == "number", "turning it on gives the save its seed")
    local seed = og.save.runModes.seed
    local r1 = RunHooks.wildSpecies(og, someWild, nil)
    T.check(r1 ~= someWild and pokemon[r1] ~= nil, "wild battles are randomized with no mod loaded")
    byId.randomWild.step(og, 1)
    T.eq(byId.randomWild.value(og), "OFF", "and OFF again")
    T.eq((RunHooks.wildSpecies(og, someWild, nil)), someWild, "off means vanilla")
    byId.randomWild.step(og, 1)
    T.eq(og.save.runModes.seed, seed, "switching back on keeps the same seed")
    byId.randomStarters.step(og, 1)
    T.eq(byId.randomStarters.value(og), "ON", "RANDOM STARTERS turns ON from OPTIONS")
    T.check(not RunModes.nuzlocke(og.save), "the randomizer never turns on Nuzlocke")
  end
end

-- ------------------------------------------------------------ online filters --
local Protocol = require("src.link.Protocol")
local living = { species = someWild, level = 5, hp = 10, moves = {} }
local dead = { species = someWild, level = 7, hp = 0, moves = {}, nuzDead = true }
local okPack, packed = pcall(Protocol.packParty, { living, dead, living })
if okPack then
  T.eq(#packed, 2, "a dead Nuzlocke mon never goes on a link battle's wire")
else
  T.check(false, "packParty ran (" .. tostring(packed) .. ")")
end
local okTs, ts = pcall(Protocol.TradeSession.new, Data, { living, dead }, {})
if okTs then
  T.check(ts:canPick(1) and not ts:canPick(2), "a trade greys the dead mon")
  T.same(ts.sendIndices, { 1 }, "and never offers it")
else
  T.check(false, "TradeSession.new ran (" .. tostring(ts) .. ")")
end
local bound = { species = someWild, level = 5, hp = 10, moves = {}, soulPair = "sec:1" }
local okTs2, ts2 = pcall(Protocol.TradeSession.new, Data, { living, bound }, {})
if okTs2 then T.check(not ts2:canPick(2), "a Soul Link mon stays with its partner") end
local GtsRules = require("src.online.gts.GtsRules")
T.check(GtsRules.depositBlocker({ party = { living, dead } }, Data, dead, nil) ~= nil, "the GTS refuses a dead mon")
T.check(GtsRules.depositBlocker({ party = { living, living } }, Data, living, 2) == nil, "the GTS takes a living one")

-- the hello
local Handshake = require("src.link.Handshake")
local okH, hello = pcall(Handshake.hello, { save = s, data = Data }, "trade")
if okH then
  T.same(hello.runModes, RunModes.summary(s), "the hello carries the run modes")
  local okV, hv = pcall(Handshake.hello, { save = { player = { name = "X" }, party = {} }, data = Data }, "trade")
  T.check(okV and hv.runModes == nil, "a normal save's hello has none")
else
  T.check(false, "Handshake.hello ran (" .. tostring(hello) .. ")")
end

-- the online gate: a run_rules mod passes, a writer does not
do
  local fakeLoader = {
    content = {}, hooks = { chains = { ["runmodes.wild_start"] = { { owner = "R" } } } },
    events = { listeners = { ["runmodes.tick"] = { { owner = "R" } } } },
  }
  T.check(Handshake._rulesOnly(fakeLoader, "R"), "rules-only seams pass the online gate")
  fakeLoader.hooks.chains["battle.damage"] = { { owner = "R" } }
  T.check(not Handshake._rulesOnly(fakeLoader, "R"), "a battle hook does not")
  fakeLoader.hooks.chains["battle.damage"] = nil
  fakeLoader.content.pokemon = { ops = { x = { { owner = "R" } } } }
  T.check(not Handshake._rulesOnly(fakeLoader, "R"), "a registry write does not")
end

-- ------------------------------------------------------------ soul link relay --
local SoulLinkService = require("src.online.SoulLinkService")
local function chan()
  local c = { inbox = {}, out = {} }
  function c:send(m) self.out[#self.out + 1] = m end
  function c:poll() local m = self.inbox; self.inbox = {}; return m end
  return c
end
local svc = SoulLinkService.new()
local c1, c2 = chan(), chan()
svc.open(c1, { pid = 1, name = "A" })
svc.open(c2, { pid = 2, name = "B" })
c1.inbox[1] = { type = "sl_ev", id = "x:1" }
c1.inbox[2] = { type = "w_bad" }
svc.update()
local got
for _, m in ipairs(c2.out) do if m.type == "sl_fwd" then got = m end end
T.check(got and got.from == 1 and got.msg.id == "x:1", "the relay forwards sl_ messages to the other member")
local leaked = false
for _, m in ipairs(c1.out) do if m.type == "sl_fwd" then leaked = true end end
T.check(not leaked, "and not back to the sender")
local fwds = 0
for _, m in ipairs(c2.out) do if m.type == "sl_fwd" then fwds = fwds + 1 end end
T.eq(fwds, 1, "a non-sl_ message is dropped")

T.finish("runmodes")
