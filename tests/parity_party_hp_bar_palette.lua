-- Parity test: the party screen's SGB block packet (#274, absorbing #272).
-- SetPal_PartyMenu sends PalPacket_PartyMenu plus BlkPacket_PartyMenu
-- (engine/gfx/palettes.asm:90, data/sgb/sgb_packets.asm:149-158 and :219), and
-- each bar block takes its palette from that mon's wPartyMenuHPBarColors entry
-- (palettes.asm:293-325).  The port gave the whole screen one MEWMON zone, and
-- the pre-tinted fill then double-applied on top of it (the #229 hazard).
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local S = require("tests.harness").suite("parity party hp bar palette")
local check, eq = S.check, S.eq

local Data = require("src.core.Data")
if not Data.maps then Data:load() end
local Font = require("src.render.Font")
Font.load(Data)

local PaletteFX = require("src.render.PaletteFX")
local HudTiles = require("src.render.HudTiles")
local PartyMenu = require("src.ui.PartyMenu")
local Pokemon = require("src.pokemon.Pokemon")

local prevMode = PaletteFX.mode

-- A 48/48 bar is one pixel per HP, so GetHealthBarColor's 27 / 10 pixel
-- thresholds land on plain numbers here.
local LEVELS = {
  { species = "BULBASAUR", hp = 48, pal = "GREENBAR" },
  { species = "PIDGEY",    hp = 26, pal = "YELLOWBAR" },
  { species = "RATTATA",   hp = 9,  pal = "REDBAR" },
  { species = "CATERPIE",  hp = 0,  pal = "REDBAR" },
}

local party = {}
for i, l in ipairs(LEVELS) do
  local mon = Pokemon.new(Data, l.species, 20)
  mon.stats.hp = 48
  mon.hp = l.hp
  party[i] = mon
  eq(PaletteFX.barPalName(l.hp, 48), l.pal,
     ("%d/48 HP is a %s bar"):format(l.hp, l.pal))
end

local game = {
  data = Data,
  save = { party = party, options = {} },
  stack = { push = function() end, pop = function() end,
            top = function() end },
}

-- ---- the block packet ----------------------------------------------------
local function zonesIn(mode, menu)
  PaletteFX.setMode(mode)
  return menu:sgbPalettes(game), mode
end

for _, mode in ipairs({ "gbc", "redpp" }) do
  local menu = PartyMenu.new(game, {})
  local zones = zonesIn(mode, menu)
  local tag = " [" .. PaletteFX.modeLabel(mode) .. "]"

  check(type(zones) == "table", "sgbPalettes returns a zone list" .. tag)
  zones = zones or {}
  eq(#zones, 2 + #party,
     "base + icon column + one block per HP bar row" .. tag)

  local green = PaletteFX.pal(Data, "GREENBAR")
  local mew = PaletteFX.pal(Data, "MEWMON")
  check(green and mew, "GREENBAR and MEWMON both resolve" .. tag)

  -- pal 1 of the PAL_SET is the screen's base, not MEWMON
  local base = zones[1] or {}
  eq(base.colors, green, "the base zone is GREENBAR, not MEWMON" .. tag)
  eq(base.x, 0, "base zone x" .. tag)
  eq(base.y, 0, "base zone y" .. tag)
  eq(base.w, 160, "base zone spans the screen width" .. tag)
  eq(base.h, 144, "base zone spans the screen height" .. tag)

  -- ATTR_BLK_DATA ... 01,00, 02,12 -> tiles x 1..2, rows 0..11 here: the block
  -- stops at row 11 because row 12 is this port's message-box edge
  local col = zones[2] or {}
  eq(col.colors, mew, "the icon column keeps MEWMON" .. tag)
  eq(col.x, 8, "icon column starts at tile 1" .. tag)
  eq(col.y, 0, "icon column starts at row 0" .. tag)
  eq(col.w, 16, "icon column is the two-tile-wide icon block" .. tag)
  eq(col.h, 96, "icon column stops above the message box" .. tag)

  -- the base swap is invisible outside the icons and the bars only because
  -- MEWMON and GREENBAR agree on paper and ink in every pack: names, levels,
  -- HP numbers, border and cursor are all color 3 on color 0
  for _, ci in ipairs({ 1, 4 }) do
    local a, b = mew and mew[ci], green and green[ci]
    check(a and b and a[1] == b[1] and a[2] == b[2] and a[3] == b[3],
          ("MEWMON and GREENBAR share color %d (text/box unchanged)%s")
            :format(ci - 1, tag))
  end

  for i, l in ipairs(LEVELS) do
    local z = zones[2 + i] or {}
    local want = PaletteFX.pal(Data, l.pal)
    eq(z.colors, want,
       ("row %d (%d/48 HP) carries the %s block palette%s")
         :format(i, l.hp, l.pal, tag))
    -- 05,YY - 11,YY shifted one tile right, because this port draws the bar at
    -- tile 5 where party_menu.asm:71-76 draws it at 4; still cap + six fill
    eq(z.x, 48, ("row %d bar block starts at tile 6%s"):format(i, tag))
    eq(z.w, 56, ("row %d bar block is seven tiles wide%s"):format(i, tag))
    eq(z.y, (i * 2 - 1) * 8, ("row %d bar block sits on its HP row%s"):format(i, tag))
    eq(z.h, 8, ("row %d bar block is one tile tall%s"):format(i, tag))
  end
end

-- ---- TM/HM list: ABLE / NOT ABLE where the bar would be (#210) ------------
do
  PaletteFX.setMode("redpp")
  local menu = PartyMenu.new(game, { tmhm = { move = "TM01", kind = "TM" } })
  local zones = menu:sgbPalettes(game) or {}
  eq(#zones, 2, "the TM/HM list has no bar rows to color")
end

-- ---- a medicine's fill holds the PRE-heal block palette (#252) ------------
do
  PaletteFX.setMode("redpp")
  local menu = PartyMenu.new(game, {})
  menu.heal = { mon = party[3], from = 9, shown = 30 }
  local zones = menu:sgbPalettes(game) or {}
  eq((zones[5] or {}).colors, PaletteFX.pal(Data, "REDBAR"),
     "a healing row keeps its pre-heal bar palette until the redraw")
end

-- ---- the bar the rects are aimed at --------------------------------------
-- grayFill: with a zone pass coming, the fill must stay raw DMG shade-2 gray
-- or the tint and the zone double-apply (a GREENBAR fill has red channel 0, so
-- the red-keyed shade shader maps the whole bar to color 3 = black).
-- PaletteFX.shader() is stubbed rather than the love global because the real
-- one caches its compile and another suite may already have resolved it.
do
  PaletteFX.setMode("redpp")
  local menu = PartyMenu.new(game, {})
  local realShader, realBar = PaletteFX.shader, HudTiles.drawHPBar
  local realDraw = love.graphics.draw
  local seen = {}
  local function record()
    HudTiles.drawHPBar = function(data, tx, ty, mon, barType, grayFill)
      seen[#seen + 1] = { tx = tx, ty = ty, barType = barType,
                          gray = grayFill and true or false }
    end
    love.graphics.draw = function() end
  end
  local function restore()
    HudTiles.drawHPBar, love.graphics.draw = realBar, realDraw
    PaletteFX.shader = realShader
  end

  PaletteFX.shader = function() return { send = function() end } end
  record()
  local ok, err = pcall(function() menu:draw() end)
  restore()
  check(ok, "PartyMenu:draw runs headless" .. (ok and "" or (": " .. tostring(err))))
  eq(#seen, #party, "one HP bar per party row")
  for i, bar in ipairs(seen) do
    eq(bar.gray, true, ("row %d draws a gray fill when a zone pass will run")
                         :format(i))
    -- the placement the sgbPalettes rects above are keyed to
    eq(bar.tx, 5, ("row %d bar starts at tile 5"):format(i))
    eq(bar.ty, i * 2 - 1, ("row %d bar sits on its HP row"):format(i))
    -- wHPBarType 2: the party menu closes with the $6C nub, not the
    -- player-battle double bar (home/pokemon.asm DrawHPBar "Right")
    eq(bar.barType, nil, ("row %d keeps the party-menu right cap"):format(i))
    eq(HudTiles.capTile(bar.barType), 0x6C,
       ("row %d cap tile is the party nub"):format(i))
  end

  -- and the other way: with no shade-remap shader nothing will colorize the
  -- canvas, so the per-pixel tint is the only color the bar can get
  seen = {}
  PaletteFX.shader = function() return nil end
  record()
  pcall(function() menu:draw() end)
  restore()
  eq(#seen, #party, "one HP bar per party row (unshaded build)")
  for i, bar in ipairs(seen) do
    eq(bar.gray, false,
       ("row %d keeps its tinted fill with no shader to colorize it"):format(i))
  end
end

PaletteFX.setMode(prevMode)
S.finish()
