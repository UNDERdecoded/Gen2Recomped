-- Round 27 (team A, group SQ): Anju's cucco minigame and carrying cuccos.
-- Required by SideQuests27.lua (R27A module); ports from the decomp:
--
-- src/object/cuccoMinigame.c (object CUCCO_MINIGAME $B9), natives:
--   CuccoMinigame_Init ($080A1550): CreateObject(CUCCO_MINIGAME) running the
--     script at intVariable (script_080101AC), CuccoMinigame action 0 (timer =
--     goalData[level].time * 60, target cuccos, unk6e 1, returned[] cleared,
--     NPC_UNK_58 the timer display), and the level's ten
--     pCuccoMinigame_MinigameCuccoDefs entries {type + 1, x, y}: CUCCO_AGGR
--     enemies at the room origin + (x, y), collision layer 1.  condition 1.
--   sub_080A1270 ($080A1270): every frame each live cucco not yet counted
--     that stands at x >= origin + $360 and y >= origin + $350 (the pen) is
--     counted (returned[i] = type + 1, its type2 = 1 so it can no longer be
--     lifted, SFX by type: SFX_VO_CUCCO5 / SFX_VO_CUCCO_CALL); counted ones
--     are kept 4 px inside the pen; a cucco that is gone is -1.  The player's
--     field_0x27[0] = $FF.  The timer runs down; at 0 SFX_CUCCO_MINIGAME_BELL
--     and the command ends (sub_08050384 only clears BG0), else it waits.
--   CuccoMinigame_Cleanup ($080A1388): every cucco still there is deleted.
--   CuccoMinigame_Results ($080A13B4): TEXT_ANJU $0C (condition 1) when the
--     count reached the goal, else $05 (condition 0).
--   CuccoMinigame_WinItem ($080A13E8): prizeData[level] by
--     InitItemGetSequence -- shells (not when all figurines are had),
--     kinstones (not when all fusions are done), the heart piece once
--     (ANJU_HEART); a skipped prize sets unk6e 2.
--   CuccoMinigame_WinRupees ($080A1460): CuccoMinigameRupees[returned type]
--     (0, 10, 50; a gone cucco (-1) reads the byte before the table, the high
--     byte of SFX_VO_CUCCO_CALL: 0), ModRupees, TEXT_ANJU $07 with the sum.
--   CuccoMinigame_AdvanceLevel ($080A14A8): level + 1 (max 9) into the
--     global flags ANJU_LV_BIT0..3 ($4B-$4E).
--   CuccoMinigame_TellObjective ($080A1608): TEXT_ANJU $02 ($06 when room
--     flag 1), the goal's time (gMessage.rupees) and count (field_0x14).
--   sub_080A1648 / sub_080A169C: SPECIAL_TILE_127 at (54..56, 52) and
--     SPECIAL_TILE_126 at (53, 53), (53, 57) on the bottom layer, and back
--     (RestorePrevTileEntity: the tiles saved here).
-- src/npc/npc58.c (NPC_UNK_58): the timer at screen (120, 16): tens of
--   seconds, seconds, tenths (timer / 600, % 600 / 60, % 60 / 6) as frames
--   of sprite parts at -12, -4, +12 and frame 10 (the mark) at 0; gone with
--   its parent.  npcUtils.c sub_0806EC20 / sub_0806EC38 create / delete it.
-- src/enemy/cuccoAggr.c, the carry (action 2, RegisterCarryEntity with
--   carryFlags $30) that EnemyField1.lua left out, wrapped around
--   EnemyField1.cucco: sub_08039298 (liftable while type2 == 0, in actions
--   1 / 3 / 4 / 5), sub_08038DD8 (lifted: timer 16, subtimer
--   gUnk_080CF7BC[type] (type 1: $78, then it frees itself: dropped, flees),
--   collision off, animation 4, SFX_VO_CUCCO4), sub_08038E18 (held: every 16
--   frames flipX ^= Random & 1 and a feather puff), sub_08038EAC (thrown:
--   flapping, flip by direction), sub_08038ED0 (landed: collision on, it
--   flees, sub_08039218).
-- src/playerItem/playerItemHeldObject.c for the throw: carryFlags $30 >> 4 =
--   3 -> speed $200, zVelocity 1.25 (gUnk_081320CC / gUnk_081320D4), the
--   object's z + 8, ProcessMovement10 (IsTileCollision type 10: low fences
--   are no wall; tested at the centre point), GravityUpdate(32.0); on the ground:
--   ACT_TILE_13/16/17/19/90 end the flight (subAction 3), else the first
--   landing bounces (SFX_PLACE_OBJ, zVelocity 1.0, speed / 2), the second
--   ends it (SFX_PLACE_OBJ once more).
-- SIMPLIFIED: the carried cucco is drawn by the carry system (first frame of
--   animation 4 over Link's head); held height 14 px as the other carried
--   enemies (Bobomb, Rollobite) use.
local bit = require("bit")
local band, bor, bxor, rshift = bit.band, bit.bor, bit.bxor, bit.rshift
local Native = require("src.zelda.tmc.Native")
local N = Native.N
local function reg(addr, fn) if not N[addr] then N[addr] = fn end end

local C = {}
C.OBJ_CUCCO_MINIGAME, C.CUCCO_AGGR, C.NPC_UNK_58 = 0xB9, 0x41, 0x58
local SFX_VO_CUCCO5, SFX_VO_CUCCO_CALL, SFX_CUCCO_MINIGAME_BELL = 0x1DA, 0xD5, 0xE2
local SFX_VO_CUCCO4, SFX_PLACE_OBJ = 0x1D9, 0x104
local ANJU_LV_BIT0, ANJU_HEART = 0x4B, 0x4F
local ITEM_SHELLS, ITEM_KINSTONE, ITEM_HEART_PIECE = 0x3F, 0x5C, 0x63
local TEXT_ANJU = 0x30 * 256

local function D() return require("src.zelda.tmc.Drops") end
local function rnd(f) return D().random(D().rngOf(f)) end

-- goalData (cuccoMinigame.c): {time, numCuccos}
C.GOAL = { [0] = { 25, 2 }, { 25, 3 }, { 30, 4 }, { 45, 5 }, { 50, 5 }, { 45, 5 }, { 50, 6 }, { 60, 7 }, { 55, 2 }, { 55, 3 } }
-- pCuccoMinigame_MinigameCuccoDefs: per level ten {type + 1, x, y}
local A = { 0x0001, 0x02E9, 0x0318, 0x0001, 0x0280, 0x0380, 0x0002, 0x0277, 0x0314, 0x0001,
            0x0332, 0x0248, 0x0001, 0x0257, 0x028C, 0x0001, 0x0199, 0x031B, 0x0001, 0x0321,
            0x01B4, 0x0002, 0x02DF, 0x01D8, 0x0001, 0x03AD, 0x02DE, 0x0001, 0x0216, 0x01CC }
local B = { 0x0002, 0x02F6, 0x0346, 0x0001, 0x0266, 0x033C, 0x0001, 0x0319, 0x0296, 0x0001,
            0x0284, 0x0284, 0x0002, 0x0216, 0x0284, 0x0001, 0x0142, 0x0330, 0x0002, 0x0179,
            0x039F, 0x0001, 0x03A6, 0x0280, 0x0001, 0x039A, 0x015D, 0x0001, 0x031E, 0x01E5 }
C.DEFS = { [0] = A, A, A, B,
  { 0x0001, 0x0296, 0x0314, 0x0001, 0x02E6, 0x0231, 0x0001, 0x0254, 0x0290, 0x0001,
    0x01F8, 0x0325, 0x0001, 0x0185, 0x0367, 0x0001, 0x0320, 0x01D6, 0x0002, 0x01F8,
    0x0287, 0x0002, 0x029D, 0x01B1, 0x0002, 0x01F9, 0x022D, 0x0002, 0x0114, 0x0321 },
  { 0x0002, 0x02F6, 0x0346, 0x0001, 0x0266, 0x033C, 0x0001, 0x0319, 0x0296, 0x0001,
    0x0284, 0x0284, 0x0002, 0x0216, 0x0284, 0x0001, 0x0142, 0x0330, 0x0002, 0x0179,
    0x039F, 0x0002, 0x022D, 0x01CB, 0x0001, 0x039A, 0x015D, 0x0001, 0x031E, 0x01E5 },
  A,
  { 0x0001, 0x02E9, 0x0318, 0x0002, 0x0280, 0x0380, 0x0002, 0x0277, 0x0314, 0x0001,
    0x0332, 0x0248, 0x0001, 0x0257, 0x028C, 0x0001, 0x0199, 0x031B, 0x0001, 0x0321,
    0x01B4, 0x0002, 0x02DF, 0x01D8, 0x0002, 0x03AD, 0x02DE, 0x0001, 0x0216, 0x01CC },
  { 0x0001, 0x004D, 0x00F3, 0x0001, 0x011A, 0x0247 },
  { 0x0001, 0x0051, 0x0328, 0x0002, 0x0114, 0x0321, 0x0002, 0x0332, 0x0248 },
}
-- prizeData: {item, subtype}
C.PRIZE = { [0] = { ITEM_SHELLS, 10 }, { ITEM_SHELLS, 10 }, { ITEM_SHELLS, 20 }, { ITEM_SHELLS, 20 },
  { ITEM_SHELLS, 30 }, { ITEM_SHELLS, 30 }, { ITEM_KINSTONE, 0x6E }, { ITEM_KINSTONE, 0x6F },
  { ITEM_KINSTONE, 0x70 }, { ITEM_HEART_PIECE, 0 } }
local SOUNDS = { [0] = SFX_VO_CUCCO5, SFX_VO_CUCCO_CALL } -- CuccoMinigame_Sounds
C.RUPEES = { [-1] = 0, [0] = 0, 10, 50, 0 }                -- CuccoMinigameRupees (-1: see header)

function C.getLevel(f)
  local l = 0
  for b = 0, 3 do if f:flag("global", ANJU_LV_BIT0 + b) then l = bor(l, bit.lshift(1, b)) end end
  return l
end
function C.advanceLevel(f)
  local l = math.min(C.getLevel(f) + 1, 9)
  for b = 0, 3 do f:setFlag("global", ANJU_LV_BIT0 + b, band(l, bit.lshift(1, b)) ~= 0) end
end

local function alive(f, e)
  if not e or e.deleted then return false end
  for _, x in ipairs(f.entities) do if x == e then return true end end
  return false
end
C.alive = alive

-- CreateEnemy(CUCCO_AGGR, type)
local function createCucco(f, form, x, y)
  local E = f:enemies()
  local c
  if E and E.spawn then
    local ok, r = pcall(E.spawn, E, { kind = 3, id = C.CUCCO_AGGR, paramA = form, paramB = 0, paramC = 0, x = x, y = y })
    if ok then c = r end
  end
  if not c then return nil end
  c.x, c.y, c.layer = x, y, 1
  f.entities[#f.entities + 1] = c
  return c
end

-- ------------------------------------------------------------------ natives
reg(0x080A1550, function(f, e, ctx) -- CuccoMinigame_Init
  ctx.condition = 0
  local Script = require("src.zelda.tmc.Script")
  local Anim = require("src.zelda.tmc.Anim")
  local level = C.getLevel(f)
  local g = C.GOAL[level]
  local m = { kind = 6, id = C.OBJ_CUCCO_MINIGAME, form = 0, x = e.x, y = e.y, z = 0, animationState = 0,
              field80 = 0, field82 = 0, interactType = 0, anim = Anim.new(), hidden = true, r27cmg = true,
              action = 1, cmgTimer = g[1] * 60, current = 0, target = g[2], unk6e = 1, returned = {}, heap = {} }
  for i = 1, 10 do m.returned[i] = 0 end
  if f.mem and f.mem:valid(ctx.intVariable or 0) then m.script = Script.new(f.mem, ctx.intVariable) end
  local defs = C.DEFS[level]
  for i = 0, 9 do
    local t = defs[i * 3 + 1] or 0
    if t >= 1 then m.heap[i + 1] = createCucco(f, t - 1, defs[i * 3 + 2], defs[i * 3 + 3]) or false
    else m.heap[i + 1] = false end
  end
  f.entities[#f.entities + 1] = m
  f.r27cucco = m -- sub_0806EC20: NPC_UNK_58, parent = the minigame
  ctx.condition = 1
end)

reg(0x080A1270, function(f, m, ctx, a) -- the minigame's frame
  local cx, cy = 0x360, 0x350
  local n = 0
  for i = 1, 10 do
    local c = m.heap and m.heap[i]
    local r = m.returned[i]
    if r == 0 then
      if c and alive(f, c) then
        if cx <= math.floor(c.x) and cy <= math.floor(c.y) then
          m.returned[i] = (c.form or 0) + 1
          c.type2 = 1
          n = n + 1
          f:sound(SOUNDS[c.form or 0] or SFX_VO_CUCCO5)
        end
      else
        m.returned[i] = -1
      end
    elseif r > 0 then
      n = n + 1
      if c and alive(f, c) then
        if cx + 4 > math.floor(c.x) then c.x = cx + 4 end
        if cy + 4 > math.floor(c.y) then c.y = cy + 4 end
      else
        m.returned[i] = -1
      end
    end
  end
  m.current = n
  f.player.field27 = 0xFF
  m.cmgTimer = m.cmgTimer - 1
  if m.cmgTimer < 1 then
    f:sound(SFX_CUCCO_MINIGAME_BELL)
  else
    a.commandSize = 0
  end
end)

reg(0x080A1388, function(f, m) -- CuccoMinigame_Cleanup
  for i = 1, 10 do
    local c = m.heap and m.heap[i]
    if (m.returned[i] or 0) >= 0 and c then c.deleted = true end
  end
end)

reg(0x080A13B4, function(f, m, ctx) -- CuccoMinigame_Results
  if (m.current or 0) >= (m.target or 0) then
    f:message(TEXT_ANJU + 0x0C, m); ctx.condition = 1
  else
    f:message(TEXT_ANJU + 0x05, m); ctx.condition = 0
  end
end)

reg(0x080A13E8, function(f, m) -- CuccoMinigame_WinItem
  local p = C.PRIZE[C.getLevel(f)]
  local skip = false
  if p[1] == ITEM_SHELLS then
    skip = f.save.stats.hasAllFigurines and true or false
  elseif p[1] == ITEM_KINSTONE then
    skip = (f.save.kinstones and f.save.kinstones.didAllFusions) and true or false
  elseif p[1] == ITEM_HEART_PIECE then
    if not f:flag("global", ANJU_HEART) then f:setFlag("global", ANJU_HEART, true) else skip = true end
  end
  if not skip then f:giveItem(p[1], p[2]) else m.unk6e = 2 end
end)

reg(0x080A1460, function(f, m) -- CuccoMinigame_WinRupees
  local sum = 0
  for i = 1, 10 do sum = sum + (C.RUPEES[m.returned[i] or 0] or 0) end
  f:modStat("rupees", sum)
  f.messageRupees = sum -- gMessage.rupees
  f:message(TEXT_ANJU + 0x07, m)
end)

reg(0x080A14A8, function(f) C.advanceLevel(f) end) -- CuccoMinigame_AdvanceLevel

reg(0x080A1608, function(f, e) -- CuccoMinigame_TellObjective
  local idx = TEXT_ANJU + 0x02
  if f:flag("room", 1) then idx = TEXT_ANJU + 0x06 end
  local g = C.GOAL[C.getLevel(f)]
  require("src.zelda.tmc.SideQuests27").messageNumbers(f, idx, e, { g[1], g[2] })
end)

local PEN = { { 54, 52, 127 }, { 55, 52, 127 }, { 56, 52, 127 }, { 53, 53, 126 }, { 53, 57, 126 } }
reg(0x080A1648, function(f) -- sub_080A1648
  local r = f.room
  f.r27penSaved = {}
  for k, t in ipairs(PEN) do
    f.r27penSaved[k] = r.maps and r.maps.bottom and r.maps.bottom[t[2] * r.tw + t[1]]
    r:setTile(1, t[1], t[2], 0x4000 + t[3])
  end
end)
reg(0x080A169C, function(f) -- sub_080A169C: RestorePrevTileEntity
  local s = f.r27penSaved
  if not s then return end
  for k, t in ipairs(PEN) do if s[k] then f.room:setTile(1, t[1], t[2], s[k]) end end
  f.r27penSaved = nil
end)
reg(0x0806EC38, function(f) f.r27cucco = nil end) -- sub_0806EC38: NPC_UNK_58 deleted

-- ------------------------------------------------------------------ the timer (npc58.c)
function C.timerDigits(t)
  t = math.max(0, t or 0)
  local a = math.floor(t / 600)
  local r = t % 600
  return a, math.floor(r / 60), math.floor((r % 60) / 6)
end

function C.draw(f, font)
  local m = f.r27cucco
  if not m then return end
  if not alive(f, m) then f.r27cucco = nil return end
  local d1, d2, d3 = C.timerDigits(m.cmgTimer)
  local NP = require("src.zelda.tmc.NpcParts")
  if f.r27npc58 == nil then
    f.r27npc58 = false
    local R = NP.readers(f.assets)
    if R then
      local parts = NP.load(R, 0x081146D0) -- gUnk_081146D0
      if #parts == 4 then f.r27npc58 = { kind = 7, id = C.NPC_UNK_58, parts = parts, def = f:npcDef(C.NPC_UNK_58, 0) } end
    end
  end
  local n = f.r27npc58
  if n then
    local P = n.parts
    P[1].frame, P[2].frame, P[3].frame, P[4].frame = d1, d2, d3, 10
    P[1].ox, P[2].ox, P[3].ox, P[4].ox = 0x100 - 12, 0x100 - 4, 12, 0
    for i = 1, 4 do P[i].oy = 0 end
    NP.draw(f, n, 0x78, 0x10, false)
  elseif font then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(string.format("%d%d\"%d", d1, d2, d3), 0x78 - 12, 0x10 - 6)
  end
end

-- ------------------------------------------------------------------ the carry
local CARRY = { [0] = 0, 0x78 }          -- gUnk_080CF7BC
local FLEE_SPEED = { [0] = 0x140, 0x200 } -- gUnk_080CF824
local FLEE_TIME = { [0] = 0x384, 0x3C }   -- gUnk_080CF828
local FX_X = { [0] = 8, -8 }              -- gCuccoAggrFxHorizontalOffsets
local FX = { [0] = 0x3A, 0x4C, 0x3A }     -- gCuccoAggrFx
local STOP_ACT = { [13] = true, [16] = true, [17] = true, [19] = true, [90] = true } -- ACT_TILE_13/16/17/19/90

local function setAnim(E, e, i) e.animIndex = nil; E:setAnim(e, i) end
local function puff(f, e) -- CuccoAggr_CreateFx
  if f.addFx then f:addFx(e.x + FX_X[e.flipX and 1 or 0], e.y, 0x0F, FX[e.form or 0] or 0x3A) end
end
local function flee(E, e) -- sub_08039218
  e.action = 5
  e.spd = FLEE_SPEED[e.form or 0] or 0x140
  e.u78 = FLEE_TIME[e.form or 0] or 0x384
  if e.animIndex ~= 4 then setAnim(E, e, 4) end
  E.field:sound(SFX_VO_CUCCO4)
end
C.flee = flee

local hook = {}
function hook.lift(f, p, e)
  e.carriedBy, e.hidden, e.noTouch, e.noHit, e.liftable = p, true, true, true, nil
  e.action, e.subAction = 2, 0
  f:objects():lift(p, { obj = e.id, form = 4, ent = e, hook = hook,
    def = { sprite = e.sprite, palette = e.def and e.def.palette, gfxType = "enemy", gfx = e.def and e.def.gfx } })
  return true
end
local function release(p, e)
  if p.carried and p.carried.ent == e then p.carried = nil end
  e.carriedBy, e.hidden = nil, false
end
-- sub_080AD27C: the throw
function hook.throw(f, p, c)
  local e = c.ent
  release(p, e)
  e.x, e.y = p.x, p.y
  e.subAction = 2
  e.dir = band((p.animationState or 4) * 4, 0x1F)
  e.tspd = 0x200
  e.czv = 0x14000
  e.cz = -14 * 65536 -- the held height (SIMPLIFIED, see header)
  e.tbounce = 0
  f:sound(0x7C)
end
function hook.drop(f, p, c)
  local e = c.ent
  release(p, e)
  e.x, e.y = p.x, p.y
  e.subAction = 2
  e.dir, e.tspd, e.czv, e.cz, e.tbounce = 0xFF, 0, 0, -4 * 65536, 1
end
C.hook = hook

-- IsTileCollision(.., collisionType 10) (movement.c), the thrown object's
-- ProcessMovement10: collision data $20-$3F / $50-$5F that are FilledNone
-- for type 10 (low fences, ledges) let it pass; $10-$13 are whole tiles
local NONE10 = {}
for _, v in ipairs({ 0x20, 0x21, 0x22, 0x25, 0x28, 0x2A, 0x2C, 0x2D, 0x2E, 0x2F, 0x30, 0x31, 0x33, 0x34, 0x35, 0x36,
                     0x37, 0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F, 0x50, 0x51, 0x52, 0x53, 0x54, 0x55, 0x56,
                     0x57, 0x58, 0x59, 0x5A, 0x5B, 0x5C, 0x5D, 0x5E, 0x5F }) do NONE10[v] = true end
C.NONE10 = NONE10
function C.solid10(f, x, y, layer)
  local r = f.room
  local c = r.coll and (r.coll[layer or 1] or r.coll[1])
  if c and r.tw then
    local fx, fy = math.floor(x), math.floor(y)
    if fx >= 0 and fy >= 0 and (not r.width or (fx < r.width and fy < r.height)) then
      local v = c[rshift(fy, 4) * r.tw + rshift(fx, 4)] or 0
      if NONE10[v] then return false end
      if v >= 0x10 and v <= 0x13 then return true end
    end
  end
  return r:isSolid(x, y, layer or 1)
end

local function actTile(f, x, y, layer)
  local t = f.room:tileType(layer or 1, math.floor(x / 16), math.floor(y / 16))
  if not t or t >= 0x4000 then return nil end
  return f.assets.actTile and f.assets.actTile[t]
end

local function carried(E, e)
  local f = E.field
  local p = f.player
  local s = e.subAction or 0
  if s == 0 then -- sub_08038DD8
    e.subAction = 1
    e.timer = 16
    e.subtimer = CARRY[e.form or 0] or 0
    e.noTouch = true
    setAnim(E, e, 4)
    f:sound(SFX_VO_CUCCO4)
    s = 1
  end
  if s == 1 then -- sub_08038E18
    if p then e.x, e.y = p.x, p.y end
    if (e.subtimer or 0) ~= 0 then
      e.subtimer = e.subtimer - 1
      if e.subtimer == 0 then
        if p and p.carried and p.carried.ent == e then
          release(p, e)
          if p.state == "carry" then p.state = "normal" end
        end
        e.hidden = false
        flee(E, e)
        e.noTouch, e.noHit = nil, nil
        e.dir = band(rnd(f), 0x1F)
        return
      end
    end
    e.timer = (e.timer or 1) - 1
    if e.timer <= 0 then
      e.timer = 16
      if band(rnd(f), 1) ~= 0 then e.flipX = not e.flipX end
      puff(f, e)
    end
    if e.anim then e.anim:update(1) end
    return
  end
  if s == 2 then -- sub_08038EAC + PlayerItemHeldObject_SubAction2
    if band(e.dir or 0, 0xF) ~= 0 and e.dir ~= 0xFF then e.flipX = rshift(band(e.dir, 0xFF), 4) == 0 end
    if e.anim then e.anim:update(1) end
    if (e.tspd or 0) ~= 0 and e.dir ~= 0xFF then
      local a = e.dir / 32 * 2 * math.pi
      local sp = e.tspd / 256
      local nx, ny = e.x + math.sin(a) * sp, e.y - math.cos(a) * sp
      if not C.solid10(f, nx, ny, e.layer or 1) then e.x, e.y = nx, ny end
    end
    local nz = (e.cz or 0) - (e.czv or 0)
    if nz < 0 then
      e.cz, e.czv = nz, (e.czv or 0) - 0x2000
    else
      e.cz, e.czv = 0, 0
      local at = actTile(f, e.x, e.y, e.layer)
      if at and STOP_ACT[at] then
        e.subAction = 3
      elseif (e.tbounce or 0) ~= 0 then
        if e.tbounce == 1 then f:sound(SFX_PLACE_OBJ) end
        e.subAction = 3
      else
        f:sound(SFX_PLACE_OBJ)
        e.tbounce = 1
        e.czv = 0x10000
        e.tspd = math.floor((e.tspd or 0) / 2)
      end
    end
    e.z = -(e.cz or 0) / 65536
    return
  end
  -- sub_08038ED0
  e.noTouch, e.noHit = nil, nil
  e.cz, e.czv, e.z = 0, 0, 0
  flee(E, e)
end

-- EnemyField1.cucco with the carry around it
function C.cucco(E, e, orig)
  if e.action == 2 then return carried(E, e) end
  local r = orig(E, e)
  if e.deleted then return r end
  if (e.form or 0) ~= 2 then
    e.carryFlags = 0x30
    local a = e.action
    e.liftable = ((e.type2 or 0) == 0 and (a == 1 or a == 3 or a == 4 or a == 5)) or nil
    e.carryHook = hook.lift
  end
  return r
end

function C.install()
  local ok, EF1 = pcall(require, "src.zelda.tmc.EnemyField1")
  if not ok or type(EF1) ~= "table" or EF1.r27aCarry or not EF1.cucco then return end
  EF1.r27aCarry = true
  local orig = EF1.cucco
  EF1.cucco = function(E, e) return C.cucco(E, e, orig) end
end

return C
