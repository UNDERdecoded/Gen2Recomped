-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Gen 4 geometry, in the shape the engine can actually load.
--
-- `Gen4Nsbmd` produces a model as Lua tables -- one table per vertex, one per
-- triangle.  That is the right shape to CHECK (it is what the corpus test
-- reads) and the wrong shape to ship: the briefcase alone is 2,430 vertex
-- tables and 1,644 triangle tables, and written as Lua source that is a
-- megabyte of `{ x = ..., y = ... }` for one model out of six.
--
-- So a packed model is two BINARY STRINGS, which is the same trick the map
-- grids already use (`def.blocks` is a 2 KB string, not 1,024 tables).
--
-- THE PRECISION IS THE CARTRIDGE'S OWN, which is what makes this lossless
-- rather than a compromise.  A Gen 4 coordinate is fx16 -- a signed 16-bit
-- number over 4096 -- so storing the raw fixed-point value keeps every
-- position exactly as the display list gave it.  Texture coordinates are in
-- sixteenths of a texel and are likewise integers already.  Nothing here
-- rounds anything that was not already round.
--
--   vertex  16 bytes  x, y, z, u, v as s16; r, g, b as u8; nx, ny, nz as s8
--   index    2 bytes  u16 into this shape's own vertex array
--   matrixSlots: optional byte per vertex preserving display-list joint restores
--
-- THE NORMAL IS NOT OPTIONAL, AND LEAVING IT OUT COST THE WHOLE OF SINNOH'S
-- LIGHTING.
--
-- This used to be fourteen bytes with a pad byte on the end, and the pad was
-- justified as making a vertex an even number of bytes.  It still is even; it
-- now carries the three axes of the normal instead of nothing, and that is the
-- difference between a lit world and a flat one.
--
-- Platinum's map display lists issue NORMAL (0x21) and NOT COLOR (0x20),
-- because the DS's geometry engine computes each vertex's colour in hardware
-- from the normal and the area light.  `Gen4Nsbmd` decodes those normals
-- correctly and puts them on every vertex table.  THIS FILE THEN THREW THEM
-- AWAY, one step before the only consumer that wants them -- so every vertex
-- in the cache kept the decoder's white default and every polygon in Sinnoh
-- drew at full brightness with no directional term.  Measured over Route 201's
-- chunk 5, Twinleaf's chunk 0 and the `t1_h01` house: 4,794 vertices, ONE
-- distinct colour between them, 255,255,255.
--
-- The normal is stored as three signed bytes rather than the cartridge's
-- 10 bits per axis.  That is 1/127 of precision on a unit vector, which is
-- four times coarser than the source and about two hundred times finer than
-- anything a diffuse term does with it; it keeps the vertex even, and it keeps
-- the side-car under 21 MB.
--
-- IT IS NOT BAKED INTO THE COLOUR HERE, deliberately.  The light is per MAP
-- and the geometry is SHARED -- one buildings set of 590 models serves every
-- town, and one terrain chunk is drawn by every map that reaches it (Route
-- 201's own log shows chunk 5 baked by six ground instances at once).  Baking
-- one map's light into shared geometry gives every other reader the wrong one,
-- so the normal travels and `src/render/Gen4Shade.lua` lights it where the map
-- -- and therefore the member and the time band -- is known.

local Gen4ModelPack = {}

Gen4ModelPack.VERTEX_BYTES = 16
Gen4ModelPack.INDEX_BYTES = 2
Gen4ModelPack.FX16 = 4096
-- Texture coordinates arrive in sixteenths of a texel; they are stored that
-- way and divided by the texture's size where the size is known.
Gen4ModelPack.UV_UNITS = 16

local floor, char, concat = math.floor, string.char, table.concat
local abs = math.abs

-- A signed 16-bit value, little endian, clamped rather than wrapped.
--
-- Clamped because a wrap is silent and a clamp is visible: a coordinate that
-- genuinely exceeded the range would put one vertex on the far side of the
-- model, which is noticeable, where a wrap would put it somewhere arbitrary
-- and plausible.  Nothing in this cartridge comes close -- the largest
-- bounding box is under five units -- so this never fires; it is here so that
-- if it ever does, it does so where someone can see it.
local function s16(value)
  value = floor(value + 0.5)
  if value > 32767 then value = 32767 end
  if value < -32768 then value = -32768 end
  if value < 0 then value = value + 65536 end
  return char(value % 256, floor(value / 256))
end

local function u16(value)
  value = floor(value + 0.5)
  if value < 0 then value = 0 end
  if value > 65535 then value = 65535 end
  return char(value % 256, floor(value / 256))
end

-- A unit-vector axis as one signed byte, two's complement.
--
-- Clamped to +-127 rather than +-128 so that decoding is a plain divide by 127
-- and +1 and -1 are exactly representable; an asymmetric range would make one
-- of the two ends land a step short and put a systematic tilt on every normal
-- that points along it.
local function s8(value)
  local v = tonumber(value) or 0
  -- ROUND HALF AWAY FROM ZERO, and do it through the magnitude.
  --
  -- The obvious spelling -- `floor(v * 127 - 0.5)` on the negative branch --
  -- is wrong, and wrong by a whole step rather than a rounding hair:
  -- `floor(-72.001)` is -73, not -72, so subtracting the half before flooring
  -- pushes every negative axis one further out.  A probe over 2,001 values
  -- reported a worst round-trip error of 0.0118 against a half-step of
  -- 0.0039 -- three times the format's own precision, on half the normals in
  -- the cartridge.
  local n = floor(abs(v) * 127 + 0.5)
  if v < 0 then n = -n end
  v = n
  if v > 127 then v = 127 end
  if v < -127 then v = -127 end
  if v < 0 then v = v + 256 end
  return char(v)
end

local function u8(value)
  value = floor(value * 255 + 0.5)
  if value < 0 then value = 0 end
  if value > 255 then value = 255 end
  return char(value)
end

-- pack(model) -> { shapes = { { vertices, indices, count, triangles, ... } } }
--
-- One packed entry per shape rather than one per model, because a shape is
-- the unit a renderer draws: it has one material, therefore one texture, and
-- therefore one draw call.  Merging them would mean carrying a per-triangle
-- material id and splitting it again at draw time.
function Gen4ModelPack.pack(model)
  local out = {
    name = model.name,
    posScale = model.posScale,
    scalingRule = model.scalingRule,
    bounds = model.bounds,
    shapes = {},
    -- WHERE EACH SHAPE STANDS, carried rather than baked.
    --
    -- A shape's vertices are in its node's space, and on the briefcase the
    -- nodes are the only record of where the three Poke Balls are.  Baking
    -- each node's transform into its vertices here would be simpler and would
    -- throw away exactly the thing an animation replaces: the same walk over
    -- the same bytecode, with a joint animation's frame instead of the model's
    -- own node, is what makes the case open.
    nodes = {},
    ops = model.pose,
    inverseBind = model.inverseBind,
  }

  for _, bone in ipairs(model.bones or {}) do
    out.nodes[#out.nodes + 1] = { name = bone.name, matrix = bone.matrix }
  end

  for _, shape in ipairs(model.shapes) do
    local material = model.materials[(shape.material or 0) + 1]
    local vertexParts, indexParts, matrixParts = {}, {}, {}
    local hasMatrices=false

    for _, v in ipairs(shape.vertices) do
      matrixParts[#matrixParts+1]=char(v.matrix==nil and 255 or v.matrix)
      if v.matrix~=nil then hasMatrices=true end
      vertexParts[#vertexParts + 1] =
        s16(v.x * Gen4ModelPack.FX16) ..
        s16(v.y * Gen4ModelPack.FX16) ..
        s16(v.z * Gen4ModelPack.FX16) ..
        s16(v.u * Gen4ModelPack.UV_UNITS) ..
        s16(v.v * Gen4ModelPack.UV_UNITS) ..
        u8(v.r) .. u8(v.g) .. u8(v.b) ..
        s8(v.nx) .. s8(v.ny) .. s8(v.nz)
    end

    for _, t in ipairs(shape.triangles) do
      -- ONE-BASED IN, ZERO-BASED OUT.  Gen4Nsbmd indexes its own Lua array, so
      -- its first vertex is 1; a mesh index buffer counts from 0 everywhere
      -- else in the world.  Converting here rather than at draw time means the
      -- renderer never has to know which convention it is holding.
      indexParts[#indexParts + 1] =
        u16(t[1] - 1) .. u16(t[2] - 1) .. u16(t[3] - 1)
    end

    out.shapes[#out.shapes + 1] = {
      name = shape.name,
      -- Its own index, because the pose is keyed by the number the bytecode
      -- uses rather than by position in this list.
      index = shape.index,
      vertices = concat(vertexParts),
      matrixSlots = hasMatrices and concat(matrixParts) or nil,
      indices = concat(indexParts),
      vertexCount = #shape.vertices,
      triangleCount = #shape.triangles,
      material = material and material.name or nil,
      texture = material and material.texture or nil,
      palette = material and material.palette or nil,
      -- The material's polygon alpha, 0..31, and only when it is not fully
      -- opaque -- 31 is the overwhelming majority and writing it on every
      -- shape would grow the cache for a value the renderer already defaults
      -- to.  A shadow polygon is 9.
      alpha = (material and material.alpha and material.alpha < 31)
              and material.alpha or nil,
      -- HOW THE TEXTURE MEETS ITS EDGES, from the material's texture
      -- parameter: bits 16 / 17 repeat S / T, 18 / 19 mirror them, and
      -- neither is CLAMP. Only when it is not plain repeat, which is what the
      -- renderer assumes. HGSS's starter balls show why it matters: their
      -- highlight, `tt_bl_hl2`, is one small spot with parameter 0 -- clamped
      -- -- and repeated it tiled the whole ball in white dots.
      wrap = Gen4ModelPack.wrapOf(material),
      -- NO NORMALS, NO LIGHTING: the DS computes a lit colour only from the
      -- NORMAL command, and a shape whose display list never issued one
      -- (HeartGold / SoulSilver's lightmapped `_lm` geometry, which issues
      -- COLOR) shows its baked vertex colours as they are. Shaded with the
      -- decoder's resting normal, Falkner's gym came out at a third of its
      -- brightness. Platinum's terrain issues NORMAL and is unaffected.
      unlit = Gen4ModelPack.hasNoNormals(shape) or nil,
      -- OUT OF THE FOG: polyAttr bit 15 is the DS's per-material fog enable.
      -- Written only when it is CLEAR, which is rare -- Morty's gym fogs the
      -- whole room to black and its candle spots (`dun_spot`) shine through.
      noFog = (material and material.polyAttr
               and math.floor(material.polyAttr / 0x8000) % 2 == 0) or nil,
      -- WHICH LIGHTS REACH IT: polyAttr bits 0..3 (the four GX lights). The
      -- area light's templates set the lights and the colours globally and
      -- leave this to the material (AreaLight_UseGlobalModelAttributes; and
      -- map_prop.c ApplyToModel passes no MODEL_LIGHT_ENABLE_FLAGS), so the
      -- night is however dark its own lights make it (Gen4Shade)
      lights = (material and material.polyAttr) and (material.polyAttr % 16) or nil,
    }
  end

  return out
end

-- hasNoNormals(shape) -> true when no vertex of it was given a NORMAL
function Gen4ModelPack.hasNoNormals(shape)
  local vs = shape and shape.vertices
  if type(vs) ~= "table" or #vs == 0 then return false end
  for _, v in ipairs(vs) do
    if not v.noNormal then return false end
  end
  return true
end

-- wrapOf(material) -> { s, t } in LOVE's words, or nil for repeat / repeat
function Gen4ModelPack.wrapOf(material)
  local p = material and material.texImageParam
  if not p then return nil end
  local function axis(repeatBit, mirrorBit)
    local rep = math.floor(p / 2 ^ repeatBit) % 2 == 1
    local mir = math.floor(p / 2 ^ mirrorBit) % 2 == 1
    if not rep then return "clamp" end
    return mir and "mirroredrepeat" or "repeat"
  end
  local ws, wt = axis(16, 18), axis(17, 19)
  if ws == "repeat" and wt == "repeat" then return nil end
  return { ws, wt }
end

-- unpack(packed) -> vertices, triangles
--
-- The inverse, and it exists to be RUN rather than to be used: the extractor
-- packs a model and then unpacks it again, and the two have to agree on every
-- coordinate.  A packer that drops a field, swaps two, or mis-signs a
-- negative produces a model that still draws -- inside out, or with one wall
-- missing -- which is the failure mode this whole file has been built to make
-- impossible to reach quietly.
function Gen4ModelPack.unpack(shape)
  local vertices, triangles = {}, {}
  local data = shape.vertices
  local stride = Gen4ModelPack.VERTEX_BYTES

  local function s16At(at)
    local a, b = data:byte(at + 1, at + 2)
    if not b then return nil end
    local value = a + b * 256
    if value >= 32768 then value = value - 65536 end
    return value
  end

  local function s8At(at)
    local byte = data:byte(at + 1)
    if not byte then return nil end
    if byte >= 128 then byte = byte - 256 end
    return byte / 127
  end

  for i = 0, shape.vertexCount - 1 do
    local at = i * stride
    local r, g, b = data:byte(at + 11, at + 13)
    vertices[i + 1] = {
      x = s16At(at) / Gen4ModelPack.FX16,
      y = s16At(at + 2) / Gen4ModelPack.FX16,
      z = s16At(at + 4) / Gen4ModelPack.FX16,
      u = s16At(at + 6) / Gen4ModelPack.UV_UNITS,
      v = s16At(at + 8) / Gen4ModelPack.UV_UNITS,
      r = (r or 255) / 255, g = (g or 255) / 255, b = (b or 255) / 255,
      nx = s8At(at + 13), ny = s8At(at + 14), nz = s8At(at + 15),
      matrix = shape.matrixSlots and shape.matrixSlots:byte(i+1) or nil,
    }
    if vertices[i+1].matrix==255 then vertices[i+1].matrix=nil end
  end

  local index = shape.indices
  for i = 0, shape.triangleCount - 1 do
    local at = i * 6
    local a, b, c, d, e, f = index:byte(at + 1, at + 6)
    triangles[i + 1] = { a + b * 256 + 1, c + d * 256 + 1, e + f * 256 + 1 }
  end

  return vertices, triangles
end

-- verify(model, packed) -> ok, complaint
--
-- Round-trip every shape and require the unpacked geometry to match what went
-- in, to the precision the format holds.  The tolerance is half a fixed-point
-- step, because that is the only rounding this does; anything bigger is a bug
-- rather than a representation.
-- One signed byte holds a unit axis to 1/127, so half a step is the most a
-- correct round trip can move it.  Written out rather than folded into the
-- position tolerance because the two formats are different and a shared number
-- would be the loosest of the pair.
local NORMAL_TOLERANCE = 0.5 / 127 + 1e-9

function Gen4ModelPack.verify(model, packed)
  local tolerance = 0.5 / Gen4ModelPack.FX16
  for i, shape in ipairs(model.shapes) do
    local out = packed.shapes[i]
    if not out then return false, ("shape %d is missing"):format(i) end
    if out.vertexCount ~= #shape.vertices then
      return false, ("shape %q: %d vertices packed, %d in")
        :format(shape.name, out.vertexCount, #shape.vertices)
    end
    local vertices, triangles = Gen4ModelPack.unpack(out)
    for k, v in ipairs(shape.vertices) do
      local w = vertices[k]
      if not w then return false, ("shape %q vertex %d lost"):format(shape.name, k) end
      if v.matrix~=w.matrix then return false,'vertex matrix slot lost' end
      for _, axis in ipairs({ "x", "y", "z" }) do
        if math.abs(v[axis] - w[axis]) > tolerance then
          return false, ("shape %q vertex %d %s: %f in, %f out")
            :format(shape.name, k, axis, v[axis], w[axis])
        end
      end
      -- THE NORMAL ROUND-TRIPS TOO, at the precision one signed byte holds.
      -- Checked for the reason the positions are: a packer that dropped this
      -- field is exactly what this format change exists to undo, and a
      -- round-trip that does not look at it would not have noticed the first
      -- time either.
      for _, axis in ipairs({ "nx", "ny", "nz" }) do
        local inValue = tonumber(v[axis]) or 0
        local outValue = w[axis]
        if outValue == nil then
          return false, ("shape %q vertex %d %s was not packed")
            :format(shape.name, k, axis)
        end
        if math.abs(inValue - outValue) > NORMAL_TOLERANCE then
          return false, ("shape %q vertex %d %s: %f in, %f out")
            :format(shape.name, k, axis, inValue, outValue)
        end
      end
    end
    for k, t in ipairs(shape.triangles) do
      local u = triangles[k]
      if not u or u[1] ~= t[1] or u[2] ~= t[2] or u[3] ~= t[3] then
        return false, ("shape %q triangle %d changed"):format(shape.name, k)
      end
    end
  end
  return true
end

return Gen4ModelPack
