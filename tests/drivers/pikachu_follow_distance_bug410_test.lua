-- Yellow's follower has to trail exactly one cell behind over a long walk
-- (#410).  ROUTE_1 column x=0 is 36 cells of plain path (tile $2c: no
-- grass, no ledge row, no object on it, per the generated ROUTE_1 blocks
-- and pokeyellow data/maps/objects/Route1.asm), so 32 steps north measure
-- the gap with nothing else moving.  Never add POKEPORT_SPEED here: it
-- scales the logic clock only, and the gap is a timing measurement.  No
-- POKEPORT_IDENTITY either: the Yellow cache lives in the default save dir.
--   POKEPORT_DRIVER=tests/drivers/pikachu_follow_distance_bug410_test.lua POKEPORT_TOUCH=0 POKEPORT_VERSION=yellow love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local PikachuFollower = require("src.world.PikachuFollower")

  local MAP = "ROUTE_1"
  local START = { x = 0, y = 34 }
  local STEPS = 32

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- ShouldPikachuSpawn wants the lab gift and a healthy party Pikachu; the
  -- level 100 lead plus a long REPEL is belt and braces, since the column
  -- below carries no grass tile and cannot roll an encounter anyway
  game.save.party = { Pokemon.new(game.data, "PIKACHU", 100) }
  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_GOT_STARTER = true
  game.save.onBike = false
  game.save.repelSteps = 9999
  game.save.player.name = "bryan"

  U.teleport(game, MAP, START.x, START.y, "up")
  U.wait(10)

  local ow = game.overworld
  local map = ow.map

  -- the run has to be walkable, grass-free and warp-free the whole way; a
  -- later map edit degrades to the longest column that still is, rather
  -- than walking the player into a fence for 500 frames
  local function runLength(cx, fromY)
    local n = 0
    local y = fromY
    while y >= 0 and map:isWalkableCell(cx, y) and not map:isGrassCell(cx, y)
          and not map:warpAtCell(cx, y) do
      n = n + 1
      y = y - 1
    end
    return n
  end

  if runLength(START.x, START.y) < STEPS + 1 then
    local best, bestX, bestY = 0, START.x, START.y
    for cx = 0, map.widthCells - 1 do
      for cy = map.heightCells - 1, 0, -1 do
        local n = runLength(cx, cy)
        if n > best then best, bestX, bestY = n, cx, cy end
      end
    end
    U.log(("column %d is short (%d cells); walking column %d from y=%d (%d cells)")
            :format(START.x, runLength(START.x, START.y), bestX, bestY, best))
    START.x, START.y = bestX, bestY
    STEPS = math.min(STEPS, best - 1)
    U.teleport(game, MAP, START.x, START.y, "up")
    U.wait(10)
    ow = game.overworld
    map = ow.map
  end
  check(("a straight %d step run exists at column %d"):format(STEPS, START.x),
        STEPS >= 30 and runLength(START.x, START.y) >= STEPS + 1)

  local function follower()
    for _, n in ipairs(ow.npcs or {}) do
      if n.pikachuFollower then return n end
    end
    return nil
  end

  check("the follower spawned on " .. MAP, follower() ~= nil)

  -- The far > 6 snap teleports the follower onto its goal and hides any
  -- drift the walk built up, so a broken run would read as a clean one.
  -- PikachuFollower.update is looked up on the module table at every call
  -- site, so wrapping the field here counts snaps without touching the
  -- engine: a cell that changes across the call while the follower is not
  -- mid-step is the snap and nothing else (a normal step lands its cell
  -- inside NPC:update, which OverworldState runs before this).
  local snaps, fastCommits = 0, 0
  local realUpdate = PikachuFollower.update
  PikachuFollower.update = function(g, o)
    local npc = follower()
    local bx, by, bmoving
    if npc then bx, by, bmoving = npc.cellX, npc.cellY, npc.moving end
    realUpdate(g, o)
    if npc and not bmoving and not npc.moving
       and (npc.cellX ~= bx or npc.cellY ~= by) then
      snaps = snaps + 1
    end
    if npc and not bmoving and npc.moving
       and (npc.stepFrames or 16) < (o.player.stepFramesCur or 16) then
      fastCommits = fastCommits + 1
    end
  end

  -- The distance sampled is the settled one: while a step is in flight the
  -- follower's committed cell is targetX/Y, which is where it will stand
  -- when the player's own landing frame is over.  Raw cell distance is
  -- kept alongside it so a report of 1 cannot come from reading the wrong
  -- field; it reads 2 all the way through a held walk, because both
  -- sprites are then mid-step, and settles to 1 the moment input stops.
  local function gap()
    local p = ow.player
    local npc = follower()
    if not npc then return -1, -1 end
    local pxc = p.targetX or p.cellX
    local pyc = p.targetY or p.cellY
    local nx = npc.targetX or npc.cellX
    local ny = npc.targetY or npc.cellY
    return math.abs(pxc - nx) + math.abs(pyc - ny),
           math.abs(p.cellX - npc.cellX) + math.abs(p.cellY - npc.cellY)
  end

  local series, raws = {}, {}
  local prevX, prevY = ow.player.cellX, ow.player.cellY
  local frames = 0
  while #series < STEPS and frames < STEPS * 40 do
    table.insert(game.input.pressQueue, "up")
    game.input.state.up = true
    frames = frames + 1
    coroutine.yield()
    local p = ow.player
    if p.cellX ~= prevX or p.cellY ~= prevY then
      prevX, prevY = p.cellX, p.cellY
      local g, r = gap()
      series[#series + 1] = g
      raws[#raws + 1] = r
    end
  end
  game.input.state.up = false
  U.wait(20) -- let the last follow step land before the final reading

  check(("all %d steps completed (%d recorded)"):format(STEPS, #series),
        #series == STEPS)

  local maxGap, badSteps = 0, 0
  for _, g in ipairs(series) do
    if g > maxGap then maxGap = g end
    if g ~= 1 then badSteps = badSteps + 1 end
  end
  local function avg(from, to)
    local sum, n = 0, 0
    for i = from, to do
      if series[i] then sum = sum + series[i] n = n + 1 end
    end
    return n > 0 and sum / n or 0
  end
  local head, tail = avg(1, 8), avg(#series - 7, #series)
  local finalGap, finalRaw = gap()

  local function compact(list)
    local out, row = {}, {}
    for i, g in ipairs(list) do
      row[#row + 1] = (g >= 0 and g < 10) and tostring(g) or ("[" .. g .. "]")
      if i % 40 == 0 then out[#out + 1] = table.concat(row) row = {} end
    end
    if #row > 0 then out[#out + 1] = table.concat(row) end
    return out
  end
  for _, row in ipairs(compact(series)) do U.log("gap per step:", row) end
  for _, row in ipairs(compact(raws)) do U.log("raw cell gap: ", row) end

  check("the gap is 1 on every step", badSteps == 0 and #series > 0)
  check(("max gap is 1 (saw %d)"):format(maxGap), maxGap == 1)
  check(("final gap is 1 (saw %d)"):format(finalGap), finalGap == 1)
  check(("Pikachu came to rest one cell behind (saw %d)"):format(finalRaw),
        finalRaw == 1)
  check(("no upward trend (first 8 avg %.2f, last 8 avg %.2f)")
          :format(head, tail), tail <= head)
  check(("the far > 6 snap never fired (%d)"):format(snaps), snaps == 0)
  U.log("fast (half length) follow steps committed:", fastCommits)

  PikachuFollower.update = realUpdate

  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  if U.shot(game, SHOT_DIR .. "/bug410_follow_distance.png") then
    U.log("captured", SHOT_DIR .. "/bug410_follow_distance.png")
  end

  U.log("Pikachu has just walked 32 cells up ROUTE_1 and should be standing")
  U.log("one cell below you, close enough to touch. Walk on and it stays")
  U.log("there; the bug left a visible cell of daylight between you.")

  while true do
    coroutine.yield()
  end
end
