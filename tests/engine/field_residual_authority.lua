package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local V, Runtime = require("src.core.GameVersion"), require("src.mods.Runtime")
local Fixture = dofile("tests/field_residual/fixture.lua")
local copy = require("src.mods.Merge").deepCopy
local old = V.get()
for _, version in ipairs({ "red", "blue", "yellow", "gold", "silver", "crystal", "firered", "emerald" }) do
  for _, mode in ipairs({ { 1, "native" }, { 2, "native" }, { 2, "unified" }, { 3, "unified" } }) do
    local f = Fixture.new(".", "gen2", version, mode[1], mode[2])
    local e = f.e
    local mutations = {
      turn = function(b)
        b.turnCount = b.turnCount + 1
      end,
      result = function(b)
        b.result = "run"
      end,
      save = function(b)
        b.game.save = copy(b.game.save)
      end,
      data = function(b)
        b.game.data = {}
      end,
      stack = function(b)
        b.game.stack = { states = {} }
      end,
      states = function(b)
        b.game.stack.states = {}
      end,
      pop = function(b)
        table.remove(b.game.stack.states)
      end,
      cover = function(b)
        table.insert(b.game.stack.states, {})
      end,
      replaceTop = function(b)
        b.game.stack.states[1] = {}
      end,
      loader = function(b)
        b.game.mods = {}
      end,
      loaderGame = function(b)
        b.game.mods.game = {}
      end,
      hooks = function()
        Runtime.hooks = {}
      end,
      actor = function(b)
        b:placeBattler(1, copy(b.enemy))
      end,
      mon = function(b)
        b.enemy.mon = copy(b.enemy.mon)
      end,
      game = function(b)
        b.game = { save = b.game.save, data = b.game.data, stack = b.game.stack }
      end,
    }
    for name, change in pairs(mutations) do
      local b = f.reset()
      local player, enemy = b.player.mon, b.enemy.mon
      e.state.requests = { { side = "enemy", amount = 4 }, { side = "player", amount = 3 } }
      local hooks = Runtime.hooks
      local off = e.api.hooks:wrap("battle.field_residual", function(next, ctx)
        local rows = next(ctx)
        change(b)
        return rows
      end, 100)
      -- Exercise admission through the actual native end-of-turn producer.
      b:endOfTurn()
      Runtime.hooks = hooks
      off()
      T.eq(player.hp, 400, name .. " invalidates field player authority")
      T.eq(enemy.hp, 400, name .. " invalidates field enemy authority")
      T.eq(e.state.calls, 1, name .. " ran the genuine callback")
      f.game.data, f.game.mods, f.result.loader.game = f.data, f.result.loader, f.game
      f.game.stack = setmetatable({}, { __index = require("src.core.StateStack") })
      f.game.stack:init()
    end
    local b = f.reset()
    b.field.tokens[1].state.cycle = b.field.tokens[1].state
    b.field.tokens[1].state.bad = math.huge
    b.field.tokens[1].state.fn = function()
      error("private")
    end
    b.field.tokens[1].state[function() end] = "private key"
    e.state.mode = "mutate"
    f.run()
    T.eq(e.state.last.field.tokens[1].state.cycle, nil, "cycles are removed from public field data")
    T.eq(e.state.last.field.tokens[1].state.bad, nil, "nonfinite field data is removed")
    T.eq(e.state.last.field.tokens[1].state.fn, nil, "callbacks are removed recursively")
    T.eq(b.player.curTypes[1], "NORMAL", "snapshot type edits cannot change native types")
    b = f.reset()
    e.state.mode, e.state.invalid =
      "invalid", setmetatable({}, {
        __index = function()
          error("private")
        end,
      })
    f.run()
    T.eq(f.hp("enemy"), 400, "metatable result is never executed")
    b = f.reset()
    e.state.requests = { setmetatable({ side = "enemy", amount = 3 }, {}) }
    f.run()
    T.eq(f.hp("enemy"), 400, "metatable descriptor is rejected")
    -- Exercise the real native faint/EXP queue instead of replacing onFaint.
    b = f.reset()
    if f.gen > 1 then
      b.enemy.destinyBond, b.enemy.grudge = true, true
    end
    b.player.lastMove = f.ids.TACKLE
    local pp = b.player.curMoves[1].pp
    e.state.requests = { { side = "enemy", amount = 99999 } }
    f.run()
    f.drain()
    T.eq(f.hp("player"), 400, "field KO is not direct-move Destiny Bond damage")
    T.eq(b.player.curMoves[1].pp, pp, "field KO is not direct-move Grudge damage")
    T.eq(e.state.faints, 1, "native field faint emits once")
    T.check(e.state.awards > 0, "native surviving player receives EXP after field KO")
    if f.gen == 3 then
      b = f.reset({ double = true })
      local reserve = copy(b.enemy.mon)
      b.enemyParty[#b.enemyParty + 1] = reserve
      e.state.requests = { { side = "enemy", battlerId = 3, amount = 99999 } }
      f.run()
      f.drain()
      T.eq(b:battlerAt(3).mon, reserve, "native end-of-turn queue fills field KO's empty flank")
      T.eq(b.result, nil, "living double side keeps battle active")
      T.eq(e.state.faints, 1, "native double flank faint emits once")
      T.check(e.state.awards > 0, "native double flank faint awards EXP once")
      b = f.reset({ double = true })
      e.state.requests = {
        { side = "enemy", battlerId = 1, amount = 99999 },
        { side = "enemy", battlerId = 3, amount = 99999 },
      }
      f.run()
      f.drain()
      T.eq(b.result, "win", "native doubles field wipe resolves victory")
      T.eq(e.state.faints, 2, "native doubles field wipe announces both foes")
      T.eq(e.state.awards, 2, "native doubles field wipe awards each foe once")
      for _, reverse in ipairs({ false, true }) do
        b = f.reset({ double = true })
        local requests = {}
        for id = 0, 3 do
          requests[#requests + 1] = {
            side = id % 2 == 0 and "player" or "enemy",
            battlerId = reverse and 3 - id or id,
            amount = 99999,
          }
        end
        if reverse then
          for _, row in ipairs(requests) do
            row.side = row.battlerId % 2 == 0 and "player" or "enemy"
          end
        end
        e.state.requests = requests
        f.run()
        f.drain()
        T.eq(b.result, "lose", "terminal doubles batch gives player loss authority")
        T.eq(e.state.awards, 0, "terminal doubles never awards enemy EXP")
        T.eq(e.state.faints, 2, "terminal doubles announces player slots only")
      end
    end
    f.close()
  end
end
V.set(old)
T.finish("field residual admission, detached data and native faint authority")
