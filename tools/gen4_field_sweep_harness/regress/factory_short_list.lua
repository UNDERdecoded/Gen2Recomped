-- The Battle Factory's rental screen must always be leavable.
--
-- SELECT only finished with three picks, so an empty or short rental list (a
-- challenge resumed with nothing on the save) held the player in the screen
-- for good: B only ever un-picks. Found by tools/gen4_field_sweep under a
-- chaos story state (D32R0301).
--
-- Run: python tools/gen4_field_sweep.py --install <cache> --regress

local S = _G.__sweep
local Game = S.Game
local failed = false
local function check(cond, what)
  if not cond then failed = true; print("REGRESS_FAIL factory_short_list: " .. what) end
end

local Screen = require("src.ui.Gen3FactoryScreen")
local Pokemon = require("src.pokemon.Pokemon")
S.enterMap("T01", 15, 25, "down")
S.run(60)
local base = S.stackDepth()

-- empty: it hands back "nothing chosen" at once
local called, result = false, "unset"
Game.stack:push(Screen.new(Game, { mode = "select", mons = {}, onDone = function(r) called, result = true, r end }))
S.run(5)
check(called and result == nil, "an empty offer closes itself with no result")
check(S.stackDepth() == base, "and leaves the stack as it was")

-- two on offer: both can be picked and confirmed
local mons = { Pokemon.new(S.Data, 1, 30), Pokemon.new(S.Data, 4, 30) }
called, result = false, nil
Game.stack:push(Screen.new(Game, { mode = "select", mons = mons, onDone = function(r) called, result = true, r end }))
S.run(3)
S.press("a"); S.run(3)
S.press("down"); S.run(3)
S.press("a"); S.run(3)
for _ = 1, 60 do S.press("a"); S.run(8); if called then break end end
check(called and type(result) == "table" and result[1] == 1 and result[2] == 2,
  "two picks on a two-Pokemon offer finish the screen")

print(failed and "REGRESS_FAIL factory_short_list" or "REGRESS_OK factory_short_list")
