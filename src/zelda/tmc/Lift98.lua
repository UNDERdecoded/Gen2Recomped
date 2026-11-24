-- Bug round bug98 (user report: "Lifting grass in Zelda minish cap gives me a sword that says the power of earth and
-- fire elements infused your blade"): a bush / grass / rock / sign lifted from the map broke as a POT when it landed.
--
-- CAUSE: a filter-6 tile entry (gUnk_080047F6) lifts as {obj = byte 2, form = byte 3}: for bushes, grass, rocks and
-- signs byte 2 is SPECIAL_FX ($0F) and byte 3 the FX type (3 = FX_BUSH, 4, $2D ...).  The landing went
-- Objects:breakThrown -> (not OBJECT_BUSH) -> Objects:shatter(e, form), i.e. BreakPot, which leaves a GROUND_ITEM of
-- item "form": FX_BUSH 3 became ITEM_RED_SWORD 3 (the Earth + Fire infusion's text), 4 the blue sword, and so on.
-- bugs95's Carry95 lands an object that carries its `held95` record the cartridge's way; this module makes the same
-- rule hold for every SPECIAL_FX object that lands without one (an older carry, a drop, a hook that rebuilt the
-- record), so a tile object can never go through BreakPot.
--
-- CARTRIDGE BEHAVIOUR (zeldaret/tmc src/playerItem/playerItemHeldObject.c, SubAction2 / sub_080ADC84): when the held
-- object lands, type2 $0F -> CreateFx(this, timer, $80): the FX of type `timer` with type2 $80, whose init picks the
-- variant (FX_BUSH / FX_GRASS_CUT: Random() & 3), plays gUnk_0811F960[type].sfx and rolls its drop table
-- (CreateRandomItemDrop); another type2 -> CreateObjectWithParent(type2, timer); $FF -> nothing.  BreakPot (pot.c) is
-- only POT's own break.  No item is ever made from the FX type.
--
-- Wraps Objects.breakThrown / dropCarried (guard Objects.lift98Installed); listed in R27A.MODULES.  No game data here.
local M = {}

M.SPECIAL_FX = 0x0F

-- the held-object record a SPECIAL_FX object lands with (Carry95.land reads type2 / timer only)
function M.record(e)
  return { type2 = M.SPECIAL_FX, timer = e.form or 0 }
end

-- true when e is a lifted tile object (SPECIAL_FX) with no held95 record
function M.bare(e)
  return e ~= nil and e.held95 == nil and (e.id == M.SPECIAL_FX or e.obj == M.SPECIAL_FX)
end

function M.install()
  local Objects = require("src.zelda.tmc.Objects")
  if Objects.lift98Installed then return end
  Objects.lift98Installed = true
  local Carry95 = require("src.zelda.tmc.Carry95")
  local break0, drop0 = Objects.breakThrown, Objects.dropCarried
  function Objects:breakThrown(e)
    if M.bare(e) then return Carry95.land(self, { x = e.x, y = e.y, held95 = M.record(e) }) end
    return break0(self, e)
  end
  function Objects:dropCarried(p)
    local c = p and p.carried
    if c and M.bare(c) and not c.bomb and not c.hook then
      p.carried = nil
      return Carry95.land(self, { x = p.x, y = p.y, held95 = M.record(c) })
    end
    return drop0(self, p)
  end
end

M.install()

return M
