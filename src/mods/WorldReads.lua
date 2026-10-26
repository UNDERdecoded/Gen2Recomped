-- Data-only readers shared by mod.world. Nothing here constructs a Pokemon,
-- loads a map, calls gameplay methods or advances either random generator.
local Ids = require("src.mods.UnifiedIds")
local Reads = {}
local METHODS = { party = true, activeBlockAt = true, liveMaps = true }

function Reads.supports(name)
  return type(name) == "string" and METHODS[name] == true
end

-- Capture native alias identity/name metadata before the loader splits alias
-- rows during merging. Fresh indexes at read time still include later mods.
function Reads.context(loader)
  local ids = Ids.new(loader)
  for _, kind in ipairs({ "pokemon", "moves", "items" }) do
    ids:entries(kind)
  end
  return {
    ids = function()
      return Ids.new(loader)
    end,
  }
end

-- Engine callers can construct WorldAPI without a mod loader too. The
-- private registry facade only reads data; Ids' bookkeeping stays on it.
local function dataIds(data)
  local loader = { content = {} }
  for _, kind in ipairs({ "pokemon", "moves", "items" }) do
    local rows = type(data[kind]) == "table" and data[kind] or {}
    loader.content[kind] = {
      base = function()
        return rows
      end,
      each = function()
        return pairs(rows)
      end,
    }
  end
  return Ids.new(loader)
end

local function copy(value, seen)
  local kind = type(value)
  if kind ~= "table" then
    if kind == "number" or kind == "string" or kind == "boolean" then
      return value
    end
    return nil
  end
  seen = seen or {}
  if seen[value] then
    return seen[value]
  end
  local out = {}
  seen[value] = out
  for key, sub in pairs(value) do
    if type(key) == "string" or type(key) == "number" then
      out[key] = copy(sub, seen)
    end
  end
  return out
end
local STATUS =
  { SLP = "sleep", PSN = "poison", BRN = "burn", FRZ = "freeze", PAR = "paralyze", TOX = "toxic" }
local STAT = {
  hp = "hp",
  attack = "attack",
  defense = "defense",
  speed = "speed",
  special = "special",
  specialAttack = "spatk",
  specialDefense = "spdef",
}

-- The same common live-Pokemon shape as the unified callback boundary.
-- Native diagnostics are data-only copies, including unknown save extensions.
function Reads.party(game, context)
  local save = game and game.save
  if not save then
    return nil, "no save"
  end
  local data = game.data or {}
  local ids = context and context.ids() or dataIds(data)
  local out = {}
  for i, raw in ipairs(save.party or {}) do
    local stats, moves = {}, {}
    for key, native in pairs(STAT) do
      stats[key] = (raw.stats or {})[native]
    end
    stats.specialAttack = stats.specialAttack or stats.special
    stats.specialDefense = stats.specialDefense or stats.special
    for slot, move in ipairs(raw.moves or {}) do
      local id = type(move) == "table" and move.id or move
      local def = (data.moves or {})[id]
      local ups = type(move) == "table" and (move.ppUps or 0) or 0
      moves[slot] = {
        id = ids:read("moves", id),
        pp = type(move) == "table" and move.pp or nil,
        maxPp = def and ((def.pp or 0) + ups * math.floor((def.pp or 0) / 5)) or nil,
        ppUps = ups,
      }
    end
    out[i] = {
      species = ids:read("pokemon", raw.species),
      item = ids:read("items", raw.item),
      nickname = raw.nickname,
      name = raw.name,
      level = raw.level,
      hp = raw.hp,
      maxHp = raw.stats and raw.stats.hp,
      status = STATUS[raw.status] or raw.status,
      isEgg = raw.isEgg == true,
      stats = stats,
      moves = moves,
      native = copy(raw),
    }
  end
  return out
end

local function integer(value, low)
  return type(value) == "number"
    and value == value
    and value < math.huge
    and value > -math.huge
    and value % 1 == 0
    and value >= low
end

-- Public block coordinates are zero-based, not walk-cell coordinates. Derive
-- geometry from this map's runtime tileset, not the selected game's number.
function Reads.metadata(map)
  local def = map and map.def
  if
    not def
    or not integer(def.width, 1)
    or not integer(def.height, 1)
    or not integer(map.blockCells, 1)
    or not integer(map.blockTiles, 1)
    or map.blockTiles * 8 ~= map.blockCells * 16
  then
    return nil, "block geometry unavailable"
  end
  return {
    tileSize = map.blockTiles * 8,
    cellSize = 16,
    coordinateBase = 0,
    kind = (def.generation == 4 or def.generation == 5 or def.gen5) and "runtime_cell"
      or map.blockCells == 1 and "metatile"
      or "block",
    width = def.width,
    height = def.height,
  }
end

function Reads.activeBlockAt(map, mapId, bx, by)
  if map.id ~= mapId then
    return nil, "map is not active"
  end
  if not integer(bx, 0) or not integer(by, 0) then
    return nil, "invalid block coordinates"
  end
  local metadata, reason = Reads.metadata(map)
  if not metadata then
    return nil, reason
  end
  if bx >= metadata.width or by >= metadata.height then
    return nil, "block coordinates out of bounds"
  end
  local index = by * metadata.width + bx + 1
  local block = map.blockPatch and map.blockPatch[index]
  if block == nil then
    local blocks = map.def.blocks
    if type(blocks) == "table" then
      block = blocks[index]
    elseif type(blocks) == "string" then
      -- Respect a cache already used by Map:blockAt, without populating it.
      if map.def._blockArray then
        block = map.def._blockArray[index]
      else
        local lo, hi = blocks:byte(index * 2 - 1, index * 2)
        if hi then
          block = (lo + hi * 256) % 1024
        end
      end
    end
  end
  if not integer(block, 0) then
    return nil, "block unavailable"
  end
  return block, metadata
end

function Reads.liveMaps(world)
  local active = world.map
  local out = {}
  local seen = {}
  local function add(map, x, y, isActive)
    if not map then
      return
    end
    -- A connected layout can show one map at several different offsets.
    -- Collapse duplicate placements only, retaining the spatial instances.
    local key = tostring(map.id) .. ":" .. tostring(x) .. ":" .. tostring(y)
    if seen[key] then
      return
    end
    seen[key] = true
    local metadata = Reads.metadata(map)
    out[#out + 1] = {
      mapId = map.id,
      x = x,
      y = y,
      active = isActive,
      width = map.widthCells,
      height = map.heightCells,
      block = metadata,
    }
  end
  add(active, 0, 0, true)
  for _, neighbor in ipairs(world.neighbors or {}) do
    add(neighbor.map, neighbor.cx or 0, neighbor.cy or 0, false)
  end
  return out
end
return Reads
