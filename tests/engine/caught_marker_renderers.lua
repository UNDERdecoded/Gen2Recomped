package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local V = require("src.core.GameVersion")
local Battle, G3 = require("src.battle.BattleState"), require("src.battle.Gen3Battle")
local Font, Hud, Assets =
  require("src.render.Font"), require("src.render.HudTiles"), require("src.render.Assets")
local Fixture = dofile("tests/caught_marker/fixture.lua")
local old = V.get()
if jit then
  jit.off(Battle.drawHUDs, true)
end
local function upvalue(owner, wanted)
  local visited = {}
  local function scan(fn)
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
      local found = scan(value)
      if found then
        return found
      end
    end
  end
  for _, fn in pairs(owner) do
    local found = scan(fn)
    if found then
      return found
    end
  end
  error("missing native compositor " .. wanted)
end
local wideHUDs = upvalue(require("src.battle.WideBattle"), "drawHUDs")
for _, version in ipairs(V.ORDER) do
  if V.generation(version) <= 3 then
    for _, mode in ipairs({ { 1, "native" }, { 2, "native" }, { 2, "unified" }, { 3, "unified" } }) do
      local f = Fixture.new(".", "gen2", version, mode[1], mode[2])
      local restore = {}
      local function patch(owner, key, value)
        local old = owner[key]
        restore[#restore + 1] = function()
          owner[key] = old
        end
        owner[key] = value
      end
      local ink = 0
      patch(Font, "draw", function(s)
        return Font.width(s)
      end)
      patch(Font, "drawCode", function() end)
      patch(Font, "drawBox", function() end)
      patch(Hud, "tile", function(code)
        if code == 0x5d then
          ink = ink + 1
        end
      end)
      patch(Battle, "drawCaughtBall", function()
        ink = ink + 1
      end)
      for i = 1, 100 do
        local key, value = debug.getupvalue(Battle.drawHUDs, i)
        if not key then
          break
        end
        if key == "hudTile" then
          debug.setupvalue(Battle.drawHUDs, i, Hud.tile)
          restore[#restore + 1] = function()
            debug.setupvalue(Battle.drawHUDs, i, value)
          end
          break
        end
      end
      local game = f.game
      game.save = require("src.core.SaveData").newGame()
      game.save.party = { require("src.pokemon.Pokemon").new(f.data, "FIXMON_A", 20) }
      game.save.pokedex = { seen = {}, owned = { FIXMON_C = true }, caught = { FIXMON_C = true } }
      Font.load(f.data)
      local b = Battle.newWild(game, "FIXMON_C", 20)
      b.phase, b.frame, b.fx, b.shown = "contract", 0, {}, {}
      b.introBalls, b.showPlayerBack, b.showEnemyTrainer, b.enemySendingOut = false, true, false, false
      b.growInScale = function() end
      b.colorMode = function()
        return false
      end
      b.demoHidesPlayer = function()
        return false
      end
      if f.gen == 3 then
        local panel, marker = love.graphics.newCanvas(128, 40), love.graphics.newCanvas(8, 8)
        local markerPath = "marker"
        local draw = love.graphics.draw
        patch(Assets, "exists", function(path)
          return path == markerPath
        end)
        patch(Assets, "image", function(path)
          return path == markerPath and marker or panel
        end)
        patch(love.graphics, "draw", function(image, ...)
          if image == marker then
            ink = ink + 1
          else
            return draw(image, ...)
          end
        end)
        f.data.constants.gen3BattleHud =
          { images = { opponent = "panel", player = "panel", caught = "marker" } }
      end
      local function draw(mode, refresh, wanted, expectedCalls, wide)
        f.e.state.mode = mode
        if refresh then
          b.enemy.name = "FOE" .. tostring(b.frame)
          b.frame = b.frame + 1
        end
        local calls = f.e.state.calls
        ink = 0
        if wide then
          wideHUDs(b, 0)
        else
          b:drawHUDs(0)
        end
        T.eq(ink, wanted, "native compositor emits expected marker: " .. version .. "/" .. mode)
        T.eq(f.e.state.calls - calls, expectedCalls, "native compositor queries marker only when eligible")
      end
      draw("native", true, f.gen == 1 and 0 or 1, 1)
      draw("hide", false, f.gen == 3 and 1 or 0, f.gen == 3 and 0 or 1)
      draw("hide", true, 0, 1)
      draw("show", true, 1, 1)
      b.enemy.shownStatus = "PSN"
      draw("show", true, f.gen == 3 and 0 or 1, f.gen == 3 and 0 or 1)
      b.enemy.shownStatus = nil
      local off = f.e.api.hooks:wrap("battle.status_hud_visible", function()
        return false
      end)
      draw("show", true, 0, 0)
      off()
      b.kind = "trainer"
      draw("show", true, 0, 0)
      b.kind = "wild"
      game.save.pokedex.owned.FIXMON_C, game.save.pokedex.caught.FIXMON_C = nil, nil
      draw("show", true, 0, 0)
      game.save.pokedex.owned.FIXMON_C = true
      if f.gen < 3 then
        draw("show", true, 1, 1, true)
        draw("hide", true, 0, 1, true)
      else
        b.double = true
        T.eq(
          require("src.battle.CaughtMarker").gbaVisible(b, b.enemy),
          false,
          "GBA doubles retain native marker exclusion"
        )
      end
      if f.gen == 3 then
        b.double = false
        local legacy = love.graphics.newCanvas(8, 16)
        local path = V.get() == "firered" and "assets/generated/pokedex_frlg/caught.png"
          or "assets/generated/ui/pokedex/caught_ball.png"
        f.data.constants.gen3BattleHud.images.caught = nil
        patch(Assets, "exists", function(candidate)
          assert(type(candidate) == "string", "asset lookup requires a path string")
          return candidate == path
        end)
        local panel = love.graphics.newCanvas(128, 40)
        patch(Assets, "image", function(candidate)
          return candidate == path and legacy or panel
        end)
        local quadArgs
        local quad = love.graphics.newQuad
        patch(love.graphics, "newQuad", function(...)
          quadArgs = { ... }
          return quad(...)
        end)
        patch(love.graphics, "draw", function(image)
          if image == legacy then
            ink = ink + 1
          end
        end)
        draw("show", true, 1, 1)
        T.check(quadArgs ~= nil, "legacy tall marker uses a cropped native tile")
        T.same(quadArgs, { 0, 4, 8, 8, 8, 16 }, "legacy cell crops to central 8x8 without stretching")
        f.data.constants.gen3BattleHud.images.caught = { invalid = true }
        draw("show", true, 1, 1)
        patch(Assets, "exists", function()
          return false
        end)
        draw("show", true, 0, 1)
      end
      for i = #restore, 1, -1 do
        restore[i]()
      end
      f.close()
    end
  end
end
V.set(old)
T.finish("caught marker native classic, wide and GBA compositors")
