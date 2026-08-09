-- VR: the POKEDEX in the player's left hand -- a voxel model of the
-- series' own field guide, strapped to the tracked grip pose, whose
-- screen is a real texture the mod can put a picture on.
--
-- Why it exists: a staged VR battle needs the 2D battle screen SOMEWHERE
-- -- the text, the menus, the HP bars are the game -- but a flat panel
-- floating square in front of the fight hides the fight. A trainer in
-- the world already has the right prop for "a handheld device with a
-- screen": look down at the Pokedex in your hand to read the battle,
-- look up to watch it happen on the map.
--
-- THE MODEL is authored here in voxels, in METRES (VOX metres a voxel),
-- around its own centre, front face +Z -- a red slab with the lens, the
-- LEDs, the hinge and a d-pad, and a dark bezel the screen sits proud
-- of. It rides VRRig.propMatrix, the same XR-to-world mapping the eyes
-- use, so it sits exactly where the hand is and keeps its real size in
-- every mode: a hand-sized device over the diorama, the same hand-sized
-- device at life scale in first person and in battle.
--
-- THE SCREEN is a separate one-quad mesh drawn with its own texture --
-- whatever canvas the caller hands `Pokedex.screen` (the VR frame hands
-- it the front buffer during a battle, cropped by UV to the battle's own
-- letterbox). No texture leaves the screen dark: a device that is off.
--
-- Everything here is passive state plus a draw call; VR.lua decides when
-- the frame exists (hand tracked, session live) and VoxelScene's eye
-- pass draws it after the world, so it composites with real depth
-- against everything else.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Mat4 = V.require("Mat4")
local Voxel3D = V.require("Voxel3D")
local VRRig = V.require("VRRig")

local Pokedex = {}

-- one voxel, in metres: a centimetre-ish grid gives the classic chunky
-- read at a device you can read a battle off (the body below comes out
-- about 12 x 19 x 3 cm -- a quarter up from the first, believable size,
-- because the screen carries every menu and was squint-small in hand)
Pokedex.VOX = 0.011 * 1.25

-- Where the device sits relative to the GRIP pose, in metres, and how it
-- is tipped. A full quarter turn forward lays the slab exactly along the
-- controller's own body -- verified in the headset -- so holding the
-- controller IS holding the device: raise your fist and the screen faces
-- you. These two are the whole of the attachment.
Pokedex.OFFSET = { 0, 0.04, -0.02 }
Pokedex.TILT = -math.pi / 2      -- radians about X: 90 degrees forward,
                                 -- flush with the controller

-- body proportions, in voxels
local W, H, D = 9, 14, 2

-- the palette the body's faces point their UVs at, one texel per colour
local COLORS = {
  { 200, 40, 48 },    -- 1 body red
  { 140, 24, 32 },    -- 2 hinge / shaded red
  { 64, 132, 244 },   -- 3 the lens blue
  { 208, 228, 255 },  -- 4 lens glint
  { 232, 60, 48 },    -- 5 LED red
  { 248, 216, 64 },   -- 6 LED yellow
  { 72, 200, 96 },    -- 7 LED green
  { 46, 46, 54 },     -- 8 bezel / d-pad dark
  { 24, 24, 30 },     -- 9 the dark screen (the "off" state's face)
}

local paletteTex = nil          -- one texel per COLORS entry
local bodyMesh = nil
local screenMesh = nil
local screenKey = nil           -- the UV rect screenMesh was built for

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

-- Append one solid box's six faces to `verts`/`indices`: position in
-- voxels (relative to the device centre), size in voxels, colour by
-- palette index. Faces carry the mod's own directional shade, so the
-- slab reads as a solid the way every extruded block here does.
local function box(verts, indices, x, y, z, w, h, d, color)
  local u = (color - 0.5) / #COLORS
  local vox = Pokedex.VOX
  local ox, oy, oz = (x - W / 2) * vox, (y - H / 2) * vox, (z - D / 2) * vox
  local sx, sy, sz = w * vox, h * vox, d * vox
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

-- the screen's face on the front, in voxels (10:9, the GB frame's shape),
-- shared by the dark "off" face in the body and the live quad
local SCREEN = { x = 1.2, y = 4.6, w = 6.6, h = 5.94 }

local function buildBody()
  if bodyMesh then return bodyMesh end
  local verts, indices = {}, {}
  -- the slab, the hinge along the right edge, the lens, the LEDs, the
  -- d-pad and two chunky buttons -- the classic cover furniture, one box
  -- each on the front face (z = D..)
  box(verts, indices, 0, 0, 0, W, H, D, 1)                       -- body
  box(verts, indices, W - 0.7, 0, 0, 0.7, H, D + 0.15, 2)        -- hinge
  box(verts, indices, 0.6, H - 2.6, D, 2, 2, 0.5, 3)             -- lens
  box(verts, indices, 0.9, H - 1.3, D + 0.5, 0.6, 0.5, 0.12, 4)  -- glint
  box(verts, indices, 3.2, H - 1.6, D, 0.8, 0.8, 0.35, 5)        -- LEDs
  box(verts, indices, 4.5, H - 1.6, D, 0.8, 0.8, 0.35, 6)
  box(verts, indices, 5.8, H - 1.6, D, 0.8, 0.8, 0.35, 7)
  -- the bezel plate the screen sits in, and the dark screen face itself
  -- (what shows when nothing is on: a device that is off, not a hole)
  box(verts, indices, SCREEN.x - 0.4, SCREEN.y - 0.4, D,
      SCREEN.w + 0.8, SCREEN.h + 0.8, 0.4, 8)
  box(verts, indices, SCREEN.x, SCREEN.y, D + 0.4,
      SCREEN.w, SCREEN.h, 0.1, 9)
  -- d-pad below the screen, two crossed bars, and the A/B buttons
  box(verts, indices, 5.6, 1.1, D, 2.1, 0.7, 0.45, 8)
  box(verts, indices, 6.3, 0.4, D, 0.7, 2.1, 0.45, 8)
  box(verts, indices, 1.2, 0.8, D, 1.1, 1.1, 0.45, 5)
  box(verts, indices, 2.9, 0.8, D, 1.1, 1.1, 0.45, 8)
  bodyMesh = Voxel3D.newMesh(verts, indices)
  return bodyMesh
end

-- The live screen: one quad a hair proud of the dark face, UV-mapped to
-- `uv` = { u0, v0, u1, v1 } of whatever texture is on it. Rebuilt only
-- when the UV rect moves (a window resize moving the battle letterbox).
local function buildScreen(uv)
  local key = table.concat({ uv[1], uv[2], uv[3], uv[4] }, ":")
  if screenMesh and screenKey == key then return screenMesh end
  local vox = Pokedex.VOX
  local x0 = (SCREEN.x - W / 2) * vox
  local y0 = (SCREEN.y - H / 2) * vox
  local x1 = x0 + SCREEN.w * vox
  local y1 = y0 + SCREEN.h * vox
  local z = (D / 2 + 0.55) * vox
  local u0, v0, u1, v1 = uv[1], uv[2], uv[3], uv[4]
  local verts = {
    { x0, y0, z, u0, v1, 1 }, { x1, y0, z, u1, v1, 1 },
    { x1, y1, z, u1, v0, 1 }, { x0, y1, z, u0, v0, 1 },
  }
  local indices = {}
  Voxel3D.pushQuad(indices, 0)
  local mesh = Voxel3D.newMesh(verts, indices)
  if mesh then
    screenMesh, screenKey = mesh, key
  end
  return mesh
end

-- ------- the frame's state, set by VR.lua
--
-- nil = no pokedex this frame (no session, no tracked left hand).
Pokedex.frame = nil

-- Stand the device on a tracked LEFT-HAND pose under the current
-- XR-to-world mapping (the same pivot/anchor/scale/yaw the eyes got).
function Pokedex.place(pose, pivot, anchor, scale, yaw)
  local m = VRRig.propMatrix(pose, pivot, anchor, scale, yaw)
  m = Mat4.mul(m, Mat4.translate(Pokedex.OFFSET[1], Pokedex.OFFSET[2],
                                 Pokedex.OFFSET[3]))
  m = Mat4.mul(m, Mat4.rotateX(Pokedex.TILT))
  Pokedex.frame = { model = m }
end

-- What the screen shows: a texture and the UV rect of it to fill the
-- screen with. nil for a dark screen. Only meaningful after place().
function Pokedex.screen(tex, u0, v0, u1, v1)
  if Pokedex.frame and tex then
    Pokedex.frame.tex = tex
    Pokedex.frame.uv = { u0 or 0, v0 or 0, u1 or 1, v1 or 1 }
  end
end

function Pokedex.clear()
  Pokedex.frame = nil
end

-- Draw the device with the scene's own pass (model matrix in world px).
-- Runs inside VoxelScene's drawScene, per eye; no shadow-caster half --
-- a UI prop should receive the world's light, not throw shade on it.
function Pokedex.draw()
  local f = Pokedex.frame
  if not f then return end
  local body = buildBody()
  local pal = palette()
  if body and pal then
    Voxel3D.draw(body, pal, f.model)
  end
  if f.tex and f.uv then
    local screen = buildScreen(f.uv)
    if screen then
      Voxel3D.draw(screen, f.tex, f.model)
    end
  end
end

-- window resize / hot reload: every GPU object here is derived and cheap
function Pokedex.invalidate()
  paletteTex, bodyMesh, screenMesh, screenKey = nil, nil, nil, nil
end

return Pokedex
