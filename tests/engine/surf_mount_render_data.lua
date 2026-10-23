package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local f = dofile("tests/surf_mount_render/fixture.lua").new(".", "firered", 2)
local data = f.data
local function sample()
  return assert(data:surfMounts(1, "A"))
end
T.check(data:supportsSurfMounts(1), "generic surf mount contract")
T.eq(data:supportsSurfMounts("1"), false, "numeric schema")
T.eq(data:supportsSurfMounts(2), false, "future schema declines")
local m = sample().mounts[1]
T.eq(m.ownerId, "player", "joins body actor identity")
T.eq(m.layer, "actorUnderlay", "mount immediately before owner")
T.eq(m.draw.x, 40, "32px mount centered on rider cell")
T.eq(m.draw.y, 52, "mount sits 8px below body plus native screen bias")
T.eq(m.groundY, 80, "ground anchor independent from bob")
T.eq(m.frame, 4, "east starts on west facing row")
T.eq(m.flipX, true, "east mirrors west")
T.eq(f.player.bobTimer, 0, "snapshot does not advance live bob")
T.eq(select(1, f.counts()), 0, "snapshot has no IO")
T.eq(f.player.blobImage, nil, "snapshot does not allocate native image")
m.draw.y = 1000
T.eq(sample().mounts[1].draw.y, 52, "detached rows")
f.setPhase("right", 48)
T.eq(sample().mounts[1].frame, 5, "FRLG second frame at 48 ticks")
T.eq(sample().mounts[1].draw.y, 53, "mount follows rider bob")
T.eq(f.player.bobTimer, 16, "repeat reads preserve timer")
f.setPhase("up", 47)
T.eq(sample().mounts[1].frame, 2, "FRLG hold before boundary")
f.setPhase("up", 96)
T.eq(sample().mounts[1].frame, 2, "FRLG phase wraps")
f.world.map.def.mapType = "UNDERWATER"
T.eq(#sample().mounts, 0, "no surface mount underwater")
f.world.map.def.mapType = "TOWN"
for _, flag in ipairs({ "hidden", "invisible" }) do
  f.player[flag] = true
  T.eq(#sample().mounts, 0, "hidden rider suppresses mount")
  f.player[flag] = nil
end
f.player.surfing = false
T.eq(#sample().mounts, 0, "not surfing is empty")
T.eq(data:surfMountSheet(1, "A", "surf:player"), nil, "no arbitrary inactive source reads")
f.player.surfing = true
f.player.fishing = true
f.player.fishTiles = { up = {} }
T.eq(#sample().mounts, 0, "native multipart fishing returns before mount")
f.player.fishTiles = nil
T.eq(#sample().mounts, 1, "ordinary fishing still draws mount")
f.player.fishing = nil
f.world.flyAnim = {}
T.eq(data:surfMounts(1, "A"), nil, "fly presentation declines")
f.world.flyAnim = nil
f.player.spinning = true
f.player.spinTimer = 0
T.eq(sample().mounts[1].facing, "left", "posed facing, not logical facing")
T.eq(f.player.spinTimer, 0, "no live spin advancement")
f.player.spinning = nil
local image = assert(data:surfMountSheet(1, "A", "surf:player"))
T.eq(image.width, 32, "encoded image width")
T.eq(image.height, 192, "six FRLG frames")
T.eq(image.path, nil, "no private source path")
T.eq(image.graphicsState, "source", "source art, not live GPU readback")
T.eq(select(1, f.counts()), 1, "explicit bounded image read")
T.eq(select(2, f.counts()), 1, "stream closed")
for _, call in ipairs({
  function()
    return data:surfMounts(1, "stale")
  end,
  function()
    return data:surfMounts(1, {})
  end,
  function()
    return data:surfMountSheet(1, "A", "../secret")
  end,
}) do
  local v, why = call()
  T.eq(v, nil, "invalid query declines")
  T.check(type(why) == "string", "reason")
end
local d = f.game.data.constants.gen3SurfBlob
local path = d.image
for _, bad in ipairs({ "/etc/passwd", "../secret", "C:secret", "bad\\path" }) do
  d.image = bad
  T.eq(data:surfMountSheet(1, "A", "surf:player"), nil, "unsafe path declines")
end
d.image = path
f.files[path] = image.bytes:sub(1, 20)
T.eq(data:surfMountSheet(1, "A", "surf:player"), nil, "truncated source declines")
f.files[path] = image.bytes
local stream = f.result.loader.fs.newFile
f.result.loader.fs.newFile = function(p)
  local file = assert(stream(p))
  file.getSize = function()
    return 4194305
  end
  file.read = function()
    error("oversized source must not be read")
  end
  return file
end
T.eq(data:surfMountSheet(1, "A", "surf:player"), nil, "size checked before read")
f.result.loader.fs.newFile = function(p)
  local file = assert(stream(p))
  file.read = function()
    error("read failure")
  end
  return file
end
local _, closed = f.counts()
T.eq(data:surfMountSheet(1, "A", "surf:player"), nil, "read exception contained")
T.eq(select(2, f.counts()), closed + 1, "file closed on failure")
f.result.loader.fs.newFile = function(p)
  local file = assert(stream(p))
  local read = file.read
  file.read = function(...)
    f.world.map.id = "B"
    return read(...)
  end
  return file
end
T.eq(data:surfMountSheet(1, "A", "surf:player"), nil, "warp during IO declines")
f.world.map.id = "A"
f.result.loader.fs.newFile = function(p)
  local file = assert(stream(p))
  local read = file.read
  file.read = function(...)
    local replacement = {}
    for k, v in pairs(f.world.map) do
      replacement[k] = v
    end
    f.world.map = replacement
    return read(...)
  end
  return file
end
T.eq(data:surfMountSheet(1, "A", "surf:player"), nil, "same-id replacement during IO declines")
f.result.loader.fs.newFile = stream
local clock = love.timer.getTime
love.timer.getTime = nil
T.eq(data:surfMounts(1, "A"), nil, "FRLG missing time source declines")
love.timer.getTime = function()
  return 0 / 0
end
T.eq(data:surfMounts(1, "A"), nil, "invalid time source declines")
love.timer.getTime = clock
d.frames = 3
T.eq(sample().mounts[1].frame, 1, "RSE up uses its own three-frame row order")
love.timer.getTime = function()
  error("static RSE frame needs no host clock")
end
T.eq(sample().mounts[1].frame, 1, "RSE source independent from wall clock")
love.timer.getTime = clock
d.frames = 257
T.eq(data:surfMounts(1, "A"), nil, "bounded frame count")
d.frames = 6
local attach = require("src.mods.SurfMountRenderData").attach
local old = {
  actors = function()
    return "body"
  end,
  fieldEffects = function()
    return "effects"
  end,
}
local api = attach(
  { renderData = old },
  function()
    return f.game
  end,
  3,
  function()
    return image.bytes
  end,
  clock
)
T.eq(api.renderData, old, "existing handle preserved")
T.eq(old:actors(), "body", "actor contract preserved")
T.eq(old:fieldEffects(), "effects", "field effect contract preserved")
for _, gen in ipairs({ 1, 2, 4 }) do
  local a = attach({}, function()
    error("no game resolution for unsupported generation")
  end, gen, function() end)
  T.eq(a.renderData:supportsSurfMounts(1), false, "generation negotiation")
  T.eq(a.renderData:surfMounts(1, "A"), nil, "unsupported generation read")
end
local function plain(value)
  if type(value) ~= "table" then
    return type(value) ~= "function" and type(value) ~= "userdata"
  end
  if getmetatable(value) then
    return false
  end
  for key, entry in pairs(value) do
    if not plain(key) or not plain(entry) then
      return false
    end
  end
  return true
end
T.check(plain(sample()), "detached mount schema has no native handles/metatables/functions")
local inactive = attach({}, function()
  return {}
end, 3, function() end)
T.eq(inactive.renderData:surfMounts(1, "A"), nil, "no resident world")
local modern = 0
f.result.loader.fs.openFile = function(path, mode)
  modern = modern + 1
  T.eq(mode, "r", "LÖVE 12 open mode")
  return stream(path)
end
assert(data:surfMountSheet(1, "A", "surf:player"))
T.eq(modern, 1, "modern source stream preferred")
T.finish("Portable surf mount data")
