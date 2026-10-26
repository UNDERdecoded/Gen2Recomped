package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local f = dofile("tests/field_effect_render/fixture.lua").new(".", "firered", 2)
local data = f.data
T.check(data:supportsFieldEffects(1), "Gen3 contract")
for _, k in ipairs({ "grass", "ripple", "sparkle" }) do
  T.check(data:supportsFieldEffects(1, k), k .. " supported")
end
T.eq(data:supportsFieldEffects("1"), false, "numeric version")
T.eq(data:supportsFieldEffects(2), false, "future version")
T.eq(data:supportsFieldEffects(1, "fly"), false, "no implied complete field support")
local function sample()
  return assert(data:fieldEffects(1, "A"))
end
local s = sample()
T.eq(s.coverage, "subset", "honest coverage")
T.eq(#s.effects, 5, "ripple, sparkle, three grass overlays")
T.eq(s.effects[1].layer, "ground", "ripples before actors")
T.eq(s.effects[1].terrainOcclusion, "reflectionCover", "terrain cover obligation")
T.eq(s.effects[1].draw.y, 38, "legacy fixed-frame bias cancelled")
T.eq(s.effects[2].layer, "front", "sparkle front pass")
T.eq(s.effects[3].ownerId, "player", "grass bound to owner")
T.eq(s.effects[3].frame, 4, "standing grass settled")
T.eq(s.effects[4].frame, 2, "entering rustle from movement progress")
T.eq(s.effects[5].ownerId, "npc:1:A:7:0:0", "same owner identity as actor contract")
T.eq(select(1, f.counts()), 0, "snapshot has no IO")
T.eq(f.world.map.def._blockArray, nil, "no lazy layout hydration")
T.eq(f.world._rippleSprite, nil, "no lazy sprite allocation")
T.eq(f.world._sparkleSprite, nil, "no sparkle allocation")
local function plain(v)
  if type(v) ~= "table" then
    return type(v) ~= "function" and type(v) ~= "userdata"
  end
  if getmetatable(v) then
    return false
  end
  for k, x in pairs(v) do
    if not plain(k) or not plain(x) then
      return false
    end
  end
  return true
end
T.check(plain(s), "only plain detached data")
s.effects[1].draw.y = 999
s.supportedKinds[1] = "changed"
T.eq(sample().effects[1].draw.y, 38, "deep detached rows")
T.eq(sample().supportedKinds[1], "grass", "detached capabilities")
f.world.ripples[1].clock = 4
T.eq(sample().effects[1].frame, 2, "hold boundary")
f.world.ripples[1].clock = 99
T.eq(sample().effects[1].frame, 4, "native final ripple frame")
f.world.sparkles[1].clock = 15
T.eq(#sample().effects, 4, "sparkle invisible during linger")
T.eq(f.world.sparkles[1].clock, 15, "reader never advances clock")
f.world.sparkles[1].clock = 0
f.player.hidden = true
T.eq(#sample().effects, 3, "hidden player grass suppressed")
f.player.hidden = nil
f.world.map.blockPatch[27] = 0 -- player's standing cell
T.eq(#sample().effects, 4, "runtime block patches win")
f.world.map.blockPatch[27] = nil
f.world.map.collisionPatch[27] = 1
T.eq(#sample().effects, 4, "runtime collision patches win")
f.world.map.collisionPatch[27] = nil
f.player.cellX = -1
T.eq(#sample().effects, 4, "off-map source cell has no grass")
f.player.cellX = 2
f.player.progress = 16
T.eq(sample().effects[4].frame, 4, "rustle clamped at end")
f.player.progress = 8
for _, call in ipairs({
  function()
    return data:fieldEffects(0, "A")
  end,
  function()
    return data:fieldEffects(1, "stale")
  end,
  function()
    return data:fieldEffects(1, {})
  end,
  function()
    return data:fieldEffectSheet(1, "A", "../../secret")
  end,
}) do
  local value, reason = call()
  T.eq(value, nil, "invalid query declines")
  T.check(type(reason) == "string", "reason")
end
local image = assert(data:fieldEffectSheet(1, "A", "field:ripple"))
T.eq(image.graphicsState, "source", "source art, no live palette claim")
T.eq(image.path, nil, "no private paths")
T.eq(image.width, 16, "PNG width")
T.eq(image.height, 80, "PNG frames")
T.eq(select(1, f.counts()), 1, "explicit source IO")
T.eq(select(2, f.counts()), 1, "file closed")
T.check(plain(image), "encoded bytes, no GPU object")
local c = f.game.data.constants
local order = c.gen3Ripple.order
c.gen3Ripple.order = { { frame = 7, hold = 3 } }
T.eq(data:fieldEffects(1, "A"), nil, "invalid visible frame fails atomically")
c.gen3Ripple.order = { { frame = 1, hold = 0 } }
T.eq(data:fieldEffects(1, "A"), nil, "zero hold rejected")
c.gen3Ripple.order = order
local grass = c.gen3TallGrass
c.gen3TallGrass = nil
T.eq(data:fieldEffects(1, "A"), nil, "missing visible grass art fails atomically")
c.gen3TallGrass = grass
local d = f.game.data.sprites.RIPPLE
local path = d.image
for _, bad in ipairs({ "/etc/passwd", "../secret", "C:secret", "bad\\path" }) do
  d.image = bad
  T.eq(data:fieldEffectSheet(1, "A", "field:ripple"), nil, "unsafe source path rejected")
end
d.image = path
local bytes = image.bytes
for _, bad in ipairs({ "bad", bytes:sub(1, 20), bytes:sub(1, 19) .. "\17" .. bytes:sub(21) }) do
  f.files[path] = bad
  T.eq(data:fieldEffectSheet(1, "A", "field:ripple"), nil, "corrupt or wrong geometry rejected")
end
f.files[path] = bytes
local old = f.result.loader.fs.newFile
f.result.loader.fs.newFile = function(p)
  local file = assert(old(p))
  file.getSize = function()
    return 4194305
  end
  file.read = function()
    error("must not read oversized file")
  end
  return file
end
T.eq(data:fieldEffectSheet(1, "A", "field:ripple"), nil, "oversized image rejected before read")
f.result.loader.fs.newFile = function(p)
  local file = assert(old(p))
  file.read = function()
    error("read failure")
  end
  return file
end
local _, closed = f.counts()
T.eq(data:fieldEffectSheet(1, "A", "field:ripple"), nil, "file exception contained")
T.eq(select(2, f.counts()), closed + 1, "file closed after read exception")
f.result.loader.fs.newFile = function(p)
  local file = assert(old(p))
  local read = file.read
  file.read = function(...)
    f.world.map.id = "B"
    return read(...)
  end
  return file
end
T.eq(data:fieldEffectSheet(1, "A", "field:ripple"), nil, "map changes during IO rejected")
f.world.map.id = "A"
f.result.loader.fs.newFile = function(p)
  local file = assert(old(p))
  local read = file.read
  file.read = function(...)
    local replacement = {}
    for k, v in pairs(f.world.map) do
      replacement[k] = v
    end
    f.world.map = setmetatable(replacement, getmetatable(f.world.map))
    return read(...)
  end
  return file
end
T.eq(data:fieldEffectSheet(1, "A", "field:ripple"), nil, "same-id map replacement during IO rejected")
f.result.loader.fs.newFile = old
local modern = 0
f.result.loader.fs.openFile = function(p, mode)
  modern = modern + 1
  T.eq(mode, "r", "modern open mode")
  return old(p)
end
assert(data:fieldEffectSheet(1, "A", "field:ripple"))
T.eq(modern, 1, "LÖVE 12 stream preferred")
-- Defensive limits and read-only failure paths.
local live = f.world.ripples
f.world.ripples = {}
for i = 1, 257 do
  f.world.ripples[i] = live[1]
end
T.eq(data:fieldEffects(1, "A"), nil, "input effect cap")
f.world.ripples = live
local savedX = live[1].px
live[1].px = 0 / 0
T.eq(data:fieldEffects(1, "A"), nil, "nonfinite position")
live[1].px = savedX
local savedFrames = d.frames
d.frames = 257
T.eq(data:fieldEffects(1, "A"), nil, "frame count cap")
d.frames = savedFrames
f.world.flyAnim = {}
T.eq(data:fieldEffects(1, "A"), nil, "fly presentation declines instead of inventing grass")
f.world.flyAnim = nil
local sources = { f.world.ripples, f.world.sparkles, f.world.entities }
f.world.ripples = {}
f.world.sparkles = {}
f.world.entities = {}
T.eq(#sample().effects, 0, "empty scene is valid")
T.eq(data:fieldEffectSheet(1, "A", "field:ripple"), nil, "expired source cannot be requested")
f.world.ripples, f.world.sparkles, f.world.entities = unpack(sources)
f.npc.berryTreeId = 1
T.eq(data:fieldEffects(1, "A"), nil, "unresolved berry visibility declines")
f.npc.berryTreeId = nil
local attach = require("src.mods.FieldEffectRenderData").attach
local existing = {
  supports = function()
    return "terrain"
  end,
  actors = function()
    return "actors"
  end,
}
local api = { renderData = existing }
attach(
  api,
  function()
    return f.game
  end,
  3,
  function()
    return bytes
  end
)
T.eq(api.renderData, existing, "extends existing terrain and actor handle")
T.eq(existing:supports(), "terrain", "terrain preserved")
T.eq(existing:actors(), "actors", "actors preserved")
for _, gen in ipairs({ 1, 2, 4 }) do
  local a = attach(
    {},
    function()
      error("unsupported generation must not resolve game")
    end,
    gen,
    function()
      error("no IO")
    end
  )
  T.eq(a.renderData:supportsFieldEffects(1), false, "generation gate")
  T.eq(a.renderData:fieldEffects(1, "A"), nil, "unsupported data read")
end
local a = attach({}, function()
  return {}
end, 3, function() end)
T.eq(a.renderData:fieldEffects(1, "A"), nil, "no overworld")
T.finish("Portable field effect render data")
