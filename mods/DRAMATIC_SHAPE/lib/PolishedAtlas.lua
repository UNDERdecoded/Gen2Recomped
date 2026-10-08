-- Polished's outdoor atlases reserve nine slots for map-group roof artwork.
-- Shape carving needs those grayscale texels, not the blank reserved slots.
local Assets = require('src.render.Assets')
local Version = require('src.core.GameVersion')
local Atlas = {}
local cache = {}
function Atlas.forMap(map)
  if Version.get() ~= 'polishedcrystal' or not map then return nil end
  local Game = require('src.core.Game')
  local roofs = Game.data and Game.data.field and Game.data.field.gen2Roofs
  local ts = map.tileset
  if not (roofs and ts and roofs.tilesets and roofs.tilesets[ts.id]) then return nil end
  local group = map.def and map.def.group or map.group
  local id = roofs.byGroup and roofs.byGroup[group]
  local image = id ~= nil and roofs.images and roofs.images[id]
  if not image then return nil end
  local key = ts.image .. ':' .. image
  if cache[key] ~= nil then return cache[key] or nil end
  local ok, out = pcall(function()
    local raw, strip = Assets.imageData(ts.image), Assets.imageData(image)
    local w, h = raw:getDimensions()
    local copy = love.image.newImageData(w, h)
    copy:paste(raw, 0, 0, 0, 0, w, h)
    local perRow = ts.tilesPerRow or w / 8
    for n = 0, (roofs.count or 9) - 1 do
      local tile = (roofs.slot or 10) + n
      copy:paste(strip, tile % perRow * 8, math.floor(tile / perRow) * 8,
                 n * 8, 0, 8, 8)
    end
    for tile,variant in pairs(ts.tileVariants or {})do
      local slot,count=roofs.slot or 10,roofs.count or 9
      if variant.base>=slot and variant.base<slot+count then
        local sx,sy=variant.base%perRow*8,math.floor(variant.base/perRow)*8
        local dx,dy=tile%perRow*8,math.floor(tile/perRow)*8
        for y=0,7 do for x=0,7 do
          copy:setPixel(dx+x,dy+y,copy:getPixel(sx+(variant.flipX and 7-x or x),sy+(variant.flipY and 7-y or y)))
        end end
      end
    end
    return copy
  end)
  cache[key] = ok and out or false
  return cache[key] or nil
end
function Atlas.invalidate() cache = {} end
Assets.register(Atlas.invalidate)
return Atlas
