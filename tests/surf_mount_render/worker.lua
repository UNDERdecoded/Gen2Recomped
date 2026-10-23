package.path = "./?.lua;./?/init.lua;" .. package.path
local root, backend, version, api = arg[1], arg[2], arg[3], tonumber(arg[4]) or 2
local f = dofile(
  root .. "/tests/surf_mount_render/" .. (backend == "gen1" and "gen1_fixture" or "fixture") .. ".lua"
).new(root, version, api)
if backend == "gen2" then
  dofile(root .. "/tests/surf_mount_render/native.lua").attach(f)
end
local reports = {}
local cases = dofile(root .. "/tests/surf_mount_render/cases.lua")
for _, case in ipairs(cases.all()) do
  cases.apply(f, backend, case)
  local tick = case.tick
  local camera = { x = tick % 2 == 1 and 13.25 or 0, y = tick % 2 == 1 and 7.75 or 0 }
  local before = backend == "gen1" and f.FE._surfBob.animClock or f.player.bobTimer
  local observation = assert(f.result.loader.exports.surf_mount_reference.observe("A"))
  local native = {}
  love.graphics.draw = function(image, q, x, y, rotation, sx, sy)
    native[#native + 1] = {
      sheetId = "surf:player",
      source = { x = q.x, y = q.y, width = q.w, height = q.h },
      x = x - (sx == -1 and q.w or 0),
      y = y - (sy == -1 and q.h or 0),
      flipX = sx == -1,
      flipY = sy == -1,
    }
  end
  f.drawNative(camera)
  assert(
    (backend == "gen1" and f.FE._surfBob.animClock or f.player.bobTimer) == before,
    "reader/native oracle must not advance timers"
  )
  for _, source in pairs(observation.sheets) do
    source.bytes = source.bytes:gsub(".", function(c)
      return ("%02x"):format(c:byte())
    end)
  end
  reports[#reports + 1] = { camera = camera, public = observation, native = native }
end
assert(f.result.loader.exports.surf_mount_reference.observe("stale") == nil)
print("SURF_RENDER " .. require("src.link.Json").encode(reports))
