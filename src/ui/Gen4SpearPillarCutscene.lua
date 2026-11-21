-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- PLATINUM'S SPEAR PILLAR CINEMATIC: the child application ScrCmd_2FB starts
-- (sub_020985E4 -> sub_0209862C: fade the field out, run the app, restart the
-- field, then let the script go on).  Art: src/import/Gen4SpearPillarArt.lua,
-- cache key gen4_spear_pillar.
--
-- READ FROM CODE: pokeplatinum src/cutscenes/spear_pillar/ (main.c,
-- common.c, pose_sequence.c, light_ball.c, screen_capture.c and the three
-- stages), transcribed state by state.  ALL THREE STAGES PLAY, in order --
-- sCutsceneStages has no variant switch -- so there is no Dialga-or-Palkia
-- choice to make; the only per-save input is the player's gender (Lucas or
-- Dawn's figure, models 61 / 63) and name (message 22).
--
--   main       SpearPillarCutscene_Init: both screens fade in from black
--              over 6 * 2 steps; the message window is BG1 (2, 19) 27x4
--
--   1 DIALGA / PALKIA ARRIVAL (dialga_palkia_arrival.c), 3D on the TOP
--     screen, the Poketch's "unavailable" picture on the bottom:
--     camera  target (0, 0, 34), distance 0x13C805, angle x -0x29FE, fovY
--             0xC01, clip 10..1008 -- then a 60-frame pan of the target
--             -46 in z
--     14      "DIALGA, the mythical Pokemon..."      16 "...And the other."
--     then    the screen-capture trail (eva 4 / evb 12 into VRAM C), the
--             camera shake task, the Dialga ball falling (77/78/80/81 all
--             four tracks), the Palkia ball 60 frames later
--     SE      timer 80 / 135  SEQ_SE_DP_CLIMAX01 panned -70 / +70
--             165 / 220      SEQ_SE_DP_CLIMAX03 -70 / +70
--             284 338 406    SEQ_SE_DP_CLIMAX09
--             310 375 432    SEQ_SE_DP_CLIMAX06
--             470 / 520      SEQ_SE_DP_CLIMAX10 -70 / +70
--     shake   intensity 4 at the Palkia ball, 5 at timer 120, 0xFF at 210,
--             6 when Dialga's ball lands, 7 at Palkia's, 8 to stop
--     land    SEQ_SE_DP_CLIMAX12 -70 / +70; each summon "bubble" (Dialga
--             66+67, Palkia 68+69) grows 0 .3 .6 1 1.2 1.1 1.0 a frame and
--             cries (pan -80 / +80, volume 80)
--     30 frames, then three white flashes of the 3D layer (to 8, to 12,
--             to 16; +1 up, -2 down), the balls are released and the two
--             whirlpools (84) grow 0.1 -> 0.8 by 0.02 a frame
--     18 / 19 Cyrus's creation speech, the whirlpools shrink back, fade out
--
--   2 LAKE GUARDIANS ARRIVAL (lake_guardians_arrival.c), the display SWAPPED
--     -- 3D on the BOTTOM, the sky on top:
--     camera  distance 200, angle x 1274, fovY 0xA66, clip 0.1..2048,
--             target y + 25; the BGM fades out over 10 frames, then
--             SEQ_D_RYAYHY once the screens have faded in
--     sky     sub BG0 = screen 73, sub BG1 = screen 72 with a vertical
--             per-line wave of 2 px; both palettes pulse toward GX_RGB
--             (16, 0, 0) at intensity / 4 (UpdateGuardianFlash)
--     each of Uxie / Mesprit / Azelf: shown and animated for 210 / 120 /
--             120 frames, SEQ_SE_PL_W392 at 100 / 19 / 18, the cry at 145 /
--             119 / 100; the 3D whitens to +16, the guardian vanishes and
--             its light ball flies up to the orbit (light_ball.c)
--     then    120 frames, the SUB screen whitens to +16, a white fade out
--
--   3 GIRATINA INTERVENTION (giratina_intervention.c), still swapped:
--     camera  as stage 1, target y 0; a 60-frame tilt of +20 degrees
--     20      the lake trio named; a 60-frame pan +70 z to the player; 21
--             (Cyrus turns south), 22 (with the player's name), BGM out,
--             the lights start to wander, the screens darken to -6, 23
--     pan     90 frames -80 z; SEQ_PL_EV_GIRA, the shadow pool (41/40);
--             SEQ_SE_PL_W060 at 15 45 75 95 115 130 145 (pitched), Cyrus
--             backs off at 60
--     rise    Giratina's silhouette (26) climbs from y -90 to -50 by 0.5 a
--             frame, the red eyes (42); its settled form (29) to y 0 with
--             the shockwave and the ripple, SEQ_SE_PL_W082C, Cyrus pushed
--             back at 20, Dialga's cry at 40 and Palkia's at 65 (pan
--             -80 / +80, volume 40) as both back away
--     24      "...a Pokemon that can only appear as a shadow."; the wings
--             (32) with the splash (53) and Giratina's field cry; 25; the
--             lunge (35); SEQ_PL_EV_GIRA2 and the attack (38); 26 at 170,
--             the cry again at 238; when the attack ends the 3D goes to
--             -16, the BGM stops, a 1-step fade out and 60 black frames
--     sky     sub BG1 = screen 20 (palette 19, also the main backdrop) with
--             a 4 px wave; colours 0-9 pulse toward 0xCCCC at intensity / 8
--
-- TIMING: the cartridge's main loop waits two VBlanks a pass, so the app,
-- its SysTasks and the screen fade all step at 30 Hz -- once every second
-- engine tick here.  The text printer runs in the print task manager, which
-- the loop executes twice a pass, so the message box ticks every engine tick.
--
-- THE SCRIPT: ScrCmd_2FB returns TRUE after starting a field task, so the
-- script waits until sub_0209862C finishes (the app has exited and the field
-- map has restarted).  The port's command pushes this screen and resumes the
-- script when it closes.  Afterwards the script hides the grunts, Mars,
-- Jupiter and Cyrus, sets VAR_SPEAR_PILLAR_STATE 3 and the distorted flags,
-- marks Dialga and Palkia seen and warps to SPEAR PILLAR (DISTORTED) 30, 30.
--
-- BEFORE IT, on the field: `ScrCmd_20D 0` starts the Red Chain effect
-- (overlay 6, the same archive's members 4-6 and 74-76) and `ScrCmd_20D 1`
-- polls it -- src/world/Gen4SpearPillarChain.lua.  `SetSubScene63` only
-- loads the CLIMAX sound-effect group (Sound_SetScene, SOUND_SCENE_SUB_63);
-- it does not touch the music, so SEQ_THE_EVENT02 plays on into stage 1
-- until stage 2 fades it.
--
-- THE SCREENS: with two panels (display / inset / top-and-bottom) each
-- engine goes where GX_SetDispSelect puts it -- stage 1's 3D on top, stages
-- 2 and 3 on the bottom under the sky.  With one (off, or swap with the
-- bottom screen lowered) the MAIN engine is shown, which is always the 3D
-- and the message window; swap's raised bottom screen shows the other one.
--
-- STAND-INS:
--   * edge marking is an outline in the table's colour where the 3D meets
--     its clear colour; polygon ids are not tracked, and toon/hardware light
--     is the renderer's ordinary lighting (SpearPillarCutscene_InitLighting's
--     light vectors are not applied);
--   * translucent polygons draw in submission order with depth (no AUTO
--     sort);
--   * stage 1's main backdrop is black (its BG palette buffer is never
--     loaded there);
--   * LCRNG is seeded with a constant (the cartridge's is time-seeded), so
--     the lights' wander points are the same every run;
--   * sound pan is approximated by a stereo position, the W060 pitch bend by
--     a pitch ratio, and cry volumes by source volume;
--   * screen fades are linear over their step count.

local Gen4Model = require("src.render.Gen4Model")
local Assets = require("src.render.Assets")
local Logger = require("src.core.Logger")
local bit = require("bit")

local S = {}
S.__index = S
S.isOpaque = true

local W, H = 256, 192
local floor = math.floor
local TAU = math.pi * 2
local FX = 4096
local multiply = Gen4Model.multiply
local FLIP_Y = { 1, 0, 0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 }

S.TEXT_BANK = 234
S.TICKS_PER_FRAME = 2

-- --------------------------------------------------------------- numbers --
local function idiv(a, b)
  local q = a / b
  if q >= 0 then return floor(q) end
  return -floor(-q)
end
local function fxc(v) if v >= 0 then return floor(v * FX + 0.5) end return -floor(-v * FX + 0.5) end
local function u16(v) return v % 65536 end
local function sinIdx(a) return math.sin(u16(a) / 65536 * TAU) end
local function cosIdx(a) return math.cos(u16(a) / 65536 * TAU) end
-- CalcSineDegrees_Wraparound: the fx32 table
local function sinDeg(d) return floor(math.sin(math.rad(d % 360)) * FX + 0.5) end
local function cosDeg(d) return floor(math.cos(math.rad(d % 360)) * FX + 0.5) end
local BAMS_PER_DEGREE = floor(65535 / 360)

-- LCRNG_Next
local function newLcrng(seed)
  local state = seed % 4294967296
  return function()
    -- state * 1103515245 + 24691, mod 2^32, without losing bits in a double
    local hi, lo = floor(state / 65536), state % 65536
    local m = 1103515245
    local mhi, mlo = floor(m / 65536), m % 65536
    local low = lo * mlo
    local mid = (hi * mlo + lo * mhi) % 65536
    state = (low + mid * 65536 + 24691) % 4294967296
    return floor(state / 65536)
  end
end

-- ----------------------------------------------------------------- sound --
local function playSe(self, name, pan, pitch)
  local okS, Sound = pcall(require, "src.core.Sound")
  if not (okS and Sound.playSe) then return end
  local ok, src = pcall(Sound.playSe, self.data, name, pitch and { pitch = pitch } or nil)
  if ok and src and pan and src.getChannelCount then
    pcall(function()
      if src:getChannelCount() == 1 then src:setPosition(pan / 128, 0, 0) end
    end)
  end
end

local function playCry(self, species, pan, volume)
  local okS, Sound = pcall(require, "src.core.Sound")
  if not (okS and Sound.playCry) then return end
  local ok, src = pcall(Sound.playCry, self.data, species)
  if ok and src then
    pcall(function()
      if volume then src:setVolume(math.min(1, volume / 127)) end
      if pan and src.getChannelCount and src:getChannelCount() == 1 then src:setPosition(pan / 128, 0, 0) end
    end)
  end
end

local function music() local ok, M = pcall(require, "src.core.Music"); return ok and M or nil end
local function playBgm(self, song)
  local M = music()
  if M and M.play then pcall(M.play, self.data, song, nil, { reason = "spear pillar" }) end
end
local function fadeOutBgm(frames)
  local M = music()
  if M and M.dsFade then pcall(M.dsFade, 0, frames) end
end
local function stopBgm()
  local M = music()
  if M and M.stop then pcall(M.stop) end
end

-- species numbers (constants/species.h)
S.DIALGA, S.PALKIA, S.GIRATINA = 483, 484, 487
S.UXIE, S.MESPRIT, S.AZELF = 480, 481, 482

-- --------------------------------------------------------------- models --
-- CutsceneModel: an Easy3DObject with up to four Easy3DAnims, each with its
-- own fx32 frame (Easy3DAnim_Update / _UpdateLooped).
local Model = {}
Model.__index = Model

function S:loadModel(part)
  local rec = self.art and self.art.parts and self.art.parts[part]
  local m = setmetatable({ part = part, rec = rec, loaded = rec ~= nil, visible = true,
                           pos = { 0, 0, 0 }, scale = { FX, FX, FX }, anims = {},
                           animSpeed = 0, playing = false, looping = false,
                           loopSecondaryAnim = false, playSecondaryAnim = false,
                           useAllAnimTracks = false, pose = 0, poseFrame = 0,
                           poseRepeatsLeft = 0, poseRepeatCount = 0, poseStepIndex = 0,
                           scaleValue = FX }, Model)
  -- CutsceneModel_LoadAnim for every track, in load order
  for i, track in ipairs(rec and rec.tracks or {}) do
    m.anims[i - 1] = { frame = 0, count = (track.frames or 1) * FX, track = track }
    m.animSpeed = FX
    m.poseStepIndex = 0xFF
    m.poseRepeatsLeft = 0xFF
  end
  return m
end

local function animUpdateLooped(a, delta)
  if not a then return end
  if delta > 0 then a.frame = (a.frame + delta) % a.count
  else
    a.frame = a.frame + delta
    if a.frame < 0 then a.frame = a.frame + a.count end
  end
end
local function animUpdate(a, delta)
  if not a then return false end
  if delta > 0 then
    if a.frame + delta < a.count then a.frame = a.frame + delta return false end
    a.frame = a.count
    return true
  end
  if a.frame + delta >= 0 then a.frame = a.frame + delta return false end
  a.frame = 0
  return true
end

-- pose_sequence.c
local POSE_FRAMES = {
  { 1, 2, 3, 2, 0xFF }, { 5, 6, 7, 6, 0xFF }, { 9, 10, 11, 10, 0xFF }, { 13, 14, 15, 14, 0xFF },
  { 0, 0, 0, 0, 0xFF }, { 4, 4, 4, 4, 0xFF }, { 10, 10, 10, 10, 0xFF }, { 14, 14, 14, 14, 0xFF },
  { 0, 0, 0, 0, 0xFF }, { 0, 1, 2, 3, 0xFF }, { 4, 5, 6, 7, 0xFF }, { 8, 9, 10, 11, 0xFF },
  { 12, 13, 14, 15, 0xFF },
}
S.POSE = { NONE = 0, WALK_BACKWARD = 1, STEP_BACK_2 = 2, STEP_SIDE_1 = 3, STEP_SIDE_2 = 4,
           TURN_NORTH = 5, TURN_SOUTH = 6, PUSHED_BACK = 9 }

function Model:poseStart(steps)
  self.playing = true
  self.poseSteps = steps
  self.poseStepIndex = 0
  self.poseRepeatsLeft = steps[1].repeatCount
  self.poseRepeatCount = steps[1].repeatCount
  self.pose = steps[1].pose
end

function Model:poseAnimFrame()
  local a = self.anims[0]
  if not a then return end
  local current = a.frame
  local ci = floor(current / FX) % 4
  local nextFrame = current + self.animSpeed
  local ni = floor(nextFrame / FX) % 4
  local row = POSE_FRAMES[self.pose]
  local target = row and row[self.poseFrame + 1] or 0xFF
  if target == 0xFF or target == nil then return end
  local newFrame
  if ni ~= ci then
    self.poseFrame = self.poseFrame + 1
    newFrame = target * 4 * FX
  else
    newFrame = nextFrame
  end
  a.frame = newFrame
end

function Model:poseMovement()
  local steps = self.poseSteps
  if self.poseRepeatsLeft == 0xFF or self.poseStepIndex == 0xFF or not steps then return end
  local step = steps[self.poseStepIndex + 1]
  if step.pose == S.POSE.NONE then
    self.playing = false
    self.poseStepIndex, self.poseRepeatsLeft, self.poseRepeatCount = 0xFF, 0xFF, 0xFF
    return
  end
  if self.poseFrame >= 4 then
    self.poseRepeatsLeft = self.poseRepeatsLeft - 1
    self.poseFrame = 0
    if self.poseRepeatsLeft == 0 then
      self.poseStepIndex = self.poseStepIndex + 1
      local nxt = steps[self.poseStepIndex + 1]
      self.pose = nxt.pose
      self.poseRepeatsLeft = nxt.repeatCount
      self.poseRepeatCount = nxt.repeatCount
      if self.pose == S.POSE.NONE then
        self.playing = false
        self.poseStepIndex, self.poseRepeatsLeft, self.poseRepeatCount = 0xFF, 0xFF, 0xFF
      end
    end
  else
    if self.poseFrame == 0 and self.poseRepeatsLeft == self.poseRepeatCount then return end
    local p = self.pose
    if p == S.POSE.WALK_BACKWARD or p == S.POSE.STEP_BACK_2 or p == S.POSE.PUSHED_BACK then
      self.pos[3] = self.pos[3] - step.stepDistance
    elseif p == S.POSE.STEP_SIDE_2 or p == S.POSE.STEP_SIDE_1 then
      self.pos[1] = self.pos[1] + step.stepDistance
    end
  end
end

-- CutsceneModel_Update's animation half (the draw half is S:drawModel)
function Model:update()
  if not self.loaded then return end
  if self.playing then
    local finished = false
    if self.looping then
      if self.pose == 0 then animUpdateLooped(self.anims[0], self.animSpeed)
      else
        self:poseMovement()
        self:poseAnimFrame()
      end
    else
      if self.useAllAnimTracks then
        for i = 0, 3 do finished = animUpdate(self.anims[i], self.animSpeed) end
      else
        finished = animUpdate(self.anims[0], self.animSpeed)
      end
    end
    if self.loopSecondaryAnim then animUpdateLooped(self.anims[1], self.animSpeed) end
    if self.playSecondaryAnim then animUpdate(self.anims[1], self.animSpeed) end
    if finished == true then self.playing = false end
  end
end

-- CutsceneModel_CloneMesh / _CloneAnim: the clone shares the source's mesh
-- and tracks, with frames of its own
function S:cloneModel(source)
  local m = self:loadModel(source.part)
  return m
end

local function setScale(m, x, y, z) m.scale = { x, y, z } end
local function setPos(m, x, y, z) m.pos = { x, y, z } end

-- ------------------------------------------------------------- camera --
-- Camera_InitWithTarget + the target it tracks (camera->targetPos): the look-
-- at target follows `cameraTarget`, the eye orbits it at `distance`
function S:initCamera(distance, ax, ay, fov, near, far)
  self.cam = { distance = distance, angle = { u16(ax), u16(ay or 0), 0 }, fov = fov,
               near = near or 10, far = far or 1008 }
end

function S:viewProjection()
  local c = self.cam
  local t = self.cameraTarget
  local target = { t[1] / FX, t[2] / FX, t[3] / FX }
  local d = c.distance / FX
  local ax, ay = c.angle[1], c.angle[2]
  local eye = { target[1] + sinIdx(ay) * d * cosIdx(ax),
                target[2] + sinIdx(u16(-ax)) * d,
                target[3] + cosIdx(ay) * d * cosIdx(ax) }
  local view = Gen4Model.lookAt(eye, target, { 0, 1, 0 })
  local proj = Gen4Model.perspective(2 * c.fov / 65536 * TAU, 4 / 3, c.near, c.far)
  return multiply(FLIP_Y, multiply(proj, view)), view
end

-- CameraPan_Start / CameraPan_Update (common.c)
function S:panStart(p)
  local pan = self.pan
  for k, v in pairs(p) do pan[k] = v end
  local d = pan.durationFrames
  pan.framesRemaining = d
  pan.stepX = idiv(BAMS_PER_DEGREE * pan.angleDeltaX, d)
  pan.stepY = idiv(BAMS_PER_DEGREE * pan.angleDeltaY, d)
  pan.stepZ = idiv(BAMS_PER_DEGREE * pan.angleDeltaZ, d)
  pan.posX = idiv(pan.positionDeltaX, d)
  pan.posY = idiv(pan.positionDeltaY, d)
  pan.posZ = idiv(pan.positionDeltaZ, d)
  local a = self.cam.angle
  pan.final = { u16(a[1] + BAMS_PER_DEGREE * pan.angleDeltaX),
                u16(a[2] + BAMS_PER_DEGREE * pan.angleDeltaY),
                u16(a[3] + BAMS_PER_DEGREE * pan.angleDeltaZ) }
end

function S:panUpdate()
  local pan = self.pan
  if (pan.framesRemaining or 0) == 0 then return true end
  local a = self.cam.angle
  pan.framesRemaining = pan.framesRemaining - 1
  if pan.framesRemaining == 0 then
    a[1], a[2], a[3] = pan.final[1], pan.final[2], pan.final[3]
    return true
  end
  a[1], a[2], a[3] = u16(a[1] + pan.stepX), u16(a[2] + pan.stepY), u16(a[3] + pan.stepZ)
  local t = self.cameraTarget
  t[1], t[2], t[3] = t[1] + pan.posX, t[2] + pan.posY, t[3] + pan.posZ
  return false
end

local function pan(duration, ax, dz, extra)
  local p = { durationFrames = duration, angleDeltaX = ax or 0, angleDeltaY = 0, angleDeltaZ = 0,
              positionDeltaX = 0, positionDeltaY = 0, positionDeltaZ = dz or 0 }
  for k, v in pairs(extra or {}) do p[k] = v end
  return p
end

-- ----------------------------------------------------------- the window --
-- SpearPillarCutscene_ShowMessage: message `id` of the bank, the player's
-- name in slot 0 for message 22, printed at the options' text speed.  The
-- messages end on a page break, which the printer waits on before it reports
-- itself done (Text_IsPrinterActive).
function S:messageText(id)
  local key = ("TEXT_B%04d_%05d"):format(S.TEXT_BANK, id)
  local s = ((self.data or {}).text or {})[key] or ""
  local name = self.playerName or ""
  -- the name goes in string buffer 0 and gen4Markup does the filling
  local buffers = {}
  for k, v in pairs((self.game or {}).stringBuffers or {}) do buffers[k] = v end
  buffers[1] = name
  local okC, Commands = pcall(require, "src.script.Commands")
  if okC and Commands and Commands.gen4Markup then
    local ok, plain = pcall(Commands.gen4Markup, s, { stringBuffers = buffers })
    if ok and type(plain) == "string" then s = plain end
  end
  return s
end

function S:showMessage(id)
  local text = self:messageText(id)
  -- the trailing page break: the printer's last wait
  local trailing = false
  while text:match("[\011\012]$") do
    text = text:sub(1, -2)
    trailing = true
  end
  local TextBox = require("src.render.TextBox")
  local ok, box = pcall(TextBox.new, self.game, text, nil, { stay = {} })
  if not ok then
    Logger.warn("spear pillar: message %d box failed: %s", id, tostring(box))
    self.msg = nil
    return
  end
  self.msg = { id = id, box = box, trailing = trailing, active = true }
end

function S:clearMessage() self.msg = nil end

function S:printerActive()
  local m = self.msg
  return m ~= nil and m.active
end

-- Text_RemovePrinter
function S:removePrinter()
  if self.msg then self.msg.active = false end
end

function S:tickMessage()
  local m = self.msg
  if not (m and m.active and m.box) then return end
  pcall(m.box.update, m.box, 1 / 60)
  if m.box.done then
    if m.trailing then
      local input = self.game and self.game.input
      if not m.armed then m.armed = true return end
      if input and (input:wasPressed("a") or input:wasPressed("b")) then
        pcall(function() require("src.core.Sound").play(self.data, "Press_AB") end)
        m.active = false
        m.box = nil   -- the page break clears the window
      end
    else
      m.active = false
    end
  end
end

-- ------------------------------------------------------------- fades --
-- StartScreenFade (brightness): the master brightness of both screens
function S:startFade(dir, colour, steps)
  local edge = colour == "white" and 16 or -16
  local from, to = 0, edge
  if dir == "in" then from, to = edge, 0 end
  self.fade = { from = from, to = to, n = math.max(1, steps), t = 0 }
  self.master = from
end
function S:fadeDone() return self.fade == nil end
function S:tickFade()
  local f = self.fade
  if not f then return end
  f.t = f.t + 1
  local v = f.from + (f.to - f.from) * f.t / f.n
  self.master = v < 0 and -floor(-v) or floor(v)
  if f.t >= f.n then self.master = f.to self.fade = nil end
end

-- G2_SetBlendBrightness / G2S_SetBlendBrightness
function S:setMainBrightness(v) self.mainBright = v end
function S:setSubBrightness(v) self.subBright = v end

-- =========================================================== STAGE 1 =====
local Stage1 = {}

function Stage1.init(self)
  local st = { state = 0, timer = 0, flashState = 0, models = {} }
  local M = st.models
  -- DialgaPalkiaArrival_InitCastModels
  M.stage = self:loadModel("stage")
  M.shockwave = self:loadModel("shockwave")
  M.dialgaBall = self:loadModel("ball")
  setPos(M.dialgaBall, fxc(-48), fxc(-10), fxc(-70))
  M.palkiaBall = self:loadModel("ball")
  setPos(M.palkiaBall, fxc(48), fxc(-10), fxc(-70))
  M.shadow = {}
  for i = 0, 3 do
    M.shadow[i] = self:loadModel("shadow")
    setScale(M.shadow[i], fxc(1.2), FX, fxc(1.2))
  end
  M.bubble = {}
  M.bubble[0] = self:loadModel("dialga")
  setPos(M.bubble[0], fxc(-50), 0, fxc(-50))
  M.bubble[0].playing, M.bubble[0].looping, M.bubble[0].animSpeed = true, true, FX / 2
  M.bubble[0].visible, M.shadow[0].visible = false, false
  M.bubble[1] = self:loadModel("palkia")
  setPos(M.bubble[1], fxc(50), 0, fxc(-50))
  M.bubble[1].playing, M.bubble[1].looping, M.bubble[1].animSpeed = true, true, FX / 2
  M.bubble[1].visible, M.shadow[1].visible = false, false
  M.player = self:loadModel(self.female and "dawn" or "lucas")
  setPos(M.player, fxc(1), 0, fxc(140))
  M.player.looping, M.player.animSpeed, M.player.pose = true, FX / 4, 2
  M.cyrus = self:loadModel("cyrus")
  setPos(M.cyrus, fxc(1), 0, fxc(60))
  M.cyrus.looping, M.cyrus.animSpeed, M.cyrus.pose = true, FX / 4, 2
  -- the sub screen: the Poketch's "unavailable" picture on sub BG0
  self.sub = "unavailable"
  self.edge = true
  self.cameraTarget[3] = fxc(34)
  self:initCamera(0x13C805, -0x29FE, 0, 0xC01, 10, 1008)
  self.disp = "MAIN_SUB"
  st.order = { "stage", "shockwave", "bubble0", "bubble1", "dialgaBall", "palkiaBall",
               "whirl1", "whirl2", "player", "cyrus", "shadow0", "shadow1", "shadow2", "shadow3" }
  return st
end

local function initWhirlpool(self, st)
  local M = st.models
  M.whirl1 = self:loadModel("whirlpool")
  setPos(M.whirl1, fxc(-48), fxc(-5), fxc(-70))
  M.whirl1.playing = false
  M.whirl2 = self:cloneModel(M.whirl1)
  setPos(M.whirl2, fxc(48), fxc(-5), fxc(-70))
  M.whirl2.playing = false
  M.whirl1.scaleValue, M.whirl2.scaleValue = fxc(0.1), fxc(0.1)
  setScale(M.whirl1, M.whirl1.scaleValue, FX, M.whirl1.scaleValue)
  setScale(M.whirl2, M.whirl2.scaleValue, FX, M.whirl2.scaleValue)
end

-- DialgaPalkiaArrival_UpdateCameraShake (a SysTask)
local function shakeTask(self)
  local sh = self.shake
  local pn = self.pan
  if sh.step == 0 then
    local d = 2
    local dx = pn.positionDeltaX or 0
    local i = sh.intensity
    local sign = sh.direction == 1 and 1 or -1
    if i == 4 or i == 6 then dx = sign * fxc(2)
    elseif i == 5 then dx = sign * fxc(4)
    elseif i == 0xFF then dx = sign * fxc(6)
    elseif i == 7 then dx = sign * fxc(2); d = 4 end
    sh.direction = 1 - sh.direction
    self:panStart({ durationFrames = d, positionDeltaX = dx, positionDeltaY = 0, positionDeltaZ = 0,
                    angleDeltaX = pn.angleDeltaX or 0, angleDeltaY = pn.angleDeltaY or 0,
                    angleDeltaZ = pn.angleDeltaZ or 0 })
    sh.step = 1
  end
  if sh.step == 1 then
    if self:panUpdate() then
      if sh.intensity == 8 then sh.step = 2 else sh.step = 0 end
    end
    return true
  end
  return false
end

-- DialgaPalkiaArrival_UpdateSummonBubble (a SysTask)
local BUBBLE_SCALES = { 0.0, 0.3, 0.6, 1.0, 1.2, 1.1, 1.0 }
local function bubbleTask(self, sb)
  if sb.step == 0 then
    local s = fxc(BUBBLE_SCALES[sb.scaleIndex + 1])
    setScale(sb.bubble, s, FX, FX)
    setScale(sb.shadow, s, FX, FX)
    sb.scaleIndex = sb.scaleIndex + 1
    sb.bubble.visible, sb.shadow.visible = true, true
    sb.step = 1
    return true
  elseif sb.step == 1 then
    sb.scaleIndex = sb.scaleIndex + 1
    if sb.scaleIndex >= #BUBBLE_SCALES then
      playCry(self, sb.species, sb.pan, 80)
      sb.step = 2
    else
      local s = fxc(BUBBLE_SCALES[sb.scaleIndex + 1])
      setScale(sb.bubble, s, FX, FX)
      setScale(sb.shadow, s, FX, FX)
    end
    return true
  end
  return false
end

local function startBubble(self, st, index, species)
  local sb = { step = 0, scaleIndex = 0, species = species, bubble = st.models.bubble[index],
               shadow = st.models.shadow[index], pan = index == 0 and -80 or 80 }
  self:task(function() return bubbleTask(self, sb) end)
end

local function flashPulse(self, st, peak)
  if st.flashState == 0 then
    if self.mainBright < peak then self:setMainBrightness(self.mainBright + 1)
    else st.flashState = 1 end
  else
    if self.mainBright > 0 then self:setMainBrightness(self.mainBright - 2)
    else
      st.state = st.state + 1
      st.flashState = 0
    end
  end
end

function Stage1.update(self, st)
  local M = st.models
  local s = st.state
  if s == 0 then   -- WAIT_FADE_IN
    if not self:fadeDone() then goto scene end
    st.state = 1
    s = 1
  end
  if s == 1 then   -- PAN_CAMERA
    self:panStart(pan(60, 0, -fxc(80 - 34)))
    st.state = 2
    s = 2
  end
  if s == 2 then   -- WAIT_PAN_CAMERA
    if self:panUpdate() then
      st.timer = 0
      st.state = 3
      self:showMessage(14)
    end
    goto scene
  end
  if s == 3 then   -- WAIT_INTRODUCE_DIALGA
    if self:printerActive() then goto scene end
    self:clearMessage()
    self:showMessage(16)
    st.state = 4
    s = 4
  end
  if s == 4 then   -- WAIT_INTRODUCE_PALKIA
    if self:printerActive() then goto scene end
    -- ScreenCapture_Start: the trail, eva 4 / evb 12
    self.capture = { eva = 4, evb = 12, primed = false }
    -- DialgaPalkiaArrival_InitCameraShake
    self.pan.angleDeltaX, self.pan.angleDeltaY, self.pan.angleDeltaZ = 0, 0, 0
    self.shake = { intensity = 0, step = 0, direction = 0 }
    self:task(function() return shakeTask(self) end)
    self:clearMessage()
    M.dialgaBall.playing, M.dialgaBall.useAllAnimTracks = true, true
    st.state = 5
    s = 5
  end
  if s == 5 then   -- WAIT_PALKIA_BALL_DELAY
    st.timer = st.timer + 1
    if st.timer >= 60 then
      self.shake.intensity = 4
      M.palkiaBall.playing, M.palkiaBall.useAllAnimTracks = true, true
      st.state = 6
    end
    goto scene
  end
  if s == 6 then   -- WAIT_DIALGA_BALL_LAND
    st.timer = st.timer + 1
    local t = st.timer
    if t == 80 then playSe(self, "SEQ_SE_DP_CLIMAX01", -70) end
    if t == 135 then playSe(self, "SEQ_SE_DP_CLIMAX01", 70) end
    if t == 310 or t == 375 or t == 432 then playSe(self, "SEQ_SE_DP_CLIMAX06") end
    if t == 284 or t == 338 or t == 406 then playSe(self, "SEQ_SE_DP_CLIMAX09") end
    if t == 165 then playSe(self, "SEQ_SE_DP_CLIMAX03", -70) end
    if t == 220 then playSe(self, "SEQ_SE_DP_CLIMAX03", 70) end
    if t == 470 then playSe(self, "SEQ_SE_DP_CLIMAX10", -70) end
    if t == 520 then playSe(self, "SEQ_SE_DP_CLIMAX10", 70) end
    if t == 120 then self.shake.intensity = 5 end
    if t == 210 then self.shake.intensity = 0xFF end
    if not M.dialgaBall.playing then
      self.shake.intensity = 6
      startBubble(self, st, 0, S.DIALGA)
      playSe(self, "SEQ_SE_DP_CLIMAX12", -70)
      st.state = 7
    end
    goto scene
  end
  if s == 7 then   -- WAIT_PALKIA_BALL_LAND
    if not M.palkiaBall.playing then
      self.shake.intensity = 7
      startBubble(self, st, 1, S.PALKIA)
      playSe(self, "SEQ_SE_DP_CLIMAX12", 70)
      st.state = 8
      st.timer = 0
    end
    goto scene
  end
  if s == 8 then   -- WAIT_SUMMON_BUBBLE_DELAY
    st.timer = st.timer + 1
    if st.timer >= 30 then st.timer = 0 st.state = 9 end
    goto scene
  end
  if s == 9 then   -- FLASH_PULSE_1
    self.shake.intensity = 8
    flashPulse(self, st, 8)
    goto scene
  end
  if s == 10 then  -- FLASH_PULSE_2
    flashPulse(self, st, 12)
    goto scene
  end
  if s == 11 then  -- FLASH_PULSE_3
    if self.mainBright < 16 then self:setMainBrightness(self.mainBright + 2)
    else
      -- DialgaPalkiaArrival_ReleaseFallingBalls, then the whirlpools
      M.dialgaBall.loaded, M.palkiaBall.loaded = false, false
      initWhirlpool(self, st)
      st.state = 12
    end
    goto scene
  end
  if s == 12 then  -- FADE_FROM_FLASH
    if self.mainBright ~= 0 then self:setMainBrightness(self.mainBright - 1)
    else
      for _, w in ipairs({ M.whirl1, M.whirl2 }) do
        w.playing, w.looping, w.playSecondaryAnim = true, true, true
      end
      st.state = 13
    end
    goto scene
  end
  if s == 13 then  -- GROW_WHIRLPOOL
    if M.whirl1.scaleValue < fxc(0.80) then
      for _, w in ipairs({ M.whirl1, M.whirl2 }) do
        w.scaleValue = w.scaleValue + fxc(0.02)
        setScale(w, w.scaleValue, FX, w.scaleValue)
      end
    else
      self:showMessage(18)
      st.state = 14
    end
    goto scene
  end
  if s == 14 then  -- WAIT_CREATION_SPEECH
    if self:printerActive() then goto scene end
    self:clearMessage()
    self:showMessage(19)
    st.state = 15
    goto scene
  end
  if s == 15 then  -- SHRINK_WHIRLPOOL
    if self:printerActive() then goto scene end
    if M.whirl1.scaleValue > fxc(0.10) then
      for _, w in ipairs({ M.whirl1, M.whirl2 }) do
        w.scaleValue = w.scaleValue - fxc(0.02)
        setScale(w, w.scaleValue, FX, w.scaleValue)
      end
    else
      self:startFade("out", "black", 6)
      st.state = 16
    end
    goto scene
  end
  if s == 16 then  -- WAIT_FADE_OUT
    if not self:fadeDone() then goto scene end
    self:clearMessage()
    st.state = 17
    goto scene
  end
  if s == 17 then  -- DONE
    st.state, st.timer = 0, 0
    return false
  end
  ::scene::
  -- the shadows follow the figures
  local function follow(sh, of, dx)
    sh.pos = { of.pos[1] - (dx or 0), of.pos[2], of.pos[3] - 2 * FX }
  end
  follow(M.shadow[0], M.bubble[0])
  follow(M.shadow[1], M.bubble[1])
  follow(M.shadow[2], M.player, FX)
  follow(M.shadow[3], M.cyrus, FX)
  -- DialgaPalkiaArrival_UpdateScene's CutsceneModel_Update calls
  for _, name in ipairs(st.order) do
    local m = self:modelByName(st, name)
    if m then m:update() end
  end
  return true
end

function Stage1.exit(self, st)
  if st.exitState == nil then
    st.exitState = 0
    -- ScreenCapture_End
    self.capture = nil
    return true
  end
  return false
end

-- =========================================================== STAGE 2 =====
local Stage2 = {}
local REVEAL_DURATION = { 210, 120, 120 }
local CRY_FRAME = { 145, 119, 100 }
local SFX_FRAME = { 100, 19, 18 }
local GUARDIANS = { S.UXIE, S.MESPRIT, S.AZELF }

function Stage2.init(self)
  local st = { state = 0, timer = 0, guardianIndex = 0, models = {} }
  local M = st.models
  M.backlight = self:loadModel("backlight")
  M.g = { [0] = self:loadModel("uxie"), self:loadModel("mesprit"), self:loadModel("azelf") }
  M.g[0].visible, M.g[1].visible, M.g[2].visible = true, false, false
  self.sub = "lake"
  self.mainBackdrop = { 1 / 31, 1 / 31, 1 / 31 }
  -- LakeGuardiansArrival_InitLights
  self.lights = {}
  self.orbitLights = {}
  for i = 0, 2 do
    local o = { x = 0, y = 0, scale = 1, state = 1, index = i, depth = 50, orbitAngle = i * 120,
                driftAngle = i * 120, jitterIntensity = 0, p = { 1, 1, self.rng() % 10, 0 },
                hidden = true, anim = 0 }
    o.driftAngle = o.orbitAngle
    self.orbitLights[i] = o
  end
  local startX, startY, startScale = { 180, -20, 280 }, { 128, 190, 150 }, { 0.1, 0.3, 0.2 }
  for i = 0, 2 do
    local l = { x = startX[i + 1] * FX, y = startY[i + 1] * FX, scale = startScale[i + 1], state = 0,
                index = i, depth = 50, orbitAngle = i * 120, driftAngle = i * 120, jitterIntensity = 0,
                p = { 1, 1, self.rng() % 10, 0 }, target = self.orbitLights[i], follow = false,
                bgPriority = (i == 1) and 0 or 2, anim = 0 }
    self.lights[i] = l
  end
  for i = 0, 2 do
    local o = self.orbitLights[i]
    self:task(function() self:lightOrbitOrApproach(o) return true end)
  end
  for i = 0, 2 do
    local l = self.lights[i]
    self:task(function() self:lightOrbitOrApproach(l) return true end)
  end
  -- ScreenScrollTask_Scroll(sub BG1, amplitude 2)
  self.wave = { amplitude = 2, pos = 0 }
  self:initCamera(fxc(200), 1274, 0, 0xA66, 0.1, 2048)
  self.cameraTarget[2] = self.cameraTarget[2] + fxc(25)
  self.edge = false
  self.disp = "SUB_MAIN"
  fadeOutBgm(10)
  return st
end

function Stage2.update(self, st)
  local M = st.models
  local s = st.state
  if s == 0 then
    self:startFade("in", "black", 6)
    st.state = 1
    s = 1
  end
  if s == 1 then
    if self:fadeDone() then
      playBgm(self, "SEQ_D_RYAYHY")
      st.state = 2
    end
  elseif s == 2 then   -- REVEAL_GUARDIAN
    local g = M.g[st.guardianIndex]
    g.visible = true
    g.playing, g.playSecondaryAnim = true, true
    st.state = 3
    st.timer = 0
  elseif s == 3 then   -- WAIT_GUARDIAN_CRY
    local i = st.guardianIndex + 1
    if st.timer == SFX_FRAME[i] then playSe(self, "SEQ_SE_PL_W392") end
    if st.timer == CRY_FRAME[i] then playCry(self, GUARDIANS[i], 0, 100) end
    st.timer = st.timer + 1
    if st.timer >= REVEAL_DURATION[i] then
      self.tint = 0
      st.timer = 0
      st.state = 4
    end
  elseif s == 4 then   -- FLASH_GUARDIAN
    self.tint = self.tint + 1
    if self.tint ~= 16 then self:setMainBrightness(self.tint)
    else
      self.lights[st.guardianIndex].follow = true
      M.g[st.guardianIndex].visible = false
      st.state = 5
      st.guardianIndex = st.guardianIndex + 1
      if st.guardianIndex >= 3 then
        self.tint = 0
        st.state = 6
      end
    end
  elseif s == 5 then   -- WAIT_FLASH_FADE
    self.tint = self.tint - 1
    if self.tint > 0 then self:setMainBrightness(self.tint)
    else st.state = 2 end
  elseif s == 6 then   -- FLASH_MAIN_SCREEN
    st.timer = st.timer + 1
    if st.timer >= 30 * 4 then
      self.tint = self.tint + 1
      if self.tint ~= 16 then self:setSubBrightness(self.tint)
      else
        self:startFade("out", "white", 1)
        st.state = 0
        return false
      end
    end
  end
  for _, m in ipairs({ M.g[0], M.g[1], M.g[2], M.backlight }) do m:update() end
  self:guardianFlash(st.guardianIndex)
  return true
end

function Stage2.exit(self, st)
  st.exitState = (st.exitState or -1) + 1
  if st.exitState == 0 then
    -- the lights and the wave go
    self:stopTasks()
    self.lights, self.orbitLights, self.wave = nil, nil, nil
    return true
  elseif st.exitState == 1 then
    -- the models go; GXLayers_EngineBToggleLayers(BG0, 0)
    self.lakeBg0Off = true
    return true
  end
  return false
end

-- SpearPillarCutscene_UpdateGuardianFlash
function S:guardianFlash(guardianIndex)
  local profile = math.min(guardianIndex, 2)
  if self.flashState == 2 then
    if self.flashTimer < (profile + 1) * 2 then self.flashTimer = self.flashTimer + 1
    else self.flashState, self.flashTimer = 0, 0 end
    return
  end
  if self.flashState == 0 then
    if self.flashIntensity < 31 then self.flashIntensity = self.flashIntensity + 1
    else self.flashState = self.flashState + 1 end
  else
    if self.flashIntensity > 0 then self.flashIntensity = self.flashIntensity - 1
    else self.flashState = self.flashState + 1 end
  end
  -- PaletteData_Blend(sub BG, 0, 32, intensity / 4, 0x10)
  self.subBlend = { colour = { 16 / 31, 0, 0 }, fraction = floor(self.flashIntensity / 4) / 16, all = true }
end

-- SpearPillarCutscene_UpdateBackgroundPulse
function S:backgroundPulse()
  if self.flashState == 0 then
    if self.flashIntensity < 31 then self.flashIntensity = self.flashIntensity + 1
    else self.flashState = bit.bxor(self.flashState, 1) end
  else
    if self.flashIntensity > 0 then self.flashIntensity = self.flashIntensity - 1
    else self.flashState = bit.bxor(self.flashState, 1) end
  end
  -- 0xCCCC = GX_RGB(12, 6, 19), colours 0-3 and 4-9
  self.subBlend = { colour = { 12 / 31, 6 / 31, 19 / 31 }, fraction = floor(self.flashIntensity / 8) / 16, all = false }
end

-- ------------------------------------------------------------ the lights --
-- light_ball.c, positions fx32 in sub-screen coordinates
local function approachStep(tx, ty, x, y, stepSize, stopDistance)
  local dx, dy = tx - x, ty - y
  local distance = math.sqrt(dx * dx + dy * dy)
  if distance < stepSize or stopDistance > distance or distance == 0 then return false end
  return true, dx * stepSize / distance, dy * stepSize / distance
end

function S:lightApproach(l, tx, ty, stepSize, stopDistance)
  local moved, sx, sy = approachStep(tx, ty, l.x / FX, l.y / FX, stepSize, stopDistance)
  if moved then
    local ox, oy = floor(sx * FX), floor(sy * FX)
    l.driftAngle = (l.driftAngle + 8) % 360
    ox = ox + sinDeg(l.driftAngle)
    oy = oy + cosDeg(l.driftAngle)
    l.x, l.y = l.x + ox, l.y + oy
  end
  return moved
end

function S:lightOrbitOrApproach(l)
  if l.state ~= 0 then
    l.orbitAngle = (l.orbitAngle + 8) % 360
    l.x = 128 * FX + sinDeg(l.orbitAngle) * 32
    l.y = (48 - 12) * FX + cosDeg(l.orbitAngle) * 12
  elseif l.target and l.follow then
    local tx, ty = idiv(l.target.x, FX), idiv(l.target.y, FX)
    self:lightApproach(l, tx, ty, 3.0, 1)
    if l.scale > 0.10 then l.scale = l.scale - 0.002 end
  end
  l.anim = l.anim + 2
end

local WANDER = { { 97, 80 }, { 87, 106 }, { 102, 94 }, { 182, 83 }, { 129, 116 },
                 { 97, 116 }, { 172, 84 }, { 187, 99 }, { 168, 123 }, { 108, 93 } }
function S:lightUpdate(l)
  if l.state == 1 then
    l.orbitAngle = (l.orbitAngle + 8) % 360
    l.x = 128 * FX + sinDeg(l.orbitAngle) * 64
    l.y = 48 * FX + cosDeg(l.orbitAngle) * 24
    l.depth = idiv(l.y, FX)
  elseif l.state == 2 then
    local p = WANDER[l.p[3] + 1]
    if not self:lightApproach(l, p[1], p[2], 3.0, 10) then
      l.p[3] = self.rng() % #WANDER
      l.state = 3
    end
    l.depth = idiv(l.y, FX)
  elseif l.state == 3 then
    l.driftAngle = (l.driftAngle + 8) % 360
    if l.driftAngle < 12 then
      l.jitterIntensity = (l.jitterIntensity + 1) % 3
      local ji = l.jitterIntensity
      -- LCRNG_Next() % 0 on the cartridge's divider: taken as 0
      l.p[1] = (ji > 0 and (self.rng() % ji) or 0) + 1
      l.p[2] = (ji > 0 and (self.rng() % ji) or 0) + 1
      l.state = 2
    end
    l.x = l.x + sinDeg(l.driftAngle) * 3 * l.p[1]
    l.y = l.y + cosDeg(l.driftAngle) * 3 * l.p[2]
    l.depth = idiv(l.y, FX)
  end
  -- LightBall_UpdateDepth
  local scale = 0.8 - l.depth / 100
  if scale <= 0.2 then scale = 0.2 end
  if scale >= 0.6 then scale = 0.6 end
  l.scale = scale
  l.priority = l.depth
  l.anim = l.anim + 2
end

-- =========================================================== STAGE 3 =====
local Stage3 = {}
local POSES = {
  dismissal = { { pose = S.POSE.TURN_SOUTH, repeatCount = 4, stepDistance = 0 }, { pose = S.POSE.NONE, repeatCount = 1 } },
  panToGiratina = { { pose = S.POSE.TURN_SOUTH, repeatCount = 4, stepDistance = 0 },
                    { pose = S.POSE.TURN_NORTH, repeatCount = 4, stepDistance = 0 }, { pose = S.POSE.NONE, repeatCount = 1 } },
  shadowRises = { { pose = S.POSE.WALK_BACKWARD, repeatCount = 2, stepDistance = -(FX / 4) }, { pose = S.POSE.NONE, repeatCount = 1 } },
  pushBack = { { pose = S.POSE.PUSHED_BACK, repeatCount = 2, stepDistance = -(FX / 4) }, { pose = S.POSE.NONE, repeatCount = 1 } },
}

function Stage3.init(self)
  local st = { step = 0, timer = 0, models = {} }
  local M = st.models
  self.sub = "gira"
  self.mainBackdrop = self:hexColour(self.art.bg and self.art.bg.gira and self.art.bg.gira.backdrop)
  M.stage = self:loadModel("stage")
  M.shadow = {}
  for i = 0, 3 do
    M.shadow[i] = self:loadModel("shadow")
    setScale(M.shadow[i], fxc(1.2), FX, fxc(1.2))
  end
  M.shockwave = self:loadModel("shockwave")
  M.splash = self:loadModel("splash")
  M.ripple = self:loadModel("ripple")
  M.bubble = { [0] = self:loadModel("dialga"), self:loadModel("palkia") }
  setPos(M.bubble[0], fxc(-50), 0, fxc(-50))
  setPos(M.bubble[1], fxc(50), 0, fxc(-50))
  for i = 0, 1 do M.bubble[i].playing, M.bubble[i].looping, M.bubble[i].animSpeed = true, true, FX / 2 end
  M.gira1 = self:loadModel("giraRise")
  setPos(M.gira1, 0, fxc(-90), 0)
  M.gira1.visible, M.gira1.loopSecondaryAnim = false, true
  M.gira2 = self:loadModel("giraFloat")
  M.gira2.visible, M.gira2.loopSecondaryAnim = false, true
  M.gira3 = self:loadModel("giraWings")
  M.gira3.visible, M.gira3.loopSecondaryAnim = false, true
  M.gira4 = self:loadModel("giraLunge")
  M.gira4.visible, M.gira4.loopSecondaryAnim = false, true
  M.gira5 = self:loadModel("giraAttack")
  M.gira5.visible, M.gira5.loopSecondaryAnim = false, true
  M.pool = self:loadModel("shadowPool")
  M.pool.visible = false
  M.eyes = self:loadModel("redEyes")
  M.eyes.visible = false
  M.player = self:loadModel(self.female and "dawn" or "lucas")
  setPos(M.player, fxc(1), 0, fxc(140))
  M.player.looping, M.player.animSpeed, M.player.pose = true, FX / 4, 2
  M.cyrus = self:loadModel("cyrus")
  setPos(M.cyrus, fxc(1), 0, fxc(60))
  M.cyrus.looping, M.cyrus.animSpeed, M.cyrus.pose = true, FX / 4, 2
  -- GiratinaIntervention_InitLakeGuardianLights
  self.lights = {}
  for i = 0, 2 do
    local l = { x = (16 + i * 64) * FX, y = 64 * FX, scale = 0.5, state = 1, index = i, depth = 50,
                orbitAngle = i * 120, driftAngle = i * 120, jitterIntensity = i,
                p = { 1, 1, self.rng() % 10, 0 }, bgPriority = 0, anim = 0 }
    self.lights[i] = l
    self:task(function() self:lightUpdate(l) return true end)
  end
  self.wave = { amplitude = 4, pos = 0 }
  self.lakeBg0Off = true
  self:initCamera(0x13C805, -0x29FE, 0, 0xC01, 10, 1008)
  self.cameraTarget[2] = 0
  self.edge = true
  self.disp = "SUB_MAIN"
  self:setMainBrightness(16)
  self:setSubBrightness(16)
  st.order = { "stage", "shockwave", "splash", "ripple", "pool", "eyes", "gira1", "gira2", "gira3",
               "gira4", "gira5", "bubble0", "bubble1", "player", "cyrus",
               "shadow0", "shadow1", "shadow2", "shadow3" }
  return st
end

function Stage3.update(self, st)
  local M = st.models
  local s = st.step
  if s == 0 then   -- FADE_IN
    self:startFade("in", "white", 6)
    self.tint = 0
    self:setMainBrightness(0)
    self:setSubBrightness(0)
    st.step = 1
    s = 1
  end
  if s == 1 then   -- WAIT_FADE_IN
    if self:fadeDone() then st.step = 2 end
  elseif s == 2 then   -- PAN_ANGLE_DOWN
    self:panStart(pan(60, 20, 0))
    st.step = 3
  elseif s == 3 then
    if self:panUpdate() then
      self:showMessage(20)
      st.step = 4
    end
  elseif s == 4 then   -- WAIT_LAKE_TRIO_DIALOGUE
    if not self:printerActive() then
      self:clearMessage()
      st.step = 5
    end
  elseif s == 5 then   -- PAN_TO_PLAYER
    self:panStart(pan(60, 0, fxc(70)))
    st.step = 6
  elseif s == 6 then   -- WAIT_PAN_TO_PLAYER
    if self:panUpdate() then
      st.timer = st.timer + 1
      if st.timer >= 10 then
        self:showMessage(21)
        M.cyrus:poseStart(POSES.dismissal)
        st.step = 7
        st.timer = 0
      end
    end
  elseif s == 7 then   -- WAIT_DISMISSAL_DIALOGUE
    if not self:printerActive() then
      self:clearMessage()
      self:showMessage(22)
      fadeOutBgm(10)
      st.step = 8
    end
  elseif s == 8 then   -- DARKEN_SCREEN
    if not self:printerActive() then
      self:clearMessage()
      st.timer = st.timer + 1
      if st.timer == 15 then
        for i = 0, 2 do
          local l = self.lights[i]
          l.state = l.state % 2 + 2
        end
      end
      if st.timer >= 30 then
        if self.tint > -6 then
          if st.timer % 2 == 1 then self.tint = self.tint - 1 end
          self:setMainBrightness(self.tint)
          self:setSubBrightness(self.tint)
        else
          self:showMessage(23)
          st.timer = 0
          st.step = 9
        end
      end
    end
  elseif s == 9 then   -- PAN_TO_GIRATINA
    if not self:printerActive() then
      self:clearMessage()
      M.cyrus:poseStart(POSES.panToGiratina)
      self:panStart(pan(90, 0, -fxc(80)))
      st.step = 10
    end
  elseif s == 10 then  -- WAIT_PAN_TO_GIRATINA
    if self:panUpdate() then
      st.step = 11
      st.timer = 0
    end
  elseif s == 11 then  -- PLAY_GIRATINA_BGM
    M.pool.playing = true
    M.pool.visible = true
    playBgm(self, "SEQ_PL_EV_GIRA")
    st.step = 12
  elseif s == 12 then  -- GIRATINA_SHADOW_RISES
    st.timer = st.timer + 1
    local t = st.timer
    if t == 60 then M.cyrus:poseStart(POSES.shadowRises) end
    if t == 15 or t == 45 or t == 75 or t == 95 or t == 115 or t == 130 or t == 145 then
      -- Sound_SetPitchForSequence(.., (t / 30 * 32) + (t % 32 * 10)), in
      -- 1/64 semitones
      local cents = idiv(t, 30) * 32 + (t % 32) * 10
      playSe(self, "SEQ_SE_PL_W060", nil, 2 ^ (cents / 64 / 12))
    end
    if not M.pool.playing then
      M.pool.visible = false
      M.eyes.visible = true
      M.gira1.visible = true
      M.gira1.playing = true
      st.timer = 0
      st.step = 13
    end
  elseif s == 13 then  -- GIRATINA_RISE_MOVEMENT
    if M.gira1.pos[2] < fxc(-50) then M.gira1.pos[2] = M.gira1.pos[2] + FX / 2
    else
      st.timer = 0
      st.step = 14
    end
  elseif s == 14 then  -- GIRATINA_RISE_COMPLETE
    if not M.gira1.playing then
      M.gira2.pos[2] = M.gira1.pos[2]
      M.gira2.playing, M.gira2.looping = true, true
      M.shockwave.playing, M.shockwave.playSecondaryAnim = true, true
      M.ripple.playing, M.ripple.loopSecondaryAnim = true, true
      M.gira1.visible = false
      M.gira2.visible = true
      st.step = 15
    end
  elseif s == 15 then  -- DIALGA_PALKIA_STEP_BACK
    st.timer = st.timer + 1
    local t = st.timer
    if t == 1 then playSe(self, "SEQ_SE_PL_W082C") end
    if t == 20 then M.cyrus:poseStart(POSES.pushBack) end
    if t == 15 + 25 then playCry(self, S.DIALGA, -80, 40) end
    if t == 40 + 25 then playCry(self, S.PALKIA, 80, 40) end
    if t < 15 + 25 then M.bubble[0].pos[3] = M.bubble[0].pos[3] - FX / 4
    else M.bubble[0].pos[3] = M.bubble[0].pos[3] - FX / 2 end
    if t < 40 + 25 then M.bubble[1].pos[3] = M.bubble[1].pos[3] - FX / 4
    else M.bubble[1].pos[3] = M.bubble[1].pos[3] - FX / 2 end
    if M.gira2.pos[2] < 0 then M.gira2.pos[2] = M.gira2.pos[2] + FX / 2
    else
      M.gira2.pos[2] = 0
      st.timer = 0
      self:showMessage(24)
      st.step = 16
    end
  elseif s == 16 then  -- WAIT_SHADOW_POKEMON_DIALOGUE
    if not self:printerActive() then
      self:clearMessage()
      M.splash.playing, M.splash.looping, M.splash.playSecondaryAnim = true, false, true
      M.gira3.playing = true
      M.gira2.visible = false
      M.gira3.visible = true
      playCry(self, S.GIRATINA, 0, 127)
      st.timer = 0
      st.step = 17
    end
  elseif s == 17 then  -- GIRATINA_TRANSFORM
    if not M.gira3.playing then
      self:showMessage(25)
      M.gira4.playing, M.gira4.looping = true, true
      M.splash.playing = false
      M.splash.visible = false
      M.gira3.visible = false
      M.gira4.visible = true
      st.step = 18
    end
  elseif s == 18 then  -- WAIT_HARNESSED_POWERS_DIALOGUE
    if not self:printerActive() then
      if st.timer == 0 then self:clearMessage() end
      playBgm(self, "SEQ_PL_EV_GIRA2")
      M.gira5.playing = true
      M.gira4.visible = false
      M.gira5.visible = true
      st.timer = 0
      st.step = 19
    end
  elseif s == 19 then  -- GIRATINA_ATTACKS_CYRUS
    st.timer = st.timer + 1
    if st.timer == 238 then playCry(self, S.GIRATINA, 0, 127) end
    if st.timer == 170 then self:showMessage(26) end
    if not M.gira5.playing then
      if self:printerActive() then self:removePrinter() end
      self.tint = -16
      self:setMainBrightness(-16)
      self:setSubBrightness(-16)
      stopBgm()
      self:clearMessage()
      st.step = 20
      st.timer = 0
    end
  elseif s == 20 or s == 21 then  -- FADE_OUT / WAIT_FADE_OUT
    if s == 20 then
      self:startFade("out", "black", 1)
      st.step = 21
    end
    if self:fadeDone() then
      self.tint = 0
      self:setMainBrightness(0)
      self:setSubBrightness(0)
      st.step = 22
    end
  else
    st.timer = st.timer + 1
    if st.timer >= 60 then
      st.step = 0
      return false
    end
  end
  local function follow(sh, of, dx)
    sh.pos = { of.pos[1] - (dx or 0), of.pos[2], of.pos[3] - 2 * FX }
  end
  follow(M.shadow[0], M.bubble[0])
  follow(M.shadow[1], M.bubble[1])
  follow(M.shadow[2], M.player, FX)
  follow(M.shadow[3], M.cyrus, FX)
  for _, name in ipairs(st.order) do
    local m = self:modelByName(st, name)
    if m then m:update() end
  end
  self:backgroundPulse()
  return true
end

function Stage3.exit(self, st)
  st.exitState = (st.exitState or -1) + 1
  if st.exitState == 0 then
    self:stopTasks()
    self.lights, self.wave = nil, nil
    return true
  elseif st.exitState == 1 then
    return true
  end
  return false
end

S.STAGES = { Stage1, Stage2, Stage3 }
S.STAGE_NAMES = { "dialga_palkia_arrival", "lake_guardians_arrival", "giratina_intervention" }

function S:modelByName(st, name)
  local M = st.models
  local n = name:match("^shadow(%d)$")
  if n then return M.shadow[tonumber(n)] end
  n = name:match("^bubble(%d)$")
  if n then return M.bubble and M.bubble[tonumber(n)] end
  return M[name]
end

-- ------------------------------------------------------------- tasks --
function S:task(fn)
  self.tasks[#self.tasks + 1] = { fn = fn, alive = true }
end
function S:runTasks()
  local list = self.tasks
  local n = #list
  for i = 1, n do
    local t = list[i]
    if t.alive then
      local ok, keep = pcall(t.fn)
      if not ok then
        Logger.warn("spear pillar: task failed: %s", tostring(keep))
        t.alive = false
      elseif not keep then t.alive = false end
    end
  end
  local live = {}
  for _, t in ipairs(self.tasks) do if t.alive then live[#live + 1] = t end end
  self.tasks = live
end
function S:stopTasks() self.tasks = {} end

-- ------------------------------------------------------------ the screen --
function S:uiSize() return W, H end
function S:wantsFillScale() return true end

function S.available(game)
  local rec = game and game.data and game.data.gen4_spear_pillar
  return type(rec) == "table" and type(rec.parts) == "table" and rec.parts.stage ~= nil
end

function S.new(game, onDone)
  local self = setmetatable({}, S)
  self.game = game
  self.data = game and game.data or {}
  self.art = self.data.gen4_spear_pillar
  self.onDone = onDone
  local save = game and game.save or {}
  local player = save.player or {}
  self.female = player.gender == "girl"
  self.playerName = player.name or ""
  self.tick = 0
  self.frame = 0
  self.tasks = {}
  self.pan = {}
  self.cameraTarget = { 0, 0, 0 }
  self.mainBright, self.subBright = 0, 0
  self.tint = 0
  -- SpearPillarCutscene_Init: tint 31/31/31, flashIntensity 31
  self.flashIntensity, self.flashState, self.flashTimer = 31, 0, 0
  self.master = -16
  self.mainBackdrop = { 0, 0, 0 }
  self.rng = newLcrng(0x5EA2)
  self.stageIndex = 1
  self.phase = "init"
  if type(self.art) ~= "table" then
    Logger.warn("spear pillar: this cache carries no `gen4_spear_pillar` -- re-import Platinum to see the cutscene")
    self.unavailable = true
    return self
  end
  self:startFade("in", "black", 6 * 2)
  return self
end

function S:hexColour(hex)
  if type(hex) ~= "string" or #hex < 6 then return { 0, 0, 0 } end
  return { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255 }
end

-- SpearPillarCutscene_Main, one 30 Hz pass
function S:logicFrame()
  self.frame = self.frame + 1
  local stage = S.STAGES[self.stageIndex]
  if self.phase == "init" then
    self.stageState = stage.init(self)
    self.phase = "update"
  elseif self.phase == "update" then
    if not stage.update(self, self.stageState) then self.phase = "exit" end
  elseif self.phase == "exit" then
    if not stage.exit(self, self.stageState) then
      self.stageIndex = self.stageIndex + 1
      if self.stageIndex > #S.STAGES then self.phase = "done"
      else self.phase = "init" end
    end
  elseif self.phase == "done" then
    return self:finish()
  end
  -- the SysTasks (shake, bubbles, lights, the wave's scroll)
  self:runTasks()
  if self.wave then self.wave.pos = (self.wave.pos + 1) % 192 end
  -- VBlank: the screen fade
  self:tickFade()
  self.captureDirty = true
end

function S:update(dt)
  if self.finished then return end
  if self.unavailable then return self:finish() end
  self.tick = self.tick + 1
  -- the print task manager runs every VBlank
  self:tickMessage()
  if self.tick % S.TICKS_PER_FRAME == 0 then self:logicFrame() end
end

function S:finish()
  if self.finished then return end
  self.finished = true
  self:releaseTargets()
  stopBgm()
  if self.game and self.game.stack and self.game.stack.top and self.game.stack:top() == self then
    self.game.stack:pop()
  end
  if self.onDone then self.onDone() end
end

-- --------------------------------------------------------------- drawing --
local models3d = setmetatable({}, { __mode = "k" })
function S:mesh(rec)
  if not rec then return nil end
  local key = rec.model
  if models3d[key] == nil then
    local ok, m = pcall(Gen4Model.new, rec.model)
    if not ok then Logger.warn("spear pillar: model %s failed: %s", tostring(rec.member), tostring(m)) end
    models3d[key] = ok and m or false
  end
  return models3d[key] or nil
end

local function modelMatrix(m)
  local sx, sy, sz = m.scale[1] / FX, m.scale[2] / FX, m.scale[3] / FX
  return { sx, 0, 0, m.pos[1] / FX,
           0, sy, 0, m.pos[2] / FX,
           0, 0, sz, m.pos[3] / FX,
           0, 0, 0, 1 }
end

function S:drawModel(m, vp, view)
  if not (m and m.loaded and m.visible and m.rec) then return end
  local mdl = self:mesh(m.rec)
  if not mdl then return end
  local Anim = require("src.import.Gen4Anim")
  local TexAnim = require("src.render.Gen4TexAnim")
  local motion, motionFrame, vis, visFrame
  local mats
  for i = 0, 3 do
    local a = m.anims[i]
    if a then
      local tr = a.track
      local f = floor(a.frame / FX)
      local last = (tr.frames or 1) - 1
      if f > last then f = last end
      if f < 0 then f = 0 end
      if tr.motion then motion, motionFrame = tr.motion, f
      elseif tr.visibility then vis, visFrame = tr.visibility, f
      elseif tr.record then
        local one = TexAnim.materials({ tr.record }, f, m.rec.model.patternImages)
        if one then
          mats = mats or {}
          for k, v in pairs(one) do
            local into = mats[k] or {}
            for kk, vv in pairs(v) do into[kk] = vv end
            mats[k] = into
          end
        end
      end
    end
  end
  -- a billboard faces the camera: the view's rotation undone, the node's
  -- own scale kept
  local function billboardOf(cur, yOnly)
    local sx = math.sqrt(cur[1] ^ 2 + cur[5] ^ 2 + cur[9] ^ 2)
    local sy = math.sqrt(cur[2] ^ 2 + cur[6] ^ 2 + cur[10] ^ 2)
    local sz = math.sqrt(cur[3] ^ 2 + cur[7] ^ 2 + cur[11] ^ 2)
    if yOnly then
      return { sx, 0, 0, cur[4], 0, sy, 0, cur[8], 0, 0, sz, cur[12], 0, 0, 0, 1 }
    end
    -- the transpose of the view's 3x3, columns scaled
    local v = view
    return { v[1] * sx, v[5] * sy, v[9] * sz, cur[4],
             v[2] * sx, v[6] * sy, v[10] * sz, cur[8],
             v[3] * sx, v[7] * sy, v[11] * sz, cur[12],
             0, 0, 0, 1 }
  end
  local pose = mdl:posed(function(node)
    local track = motion and motion.tracks[node]
    return track and Anim.unpackFrame(track, math.min(motionFrame, (motion.frames or 1) - 1)) or nil
  end, billboardOf)
  local shapes = mdl.shapes
  if vis then
    local nodes = m.rec.model.shapeNodes or {}
    local keep = {}
    for _, sh in ipairs(shapes) do
      local node = nodes[sh.index]
      if node == nil or Anim.visible(vis, node, visFrame) then keep[#keep + 1] = sh end
    end
    mdl.shapes = keep
  end
  pcall(mdl.draw, mdl, multiply(vp, modelMatrix(m)), pose, mats)
  mdl.shapes = shapes
end

local layerShader
local function shader()
  if layerShader == nil then
    local ok, sh = pcall(love.graphics.newShader, [[
      extern number bright;
      extern number edge;
      extern vec2 texel;
      extern vec3 edgeColour;
      extern vec3 tintColour;
      extern number tint;
      vec4 effect(vec4 colour, Image tex, vec2 uv, vec2 sc) {
        vec4 p = Texel(tex, uv);
        if (edge > 0.5 && p.a > 0.0) {
          float n = Texel(tex, uv + vec2(texel.x, 0.0)).a * Texel(tex, uv - vec2(texel.x, 0.0)).a
                  * Texel(tex, uv + vec2(0.0, texel.y)).a * Texel(tex, uv - vec2(0.0, texel.y)).a;
          if (n == 0.0) p.rgb = edgeColour * p.a;
        }
        if (tint > 0.0) p.rgb = mix(p.rgb, tintColour * p.a, tint);
        if (bright > 0.0) p.rgb = mix(p.rgb, vec3(p.a), bright);
        else if (bright < 0.0) p.rgb = mix(p.rgb, vec3(0.0), -bright);
        return p * colour;
      }
    ]])
    layerShader = ok and sh or false
    if not ok then Logger.warn("spear pillar: layer shader failed: %s", tostring(sh)) end
  end
  return layerShader or nil
end

-- draw an image (straight alpha) or a canvas (premultiplied) through the
-- layer shader: brightness -16..16, an optional tint, an optional edge
local function drawLayer(drawable, opts, x, y, quad)
  local g = love.graphics
  local sh = shader()
  opts = opts or {}
  if opts.premultiplied then g.setBlendMode("alpha", "premultiplied") end
  if sh then
    sh:send("bright", (opts.bright or 0) / 16)
    sh:send("edge", opts.edge and 1 or 0)
    sh:send("texel", { 1 / W, 1 / H })
    sh:send("edgeColour", { 2 / 31, 2 / 31, 2 / 31 })
    sh:send("tintColour", opts.tintColour or { 0, 0, 0 })
    sh:send("tint", opts.tint or 0)
    g.setShader(sh)
  end
  g.setColor(1, 1, 1, opts.alpha or 1)
  if quad then g.draw(drawable, quad, x or 0, y or 0) else g.draw(drawable, x or 0, y or 0) end
  g.setShader()
  g.setBlendMode("alpha", "alphamultiply")
end
S._drawLayer = drawLayer

local function image(path)
  if type(path) == "table" then path = path.path end
  if type(path) ~= "string" then return nil end
  local ok, img = pcall(Assets.image, path)
  if ok and img then img:setFilter("nearest", "nearest"); img:setWrap("repeat", "repeat") return img end
  return nil
end
function S:pic(path)
  self.pics = self.pics or {}
  if path == nil then return nil end
  if self.pics[path] == nil then self.pics[path] = image(path) or false end
  return self.pics[path] or nil
end

function S:targets()
  if self.canvases then return true end
  local g = love.graphics
  self.canvases = { main = g.newCanvas(W, H), sub = g.newCanvas(W, H), cap1 = g.newCanvas(W, H),
                    cap2 = g.newCanvas(W, H) }
  for _, c in pairs(self.canvases) do c:setFilter("nearest", "nearest") end
  self.colour3d, self.depth3d = Gen4Model.newTarget(W, H)
  return true
end

function S:releaseTargets()
  for _, c in pairs(self.canvases or {}) do pcall(c.release, c) end
  if self.colour3d then pcall(self.colour3d.release, self.colour3d) end
  if self.depth3d then pcall(self.depth3d.release, self.depth3d) end
  self.canvases, self.colour3d, self.depth3d = nil, nil, nil
  self.released = true
end

-- the main engine: backdrop, BG0 = the 3D (with G2 brightness), BG1 = the
-- message window
function S:renderMain()
  local g = love.graphics
  local st = self.stageState
  local stage = S.STAGES[self.stageIndex]
  g.setCanvas(self.canvases.main)
  local bd = self.mainBackdrop or { 0, 0, 0 }
  local b = (self.mainBright or 0) / 16
  local r, gg, bb = bd[1], bd[2], bd[3]
  if b > 0 then r, gg, bb = r + (1 - r) * b, gg + (1 - gg) * b, bb + (1 - bb) * b
  elseif b < 0 then r, gg, bb = r * (1 + b), gg * (1 + b), bb * (1 + b) end
  g.clear(r, gg, bb, 1)
  if st and st.models and self.colour3d and self.phase ~= "init" then
    g.push("all")
    g.setCanvas({ self.colour3d, depthstencil = self.depth3d })
    g.clear(0, 0, 0, 0, true, true)
    local vp, view = self:viewProjection()
    local order = st.order or { "g0", "g1", "g2", "backlight" }
    if stage == Stage2 then
      self:drawModel(st.models.g[0], vp, view)
      self:drawModel(st.models.g[1], vp, view)
      self:drawModel(st.models.g[2], vp, view)
      self:drawModel(st.models.backlight, vp, view)
    else
      for _, name in ipairs(order) do self:drawModel(self:modelByName(st, name), vp, view) end
    end
    g.pop()
    g.setCanvas(self.canvases.main)
    drawLayer(self.colour3d, { premultiplied = true, bright = self.mainBright, edge = self.edge })
  end
  if self.msg and self.msg.box then pcall(self.msg.box.draw, self.msg.box) end
  g.setCanvas()
  -- the screen-capture trail: VRAM C = (2D3D * eva + VRAM C * evb) / 16,
  -- once a pass, and VRAM C is what the main screen displays
  local cap = self.capture
  if cap then
    if self.captureDirty or not cap.primed then
      local src, dst = self.canvases.cap1, self.canvases.cap2
      g.setCanvas(dst)
      g.clear(0, 0, 0, 1)
      g.setColor(1, 1, 1, 1)
      if cap.primed then
        g.draw(src, 0, 0)
        g.setColor(1, 1, 1, cap.eva / 16)
      end
      g.draw(self.canvases.main, 0, 0)
      g.setColor(1, 1, 1, 1)
      g.setCanvas()
      self.canvases.cap1, self.canvases.cap2 = dst, src
      cap.primed = true
      self.captureDirty = false
    end
    return self.canvases.cap1
  end
  return self.canvases.main
end

function S:drawLight(l, palette)
  local lights = self.art.lights
  if not lights then return end
  local seq = lights.sequences and lights.sequences[0]
  local frames = seq and seq.frames or {}
  local total = 0
  for _, f in ipairs(frames) do total = total + (f.duration or 0) end
  local cell = frames[1] and frames[1].cell
  if total > 0 then
    local t = (l.anim or 0) % total
    local at = 0
    for _, f in ipairs(frames) do
      at = at + (f.duration or 0)
      if t < at then cell = f.cell break end
    end
  end
  local rec = cell and lights.cells[palette] and lights.cells[palette][cell]
  local img = rec and self:pic(rec.path)
  if not img then return end
  local s = l.scale or 1
  local x, y = l.x / FX, l.y / FX
  love.graphics.draw(img, x - (rec.originX or 0) * s, y - (rec.originY or 0) * s, 0, s, s)
end

-- a background layer with the per-line vertical wave (ScreenScrollManager_
-- ScrollY on BGxVOFS): line i shows row i + sine[(pos + i + 180) % 192]
function S:drawWaveLayer(img, amplitude, phase)
  local g = love.graphics
  local iw, ih = img:getDimensions()
  self.quad = self.quad or g.newQuad(0, 0, W, 1, iw, ih)
  for i = 0, H - 1 do
    local angle = ((phase + i + 180) % 192) * 682
    local off = floor(math.sin(u16(angle) / 65536 * TAU) * amplitude)
    self.quad:setViewport(0, (i + off) % ih, W, 1, iw, ih)
    g.draw(img, self.quad, 0, i)
  end
end

function S:renderSub()
  local g = love.graphics
  g.setCanvas(self.canvases.sub)
  g.clear(0, 0, 0, 1)
  local bg = self.art.bg or {}
  local sub = self.sub
  local bright = self.subBright or 0
  local blend = self.subBlend
  local function opts(all)
    local o = { bright = bright }
    if blend and blend.fraction > 0 then
      o.tintColour = blend.colour
      o.tint = (all or blend.all) and blend.fraction or 0
    end
    return o
  end
  if sub == "unavailable" then
    local img = self:pic(bg.unavailable and bg.unavailable.bg0)
    if img then drawLayer(img, { bright = bright }, 0, 0, g.newQuad(0, 0, W, H, img:getDimensions())) end
  elseif sub == "lake" or sub == "gira" then
    local rec = bg[sub] or {}
    -- the backdrop is colour 0 of the same palette, blended with it
    local c = self:hexColour(rec.backdrop)
    if blend and blend.fraction > 0 then
      for k = 1, 3 do c[k] = c[k] + (blend.colour[k] - c[k]) * blend.fraction end
    end
    local b = bright / 16
    for k = 1, 3 do
      if b > 0 then c[k] = c[k] + (1 - c[k]) * b elseif b < 0 then c[k] = c[k] * (1 + b) end
    end
    g.clear(c[1], c[2], c[3], 1)
    local bg1 = self:pic(rec.bg1)
    local phase = self.wave and self.wave.pos or 0
    local amp = self.wave and self.wave.amplitude or 0
    if not self.layerCanvas then
      self.layerCanvas = g.newCanvas(W, H)
      self.layerCanvas:setFilter("nearest", "nearest")
    end
    -- BG1 (priority 2), with the wave, then its palette blend
    g.setCanvas(self.layerCanvas)
    g.clear(0, 0, 0, 0)
    g.setColor(1, 1, 1, 1)
    if bg1 then self:drawWaveLayer(bg1, amp, phase) end
    if sub == "gira" and blend and blend.fraction > 0 then
      -- colours 0-9 only: the mask, in the blend colour, at the fraction
      local mask = self:pic(rec.pulse)
      if mask then
        g.setColor(blend.colour[1], blend.colour[2], blend.colour[3], blend.fraction)
        self:drawWaveLayer(mask, amp, phase)
        g.setColor(1, 1, 1, 1)
      end
    end
    g.setCanvas(self.canvases.sub)
    local o = opts(sub == "lake")
    if sub == "gira" then o.tint = 0 end
    o.premultiplied = true
    drawLayer(self.layerCanvas, o)
    -- OBJ at BG priority 2 (lights 0 and 2 of the lake), then BG0
    -- (priority 0), then OBJ at priority 0
    local lights = self.lights or {}
    do
      local list = {}
      for i = 0, 2 do if lights[i] then list[#list + 1] = lights[i] end end
      -- a larger OBJ priority value draws behind
      table.sort(list, function(a, b2) return (a.priority or 0) > (b2.priority or 0) end)
      local sh = shader()
      local function drawSet(pri)
        for _, l in ipairs(list) do
          if (l.bgPriority or 0) == pri then
            if sh then
              sh:send("bright", bright / 16); sh:send("edge", 0); sh:send("tint", 0)
              g.setShader(sh)
            end
            g.setColor(1, 1, 1, 1)
            self:drawLight(l, l.index)
            g.setShader()
          end
        end
      end
      drawSet(2)
      if sub == "lake" and not self.lakeBg0Off then
        local bg0 = self:pic(rec.bg0)
        if bg0 then drawLayer(bg0, opts(true), 0, 0, g.newQuad(0, 0, W, H, bg0:getDimensions())) end
      end
      drawSet(0)
    end
  end
  g.setCanvas()
end

-- which engine the top screen shows (GX_SetDispSelect)
function S:topEngine() return self.disp == "SUB_MAIN" and "sub" or "main" end

local function masterOver(level)
  if not level or level == 0 then return end
  local g = love.graphics
  if level > 0 then g.setColor(1, 1, 1, level / 16) else g.setColor(0, 0, 0, -level / 16) end
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)
end

function S:draw()
  local g = love.graphics
  if self.unavailable or self.released or not self:targets() then
    g.setColor(0, 0, 0, 1); g.rectangle("fill", 0, 0, W, H)
    return
  end
  g.push("all")
  g.origin()
  g.setScissor()
  local main = self:renderMain()
  self:renderSub()
  g.pop()
  local screens = { main = main, sub = self.canvases.sub }
  -- TWO PANELS (display / inset / top-and-bottom): each engine where the
  -- cartridge's GX_SetDispSelect puts it.  ONE (off, or swap with the bottom
  -- lowered): the main engine -- the 3D and the message window, wherever
  -- the cartridge shows it; swap's raised bottom screen is the other one.
  local SS = require("src.ui.SecondScreen")
  local dual = SS.separate and SS.separate(self.game) and SS.draw
  local top = dual and self:topEngine() or "main"
  if not dual and SS.mode and SS.mode(self.game) == "swap" and SS.raised and SS.raised(self.game) then
    top = "sub"
  end
  local bottom = top == "main" and "sub" or "main"
  g.setColor(1, 1, 1, 1)
  g.draw(screens[top], 0, 0)
  masterOver(self.master)
  if dual then
    SS.draw(self.game, function()
      g.setColor(1, 1, 1, 1)
      g.draw(screens[bottom], 0, 0)
      masterOver(self.master)
    end)
  end
end

-- for the harness
function S:describe()
  local st = self.stageState or {}
  return ("stage %d %s state %s timer %s msg %s fade %s"):format(self.stageIndex, tostring(self.phase),
    tostring(st.state or st.step), tostring(st.timer), tostring(self.msg and self.msg.id),
    tostring(self.master))
end

return S
