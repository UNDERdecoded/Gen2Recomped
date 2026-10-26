-- Opt-in real-renderer test; needs the selected game's exact local import.
-- POKEPORT_DRIVER=tests/gen3_summary_capture.lua QA_SUMMARY_OUT=<existing dir>
-- QA_EXPECT_SUMMARY=1 enables candidate assertions; omit for the base capture.
local function wait(n)
  for _ = 1, n do
    coroutine.yield()
  end
end
return function(game)
  local ok, err = xpcall(function()
    if love.setDeprecationOutput then
      love.setDeprecationOutput(false)
    end
    local version = require("src.core.GameVersion").get()
    assert(version == "emerald" or version == "firered")
    local expected = os.getenv("QA_EXPECT_SUMMARY") == "1"
    local out = assert(os.getenv("QA_SUMMARY_OUT"))
    local Codec = require("src.core.SaveSerializer")
    local Menu = require("src.ui.Gen3SummaryMenu")
    local rec = game.data.constants.gen3Summary
    if expected then
      assert(Menu.__summaryPresentation and rec.parts and rec.words)
      if version == "emerald" then
        assert(rec.typeBadges.count == 23 and rec.words.switch and rec.words.cancel)
        local f = assert(io.open(out .. "/emerald-palette.json", "w"))
        f:write(
          require("src.link.Json").encode({
            panel = rec.parts.palette[15],
            header = rec.parts.palette[72],
            border = rec.parts.palette[71],
          })
        )
        f:close()
      else
        assert(
          rec.words.PageCancel:find("{DPAD_RIGHT}", 1, true)
            and rec.words.PageDetail:find("{A_BUTTON}", 1, true)
        )
      end
    end
    math.randomseed(12345)
    love.math.setRandomSeed(12345)
    while game.stack:top() do
      game.stack:pop()
    end
    game.stack:push(
      require("src.world.OverworldController"),
      game.save.player.map,
      game.save.player.x,
      game.save.player.y,
      "down"
    )
    wait(4)
    local mon = require("src.pokemon.Pokemon").new(game.data, "BULBASAUR", 15)
    mon.nickname = "BULBASAUR"
    mon.ot = "TEST"
    mon.otId = 12345
    mon.moves = {
      { id = "TACKLE", pp = 35 },
      { id = "GROWL", pp = 10 },
      { id = "LEECH_SEED", pp = 2 },
      {
        id = "SLEEP_POWDER",
        pp = 0,
      },
    }
    game.save.party = { mon }
    game.save.player.name = "TEST"
    local function snapshot(label, screen)
      local pushed = game.stack:top() ~= screen
      if pushed then
        game.stack:push(screen)
      end
      wait(4)
      -- Check one synchronous draw for save immutability, with graphics restored.
      local frames = {}
      local originalDraw = love.graphics.draw
      local sheet = expected
        and version == "emerald"
        and rec.typeBadges
        and require("src.render.Assets").image(rec.typeBadges.image)
      if sheet and (label == "page-3" or label == "page-4") then
        love.graphics.draw = function(image, quad, ...)
          if image == sheet then
            local _, y = quad:getViewport()
            frames[#frames + 1] = y / 16
            assert(label ~= "page-4" or y >= 18 * 16, "Contest row used a battle badge")
          end
          return originalDraw(image, quad, ...)
        end
      end
      local saved = Codec.encode(game.save)
      local canvas = love.graphics.newCanvas(240, 160, { dpiscale = 1 })
      love.graphics.push("all")
      love.graphics.setCanvas(canvas)
      love.graphics.origin()
      love.graphics.setScissor()
      love.graphics.setShader()
      screen:draw()
      love.graphics.draw = originalDraw
      if sheet and (label == "page-3" or label == "page-4") then
        assert(#frames == 4, "Summary rows lost their type/category sprites")
        print("SUMMARY_BADGE_FRAMES", version, label, table.concat(frames, ","))
      end
      love.graphics.pop()
      canvas:release()
      assert(saved == Codec.encode(game.save), "Drawing changed the save: " .. label)
      local done = false
      love.graphics.captureScreenshot(function(frame)
        local path = out .. "/" .. version .. "-" .. label .. ".png"
        local f = assert(io.open(path, "wb"))
        f:write(frame:encode("png"):getString())
        f:close()
        done = true
      end)
      while not done do
        wait(1)
      end
      if pushed then
        game.stack:pop()
      end
      print("SUMMARY_CAPTURE", version, label)
    end
    local s = Menu.new(game, { mon = mon })
    for page = 1, (version == "emerald" and 4 or 3) do
      s.page = page
      snapshot("page-" .. page, s)
    end
    local function press(key)
      game:keypressed(key)
      wait(1)
      game:keyreleased(key)
      wait(2)
    end
    local world = game.stack:top()
    local slots = mon.moves
    local before = Codec.encode(slots)
    s = Menu.new(game, { mon = mon })
    s.page = 3
    game.stack:push(s)
    wait(3)
    press("z")
    assert(s.moveSelect)
    press("down")
    assert(s.moveIndex == 2)
    snapshot("detail-second", s)
    press("x")
    assert(not s.moveSelect)
    press("x")
    assert(game.stack:top() == world)
    local answers, value = 0, "pending"
    s = Menu.new(game, {
      mon = mon,
      choose = {
        move = "VINE_WHIP",
        onChoose = function(i)
          answers = answers + 1
          value = i
        end,
      },
    })
    game.stack:push(s)
    wait(3)
    for _ = 1, 4 do
      press("down")
    end
    assert(s.moveIndex == 5)
    snapshot("learn-fifth", s)
    press("x")
    assert(answers == 1 and value == nil and game.stack:top() == world)
    assert(
      mon.moves == slots and Codec.encode(slots) == before,
      "Navigation changed move slots or PP"
    )
    print(
      "GEN3_SUMMARY_CAPTURE_OK",
      version,
      expected and "candidate" or "base",
      "native details/fifth-row/cancel and draw immutability"
    )
  end, debug.traceback)
  if not ok then
    print("GEN3_SUMMARY_CAPTURE_FAILED", err)
  end
  love.event.quit(ok and 0 or 1)
end
