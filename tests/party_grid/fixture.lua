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
    "portable_party_grid"
  )
  f.start()
  local game, battle, party = f.game, f.battle(), f.party()
  local menu
  local original = party[1]
  if backend == "gen1" and f.generation == 3 then
    menu = require("src.ui.game3.party_menu")
    menu.show(party, nil, { session = game.session, battle = battle, mode = "battle_switch" })
    f.index = function(value)
      if value then
        menu.cursor = value == "cancel" and 7 or value
      end
      return menu.cursor == 7 and "cancel" or menu.cursor
    end
    f.count = function(n)
      menu._party = {}
      for i = 1, n do
        menu._party[i] = original
      end
    end
    local oldClose = f.close
    f.close = function()
      menu.open = false
      oldClose()
    end
    f.update = function()
      menu.handleInput(game.input)
    end
    f.battleMode = function(value)
      menu._battle = value and battle or nil
    end
  elseif backend == "gen1" and f.generation == 2 then
    menu = require("src.ui.gen2.PartyMenu").new(game, { party = party, battle = true })
    f.count = function(n)
      menu.party = {}
      for i = 1, n do
        menu.party[i] = original
      end
    end
  else
    local class = f.generation == 3 and "src.ui.Gen3PartyMenu" or "src.ui.PartyMenu"
    menu = require(class).new(game, { battle = battle, party = party })
    f.count = function(n)
      local list = {}
      for i = 1, n do
        list[i] = original
      end
      if f.generation ~= 3 then
        menu.party = list
      end
      battle.playerParty = list
    end
    if f.generation == 3 then
      game.data.constants = game.data.constants or {}
      local slots = {}
      for i = 1, 6 do
        slots[i] = {
          window = { x = 0, y = 0, width = 80, height = 32 },
          icon = { x = i == 1 and 16 or 104, y = i == 1 and 40 or 18 + 24 * (i - 2) },
        }
      end
      game.data.constants.gen3PartyMenu = { slots = slots }
    end
  end
  if not f.index then
    f.index = function(value)
      if value then
        menu.index = value == "cancel" and #menu:party() + 1 or value
      end
      if f.generation == 3 and menu.index == #menu:party() + 1 then
        return "cancel"
      end
      return menu.index
    end
  end
  f.battleMode = f.battleMode or function(value)
    menu.battle = value and battle or nil
  end
  f.update = f.update or function()
    menu:update(0)
  end
  f.menu = menu
  f.press = function(direction)
    game.input.pressed = type(direction) == "table" and direction
      or (direction and { [direction] = true } or {})
    f.update()
    return f.index()
  end
  f.grid = function()
    if backend == "gen1" and f.generation == 3 then
      return menu.gridNavigation()
    end
    return menu:gridNavigation()
  end
  f.count(6)
  return f
end
return M
