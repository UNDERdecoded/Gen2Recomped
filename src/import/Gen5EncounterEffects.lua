-- BLACK AND WHITE'S INTO-BATTLE EFFECTS: the field picture on a 3D model.
--
-- ov21's dispatcher (0x021CF498) runs one of 37 effects out of the table at
-- 0x021DB4FC ({start, draw, overlay, param, heap} x 37). Six of them -- the
-- ordinary ones -- live in overlay 76 and are all the same program
-- (0x021F52D8 / 0x021F5334) over a different model of /a/1/2/9:
--
--   effect  0  ee_yasei1   members 7 / 6    wild, grass
--   effect  1  ee_yasei2   members 9 / 8    wild, the other grass call
--   effect  5  ee_trnor    members 5 / 4    trainer
--   effect  6  ee_trmizu   members 3 / 2    trainer, on water
--   effect 31  ee_symbol   members 1 / 0    the legends' "symbol" battles
--   effect 35  ee_zoroark  members 11 / 10  Zoroark
--
-- The program: two white flashes of the top screen (brightness 0 -> 16 -> 0,
-- twice); the frame is captured into the model's 256 x 192 direct-colour
-- texture ("direct"); the model's joint animation plays a frame a tick; 20
-- frames before its end both screens fade to white (mask 12: the param is 1
-- for all six), and the effect ends when both are done.
--
-- THE CAMERA is arm9 0x0202E688's own, not the field's: G3_Perspective with
-- the half-FOV of sin 1398 / cos 3850 (19.96 degrees), aspect 0x1555 (4:3),
-- near 1, far 1024; G3_LookAt from (0, 0, 528) at the origin, up +Y; the
-- model turned 90 degrees about X (0x0207AF00 with sin 4096 / cos 0). The
-- model's rest plane is 512 x 384 at the origin, which that camera sees as
-- exactly the screen -- so frame 0 is the field, untouched.
--
-- What is baked: every vertex in that camera's world space (the turn applied)
-- per animation frame, so the renderer only projects. Positions are the
-- model's units (the vertex at its posScale).
--
-- PACKED, because as numbers it is five megabytes of Lua: every list is a hex
-- string of 16-bit values (4 digits each, two's complement) -- positions at
-- 1/8 unit, texture coordinates at 1/4096 of the texture, the triangles'
-- 1-based vertex numbers as they are. `M.unpack(effect)` reads them back.

local M = {}

M.PATH = "/a/1/2/9"
M.EFFECTS = {
  [0] = { name = "ee_yasei1", model = 7, anim = 6 },
  [1] = { name = "ee_yasei2", model = 9, anim = 8 },
  [5] = { name = "ee_trnor", model = 5, anim = 4 },
  [6] = { name = "ee_trmizu", model = 3, anim = 2 },
  [31] = { name = "ee_symbol", model = 1, anim = 0 },
  [35] = { name = "ee_zoroark", model = 11, anim = 10 },
}
M.CAMERA = { eyeZ = 528, tanHalfY = 1398 / 3850, aspect = 0x1555 / 4096, near = 1, far = 1024 }
M.TEXTURE = { 256, 192 }

local function round(v) return math.floor(v * 100 + 0.5) / 100 end

M.POS_SCALE, M.UV_SCALE = 8, 4096

local function pack(list, scale)
  local out = {}
  for i, v in ipairs(list) do
    local n = math.floor(v * scale + 0.5)
    if n < -32768 then n = -32768 elseif n > 32767 then n = 32767 end
    out[i] = ("%04x"):format(n % 65536)
  end
  return table.concat(out)
end

M.pack = pack

-- digits by byte: read as the into-battle effect first plays, and a sub() +
-- tonumber() per value cost most of a frame interpreted (love-android runs
-- with the JIT off); `pack` writes only lowercase hex, four digits a value
local HEX = {}
for c = 0, 255 do HEX[c] = 0 end
for d = 0, 9 do HEX[48 + d] = d end
for d = 0, 5 do HEX[65 + d] = 10 + d; HEX[97 + d] = 10 + d end
local byte = string.byte

local function unpackList(text, scale)
  local out, k = {}, 0
  local len = #text
  for i = 1, len, 4 do
    local n
    if i + 3 <= len then
      local a, b, c, d = byte(text, i, i + 3)
      n = HEX[a] * 4096 + HEX[b] * 256 + HEX[c] * 16 + HEX[d]
    else
      n = tonumber(text:sub(i, i + 3), 16) or 0
    end
    if n >= 32768 then n = n - 65536 end
    k = k + 1
    out[k] = n / scale
  end
  return out
end

-- unpack(effect) -> effect, its lists read back (cached on it)
function M.unpack(eff)
  if not eff or eff.uv then return eff end
  eff.uv = unpackList(eff.uvHex or "", M.UV_SCALE)
  eff.tris = unpackList(eff.trisHex or "", 1)
  eff.pos = {}
  for f, text in ipairs(eff.posHex or {}) do eff.pos[f] = unpackList(text, M.POS_SCALE) end
  return eff
end

-- bake(modelBytes, animBytes, opts) -> { frames, uv = {u, v, ...},
--   tris = {a, b, c, ...}, pos = { [frame] = {x, y, z, ...} }, shapes } or nil, why
-- opts.flat: no turn about X (the scenes are modelled facing the camera);
-- opts.sizeOf(shape, model): the texture's size for that shape (the screen's
-- 256 x 192 by default). `shapes` lists each shape's first triangle and count.
function M.bake(modelBytes, animBytes, opts)
  opts = opts or {}
  local Nsbmd = require("src.import.Gen4Nsbmd")
  local Anim = require("src.import.Gen4Anim")
  local parsed = Nsbmd.parse(modelBytes)
  local md = parsed and parsed.models and parsed.models[1]
  if not md then return nil, "no model" end
  local info = animBytes and Anim.parse(animBytes)
  local anim = info and info.animations and info.animations[1]
  local joints = anim and Anim.jointMatrices(animBytes, anim)
  if not joints then
    -- a model with no joint animation (opts.bindPose) stands in its rest pose
    if not opts.bindPose then return nil, "no joint animation" end
    joints, anim = {}, { frames = 1 }
  end
  local scale = md.posScale or 1
  local tw, th = M.TEXTURE[1], M.TEXTURE[2]
  local out = { name = md.name, frames = anim.frames, uv = {}, tris = {}, pos = {}, shapes = {} }
  local verts = {}
  for shapeIndex, shape in ipairs(md.shapes) do
    local base = #verts
    if opts.sizeOf then tw, th = opts.sizeOf(shape, md) end
    out.shapes[shapeIndex] = { first = #out.tris / 3, count = #shape.triangles, shape = shape }
    for _, v in ipairs(shape.vertices) do
      verts[#verts + 1] = { v = v, shape = shapeIndex - 1 }
      out.uv[#out.uv + 1] = round(v.u / tw * 10000) / 10000
      out.uv[#out.uv + 1] = round(v.v / th * 10000) / 10000
    end
    for _, t in ipairs(shape.triangles) do
      out.tris[#out.tris + 1] = base + t[1]
      out.tris[#out.tris + 1] = base + t[2]
      out.tris[#out.tris + 1] = base + t[3]
    end
  end
  for f = 0, anim.frames - 1 do
    local P = Nsbmd.pose(md.pose, function(node)
      local j = joints[node + 1]
      return j and j.track[f + 1] or (md.bones[node + 1] and md.bones[node + 1].matrix)
    end, md.inverseBind, md.scalingRule)
    local frame = {}
    for _, e in ipairs(verts) do
      local v = e.v
      local stack = P.stacks[e.shape] or P.stack
      local m = (v.matrix and stack[v.matrix]) or P[e.shape]
      local x, y, z = v.x * scale, v.y * scale, v.z * scale
      local wx = m[1] * x + m[2] * y + m[3] * z + m[4]
      local wy = m[5] * x + m[6] * y + m[7] * z + m[8]
      local wz = m[9] * x + m[10] * y + m[11] * z + m[12]
      -- the 90-degree turn about X: model Y comes at the camera, model Z
      -- becomes down
      if opts.flat then
        frame[#frame + 1] = round(wx)
        frame[#frame + 1] = round(wy)
        frame[#frame + 1] = round(wz)
      else
        frame[#frame + 1] = round(wx)
        frame[#frame + 1] = round(-wz)
        frame[#frame + 1] = round(wy)
      end
    end
    out.pos[f + 1] = frame
  end
  return out
end

function M.build(x)
  local Narc = require("src.import.NarcArchive")
  local Lz = require("src.import.Gen5Lz")
  local raw = x.rom:read(M.PATH)
  local arc = raw and Narc.parse(raw)
  if not arc then return nil end
  local function member(i)
    local b = arc:get(i)
    if b and Lz.isCompressed(b) then b = Lz.decompress(b) end
    return b
  end
  local out = { camera = M.CAMERA, effects = {},
                source = "ROM:" .. M.PATH .. " (ov76 0x021F52D8, camera arm9 0x0202E688)" }
  for id, e in pairs(M.EFFECTS) do
    local ok, baked = pcall(M.bake, member(e.model), member(e.anim))
    if ok and baked then
      baked.effect = id
      local posHex = {}
      for f, list in ipairs(baked.pos) do posHex[f] = pack(list, M.POS_SCALE) end
      out.effects[e.name] = { name = baked.name, effect = id, frames = baked.frames,
                              uvHex = pack(baked.uv, M.UV_SCALE), trisHex = pack(baked.tris, 1),
                              posHex = posHex }
    else
      print(("Gen5EncounterEffects: %s failed: %s"):format(e.name, tostring(baked)))
    end
  end
  -- the special trainers' and legends' cut-ins (src/import/Gen5EncounterCutIns.lua)
  local okCut, cutins = pcall(require("src.import.Gen5EncounterCutIns").build, x)
  if okCut then out.cutins = cutins
  else print("Gen5EncounterEffects: cut-ins failed: " .. tostring(cutins)) end
  local okScenes, scenes = pcall(M.buildScenes, x)
  if okScenes then out.scenes = scenes
  else print("Gen5EncounterEffects: scenes failed: " .. tostring(scenes)) end
  return out
end

-- THE SCENES: effects 3 and 4 are ov73's "3D object" effects over the live
-- field -- ov74's records 24 / 25 name /a/1/1/7 scenes 21 / 22, and those
-- name /a/1/1/5's models and joint animations:
--
--   effect 3  cave_ci  members 118 / 119  a black curtain, its lower edge
--                                         jagged, dropped over the screen
--   effect 4  sand_ci  members 120 / 121  a sand sheet swept left to right
--
-- Drawn in the view every ov73 scene is built for, +-64 x +-48 units at
-- z = 0 (see Gen5EncounterCutIns: the cut-ins' own full-screen planes fix
-- it); the curtain, +-70 wide, covers it once down. These two run no
-- particles (the record's SPA slot is 0xFFFF).
M.SCENE_PATH = "/a/1/1/5"
M.SCENES = {
  [3] = { name = "cave_ci", model = 118, anim = 119 },
  [4] = { name = "sand_ci", model = 120, anim = 121 },
}
M.SCENE_VIEW = { halfY = 48, aspect = 0x1555 / 4096 }

function M.buildScenes(x)
  local Narc = require("src.import.NarcArchive")
  local Lz = require("src.import.Gen5Lz")
  local Models = require("src.import.Gen4Models")
  local raw = x.rom:read(M.SCENE_PATH)
  local arc = raw and Narc.parse(raw)
  if not arc then return nil end
  local function member(i)
    local b = arc:get(i)
    if b and Lz.isCompressed(b) then b = Lz.decompress(b) end
    return b
  end
  local out = { view = M.SCENE_VIEW, source = "ROM:" .. M.SCENE_PATH .. " via /a/1/1/7 scenes 21 / 22" }
  for id, e in pairs(M.SCENES) do
    local bytes = member(e.model)
    local at = bytes and bytes:find("TEX0", 1, true)
    local tex = at and Models.parse(bytes, at - 1)
    local Nsbmd = require("src.import.Gen4Nsbmd")
    local md = Nsbmd.parse(bytes).models[1]
    local function textureOf(shape)
      local mat = md.materials[(shape.material or 0) + 1]
      local tname = mat and mat.texture
      for k, t in ipairs(tex and tex.textures or {}) do
        if t.name == tname then return k, t, mat end
      end
    end
    local baked = M.bake(bytes, member(e.anim), { flat = true, sizeOf = function(shape)
      local _, t = textureOf(shape)
      return t and t.width or 1, t and t.height or 1
    end })
    local shapes = {}
    for si, sh in ipairs(baked.shapes) do
      local k, t, mat = textureOf(sh.shape)
      local image, saved
      if k then
        local pal = 1
        for pk, pl in ipairs(tex.palettes or {}) do if mat and pl.name == mat.palette then pal = pk end end
        image = Models.decode(tex, bytes, k, pal)
        saved = image and x:saveImage(("battle5/encounter/%s_%s"):format(e.name, t.name:gsub("[^%w_%-]", "_")), image)
      end
      shapes[si] = { first = sh.first, count = sh.count, image = saved and saved.path or nil,
                     texture = t and t.name or nil }
    end
    local posHex = {}
    for f, list in ipairs(baked.pos) do posHex[f] = pack(list, M.POS_SCALE) end
    out[e.name] = { name = e.name, effect = id, frames = baked.frames, shapes = shapes,
                    uvHex = pack(baked.uv, M.UV_SCALE), trisHex = pack(baked.tris, 1), posHex = posHex }
  end
  return out
end

return M
