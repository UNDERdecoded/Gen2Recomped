-- Production public facades/loaders; native battle entry/timing seams only.
local M = {}
function M.fixture(root, backend, version)
  local codeRoot = debug.getinfo(1, "S").source:sub(2):match("^(.*)/wild_battle%.lua$")
  local f = dofile(codeRoot .. "/warp.lua").fixture(root, backend, version, "wild_battle")
  love = love or require("tests.love_stub")
  f.game.save.party = { { species = "MEW", hp = 20, level = 10, stats = { hp = 20 } } }
  f.game.save.pokedex = { seen = {}, caught = {} }
  f.constructed, f.pushed, f.after = 0, 0, 0
  function f.ow:afterBattle(result, battle)
    f.after = f.after + 1
    f.lastResult, f.cleanedBattle = result, battle
    if f.cleanupError then
      error("native cleanup probe", 0)
    end
  end
  function f:admit(battle, callback, nativeCleanup)
    self.pushed = self.pushed + 1
    self.battle, self.finish, self.nativeCleanup = battle, callback, nativeCleanup
    self.busy = true
    self.game.stack.states[2] = battle
    if self.synchronous then
      self:complete("win", nil, "tail")
    end
    if self.pushFailure then
      return false, "battle failed"
    end
    -- Native host admission is void on success.
  end
  function f:complete(...)
    self.busy = false
    self.game.stack.states[2] = nil
    if self.nativeCleanup and not self.cleaned then
      self.cleaned = true
      self.ow:afterBattle((...), self.battle)
    end
    return self.finish(...)
  end
  local original = package.loaded["src.battle.BattleState"]
  local function construct(game, species, level)
    f.constructed = f.constructed + 1
    game.save.pokedex.seen[species] = true
    if f.constructError then
      error("native constructor probe", 0)
    end
    return { kind = "wild", species = species, level = level }
  end
  package.loaded["src.battle.BattleState"] = { newWild = construct }
  f.restore = function()
    package.loaded["src.battle.BattleState"] = original
  end
  function f.ow:pushBattle(battle)
    return f:admit(battle, battle.onFinish, false)
  end
  if backend == "gen1" and f.gen == 2 then
    package.loaded["src.battle.gen2.Mon"] = {
      new = function(data, species, level)
        return construct(f.game, species, level)
      end,
    }
    function f.ow:startBattle(spec, onDone)
      local result, reason = f:admit(spec.wild, onDone or function() end, true)
      if result == false then
        return result, reason
      end
      return true
    end
  elseif backend == "gen1" and f.gen == 3 then
    local pokemon = require("src.core.game3.pokemon")
    for key, value in pairs(f.game.data.gen3Pokemon) do
      pokemon[key] = value
    end
    pokemon._byName = { MEW = 151 }
    package.loaded["src.core.game3.battle_bridge"] = {
      startWild = function(_, game, spec, opts)
        local b = construct(game, spec.species, spec.level)
        local result, reason = f:admit(b, opts and opts.done or function() end, true)
        if result == false then
          return result, reason
        end
        return true
      end,
    }
  end
  return f
end
function M.run(root, backend, version)
  local f = M.fixture(root, backend, version)
  local report = { invalid = {} }
  for _, args in ipairs({
    { "", 5 },
    { "NO_SUCH_SPECIES", 5 },
    { "MEW", 0 },
    { "MEW", 1.5 },
    { "MEW", 101 },
    { "MEW", 5, false },
  }) do
    local value, why = f.exports.request(unpack(args))
    assert(value == nil, "invalid battle accepted")
    report.invalid[#report.invalid + 1] = why
    assert(f.constructed == 0 and f.pushed == 0 and next(f.game.save.pokedex.seen) == nil)
  end
  f.game.save.party[1].hp = 0
  local value, why = f.exports.request("MEW", 5)
  assert(value == nil and why == "no healthy party")
  report.empty = why
  f.game.save.party[1].hp = 20
  assert(f.exports.request("MEW", 5, f.exports.notify))
  assert(f.battle.level == 5 and f.pushed == 1)
  value, why = f.exports.request("MEW", 5)
  assert(value == nil and why == "world is busy")
  f:complete("win", nil, "tail")
  assert(f.after == 1)
  f:complete("lose")
  local r = f.exports.result()
  assert(r.calls == 1 and r.args.n == 3 and r.args.third == "tail")
  report.complete = r
  f.restore()
  f = M.fixture(root, backend, version)
  f.synchronous = true
  assert(f.exports.request("MEW", 100, f.exports.notify))
  assert(f.exports.result().calls == 1 and f.after == 1)
  report.synchronous = f.exports.result()
  f.restore()
  print("API3_CONTRACT " .. require("src.link.Json").encode(report))
  return report
end
return M
