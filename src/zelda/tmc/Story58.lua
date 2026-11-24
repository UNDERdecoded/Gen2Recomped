-- Round 58: Mayor Hagen's interact box (src/npc/mayorHagen.c MayorHagen_MakeInteractable, $0806CE5C).  Listed in
-- R37.MODULES (registers the native on load).
--
-- CARTRIDGE BEHAVIOUR: MayorHagen_MakeInteractable (script_Mayor): AddInteractableWhenBigFuser(GetFusionToOffer)
--   and SetInteractableObjectCollision(this, 1, 0, &gUnk_08113F44) -- a box below him (offset and half sizes from
--   the Rect), every direction, so full-size Link talks to him across his desk.  The port only made him talkable
--   (Native's generic <Npc>_MakeInteractable): its reach stopped short of the desk, and the book-3 hint
--   (MIZUKAKI_HINT3_MAYOR) could not be had.
-- The Rect is read from the player's ROM (RomTablesCat "Story58.MAYOR_BOX").
local M = {}
M.A_MAKE_INTERACTABLE = 0x0806CE5C
local BOX = require("src.zelda.tmc.RomTables").t("Story58.MAYOR_BOX") -- gUnk_08113F44 (Rect)
M.BOX = BOX

function M.makeInteractable(f, e)
  e.talkable = true -- AddInteractableWhenBigFuser (the offer: Fusers.onSpawn)
  e.interactBox = { x = BOX.x, y = BOX.y, w = BOX.w, h = BOX.h, dirs = 0 } -- SetInteractableObjectCollision(1, 0, Rect)
end
require("src.zelda.tmc.Native").N[M.A_MAKE_INTERACTABLE] = M.makeInteractable

return M
