-- Parity test: all three fishing rods are refused while surfing (#533).
--
-- pokered's FishingInit (engine/items/item_effects.asm) reads
-- wWalkBikeSurfState after IsNextTileShoreOrWater passes, and refuses
-- with carry set when it equals 2 (surfing). Every ItemUseXRod entry does
-- `jp c, ItemUseNotTime` on that carry, so a surfing player gets the same
-- "OAK: %s! This isn't the time to use that!" text used for the
-- mid-battle refusal, and the rod is never consumed. The port's ow.player
-- surf flag was never checked, so BagMenu's isWaterCell check alone let a
-- surfing player fish (the faced cell while surfing is always water).
--
-- Self-contained; run via `luajit tests/parity_surf_rod_refusal.lua`.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local S = require("tests.harness").suite("parity surf rod refusal")
local check, eq = S.check, S.eq

local Data = require("src.core.Data")
Data:load()

local ItemEffects = require("src.inventory.ItemEffects")
local save = require("src.core.SaveData").newGame()

for _, rod in ipairs({ "OLD_ROD", "GOOD_ROD", "SUPER_ROD" }) do
  -- surfing: refused even though ow/player exists and the faced cell
  -- would otherwise be fishable water
  local surfingOw = { player = { surfing = true } }
  local result, msgs = ItemEffects.use(Data, save, rod, nil, false, nil, surfingOw)
  eq(result, "failed", rod .. " is refused while surfing")
  check(msgs and msgs[1] and msgs[1]:find("isn't the", 1, true) ~= nil,
        rod .. " surfing refusal uses the OAK 'not the time' text")
  eq(save.inventory[rod], nil, rod .. " is not consumed while surfing")

  -- not surfing: still allowed to fish
  local groundOw = { player = { surfing = false } }
  local r2 = ItemEffects.use(Data, save, rod, nil, false, nil, groundOw)
  eq(r2, "fish", rod .. " still fishes normally when not surfing")

  -- no overworld handle at all (e.g. called from a context without ow):
  -- must not error, and must not silently allow fishing that a surfing
  -- player would be refused
  local r3 = ItemEffects.use(Data, save, rod, nil, false, nil, nil)
  eq(r3, "fish", rod .. " with no ow handle falls through to fish (no surf info available)")
end

S.finish()
