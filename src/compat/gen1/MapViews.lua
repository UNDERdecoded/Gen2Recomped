-- Owned compatibility snapshots over the native map owner. No map loads,
-- renderer construction, shared-definition writes or save access.
local Views = {}
local editions = { firered = true, leafgreen = true, emerald = true, ruby = true, sapphire = true }
local directions = {north=true,south=true,east=true,west=true,dive=true,emerge=true}
local function uint(n, max)
  return type(n) == "number" and n >= 0 and n <= max and n % 1 == 0
end
local function world(game)
  local states = game.stack and game.stack.states
  if states then
    for i = #states, 1, -1 do if states[i].isOverworld then return states[i] end end
    return nil
  end
  return game.overworld and game.overworld.isOverworld and game.overworld or nil
end
local function kind(mapType)
  local numbers = {NONE=0,TOWN=1,CITY=2,ROUTE=3,UNDERGROUND=4,UNDERWATER=5,OCEAN_ROUTE=6,UNKNOWN=7,INDOOR=8,SECRET_BASE=9}
  mapType = numbers[mapType] or tonumber(mapType) or 0
  if mapType == 4 or mapType == 8 or mapType == 9 then return "indoor", "INDOOR" end
  -- Match the public census registration, including its ocean/underwater
  -- classification, rather than silently changing imported mod semantics.
  if mapType == 3 then return "route", "ROUTE" end
  return "town", "TOWN"
end

function Views.new(getGame, getEdition)
  assert(type(getGame) == "function" and type(getEdition) == "function", "native map view resolvers required")
  -- Companion contracts are loaded on construction, never by a native boot
  -- that does not request compatibility observations.
  local Identity = require("src.compat.gen1.MapIdentity")
  local Behavior = require("src.compat.gen1.MetatileBehavior")
  local Classes = require("src.compat.gen1.CollisionClass")
  local Layout = require("src.core.game3.layout_native")
  local Tiles = require("src.render.Gen3Tiles")
  local Versions = require("src.core.GameVersion")
  local function weakCache() return setmetatable({}, {__mode = "v"}) end
  local owner, data, maps, edition, binding, cache, ended = nil, nil, nil, nil, nil, weakCache(), false
  local serial, published = 0, setmetatable({}, {__mode = "k"})
  local ids = setmetatable({}, {__mode = "k"})
  local function token(value)
    if type(value) ~= "table" then return value or false end
    if not ids[value] then ids[value] = {} end
    return ids[value]
  end
  local handle = {}
  local function reset() cache = weakCache(); binding = nil; owner, data, maps, edition = nil, nil, nil, nil end
  local function currentOwner()
    if ended then return nil, "map view owner released" end
    local game, id = getGame(), getEdition()
    if type(game) ~= "table" or not editions[id] or not Versions.info(id)
        or not game.data or type(game.data.maps) ~= "table" then
      reset(); return nil, "no native GBA session"
    end
    local ow = world(game)
    if not (ow and ow.map and game.data.maps[ow.map.id] == ow.map.def) then
      reset(); return nil, "no active native map"
    end
    if game ~= owner or game.data ~= data or game.data.maps ~= maps or id ~= edition then
      reset(); owner, data, maps, edition = game, game.data, game.data.maps, id
      binding = Identity.bind(maps, edition)
    end
    return ow
  end
  local function loaded(ow, id, def)
    if ow.map.id == id or ow.map.def == def then return ow.map end
    for _, row in ipairs(ow.neighbors or {}) do
      if row.map and (row.map.id == id or row.map.def == def) then return row.map end
    end
  end
  local function build(id)
    local ow, why = currentOwner(); if not ow then return nil, why end
    local nativeId, def = binding:nativeId(id)
    if not nativeId and maps[id] then
      local alias = binding:legacyId(id)
      if alias then nativeId, def = binding:nativeId(alias) end
    end
    if not nativeId then return nil, "map identity unavailable" end
    local canonical = binding:legacyId(nativeId)
    local live = loaded(ow, nativeId, def)
    if live and live.def ~= def then return nil, "resident map definition changed" end
    local w, h = def.width, def.height
    if not uint(w, 1024) or w == 0 or not uint(h, 1024) or h == 0 or def.blockPx ~= 16 then
      return nil, "native layout dimensions unavailable"
    end
    local sets, constants = data.map_tilesets, data.constants
    local pair = data.tilesets and data.tilesets[def.tileset]
    local a = pair and sets and sets[pair.primaryKey]
    local b = pair and sets and sets[pair.secondaryKey]
    local geometry = constants and constants.gen3Layout
    if not (a and b and geometry and Tiles.sourceBehavior
        and uint(geometry.metatilesInPrimary,1023) and geometry.metatilesInPrimary > 0
        and uint(geometry.tilesInPrimary,1023) and geometry.tilesInPrimary > 0
        and uint(geometry.palettesInPrimary,15) and geometry.palettesInPrimary > 0
        and geometry.metatileLayers == 2) then return nil, "original tileset attributes unavailable" end
    local rawFlags = constants.gen3SourceBehaviorFlags
    local frlg = edition == "firered" or edition == "leafgreen"
    if not frlg and not (rawFlags and rawFlags.version == 1 and type(rawFlags.raw) == "string"
        and #rawFlags.raw == 240 and rawFlags.romSha1 == Versions.info(edition).sha1) then
      return nil, "original terrain flags unavailable"
    end
    local bw, bh, border = def.sourceBorderWidth, def.sourceBorderHeight, def.sourceBorder
    if not uint(bw, 255) or bw == 0 or not uint(bh, 255) or bh == 0
        or type(border) ~= "string" or #border ~= bw * bh * 2 then return nil, "original border unavailable" end
    if def.connections and next(def.connections) and not def.sourceConnections then
      return nil, "original connection order unavailable"
    end
    local decodedBlocks = def._blockArraySource == def.blocks and def._blockArray
    local cached = cache[nativeId]
    local prior = cached and published[cached].stamp
    -- The stamp is private. Validate every source field on a hit without
    -- allocating another 34-element snapshot for each terrain read.
    if prior and
        prior[1] == (token(owner))
        and prior[2] == (token(maps))
        and prior[3] == (edition)
        and prior[4] == (token(def))
        and prior[5] == (token(live))
        and prior[6] == (live and live.gridRevision or 0)
        and prior[7] == (token(def.blocks))
        and prior[8] == (token(def.collisionCells))
        and prior[9] == (token(def.elevationCells))
        and prior[10] == (token(def.sourceConnections))
        and prior[11] == (token(def.warps))
        and prior[12] == (w)
        and prior[13] == (h)
        and prior[14] == (token(decodedBlocks))
        and prior[15] == (token(a))
        and prior[16] == (token(b))
        and prior[17] == (a.attributes or false)
        and prior[18] == (b.attributes or false)
        and prior[19] == (a.sourceAttributes or false)
        and prior[20] == (b.sourceAttributes or false)
        and prior[21] == (a.sourceAttributeBytes or false)
        and prior[22] == (b.sourceAttributeBytes or false)
        and prior[23] == (a.sourceBehaviorMask or false)
        and prior[24] == (b.sourceBehaviorMask or false)
        and prior[25] == (rawFlags and rawFlags.raw or false)
        and prior[26] == (border)
        and prior[27] == (bw)
        and prior[28] == (bh)
        and prior[29] == (token(geometry))
        and prior[30] == (geometry.metatilesInPrimary)
        and prior[31] == (geometry.tilesInPrimary)
        and prior[32] == (geometry.palettesInPrimary)
        and prior[33] == (geometry.metatileLayers)
        and prior[34] == (def.mapType or 0) then return cached end
    local stamp = {token(owner),token(maps),edition,token(def), token(live), live and live.gridRevision or 0,
      token(def.blocks), token(def.collisionCells), token(def.elevationCells), token(def.sourceConnections), token(def.warps), w, h,
      token(decodedBlocks),
      token(a), token(b), a.attributes or false, b.attributes or false, a.sourceAttributes or false, b.sourceAttributes or false,
      a.sourceAttributeBytes or false, b.sourceAttributeBytes or false,
      a.sourceBehaviorMask or false, b.sourceBehaviorMask or false,
      rawFlags and rawFlags.raw or false, border, bw, bh, token(geometry), geometry.metatilesInPrimary,
      geometry.tilesInPrimary,geometry.palettesInPrimary,geometry.metatileLayers,def.mapType or 0}
    local terrain = Tiles.new({primary = a, secondary = b}, geometry)
    local flags = {}
    if not frlg then
      for raw = 0, 239 do
        local bits = rawFlags.raw:byte(raw + 1)
        if bits > 7 then return nil, "invalid original terrain flags" end
        flags[Behavior.fromRaw(edition, raw)] = bits
      end
    end
    local classify = Classes.new(frlg and "frlg" or "rse", flags)
    local mapKind, environment = kind(def.mapType)
    local warps = {}
    for _, row in ipairs(def.warps or {}) do
      if uint(row.x, w - 1) and uint(row.y, h - 1) then warps[row.y * w + row.x + 1] = true end
    end
    local paddedW, paddedH = w + w % 2, h + h % 2
    local cells = {}
    for y = 0, paddedH - 1 do for x = 0, paddedW - 1 do
      local sx, sy = math.min(x, w - 1), math.min(y, h - 1)
      local index = sy * w + sx + 1
      local mid = live and live.blockPatch and live.blockPatch[index]
      if mid == nil then
        local blocks = decodedBlocks or def.blocks
        if type(blocks) == "table" then mid = blocks[index]
        elseif type(blocks) == "string" and #blocks >= index * 2 then
          mid = (blocks:byte(index * 2 - 1) + blocks:byte(index * 2) * 256) % 1024
        end
      end
      local collision = live and live.collisionPatch and live.collisionPatch[index]
      if collision == nil then collision = def.collisionCells and def.collisionCells[index] end
      local elevation = live and live.elevationPatch and live.elevationPatch[index]
      if elevation == nil then elevation = def.elevationCells and def.elevationCells[index] end
      if not uint(mid, 1023) or not uint(collision, 3) or not uint(elevation, 15) then return nil, "native cell source unavailable" end
      if mapKind == "indoor" and (x >= w or y >= h) then mid, collision, elevation = 0, 1, 0 end
      local raw = terrain:sourceBehavior(mid)
      if raw == nil then return nil, "original cell behavior unavailable" end
      local behavior = Behavior.fromRaw(edition, raw)
      local coll = classify.fromCell(mid, collision, behavior, mapKind)
      -- Resolve the native pack's final blocking guard after classification.
      -- These are the land classes emitted by our classifier; water, walls
      -- and directional ledges retain their own categories.
      if collision ~= 0 and (coll == 0 or coll == 0x18 or coll == 0x2b
          or ((coll == 0x71 or coll == 0x72) and not (x < w and y < h and warps[index]))) then coll = 7 end
      cells[#cells + 1] = {mid = mid, coll = coll, elev = elevation}
    end end
    local borders = {}; for i = 1, bw * bh do borders[i] = (border:byte(i * 2 - 1) + border:byte(i * 2) * 256) % 1024 end
    local converted = {}
    for _, row in ipairs(def.sourceConnections or {}) do
      if not directions[row.dir]
          or type(row.offset) ~= "number" or row.offset % 1 ~= 0 then return nil,"invalid source connection" end
      local destination = binding:legacyId(row.map)
      if not destination then return nil, "connection map identity unavailable" end
      converted[#converted + 1] = {dir = row.dir, map = destination, offset = row.offset}
    end
    local convertedWarps = {}
    for _, row in ipairs(def.warps or {}) do
      local destination = row.destMap
      local canonicalDestination = binding:legacyId(destination)
      local group, number
      if not canonicalDestination and type(destination) == "string" then
        group, number = destination:match("^MAP_G(%d+)_N(%d+)$")
        group, number = tonumber(group), tonumber(number)
        canonicalDestination = group and Identity.lookup(edition, group, number) or Identity.lookup(edition, destination)
      end
      convertedWarps[#convertedWarps+1]={x=row.x,y=row.y,elevation=row.elevation,destWarp=row.destWarp,
        destMap=canonicalDestination,nativeDestination=destination,
        mapGroup=not canonicalDestination and group or nil,mapNum=not canonicalDestination and number or nil}
    end
    local snapshot = {id = canonical, nativeId = nativeId, nativePair = def.tileset,
      width = w, height = h, kind = mapKind, environment = environment,
      connections = converted, warps = convertedWarps}
    -- The native pair key is explicit. Atlas-name compatibility is a separate
    -- provider and this observation is not installed as the old map module.
    snapshot.midLayout = Layout.fromDecoded({width = paddedW, height = paddedH, trueWidth = w, trueHeight = h,
      cells = cells, borderWidth = bw, borderHeight = bh, borderMids = borders}, canonical, def.tileset)
    serial = serial + 1; snapshot.revision = serial
    cache[nativeId], published[snapshot] = snapshot, {stamp = stamp,id = nativeId}
    return snapshot
  end
  function handle:current()
    local ow, why = currentOwner(); if not ow then return nil, why end
    return build(ow.map.id)
  end
  function handle:map(id) return build(id) end
  function handle:isCurrent(view)
    local record = published[view]; if not record then return false end
    local fresh = build(record.id)
    return fresh == view
  end
  function handle:invalidate(id)
    if id == nil then cache = weakCache(); return end
    local _, why = currentOwner(); if why then return end
    local key = binding:nativeId(id)
    cache[key or id] = nil
  end
  function handle:release() ended = true; reset(); getGame, getEdition = nil, nil end
  return handle
end
return Views
