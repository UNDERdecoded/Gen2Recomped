-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- SINNOH'S GROUND, in the shape the engine can draw it.
--
-- Platinum has no tileset.  Its world is 666 land chunks, each 32 x 32 tiles
-- of 16 world units -- a 512-unit square -- carrying an NSBMD mesh, a BDHC
-- height field and a 2,048-byte permission grid.  A map is a MATRIX of those
-- chunks, and every map in the game is one matrix.
--
-- Until now the engine drew `TILESET_GEN4_STANDIN` over all of it: one flat
-- colour per terrain class, which is a legible plan of a map and is not
-- Sinnoh.  This is the stage that puts the cartridge's own ground in the
-- cache.
--
-- WHAT IS MEASURED RATHER THAN ASSUMED, because every one of these was got
-- wrong once first:
--
--   * A CHUNK'S LOCAL ORIGIN IS ITS CENTRE.  `posScale` is 32 and a chunk's
--     vertices run about -8..+8, so world units are `value * posScale` and the
--     chunk spans -256..+256 of its 512-unit square.  Read as 0..512, seven
--     eighths of the mesh falls off the edge -- 236 triangles of 2,667 landed
--     before this was found, which looks like a broken decoder and is
--     arithmetic.
--   * ALL 666 CHUNKS CARRY BOTH A MESH AND A BDHC.  Neither is optional.
--   * A CHUNK'S MESH CARRIES NO TEXTURES.  It names them; the pictures are in
--     `map_tex_set.narc`, chosen by the MAP's area record, and a chunk shared
--     between two maps is textured by whichever map the player is standing in.
--
-- THE GEOMETRY GOES IN A SIDE-CAR BINARY, not in a Lua table.  Packed, the 666
-- chunks are 17.7 MB; as escaped Lua source that is nearer 50 MB and the cache
-- would take minutes to load.  `CacheFs.write` takes raw bytes -- it is what
-- every PNG already goes through -- so the chunks are one file and the Lua
-- module is an index of offsets into it.

local Gen4Maps = require("src.import.Gen4Maps")
local Gen4Models = require("src.import.Gen4Models")
local Gen4ModelPack = require("src.import.Gen4ModelPack")
local Gen4Nsbmd = require("src.import.Gen4Nsbmd")

local Gen4Terrain = {}

local floor, concat = math.floor, table.concat

-- A chunk is 32 x 32 tiles of 16 units; the square is 512 units on a side and
-- its origin is the middle of it.
Gen4Terrain.CHUNK_TILES = Gen4Maps.CHUNK or 32
Gen4Terrain.TILE_UNITS = Gen4Maps.TERRAIN_TILE_UNITS or 16
Gen4Terrain.CHUNK_UNITS = Gen4Maps.TERRAIN_CHUNK_UNITS or 512

-- One pixel per world unit, so a chunk bakes to a 512 x 512 picture and a tile
-- to 16 x 16 -- the same tile size every other generation in this engine draws
-- at, which is what lets the sprites and the collision grid land on it without
-- a second scale to keep in step.
Gen4Terrain.PIXELS_PER_UNIT = 1

-- ---------------------------------------------------------------------------
-- The chunks
-- ---------------------------------------------------------------------------

-- chunk(landBytes) -> { packed, bdhc, permissions }, or nil plus the reason.
--
-- `packed` is Gen4ModelPack's output: per shape, the vertices and indices as
-- binary strings, and the material's texture and palette NAMES.  The pack is
-- the same one the starter models go through, so the same `verify` applies --
-- and it is run here, on every chunk, because a packer that drops a field
-- produces a mesh that still draws, inside out or with a wall missing.
function Gen4Terrain.chunk(landBytes)
  local land, why = Gen4Maps.land(landBytes)
  if not land then return nil, why end
  if #land.model == 0 then return nil, "this chunk carries no mesh" end

  local set = Gen4Nsbmd.parse(land.model)
  local model = set and set.models and set.models[1]
  if not model then return nil, "the chunk's mesh would not parse" end

  local packed = Gen4ModelPack.pack(model)
  local ok, packWhy = Gen4ModelPack.verify(model, packed)
  if not ok then return nil, "pack round trip: " .. tostring(packWhy) end

  return {
    packed = packed,
    bdhc = land.bdhc,
    permissions = land.permissions,
    shapes = #packed.shapes,
    -- WHERE THE BUILDINGS STAND, which is the chunk's own second block and was
    -- being parsed and thrown away.  `Gen4Maps.objects` has read it since the
    -- map work; nothing carried it into the cache, so the renderer had the
    -- ground and no idea what was on it.
    objects = Gen4Maps.objects(land),
  }
end

-- append(state, chunk) -> the index entry for it.
--
-- `state` accumulates two byte streams -- the geometry and the BDHC blobs --
-- and hands back offsets into them.  Kept as a list of parts and concatenated
-- once at the end, because 666 chunks appended to a growing string is the
-- difference between an import and a hang.
function Gen4Terrain.newBlob()
  return { geometry = {}, geometryAt = 0, heights = {}, heightsAt = 0,
           -- ...AND THE PERMISSIONS, which are the per-tile BEHAVIOUR of the
           -- outdoor world and were parsed and dropped. See `append`.
           perms = {}, permsAt = 0 }
end

function Gen4Terrain.append(state, chunk)
  local entry = { posScale = chunk.packed.posScale, shapes = {} }

  -- The placements ride in the INDEX rather than the blob: there are a handful
  -- per chunk and each is six numbers, so a side-car offset would cost more to
  -- read than the numbers themselves.  Models with no scale recorded are left
  -- without one rather than given 1, so a reader can tell "the cartridge said
  -- one" from "the cartridge said nothing".
  if chunk.objects and #chunk.objects > 0 then
    entry.objects = chunk.objects
  end

  -- WHERE THE CHUNK'S OWN GEOMETRY STANDS, when it does not stand at the
  -- origin.
  --
  -- Reported from play: *"the bike routes building entrance also isnt
  -- rendering properly above oreburg, its putting the npcs and players in a
  -- dark area and the building area is to the right"*.
  --
  -- A chunk model's shapes are drawn through a NODE, exactly like every other
  -- model in this cartridge, and `Gen4ModelPack.pack` has carried `nodes` and
  -- `ops` all along with a comment saying why they must not be baked into the
  -- vertices. This function then wrote neither, so the whole mechanism stopped
  -- here and every chunk was drawn as though its node were the identity.
  --
  -- On 649 of the 666 chunks it IS the identity, which is why this went
  -- unnoticed. The rest carry a real translation: Route 206's gate sits on a
  -- node at (-135.99, 21.45, -133.93), and applying it moves the room from
  -- tiles 8.5..22.5 -- where it was drawn, beside the players standing in the
  -- dark -- onto tiles 0..14, which is exactly where that chunk's own
  -- permission grid puts its walls and where its warps and NPCs already were.
  --
  -- WRITTEN ONLY WHEN IT SAYS SOMETHING. 666 identity matrices would be ~11,000
  -- numbers in a cache file that is already 163,899 lines, to state that
  -- nothing moves. A reader that finds no nodes draws at the origin, which is
  -- what it did before and is right for those chunks.
  local moved = false
  for _, node in ipairs(chunk.packed.nodes or {}) do
    local m = node.matrix
    -- The translation column of a 4x4 held row-major: a node that only ever
    -- rotates or scales still has to be carried, so this tests the WHOLE
    -- matrix against the identity rather than its translation alone.
    if type(m) == "table" then
      for i = 1, 16 do
        local want = (i == 1 or i == 6 or i == 11 or i == 16) and 1 or 0
        if math.abs((m[i] or want) - want) > 1e-6 then moved = true break end
      end
    end
    if moved then break end
  end
  if moved then
    entry.nodes = chunk.packed.nodes
    entry.ops = chunk.packed.ops
  end

  for _, shape in ipairs(chunk.packed.shapes) do
    local vAt = state.geometryAt
    state.geometry[#state.geometry + 1] = shape.vertices
    state.geometryAt = state.geometryAt + #shape.vertices
    local iAt = state.geometryAt
    state.geometry[#state.geometry + 1] = shape.indices
    state.geometryAt = state.geometryAt + #shape.indices

    entry.shapes[#entry.shapes + 1] = {
      name = shape.name,
      vertexAt = vAt, vertexBytes = #shape.vertices, vertexCount = shape.vertexCount,
      indexAt = iAt, indexBytes = #shape.indices, triangleCount = shape.triangleCount,
      texture = shape.texture, palette = shape.palette,
      material = shape.material,
      -- ...AND THE ALPHA THAT MATERIAL STATES, which is the only field of the
      -- pack this index dropped.  `Gen4ModelPack` has computed it since the
      -- house shadows came out black -- polyAttr bits 16..20, kept only when
      -- it is under 31 -- and the value stopped HERE, one line short of the
      -- cache, so every terrain shape in Sinnoh drew fully opaque.
      --
      -- MEASURED FROM THE CARTRIDGE over all 666 chunks, not assumed: 155 of
      -- 7,346 terrain materials state an alpha below 31, across 107 chunks.
      --
      --   sea                13/31 x12, 21/31 x12
      --   water01            13/31        water02   15/31
      --   shadowchip         12/31 x27  -- the ground shadow decals
      --   dun_shadow         10..19/31 x8
      --   wtk_kabe_garasu3   16..20/31  -- `garasu`: a glass window
      --   h_kage etc         3..15/31  x30
      --
      -- `Gen4Model.shapeAlpha` has honoured `shape.alpha` all along, so this
      -- one field is the whole fix on the read side.  It needs a re-import to
      -- take effect: a cache written before today carries no alpha, which is
      -- what the name fallback over there is for.
      alpha = shape.alpha,
    }
  end

  if chunk.bdhc and #chunk.bdhc > 0 then
    entry.heightAt = state.heightsAt
    entry.heightBytes = #chunk.bdhc
    state.heights[#state.heights + 1] = chunk.bdhc
    state.heightsAt = state.heightsAt + #chunk.bdhc
  end

  -- THE PER-TILE BEHAVIOUR OF THE OUTDOOR WORLD, which was parsed and dropped.
  --
  -- Reported from play: *"i cant walk directly into the cave it wont warp me"*.
  -- A Gen 4 door or cave mouth is opened by pressing the direction the tile
  -- under the player NAMES (`PlayerAvatar_WillWarp`, src/player_move.c), and
  -- that name is a behaviour byte. Only 302 of Platinum's 593 map defs carry a
  -- behaviour grid of their own; the other 291 -- which is every outdoor map,
  -- and so every cave mouth in Sinnoh -- keep theirs in the land chunk's
  -- PERMISSION block, one u16 per tile.
  --
  -- `Gen4Terrain.chunk` has read that block since the map work and `append`
  -- never wrote it, so at runtime the outdoor world had no behaviour at all:
  -- not a wrong answer, no answer. Measured on the cache before this line
  -- existed -- zero warps in all of Sinnoh sat on a press-north mat, because
  -- the maps that carry them hold no grid to read.
  --
  -- A SIDE-CAR, like the heights above it. 666 chunks of 32x32 u16 is 1.3 MB,
  -- which is a file and not a Lua table; `heights.bin` is the pattern and the
  -- reader is the same two fields.
  if chunk.permissions and #chunk.permissions > 0 then
    entry.permAt = state.permsAt
    entry.permBytes = #chunk.permissions
    state.perms[#state.perms + 1] = chunk.permissions
    state.permsAt = state.permsAt + #chunk.permissions
  end

  return entry
end

function Gen4Terrain.finish(state)
  return concat(state.geometry), concat(state.heights), concat(state.perms)
end

-- ---------------------------------------------------------------------------
-- The texture sets
-- ---------------------------------------------------------------------------

-- ONE PICTURE PER TEXTURE, and an atlas was tried first.
--
-- A map texture is TILED across the faces it dresses: a chunk's UVs run from
-- about -196 to +228 texels on a 64-texel picture, which is the same grass
-- laid down seven times over. That needs a sampler set to repeat, and a
-- sub-rectangle of an atlas cannot repeat -- the wrap applies to the whole
-- sheet, so every tiled face would smear its neighbours across itself.
--
-- Packing them and cropping back out at run time would work and buys nothing:
-- the pictures are 16 to 128 pixels square, `Gen4Model.new` already loads a
-- shape's texture by path and already sets `repeat` on it, and the cost of the
-- honest version is a file count rather than a code path. So each texture is
-- its own PNG and the index names it.
--
-- WHICH PALETTE EACH TEXTURE WEARS -- and it was palette 1, for all of them.
--
-- The note that used to sit here said: "Against the FIRST palette: a texture's
-- own palette is named by the MATERIAL that wears it, which is a fact about
-- the chunk rather than about the picture, and the great majority of these
-- sets pair one palette with one texture anyway."  The first half is true.
-- The second half is false, and it painted Sinnoh one colour.
--
-- Reported from play: "much of the tileset didnt seem properly colored
-- especially when outside".  Set 6, which is Twinleaf Town's, holds 78
-- textures and SEVENTY-FOUR palettes.  `ngrass` -- grass -- came out in
-- browns, because palette 1 of that set is `apeak`, a mountain top.  Every
-- outdoor map in the game was wearing one palette.
--
-- THE JOIN IS ALREADY IN THE CACHE and always was: every chunk shape carries
-- `material`, `texture` AND `palette`, because `Gen4Nsbmd` reads the material
-- that names both.  `ngrass` is worn with palette `grass`.  Nothing used it.
--
-- AND NAME-MATCHING IS NOT A SUBSTITUTE, which is worth saying because it is
-- the obvious shortcut.  Counted over all 7,547 chunk shapes: of the 1,149
-- distinct texture names, **553 are worn with a palette of a different name**
-- -- `ngrass02` wears `grass02`, `bf_symbol2` wears `symbol`, `ginga2` wears
-- `dun26_092`, and a further 553 follow a `_pl` suffix convention that the
-- other half does not.  Across the archives as a whole, 1,293 of 3,130 map
-- textures and 2,104 of 3,063 building textures have no palette of their own
-- name at all.
--
-- TWENTY-NINE textures are worn with MORE THAN ONE palette (`wcliff` is
-- `criff` on 76 shapes and `wcriff` on 7).  Those get a second picture filed
-- under "<texture>#<palette>"; every other texture is filed once under its
-- own name, so the file count barely moves.
--
-- `pairing` is { [textureName] = { [paletteName] = uses } }, gathered from the
-- chunks -- which are extracted before this runs, so there is nothing to
-- reorder.  Without it this falls back to a same-name palette and then to
-- position, which is better than palette 1 and is still not the answer.
function Gen4Terrain.paletteFor(parsed, texture, paletteName, index)
  local at = paletteName and Gen4Models.paletteIndexByName(parsed, paletteName)
  if at then return at end
  at = Gen4Models.paletteIndexByName(parsed, texture.name)
  if at then return at end
  return (parsed.palettes and parsed.palettes[index]) and index or 1
end

-- Returns a list of { name, texture, palette, image }, in the archive's own
-- order.  `name` is the key the picture is filed under.
function Gen4Terrain.textures(parsed, data, pairing)
  if not (parsed and parsed.textures) then return nil, "no textures" end
  local out, undecoded = {}, {}
  for i, t in ipairs(parsed.textures) do
    local worn = pairing and pairing[t.name]
    local names = {}
    if worn then
      for name in pairs(worn) do names[#names + 1] = name end
      -- Most-used first, so the bare name is the picture most of the map
      -- actually wants; ties broken by name so an import is reproducible.
      table.sort(names, function(a, b)
        if worn[a] ~= worn[b] then return worn[a] > worn[b] end
        return a < b
      end)
    end

    local first = true
    local failed = nil
    for pass = 1, math.max(#names, 1) do
      local name = names[pass]
      local at = Gen4Terrain.paletteFor(parsed, t, name, i)
      local image, why = Gen4Models.decode(parsed, data, i, at)
      if image then
        if first then
          out[#out + 1] = { name = t.name, texture = t.name,
                            palette = name, image = image }
          first = false
        end
        -- Only a texture worn with two palettes needs the second key.
        if name and #names > 1 then
          out[#out + 1] = { name = t.name .. "#" .. name, texture = t.name,
                            palette = name, image = image }
        end
      else
        failed = why
      end
    end
    if first then
      undecoded[#undecoded + 1] =
        ("%s (%s)"):format(tostring(t.name), tostring(failed))
    end
  end
  return out, undecoded
end

-- ---------------------------------------------------------------------------
-- Which chunks a map is made of
-- ---------------------------------------------------------------------------

-- grid(matrix) -> { width, height, land = { ... } }, row-major, 0-based ids.
--
-- The matrix IS the map: every map in the cartridge is one matrix, and a tile
-- at (tx, ty) belongs to the chunk at (tx // 32, ty // 32).  So the renderer
-- needs no per-map geometry of its own -- it needs this list and the chunk
-- store above.
function Gen4Terrain.grid(matrix)
  if not matrix then return nil end
  local land = {}
  for y = 0, matrix.height - 1 do
    for x = 0, matrix.width - 1 do
      land[y * matrix.width + x + 1] = Gen4Maps.chunkAt(matrix, x, y)
    end
  end
  -- ...and how far up each chunk is drawn (`Gen4Ground.chunkLift`). Carried
  -- only when the matrix has the section, which is the overworld and a few
  -- others; an interior's grid stays as small as it was.
  local altitudes
  for _, a in ipairs(matrix.altitudes or {}) do
    if a ~= 0 then altitudes = matrix.altitudes break end
  end
  return { width = matrix.width, height = matrix.height, land = land,
           altitudes = altitudes }
end

return Gen4Terrain
