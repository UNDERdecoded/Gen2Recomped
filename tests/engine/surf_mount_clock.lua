package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local f = dofile("tests/surf_mount_render/fixture.lua").new(".", "firered", 2)
local p = f.player
p.isUnderwater = function()
  return false
end
local function row()
  return assert(f.data:surfMounts(1, "A")).mounts[1]
end
for tick = 1, 64 do
  p:update()
  T.eq(p.bobTimer, tick % 32, "one bob tick per fixed update")
  local _, _, y = p:pose()
  T.eq(y, p.py + (tick % 32 < 16 and 0 or 1), "native rider position follows fixed clock")
  for i = 1, 3 do
    T.eq(row().riderPose.y, y, "repeated public reads match same native pose")
    p:pose()
  end
  T.eq(p.bobTimer, tick % 32, "display/read count cannot advance bob")
end
p.bobTimer = 15
for i = 1, 16 do
  p:update()
end
T.eq(p.bobTimer, 31, "updates without any draw keep surf animation alive")
T.eq(row().draw.y, 53, "mount observes updated bob after skipped draws")
p.freeWalk = function()
  return false
end
p.freeInput = { 0, 0, {}, {} }
p:update()
T.eq(p.bobTimer, 0, "free camera update advances once, including wrap")
p.freeWalk = nil
p.hopFrames = 3
p.hopTotal = 3
p:update()
T.eq(p.bobTimer, 0, "ledge-hop pose has priority over surf bob")
p.hopFrames = 1
p:update()
T.eq(p.bobTimer, 1, "landing resumes bob in same fixed step")
p.acroBike = true
p.acroTrick = "hop"
p:update()
T.eq(p.bobTimer, 1, "acro pose has priority over surf bob")
p.acroBike = nil
p.acroTrick = nil
p.surfing = false
p:update()
T.eq(p.bobTimer, 1, "non-surf update preserves clock")
require("src.core.GameVersion").set("red")
p.surfing = true
p.bobTimer = 15
p:update()
T.eq(p.bobTimer, 15, "GB update behavior retained")
p:pose()
T.eq(p.bobTimer, 16, "GB draw-side bob behavior retained")
T.finish("Surf mount fixed-update clock")
