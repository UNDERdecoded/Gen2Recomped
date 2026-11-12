-- Round 9: the natives the intro's castle scenes call (the sword
-- ceremony in the Castle Garden, script_Npc4EIntroCastle and the guards /
-- objects it drives).  The scripts themselves run from the ROM (Script.lua);
-- these are the C helpers they call, by address.
--
-- CARTRIDGE BEHAVIOUR (ported):
--   * guard.c sub_08064050: intVariable = 1 / 2 / 3 for type2 $11 / $12 /
--     $13, else 0 (the four chest guards' JumpTable).
--   * guardWithSpear.c sub_0806407C: a garden guard's wander: a new
--     direction every (Random() & $3F) + $20 frames (never straight back),
--     speed $80, kept within 16 px of where it started.
--   * guardWithSpear.c sub_08064180: deletes the first GUARD_1 ($15) NPC.
--   * cutsceneMiscObject.c sub_08095244: a type-0 caller makes
--     CUTSCENE_MISC_OBJECT type $A at (+16, -16) running
--     script_CutsceneMiscObjectSwordInChest ($0801183C).
--   * script.c DeleteHitbox ($0807F338): no hitbox (not solid).
--   * script.c sub_0807FB28: a white fill (SetFillColor $7FFF) held
--     intVariable frames, then cleared.
local Native = require("src.zelda.tmc.Native")
local N = Native.N
local bit = require("bit")
local band = bit.band

local C = {}

local function rnd(f) local D = require("src.zelda.tmc.Drops") return D.random(D.rngOf(f)) end

N[0x08064050] = function(f, e, ctx)
  local t2 = band(e.param or 0, 0xFF)
  ctx.intVariable = (t2 == 0x11 and 1) or (t2 == 0x12 and 2) or (t2 == 0x13 and 3) or 0
end

N[0x0806407C] = function(f, e, ctx, a)
  if (ctx.unk18 or 0) == 0 then
    ctx.unk18 = 1
    ctx.unk12 = band(rnd(f), 0x3F) + 0x20
    local dir = band(rnd(f), 0x18)
    local cur = e.direction or 0
    if cur == 0 and dir == 16 then dir = 8
    elseif cur == 8 and dir == 24 then dir = 16
    elseif cur == 16 and dir == 0 then dir = 24
    elseif cur == 24 and dir == 8 then dir = 0 end
    e.direction = dir
    e.animationState = dir / 4
    e.speed = 0x80
    e.wanderAnim = true
  end
  e.homeX, e.homeY = e.homeX or e.x, e.homeY or e.y
  require("src.zelda.tmc.Script").moveAngle(e, e.speed or 0x80, (e.direction or 0) * 8)
  local x, y = e.x - e.homeX, e.y - e.homeY
  if x > 16 then e.x = e.homeX + 16; ctx.unk12 = 1 end
  if x < -16 then e.x = e.homeX - 16; ctx.unk12 = 1 end
  if y > 16 then e.y = e.homeY + 16; ctx.unk12 = 1 end
  if y < -16 then e.y = e.homeY - 16; ctx.unk12 = 1 end
  ctx.unk12 = ctx.unk12 - 1
  if ctx.unk12 ~= 0 then a.commandSize = 0 end
end

-- castleMaid.c sub_080646A4: the same wander (walking animation on)
N[0x080646A4] = function(f, e, ctx, a)
  ctx.postScriptActions = bit.bor(ctx.postScriptActions or 0, 2)
  return N[0x0806407C](f, e, ctx, a)
end
-- castleMaid.c CastleMaid_SetDialogFunc: talking uses the NPC's own script
N[0x08064644] = function(f, e, ctx) e.dialogFunc = ctx.intVariable end

N[0x08064180] = function(f)
  for _, x in ipairs(f.entities) do
    if x.kind == 7 and x.id == 0x15 and not x.deleted then x.deleted = true; x.hidden = true; return end
  end
end

N[0x08095244] = function(f, e)
  if (e.form or 0) ~= 0 then return end
  local o = f:spawn({ kind = 6, id = 0x6A, paramA = 0x0A, paramB = 0, x = e.x + 16, y = e.y - 16,
                      paramC = 0x0801183C, pool = 0x4F })
  if o then o.parent = e end
end

-- cutsceneMiscObject.c sub_08095330: the chest's child (type $B) at z 16
N[0x08095330] = function(f, e)
  local o = f:spawn({ kind = 6, id = 0x6A, paramA = 0x0B, paramB = 0, x = e.x, y = e.y, paramC = 0, pool = 0x0F })
  if o then o.z = 16; o.parent = e; e.child = o end
end
-- sub_08095364: the child flies off (frame 2, zVelocity 3, speed $80)
N[0x08095364] = function(f, e)
  local o = e.child
  if o then o.z, o.zv, o.flyX = 16, 3, 0.5 end
end
-- sub_08095420 / sub_0809545C: a type $C / $D object at (0, -16) running the
-- script in intVariable ($D also gets a type-2 object on it)
N[0x08095420] = function(f, e, ctx)
  f:spawn({ kind = 6, id = 0x6A, paramA = 0x0C, paramB = 0, x = e.x, y = e.y - 16, paramC = ctx.intVariable, pool = 0x4F })
end
N[0x0809545C] = function(f, e, ctx)
  local p = f:spawn({ kind = 6, id = 0x6A, paramA = 0x0D, paramB = 0, x = e.x, y = e.y - 16, paramC = ctx.intVariable, pool = 0x4F })
  if p then
    local o = f:spawn({ kind = 6, id = 0x6A, paramA = 0x02, paramB = 0, x = p.x, y = p.y, paramC = 0, pool = 0x0F })
    if o then o.parent = p end
  end
end
-- script.c CheckEntityOnScreen ($0807F8BC)
N[0x0807F8BC] = function(f, e, ctx)
  local sx, sy = e.x - (f.camX or 0), e.y - (f.camY or 0)
  ctx.condition = (sx >= -16 and sx < 256 and sy >= -16 and sy < 176) and 1 or 0
end

N[0x0807F338] = function(f, e) e.solid = false; e.noHitbox = true end -- DeleteHitbox

-- script.c CheckAnyKeyPressed: gInput.newKeys
N[0x0807F0D8] = function(f, e, ctx) ctx.condition = f.anyKeyPressed and 1 or 0 end

-- roomInit.c sub_0804BCDC: DoExitTransitionWithType(&gUnk_0813AB80) to
-- Hyrule Castle room 4 (x $C8, y $48, layer 1, facing 4)
N[0x0804BCDC] = function(f)
  f:startTransition({ warpType = 1, area = 0x80, room = 0x04, endX = 0xC8, endY = 0x48, facing = 4, kind = 0, layer = 1 })
end

-- npc4E.c NPC4E_SaveEquippedItems / NPC4E_RestoreEquippedItems (the
-- shield try-out); the sword upgrade swap of the restore is not needed here
N[0x0806DC3C] = function(f, e)
  local eq = f.save.equip or {}
  e.savedEquip = { a = eq.a, b = eq.b }
end
N[0x0806DC58] = function(f, e)
  if e.savedEquip then
    f.save.equip = f.save.equip or {}
    f.save.equip.a, f.save.equip.b = e.savedEquip.a, e.savedEquip.b
  end
end

-- cutsceneMiscObject.c sub_08095810: the ZeldaMagic object (type $11)
-- running script_ZeldaMagic ($08011940)
N[0x08095810] = function(f, e)
  local o = f:spawn({ kind = 6, id = 0x6A, paramA = 0x11, paramB = 0, x = e.x, y = e.y, paramC = 0x08011940, pool = 0x4F })
  if o then o.parent = e end
end

-- SIMPLIFIED (visual only, no script flow): sub_08094B6C / sub_08094B80
-- (spritePriority.b1 3 / 2), nullsub_527, sub_0809567C (a monster object
-- flies at the player: CutsceneMiscObject's own actions are not ported),
-- Create/DeleteRepeatedSoundManager ($0805DDEC / $0805DE18), $08066CA4
N[0x08094B6C] = function(f, e) e.prioB1 = 3 end
N[0x08094B80] = function(f, e) e.prioB1 = 2 end
N[0x08095458] = function() end
N[0x0809567C] = function(f, e) e.flyAtPlayer = true end
N[0x0805DDEC] = function() end
N[0x0805DE18] = function() end
N[0x08066CA4] = function() end

N[0x0807FB28] = function(f, e, ctx, a)
  if (ctx.unk18 or 0) == 0 then f.fillColor = { 1, 1, 1 } end
  ctx.unk18 = (ctx.unk18 or 0) + 1
  if ctx.unk18 >= (ctx.intVariable or 0) then f.fillColor = nil
  else a.commandSize = 0 end
end

-- Round 10: the assembly (script_Npc4EIntroAssembly and the king's /
-- smith's scripts).  Addresses read from the ROM's thumb code:
--   $0807F238 SetPlayerAnimation2 (ldr r2,=gPlayerState; ldr r0,[r1,#4];
--             strh r0,[r2,#8]): gPlayerState.animation = intVariable.
--   $0807F918 PutItemAnySlot (ldr r0,[r1,#4]; bl PutItemOnSlot).
--   kingDaltus.c sub_0806673C: the king's line by progress.
--   npc4E.c sub_0806DCC0: the overworld map cursor to ($7C8, $F8).
N[0x0807F238] = function(f, e, ctx) f.player.scriptAnim = ctx.intVariable end
-- itemUtils.c PutItemOnSlot: a button item (1..$1F) goes on A if A is
-- empty, else B if B is empty, else replaces the button holding an item of
-- the same menu slot; otherwise it is not equipped
function C.putItemOnSlot(f, item)
  if item < 1 or item > 0x1F then return end
  local eq = f.save.equip
  local meta = f.assets.manifest.itemMeta or {}
  local slot
  if not eq.a or eq.a == 0 then slot = "a"
  elseif not eq.b or eq.b == 0 then slot = "b"
  else
    local ms = meta[item] and meta[item].slot
    if ms and meta[eq.a] and meta[eq.a].slot == ms then slot = "a"
    elseif ms and meta[eq.b] and meta[eq.b].slot == ms then slot = "b" end
  end
  if slot then f:equip(slot, item) end
end
N[0x0807F918] = function(f, e, ctx) C.putItemOnSlot(f, ctx.intVariable or 0) end
N[0x0806673C] = function(f, e)
  local idx
  if not f:flag("global", 0x02) then idx = 0x1058          -- LV1_CLEAR
  elseif f:inventory(2) == 0 then idx = 0x1326             -- ITEM_GREEN_SWORD
  elseif f:inventory(3) == 0 then idx = 0x1329             -- ITEM_RED_SWORD
  else idx = 0x132E end
  f:message(idx, e)
end
N[0x0806DCC0] = function(f)
  f.save.mapStatus = f.save.mapStatus or {}
  f.save.mapStatus.owx, f.save.mapStatus.owy = 0x7C8, 0xF8
end

return C
