local M = {}
function M.new(root, backend, version, api, format, noMod, failing)
  local f = dofile(root .. "/tests/charge_required/fixture.lua").new(
    root,
    backend,
    version,
    api,
    format,
    noMod,
    failing,
    "portable_field_residual"
  )
  local source = f.fresh
  local b
  f.game.mods = f.result.loader
  function f.reset(opts)
    opts = opts or {}
    if backend == "gen2" and f.gen == 2 then
      f.data.pokemon.CHARMANDER.types = { "NORMAL", "NORMAL" }
    end
    b = source("TACKLE").battle
    if opts.double then
      assert(f.gen == 3, "double field fixture requires GBA")
      if backend == "gen1" then
        local copy = require("src.mods.Merge").deepCopy
        b = require("src.core.game3.battle.state").new({
          double = true,
          wild = true,
          playerParty = { b.player.mon, copy(b.player.mon) },
          foeParty = { b.enemy.mon, copy(b.enemy.mon) },
        })
        b.rng = function(lo)
          return lo or 0
        end
      else
        local extra = source("TACKLE").battle
        f.game.save.party = { b.player.mon, extra.player.mon }
        b.playerParty = f.game.save.party
        b.enemyParty = { b.enemy.mon, extra.enemy.mon }
        b.double = true
        b:placeBattler(2, extra.player)
        b:placeBattler(3, extra.enemy)
        b:syncSides()
      end
    end
    f.game.save.party = backend == "gen1" and f.gen == 2 and b.party or f.game.save.party
    b.field = b.field or {}
    b.field.tokens = {
      {
        id = "portable",
        state = { intensity = 4 },
        onExpire = function()
          error("private callback")
        end,
      },
    }
    b.turnCount, b.turn = 1, backend == "gen1" and f.gen == 2 and 0 or 1
    b.phase, b.queue = "menu", {}
    local active = {}
    if backend == "gen1" and f.gen == 3 then
      active = require("src.core.game3.battle.adapter").new(b):activeBattlers()
    elseif backend == "gen1" then
      active = { b.player, b.enemy }
    else
      for _, actor in b:activeBattlers() do
        active[#active + 1] = actor
      end
    end
    for _, actor in ipairs(active) do
      local mon = backend == "gen1" and f.gen == 2 and actor or actor.mon
      mon.nickname, mon.maxHp, mon.hp = "PROBE", 400, 400
      actor.name = "PROBE"
      if backend == "gen1" and f.gen == 3 then
        actor.type1, actor.type2 = 0, 0
      end
    end
    f.battle = b
    if backend == "gen2" or f.gen == 1 then
      f.game.stack.states = { b }
    end
    if f.e then
      f.e.state.requests, f.e.state.mode = {}, "none"
      f.e.state.calls, f.e.state.faints, f.e.state.awards = 0, 0, 0
    end
    return b
  end
  function f.actor(id)
    if backend == "gen1" and f.gen == 3 then
      return require("src.core.game3.battle.state").battler(b, id)
    end
    return b:battlerAt(id)
  end
  function f.hp(side)
    local actor = b[side]
    return backend == "gen1" and f.gen == 2 and actor.hp or actor.mon.hp
  end
  function f.setHP(side, value)
    local actor = b[side]
    if backend == "gen1" and f.gen == 2 then
      actor.hp = value
    else
      actor.mon.hp = value
    end
  end
  function f.run()
    if backend == "gen1" and f.gen == 2 then
      f.events = b:takeTurn({ kind = "skip" })
    elseif backend == "gen1" and f.gen == 3 then
      require("src.core.game3.battle.engine")
      f.events =
        require("src.core.game3.battle.residuals").runTurn(require("src.core.game3.battle.adapter").new(b))
    else
      b:endOfTurn()
    end
    return f.events
  end
  function f.drain()
    if backend == "gen1" and f.gen > 1 then
      return
    end
    for _ = 1, 2000 do
      local row = table.remove(b.queue, 1)
      if not row then
        return
      end
      if row.fn then
        b.nextInsert = 0
        row.fn()
      end
    end
    error("native field/faint queue did not terminate")
  end
  f.reset()
  return f
end
return M
