-- T4: constants.bagSize controls the bag through the public mod API while
-- vanilla and existing-save behavior remain unchanged.

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Bag = require("src.inventory.Bag")

local CAPACITY_MOD = {
  ["mods/fix_small_bag/manifest.json"] = [[{
    "id": "fix_small_bag",
    "name": "Fixture Small Bag",
    "version": "1.0.0",
    "entry": "main.lua",
    "api": 2
  }]],
  ["mods/fix_small_bag/main.lua"] = [[
    local mod = ...
    mod.content.constants:patch("bagSize", 2)
  ]],
}

-- No-mod parity: the new lookup keeps the cartridge's 20-slot limit.
do
  local data = T.fixtures.fresh()
  local run = T.sdk.loadNone({ data = data })
  T.eq(#run.errors, 0, "the no-mod baseline loads cleanly")
  T.eq(Bag.capacity(data), 20, "the vanilla bag still has 20 slots")
  T.eq(Bag.capacity({}), 20, "a stale dataset without bagSize falls back to 20")
  run.release()
end

-- The public constants registry changes both the reported and enforced cap.
do
  local data = T.fixtures.fresh()
  local run = T.sdk.loadMods({ "mods/fix_small_bag" },
    { data = data, fs = T.sdk.memfs(CAPACITY_MOD) })
  T.eq(#run.errors, 0, "the capacity mod loads cleanly")
  T.eq(Bag.capacity(data), 2, "Bag.capacity reads merged constants.bagSize")

  local save = { inventory = {} }
  T.check(Bag.add(save, "FIX_POTION", 1, data), "the first item fits")
  T.check(Bag.add(save, "FIX_BALL", 1, data), "the second item fits")
  T.check(not Bag.add(save, "FIX_TM", 1, data),
    "a new item is refused at the modded limit")
  T.eq(Bag.slots(save), 2, "a refused add does not change the bag")
  run.release()
end

-- Saves are dictionaries, not fixed arrays: lowering the active cap never
-- truncates an older or modded save. Existing stacks remain usable while a
-- new item waits until the player makes enough room.
do
  local data = T.fixtures.fresh()
  data.constants.bagSize = 1
  local save = {
    inventory = { FIX_POTION = 1, FIX_BALL = 1 },
    bagOrder = { "FIX_POTION", "FIX_BALL" },
  }
  T.eq(Bag.slots(save), 2, "an over-cap save keeps all existing slots")
  T.check(Bag.add(save, "FIX_POTION", 1, data),
    "an over-cap save can still add to an existing stack")
  T.eq(save.inventory.FIX_POTION, 2, "the existing stack is updated")
  T.check(not Bag.add(save, "FIX_TM", 1, data),
    "an over-cap save cannot add another item kind")
  T.eq(Bag.slots(save), 2, "the compatibility path never drops items")
end

T.finish("bag_capacity")
