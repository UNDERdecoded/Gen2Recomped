-- Reuse native backend construction from trainer admission; use a different
-- unchanged consumer and no trainer hook, then settle the actual native menu.
local M = {}
function M.new(root, backend, version, api, format)
  local f = dofile(root .. "/tests/trainer_preparation/fixture.lua").new(
    root,
    backend,
    version,
    api,
    format,
    false,
    false,
    "portable_battle_auxiliary"
  )
  f.start()
  local battle, game = assert(f.battle()), f.game
  local update, index, ready
  if backend == "gen1" and f.generation == 3 then
    local B = require("src.core.game3.battle")
    local Ui = require("src.core.game3.battle.ui")
    local Anim = require("src.core.game3.battle.anim")
    local State = require("src.core.game3.battle.state")
    B.reset()
    B._active, B._st = true, battle
    B._adapter = require("src.core.game3.battle.adapter").new(battle)
    B._phase, B._auto, B._headless, B._fade = "command", false, false, false
    Ui.reset({ headless = false })
    Ui.bindState(battle, game.session)
    Ui._headless = false
    Ui.openMenu()
    Anim.reset({ headless = true })
    for id = 0, 1 do
      local b, p = State.battler(battle, id), Anim.present(id)
      Anim.setShown(id, b)
      p.displayHp, p.displayMaxHp = b.mon.hp, b.mon.maxHp
      p.displayStatus = b.status or b.mon.status or b.mon.status1
    end
    update = function()
      B.update(0, game)
    end
    index = function(value)
      if value then
        Ui._menuIndex = value
      end
      return Ui._menuIndex
    end
    ready = function()
      return B._phase == "command"
    end
  elseif backend == "gen1" and f.generation == 2 then
    local screen = game.stack:top()
    assert(screen and screen.battle == battle, "actual Gen1 Gold battle screen missing")
    screen.phase, screen.slideFrame, screen.queue = "menu", 1000, {}
    screen.showPlayerHud, screen.showEnemyHud = true, true
    screen.ballRows = { player = false, enemy = false }
    screen.shownMon = { player = battle.player, enemy = battle.enemy }
    screen.shownHp = { player = battle.player.hp, enemy = battle.enemy.hp }
    screen.shownStatus = { player = false, enemy = false }
    screen.shownExp = 0
    update = function()
      screen:update(0)
    end
    index = function(value)
      if value then
        screen.menuIndex = value
      end
      return screen.menuIndex
    end
    ready = function()
      return screen:menuAuxiliarySafe()
    end
  else
    battle:syncSides()
    battle.phase, battle.frame, battle.queue = "menu", 0, {}
    battle.gen4CursorActive = true
    battle.checkpointOrigin = { kind = "trainer_encounter" }
    game.stack.states = { battle }
    update = function()
      battle:update(0)
    end
    index = function(value)
      if value then
        battle.menuIndex = value
      end
      return battle.menuIndex
    end
    ready = function()
      if backend == "gen2" then
        return require("src.battle.MenuAuxiliary").ready(battle)
      end
      return require("src.battle.BattleSafety").inspect(game, battle) == true
    end
  end
  f.update, f.index, f.ready = update, index, ready
  return f
end
return M
