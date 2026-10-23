local M = {}
function M.new(root, version, api)
  local T = require("tests.modkit")
  require("src.core.GameVersion").set(version)
  local FE = require("src.core.game3.field_effects")
  local P = require("src.core.game3.player")
  local Bob = require("src.core.game3.surf_bob")
  local family = version == "emerald" and "rse" or "frlg"
  local file = assert(io.open(root .. "/tests/surf_mount_render/assets/" .. family .. ".png", "rb"))
  local bytes = file:read("*a")
  file:close()
  local image
  if love.getVersion then
    local fd = love.filesystem.newFileData(bytes, "fixture.png")
    local pixels = love.image.newImageData(fd)
    fd:release()
    image = love.graphics.newImage(pixels)
    pixels:release()
    image:setFilter("nearest", "nearest")
  else
    image = {}
  end
  local frames = family == "frlg" and 6 or 3
  local s = { image = image, quads = {}, fw = 32, fh = 32, frames = frames }
  for frame = 0, frames - 1 do
    s.quads[frame] = love.graphics.newQuad(0, frame * 32, 32, 32, 32, frames * 32)
  end
  FE._sheets = { surf_blob = s }
  FE._anims = {}
  FE._fx = nil
  FE._manifest = {
    family = family,
    _byName = {
      surf_blob = {
        anims = {
          { { "frame", 0, 48, false } },
          { { "frame", 1, 48, false } },
          { { "frame", 2, 48, false } },
          { { "frame", 2, 48, true } },
        },
      },
    },
  }
  local Objects = require("src.core.game3.objects")
  Objects._byId = {}
  Objects._order = {}
  Objects._bounds = { w = 8, h = 8 }
  Objects._mapId = "A"
  local f = { FE = FE, player = P, sheet = s, bytes = bytes, image = image }
  function f.setPhase(facing, tick)
    P.facing = facing
    P.surfing = true
    P.surfHopping = false
    P.dismounting = false
    P.underwater = false
    P.hidden = false
    P.px = 48
    P.py = 64
    P.cellX = 3
    P.cellY = 4
    P.targetX = 4
    P.targetY = 4
    P.elevation = 3
    local b = Bob.newBlob(family)
    b.dir = facing
    b.animClock = tick
    b.y2 = math.floor(tick / 8) % 3 - 1
    b.state = Bob.BOB_PLAYER_AND_MON
    FE._surfBob = b
    P.spriteYOffset = Bob.playerY2(b)
  end
  function f.drawNative(camera)
    FE.drawBehind(camera.x, camera.y)
  end
  dofile(root .. "/tools/surf-mount-render-check/gen1_reference.lua").install(require("src.mods.Loader"), f)
  local files = {}
  for _, name in ipairs({ "main.lua", "Mounts.lua", "manifest.json" }) do
    local file = assert(io.open(root .. "/examples/portable_surf_mounts/" .. name, "rb"))
    files["mods/surf_mount_reference/" .. name] = file:read("*a")
    file:close()
  end
  local Json = require("src.link.Json")
  local manifest = assert(Json.decode(files["mods/surf_mount_reference/manifest.json"]))
  manifest.api = api
  files["mods/surf_mount_reference/manifest.json"] = Json.encode(manifest)
  f.result = T.sdk.loadMods(
    { "mods/surf_mount_reference" },
    { data = T.fixtures.fresh(), fs = T.sdk.memfs(files) }
  )
  assert(#f.result.errors == 0, "generic consumer must load through real Gen1 Loader")
  f.setPhase("right", 0)
  return f
end
return M
