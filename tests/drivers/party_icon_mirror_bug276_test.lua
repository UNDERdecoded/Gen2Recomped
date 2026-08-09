-- Driver: eyeball the party icons after the OAM mirror landed (#276, #238).
-- pokered engine/gfx/mon_icons.asm:234-251 sends every class but ICON_HELIX
-- through WriteSymmetricMonPartySpriteOAM (engine/items/town_map.asm:494-534),
-- which writes each tile twice, attributes 0 then OAM_XFLIP, so the frame's
-- right column never reaches the screen.  Geometry: parity_party_icon_mirror.
--   POKEPORT_DRIVER=tests/drivers/party_icon_mirror_bug276_test.lua POKEPORT_IDENTITY=bug276 SHOT_DIR=/tmp/shots love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Assets = require("src.render.Assets")
  local PartyMenu = require("src.ui.PartyMenu")
  local Pokemon = require("src.pokemon.Pokemon")
  local Screens = require("src.ui.Screens")
  local Strings = require("src.core.Strings")

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- One mon per icon class, in party order.  `asym` is which of the two
  -- frames carries the asymmetric art (measured below, not assumed): that
  -- decides when the icon is worth looking at, since AnimatePartyMon only
  -- animates the icon under the cursor.
  local ROWS = {
    { species = "CHARMANDER", icon = "MON",       asym = "rest" },
    { species = "PIKACHU",    icon = "FAIRY",     asym = "rest" },
    { species = "SPEAROW",    icon = "BIRD",      asym = "alt" },
    { species = "OMANYTE",    icon = "HELIX",     asym = "whole" },
    { species = "WEEDLE",     icon = "BUG",       asym = "none" },
    { species = "RATTATA",    icon = "QUADRUPED", asym = "none" },
  }

  -- ---- preconditions the eye cannot check --------------------------------
  -- A wrong icon class, a sheet that fails to load and a missing mirrorsIcon
  -- all end in "the icons look odd", same as the bug did.
  local icons = game.data.icons
  check("data.icons carries the icon registry",
        icons ~= nil and icons.icons ~= nil and icons.byDex ~= nil)

  check("PartyMenu.mirrorsIcon is exported",
        type(PartyMenu.mirrorsIcon) == "function")
  local mirrors = type(PartyMenu.mirrorsIcon) == "function"
                  and PartyMenu.mirrorsIcon or function() return nil end
  -- data/pokemon/menu_icons.asm gives ICON_HELIX to Shellder/Cloyster,
  -- Staryu/Starmie and the Omanyte/Kabuto lines, and to nothing else
  check("HELIX is the one class that keeps the whole frame",
        mirrors("HELIX") == false and mirrors("MON") == true)
  check("mod-supplied icon art (no built-in name) still draws whole",
        mirrors(nil) == false)

  -- how many mirrored pixel PAIRS of a 16x16 frame disagree in the source
  -- art; 0 means the mirror is a pixel-for-pixel no-op for that frame
  local function frameAsymmetry(path, frame)
    local ok, id = pcall(Assets.imageData, path)
    if not (ok and id) then return nil end
    local h = id:getHeight()
    if (frame + 1) * 16 > h then return nil end
    local n = 0
    for dy = 0, 15 do
      for dx = 0, 7 do
        local r1, g1, b1, a1 = id:getPixel(dx, frame * 16 + dy)
        local r2, g2, b2, a2 = id:getPixel(15 - dx, frame * 16 + dy)
        if r1 ~= r2 or g1 ~= g2 or b1 ~= b2 or a1 ~= a2 then n = n + 1 end
      end
    end
    return n
  end

  for _, row in ipairs(ROWS) do
    local def = game.data.pokemon[row.species]
    local name = def and def.dex and icons.byDex[def.dex]
    check(row.species .. " uses the " .. row.icon .. " icon", name == row.icon)
    local path = name and icons.icons[name]
    check(row.icon .. " resolves a sheet path",
          type(path) == "string" and path ~= "")
    row.path = path
    if path then
      local rest = PartyMenu.frameFor(name, false, 96)
      local alt = PartyMenu.frameFor(name, true, 96)
      local ar = frameAsymmetry(path, rest)
      local aa = (row.icon ~= "HELIX" and row.icon ~= "BALL")
                 and frameAsymmetry(path, alt) or nil
      check(row.icon .. " sheet art loads", ar ~= nil)
      U.log(("  %-9s rest frame %d: %s   animated frame %s: %s")
              :format(row.icon, rest,
                      ar and (ar .. " mirrored pixel pairs differ") or "?",
                      aa and tostring(alt) or "-",
                      aa and (aa .. " differ") or "-"))
      if row.asym == "rest" then
        check(row.icon .. " rest frame really is asymmetric art",
              (ar or 0) > 0)
      elseif row.asym == "alt" then
        check(row.icon .. " animated frame really is asymmetric art",
              (aa or 0) > 0)
        check(row.icon .. " rest frame was already symmetric", ar == 0)
      elseif row.asym == "none" then
        check(row.icon .. " is untouched by the mirror (both frames symmetric)",
              ar == 0 and aa == 0)
      end
    end
  end

  -- ---- park the player, then open the party list -------------------------
  -- (10,12) in PALLET_TOWN carries no warp/bg/object event; any open cell
  -- would do, and the fallback below finds one if a map edit closes it.
  local party = {}
  for i, row in ipairs(ROWS) do
    party[i] = Pokemon.new(game.data, row.species, 20 + i)
  end
  game.save.party = party
  game.save.player.name = game.save.player.name or "RED"

  U.teleport(game, "PALLET_TOWN", 10, 12, "down")
  U.wait(10)
  local ow = game.overworld
  if ow and ow.map and not ow.map:isWalkableCell(10, 12) then
    -- take the first free walkable cell rather than park inside scenery
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

  -- walked for real rather than pushed, so a broken start menu surfaces here
  -- instead of masquerading as an icon bug
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

  -- ---- what the screen actually holds ------------------------------------
  -- Render the live menu into a clean 160x144 canvas and fold each icon block
  -- (x 8..23) down its middle.  No SGB zone pass needed: mirror symmetry is
  -- geometry, and colorization maps both sides the same way.
  local function snapshot()
    local canvas = love.graphics.newCanvas(160, 144)
    love.graphics.setCanvas(canvas)
    love.graphics.clear(1, 1, 1, 1)
    love.graphics.setColor(1, 1, 1, 1)
    pm:draw()
    love.graphics.setCanvas()
    love.graphics.setColor(1, 1, 1, 1)
    return canvas:newImageData()
  end

  local function foldRow(id, i)
    local y0 = PartyMenu.entryY(i)
    local n = 0
    for dy = 0, 15 do
      for dx = 0, 7 do
        local r1, g1, b1 = id:getPixel(8 + dx, y0 + dy)
        local r2, g2, b2 = id:getPixel(23 - dx, y0 + dy)
        if math.abs(r1 - r2) > 0.01 or math.abs(g1 - g2) > 0.01
           or math.abs(b1 - b2) > 0.01 then
          n = n + 1
        end
      end
    end
    return n
  end

  if getmetatable(pm) == PartyMenu and love.graphics.newCanvas then
    local keepIndex, keepBlink = pm.index, pm.blink
    -- everything at rest, cursor parked on the fossil so no other row animates
    pm.index, pm.blink = 4, 0
    local rest = snapshot()
    for i, row in ipairs(ROWS) do
      local n = foldRow(rest, i)
      U.log(("  row %d %-10s folded: %d mismatched pixel pairs")
              :format(i, row.species, n))
      if row.icon == "HELIX" then
        check("the fossil icon is still asymmetric on purpose", n > 0)
      else
        check(row.species .. "'s icon is left-right symmetric on screen", n == 0)
      end
    end

    -- AnimatePartyMon runs the selected icon at 5 frames per phase while its
    -- HP bar is green, so blink 5 is the alternate frame (asymmetric for BIRD)
    pm.index, pm.blink = 3, 5
    local bird = snapshot()
    check("SPEAROW's animated frame is symmetric too", foldRow(bird, 3) == 0)

    pm.index, pm.blink = keepIndex, keepBlink
  end

  -- ---- screenshots -------------------------------------------------------
  pm.index = 1
  U.wait(4)
  if U.shot(game, DIR .. "/bug276_party_rest.png") then
    U.log("captured", DIR .. "/bug276_party_rest.png")
  end
  -- put the cursor on SPEAROW so the capture catches the animated bird
  U.tap(game, "down")
  U.wait(6)
  U.tap(game, "down")
  U.wait(20)
  if U.shot(game, DIR .. "/bug276_party_bird_selected.png") then
    U.log("captured", DIR .. "/bug276_party_bird_selected.png")
  end

  -- ---- hand off ----------------------------------------------------------
  U.log("Party list is open, cursor on SPEAROW: CHARMANDER, PIKACHU, SPEAROW,")
  U.log("OMANYTE, WEEDLE, RATTATA. Fold any icon but row 4 down its middle and")
  U.log("the halves should match, at rest and while the selected one bounces")
  U.log("(#276). Row 4, the fossil, is the deliberate exception.")

  while true do
    coroutine.yield()
  end
end
