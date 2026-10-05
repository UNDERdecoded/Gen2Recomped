-- THE SUPER CONTEST'S PICTURES, AT RUN TIME: the images the importer composed
-- from contest_bg / contest_obj (src/import/Gen4ContestArt.lua), looked up in
-- the cache module `gen4_contest_art`.
--
-- `draw` puts a background at its top-left and a SPRITE (an entry with an
-- origin) at the point the cartridge positions it by -- the sprite's centre,
-- as SpriteTemplate x/y are -- so the coordinates in the screens are the
-- overlay's own numbers.

local Assets = require("src.render.Assets")

local Art = {}

local images, quads = {}, {}

local function entry(game, key)
  local index = game and game.data and game.data.gen4_contest_art
  return index and index[key]
end

function Art.available(game)
  return entry(game, "acting_stage") ~= nil
end

function Art.image(game, key)
  local rec = entry(game, key)
  local path = type(rec) == "table" and rec.path or rec
  if not path then return nil end
  if images[path] == nil then
    local ok, img = pcall(Assets.image, path)
    images[path] = ok and img or false
  end
  return images[path] or nil, rec
end

function Art.draw(game, key, x, y)
  local img, rec = Art.image(game, key)
  if not img then return false end
  local ox = type(rec) == "table" and rec.originX or 0
  local oy = type(rec) == "table" and rec.originY or 0
  love.graphics.draw(img, (x or 0) + ox, (y or 0) + oy)
  return true
end

-- part of a background: the 256x192 window of a 512x256 BG, a button out of
-- a full-screen map
function Art.drawRegion(game, key, sx, sy, w, h, x, y)
  local img = Art.image(game, key)
  if not img then return false end
  local id = key .. ":" .. sx .. "," .. sy .. "," .. w .. "," .. h
  local q = quads[id]
  if not q then
    q = love.graphics.newQuad(sx, sy, w, h, img:getDimensions())
    quads[id] = q
  end
  love.graphics.draw(img, q, x or sx, y or sy)
  return true
end

return Art
