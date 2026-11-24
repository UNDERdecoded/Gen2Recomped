-- Round 75: Cloud Tops' room code (src/roomInit.c) and the CLOUD object ($A3, src/object/cloud.c).
-- Neither was ported: the cloud bulges over the two golden Kinstones / red whirlwinds never cleared when their Cloud
-- Piranhas were beaten, the five pinwheels' last fusion never brought the great whirlwind (KUMOTATSUMAKI), and the
-- top tier's Wind Crest (Cloud Tops) never appeared.
--
-- CARTRIDGE BEHAVIOUR (ported):
--   * sub_StateChange_CloudTops_Bottom ($08:02): global KUMOTATSUMAKI -> sub_0809F814(TILE_POS $6DE); local
--     KUMOUE_02_00 -> sub_0809F814($0E0) else LoadRoomEntityList(gUnk_080DD7E0); local KUMOUE_02_02 ->
--     sub_0809F814($BA3) else gUnk_080DD840.
--   * sub_StateChange_CloudTops_House / sub_unk1 ($08:00): WINDCREST_CLOUD_TOPS clear -> gUnk_080DD364.
--   * sub_0809F814(pos): sub_0807BB68(gUnk_081247D0, pos, LAYER_BOTTOM): nine SetTileTypes (a 3 x 3 patch: the
--     cloud bulge's tiles -> open cloud).  The table is read from the player's ROM (RomTables "Cloud75.TILES").
--   * Cloud type 0, type2 != 0 (a bulge): action 1 waits for room flag `timer` (the Cloud Piranhas' fight); then
--     SetPlayerControl(3) + PausePlayer, camera on the cloud, 120 frames (once the camera has arrived): at 30
--     SetLocalFlag(type2); eight puffs every 8 frames, SFX_184 every 12; at 0 SFX_11D + the tiles, 120 frames;
--     then the camera back on Link, SFX_SECRET_BIG, 30 frames (once the camera is back): CONTROL_1, gone.
--   * Cloud type 0, type2 0 (the big bulge, from script_Npc4EFirstCloud's gUnk_080DD730 after the fifth pinwheel):
--     gPauseMenuOptions.disabled, camera on it, 120 frames of puffs, SFX_11D + the tiles, 90 frames, SFX_SECRET_BIG,
--     SetGlobalFlag(KUMOTATSUMAKI), LoadRoomEntityList(gUnk_080DD750) (the orchestrator gives Link back), gone.
--   * Cloud type 1 (a puff): 8 .. 38 frames of LinearMoveUpdate at its speed / direction, a random 1-2 px jitter.
-- SIMPLIFIED: the puffs are drawn with the object's first animation frame (frameIndex 0 .. 3 not picked).
local bit = require("bit")
local band, rshift = bit.band, bit.rshift

local M = {}

M.AREA = 0x08
M.ROOM_HOUSE, M.ROOM_MIDDLE, M.ROOM_BOTTOM = 0x00, 0x01, 0x02
M.ID = 0xA3 -- CLOUD
M.KUMOTATSUMAKI = 0x24                     -- global
M.KUMOUE_02_00, M.KUMOUE_02_02 = 0xF3, 0xF5 -- local (Cloud Tops' bank)
M.POS_VORTEX, M.POS_NORTH, M.POS_SOUTH = 0x6DE, 0x0E0, 0xBA3
M.LIST_NORTH, M.LIST_SOUTH, M.LIST_CREST, M.LIST_VORTEX = 0x080DD7E0, 0x080DD840, 0x080DD364, 0x080DD750
M.WINDCREST_CLOUD_TOPS = 26
local SFX_11D, SFX_184, SFX_SECRET_BIG = 0x11D, 0x184, 0x73
M.SFX_11D, M.SFX_184, M.SFX_SECRET_BIG = SFX_11D, SFX_184, SFX_SECRET_BIG

local function tiles() return require("src.zelda.tmc.RomTables").t("Cloud75.TILES") end -- gUnk_081247D0

-- sub_0809F814: the 3 x 3 patch at TILE_POS pos (x | y << 6), layer 1
function M.clear(f, pos, tbl)
  tbl = tbl or tiles()
  local O = f:objects()
  if not (O and O.setTileType) then return 0 end
  local n = 0
  for i = 0, 15 do
    local e = tbl[i]
    if not e then break end
    local tt, off = e[1], e[2]
    local p = pos + off
    O:setTileType(1, band(p, 63), rshift(p, 6), tt)
    n = n + 1
  end
  return n
end

-- OURS (a save repair, not cartridge code): before round 75 the port set every pinwheel flag on arrival (Natives40's
-- mislabelled NPC4E natives).  On the cartridge KUMOUE_02_AWASE_0n is set only by the fusion with Mysterious Cloud n
-- (KINSTONE_MYSTERIOUS_CLOUD_n), so a flag without its fusion is cleared; a real fusion keeps its flag.
function M.repairPinwheels(f)
  local ok, flags = pcall(function() return require("src.zelda.tmc.Objects37").PINWHEEL_FLAGS end)
  if not ok or not flags or not f.kinstoneFused then return 0 end
  local n = 0
  for i = 0, 4 do
    local fl = flags[i]
    if fl and f:flag("local", fl) and not f:kinstoneFused(i + 1) then f:setFlag("local", fl, false); n = n + 1 end
  end
  if n > 0 then -- the room's PINWHEELs were made spinning already (pinwheel.c reads its flag at init)
    for _, e in ipairs(f.entities or {}) do
      if e.kind == 6 and e.id == 0xBE and e.pinFlag and not f:flag("local", e.pinFlag) then e.action = 1 end
    end
  end
  return n
end

-- one entry of R27B.MODULES: R26.roomInit runs it after the room's lists
function M.roomInit(f)
  local r = f.room
  if not r or r.area ~= M.AREA then return end
  if r.room == M.ROOM_BOTTOM then
    M.repairPinwheels(f)
    if f:flag("global", M.KUMOTATSUMAKI) then M.clear(f, M.POS_VORTEX) end
    if f:flag("local", M.KUMOUE_02_00) then M.clear(f, M.POS_NORTH) else f:loadEntityList(M.LIST_NORTH) end
    if f:flag("local", M.KUMOUE_02_02) then M.clear(f, M.POS_SOUTH) else f:loadEntityList(M.LIST_SOUTH) end
  elseif r.room == M.ROOM_HOUSE then
    if band(f.save and f.save.windcrests or 0, bit.lshift(1, M.WINDCREST_CLOUD_TOPS)) == 0 then f:loadEntityList(M.LIST_CREST) end
  end
end

local function rnd() return love and love.math and love.math.random(0, 0xFFFFFFF) or math.random(0, 0xFFFFFFF) end

-- sub_0809F770 + sub_0809F7BC: eight puffs round the cloud
local function puffs(D, e)
  local f = D.field
  local O = f:objects()
  for i = 1, 8 do
    local u = rnd()
    local c = { kind = 6, id = M.ID, form = 1, type2 = 0, x = e.x + band(u, 31) - 16, y = e.y + band(rshift(u, 8), 31) - 16,
                z = 0, animationState = 0, field80 = 0, field82 = 0, interactType = 0, layer = e.layer, dungeon = true,
                flags = 0, flag = 0, spritePriority = 0 }
    local v = rnd()
    local okS, sp = pcall(function() return require("src.zelda.tmc.RomTables").t("Cloud75.SPEEDS")[band(v, 3)] end) -- gUnk_081247C8
    c.speed = okS and sp or 0
    c.direction = band(rshift(v, 8), 31)
    c.timer = band(rnd(), 30) + 8
    local def = O and O:def(M.ID, 1)
    if def then O:dress(c, def, 0) end
    c.extUpdate = function(DD, me) M.puff(DD, me) end
    f.entities[#f.entities + 1] = c
    if D.track then D:track(c) end
  end
end

function M.puff(D, c)
  if c.deleted then return end
  local a = c.direction * 8 / 256 * 2 * math.pi
  local s = (c.speed or 0x100) / 256
  c.x = c.x + math.sin(a) * s
  c.y = c.y - math.cos(a) * s
  if c.anim and c.anim.update then c.anim:update(1) end
  c.timer = c.timer - 1
  if c.timer <= 0 then c.deleted = true end
end

local function camArrived(f) return not f.scrolling end

function M.update(D, e)
  local f = D.field
  if e.deleted then return end
  local p = f.player
  if e.type2 == 0 then
    if e.action == 0 then
      e.action, e.timer, e.u68 = 1, 120, 12
      f.cameraTarget = e
      f.menuDisabled = true
      puffs(D, e)
    elseif e.action == 1 then
      e.timer = e.timer - 1
      if e.timer == 0 then
        e.action, e.timer = 2, 90
        f:sound(SFX_11D)
        M.clear(f, M.posOf(f, e))
      else
        if band(f.frame or 0, 7) == 0 then puffs(D, e) end
        e.u68 = e.u68 - 1; if e.u68 == 0 then e.u68 = 12; f:sound(SFX_184) end
      end
    elseif e.action == 2 then
      e.timer = e.timer - 1
      if e.timer == 0 then
        f:sound(SFX_SECRET_BIG)
        f:setFlag("global", M.KUMOTATSUMAKI, true)
        f:loadEntityList(M.LIST_VORTEX)
        e.deleted = true
      end
    end
    return
  end
  if e.action == 0 then
    e.action, e.u68 = 1, 12
  elseif e.action == 1 then
    if f:flag("room", e.timer0 or 0) then
      e.action, e.timer = 2, 120
      p.control = false; p.moving = false
      f.cameraTarget = e
    end
  elseif e.action == 2 then
    if camArrived(f) then
      if e.timer == 30 then f:setFlag("local", e.type2, true) end
      e.timer = e.timer - 1
      if e.timer == 0 then
        e.action, e.timer = 3, 120
        f:sound(SFX_11D)
        M.clear(f, M.posOf(f, e))
      else
        if band(f.frame or 0, 7) == 0 then puffs(D, e) end
        e.u68 = e.u68 - 1; if e.u68 == 0 then e.u68 = 12; f:sound(SFX_184) end
      end
    end
  elseif e.action == 3 then
    e.timer = e.timer - 1
    if e.timer == 0 then
      e.action, e.timer = 4, 30
      f.cameraTarget = nil
      f:sound(SFX_SECRET_BIG)
    end
  elseif e.action == 4 then
    if camArrived(f) then
      e.timer = e.timer - 1
      if e.timer == 0 then p.control = true; e.deleted = true end
    end
  end
end

-- the TILE_POS under the cloud (x / y relative to the room)
function M.posOf(f, e)
  return band(rshift(math.floor(e.x), 4), 63) + bit.lshift(band(rshift(math.floor(e.y), 4), 63), 6)
end

-- A WHIRLWIND with a script (ENT_SCRIPTED: Cloud Tops' hidden whirlwinds, script_HiddenWhirlwind1 / 2) is still a
-- whirlwind: Whirlwind_Init / Action1 run the script themselves (ExecuteScriptForEntity), and Action1 catches Link only
-- while spriteSettings.draw is set.  The port made such an entity a bare script holder (no whirlwind).
M.WHIRLWIND = 0x5E
function M.scriptedObject(f, d, e)
  if d.id ~= M.WHIRLWIND or not f._dungeon then return nil end
  local de = f._dungeon:spawnObject(d)
  if not de then return nil end
  de.script = e.script
  de.unplaced = e.unplaced
  local u = de.extUpdate
  de.extUpdate = function(dd, me, input) if me.hidden then return end return u(dd, me, input) end
  return de
end

-- one entry of R27B.MODULES (Dungeon:spawnObject -> R26 -> R27B): CLOUD type 0
function M.spawnObject(D, e)
  if e.id ~= M.ID or (e.form or 0) ~= 0 then return nil end
  e.action = 0
  e.hidden = true -- spriteSettings.draw = 0
  e.cloud75 = true
  e.extUpdate = function(DD, x) M.update(DD, x) end
  D:track(e)
  return e
end

return M
