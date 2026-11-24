-- Round 86: cracked floor (ACT_TILE_8 -> SURFACE_7, src/player.c SurfaceAction_7) and CRACKING_GROUND
-- (src/object/crackingGround.c).  An R27A module: it wraps Dungeon.checkFall when it is required.
--
-- CARTRIDGE BEHAVIOUR (ported):
--   * GetSurfaceCalcType (src/playerUtils.c): gPlayerState.surfacePositionSameTimer counts the frames Link's
--     (x, y) stays on one tile position with one tile type (0 when either changes; it stops at $FF);
--     sub_080741C4 (jumping with jump_status & 7 not 3, or z not 0) clears it.
--   * SurfaceAction_7: not jumping / off the ground, not Minish, and the timer exactly 15 ->
--     CreateObjectWithParent(Link, CRACKING_GROUND): the object snaps to Link's tile.
--   * CrackingGround: timer 20; each frame `if (timer-- == 0)` -> sub_0807B7D8(TILE_TYPE $35, its tile, its
--     layer) (the tile becomes a pit), FX_FALL_DOWN, SFX_126, gone (21 frames after it was made).
--   The new tile's act / collision come from the room's tile-type tables (read from the ROM at import), so a
--   Link still standing there falls through the dungeon's pit code.
-- SIMPLIFIED: the timer is counted in the port's player states that run Dungeon.checkFall (normal, gust,
--   shield); the cracking object has no sprite of its own (the cartridge's draws nothing either).
local M = {}

M.ACT_CRACKED = 0x08
M.TILE_PIT = 0x35
M.CRACK_AT = 15
M.CRACK_TIMER = 20
M.SFX_126 = 0x126
M.SPECIAL_FX, M.FX_FALL_DOWN = 0x0F, 0x00

local Dungeon = require("src.zelda.tmc.Dungeon")

-- one frame of GetSurfaceCalcType's timer + SurfaceAction_7 for the player; returns the tile it cracked (or nil)
function M.playerFrame(d, p)
  local f = d.field
  local r = f.room
  if (p.z or 0) ~= 0 or p.jumping then p.crackSame, p.crackPos = 0, nil return nil end -- sub_080741C4
  local layer = p.layer == 2 and 2 or 1
  local tx, ty = math.floor(p.x / 16), math.floor(p.y / 16)
  local pos = ty * 4096 + tx
  local tt = r:tileType(layer, tx, ty)
  if pos ~= p.crackPos or tt ~= p.crackType then p.crackPos, p.crackType, p.crackSame = pos, tt, 0 end
  if (p.crackSame or 0) ~= 0xFF then p.crackSame = (p.crackSame or 0) + 1 end
  if p.minish or p.crackSame ~= M.CRACK_AT then return nil end
  if d:actAt(p.x, p.y, layer) ~= M.ACT_CRACKED then return nil end
  f.cracking86 = f.cracking86 or {}
  local c = { tx = tx, ty = ty, layer = layer, timer = M.CRACK_TIMER, room = r }
  f.cracking86[#f.cracking86 + 1] = c
  return c
end

-- one frame of every CRACKING_GROUND in the room
function M.objectsFrame(d)
  local f = d.field
  local list = f.cracking86
  if not list then return end
  for i = #list, 1, -1 do
    local c = list[i]
    if c.room ~= f.room then table.remove(list, i)
    else
      local t = c.timer
      c.timer = t - 1
      if t == 0 then
        f:objects():setTileType(c.layer, c.tx, c.ty, M.TILE_PIT)
        f:addFx(c.tx * 16 + 8, c.ty * 16 + 8, M.SPECIAL_FX, M.FX_FALL_DOWN)
        f:sound(M.SFX_126)
        table.remove(list, i)
      end
    end
  end
end

if not Dungeon._cracked86 then
  Dungeon._cracked86 = true
  local checkFall = Dungeon.checkFall
  Dungeon.checkFall = function(self, ...)
    local p = self.field and self.field.player
    if p then
      if p.state == "normal" or p.state == "gust" or p.state == "shield" then M.playerFrame(self, p)
      else p.crackSame, p.crackPos = 0, nil end
    end
    M.objectsFrame(self)
    local safe0 = self.safe
    checkFall(self, ...)
    -- sub_0807A8D8: the path memory only takes tiles whose flags have bit $20; a cracked tile's have none, so
    -- RespawnPlayer never puts Link back on one (it may be a pit by then)
    local s = self.safe
    if s and s ~= safe0 and self.field and self.field.room and self:actAt(s.x, s.y, s.layer or 1) == M.ACT_CRACKED then
      local r = self.field.room
      local tt = r:tileType(s.layer == 2 and 2 or 1, math.floor(s.x / 16), math.floor(s.y / 16))
      local fl = require("src.zelda.tmc.Respawn85").flagsOf(self.field, tt)
      if require("bit").band(fl, 0x20) == 0 then self.safe = safe0 end
    end
  end
end

return M
