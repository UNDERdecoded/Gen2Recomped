-- Exercise the actual battle producers, spying only at font/tile leaves.
local M = {}
local function upvalue(owner, wanted)
  local visited = {}
  local function search(fn)
    if type(fn) ~= "function" or visited[fn] then
      return
    end
    visited[fn] = true
    for i = 1, 100 do
      local name, value = debug.getupvalue(fn, i)
      if not name then
        break
      end
      if name == wanted then
        return value
      end
      local found = search(value)
      if found then
        return found
      end
    end
  end
  for _, fn in pairs(owner) do
    local found = search(fn)
    if found then
      return found
    end
  end
  error("native producer missing: " .. wanted)
end
function M.run(f)
  local T, Version = f.T, require("src.core.GameVersion")
  local e, mon, game = f.exports, f.mon, f.game
  local levels, labels, draw, b = 0, 0
  local restoreLeaf
  local function ink(text)
    text = tostring(text)
    if text == "42" or text == "Lv42" or text == "<LV>42" then
      levels = levels + 1
    end
    if text:find("Lv42", 1, true) or text:find("<LV>42", 1, true) then
      labels = labels + 1
    end
    return 16
  end
  if f.backend == "gen1" and Version.generation() == 3 then
    require("src.import.gba.versions").select(Version.get())
    local Font = require("src.ui.game3.frlg_font")
    f.patch(Font, "draw", ink)
    f.patch(Font, "drawGlyph", function(code)
      if code == Font.CHAR_LV_2 then
        labels = labels + 1
      end
    end)
    f.patch(Font, "advance", function()
      return 6
    end)
    -- This is the private routine Healthbox.draw uses for singles and doubles;
    -- keep it intact, with a real native state/session context.
    local level = upvalue(require("src.core.game3.battle.healthbox"), "draw_level")
    draw = function()
      for _, side in ipairs({ "enemy", "player" }) do
        level(mon.level, 0, 0, 0, mon, side, { session = { game = game } })
      end
    end
  else
    local Font = require("src.render.Font")
    Font.load(game.data)
    f.patch(Font, "draw", ink)
    f.patch(Font, "drawCode", function() end)
    f.patch(Font, "drawBox", function() end)
    local Hud = require("src.render.HudTiles")
    f.patch(Hud, "tile", function(code)
      if code == 0x6E then
        labels = labels + 1
      end
    end)
    local class = require(
      f.backend == "gen1" and Version.generation() == 2 and "src.ui.gen2.BattleState"
        or "src.battle.BattleState"
    )
    if jit and class.drawHUDs then
      jit.off(class.drawHUDs, true)
    end
    -- BattleState captures this font/tile leaf when its module is loaded.
    -- The SDK may already have loaded it before we install the recorder.
    for i = 1, 100 do
      local name, value = debug.getupvalue(class.drawHUDs or function() end, i)
      if not name then
        break
      end
      if name == "hudTile" then
        debug.setupvalue(class.drawHUDs, i, Hud.tile)
        restoreLeaf = function()
          debug.setupvalue(class.drawHUDs, i, value)
        end
        break
      end
    end
    b = setmetatable({
      game = game,
      data = game.data,
      phase = "contract",
      frame = 0,
      fx = {},
      ballRows = {},
      shown = {},
      showEnemyHud = true,
      showPlayerHud = true,
      player = { name = "SCOUT", mon = mon, shownHP = mon.hp, isPlayer = true },
      enemy = { name = "FOE", mon = mon, shownHP = mon.hp, isPlayer = false },
    }, { __index = class })
    if f.backend == "gen1" and Version.generation() == 2 then
      local Chrome = require("src.ui.gen2.Chrome")
      f.patch(Chrome, "printThrough", ink)
      f.patch(Chrome, "printRightThrough", ink)
      b.hud = {
        available = function()
          return true
        end,
        drawEnemyFrame = function() end,
        drawPlayerFrame = function() end,
        drawExpBar = function() end,
      }
      b.activeMon = function()
        return mon
      end
      b.name = function()
        return "SCOUT"
      end
      b.hudCleared = function()
        return false
      end
      b.statusTag = function() end
      b.genderSymbol = function() end
      b.caughtMarkerVisible = function()
        return false
      end
      b.hudHp = function()
        return mon.hp
      end
      b.drawHpBar = function() end
      draw = function()
        b:drawEnemyHud()
        b:drawPlayerHud()
      end
    else
      b.growInScale = function() end
      b.colorMode = function()
        return false
      end
      b.demoHidesPlayer = function()
        return false
      end
      draw = function()
        b:drawHUDs(0)
      end
    end
  end
  local seen = {}
  local off = f.result.loader.hooks:wrap("pokemon.level_visible", function(next, m, ctx)
    T.eq(m, mon, "native battle supplies actual Pokemon")
    T.eq(ctx.game, game, "native battle supplies current Game")
    seen[ctx.where] = true
    return next(m, ctx)
  end, 1000)
  local rows = {}
  for _, phase in ipairs({
    { enemy = false, player = false, count = 2 },
    { enemy = true, player = false, count = 1 },
    { enemy = false, player = true, count = 1 },
    { enemy = true, player = true, count = 0 },
    { enemy = false, player = false, count = 2 },
  }) do
    e.hide("battle.enemy", phase.enemy)
    e.hide("battle.player", phase.player)
    levels, labels, seen = 0, 0, {}
    draw()
    T.eq(levels, phase.count, "native battle level digits")
    T.eq(labels, phase.count, "native battle level labels")
    T.check(seen["battle.enemy"] and seen["battle.player"], "native battle surfaces")
    rows[#rows + 1] = { enemy = phase.enemy, player = phase.player, levels = levels, labels = labels }
  end
  off()
  if restoreLeaf then
    restoreLeaf()
  end
  return rows
end
return M
