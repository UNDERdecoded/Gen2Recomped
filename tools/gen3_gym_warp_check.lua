-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- A HEADLESS HOENN OVERWORLD, WALKED THROUGH PETALBURG GYM'S DOORS.
--
-- Reported from play, from somebody else's machine: "petalburg gym in emerald
-- still showing as a black background when i warp through the rooms even with
-- no mods on", and then: "I suspect its drawing the right room but not spawning
-- the player in the right location after going through the doors."
--
-- Pass 141 proved the DATA can draw -- the blocks, the tileset pair, the id
-- space, every room's window fill. It could not answer where the player ends
-- up, because it never ran a warp. This does: it stands up the REAL
-- `OverworldController` on the real Emerald cache, puts the player on each of
-- the gym's thirty-six self-warps in turn, and takes them through the engine's
-- own `takeWarp` -> `startWarpTo` -> `setMap` path.
--
-- WHY THE GYM IS THE HARD CASE.  It is ONE map, nine blocks wide against a
-- fifteen-block screen and 112 tall, and 36 of its 38 warps point back at
-- itself: the rooms are stacked inside a single layout and the doors between
-- them are self-warps. A warp whose destination map is the map you are already
-- on is the one shape nothing else in the region exercises.
--
-- WHAT IT REPORTS THAT IS WORTH KNOWING EVEN WHEN GREEN.  Every room-door
-- destination is an IMPASSABLE cell -- the lower half of the sliding door,
-- which `PetalburgGymSetDoorMetatiles` ORs `MAPGRID_IMPASSABLE` onto in every
-- frame, open or shut, on the cartridge as well. So the player really does
-- land standing in a doorway. Section 4 is there because that is only correct
-- as long as they can walk OUT of it.
--
-- Usage: texlua tools/gen3_gym_warp_check.lua [emerald/data/generated]

package.path = "./?.lua;" .. package.path
-- LuaJIT's `bit` library, which texlua has not got.  Only the ops the engine
-- actually reaches are provided; anything else raises rather than lying.
package.preload["bit"] = function()
  local function tou32(v) v = math.floor(v) % 4294967296 return v end
  local function bitop(a, b, f)
    a, b = tou32(a), tou32(b)
    local r, m = 0, 1
    for _ = 1, 32 do
      r = r + f(a % 2, b % 2) * m
      a, b, m = math.floor(a / 2), math.floor(b / 2), m * 2
    end
    return r
  end
  local M = {}
  function M.band(a, b, ...) local r = bitop(a, b, function(x,y) return (x==1 and y==1) and 1 or 0 end)
    for _, c in ipairs({...}) do r = M.band(r, c) end return r end
  function M.bor(a, b, ...) local r = bitop(a, b, function(x,y) return (x==1 or y==1) and 1 or 0 end)
    for _, c in ipairs({...}) do r = M.bor(r, c) end return r end
  function M.bxor(a, b, ...) local r = bitop(a, b, function(x,y) return (x~=y) and 1 or 0 end)
    for _, c in ipairs({...}) do r = M.bxor(r, c) end return r end
  function M.bnot(a) return 4294967295 - tou32(a) end
  function M.lshift(a, n) return tou32(tou32(a) * 2 ^ n) end
  function M.rshift(a, n) return math.floor(tou32(a) / 2 ^ n) end
  function M.arshift(a, n) return M.rshift(a, n) end
  function M.tobit(a) local v = tou32(a) return v >= 2147483648 and v - 4294967296 or v end
  function M.tohex(a) return ("%08x"):format(tou32(a)) end
  return M
end
local EM = os.getenv("EMDATA") or "/mnt/user-data/uploads/generated"

-- ---- a love that records rather than draws --------------------------------
local function batch(img) local b={n=0,img=img}
  function b:clear() self.n=0 end function b:add() self.n=self.n+1 end
  function b:setTexture(t) self.img=t end function b:release() end return b end
local function image(w,h) local i={w=w or 1,h=h or 1}
  function i:getWidth() return self.w end function i:getHeight() return self.h end
  function i:release() end function i:setFilter() end function i:setWrap() end
  function i:getDimensions() return self.w, self.h end
  function i:getFormat() return "rgba8" end
  function i:getPixel() return 0,0,0,0 end
  function i:setPixel() end
  function i:newImageData() local d=image(self.w,self.h) d.setPixel=function() end return d end
  return i end
love = {
  timer = { getTime = function() return 0 end, getDelta = function() return 1/60 end },
  math = { random = function(a,b) if b then return a else return a or 0.5 end end,
           newRandomGenerator = function() return { random = function(_,a,b) return a or 0 end } end },
  image = { newImageData = function(w,h) local d=image(w,h) d.setPixel=function() end return d end },
  graphics = {
    newSpriteBatch = batch,
    newQuad = function(x,y,w,h,sw,sh) return {x,y,w,h,sw,sh,setViewport=function() end} end,
    newImage = function(d) return image(d and d.w, d and d.h) end,
    newCanvas = function(w,h) local c=image(w,h) c.newImageData=function(s) return image(s.w,s.h) end return c end,
    newShader = function() return nil end,
    draw=function() end, setColor=function() end, getColor=function() return 1,1,1,1 end,
    push=function() end, pop=function() end, origin=function() end,
    setScissor=function() end, getScissor=function() end, clear=function() end,
    rectangle=function() end, setCanvas=function() end, getCanvas=function() return nil end,
    setBlendMode=function() end, getBlendMode=function() return "alpha" end,
    translate=function() end, scale=function() end, setShader=function() end,
    getWidth=function() return 240 end, getHeight=function() return 160 end,
    setDefaultFilter=function() end, setLineWidth=function() end, print=function() end,
    newFont=function() return { getWidth=function() return 8 end, getHeight=function() return 8 end } end,
  },
  filesystem = { getInfo=function() return nil end, read=function() return nil end,
                 write=function() return true end, append=function() return true end,
                 getSaveDirectory=function() return "." end, createDirectory=function() return true end },
  system = { getOS = function() return "Linux" end },
  window = { getMode = function() return 240,160,{} end },
  audio = { newSource = function() return nil end },
  event = { push = function() end },
  keyboard = { isDown = function() return false end },
}


local fails, checks = 0, 0
local function ok(cond, fmt, ...)
  checks = checks + 1
  if not cond then
    fails = fails + 1
    io.write("FAIL: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
  end
end
local function section(n) io.write(("\n-- %s\n"):format(n)) end

local EM = arg and arg[1] or "G:/Gen2Recomped/emerald/data/generated"
local function load(name)
  local chunk = loadfile(EM .. "/" .. name .. ".lua")
  if not chunk then return nil end
  local okRun, v = pcall(chunk)
  return okRun and v or nil
end

-- THE REPO'S OWN HAND-PORTED SCRIPTS HAVE TO BE REACHABLE.
--
-- Entering the gym runs `data/scripts/init.lua`, which is a file in this
-- REPOSITORY and not in the extracted cache. Run from a tree without it -- a
-- partial checkout, or a working copy holding only src/ and tools/ -- the
-- require fails inside the overworld and this check reported "the overworld
-- would not enter the gym", which is a confident accusation against the
-- engine for something the engine never saw.
--
-- So it is tested up front, and a missing tree exits 2: this tree's
-- convention for "I could not run", which `tools/run_checks.py` counts as
-- SKIPPED rather than as a fault.
do
  local probe = io.open("data/scripts/init.lua", "rb")
  if not probe then
    io.write("cannot reach data/scripts/init.lua from " .. (os.getenv("PWD") or "the")
             .. " working directory\n")
    io.write("  the gym entry runs the repo's hand-ported scripts, so this\n"
             .. "  check needs the whole repository, not just src/ and tools/\n")
    os.exit(2)
  end
  probe:close()
end

local GameVersion = require("src.core.GameVersion")
GameVersion.set("emerald")

local Data = require("src.core.Data")
local TABLES = { "maps","tilesets","map_tilesets","constants","field","moves",
                 "items","pokemon","text","trainers","encounters","map_scripts",
                 "scenes","sprites","icons","songs","audio","type_chart","font",
                 "save_layout","map_layouts" }
local loaded = 0
for _, name in ipairs(TABLES) do
  local t = load(name)
  if t then Data[name] = t loaded = loaded + 1 end
end
if not Data.maps then
  io.write(("  cannot read %s/maps.lua\n"):format(EM))
  io.write("\n  Pass the generated Emerald data root as the first argument.\n")
  os.exit(2)
end
io.write(("  %s: %d table(s)\n"):format(EM, loaded))

local Game = require("src.core.Game")
Game.data = Data
Game.input = { pressed = function() return false end,
               down = function() return false end, dir = function() end,
               isDown = function() return false end, wasPressed = function() return false end,
               direction = function() end }
Game.save = { player = { name = "MAY", gender = "girl" }, party = {}, flags = {},
              vars = {}, options = {}, bag = {} }
-- THE RENDERER, ONLY AS FAR AS THE OVERWORLD ASKS IT ANYTHING.  The real one
-- wants canvases and a shader; `enter` and the camera reach two questions.
Game.renderer = {
  worldViewSize = function() return 240, 160 end,
  fitScale = function() return 1 end,
  beginFrame = function() end, endFrame = function() end,
  uiSize = function() return 240, 160 end,
}
local StateStack = require("src.core.StateStack")
if StateStack.init then pcall(StateStack.init, StateStack) end
Game.stack = StateStack
-- A TRANSITION THAT RUNS ITS BODY AT ONCE.  `startWarpTo` hands the map change
-- to a fade and the fade runs it a frame later; with no frames, the warp would
-- never complete and every assertion below would be about the cell the player
-- started on. Named here rather than hidden, because it is the one place this
-- harness is not the engine.
local Transition = require("src.render.Transition")
local realTransitionNew = Transition.new
Transition.new = function(_, body)
  if type(body) == "function" then pcall(body) end
  return { isTransition = true, update = function() end, draw = function() end }
end

local GYM = "MAP_G08_N01"
local def = Data.maps[GYM]
ok(def ~= nil, "%s is not in the dataset", GYM)
if not def then
  io.write(("\n%d checks, %d failed\n"):format(checks, fails))
  os.exit(1)
end

local OW = require("src.world.OverworldController")
local okEnter, err = pcall(OW.enter, OW, GYM, 4, 110, "up")
ok(okEnter, "the overworld would not enter the gym: %s", tostring(err))
if not okEnter then
  io.write(("\n%d checks, %d failed\n"):format(checks, fails))
  os.exit(1)
end

local function rawAt(bx, by)
  if bx < 0 or by < 0 or bx >= def.width or by >= def.height then return nil end
  local i = by * def.width + bx + 1
  local lo, hi = def.blocks:byte(i * 2 - 1, i * 2)
  return lo + hi * 256
end
local function solid(bx, by)
  local v = rawAt(bx, by)
  return v and (math.floor(v / 1024) % 4) ~= 0
end

-- how much of the screen the tile pass actually fills at the camera it is on
local function frame()
  local r = OW.map.renderer
  local cam = OW.camera
  r.win = nil
  if not pcall(r.ensureWindow, r, cam.x, cam.y, 240, 160) then return -1, -1 end
  local w, n = r.win, r.blockTiles
  if not w then return -1, -1 end
  local cx0, cy0 = math.floor(w.tx0 / n), math.floor(w.ty0 / n)
  local cx1, cy1 = math.ceil(w.tx1 / n), math.ceil(w.ty1 / n)
  local cells, drew = 0, 0
  for cy = cy0, cy1 - 1 do
    for cx = cx0, cx1 - 1 do
      cells = cells + 1
      local id = OW.map:blockAt(cx, cy)
      if id and r:gen3QuadFor(id) then drew = drew + 1 end
    end
  end
  return cells, drew
end

-- ---------------------------------------------------------------------------
section("1. the gym is the shape the cartridge says")
-- ---------------------------------------------------------------------------
ok(def.width == 9 and def.height == 112, "the gym is %sx%s, not 9x112",
   tostring(def.width), tostring(def.height))
local selfWarps = 0
for _, w in ipairs(def.warps or {}) do
  if w.destMap == GYM then selfWarps = selfWarps + 1 end
end
io.write(("  %d warps, %d of them back into this map\n")
         :format(#(def.warps or {}), selfWarps))
ok(selfWarps >= 30, "only %d self-warps; the rooms are supposed to be one "
   .. "layout", selfWarps)
ok(OW.map and OW.map.id == GYM, "the overworld did not end up in the gym")

-- ---------------------------------------------------------------------------
section("2. every door lands the player where the cartridge says")
-- ---------------------------------------------------------------------------
local wrong, blank, solidArrivals = 0, 0, 0
for i, w in ipairs(def.warps or {}) do
  if w.destMap == GYM then
    OW.player.cellX, OW.player.cellY = w.x, w.y
    OW.player.px, OW.player.py = w.x * 16, w.y * 16
    local okW, errW = pcall(OW.takeWarp, OW, w)
    ok(okW, "warp %d (%d,%d) raised: %s", i - 1, w.x, w.y, tostring(errW))
    if okW then
      local expect = def.warps[w.destWarp]
      local px, py = OW.player.cellX, OW.player.cellY
      local landed = expect and px == expect.x and py == expect.y
      if not landed then wrong = wrong + 1 end
      ok(landed, "warp %d (%d,%d) landed the player at %d,%d; its destination "
         .. "warp is %s", i - 1, w.x, w.y, px, py,
         expect and (expect.x .. "," .. expect.y) or "missing")
      ok(px >= 0 and py >= 0 and px < def.width and py < def.height,
         "warp %d put the player OUTSIDE the map at %d,%d -- every visible "
         .. "cell would be border, which is what a black screen is",
         i - 1, px, py)
      if solid(px, py) then solidArrivals = solidArrivals + 1 end
      OW.camera:follow(OW.player.px, OW.player.py, 240, 160)
      local cells, drew = frame()
      if drew < 1 then blank = blank + 1 end
      ok(cells > 0, "warp %d filled an empty window", i - 1)
      ok(drew == cells, "warp %d: %d of %d cells on screen have no picture",
         i - 1, cells - drew, cells)
    end
  end
end
io.write(("  %d self-warps taken: %d landed wrong, %d drew nothing, "
          .. "%d landed on an impassable cell\n")
         :format(selfWarps, wrong, blank, solidArrivals))
ok(wrong == 0, "%d warp(s) landed the player somewhere else", wrong)
ok(blank == 0, "%d warp(s) left nothing on screen", blank)
-- The doorways ARE impassable, on the cartridge too, and half the warps land
-- on one. Asserted rather than merely reported so that a dataset which stopped
-- marking them would be noticed -- it would mean the collision had changed
-- under the doors.
ok(solidArrivals >= 16, "only %d arrivals are on an impassable cell; the gym's "
   .. "doorways are impassable in every frame and half the warps land on one",
   solidArrivals)

-- ---------------------------------------------------------------------------
section("3. and a control, so section 2 can fail")
-- ---------------------------------------------------------------------------
do
  local w = nil
  for _, cand in ipairs(def.warps or {}) do
    if cand.destMap == GYM then w = cand break end
  end
  ok(w ~= nil, "no self-warp to run the control on")
  if w then
    local keep = w.destWarp
    w.destWarp = 1              -- the city exit, which is not where it goes
    OW.player.cellX, OW.player.cellY = w.x, w.y
    OW.player.px, OW.player.py = w.x * 16, w.y * 16
    pcall(OW.takeWarp, OW, w)
    local expect = def.warps[keep]
    ok(not (OW.player.cellX == expect.x and OW.player.cellY == expect.y),
       "a warp pointed at the wrong destination still landed the player at "
       .. "%d,%d -- section 2 is not reading the arrival at all",
       OW.player.cellX, OW.player.cellY)
    w.destWarp = keep
  end
end

-- ---------------------------------------------------------------------------
section("4. the player can get out of the doorway they land in")
-- ---------------------------------------------------------------------------
-- Landing on an impassable cell is the cartridge's own behaviour and is only
-- correct as long as it is not a trap. `PetalburgGymSetDoorMetatiles` ORs
-- MAPGRID_IMPASSABLE onto both halves of the door in EVERY frame, open or
-- shut, so there is no frame in which the doorway is walkable and the way out
-- is always the tile below.
local Collision = require("src.world.Collision")
pcall(Collision.load, Data)
local DOORWAYS = { {1,105},{7,105},{1,92},{7,92},{1,79},{7,79},{1,66},{7,66},
                   {1,53},{7,53},{1,40},{7,40},{1,27},{7,27},{1,14},{7,14} }
local stuck, doorTiles = 0, 0
for _, c in ipairs(DOORWAYS) do
  OW.player.cellX, OW.player.cellY = c[1], c[2]
  OW.player.px, OW.player.py = c[1] * 16, c[2] * 16
  local any = false
  for _, d in ipairs({ "up", "down", "left", "right" }) do
    if Collision.canMove(OW.map, OW.cast or OW.entities, OW.player, d) then
      any = true
    end
  end
  if not any then stuck = stuck + 1 end
  ok(any, "a player landing in the doorway at %d,%d cannot move in any "
     .. "direction", c[1], c[2])
  if OW.map.isDoorTileCell and OW.map:isDoorTileCell(c[1], c[2]) then
    doorTiles = doorTiles + 1
  end
end
io.write(("  %d doorways, %d leave the player stuck, %d read as door tiles\n")
         :format(#DOORWAYS, stuck, doorTiles))
ok(stuck == 0, "%d doorway(s) are a trap", stuck)
-- RECORDED, NOT ASSERTED: none of them carries a door BEHAVIOUR, so the Gen 3
-- arrival step-out never fires here and the player is left standing in the
-- doorway rather than walked a tile clear of it. That is what the cartridge
-- does too -- these are sliding gym doors, not the animated doors
-- MetatileBehavior_IsDoor names -- so it is a fact about the map and not a
-- fault. It is printed because "why am I standing in the door" is a question
-- this file should be able to answer.

section("5. live transitions and room-entry scripts")
Transition.new = realTransitionNew
Game.stack.states = {}
OW.pendingScripts = {}
OW.transitioning = nil
local function settle()
  for tick = 1, 180 do
    local top = Game.stack:top()
    if top then top:update(1/60) else OW:update(1/60) end
    if not OW.transitioning and not OW.runner:isRunning()
       and not (OW.pendingScripts and OW.pendingScripts[1]) then return true end
  end
  return false
end
OW:setMap(GYM, 4, 110, "up")
ok(settle(), "main room entry did not settle")
for i, w in ipairs(def.warps or {}) do
  if w.destMap == GYM then
    OW.player.cellX, OW.player.cellY = w.x, w.y
    OW.player.px, OW.player.py = w.x * 16, w.y * 16
    OW:takeWarp(w)
    ok(settle(), "live warp %d did not release input", i - 1)
    for tick = 1, 30 do OW:update(1/60) end
    local expected = def.warps[w.destWarp]
    ok(OW.player.cellX == expected.x and OW.player.cellY == expected.y,
       "live warp %d left player at %s,%s", i - 1,
       tostring(OW.player.cellX), tostring(OW.player.cellY))
    local cells, drew = frame()
    ok(cells > 0 and drew == cells, "live warp %d did not draw its room", i - 1)
  end
end

section("6. extracted sliding-door script with variable coordinates")
-- These doors use an A-button script, rather than ordinary walking warps.
-- Find its shared warpdoor block in the ROM cache, without depending on a
-- particular ROM address. The door choice sets these two temporary variables.
local VM = require("src.script.Gen3ScriptVM")
local entry
for label, rows in pairs(Data.map_scripts.scripts) do
  for _, row in ipairs(rows) do
    if row[1] == "warpdoor" and row[2] == 8 and row[3] == 1
       and row[5] == 0x8008 and row[6] == 0x8009 then entry = label end
  end
end
ok(entry ~= nil, "extracted Petalburg variable-coordinate door script missing")
if entry then
  local script = assert(VM.compile(Data, entry))
  for _, slot in ipairs({3,6,9,10,15,16,21,22,23,24,33,34}) do
    local w = def.warps[slot]
    local expected = def.warps[w.destWarp]
    OW:setMap(GYM, w.x, w.y+1, "up")
    ok(settle(), "door %d entry setup did not settle", slot)
    Game.save.gen3Vars = Game.save.gen3Vars or {}
    Game.save.gen3Vars[0x8008], Game.save.gen3Vars[0x8009] = expected.x, expected.y
    OW.runner:run(script)
    ok(settle(), "scripted door %d did not release input", slot)
    ok(OW.player.cellX == expected.x and OW.player.cellY == expected.y,
       "scripted door %d landed at %s,%s instead of %d,%d", slot,
       tostring(OW.player.cellX), tostring(OW.player.cellY), expected.x, expected.y)
    local cells, drew = frame()
    ok(cells > 0 and drew == cells, "scripted door %d left a black room", slot)
    local canLeave = false
    for _, dir in ipairs({"up", "down", "left", "right"}) do
      canLeave = canLeave or Collision.canMove(OW.map, OW.cast or OW.entities, OW.player, dir)
    end
    ok(canLeave, "scripted door %d cannot leave the arrival doorway", slot)
  end
end

section("7. stored warp coordinates resolve when recorded")
local Commands = require("src.script.Commands")
local ctx = OW.runner:makeContext()
Game.save.gen3Vars[0x4001], Game.save.gen3Vars[0x8009] = 7, 85
for _, case in ipairs({{"g3_set_warp", "gen3PendingWarp"},
                      {"g3_set_dynamic_warp", "gen3DynamicWarp"},
                      {"g3_set_hole_warp", "gen3HoleWarp"}}) do
  Commands[case[1]](ctx, 8, 1, 255, 0x4001, 0x8009)
  Game.save.gen3Vars[0x4001] = 1
  local recorded = Game.save[case[2]]
  ok(recorded.x == 7 and recorded.y == 85, "%s stored variable IDs or deferred resolution", case[1])
  Commands[case[1]](ctx, 8, 1, 255, 0, 98)
  recorded = Game.save[case[2]]
  ok(recorded.x == 0 and recorded.y == 98, "%s lost literal coordinates", case[1])
  Commands[case[1]](ctx, 8, 1, 255, nil, nil)
  recorded = Game.save[case[2]]
  ok(recorded.x == nil and recorded.y == nil, "%s converted missing coordinates to zero", case[1])
  Game.save.gen3Vars[0x4001] = 7
end

io.write(("\n%d checks, %d failed\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
