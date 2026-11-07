-- The frame: Emerald 3DS's CtrVoxel_Draw on LOVE.
--
--   * map instances: the current map at (0, 0) and the engine's own placed
--     neighbours, each built once (Builder) and translated by its origin;
--   * the camera (voxel_camera.c): pitch from the ANGLE rung, vertical FOV
--     35, eye south of the player at (8 + scale) * 100 / zoom cells, easing
--     0.15 a frame toward the player's tile corner, raised and shifted by the
--     relief under it;
--   * terrain, trees and buildings alpha-tested on a depth buffer, no culling;
--   * characters as upright cards turned to the camera, sized by
--     sqrt(cos pitch), feet on their tile's centre lifted by the relief;
--   * the player's silhouette where a wall hides them;
--   * the shading equation of voxel.v.pica: shade x sun/shade tint, the 1.30
--     saturation grade, and distance haze outdoors.

local V = ...
local Data = V.require("Data")
local Atlas = V.require("Atlas")
local Builder = V.require("Builder")
local Trees = V.require("Trees")

local Render = {}

local floor, sqrt, rad = math.floor, math.sqrt, math.rad

Render.ANGLES = { 34, 37, 40, 43, 46 }
Render.zoom = 100

-- ------------------------------------------------------------- matrices --

local function mul(a, b)
  local r = {}
  for i = 0, 3 do
    for j = 0, 3 do
      local s = 0
      for k = 0, 3 do s = s + a[i * 4 + k + 1] * b[k * 4 + j + 1] end
      r[i * 4 + j + 1] = s
    end
  end
  return r
end

local function perspective(fovY, aspect, near, far)
  local f = 1 / math.tan(fovY / 2)
  local d = near - far
  return { f / aspect, 0, 0, 0,
           0, f, 0, 0,
           0, 0, (far + near) / d, 2 * far * near / d,
           0, 0, -1, 0 }
end

local function lookAt(ex, ey, ez, tx, ty, tz)
  local fx, fy, fz = tx - ex, ty - ey, tz - ez
  local fl = sqrt(fx * fx + fy * fy + fz * fz)
  fx, fy, fz = fx / fl, fy / fl, fz / fl
  -- s = f x up(0,1,0)
  local sx, sy, sz = -fz, 0, fx
  local sl = sqrt(sx * sx + sz * sz)
  sx, sz = sx / sl, sz / sl
  -- u = s x f
  local ux, uy, uz = sy * fz - sz * fy, sz * fx - sx * fz, sx * fy - sy * fx
  return { sx, sy, sz, -(sx * ex + sy * ey + sz * ez),
           ux, uy, uz, -(ux * ex + uy * ey + uz * ez),
           -fx, -fy, -fz, (fx * ex + fy * ey + fz * ez),
           0, 0, 0, 1 }
end

local function translate(x, y, z)
  return { 1, 0, 0, x, 0, 1, 0, y, 0, 0, 1, z, 0, 0, 0, 1 }
end

local function transform(m, x, y, z)
  local cx = m[1] * x + m[2] * y + m[3] * z + m[4]
  local cy = m[5] * x + m[6] * y + m[7] * z + m[8]
  local cz = m[9] * x + m[10] * y + m[11] * z + m[12]
  local cw = m[13] * x + m[14] * y + m[15] * z + m[16]
  return cx, cy, cz, cw
end

-- --------------------------------------------------------------- shader --

local SHADER = [[
varying float vDist;
#ifdef VERTEX
uniform mat4 vp;
uniform mat4 model;
uniform mat4 view;
vec4 position(mat4 transform_projection, vec4 vertex_position) {
  vec4 w = model * vertex_position;
  vDist = -(view * w).z;
  return vp * w;
}
#endif
#ifdef PIXEL
uniform vec3 sunTint;
uniform vec3 shadeTint;
uniform vec3 hazeRgb;
uniform vec3 haze;        // start, scale, max
uniform float silhouette;       // 1 = a silhouette: flat colour, the texel's alpha
uniform vec4 flatColor;
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen) {
  vec4 t = Texel(tex, uv);
  if (t.a < 0.5) discard;
  if (silhouette > 0.5) return vec4(flatColor.rgb, flatColor.a);
  float y = dot(t.rgb, vec3(0.299, 0.587, 0.114));
  vec3 graded = clamp(vec3(y) + (t.rgb - vec3(y)) * 1.30, 0.0, 1.0);
  float shade = color.r;
  float lit = clamp((shade - 0.62) / (1.0 - 0.62), 0.0, 1.0);
  vec3 rgb = graded * shade * mix(shadeTint, sunTint, lit);
  float h = clamp((vDist - haze.x) * haze.y, 0.0, haze.z);
  return vec4(mix(rgb, hazeRgb, h), 1.0);
}
#endif
]]

local function compat(source)
  local major = love.getVersion and love.getVersion() or 11
  if major < 12 then return source end
  -- the engine's answer knows the backend (Metal has no flip to cancel)
  local okCore, core = pcall(require, "src.render.ClipSpaceCompat")
  if okCore and core and core.shader then return core.shader(source) end
  local count
  source, count = source:gsub("vec4%s+position%s*%(", "vec4 legacyPosition(")
  if count == 0 then return source end
  return source .. [[
#ifdef VERTEX
vec4 position(mat4 transform_projection, vec4 vertex_position) {
  vec4 clip = legacyPosition(transform_projection, vertex_position);
  clip.y *= love_ClipSpaceParams.x;
  return clip;
}
#endif
]]
end

local shader
local function getShader()
  if shader == nil then
    local ok, made = pcall(love.graphics.newShader, compat(SHADER))
    shader = ok and made or false
    if not ok then V.log("shader failed: %s", tostring(made)) end
  end
  return shader or nil
end

function Render.available()
  return love.graphics and love.graphics.newCanvas and love.graphics.setDepthMode
    and getShader() ~= nil
end

-- --------------------------------------------------------- render target --

local targets = {}
local DEPTH_FORMATS = { "depth24", "depth24stencil8", "depth32f", "depth16" }
local function releaseTarget(t)
  pcall(t.color.release, t.color)
  if t.depth then pcall(t.depth.release, t.depth) end
end
-- a colour + depth pair the size of the window; `slot` keeps the battle's
-- apart from the field's
local function targetFor(w, h, slot)
  slot = slot or "field"
  local target = targets[slot]
  if target and target.w == w and target.h == h then return target end
  if target then releaseTarget(target) end
  local color = love.graphics.newCanvas(w, h)
  local depth
  for _, f in ipairs(DEPTH_FORMATS) do
    local ok, made = pcall(love.graphics.newCanvas, w, h, { format = f })
    if ok then depth = made break end
  end
  target = { w = w, h = h, color = color, depth = depth }
  targets[slot] = target
  return target
end

function Render.invalidate()
  for _, t in pairs(targets) do releaseTarget(t) end
  targets = {}
end

-- ------------------------------------------------------------ instances --

local built = setmetatable({}, { __mode = "k" })   -- map -> instance
local failed = setmetatable({}, { __mode = "k" })

-- Is a sheet record's picture still there?  The engine frees the sheets of
-- the tileset pairs it has not drawn lately (TileRenderer gen3Evict).
local function alive(record)
  if not (record and record.bottom and record.top) then return false end
  return pcall(record.bottom.getWidth, record.bottom) and pcall(record.top.getWidth, record.top)
end
Render.alive = alive

local function instanceOf(map)
  local inst = built[map]
  -- built from a sheet the engine has since replaced: build it again
  if inst and (inst.atlas.record ~= (map.renderer and map.renderer.gen3) or not alive(inst.atlas.record)) then
    built[map], inst = nil, nil
  end
  if inst or failed[map] then return inst end
  if not alive(map.renderer and map.renderer.gen3) then return nil end
  local t0 = love.timer and love.timer.getTime() or os.clock()
  local ok, made = pcall(Builder.build, map)
  if ok and made then
    built[map] = made
    if os.getenv("E3DS_TIMING") then
      V.log("built %s in %.0f ms", tostring(map.def and map.def.id),
            ((love.timer and love.timer.getTime() or os.clock()) - t0) * 1000)
    end
    return made
  end
  failed[map] = true
  V.log("could not build %s: %s", tostring(map and map.def and map.def.id), tostring(made))
  return nil
end

function Render.drop()
  built = setmetatable({}, { __mode = "k" })
  failed = setmetatable({}, { __mode = "k" })
  Render.beltKey, Render.beltMesh = nil, nil
end

-- A cell's lift and shift on its own map (no deck), cells.
local function cellRelief(inst, x, y)
  local g, d = Data.reliefCell(inst.layout, x, y)
  local z = y + 0.5
  local h, dz = 0, 0
  if g then h, dz = g[12] / 16, d[12] / 16 end
  return inst.base + h, Data.stretchZ(inst.layout, z + dz) + inst.base - z
end

-- THE SEAMS.  Every map's relief is solved on its own, and the bake does
-- not always agree with itself across a connection: Route 119's top is a
-- plateau four levels up while Fortree, which stands on it, has no relief
-- and so stands at 0.  Drawn as baked, the route floats four cells above
-- the town and, by the 45-degree rule, four cells south of it too.  So a
-- neighbour is moved, as a whole, by the difference its edge and the
-- current map's edge most often show across the seam: up/down by the lift
-- and north/south by the shift, which keeps the paths across it lined up.
local seams = setmetatable({}, { __mode = "k" })
local function mostCommon(counts)
  local best, n = 0, -1
  for v, c in pairs(counts) do
    if c > n or (c == n and math.abs(v) < math.abs(best)) then best, n = v, c end
  end
  return best
end

local function seamOffset(cur, nb, ox, oy)
  local byCur = seams[cur]
  if not byCur then byCur = setmetatable({}, { __mode = "k" }); seams[cur] = byCur end
  local key = ox .. "," .. oy
  local hit = byCur[nb] and byCur[nb][key]
  if hit then return hit[1], hit[2] end
  local pairs_ = {}
  local W, H = cur.width, cur.height
  if ox >= W or ox + nb.width <= 0 then
    -- east or west: a column of cells each side
    local cx = ox >= W and W - 1 or 0
    local nx = ox >= W and 0 or nb.width - 1
    for y = math.max(0, oy), math.min(H, oy + nb.height) - 1 do
      pairs_[#pairs_ + 1] = { cx, y, nx, y - oy }
    end
  elseif oy >= H or oy + nb.height <= 0 then
    local cy = oy >= H and H - 1 or 0
    local ny = oy >= H and 0 or nb.height - 1
    for x = math.max(0, ox), math.min(W, ox + nb.width) - 1 do
      pairs_[#pairs_ + 1] = { x, cy, x - ox, ny }
    end
  end
  local lifts, shifts = {}, {}
  for _, p in ipairs(pairs_) do
    local la, sa = cellRelief(cur, p[1], p[2])
    local lb, sb = cellRelief(nb, p[3], p[4])
    local dl = floor((la - lb) * 16 + 0.5) / 16
    local ds = floor((sa - sb) * 16 + 0.5) / 16
    lifts[dl] = (lifts[dl] or 0) + 1
    shifts[ds] = (shifts[ds] or 0) + 1
  end
  local dy, dz = mostCommon(lifts), mostCommon(shifts)
  byCur[nb] = byCur[nb] or {}
  byCur[nb][key] = { dy, dz }
  return dy, dz
end

-- the instances on screen: { inst, ox, oy, dy, dz } in cells, current map
-- first; dy/dz are the seam's vertical and depth corrections (see above).
-- The current map is built at once (it is what the player stands on); its
-- neighbours stream in one a frame, so arriving in a town costs one map's
-- build and not five.  A neighbour not built yet is simply not drawn.
local function instances(state)
  local list = {}
  local cur = state.map and instanceOf(state.map)
  if cur then list[1] = { inst = cur, ox = 0, oy = 0, dy = 0, dz = 0 } end
  local budget = 1
  for _, nb in ipairs(state.neighbors or {}) do
    local inst = nb.map and built[nb.map]
    if inst and (inst.atlas.record ~= (nb.map.renderer and nb.map.renderer.gen3) or not alive(inst.atlas.record)) then
      built[nb.map], inst = nil, nil
    end
    if not inst and nb.map and not failed[nb.map] and budget > 0 then
      budget = budget - 1
      inst = instanceOf(nb.map)
    end
    if inst and cur then
      local ox, oy = (nb.ox or 0) / 16, (nb.oy or 0) / 16
      local dy, dz = seamOffset(cur, inst, ox, oy)
      list[#list + 1] = { inst = inst, ox = ox, oy = oy, dy = dy, dz = dz }
    end
  end
  return list
end

-- The engine keeps a tileset pair's sheet only while something draws it,
-- and with this mode on the engine itself draws none of the maps on screen:
-- say they are in use, or a neighbour's sheet is freed under the mod.
local function touch(list)
  local ok, TileRenderer = pcall(require, "src.render.TileRenderer")
  if not (ok and TileRenderer.touchGen3) then return end
  for _, e in ipairs(list) do
    local r = e.inst.map and e.inst.map.renderer
    if r and r.gen3Key then TileRenderer.touchGen3(r.gen3Key) end
  end
end

local function instanceAt(list, wx, wz)
  for _, e in ipairs(list) do
    local lx, lz = wx - e.ox, wz - e.oy
    if lx >= 0 and lz >= 0 and lx < e.inst.width and lz < e.inst.height then return e, lx, lz end
  end
  return nil
end

-- VoxelRelief_LiftAt / ShiftAt at a world point, plus a bridge deck
local function reliefAt(list, wx, wz, elevation)
  local e, lx, lz = instanceAt(list, wx, wz)
  if not e then
    local first = list[1]
    return first and first.inst.base or 0, 0
  end
  local inst = e.inst
  local cx, cz = floor(lx), floor(lz)
  local lift, shift = inst.base + (e.dy or 0), e.dz or 0
  local g, d = Data.reliefCell(inst.layout, cx, cz)
  if g then
    local fx, fy = (lx - cx) * 4, (lz - cz) * 4
    local i, j = math.min(3, floor(fx)), math.min(3, floor(fy))
    fx, fy = fx - i, fy - j
    local function s(t)
      local a = t[j * 5 + i] * (1 - fx) + t[j * 5 + i + 1] * fx
      local b = t[(j + 1) * 5 + i] * (1 - fx) + t[(j + 1) * 5 + i + 1] * fx
      return (a * (1 - fy) + b * fy) / 16
    end
    lift, shift = lift + s(g), shift + s(d)
  end
  -- drawn as far south as the map's base is high, and through its seam's
  -- ease (VoxelRelief_ShiftAt)
  shift = shift + Data.stretchZ(inst.layout, lz + shift - (e.dz or 0)) - (lz + shift - (e.dz or 0)) + inst.base
  local deck = Data.deckAt(inst.layout, cx, cz)
  if deck and (deck.elevation == 0 or elevation == nil or deck.elevation == elevation) then
    local up = (deck.top + (deck.bottom - deck.top) * (lz - cz)) / 16
    lift, shift = lift + up, shift + up
  end
  return lift, shift
end

-- -------------------------------------------------------------- camera --

local cam = { tx = nil, tz = nil, ground = 0 }
Render.cam = cam

-- The 3DS's 3D ZOOM (90-120 %) is the engine's own survey zoom here: the
-- wheel, '=' / '-', the hotkey and the OPTIONS row all move Zoom.offset, and
-- its scale over the fit scale is how much closer the eye comes.  Zooming
-- out past FIT pulls the eye back instead of shrinking a flat picture.
local zoomEase = nil
function Render.zoomPercent(ctx)
  local want = Render.zoom
  local okG, Game = pcall(require, "src.core.Game")
  local renderer = okG and Game and Game.renderer
  if ctx and ctx.scale and renderer and renderer.fitScale then
    local okS, S = pcall(renderer.fitScale, renderer)
    if okS and S and S > 0 then
      want = Render.zoom * math.max(0.3, math.min(2.5, ctx.scale / S))
      if os.getenv("E3DS_TIMING") and Render.saidZoom ~= ctx.scale .. "/" .. S then
        Render.saidZoom = ctx.scale .. "/" .. S
        V.log("zoom: scale %s fit %s", tostring(ctx.scale), tostring(S))
      end
    end
  end
  zoomEase = zoomEase and zoomEase + (want - zoomEase) * 0.2 or want
  if math.abs(zoomEase - want) < 0.05 then zoomEase = want end
  return zoomEase
end

local function placeCamera(state, list, dt, level, ctx)
  local p = state.player
  if not p then return end
  local px, pz = (p.px or 0) / 16, (p.py or 0) / 16
  local lift, shift = reliefAt(list, px + 0.5, pz + 0.5, p.elevation)
  pz = pz + shift
  -- a map change: walking over a connection shifts the camera by the new
  -- origin (VoxelCamera_Shift), a warp snaps it
  if cam.map ~= state.map then
    local moved = false
    if cam.map and cam.tx then
      for _, nb in ipairs(cam.neighbours or {}) do
        if nb.map == state.map then
          cam.tx, cam.tz = cam.tx - nb.ox, cam.tz - nb.oy - nb.dz
          cam.ground = cam.ground - nb.dy
          moved = true
          break
        end
      end
    end
    if not moved then cam.tx, cam.tz, cam.ground = px, pz, lift end
    cam.map = state.map
  end
  cam.neighbours = {}
  for i = 2, #list do
    local e = list[i]
    cam.neighbours[#cam.neighbours + 1] = { map = e.inst.map, ox = e.ox, oy = e.oy, dy = e.dy, dz = e.dz }
  end
  local k = 1 - (1 - 0.15) ^ math.min(4, (dt or 1 / 60) * 60)
  cam.tx = (cam.tx or px) + (px - (cam.tx or px)) * k
  cam.tz = (cam.tz or pz) + (pz - (cam.tz or pz)) * k
  cam.ground = cam.ground + (lift - cam.ground) * k
  local def = state.map.def
  local scale = 5
  local connected = def.connections and next(def.connections) ~= nil
  if not connected then
    scale = math.min(5, math.max(def.width or 0, def.height or 0) * 0.2)
  end
  cam.distance = (8 + scale) * 100 / Render.zoomPercent(ctx)
  cam.pitch = rad(Render.ANGLES[level] or 40)
  cam.ex = cam.tx
  cam.ey = cam.ground + math.tan(cam.pitch) * cam.distance
  cam.ez = cam.tz + cam.distance
end

function Render.update(dt, level, state)
  Render.dt = (Render.dt or 0) + (dt or 0)
end

-- -------------------------------------------------------------- sprites --

local cardMesh
local function card()
  if not cardMesh then
    cardMesh = love.graphics.newMesh(Builder.FORMAT, {
      { 0, 0, 0, 0, 0, 1, 1, 1, 1 }, { 0, 0, 0, 0, 0, 1, 1, 1, 1 },
      { 0, 0, 0, 0, 0, 1, 1, 1, 1 }, { 0, 0, 0, 0, 0, 1, 1, 1, 1 } }, "fan", "stream")
  end
  return cardMesh
end

local function frameOf(sprite, facing, phase, flip)
  local def = sprite.def or {}
  if (def.frames or 1) <= 1 then return 0, false end
  if def.monIcon then return floor((love.timer.getTime() or 0) * 4) % 2, false end
  if sprite.poseFrame then
    local ok, f, m = pcall(sprite.poseFrame, sprite, facing, phase, flip)
    if ok and f then return f, m end
  end
  return 0, false
end

-- the cards of everybody on screen, each a table the draw below consumes
local function cardsOf(state, list)
  local cards = {}
  local narrow = sqrt(math.cos(cam.pitch or rad(40)))
  for _, e in ipairs(state.entities or {}) do
    if not (state.flyAnim and e == state.player) and e.pose then
      local ok, sprite, vx, vy, facing, phase, flip = pcall(e.pose, e)
      if ok and sprite and sprite.frames then
        local okImg, img = pcall(sprite.resolveImage, sprite)
        local frame, mirror = frameOf(sprite, facing, phase, flip)
        local q = sprite.frames[frame] or sprite.frames[0]
        if okImg and img and q then
          local qx, qy, qw, qh = q:getViewport()
          local iw, ih = img:getDimensions()
          local cx, cz = (vx or e.px or 0) / 16 + 0.5, (e.py or 0) / 16 + 0.5
          local lift, shift = reliefAt(list, cx, cz, e.elevation)
          local hop = ((e.py or 0) - (vy or e.py or 0)) / 16
          local halfW = qw / 16 * 0.5 * narrow
          local height = qh / 16 / narrow
          local u0, u1 = qx / iw, (qx + qw) / iw
          if mirror then u0, u1 = u1, u0 end
          cards[#cards + 1] = {
            img = img, x = cx, y = lift + hop * (1 / narrow), z = cz + shift,
            halfW = halfW, height = height, u0 = u0, u1 = u1, v0 = qy / ih, v1 = (qy + qh) / ih,
            player = e == state.player,
          }
        end
      end
    end
  end
  return cards
end

local function drawCard(sh, c, shade)
  local m = card()
  local s = shade or 1
  m:setVertices({
    { c.x - c.halfW, c.y, c.z, c.u0, c.v1, s, s, s, 1 },
    { c.x + c.halfW, c.y, c.z, c.u1, c.v1, s, s, s, 1 },
    { c.x + c.halfW, c.y + c.height, c.z, c.u1, c.v0, s, s, s, 1 },
    { c.x - c.halfW, c.y + c.height, c.z, c.u0, c.v0, s, s, s, 1 } })
  m:setTexture(c.img)
  love.graphics.draw(m)
end

-- ----------------------------------------------------------------- draw --

local IDENTITY = translate(0, 0, 0)

local function covered(list)
  return function(wx, wy)
    for i = 2, #list do
      local e = list[i]
      local lx, ly = wx - e.ox, wy - e.oy
      if lx >= 0 and ly >= 0 and lx < e.inst.width and ly < e.inst.height then return true end
    end
    return false
  end
end

local function beltFor(list)
  local key = {}
  for _, e in ipairs(list) do key[#key + 1] = tostring(e.inst) .. "@" .. e.ox .. "," .. e.oy .. "," .. e.dy .. "," .. e.dz end
  key = table.concat(key, ";")
  if Render.beltKey ~= key then
    Render.beltKey = key
    local ok, made = pcall(Builder.belt, list[1].inst, covered(list), 14)
    Render.beltMesh = ok and made or nil
    if not ok then V.log("belt failed: %s", tostring(made)) end
  end
  return Render.beltMesh
end

-- The shader's frame constants, the target bound and cleared, the state
-- every pass below starts from.  Leaves a push("all") open for the caller.
local function sceneBegin(t, sh, vp, view, eyeDist, outdoor)
  sh:send("vp", "row", vp)
  sh:send("view", "row", view)
  if outdoor then
    sh:send("sunTint", { 1.00, 0.99, 0.95 })
    sh:send("shadeTint", { 0.93, 0.97, 1.05 })
    sh:send("hazeRgb", { 210 / 255, 230 / 255, 250 / 255 })
    local start, ramp, hmax = eyeDist * 1.05, eyeDist * 0.60, 0.14
    sh:send("haze", { start, hmax / ramp, hmax })
  else
    sh:send("sunTint", { 1, 1, 1 })
    sh:send("shadeTint", { 1, 1, 1 })
    sh:send("hazeRgb", { 0, 0, 0 })
    sh:send("haze", { 0, 0, 0 })
  end
  sh:send("silhouette", 0)
  sh:send("flatColor", { 1, 1, 1, 1 })

  love.graphics.push("all")
  love.graphics.origin()
  if t.depth then
    love.graphics.setCanvas({ t.color, depthstencil = t.depth })
  else
    love.graphics.setCanvas({ t.color, depth = true })
  end
  if outdoor then
    love.graphics.clear(210 / 255, 230 / 255, 250 / 255, 1, true, 1)
  else
    love.graphics.clear(0, 0, 0, 1, true, 1)
  end
  love.graphics.setDepthMode("lequal", true)
  love.graphics.setMeshCullMode("none")
  love.graphics.setBlendMode("replace")
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.setShader(sh)
end

-- Every instance's ground, trees and buildings, and the border belt.
local function drawTerrain(sh, list, cur)
  local treeImg = Trees.image()
  local function drawSet(ground, trees, buildings, page, atlasCanvas, ox, oy, dy, dz)
    sh:send("model", "row", translate(ox, dy or 0, oy + (dz or 0)))
    if ground then ground:setTexture(atlasCanvas); love.graphics.draw(ground) end
    if trees and treeImg then trees:setTexture(treeImg); love.graphics.draw(trees) end
    if buildings and page then buildings:setTexture(page); love.graphics.draw(buildings) end
  end
  for _, e in ipairs(list) do
    local inst = e.inst
    drawSet(inst.ground, inst.trees, inst.buildings, inst.page, inst.atlas.canvas, e.ox, e.oy, e.dy, e.dz)
  end
  local belt = beltFor(list)
  if belt then drawSet(belt.ground, belt.trees, nil, nil, cur.atlas.canvas, 0, 0) end
end

function Render.drawWorld(ctx, dt, level)
  local state = ctx.state
  if not (state and state.map and state.player) then return nil end
  local sh = getShader()
  if not sh then return nil end
  local list = instances(state)
  if not list[1] then return nil end
  local cur = list[1].inst
  touch(list)

  placeCamera(state, list, dt, level, ctx)

  local w, h = math.max(1, floor(ctx.width or 1)), math.max(1, floor(ctx.height or 1))
  local t = targetFor(w, h)
  local proj = perspective(rad(35), w / h, 1.0, 200.0)
  -- canvases run Y down: flip clip-space Y, as every pipeline here does
  proj = mul({ 1, 0, 0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 }, proj)
  local view = lookAt(cam.ex, cam.ey, cam.ez, cam.tx, cam.ground, cam.tz)
  local vp = mul(proj, view)
  Render.vp, Render.w, Render.h = vp, w, h

  for _, e in ipairs(list) do Atlas.animate(e.inst.atlas, e.inst.map) end

  local outdoor = cur.outdoor
  local eyeDist = cam.distance / math.cos(cam.pitch)
  sceneBegin(t, sh, vp, view, eyeDist, outdoor)
  drawTerrain(sh, list, cur)

  -- characters
  sh:send("model", "row", IDENTITY)
  local cards = cardsOf(state, list)
  -- their cast shadows (outdoors): the sprite's own picture laid on the
  -- ground and sheared away from the north-west sun, a translucent decal
  if outdoor then
    love.graphics.setDepthMode("lequal", false)
    love.graphics.setBlendMode("alpha")
    sh:send("silhouette", 1)
    sh:send("flatColor", { 8 / 255, 20 / 255, 40 / 255, 0.36 })
    local m = card()
    for _, c in ipairs(cards) do
      local y = c.y + 0.03
      local fx, fz = 0.85 * c.height, 0.55 * c.height
      m:setVertices({
        { c.x - c.halfW, y, c.z, c.u0, c.v1, 1, 1, 1, 1 },
        { c.x + c.halfW, y, c.z, c.u1, c.v1, 1, 1, 1, 1 },
        { c.x + c.halfW + fx, y, c.z + fz, c.u1, c.v0, 1, 1, 1, 1 },
        { c.x - c.halfW + fx, y, c.z + fz, c.u0, c.v0, 1, 1, 1, 1 } })
      m:setTexture(c.img)
      love.graphics.draw(m)
    end
    sh:send("silhouette", 0)
    love.graphics.setDepthMode("lequal", true)
    love.graphics.setBlendMode("replace")
  end
  for _, c in ipairs(cards) do drawCard(sh, c, 1) end
  -- the player where a wall hides them: a light silhouette, colour only
  for _, c in ipairs(cards) do
    if c.player then
      love.graphics.setDepthMode("greater", false)
      love.graphics.setBlendMode("alpha")
      sh:send("silhouette", 1)
      sh:send("flatColor", { 240 / 255, 232 / 255, 216 / 255, 0.627 })
      drawCard(sh, c, 1)
      sh:send("silhouette", 0)
      love.graphics.setDepthMode("lequal", true)
      love.graphics.setBlendMode("replace")
    end
  end

  love.graphics.setShader()
  love.graphics.setDepthMode()
  love.graphics.setBlendMode("alpha")
  -- the field effects (dust, emotes, the heal flash...) the engine owns,
  -- anchored where their ground point projects
  if ctx.drawFx then
    local function project(wx, wy)
      local x, z = wx / 16, wy / 16
      local lift, shift = reliefAt(list, x, z)
      local cx, cy, _, cw = transform(vp, x, lift, z + shift)
      if cw <= 0 then return nil end
      return (cx / cw * 0.5 + 0.5) * w, (cy / cw * 0.5 + 0.5) * h
    end
    local ax, ay = project(state.player.px or 0, state.player.py or 0)
    local bx = project((state.player.px or 0) + 16, state.player.py or 0)
    local scale = (ax and bx) and math.abs(bx - ax) / 16 or nil
    love.graphics.setCanvas(t.color)
    pcall(ctx.drawFx, project, scale)
  end
  love.graphics.pop()
  return t.color
end

-- what the battle view (Battle.lua) shares with the field's
Render.internal = {
  mul = mul, perspective = perspective, lookAt = lookAt, transform = transform,
  getShader = getShader, targetFor = targetFor, instances = instances,
  reliefAt = reliefAt, sceneBegin = sceneBegin, drawTerrain = drawTerrain,
  instanceAt = instanceAt, touch = touch,
}

return Render
