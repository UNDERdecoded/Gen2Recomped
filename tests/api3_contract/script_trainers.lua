local M = {}
function M.fixture(root, backend, version)
  local codeRoot = debug.getinfo(1, "S").source:sub(2):match("^(.*)/script_trainers%.lua$")
  local f = dofile(codeRoot .. "/script_battles.lua").fixture(root, backend, version, "script_trainers")
  f.game.data.trainers =
    { PROBE = { id = "PROBE", index = 7, name = "PROBE", parties = { { { species = "MEW", level = 5 } } } } }
  f.game.data.constants = f.game.data.constants or {}
  f.game.data.constants.trainerOrder = { [7] = "PROBE" }
  f.game.data.constants.gen3TrainerFlagBase = 0x500
  local battle = package.loaded["src.battle.BattleState"]
  battle.newTrainer = function(game, class, member)
    f.constructed = f.constructed + 1
    if f.constructError then
      error("trainer constructor probe", 0)
    end
    return { kind = "trainer", class = class, member = member }
  end
  f.trainerRef = f.gen == 1 and "PROBE" or 7
  if backend == "gen1" and f.gen == 2 then
    f.game.data.trainers = {
      classes = {
        PROBE = {
          id = "PROBE",
          index = 7,
          name = "PROBE",
          trainers = { { id = "PROBE_1", name = "PROBE", party = { { species = "MEW", level = 5 } } } },
        },
      },
    }
    function f.ow:trainerParty(class, member)
      return require("src.world.gen2.TrainerHouse").lookup(f.game.data.trainers, f.game.save, class, member)
    end
    function f.ow:startScriptedBattle(trainer, _, done)
      f.constructed = f.constructed + 1
      return f:admit({ kind = "trainer", trainer = trainer }, done, true)
    end
  elseif backend == "gen1" and f.gen == 3 then
    package.loaded["src.core.game3.scripting.trainers"] = {
      get = function(id)
        return id == 7 and { party = { { species = 151, level = 5 } } } or nil
      end,
      foeFromId = function(id)
        return id == 7 and { trainerId = id, party = { { species = 151, level = 5 } } } or nil
      end,
    }
    package.loaded["src.core.game3.battle_bridge"].start = function(_, game, foe, opts)
      f.constructed = f.constructed + 1
      local value, why = f:admit({ kind = "trainer", foe = foe }, opts.done, true)
      if value == false then
        return value, why
      end
      return true
    end
  end
  return f
end
function M.run(root, backend, version)
  local report = {}
  for _, outcome in ipairs({ "win", "lose", "run" }) do
    local f = M.fixture(root, backend, version)
    assert(f.exports.queue({
      { "start_battle", "trainer", f.trainerRef, 1 },
      { "check_battle_result", outcome },
      { "jump_if_false", "end" },
      { "set_flag", "mod:after" },
    }))
    assert(f.constructed == 1 and f.pushed == 1 and f.exports.result().done == 0)
    f:complete(outcome)
    f:drain()
    assert(f.after == 1 and f.exports.result().success and f.exports.get("mod:after"))
    report[outcome] = { after = f.after, complete = true }
    f.restore()
  end
  local f = M.fixture(root, backend, version)
  local value, why = f.exports.queue({ { "set_flag", "mod:prefix" }, { "start_battle", "trainer", 999, 1 } })
  assert(value == nil and type(why) == "string" and not f.exports.get("mod:prefix") and f.constructed == 0)
  report.preflight = true
  f.restore()
  print("API3_CONTRACT " .. require("src.link.Json").encode(report))
  return report
end
return M
