package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Contract = require("tests.api3_contract.script_trainers")
local Runtime = require("src.mods.Runtime")
local Version = require("src.core.GameVersion")
local saved = { Version.get(), Runtime.events, Runtime.hooks, Runtime.errors, Runtime.currentMod, love }
local function fixture(v)
  return Contract.fixture("tests/api3_contract", "gen2", v or "red")
end
for _, v in ipairs({ "red", "blue", "yellow", "gold", "silver", "crystal", "firered", "emerald" }) do
  local ok, why = pcall(Contract.run, "tests/api3_contract", "gen2", v)
  T.check(ok, v .. " shared trainer contract: " .. tostring(why))
end
for _, rows in ipairs({
  { { "set_flag", "mod:prefix" }, { "start_battle", "trainer", 999, 1 } },
  { { "start_battle", "trainer", {}, 1 } },
  { { "start_battle", "trainer", "PROBE", 0 } },
  { { "start_battle", "trainer", "PROBE", 256 } },
  { { "start_battle", "trainer", "PROBE", 2 } },
  { { "start_battle", "trainer", "PROBE", 1, {} } },
}) do
  local f = fixture()
  T.eq(f.exports.queue(rows), nil, "invalid trainer preflight")
  T.eq(f.constructed, 0, "invalid trainer does not construct")
  T.eq(f.exports.get("mod:prefix"), false, "invalid suffix prevents prefix")
  f.restore()
end
for _, change in ipairs({ "species", "level", "empty", "oversized", "ambiguous" }) do
  local f = fixture("gold")
  local row = f.game.data.trainers.PROBE
  if change == "species" then
    row.parties[1][1].species = "UNKNOWN"
  elseif change == "level" then
    row.parties[1][1].level = 101
  elseif change == "empty" then
    row.parties[1] = {}
  elseif change == "oversized" then
    for i = 2, 7 do
      row.parties[1][i] = row.parties[1][1]
    end
  else
    f.game.data.trainers.OTHER = { id = "OTHER", index = 7, parties = row.parties }
  end
  T.eq(
    f.exports.queue({ { "set_flag", "mod:prefix" }, { "start_battle", "trainer", 7, 1 } }),
    nil,
    "invalid native trainer data: " .. change
  )
  T.eq(f.constructed, 0, "invalid data never constructs")
  T.eq(f.exports.get("mod:prefix"), false, "invalid data never runs prefix")
  f.restore()
end
do
  local f = fixture("gold")
  f.game.data.trainers.ALIAS = require("src.mods.Merge").deepCopy(f.game.data.trainers.PROBE)
  T.check(f.exports.queue({ { "start_battle", "trainer", 7, 1 } }), "canonical native alias resolves once")
  T.eq(f.battle.class, "PROBE", "native class identity selected deterministically")
  f:complete("win")
  f:drain()
  f.restore()
end
for _, change in ipairs({ "missing_order", "ambiguous_order", "missing_base", "invalid_flags", "member" }) do
  local f = fixture("firered")
  local row = { "start_battle", "trainer", 7, 1 }
  if change == "missing_order" then
    f.game.data.constants.trainerOrder = {}
  elseif change == "ambiguous_order" then
    f.game.data.constants.trainerOrder[8] = "PROBE"
  elseif change == "missing_base" then
    f.game.data.constants.gen3TrainerFlagBase = nil
  elseif change == "invalid_flags" then
    f.game.save.flags = false
  else
    row[4] = 2
  end
  T.eq(f.exports.queue({ row }), nil, "unrepresentable Gen3 trainer refused: " .. change)
  T.eq(f.constructed, 0, "Gen3 refusal has no constructor")
  f.restore()
end
for _, change in ipairs({ "rollback", "save", "data", "player", "cancel" }) do
  local f = fixture("firered")
  T.check(
    f.exports.queue({ { "start_battle", "trainer", 7, 1 }, { "set_flag", "mod:after" } }),
    "trainer admitted before retirement"
  )
  local callback = f.finish
  if change == "rollback" then
    f.loader:_rollback("script_trainers")
  elseif change == "player" then
    f.ow.player = {}
  elseif change == "cancel" then
    require("src.mods.PortableScripts").cancelAll(f.loader, "script_trainers")
  else
    f.game[change] = {}
  end
  f:tick()
  T.eq(f.game.stack:top(), f.battle, "trainer native screen survives script retirement")
  f:complete("win")
  callback("lose")
  T.eq(f.exports.result().success, false, "retired trainer cannot continue")
  T.eq(
    f.after,
    (change == "rollback" or change == "cancel") and 1 or 0,
    "native cleanup only on same session"
  )
  T.eq(f.exports.result().done, 1, "late trainer callback completes once")
  if change == "rollback" or change == "cancel" then
    T.eq(
      f.game.save.flags.FLAG_G3_0507,
      true,
      "native trainer victory flag survives originating mod retirement"
    )
  end
  f.restore()
end
do
  local f = fixture()
  T.check(
    f.exports.queue({ { "wait", 1 }, { "start_battle", "trainer", "PROBE", 1 } }),
    "deferred trainer preflight"
  )
  f.game.data.trainers.PROBE.parties[1][1].species = "UNKNOWN"
  f:drain()
  T.eq(f.exports.result().success, false, "trainer data revalidated at dispatch")
  T.eq(f.constructed, 0, "changed live roster cannot construct")
  f.restore()
end
for _, failure in ipairs({ "constructError", "pushFailure", "cleanupError", "constructUnload" }) do
  local f = fixture()
  if failure == "constructUnload" then
    local native = package.loaded["src.battle.BattleState"].newTrainer
    package.loaded["src.battle.BattleState"].newTrainer = function(...)
      local result = native(...)
      f.loader:_rollback("script_trainers")
      return result
    end
  else
    f[failure] = true
  end
  T.check(
    f.exports.queue({ { "start_battle", "trainer", "PROBE", 1 }, { "set_flag", "mod:after" } }),
    "trainer native failure admitted"
  )
  if failure == "cleanupError" then
    f:complete("win")
  end
  T.eq(f.exports.result().success, false, "trainer native failure terminates")
  T.eq(f.exports.get("mod:after"), false, "trainer native failure suppresses suffix")
  if failure == "constructUnload" then
    T.eq(f.pushed, 0, "retired constructor cannot push trainer battle")
  end
  f.restore()
end
for _, v in ipairs({ "red", "gold", "crystal", "firered", "emerald" }) do
  for _, outcome in ipairs({ "win", "lose" }) do
    local f = fixture(v)
    f.restore()
    local data = T.fixtures.fresh()
    data.trainers.PROBE = {
      id = "PROBE",
      index = 7,
      name = "PROBE",
      baseMoney = 10,
      parties = { { { species = "FIXMON_B", level = 5 } } },
    }
    data.constants.gen = Version.generation(v)
    data.constants.trainerOrder = { [7] = "PROBE" }
    data.constants.gen3TrainerFlagBase = 0x500
    f.game.data = data
    f.game.save = require("src.core.SaveData").newGame()
    f.game.session = f.game.save
    f.game.save.party = { require("src.pokemon.Pokemon").new(data, "FIXMON_A", 15) }
    require("src.render.Font").load(data)
    T.check(
      f.exports.queue({
        { "start_battle", "trainer", f.trainerRef, 1 },
        { "check_battle_result", outcome },
        { "jump_if_false", "end" },
        { "set_flag", "mod:after" },
      }),
      v .. " native trainer admitted"
    )
    T.eq(f.battle.kind, "trainer", "actual native trainer kind")
    T.eq(f.battle.enemy.mon.species, "FIXMON_B", "actual native trainer party built")
    T.eq(f.battle.partyIndex, 1, "actual native member selected")
    f:complete(outcome)
    f:drain()
    T.eq(f.after, 1, "actual trainer cleanup retained")
    T.eq(f.exports.get("mod:after"), true, "native trainer outcome branch")
    if f.gen == 3 then
      T.eq(f.game.save.flags.FLAG_G3_0507 == true, outcome == "win", "native trainer flag tracks win only")
    end
  end
end
Version.set(saved[1])
Runtime.events, Runtime.hooks, Runtime.errors, Runtime.currentMod, love =
  saved[2], saved[3], saved[4], saved[5], saved[6]
T.finish("Portable script trainers")
