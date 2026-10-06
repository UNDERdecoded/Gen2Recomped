-- tools/gen4_trainer_card_harness/main.lua
--
-- PLATINUM'S TRAINER CASE, RENDERED in the states that matter, into
-- trainer_card.png (LOVE save directory): the front at every card level
-- (normal .. black, 0..5 stars) and the no-dex face, Dawn's card, the back,
-- the colon's hidden half of the blink, the badge case with the lid down and
-- open (three badges and all eight) on the touch screen, the case page on a
-- single screen, and a cache without gen4_trainer_card_art (the fallback).
--
--   POKEPORT_DATA_DIR=<platinum cache>/data/generated \
--   POKEPORT_ASSET_ROOT=<platinum cache> love tools/gen4_trainer_card_harness
--
-- (run from the repository root).  The cache needs `gen4_trainer_card_art`
-- (see tools/gen4_art_extract `trainer_card`).

function love.load()
  local ok, err = xpcall(function()
    require("src.core.GameVersion").set("platinum")
    local assetRoot = os.getenv("POKEPORT_ASSET_ROOT")
    if assetRoot then
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
    end
    local Data = require("src.core.Data")
    Data:load()
    require("src.render.Font").load(Data)
    pcall(function() require("src.ui.Theme").load(Data) end)

    local bottomFn
    local secondShown = true
    package.loaded["src.ui.SecondScreen"] = {
      mode = function() return secondShown and "display" or "swap" end,
      stowed = function() return false end, draw = function(_, fn) bottomFn = fn end,
      -- the harness hands bottom-screen coordinates straight through
      toLocal = function(_, x, y) return x, y end }
    local pressed = {}
    local FAILS = 0
    local function check(cond, what)
      if not cond then FAILS = FAILS + 1 end
      print((cond and "ok   " or "FAIL ") .. what)
    end
    local function frames(s, n) for _ = 1, n do s:update(); pressed = {} end end

    local Badges = require("src.inventory.Badges")
    local function makeSave(opts)
      local inv = {}
      for i, entry in ipairs(Badges.list(Data) or {}) do
        if i <= (opts.badges or 0) then inv[Badges.itemFor(entry)] = 1 end
      end
      local seen = {}
      if opts.dex ~= false then for s = 1, 151 do seen[s] = true end end
      local signature
      if opts.signature then
        -- a looping scrawl, as 64 rows of 192 '0'/'1'
        signature = {}
        for y = 0, 63 do
          local line = {}
          for x = 0, 191 do
            local cy = 32 + math.floor(18 * math.sin(x / 9) + 6 * math.sin(x / 3.1))
            line[#line + 1] = (x > 12 and x < 180 and math.abs(y - cy) <= 1) and "1" or "0"
          end
          signature[#signature + 1] = table.concat(line)
        end
      end
      return { inventory = inv, money = 123456, playTime = 3600 * 12 + 60 * 34,
        player = { gender = opts.gender or "boy", name = "LUCAS", id = 54321, signature = signature },
        badgePolish = opts.polish,
        pokedex = { seen = seen, owned = {} }, flags = {}, options = {} }
    end
    local function makeGame(save)
      return { data = Data, save = save,
        input = { wasPressed = function(_, k) return pressed[k] == true end, isDown = function() return false end },
        stack = { pop = function() end, push = function() end } }
    end
    local Card = require("src.ui.Gen4TrainerCard")

    local scenes = {
      { "normal", {}, function(s) end },
      { "cobalt", {}, function(s) s.face = "cobalt" end },
      { "bronze", {}, function(s) s.face = "bronze" end },
      { "silver", {}, function(s) s.face = "silver" end },
      { "gold", {}, function(s) s.face = "gold" end },
      { "black", {}, function(s) s.face = "black" end },
      { "no dex, dawn", { dex = false, gender = "girl" }, function(s) end },
      { "back", {}, function(s) s.page = 2 end },
      { "colon off", {}, function(s) s.t = 3 end },
      { "lid down (bottom)", { badges = 3 }, function(s) end, true },
      { "case open, 3 (bottom)", { badges = 3 }, function(s) s:setLid(true) end, true },
      { "case open, 8 (bottom)", { badges = 8 }, function(s) s:setLid(true) end, true },
      { "case page, one screen", { badges = 8 }, function(s) s.page = 3 end, false, false },
      { "no card art", {}, function(s) s.cardArt = {} end },
      -- the flip: A, then five and seven frames (shrinking), eleven and
      -- fourteen (past the swap at frame 10, the back growing)
      { "flip, frame 5", {}, function(s) pressed.a = true; frames(s, 5) end },
      { "flip, frame 7", {}, function(s) pressed.a = true; frames(s, 7) end },
      { "flip, frame 11 (back)", {}, function(s) pressed.a = true; frames(s, 11) end },
      { "flip, frame 14 (back)", {}, function(s) pressed.a = true; frames(s, 14) end },
      { "back, signed", { signature = true }, function(s) s.page = 2 end },
      -- a tap on the button through touchpressed, then six frames: the lid
      -- part way up, the button fully pressed, the effect running
      { "button tap, 4 frames (bottom)", { badges = 8 }, function(s)
          s:touchpressed("mouse", 130, 160); frames(s, 4) end, true },
      { "lid half open (bottom)", { badges = 8 }, function(s)
          s:touchpressed("mouse", 130, 160); s:touchreleased("mouse"); frames(s, 11) end, true },
      { "polish levels (bottom)", { badges = 8,
          polish = { 50, 120, 140, 175, 199, 190, 169, 100 } }, function(s) s:setLid(true); s.t = 20 end, true },
      { "polish, sparkles later (bottom)", { badges = 8,
          polish = { 50, 120, 140, 175, 199, 190, 169, 100 } }, function(s) s:setLid(true); s.t = 37 end, true },
      { "button held (bottom)", { badges = 3 }, function(s)
          s:setLid(true); s.buttonFace = 2; s.effectT = 3 end, true },
    }
    local pages = {}
    for _, sc in ipairs(scenes) do
      secondShown = sc[5] ~= false
      local screen = Card.new(makeGame(makeSave(sc[2])), {})
      sc[3](screen)
      if screen.face ~= screen:faceName() then
        -- a forced level: the ink is read for that face
        screen.inkPair = require("src.render.Gen4Palettes").text(Data,
          "trainer_card/trainer_card_front" .. (({ cobalt = "_cobalt", bronze = "_bronze", silver = "_silver",
            gold = "_gold", black = "_black", no_dex = "_no_dex" })[screen.face] or ""), 15, 1, 2)
      end
      bottomFn = nil
      local cv = love.graphics.newCanvas(256, 192)
      love.graphics.setCanvas(cv)
      love.graphics.clear(0, 0, 0, 1)
      screen:draw()
      love.graphics.setCanvas()
      if sc[4] and bottomFn then
        local b = love.graphics.newCanvas(256, 192)
        love.graphics.setCanvas(b)
        love.graphics.clear(0, 0, 0, 1)
        bottomFn()
        love.graphics.setCanvas()
        pages[#pages + 1] = b
      else
        pages[#pages + 1] = cv
      end
      print(sc[1], screen.face, screen.page)
    end
    local perRow = 3
    local rows = math.ceil(#pages / perRow)
    local sheet = love.graphics.newCanvas(perRow * 260, rows * 196)
    love.graphics.setCanvas(sheet)
    love.graphics.clear(1, 0, 1, 1)
    for i, p in ipairs(pages) do
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(p, ((i - 1) % perRow) * 260, math.floor((i - 1) / perRow) * 196)
    end
    love.graphics.setCanvas()
    sheet:newImageData():encode("png", "trainer_card.png")
    print("saved to " .. love.filesystem.getSaveDirectory())

    -- THE STATE MACHINE, against TrainerCaseApp_Main's own frame counts
    secondShown = true
    do
      local s = Card.new(makeGame(makeSave({})), {})
      pressed.a = true
      local n = 0
      repeat frames(s, 1); n = n + 1 until s.state == "main" or n > 60
      -- 1 initial, 8 shrinking, 1 swap, 7 growing
      check(n == 17 and s.page == 2, ("A flips to the back in 17 frames (took %d, page %d)"):format(n, s.page))
      pressed.a = true; frames(s, 1)
      check(s.state == "flip", "A on the back flips again")
      frames(s, 20)
      check(s.page == 1 and s:cardScale() == 1, "and lands on the front at scale 1")
    end
    do
      local s = Card.new(makeGame(makeSave({ badges = 8 })), {})
      check(s:touchpressed("mouse", 130, 160) == true, "a touch on the shown bottom screen is claimed")
      frames(s, 1)
      check(s.state == "lid" and s.buttonFace == 1 and s.effectT == 1, "the tap pushes the button half way and starts the effect")
      frames(s, 1)
      check(s.buttonFace == 2, "then fully")
      local n = 2
      repeat frames(s, 1); n = n + 1 until s.state == "main" or n > 60
      check(s.lidOpen and math.abs(s.lidScale - 1 / 32) < 1e-9,
            ("the lid opens to 1/32 (open %s, scale %.4f, %d frames)"):format(tostring(s.lidOpen), s.lidScale, n))
      check(s.buttonFace == 2, "the button stays down while the touch holds it")
      s:touchmoved("mouse", 30, 60); frames(s, 3)
      check(s.buttonFace == 0, "and springs back when the touch leaves it")
      s:touchreleased("mouse")
      -- polishing Coal (140, normal: four counted steps a point)
      s:touchpressed("mouse", 40, 60); frames(s, 1)
      for i = 1, 40 do s:touchmoved("mouse", (i % 2 == 0) and 40 or 50, 60); frames(s, 1) end
      s:touchreleased("mouse"); frames(s, 1)
      local p = s.game.save.badgePolish and s.game.save.badgePolish[1]
      check(p and p >= 148 and p <= 150, ("forty rubs over Coal polish it 140 -> ~149 (got %s)"):format(tostring(p)))
      -- a wobble of under 3 px counts for nothing
      s:touchpressed("mouse", 40, 60); frames(s, 1)
      for i = 1, 20 do s:touchmoved("mouse", (i % 2 == 0) and 40 or 42, (i % 2 == 0) and 60 or 62); frames(s, 1) end
      s:touchreleased("mouse")
      check(s.game.save.badgePolish[1] == p, "strokes under 3 px do not polish")
      -- close again with SELECT, the key path
      pressed.select = true; frames(s, 1)
      frames(s, 30)
      check(not s.lidOpen and s.lidScale == 1 and s.state == "main", "SELECT closes the lid")
      s:touchpressed("mouse", 40, 60); frames(s, 1)
      for i = 1, 10 do s:touchmoved("mouse", (i % 2 == 0) and 40 or 50, 60); frames(s, 1) end
      s:touchreleased("mouse")
      check(s.game.save.badgePolish[1] == p, "with the lid down the badges cannot be touched")
      local popped = false
      s.game.stack.pop = function() popped = true end
      pressed.b = true; frames(s, 1)
      check(popped, "B leaves")
    end
    do
      local s = Card.new(makeGame(makeSave({ badges = 1 })), {})
      s:setLid(true)
      s:touchpressed("mouse", 100, 60); frames(s, 1)
      for i = 1, 20 do s:touchmoved("mouse", (i % 2 == 0) and 90 or 100, 60); frames(s, 1) end
      s:touchreleased("mouse")
      check(not (s.game.save.badgePolish and s.game.save.badgePolish[2]), "a badge not yet won cannot be polished")
      check(Card.polishLevel(99) == 0 and Card.polishLevel(100) == 1 and Card.polishLevel(140) == 2
            and Card.polishLevel(170) == 3 and Card.polishLevel(190) == 4 and Card.polishLevel(199) == 4,
            "the polish levels at the cartridge's thresholds")
      check(Card.dirtRow(0) == 3 and Card.dirtRow(1) == 2 and Card.dirtRow(2) == 1 and Card.dirtRow(3) == 0
            and Card.dirtRow(4) == 0, "the dirt rows: 3 - level, 0 at four sparkles")
    end
    secondShown = false
    do
      local s = Card.new(makeGame(makeSave({})), {})
      check(s:touchpressed("mouse", 130, 160) == false, "without the bottom screen a touch is not claimed")
      pressed.a = true; frames(s, 20)
      check(s.page == 2 and s.state == "main", "one screen: A flips to the back")
      pressed.a = true; frames(s, 1)
      check(s.page == 3, "then A goes to the case page")
      pressed.b = true; frames(s, 1)
      check(s.page == 1, "and B steps back to the front")
    end
    print(("%d harness checks failed"):format(FAILS))
  end, debug.traceback)
  if not ok then print(err) end
  love.event.quit()
end
