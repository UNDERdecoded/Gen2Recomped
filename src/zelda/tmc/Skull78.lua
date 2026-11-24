-- Round 78: the FLYING_SKULL's drop when it breaks, hooked from EnemyFoW's skullBreak.
--
-- CARTRIDGE BEHAVIOUR (ported):
--   * flyingSkull.c sub_0803A0E0 (every way a skull breaks: thrown and landed, hit while carried, flown into a wall,
--     the flip's fall) is CreateFx(super, FX_BONE, sub_0808288C(super, super->type2, 0, 0)); DeleteThisEntity.
--   * pot.c sub_0808288C(this, form, ..): form $FF -> 0 (nothing); form 0 -> $80 (the effect's type2 $80: the random
--     drop of FX_BONE's row of gUnk_0811F960, as a pot's FX_POT_SHATTER); any other form -> a GROUND_ITEM of that
--     item right there (timer 0).
--   The port made the bone effect only: a broken skull never dropped anything (the Palace of Winds' skull rooms are
--   where a player heals).
--   type2 is the room entry's paramB low byte (Enemies.lua spawnB); the drop table row comes from the player's ROM
--   (manifest.drops.fxTable, Drops.fxDrop), as the pots' does.
local bit = require("bit")
local band = bit.band

local M = {}

M.FX_BONE = 0x3C

function M.form(e)
  if e.skullType2 ~= nil then return e.skullType2 end
  return band(e.spawnB or 0, 0xFF)
end

-- sub_0808288C for a skull; returns what was made ("random" / an item id / nil)
function M.drop(f, e)
  if not f or not e or e._skull78 then return nil end
  e._skull78 = true
  local form = M.form(e)
  if form == 0xFF then return nil end
  if form == 0 then
    local okD, Drops = pcall(require, "src.zelda.tmc.Drops")
    if okD and type(Drops) == "table" and Drops.fxDrop and f.assets then Drops.fxDrop(f, e, M.FX_BONE) end
    return "random"
  end
  local O = f._objects or (f.objects and f:objects())
  if O and O.groundItem then O:groundItem(form, 0, e.x, e.y, {}) end
  return form
end

return M
