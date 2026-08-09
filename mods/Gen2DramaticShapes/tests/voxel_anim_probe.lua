-- Driver: does the water/flower tile animation reach voxel mode?
--
-- Shoots a burst of frames spaced about one animation period apart, in
-- voxel mode and (for reference) flat.  The evidence is the difference
-- between consecutive shots: water tile $14 rolls sideways a pixel a step
-- and flower tile $03 cycles three frames, so the burst should NOT be
-- eight copies of the same picture.
--
--   POKEPORT_DRIVER=mods/DRAMATIC_SHAPE/tests/voxel_anim_probe.lua lovec .
--
-- knobs (env):
--   ANIM_MAP    map id                        (default PALLET_TOWN)
--   ANIM_SPOT   "x,y[,facing]"                (default 5,6,down)
--   ANIM_SHOTS  frames in the burst           (default 6)
--   ANIM_LEVEL  voxel rung, 0 = flat          (default 3)
--   SHOT_DIR    output directory, must exist  (default "shots")
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pipelines = require("src.render.Pipelines")
  local TileRenderer = require("src.render.TileRenderer")

  local SPEED = math.max(1,
    math.floor(tonumber(os.getenv("POKEPORT_SPEED")) or 1))
  local function wait(n) U.wait(n * SPEED) end

  local DIR = os.getenv("SHOT_DIR") or "shots"
  local mapId = os.getenv("ANIM_MAP") or "PALLET_TOWN"
  local shots = math.floor(tonumber(os.getenv("ANIM_SHOTS")) or 6)
  local level = math.floor(tonumber(os.getenv("ANIM_LEVEL")) or 3)
  local sx, sy, facing = (os.getenv("ANIM_SPOT") or "5,6,down")
    :match("^%s*(%d+)%s*,%s*(%d+)%s*,?%s*(%a*)")
  facing = (facing ~= "" and facing) or "down"

  local tileset = game.data.maps[mapId] and game.data.maps[mapId].tileset
  local specs = tileset and game.data.tilesets
                and TileRenderer.defaultAnimatedTiles(game.data.tilesets[tileset])
  print(("[anim] %s tileset=%s animated entries=%d")
    :format(mapId, tostring(tileset), specs and #specs or 0))
  for _, s in ipairs(specs or {}) do
    print(("[anim]   tile $%02X kind=%s period=%s")
      :format(s.tile or -1, tostring(s.kind), tostring(s.period)))
  end

  local Zoom = require("src.render.Zoom")
  Zoom.reset()
  Pipelines.setLevel("tiltshift", 0)
  U.teleport(game, mapId, tonumber(sx), tonumber(sy), facing)
  wait(20)

  Pipelines.setLevel("voxel", level)
  wait(30)                          -- outlast the camera tween

  -- the atlas the terrain mesh actually samples, dumped per step: if these
  -- differ but the frames do not, the animated tiles are not reaching the
  -- geometry (baked into prop prisms, say) rather than not animating
  local V = game.mods.exports["DRAMATIC_SHAPE"]
  V = V and V.lib
  local TerrainAtlas = V and V.require("TerrainAtlas")
  local PaletteFX = require("src.render.PaletteFX")
  local function dumpAtlas(tag)
    if not TerrainAtlas then return end
    local ow = game.overworld
    local map = ow and ow.map
    if not map then return end
    local colors = nil
    if not PaletteFX.usesGbcPack() and ow.paletteFor then
      colors = ow:paletteFor(map)
    end
    local img = TerrainAtlas.forMap(map, colors)
    if not img then return end
    print(("[anim]   atlas %s: animated copy=%s")
      :format(tag, tostring(img ~= map.renderer.image)))
    local ok = pcall(function()
      local w, h = img:getDimensions()
      local c = love.graphics.newCanvas(w, h)
      love.graphics.setCanvas(c)
      love.graphics.clear(0, 0, 0, 0)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(img)
      love.graphics.setCanvas()
      c:newImageData():encode("png", "atlas_" .. tag .. ".png")
    end)
    if not ok then print("[anim]   atlas dump failed") end
  end

  -- where the animated tiles ended up in the geometry: a flat top quad
  -- samples its tile through uvRect and picks the atlas patch up, but a
  -- cell Structures turned into a prop prism has its pixels baked as
  -- point-sampled voxels and would not
  if V and specs then
    local Structures = V.require("Structures")
    local ow = game.overworld
    local S = ow and ow.map and Structures.forMap(ow.map)
    if S then
      local def = ow.map.def
      for _, spec in ipairs(specs) do
        if not spec.tile then goto continue end   -- "toggle" specs claim
                                                  -- tile LISTS, not one slot
        local flat, prop, run, first = 0, 0, 0, nil
        for ty = 0, def.height * 4 - 1 do
          for tx = 0, def.width * 4 - 1 do
            local k = (ty + 64) * 4096 + (tx + 64)
            if S.tileAt[k] == spec.tile then
              if S.skip[k] then prop = prop + 1
              elseif S.runs[k] then run = run + 1
              else
                flat = flat + 1
                first = first or { tx, ty }
              end
            end
          end
        end
        print(("[anim]   tile $%02X on this map: %d flat, %d in a volume run,"
               .. " %d inside a prop%s"):format(spec.tile, flat, run, prop,
          first and (" -- first at cell " .. math.floor(first[1] / 2)
                     .. "," .. math.floor(first[2] / 2)) or ""))
        ::continue::
      end
    end
  end

  -- one animation period is 20 logic frames at 60Hz, and TileRenderer.tick
  -- runs on wall-clock steps, so ~22 rendered frames lands the next step.
  -- animFrame is an OPTIONAL engine seam this build may not export; the
  -- mod's own clock (TerrainAtlas._animFrame) reads the same counter by
  -- whatever route exists, so ask it first.
  local function clock()
    if TerrainAtlas and TerrainAtlas._animFrame then
      local ok, f = pcall(TerrainAtlas._animFrame)
      if ok and type(f) == "number" then return f end
    end
    if TileRenderer.animFrame then
      local ok, f = pcall(TileRenderer.animFrame)
      if ok and type(f) == "number" then return f end
    end
    return -1
  end
  for i = 1, shots do
    game.capturePath = ("%s/anim_%s_L%d_%02d.png"):format(DIR, mapId, level, i)
    wait(3)
    print(("[anim] shot %d at animFrame %d step %d"):format(
      i, clock(), math.floor(clock() / 20) % 8))
    dumpAtlas(tostring(i))
    wait(22)
  end

  Pipelines.setLevel("voxel", 0)
  wait(5)
  print("[anim] done")
end
