-- Standalone from the Gen2Recomped repository root:
--   luajit mods/examples/indigo_97/tests/indigo_97_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
Data.sprites.SPRITE_RED = {
  id = "SPRITE_RED", image = "sprites/chris.png", frames = 6, walker = true,
}
Data.sprites.SPRITE_RED_BIKE = {
  id = "SPRITE_RED_BIKE", image = "sprites/chrisbike.png", frames = 6,
}

local MOD = "mods/examples/indigo_97"

local function noCacheFs()
  local inner = T.fs.new(".")
  local overlay = {}
  local mount = "mods/indigo_97"

  local function map(path)
    if path == mount then return MOD end
    if path and path:sub(1, #mount + 1) == mount .. "/" then
      return MOD .. path:sub(#mount + 1)
    end
    return path
  end

  local fs = { root = inner.root }
  function fs.read(path)
    if path:sub(1, 17) == "assets/generated/" then return nil end
    return overlay[path] or inner.read(map(path))
  end
  function fs.write(path, body) overlay[path] = body return true end
  function fs.createDirectory() return true end
  function fs.load(path) return inner.load(map(path)) end
  function fs.getInfo(path)
    if path == "mods" then return { type = "directory" } end
    if path:sub(1, 17) == "assets/generated/" then return nil end
    if overlay[path] then return { type = "file" } end
    return inner.getInfo(map(path))
  end
  function fs.getDirectoryItems(path)
    if path == "mods" then return { "indigo_97" } end
    return inner.getDirectoryItems(map(path))
  end
  return fs
end

local run = T.sdk.loadMod("mods/indigo_97", { data = Data, fs = noCacheFs() })
T.eq(#run.errors, 0,
  "loads clean with no imported cache (" .. tostring(run.errors[1]) .. ")")
T.eq(run.mod and run.mod.manifest.assets_transforms, "transforms.lua",
  "declares the ROM-safe asset transform")

for _, id in ipairs({ "SPRITE_RED", "SPRITE_RED_BIKE" }) do
  local sprite = Data.sprites[id]
  T.check(sprite ~= nil, id .. " remains registered")
  T.eq(sprite.trueColor, true, id .. " opts out of the world shade remap")
  T.check(sprite.image ~= nil and sprite.image ~= "", id .. " keeps its source path")
end

local function fakeImage(width, height, initial)
  local data = {}
  local image = {}
  local function key(x, y) return y * width + x end
  function image:getDimensions() return width, height end
  function image:getPixel(x, y)
    local p = data[key(x, y)] or initial or { 0, 0, 0, 0 }
    return p[1], p[2], p[3], p[4]
  end
  function image:setPixel(x, y, r, g, b, a)
    data[key(x, y)] = { r, g, b, a }
  end
  return image
end

local function sourceSheet()
  local image = fakeImage(16, 96, { 1, 1, 1, 1 })
  -- A simple opaque figure in every frame exercises transparency, region
  -- colours and all six direction/step slots without carrying game artwork.
  for frame = 0, 5 do
    local fy = frame * 16
    for y = 0, 15 do
      for x = 5, 10 do
        local shade = (x == 5 or x == 10 or y == 0 or y == 15) and 0 or 1 / 3
        image:setPixel(x, fy + y, shade, shade, shade, 1)
      end
    end
    image:setPixel(5, fy, 0, 0, 0, 1)
    image:setPixel(7, fy + 7, 2 / 3, 2 / 3, 2 / 3, 1)
  end
  return image
end

local transform = assert(loadfile(MOD .. "/transforms.lua"))()
T.check(type(transform) == "function", "transforms.lua returns function(ctx)")

local written = {}
local ok, err = pcall(transform, {
  exists = function() return true end,
  readImage = function() return sourceSheet() end,
  blank = function(w, h) return fakeImage(w, h) end,
  writeImage = function(image, rel) written[rel] = image end,
})
T.check(ok, "the transform runs in its restricted context (" .. tostring(err) .. ")")
T.check(written["sprites/chris.png"] ~= nil, "writes the walking sheet")
T.check(written["sprites/chrisbike.png"] ~= nil, "writes the bicycle sheet")

local walk = written["sprites/chris.png"]
local _, _, _, transparent = walk:getPixel(0, 0)
T.eq(transparent, 0, "OBJ colour 0 becomes transparent")
local rr, rg, rb, ra = walk:getPixel(6, 4)
T.check(ra == 1 and rr > rg and rr > rb, "cap region becomes opaque red")
local wr, wg, wb = walk:getPixel(7, 2)
T.check(wr > 0.6 and wg > 0.6 and wb > 0.6, "cap front receives its pale panel")
local sr, sg, sb = walk:getPixel(7, 7)
T.check(sr > sg and sg > sb, "face region receives a warm skin tone")

run.release()
T.finish("indigo_97")

