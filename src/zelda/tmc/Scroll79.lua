-- Round 79: the collision layer across a room scroll.
--
-- CARTRIDGE BEHAVIOUR: walking off a room's edge into the next room of the
-- area (playerUtils.c sub_0807BD14 -> scrollAction 2, scroll.c Scroll2*) only
-- moves the camera and Link (x +- 0.25, y +- 0.375 a frame); it never calls
-- InitializePlayer (gameUtils.c, collisionLayer = player_status.layer), so
-- gPlayerEntity.base.collisionLayer is kept.  The port's enterRoom starts a
-- room change on layer 1 (right for warps without a layer); a scroll put Link
-- on the bottom map: the Palace of Winds' grate corridor $70:2C -> $70:2D
-- (layer 2) left him in the door's wall on layer 1, unable to go on or back.
-- Here the layer Link had before the scroll is put back.  A mine cart ride
-- keeps its own (Minecart.onEnterRoom) and warps (no `scroll`) are untouched.
local S = {}

function S.keep(exit, layerBefore, cartRide)
  if not exit or not exit.scroll or cartRide then return nil end
  if layerBefore ~= 1 and layerBefore ~= 2 and layerBefore ~= 3 then return nil end
  return layerBefore
end

function S.after(f, exit, layerBefore)
  local l = S.keep(exit, layerBefore, f.cartRide)
  if l and f.player then f.player.layer = l end
  return l
end

return S
