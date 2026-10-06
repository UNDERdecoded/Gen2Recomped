-- tools/gen4_contest_dance_harness/main.lua
--
-- THE SUPER CONTEST SCREEN, RENDERED: builds a Normal-rank Cool contest for a
-- Pikachu, dances the Dance round (copying every lead) into contest_dance.png
-- (LOVE save directory for `bt_gen4`), printing the scores.
--
--   POKEPORT_DATA_DIR=<platinum cache>/data/generated \
--   POKEPORT_ASSET_ROOT=<platinum cache> love tools/gen4_contest_dance_harness

function love.load()
  local ok, err = xpcall(function()
    require("src.core.GameVersion").set("platinum")
    -- POKEPORT_ASSET_ROOT: the launcher mounts the cache's `assets/`; this
    -- harness has no launcher, so read the pictures (contest art, fonts,
    -- sprites) straight from that folder, as the battle harness does.
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
    local C = require("src.pokemon.Gen4Contest")
    local pressed = {}
    local game = { data = Data, input = { wasPressed = function(_, k) local v = pressed[k]; pressed[k] = nil; return v end },
      stack = { pop = function() end } }
    local topFn
    package.loaded["src.ui.SecondScreen"] = { mode = function() return "display" end,
      stowed = function() return false end, draw = function(_, fn) topFn = fn end }
    local c = C.new({ data = Data, rank = tonumber(os.getenv("RANK") or "0"), type = tonumber(os.getenv("TYPE") or "0"),
      competition = C.OFFICIAL, seed = 7,
      mon = { species = 25, nickname = "PIKACHU", contest = { cool = 60 } }, playerName = "LUCAS", partySlot = 0 })
    local done = false
    local ui = require("src.ui.Gen4ContestDance").new(game, c, { onDone = function() done = true end })
    pressed.a = true
    local pages, labels = {}, {}
    local function snap(label)
      for _, which in ipairs({ "top", "pad" }) do
        local cv = love.graphics.newCanvas(256, 192)
        love.graphics.setCanvas(cv)
        love.graphics.clear(0, 0, 0, 1)
        topFn = nil
        ui:draw()
        if which == "pad" then love.graphics.clear(0, 0, 0, 1); if topFn then topFn() end end
        love.graphics.setCanvas()
        pages[#pages + 1], labels[#labels + 1] = cv, label .. " " .. which
      end
    end
    local KEY = { "up", "down", "left", "right" }
    local D = require("src.pokemon.Gen4ContestDance")
    local shots = {}
    for r = 0, 3 do
      local s = D.measureStart(ui.d, r, 0)
      shots[math.floor(s - 20)] = "r" .. r .. " pre"
      shots[math.floor(s + ui.d.half - 6)] = "r" .. r .. " lead"
      shots[math.floor(s + ui.d.measure - 20)] = "r" .. r .. " copy"
      if r == 3 then shots[math.floor(s) + 32] = "r3 press" end
    end
    for f = 1, 30000 do
      local ms = ui.ms
      if ui.mode == "dance" and ms then
        local t = ui.frame + 1 - ms.start
        if ms.lead ~= 0 then
          for _, l in ipairs(ms.leadMoves) do
            if math.floor((l.grid + ui.d.steps) * ui.d.hs) == math.floor(t) then pressed[KEY[l.dir]] = true end
          end
        elseif t == 30 or t == 60 or t == 90 then pressed[KEY[math.floor(t / 30)]] = true end
      end
      if ui.mode == "intro" then pressed.a = true end
      ui:update(1 / 60)
      if shots[ui.frame] and ui.mode == "dance" then snap(shots[ui.frame]); shots[ui.frame] = nil end
      if ui.mode == "end" and ui.message and ui.message ~= ui.lastSnap then ui.lastSnap = ui.message; snap("end"); pressed.a = true end
      if done then break end
    end
    print("scores", c.scores[0].dance, c.scores[1].dance, c.scores[2].dance, c.scores[3].dance, "done", done)
    local cols = 6
    local sheet = love.graphics.newCanvas(cols * 260, math.ceil(#pages / cols) * 206)
    love.graphics.setCanvas(sheet)
    love.graphics.clear(0.1, 0.1, 0.1, 1)
    for i, p in ipairs(pages) do
      local x, y = ((i - 1) % cols) * 260, math.floor((i - 1) / cols) * 206
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(p, x, y)
      love.graphics.print(labels[i], x + 2, y + 192)
    end
    love.graphics.setCanvas()
    sheet:newImageData():encode("png", "contest_dance.png")
    print("saved to " .. love.filesystem.getSaveDirectory())
  end, debug.traceback)
  if not ok then print(err) end
  love.event.quit()
end
