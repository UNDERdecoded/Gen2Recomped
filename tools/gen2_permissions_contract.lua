-- ROM-free behavioral dump. Run from each engine's own checkout, passing
-- "native" here or "reference" for the pinned Gen1 engine. Compare stdout.
package.path = "./?.lua;./?/init.lua;" .. package.path
local Version = require("src.core.GameVersion")
Version.set("crystal")
local P = require(arg[1] == "reference" and "src.world.gen2.Permissions" or "src.world.Collision")
for byte = 0, 255 do
  io.write(byte, ":", P.isIce(byte) and "ice" or "-", ":",
    P.currentDirection(byte) or "-", ":", P.doorForcedDirection(byte) or "-", "\n")
end
local deltas = {up={0,-1}, down={0,1}, left={-1,0}, right={1,0}}
for _, dir in ipairs({"up", "down", "left", "right"}) do
  local delta = deltas[dir]
  for source = 0, 255 do
    local row = {}
    for destination = 0, 255 do
      local function collOf(x, y)
        if x == 0 and y == 0 then return source end
        if x == delta[1] and y == delta[2] then return destination end
        return 0
      end
      row[#row+1] = P.stepPermitted(collOf,0,0,dir) and "1" or "0"
    end
    io.write(dir, ":", source, ":", table.concat(row), "\n")
  end
end
