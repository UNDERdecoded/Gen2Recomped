-- One Minish Cap room: its two BG layers, collision, exits and entity lists.
--
-- Collision follows the cartridge (src/playerUtils.c sub_0807BBE4 and
-- src/movement.c IsTileCollision): every 16x16 metatile of a layer has a
-- collision byte = gMapTileTypeToCollisionData[tileType[metatile]] (or the
-- special-tile table for metatile ids >= $4000, or the room's own collision
-- map when it ships one).  A byte below $10 is four 8x8 quarters (bit 3
-- top-left, 2 top-right, 1 bottom-left, 0 bottom-right, $0F solid); $FF
-- and $10+ pick one of the partial shapes (diagonals, 3/8 strips) through
-- the cartridge's shape lookup, tested per pixel against its masks.

local bit = require("bit")
local band, rshift = bit.band, bit.rshift

local Room = {}
Room.__index = Room

-- IsPosInTransitionRect's half extents per area-warp shape (scroll.c)
local SHAPE_HALF = { [0] = { 6, 6 }, { 6, 14 }, { 14, 6 }, { 22, 6 } }

function Room.load(assets, area, room)
  local maps = assets:roomMaps(area, room)
  if not maps then return nil, "no room " .. area .. ":" .. room end
  local h = maps.header
  local self = setmetatable({
    assets = assets, area = area, room = room,
    x = h.x, y = h.y, width = h.w, height = h.h,
    tw = maps.w, th = maps.h, maps = maps,
    exits = h.exits or {}, entities = h.entities or {},
    tileEntities = h.tileEntities or {},
    areaInfo = assets:area(area),
  }, Room)
  self.atlas = assets:atlas(area, h.ts)
  self:buildCollision()
  self:buildBatches()
  return self
end

function Room:buildCollision()
  local A = self.assets
  local types = self.atlas and self.atlas.types or { bottom = {}, top = {} }
  self.coll = {}
  for layer, name in ipairs({ "bottom", "top" }) do
    local m = self.maps[name]
    local t = types[name] or {}
    local c = {}
    for i = 0, self.tw * self.th - 1 do
      local mt = m[i] or 0
      local v
      if mt >= 0x4000 then
        v = A.specialCollision[mt - 0x4000] or 0
      else
        v = A.typeCollision[t[mt] or 0] or 0
      end
      c[i] = v
    end
    self.coll[layer] = c
  end
  if self.maps.collisionOverride then
    for i, v in pairs(self.maps.collisionOverride) do self.coll[1][i] = v end
  end
end

-- Rebuild one cell after the map changes (a cut bush, an opened chest).
function Room:setTile(layer, tx, ty, metatile)
  local name = layer == 2 and "top" or "bottom"
  local i = ty * self.tw + tx
  self.maps[name][i] = metatile
  local t = self.atlas and self.atlas.types[name] or {}
  local v
  if metatile >= 0x4000 then v = self.assets.specialCollision[metatile - 0x4000] or 0
  else v = self.assets.typeCollision[t[metatile] or 0] or 0 end
  self.coll[layer][i] = v
  self.dirty = true
end

function Room:tileType(layer, tx, ty)
  local name = layer == 2 and "top" or "bottom"
  local mt = self.maps[name][ty * self.tw + tx]
  if not mt then return nil end
  if mt >= 0x4000 then return mt end
  local t = self.atlas and self.atlas.types[name]
  return t and t[mt], mt
end

-- per-pixel collision for collisionType 0 (the player and most NPCs)
function Room:isSolid(x, y, layer)
  x, y = math.floor(x), math.floor(y)
  if x < 0 or y < 0 or x >= self.width or y >= self.height then return true end
  local c = self.coll[layer or 1]
  local v = c[rshift(y, 4) * self.tw + rshift(x, 4)] or 0
  if v == 0 then return false end
  if v < 0x10 then
    if v == 0x0F then return true end
    local q = v
    if band(y, 8) == 0 then q = rshift(q, 2) end
    if band(x, 8) == 0 then q = rshift(q, 1) end
    return band(q, 1) ~= 0
  end
  local A = self.assets
  local shape
  if v == 0xFF then shape = 1
  else shape = A.shapeLookup and A.shapeLookup[v - 0x10] or 1 end
  if shape == 0 then return false end
  if shape == 1 or not A.shapeMasks then return true end
  local mask = A.shapeMasks[shape - 2]
  if not mask then return true end
  return band(rshift(mask[band(y, 15)] or 0, band(x, 15)), 1) ~= 0
end

-- ---------------------------------------------------------------------------
-- drawing: one SpriteBatch per layer
-- ---------------------------------------------------------------------------
function Room:buildBatches()
  self.batches = {}
  if not self.atlas or self.maps.special then return end
  for _, name in ipairs({ "bottom", "top" }) do
    local img = self.atlas[name]
    local batch = love.graphics.newSpriteBatch(img, self.tw * self.th, "static")
    local quads = self.atlas.quads
    if not quads then
      quads = {}
      self.atlas.quads = quads
    end
    local m = self.maps[name]
    for ty = 0, self.th - 1 do
      for tx = 0, self.tw - 1 do
        local t = m[ty * self.tw + tx] or 0
        if t > 0 and t < 0x800 then
          local q = quads[t]
          if not q then
            q = love.graphics.newQuad((t % 32) * 16, math.floor(t / 32) * 16, 16, 16, 512, 1024)
            quads[t] = q
          end
          batch:add(q, tx * 16, ty * 16)
        end
      end
    end
    self.batches[name] = batch
  end
  self:buildAnimBatches()
  self.dirty = false
end

-- overlay batches for the BG tile animations: the cells whose metatile an
-- animation rewrites, drawn from that animation's packed frame atlas
function Room:buildAnimBatches()
  self.animBatches = {}
  local anims = self.atlas and self.atlas.anims
  if not anims then return end
  self.animState = self.animState or {}
  for ai, anim in ipairs(anims) do
    self.animState[ai] = self.animState[ai] or { frame = 1, timer = anim.timers[1] or 8 }
    for name, L in pairs(anim.layers) do
      local m = self.maps[name]
      local img = L.images[self.animState[ai].frame] or L.images[1]
      local batch
      for ty = 0, self.th - 1 do
        for tx = 0, self.tw - 1 do
          local t = m[ty * self.tw + tx]
          local s = t and L.slots[t]
          if s then
            batch = batch or love.graphics.newSpriteBatch(img, 256, "static")
            local q = love.graphics.newQuad((s % 32) * 16, math.floor(s / 32) * 16, 16, 16, 512, L.h)
            batch:add(q, tx * 16, ty * 16)
          end
        end
      end
      if batch then
        self.animBatches[#self.animBatches + 1] = { anim = ai, layer = name, batch = batch, images = L.images }
      end
    end
  end
end

-- UpdateBgAnimations: each animation counts down and steps to its next
-- frame (looping), one frame per tick
function Room:updateAnims()
  local anims = self.atlas and self.atlas.anims
  if not (anims and self.animState) then return end
  for ai, anim in ipairs(anims) do
    local st = self.animState[ai]
    if st then
      st.timer = st.timer - 1
      if st.timer <= 0 then
        st.frame = st.frame % #anim.timers + 1
        st.timer = anim.timers[st.frame] or 8
        for _, b in ipairs(self.animBatches or {}) do
          if b.anim == ai then b.batch:setTexture(b.images[st.frame] or b.images[1]) end
        end
      end
    end
  end
end

function Room:drawLayer(name, camX, camY)
  if self.dirty then self:buildBatches() end
  local b = self.batches[name]
  if b then love.graphics.draw(b, -math.floor(camX), -math.floor(camY)) end
  for _, ab in ipairs(self.animBatches or {}) do
    if ab.layer == name then love.graphics.draw(ab.batch, -math.floor(camX), -math.floor(camY)) end
  end
end

-- swap in a tileset manager's graphics (Assets:atlas `swap`); same
-- metatiles and collision, new pixels
function Room:applySwap(swap)
  local atlas = self.assets:atlas(self.area, self.maps.header.ts, swap)
  if atlas and atlas ~= self.atlas then
    self.atlas = atlas
    self:buildBatches()
  end
end

function Room:backdrop()
  return self.atlas and self.atlas.backdrop or { 0, 0, 0 }
end

-- ---------------------------------------------------------------------------
-- exits (src/scroll.c)
-- ---------------------------------------------------------------------------
-- area / area2 warps whose rectangle holds (x, y)
function Room:areaExitAt(x, y)
  for _, e in ipairs(self.exits) do
    if e.warpType == 1 or e.warpType == 3 then
      local s = SHAPE_HALF[e.shape] or SHAPE_HALF[0]
      if math.abs(x - e.startX) <= s[1] and math.abs(y - e.startY) <= s[2] then
        return e
      end
    end
  end
  return nil
end

-- border warps for leaving through edge `dir` (0 N, 1 E, 2 S, 3 W)
function Room:borderExit(dir, x, y)
  local mask
  if dir == 0 then mask = (self.width / 2 < x) and 0x02 or 0x01
  elseif dir == 1 then mask = (self.height / 2 < y) and 0x08 or 0x04
  elseif dir == 2 then mask = (self.width / 2 < x) and 0x20 or 0x10
  else mask = (self.height / 2 < y) and 0x80 or 0x40 end
  for _, e in ipairs(self.exits) do
    if (e.warpType == 0 or e.warpType == 2) and band(e.shape, mask) ~= 0 then return e end
  end
  return nil
end

return Room
