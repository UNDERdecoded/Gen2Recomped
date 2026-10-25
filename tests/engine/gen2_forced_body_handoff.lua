package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local V = require("src.core.GameVersion")
local W = require("src.world.OverworldController")
local Map = require("src.world.Map")
local Player = require("src.world.Player")
local Runner = require("src.script.ScriptRunner")
local Stack = require("src.core.StateStack")
local Sound = require("src.core.Sound")
local originalVersion, oldSound = V.get(), Sound.play
Sound.play = function() end -- audio device only
local slot, oldGame
for i = 1, 100 do
  local name, value = debug.getupvalue(W.onStepComplete, i)
  if name == "Game" then slot, oldGame = i, value; break end
end
assert(slot)
local function fixture(collision)
  local data = T.fixtures.fresh()
  local def = {id = "FORCED_BODY", generation = 2, environment = 3,
    width = 3, height = 3, blocks = {1,1,1,1,2,1,1,1,1}, warps = {}}
  data.maps[def.id] = def
  local ts = {id = "FORCED_FLOOR", blockCells = 2,
    collision = {255,255,255,255,0,0,0,0,collision,0,0,0},
    walkable = {0,0x23,0x2b,0x71,0x79,0x7a,0x7b,0xb1},
    waterTiles = {0x29}, shoreTiles = {}, grassTiles = {}}
  local p = setmetatable({cellX = 2, cellY = 2, px = 32, py = 32,
    facing = "down", moving = false, progress = 0, turnTimer = 0,
    turnArmed = true, stepFrames = 16, animClock = 0}, {__index = Player})
  local w = setmetatable({map = Map.new(def, ts), player = p, entities = {p},
    npcs = {}, ghosts = {}, scriptMoves = {}, pendingScripts = {}}, {__index = W})
  local g = {data = data, save = {party = {}, flags = {}, player = {name = "QA"}},
    overworld = w, world = w, stack = setmetatable({states = {}, worldState = w}, {__index = Stack})}
  w.runner = Runner.new(g, w)
  debug.setupvalue(W.onStepComplete, slot, g)
  return w, g, ts
end
local directions = {"right", "left", "up", "down"}
for _, version in ipairs({"gold", "silver", "crystal", "prism"}) do
  V.set(version)
  for byte = 0x30, 0x3f do
    local w = fixture(byte)
    T.eq(w:resumeForcedMovement(), true, version .. " current owns the input frame")
    T.eq(#w.scriptMoves, 1, "one real native movement is queued")
    T.eq(w.scriptMoves[1].dir, directions[byte % 4 + 1], "collision chooses native current direction")
    T.eq(w.player.moving, false, "queue admission does not interpolate the actor early")
    T.eq(w:resumeForcedMovement(), false, "queued owner refuses duplicate admission")
    w:updateScriptMoves()
    T.eq(w.player.moving, true, "real native script mover begins interpolation")
  end
  for _, byte in ipairs({0x71, 0x79, 0x7a, 0x7b}) do
    local w = fixture(byte)
    T.eq(w:resumeForcedMovement(), true, "forced door does not require a held key")
    T.eq(w.scriptMoves[1].dir, "down", "door retains its native downward direction")
  end
  for _, byte in ipairs({0x23, 0x2b}) do
    local w = fixture(byte)
    T.eq(w:resumeForcedMovement(), false, "standing on ice alone invents no travel direction")
    w.turningDirection = "right"
    T.eq(w:resumeForcedMovement(), true, "external ice latch returns ownership to native ice handler")
    T.eq(w.iceSlide, "right", "actual native ice latch is armed")
    T.eq(#w.scriptMoves, 1, "ice starts the existing native queue")
    T.eq(w.scriptMoves[1].dir, "right", "ice queue uses actual incoming direction")
    T.eq(w.todSteps, nil, "handoff does not replay the free body's completed landing")
  end
  local w, g, ts = fixture(0x30)
  -- Block the east destination without replacing the mover or permission code.
  ts.collision[10] = 0x07
  T.eq(w:resumeForcedMovement(), true, "blocked current still owns the input frame")
  T.eq(#w.scriptMoves, 0, "blocked current cannot queue a wall crossing")
  T.eq(w.player.moving, false, "blocked current cannot start interpolation")
  ts.collision[10] = 0xb1 -- destination's west wall
  T.eq(w:resumeForcedMovement(), true, "directional wall still retains forced ownership")
  T.eq(#w.scriptMoves, 0, "native destination side wall is respected")
  for _, field in ipairs({"transitioning", "fieldMove", "fishing", "headbutt", "mapSetup", "moveState", "battleActive"}) do
    w = fixture(0x30); w[field] = true
    T.eq(w:resumeForcedMovement(), false, "existing owner retains forced movement: " .. field)
    T.eq(#w.scriptMoves, 0, "owner cannot acquire an extra queue")
  end
  w, g = fixture(0x30); g.stack.states = {{}}
  T.eq(w:resumeForcedMovement(), false, "an overlay retains input ownership")
  w, g = fixture(0x30); w.player.moving = true
  T.eq(w:resumeForcedMovement(), false, "mid-step forced input cannot queue another move")
  w, g = fixture(0x30); w.runner:run({{"wait", 3}})
  T.eq(w:resumeForcedMovement(), false, "actual native runner retains ownership")
  w, g = fixture(0x23); w.turningDirection = "invalid"
  T.eq(w:resumeForcedMovement(), false, "invalid external latch is refused")
  w, g = fixture(0); w.turningDirection = "right"
  T.eq(w:resumeForcedMovement(), false, "ordinary floor remains ordinary input")
  T.eq(w.turningDirection, nil, "leaving ice retires the external travel latch")
  w, g = fixture(0x30)
  local native = w.scriptMove
  w.scriptMove = function() error("forced queue error") end
  T.eq(pcall(w.resumeForcedMovement, w), false, "native queue errors remain observable")
  w.scriptMove = native
  T.eq(w:resumeForcedMovement(), true, "queue error does not leave an admission lock")
end
for _, version in ipairs({"red", "emerald", "firered", "platinum"}) do
  V.set(version)
  local w = fixture(0x30); w.turningDirection = "left"
  T.eq(w:resumeForcedMovement(), false, "other generations retain their own movement path")
  T.eq(w.turningDirection, "left", "other-generation fields are untouched")
  T.eq(#w.scriptMoves, 0, "no Gen2 queue in another generation")
end
V.set(originalVersion); Sound.play = oldSound
debug.setupvalue(W.onStepComplete, slot, oldGame)
T.finish("native Gen2 forced movement after external body landing")
