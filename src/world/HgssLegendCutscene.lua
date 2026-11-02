-- THE KIMONO GIRLS' DANCE: HeartGold's Ho-Oh at the Bell Tower (D17R0110)
-- and SoulSilver's Lugia at the Whirl Islands (D40R0107).
--
-- A transcription of pokeheartgold src/field/legend_cutscene_camera.c. The
-- scripts drive it with twelve commands (Gen4Commands g4_legend_*); this
-- module owns what they start:
--
--   * the CLEAR BELL (or Tidal Bell) rising out of the bag, idling, and
--     shimmering with the corner bells -- the decomp's
--     ClearBellCutscene3dObjectTaskData state machine, NUL -> RISE -> IDLE ->
--     SHIMMER -> IDLE;
--   * the CAMERA: four (HG) / five (SS) fixed set-ups (distance, angle,
--     perspective, look-at offset) and linear translation paths between them
--     (camera_translation.c), played through Gen4View.scripted in the 3D view;
--   * HeartGold's falling LEAVES (BG2/BG3 tilemap frames, six of each, every
--     six frames, scrolling) and SoulSilver's WAVES model;
--   * Lugia's EYE GLIMMER and the BIRD'S FINAL APPROACH: the legendary's map
--     object dropping 120 (HG) / 160 (SS) units one a frame with its wing
--     beats, then its cry and the expanding ring.
--
-- Everything ticks once per overworld update, the clock the script's own
-- `waittime` counts, so the effects stay in step with the script exactly as
-- they do on the cartridge.

local M = {}

local function Game() return package.loaded["src.core.Game"] end
local function data()
  local G = Game()
  return G and G.data or {}
end
local function art() return data().gen4_legend_art end

local function version()
  local ok, GV = pcall(require, "src.core.GameVersion")
  return ok and GV.get() or "heartgold"
end
local function soulSilver() return version() == "soulsilver" end

-- ------------------------------------------------------------ the tables --
-- CameraParam: distance (fx32), angle.x (u16, the negated pitch), perspective
local function param(dist, ax, persp) return { distance = dist, ax = ax, persp = persp } end
local D = 666.922119148625
M.CAMERA_HG = { param(D, 0xF562, 0x5C1), param(D, 0xF562, 0x5C1), param(D, 0xF762, 0xCC1), param(D, 0xFBA2, 0xCC1) }
M.CAMERA_SS = { param(D, 0xDFE2, 0x5C1), param(D, 0xDFE2, 0x5C1), param(D, 0xDEF2, 0x5C1),
                param(D, 0xDEF2, 0x5C1), param(D, 0xDEF2, 0x5C1) }
M.OFFSET_HG = { { -195, -148.605, -45.19165 }, { 198, -148.605, -45.19165 },
                { 0, -35.751708984375, -23.0476 }, { 0, 495.6323, 28.73 } }
M.OFFSET_SS = { { -127, 0, -208 }, { 63, 0, -208 }, { 0, 0, -82 }, { 0, 0, -433 }, { 0, 0, -225 } }
-- corner bells, relative to the player
M.CORNERS_HG = { { 200, -73, 144 }, { -198, -73, 144 }, { 200, -73, -270 }, { -198, -73, -270 } }
M.CORNERS_SS = { { 128, 32, -180 }, { -128, 32, -180 } }

M.SE_EYE_GLIMMER = 2317         -- SEQ_SE_GS_RUGIA_MENOHIKARI
M.SE_WING = 2319                -- SEQ_SE_GS_STOPPERKAIJO
M.SE_FLAP_LUGIA = 2318          -- SEQ_SE_GS_RUGIA_HABATAKI
M.SE_FLAP_HO_OH = 2314          -- SEQ_SE_GS_HOUOU_HABATAKI
M.BIRD_OBJECT = 5               -- obj_D17R0110_hou_obj01 / obj_D40R0107_lug_obj01
M.SPECIES_HO_OH, M.SPECIES_LUGIA = 250, 249

-- -------------------------------------------------------- animated parts --
local models = {}
local function modelFor(name)
  if models[name] ~= nil then return models[name] or nil end
  local a = art()
  local part = a and a.parts and a.parts[name]
  local ok, m = false, nil
  if part then ok, m = pcall(require("src.render.Gen4Model").new, part.model) end
  models[name] = ok and m or false
  return ok and m or nil
end

-- an object: a part playing from frame 0, looping or not
local function newObject(name, offset)
  return { part = name, frame = 0, offset = offset or { 0, 0, 0 }, active = false }
end

local function partOf(name)
  local a = art()
  return a and a.parts and a.parts[name]
end

-- FX32_ONE a frame; true when every animation of the list has reached its end
local function advance(obj, loop)
  local part = partOf(obj.part)
  local frames = part and part.frames or 1
  if frames < 1 then frames = 1 end
  if loop then
    obj.frame = (obj.frame + 1) % frames
    return false
  end
  if obj.frame < frames - 1 then obj.frame = obj.frame + 1 end
  return obj.frame >= frames - 1
end

-- -------------------------------------------------------------- the state --
M.state = nil

local function overworld()
  local G = Game()
  return G and G.overworld
end

local function playSe(id)
  local okC, Commands = pcall(require, "src.script.Commands")
  if okC and Commands.play_sound then
    pcall(Commands.play_sound, { game = Game(), overworld = overworld() }, id)
  end
end

local function birdEntity(ow)
  for _, e in ipairs((ow and ow.entities) or {}) do
    local id = e.localId or (e.def and e.def.localId)
    if id == M.BIRD_OBJECT then return e end
  end
end

-- where the player's feet are, in the ground's world space
local function anchor(ow)
  local p = ow and ow.player
  if not p then return 0, 0, 0 end
  local ground = ow.map and ow.map.renderer and ow.map.renderer.gen4Ground
  local gx, gz = (p.px or 0) + 8, (p.py or 0) + 8
  local y = ground and ground.groundY and ground:groundY(gx, gz) or 0
  return gx, y, gz
end

-- ------------------------------------------------------------- the camera --
local function axToPitch(ax) return ((65536 - ax) % 65536) * 360 / 65536 end
local function perspToHalfFov(p) return p * 360 / 65536 end

-- the field camera before any set-up: the map's own row, offset zero
local function fieldCamera(ow)
  local ground = ow and ow.map and ow.map.renderer and ow.map.renderer.gen4Ground
  local cfg = ground and ground.camera or {}
  local pitch = tonumber(cfg.pitch) or 48.7
  return { near = tonumber(cfg.near) or 150, far = tonumber(cfg.far) or 1200,
    distance = tonumber(cfg.distance) or D,
    ax = math.floor((65536 - pitch * 65536 / 360) % 65536),
    persp = math.floor((tonumber(cfg.halfFov) or 8.09) * 65536 / 360),
    offset = { 0, 0, 0 } }
end

local function applyCamera(cam)
  local View = require("src.render.Gen4View")
  View.scripted = cam and {
    distance = cam.distance, pitch = axToPitch(cam.ax), halfFov = perspToHalfFov(cam.persp),
    offset = { cam.offset[1], cam.offset[2], cam.offset[3] },
    near = cam.near, far = cam.far,
  } or nil
end

local function forceView(on)
  require("src.render.Gen4Camera").setCutsceneField3d(on)
end

-- camera_translation.c, one step: distance, angle (u16, by the shorter of the
-- two subtractions the way stepAngleX does it), perspective, and the offset
local function stepCamera(cam, from, to, step, duration)
  cam.distance = from.distance + (to.distance - from.distance) * step / duration
  local scaled
  if to.ax >= from.ax then scaled = math.floor((to.ax - from.ax) * step / duration)
  else scaled = -math.floor((from.ax - to.ax) * step / duration) end
  cam.ax = (from.ax + scaled) % 65536
  cam.persp = from.persp + math.floor((to.persp - from.persp) * step / duration)
  for i = 1, 3 do
    cam.offset[i] = from.offset[i] + (to.offset[i] - from.offset[i]) * step / duration
  end
end

local function startPan(st, to, duration)
  local cam = st.camera or fieldCamera(overworld())
  st.camera = cam
  st.pan = { from = { distance = cam.distance, ax = cam.ax, persp = cam.persp,
                      offset = { cam.offset[1], cam.offset[2], cam.offset[3] } },
             to = to, step = 0, duration = duration }
end

-- ----------------------------------------------------------- the commands --
function M.begin()
  local ow = overworld()
  local ss = soulSilver()
  local corners = ss and M.CORNERS_SS or M.CORNERS_HG
  local st = {
    ss = ss, bellState = "nul", shimmerOnly = false,
    rise = newObject("bellRise"), shimmer = newObject("bellShimmer"), corners = {},
    params = ss and M.CAMERA_SS or M.CAMERA_HG, offsets = ss and M.OFFSET_SS or M.OFFSET_HG,
  }
  for i, c in ipairs(corners) do st.corners[i] = newObject("cornerBell", c) end
  st.camera = nil
  M.state = st
  forceView(true)
  return st
end

function M.finish()
  -- LegendCutscene_EndClearBellAnim frees the bell task's camera wrapper; the
  -- camera itself stays where the dance left it until the field reloads
  local st = M.state
  if st then st.bellState = "done"; st.leaves = nil end
end

function M.riseFromBag()
  local st = M.state
  if st then st.bellState = "rise" end
end

function M.shimmer(clearBellOnly)
  local st = M.state
  if not st then return end
  st.shimmerOnly = (tonumber(clearBellOnly) or 0) ~= 0
  if st.bellState == "idle" then st.bellState = "shimmerBegin"
  else st.shimmerPending = true end -- Task_WaitShimmerEffectAndRestart
end

function M.moveCamera(scene)
  local st = M.state
  if not st then return end
  scene = (tonumber(scene) or 0) + 1
  local p, o = st.params[scene], st.offsets[scene]
  if not (p and o) then return end
  st.pan = nil
  -- ...and Camera_SetPerspectiveClippingPlane(150, 1700)
  st.camera = { distance = p.distance, ax = p.ax, persp = p.persp, offset = { o[1], o[2], o[3] },
    near = 150, far = 1700 }
  applyCamera(st.camera)
end

function M.panCamera(destination)
  local st = M.state
  if not st then return end
  local dest = tonumber(destination) or 0
  local point = dest == 0 and 1 or 4
  local p, o = st.params[point], st.offsets[point]
  local duration
  if st.ss then duration = dest == 0 and 160 or 200 else duration = dest == 0 and 200 or 20 end
  startPan(st, { distance = p.distance, ax = p.ax, persp = p.persp, offset = { o[1], o[2], o[3] } }, duration)
end

function M.panDone()
  local st = M.state
  return not (st and st.pan)
end

function M.wavesOrLeavesBegin()
  local st = M.state
  if not st then return end
  if st.ss then
    st.waves = newObject("waves"); st.waves.active = true
  else
    st.leaves = { index = 1, timer = 0, bg2X = 0, bg3X = 0, bgY = 0 }
  end
end

function M.wavesOrLeavesEnd()
  local st = M.state
  if not st then return end
  st.waves, st.leaves = nil, nil
end

function M.eyeGlimmer()
  local st = M.state or M.begin()
  st.glimmer = newObject("eyeGlimmer", { 0, 100, -350 })
  st.glimmer.active, st.glimmer.timer = true, 0
end

function M.glimmerDone()
  local st = M.state
  return not (st and st.glimmer)
end

function M.lugiaArrivesBegin()
  local st = M.state or M.begin()
  if not st.ss then return end
  local ow = overworld()
  st.lugiaSaved = st.camera or fieldCamera(ow)
  local p, o = M.CAMERA_SS[5], M.OFFSET_SS[5]
  st.camera = { distance = p.distance, ax = p.ax, persp = p.persp, near = 150, far = 1700,
    offset = { st.lugiaSaved.offset[1] + o[1], st.lugiaSaved.offset[2] + o[2], st.lugiaSaved.offset[3] + o[3] } }
  applyCamera(st.camera)
end

function M.lugiaArrivesPan()
  local st = M.state
  if not (st and st.ss and st.lugiaSaved) then return end
  local s = st.lugiaSaved
  startPan(st, { distance = s.distance, ax = s.ax, persp = s.persp,
    offset = { s.offset[1], s.offset[2], s.offset[3] } }, 30)
end

function M.lugiaArrivesEnd()
  local st = M.state
  if st then st.lugiaSaved = nil end
end

function M.birdFinalApproach()
  local st = M.state or M.begin()
  st.bird = { state = "init" }
end

function M.birdDone()
  local st = M.state
  return not (st and st.bird)
end

-- `cinematic` rebuilds the field behind its movie: the camera is the map's
-- own again (still the real 3D one, so the bird's ring has its depth)
function M.fieldRebuilt()
  local st = M.state
  if not st then return end
  st.camera, st.pan = nil, nil
  applyCamera(nil)
  -- ...and the bell task's objects went with the old field
  st.bellState = "done"
  st.rise.active, st.shimmer.active = false, false
  for _, c in ipairs(st.corners) do c.active = false end
  st.waves, st.leaves, st.glimmer = nil, nil, nil
end

-- leaving the map, or the script finishing with the dance long over, hands
-- the camera back -- the cartridge rebuilds its field camera from the header
function M.reset()
  if M.state and M.state.bird then
    local e = birdEntity(overworld())
    if e then e.spriteOffset = nil end
  end
  M.state = nil
  applyCamera(nil)
  forceView(false)
end

-- ---------------------------------------------------- the legendary wing --
-- ShowLegendaryWing <n> (overlay 2 0x0224618C, its task ov02_022461DC): the
-- Silver / Rainbow Wing over the player at the Tin Tower (0) and the Whirl
-- Islands (1). The model goes down at the player's position with
-- SEQ_SE_GS_STOPPERKAIJO and plays its first set; when that ends the second
-- set (and the map's third script is queued); when that ends the third; then
-- the object goes. Independent of the dance (M.state), so it ticks and draws
-- through the same hooks with M.wing alone.
M.wing = nil

function M.showWing(variant)
  local base = (tonumber(variant) or 0) == 1 and "wingWhirl" or "wingTin"
  local x, y, z = anchor(overworld())
  local obj = newObject(base)
  obj.active = true
  M.wing = { base = base, phase = 0, obj = obj, x = x, y = y, z = z }
  playSe(M.SE_WING)
end

local function tickWing()
  local w = M.wing
  if not (w and partOf(w.obj.part)) then M.wing = nil return end
  if not advance(w.obj, false) then return end
  if w.phase == 0 then
    w.phase, w.obj.part, w.obj.frame = 1, w.base .. "Shine", 0
  elseif w.phase == 1 then
    w.phase, w.obj.part, w.obj.frame = 2, w.base .. "Fade", 0
  else
    M.wing = nil
  end
end

-- --------------------------------------------------------------- one tick --
local function tickBird(st, ow)
  local b = st.bird
  local e = birdEntity(ow)
  local hg = not st.ss
  if b.state == "init" then
    b.ring = newObject("birdRing", hg and { 0, 40, -16 } or { 0, 0, -280 })
    b.state = "correct"
  elseif b.state == "correct" then
    b.yDelta = hg and 120 or 160
    if e then
      e.spriteOffset = e.spriteOffset or {}
      e.spriteOffset.lift = b.yDelta
      -- ...and SHOWN: the script's MakeObjectVisible hid the bird's picture
      -- (that command sets the hide bit -- see ScrCmd_374 in Gen4ScriptVM),
      -- and this state's MapObject_SetVisible(mapObject, FALSE) is what
      -- clears it (legend_cutscene_camera.c, CORRECT_POS). Without it Ho-Oh
      -- and Lugia flew in and stood on their perch unseen, talkable but
      -- never drawn.
      require("src.world.HgssModelObjects").setInvisible(ow, e, false)
    end
    b.delay, b.flapGap = 0, 0
    b.state = "flap"
  elseif b.state == "flap" then
    b.delay = b.delay + 1
    if b.delay >= (hg and 0 or 18) then
      if b.flapGap == 0 then
        playSe(hg and M.SE_FLAP_HO_OH or M.SE_FLAP_LUGIA)
        b.flapGap = 24
      end
      b.flapGap = b.flapGap - 1
    end
    b.yDelta = b.yDelta - 1
    local snapped = b.yDelta <= 0
    if snapped then b.yDelta = 0 end
    if e then e.spriteOffset = e.spriteOffset or {}; e.spriteOffset.lift = b.yDelta end
    if snapped then b.delay = 0; b.state = "altAnim" end
  elseif b.state == "altAnim" then
    b.delay = b.delay + 1
    if b.delay >= 60 then b.delay = 0; b.state = "cry" end
  elseif b.state == "cry" then
    b.delay = b.delay + 1
    if b.delay >= 50 then
      b.ring.active = true
      pcall(require("src.core.Sound").playCry, data(), hg and M.SPECIES_HO_OH or M.SPECIES_LUGIA)
      b.animTimer, b.delay = 0, 0
      b.state = "ring"
    end
  elseif b.state == "ring" then
    local done = advance(b.ring, false)
    b.animTimer = b.animTimer + 1
    if done and b.animTimer >= 65 then
      b.ring.active = false
      b.delay = 0
      b.state = "after"
    end
  elseif b.state == "after" then
    b.delay = b.delay + 1
    if b.delay >= 30 then
      if e and e.spriteOffset then e.spriteOffset.lift = nil end
      st.bird = nil
    end
  end
end

function M.tick(ow)
  if M.wing then tickWing() end
  local st = M.state
  if not st then return end
  if ow and ow.map and st.mapId and ow.map.id ~= st.mapId then M.reset() return end
  st.mapId = st.mapId or (ow and ow.map and ow.map.id)
  if os.getenv and os.getenv("LEGENDDBG") then
    local ground = ow and ow.map and ow.map.renderer and ow.map.renderer.gen4Ground
    local V = require("src.render.Gen4View")
    st.dbg = (st.dbg or 0) + 1
    if st.dbg % 60 == 1 then
      print(("[legend] bell=%s mode=%s force=%s view3d=%s viewPitch=%s scripted=%s pan=%s"):format(
        st.bellState, tostring(require("src.render.Gen4Camera").mode()),
        tostring(require("src.render.Gen4Camera").forceField3d),
        tostring(ground and ground.view3d and ground.view3d.mode), tostring(ground and ground.viewPitch),
        tostring(V.scripted and V.scripted.pitch), tostring(st.pan and st.pan.step)))
    end
  end
  -- the dance over and its script finished (the battle included): the field
  -- camera comes back, as it does when the cartridge rebuilds the field
  local running = ow and ow.runner and ow.runner.isRunning and ow.runner:isRunning()
  if st.bellState == "done" and not running and not (st.bird or st.pan or st.glimmer) then
    M.reset()
    return
  end

  -- the bell: Field3dObjectTaskUpdate_ClearBellCutscene
  local s = st.bellState
  if s == "rise" then
    st.rise.part, st.rise.frame, st.rise.active = "bellRise", 0, true
    st.bellState = "riseWait"
  elseif s == "riseWait" then
    if advance(st.rise, false) then
      -- bellShimmerReplaceGraphics: the idle animations, from frame 0
      st.rise.part, st.rise.frame = "bellIdle", 0
      st.bellState = "idle"
    end
  elseif s == "idle" then
    advance(st.rise, true)
    if st.shimmerPending then st.shimmerPending = nil; st.bellState = "shimmerBegin" end
  elseif s == "shimmerBegin" then
    st.rise.active = false
    st.shimmer.active, st.shimmer.frame = true, 0
    for i, c in ipairs(st.corners) do c.active = not st.shimmerOnly; c.frame = 0 end
    st.bellState = "shimmerWait"
  elseif s == "shimmerWait" then
    advance(st.rise, true)
    for _, c in ipairs(st.corners) do advance(c, false) end
    if advance(st.shimmer, false) then
      st.shimmer.active = false
      for _, c in ipairs(st.corners) do c.active = false end
      st.rise.active = true
      st.bellState = "idle"
    end
  end

  -- the camera path
  local pan = st.pan
  if pan then
    pan.step = pan.step + 1
    stepCamera(st.camera, pan.from, pan.to, pan.step, pan.duration)
    applyCamera(st.camera)
    if pan.step >= pan.duration then st.pan = nil end
  end

  -- leaves (HG): a new tilemap every six frames, BG2 drifting left, BG3
  -- right, both up
  local lv = st.leaves
  if lv then
    lv.timer = lv.timer + 1
    if lv.timer >= 6 then
      lv.timer = 0
      lv.index = lv.index % 6 + 1
    end
    lv.bg2X = (lv.bg2X - 1) % 256
    lv.bg3X = (lv.bg3X + 1) % 256
    lv.bgY = (lv.bgY - 1) % 256
  end
  if st.waves then advance(st.waves, true) end

  -- Lugia's eye glimmer (Task_LugiaEyeGlimmer)
  local gl = st.glimmer
  if gl then
    gl.timer = gl.timer + 1
    if gl.timer == 2 then playSe(M.SE_EYE_GLIMMER) end
    if advance(gl, false) then st.glimmer = nil end
  end

  if st.bird then tickBird(st, ow) end
end

-- ------------------------------------------------------------- drawing --
local function drawObject(obj, ground, vp, ox, oy, oz)
  if not (obj and obj.active) then return end
  local mdl = modelFor(obj.part)
  local part = partOf(obj.part)
  if not (mdl and part) then return end
  local Gen4Model = require("src.render.Gen4Model")
  local Anim = require("src.import.Gen4Anim")
  local frame = obj.frame
  local motion = part.motion
  local pose = motion and mdl:posed(function(node)
    local track = motion.tracks[node]
    return track and Anim.unpackFrame(track, math.min(frame, (motion.frames or 1) - 1)) or nil
  end) or nil
  local mats = require("src.render.Gen4TexAnim").materials(part.records, frame, part.model.patternImages)
  local o = obj.offset
  local m = Gen4Model.multiply(vp, { 1, 0, 0, ox + o[1] + (ground.offsetX or 0),
                                     0, 1, 0, oy + o[2],
                                     0, 0, 1, oz + o[3] + (ground.offsetY or 0),
                                     0, 0, 0, 1 })
  mdl:draw(m, pose, mats)
end

-- the field camera's live pass (Gen4Ground, beside Gen4FieldFx): the wing
-- in the ordinary field view, placed the way the obstacle animations are
function M.drawLive(ground, left, top, vw, vh)
  local w = M.wing
  if not (w and w.obj.active) then return end
  local mdl = modelFor(w.obj.part)
  local part = partOf(w.obj.part)
  if not (mdl and part) then return end
  local Gen4Ground = require("src.render.Gen4Ground")
  local Anim = require("src.import.Gen4Anim")
  local frame = w.obj.frame
  local motion = part.motion
  local pose = motion and mdl:posed(function(node)
    local track = motion.tracks[node]
    return track and Anim.unpackFrame(track, math.min(frame, (motion.frames or 1) - 1)) or nil
  end) or nil
  local mats = require("src.render.Gen4TexAnim").materials(part.records, frame, part.model.patternImages)
  local half = ground.half or 0
  local base = ground:screenMatrix(w.x + (ground.offsetX or 0) - left - half,
                                   w.z + (ground.offsetY or 0) - top - half, vw, vh)
  local m = Gen4Ground.liftMatrix(base, w.y)
  local spread = Gen4Ground.liftedSpread and Gen4Ground.liftedSpread(ground.spread, w.y) or ground.spread
  mdl:draw(m, pose, mats, nil, spread)
end

-- the 3D view's pass (Gen4Ground:drawFree), with the world's depth
function M.drawFree(ground, vp)
  local w = M.wing
  if w then drawObject(w.obj, ground, vp, w.x, w.y, w.z) end
  local st = M.state
  if not st then return end
  local ow = overworld()
  local x, y, z = anchor(ow)
  drawObject(st.rise, ground, vp, x, y, z)
  drawObject(st.shimmer, ground, vp, x, y, z)
  for _, c in ipairs(st.corners) do drawObject(c, ground, vp, x, y, z) end
  drawObject(st.waves, ground, vp, x, y, z)
  drawObject(st.glimmer, ground, vp, x, y, z)
  if st.bird and st.bird.ring then drawObject(st.bird.ring, ground, vp, x, y, z) end
end

-- HeartGold's leaves, over the field and under the message box (BG2 at
-- priority 0, BG3 at 1, the 3D on BG0 at 2)
function M.leavesActive()
  return M.state and M.state.leaves and art() and art().leaves and true or false
end

local leafImages = {}
local function leafImage(path)
  if leafImages[path] == nil then
    local ok, img = pcall(require("src.render.Assets").image, path)
    leafImages[path] = ok and img or false
  end
  return leafImages[path] or nil
end

function M.drawLeaves(w, h)
  local st = M.state
  local lv = st and st.leaves
  local a = art()
  if not (lv and a and a.leaves) then return false end
  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  local function layer(list, sx, sy)
    local img = leafImage(list[lv.index])
    if not img then return end
    local iw, ih = img:getWidth(), img:getHeight()
    -- a BG offset scrolls the picture the other way
    local x0 = -(sx % iw)
    local y0 = -(sy % ih)
    for yy = y0, h, ih do
      for xx = x0, w, iw do g.draw(img, xx, yy) end
    end
  end
  layer(a.leaves.bg3, lv.bg3X, lv.bgY)
  layer(a.leaves.bg2, lv.bg2X, lv.bgY)
  return true
end

return M
