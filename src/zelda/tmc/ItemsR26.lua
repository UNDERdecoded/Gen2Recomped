-- Round 26 (team A): the items of round 26, one dispatcher so the shared
-- files carry a single anchored line per hook.
--
--   Crenel.useItem   -> ItemsR26.use(player, item, button, input)
--   Field:giveItem   -> ItemsR26.giveItem(f, item, param)   (GiveItem's
--                       gItemMetaData cases that touch other items/stats)
--   Dungeon:checkFall-> ItemsR26.water(dungeon, p, act)      (deep water with
--                       the Flippers: swimming instead of the fall)
--   Player:update    -> ItemsR26.frame(p, input)             (per-frame states
--                       a module keeps outside "ext": the Boots' dash, the
--                       Cape's jump, swimming)
--
-- Each module in ItemsR26.MODULES may export use / giveItem / water / frame /
-- draw with the same signatures; the first that returns true wins.  A module
-- that is missing is skipped (its items do nothing, as before round 26).
local M = {}

M.MODULES = {
  "src.zelda.tmc.ItemBoomerang", -- ITEM_BOOMERANG $0B / MAGIC $0C (playerItemBoomerang.c)
  "src.zelda.tmc.ItemBow",       -- ITEM_BOW $09 / LIGHT_ARROW $0A (itemBow.c, playerItemBow.c)
  "src.zelda.tmc.ItemCape",      -- ITEM_ROCS_CAPE $14 (itemRocsCape.c, player.c DoJump)
  "src.zelda.tmc.ItemBoots",     -- ITEM_PEGASUS_BOOTS $15 (itemPegasusBoots.c, playerItemDashSword.c)
  "src.zelda.tmc.ItemMitts",     -- ITEM_MOLE_MITTS $13 (itemMoleMitts.c)
  "src.zelda.tmc.ItemLantern",   -- ITEM_LANTERN_OFF/ON $0F/$10 (itemLantern.c, playerItemLantern.c)
  "src.zelda.tmc.ItemOcarina",   -- ITEM_OCARINA $17 (itemOcarina.c) + the wind-crest warp
  "src.zelda.tmc.Swim",          -- ITEM_FLIPPERS $46: PlayerSwimming
  "src.zelda.tmc.FourSword",     -- the split charge and the Link clones (before SwordSkills: it reads p.ss, never consumes)
  "src.zelda.tmc.SwordSkills",   -- the sword's charge, spin and the scroll techniques
}

local loaded
function M.mods()
  if loaded then return loaded end
  loaded = {}
  for _, n in ipairs(M.MODULES) do
    local ok, m = pcall(require, n)
    if ok and type(m) == "table" then loaded[#loaded + 1] = m
    elseif not ok and not tostring(m):find("not found", 1, true) then error(m) end
  end
  return loaded
end
function M._setModules(list) loaded = list end

local function each(fn, ...)
  for _, m in ipairs(M.mods()) do
    local f = m[fn]
    if f then local r = f(...) if r then return r end end
  end
  return nil
end

function M.use(p, item, button, input) return each("use", p, item, button, input) end
function M.giveItem(f, item, param) return each("giveItem", f, item, param) end
function M.water(dungeon, p, act) return each("water", dungeon, p, act) end
function M.frame(p, input) return each("frame", p, input) end
function M.draw(p, x, y) return each("draw", p, x, y) end

return M
