package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local f = dofile("tests/actor_render/fixture.lua").new(".", "firered", 2)
local data = f.data
T.check(data:supportsActors(1), "Gen3 actor contract")
T.eq(data:supportsActors("1"), false, "version must be numeric")
local scene = assert(data:actors(1, "A"))
T.eq(#scene.actors, 4, "player, active NPCs and resident ghost; hidden excluded")
local function player(s)
  for _, a in ipairs(s.actors) do
    if a.kind == "player" then
      return a
    end
  end
end
local p = player(scene)
T.eq(p.frame, 5, "right step uses source left step")
T.eq(p.flipX, true, "right faces east by flipping")
T.eq(p.draw.y, 24, "32px actor anchors at 16px cell bottom")
T.eq(p.groundY, 56, "ground anchor independent from sprite height")
T.eq(p.source.y, 160, "current source rectangle")
T.eq(select(1, f.counts()), 0, "snapshot performs no file reads")
local png = assert(data:actorSheet(1, "A", p.sheetId))
T.eq(png.width, 16, "sheet width")
T.eq(png.height, 288, "nine source frames")
T.eq(png.bytes:sub(1, 8), "\137PNG\r\n\26\n", "encoded image, not path or GPU handle")
T.eq(png.path, nil, "native path stays private")
T.eq(select(1, f.counts()), 1, "image query explicitly reads source")
p.draw.y = 999
scene.actors[1].id = "changed"
T.eq(player(assert(data:actors(1, "A"))).draw.y, 24, "detached observations")
f.player.running = true
T.eq(player(assert(data:actors(1, "A"))).sheetId, "sprite:RUN", "run sheet")
f.player.onBike = true
T.eq(player(assert(data:actors(1, "A"))).sheetId, "sprite:BIKE", "bike beats run")
f.player.surfing = true
f.player.bobTimer = 15
local bob = assert(data:actors(1, "A"))
T.eq(f.player.bobTimer, 15, "surf pose does not advance live bob")
T.eq(player(bob).sheetId, "sprite:SURF", "surf sheet")
T.eq(player(assert(data:actors(1, "A"))).draw.y, player(bob).draw.y, "repeated pose is stable")
f.player.spinning = true
f.player.spinTimer = 2
assert(data:actors(1, "A"))
T.eq(f.player.spinTimer, 2, "spin timer is observational")
f.player.spinning = nil
f.player.surfing = nil
f.player.onBike = nil
f.player.running = nil
f.player.fieldMove = true
f.player.fieldMovePose = 3
local pose = player(assert(data:actors(1, "A")))
T.eq(pose.sheetId, "sprite:POSE", "field-move source")
T.eq(pose.frame, 3, "field-move sequence instead of facing")
f.player.fieldMove = nil
f.npc.fixedFrame = 2
for _, a in ipairs(assert(data:actors(1, "A")).actors) do
  if a.localId == 1 and a.mapId == "A" then
    T.eq(a.frame, 2, "fixed NPC pose")
  end
end
f.npc.fixedFrame = nil
-- Real native draw rules remain the pose oracle, with its live clocks isolated.
local nativePlayer = require("src.world.Player")
for _, facing in ipairs({ "down", "up", "left", "right" }) do
  for _, clock in ipairs({ 0, 8, 16, 24 }) do
    f.player.facing = facing
    f.player.animClock = clock
    local row = player(assert(data:actors(1, "A")))
    local sprite, px, py, direction, phase, step = nativePlayer.pose(setmetatable({
      sprite = f.walk,
      px = f.player.px,
      py = f.player.py,
      facing = facing,
      animClock = clock,
      moving = true,
      isUnderwater = function()
        return false
      end,
    }, nativePlayer))
    local frame, flip = sprite:poseFrame(direction, phase, step)
    T.eq(row.frame, frame, "pose uses native frame rules")
    T.eq(row.flipX, flip, "pose uses native flip rules")
  end
end
f.player.facing = "right"
f.player.animClock = 8
f.player.hopFrames = 16
f.player.hopTotal = 32
T.eq(player(assert(data:actors(1, "A"))).draw.y, 14, "hop draw is lifted")
T.eq(player(assert(data:actors(1, "A"))).groundY, 56, "hop contact stays grounded")
f.player.hopFrames = nil
f.world.map.def.mapType = "UNDERWATER"
f.player.underwaterSprite = f.bike
T.eq(player(assert(data:actors(1, "A"))).sheetId, "sprite:BIKE", "underwater source from resident map")
f.world.map.def.mapType = "TOWN"
local pngFile = assert(io.open("tests/actor_render/assets/gen2.png", "rb"))
local encoded = pngFile:read("*a")
pngFile:close()
local originalPath = f.walk.def.image
f.walk.def.image = "assets/generated/actor-test.png"
f.files["mods/actor_reference/overrides/actor-test.png"] = encoded
local fsInfo = love.filesystem.getInfo
love.filesystem.getInfo = f.result.loader.fs.getInfo
T.eq(assert(data:actorSheet(1, "A", "sprite:AVATAR")).bytes, encoded, "native asset override resolution")
love.filesystem.getInfo = fsInfo
f.walk.def.image = "../private.png"
T.eq(data:actorSheet(1, "A", "sprite:AVATAR"), nil, "declared traversal path rejected")
f.walk.def.image = originalPath
local Sprite = require("src.render.SpriteRenderer")
local savedSprite = f.npc.sprite
f.npc.sprite = Sprite.new({
  id = "STILL",
  image = "tests/actor_render/assets/fixed.png",
  trueColor = true,
  gen3ObjectEvent = true,
  frames = 1,
  frameWidth = 16,
  frameHeight = 32,
})
for _, a in ipairs(assert(data:actors(1, "A")).actors) do
  if a.localId == 1 and a.mapId == "A" then
    T.eq(a.frame, 0, "single-frame object stays still")
    T.eq(a.flipX, false, "single-frame object does not turn with facing")
  end
end
f.npc.sprite = savedSprite
f.world.flyAnim = {}
T.eq(data:actors(1, "A"), nil, "fly presentation cannot masquerade as an ordinary player")
f.world.flyAnim = nil
local draw, random = love.graphics.draw, math.random
love.graphics.draw = function()
  error("read must not draw")
end
math.random = function()
  error("read must not consume RNG")
end
local beforeGame = package.loaded["src.core.Game"]
assert(data:actors(1, "A"))
assert(data:actorSheet(1, "A", "sprite:AVATAR"))
T.eq(package.loaded["src.core.Game"], beforeGame, "reads do not bootstrap Game")
love.graphics.draw, math.random = draw, random
local stream = f.result.loader.fs.newFile
f.result.loader.fs.newFile = function(path)
  f.world.map.id = "B"
  return stream(path)
end
T.eq(data:actorSheet(1, "A", "sprite:AVATAR"), nil, "stale world during file observation declines")
f.world.map.id = "A"
f.result.loader.fs.newFile = stream
-- LÖVE 12 opens the file directly; preserve an active version-cache shim.
local originalFs = f.result.loader.fs
local cache = package.loaded["src.import.CacheFs"]
local oldOpen, oldNew = love.filesystem.openFile, love.filesystem.newFile
f.files["qa-prefix/" .. f.walk.def.image] = encoded
package.loaded["src.import.CacheFs"] = {
  _redirect = function(path)
    return "qa-prefix/" .. path
  end,
}
love.filesystem.openFile = function(path, mode)
  T.eq(mode, "r", "modern stream opens read-only")
  T.eq(path, "qa-prefix/" .. f.walk.def.image, "modern reader honors version cache")
  local file = assert(stream(path))
  file.open = function()
    error("modern file is already open")
  end
  return file
end
love.filesystem.newFile = function()
  error("deprecated stream must not be used")
end
f.result.loader.fs = love.filesystem
T.eq(assert(data:actorSheet(1, "A", "sprite:AVATAR")).bytes, encoded, "modern streaming path")
f.result.loader.fs = originalFs
love.filesystem.openFile, love.filesystem.newFile = oldOpen, oldNew
package.loaded["src.import.CacheFs"] = cache
local before = f.world.entities[1]
assert(data:actors(1, "A"))
T.eq(f.world.entities[1], before, "native array not sorted")
f.player.hidden = true
T.eq(#assert(data:actors(1, "A")).actors, 3, "hidden player")
T.eq(data:actorSheet(1, "A", "sprite:RUN"), nil, "unselected sheet is not public")
f.player.hidden = nil
T.eq(data:actors(1, "B"), nil, "stale map")
T.eq(data:actors(2, "A"), nil, "unknown actor version")
T.eq(data:actorSheet(1, "A", "../save"), nil, "IDs do not resolve paths")
local path = f.walk.def.image
f.files[path] = "bad"
T.eq(data:actorSheet(1, "A", "sprite:AVATAR"), nil, "corrupt PNG source declines")
f.files[path] = string.rep("x", 4194305)
local reads = f.counts()
T.eq(data:actorSheet(1, "A", "sprite:AVATAR"), nil, "oversize source declines")
T.eq(f.counts(), reads, "oversize source never read")
f.files[path] = nil
f.npc.hidden = nil
f.npc.facing = function() end
T.eq(data:actors(1, "A"), nil, "invalid runtime state has no partial scene or functions")
f.npc.facing = "right"
local ghost = assert(data:actors(1, "A")).actors[1]
T.eq(ghost.mapId, "B", "neighbor source map")
T.eq(ghost.x, -32, "neighbor pixel offset")
f.world.ghosts[2] = { npc = f.ghost, nb = f.world.ghosts[1].nb, ox = 32, oy = 16 }
T.eq(#assert(data:actors(1, "A")).actors, 5, "same object at distinct placements is retained")
local many = {}
for i = 1, 257 do
  many[i] = f.npc
end
f.world.entities = many
T.eq(data:actors(1, "A"), nil, "bounded actor inspection")
f.world.entities = {}
f.game.overworld = nil
f.game.stack.states = {}
T.eq(data:actors(1, "A"), nil, "title has no world")
local attach = require("src.mods.ActorRenderData").attach
local legacy = { renderData = {
  supports = function()
    return "terrain"
  end,
} }
attach(
  legacy,
  function()
    return f.game
  end,
  1,
  function()
    error("no read")
  end
)
T.eq(legacy.renderData.supports(), "terrain", "terrain methods retained when composed")
T.eq(legacy.renderData:supportsActors(1), false, "unsupported generation")
local empty = attach({}, function()
  return true
end, 3, function() end).renderData
T.eq(empty:actors(1, "A"), nil, "partially bootstrapped Game is not loaded")
T.eq(legacy.renderData:actors(1, "A"), nil, "unsupported generation refuses reads")
T.finish("Portable actor render data")
