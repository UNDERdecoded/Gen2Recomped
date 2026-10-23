local F = {}
function F.new(root, version, api)
  local T = require("tests.modkit")
  require("src.core.GameVersion").set(version)
  local Player = require("src.core.game3.player")
  local Objects = require("src.core.game3.objects")
  local function npc(id, x, y)
    return {
      localId = id,
      cellX = x / 16,
      cellY = y / 16,
      px = x,
      py = y,
      visible = true,
      graphicsId = 1,
      elevation = 3,
      facing = "right",
      moving = true,
      animClock = 0,
      stepFlip = false,
    }
  end
  local a, b, h = npc(1, 48, 48), npc(2, 80, 32), npc(3, 0, 0)
  h.hidden = true
  Objects._byId = { [1] = a, [2] = b, [3] = h }
  Objects._order = { 2, 3, 1 }
  Objects._mapId = "A"
  Objects._bounds = { w = 100, h = 100 }
  Player.px, Player.py, Player.facing, Player.graphicsId = 24, 40, "right", 1
  Player.visible, Player.hidden, Player.moving, Player.elevation = true, false, true, 3
  local g = npc(1, 16, 16)
  local fixture = {
    root = root,
    player = Player,
    npc = a,
    other = b,
    sprites = { [1] = { frameCount = 9, width = 16, height = 32 } },
    neighbors = {
      {
        mapId = "B",
        x = -48,
        y = 16,
        pool = {
          byId = { [1] = g },
          order = { 1 },
          bounds = {
            w = 100,
            h = 100,
          },
        },
      },
    },
  }
  dofile(root .. "/tools/actor-render-check/gen1_reference.lua").install(require("src.mods.Loader"), fixture)
  local files = {}
  for _, name in ipairs({ "main.lua", "Actors.lua", "manifest.json" }) do
    local f = assert(io.open(root .. "/examples/portable_oasc_actors/" .. name, "rb"))
    files["mods/actor_reference/" .. name] = f:read("*a")
    f:close()
  end
  local Json = require("src.link.Json")
  local manifest = assert(Json.decode(files["mods/actor_reference/manifest.json"]))
  manifest.api = api
  files["mods/actor_reference/manifest.json"] = Json.encode(manifest)
  fixture.result = T.sdk.loadMods(
    { "mods/actor_reference" },
    { data = T.fixtures.fresh(), fs = T.sdk.memfs(files) }
  )
  assert(#fixture.result.errors == 0, "Gen1 reference consumer must load")
  function fixture.setPose(facing, phase, step)
    Player.facing = facing
    Player.animCmd = step and (phase == 1 and 0 or 1) or (phase == 1 and 2 or 3)
    Player.observedClock = (phase == 1 and 8 or 0) + (step and 16 or 0)
  end
  return fixture
end
return F
