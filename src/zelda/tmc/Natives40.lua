-- Round 40: the last script natives the room survey listed as missing
-- (round 37's survey: 6 keys), ported from the decomp.
--
-- CARTRIDGE BEHAVIOUR
--   castorWildsStatue.c (script_CastorWildsStatueRock, Castor Wilds $04:00):
--     sub_080676D8: subAction++ (one more statue's Kinstone fused).
--     sub_0806757C: subAction 1..2 -> LoadFixedGFX(gUnk_08110E68[subAction])
--       (the rock's cracked pictures $C8 / $C9 / $CA); subAction >= 3 ->
--       RestorePrevTileEntity on tiles $E81 / $E82 / $E83 / $EC3 (bottom):
--       the four SPECIAL_TILE_34 the rock set at init are walkable again.
--     sub_080675D4: nine FX_DEATH at gUnk_08110E78 offsets and four FX_ROCK
--       at gUnk_08110E8A, z = (subAction << 2) - 12; subAction > 2 hides
--       the rock.
--   townMinish.c (Hyrule Town's Minish, script_TownMinish1 / 3,
--   script_RemTownMinish):
--     TownMinish_MakeInteractable ($0806ADFC): AddInteractableWhenBigFuser.
--     sub_0806AEE4: every 3rd frame the head looks at Link inside a $20 x $20
--       rect (GetFacingDirectionInRectRadius), else at its start facing
--       (unk_6a = the entity's timer byte): frame / frameIndex from
--       gUnk_081125F4[animationState / 2][dir >> 1]; bit 7 of the second
--       byte turns the body (GetAnimationStateForDirection8).
--   npc4E.c (Cloud Tops' clouds, Veil Falls' Source of the Flow):
--     NPC4E_MakeFuserInteractable ($0806DAAC): AddInteractableFuser(this,
--       NPC4E_GetKinstoneId): types 1..5 -> KINSTONE_MYSTERIOUS_CLOUD_*
--       (1..5), 11 -> KINSTONE_SOURCE_FLOW (9), 6..10 -> GetFusionToOffer.
--     NPC4E_SetPinwheelFlag ($0806DAD0): SetLocalFlag(KUMOUE_02_AWASE_0n) for
--       type n (1..5; the same flags as gPinwheelFlags[0..4]) +
--       SFX_TASK_COMPLETE.
--     sub_0806DB84: two MINISH_VILLAGE_OBJECTs (types 4 and 5, frame 0 / 1,
--       priority 7) 8 px left / right of the NPC, each running its stone-
--       opening script (the literal pool at $0806DBEC / $0806DBF0 names them).
-- SIMPLIFIED: sub_0806DB84's hitbox swap (gUnk_08114154) is not modelled
--   (the NPC's interact box comes from NPC4E_ChangeInteractableHitbox);
--   the rock's FX are not sorted above it (SortEntityAbove).
local bit = require("bit")
local band, rshift = bit.band, bit.rshift

local M = {}

local N = require("src.zelda.tmc.Native").N
local function reg(addr, fn) if not N[addr] then N[addr] = fn end end
local function npcT(f) return require("src.zelda.tmc.Ppu").table({ A = f.assets }, "npcData") end

local SPECIAL_FX, FX_DEATH, FX_ROCK = 0x0F, 2, 4
local SFX_TASK_COMPLETE = 0xCD
local A_STATUE_GFX, A_STATUE_DEATH, A_STATUE_ROCK = 0x08110E68, 0x08110E78, 0x08110E8A
local A_TOWN_LOOK = 0x081125F4
M.STATUE_TILES = { 0xE81, 0xE82, 0xE83, 0xEC3 }
M.NPC4E_KINSTONE = { [1] = 1, [2] = 2, [3] = 3, [4] = 4, [5] = 5, [11] = 9 }
M.MVO = 0x3E
M.STONE_SCRIPT_PTRS = { 0x0806DBEC, 0x0806DBF0 } -- sub_0806DB84's literal pool

local function s8(v) return v >= 0x80 and v - 0x100 or v end

-- ------------------------------------------------------- castorWildsStatue.c
reg(0x080676D8, function(f, e) e.subAction = (e.subAction or 0) + 1 end)
reg(0x0806757C, function(f, e)
  local sa = e.subAction or 0
  if sa == 0 then return end
  if sa >= 3 then
    for _, pos in ipairs(M.STATUE_TILES) do
      f:dungeon():block(pos % 64, math.floor(pos / 64), 1, false) -- RestorePrevTileEntity(pos, 1)
    end
  else
    local t = npcT(f)
    if t then e.gfx = t.u32(A_STATUE_GFX + sa * 4) end
  end
end)
reg(0x080675D4, function(f, e)
  local t = npcT(f)
  local z = (e.subAction or 0) * 4 - 12
  if t and f.addFx then
    local n0 = #f.entities
    for i = 0, 8 do f:addFx(e.x + s8(t.u8(A_STATUE_DEATH + i * 2)), e.y + s8(t.u8(A_STATUE_DEATH + i * 2 + 1)), SPECIAL_FX, FX_DEATH) end
    for i = 0, 3 do f:addFx(e.x + s8(t.u8(A_STATUE_ROCK + i * 2)), e.y + s8(t.u8(A_STATUE_ROCK + i * 2 + 1)), SPECIAL_FX, FX_ROCK) end
    for i = n0 + 1, #f.entities do local x = f.entities[i]; x.z = z; x.layer = e.layer end
  end
  if (e.subAction or 0) > 2 then e.hidden = true end
end)

-- ------------------------------------------------------------- townMinish.c
reg(0x0806ADFC, function(f, e) e.talkable = true end) -- TownMinish_MakeInteractable (AddInteractableWhenBigFuser)
-- GetFacingDirection (0..31, 0 = north, clockwise)
local function dir32(e, p)
  local a = math.atan2(p.x - e.x, -(p.y - e.y))
  return math.floor(a / (2 * math.pi) * 32 + 0.5) % 32
end
function M.townMinishLook(f, e)
  if (e.lookTimer or 0) > 0 then e.lookTimer = e.lookTimer - 1 return end
  e.lookTimer = 2
  local p = f.player
  local d
  if p and math.abs(p.x - e.x) < 0x20 and math.abs(p.y - e.y) < 0x20 then d = dir32(e, p)
  else
    local st = band(rshift(e.param or 0, 8), 0xFF) -- unk_6a = the entity's timer byte
    e.animationState = st * 2
    d = st * 8
  end
  local t = npcT(f)
  if not t then return end
  local a = A_TOWN_LOOK + rshift(e.animationState or 0, 1) * 0x20 + rshift(d, 1) * 2
  local b1, b2 = t.u8(a), t.u8(a + 1)
  if band(b2, 0x80) ~= 0 then e.animationState = band(math.floor((d + 2) / 4), 7) end
  e.headFrame = b1
  e.staticFrame = band(b2, 0x7F)
end
reg(0x0806AEE4, M.townMinishLook)

-- ----------------------------------------------------------------- npc4E.c
function M.npc4eKinstone(f, e)
  local ty = e.form or 0
  if ty >= 6 and ty <= 10 then
    if e.fuserId then return require("src.zelda.tmc.Fusers").offer(f, e.fuserId) end
    return e.fuser or 0
  end
  return M.NPC4E_KINSTONE[ty] or 0
end
-- round 75: the USA addresses were one function off (the scripts' Call words: script_Npc4EFirstCloud calls $0806DAAC
-- first, inside its BeginBlock, then $0806DAD0, and in its loop $0806DAAC after UpdateFusion; $0806DAE8 / $0806DB44
-- after the fusion): $0806DAAC is NPC4E_IsKinstoneFused, $0806DAD0 NPC4E_MakeFuserInteractable, $0806DAE8
-- NPC4E_SetPinwheelFlag, $0806DB44 NPC4E_IsEveryPinwheelActivated.  With the old labels every Mysterious Cloud set
-- its pinwheel flag on its first frame (all five pinwheels spun on arrival, no fusion counted).
reg(0x0806DAAC, function(f, e, ctx, a) -- NPC4E_IsKinstoneFused: condition = CheckKinstoneFused(NPC4E_GetKinstoneId)
  local id = M.npc4eKinstone(f, e)
  ctx.condition = (id ~= 0 and f.kinstoneFused and f:kinstoneFused(id)) and 1 or 0
  if a then a.flags = bit.bor(a.flags, 1) end
end)
reg(0x0806DB44, function(f, e, ctx) -- NPC4E_IsEveryPinwheelActivated
  local flags = require("src.zelda.tmc.Objects37").PINWHEEL_FLAGS
  local all = true
  for i = 0, 4 do if not (flags and flags[i] and f:flag("local", flags[i])) then all = false end end
  ctx.condition = all and 1 or 0
end)
reg(0x0806DAD0, function(f, e) -- NPC4E_MakeFuserInteractable
  e.fuser = M.npc4eKinstone(f, e)
  e.talkable = true
end)
reg(0x0806DAE8, function(f, e) -- NPC4E_SetPinwheelFlag
  local ty = e.form or 0
  if ty >= 1 and ty <= 5 then
    local flags = require("src.zelda.tmc.Objects37").PINWHEEL_FLAGS -- gPinwheelFlags[0..4] = KUMOUE_02_AWASE_01..05
    local fl = flags and flags[ty - 1]
    if fl then f:setFlag("local", fl, true) end
  end
  f:sound(SFX_TASK_COMPLETE)
end)
reg(0x0806DB84, function(f, e) -- the Source of the Flow's two stones
  if not f.mem then return end
  for i = 0, 1 do
    local ptr = M.STONE_SCRIPT_PTRS[i + 1]
    local script = f.mem:valid(ptr) and f.mem:u32(ptr) or require("src.zelda.tmc.Veil74").stoneScript(i) -- round 74: the literal pool is code, outside scripts.bin
    local o = f:spawn({ kind = 6, id = M.MVO, paramA = 4 + i, paramB = 0, x = math.floor(e.x) + (i == 0 and -8 or 8),
                        y = math.floor(e.y), pool = 0x4F, paramC = script })
    if o then
      o.staticFrame = i
      o.spritePriority = 7
      o.layer = e.layer
      local listed = false
      for k = #f.entities, math.max(1, #f.entities - 2), -1 do if f.entities[k] == o then listed = true break end end
      if not listed then f.entities[#f.entities + 1] = o end
    end
  end
end)

return M
