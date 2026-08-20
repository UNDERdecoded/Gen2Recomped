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
Data.sprites.SPRITE_KRIS = {
  id = "SPRITE_KRIS", image = "sprites/kris.png", frames = 6, walker = true,
}
Data.sprites.SPRITE_KRIS_BIKE = {
  id = "SPRITE_KRIS_BIKE", image = "sprites/kris_bike.png", frames = 6,
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

for _, id in ipairs({
    "SPRITE_RED", "SPRITE_RED_BIKE", "SPRITE_KRIS", "SPRITE_KRIS_BIKE",
  }) do
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

local function sourceFishingPose()
  local image = fakeImage(16, 8, { 1, 1, 1, 1 })
  -- A compact lower-body/rod pose: opaque shades exercise face, outfit,
  -- glove, trouser and shoe regions without embedding cartridge artwork.
  for y = 0, 7 do
    for x = 3, 12 do
      local edge = x == 3 or x == 12 or y == 7
      local shade = edge and 0 or (y % 2 == 0 and 1 / 3 or 2 / 3)
      image:setPixel(x, y, shade, shade, shade, 1)
    end
  end
  return image
end

local transform = assert(loadfile(MOD .. "/transforms.lua"))()
T.check(type(transform) == "function", "transforms.lua returns function(ctx)")

local written = {}
local ok, err = pcall(transform, {
  exists = function() return true end,
  readImage = function(rel)
    return rel:sub(1, 3) == "fx/" and sourceFishingPose() or sourceSheet()
  end,
  blank = function(w, h) return fakeImage(w, h) end,
  writeImage = function(image, rel) written[rel] = image end,
})
T.check(ok, "the transform runs in its restricted context (" .. tostring(err) .. ")")
T.check(written["sprites/chris.png"] ~= nil, "writes the walking sheet")
T.check(written["sprites/chrisbike.png"] ~= nil, "writes the bicycle sheet")
T.check(written["sprites/kris.png"] ~= nil, "writes the Crystal walking sheet")
T.check(written["sprites/kris_bike.png"] ~= nil,
  "writes the Crystal bicycle sheet")
for _, rel in ipairs({
    "fx/chris_fish_down.png", "fx/chris_fish_up.png",
    "fx/chris_fish_side.png", "fx/kris_fish_down.png",
    "fx/kris_fish_up.png", "fx/kris_fish_side.png",
  }) do
  T.check(written[rel] ~= nil, "writes " .. rel)
end

local walk = written["sprites/chris.png"]
local _, _, _, transparent = walk:getPixel(0, 0)
T.eq(transparent, 0, "OBJ colour 0 becomes transparent")
local rr, rg, rb, ra = walk:getPixel(6, 4)
T.check(ra == 1 and rr > rg and rr > rb, "cap region becomes opaque red")
local wr, wg, wb = walk:getPixel(7, 2)
T.check(wr > 0.6 and wg > 0.6 and wb > 0.6, "cap front receives its pale panel")
local sr, sg, sb = walk:getPixel(7, 7)
T.check(sr > sg and sg > sb, "face region receives a warm skin tone")

local function fingerprint(image)
  local count, sum = 0, 0
  for y = 0, 95 do
    for x = 0, 15 do
      local r, g, b, a = image:getPixel(x, y)
      if a > 0 then
        count = count + 1
        local value = math.floor(r * 255 + 0.5) * 65536
          + math.floor(g * 255 + 0.5) * 256
          + math.floor(b * 255 + 0.5)
        sum = (sum + value * (x + 1) * (y + 1)) % 9007199254740881
      end
    end
  end
  return count, sum
end

local walkCount, walkSum = fingerprint(written["sprites/chris.png"])
local bikeCount, bikeSum = fingerprint(written["sprites/chrisbike.png"])
T.eq(walkCount, 576, "boy walking transform keeps the 1.0.0 opaque mask")
T.eq(walkSum, 1391291369803,
  "boy walking transform is pixel-identical to 1.0.0")
T.eq(bikeCount, 576, "boy bicycle transform keeps the 1.0.0 opaque mask")
T.eq(bikeSum, 1498433350348,
  "boy bicycle transform is pixel-identical to 1.0.0")

local girl = written["sprites/kris.png"]
local hr, hg, hb = girl:getPixel(7, 2)
T.check(hr > hg and hg > hb, "Crystal heroine receives orange hair")
local fr, fg, fb = girl:getPixel(7, 5)
T.check(fr > fg and fg > fb, "Crystal heroine receives warm skin")
local yr, yg, yb = girl:getPixel(7, 10)
T.check(yr > yg and yg > yb, "Crystal heroine receives a yellow top")
local dr, dg, db = girl:getPixel(7, 13)
T.check(db > dr and dg > dr, "Crystal heroine receives denim-blue shorts")
local er, eg, eb = girl:getPixel(7, 14)
T.check(er > eg and er > eb, "Crystal heroine receives red shoes")
local tr, tg, tb = girl:getPixel(7, 16 + 10)
T.check(tg > tb and tb > tr, "Crystal heroine receives a teal backpack")

local boyFish = written["fx/chris_fish_down.png"]
local bfr, bfg, bfb = boyFish:getPixel(6, 3)
T.check(bfb > bfg and bfg > bfr,
  "boy fishing pose receives the blue jacket treatment")
local bsr, bsg, bsb = boyFish:getPixel(6, 5)
T.check(bsb > bsg and bsg > bsr,
  "boy fishing pose receives pale trouser shading")
local girlFish = written["fx/kris_fish_down.png"]
local gyr, gyg, gyb = girlFish:getPixel(6, 3)
T.check(gyr > gyg and gyg > gyb,
  "Crystal heroine fishing pose receives the yellow top treatment")
local gdr, gdg, gdb = girlFish:getPixel(6, 5)
T.check(gdb > gdr and gdg > gdr,
  "Crystal heroine fishing pose receives denim-blue shorts")

local missingGirlFish = {}
local missingOk, missingErr = pcall(transform, {
  exists = function(rel) return not rel:match("^fx/kris_fish_") end,
  readImage = function(rel)
    return rel:sub(1, 3) == "fx/" and sourceFishingPose() or sourceSheet()
  end,
  blank = function(w, h) return fakeImage(w, h) end,
  writeImage = function(_, rel) missingGirlFish[rel] = true end,
})
T.check(missingOk,
  "Gold/Silver run cleanly without Crystal fishing assets ("
    .. tostring(missingErr) .. ")")
T.eq(missingGirlFish["fx/kris_fish_down.png"], nil,
  "missing Crystal fishing poses are skipped")

run.release()
T.finish("indigo_97")
