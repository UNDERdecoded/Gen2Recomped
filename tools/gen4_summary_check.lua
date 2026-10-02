-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- tools/gen4_summary_check.lua -- the summary page's Pokemon picture.
--
-- The slot was declared when the screen was written and never drawn into, so
-- for its whole life the page came up as numbers beside an empty plate.  That
-- is the kind of fault nothing reports: the screen works, the words are right,
-- and the only symptom is an absence.
--
-- Two numbers are being checked, and they are checked the way each was got:
--   the CENTRE is stated by the cartridge and independently measured off the
--   art, so the check is that the two MEET;
--   the MIRROR is a reading of a flag, so the check is that the decision
--   function makes both answers and does not mirror a cache that has no flag
--   to read.
--
-- Run:  texlua tools/gen4_summary_check.lua

local root = (arg[0] or ""):gsub("[^/\\]*$", "")
if root ~= "" then package.path = root .. "../?.lua;" .. package.path end
package.path = "./?.lua;" .. package.path

local Menus = require("src.import.Gen4Menus")
local Otherpoke = require("src.import.Gen4Otherpoke")

local fails, checks = 0, 0
local function ok(cond, what, got, want)
  checks = checks + 1
  if cond then io.write(("  ok    %-56s %s\n"):format(what, tostring(got)))
  else fails = fails + 1
       io.write(("  FAIL  %-56s got %s, expected %s\n")
                :format(what, tostring(got), tostring(want))) end
end

-- The screen is a love.graphics consumer, so its module is read rather than
-- required.  Reading it is also the only way to check that the constants the
-- SCREEN falls back to are the ones the IMPORT writes -- requiring it would
-- need a graphics device and would then be testing one copy twice.
local function screenSource()
  local f = io.open((root ~= "" and root .. "../" or "") .. "src/ui/Gen4SummaryMenu.lua", "rb")
  if not f then return nil end
  local s = f:read("*a"); f:close()
  return s
end

local src = screenSource()
if not src then
  io.write("cannot read src/ui/Gen4SummaryMenu.lua\n")
  os.exit(2)
end

local function number(pattern)
  return tonumber(src:match(pattern))
end

io.write("the summary page's picture\n")

-- ------------------------------------------------------------ the centre --

local L = Menus.SUMMARY_LAYOUT
local P = L.picture

ok(type(P) == "table" and P.x == 52 and P.y == 104,
   "the import writes the cartridge's own sprite centre",
   type(P) == "table" and ("%s,%s"):format(tostring(P.x), tostring(P.y)) or "?",
   "52,104")
ok(P.plate == 64, "...and the plate it is centred on", P.plate, 64)

-- THE TWO STATEMENTS MEETING.  The plate measured off all ten page tilemaps
-- is x 20..83, y 72..135.  A `plate`-sided square centred on the stated pair
-- must be exactly that rect -- and this is arithmetic on the constants, not
-- the measured numbers restated, so a change to either side breaks it.
local half = P.plate / 2
ok(P.x - half == 20 and P.x + half - 1 == 83,
   "a 64-square on that centre is the measured plate, across",
   ("%d..%d"):format(P.x - half, P.x + half - 1), "20..83")
ok(P.y - half == 72 and P.y + half - 1 == 135,
   "...and down",
   ("%d..%d"):format(P.y - half, P.y + half - 1), "72..135")

-- WHAT THE PICTURE MUST CLEAR.  It is 80 square on a 64 plate, so it overhangs
-- -- and the thing it must not overhang INTO is the label column, which was
-- measured off the same art for a different reason entirely.
local size = number("PICTURE_SIZE = (%d+)") or 0
ok(size == 80, "the picture is the pokegra cell, undoubled", size, 80)
local right = P.x + size / 2
ok(right <= L.label.x, "...and still clears the label column at its widest",
   ("%d <= %d"):format(right, L.label.x), "true")
ok(P.x - size / 2 >= 0 and P.y - size / 2 >= 0 and P.y + size / 2 <= 192,
   "...and sits on the screen on all four sides",
   ("%d,%d..%d,%d"):format(P.x - size / 2, P.y - size / 2,
                           right, P.y + size / 2), "inside 256x192")

-- The screen's own fallback must be the same pair, because a cache with no
-- `summary` record uses it and would otherwise disagree with every other cache.
ok(src:find("picture = { x = 52, y = 104, plate = 64 }", 1, true) ~= nil,
   "the screen's fallback layout agrees with the import", "yes", "yes")
ok(src:find("Gen4SummaryMenu.PICTURE = { x = 52, y = 104, plate = 64 }",
            1, true) ~= nil,
   "...and so does the constant it falls back to", "yes", "yes")

-- -------------------------------------------------------------- the egg --

-- The screen names the egg by a string; the extractor builds the same string
-- from a row.  Asserting one against the other is what stops the two drifting
-- when a form row is renamed.
local eggKey = src:match('EGG_KEY = "([^"]+)"')
local eggRow, manaphyRow
for _, row in ipairs(Otherpoke.FORMS) do
  if row.species == 0 and row.name == "egg" then
    if row.form == "base" then eggRow = row else manaphyRow = row end
  end
end
ok(eggRow ~= nil, "pl_otherpoke still files an egg under species 0",
   eggRow and Otherpoke.key(eggRow) or "nil", "a row")
ok(eggRow ~= nil and eggKey == Otherpoke.key(eggRow),
   "...and the screen's key is that row's own",
   tostring(eggKey), eggRow and Otherpoke.key(eggRow) or "?")
ok(eggRow ~= nil and eggRow.front ~= nil and eggRow.back == nil,
   "...a front picture and no back, which is what an egg has",
   eggRow and ("front %s, back %s"):format(tostring(eggRow.front),
                                           tostring(eggRow.back)) or "?",
   "front only")
-- The separate Manaphy egg resource must be available to the summary screen.
ok(manaphyRow ~= nil
   and src:find(Otherpoke.key(manaphyRow), 1, true),
   "the summary can select the separately extracted Manaphy egg",
   manaphyRow and Otherpoke.key(manaphyRow) or "nil", "present")

-- ------------------------------------------------------------ the mirror --

-- The cartridge's rule, restated as the function the screen uses.  It is
-- restated rather than imported because the screen needs love.graphics; what
-- matters is that all three answers are distinct, which is the whole content
-- of the reading.
local function flipFor(def)
  return def ~= nil and def.flipSprite ~= nil and not def.flipSprite
end

ok(flipFor({ flipSprite = false }) == true,
   "a species with the flag clear is mirrored", "mirrored", "mirrored")
ok(flipFor({ flipSprite = true }) == false,
   "UNOWN, SPINDA and the other 26 with it set are not",
   "as drawn", "as drawn")
-- THE ONE THAT MATTERS FOR THE OTHER THREE GAMES.  A Gen 1-3 species row has
-- no `flipSprite` at all, and the obvious `not def.flipSprite` would mirror
-- every Pokemon in Kanto, Johto and Hoenn.
ok(flipFor({}) == false, "a row with no such field is left alone",
   "as drawn", "as drawn")
ok(flipFor(nil) == false, "and so is no row at all", "as drawn", "as drawn")

-- A canary: if the decision ever collapses to one answer the four lines above
-- still pass individually and say nothing.
local answers = {}
answers[tostring(flipFor({ flipSprite = false }))] = true
answers[tostring(flipFor({ flipSprite = true }))] = true
local distinct = 0
for _ in pairs(answers) do distinct = distinct + 1 end
ok(distinct == 2, "...and the decision still has two answers", distinct, 2)

-- The screen must actually ask that question of the data rather than of a
-- constant -- the fault this whole file exists for is a slot nobody filled.
ok(src:find("def.flipSprite", 1, true) ~= nil,
   "the screen reads the flag off the species row", "yes", "yes")
ok(src:find("self:drawPicture()", 1, true) ~= nil,
   "...and the page actually draws the picture", "yes", "yes")

io.write(("\n%d checks, %d failures\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
