-- Regression test for issue #207 ("Back of sprite only showing outline").
--
-- In the forced-mono display modes (OG / OG INV / CLASSIC) a warm-palette
-- mon's battle pic (e.g. CHARMANDER, SGB palette REDMON) rendered as a bare
-- black outline on white, its two mid shades gone, while cool-palette mons
-- (SQUIRTLE, CYANMON) kept full shading.  Root cause is a double shade-remap:
-- BattleState bakes each pic ONCE with the species' SGB colors, then draws it
-- onto the UI canvas; in these modes BattleState exposes no SGB zones, so
-- Renderer:endFrame invents a whole-screen GRAYS zone (PaletteFX.ensureZones)
-- and runs the ENTIRE colored battle frame through PaletteFX.shader() a SECOND
-- time.  That shader keys the DMG shade off the red channel
-- (r>0.83?c0:r>0.5?c1:r>0.17?c2:c3); REDMON's two mid shades have red 1.0 and
-- 0.839 -- BOTH > 0.83 -- so they collapse into shade 0 (the white paper),
-- leaving only the near-black outline as shade 3.  CYANMON's reds (0.678,
-- 0.451) land in the c1/c2 buckets, which is why blue mons were unaffected.
--
-- Gen1-correct behavior: mon pics are 2bpp 4-shade tiles (gfx/pokemon/back,
-- gfx/pokemon/front); all four shades must be visible, and the same grayscale
-- palette that renders SQUIRTLE renders CHARMANDER.  The fix draws the pics as
-- raw DMG grays in these modes so the whole-screen remap recolors 255->c0,
-- 170->c1, 85->c2, 0->c3 -- all four shades survive.
--
-- This driver forces OG, gives the player a CHARMANDER (the failing warm
-- palette), enters a wild SQUIRTLE battle, and screenshots the exact action
-- menu the reporter shows.  The assertion replays the on-screen two-stage
-- pipeline into a clean 160x144 canvas (BattleState:draw, then the whole-screen
-- GRAYS remap) and asserts the player CHARMANDER back-pic interior contains
-- mid-gray shades (not outline-only), with the enemy SQUIRTLE front interior as
-- an always-passing control.
--
-- Run:
--   SHOT_DIR=/tmp/bug207 POKEPORT_IDENTITY=bug207 POKEPORT_TOUCH=0 \
--     POKEPORT_DRIVER=tests/drivers/battle_mono_sprite_bug207_test.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "."
  local PaletteFX = require("src.render.PaletteFX")

  -- Set the SAVED option, not just the live mode: Game:applyOptions re-reads
  -- save.options.colors, so a bare setMode would get reverted to the default.
  game.save.options = game.save.options or {}
  game.save.options.colors = "og"
  PaletteFX.setMode("og")

  -- CHARMANDER :L5 -- SGB palette REDMON, the warm palette that collapsed.
  local Pokemon = require("src.pokemon.Pokemon")
  game.save.party = { Pokemon.new(game.data, "CHARMANDER", 5) }

  U.teleport(game, "ROUTE_1", 5, 5, "down")
  local ow = game.overworld

  local BattleState = require("src.battle.BattleState")
  local battle = BattleState.newWild(game, "SQUIRTLE", 5)
  battle.onFinish = function() end
  ow:pushBattle(battle)

  U.wait(220)
  U.shot(game, DIR .. "/bug207_og_intro.png")

  -- Advance the intro text to the action menu deterministically (phase flips
  -- to "menu" once "Go! CHARMANDER!" has swapped in the species back pic).
  for _ = 1, 40 do
    if battle.phase == "menu" then break end
    U.tap(game, "a")
    U.wait(6)
  end
  U.wait(4)
  -- The reporter's exact screen: the FIGHT/PKMN/ITEM/RUN action menu with the
  -- player's CHARMANDER back pic fully visible bottom-left.
  U.shot(game, DIR .. "/bug207_og_menu.png")

  if not (love and love.graphics and love.graphics.newCanvas
          and battle.phase == "menu") then
    error("issue #207 driver: never reached the battle action menu")
  end

  -- Replay the on-screen forced-mono pipeline into an offscreen 160x144 canvas.
  -- Stage 1 is BattleState's own colorized frame (its internal SGB zone pass
  -- plus the mon pics drawn via picImage).  Stage 2 is Renderer:endFrame's
  -- whole-screen remap for a state with no SGB zones: ensureZones -> whole(GRAYS),
  -- then blit sends GRAYS through the shade shader over the FULL frame.  This is
  -- pixel-faithful to the presented window (the U.shot captures above), but in
  -- clean 160x144 canvas space so the sample boxes are resolution-independent.
  local g = love.graphics
  local shader = PaletteFX.shader()
  local prev = g.getCanvas()
  local a = g.newCanvas(160, 144)
  local b = g.newCanvas(160, 144)
  g.setCanvas(a)
  g.clear(1, 1, 1, 1)          -- battle letterbox is white (letterboxWhite)
  g.setColor(1, 1, 1, 1)
  battle:draw()
  g.setCanvas(b)
  g.clear(0, 0, 0, 1)
  g.setShader(shader)
  PaletteFX.sendColors(shader, PaletteFX.GRAYS)
  g.setColor(1, 1, 1, 1)
  g.draw(a, 0, 0)
  g.setShader()
  g.setCanvas(prev)
  local id = b:newImageData()
  do
    local png = id:encode("png")
    local f = io.open(DIR .. "/bug207_og_offscreen.png", "wb")
    if f then f:write(png:getString()); f:close() end
  end

  -- Count mid-gray pixels in a box.  The forced-mono frame is neutral gray:
  -- shade 0 = white (~1.0), shade 3 = black (~0.0), and the two MID shades are
  -- ltgray (170/255 = 0.667) and dkgray (85/255 = 0.333).  A mid shade exists
  -- only when all four DMG shades survived the remap; an outline-only pic has
  -- pure white + pure black and zero mid pixels.
  local function midCount(x0, y0, x1, y1)
    local n = 0
    for y = y0, y1 do
      for x = x0, x1 do
        local r = id:getPixel(x, y)
        if r > 0.18 and r < 0.82 then n = n + 1 end
      end
    end
    return n
  end

  -- Player CHARMANDER back pic: hlcoord 1,5 (x=8), feet at y=96 -- interior
  -- box well inside the body, clear of the white matte and the near-black
  -- outline, and clear of the bottom-right HUD/HP bar.
  local backMid = midCount(12, 50, 52, 92)
  -- Enemy SQUIRTLE front pic: 7x7 slot at hlcoord 12,0 (x~96) -- control that
  -- always keeps its mid shades (CYANMON reds land in the c1/c2 buckets).
  local enemyMid = midCount(104, 8, 148, 48)
  U.log(string.format("player back mid-gray px = %d ; enemy front mid-gray px = %d",
                      backMid, enemyMid))

  if enemyMid <= 20 then
    error(string.format(
      "issue #207 driver: control failed -- enemy SQUIRTLE front has no "
      .. "mid-gray (%d); sample box or pipeline is wrong", enemyMid))
  end
  if backMid <= 20 then
    error(string.format(
      "issue #207: OG-mode CHARMANDER back pic is outline-only -- interior "
      .. "has %d mid-gray px (expected the full 4-shade grayscale, like the "
      .. "enemy front's %d)", backMid, enemyMid))
  end
  U.log(string.format(
    "issue #207 PASS: OG-mode CHARMANDER back keeps its mid shades "
    .. "(%d mid-gray px, control enemy %d)", backMid, enemyMid))

  U.wait(4)
end
