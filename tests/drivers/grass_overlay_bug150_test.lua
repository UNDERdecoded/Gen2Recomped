-- Visual + render-decision regression for #150 ("Grass transparency is off").
--
-- The reporter's should_be.png shows Red standing in Route 1 tall grass with a
-- GREEN cap that blends into the grass.  That green is the ROUTE palette's own
-- entry 2 (173,230,90), not an object palette of the character's: overworld
-- OBJs run through rOBP0 = $D0 (home/fade.asm FadePal4 `dc 3,1,0,0`), which
-- lifts OBJ color 1 to DMG shade 0 and color 2 to shade 1, so the cap lands on
-- the very colour the grass beside it uses.  Drawn with an identity shade map
-- the cap landed on shade 2 = light-blue (165,214,255) instead -- the clash
-- #150 reported.  The first fix baked PaletteFX.ogObj() (the Game Boy Color
-- boot ROM's green) onto SGB characters, which is a different machine's answer
-- and became #301 ("people in SGB mode are green"): the Super Game Boy cannot
-- colour an OBJ apart from the BG at all, since pokered never sends OBJ_TRN
-- (data/sgb/sgb_packets.asm defines ATTR_BLK / PAL_SET / PAL_TRN / MLT_REQ /
-- CHR_TRN / PCT_TRN and nothing else).  So SGB bakes the OBP0 ramp
-- (PaletteFX.dmgObj) and lets the zone shader colour the result.
--
-- Gate (fails before the fix, passes after):
--   * PaletteFX.usesSpriteObp("gbc") == false -- SGB owns no object palette
--   * the player SpriteRenderer still bakes a distinct image in SGB mode
--     (resolveImage() ~= the raw grayscale sheet): rOBP0 plus the alpha key
--   * that bake puts the cap (sheet shade 2) on DMG shade 1, which the zone
--     shader then reads out of the map palette as its entry 2 -- ROUTE's grass
--     green, not its light-blue
-- Regression guard (must hold before AND after -- terrain is untouched):
--   * the ROUTE terrain palette still carries BOTH grass green (173,230,90) and
--     light-blue (165,214,255), so the grass field keeps its green+blue dither.
--
-- The SECOND half of #150 is the feet overdraw itself.  Tall grass hides the
-- lower half of whoever stands in it (the GB OBJ-priority trick: an OBJ shows
-- through BG colour 0 and hides under colours 1-3), which the port reproduces
-- by redrawing the cell's bottom tile row over the sprite with shade 0 keyed
-- to alpha.  Every mode but ADVANCED still has DMG white sitting in shade 0 at
-- draw time, so a white test finds it; ADVANCED bakes the real per-tile GBC
-- palette into the atlas first (TileRenderer.getGbcAtlas), which turns the
-- grass tile's shade 0 into its palette's light green -- the white test then
-- never fires and the patch paints an opaque block over the player.  Hence the
-- gap-pixel gate below, run in BOTH modes so the two can't drift apart again.
--
-- Screenshots (SHOT_DIR): grass_bug150_sgb.png (the reported view),
-- grass_bug150_advanced.png (the ADVANCED view) and grass_bug150_ogred.png
-- (OG RED reference -- green character, red terrain).
--
-- Run: POKEPORT_DRIVER=tests/drivers/grass_overlay_bug150_test.lua \
--      POKEPORT_IDENTITY=bug150 POKEPORT_TOUCH=0 love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local PaletteFX = require("src.render.PaletteFX")
  local DIR = os.getenv("SHOT_DIR") or "."

  local fails = 0
  local function check(cond, msg)
    if cond then U.log("ok:   " .. msg)
    else fails = fails + 1; U.log("FAIL: " .. msg) end
  end
  local function hasColor(pal, r, g, b)
    if not pal then return false end
    for i = 1, #pal do
      if pal[i][1] == r and pal[i][2] == g and pal[i][3] == b then return true end
    end
    return false
  end

  -- How many of the 16x8 feet-overdraw pixels let the thing underneath show
  -- through, measured the way the screen does it: render the cell's bottom
  -- tile row over an opaque magenta field and count the magenta survivors.
  -- Mode-agnostic on purpose -- it asks what reached the framebuffer, not
  -- which of the two keying paths (shader or baked alpha) produced it.
  local function grassGapPixels(ow)
    local p = ow.player
    local canvas = love.graphics.newCanvas(16, 8)
    love.graphics.setCanvas(canvas)
    love.graphics.clear(1, 0, 1, 1)
    love.graphics.setColor(1, 1, 1, 1)
    -- camera placed so the cell's bottom tile row lands at the canvas origin
    ow.map.renderer:drawCellBottom(p.cellX, p.cellY, p.cellX * 16, p.cellY * 16 + 8)
    love.graphics.setCanvas()
    local id = canvas:newImageData()
    local n = 0
    for y = 0, 7 do
      for x = 0, 15 do
        local r, g, b = id:getPixel(x, y)
        if r > 0.9 and g < 0.1 and b > 0.9 then n = n + 1 end
      end
    end
    return n
  end

  -- a party + starter flag so the overworld is fully usable
  game.save.flags.EVENT_GOT_STARTER = true
  local Pokemon = require("src.pokemon.Pokemon")
  table.insert(game.save.party, Pokemon.new(game.data, "CHARMANDER", 5))

  -- default SGB color mode.  Set the SAVED option too: Game:applyOptions
  -- re-reads save.options.colors, so a bare setMode() would get reverted.
  game.save.options = game.save.options or {}
  game.save.options.colors = "gbc"
  PaletteFX.setMode("gbc")

  U.teleport(game, "ROUTE_1", 10, 6, "down")
  local ow = game.overworld
  local p = ow.player
  check(ow.map.id == "ROUTE_1", "on ROUTE_1")
  check(ow.map:isGrassCell(p.cellX, p.cellY),
        "player stands on a tall-grass cell (" .. p.cellX .. "," .. p.cellY .. ")")

  U.wait(40) -- let the grass/flower tile animation cycle
  U.shot(game, DIR .. "/grass_bug150_sgb.png")

  -- the feet overdraw is see-through in SGB (the mode the reporter compared
  -- ADVANCED against), so this side of the gate holds before AND after
  local sgbGaps = grassGapPixels(ow)
  check(sgbGaps > 0,
        "SGB grass feet overdraw shows the sprite through its gaps ("
        .. sgbGaps .. "/128 px)")

  -- === render-decision gate: fails before the fix, passes after =========
  check(PaletteFX.usesSpriteObp("gbc") == false,
        "SGB owns no object palette (it cannot colour an OBJ apart from the BG)")

  -- the player's sprite must still resolve to a baked image (not the raw
  -- grayscale sheet) in SGB mode -- that bake is rOBP0 plus the alpha key
  local spr = p.sprite
  check(spr and spr.image and spr:resolveImage() ~= spr.image,
        "player sprite bakes a distinct OBP0 image in SGB mode")

  -- OBP0 (`dc 3,1,0,0`) sends the cap -- sheet shade 2 -- to DMG shade 1, so
  -- the zone shader hands it the map palette's entry 2 rather than the entry 3
  -- light-blue an identity shade map used to pick
  local obp = PaletteFX.dmgObj()
  check(obp and obp[3][1] == 170 and obp[3][2] == 170 and obp[3][3] == 170,
        "OBP0 bake puts sheet shade 2 on DMG shade 1 (170)")
  local cap = PaletteFX.pal(game.data, ow:paletteNameFor(ow.map))
  cap = cap and cap[2]            -- DMG shade 1 -> 2nd palette entry
  check(cap and cap[2] > cap[1] and cap[2] > cap[3],
        "the cap's resolved map colour is green-dominant (g>r and g>b)")
  check(cap and not (cap[1] == 165 and cap[2] == 214 and cap[3] == 255),
        "the cap's resolved map colour is NOT ROUTE light-blue (165,214,255)")

  -- === regression guard: terrain palette untouched =====================
  local terrain = PaletteFX.pal(game.data, ow:paletteNameFor(ow.map))
  check(hasColor(terrain, 173, 230, 90),
        "ROUTE terrain palette still contains grass green (173,230,90)")
  check(hasColor(terrain, 165, 214, 255),
        "ROUTE terrain palette still contains light-blue (grass keeps its blue dither)")

  -- === ADVANCED (RED++): the same overdraw, over a baked true-colour atlas ==
  -- setMode drops every cached Map/TileRenderer and reloads the visible one,
  -- so re-read the state's map before touching its renderer.
  game.save.options.colors = "redpp"
  PaletteFX.setMode("redpp")
  U.wait(20)
  ow = game.overworld
  check(ow.map.renderer.gbcAtlas ~= nil,
        "ADVANCED baked the per-tile GBC atlas for ROUTE_1")
  local advGaps = grassGapPixels(ow)
  check(advGaps > 0,
        "ADVANCED grass feet overdraw shows the sprite through its gaps ("
        .. advGaps .. "/128 px)")
  -- the gaps must be the SAME pixels the other modes key -- a baked-in green
  -- shade 0 is what #150 saw, so the count has to match SGB's exactly
  check(advGaps == sgbGaps,
        "ADVANCED keys the same shade-0 pixels SGB does (" .. advGaps
        .. " vs " .. sgbGaps .. ")")
  U.shot(game, DIR .. "/grass_bug150_advanced.png")

  -- ROUTE_1 is the OVERWORLD tileset; the other two tilesets that own a grass
  -- tile (FOREST $20, PLATEAU $45) file it under the very same pack group 2,
  -- so all three baked the same green over shade 0 and all three broke
  -- together.  One tileset passing proves nothing about the other two.
  for _, spot in ipairs({ { "VIRIDIAN_FOREST", 6, 6, "FOREST" },
                          { "ROUTE_23", 10, 44, "PLATEAU" } }) do
    local id, cx, cy, tsId = spot[1], spot[2], spot[3], spot[4]
    U.teleport(game, id, cx, cy, "down")
    U.wait(10)
    ow = game.overworld
    check(ow.map.tileset.id == tsId
          and ow.map:isGrassCell(ow.player.cellX, ow.player.cellY),
          id .. ": player stands on " .. tsId .. " tall grass")
    check(ow.map.renderer.gbcAtlas ~= nil, id .. ": ADVANCED baked its atlas")
    local gaps = grassGapPixels(ow)
    check(gaps > 0, id .. ": ADVANCED grass feet overdraw shows the sprite "
          .. "through its gaps (" .. gaps .. "/128 px)")
  end

  -- OG RED reference for the human diff (green character over red terrain)
  U.teleport(game, "ROUTE_1", 10, 6, "down")
  game.save.options.colors = "ogred"
  PaletteFX.setMode("ogred")
  U.wait(20)
  U.shot(game, DIR .. "/grass_bug150_ogred.png")
  -- restore the default so the run doesn't end in a non-default mode
  game.save.options.colors = "gbc"
  PaletteFX.setMode("gbc")
  U.wait(2)

  if fails > 0 then error(fails .. " check(s) failed for #150") end
  U.log("all #150 checks passed")
end
