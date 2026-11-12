-- Round 11: falling into a hole (player.c PlayerFall).
--
-- CARTRIDGE BEHAVIOUR
--   * PlayerFallInit: SnapToTile (the tile's centre), PL_BUSY | PL_DROWNING,
--     ANIM_FALL ($1B8; Minish ANIM_FALL_MINISH $1BA, no cap
--     ANIM_FALL_NOCAP $458), collision off, items put away, SFX_PLY_VO7 and
--     SFX_FALL_HOLE.
--   * PlayerFallUpdate: the animation plays; when it is done (ANIM_DONE)
--     Link respawns at his last safe spot (RespawnPlayer), iframes 32,
--     ModHealth(-kFallDamage) (2 = a quarter heart).
--   * The Zelda follower (zeldaFollower.c sub_08068318) keeps pushing
--     Link's position into her history every frame while his framestate
--     is FALL ($0A), and when it leaves FALL she is put on Link and her
--     history refilled (sub_08068578).
local F = {}

local ANIM_FALL, ANIM_FALL_MINISH, ANIM_FALL_NOCAP = 0x1B8, 0x1BA, 0x458
local SFX_PLY_VO7, SFX_FALL_HOLE = 0x7B, 0x85
local K_FALL_DAMAGE = 2

local function update(p, input)
  p.anim:update(1)
  if p.anim.done and p.fallExit and (p.field.save.stats.health or 0) > 0 then
    -- round 13: PL_PIT_IS_EXIT (Holes.lua): no respawn; Link is hidden and
    -- DoHoleTransition takes him to the room below
    local f = p.field
    local ex = p.fallExit
    p.fallExit = nil
    p.state = "normal"
    p.extUpdate = nil
    p.falling = nil
    p:setAnim(p:animFor("idle"), true)
    f:startTransition(ex)
    return
  end
  if p.anim.done then
    local f = p.field
    local d = f:dungeon()
    local st = d.safe or f.entry
    p.x, p.y = st.x, st.y
    p.state = "normal"
    p.extUpdate = nil
    p.falling = nil
    p.invuln = 32
    p:setAnim(p:animFor("idle"), true)
    f:modStat("health", -K_FALL_DAMAGE)
    f.playerRespawned = true -- the Zelda follower re-joins (ZeldaFollower.lua)
  end
end

-- PlayerFallInit; returns true when the fall started
function F.start(d, p, exit)
  local f = d.field
  p.fallExit = exit -- round 13: a HOLE_MANAGER's pit (Holes.lua)
  p.x = math.floor(p.x / 16) * 16 + 8
  p.y = math.floor(p.y / 16) * 16 + 8
  p.state = "ext"
  p.falling = true
  p.extUpdate = update
  p.carried = nil
  local id = p.minish and ANIM_FALL_MINISH or (not p.hasCap and ANIM_FALL_NOCAP or ANIM_FALL)
  p:setAnim(id, true)
  f:sound(SFX_PLY_VO7)
  f:sound(SFX_FALL_HOLE)
  return true
end

F.ANIMS = { ANIM_FALL, ANIM_FALL_MINISH, ANIM_FALL_NOCAP }

return F
