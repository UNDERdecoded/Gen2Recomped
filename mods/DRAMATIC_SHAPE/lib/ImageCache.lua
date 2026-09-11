-- Voxel world mode: decoded pixels, kept.
--
-- Assets.imageData is deliberately uncached upstream -- "pixel-level reads
-- resolve the same way but stay uncached: the caller keeps the derived
-- product" (src/render/Assets.lua) -- which is the right contract for the
-- flat renderer, whose one caller decodes a strip once and keeps the strip.
--
-- This mod is not that caller. It reads the same handful of images over and
-- over, from several places that do not know about each other:
--
--   * the tileset atlas, decoded by Structures (its own cache), by
--     TerrainAtlas twice (the SGB bake and the RED++ rebake), by
--     TerrainAtlas again to learn a tile's shades, and by GlassMask;
--   * the FLOWER FRAME files, decoded inside patch() -- which runs every
--     time the animation step turns over, about three times a second, for
--     as long as the map is on screen. That one is not a load cost at all,
--     it is a recurring per-second cost on the render thread, and it was
--     the single clearest waste the first profile turned up.
--
-- So: one table, keyed by the path as the CALLER gave it, holding the
-- decoded ImageData. Registered with Assets.invalidate so a hot reload
-- drops it alongside every other downstream cache.
--
-- The entries are never evicted by size. That is deliberate and bounded:
-- what lands here is tileset art and animation frames -- a few dozen small
-- images for a whole session, tens of kilobytes each -- not per-map bakes,
-- which have their own eviction in TerrainAtlas.setLive.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Assets = require("src.render.Assets")
local Perf = V.require("Perf")

local ImageCache = {}

local cache = {}

-- The decoded pixels for `path`, or nil when it cannot be read.
--
-- `false` is cached for an unreadable path, so a missing or corrupt asset
-- costs one failed decode for the session rather than one per frame -- the
-- same sticky-failure shape the rest of this mod uses for GPU objects.
function ImageCache.get(path)
  if not path then return nil end
  local hit = cache[path]
  if hit ~= nil then
    Perf.count("imageCache.hit")
    return hit or nil
  end
  local t0 = Perf.now()
  local ok, data = pcall(Assets.imageData, path)
  Perf.add("ImageCache.decode", t0)
  Perf.count("imageCache.miss")
  cache[path] = (ok and data) or false
  return cache[path] or nil
end

function ImageCache.invalidate()
  cache = {}
end

Assets.register(ImageCache.invalidate)

return ImageCache
