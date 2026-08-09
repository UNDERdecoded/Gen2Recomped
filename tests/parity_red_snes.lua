-- Parity test: Red's bedroom SNES (#135).
--
-- pokered hidden_events.asm REDS_HOUSE_2F:
--   hidden_event 3, 5, PrintRedSNESText, ANY_FACING
-- PrintRedSNESText shows _RedBedroomSNESText ("{PLAYER} is playing the SNES!").
--
-- Self-contained; run via `luajit tests/parity_red_snes.lua`.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local Data = require("src.core.Data")
if not (Data.maps and Data.maps.REDS_HOUSE_2F) then Data:load() end
local Font = require("src.render.Font")
if not pcall(Font.encode, "A") then Font.load(Data) end
require("data.scripts.init")
local MapScripts = require("src.script.MapScripts")
local S = require("tests.harness").suite("parity red snes")
local check, eq = S.check, S.eq

check(Data.text._RedBedroomSNESText ~= nil, "_RedBedroomSNESText is extracted")
check(Data.text._RedBedroomSNESText:find("SNES", 1, true),
      "_RedBedroomSNESText mentions the SNES")

local hooks = MapScripts.get("REDS_HOUSE_2F")
check(hooks and type(hooks.onInteract) == "function",
      "REDS_HOUSE_2F registers onInteract for the SNES")

-- stub just enough of the overworld/game stack to exercise the hook
local pushed
local game = {
  data = Data,
  save = { player = { name = "RED", rival = "BLUE" } },
  stack = {
    push = function(_, state) pushed = state end,
  },
}
local ow = { player = { facing = "up" } }

eq(hooks.onInteract(game, ow, 0, 1), false,
   "bedroom PC tile is not claimed by the SNES hook")
eq(hooks.onInteract(game, ow, 3, 6), false,
   "spawn tile is not claimed by the SNES hook")

pushed = nil
eq(hooks.onInteract(game, ow, 3, 5), true,
   "SNES at (3,5) consumes the interact")
check(pushed ~= nil and pushed.pages ~= nil, "SNES interact pushes a TextBox")
local flat = table.concat(pushed.pages[1] or {}, "\n")
check(flat:find("SNES", 1, true) and flat:find("RED", 1, true),
      "SNES TextBox shows the bedroom SNES line with the player name")

-- ANY_FACING: facing is irrelevant once the faced cell is (3,5)
ow.player.facing = "left"
pushed = nil
eq(hooks.onInteract(game, ow, 3, 5), true,
   "SNES still fires when the player faces it from the side")

S.finish()
