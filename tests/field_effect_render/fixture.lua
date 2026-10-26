local F = {}
function F.new(root, version, api)
  local T = require("tests.modkit")
  require("src.core.GameVersion").set(version or "firered")
  local Map = require("src.world.Map")
  local ow = {
    isOverworld = true,
    ripples = { { px = 32, py = 38, clock = 0 } },
    sparkles = { { px = 64, py = 32, clock = 0 } },
    entities = {},
    ghosts = {},
  }
  local cells = {}
  for i = 1, 64 do
    cells[i] = "\1\0"
  end
  ow.map = setmetatable({
    id = "A",
    def = { width = 8, height = 8, blocks = table.concat(cells), collisionCells = {}, borderBlock = 0 },
    widthCells = 8,
    heightCells = 8,
    blockCells = 1,
    blockPatch = {},
    collisionPatch = {},
    shutCells = {},
    tileset = { collision = { [2] = 2 } },
    grassTiles = { [2] = true },
  }, Map)
  local player =
    { cellX = 2, cellY = 3, px = 32, py = 48, progress = 8, stepFrames = 16, targetX = 3, targetY = 3 }
  local npc = { def = { index = 7 }, cellX = 4, cellY = 3, px = 64, py = 48, progress = 0 }
  ow.player = player
  ow.entities = { player, npc }
  local game = { overworld = ow, stack = { states = { ow } }, data = T.fixtures.fresh() }
  local c = {
    gen3TallGrass = {
      image = "tests/field_effect_render/assets/grass.png",
      frameWidth = 16,
      frameHeight = 16,
      frames = 5,
    },
    gen3Ripple = {
      key = "RIPPLE",
      order = {
        { frame = 0, hold = 4 },
        { frame = 2, hold = 5 },
        {
          frame = 4,
          hold = 6,
        },
      },
    },
    gen3Sparkle = {
      key = "SPARKLE",
      order = {
        { frame = 0, hold = 5 },
        { frame = 1, hold = 5 },
        {
          frame = 2,
          hold = 5,
        },
      },
      linger = 35,
    },
  }
  game.data.constants = c
  game.data.sprites = {}
  for _, kind in ipairs({ "ripple", "sparkle" }) do
    local key = kind:upper()
    game.data.sprites[key] = {
      id = key,
      image = "tests/field_effect_render/assets/" .. kind .. ".png",
      trueColor = true,
      frameWidth = 16,
      frameHeight = 16,
      frames = kind == "ripple" and 5 or 3,
    }
  end
  local files = {}
  for _, name in ipairs({ "Effects.lua", "main.lua", "manifest.json" }) do
    local f = assert(io.open(root .. "/examples/portable_oasc_effects/" .. name, "rb"))
    files["mods/effect_reference/" .. name] = f:read("*a")
    f:close()
  end
  local Json = require("src.link.Json")
  local manifest = assert(Json.decode(files["mods/effect_reference/manifest.json"]))
  manifest.api = api or 2
  files["mods/effect_reference/manifest.json"] = Json.encode(manifest)
  local result = T.sdk.loadMods({ "mods/effect_reference" }, { data = game.data, fs = T.sdk.memfs(files) })
  assert(#result.errors == 0, "reference mod must load")
  result.loader.game = game
  local reads, closed = 0, 0
  result.loader.fs.newFile = function(path)
    local bytes = files[path]
    if bytes == nil then
      local f = io.open(root .. "/" .. path, "rb")
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
    world = ow,
    game = game,
    player = player,
    npc = npc,
    files = files,
    result = result,
    data = result.loader.apis.effect_reference.renderData,
    counts = function()
      return reads, closed
    end,
  }
end
return F
