-- Parity test (#96): blackouts must not play the Dig/Teleport EnterMapAnim.
--
-- pret HandleBlackOut fades to black and SpecialEnterMap's without setting
-- BIT_FLY_WARP / BIT_DUNGEON_WARP, so EnterMap skips EnterMapAnim.  Dig,
-- Teleport and Escape Rope go through HandleFlyWarpOrDungeonWarp and do
-- spin.  warpToHealPoint used to always set arriveWarp="teleport", so a
-- loss (notably Elite Four -> Indigo lobby) rematerialized with the
-- teleport spin instead of a plain whiteout warp.
-- Self-contained; run via `luajit tests/parity_blackout_warp.lua`.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local Data = require("src.core.Data")
if not (Data.maps and Data.maps.PALLET_TOWN) then Data:load() end
local S = require("tests.harness").suite("parity blackout warp")
local check, eq = S.check, S.eq

require("src.render.Font").load(Data)
local Game       = require("src.core.Game")
local Input      = require("src.core.Input")
local StateStack = require("src.core.StateStack")
local Renderer   = require("src.render.Renderer")
local SaveData   = require("src.core.SaveData")
local Pokemon    = require("src.pokemon.Pokemon")
local OW         = require("src.world.OverworldController")

Game.data = Data
Game.input = Input; Input:init()
Game.renderer = Renderer; Renderer:init()
Game.stack = StateStack; StateStack:init()
Game.save = SaveData.newGame()
Game.save.party = { Pokemon.new(Data, "SQUIRTLE", 5) }
Game.save.party[1].hp = 0
Game.save.lastHeal = { map = "INDIGO_PLATEAU_LOBBY", x = 7, y = 6,
                       outdoor = { id = "INDIGO_PLATEAU", x = 9, y = 5 } }

Game.stack:push(OW, "LORELEIS_ROOM", 4, 5, "up")
local ow = Game.stack:top()
Game.overworld = ow

local captured
local realStart = ow.startWarpTo
ow.startWarpTo = function(self, mapId, x, y, facing, onDone, opts)
  captured = self.arriveWarp
  -- skip Transition; only the arrive flag matters here
  self.arriveWarp = nil
  self.transitioning = false
end

-- Battle blackout (afterBattle -> warpToHealPoint): no EnterMapAnim.
captured = "sentinel"
ow:afterBattle("lose", { oppClass = "OPP_LORELEI" })
eq(captured, nil,
   "Elite Four blackout does not set arriveWarp=teleport (#96)")

-- Poison / field blackout path uses the same helper with no opts.
captured = "sentinel"
ow.arriveWarp = nil
ow:warpToHealPoint()
eq(captured, nil, "plain warpToHealPoint has no teleport arrive FX")

-- Dig / Teleport / Escape Rope keep EnterMapAnim.
captured = "sentinel"
ow:warpToHealPoint(nil, { arrive = "teleport" })
eq(captured, "teleport",
   "escape warps still request EnterMapAnim on arrival")

ow.startWarpTo = realStart
S.finish()
