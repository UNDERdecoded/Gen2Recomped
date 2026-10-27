-- Legacy decoded 16px layout contract. These are mod-owned layouts,
-- not aliases to the shared native Map or its two-bit collision grid.
-- coll here is the old classified COLL_* byte; it is not raw GBA collision.
local Layout = {}
Layout.__index = Layout

function Layout.fromDecoded(decoded, mapId, pair, blob)
  local layout = setmetatable({
    mapId = mapId, pair = pair or "sevii_outdoor",
    width = decoded.width or 0, height = decoded.height or 0,
    trueWidth = decoded.trueWidth or decoded.width or 0,
    trueHeight = decoded.trueHeight or decoded.height or 0,
    borderWidth = decoded.borderWidth or 1, borderHeight = decoded.borderHeight or 1,
    borderMids = decoded.borderMids or { 0 }, cells = decoded.cells or {},
    overrides = {}, _revision = 0,
  }, Layout)
  if blob then
    layout._workerSource = {
      blob = blob, cells = decoded.cells, width = decoded.width, height = decoded.height,
      trueWidth = decoded.trueWidth or decoded.width, trueHeight = decoded.trueHeight or decoded.height,
    }
  end
  return layout
end

local function outside(layout, x, y)
  return x < 0 or y < 0 or x >= (layout.trueWidth or layout.width)
    or y >= (layout.trueHeight or layout.height)
end
local function borderMid(layout, x, y)
  return layout.borderMids[(y % layout.borderHeight) * layout.borderWidth + x % layout.borderWidth + 1] or 0
end
function Layout:cellAt(x, y)
  local row = self.overrides[y * 1024 + x]
  if row then return row end
  if outside(self, x, y) then return { mid = borderMid(self, x, y), coll = 255, elev = 0 } end
  return self.cells[y * self.width + x + 1] or { mid = 0, coll = 255, elev = 0 }
end
local baseCellAt = Layout.cellAt
local function field(layout, x, y, key, missing, border)
  if layout.cellAt ~= baseCellAt then return layout:cellAt(x, y)[key] end
  local row = layout.overrides[y * 1024 + x]
  if row then return row[key] end
  if outside(layout, x, y) then
    if border ~= nil then return border end
    return borderMid(layout, x, y)
  end
  row = layout.cells[y * layout.width + x + 1]
  if row then return row[key] end
  return missing
end
function Layout:midAt(x, y) return field(self, x, y, "mid", 0) end
function Layout:collAt(x, y) return field(self, x, y, "coll", 255, 255) end
function Layout:elevAt(x, y) return field(self, x, y, "elev", 0, 0) end

function Layout:collArray()
  if self.width * self.height <= 0 then return nil end
  local out = {}
  for y = 0, self.height - 1 do
    for x = 0, self.width - 1 do
      local i = y * self.width + x + 1
      local override, row = self.overrides[y * 1024 + x], self.cells[i]
      -- Padding stays blocked even if a caller stored an outside override.
      out[i] = not outside(self, x, y) and (override and override.coll or row and row.coll or 255) or 255
    end
  end
  return out
end

local function invalidate(layout, coordinates)
  local view = package.loaded["src.core.game3.field_view"]
  if not view then return end
  if coordinates and #coordinates <= 128 and view.invalidateLayoutCell then
    for i = 1, #coordinates, 2 do view.invalidateLayoutCell(layout, coordinates[i], coordinates[i + 1]) end
  else view._nativeDirty = true end
end
function Layout:applyOverride(x, y, mid, coll, elev)
  self._revision = (self._revision or 0) + 1
  x, y = tonumber(x) or 0, tonumber(y) or 0
  self.overrides[y * 1024 + x] = { mid = tonumber(mid) or 0, coll = coll ~= nil and coll or 255, elev = elev or 0 }
  invalidate(self, { x, y })
end
function Layout:setMetatiles(rows)
  local coordinates = {}
  for _, row in ipairs(rows or {}) do
    local x, y = tonumber(row.x) or 0, tonumber(row.y) or 0
    local before = self:cellAt(x, y)
    self.overrides[y * 1024 + x] = {
      mid = tonumber(row.mid) or before.mid or 0,
      coll = row.coll ~= nil and row.coll or before.coll,
      elev = row.elev ~= nil and row.elev or before.elev or 0,
    }
    coordinates[#coordinates + 1] = x; coordinates[#coordinates + 1] = y
  end
  if #coordinates > 0 then self._revision = (self._revision or 0) + 1; invalidate(self, coordinates) end
  return #coordinates / 2
end
function Layout:stamp(source, ox, oy)
  if type(source) ~= "table" or type(source.cells) ~= "table" then return 0 end
  ox, oy = tonumber(ox) or 0, tonumber(oy) or 0
  local count = 0
  for y = 0, (source.trueHeight or source.height or 0) - 1 do
    for x = 0, (source.trueWidth or source.width or 0) - 1 do
      local row = source.cells[y * source.width + x + 1]
      if row then
        self.overrides[(oy + y) * 1024 + ox + x] = { mid = row.mid or 0, coll = row.coll ~= nil and row.coll or 255, elev = row.elev or 0 }
        count = count + 1
      end
    end
  end
  invalidate(self)
  if count > 0 then self._revision = (self._revision or 0) + 1 end
  return count
end
function Layout:clearOverrides()
  if next(self.overrides) then self.overrides = {}; self._revision = (self._revision or 0) + 1 end
  invalidate(self)
end

function Layout:workerPacked()
  local source = self._workerSource
  if not source or self.cells ~= source.cells or self.width ~= source.width or self.height ~= source.height
    or self.trueWidth ~= source.trueWidth or self.trueHeight ~= source.trueHeight
    or self.cellAt ~= baseCellAt or self.midAt ~= Layout.midAt then return nil end
  local assets = package.loaded["src.render.Assets"]
  if assets and assets.loader and #assets.loader:overrideOrder() > 0 then return nil end
  local overrides, borders = {}, {}
  for key, row in pairs(self.overrides) do overrides[key] = { mid = row.mid } end
  for i = 1, self.borderWidth * self.borderHeight do borders[i] = self.borderMids[i] end
  return { blob = source.blob, off = 17 + source.blob:byte(15) * source.blob:byte(16) * 2,
    width = self.width, trueWidth = self.trueWidth, trueHeight = self.trueHeight,
    borderWidth = self.borderWidth, borderHeight = self.borderHeight, borderMids = borders, overrides = overrides }
end
return Layout
