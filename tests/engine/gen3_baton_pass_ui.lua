package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Copy = require("src.mods.Merge").deepCopy
for _, version in ipairs({ "firered", "emerald" }) do
  local f = require("tests.enemy_actions.baton_pass").fixture(".", "gen2", version)
  T.link.prepare(f.data)
  local game = T.link.fakeGame(f.data, "CHARMANDER", { name = "PLAYER", level = 30 })
  game.stack.states = game.stack.list
  f.result.loader.game = game
  local mon = game.save.party[1]
  mon.nickname = "ALPHA"
  mon.moves = { { id = f.ids.BATON_PASS, pp = 20 }, { id = f.ids.TACKLE, pp = 10 } }
  mon.stats.hp, mon.hp = 400, 400
  game.save.party[2], game.save.party[3] = Copy(mon), Copy(mon)
  game.save.party[2].nickname, game.save.party[3].nickname = "BETA", "GAMMA"
  local b = require("src.battle.BattleState").newWild(game, "CHARMANDER", 30)
  b:syncSides()
  b.enemy.mon.moves = { { id = f.ids.TACKLE, pp = 10 } }
  b.enemy.curMoves = b.enemy.mon.moves
  b.enemy.mon.stats.hp, b.enemy.mon.hp = 400, 400
  b.player.curStats.speed, b.enemy.curStats.speed = 200, 100
  b.player.stages.attack = 2
  f.e.choose(function()
    return { move = "TACKLE" }
  end)
  -- A real queued turn, with its slower attack already waiting on the donor slot.
  game.stack.states[1] = b
  b:resolveTurn(b.player.curMoves[1])
  local ui, screen
  local function frame()
    require("src.core.Input").pressed = { a = true }
    game.stack:update(1 / 60)
  end
  for _ = 1, 10000 do
    local top = game.stack:top()
    if top ~= b then
      local view = f.e.api.ui:snapshot()
      if view and view.kind == "party" then
        ui, screen = view, top
        break
      end
    end
    frame()
  end
  T.check(ui ~= nil, "Baton Pass opens the actual native party screen")
  assert(ui, "party chooser never opened")
  T.eq(b.player.mon, mon, "donor remains active until a choice")
  T.eq(mon.moves[1].pp, 19, "PP is spent before native party selection")
  T.eq(ui.canBack, false, "public UI cannot cancel a forced Baton Pass choice")
  local back, why = f.e.api.ui:submit({ id = 1, revision = ui.revision, kind = "back" })
  T.eq(back, nil, "public back intent is refused")
  T.check(type(why) == "string", "back refusal explains the unavailable operation")
  screen:cancel()
  T.eq(game.stack:top(), screen, "native B/cancel leaves forced picker open")
  local pending = b._gen3BatonPending
  T.eq(
    require("src.battle.Gen3BatonPass").select(b, pending, 1),
    false,
    "current active donor is not eligible"
  )
  game.save.party[3].hp = 0
  local stale = f.e.api.ui:submit({ id = 2, revision = ui.revision, kind = "select", index = 3 })
  T.eq(stale, nil, "party mutation invalidates an old UI offer")
  T.eq(
    require("src.battle.Gen3BatonPass").select(b, pending, 3),
    false,
    "fainted replacement is refused even by native continuation"
  )
  game.save.party[3].hp = 400
  local current = assert(f.e.api.ui:snapshot())
  local accepted, error =
    f.e.api.ui:submit({ id = 3, revision = current.revision, kind = "select", index = 3 })
  T.eq(accepted, true, "public UI chooses the last eligible member: " .. tostring(error))
  T.eq(game.stack:top(), b, "selection returns to the battle queue")
  for _ = 1, 15000 do
    if b.phase == "menu" and not b._gen3BatonPending then
      break
    end
    frame()
  end
  T.eq(b.player.mon, game.save.party[3], "queued continuation installs the selected Gamma")
  T.eq(b.player.stages.attack, 2, "queued native switch retains donor stages")
  T.eq(mon.hp, 400, "slower attack does not damage the retired donor")
  T.check(game.save.party[3].hp < 400, "slower queued attack hits the current occupant")
  T.eq(mon.moves[1].pp, 19, "resuming the chooser does not spend PP twice")
  T.eq(b.turnCount, 1, "Baton Pass does not create an extra turn")
  T.eq(b._gen3BatonPending, nil, "choice state is cleared after the turn")
  T.eq(
    require("src.battle.Gen3BatonPass").select(b, pending, 2),
    false,
    "completed choice cannot be replayed"
  )
  T.eq(b.player.mon.nickname, "GAMMA", "replayed callback cannot replace the selected mon")
  local initial = { game.save.party[1] }
  local owner = { playerParty = initial }
  local Menu = require("src.ui.Gen3PartyMenu")
  local linked = Menu.new(game, { battle = owner, party = initial })
  T.eq(linked:party(), initial, "ordinary link picker starts with the live battle roster")
  owner.playerParty = { game.save.party[2], game.save.party[3] }
  T.eq(linked:party(), owner.playerParty, "ordinary link picker follows a replaced live roster")
  local distinct = { game.save.party[3] }
  local ally = Menu.new(game, { battle = owner, party = distinct, forceSwitch = true })
  T.eq(ally:party(), distinct, "owner-specific picker retains its distinct party")
  T.eq(#ally:party(), 1, "owner-specific roster never expands into the other trainer's party")
  local lateOwner = {}
  local late = Menu.new(game, { battle = lateOwner, party = initial })
  lateOwner.playerParty = distinct
  T.eq(late:party(), distinct, "ordinary picker follows a roster installed after screen creation")
  f.close()
end
T.finish("native Baton Pass party UI and queued turn continuation")
