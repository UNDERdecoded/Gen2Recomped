-- Driver: eyeball the party screen's colors (#274, absorbing #272).  pokered
-- SetPal_PartyMenu (engine/gfx/palettes.asm:90) sends a four-palette block
-- packet: MEWMON over the icon column, GREENBAR elsewhere, and one block per
-- HP-bar row from GetHealthBarColor (palettes.asm:293-325).
--   POKEPORT_DRIVER=tests/drivers/party_hp_palette_bug274_test.lua \
--     POKEPORT_IDENTITY=bug274 SHOT_DIR=/tmp/shots love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local PaletteFX = require("src.render.PaletteFX")
  local PartyMenu = require("src.ui.PartyMenu")
  local Pokemon = require("src.pokemon.Pokemon")
  local Screens = require("src.ui.Screens")
  local Strings = require("src.core.Strings")

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- Set the SAVED option, not just the live mode: Game:applyOptions re-reads
  -- save.options.colors, so a bare setMode gets reverted.
  game.save.options = game.save.options or {}
  game.save.options.colors = "redpp"
  PaletteFX.setMode("redpp")
  check("COLORS is ADVANCED (the mode #274 was reported in)",
        PaletteFX.mode == "redpp" and PaletteFX.modeLabel() == "ADVANCED")

  -- A 48/48 bar is one pixel per HP, so GetHealthBarColor's 27 / 10 pixel
  -- thresholds land on plain numbers.
  local ROWS = {
    { species = "BULBASAUR", hp = 48, pal = "GREENBAR", fill = true },
    { species = "PIDGEY",    hp = 26, pal = "YELLOWBAR", fill = true },
    { species = "RATTATA",   hp = 9,  pal = "REDBAR", fill = true },
    { species = "CATERPIE",  hp = 0,  pal = "REDBAR", fill = false },
  }

  -- ---- preconditions the eye cannot check --------------------------------
  -- A missing palette name, an absent shader or a stale zone rect all read as
  -- "the colors look wrong", exactly like the bug did.
  local function pal(name) return PaletteFX.pal(game.data, name) end
  local function rgb(c)
    return c and ("{" .. c[1] .. "," .. c[2] .. "," .. c[3] .. "}") or "nil"
  end

  local mew = pal("MEWMON")
  local green = pal("GREENBAR")
  check("MEWMON and the three bar palettes all resolve",
        mew ~= nil and green ~= nil and pal("YELLOWBAR") ~= nil
        and pal("REDBAR") ~= nil)
  -- the exact purple the reporter's screenshot was full of
  check("MEWMON color 2 is the reported purple {115,33,165}",
        mew ~= nil and mew[3][1] == 115 and mew[3][2] == 33 and mew[3][3] == 165)
  U.log("  MEWMON   :", rgb(mew and mew[1]), rgb(mew and mew[2]),
        rgb(mew and mew[3]), rgb(mew and mew[4]))
  for _, n in ipairs({ "GREENBAR", "YELLOWBAR", "REDBAR" }) do
    local c = pal(n)
    U.log(("  %-9s fill color 2: %s"):format(n, rgb(c and c[3])))
  end
  -- the base zone swapped from MEWMON to GREENBAR, which stays invisible only
  -- because the two agree on paper and ink: the nicknames, level line, HP
  -- numbers, box border and cursor are all color 3 on color 0
  check("MEWMON and GREENBAR share color 0 and color 3 (text/box unchanged)",
        mew ~= nil and green ~= nil
        and mew[1][1] == green[1][1] and mew[1][2] == green[1][2]
        and mew[1][3] == green[1][3]
        and mew[4][1] == green[4][1] and mew[4][2] == green[4][2]
        and mew[4][3] == green[4][3])
  -- with no shade-remap shader nothing colorizes the canvas and the pixel
  -- counts below are meaningless
  check("the SGB shade-remap shader compiled", PaletteFX.shader() ~= nil)

  for _, row in ipairs(ROWS) do
    check(row.species .. " is a known species",
          game.data.pokemon[row.species] ~= nil)
    check(("%d/48 HP is a %s bar"):format(row.hp, row.pal),
          PaletteFX.barPalName(row.hp, 48) == row.pal)
  end

  -- ---- park the player, then open the party list yourself -----------------
  -- pokered data/maps/objects/PalletTown.asm: (10, 12) carries no warp_event,
  -- bg_event or object_event.  Any open cell would do; the fallback below
  -- finds one if a map edit ever closes this one.
  local party = {}
  for i, row in ipairs(ROWS) do
    local mon = Pokemon.new(game.data, row.species, 20)
    mon.stats.hp = 48
    mon.hp = row.hp
    party[i] = mon
  end
  game.save.party = party
  game.save.player.name = game.save.player.name or "RED"

  U.teleport(game, "PALLET_TOWN", 10, 12, "down")
  U.wait(10)
  local ow = game.overworld
  if ow and ow.map and not ow.map:isWalkableCell(10, 12) then
    local fx, fy
    for y = 1, 16 do
      for x = 1, 18 do
        if not fx and ow.map:isWalkableCell(x, y) and not ow:npcAtCell(x, y) then
          fx, fy = x, y
        end
      end
    end
    if fx then
      U.log("(10, 12) is blocked now; standing on", fx, fy)
      U.teleport(game, "PALLET_TOWN", fx, fy, "down")
      U.wait(10)
    end
  end

  -- START -> POKéMON -> A, walked rather than pushed, so a broken start menu
  -- shows up here instead of masquerading as a palette bug
  U.tap(game, "start")
  U.wait(12)
  local menu = game.stack:top()
  local target = 1
  if menu and menu.items then
    local want = Strings("POKéMON")
    for i, it in ipairs(menu.items) do
      if it.label == want then target = i break end
    end
    check("START menu lists POKéMON", menu.items[target] ~= nil
          and menu.items[target].label == want)
    for _ = 2, target do
      U.tap(game, "down")
      U.wait(4)
    end
  else
    check("START opened the start menu", false)
  end
  U.tap(game, "a")
  U.wait(16)

  local pm = game.stack:top()
  if getmetatable(pm) ~= PartyMenu then
    U.log("start-menu walk did not land on the party list; pushing it directly")
    Screens.push(game, "PartyMenu", {})
    U.wait(12)
    pm = game.stack:top()
  end
  check("the party list is open", getmetatable(pm) == PartyMenu)

  -- ---- the block packet this screen asks for ------------------------------
  local zones = getmetatable(pm) == PartyMenu and pm:sgbPalettes(game) or nil
  check("sgbPalettes returns base + icon column + one block per bar row",
        type(zones) == "table" and #zones == 2 + #ROWS)
  zones = zones or {}
  check("the base zone is GREENBAR over the whole screen",
        zones[1] ~= nil and zones[1].colors == green and zones[1].x == 0
        and zones[1].y == 0 and zones[1].w == 160 and zones[1].h == 144)
  check("the icon column is a MEWMON block at tiles 1-2, rows 0-11",
        zones[2] ~= nil and zones[2].colors == mew and zones[2].x == 8
        and zones[2].y == 0 and zones[2].w == 16 and zones[2].h == 96)
  for i, row in ipairs(ROWS) do
    local z = zones[2 + i]
    check(("row %d (%d/48 HP) carries the %s block palette")
            :format(i, row.hp, row.pal),
          z ~= nil and z.colors == pal(row.pal))
    check(("row %d's block covers the bar's cap + six fill tiles"):format(i),
          z ~= nil and z.x == 48 and z.w == 56 and z.y == (i * 2 - 1) * 8
          and z.h == 8)
  end

  -- ---- what the screen actually holds -------------------------------------
  -- Render the live menu into a clean 160x144 canvas and run the same zone
  -- pass Renderer:endFrame does (shade-remap shader, sendColors per zone,
  -- scissor to its rect, redraw), at scale 1 so a pixel is a pixel.
  local function colorized()
    local raw = love.graphics.newCanvas(160, 144)
    love.graphics.setCanvas(raw)
    love.graphics.clear(1, 1, 1, 1)
    love.graphics.setColor(1, 1, 1, 1)
    pm:draw()
    love.graphics.setCanvas()

    local out = love.graphics.newCanvas(160, 144)
    local shader = PaletteFX.shader()
    love.graphics.setCanvas(out)
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.setColor(1, 1, 1, 1)
    if shader then love.graphics.setShader(shader) end
    for _, z in ipairs(pm:sgbPalettes(game) or {}) do
      if shader and z.colors then PaletteFX.sendColors(shader, z.colors) end
      love.graphics.setScissor(z.x, z.y, z.w, z.h)
      love.graphics.draw(raw, 0, 0)
    end
    love.graphics.setScissor()
    love.graphics.setShader()
    love.graphics.setCanvas()
    love.graphics.setColor(1, 1, 1, 1)
    return out:newImageData()
  end

  -- count pixels in a rect that match a palette color (the zone pass writes
  -- palette colors exactly, so the tolerance only absorbs 8-bit rounding)
  local function countColor(id, c, x0, y0, x1, y1)
    if not c then return -1 end
    local want = { c[1] / 255, c[2] / 255, c[3] / 255 }
    local n = 0
    for y = y0, y1 do
      for x = x0, x1 do
        local r, g, b = id:getPixel(x, y)
        if math.abs(r - want[1]) < 0.02 and math.abs(g - want[2]) < 0.02
           and math.abs(b - want[3]) < 0.02 then
          n = n + 1
        end
      end
    end
    return n
  end

  if getmetatable(pm) == PartyMenu and love.graphics.newCanvas
     and PaletteFX.shader() then
    local id = colorized()

    -- (a) the icons: OBP0 "3100" means an object never displays shade 2, so
    -- MEWMON's third color must appear nowhere on the screen at all
    local purple = countColor(id, mew and mew[3], 0, 0, 159, 143)
    U.log("  MEWMON color-2 (purple) pixels on the whole screen:", purple)
    check("no purple anywhere -- the icons never show shade 2", purple == 0)
    -- and the icons are there at all: MEWMON color 1 is the warm orange they
    -- read as after the OBP bake
    local flesh = countColor(id, mew and mew[2], 8, 0, 23, 95)
    U.log("  MEWMON color-1 (orange) pixels in the icon column:", flesh)
    check("the icon column is drawn (not blank)", flesh > 0)

    -- (b) the bars: each row's fill must be ITS OWN bar color and none of the
    -- other two.  Fill tiles run x 56..103 (drawHPBar at tile 5: "HP" 40,
    -- ":[" 48, six fill tiles 56..103, cap 104).
    for i, row in ipairs(ROWS) do
      local y0 = (i * 2 - 1) * 8
      local own = pal(row.pal)
      -- the three bar palettes share color 0/1/3; only color 2, the fill
      -- shade, tells them apart
      local mine = countColor(id, own and own[3], 56, y0, 103, y0 + 7)
      U.log(("  row %d (%d/48 HP) %s fill pixels: %d")
              :format(i, row.hp, row.pal, mine))
      if row.fill then
        check(("row %d's bar is filled with %s"):format(i, row.pal), mine > 0)
      end
      for _, other in ipairs({ "GREENBAR", "YELLOWBAR", "REDBAR" }) do
        if other ~= row.pal then
          local c = pal(other)
          local n = countColor(id, c and c[3], 56, y0, 103, y0 + 7)
          check(("row %d's bar carries no %s"):format(i, other), n == 0)
        end
      end
    end
  end

  -- ---- screenshots ---------------------------------------------------------
  U.wait(4)
  if U.shot(game, DIR .. "/bug274_party_advanced.png") then
    U.log("captured", DIR .. "/bug274_party_advanced.png")
  end
  -- the same screen in SGB: the block packet changed for every mode, not just
  -- ADVANCED
  game.save.options.colors = "gbc"
  PaletteFX.setMode("gbc")
  U.wait(10)
  if U.shot(game, DIR .. "/bug274_party_sgb.png") then
    U.log("captured", DIR .. "/bug274_party_sgb.png")
  end
  game.save.options.colors = "redpp"
  PaletteFX.setMode("redpp")
  U.wait(10)

  -- ---- hand off -----------------------------------------------------------
  U.log("The party list is open in COLORS = ADVANCED: BULBASAUR 48/48, PIDGEY")
  U.log("26/48, RATTATA 9/48, CATERPIE 0/48.  Three different bar colors run")
  U.log("down the screen (green, yellow, red) and the icons carry no purple.")
  U.log("#274 was every bar solid black at full health and purple-blotched icons.")
  U.log("OPTION -> COLORS cycles modes; OG and CLASSIC are mono by design.")
  U.log("Captures: bug274_party_advanced.png and bug274_party_sgb.png in " .. DIR)

  while true do
    coroutine.yield()
  end
end
