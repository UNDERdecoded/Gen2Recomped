-- Round 50: a held button's release delay and the timed small chests.
--
-- CARTRIDGE BEHAVIOUR:
--   * button.c Button_Action3 / Action4 (type 1, the held button): when
--     nothing presses it any more the flag is not cleared at once -- action
--     4 waits 24 frames (Link carrying an object, heldObject 2, or pushing:
--     gPlayerState.field_0x35 bit 7 clear) or 8 frames (otherwise:
--     field_0x35 is $FF while Link is not pushing, sub_08078FB0); pressed
--     again meanwhile -> back to action 3.  Then ClearFlag, TILE_TYPE_119,
--     SFX_BUTTON_PRESS.
--   * chestSpawner.c ChestSpawner_Type0Action2 / Action3 (types 1 and 7):
--     the chest that appeared when its flag was set stays only while the
--     flag stays set; once cleared, unk_72 = timer * 60 frames (set when it
--     appeared; 0 when the flag was already set at init) count down, then
--     action 1 again: RestorePrevTileEntity (the tile before the chest),
--     CreateDeathFx.  An opened chest (TILE_TYPE_116 under it) is left
--     alone.  (Before: the port's chest stayed for good -- FoW $18:01's
--     button chest could be opened after stepping off the button.)
-- SIMPLIFIED: "pushing" is the port's push animation state (PushAnim) or a
--   carried object; the death FX is the port's generic FX at the chest.
local M = {}

local TT_OPEN = 0x74 -- TILE_TYPE_116 (an opened small chest)
local SFX_SECRET = 0x72
M.TT_OPEN = TT_OPEN

-- the delay before a held button lets go (Button_Action3's timer)
function M.releaseDelay(p)
  if not p then return 8 end
  if p.state == "carry" or p.carried then return 24 end
  local ok, pa = pcall(function() return require("src.zelda.tmc.PushAnim").anim(p) end)
  if ok and pa then return 24 end
  return 8
end

-- Dungeon:updateButton for a held (type 1) button; returns nothing
function M.held(d, e, on, setPressed, setReleased)
  if on then
    e.relT = nil
    if not e.pressed then setPressed() end
    return
  end
  if not e.pressed then return end
  if not e.relT then e.relT = M.releaseDelay(d.field.player) return end
  e.relT = e.relT - 1
  if e.relT > 0 then return end
  e.relT = nil
  setReleased()
end

local function layerName(e) return (e.layer == 2) and "top" or "bottom" end

-- remember the tile under a small chest before the chest tile is written
function M.remember(d, e)
  local r = d.field.room
  local m = r.maps and r.maps[layerName(e)]
  if m and e.tx then e.prevMt = m[e.ty * r.tw + e.tx] end
end

-- called when a small chest of type 1 / 7 appears (Action2)
function M.appeared(d, e)
  e.unk72 = (e.timer0 or 0) * 60
end

-- ChestSpawner_Type0Action3 for types 1 / 7; true while it handled the chest
function M.update(d, e)
  if not (e.small and e.shown and (e.form == 1 or e.form == 7)) then return nil end
  local f = d.field
  local r = f.room
  if r:tileType(e.layer == 2 and 2 or 1, e.tx, e.ty) == TT_OPEN then e.timedDone = true return true end
  if e.timedDone then return true end
  if d:check(e.flag) then return true end
  if (e.unk72 or 0) ~= 0 then e.unk72 = e.unk72 - 1 return true end
  -- back to action 1: the old tile, the death FX
  e.shown = false
  if e.prevMt then r:setTile(e.layer == 2 and 2 or 1, e.tx, e.ty, e.prevMt) end
  if f.addFx then f:addFx(e.x, e.y, 0x0F, 0x02) end
  return true
end

M.SFX_SECRET = SFX_SECRET
return M
