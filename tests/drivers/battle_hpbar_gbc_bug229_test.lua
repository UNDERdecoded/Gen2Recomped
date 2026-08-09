-- Regression test for issue #229 ("GSC palette black full health").
--
-- In RED++ ("Gen 2 / GSC-style") COLORS mode the full-health (green-band)
-- in-battle HP bar rendered as a solid black rectangle.  Root cause is in
-- src/render/HudTiles.lua drawHPBar: it pre-tinted the fill with GREENBAR's
-- fill color {0,189,0} (red channel 0), zeroing the red channel of every bar
-- pixel; the battle zone shade-remap shader (PaletteFX.shader, keyed ONLY on
-- the red channel) then mapped every zeroed-red pixel to color 3 = black.
-- Red/orange bands survived because REDBAR {247,0,0} / YELLOWBAR {247,165,0}
-- keep a nonzero red channel.  SGB ('gbc') mode was unaffected because
-- PaletteFX.pack({}) returns nil there, so the fill was already drawn gray.
--
-- Gen1-correct behavior: the DMG hardware bar is one gray shade recolored by
-- the SGB region palette (home/pokemon.asm DrawHPBar + engine/gfx/palettes.asm
-- SetPal_Battle + data/sgb/sgb_packets.asm BlkPacket_Battle), never a per-pixel
-- repaint.  This driver forces RED++, enters a full-HP wild battle, screenshots
-- the intro + action menu, then renders the battle into a clean 160x144 canvas
-- and asserts the player AND enemy HP-bar fill bands are green (not black).
--
-- Run:
--   SHOT_DIR=/tmp/bug229 POKEPORT_IDENTITY=bug229 POKEPORT_TOUCH=0 \
--     POKEPORT_DRIVER=tests/drivers/battle_hpbar_gbc_bug229_test.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "."
  local PaletteFX = require("src.render.PaletteFX")

  -- Set the SAVED option, not just the live mode: Game:applyOptions re-reads
  -- save.options.colors, so a bare setMode would get reverted to the default.
  game.save.options = game.save.options or {}
  game.save.options.colors = "redpp"
  PaletteFX.setMode("redpp")

  -- BULBASAUR :L5 is 19/19 -> full HP -> green band (matches the issue shot).
  local Pokemon = require("src.pokemon.Pokemon")
  game.save.party = { Pokemon.new(game.data, "BULBASAUR", 5) }

  U.teleport(game, "ROUTE_1", 5, 5, "down")
  local ow = game.overworld

  local BattleState = require("src.battle.BattleState")
  local battle = BattleState.newWild(game, "RATTATA", 3) -- full HP -> green
  battle.onFinish = function() end
  ow:pushBattle(battle)

  U.wait(220)
  U.shot(game, DIR .. "/bug229_redpp_intro.png")

  -- Advance the intro text to the action menu deterministically (phase flips
  -- to "menu" at BattleState:1111/1243); stop before a menu tap enters FIGHT.
  for _ = 1, 40 do
    if battle.phase == "menu" then break end
    U.tap(game, "a")
    U.wait(6)
  end
  U.wait(4)
  U.shot(game, DIR .. "/bug229_redpp_menu.png")

  -- Programmatic assertion: render the battle into a clean offscreen 160x144
  -- canvas -- BattleState:draw runs its own SGB zone pass internally, so this
  -- is the real colorized output (verified pixel-identical to the on-screen
  -- capture).  Sample the CENTER fill rows of each bar (an 8px bar tile is
  -- white frame rows / fill rows / white frame rows, so the middle rows are
  -- the fill).  Before the fix the fill is ~ (0,0,0); after the fix it is
  -- ~ (0,0.74,0) (GREENBAR fill {0,189,0}/255).
  if love and love.graphics and love.graphics.newCanvas and battle.phase == "menu" then
    local canvas = love.graphics.newCanvas(160, 144)
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.setColor(1, 1, 1, 1)
    battle:draw()
    love.graphics.setCanvas()
    local id = canvas:newImageData()
    do local dbg = id:encode("png"); local f = io.open(DIR .. "/bug229_offscreen.png", "wb"); if f then f:write(dbg:getString()); f:close() end end

    local function green(r, g, b) return g > 0.4 and g > r and g > b end
    -- returns worst (lowest-green) fill pixel across the center rows sampled
    local function worstFill(x, ys)
      local wr, wg, wb = 1, 1, 1
      for _, y in ipairs(ys) do
        local r, g, b = id:getPixel(x, y)
        if g < wg then wr, wg, wb = r, g, b end
      end
      return wr, wg, wb
    end
    -- player bar: drawHPBar tile (10,9) -> fill x 96..143; fill rows y 74..77
    local pr, pg, pb = worstFill(120, { 75, 76 })
    -- enemy bar: drawHPBar tile (2,2) -> fill x 32..79; fill rows y 18..21
    local er, eg, eb = worstFill(56, { 19, 20 })
    U.log(string.format("player fill rgb = %.2f %.2f %.2f", pr, pg, pb))
    U.log(string.format("enemy  fill rgb = %.2f %.2f %.2f", er, eg, eb))

    if not (green(pr, pg, pb) and green(er, eg, eb)) then
      error(string.format(
        "issue #229: RED++ HP bar fill not green (player %.2f/%.2f/%.2f enemy %.2f/%.2f/%.2f)",
        pr, pg, pb, er, eg, eb))
    end
    U.log("issue #229 PASS: green HP bar fill in RED++")
  else
    error("issue #229 driver: never reached the battle action menu")
  end

  U.wait(4)
end
