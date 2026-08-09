-- Parity test: the Pokedex entry page actually holds its front pic.
--
-- The pic load read
--
--   local ok, img = path and pcall(love.graphics.newImage, path)
--
-- which looks like a guarded pcall but is not one: `path and pcall(...)` is
-- an expression, so Lua adjusts it to a single value and `img` is always
-- nil.  Every dex page drew its name, kind, height and description with an
-- empty pic box -- the starter previews in Oak's lab and every entry opened
-- from the Pokedex list alike (#307).
--
-- The guard has to be a statement for pcall's second return to survive.
-- This test would also catch a genuinely missing or unreadable sprite file,
-- which is the other way the box comes up empty.
--
-- Self-contained; run via `luajit tests/parity_dex_pic.lua`.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local S = require("tests.harness").suite("parity dex pic")
local check = S.check

local Data = require("src.core.Data")
if not Data.maps then Data:load() end
local Font = require("src.render.Font")
Font.load(Data)

local DexEntryMenu = require("src.ui.DexEntryMenu")
local SaveData = require("src.core.SaveData")
local Sprites = require("src.pokemon.Sprites")
local Sound = require("src.core.Sound")

Sound.playCry = function() end -- the page cries on open; stay silent here

local game = { data = Data, save = SaveData.newGame(),
               stack = { push = function() end, pop = function() end,
                         top = function() end } }

-- the three starters (the lab preview path, StarterDex/forceOwned) plus a
-- plain list entry, so a regression in either caller shows up here
local CASES = {
  { "BULBASAUR", { species = "BULBASAUR", forceOwned = true } },
  { "CHARMANDER", { species = "CHARMANDER", forceOwned = true } },
  { "SQUIRTLE", { species = "SQUIRTLE", forceOwned = true } },
  { "PIDGEY", "PIDGEY" },
}
for _, case in ipairs(CASES) do
  local species, arg = case[1], case[2]
  local path = Sprites.path(Data, species, "front", { kind = "dex" })
  check(type(path) == "string" and path ~= "",
        species .. " resolves a front pic path")
  local page = DexEntryMenu.new(game, arg)
  check(page.sprite ~= nil, species .. " dex page holds its pic")
end

S.finish()
