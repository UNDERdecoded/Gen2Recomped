-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- DIVE INTO THE ABYSSAL RUINS (Black / White).
--
-- READ FROM CODE (Black):
--   * the field's A press (ov21 0x02189EF4), when no object or event
--     answered: 0x021CD440 asks the DIVE TABLE (ov21 0x021DB450, four
--     records { zone, x, z, destination }) for the player's matrix cell --
--     a 3 x 3 box from (x, z) (0x021CD400) -- and on a hit runs common
--     script 0x271B (member 867): "It's a deep part of the sea. Would you
--     like to use Dive?", the Dive user (move 291), the HM cut-in, 0x0C8 0
--   * the table: Undella Bay (zone 240) at (800, 275) -> 241, (785, 289) ->
--     242, (815, 289) -> 243, (800, 307) -> 244 -- the Abyssal Ruins' four
--     entrances
--   * 0x0C8 0 (0x021D2418 -> 0x021D2278): the camera drops (0x21C7858,
--     -0x40000 over 40 frames), SE 0x63C, then the warp (0x02184FD4) to the
--     destination zone's own location (0x02014204): no warp record, the
--     zone header's +0x24 / +0x28 / +0x2C -- on a rail zone (the Abyssal
--     Ruins are) a rail position <line, along, across> (0x02013C70 /
--     0x02013B90), else whole units (0x02013B74)
-- The rail position goes to a tile the way the import places rail events
-- (src/import/Gen5Field.lua's railTile; the same arithmetic here, over the
-- cache's gen5_rails).
-- INFERRED: the dive is offered only while surfing (the A press it hangs
-- off is the surfing player's); the camera drop is folded into the warp's
-- fade; the diver arrives on foot, facing up.

local M = {}

M.COMMON = 0x271B
M.ZONE = 240
M.TABLE = { { x = 800, z = 275, dest = 241 }, { x = 785, z = 289, dest = 242 },
            { x = 815, z = 289, dest = 243 }, { x = 800, z = 307, dest = 244 } }

local function header(def) return def and tonumber(def.header) end

-- the destination zone for the player's matrix cell, or nil
function M.destination(ow)
  local def = ow and ow.map and ow.map.def
  local p = ow and ow.player
  if not (p and header(def) == M.ZONE) then return nil end
  local gx, gz = p.cellX + (def.originX or 0), p.cellY + (def.originY or 0)
  for _, r in ipairs(M.TABLE) do
    if gx >= r.x and gx < r.x + 3 and gz >= r.z and gz < r.z + 3 then return r.dest end
  end
  return nil
end

local function generated(name)
  local dir = os.getenv("POKEPORT_DATA_DIR")
  if dir then
    local chunk = loadfile(dir .. "/" .. name .. ".lua")
    if chunk then local ok, t = pcall(chunk) if ok then return t end end
  end
  local ok, t = pcall(require, "data.generated." .. name)
  return ok and t or nil
end

-- <line, along, across> to a tile of `def` (Gen5Field's railTile)
function M.railTile(data, def, li, along, across)
  local line = data.lines[li] or data.lines[tostring(li)]
  local a = line and (data.points[line.a] or data.points[tostring(line.a)])
  local b = line and (data.points[line.b] or data.points[tostring(line.b)])
  if not (a and b) then return nil end
  local n = math.max(line.raw and line.raw[6] or 1, 1)
  local t = math.min(math.max((along + 0.5) / n, 0), 1)
  local x, z, tx, tz
  local curve = data.curves and (data.curves[li] or data.curves[tostring(li)])
  if curve and curve.kind == 1 then
    local ra = math.sqrt((a.x - curve.cx) ^ 2 + (a.z - curve.cz) ^ 2)
    local rb = math.sqrt((b.x - curve.cx) ^ 2 + (b.z - curve.cz) ^ 2)
    local ta = math.atan2(a.z - curve.cz, a.x - curve.cx)
    local tb = math.atan2(b.z - curve.cz, b.x - curve.cx)
    local d = tb - ta
    if d > math.pi then d = d - 2 * math.pi elseif d < -math.pi then d = d + 2 * math.pi end
    local th = ta + d * t
    local r = ra + (rb - ra) * t
    x, z = curve.cx + r * math.cos(th), curve.cz + r * math.sin(th)
    local sg = d >= 0 and 1 or -1
    tx, tz = -math.sin(th) * sg, math.cos(th) * sg
  else
    x, z = a.x + (b.x - a.x) * t, a.z + (b.z - a.z) * t
    local len = math.max(math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2), 1e-6)
    tx, tz = (b.x - a.x) / len, (b.z - a.z) / len
  end
  x, z = x - tz * across * 16, z + tx * across * 16
  return math.floor(x / 16) - (def.originX or 0), math.floor(z / 16) - (def.originY or 0)
end

-- where a dive into `zone` lands: its header's location, as a local tile
function M.arrival(data, zone)
  local mapId = ("Z%03d"):format(zone)
  local def = data and data.maps and data.maps[mapId]
  local zones = data and data.gen5_zones or generated("gen5_zones")
  local z = zones and (zones[zone] or zones[tostring(zone)])
  if not (def and z) then return nil end
  local rail = def.gen5Rail
  if rail then
    local rails = generated("gen5_rails")
    local rd = rails and (rails[rail.file] or rails[tostring(rail.file)])
    if rd then
      local x, y = M.railTile(rd, def, z.spawnX or 0, z.spawnY or 0, z.spawnZ or 0)
      if x then return mapId, x, y end
    end
  end
  return mapId, (z.spawnX or 0) - (def.originX or 0), (z.spawnZ or 0) - (def.originY or 0)
end

-- the A press: a dive spot under a surfing player runs common 0x271B
function M.tryInteract(ow)
  local p = ow and ow.player
  if not (p and p.surfing) or not M.destination(ow) then return false end
  local data = require("src.core.Game").data
  local VM = require("src.script.Gen4ScriptVM")
  local pool = VM.store(data)
  local Bands = require("src.import.Gen4ScriptBands")
  local kind, name, index = Bands.classify(M.COMMON)
  local band = pool and pool.bands and kind == "band" and pool.bands[name]
  local label = band and band.entries and band.entries[index + 1]
  local rows = label and VM.compile(data, label)
  if not rows then return false end
  ow.runner:run(rows, { mapId = ow.map.id })
  return true
end

return M
