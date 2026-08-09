-- HORDE MODE: the handgun.
--
-- A voxel model in the player's right hand, authored here in METRES the
-- way lib/Pokedex authors the device in the left one -- because the VR
-- mapping's scale is what turns metres into world pixels, a mesh built
-- this way is the right size in the hand at every scale the mod has, and
-- the same mesh serves the flat screen's view model.
--
-- IN VR the gun rides the tracked right hand through VRRig.propMatrix,
-- pointed by the runtime's AIM pose where one exists (the pose a runtime
-- defines as "where the user is pointing") and by the grip pose where it
-- does not. You aim it by pointing it. The iron sights are real geometry,
-- and lining them up is how you shoot accurately, because the shot is
-- traced down the model's own barrel axis.
--
-- ON THE FLAT SCREEN there is no hand to track, so the gun is carried by
-- the camera: a model matrix built from the first-person eye and its yaw
-- and pitch, with the gun hanging at the hip until the player aims. AIM
-- DOWN SIGHTS slides it to the centre of the screen with the sight line
-- ON the eye axis -- the model is authored with its rear notch at the
-- origin precisely so that offset is (0, 0, forward) -- and narrows the
-- field of view, which is the whole of what aiming does here.
--
-- THE SHOT IS A RAY, traced the same way in both modes: march it in world
-- pixels, let terrain height stop it (a wall is a tall cell, so a cell
-- whose ground is above the ray's height is a wall the bullet hits), and
-- test every live mob against it as a standing cylinder. Nearest wins,
-- and a hit above the shoulder line counts double.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Mat4 = V.require("Mat4")
local Voxel3D = V.require("Voxel3D")
local VRRig = V.require("VRRig")
local FirstPerson = V.require("FirstPerson")
local Horde = V.require("Horde")
local HordeSfx = V.require("HordeSfx")

local HordeGun = {}

-- ------- tuning

HordeGun.MAG = 8
HordeGun.RELOAD_TIME = 1.5
HordeGun.FIRE_COOLDOWN = 0.17      -- semi-auto, and it fits the reload clicks
HordeGun.RANGE = 220               -- world pixels: about fourteen cells
HordeGun.HIT_RADIUS = 6            -- a person is about twelve pixels wide
HordeGun.ADS_TIME = 0.13
HordeGun.ADS_FOV = math.rad(40)

-- Where the gun sits relative to the EYE, in metres, hip and aimed. The
-- model's own origin is its rear sight notch, so the aimed offset is a
-- pure push forward: nothing to line up, it is already lined up.
HordeGun.HIP = { -0.115, -0.125, 0.30 }
HordeGun.ADS = { 0, -0.002, 0.34 }

-- Where it sits relative to the tracked hand, in METRES and in the POSE's
-- own axes -- so with the barrel pointed away from the player (see below)
-- -Z is forward, and this nudges the gun a little down and forward of the
-- pose origin so the hand is behind it rather than inside it.
HordeGun.HAND_OFFSET = { 0, -0.012, -0.02 }

-- THE BARREL, AND WHICH WAY IS FORWARD.
--
-- OpenXR's AIM pose -- the one this rides where the runtime offers it --
-- is defined with its **-Z axis pointing the way the user is aiming**.
-- The model below is authored with its barrel along **+Z**, because that
-- is what the flat screen's view model wants (Ry(yaw)*Rx(pitch) carries
-- +Z onto the look direction). Half a turn about Y is what reconciles
-- them, and it is the whole of the attachment.
--
-- Getting this wrong does not read as "slightly off": the first cut
-- copied the Pokedex's quarter-turn about X, which lays a flat slab along
-- the controller's body and is exactly right for a slab -- on a gun it
-- pointed the muzzle at the player's own face.
HordeGun.HAND_YAW = math.pi

-- AND A PITCH, because a hand is not a tripod. A controller held the way
-- you hold a pistol -- fist closed, wrist cocked -- has its own aim axis
-- running up and forward out of the top of your fist, well above the line
-- your hand FEELS like it is pointing along. A model laid flat on that
-- axis reads as a gun held by somebody with a broken wrist.
--
-- So the gun tips its muzzle down 45 degrees off the pose, which puts the
-- barrel back on the line the grip implies. The shot follows: the ray is
-- read off the finished matrix's own +Z column (see place), so it comes
-- out of the barrel as drawn rather than off the pose it was hung on --
-- point the gun, hit the thing.
HordeGun.HAND_PITCH = math.rad(45)

-- ------- the model
--
-- One voxel is 8mm, so the pistol below comes out about 18cm long -- a
-- compact service automatic. Authored around the REAR SIGHT NOTCH at the
-- origin, barrel down +Z, up +Y. (+X is the viewer's LEFT: the world runs
-- +X east and +Z south, so a body facing +Z has its right hand toward
-- -X, which is why the hip offset's x is negative.)

local VOX = 0.008

local COLORS = {
  { 60, 62, 72 },      -- 1 slide
  { 30, 31, 38 },      -- 2 frame / shadowed
  { 46, 40, 40 },      -- 3 grip
  { 104, 108, 122 },   -- 4 highlight
  { 248, 240, 176 },   -- 5 sight dot
  { 18, 18, 22 },      -- 6 bore
  { 132, 136, 148 },   -- 7 trigger
  { 255, 246, 196 },   -- 8 flash core
  { 255, 168, 56 },    -- 9 flash edge
}

local paletteTex, bodyMesh, flashMesh = nil, nil, nil

local function palette()
  if paletteTex then return paletteTex end
  if not (love.image and love.image.newImageData
          and love.graphics and love.graphics.newImage) then return nil end
  local ok, data = pcall(love.image.newImageData, #COLORS, 1)
  if not (ok and data) then return nil end
  for i, c in ipairs(COLORS) do
    pcall(data.setPixel, data, i - 1, 0,
          c[1] / 255, c[2] / 255, c[3] / 255, 1)
  end
  local built, img = pcall(love.graphics.newImage, data)
  if not built then return nil end
  pcall(img.setFilter, img, "nearest", "nearest")
  paletteTex = img
  return img
end

-- one solid box, in voxels, straight into the shared vertex format
local function box(verts, indices, x, y, z, w, h, d, color)
  local u = (color - 0.5) / #COLORS
  local ox, oy, oz = x * VOX, y * VOX, z * VOX
  local sx, sy, sz = w * VOX, h * VOX, d * VOX
  for face = 1, 6 do
    local corners = Voxel3D.FACE_CORNERS[face]
    local shade = Voxel3D.FACE_SHADE[face]
    local n = #verts / 4
    for _, c in ipairs(corners) do
      verts[#verts + 1] = { ox + c[1] * sx, oy + c[2] * sy, oz + c[3] * sz,
                            u, 0.5, shade }
    end
    Voxel3D.pushQuad(indices, n)
  end
end

local function buildBody()
  if bodyMesh then return bodyMesh end
  local v, i = {}, {}
  -- slide, and the bore's dark eye at the end of it
  box(v, i, -2, -5, -1, 4, 4, 18, 1)
  box(v, i, -2, -2, -1, 4, 0.6, 18, 4)        -- the light along the top edge
  box(v, i, -1, -4, 16.6, 2, 2, 0.6, 6)
  -- frame under the slide, and the dust cover forward of the guard
  box(v, i, -1.8, -8, 0.5, 3.6, 3.2, 12, 2)
  -- the grip, three blocks stepping back: a raked butt without a hull
  box(v, i, -1.8, -11, -1.2, 3.6, 3.2, 5, 3)
  box(v, i, -1.8, -14, -2.6, 3.6, 3.2, 5, 3)
  box(v, i, -1.8, -16.8, -3.8, 3.6, 3, 5, 2)
  -- trigger guard: the bar under, the post in front
  box(v, i, -1.4, -11.4, 3.6, 2.8, 1, 4.4, 2)
  box(v, i, -1.4, -11.4, 7.4, 2.8, 3.4, 1, 2)
  box(v, i, -0.9, -10.8, 4.6, 1.8, 2, 1, 7)   -- the trigger itself
  -- IRON SIGHTS. Two rear posts with a notch between them at the origin,
  -- one front post at the muzzle: look through the gap, put the front
  -- post's dot in it, and the barrel is pointing where you are looking.
  box(v, i, -2, -1, -0.2, 0.9, 1.3, 1.4, 2)
  box(v, i, 1.1, -1, -0.2, 0.9, 1.3, 1.4, 2)
  box(v, i, -1.95, -0.2, 0.3, 0.5, 0.5, 0.5, 5)
  box(v, i, 1.45, -0.2, 0.3, 0.5, 0.5, 0.5, 5)
  box(v, i, -0.45, -1, 15.2, 0.9, 1.5, 1, 2)
  box(v, i, -0.3, 0.1, 15.4, 0.6, 0.6, 0.6, 5)
  bodyMesh = Voxel3D.newMesh(v, i)
  return bodyMesh
end

-- the muzzle flash: a bright cross of boxes off the bore, drawn for two
-- frames after a shot and never lit by anything
local function buildFlash()
  if flashMesh then return flashMesh end
  local v, i = {}, {}
  box(v, i, -1.6, -4.6, 17.4, 3.2, 3.2, 2.6, 8)
  box(v, i, -3.4, -3.8, 17.6, 6.8, 1.6, 1.8, 9)
  box(v, i, -0.9, -6.4, 17.6, 1.8, 6.4, 1.8, 9)
  box(v, i, -1.1, -4.1, 19.6, 2.2, 2.2, 2.2, 9)
  flashMesh = Voxel3D.newMesh(v, i)
  return flashMesh
end

-- ------- state

local gun = {
  ammo = HordeGun.MAG,
  reloading = false,
  reloadT = 0,
  reloadStage = 0,
  cooldown = 0,
  ads = false,
  adsBlend = 0,
  kick = 0,
  flash = 0,
  frame = nil,        -- the VR hand's model matrix for this frame
  ray = nil,          -- the VR aim ray in world space, if there is one
}

HordeGun.state = gun

function HordeGun.reset()
  gun.ammo = HordeGun.MAG
  gun.reloading, gun.reloadT, gun.reloadStage = false, 0, 0
  gun.cooldown, gun.kick, gun.flash = 0, 0, 0
  gun.ads, gun.adsBlend = false, 0
  gun.frame, gun.ray = nil, nil
end

-- how far into the aim the sights are, 0..1 -- read by the HUD (the
-- crosshair goes away) and by the camera (the field of view narrows)
function HordeGun.adsBlend()
  return gun.adsBlend
end

function HordeGun.ammo()
  return gun.ammo, HordeGun.MAG, gun.reloading
end

function HordeGun.setAds(on)
  gun.ads = on and true or false
end

-- ------- the shot

-- The eye and the direction it is looking, in world pixels. In VR this is
-- the gun's own barrel (set by the VR frame); on the flat screen it is
-- the camera, because the gun follows the camera exactly.
local function ray(G)
  if gun.ray then return gun.ray end
  local ow = G and G.overworld
  if not (ow and ow.player and ow.map) then return nil end
  local p = ow.player
  local gh = 0
  pcall(function()
    gh = V.require("VoxelScene").groundAt(ow.map, p.cellX, p.cellY) or 0
  end)
  local cp = math.cos(FirstPerson.pitch)
  return {
    p.px + 8, gh + FirstPerson.EYE_HEIGHT, p.py + 8,
    math.sin(FirstPerson.yaw) * cp,
    -math.sin(FirstPerson.pitch),
    math.cos(FirstPerson.yaw) * cp,
  }
end

-- How far the ray travels before terrain stops it. A wall in this world
-- is a cell whose ground stands taller than the ray does where it crosses
-- it, which is the same test for a fence you can shoot over, a building
-- you cannot, and a doorway you can shoot through.
local function occlusion(map, r)
  local VoxelScene = V.require("VoxelScene")
  local step = 3
  local t = step
  while t <= HordeGun.RANGE do
    local x = r[1] + r[4] * t
    local y = r[2] + r[5] * t
    local z = r[3] + r[6] * t
    local cx, cy = math.floor(x / 16), math.floor(z / 16)
    if not map:inBounds(cx, cy) then return t end
    local gh = 0
    local ok, got = pcall(VoxelScene.groundAt, map, cx, cy)
    if ok and got then gh = got end
    if y < gh - 0.5 then return t end
    if y < 0 then return t end
    t = t + step
  end
  return HordeGun.RANGE
end

-- The nearest mob the ray reaches, and whether it caught the head.
local function pick(G, r, maxT)
  local Mobs = V.require("HordeMobs")
  local VoxelScene = V.require("VoxelScene")
  local ow = G and G.overworld
  if not (ow and ow.map) then return nil end
  local flat = r[4] * r[4] + r[6] * r[6]
  if flat < 1e-6 then return nil end
  local best, bestT, bestHead = nil, maxT, false
  for _, e in ipairs(Mobs.list()) do
    local npc = e.npc
    if npc and not e.dead and e.mapId == ow.map.id then
      local mx, mz = npc.px + 8, npc.py + 8
      local t = ((mx - r[1]) * r[4] + (mz - r[3]) * r[6]) / flat
      if t > 0 and t < bestT then
        local hx = r[1] + r[4] * t - mx
        local hz = r[3] + r[6] * t - mz
        if hx * hx + hz * hz <= HordeGun.HIT_RADIUS * HordeGun.HIT_RADIUS then
          local gh = 0
          local ok, got = pcall(VoxelScene.groundAt, ow.map,
                                npc.cellX, npc.cellY)
          if ok and got then gh = got end
          local y = r[2] + r[5] * t
          if y >= gh - 2 and y <= gh + 17 then
            best, bestT, bestHead = e, t, y >= gh + 11
          end
        end
      end
    end
  end
  return best, bestHead
end

-- Pull the trigger. Every input device funnels here (see Horde.install,
-- FirstPerson's mouse and touch wraps, and VR.driveControls), so the
-- cooldown below is also what keeps two devices reporting the same press
-- from spending two rounds.
function HordeGun.fire()
  if not Horde.playing() then return false end
  if gun.cooldown > 0 or gun.reloading then return false end
  if gun.ammo <= 0 then
    gun.cooldown = 0.35
    HordeSfx.play(HordeSfx.DRY)
    HordeGun.reload()
    return false
  end
  local G = require("src.core.Game")
  gun.ammo = gun.ammo - 1
  gun.cooldown = HordeGun.FIRE_COOLDOWN
  gun.kick = 1
  gun.flash = 0.05
  HordeSfx.shot()

  local r = ray(G)
  if r then
    local ow = G.overworld
    local maxT = ow and ow.map and occlusion(ow.map, r) or HordeGun.RANGE
    local hit, head = pick(G, r, maxT)
    if hit then
      local Mobs = V.require("HordeMobs")
      local result = Mobs.hit(hit, head and 2 or 1)
      local s = Horde.session
      if s then
        s.hitMarker = 1
        if result == "kill" and head then Horde.addScore(50) end
      end
    end
  end
  if gun.ammo <= 0 then HordeGun.reload() end
  return true
end

function HordeGun.reload()
  if gun.reloading or gun.ammo >= HordeGun.MAG then return false end
  gun.reloading = true
  gun.reloadT = 0
  gun.reloadStage = 0
  return true
end

-- ------- the frame

function HordeGun.update(dt, live)
  if not Horde.active then
    FirstPerson.fovScale = 1        -- give the lens back on the way out
    return
  end
  gun.cooldown = math.max(0, gun.cooldown - dt)
  gun.kick = math.max(0, gun.kick - dt * 7)
  gun.flash = math.max(0, gun.flash - dt)

  local target = (gun.ads and live) and 1 or 0
  local astep = dt / HordeGun.ADS_TIME
  if gun.adsBlend < target then
    gun.adsBlend = math.min(target, gun.adsBlend + astep)
  else
    gun.adsBlend = math.max(target, gun.adsBlend - astep)
  end
  -- the lens narrows with the sights. Half of what aiming does here is
  -- the model coming to the centre of the screen; the other half is this
  local e = gun.adsBlend * gun.adsBlend * (3 - 2 * gun.adsBlend)
  FirstPerson.fovScale = 1 - (1 - HordeGun.ADS_FOV / FirstPerson.FOV) * e

  if gun.reloading then
    local was = gun.reloadT
    gun.reloadT = gun.reloadT + dt
    -- three clicks on their own clock: the magazine out, the fresh one
    -- in, the slide home. Staged by time rather than animated frames so
    -- the sound and the dip below stay in step at any frame rate.
    local marks = { { 0.10, HordeSfx.MAG_OUT }, { 0.62, HordeSfx.MAG_IN },
                    { 1.15, HordeSfx.RACK } }
    for _, m in ipairs(marks) do
      if was < m[1] and gun.reloadT >= m[1] then HordeSfx.play(m[2]) end
    end
    if gun.reloadT >= HordeGun.RELOAD_TIME then
      gun.reloading = false
      gun.reloadT = 0
      gun.ammo = HordeGun.MAG
    end
  end
end

-- ------- VR placement
--
-- Called from the VR frame with the same mapping the eyes got. `pose` is
-- the tracked right hand -- the runtime's aim pose where it has one.

function HordeGun.place(pose, pivot, anchor, scale, yaw)
  if not (Horde.active and pose) then
    HordeGun.clear()
    return
  end
  local m = VRRig.propMatrix(pose, pivot, anchor, scale, yaw)
  m = Mat4.mul(m, Mat4.translate(HordeGun.HAND_OFFSET[1],
                                 HordeGun.HAND_OFFSET[2],
                                 HordeGun.HAND_OFFSET[3]))
  m = Mat4.mul(m, Mat4.rotateY(HordeGun.HAND_YAW))
  m = Mat4.mul(m, Mat4.rotateX(HordeGun.HAND_PITCH))
  -- the recoil, up and back along the gun's own axes
  local k = gun.kick
  if k > 0 then
    m = Mat4.mul(m, Mat4.translate(0, 0, -0.05 * k))
    m = Mat4.mul(m, Mat4.rotateX(-0.30 * k))
  end
  gun.frame = m

  -- the barrel, in world pixels: the shot goes where the gun points, so
  -- lining the sights up with an eye is what aims it
  local o = { m[4], m[8], m[12] }
  local dx, dy, dz = m[3], m[7], m[11]        -- the model's +Z column
  local len = math.sqrt(dx * dx + dy * dy + dz * dz)
  if len > 1e-6 then
    gun.ray = { o[1], o[2], o[3], dx / len, dy / len, dz / len }
  else
    gun.ray = nil
  end
end

function HordeGun.clear()
  gun.frame, gun.ray = nil, nil
end

-- ------- drawing
--
-- Runs inside VoxelScene's drawScene, once per eye in VR and once per
-- frame flat, after the world -- so the gun composites with real depth
-- and leaning it into a wall occludes honestly.

-- Should the gun be drawn at all this frame? Keyed on the first-person
-- rig's own IDENTITY rather than on the rung's number, because a staged
-- VR battle places a camera through the same seam and the gun has no
-- business in it.
function HordeGun.visible()
  if not Horde.active then return false end
  if gun.frame then return true end
  return FirstPerson.cardBlend() > 0.35
end

-- The flat screen's view model matrix: carried by the camera, offset to
-- the hip or the sight line, with the recoil on top.
local function flatModel()
  local cam = Voxel3D.camera
  local eye = cam and cam.eye
  if not eye then return nil end
  local a = gun.adsBlend
  a = a * a * (3 - 2 * a)
  local hip, ads = HordeGun.HIP, HordeGun.ADS
  local ox = hip[1] + (ads[1] - hip[1]) * a
  local oy = hip[2] + (ads[2] - hip[2]) * a
  local oz = hip[3] + (ads[3] - hip[3]) * a
  -- the reload dip: the gun swings down and out of the shot while the
  -- hands are busy, easing back as the slide comes home
  if gun.reloading then
    local t = math.min(1, gun.reloadT / HordeGun.RELOAD_TIME)
    local dip = math.sin(math.min(1, t * 1.15) * math.pi)
    oy = oy - 0.09 * dip
    ox = ox - 0.03 * dip
  end
  local k = gun.kick
  oz = oz - 0.045 * k

  local m = Mat4.translate(eye[1], eye[2], eye[3])
  m = Mat4.mul(m, Mat4.rotateY(FirstPerson.yaw))
  m = Mat4.mul(m, Mat4.rotateX(FirstPerson.pitch - 0.34 * k))
  m = Mat4.mul(m, Mat4.scale(VRRig.FP_SCALE, VRRig.FP_SCALE, VRRig.FP_SCALE))
  m = Mat4.mul(m, Mat4.translate(ox, oy, oz))
  if gun.reloading then
    local t = math.min(1, gun.reloadT / HordeGun.RELOAD_TIME)
    m = Mat4.mul(m, Mat4.rotateX(-0.55 * math.sin(math.min(1, t * 1.15)
                                                  * math.pi)))
  end
  return m
end

function HordeGun.draw()
  if not HordeGun.visible() then return end
  local model = gun.frame or flatModel()
  if not model then return end
  local body, pal = buildBody(), palette()
  if not (body and pal) then return end
  Voxel3D.draw(body, pal, model)
  if gun.flash > 0 then
    local flash = buildFlash()
    if flash then Voxel3D.draw(flash, pal, model) end
  end
end

function HordeGun.invalidate()
  paletteTex, bodyMesh, flashMesh = nil, nil, nil
end

return HordeGun
