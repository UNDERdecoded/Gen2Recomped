package.path = "./?.lua;./?/init.lua;" .. package.path
local root, backend, version, api = arg[1], arg[2], arg[3], tonumber(arg[4]) or 2
local f = dofile(
  root .. "/tests/field_effect_render/" .. (backend == "gen1" and "gen1_fixture" or "fixture") .. ".lua"
).new(root, version, api)
if backend == "gen2" then
  dofile(root .. "/tests/field_effect_render/native.lua").attach(f)
end
local reports = {}
local camera = { x = 0, y = 0 }
for _, clock in ipairs({ 0, 3, 4, 5, 8, 9, 10, 14, 15, 16, 49 }) do
  f.setClock(clock)
  camera.x, camera.y = clock % 2 == 1 and 13.25 or 0, clock % 2 == 1 and 7.75 or 0
  local before = backend == "gen1" and f.FE._anims[1].timer or f.world.ripples[1].clock
  local observation = assert(f.result.loader.exports.effect_reference.observe("A"))
  local native = {}
  for _, layer in ipairs({ "ground", "actorCover", "front" }) do
    local calls = {}
    love.graphics.draw = function(image, q, x, y, rotation, sx, sy)
      calls[#calls + 1] = {
        image = image,
        source = { x = q.x, y = q.y, width = q.w, height = q.h },
        x = x,
        y = y,
        flipX = sx == -1,
        flipY = sy == -1,
      }
    end
    f.drawNative(layer, camera)
    for _, call in ipairs(calls) do
      local kind = assert(f.imageKinds[call.image], "native source not identified")
      call.image = nil
      call.sheetId = "field:" .. kind
      call.layer = layer
      call.x = call.x - (call.flipX and call.source.width or 0)
      call.y = call.y - (call.flipY and call.source.height or 0)
      native[#native + 1] = call
    end
  end
  assert((backend == "gen1" and f.FE._anims[1].timer or f.world.ripples[1].clock) == before)
  for _, source in pairs(observation.sheets) do
    source.bytes = source.bytes:gsub(".", function(c)
      return ("%02x"):format(c:byte())
    end)
  end
  reports[#reports + 1] =
    { clock = clock, camera = { x = camera.x, y = camera.y }, public = observation, native = native }
end
assert(f.result.loader.exports.effect_reference.observe("stale") == nil)
print("FIELD_RENDER " .. require("src.link.Json").encode(reports))
