-- Parity: scripted NPC exit walks must stay on walkable ground and must never
-- route through the player's parking cell (#236, #241).  scriptMove is a pure
-- tween with no collision, like pokered's MoveSprite, so the movement lists
-- are the only thing keeping an NPC out of solid world.  #236 picks the
-- Route 22 exit list off wSavedCoordIndex (home/map_objects.asm:107); #241
-- never walks the Pewter guide home (PewterCity.asm:133 + SetSpritePosition2).

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local Data = require("src.core.Data")
if not (Data.maps and Data.maps.ROUTE_22) then Data:load() end
local MapLoader = require("src.world.MapLoader")

local S = require("tests.harness").suite("parity npc exit clearance")
local check, eq = S.check, S.eq

-- restored at the bottom for the suites run after this file
local realMusic = package.loaded["src.core.Music"]
local realCommands = package.loaded["src.script.Commands"]
local realPicBox = package.loaded["src.ui.PicBox"]
local realTextBox = package.loaded["src.render.TextBox"]
package.loaded["src.core.Music"] = {
  play = function() end, playMap = function() end,
  playOnce = function() return true end, stop = function() end,
}
package.loaded["src.script.Commands"] = { hide_object = function() end }
package.loaded["src.ui.PicBox"] = { new = function() return {} end }
-- the mock stack below runs a TextBox's continuation the moment it is handed
-- one, so the whole callback chain (escort -> "take on BROCK" -> walk home)
-- plays out inside one call with no frame pump
package.loaded["src.render.TextBox"] = {
  new = function(_, s, done) return { text = s, done = done } end,
}

local story5 = dofile("data/scripts/story5.lua")

local DIRV = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

-- Replay a movement list one cell at a time.  `avoid` is the player's parking
-- cell: pokered's lists are authored so the NPC walks around him.
local function replay(map, sx, sy, dirs, avoid, label)
  local x, y = sx, sy
  for i, d in ipairs(dirs) do
    local v = DIRV[d]
    check(v ~= nil, ("%s step %d is a real direction (%s)"):format(label, i, tostring(d)))
    if not v then return x, y end
    x, y = x + v[1], y + v[2]
    check(map:isWalkableCell(x, y),
          ("%s step %d (%s) lands on walkable ground at (%d,%d)")
            :format(label, i, d, x, y))
    check(not (x == avoid.x and y == avoid.y),
          ("%s step %d (%s) does not walk through the player on (%d,%d)")
            :format(label, i, d, avoid.x, avoid.y))
  end
  return x, y
end

-- ------------------------------------------------------------ #236
-- Route 22: both ambush tiles, both rivals.
do
  local r22 = MapLoader.load(Data, "ROUTE_22")

  -- ground truth first, so a later map/tileset change reads as "the cliff
  -- moved" rather than as a script regression
  check(not r22:isWalkableCell(28, 3),
        "ROUTE_22 (28,3) is the cliff face, not walkable (the #236 crash site)")
  check(not r22:isWalkableCell(30, 7),
        "ROUTE_22 (30,7) is solid too (the old y=5 branch crossed it)")
  for x = 28, 31 do
    for y = 4, 5 do
      check(r22:isWalkableCell(x, y),
            ("ROUTE_22 (%d,%d) is walkable ambush ground"):format(x, y))
    end
  end
  check(r22:isWalkableCell(31, 10),
        "ROUTE_22 (31,10) is walkable (pokered's exit end cell)")

  -- the object_event spawn both rivals share
  local spawn
  for _, o in ipairs(Data.maps.ROUTE_22.objects or {}) do
    if o.name == "ROUTE22_RIVAL1" then spawn = o end
  end
  check(spawn ~= nil, "ROUTE22_RIVAL1 has an object_event")
  eq(spawn and spawn.x, 25, "ROUTE22_RIVAL1 spawns at x=25")
  eq(spawn and spawn.y, 5, "ROUTE22_RIVAL1 spawns at y=5")

  -- drive onStep the way ScriptRunner would: capture the queued rows without
  -- executing them
  local function capture(game, x, y)
    local rows
    local ow = {
      runner = {
        isRunning = function() return false end,
        run = function(_, r) rows = r end,
      },
      player = { facing = "down" },
      npcByIndex = function() return { def = { name = "X" } } end,
    }
    check(story5.ROUTE_22.onStep(game, ow, x, y),
          ("ROUTE_22 onStep fires at (%d,%d)"):format(x, y))
    return rows, ow.player.facing
  end

  local function row(rows, name)
    for _, r in ipairs(rows or {}) do
      if r[1] == name then return r end
    end
  end

  -- (trigger y, expected end cell) for rival 1; rival 2 always ends back
  -- on his spawn because Route22Rival2ExitMovementData1 falls through
  -- into Data2 (Route22.asm:355).
  local cases = {
    { n = 1, y = 4, endX = 31, endY = 10,
      flags = { EVENT_GOT_POKEDEX = true } },
    { n = 1, y = 5, endX = 31, endY = 10,
      flags = { EVENT_GOT_POKEDEX = true } },
    { n = 2, y = 4, endX = 25, endY = 5,
      flags = { EVENT_BEAT_BROCK = true,
                EVENT_BEAT_ROUTE22_RIVAL_1ST_BATTLE = true,
                EVENT_BEAT_GIOVANNI = true } },
    { n = 2, y = 5, endX = 25, endY = 5,
      flags = { EVENT_BEAT_BROCK = true,
                EVENT_BEAT_ROUTE22_RIVAL_1ST_BATTLE = true,
                EVENT_BEAT_GIOVANNI = true } },
  }

  for _, c in ipairs(cases) do
    local tag = ("rival%d from (29,%d)"):format(c.n, c.y)
    local rows, playerFacing =
      capture({ save = { flags = c.flags }, data = {} }, 29, c.y)
    local moveTo = row(rows, "move_npc_to")
    local face = row(rows, "face_object")
    local walk = row(rows, "walk_npc")
    check(moveTo and face and walk, tag .. ": scene has move/face/walk rows")
    if moveTo and face and walk then
      local rx, ry = moveTo[3], moveTo[4]
      -- Route22MoveRivalRightScript only ever walks him RIGHT along his
      -- own spawn row, so he cannot end up anywhere but row 5.
      eq(ry, 5, tag .. ": rival stops on his own row 5")
      check(r22:isWalkableCell(rx, ry),
            ("%s: rival stops on walkable ground (%d,%d)"):format(tag, rx, ry))
      check(not (rx == 29 and ry == c.y),
            tag .. ": rival does not stop on top of the player")
      check(math.abs(rx - 29) + math.abs(ry - c.y) == 1,
            tag .. ": rival stops in a cell adjacent to the player")

      -- the two sprites have to be looking at each other, or the battle text
      -- reads as a conversation with empty air
      local fv = DIRV[face[3]]
      check(fv and rx + fv[1] == 29 and ry + fv[2] == c.y,
            ("%s: rival faces %s, straight at the player"):format(tag, tostring(face[3])))
      local pv = DIRV[playerFacing]
      check(pv and 29 + pv[1] == rx and c.y + pv[2] == ry,
            ("%s: player is turned %s, straight at the rival")
              :format(tag, tostring(playerFacing)))

      local ex, ey = replay(r22, rx, ry, walk[3], { x = 29, y = c.y }, tag .. " exit")
      eq(ex, c.endX, tag .. ": exit ends at x=" .. c.endX)
      eq(ey, c.endY, tag .. ": exit ends at y=" .. c.endY)
    end
  end
end

-- ------------------------------------------------------------ #241
-- Pewter City: the gym guide's walk after the escort.
do
  local pew = MapLoader.load(Data, "PEWTER_CITY")

  check(pew:isWalkableCell(11, 18), "PEWTER_CITY (11,18) is the player's parking cell")
  check(pew:isWalkableCell(12, 18), "PEWTER_CITY (12,18) is where the escort leaves the guide")
  for x = 13, 17 do
    check(pew:isWalkableCell(x, 18),
          ("PEWTER_CITY (%d,18) is walkable gym road"):format(x))
  end
  -- why the original teleports him instead of walking him home: (17,18)
  -- is a dead-end pocket, so there is no route out that misses the player
  check(not pew:isWalkableCell(18, 18), "PEWTER_CITY (18,18) is the fence")
  check(not pew:isWalkableCell(17, 17), "PEWTER_CITY (17,17) is wall")

  local spawn
  for _, o in ipairs(Data.maps.PEWTER_CITY.objects or {}) do
    if o.name == "PEWTERCITY_YOUNGSTER" then spawn = o end
  end
  check(spawn ~= nil, "PEWTERCITY_YOUNGSTER has an object_event")
  eq(spawn and spawn.x, 35, "PEWTERCITY_YOUNGSTER spawns at x=35")
  eq(spawn and spawn.y, 16, "PEWTERCITY_YOUNGSTER spawns at y=16")

  -- Run the escort through a mock overworld.  scriptMove lands synchronously
  -- here instead of over 16 frames, and the real pump advances guide and
  -- player in the same frame, so only per-entity cell SEQUENCES are
  -- meaningful, which is all these assertions read.
  local function runEscort(tx, ty)
    local moves = {}
    local guy = { cellX = spawn.x, cellY = spawn.y, facing = "down", moving = false }
    local player = { cellX = tx, cellY = ty, facing = "left" }
    local game = {
      data = { text = {} },
      save = { flags = {} },
      stack = { push = function(_, box) if box.done then box.done() end end },
    }
    local ow = {
      scriptMoves = {},
      runner = { isRunning = function() return false end },
      player = player,
      npcByIndex = function(_, i) return (i == 5) and guy or nil end,
      scriptMove = function(_, ent, dir, tiles, onDone)
        local v = DIRV[dir]
        for _ = 1, (tiles or 1) do
          ent.cellX, ent.cellY = ent.cellX + v[1], ent.cellY + v[2]
        end
        ent.facing = dir
        moves[#moves + 1] = {
          who = (ent == guy) and "guy" or "player",
          dir = dir, x = ent.cellX, y = ent.cellY,
        }
        if onDone then onDone() end
      end,
    }
    story5.PEWTER_CITY.talk.TEXT_PEWTERCITY_YOUNGSTER(game, ow, guy, nil)
    return moves, guy, player
  end

  -- PewterGymGuyCoords: every tile that arms the escort
  for _, trig in ipairs({ { 35, 17 }, { 36, 17 }, { 37, 18 }, { 37, 19 }, { 34, 16 } }) do
    local tag = ("guide from (%d,%d)"):format(trig[1], trig[2])
    local moves, guy, player = runEscort(trig[1], trig[2])
    check(#moves > 0, tag .. ": the escort actually walked")

    -- the escort's landing pair decides what the walk home has to avoid
    local lastPlayer
    for i, m in ipairs(moves) do
      if m.who == "player" then lastPlayer = i end
    end
    check(lastPlayer ~= nil, tag .. ": the player was walked too")
    eq(player.cellX, 11, tag .. ": player parks on x=11")
    eq(player.cellY, 18, tag .. ": player parks on y=18")

    -- everything after the player's last step is the walk home
    local home = {}
    for i = (lastPlayer or 0) + 1, #moves do
      check(moves[i].who == "guy", tag .. ": only the guide moves after the escort")
      home[#home + 1] = moves[i]
    end
    eq(#home, 5, tag .. ": MovementData_PewterGymGuyExit is five steps")
    local hx, hy = 12, 18
    for i, m in ipairs(home) do
      eq(m.dir, "right", ("%s: exit step %d is RIGHT"):format(tag, i))
      local v = DIRV[m.dir] or { 0, 0 }
      hx, hy = hx + v[1], hy + v[2]
      check(pew:isWalkableCell(hx, hy),
            ("%s: exit step %d lands on walkable ground (%d,%d)")
              :format(tag, i, hx, hy))
      check(not (hx == 11 and hy == 18),
            ("%s: exit step %d does not walk through the player on (11,18)")
              :format(tag, i))
    end
    eq(hx, 17, tag .. ": the exit ends on x=17")
    eq(hy, 18, tag .. ": the exit ends on y=18")

    -- SetSpritePosition2 + ShowObject: back on the object_event spawn
    eq(guy.cellX, spawn.x, tag .. ": guide is snapped back to spawn x")
    eq(guy.cellY, spawn.y, tag .. ": guide is snapped back to spawn y")
    eq(guy.facing, "down", tag .. ": guide faces DOWN again at his spawn")
    -- npcAtCell (OverworldController.lua:1451) also matches on targetX/Y, so
    -- a teleport that leaves them set reserves the vacated cell forever and
    -- silently walls the player out of the pocket
    eq(guy.targetX, nil, tag .. ": the snap clears targetX")
    eq(guy.targetY, nil, tag .. ": the snap clears targetY")
    eq(guy.moving, false, tag .. ": the snap clears the moving flag")
  end
end

package.loaded["src.core.Music"] = realMusic
package.loaded["src.script.Commands"] = realCommands
package.loaded["src.ui.PicBox"] = realPicBox
package.loaded["src.render.TextBox"] = realTextBox

S.finish()
