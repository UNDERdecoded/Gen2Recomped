package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Contract = require("tests.api3_contract.script_battles")
local Runtime = require("src.mods.Runtime")
local Version = require("src.core.GameVersion")
local Battle = require("src.battle.BattleState")
local saved = { Version.get(), Runtime.events, Runtime.hooks, Runtime.errors, Runtime.currentMod, love }
local function fixture(v)
  return Contract.fixture("tests/api3_contract", "gen2", v or "red")
end
for _, v in ipairs({ "red", "blue", "yellow", "gold", "silver", "crystal", "firered", "emerald" }) do
  local ok, why = pcall(Contract.run, "tests/api3_contract", "gen2", v)
  T.check(ok, v .. " shared script battle: " .. tostring(why))
end
for _, rows in ipairs({
  { { "set_flag", "mod:prefix" }, { "start_battle", "wild", "UNKNOWN", 5 } },
  { { "start_battle", "wild", "MEW", 0 } },
  { { "start_battle", "wild", "MEW", 101 } },
  { { "start_battle", "trainer", "ANY", 1 } },
  { { "static_battle", "MEW", 5, "mod.other.bad" } },
  { { "static_battle", "MEW", 5 }, { "check_battle_result", "invalid" } },
}) do
  local f = fixture()
  T.eq(f.exports.queue(rows), nil, "invalid battle list preflight")
  T.eq(f.exports.get("mod:prefix"), false, "invalid suffix has no flag prefix")
  T.eq(f.constructed, 0, "preflight constructs no native battle")
  f.restore()
end
for _, outcome in ipairs({ "win", "lose", "run", "caught" }) do
  local f = fixture()
  T.check(
    f.exports.queue({
      { "static_battle", "MEW", 5, "mod:beat" },
      { "check_battle_result", outcome },
      { "jump_if_false", "end" },
      { "set_flag", "mod:after" },
    }),
    "private static beat flag admitted"
  )
  f:complete(outcome)
  f:drain()
  T.eq(f.exports.get("mod:beat"), outcome ~= "lose", "private static flag is generation independent")
  T.eq(f.exports.get("mod:after"), true, "battle result branch executes")
  f.restore()
end
for _, change in ipairs({ "cancel", "rollback", "save", "data", "player" }) do
  local f = fixture()
  local original = f.ow.runner
  T.check(
    f.exports.queue({ { "static_battle", "MEW", 5, "mod:beat" }, { "set_flag", "mod:after" } }),
    "battle admitted before retirement"
  )
  local finish = f.finish
  if change == "cancel" then
    require("src.mods.PortableScripts").cancelAll(f.loader, "script_battles")
  elseif change == "rollback" then
    f.loader:_rollback("script_battles")
  elseif change == "player" then
    f.ow.player = {}
  else
    f.game[change] = {}
  end
  f:tick()
  T.eq(f.game.stack:top(), f.battle, "cancelling script preserves native battle screen")
  T.eq(f.exports.result().done, 1, "retirement completes once")
  T.eq(f.exports.result().success, false, "retired battle cannot finish script")
  f:complete("caught")
  finish("win")
  finish("run")
  T.eq(
    f.after,
    (change == "cancel" or change == "rollback") and 1 or 0,
    "cleanup only for retained native session"
  )
  T.eq(f.exports.result().done, 1, "native finish cannot replay retired completion")
  T.eq(f.ow.runner, original, "idle runner restored")
  f.restore()
end
do
  local f = fixture()
  T.check(
    f.exports.queue({ { "start_battle", "wild", "MEW", 5 }, { "set_flag", "mod:after" } }),
    "battle before foreign overlay"
  )
  local callback = f.finish
  f:complete("win")
  local overlay = {}
  f.game.stack.states[2] = overlay
  callback("lose")
  callback("run")
  for _ = 1, 5 do
    f:tick()
  end
  T.eq(f.exports.get("mod:after"), false, "battle callback cannot resume under foreign UI")
  T.eq(f.after, 1, "native cleanup is one-shot")
  f.game.stack.states[2] = nil
  f:drain()
  T.eq(f.exports.get("mod:after"), true, "foreground battle continuation runs")
  f.restore()
end
for _, failure in ipairs({ "constructError", "pushFailure", "cleanupError", "unhealthy", "constructUnload" }) do
  local f = fixture()
  if failure == "unhealthy" then
    f.game.save.party[1].hp = 0
  elseif failure == "constructUnload" then
    local native = package.loaded["src.battle.BattleState"].newWild
    package.loaded["src.battle.BattleState"].newWild = function(...)
      local result = native(...)
      f.loader:_rollback("script_battles")
      return result
    end
  else
    f[failure] = true
  end
  T.check(
    f.exports.queue({ { "start_battle", "wild", "MEW", 5 }, { "set_flag", "mod:after" } }),
    "admitted program reports native failure"
  )
  if failure == "cleanupError" then
    f:complete("win")
  end
  T.eq(f.exports.result().success, false, "native failure finishes script")
  T.eq(f.exports.get("mod:after"), false, "native failure suppresses suffix")
  if failure == "constructUnload" then
    T.eq(f.pushed, 0, "owner retired during construction cannot push battle")
  end
  f.restore()
end
do
  local f = fixture()
  f.synchronous = true
  T.check(
    f.exports.queue({ { "start_battle", "wild", "MEW", 5 }, { "set_flag", "mod:after" } }),
    "synchronous battle admitted"
  )
  T.eq(f.exports.result().success, true, "synchronous battle completion handled")
  T.eq(f.after, 1, "synchronous cleanup once")
  f.restore()
end
for _, v in ipairs({ "red", "gold", "firered", "emerald" }) do
  for _, outcome in ipairs({ "win", "lose", "run", "caught" }) do
    local f = fixture(v)
    local def = { name = "NPC", index = 1, localId = 1, x = 1, y = 1, eventFlag = "FLAG_A", flag = 7 }
    f.ow.map.def.objects = { def }
    f.ow.talkNpc = { def = def, cellX = 1, cellY = 1 }
    function f.ow:syncObjectVisibility()
      f.hidden = true
    end
    function f.ow:setMap()
      f.hidden = f.game.save.objectToggles[f.home].NPC == false
    end
    T.check(
      f.exports.queue({ { "static_battle", "MEW", 5, "mod:beat" }, { "set_flag", "mod:after" } }),
      "static NPC battle admitted"
    )
    T.eq(f.hidden, nil, "NPC stays visible during battle")
    f:complete(outcome)
    f:drain()
    T.eq(f.exports.result().success, true, "static NPC continuation succeeds")
    T.eq(f.hidden == true, outcome ~= "lose", "static NPC hidden on every non-loss outcome")
    T.eq(f.exports.get("mod:after"), true, "static object update resumes later rows")
    f.restore()
  end
end
-- Actual native constructors and Pokémon creation, retaining the entry timing seam.
for _, v in ipairs({ "red", "gold", "crystal", "firered", "emerald" }) do
  local f = fixture(v)
  f.restore()
  local data = T.fixtures.fresh()
  data.pokemon.MEW = require("src.mods.Merge").deepCopy(data.pokemon.FIXMON_A)
  data.pokemon.MEW.id, data.pokemon.MEW.name = "MEW", "MEW"
  data.constants.gen = Version.generation(v)
  f.game.data = data
  f.game.save = require("src.core.SaveData").newGame()
  f.game.session = f.game.save
  f.game.save.party = { require("src.pokemon.Pokemon").new(data, "FIXMON_A", 15) }
  require("src.render.Font").load(data)
  T.check(
    f.exports.queue({ { "static_battle", "MEW", 5, "mod:beat" }, { "set_flag", "mod:after" } }),
    v .. " native constructor admitted"
  )
  T.eq(f.battle.kind, "wild", "native battle kind")
  T.eq(f.battle.enemy.mon.species, "MEW", "native enemy species")
  f:complete("caught")
  f:drain()
  T.eq(f.after, 1, "native cleanup retained")
  T.eq(f.exports.get("mod:beat"), true, "actual native battle resumes static suffix")
end
Version.set(saved[1])
Runtime.events, Runtime.hooks, Runtime.errors, Runtime.currentMod, love =
  saved[2], saved[3], saved[4], saved[5], saved[6]
T.finish("Portable script battles")
