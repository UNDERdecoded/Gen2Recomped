-- THE MAP SET a world is played on (docs/online-design.md 2.4 / 2.8): a
-- digest of the game's map ids, carried in the world hello as `mapSet`.
-- Members must share it with the host, so a ghost's "map T01, cell 9,4"
-- means the same place on every screen in the world.  R/B/Y share one, G/S
-- share one, FR/LG share one; Platinum and HGSS do not (different regions),
-- and a romhack's added map gives it its own.
--
-- Aliases (Data's friendly ids for one map) fold onto the def's own `id`,
-- so the digest is the set of maps, not the set of names for them.  Pure.

local MapSet = {}

local bit = bit or (pcall(require, "bit") and require("bit")) or nil

local function fnv(text, h)
  for i = 1, #text do
    h = bit.bxor(h, text:byte(i))
    -- 32-bit FNV-1a multiply kept inside the double's exact range
    local lo = bit.band(h, 0xFFFF)
    local hi = bit.rshift(h, 16) % 65536
    h = bit.tobit(lo * 403 + bit.lshift((hi * 403 + lo * 256) % 65536, 16))
  end
  return h
end

function MapSet.ids(maps)
  local seen, ids = {}, {}
  for key, def in pairs(maps or {}) do
    local id = type(def) == "table" and def.id or key
    id = tostring(id)
    if not seen[id] then
      seen[id] = true
      ids[#ids + 1] = id
    end
  end
  table.sort(ids)
  return ids
end

function MapSet.digest(maps)
  local ids = MapSet.ids(maps)
  local a, b = bit.tobit(2166136261), bit.tobit(0x811C9DC5 + 0x9E37)
  for _, id in ipairs(ids) do
    a = fnv(id .. "\n", a)
    b = fnv("\n" .. id, b)
  end
  return ("%08x%08x:%d"):format(a % 4294967296, b % 4294967296, #ids)
end

local cache = setmetatable({}, { __mode = "k" })

-- the digest of a loaded dataset (cached per data table)
function MapSet.of(data)
  local maps = data and data.maps
  if not maps then return nil end
  local hit = cache[maps]
  if hit then return hit end
  local ok, d = pcall(MapSet.digest, maps)
  if not ok then return nil end
  cache[maps] = d
  return d
end

return MapSet
