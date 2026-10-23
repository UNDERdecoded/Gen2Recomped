local M = {}
function M.new(root, version, api)
  local T = require("tests.modkit")
  require("src.core.GameVersion").set(version)
  local FE = require("src.core.game3.field_effects")
  local R = require("src.core.game3.field_effects_rse")
  local P = require("src.core.game3.player")
  local f = { FE = FE, R = R, player = P, sources = {}, clock = 0, imageKinds = {} }
  FE._manifest = false -- The fixtures supply already-resident sheets, never import a ROM.
  FE._sheets = {}
  FE._anims = {}
  R._list = {}
  P.surfing = false
  P.surfHopping = false
  P.dismounting = false
  P.px = 32
  P.py = 48
  for _, kind in ipairs({ "grass", "ripple", "sparkle" }) do
    local file = assert(io.open(root .. "/tests/field_effect_render/assets/" .. kind .. ".png", "rb"))
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
      image = { path = kind }
    end
    f.imageKinds[image] = kind
    local frames = kind == "sparkle" and 3 or 5
    local s = { image = image, quads = {}, quadsFront = {}, fw = 16, fh = 16, frames = frames, bytes = bytes }
    for frame = 0, frames - 1 do
      s.quads[frame] = love.graphics.newQuad(0, frame * 16, 16, 16, 16, frames * 16)
      s.quadsFront[frame] = love.graphics.newQuad(0, frame * 16 + 8, 16, 8, 16, frames * 16)
    end
    f.sources[kind] = s
    FE._sheets[kind == "grass" and "tall_grass" or kind] = s
  end
  -- Empty resident object pool prevents unrelated NPC/reflection effects.
  local Objects = require("src.core.game3.objects")
  Objects._byId = {}
  Objects._order = {}
  Objects._bounds = { w = 8, h = 8 }
  Objects._mapId = "A"
  function f.setClock(clock)
    f.clock = clock
    FE._fx = { cx = 2, cy = 3, seq = true, frame = math.min(4, math.floor(clock / 4)) }
    FE._anims =
      { { kind = "ripple", cx = 2, cy = 2, frame = math.min(4, math.floor(clock / 4)), timer = clock } }
    R._list = {
      {
        name = "small_sparkle",
        sheet = f.sources.sparkle,
        x = 72,
        y = 40,
        layer = "front",
        timer = clock,
        hidden = clock >= 15,
        a = { frame = math.min(2, math.floor(clock / 5)), hflip = clock % 2 == 1, vflip = clock % 3 == 1 },
      },
    }
  end
  function f.drawNative(layer, camera)
    if layer == "ground" then
      FE.drawBehind(camera.x, camera.y)
    elseif layer == "actorCover" then
      local actors = {}
      FE.collectActors(actors, camera.x, camera.y)
      for _, a in ipairs(actors) do
        if a.kind == "field_effect_grass" then
          a:draw(camera.x, camera.y)
        end
      end
    else
      R.drawFront(camera.x, camera.y)
    end
  end
  dofile(root .. "/tools/field-effect-render-check/gen1_reference.lua").install(require("src.mods.Loader"), f)
  local files = {}
  for _, name in ipairs({ "main.lua", "Effects.lua", "manifest.json" }) do
    local file = assert(io.open(root .. "/examples/portable_oasc_effects/" .. name, "rb"))
    files["mods/effect_reference/" .. name] = file:read("*a")
    file:close()
  end
  local Json = require("src.link.Json")
  local manifest = assert(Json.decode(files["mods/effect_reference/manifest.json"]))
  manifest.api = api
  files["mods/effect_reference/manifest.json"] = Json.encode(manifest)
  f.result = T.sdk.loadMods(
    { "mods/effect_reference" },
    { data = T.fixtures.fresh(), fs = T.sdk.memfs(files) }
  )
  assert(#f.result.errors == 0, "Gen1 reference consumer must load")
  f.setClock(0)
  return f
end
return M
