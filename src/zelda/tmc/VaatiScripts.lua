-- Round 27 (team B): the Dark Hyrule Castle cutscenes' C side -- the NPC
-- bodies, objects and script natives the DHC scripts (data/scripts/dhc/*.inc)
-- need so each Vaati fight starts from its own cartridge script.  The scripts
-- themselves run from the ROM (Script.lua); R27B.lua dispatches here.
--
-- ENTITY BODIES: Field gives every scripted entity (pool $4x) a Script, but no
--   per-id C code.  M.frame (R27B.frame, every Field frame) attaches a body
--   from M.BODY[kind * 256 + id] to each entity once (its match() decides) and
--   ticks it; SanctuaryScripts.lua registers its bodies in the same table.  A
--   body that owns its animation sets literalAnim (Field then never steps a
--   kind-7 animation: the body calls step()).
--
-- VAATI NPC $27 (src/npc/vaati.c), DHC / Sanctuary areas only:
--   VaatiAction0: drawn, unk_68 / unk_69 0, PRIO_MESSAGE.  VaatiAction1: the
--   script, sub_08066B74 (postScriptActions bits 20..28: unk_80 =
--   animationState / 2 + $10, $14, ... $30; bit 29 unk_68 1, 30 unk_68 $FF,
--   31 unk_69 ^= 1) then HandlePostScriptActions; unk_69 set -> every 4th
--   frame sub_08095CB0 (a CUTSCENE_MISC_OBJECT $1B afterimage: his frame, 16
--   frames, blinking the last 8); the frame byte (& ~$80): 1 SFX_21C, 2
--   SFX_21E, 3 intVariable 4 + CreateRepeatedSoundManager, 4 intVariable 4 +
--   DeleteRepeatedSoundManager + SFX_21D.  Vaati_Apparate ($08066C94):
--   CreateVaatiApparateManager(0) + SFX_APPARATE.
-- VAATI_REBORN NPC $3B (src/npc/vaatiReborn.c, the Vaati 2 room $8C:00):
--   type 0 starts $A0 up (timer 160, spriteOffsetY $20), makes four type 2
--   (type2 0..3: gUnk_08112F80 + (0, $21) from it, flipX when type2 & 2, its
--   draw flag) and a type 1 (33 below it); everyone waits for room flag 3
--   (script_CutsceneOrchestratorV2Intro sets it).  Type 0 then comes down 1
--   px a frame (SFX_1A9 every 32) and at 0 makes type 3 there, shows
--   TEXT_VAATI2 $34 and goes.  Type 3 makes type 4 / type 5 (the overlay
--   parts, animated once its subAction is not 0), waits 1 frame, its
--   animation 0 to the end, then palette $13F + animation 1, ten frames with
--   bit $10, SFX_SUMMON + animation 2, at its end room flag 0 (VAATI_
--   TRANSFIGURED starts, BossVaati2.lua) and it goes.
-- VAATI1_PORTAL $AB (src/object/vaati1Portal.c, $89:00): layer 1, priority 7,
--   animation 0 frozen until room flag 0, then to its end (action 2); room
--   flag 1 -> sub_080A0190 (Link onto it, PLAYER_FALL, PL_PIT_IS_EXIT) and
--   CreateHoleManager($37) when he is within 16 px (Holes.lua / PlayerFall).
-- NPC4E_DoScreenTransition indices 4 (V1 defeated -> AREA_VAATI_2 room 0 at
--   $B0,$D8 layer 2), 5 (V2 defeated -> DHC 3F Triple Darknut at $A8,$78) and
--   2 (the castle collapsing -> DHC 1F Entrance at $198,$168, gUnk_0813ABE4),
--   gNpc4ETransitions (src/data/screenTransitions.c gUnk_0813AC0C / AC20),
--   added to BossVaati3.NPC4E_TRANSITIONS.
-- ZELDA NPC $28 in DHC (zelda.c): sub_08066E50 (animation $4C),
--   sub_08066E80 (animation $16, the hop at its frame bit 1: zVelocity 2.0,
--   SFX_PLY_JUMP, $100 south with gravity 32, landing animation $1E to its
--   end); HandleEntity0x82Actions bit $10 (spriteOffsetX jitter) for the
--   DoPostScriptAction $10 of the stone scripts.
-- SANCTUARY_STONE_TABLET $A6 (object/sanctuaryStoneTablet.c, native
--   sub_0807F8E8): made on the script's entity, objFlags = (intVariable &
--   $3FF) | $8000 (a room flag); set already -> gone.  Hit by the Four Sword's
--   spiral beam (contactFlags CONTACT_NOW | $21) -> FX_MAGIC_STORM (priority
--   3, offset -5), the flag, gone.
-- PLAYER_ITEM_SPIRAL_BEAM (playerItemSpiralBeam.c): a sword swing's frame
--   with frameSpriteSettings & 1 while Link has the Four Sword
--   (SKILL_FOURSWORD, itemSword.c) makes one: Link's position, speed $380 the
--   way he faces, animation (state >> 1) + $C of sprite 175, 60 frames;
--   a wall or a contact -> FX_SWORD_MAGIC.  SIMPLIFIED: the wall test
--   (sub_080B1BA4 / sub_080040D8 with gUnk_08003E44) is "solid on both
--   layers" (the beam flies over a raised dais's edge, as on the cartridge).
-- OTHER NATIVES: ReadPlayerAnimationState, SetEntityHeight, DisablePauseMenu,
--   StartDarkNutTimer (gSave.darknut_timer 10800, counted down in DHC;
--   DarknutTimerHandler -> ResetTimerFlags), sub_080752AC (Link walks out of
--   a door: LinearMoveUpdate until off ACT_TILE_41, then 6 frames),
--   sub_0804D7EC / sub_0804D810 (SPECIAL_TILE_114 on gUnk_080EAE00's tiles
--   and back), sub_08094F98 (CUTSCENE_MISC_OBJECT type 5: a falling rock every
--   32 frames somewhere on screen, from z -160, gravity 32, landing animation
--   1 + SFX_LAVA_TILE_FLIP; over a pit (ACT_TILE_13) it falls on off screen),
--   sub_0807F714 / sub_0807F738 (draw above / below).
--
-- SIMPLIFIED: the VAATI_APPARATE_MANAGER's BG3 wave (a gfx group swirling
--   around him) is not drawn (the sound plays); CreateRepeatedSoundManager is
--   Ceremony.lua's no-op; the darknut timer has no HUD clock and its timeout
--   only clears the flags (no MenuFadeIn); the spiral beam hits only the stone
--   tablets (its enemy contact is not ported); the afterimage blinks by draw.
local bit = require("bit")
local band, bor, bxor, rshift, lshift = bit.band, bit.bor, bit.bxor, bit.rshift, bit.lshift

local M = {}

M.ROM_RANGES = {
  dhcZeldaRing = { 0x080EAE00, 0x080EAE20 }, -- gUnk_080EAE00 (data_080D5360/gUnk_080EAE00.bin): u16 tile positions, 0-terminated
}

local SFX = { APPARATE = 0xF7, EVAPORATE = 0xF6, S21C = 0x21C, S21D = 0x21D, S21E = 0x21E, S1A9 = 0x1A9,
              SUMMON = 0xF4, PLY_JUMP = 0x7C, LAVA_TILE_FLIP = 0x17E, ITEM_SWORD_BEAM = 0x13F } -- include/sound.h
M.SFX = SFX
local SPECIAL_FX, FX_MAGIC_STORM, FX_SWORD_MAGIC = 0x0F, 78, 25
local SP114 = 0x4072
local ACT_TILE_13, ACT_TILE_41 = 0x0D, 0x29
local TEXT_VAATI2 = 0x16

M.AREAS = { [0x78] = true, [0x81] = true, [0x88] = true, [0x89] = true, [0x8A] = true, [0x8B] = true, [0x8C] = true, [0x8D] = true }
local function inArea(f) return f.room and M.AREAS[f.room.area] end

-- ---------------------------------------------------------------- helpers
local function Script() return require("src.zelda.tmc.Script") end
local function anim(f, e, a)
  e.literalAnim = true
  e.objAnim, e.animIndex, e.forceAnim = a, a, nil
  local spr = e.sprite and f.assets:sprite(e.sprite)
  if spr then e.anim:set(spr, a, true) end
  e._lk, e._lt = nil, nil
end
M.anim = anim
-- one animation step (the body owns the animation); true when a keyframe was loaded
local function step(e)
  local a = e.anim
  local k0, t0 = a.key, a.timer
  a:update(1)
  return a.key ~= k0 or a.timer > t0
end
M.step = step
-- a keyframe loaded since the last call (Field steps the animation)
local function newKey(e)
  local a = e.anim
  local k, t = a.key, a.timer
  local nk = (e._lk ~= k) or (e._lt ~= nil and t > e._lt)
  e._lk, e._lt = k, t
  return nk
end
M.newKey = newKey
local function fx(f, x, y, t) if f.addFx then return f:addFx(x, y, SPECIAL_FX, t) end end
M.fx = fx
local function sound(f, s) if f.sound then f:sound(s) end end

-- the generic HandlePostScriptActions bits Script.lua does not cover (3,
-- 15..19) and HandleEntity0x82Actions $10 / $20
function M.postExtra(ctx, e)
  local a = ctx.postScriptActions or 0
  if band(a, 0x8) ~= 0 then e.zVelocity = 1.5 end
  if band(a, 0x8000) ~= 0 then e.field82 = bxor(e.field82 or 0, 4) end
  if band(a, 0x10000) ~= 0 then e.field82 = bxor(e.field82 or 0, 0x10) end
  if band(a, 0x20000) ~= 0 then e.flipX = not e.flipX end
  if band(a, 0x40000) ~= 0 then e.field82 = bor(e.field82 or 0, 0x20) end
  if band(a, 0x80000) ~= 0 then e.field82 = band(e.field82 or 0, bit.bnot(0x20)) end
  ctx.postScriptActions = band(a, bit.bnot(0xF8008))
  if band(a, 0x200) ~= 0 then e.spriteOX, e.spriteOY = nil, nil end
end
local JITTER = { [0] = -1, -2, 0, 1 }
function M.e82(f, e)
  local v = e.field82 or 0
  if band(v, 0x10) ~= 0 then
    if (f.frame or 0) % 2 == 0 then e.spriteOX = JITTER[math.random(0, 3)] end
  elseif e._jit then e.spriteOX = nil end
  e._jit = band(v, 0x10) ~= 0
end
-- install a postScriptActions handler on an entity's script (Field calls
-- e.script:postActions(e) after each run)
function M.hookPost(e, fn)
  local s = e.script
  if not s or s._r27post then return end
  s._r27post = true
  s.postActions = function(self, ent)
    if fn then fn(self, ent) end
    M.postExtra(self, ent)
    Script().postActions(self, ent)
  end
end

-- ---------------------------------------------------------------- bodies
M.BODY = {}
local function body(kind, id, b) M.BODY[kind * 256 + id] = b end
M.body = body

function M.frame(f, input)
  -- a room transition after a closed iris (script_Npc4ECastleCollapsing's
  -- SetFadeIrisInOut, then NPC4E_DoScreenTransition): the exit transition's
  -- fade takes over from black (as Field:fade does for a plain fade), the
  -- closed window is dropped so the new room fades in
  if f.transition and f.iris and f.iris.out and not f.iris.active and inArea(f) then f.iris = nil; f.fadeLevel = 1 end
  if (f.menu and f.menu.open) or f.transition or f.gameOver or not f.entities then return false end
  M.darknutTick(f)
  M.spiralCheck(f)
  local ents = f.entities
  for i = 1, #ents do
    local e = ents[i]
    if e and not e.deleted then
      local b = e.r27vBody
      if b == nil then
        b = M.BODY[(e.kind or 0) * 256 + (e.id or 0)] or false
        if b and b.match and not b.match(f, e) then b = false end
        e.r27vBody = b
        if b and b.init then b.init(f, e) end
      end
      if b and b.tick and not e.deleted then b.tick(f, e) end
    end
  end
  return false
end

-- an entity drawn as one fixed frame (afterimages)
function M.drawStatic(e, f, camX, camY)
  if e.hidden or not e.frameNo or e.frameNo == 0xFF or not (love and love.graphics and love.graphics.draw) then return end
  local img, ox, oy = f.assets:spriteFrame(e.sprite, e.frameNo, e.palette, "r27v" .. tostring(e.sprite), e.gfx)
  if not img then return end
  local x = math.floor(e.x - camX + (e.spriteOX or 0))
  local y = math.floor(e.y - camY - (e.z or 0) + (e.spriteOY or 0))
  if e.flipFrame then love.graphics.draw(img, x - ox, y + oy, 0, -1, 1) else love.graphics.draw(img, x + ox, y + oy) end
end

-- ---------------------------------------------------------------- Vaati $27
local VAATI_ANIM = { [20] = 0x10, [21] = 0x14, [22] = 0x18, [23] = 0x1C, [24] = 0x20, [25] = 0x24, [26] = 0x28, [27] = 0x2C, [28] = 0x30 }
function M.vaatiPost(ctx, e) -- sub_08066B74
  local a = ctx.postScriptActions or 0
  local hi = band(a, lshift(0xFFF, 20))
  ctx.postScriptActions = band(a, 0xFFFFF)
  if hi == 0 then return end
  local st = rshift(e.animationState or 0, 1)
  for b = 20, 31 do
    if band(hi, lshift(1, b)) ~= 0 then
      if VAATI_ANIM[b] then e.field80 = st + VAATI_ANIM[b]
      elseif b == 29 then e.u68 = 1
      elseif b == 30 then e.u68 = 0xFF
      else e.u69 = bxor(e.u69 or 0, 1) end
    end
  end
end
function M.afterimage(f, e) -- sub_08095CB0
  local a = e.anim
  local im = { kind = 6, id = 0x6A, form = 0x1B, x = e.x, y = e.y, z = e.z or 0, sprite = e.sprite, palette = e.palette,
               gfx = e.gfx, frameNo = a and a.frame, flipFrame = a and a:hflip() ~= (e.flipX or false), timer = 16,
               anim = require("src.zelda.tmc.Anim").new(), animationState = 0, field80 = 0, field82 = 0, interactType = 0,
               spritePriority = e.spritePriority, r27vBody = M.BODY[6 * 256 + 0x6A] }
  im.drawGhost = M.drawStatic
  f.entities[#f.entities + 1] = im
  e.child = im
  return im
end
body(7, 0x27, {
  match = function(f) return inArea(f) end,
  init = function(f, e) -- VaatiAction0
    e.hidden = false
    e.u68, e.u69 = 0, 0
    e.talkable, e.solid = false, false
    M.hookPost(e, M.vaatiPost)
  end,
  tick = function(f, e) -- VaatiAction1 (the script itself runs in Field's loop)
    if not e.script or not e.script._r27post then M.hookPost(e, M.vaatiPost) end
    if (e.u69 or 0) ~= 0 and (f.frame or 0) % 4 == 0 and not e.hidden then M.afterimage(f, e) end
    if e.anim and newKey(e) then
      local fr = band(e.anim.flags or 0, 0x7F)
      if fr == 1 then sound(f, SFX.S21C)
      elseif fr == 2 then sound(f, SFX.S21E)
      elseif fr == 3 then if e.script then e.script.intVariable = 4 end
      elseif fr == 4 then if e.script then e.script.intVariable = 4 end sound(f, SFX.S21D) end
    end
    M.e82(f, e)
  end,
})

-- ---------------------------------------------------------------- VaatiReborn $3B
local REBORN_OFS = { [0] = { 10, -29 }, { -10, -29 }, { 15, -21 }, { -15, -21 } } -- gUnk_08112F80
local function alive(p) return p and not p.deleted and p end
local function spawnNpc(f, id, typ, type2, x, y)
  local e = f:spawn({ kind = 7, id = id, paramA = typ, paramB = type2 or 0, pool = 0x0F, x = x, y = y, paramC = 0 })
  return e
end
M.spawnNpc = spawnNpc
local function rebornPos(f, e) -- sub_0806B96C
  local p = alive(e.parent)
  if not p then e.deleted = true return end
  local o = REBORN_OFS[band(e.param or 0, 3)]
  e.hidden = p.hidden
  e.x, e.y = p.x + o[1], p.y + o[2] + 0x21
end
local reborn = {}
reborn.init = function(f, e) -- VaatiRebornAction0
  e.talkable, e.solid = false, false
  e.action, e.subAction, e.timer = 1, 0, 0
  local t = e.form or 0
  if t == 0 then
    e.y = e.y - 0xA0
    e.timer, e.subtimer = 160, 32
    e.spriteOY = 0x20
    for i = 0, 3 do local c = spawnNpc(f, 0x3B, 2, i, e.x, e.y) if c then c.parent = e end end
    local c = spawnNpc(f, 0x3B, 1, 0, e.x, e.y + 1)
    if c then c.parent = e; c.spriteOY = -1 end
    anim(f, e, 0)
  elseif t == 1 or t == 5 then anim(f, e, 0)
  elseif t == 2 then
    if band(e.param or 0, 2) ~= 0 then e.flipX = true end
    if e.parent then rebornPos(f, e) end
    anim(f, e, 0)
  elseif t == 3 then
    e.timer, e.subtimer = 1, 32
    local c = spawnNpc(f, 0x3B, 4, 0, e.x, e.y)
    if c then c.parent = e; c.spritePriority = (e.spritePriority or 4) - 1 end
    c = spawnNpc(f, 0x3B, 5, 0, e.x, e.y)
    if c then c.parent = e; c.spritePriority = (e.spritePriority or 4) + 1 end
    anim(f, e, 0)
  elseif t == 4 then anim(f, e, 0) end
end
reborn.tick = function(f, e) -- VaatiRebornAction1
  if not e.action then reborn.init(f, e) end
  if not f:flag("room", 3) then return end
  local t = e.form or 0
  if t == 0 then
    e.y = e.y + 1
    e.timer = e.timer - 1
    if e.timer == 0 then
      local c = spawnNpc(f, 0x3B, 3, 0, e.x, e.y)
      if not c then return end
      c.y = e.y
      f:message(TEXT_VAATI2 * 256 + 0x34, e)
      e.subAction = e.subAction + 1
      e.deleted = true
      return
    end
    e.subtimer = e.subtimer - 1
    if e.subtimer == 0 then e.subtimer = 32; sound(f, SFX.S1A9) end
    step(e)
  elseif t == 1 then
    local p = alive(e.parent)
    if not p then e.deleted = true return end
    e.x, e.y = p.x, p.y + 33
    step(e)
  elseif t == 2 then
    rebornPos(f, e)
    step(e)
  elseif t == 3 then
    local loaded = false
    if e.subAction == 0 then
      e.timer = e.timer - 1
      if e.timer == 0 then e.subAction = 1 end
    elseif e.subAction == 1 then
      if e.anim.done then
        e.subAction = 2
        e.palette = f.assets:objPalette(0x13F)
        anim(f, e, 1)
      end
    elseif e.subAction == 2 then
      if e._b10 then
        e._b10 = nil
        e.timer = e.timer + 1
        if e.timer == 10 then
          e.subAction = 3
          sound(f, SFX.SUMMON)
          e.timer = 0
          anim(f, e, 2)
        end
      end
    elseif e.subAction == 3 then
      if e.anim.done then
        f:setFlag("room", 0, true)
        e.deleted = true
        return
      end
    end
    e.subtimer = e.subtimer - 1
    if e.subtimer == 0 then e.subtimer = 32; sound(f, SFX.S1A9) end
    loaded = step(e)
    if loaded and band(e.anim.flags or 0, 0x10) ~= 0 then e._b10 = true end
  else
    local p = alive(e.parent)
    if not p then e.deleted = true return end
    if (p.subAction or 0) == 0 then return end
    step(e)
  end
end
body(7, 0x3B, { init = reborn.init, tick = reborn.tick })
M.reborn = reborn

-- ---------------------------------------------------------------- afterimage ($6A type $1B)
-- CUTSCENE_MISC_OBJECT type $1B (CutsceneMiscObject_Type27): `timer` frames,
-- the draw flag toggled each frame under 8; other $6A types are
-- SanctuaryScripts' (M.MISC[type])
M.MISC = {}
M.MISC[0x1B] = { tick = function(f, e)
  if (e.timer or 0) ~= 0 then
    e.timer = e.timer - 1
    if e.timer < 8 then e.hidden = not e.hidden end
    if e.timer ~= 0 then return end
  end
  e.deleted = true
end }
body(6, 0x6A, {
  match = function(f, e) return inArea(f) and M.MISC[e.form or -1] ~= nil and (M.MISC[e.form].match == nil or M.MISC[e.form].match(f, e)) end,
  init = function(f, e) local m = M.MISC[e.form] if m.init then m.init(f, e) end end,
  tick = function(f, e) local m = M.MISC[e.form] if m.tick then m.tick(f, e) end end,
})

-- CUTSCENE_MISC_OBJECT type 5 (sub_08094F98: the castle crumbling)
local function rnd(n) return math.random(0, n - 1) end
local function dressMisc(f, e, typ)
  local O = f:objects()
  local def = O and O:def(0x6A, typ)
  if def then O:dress(e, def, 0) end
  return def
end
M.dressMisc = dressMisc
local function newObj(f, id, typ, type2, x, y)
  local e = { kind = 6, id = id, form = typ, type2 = type2 or 0, param = type2 or 0, x = x or 0, y = y or 0, z = 0,
              animationState = 0, field80 = 0, field82 = 0, interactType = 0, speed = 0x100,
              anim = require("src.zelda.tmc.Anim").new() }
  return e
end
M.newObj = newObj
M.MISC[5] = {
  tick = function(f, e)
    local d = f:dungeon()
    if (e.type2 or 0) == 0 then
      e.hidden = true
      if (f.frame or 0) % 32 == 0 then
        local p = newObj(f, 0x6A, 5, 1, (f.camX or 0) + rnd(240), (f.camY or 0) + rnd(160))
        if dressMisc(f, p, 5) then f.entities[#f.entities + 1] = p end
      end
      return
    end
    if (e.type2 or 0) == 1 then
      if not e.act then
        e.act, e.cz, e.czv = 1, -160, 0
        anim(f, e, 0)
        if d and d:actAt(e.x, e.y, e.layer or 1) == ACT_TILE_13 then e.act = 3 end
      elseif e.act == 1 or e.act == 3 then
        e.cz = e.cz - e.czv
        e.czv = e.czv - 0.125
        if e.act == 1 and e.cz > 0 then
          e.act, e.cz, e.czv = 2, 0, 0
          anim(f, e, 1)
          sound(f, SFX.LAVA_TILE_FLIP)
        elseif e.act == 3 and (e.y - (f.camY or 0) + e.cz) > 200 then e.deleted = true end
      elseif e.act == 2 then
        step(e)
        if e.anim.done then e.deleted = true end
      end
      e.z = -(e.cz or 0)
    end
  end,
}

-- ---------------------------------------------------------------- Zelda $28 (DHC)
body(7, 0x28, {
  match = function(f, e) return inArea(f) end,
  init = function(f, e) M.hookPost(e) end,
  tick = function(f, e)
    if e.script and not e.script._r27post then M.hookPost(e) end
    M.e82(f, e)
    if e.zelHop then M.zeldaHopDraw(e) end
  end,
})
-- NPC_UNK_4E (npc4E.c), the scripts' invisible host: DoPostScriptAction 8
-- clears its draw flag, but an interactable one (MakePedestalInteractable,
-- AddInteractableCheckableObject) still answers on the cartridge; it has no
-- sprite, so it is kept "shown" for Field:tryInteract
body(7, 0x4E, {
  match = function(f) return inArea(f) end,
  tick = function(f, e) if e.hidden and not e.sprite and e.talkable then e.hidden = false end end,
})
function M.zeldaHopDraw(e) e.z = math.max(0, e.zelHop.z or 0) end

-- ---------------------------------------------------------------- natives
local N = require("src.zelda.tmc.Native").N
local function stay(a) a.commandSize = 0 end
local function keepGoing(a) a.flags = bor(a.flags, 1) end

N[0x08066C94] = N[0x08066C94] or function(f, e) -- Vaati_Apparate
  sound(f, SFX.APPARATE)
end
N[0x0807F584] = N[0x0807F584] or function(f, e, ctx) ctx.intVariable = rshift(f.player.animationState or 0, 1) end -- ReadPlayerAnimationState
N[0x0807F98C] = N[0x0807F98C] or function(f, e, ctx) -- SetEntityHeight (z.WORD, negative = up)
  local v = ctx.intVariable or 0
  if v >= 0x80000000 then v = v - 0x100000000 end
  e.z = -v / 65536
end
N[0x0807DF38] = N[0x0807DF38] or function(f) f.menuDisabled = true end -- DisablePauseMenu
N[0x08053494] = N[0x08053494] or function(f) f.save.darknutTimer = 10800 end -- StartDarkNutTimer
N[0x0807F714] = N[0x0807F714] or function(f, e) e.overLink = true end   -- sub_0807F714: sorted above
N[0x0807F738] = N[0x0807F738] or function(f, e) e.overLink = nil; e.spritePriority = math.min(7, (e.spritePriority or 4) + 1) end -- sorted below
N[0x080752AC] = N[0x080752AC] or function(f, e, ctx, a) -- sub_080752AC: out of a door
  local p = f.player
  Script().moveAngle(p, p.speed or 0x100, p.angle or 0)
  if (ctx.unk18 or 0) == 0 then
    local d = f:dungeon()
    if not (d and d:actAt(p.x, p.y, p.layer or 1) == ACT_TILE_41) then ctx.unk18, ctx.unk19 = 1, 6 end
  else
    ctx.unk19 = ctx.unk19 - 1
    if ctx.unk19 == 0 then return end
  end
  stay(a)
end
-- sub_0804D7EC / sub_0804D810: SPECIAL_TILE_114 on gUnk_080EAE00 and back
local function ringTiles(f)
  local T = require("src.zelda.tmc.ExtractR26").tables(f, "dhcZeldaRing")
  local out = {}
  if T then
    for i = 0, 15 do
      local v = T.u16(0x080EAE00 + 2 * i)
      if v == 0 then break end
      out[#out + 1] = v
    end
  end
  return out
end
M.ringTiles = ringTiles
N[0x0804D7EC] = N[0x0804D7EC] or function(f)
  local tl = require("src.zelda.tmc.DHCObjects")._tile
  M.ringSaved = { room = f.room, tiles = {} }
  for _, pos in ipairs(ringTiles(f)) do
    M.ringSaved.tiles[pos] = tl.get(f, 1, pos)
    tl.set(f, 1, pos, SP114)
  end
end
N[0x0804D810] = N[0x0804D810] or function(f)
  local s = M.ringSaved
  if not s or s.room ~= f.room then return end
  local tl = require("src.zelda.tmc.DHCObjects")._tile
  for pos, mt in pairs(s.tiles) do if mt then tl.set(f, 1, pos, mt) end end
  M.ringSaved = nil
end
N[0x08094F98] = N[0x08094F98] or function(f) -- CreateObject(CUTSCENE_MISC_OBJECT, 5, 0)
  local e = newObj(f, 0x6A, 5, 0, 0, 0)
  e.hidden, e.sprite = true, 0
  e.r27vBody = nil
  f.entities[#f.entities + 1] = e
end
N[0x08066E50] = N[0x08066E50] or function(f, e) e.field80 = 0x4C; e.animIndex = nil end -- Zelda: animation $4C
N[0x08066E80] = N[0x08066E80] or function(f, e, ctx, a) -- Zelda's hop
  local s = ctx.unk18 or 0
  e.zelHop = e.zelHop or { z = 0, v = 0 }
  local h = e.zelHop
  if s == 0 then
    ctx.unk18 = 1
    e.field80 = 0x16; e.animIndex = nil
  elseif s == 1 then
    if band(e.anim.flags or 0, 1) ~= 0 then
      ctx.unk18 = 2
      h.v = 2.0
      sound(f, SFX.PLY_JUMP)
    end
  elseif s == 2 or s == 3 then
    Script().moveAngle(e, 0x100, 0x80)
    h.z = h.z + h.v
    h.v = h.v - 0.125
    if s == 2 and h.v < 0 then ctx.unk18 = 3 end
    if s == 3 and h.z <= 0 then
      h.z, h.v = 0, 0
      ctx.unk18 = 4
      e.field80 = 0x1E; e.animIndex = nil
    end
  elseif s == 4 then
    if e.anim.done and e.animIndex == 0x1E then
      e.zelHop = nil; e.z = 0
      keepGoing(a)
      return
    end
  end
  if e.zelHop then e.z = math.max(0, h.z) end
  stay(a)
end

-- ---------------------------------------------------------------- stone tablet
-- SANCTUARY_STONE_TABLET: sub_0807F8E8 (src/script.c) makes it on the entity
function M.spawnTablet(f, parent, spec)
  if f:dungeon() and f:dungeon():check(spec) then return nil end
  local t = { kind = 6, id = 0xA6, tablet = true, parent = parent, flagSpec = spec, x = parent.x, y = parent.y,
              hidden = true, ticker = true, interactType = 0, field80 = 0, field82 = 0 }
  t.extUpdate = function(d, me) M.tabletUpdate(d.field, me) end
  t.room = f.room
  local d = f:dungeon()
  if d then d:track(t) end
  local live = M.liveTablets(f)
  live[#live + 1] = t
  return t
end
-- this room's tablets (a room change drops the others)
function M.liveTablets(f)
  local out = {}
  for _, t in ipairs(M.tablets or {}) do if not t.deleted and t.room == f.room then out[#out + 1] = t end end
  M.tablets = out
  return out
end
local function overlap(ax, ay, aw, ah, bx, by, bw, bh)
  return math.abs(ax - bx) < aw + bw and math.abs(ay - by) < ah + bh
end
function M.tabletUpdate(f, t)
  if t.deleted then return end
  local p = t.parent
  if p then t.x, t.y = p.x, p.y end
  for _, b in ipairs(f.entities) do
    -- gHitbox_0 {0, -3, 6 x 6} against the beam's {0, 0, 6 x 6}
    if b.spiral and not b.deleted and overlap(t.x, t.y - 3, 6, 6, b.x, b.y, 6, 6) then
      local x = fx(f, t.x, t.y, FX_MAGIC_STORM)
      if type(x) == "table" then x.spritePriority = 3; x.spriteOY = -5 end
      f:dungeon():set(t.flagSpec)
      t.deleted = true
      b.hitTablet = true
      return
    end
  end
end
N[0x0807F8E8] = N[0x0807F8E8] or function(f, e, ctx)
  M.spawnTablet(f, e, bor(band(ctx.intVariable or 0, 0x3FF), 0x8000))
end

-- ---------------------------------------------------------------- spiral beam
local SPIRAL_SPEED = 0x380 / 256
local DIRV = { [0] = { 0, -1 }, [2] = { 1, 0 }, [4] = { 0, 1 }, [6] = { -1, 0 } }
function M.spawnSpiral(f, p)
  local s = band(p.animationState or 4, 6)
  local b = { kind = 8, id = 0x14, spiral = true, hitType = 0x21, x = p.x, y = p.y, z = 0, layer = p.layer or 1, dir = s,
              life = 60, sprite = 175, animationState = s, field80 = 0, field82 = 0, interactType = 0,
              anim = require("src.zelda.tmc.Anim").new() }
  b.palette = f.assets:objPalette(0)
  local spr = f.assets:sprite(175)
  if spr then b.anim:set(spr, rshift(s, 1) + 0xC, true) end
  b.drawGhost = function(me, field, camX, camY)
    me.frameNo = me.anim.frame
    me.flipFrame = me.anim:hflip()
    M.drawStatic(me, field, camX, camY)
  end
  b.extUpdate = function(_, me) M.spiralUpdate(f, me) end
  local v = DIRV[s]
  b.x, b.y = b.x + v[1] * SPIRAL_SPEED, b.y + v[2] * SPIRAL_SPEED -- the Init's LinearMoveUpdate
  f.entities[#f.entities + 1] = b
  if f:dungeon() then f:dungeon():track(b) end
  sound(f, SFX.ITEM_SWORD_BEAM)
  M.spiralUpdate(f, b)
  return b
end
function M.spiralUpdate(f, b)
  if b.deleted then return end
  if b.life <= 0 then b.deleted = true return end
  b.life = b.life - 1
  b.anim:update(1)
  local v = DIRV[b.dir]
  b.x, b.y = b.x + v[1] * SPIRAL_SPEED, b.y + v[2] * SPIRAL_SPEED
  for _, t in ipairs(M.liveTablets(f)) do M.tabletUpdate(f, t) end
  local r = f.room
  if b.hitTablet or (r and r.isSolid and r:isSolid(b.x, b.y, 1) and r:isSolid(b.x, b.y, 2)) then
    fx(f, b.x, b.y, FX_SWORD_MAGIC)
    b.deleted = true
    return
  end
end
-- the swing's beam frame with the Four Sword (checked at the top of each
-- Field frame: the swing itself is ItemsR26 / SwordSkills', which run before
-- R27B.playerFrame and take Link's whole frame)
function M.spiralCheck(f)
  local p = f.player
  if not p then return end
  if p.state ~= "sword" then p.r27spiral = nil return end
  local v = f:inventory(6)
  if not (v == true or (type(v) == "number" and v >= 1)) then return end
  if band(p.anim and p.anim.flip or 0, 1) ~= 0 and not p.r27spiral then
    p.r27spiral = true
    M.spawnSpiral(f, p)
  end
end

-- ---------------------------------------------------------------- darknut timer
-- ResetTimerFlags sClearFlags (gameUtils.c): FLAG_BANK_10 ($8C0) LV6_GUFUU1_GISHIKI $77, _DEMO $78,
-- LV6_ZELDA_DISCURSE $79, LV6_00_ESCAPE $7A, LV6_GUFUU2_DEAD $7B, global ENDING $51, LV6_KANE_START $7C,
-- _1ST $7D, _2ND $7E, LV6_SOTO_ENDING $7F (include/flags.h, the bank's first id $FD2 as the ROM's
-- script_KingDaltusStone reads LV6_1d_KEYGET $71 / LV6_39_KING $96)
local TIMER_FLAGS = { { 0x8C0, 0x77 }, { 0x8C0, 0x78 }, { 0x8C0, 0x79 }, { 0x8C0, 0x7A }, { 0x8C0, 0x7B }, { "g", 0x51 },
                      { 0x8C0, 0x7C }, { 0x8C0, 0x7D }, { 0x8C0, 0x7E }, { 0x8C0, 0x7F } }
M.TIMER_FLAGS = TIMER_FLAGS
function M.darknutTick(f)
  local s = f.save
  if not s or not s.darknutTimer or s.darknutTimer <= 0 then return end
  if not (f.room and f.room.area == 0x88) then return end
  s.darknutTimer = s.darknutTimer - 1
  if s.darknutTimer == 0 then
    if f:flag("bank", 0x79, 0x8C0) then f:setFlag("global", 0x1C, false) end -- LV6_ZELDA_DISCURSE -> ZELDA_CHASE
    for _, t in ipairs(TIMER_FLAGS) do
      if t[1] == "g" then f:setFlag("global", t[2], false) else f:setFlag("bank", t[2], false, t[1]) end
    end
  end
end

-- ---------------------------------------------------------------- objects
M.VAATI1_PORTAL = 0xAB
function M.spawnObject(d, e)
  if e.id ~= M.VAATI1_PORTAL then return nil end
  local f = d.field
  local O = f:objects()
  local def = O:def(M.VAATI1_PORTAL, e.form or 0)
  if def then O:dress(e, def, 0) end
  e.layer = 1
  e.oamPrio, e.spritePriority = 3, 7
  e.action = 1
  anim(f, e, 0)
  e.extUpdate = function(dd, me) M.portalUpdate(dd.field, me) end
  d:track(e)
  return e
end
function M.portalUpdate(f, e)
  if e.action == 1 then
    if f:flag("room", 0) then
      step(e)
      if e.anim.done then e.action = 2 end
    end
  elseif e.action == 2 and f:flag("room", 1) and not e.fell then
    local p = f.player
    local inRect = math.abs(p.x - e.x) <= 0x10 and math.abs(p.y - e.y) <= 0x10
    p.x, p.y = e.x, e.y -- sub_080A0190: CopyPosition, PLAYER_FALL, PL_PIT_IS_EXIT
    e.fell = true
    local d = f:dungeon()
    local exit
    if inRect then
      require("src.zelda.tmc.Holes").spawn(d, { type = 0x37 })
      exit = require("src.zelda.tmc.Holes").exitFor(d, p)
    end
    require("src.zelda.tmc.PlayerFall").start(d, p, exit)
  end
end

-- ---------------------------------------------------------------- NPC4E transitions
do
  local ok, V3 = pcall(require, "src.zelda.tmc.BossVaati3")
  if ok and type(V3) == "table" and V3.NPC4E_TRANSITIONS then
    local T = V3.NPC4E_TRANSITIONS
    -- gUnk_0813AC0C: WARP_TYPE_AREA, (0xb0, 0xd8), AREA_VAATI_2 room 0, layer 2 (TRANSITION_FADE_WHITE_SLOW)
    T[4] = T[4] or { warpType = 1, area = 0x8C, room = 0, endX = 0xB0, endY = 0xD8, facing = 0, kind = 0, layer = 2 }
    -- gUnk_0813AC20: WARP_TYPE_AREA, (0xa8, 0x78), DHC 3F Triple Darknut, layer 1
    T[5] = T[5] or { warpType = 1, area = 0x88, room = 0x06, endX = 0xA8, endY = 0x78, facing = 0, kind = 0, layer = 1 }
    -- gUnk_0813ABE4: WARP_TYPE_AREA, (0x198, 0x168), DHC 1F Entrance, layer 1, facing 4 (script_Npc4ECastleCollapsing,
    -- the escape starts: the fall-through end of script_Npc4EAfterDefeatingV2 in $89:00)
    T[2] = T[2] or { warpType = 1, area = 0x88, room = 0x00, endX = 0x198, endY = 0x168, facing = 4, kind = 0, layer = 1 }
  end
end

return M
