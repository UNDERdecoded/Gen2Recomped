package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Fixture = dofile("tests/battle_bottom_ui/fixture.lua")
local Version = require("src.core.GameVersion")
local Battle = require("src.battle.BattleState")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local Font = require("src.render.Font")
local originalVersion = Version.get()
for _, version in ipairs(Version.ORDER) do
  for _, layout in ipairs({ "classic", "wide" }) do
    local f = Fixture.new(".", "gen2", version, 3, "unified")
    local game = f.game
    game.save = SaveData.newGame()
    game.save.options.battleLayout = layout
    game.save.party = { Pokemon.new(game.data, "FIXMON_A", 20) }
    f.result.loader.game = game
    Font.load(game.data)
    local b = Battle.newWild(game, "FIXMON_C", 10)
    b:syncSides()
    b.phase, b.frame, b.queue = "messages", 0, {}
    b.current, b.shown, b.fx = {}, {}, {}
    b.animPlaying = true
    b.animPlayer = { stepIndex = 1, steps = { { sprites = {} } } }
    game.stack.states = { b }
    local marks = {}
    local function mark(name)
      marks[name] = (marks[name] or 0) + 1
    end
    f.patch(b, "drawPicsLayer", function()
      mark("actors")
    end)
    f.patch(b, "drawHUDs", function()
      mark("hud")
    end)
    f.patch(b, "drawAnimLayer", function()
      mark("animation")
    end)
    f.patch(b, "drawBattleField", function()
      mark("field")
    end)
    f.patch(b, "colorMode", function()
      return false
    end)
    local rectangle = love.graphics.rectangle
    f.patch(love.graphics, "rectangle", function(mode, x, y, w, h, ...)
      if mode == "fill" and w >= 160 and h >= 120 then
        mark("field")
      end
      return rectangle(mode, x, y, w, h, ...)
    end)
    for _, name in ipairs({ "drawBox", "drawDialogueBox" }) do
      f.patch(Font, name, function(tx, ty)
        if ty >= 12 then
          mark("bottom")
        end
      end)
    end
    local Hud = require("src.render.HudTiles")
    f.patch(Hud, "tile", function()
      mark("hud")
    end)
    f.patch(Hud, "drawHPBar", function()
      mark("hud")
    end)
    local G4 = require("src.battle.Gen4Battle")
    f.patch(G4, "drawBattlers", function()
      mark("actors")
    end)
    f.patch(G4, "drawHealthboxes", function()
      mark("hud")
      return true
    end)
    f.patch(G4, "drawParticles", function()
      mark("animation")
    end)
    local function frame(hidden)
      f.exports.hide(hidden)
      marks = {}
      b:draw()
      local out = {}
      for key, value in pairs(marks) do
        out[key] = value
      end
      return out
    end
    local native, hidden = frame(false), frame(true)
    T.check((native.bottom or 0) > 0, version .. "/" .. layout .. " native bottom backing exists")
    T.eq(hidden.bottom or 0, 0, version .. "/" .. layout .. " actual compositor omits bottom backing")
    for _, part in ipairs({ "field", "actors", "hud" }) do
      T.check((native[part] or 0) > 0, part .. " exists before hiding")
      T.eq(hidden[part], native[part], part .. " dispatch unchanged when hiding bottom")
    end
    T.eq(hidden.animation, native.animation, "animation dispatch unchanged")
    -- Palette-canvas branch uses the same bottom gate as the flat GB path.
    if f.generation <= 2 and layout == "classic" then
      b.colorMode = function()
        return true
      end
      f.patch(b, "drawZonePass", function()
        mark("palette")
      end)
      local visibleColor, hiddenColor = frame(false), frame(true)
      T.check((visibleColor.bottom or 0) > 0, "palette compositor has native bottom")
      T.eq(hiddenColor.bottom or 0, 0, "palette compositor hides bottom")
      T.eq(hiddenColor.palette, visibleColor.palette, "palette pass is preserved")
      T.eq(hiddenColor.actors, visibleColor.actors, "palette actor pass is preserved")
    end
    -- Exercise the real battle update with identical inputs in both modes.
    b.animPlayer, b.animPlaying, b.current = nil, false, nil
    b.phase, b.menuIndex, b.gen4CursorActive = "menu", 1, true
    local function move(hiddenBottom)
      f.exports.hide(hiddenBottom)
      b.menuIndex, b.frame, b.gen4MenuColumn = 1, 0, nil
      f.input:reset()
      f.input:keypressed("down")
      f.input:step()
      local polls = f.exports.seen.calls
      b:update(1 / 60)
      T.eq(f.exports.seen.calls, polls, "native update never queries draw predicate")
      return b.menuIndex, b.frame
    end
    local index, ticks = move(false)
    local hiddenIndex, hiddenTicks = move(true)
    T.neq(index, 1, "native menu handles directional input")
    T.eq(hiddenIndex, index, "hidden native menu handles same input")
    T.eq(hiddenTicks, ticks, "hidden native battle advances same logic clock")
    f.close()
  end
end
Version.set(originalVersion)
T.finish("battle.bottom_ui_visible native composition")
