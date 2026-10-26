local M = {}
function M.new(root, backend, version, api, format)
  local f = dofile(root .. "/tests/battle_auxiliary/shared.lua").new(
    root,
    backend,
    version,
    api,
    format,
    "portable_battle_grid"
  )
  local b, game = f.battle(), f.game
  local Ui, screen
  if backend == "gen1" and f.generation == 3 then
    Ui = require("src.core.game3.battle.ui")
    Ui._mode, Ui._moveIndex = "moves", 1
    f.handle = b
    f.grid = function()
      return Ui.moveGridNavigation()
    end
    f.index = function(value)
      if value then
        Ui._moveIndex = value
      end
      return Ui._moveIndex
    end
    f.count = function(n)
      b.player.mon.moves, b.player.mon.pp, b.player.mon.maxPp = {}, {}, {}
      for i = 1, n do
        b.player.mon.moves[i] = 33
        b.player.mon.pp[i] = 35
        b.player.mon.maxPp[i] = 35
      end
    end
    f.double = function(value)
      b.double = value
      if value then
        f.update = function()
          Ui.handleInput(game.input)
        end
      else
        f.update = function()
          require("src.core.game3.battle").update(0, game)
        end
      end
    end
  elseif backend == "gen1" and f.generation == 2 then
    screen = game.stack:top()
    screen.phase, screen.moveIndex = "moves", 1
    f.handle = screen
    f.grid = function()
      return screen:moveGridNavigation()
    end
    f.index = function(value)
      if value then
        screen.moveIndex = value
      end
      return screen.moveIndex
    end
    f.count = function(n)
      b.player.moves = {}
      for i = 1, n do
        b.player.moves[i] = "SPLASH"
      end
    end
  else
    b.phase, b.moveIndex = "moveSelect", 1
    f.handle = b
    f.grid = function()
      return b:moveGridNavigation()
    end
    f.index = function(value)
      if value then
        b.moveIndex = value
      end
      return b.moveIndex
    end
    f.count = function(n)
      local moves = {}
      for i = 1, n do
        moves[i] = { id = "FIX_TACKLE", pp = 35 }
      end
      b.player.curMoves, b.player.mon.moves = moves, moves
    end
    f.double = function(value)
      b.double = value
    end
  end
  f.count(4)
  f.press = function(direction)
    game.input.pressed = direction and { [direction] = true } or {}
    f.update()
    return f.index()
  end
  return f
end
return M
