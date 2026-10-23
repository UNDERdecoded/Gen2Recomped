package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Fixture = dofile("tests/status_hud/fixture.lua")
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
    b.showPlayerBack, b.showEnemyTrainer, b.enemySendingOut, b.introBalls = false, false, false, false
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
    f.patch(Font, "draw", function(_, _, y)
      if type(y) == "number" and y < 104 then
        mark("hud")
      end
      return 16
    end)
    local G4 = require("src.battle.Gen4Battle")
    f.patch(G4, "drawBattlers", function()
      mark("actors")
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
    T.eq(hidden.bottom, native.bottom, "status predicate preserves native bottom backing")
    T.check((native.hud or 0) > 0, "native status text exists")
    T.eq(hidden.hud or 0, 0, "actual compositor omits status text")
    for _, part in ipairs({ "field", "actors" }) do
      T.check((native[part] or 0) > 0, part .. " exists before hiding")
      T.eq(hidden[part], native[part], part .. " dispatch unchanged when hiding status")
    end
    T.eq(hidden.animation, native.animation, "animation dispatch unchanged")
    -- Palette-canvas branch uses the same status gate as the flat GB path.
    if f.generation <= 2 and layout == "classic" then
      b.colorMode = function()
        return true
      end
      f.patch(b, "drawZonePass", function()
        mark("palette")
      end)
      local visibleColor, hiddenColor = frame(false), frame(true)
      T.check((visibleColor.bottom or 0) > 0, "palette compositor has native bottom")
      T.eq(hiddenColor.bottom, visibleColor.bottom, "palette compositor preserves bottom")
      T.check((visibleColor.hud or 0) > 0, "palette compositor has status text")
      T.eq(hiddenColor.hud or 0, 0, "palette compositor hides status text")
      T.eq(hiddenColor.palette, visibleColor.palette, "palette pass is preserved")
      T.eq(hiddenColor.actors, visibleColor.actors, "palette actor pass is preserved")
    end
    -- Bottom UI and status predicates remain independent in both directions.
    f.exports.hide(false)
    local off = f.public.hooks:wrap("battle.bottom_ui_visible", function()
      return false
    end)
    local bottomHidden = frame(false)
    T.eq(bottomHidden.bottom or 0, 0, "bottom predicate independently hides menu")
    T.eq(bottomHidden.hud, native.hud, "bottom predicate preserves native status")
    off()
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
    T.eq(hiddenIndex, index, "hidden HUD menu handles same input")
    T.eq(hiddenTicks, ticks, "hidden native battle advances same logic clock")
    f.close()
  end
end
Version.set(originalVersion)
T.finish("battle.status_hud_visible native composition")
