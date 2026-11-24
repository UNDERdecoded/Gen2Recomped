-- Round 34: BIG_VORTEX ($82, src/object/bigVortex.c -- the wind vortexes of
-- Lake Hylia's ruins / the Cloud Tops / the Palace of Winds) and
-- PlayerParachute's states 6 / 7 (player.c sub_0807380C / sub_08073884)
-- that a Cloud Tops whirlwind or a vortex starts (gPlayerState.field_0x38
-- 1).  In R34.MODULES (spawnObject); the states run from Whirlwind.lua.
--
-- CARTRIDGE BEHAVIOUR:
--   * BigVortex type 0, Init: z -16; flag (paramC >> 16) != 0 and not set
--     -> action 1 (hidden); else action 3, drawn, sub_08098E88 (the two
--     child sprites, types 1 / 2, at y - 1 / - 2 with spriteOffsetY 8 /
--     $10); animation 0.
--   * Action1: the flag set -> FX_BIG_EXPLOSION2 at y + 8, 45 frames
--     (Action2), then drawn + the children (Action3).
--   * Action3: Link within 8 x 8 (sub_0800419C) -> Link at the vortex,
--     collision layer 1, PLAYER_PARACHUTE queued with field_0x38 = 1 and
--     field_0x39 = type2; type2 1 sets global TATSUMAKI; PutAwayItems;
--     Action4 (animation only).  Types 1 / 2: animation = type, affine
--     scale gUnk_08123690[type & 2] ($1C0 x $160 / $300 x $200).
--   * PlayerParachute with field_0x38 1: state 1 at once zVelocity 4.5625;
--     state 2 falling above z -32 -> state 6 (collision off, timer 30).
--     6 (sub_0807380C): every 4 frames animationState += 2 (the turning
--     animations); above z -16 GravityUpdate(gravity / 16), else 30 frames
--     -> 7 (timer 60, zVelocity 2.0).  7 (sub_08073884): every 2 frames
--     the turn; 60 frames -> field_0x39 != $FF: DoExitTransition(
--     gUnk_0813AD88[field_0x39]) (the list below, from screenTransitions.c),
--     else InitParachuteRoom (the room above: room - 1, x / y & $3F8,
--     PL_SPAWN_PARACHUTE_FORWARD); GravityUpdate(-gravity * 3 / 4).
-- SIMPLIFIED: the arrival spawn types 9 / 10 are the port's (9 = Minish,
--   10 = a plain arrival, not the forward glide); the vortex's affine
--   children are drawn unscaled.
local bit = require("bit")
local band = bit.band

local M = {}
M.ID = 0x82
local TATSUMAKI = 0x23 -- flags.h (global)
-- gUnk_0813AD88 {area, room, endX, endY, layer, spawn type, facing}
M.EXITS = {
  [0] = require("src.zelda.tmc.RomTables").t("Vortex34.EXIT_0"),
  [1] = require("src.zelda.tmc.RomTables").t("Vortex34.EXIT_1"),
  [2] = require("src.zelda.tmc.RomTables").t("Vortex34.EXIT_2"),
  [3] = require("src.zelda.tmc.RomTables").t("Vortex34.EXIT_3"),
  [4] = require("src.zelda.tmc.RomTables").t("Vortex34.EXIT_4"),
}
local SCALE = require("src.zelda.tmc.RomTables").t("Vortex34.SCALE") -- gUnk_08123690
local FX_BIG_EXPLOSION2, SPECIAL_FX = 0x43, 0x0F

-- the exit a finished state 7 takes
function M.exitFor(f, p, pa)
  local idx = pa.exitIdx or 0xFF
  if idx ~= 0xFF then
    local e = M.EXITS[idx]
    if not e then return nil end
    local x = {}
    for k, v in pairs(e) do x[k] = v end
    x.warpType = 1
    return x
  end
  -- InitParachuteRoom
  local r = f.room
  return { warpType = 1, area = r.area, room = r.room - 1, endX = band(math.floor(p.x), 0x3F8),
           endY = band(math.floor(p.y), 0x3F8), layer = 1, kind = 10, facing = 4 }
end

-- PlayerParachute states 6 / 7 (from Whirlwind.player)
function M.parachute(p, pa, f, turns, grav, gravity)
  local fr = f.frame or 0
  local function turn(mask)
    if band(fr, mask) == 0 then p.animationState = band((p.animationState or 4) + 2, 6) end
    local a = turns[band(p.animationState or 0, 6) / 2]
    if p.paraAnim ~= a then p:setAnim(a, true); p.paraAnim = a else p.anim:update(1) end
  end
  if pa.sub == 6 then
    turn(3)
    if (p.z or 0) > 16 then gravity(p, grav / 16)
    else
      pa.timer = pa.timer - 1
      if pa.timer <= 0 then pa.sub, pa.timer, p.zv = 7, 60, 2.0 end
    end
  else
    turn(1)
    pa.timer = pa.timer - 1
    if pa.timer == 0 and not pa.left then
      pa.left = true
      local ex = M.exitFor(f, p, pa)
      if ex then
        f:startTransition(ex)
        if f.transition then f.transition.vortex34 = true; p.vortexArrive34 = true end
        require("src.zelda.tmc.Vortex74").note(p, ex) -- round 74: its spawn type / facing for the arrival hop
      end
    end
    p.z = (p.z or 0) + (p.zv or 0)
    p.zv = (p.zv or 0) + grav * 3 / 4
  end
end

-- after the room change (the port's plain arrival): Link back on the ground
function M.frame(f)
  local p = f.player
  if p and p.vortexArrive34 and not f.transition then
    p.vortexArrive34 = nil
    p.z, p.zv, p.para, p.fall, p.cap, p.drawOver, p.paraAnim = 0, 0, nil, nil, nil, nil, nil
    if p.state == "ext" then p.state = "normal"; p.extUpdate = nil end
    require("src.zelda.tmc.Vortex74").arrive(f, p) -- round 74: PL_SPAWN_PARACHUTE_FORWARD / _UP: PlayerWarp's hop (sub_0807B144)
  end
  return false
end

-- ---------------------------------------------------------------------------
-- the vortex
-- ---------------------------------------------------------------------------
local function children(f, d, e)
  local O = f:objects()
  for t = 1, 2 do
    local c = { kind = 6, id = M.ID, form = t, x = e.x, y = e.y - t, z = 0, animationState = 0, field80 = 0,
                field82 = 0, interactType = 0, layer = e.layer }
    local def = O:def(M.ID, t)
    if def then
      O:dress(c, def, t)
      c.objAnim, c.spriteOY = t, 8 * t
      local s = SCALE[band(t, 2)]
      c.scale34 = s
      c.extUpdate = function(_, me) me.anim:update(1) end
      f.entities[#f.entities + 1] = c
      d:track(c)
    end
  end
end

local function show(f, d, e)
  e.hidden = false
  e.action = 3
  children(f, d, e)
end

local function update(f, d, e)
  local p = f.player
  if e.action == 1 then
    if d:check(e.flag) then
      e.action, e.timer = 2, 45
      if f.addFx then f:addFx(e.x, e.y + 8, SPECIAL_FX, FX_BIG_EXPLOSION2) end
    end
  elseif e.action == 2 then
    e.timer = e.timer - 1
    if e.timer == 0 then show(f, d, e) end
  elseif e.action == 3 then
    if p and not p.minish and p.state == "normal" and math.abs(p.x - e.x) <= 8 and math.abs(p.y - e.y) <= 8 then
      p.x, p.y, p.layer = e.x, e.y, 1
      local W = require("src.zelda.tmc.Whirlwind")
      if p.field and p.field.objects and p.carried then p.field:objects():dropCarried(p) end
      W.start(p, 1, e.type2 or 0)
      if (e.type2 or 0) == 1 then f:setFlag("global", TATSUMAKI, true) end
      e.action = 4
    end
    e.anim:update(1)
  else
    e.anim:update(1)
  end
end
M.update = update

function M.spawnObject(d, e)
  if e.id ~= M.ID then return nil end
  local f = d.field
  local O = f:objects()
  local def = O and O:def(M.ID, e.form or 0)
  if def then O:dress(e, def, 0); e.objAnim = 0 end
  e.z = 16
  e.vortex34 = true
  if (e.form or 0) ~= 0 then
    e.extUpdate = function(_, me) me.anim:update(1) end
    d:track(e)
    return e
  end
  if (e.flag or 0) ~= 0 and not d:check(e.flag) then
    e.action, e.hidden = 1, true
  else
    show(f, d, e)
  end
  e.extUpdate = function(dd, me) update(f, dd, me) end
  d:track(e)
  return e
end

return M
