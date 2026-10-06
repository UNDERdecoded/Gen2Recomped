-- tools/gen4_battle_ui_harness/main.lua
--
-- PLATINUM'S BATTLE PRESENTATION, BOTH SCREENS, IN THE STATES THAT MATTER,
-- into battle_ui.png (LOVE save directory, identity `bt_gen4_battle_ui`).
-- Each row is one state: the top screen on the left, the bottom screen (when
-- that state draws one) on the right.
--
--   POKEPORT_DATA_DIR=<platinum cache>/data/generated \
--   POKEPORT_ASSET_ROOT=<platinum cache> love tools/gen4_battle_ui_harness
--
-- (run from the repository root).  STATES=a,b,... limits the rows; the names
-- are the first column of SCENES below.
--
-- Unlike tools/gen4_battle_harness (one battle, ticked, one frame) this one
-- builds a fresh battle per state, walks it to the action menu by pressing A,
-- and then sets up the state by hand -- the menus have no other way to be
-- looked at headless.

local function stubAssets(assetRoot)
  local Assets = require("src.render.Assets")
  local realImage, held = Assets.image, {}
  Assets.image = function(path, ...)
    if type(path) == "string" and not held[path] then
      local f = io.open(assetRoot .. "/" .. path, "rb")
      if f then
        local bytes = f:read("*a"); f:close()
        local okI, img = pcall(love.graphics.newImage, love.filesystem.newFileData(bytes, path))
        if okI then img:setFilter("nearest", "nearest"); held[path] = img end
      end
    end
    return held[path] or realImage(path, ...)
  end
  local realData, heldData = Assets.imageData, {}
  Assets.imageData = function(path, ...)
    if type(path) == "string" and not heldData[path] then
      local f = io.open(assetRoot .. "/" .. path, "rb")
      if f then
        local bytes = f:read("*a"); f:close()
        local okD, d = pcall(love.image.newImageData, love.filesystem.newFileData(bytes, path))
        if okD then heldData[path] = d end
      end
    end
    return heldData[path] or realData(path, ...)
  end
end

function love.load()
  local ok, err = xpcall(function()
    require("src.core.GameVersion").set("platinum")
    local assetRoot = os.getenv("POKEPORT_ASSET_ROOT")
    if assetRoot then stubAssets(assetRoot) end
    local Data = require("src.core.Data")
    Data:load()
    require("src.render.Font").load(Data)
    pcall(function() require("src.ui.Theme").load(Data) end)

    -- The bottom screen is captured, not shown: `draw` hands its body here.
    local bottomFn
    local stowed = false
    local SS = require("src.ui.SecondScreen")
    SS.mode = function() return "display" end
    SS.stowed = function() return stowed end
    SS.draw = function(_, fn) bottomFn = fn end
    SS.drawFrame = function() end

    local Pokemon = require("src.pokemon.Pokemon")
    local SaveData = require("src.core.SaveData")
    local BattleState = require("src.battle.BattleState")
    local Game = require("src.core.Game")
    Game.data = Data

    local scratch
    local function newBattle(opts)
      Game.save = SaveData.newGame(Game.bootConfig and Game:bootConfig() or {})
      local lead = Pokemon.new(Data, opts.party or 392, opts.partyLevel or 18)
      Game.save.party = { lead }
      for _, extra in ipairs(opts.more or {}) do
        local m = Pokemon.new(Data, extra[1], extra[2])
        if extra.hp then m.hp = extra.hp end
        if extra.status then m.status = extra.status end
        Game.save.party[#Game.save.party + 1] = m
      end
      if opts.owned then
        Game.save.pokedex = Game.save.pokedex or { seen = {}, owned = {} }
        Game.save.pokedex.owned = Game.save.pokedex.owned or {}
        Game.save.pokedex.owned[opts.species or 396] = true
      end
      local pressed = false
      Game.input = {
        wasPressed = function(_, k) return pressed and (k == "a") end,
        isDown = function() return false end,
        wasReleased = function() return false end,
      }
      local battle
      if opts.trainer then
        battle = BattleState.newTrainer(Game, opts.trainer, 1)
      else
        battle = BattleState.newWild(Game, opts.species or 396, opts.level or 4)
      end
      if battle.enter then pcall(battle.enter, battle) end
      for i = 1, opts.ticks or 900 do
        pressed = (i % 20 == 0)
        local okU, errU = pcall(battle.update, battle, 1 / 60)
        if not okU then print("update raised: " .. tostring(errU)); break end
        -- the party gauge animates off the frames it is DRAWN on, so a
        -- state that wants it mid-flight draws every tick (offscreen)
        if opts.drawEach then
          scratch = scratch or love.graphics.newCanvas(256, 192)
          love.graphics.setCanvas(scratch)
          pcall(battle.draw, battle)
          love.graphics.setCanvas()
        end
        if battle.phase == "menu" and not opts.ticks then break end
      end
      pressed = false
      return battle
    end

    local SCENES = {
      { "intro", { ticks = 140 } },
      { "menu", {} },
      { "moves", {}, function(b)
          b.phase = "moveSelect"; b.moveIndex = 2
        end },
      { "lowhp", { owned = true, more = { { 25, 14, hp = 0 }, { 54, 12, status = "PSN" } } }, function(b)
          b.player.mon.hp = math.max(1, math.floor(b.player.mon.stats.hp / 8))
          b.player.shownHP = b.player.mon.hp
          b.player.mon.status = "PAR"
          b.enemy.mon.hp = math.max(1, math.floor(b.enemy.mon.stats.hp * 0.4))
          b.enemy.shownHP = b.enemy.mon.hp
          b.enemy.mon.status = "PSN"
          for i, mv in ipairs(b.player.curMoves or {}) do mv.pp = math.max(0, mv.pp - 9 * (i - 1)) end
        end },
      { "lowhp_moves", { more = { { 25, 14, hp = 0 } } }, function(b)
          b.player.mon.hp = 3; b.player.shownHP = 3
          b.player.mon.status = "BRN"
          for i, mv in ipairs(b.player.curMoves or {}) do mv.pp = math.max(0, mv.pp - 9 * (i - 1)) end
          b.phase = "moveSelect"; b.moveIndex = 4
        end },
      { "trainer_intro", { trainer = tonumber(os.getenv("TRAINER") or "2"), ticks = tonumber(os.getenv("INTRO") or "150"), drawEach = true } },
      { "trainer", { trainer = tonumber(os.getenv("TRAINER") or "2") } },
      -- a double's "at whom?", built by hand on a single battle: the foe on
      -- the left foe slot, a copy of it on the right one, the partner beside
      { "target", {}, function(b)
          local function as(src, pos, name)
            local c = setmetatable({ position = pos, name = name or src.name }, { __index = src })
            return c
          end
          b.targetChoices = { as(b.enemy, 1), as(b.enemy, 3, "SHINX"), as(b.player, 2, "PACHIRISU") }
          b.targetIndex = 2
          b.pendingMove = b.player.curMoves and b.player.curMoves[1]
          b.phase = "targetSelect"
        end },
      -- the battle party list, both of its screens, over a full party: the
      -- lead in battle, a fainted one, a poisoned one holding an item, an
      -- egg, a red-HP one and one more
      { "party", { more = { { 25, 14, hp = 0 }, { 54, 12, status = "PSN" }, { 175, 1 }, { 133, 9 }, { 396, 7 } } },
        function(b)
          local party = b.game.save.party
          party[3].item = 1
          party[4].isEgg = true; party[4].egg = true
          party[5].hp = 2
          local P = require("src.ui.Gen4BattleParty")
          print("party screen id: " .. tostring(require("src.battle.Gen4Battle").partyScreenId(b)))
          local s = P.new(b.game, { battle = b })
          s.index = 3
          return s
        end },
      { "party_select", { more = { { 25, 14 } } }, function(b)
          local P = require("src.ui.Gen4BattleParty")
          local s = P.new(b.game, { battle = b })
          s.index = 2; s.screen = "select"; s.selectIndex = 3
          return s
        end },
      { "compact", {}, function() stowed = true end },
      { "compact_moves", {}, function(b) stowed = true; b.phase = "moveSelect"; b.moveIndex = 1 end },
    }
    local only = {}
    for name in (os.getenv("STATES") or ""):gmatch("[^,]+") do only[name] = true end

    local rows = {}
    for _, sc in ipairs(SCENES) do
      if next(only) == nil or only[sc[1]] then
        stowed = false
        local okB, battle = pcall(newBattle, sc[2])
        if not okB then
          print(sc[1] .. ": " .. tostring(battle))
        else
          local overlay = sc[3] and sc[3](battle)
          bottomFn = nil
          local top = love.graphics.newCanvas(256, 192)
          love.graphics.setCanvas(top)
          love.graphics.clear(0, 0, 0, 1)
          local okD, errD = pcall(battle.draw, battle)
          -- a screen the battle opened, drawn over it as the stack would
          if type(overlay) == "table" and overlay.draw then
            local okO, errO = pcall(overlay.draw, overlay)
            if not okO then print(sc[1] .. " overlay raised: " .. tostring(errO)) end
          end
          love.graphics.setCanvas()
          if not okD then print(sc[1] .. " draw raised: " .. tostring(errD)) end
          local bottom
          if bottomFn then
            bottom = love.graphics.newCanvas(256, 192)
            love.graphics.setCanvas(bottom)
            love.graphics.clear(0, 0, 0, 1)
            local okF, errF = pcall(bottomFn)
            love.graphics.setCanvas()
            if not okF then print(sc[1] .. " bottom raised: " .. tostring(errF)) end
          end
          print(("%-14s phase=%s menuIndex=%s"):format(sc[1], tostring(battle.phase),
                tostring(battle.menuIndex)))
          rows[#rows + 1] = { top, bottom }
        end
      end
    end
    local sheet = love.graphics.newCanvas(2 * 260, #rows * 196)
    love.graphics.setCanvas(sheet)
    love.graphics.clear(1, 0, 1, 1)
    for i, r in ipairs(rows) do
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(r[1], 0, (i - 1) * 196)
      if r[2] then love.graphics.draw(r[2], 260, (i - 1) * 196) end
    end
    love.graphics.setCanvas()
    sheet:newImageData():encode("png", "battle_ui.png")
    print("saved to " .. love.filesystem.getSaveDirectory())
  end, debug.traceback)
  if not ok then print(err) end
  love.event.quit()
end

function love.draw() end
