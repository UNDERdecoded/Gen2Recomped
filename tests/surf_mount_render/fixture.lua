local M = {}
function M.new(root, version, api)
  local T = require("tests.modkit")
  require("src.core.GameVersion").set(version)
  local P = require("src.world.Player")
  local Sprite = require("src.render.SpriteRenderer")
  local rider = {
    id = "RIDER",
    image = "tests/surf_mount_render/assets/rider.png",
    trueColor = true,
    gen3ObjectEvent = true,
    frameWidth = 16,
    frameHeight = 32,
    frames = 9,
  }
  local sprite = Sprite.new(rider)
  local p = setmetatable({
    sprite = sprite,
    surfSprite = sprite,
    fieldMoveSprite = sprite,
    surfing = true,
    px = 48,
    py = 64,
    cellX = 3,
    cellY = 4,
    animClock = 8,
    progress = 8,
    stepFrames = 16,
    elevation = 3,
    facing = "right",
    bobTimer = 0,
    turnTimer = 0,
    moving = false,
  }, P)
  local ow = {
    isOverworld = true,
    map = { id = "A", def = { mapType = "TOWN" } },
    player = p,
    entities = { p },
    ghosts = {},
  }
  local game = { data = T.fixtures.fresh(), overworld = ow, stack = { states = { ow } } }
  local family = version == "emerald" and "rse" or "frlg"
  game.data.constants.gen3SurfBlob = {
    image = "tests/surf_mount_render/assets/" .. family .. ".png",
    trueColor = true,
    frameWidth = 32,
    frameHeight = 32,
    frames = family == "frlg" and 6 or 3,
  }
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
  local result = T.sdk.loadMods(
    { "mods/surf_mount_reference" },
    { data = game.data, fs = T.sdk.memfs(files) }
  )
  assert(#result.errors == 0, "generic reference mod must load")
  result.loader.game = game
  local reads, closed = 0, 0
  result.loader.fs.newFile = function(path)
    local bytes = files[path]
    if bytes == nil then
      local file = io.open(root .. "/" .. path, "rb")
      if file then
        bytes = file:read("*a")
        file:close()
      end
    end
    if not bytes then
      return nil
    end
    return {
      open = function()
        return true
      end,
      getSize = function()
        return #bytes
      end,
      read = function(_, n)
        reads = reads + 1
        return bytes:sub(1, n)
      end,
      close = function()
        closed = closed + 1
        return true
      end,
    }
  end
  local f = {
    game = game,
    world = ow,
    player = p,
    result = result,
    files = files,
    data = result.loader.apis.surf_mount_reference.renderData,
    counts = function()
      return reads, closed
    end,
  }
  function f.setPhase(facing, tick)
    p.facing = facing
    p.bobTimer = tick % 32
    f.seconds = tick / 60
  end
  f.setPhase("right", 0)
  love.timer = love.timer or {}
  love.timer.getTime = function()
    return f.seconds
  end
  return f
end
return M
