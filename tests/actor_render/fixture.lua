-- Synthetic sprite art and resident native actor shapes; no ROM or save.
local F = {}
function F.new(root, version, api)
  local T = require("tests.modkit")
  require("src.core.GameVersion").set(version or "firered")
  local Player = require("src.world.Player")
  local NPC = require("src.world.NPC")
  local Sprite = require("src.render.SpriteRenderer")
  local function sprite(name, file, frames, poses)
    local d = {
      id = name,
      image = "tests/actor_render/assets/" .. (file or "gen2.png"),
      trueColor = true,
      gen3ObjectEvent = true,
      frameWidth = 16,
      frameHeight = 32,
      frames = frames or 9,
      walker = true,
      poseFrames = poses,
    }
    return Sprite.new(d)
  end
  local walk = sprite("AVATAR")
  local run = sprite("RUN")
  local bike = sprite("BIKE")
  local surf = sprite("SURF")
  local pose = sprite("POSE", "pose.png", 1, 5)
  local function npc(index, x, y, which)
    return setmetatable({
      def = { index = index, elevation = 3 },
      id = "A_obj_" .. index,
      sprite = which or walk,
      px = x,
      py = y,
      cellX = x / 16,
      cellY = y / 16,
      progress = 8,
      moving = true,
      facing = "right",
      stepFlip = false,
    }, NPC)
  end
  local player = setmetatable({
    sprite = walk,
    runSprite = run,
    bikeSprite = bike,
    surfSprite = surf,
    fieldMoveSprite = pose,
    px = 24,
    py = 40,
    progress = 8,
    animClock = 8,
    moving = true,
    facing = "right",
    elevation = 3,
  }, Player)
  local a, b = npc(1, 48, 48), npc(2, 80, 32)
  local hidden = npc(3, 0, 0)
  hidden.hidden = true
  local nb = { map = { id = "B" }, cx = -3, cy = 1 }
  local ghost = npc(1, 16, 16)
  local ow = {
    isOverworld = true,
    map = { id = "A", def = { mapType = "TOWN" } },
    player = player,
    entities = { b, hidden, player, a },
    ghosts = { { npc = ghost, nb = nb, ox = -48, oy = 16 } },
  }
  local game = { data = T.fixtures.fresh(), overworld = ow, stack = { states = { ow } } }
  local files = {}
  for _, name in ipairs({ "main.lua", "Actors.lua", "manifest.json" }) do
    local f = assert(io.open(root .. "/examples/portable_oasc_actors/" .. name, "rb"))
    files["mods/actor_reference/" .. name] = f:read("*a")
    f:close()
  end
  local Json = require("src.link.Json")
  local manifest = assert(Json.decode(files["mods/actor_reference/manifest.json"]))
  manifest.api = api or 2
  files["mods/actor_reference/manifest.json"] = Json.encode(manifest)
  local result = T.sdk.loadMods({ "mods/actor_reference" }, { data = game.data, fs = T.sdk.memfs(files) })
  assert(#result.errors == 0, "reference mod must load")
  result.loader.game = game
  -- The SDK alias filesystem does not forward streaming-file methods.
  -- Add a bounded test stream after load; native LÖVE supplies this itself.
  local reads, closed = 0, 0
  result.loader.fs.newFile = function(path)
    local bytes = files[path]
    if bytes == nil then
      local f = io.open(path, "rb")
      if f then
        bytes = f:read("*a")
        f:close()
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
  return {
    game = game,
    world = ow,
    player = player,
    npc = a,
    other = b,
    ghost = ghost,
    walk = walk,
    run = run,
    bike = bike,
    surf = surf,
    pose = pose,
    files = files,
    result = result,
    data = result.loader.apis.actor_reference.renderData,
    counts = function()
      return reads, closed
    end,
  }
end
return F
