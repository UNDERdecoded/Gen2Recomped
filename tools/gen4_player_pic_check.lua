-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- WHOSE BACK IS THE PLAYER FIGHTING WITH, AND IN WHOSE COLOURS?
--
-- Reported from play, on Platinum: "my trainers backsprite and possibly others
-- are drawing with a red hue overlay rather than their proper colors."
--
-- It is not a tint and it is not a palette decode fault. The chain is:
--
--   `field.playerForms.boy.back` is Lucas's own back sprite and the cache has
--   carried it all along; `Sprites.playerPath` picks it correctly; the record
--   has no `trueColor`, so `playerPath` answers false; `BattleState` then calls
--   `getImage(path, namedPalette(data, "MEWMON"), false)` -- and a false there
--   means REPAINT THIS to the four-shade SGB ramp.
--
-- `MEWMON` is the palette the intro uses while the back pic is up, because
-- wBattleMonSpecies is still 0 when SET_PAL_BATTLE runs. Mew's palette is pink.
-- So a full-colour Lucas is repainted in Mew's colours, which is the report.
--
-- The flag already exists and is already honoured -- Crystal's KRIS and Hoenn's
-- WALLY both set it for exactly this reason. `Sprites.markFormsTrueColor` says
-- it for a generation whose art is in colour by construction.
--
-- Usage: texlua tools/gen4_player_pic_check.lua [platinum/data/generated]

local root = (arg[0] or ""):gsub("[^/\\]*$", "")
if root ~= "" then package.path = root .. "../?.lua;" .. package.path end
package.path = "./?.lua;" .. package.path

local fails, checks = 0, 0
local function ok(cond, fmt, ...)
  checks = checks + 1
  if not cond then
    fails = fails + 1
    io.write("FAIL: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
  end
end
local function section(n) io.write(("\n-- %s\n"):format(n)) end

local Sprites = require("src.pokemon.Sprites")

-- ---------------------------------------------------------------------------
section("1. the real Platinum cache, as it is on disk")
-- ---------------------------------------------------------------------------
local plRoot = arg and arg[1] or "G:/Gen2Recomped/platinum/data/generated"
local chunk = loadfile(plRoot .. "/field.lua")
if not chunk then
  io.write(("  cannot read %s/field.lua\n"):format(plRoot))
  io.write("\n  Pass the generated Platinum data root as the first argument.\n")
  os.exit(2)
end
local okRun, field = pcall(chunk)
ok(okRun and type(field) == "table", "the Platinum field table would not load")
if okRun and type(field) == "table" then
  local forms = field.playerForms
  ok(type(forms) == "table", "the cache carries no playerForms at all")
  if type(forms) == "table" then
    -- WHAT THE CACHE SHIPS, before anything touches it. This is the half of
    -- the bug that is not in any code: the picture is right and the flag is
    -- absent.
    local withBack, preMarked = 0, 0
    for _, form in pairs(forms) do
      if type(form) == "table" and form.back then
        withBack = withBack + 1
        if form.trueColor ~= nil then preMarked = preMarked + 1 end
      end
    end
    io.write(("  %d player form(s) carry a back pic, %d of them state "
              .. "trueColor\n"):format(withBack, preMarked))
    ok(withBack >= 2, "only %d form(s) carry a back pic; Sinnoh has two",
       withBack)
    ok(forms.boy and forms.boy.back
       and forms.boy.back == "assets/generated/gen4/battle/trainer_back/000.png",
       "the boy's back pic is %s, not Platinum's own player back (trbgra class 0, Lucas's winter coat)",
       tostring(forms.boy and forms.boy.back))
    ok(forms.girl and forms.girl.back
       and forms.girl.back == "assets/generated/gen4/battle/trainer_back/001.png",
       "the girl's back pic is %s, not trbgra class 1 (Dawn's winter coat)", tostring(forms.girl and forms.girl.back))

    -- ...AND AFTER THE LIFT.
    local marked = Sprites.markFormsTrueColor(field)
    io.write(("  markFormsTrueColor stamped %d\n"):format(marked))
    ok(marked == withBack - preMarked,
       "%d form(s) were stamped; %d were missing the flag", marked,
       withBack - preMarked)
    for name, form in pairs(forms) do
      if type(form) == "table" and form.back then
        ok(form.trueColor == true,
           "the %s form still has trueColor=%s, so its art is repainted with "
           .. "the SGB palette", tostring(name), tostring(form.trueColor))
      end
    end
    -- IDEMPOTENT: `Data:load` runs again on a mod reload, and a second pass
    -- must stamp nothing rather than report work it did not do.
    local again = Sprites.markFormsTrueColor(field)
    ok(again == 0, "a second pass stamped %d more", again)
    -- `order` is a list of names sharing the table and must not be mistaken
    -- for a form
    ok(type(forms.order) ~= "table" or forms.order.trueColor == nil,
       "the `order` list was stamped as if it were a player form")
  end
end

-- ---------------------------------------------------------------------------
section("2. the flag reaches playerPath, which is the only thing that matters")
-- ---------------------------------------------------------------------------
-- Stamping the record is not the fix; `playerPath`'s SECOND return value is
-- what `BattleState` passes to `getImage`, and false there means repaint.
do
  local data = {
    field = { playerForms = {
      boy = { back = "assets/generated/gen4/battle/trainer_backs_lucas_dp_00.png" },
      girl = { back = "assets/generated/gen4/battle/trainer_backs_dawn_dp_00.png" },
      order = { "boy", "girl" },
    } },
  }
  -- BEFORE: the bug, reproduced from the same call the battle makes
  local path, trueColor = Sprites.playerPath(data, "back",
                                             { kind = "battle", save = {} })
  ok(path and path:find("lucas", 1, true) ~= nil,
     "playerPath answered %s for the back pic", tostring(path))
  ok(trueColor == false,
     "an unstamped form already answers trueColor=%s -- then this check "
     .. "cannot tell the fix from the bug", tostring(trueColor))
  -- AFTER
  Sprites.markFormsTrueColor(data.field)
  local path2, trueColor2 = Sprites.playerPath(data, "back",
                                               { kind = "battle", save = {} })
  ok(path2 == path, "the picture changed as well: %s -> %s", tostring(path),
     tostring(path2))
  ok(trueColor2 == true,
     "playerPath still answers trueColor=%s, so BattleState still repaints "
     .. "Lucas with Mew's palette", tostring(trueColor2))
  -- and the girl, because a save with a gender picks the other record
  local gPath, gTrue = Sprites.playerPath(data, "back",
    { kind = "battle", save = { player = { gender = "girl" } } })
  ok(gPath and gPath:find("dawn", 1, true) ~= nil,
     "a girl save gets %s", tostring(gPath))
  ok(gTrue == true, "the girl's back pic answers trueColor=%s", tostring(gTrue))
end

-- ---------------------------------------------------------------------------
section("3. Kanto and Johto are untouched")
-- ---------------------------------------------------------------------------
-- The Game Boy's back pic IS four-shade art and the SGB recolor is correct for
-- it. A lift that marked everything true-colour would leave RED grey on a
-- colour display, which is the opposite mistake and just as invisible here
-- unless it is checked.
do
  local data = { field = {} }   -- no playerForms: FieldDefaults answers
  local path, trueColor = Sprites.playerPath(data, "back", { kind = "battle" })
  ok(path and path:find("redb", 1, true) ~= nil,
     "the Gen 1 default back pic is %s", tostring(path))
  ok(trueColor == false,
     "Kanto's four-shade back pic now claims to be true-colour, so it never "
     .. "gets its palette and stays grey")
  ok(Sprites.markFormsTrueColor(data.field) == 0,
     "the lift stamped something on a cartridge with no player forms")
  ok(Sprites.markFormsTrueColor(nil) == 0, "the lift raised on a nil field")
  -- a dataset that says false MEANS false
  local said = { playerForms = { boy = { back = "x.png", trueColor = false } } }
  Sprites.markFormsTrueColor(said)
  ok(said.playerForms.boy.trueColor == false,
     "a form that says trueColor=false was overwritten, so a mod shipping "
     .. "four-shade player art cannot say so")
end

-- ---------------------------------------------------------------------------
section("4. and Data does the stamping on a Gen 4 cache")
-- ---------------------------------------------------------------------------
local function slurp(rel)
  local f = io.open(root .. "../" .. rel, "rb") or io.open(rel, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return (s:gsub("\r\n", "\n"))
end
local dataSrc = slurp("src/core/Data.lua")
ok(dataSrc ~= nil, "could not open Data.lua")
if dataSrc then
  ok(dataSrc:find(".markFormsTrueColor(self.field)", 1, true) ~= nil,
     "nothing in Data.lua calls the lift, so the cache is loaded with the "
     .. "flag still absent and the back pic is still repainted")
end

io.write(("\n%d checks, %d failed\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
