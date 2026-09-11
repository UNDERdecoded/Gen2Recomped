-- Drawing the quads.
--
-- A SOFTWARE PROJECTION, ON PURPOSE.  The geometry this shows comes out of
-- core/Mesh.lua as world-space quads, and the only thing this file does is
-- decide where they land on the screen.  It shares no code with the game's
-- renderer and claims none of its lighting: the preview is lit
-- approximately and shaped exactly, which is the right way round for a
-- tool whose whole job is to answer "what shape is this".
--
-- Depth is painter's algorithm on the quad centroid.  It is wrong for
-- interpenetrating geometry and right for everything a tile is made of,
-- and it costs no depth buffer -- which matters because a LOVE mesh is a
-- 2D primitive and the perspective divide has already happened by the time
-- it is drawn.
--
-- TEXTURING IS AFFINE WITHIN A QUAD.  A LOVE mesh interpolates uv linearly
-- in screen space, so a quad seen at a steep angle wears its art slightly
-- warped.  Quads here are eight world pixels across; at the zoom this tool
-- uses the error is under a pixel, and the alternative -- subdividing every
-- face -- would cost more than it buys.

local Render3D = {}
Render3D.__index = Render3D

-- Renderer selection, global rather than per instance: it is a property of
-- the machine, not of one viewport.  nil/true means "use the GPU path when it
-- works"; false forces the painter path.
Render3D.useGPU = nil
Render3D.gpuError = nil

function Render3D.new()
  return setmetatable({
    quads = {},
    verts = {},
    order = {},
    mesh = nil,
    capacity = 0,
  }, Render3D)
end

-- A REVISION THAT FOLLOWS THE CONTENT, not the call.
--
-- This is handed the scene's quad list every frame, and bumping the revision
-- each time meant the GPU mesh -- a quarter of a million quads on a whole
-- Hoenn map -- was rebuilt and re-uploaded sixty times a second for geometry
-- that had not changed by one vertex.  It is the same mistake the CPU path
-- made in a different place, and it cost the same.
--
-- The caller states the version; identity of the table is the fallback.
function Render3D:setQuads(quads, version)
  quads = quads or {}
  local changed
  if version ~= nil then
    changed = version ~= self.quadVersion
    self.quadVersion = version
  else
    changed = quads ~= self.quads
  end
  self.quads = quads
  if changed then self.rev = (self.rev or 0) + 1 end
end

-- --------------------------------------------------------------- camera

function Render3D.orbitCamera(target, yaw, pitch, dist, fov)
  local cy, sy = math.cos(yaw), math.sin(yaw)
  local cp, sp = math.cos(pitch), math.sin(pitch)
  local eye = {
    target[1] + dist * cp * sy,
    target[2] + dist * sp,
    target[3] + dist * cp * cy,
  }
  return { eye = eye, target = target, fov = fov or 0.9, up = { 0, 1, 0 } }
end

function Render3D.fpCamera(eye, yaw, pitch, fov)
  local cy, sy = math.cos(yaw), math.sin(yaw)
  local cp, sp = math.cos(pitch), math.sin(pitch)
  return {
    eye = eye,
    target = { eye[1] + cp * sy, eye[2] + sp, eye[3] + cp * cy },
    fov = fov or 1.2,
    up = { 0, 1, 0 },
  }
end

local function normalise(v)
  local l = math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3])
  if l < 1e-9 then return { 0, 0, 1 } end
  return { v[1] / l, v[2] / l, v[3] / l }
end

local function cross(a, b)
  return { a[2] * b[3] - a[3] * b[2],
           a[3] * b[1] - a[1] * b[3],
           a[1] * b[2] - a[2] * b[1] }
end

local function basis(cam)
  local f = normalise({ cam.target[1] - cam.eye[1],
                        cam.target[2] - cam.eye[2],
                        cam.target[3] - cam.eye[3] })
  local r = normalise(cross(f, cam.up))
  local u = cross(r, f)
  return f, r, u
end

-- ---------------------------------------------------------------- draw

-- A DEPTH BUCKET SORT, not a comparison sort.
--
-- Painter's order over twenty thousand quads with `table.sort` and a
-- comparator closure is a few hundred thousand comparisons EVERY FRAME, and
-- the pairs it was sorting were a freshly allocated two-element table each,
-- so it fed the collector at the same time.  Bucketing by depth is one pass,
-- no allocation, and the only thing it costs is that two quads inside the
-- same bucket are drawn in an arbitrary order -- at 1024 buckets across the
-- visible depth range that is a fraction of a world pixel, which is finer
-- than the geometry it is ordering.
local BUCKETS = 1024

-- ---------------------------------------------------------------- matrices

-- Column-major, flat, the way LOVE wants a mat4 sent with layout "column".
local function matMul(a, b)
  local o = {}
  for c = 0, 3 do
    for r = 0, 3 do
      o[c * 4 + r + 1] =
          a[0 * 4 + r + 1] * b[c * 4 + 1]
        + a[1 * 4 + r + 1] * b[c * 4 + 2]
        + a[2 * 4 + r + 1] * b[c * 4 + 3]
        + a[3 * 4 + r + 1] * b[c * 4 + 4]
    end
  end
  return o
end

local function lookAt(cam)
  local f, r, u = basis(cam)
  local e = cam.eye
  -- rows are the basis; the translation is -dot(basis, eye).  f is NEGATED
  -- because the view looks down -Z, which is the one sign in this whole file
  -- worth checking twice: get it wrong and the world is behind you.
  return {
    r[1], u[1], -f[1], 0,
    r[2], u[2], -f[2], 0,
    r[3], u[3], -f[3], 0,
    -(r[1] * e[1] + r[2] * e[2] + r[3] * e[3]),
    -(u[1] * e[1] + u[2] * e[2] + u[3] * e[3]),
     (f[1] * e[1] + f[2] * e[2] + f[3] * e[3]),
    1,
  }
end

-- THE Y FLIP, AND WHY IT IS HERE.
--
-- LOVE draws with y increasing DOWNWARD and compensates for the framebuffer's
-- opposite convention inside its own projection.  A shader that returns clip
-- coordinates of its own bypasses that compensation entirely -- so the world
-- came out MIRRORED VERTICALLY, which does not read as "upside down" so much
-- as "the ground is a wall": the map plane stood at an angle to the floor
-- grid, which is drawn on the CPU through LOVE's own transform and was
-- therefore right all along.  The two disagreeing is the whole symptom.
--
-- One sign, in one place, rather than flipping the image after the fact:
-- flipping at blit time would leave the depth buffer and the face winding
-- describing a world the picker does not live in.
local function perspective(fovy, aspect, near, far)
  local t = 1 / math.tan(fovy / 2)
  return {
    t / aspect, 0, 0, 0,
    0, -t, 0, 0,
    0, 0, (far + near) / (near - far), -1,
    0, 0, (2 * far * near) / (near - far), 0,
  }
end

-- Exposed for the self test: a sign error in any of these is invisible in
-- code review and unmistakable on screen, which is the worst combination
-- there is.  The test checks the composed matrix against known points --
-- centre to the origin, up to negative ndc y (LOVE's canvas is y-down),
-- east to positive x, far to larger depth.
Render3D.lookAt = lookAt
Render3D.perspective = perspective
Render3D.matMul = matMul

-- ------------------------------------------------------------- the GPU path

-- WHY THIS EXISTS.
--
-- The painter's-algorithm path below projects every corner of every quad on
-- the CPU, sorts them, writes six vertices each into a Lua table and hands
-- that to the GPU -- every frame.  On a still picture that is cached and
-- costs nothing.  While the camera is MOVING it is the whole cost, and on an
-- Emerald window with the detector's forest that is tens of thousands of
-- quads: a few hundred thousand vector operations and a couple of million
-- table stores per frame, which is exactly as slow as it sounds.
--
-- None of that work is the CPU's to do.  A vertex shader with a projection
-- matrix does it for free, and a depth buffer does the sorting -- so the
-- geometry is uploaded ONCE when the scene changes and rotating is a matrix
-- upload and a draw call.
--
-- It is guarded end to end.  A driver without depth on the backbuffer, a
-- LOVE too old for Data-backed meshes, a shader that will not compile: any of
-- those falls back to the painter path with the reason kept, because a tool
-- that renders slowly is worth having and one that renders nothing is not.
local VERTEX_FORMAT = {
  { "VertexPosition", "float", 3 },
  { "VertexTexCoord", "float", 2 },
  { "VertexColor", "byte", 4 },
}

local SHADER_SRC = [[
uniform mat4 u_mvp;
vec4 position(mat4 transform_projection, vec4 vertex_position)
{
    return u_mvp * vertex_position;
}
]]

local sharedShader, shaderTried = nil, false
local function getShader()
  if shaderTried then return sharedShader end
  shaderTried = true
  local ok, sh = pcall(love.graphics.newShader, SHADER_SRC)
  sharedShader = ok and sh or nil
  if not ok then Render3D.gpuError = "shader: " .. tostring(sh) end
  return sharedShader
end

local whiteImage = nil
local function getWhite()
  if whiteImage then return whiteImage end
  local ok, img = pcall(function()
    local d = love.image.newImageData(1, 1)
    d:setPixel(0, 0, 1, 1, 1, 1)
    return love.graphics.newImage(d)
  end)
  whiteImage = ok and img or nil
  return whiteImage
end

function Render3D:releaseGPU()
  if self.gpuMesh and self.gpuMesh.release then pcall(self.gpuMesh.release, self.gpuMesh) end
  self.gpuMesh = nil
  self.gpuRev = nil
  self.gpuCapacity = nil
end

-- Build the static mesh.  Once per scene change, not once per frame.
function Render3D:buildGPU()
  local quads = self.quads
  local n = #quads
  if n == 0 then self:releaseGPU() self.gpuRev = self.rev return false end

  local verts = self.gpuVerts or {}
  self.gpuVerts = verts
  local vi = 0
  local TRI = { 1, 2, 3, 1, 3, 4 }
  for qi = 1, n do
    local q = quads[qi]
    local sh = math.max(0, math.min(1, q.shade or 1))
    local uv = q.uv
    for t = 1, 6 do
      local k = TRI[t]
      local p = q[k]
      vi = vi + 1
      local v = verts[vi]
      if not v then v = {} verts[vi] = v end
      v[1] = p[1]; v[2] = p[2]; v[3] = p[3]
      local uk = uv and uv[k]
      v[4] = uk and uk[1] or 0
      v[5] = uk and uk[2] or 0
      v[6] = sh; v[7] = sh; v[8] = sh; v[9] = 1
    end
  end
  for k = #verts, vi + 1, -1 do verts[k] = nil end

  -- GROW, DO NOT REALLOCATE.  A new Mesh is a new GPU buffer, and building a
  -- whole map hands one over every time the wipe advances.  The buffer is
  -- kept and over-written instead, with the draw range naming how much of it
  -- is real -- otherwise the tail of the last, larger scene is still in there
  -- and gets drawn.
  if not self.gpuMesh or (self.gpuCapacity or 0) < vi then
    local want = math.max(vi * 1.4, 6144)
    local ok, mesh = pcall(love.graphics.newMesh, VERTEX_FORMAT,
                           math.floor(want), "triangles", "dynamic")
    if not ok then
      Render3D.gpuError = "mesh: " .. tostring(mesh)
      self:releaseGPU()
      return false
    end
    self:releaseGPU()
    self.gpuMesh = mesh
    self.gpuCapacity = math.floor(want)
  end
  local okSet = pcall(function()
    self.gpuMesh:setVertices(verts, 1)
    self.gpuMesh:setDrawRange(1, vi)
  end)
  if not okSet then
    Render3D.gpuError = "setVertices failed"
    self:releaseGPU()
    return false
  end
  self.gpuCount = vi
  self.gpuRev = self.rev
  return true
end

-- The canvas the 3D pass draws into.  It needs a DEPTH buffer, which the
-- backbuffer may or may not have, and which a canvas can always be given.
function Render3D:ensureTargets(w, h)
  w, h = math.max(1, math.floor(w)), math.max(1, math.floor(h))
  if self.cw == w and self.ch == h and self.colorCanvas then return true end
  local ok, a, b = pcall(function()
    local c = love.graphics.newCanvas(w, h)
    local d = love.graphics.newCanvas(w, h, { format = "depth24",
                                              readable = false })
    return c, d
  end)
  if not (ok and a and b) then
    Render3D.gpuError = "canvas: " .. tostring(a)
    return false
  end
  self.colorCanvas, self.depthCanvas = a, b
  self.cw, self.ch = w, h
  return true
end

function Render3D:drawGPU(image, x, y, w, h, cam, opts)
  local shader = getShader()
  if not shader then return nil end
  if not self:ensureTargets(w, h) then return nil end
  if self.gpuRev ~= self.rev then
    if not self:buildGPU() then return nil end
  end
  if not self.gpuMesh then return 0 end

  local proj = perspective(cam.fov, w / h, 0.5, 4096)
  local mvp = matMul(proj, lookAt(cam))

  -- THE SCISSOR HAD TO GO FIRST, and this is the crop.
  --
  -- The viewport sets a scissor in SCREEN coordinates so its contents cannot
  -- spill into the docks.  Switching render target does not clear it -- so
  -- the rectangle meant for the screen was still clipping while drawing into
  -- a canvas whose own origin is (0,0), cutting everything left of and above
  -- the viewport's own position out of the canvas, and then blitting what
  -- survived at an offset.  That is the shifted, cropped world, exactly.
  local prevCanvas = love.graphics.getCanvas()
  local sx, sy, sw, sh = love.graphics.getScissor()
  local okDraw = pcall(function()
    love.graphics.setCanvas({ self.colorCanvas, depthstencil = self.depthCanvas })
    love.graphics.setScissor()
    -- TRANSPARENT, not the background colour: the floor grid and the 2D
    -- reference plane are drawn to the screen BEFORE this pass, and an
    -- opaque canvas blitted over them would erase both.
    love.graphics.clear(0, 0, 0, 0, true, true)
    love.graphics.setDepthMode("less", true)
    love.graphics.setShader(shader)
    shader:send("u_mvp", "column", mvp)
    self.gpuMesh:setTexture(image or getWhite())
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.gpuMesh, 0, 0)
    love.graphics.setShader()
    love.graphics.setDepthMode()
    love.graphics.setCanvas(prevCanvas)
  end)
  -- put it back whatever happened, or the next panel draws unclipped
  if sx then love.graphics.setScissor(sx, sy, sw, sh)
  else love.graphics.setScissor() end
  if not okDraw then
    pcall(love.graphics.setShader)
    pcall(love.graphics.setDepthMode)
    pcall(love.graphics.setCanvas, prevCanvas)
    Render3D.gpuError = "draw failed"
    return nil
  end

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(self.colorCanvas, x, y)
  self.lastMode = "gpu"
  -- the projection the pickers need, without projecting anything: they build
  -- their own rays from the camera
  self.lastCam = { cam = cam, x = x, y = y, w = w, h = h }
  return math.floor(self.gpuCount / 6)
end

function Render3D:draw(image, x, y, w, h, cam, opts)
  opts = opts or {}
  self.lastCam = { cam = cam, x = x, y = y, w = w, h = h }

  -- GPU FIRST.  The CPU path is the fallback, not the plan.
  if Render3D.useGPU ~= false and not self.gpuBroken and not self.forceCPU then
    local n = self:drawGPU(image, x, y, w, h, cam, opts)
    if n then
      if opts.wireframe then
        -- the wireframe still needs screen-space corners, so it pays for a
        -- projection -- which is why it is a toggle and not always on
        self:projectAll(x, y, w, h, cam)
        self:drawWire()
      end
      return n
    end
    self.gpuBroken = true
  end

  return self:drawCPU(image, x, y, w, h, cam, opts)
end

-- Project every corner into `px/py/pz` without drawing.  Used by the
-- wireframe and by box select, both of which are occasional.
function Render3D:projectAll(x, y, w, h, cam)
  local quads = self.quads
  local f, r, u = basis(cam)
  local ex, ey, ez = cam.eye[1], cam.eye[2], cam.eye[3]
  local scale = (h / 2) / math.tan(cam.fov / 2)
  local cx, cy = x + w / 2, y + h / 2
  local px, py, pz = self.px or {}, self.py or {}, self.pz or {}
  self.px, self.py, self.pz = px, py, pz
  local sorted = self.sorted or {}
  self.sorted = sorted
  local n = 0
  for qi = 1, #quads do
    local q = quads[qi]
    local base = (qi - 1) * 4
    local ok = true
    for k = 1, 4 do
      local p = q[k]
      local dx, dy, dz = p[1] - ex, p[2] - ey, p[3] - ez
      local vz = dx * f[1] + dy * f[2] + dz * f[3]
      if vz < 0.5 then ok = false break end
      px[base + k] = cx + ((dx * r[1] + dy * r[2] + dz * r[3]) / vz) * scale
      py[base + k] = cy - ((dx * u[1] + dy * u[2] + dz * u[3]) / vz) * scale
      pz[base + k] = vz
    end
    if ok then n = n + 1 sorted[n] = qi end
  end
  self.lastProj = { px = px, py = py, pz = pz, sorted = sorted, count = n,
                    scale = scale, quads = quads }
  return n
end

function Render3D:drawCPU(image, x, y, w, h, cam, opts)
  opts = opts or {}
  local quads = self.quads
  if #quads == 0 then self.lastProj = nil return 0 end

  local f, r, u = basis(cam)
  local ex, ey, ez = cam.eye[1], cam.eye[2], cam.eye[3]
  local half = math.tan(cam.fov / 2)
  local scale = (h / 2) / half
  local cx, cy = x + w / 2, y + h / 2
  local near = 0.5

  -- NOTHING CHANGED means nothing to recompute.  Orbiting is the only time
  -- the projection actually moves; the rest of the time the reader is
  -- looking at a still picture, and redrawing a still picture from scratch
  -- sixty times a second is the difference between a tool that feels alive
  -- and one that feels stuck.
  self.lastMode = "cpu"
  local sig = ("%d|%.3f|%.3f|%.3f|%.3f|%.3f|%.3f|%.4f|%d|%d|%d|%d|%s")
      :format(self.rev or 0, ex, ey, ez, cam.target[1], cam.target[2],
              cam.target[3], cam.fov, x, y, w, h,
              tostring(opts.wireframe) .. tostring(image ~= nil))
  if sig == self.lastSig and self.mesh and self.lastCount and self.lastCount > 0 then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.mesh, 0, 0)
    if opts.wireframe then self:drawWire() end
    return self.lastVisible or 0
  end

  local px, py, pz = self.px or {}, self.py or {}, self.pz or {}
  self.px, self.py, self.pz = px, py, pz
  local ord, dep = self.ord or {}, self.dep or {}
  self.ord, self.dep = ord, dep

  local visible = 0
  local minD, maxD = math.huge, -math.huge
  local vx0, vy0, vx1, vy1 = x, y, x + w, y + h

  for qi = 1, #quads do
    local q = quads[qi]
    local ok = true
    local depth = 0
    local base = (qi - 1) * 4
    local sx0, sy0, sx1, sy1 = math.huge, math.huge, -math.huge, -math.huge
    for k = 1, 4 do
      local p = q[k]
      local dx, dy, dz = p[1] - ex, p[2] - ey, p[3] - ez
      local vz = dx * f[1] + dy * f[2] + dz * f[3]
      if vz < near then ok = false break end
      local vxx = dx * r[1] + dy * r[2] + dz * r[3]
      local vyy = dx * u[1] + dy * u[2] + dz * u[3]
      local sx = cx + (vxx / vz) * scale
      local sy = cy - (vyy / vz) * scale
      px[base + k] = sx
      py[base + k] = sy
      pz[base + k] = vz
      if sx < sx0 then sx0 = sx end
      if sx > sx1 then sx1 = sx end
      if sy < sy0 then sy0 = sy end
      if sy > sy1 then sy1 = sy end
      depth = depth + vz
    end
    -- OFF-SCREEN IS NOT DRAWN.  A map window is meshed a good way past the
    -- edge of the view and most of it lands outside; carrying those quads
    -- through the sort and into the vertex buffer costs exactly as much as
    -- drawing them and shows nothing.
    if ok and (sx1 < vx0 or sx0 > vx1 or sy1 < vy0 or sy0 > vy1) then
      ok = false
    end
    if ok then
      visible = visible + 1
      ord[visible] = qi
      depth = depth * 0.25
      dep[visible] = depth
      if depth < minD then minD = depth end
      if depth > maxD then maxD = depth end
    end
  end
  if visible == 0 then
    self.lastProj = nil
    self.lastSig = nil
    self.lastCount = 0
    return 0
  end

  -- bucket far-to-near
  local span = maxD - minD
  local scaleB = (span > 1e-6) and ((BUCKETS - 1) / span) or 0
  local heads = self.heads or {}
  local nextI = self.nextI or {}
  self.heads, self.nextI = heads, nextI
  for b = 0, BUCKETS - 1 do heads[b] = 0 end
  for i = 1, visible do
    local b = BUCKETS - 1 - math.floor((dep[i] - minD) * scaleB)
    if b < 0 then b = 0 elseif b > BUCKETS - 1 then b = BUCKETS - 1 end
    nextI[i] = heads[b]
    heads[b] = i
  end

  local verts = self.verts
  local vi = 0
  local sorted = self.sorted or {}
  self.sorted = sorted
  local sn = 0
  local TRI = self.tri
  if not TRI then TRI = { 1, 2, 3, 1, 3, 4 } self.tri = TRI end

  for b = 0, BUCKETS - 1 do
    local i = heads[b]
    while i ~= 0 do
      local qi = ord[i]
      sn = sn + 1
      sorted[sn] = qi
      local q = quads[qi]
      local base = (qi - 1) * 4
      local sh = q.shade or 1
      local uv = q.uv
      for t = 1, 6 do
        local k = TRI[t]
        vi = vi + 1
        local v = verts[vi]
        if not v then v = {} verts[vi] = v end
        v[1] = px[base + k]
        v[2] = py[base + k]
        local uk = uv and uv[k]
        v[3] = uk and uk[1] or 0
        v[4] = uk and uk[2] or 0
        v[5] = sh; v[6] = sh; v[7] = sh; v[8] = 1
      end
      i = nextI[i]
    end
  end

  if vi > 0 then
    if not self.mesh or self.capacity < vi then
      -- grow in big steps: reallocating a mesh is a GPU buffer allocation
      -- and doing it a few vertices at a time is its own kind of slow
      self.capacity = math.max(vi * 2, 4096)
      self.mesh = love.graphics.newMesh(self.capacity, "triangles", "stream")
    end
    -- UPLOAD AND DRAW EXACTLY THE LIVE VERTICES.
    --
    -- The buffer is bigger than the frame needs, and the old code answered
    -- that by zero-filling the spare capacity and uploading all of it -- two
    -- extra passes over a quarter-million-quad buffer every frame, to draw
    -- degenerate triangles at the origin.  A draw range says the same thing
    -- and costs nothing: whatever stale vertices sit past `vi` are simply
    -- never drawn.
    for k = #verts, vi + 1, -1 do verts[k] = nil end
    self.mesh:setVertices(verts, 1)
    self.mesh:setDrawRange(1, vi)
    if image then self.mesh:setTexture(image) else self.mesh:setTexture() end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.mesh, 0, 0)
  end

  self.lastProj = { px = px, py = py, pz = pz, sorted = sorted, count = sn,
                    scale = scale, quads = quads }
  self.lastSig = sig
  self.lastCount = vi
  self.lastVisible = visible
  self.sortedCount = sn

  if opts.wireframe then self:drawWire() end
  return visible
end

function Render3D:drawWire()
  local pr = self.lastProj
  if not pr then return end
  love.graphics.setLineWidth(1)
  love.graphics.setColor(0.35, 0.85, 1, 0.45)
  local px, py = pr.px, pr.py
  for i = 1, pr.count do
    local base = (pr.sorted[i] - 1) * 4
    love.graphics.polygon("line",
      px[base + 1], py[base + 1], px[base + 2], py[base + 2],
      px[base + 3], py[base + 3], px[base + 4], py[base + 4])
  end
end

-- ------------------------------------------------------------------ rays

-- The world-space ray under the cursor.
--
-- PICKING BY RAY RATHER THAN BY GEOMETRY is the change that lets the GPU own
-- the projection.  The old picker walked every quad's screen polygon, which
-- meant the CPU had to have projected them all -- the very work the shader
-- was brought in to stop doing.  A ray needs the camera and nothing else, and
-- what it is tested against is the height field, which is a lookup per step
-- rather than a polygon test per quad.
function Render3D:ray(mx, my)
  local lc = self.lastCam
  if not lc then return nil end
  local cam, x, y, w, h = lc.cam, lc.x, lc.y, lc.w, lc.h
  local f, r, u = basis(cam)
  local scale = (h / 2) / math.tan(cam.fov / 2)
  local sx = (mx - (x + w / 2)) / scale
  local sy = -(my - (y + h / 2)) / scale
  local d = normalise({
    f[1] + r[1] * sx + u[1] * sy,
    f[2] + r[2] * sx + u[2] * sy,
    f[3] + r[3] * sx + u[3] * sy,
  })
  return { cam.eye[1], cam.eye[2], cam.eye[3] }, d
end

-- ---------------------------------------------------------------- picking

local function pointInQuad(mx, my, px, py, base)
  -- two triangles, same split the renderer uses
  local function tri(a, b, c)
    local x1, y1 = px[base + a], py[base + a]
    local x2, y2 = px[base + b], py[base + b]
    local x3, y3 = px[base + c], py[base + c]
    local d = (y2 - y3) * (x1 - x3) + (x3 - x2) * (y1 - y3)
    if math.abs(d) < 1e-9 then return false end
    local l1 = ((y2 - y3) * (mx - x3) + (x3 - x2) * (my - y3)) / d
    local l2 = ((y3 - y1) * (mx - x3) + (x1 - x3) * (my - y3)) / d
    local l3 = 1 - l1 - l2
    return l1 >= 0 and l2 >= 0 and l3 >= 0
  end
  return tri(1, 2, 3) or tri(1, 3, 4)
end

-- The nearest quad under the cursor, from the last frame's projection.
-- Walked from the NEAR end of the painter's order, because the last thing
-- drawn is the thing you are looking at.
function Render3D:pickAt(mx, my)
  local pr = self.lastProj
  if not pr then return nil end
  for oi = pr.count, 1, -1 do
    local qi = pr.sorted[oi]
    local base = (qi - 1) * 4
    if pointInQuad(mx, my, pr.px, pr.py, base) then
      local q = pr.quads[qi]
      local depth = (pr.pz[base + 1] + pr.pz[base + 2]
                   + pr.pz[base + 3] + pr.pz[base + 4]) / 4
      return q, depth, pr.scale
    end
  end
  return nil
end

-- How many world units one screen pixel is worth at a given view depth.
-- This is what turns a vertical drag into a height in world pixels, and it
-- has to follow the depth or dragging near the camera moves a column ten
-- times as far as dragging at the back of the scene.
-- How many world units one screen pixel is worth at a given view depth.
-- Taken from the CAMERA, not from a stored projection: with the GPU path
-- there may not have been a CPU projection this frame, and a drag must not
-- change speed depending on which renderer is running.
function Render3D:worldPerPixel(depth)
  local lc = self.lastCam
  if not (lc and depth) then return 0.25 end
  local scale = (lc.h / 2) / math.tan(lc.cam.fov / 2)
  if scale <= 0 then return 0.25 end
  return depth / scale
end

-- Project one world point with the last frame's camera, for drawing handles.
function Render3D:projectWith(cam, x, y, w, h, wx, wy, wz)
  local f, r, u = basis(cam)
  local ex, ey, ez = cam.eye[1], cam.eye[2], cam.eye[3]
  local half = math.tan(cam.fov / 2)
  local scale = (h / 2) / half
  local cx, cy = x + w / 2, y + h / 2
  local dx, dy, dz = wx - ex, wy - ey, wz - ez
  local vz = dx * f[1] + dy * f[2] + dz * f[3]
  if vz < 0.5 then return nil end
  local vx = dx * r[1] + dy * r[2] + dz * r[3]
  local vy = dx * u[1] + dy * u[2] + dz * u[3]
  return cx + (vx / vz) * scale, cy - (vy / vz) * scale, vz
end

-- The floor grid over an arbitrary world rectangle: one line per world
-- pixel, brighter every 8 (a tile) and brighter again every 16 (a cell), so
-- a height read off the preview can be counted rather than guessed.  Lines
-- are skipped as they get dense, because at map zoom a line per pixel is a
-- grey wash and costs thousands of draw calls to produce it.
function Render3D:drawFloor(x, y, w, h, cam, wx0, wz0, ww, wh)
  local function proj(px, py, pz)
    return self:projectWith(cam, x, y, w, h, px, py, pz)
  end
  -- how many world pixels one screen pixel covers, roughly, at the centre
  local a = select(1, proj(wx0, 0, wz0))
  local b = select(1, proj(wx0 + 8, 0, wz0))
  local stride = 1
  if a and b then
    local px = math.abs(b - a) / 8
    if px < 0.12 then stride = 16 elseif px < 0.4 then stride = 8
    elseif px < 1.2 then stride = 4 end
  else
    stride = 8
  end

  love.graphics.setLineWidth(1)
  for i = 0, ww, stride do
    local a2 = (i % 16 == 0) and 0.26 or ((i % 8 == 0) and 0.14 or 0.05)
    love.graphics.setColor(1, 1, 1, a2)
    local x1, y1 = proj(wx0 + i, 0, wz0)
    local x2, y2 = proj(wx0 + i, 0, wz0 + wh)
    if x1 and x2 then love.graphics.line(x1, y1, x2, y2) end
  end
  for j = 0, wh, stride do
    local a2 = (j % 16 == 0) and 0.26 or ((j % 8 == 0) and 0.14 or 0.05)
    love.graphics.setColor(1, 1, 1, a2)
    local x1, y1 = proj(wx0, 0, wz0 + j)
    local x2, y2 = proj(wx0 + ww, 0, wz0 + j)
    if x1 and x2 then love.graphics.line(x1, y1, x2, y2) end
  end
end

return Render3D
