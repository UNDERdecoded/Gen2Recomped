-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- THE UNDERGROUND'S MENU, WHICH IS THE WAY OUT.
--
-- Pass 130 built the descent and left the ascent as a DELIBERATE DEVIATION:
-- the Explorer Kit doubled as the way up, because the cartridge's
-- `CanUseExplorerKit` refuses the kit down there precisely because this menu is
-- what you use. So the one assertion that matters here is that GO UP works --
-- by button AND by finger, since the Underground is the one place in Platinum
-- where the field is on the touch screen.
--
-- THE ORDER IS LOAD-BEARING. GO UP is sixth of seven in
-- `sUndergroundMenuOptions`, and four of the other six have no subsystem behind
-- them yet. A port that dropped those four would move GO UP to second and put
-- the only option that matters under a different finger -- so they stay, they
-- refuse by name, and this check pins the position.
--
-- Usage: texlua tools/gen4_underground_menu_check.lua [<cache dir>]
--    or: python tools/run_lua_check.py tools/gen4_underground_menu_check.lua [<cache>]

package.path = "./?.lua;" .. package.path

if not pcall(require, "bit") then
  package.preload["bit"] = function()
    local M = {}
    for _, n in ipairs({ "band", "bor", "bxor", "lshift", "rshift", "arshift" }) do
      M[n] = function() return 0 end
    end
    M.bnot = function() return 0 end
    M.tobit = function(a) return a end
    M.tohex = function() return "0" end
    return M
  end
end

love = love or {
  graphics = { setColor = function() end, rectangle = function() end,
               draw = function() end, getWidth = function() return 240 end,
               getHeight = function() return 160 end },
  filesystem = { getInfo = function() return nil end, read = function() return nil end },
  timer = { getTime = function() return 0 end },
  system = { getOS = function() return "Linux" end },
}

local fails, checks = 0, 0
local function ok(cond, fmt, ...)
  checks = checks + 1
  if not cond then
    fails = fails + 1
    io.write("FAIL: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
  end
end
local function section(n) io.write(("\n-- %s\n"):format(n)) end

local okM, Menu = pcall(require, "src.ui.Gen4UndergroundMenu")
local okU, UG = pcall(require, "src.world.Gen4Underground")
local okT, Gen4Text = pcall(require, "src.import.Gen4Text")
ok(okM and okU and okT, "a module did not load: %s %s %s",
   tostring(Menu), tostring(UG), tostring(Gen4Text))
if not (okM and okU and okT) then
  io.write(("\n%d checks, %d failed\n"):format(checks, fails))
  os.exit(1)
end

-- ---------------------------------------------------------------------------
section("1. the cartridge's seven options, in the cartridge's order")
-- ---------------------------------------------------------------------------
-- `sUndergroundMenuOptions`, and the bank entries beside them. Both are pinned:
-- the ORDER because GO UP's position is what the four unserved rows exist to
-- preserve, and the ENTRY because a shifted bank index shows another screen's
-- words with no error anywhere.
local WANT = {
  { id = "traps",     entry = 121 },
  { id = "spheres",   entry = 122 },
  { id = "goods",     entry = 123 },
  { id = "treasures", entry = 124 },
  { id = "trainer",   entry = 125, player = true },
  { id = "go_up",     entry = 126 },
  { id = "close",     entry = 127 },
}
ok(Menu.BANK == 634, "the menu reads bank %s, not 634", tostring(Menu.BANK))
ok(#Menu.OPTIONS == 7, "%d options, not seven", #Menu.OPTIONS)
for i, want in ipairs(WANT) do
  local got = Menu.OPTIONS[i]
  ok(got ~= nil and got.id == want.id,
     "option %d is %q and the cartridge has %q", i,
     tostring(got and got.id), want.id)
  ok(got ~= nil and got.entry == want.entry,
     "option %d (%s) reads bank entry %s, not %d", i, want.id,
     tostring(got and got.entry), want.entry)
  ok((got ~= nil and got.player == true) == (want.player == true),
     "option %d (%s): the player-name row is bank 634 entry 125 and nothing "
       .. "else", i, want.id)
end
-- GO UP's POSITION, asserted on its own because it is the reason the unserved
-- rows are kept.
local goUpAt = nil
for i, o in ipairs(Menu.OPTIONS) do if o.id == "go_up" then goUpAt = i end end
ok(goUpAt == 6, "GO UP is option %s and the cartridge puts it sixth",
   tostring(goUpAt))

-- ---------------------------------------------------------------------------
section("2. the geometry is the cartridge's, and two of its numbers agree")
-- ---------------------------------------------------------------------------
-- `Window_Add(..., BG_LAYER_MAIN_3, 20, 1, 11, NELEMS * 3, 13, ...)` gives the
-- panel and a three-tile row pitch. `sSpriteTemplates[CURSOR_TEMPLATE]` gives
-- the cursor at x 204, y 20 -- a SEPARATE statement in the same file.
--
-- THE CHECK IS THAT THEY MEET: row one's centre, computed from the window
-- alone, must land on the cursor the cartridge draws there. Two numbers from
-- two places agreeing is the one thing here that cannot be a coincidence of
-- my own arithmetic.
local L = Menu._layout
ok(type(L) == "table", "the menu publishes no _layout for a check to use")
if type(L) == "table" then
  ok(L.panelTileX == 20 and L.panelTileY == 1 and L.panelTileW == 11,
     "the panel is at tile %s,%s width %s, not 20,1 width 11",
     tostring(L.panelTileX), tostring(L.panelTileY), tostring(L.panelTileW))
  ok(L.rowTiles == 3, "the row pitch is %s tiles, not three", tostring(L.rowTiles))
  local x, y, w, h = Menu.rowRect(1, 7)
  ok(x ~= nil, "rowRect(1) gave nothing")
  if x then
    local centreX, centreY = x + w / 2, y + h / 2
    ok(centreY == 20,
       "row one's centre is y=%s and the cartridge's cursor sits at y=20",
       tostring(centreY))
    ok(centreX == 204,
       "row one's centre is x=%s and the cartridge's cursor sits at x=204",
       tostring(centreX))
  end
  -- ...AND THE ROWS TILE THE PANEL: no gap for a tap to fall through, no
  -- overlap for two rows to claim.
  local covered = 0
  for i = 1, 7 do
    local rx, ry, rw, rh = Menu.rowRect(i, 7)
    ok(rx == L.panelX and rw == L.panelW, "row %d is not the panel's width", i)
    covered = covered + rh
    if i > 1 then
      local _, py, _, ph = Menu.rowRect(i - 1, 7)
      ok(ry == py + ph, "row %d starts at %s and row %d ends at %s",
         i, tostring(ry), i - 1, tostring(py + ph))
    end
  end
  ok(covered == 7 * L.pitch, "the seven rows cover %s, not the panel's %s",
     tostring(covered), tostring(7 * L.pitch))
  ok(Menu.rowRect(0, 7) == nil and Menu.rowRect(8, 7) == nil,
     "rowRect answers for an option that does not exist")
end

-- ---------------------------------------------------------------------------
section("3. a finger finds the row it is on, and only that row")
-- ---------------------------------------------------------------------------
for i = 1, 7 do
  local x, y, w, h = Menu.rowRect(i, 7)
  ok(Menu.rowAt(x + w / 2, y + h / 2, 7) == i,
     "the centre of row %d does not resolve to row %d", i, i)
  ok(Menu.rowAt(x, y, 7) == i, "row %d's top-left corner misses", i)
  ok(Menu.rowAt(x + w - 1, y + h - 1, 7) == i,
     "row %d's bottom-right corner misses", i)
end
-- ...AND A MISS IS A MISS. Without these the hit test could answer every
-- point with row 1 and the loop above would still pass.
ok(Menu.rowAt(L.panelX - 1, L.panelY + 4, 7) == nil, "a press left of the panel hits")
ok(Menu.rowAt(L.panelX + L.panelW, L.panelY + 4, 7) == nil,
   "a press right of the panel hits")
ok(Menu.rowAt(L.panelX + 4, L.panelY - 1, 7) == nil, "a press above the panel hits")
ok(Menu.rowAt(L.panelX + 4, L.panelY + 7 * L.pitch, 7) == nil,
   "a press below the panel hits")
ok(Menu.rowAt(nil, 10, 7) == nil and Menu.rowAt(10, nil, 7) == nil,
   "the hit test accepts a nil coordinate")

-- ---------------------------------------------------------------------------
section("4. GO UP goes up -- by button and by finger")
-- ---------------------------------------------------------------------------
local function fixture(remembered)
  local warps, popped = {}, 0
  local text = {}
  for entry, word in pairs({ [121] = "TRAPS", [122] = "SPHERES", [123] = "GOODS",
                             [124] = "TREASURES", [125] = "{STRVAR_1 1 1 0}",
                             [126] = "GO UP", [127] = "CLOSE" }) do
    text[Gen4Text.label(634, entry)] = word
  end
  local ow = {
    map = { id = UG.MAP_ID, def = { label = "Mystery Zone" } },
    startWarpTo = function(_, map, x, y, facing)
      warps[#warps + 1] = { map = map, x = x, y = y, facing = facing }
    end,
  }
  local game = {
    data = { text = text, maps = { ["C01"] = { id = "C01" } } },
    save = { playerName = "CEDRIC",
             gen4SpecialLocation = remembered
               and { map = "C01", x = 12, y = 7, facing = "up" } or nil },
    stack = { pop = function() popped = popped + 1 end },
    overworld = ow,
  }
  return game, warps, function() return popped end
end

do
  local game, warps, popped = fixture(true)
  ok(UG.isUnderground(game.overworld),
     "the fixture is not underground, so nothing below tests the real path")
  local menu = Menu.new(game, {})
  ok(#menu.rows == 7, "the menu built %d rows", #menu.rows)
  ok(menu.rows[5].label == "CEDRIC",
     "the player row reads %q rather than the player's name",
     tostring(menu.rows[5].label))
  ok(menu.rows[6].label == "GO UP", "row six reads %q",
     tostring(menu.rows[6].label))

  local went = menu:activate(6)
  ok(went == true, "GO UP refused on a save that remembers: %s",
     tostring(menu.message))
  ok(#warps == 1, "GO UP started %d warps", #warps)
  if warps[1] then
    ok(warps[1].map == "C01" and warps[1].x == 12 and warps[1].y == 7
         and warps[1].facing == "up",
       "GO UP went to %s @ %s,%s facing %s rather than the remembered cell",
       tostring(warps[1].map), tostring(warps[1].x), tostring(warps[1].y),
       tostring(warps[1].facing))
  end
  ok(popped() == 1, "GO UP left the menu on the stack over the trip (%d pops)",
     popped())
end

-- BY FINGER. The same thing through `touchpressed`, which is the half of #198
-- that is actually new -- `Gen4StartMenu` takes buttons only.
do
  local game, warps = fixture(true)
  package.loaded["src.render.Renderer"] =
    { uiPresentation = { x = 0, y = 0, w = 256, h = 192, scaleX = 1, scaleY = 1 } }
  local menu = Menu.new(game, {})
  local x, y, w, h = Menu.rowRect(6, 7)
  local handled = menu:touchpressed(1, x + w / 2, y + h / 2)
  ok(handled == true, "a tap on GO UP was not taken by the menu")
  ok(menu.index == 6, "a tap on row six left the cursor on row %s",
     tostring(menu.index))
  ok(#warps == 1, "a tap on GO UP started %d warps", #warps)
  -- A MISS IS STILL OURS: this panel is modal, and a press falling through
  -- would walk the player around underneath it.
  local missed = menu:touchpressed(1, 4, 4)
  ok(missed == true, "a press off the panel fell through to the field")
end

-- ...AND IT REFUSES, OUT LOUD, WHEN IT CANNOT.
do
  local game, warps = fixture(false)
  local menu = Menu.new(game, {})
  local went = menu:activate(6)
  ok(went == false, "GO UP claimed success with nothing remembered")
  ok(#warps == 0, "GO UP warped with nothing remembered")
  ok(type(menu.message) == "string" and #menu.message > 0,
     "GO UP refused silently, which reads as a dead button")
end

-- ---------------------------------------------------------------------------
section("5. the four unserved rows refuse by name, and CLOSE closes")
-- ---------------------------------------------------------------------------
do
  local game, warps, popped = fixture(true)
  local menu = Menu.new(game, {})
  local refused = 0
  for i, row in ipairs(menu.rows) do
    if row.id ~= "go_up" and row.id ~= "close" then
      menu.message = nil
      local acted = menu:activate(i)
      ok(acted == false, "%s reported success and has no subsystem", row.id)
      ok(type(menu.message) == "string" and #menu.message > 0,
         "%s refused with no message, which is indistinguishable from a "
           .. "broken row", row.id)
      refused = refused + 1
    end
  end
  ok(refused == 5, "%d rows were exercised as unserved, not five", refused)
  ok(#warps == 0, "an unserved row started a warp")
  -- CLOSE
  menu:activate(7)
  ok(popped() == 1, "CLOSE popped %d times", popped())
end
-- THE UNSERVED LIST MUST NOT GO STALE. When one of these is built, its entry
-- comes out of the table and this number comes down -- which is the line that
-- says so.
local unserved = 0
for _ in pairs(Menu.UNSERVED or {}) do unserved = unserved + 1 end
ok(unserved == 5,
   "%d rows are listed unserved and five were recorded -- if one was built, "
     .. "take it out of UNSERVED and lower this", unserved)
for _, id in ipairs({ "traps", "spheres", "goods", "treasures", "trainer" }) do
  local why = (Menu.UNSERVED or {})[id]
  ok(type(why) == "string" and #why > 8,
     "%s has no reason written against it; one word is not a reason", id)
end
ok((Menu.UNSERVED or {}).go_up == nil and (Menu.UNSERVED or {}).close == nil,
   "GO UP or CLOSE is listed as unserved, which would make the menu a dead end")

-- ---------------------------------------------------------------------------
section("6. it is wired to the field")
-- ---------------------------------------------------------------------------
-- A screen nothing opens is a screen that does not exist. Both halves are
-- read out of the source, because neither can be observed from here: the
-- alias table, and the field's START handler asking about the Underground
-- BEFORE it asks the dataset for its own start menu.
local function slurp(path)
  local fh = io.open(path, "rb")
  if not fh then return nil end
  local t = fh:read("*a")
  fh:close()
  return t
end
local screens = slurp("src/ui/Screens.lua")
ok(screens ~= nil, "src/ui/Screens.lua could not be read")
if screens then
  ok(screens:find('UndergroundMenu%s*=%s*{%s*id%s*=%s*"Gen4UndergroundMenu"') ~= nil,
     "Screens has no UndergroundMenu alias for Gen4UndergroundMenu")
end
local field = slurp("src/world/OverworldController.lua")
ok(field ~= nil, "src/world/OverworldController.lua could not be read")
if field then
  ok(field:find('Screens%.push%(Game,%s*"UndergroundMenu"%)') ~= nil,
     "the field never pushes UndergroundMenu")
  -- ...AND IN THE RIGHT ORDER. Asked after the dataset's own start menu, the
  -- push would be unreachable: that branch returns.
  local hook = field:find('Screens%.push%(Game,%s*"UndergroundMenu"%)')
  local normal = field:find('Screens%.push%(Game,%s*screens%.startMenu')
  ok(hook ~= nil and normal ~= nil and hook < normal,
     "the Underground menu is pushed after the field's start menu, so it can "
       .. "never be reached")
end

io.write(("\n%d checks, %d failed\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
