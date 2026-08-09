-- Public seams a tool mod needs: a fixed-step input hook and a
-- title-menu entry point.  Both are no-ops without a mod (gate_hooks.lua
-- covers that parity); this case proves a real public wrapper can act at the
-- correct point and decorate the real title menu.

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Hooks = require("src.mods.Hooks")
local Runtime = require("src.mods.Runtime")

local savedEvents, savedHooks, savedErrors =
  Runtime.events, Runtime.hooks, Runtime.errors
local hooks = Hooks.new()
Runtime.hooks = hooks

-- If input.step disappears, or moves after Input:step, a bot's buttons land
-- one logic tick late.  Exercise Game:step itself and pin the observable
-- ordering rather than merely checking that a hook was registered.
do
  local order = {}
  local fake = {
    input = { step = function() order[#order + 1] = "input" end },
    stack = { update = function(_, dt)
      order[#order + 1] = "world"
      T.eq(dt, 1 / 60, "the world receives the fixed-step dt")
    end },
    save = {},
  }
  hooks:wrap("input.step", function(nextFn, game, dt)
    T.check(game == fake, "input.step receives the live Game object")
    T.eq(dt, 1 / 60, "input.step receives the fixed-step dt")
    order[#order + 1] = "hook"
    return nextFn(game, dt)
  end, 0, "tool_fixture")

  require("src.core.Game").step(fake, 1 / 60)
  T.eq(table.concat(order, ","), "hook,input,world",
    "input.step runs before input edges are promoted and before gameplay")
  hooks:removeOwner("tool_fixture")
end

-- If ui.title_menu.items disappears, a tool mod can load but has no
-- safe user-facing way to begin a fresh, non-destructive run.
do
  local TitleState = require("src.ui.TitleState")
  local stack = { states = {} }
  function stack:push(state) self.states[#self.states + 1] = state end
  function stack:top() return self.states[#self.states] end
  local game = {
    data = { field = { title = { cycleSpecies = { "MEW" } } },
             pokemon = { MEW = {} } },
    stack = stack,
  }

  hooks:wrap("ui.title_menu.items", function(nextFn, liveGame, items)
    T.check(liveGame == game, "ui.title_menu.items receives the live Game")
    table.insert(items, #items, { label = "AUTOPLAY" })
    return nextFn(liveGame, items)
  end, 0, "tool_fixture")

  TitleState.new(game, {}):openMenu()
  local menu = stack:top()
  T.eq(menu.items[#menu.items - 1].label, "AUTOPLAY",
    "ui.title_menu.items can insert AUTOPLAY before EXIT GAME")
  hooks:removeOwner("tool_fixture")
end

-- A viewer/AI session must be able to veto every normal progress-save path,
-- including the in-game SAVE menu and autosaves, before captureSave mutates
-- the live snapshot in preparation for disk IO.
do
  local captured = false
  local fake = {
    save = {},
    overworld = { captureSave = function() captured = true end },
  }
  hooks:wrap("save.write", function(nextFn, game)
    T.check(game == fake, "save.write receives the live Game object")
    return false
  end, 0, "tool_fixture")

  local saved = require("src.core.Game").writeSave(fake)
  T.eq(saved, false, "save.write can veto progress persistence")
  T.eq(captured, false, "a veto happens before save-state capture")
  hooks:removeOwner("tool_fixture")
end

-- A tool status indicator draws in window space after the renderer composites
-- the game. This gives it exact playfield/margin geometry and keeps it crisp
-- over compatible render pipelines without entering the game canvas.
do
  local Renderer = require("src.render.Renderer")
  local TouchControls = require("src.core.TouchControls")
  local savedSetUISize, savedBegin, savedEnd, savedTouch =
    Renderer.setUISize, Renderer.beginFrame, Renderer.endFrame,
    TouchControls.draw
  local order = {}
  Renderer.setUISize = function() end
  Renderer.beginFrame = function() end
  Renderer.endFrame = function()
    order[#order + 1] = "present"
    return {
      width = 1024, height = 768,
      gameX = 112, gameY = 24,
      gameWidth = 800, gameHeight = 720,
      scale = 5,
    }
  end
  TouchControls.draw = function() order[#order + 1] = "touch" end

  -- Game:draw iterates stack.states and calls each state's draw (it no
  -- longer goes through stack:draw), so the fixture must put a drawable
  -- state on the stack to observe composition order.
  local fake = {
    overworld = {},
    stack = {
      states = {
        { draw = function() order[#order + 1] = "states" end },
      },
    },
  }
  function fake.stack:visibleBase() return 1 end
  function fake.stack:top() return self.states[#self.states] end

  hooks:wrap("render.hud", function(nextFn, game, viewport)
    T.check(game == fake, "render.hud receives the live Game object")
    T.eq(viewport.width, 1024, "render.hud receives the window width")
    T.eq(viewport.height, 768, "render.hud receives the window height")
    T.eq(viewport.gameX, 112, "render.hud receives the playfield origin")
    T.eq(viewport.gameWidth, 800, "render.hud receives the playfield width")
    order[#order + 1] = "hud"
    return nextFn(game, viewport)
  end, 0, "tool_fixture")

  require("src.core.Game").draw(fake)
  T.eq(table.concat(order, ","), "states,present,hud,touch",
    "render.hud draws after frame composition and before touch controls")
  hooks:removeOwner("tool_fixture")
  Renderer.setUISize, Renderer.beginFrame, Renderer.endFrame,
    TouchControls.draw = savedSetUISize, savedBegin, savedEnd, savedTouch
end

Runtime.events, Runtime.hooks, Runtime.errors =
  savedEvents, savedHooks, savedErrors

T.finish("tool_mod_hooks")
