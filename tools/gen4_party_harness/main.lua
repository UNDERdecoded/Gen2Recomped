-- tools/gen4_party_harness/main.lua
--
-- PLATINUM'S PARTY SCREEN, RENDERED in the states that matter, into
-- party.png (LOVE save directory): cursor on the lead, cursor on a fainted
-- member, the submenu open (with field moves), the item submenu, switching,
-- CANCEL selected, a TM being taught, a short party (empty slots), a cache
-- without the party art (the fallbacks) and the bottom screen.  The party carries a full-HP lead holding an item, a
-- partial-HP member holding mail, a paralysed one, a fainted one, an egg and
-- a red-HP one.
--
--   POKEPORT_DATA_DIR=<platinum cache>/data/generated \
--   POKEPORT_ASSET_ROOT=<platinum cache> love tools/gen4_party_harness
--
-- (run from the repository root).  The cache needs `gen4_party_art` (see
-- tools/gen4_art_extract `party`); the party screen's newer words are taken
-- from the cache's gen4_text bank 453 when its gen4_menus predates them.

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

    -- the words a re-imported cache carries (Gen4Menus.PARTY_TEXT), from the
    -- cache's own text banks when its gen4_menus is older than them
    local dir = os.getenv("POKEPORT_DATA_DIR")
    local words = (((Data.gen4_menus or {}).partyMenu or {}).text) or {}
    local okT, text = pcall(dofile, dir and (dir .. "/gen4_text.lua") or "")
    local bank = okT and type(text) == "table" and text[453]
    if bank then
      for key, index in pairs(require("src.import.Gen4Menus").PARTY_TEXT) do
        if words[key] == nil and bank[index] then words[key] = bank[index] end
      end
    end
    Data.gen4_menus = Data.gen4_menus or {}
    Data.gen4_menus.partyMenu = Data.gen4_menus.partyMenu or {}
    Data.gen4_menus.partyMenu.text = words

    local bottomFn
    package.loaded["src.ui.SecondScreen"] = { mode = function() return "display" end,
      stowed = function() return false end, draw = function(_, fn) bottomFn = fn end }

    local function mon(species, level, hp, max, extra)
      local m = { species = species, level = level, hp = hp, stats = { hp = max }, maxHp = max,
                  moves = { { id = 33 } }, gender = "male", personality = 0 }
      for k, v in pairs(extra or {}) do m[k] = v end
      return m
    end
    local itemId, mailId
    for id, rec in pairs(Data.items or {}) do
      if type(rec) == "table" then
        if not mailId and rec.pocket == "MAIL" then mailId = id end
        if not itemId and rec.pocket == "ITEMS" and id ~= 0 then itemId = id end
      end
    end
    local function fullParty()
      return {
        mon(392, 42, 120, 120, { item = itemId, moves = { { id = 57 }, { id = 15 }, { id = 33 }, { id = 91 } } }),
        mon(395, 38, 50, 110, { item = mailId }),
        mon(25, 30, 70, 70, { status = "PAR" }),
        mon(133, 25, 0, 60),
        mon(175, 1, 10, 10, { isEgg = true, egg = true, nickname = "EGG" }),
        mon(54, 22, 6, 64, { status = nil }),
      }
    end
    local function makeGame(party)
      return { data = Data, save = { party = party, options = {}, inventory = {}, badges = {} },
        input = { wasPressed = function() return false end, isDown = function() return false end },
        stack = { pop = function() end, push = function() end } }
    end
    local Party = require("src.ui.Gen4PartyMenu")

    local scenes = {
      { "lead", function(s) s.index = 1 end },
      { "fainted", function(s) s.index = 4 end },
      { "submenu", function(s) s.index = 1; s.submenu = 2 end },
      { "item submenu", function(s) s.index = 2; s.itemMenu = true; s.submenu = 1 end },
      { "switching", function(s) s.switchFrom = 1; s.index = 3 end },
      { "cancel", function(s) s.index = #s:party() + 1 end },
      { "teach", function(s) s.index = 2; s.tmhm = { move = 15, kind = "HM" } end },
      { "short party", function(s) s.index = 2 end, function(p) return { p[1], p[2], p[3], p[4] } end },
      -- an older cache: no gen4_party_art, so every fallback is drawn
      { "no party art", function(s) s.index = 2; s.partyArt = {} end },
    }
    local pages = {}
    for k, sc in ipairs(scenes) do
      local party = fullParty()
      if sc[3] then party = sc[3](party) end
      local screen = Party.new(makeGame(party), {})
      screen.t = 0
      sc[2](screen)
      local cv = love.graphics.newCanvas(256, 192)
      love.graphics.setCanvas(cv)
      love.graphics.clear(0, 0, 0, 1)
      bottomFn = nil
      screen:draw()
      love.graphics.setCanvas()
      pages[#pages + 1] = cv
      if k == 1 and bottomFn then
        local b = love.graphics.newCanvas(256, 192)
        love.graphics.setCanvas(b)
        love.graphics.clear(0, 0, 0, 1)
        bottomFn()
        love.graphics.setCanvas()
        pages[#pages + 1] = b
      end
      print(sc[1], table.concat(screen:actions(), ","))
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
    sheet:newImageData():encode("png", "party.png")
    print("saved to " .. love.filesystem.getSaveDirectory())
  end, debug.traceback)
  if not ok then print(err) end
  love.event.quit()
end
