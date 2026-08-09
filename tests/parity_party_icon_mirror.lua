-- Parity test: the party list draws each icon as a mirrored LEFT half (#276).
-- pokered engine/gfx/mon_icons.asm:234-251 sends every icon but ICON_HELIX
-- through WriteSymmetricMonPartySpriteOAM (engine/items/town_map.asm:494-534),
-- whose inner loop writes the same tile twice (plain, then OAM_XFLIP) before
-- bumping the tile number by 2, so the frame's right column never reaches the
-- screen.  Pixels: tests/drivers/party_icon_mirror_bug276_test.lua.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local S = require("tests.harness").suite("parity party icon mirror")
local check, eq = S.check, S.eq

local Data = require("src.core.Data")
if not Data.maps then Data:load() end
local Font = require("src.render.Font")
Font.load(Data)

local PartyMenu = require("src.ui.PartyMenu")
local Pokemon = require("src.pokemon.Pokemon")

-- ---- the HELIX carve-out, as a pure function -----------------------------
-- data/pokemon/menu_icons.asm gives ICON_HELIX to Shellder/Cloyster,
-- Staryu/Starmie and the fossil lines, and to nothing else.
check(type(PartyMenu.mirrorsIcon) == "function",
      "PartyMenu.mirrorsIcon is exported")
-- keep going when it is missing, so the draw geometry below still reports
local mirrors = type(PartyMenu.mirrorsIcon) == "function"
                and PartyMenu.mirrorsIcon or function() return nil end
eq(mirrors("MON"), true, "MON mirrors")
eq(mirrors("FAIRY"), true, "FAIRY mirrors")
eq(mirrors("BIRD"), true, "BIRD mirrors")
eq(mirrors("BALL"), true, "BALL mirrors")
eq(mirrors("HELIX"), false, "HELIX takes the asymmetric path")
eq(mirrors(nil), false, "mod art (no built-in icon name) draws whole")

-- ---- one party row per icon class, each on its own sheet -----------------
-- Distinct sheets so a recorded draw can be attributed back to its row.
-- byDex is the extractor's copy of MonPartyData; the frames come from
-- PartyMenu.iconFrames (data/icon_pointers.asm MonPartySpritePointers).
local CASES = {
  { species = "CHARMANDER", icon = "MON",       rest = 3, alt = 0 },
  { species = "PIKACHU",    icon = "FAIRY",     rest = 3, alt = 0 },
  { species = "SPEAROW",    icon = "BIRD",      rest = 3, alt = 0 },
  -- HELIX and BALL carry no iconFrames row: one 16x16 frame, and
  -- AnimatePartyMon nudges them a pixel down instead of swapping frames.
  { species = "OMANYTE",    icon = "HELIX",     rest = 0 },
  { species = "WEEDLE",     icon = "BUG",       rest = 1, alt = 0 },
  { species = "RATTATA",    icon = "QUADRUPED", rest = 0, alt = 1 },
}

local icons = Data.icons
check(icons and icons.icons and icons.byDex, "data.icons carries icons/byDex")

local party = {}
for i, c in ipairs(CASES) do
  local def = Data.pokemon[c.species]
  local name = def and def.dex and icons.byDex[def.dex]
  eq(name, c.icon, c.species .. " uses the " .. c.icon .. " icon")
  local path = name and icons.icons[name]
  check(type(path) == "string" and path ~= "",
        c.icon .. " resolves a sheet path")
  c.path = path
  eq(PartyMenu.frameFor(name, false, 96), c.rest, c.icon .. " rest frame")
  if c.alt then
    eq(PartyMenu.frameFor(name, true, 96), c.alt, c.icon .. " animated frame")
  end
  party[i] = Pokemon.new(Data, c.species, 20)
end

-- every case must sit on its own sheet or the per-row attribution below lies
do
  local seen = {}
  for _, c in ipairs(CASES) do
    check(c.path and not seen[c.path], (c.icon or "?") .. " has its own sheet")
    seen[c.path] = true
  end
end

local game = {
  data = Data,
  save = { party = party, options = {} },
  stack = { push = function() end, pop = function() end,
            top = function() end },
}
local menu = PartyMenu.new(game, {})

-- ---- record the icon draws ------------------------------------------------
-- love.graphics.draw(image, quad, x, y, r, sx, sy).  The stub's newImage
-- keeps the resolved path, which is how a draw is tied back to a row.
local function drawsFor(index, blink)
  menu.index = index or 1
  menu.blink = blink or 0
  local real = love.graphics.draw
  local rec = {}
  love.graphics.draw = function(img, a, b, c, d, e, f)
    rec[#rec + 1] = { img = img, a = a, b = b, c = c, d = d, e = e, f = f }
  end
  local ok, err = pcall(function() menu:draw() end)
  love.graphics.draw = real
  check(ok, "PartyMenu:draw runs headless" .. (ok and "" or (": " .. tostring(err))))
  local byRow = {}
  for _, r in ipairs(rec) do
    local p = type(r.img) == "table" and r.img.path
    if type(p) == "string" then
      for ci, c in ipairs(CASES) do
        -- Assets.resolve may prefix an override dir, so match on the tail
        if p:sub(-#c.path) == c.path then
          byRow[ci] = byRow[ci] or {}
          table.insert(byRow[ci], r)
        end
      end
    end
  end
  return byRow
end

-- Park the cursor on row 4 (the fossil) so the other five rows are at rest
-- and no alt frame is in play.
local rows = drawsFor(4, 0)

for i, c in ipairs(CASES) do
  local d = rows[i] or {}
  local y = PartyMenu.entryY(i)
  if c.icon == "HELIX" then
    -- WriteAsymmetricMonPartySpriteOAM (town_map.asm:461-492): the one icon
    -- whose four tile patterns are all distinct, so it draws whole
    eq(#d, 1, "HELIX icon is one whole draw")
    if d[1] then
      eq(d[1].a, 8, "HELIX draws at x=8 with no quad")
      eq(d[1].b, y, "HELIX draws on its own row")
    end
  else
    eq(#d, 2, c.icon .. " icon is a half plus its mirror")
    local half, flip = d[1], d[2]
    if half and flip then
      check(type(half.a) == "table" and half.a.w == 8 and half.a.h == 16,
            c.icon .. " left half is an 8x16 quad")
      eq(type(half.a) == "table" and half.a.x, 0,
         c.icon .. " left half starts at the frame's left edge")
      eq(type(half.a) == "table" and half.a.y, c.rest * 16,
         c.icon .. " left half reads the rest frame")
      eq(half.b, 8, c.icon .. " left half lands at x=8")
      eq(half.c, y, c.icon .. " left half lands on its row")
      eq(flip.a, half.a, c.icon .. " mirror reuses the same left-half quad")
      eq(flip.b, 8 + 16, c.icon .. " mirror is anchored on the block's right edge")
      eq(flip.c, y, c.icon .. " mirror lands on its row")
      eq(flip.e, -1, c.icon .. " mirror is x-flipped (OAM_XFLIP)")
      eq(flip.f, 1, c.icon .. " mirror is not y-flipped")
    end
  end
end

-- ---- the animated frame mirrors too --------------------------------------
-- AnimatePartyMon only animates the selected mon, and BIRD is the class whose
-- animated frame is the asymmetric one, so a Spearow only goes lopsided while
-- the cursor is on it.  At full HP the phase is 5 frames, so blink 5 is alt.
do
  local bird = 3
  local alt = drawsFor(bird, 5)
  local d = alt[bird] or {}
  eq(#d, 2, "the animated BIRD frame is still a half plus its mirror")
  if d[1] and d[2] then
    eq(type(d[1].a) == "table" and d[1].a.y, CASES[bird].alt * 16,
       "the animated BIRD frame is tile 0, not the rest frame")
    eq(d[1].a.w, 8, "the animated BIRD half is 8 wide")
    eq(d[2].e, -1, "the animated BIRD mirror is x-flipped")
  end
end

S.finish()
