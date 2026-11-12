-- Round 11: pushable block tiles (ACT_TILE_112) and the PUSHED_BLOCK object.
--
-- CARTRIDGE BEHAVIOUR (src/beanstalkSubtask.c ACT_TILE_112, sub_0801A9F0 /
-- sub_0801AA58; src/object/blockPushed.c):
--   * Tile types $360-$364 are blocks Link can push while he leans on them
--     in his push animation: $360 any way, $361 north only, $364 east only,
--     $362 south only, $363 west only.
--   * The block moves only if the tile beyond has collision 0 or $20-$3F.
--     The tile it leaves becomes TILE_TYPE_32 (vertical push) or 33
--     (horizontal), a PUSHED_BLOCK object (type 0) slides the block at
--     speed $80 for 32 frames (SFX_10F), pushing Link out of its hitbox
--     (gUnk_0811F62C: 5 x 4) every frame, then sets tile $365 (a block that
--     no longer moves) where it stops.
-- Round 12: the push starts on a frame where Link's ANIM_PUSH keyframe has
-- flag bit 0 (sub_0801A4F8, PushAnim.lua); before round 12 it waited 16
-- frames.  Link does not play PLAYER_PUSH's own animation while it slides.
local bit = require("bit")
local band = bit.band

local PB = {}

local OBJ_PUSHED_BLOCK = 0x07
local DIRS = { [0x360] = "any", [0x361] = 0, [0x364] = 2, [0x362] = 4, [0x363] = 6 }
local SFX_10F = 0x10F
local BOX = { x = 0, y = 0, w = 5, h = 4 }

local function update(d, e)
  local f = d.field
  e.x = e.x + e.mdx * 0.5
  e.y = e.y + e.mdy * 0.5
  require("src.zelda.tmc.Hitboxes").pushOut(f, e, BOX)
  e.timer = e.timer - 1
  if e.timer <= 0 then
    f:objects():setTileType(e.layer, e.dtx, e.dty, 0x365)
    e.deleted = true
  end
end

-- called every frame from Dungeon:update with the pad
function PB.check(d, input)
  local f = d.field
  local p = f.player
  if p.state ~= "normal" or p.minish or (p.z or 0) > 0 then p.blockPush = 0 return end
  local s = p.animationState
  local key = ({ [0] = "up", [2] = "right", [4] = "down", [6] = "left" })[s]
  if not (key and input.down(key)) then p.blockPush = 0 return end
  local fx, fy = p:frontPoint(6)
  local tx, ty = math.floor(fx / 16), math.floor(fy / 16)
  local tt = f.room:tileType(p.layer or 1, tx, ty)
  local allow = tt and DIRS[tt]
  if not allow or (allow ~= "any" and allow ~= s) then p.blockPush = 0 return end
  p.blockPush = (p.blockPush or 0) + 1
  if p.pushFrame == nil then if p.blockPush < 16 then return end -- no push animation yet
  elseif not p.pushFrame then return end
  p.blockPush = 0
  local dx = (s == 2 and 1) or (s == 6 and -1) or 0
  local dy = (s == 4 and 1) or (s == 0 and -1) or 0
  local r = f.room
  local c = r.coll and r.coll[(p.layer == 2) and 2 or 1]
  local v = c and c[(ty + dy) * r.tw + (tx + dx)] or 0xFF
  if not (v == 0 or (v >= 0x20 and v < 0x40)) then return end
  f:objects():setTileType(p.layer or 1, tx, ty, (dx ~= 0) and 0x21 or 0x20)
  local e = { kind = 6, id = OBJ_PUSHED_BLOCK, form = 0, x = tx * 16 + 8, y = ty * 16 + 8, z = 0, layer = p.layer or 1,
              mdx = dx, mdy = dy, timer = 32, dtx = tx + dx, dty = ty + dy, extUpdate = update, pushedBlock = true }
  local def = f:objects():def(OBJ_PUSHED_BLOCK, 0)
  if def then f:objects():dress(e, def, 0) end
  f.entities[#f.entities + 1] = e
  d:track(e)
  f:sound(SFX_10F)
end

return PB
