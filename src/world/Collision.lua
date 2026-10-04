-- Movement permission checks: tile passability (from generated collision
-- data), map bounds, and entity occupancy.

local Runtime = require("src.mods.Runtime")

local Collision = {}

local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
Collision.DELTA = DELTA

function Collision.target(cx, cy, dir)
  local d = DELTA[dir]
  return cx + d[1], cy + d[2]
end

-- entities: array of anything with cellX/cellY (and optional targetX/targetY
-- while mid-step, so nobody walks into a cell being entered).
-- e.passable entities never block (Yellow's companion Pikachu: the player
-- walks straight through and it re-trails, pikachu_follow.asm).
-- Big objects (Snorlax, Lapras doll) occupy a 2x2 footprint on the grid.
-- Exposed because a seam proxy has to answer this the same way its owner
-- does (OverworldState:updateCast): two spellings of "big" would put a
-- Snorlax's second cell on one side of a connection and not the other.
-- WHICH WAY A STEP ACTUALLY TRAVELS, which is not always which way it looks.
--
-- Reported from play: "its hopping me forward instead of the direction i
-- pressed i still land on the right tile after the forward hop though".  Both
-- walkers interpolated a step as `DELTA[facing] * progress`, which is right
-- only while the two agree.  They stop agreeing the moment something sets
-- facingDirectionLocked -- the Acro Bike's side jump, and the muddy slope
-- that shoves you back down the hill still facing up it -- and then the
-- sprite slides along its NOSE for the whole step and teleports onto the
-- real cell at the end.  The cell was always right; only the 16 pixels
-- getting there were wrong.
--
-- The step's own target says it without being told: mid-step this engine
-- leaves cellX on the cell being left and targetX on the one being entered.
-- Normalised to one cell because the NPC walker scales by its own `span`.
-- Facing is the fallback for a step with no target at all, which is what the
-- two walkers used to do for every step.
function Collision.stepDelta(e)
  local dx = (e.targetX or e.cellX or 0) - (e.cellX or 0)
  local dy = (e.targetY or e.cellY or 0) - (e.cellY or 0)
  if dx == 0 and dy == 0 then
    local d = DELTA[e.facing]
    return d and d[1] or 0, d and d[2] or 0
  end
  if dx ~= 0 then dx = dx > 0 and 1 or -1 end
  if dy ~= 0 then dy = dy > 0 and 1 or -1 end
  return dx, dy
end

function Collision.isBig(e)
  return (e.big or (e.sprite and e.sprite.big)
          or (e.def and e.def.big)
          or (e.def and (e.def.sprite == "SPRITE_BIG_SNORLAX"
                         or e.def.sprite == "SPRITE_BIG_LAPRAS"))) and true
         or false
end

local function entityBlocks(e, cx, cy)
  local x, y = e.cellX, e.cellY
  if not (x and y) then return false end
  if Collision.isBig(e) then
    -- Origin cell is the top-left of the 2x2 (pret big object_event)
    return cx >= x and cx <= x + 1 and cy >= y and cy <= y + 1
  end
  if x == cx and y == cy then return true end
  if e.targetX == cx and e.targetY == cy then return true end
  return false
end

-- `e.of` is a SEAM PROXY'S owner: a body standing on a connected map, put
-- into these cells so that the two casts can see each other (see
-- OverworldState:updateCast).  A mover meeting its own proxy is meeting
-- itself, which is why the owner is tested alongside the entity.
-- AN OBJECT A SCRIPT TOOK OFF THE MAP IS NOT STILL STANDING THERE.
--
-- `hidden` was read by the DRAW pass and by nothing else, so a script's
-- `RemoveObject` made a character invisible and left their tile blocked for
-- the rest of the session.  Reported from play: *"he greets me at the door but
-- it won't let me in his house after"* -- Twinleaf's rival stands ON the warp
-- into his own house (the cartridge puts him there so he blocks it during his
-- scene), and the scene ends by removing him.  He went invisible; the doorway
-- stayed shut.  The same wall answered A, which is where the log's
-- "no text for Twinleaf Town/nil" came from: pressing A at the door talked to
-- somebody who was no longer in the game.
--
-- BURIED IS THE EXCEPTION AND IT IS NOT AN EDGE CASE.  Route 113's trainers
-- are under the ash: invisible and genuinely in the way, and they rise when
-- they spot you.  `buried` is kept precisely so "a script hid this" can be
-- told from "this is covered up", so it is the one hidden thing that still
-- blocks.
--
-- The engine already took this view in one place -- a seam proxy is built with
-- `passable = body.passable or body.hidden` -- so this is that rule applied
-- where it was missing rather than a new one.
local function entityAbsent(e)
  return e.hidden and not e.buried
end
Collision.entityAbsent = entityAbsent

function Collision.occupied(entities, cx, cy, ignore)
  for _, e in ipairs(entities) do
    if e ~= ignore and e.of ~= ignore and not e.passable and not entityAbsent(e) then
      if entityBlocks(e, cx, cy) then
        return e
      end
    end
  end
  return nil
end

-- Tile-pair (elevation) collisions: certain tile pairs can't be crossed
-- in a given tileset (cave/forest ledges).  data set via Collision.load.
local tilePairs = nil

function Collision.load(data)
  tilePairs = data.field and data.field.tilePairs or { land = {}, water = {} }
end

-- WHICH PAIR LIST APPLIES, and whether its rows still need naming.
--
-- The global list is the running game's, keyed by the plain tileset name. An
-- ADOPTED tileset carries its own -- brought across from the cartridge it came
-- out of, already filtered to itself (see AdoptedTileset) -- and its rows must
-- NOT be name-matched: the map's tileset is `CAVERN@red` and every row in it
-- says `CAVERN`, which is the mismatch that made an imported Cerulean Cave's
-- ledges walkable from every side.
--
-- The record's own list wins where it has one. A Gen 2 build has no global
-- pair list at all -- Crystal's `field.lua` has no `tilePairs` key, because
-- Gen 2 fences elevation with collision classes instead -- so for these maps
-- there is nothing to fall back TO.
local function pairList(map, mover)
  local key = mover.surfing and "water" or "land"
  local own = map.tileset and map.tileset.tilePairs
  local ownList = own and own[key]
  if ownList and #ownList > 0 then return ownList, true end
  if not tilePairs then return nil, false end
  return tilePairs[key], false
end

local function pairBlocked(map, mover, sx, sy, tx, ty)
  local list, preFiltered = pairList(map, mover)
  if not list or #list == 0 then return false end
  local tileset = map.def.tileset
  local a = map:cellTile(sx, sy)
  local b = map:cellTile(tx, ty)
  for _, p in ipairs(list) do
    if (preFiltered or p.tileset == tileset)
       and ((p.a == a and p.b == b) or (p.a == b and p.b == a)) then
      return true
    end
  end
  return false
end

-- One-way (directional) walls: Gen2 collision classes $b0-$b7 / $c0-$c7.
-- They are LAND/WATER in CollisionPermissionTable, so the passability test
-- above waves them through; what actually fences them is
-- GetMovementPermissions (home/map.asm), which reads the class of the cell
-- the mover is on plus the four around it and clears the direction bit for
-- whichever side is walled.  Skipping that is why the player could walk off
-- the north ledge of an Ice Path cliff instead of being stopped at its lip.
--
-- Two halves, matching the ROM: the standing tile blocks stepping OUT over
-- its walled side, and the destination tile blocks stepping IN through it.
local OPPOSITE = { up = "down", down = "up", left = "right", right = "left" }

-- Collision.lua
local function sideWallBlocked(map, mover, dir, tx, ty)
  if not map.sideWallAt then return false end
  local out = map:sideWallAt(mover.cellX, mover.cellY)
  if out and out[dir] then return true end
  -- only examine the destination cell when it actually exists
  if not map:inBounds(tx, ty) then return false end
  local into = map:sideWallAt(tx, ty)
  return (into and into[OPPOSITE[dir]]) == true
end

local function verdict(map, entities, mover, dir, tx, ty)
  -- directional walls must be tested before the bounds short-circuit;
  -- otherwise an Ice Path cliff that faces the map edge is treated as a
  -- pure “bounds” case and the connection/edge-warp logic can fire.
  if sideWallBlocked(map, mover, dir, tx, ty) then
    return false, "tile"
  end
  if not map:inBounds(tx, ty) then
    return false, "bounds"
  end
  if mover.onBike and map.runningBlockedAt and map:runningBlockedAt(tx, ty) then
    return false, "tile"
  end
  if not map:isWalkableCell(tx, ty) then
    if not (mover.surfing and map:isWaterCell(tx, ty)) then
      return false, "tile"
    end
  end
  -- THE OTHER HALF OF A GEN 3 MAP CELL.
  --
  -- Collision alone does not keep anyone out of the water in Hoenn: the sea
  -- is passable ground with an elevation of 1, and dry land is elevation 3.
  -- The cartridge refuses a step between two different non-zero elevations,
  -- and that is the whole of "you cannot walk onto water", "you cannot step
  -- off a cliff" and "the bridge and the river beneath it are different
  -- places".  Maps that carry no elevation -- every Gen 1 and Gen 2 map --
  -- answer nil here and nothing changes for them.
  if map.elevationBlocks and map:elevationBlocks(mover.elevation, tx, ty) then
    -- ...except getting OFF the water.  The cartridge turns exactly this
    -- mismatch into COLLISION_STOP_SURFING when the cell ahead is land the
    -- surfer can stand on, which is how you come ashore anywhere along a
    -- coast rather than only where the map says so.
    local landing = mover.surfing and map.isWaterCell
                    and map:isWalkableCell(tx, ty) and not map:isWaterCell(tx, ty)
    if not landing then
      return false, "elevation"
    end
  end
  -- THE ACRO BIKE TILES ARE WALLS TO EVERYONE ELSE.
  --
  -- Emerald's CheckAcroBikeCollision runs only where the ordinary collision
  -- came back NONE -- which is why it sits here, after the walkable and
  -- elevation tests -- and turns five behaviours into a collision code.  On
  -- foot, PlayerNotOnBikeMoving bumps on every one of them; the trick that
  -- passes each is the rider's, and the port has no Acro Bike yet, so today
  -- this is always a wall.  That IS the cartridge's answer for a player on
  -- foot, which is every player the port can currently be.
  if map.acroObstacleAt then
    local obstacle = map:acroObstacleAt(tx, ty)
    if obstacle and not Collision.acroTrickPasses(mover, obstacle, dir) then
      return false, "tile"
    end
    -- ...and the rail under the rider, asked whatever is ahead
    if Collision.railHolds(map, mover, dir) then
      return false, "tile"
    end
  end
  if pairBlocked(map, mover, mover.cellX, mover.cellY, tx, ty) then
    return false, "tile"
  end
  if Collision.occupied(entities, tx, ty, mover) then
    return false, "entity"
  end
  return true
end

-- ONE TILE OF A TRAINER'S LINE OF SIGHT.
--
-- Asked for directly: "they also see me through each other".  They did, and
-- through the gym wall beside them too: the sight test was a facing, a shared
-- row or column and a pixel range, and nothing at all about what stood in
-- between.
--
-- The cartridge checks the gap tile by tile.  CheckPathBetweenTrainerAndPlayer
-- (0B3FB0) steps from the trainer towards the player, calls
-- GetCollisionFlagsAtCoords (092C8C) on each tile short of the player, and
-- gives up on `collision ~= 0 and (collision & ~1) ~= 0`.  That mask is the
-- whole rule, and it is worth spelling out because the flags are not the
-- collision CODES they look like (092C8C, read bottom-up):
--
--     1  the tile is outside the WATCHER'S OWN movement range
--     2  impassable metatile, off the map, or a wall facing this way
--     4  a different elevation from the one the watcher is standing at
--     8  another object event is standing there
--
-- ...and `& ~1` drops the first: a trainer sees past the edge of its own
-- wander box, which it must, or a trainer with a one-tile range could never
-- spot anybody.  The other three all stop the line, which is the sentence
-- above -- a wall, a ledge to another level, or ANOTHER NPC.
--
-- The player is never one of the tiles this is asked about: the walk covers
-- the tiles strictly between, and the far end is the player by construction
-- (the cartridge's own last step is a separate test for exactly that).
function Collision.sightBlocked(map, entities, watcher, dir, sx, sy, tx, ty)
  if sideWallBlocked(map, watcher, dir, tx, ty) then return true end
  if not map:inBounds(tx, ty) then return true end
  if not map:isWalkableCell(tx, ty) then return true end
  if pairBlocked(map, watcher, sx, sy, tx, ty) then return true end
  if map.elevationBlocks and map:elevationBlocks(watcher.elevation, tx, ty) then
    return true
  end
  if Collision.occupied(entities, tx, ty, watcher) then return true end
  return false
end

-- The whole gap, from the watcher to one tile short of the player.
--
-- `dist` is in cells and is at least 1; a trainer standing next to the player
-- has no gap to walk and is always clear, which is the cartridge's
-- `approachDistance - 1` loop count.
function Collision.sightPathClear(map, entities, watcher, dir, dist)
  local x, y = watcher.cellX, watcher.cellY
  for _ = 1, (tonumber(dist) or 0) - 1 do
    local tx, ty = Collision.target(x, y, dir)
    if Collision.sightBlocked(map, entities, watcher, dir, x, y, tx, ty) then
      return false
    end
    x, y = tx, ty
  end
  return true
end

-- Whether the mover is doing the Acro Bike trick that makes one of the five
-- obstacle behaviours passable.
--
-- BOTH MOVING TRICKS PASS A BUMPY SLOPE.  The rule here used to want a hop
-- for it, but the cartridge's two moving transitions agree:
-- WheelieHoppingMoving carries on through COLLISION_WHEELIE_HOP, and
-- WheelieMoving does too.  What neither of them passes is an ISOLATED rail --
-- the one-cell kind you can only reach with a sideways jump -- so those are a
-- wall to a rider coming at them, trick or no trick.
--
--   a bumpy slope is passable while hopping OR wheelieing
--   a full rail is ridden ALONG ITS AXIS, either way, and is a wall across it
--   an isolated rail is not entered by moving into it at all
--
-- `mover.acroBike` is what the Acro Bike sets and `mover.acroTrick` is the
-- trick in progress -- "wheelie" from the moment B goes down, "hop" only once
-- the wheelie has been held past its own threshold (see
-- OverworldState:updateAcroBike).
local ACRO_AXIS_DIRS = {
  vertical   = { up = true, down = true },
  horizontal = { left = true, right = true },
}

-- WHO MAY MOVE ONTO ONE, WHICH IS NOT WHAT THIS USED TO SAY.
--
-- Reported from play: "for these tiles that are bike paths above water areas
-- like in route 119 you should be able to ride on them on the bike, and if
-- using the acro bike while bunny hopping and holding a direction bunny hop
-- between them to get through the paths".  You could not ride them at all:
-- this asked for the Acro Bike AND a trick AND a direction along the rail,
-- and the cartridge asks for none of the three.
--
-- THE CARTRIDGE'S OWN CHAIN, read end to end.  CheckAcroBikeCollision
-- (008B2E4) runs inside the shared CheckForObjectEventCollision wherever the
-- ordinary collision came back NONE, and turns the five behaviours into a
-- code out of its own two tables (0849749C and 084974B0):
--
--     bumpy slope                9
--     isolated vertical rail    10
--     isolated horizontal rail  11
--     vertical rail             12
--     horizontal rail           13
--
-- Any non-zero code stops ordinary movement, which is why all five are walls
-- on foot.  What differs is what each BIKE TRANSITION does with the code:
--
--   AcroBikeTransition_Moving        (011987A)  0 or >11 -> move
--   MachBikeTransition_TrySpeedUp    (01192D8)  0 or >11 -> move
--   AcroBike WheelieMoving           (0119AEE)  0 or >11 -> move; 9 -> stay
--   AcroBike WheelieHoppingMoving    (01199EE)  0, 9, or >11 -> move
--
-- So a FULL RAIL (12 or 13) is ridden by EITHER BIKE with no trick at all and
-- in any direction -- the rail is a road, not an obstacle -- and the BUMPY
-- SLOPE (9) wants the BUNNY HOP specifically: a wheelie on one stands still
-- (PlayerIdleWheelie), which is the half this port had as "either trick".
--
-- The ISOLATED rails (10, 11) are entered by NOTHING that moves.  They are
-- crossed by the Acro Bike's SIDE JUMP -- a perpendicular direction tapped
-- and released inside six frames (AcroBikeHandleInputTurning, 01194D4),
-- which leaps two tiles (0119A24) -- and a jump is not a step, so it never
-- comes through here.  Refusing them is right until that lands.
--
-- What keeps a rider ON a rail is a different rule about a different tile:
-- see Collision.railHolds below.
function Collision.acroTrickPasses(mover, obstacle, dir)
  if not obstacle then return true end
  if not mover then return false end
  if obstacle.isolated then return false end
  if obstacle.axis then
    -- a full rail: a road for either bike, and a wall to anyone on foot
    return (mover.acroBike or mover.machBike) and true or false
  end
  -- the bumpy slope, which is the Acro Bike's and wants the hop
  return (mover.acroBike and mover.acroTrick == "hop") and true or false
end

-- ...AND THE RAIL YOU ARE ALREADY ON ONLY RUNS ONE WAY.
--
-- CanBikeFaceDirOnMetatile (0119F74) is asked by every one of the four bike
-- transitions above, BEFORE the collision is, and it reads the tile UNDER the
-- rider rather than the one ahead: east or west is refused on a vertical
-- rail, north or south on a horizontal one, isolated or not.  That is what
-- makes a rail a path -- you get on, and then it carries you -- and it is the
-- half whose absence made "enter only along the axis" look almost right while
-- keeping the rider off the rail altogether.
--
-- It is a BIKE rule and needs no on-foot arm: on foot you cannot be standing
-- on one of these, because acroTrickPasses refused you the step onto it.
function Collision.railHolds(map, mover, dir)
  if not (map and mover and (mover.acroBike or mover.machBike)) then
    return false
  end
  if not map.acroObstacleAt then return false end
  local here = map:acroObstacleAt(mover.cellX, mover.cellY)
  if not (here and here.axis) then return false end
  local along = ACRO_AXIS_DIRS[here.axis]
  return not (along and along[dir])
end

-- THE SIDE JUMP, which is how you actually get from one rail to the next.
--
-- Reported from play: "The bunny hopping doesnt work to move between the
-- rails, and its letting me turn the bike vertically when i dont think it
-- should while on these rails double check the rom on how this should
-- function."  The rom says the bunny hop never crosses anything: the
-- BUNNY_HOP state handler (01195E0) answers only FACE_DIRECTION, HOPPING
-- STANDING, HOPPING MOVING or MOVING, and HOPPING MOVING asks
-- CanBikeFaceDirOnMetatile first, so a rider hopping on a rail is held on it
-- exactly like a rider who is not.
--
-- What crosses is sAcroBikeTransitions[8], AcroBikeTransition_SideJump
-- (0119A24), reached ONLY from the TURNING state (01194C8) -- which state 0
-- enters when a direction that is not the rider's facing arrives while the
-- rider is not already moving.  TURNING lasts six frames; inside them,
-- AcroBike_GetJumpDirection (0119D30) walks a four-row table at 0x085974C0:
--
--     dirHistory  & 0xF == the direction        (SOUTH/NORTH/WEST/EAST)
--     abHistory   & 0xF == 2                    (B, and only B, of ABSS)
--     both of those histories no older than four frames (0x085974BE = {4,0})
--
-- The histories only rotate when their value CHANGES (0119C64), so "no older
-- than four frames" means each was PRESSED four frames ago or less -- B held
-- down since before the tap does not qualify, which is the other half of why
-- hopping across cannot work.  The press that does it is the direction and B
-- together.  Matching direction that is the OPPOSITE of facing is a turn
-- jump instead (transition 9); anything else perpendicular is this.
--
-- IT IS ONE TILE, AND IT DOES NOT TURN YOU.  Reported from play: "When
-- hopping between them its making me jump 2 at once instead of one at a
-- time, and its changing me to face the direction im moving in when it
-- shouldnt".  Both are the cartridge's, and both were read off the wrong
-- routine here first:
--
--   * SideJump ends in 0093514, whose ids are 0x42..0x45, whose init is
--     InitJump(..., distance = 1, ...).  THE LEDGE is the two-tile one --
--     PlayerJumpLedge (008B840) ends in 0093490, ids 0x0C..0x0F, distance 2
--     -- and the two were conflated.  InitJump's own table settles it
--     (0x0850DFBC = {0,1,1} placed, 0x0850DFC2 = {0,0,1} added on landing:
--     distance 1 is one tile, distance 2 is two).
--
--   * SideJump sets facingDirectionLocked before it asks for the movement
--     (`ldrb r0,[r4,#1] / orr r0,#2 / strb r0,[r4,#1]` at 0119A6C, bit 9 of
--     the ObjectEvent bitfield).  The rider leaps sideways STILL FACING the
--     way they were going.
--
-- ...and the two together are what make a crossing possible at all.  The
-- jump is chosen only when the press is PERPENDICULAR to facing, so a facing
-- that followed the leap would make the second hop of a chain no longer
-- perpendicular and the chain would stop after one stone.  MAP_G00_N34 is
-- built entirely out of that chain: a vertical rail at x4 carries the rider
-- south to row 10, three ISOLATED vertical rails sit at x5..x7, and another
-- full vertical rail at x8 carries them on south -- so the crossing is three
-- eastward hops taken one stone at a time, all of them still facing south.
--
-- What the jump may clear, from SideJump's own head -- and with one tile of
-- travel, the tile it clears IS the tile it lands on:
--
--     collision 0        -> jump          (an ordinary empty tile)
--     collision 7        -> nothing at all
--     collision 1..9     -> TurnDirection (a wall, or the bumpy slope)
--     collision 10..13   -> jump IFF 0119FC4 says so
--
-- and 0119FC4 is one rule stated twice: a north/south leap is refused onto a
-- VERTICAL rail (10, 12) and an east/west leap onto a HORIZONTAL one (11,
-- 13).  A rail running the way you are jumping is a road you should be
-- riding; a rail running across your leap is the stepping stone.
local JUMP_AXIS = {
  up = "vertical", down = "vertical",
  left = "horizontal", right = "horizontal",
}

-- Returns the landing cell for an Acro Bike side jump toward `dir`, or nil.
-- The caller owns the trigger (perpendicular, tapped, B down, standing
-- still); this owns the geometry.
function Collision.acroSideJump(map, entities, mover, dir)
  if not (map and mover and mover.acroBike) then return nil end
  local axis = JUMP_AXIS[dir]
  if not axis then return nil end

  local fx, fy = Collision.target(mover.cellX, mover.cellY, dir)
  if not (map.inBounds and map:inBounds(fx, fy)) then return nil end

  -- CheckAcroBikeCollision runs only where the ORDINARY collision came back
  -- NONE (008B124), so a rail metatile that is itself impassable -- and
  -- MAP_G00_N34 row 11 is four of them, sitting directly under the stepping
  -- stones -- never reaches the rail arm at all: it answers 1..6 and SideJump
  -- turns on it.  That is this test, and it has to come first.
  if not (map.isWalkableCell and map:isWalkableCell(fx, fy)) then
    return nil
  end
  local onto = map.acroObstacleAt and map:acroObstacleAt(fx, fy)
  if onto then
    -- a bumpy slope (9) is not jumped; a rail is, unless it runs our way
    if not onto.axis then return nil end
    if onto.axis == axis then return nil end
  end
  if Collision.occupied(entities, fx, fy, mover) then return nil end

  return fx, fy
end

-- the movement.collision chain sees the boolean; a wrapper that flips it
-- rewrites ctx.reason to say why (the engine's own reasons are bounds /
-- tile / entity), so the hook stays a single-value middleware
local function passthrough(allowed) return allowed end

-- THE SAME VERDICT, ASKED ABOUT A CELL INSTEAD OF A DIRECTION.
--
-- MOTIVATED BY THE CLIFF BESIDE ROUTE 114'S METEOR FALLS MOUTH, which a
-- free-walking camera could climb.  Reported from play: "when using first and
-- third person into caves im getting an issue where it makes me move on top
-- of the cliff instead of going into the cave entrance. shouldnt be able to
-- climb on top of cliffs either in first or third person".
--
-- `verdict` has always taken an explicit target -- canMove merely derives one
-- from a direction -- and everything above it is the real step test: the
-- one-way walls, the bounds, the passability, the ELEVATION, the acro tiles
-- and rails, the tile pairs, the occupancy.  What there was no way to do from
-- outside this file was ask that question about a cell you name yourself.
--
-- A caller that moves CONTINUOUSLY has to.  A grid step is always one cell in
-- one of four directions, so a direction IS a target; a body with a radius
-- sliding along a wall overlaps up to two cells per axis, and has to ask about
-- each of them.  Without this, such a caller has no choice but to restate the
-- test -- and a restatement is a copy that stops being true the day a clause
-- is added here.  That is exactly what had happened: the voxel mod's free walk
-- reimplemented four of these seven tests and silently lost the other three,
-- so in first and third person Hoenn had no elevation at all -- 4,376 cliff
-- steps and 3,704 water steps across 107 maps that the grid walk refuses.
--
-- `dir` is the AXIS BEING CROSSED, not the bearing to the cell: a body sliding
-- east asks "right" about every cell on its leading edge, including the one
-- diagonally ahead, because east is the way it is going through that
-- boundary.  That is the reading sideWallBlocked and railHolds want -- both
-- are about which SIDE is fenced -- and it is the only one a diagonal probe
-- has, since the mover crosses one axis at a time.  A caller with no axis to
-- name may pass nil: the two direction-keyed tests then look up a nil key,
-- find nothing, and the other five answer in full.
--
-- Returns the same pair `verdict` does: true, or false plus the reason.
function Collision.mayEnter(map, entities, mover, tx, ty, dir)
  local allowed, why = verdict(map, entities, mover, dir, tx, ty)
  if Runtime.wantsHook("movement.collision") then
    local ctx = { map = map, mover = mover, dir = dir,
                  fromX = mover.cellX, fromY = mover.cellY,
                  toX = tx, toY = ty, reason = why }
    allowed = Runtime.call("movement.collision", passthrough, allowed, ctx)
    why = ctx.reason
  end
  return allowed, why
end

-- Returns true when the mover may step from (cx,cy) toward dir.
-- Out-of-bounds is blocked here; the OverworldController handles map
-- connections and edge warps before asking.  Per-step hot path: with an
-- empty chain this costs one table lookup and no ctx allocation.
function Collision.canMove(map, entities, mover, dir)
  local tx, ty = Collision.target(mover.cellX, mover.cellY, dir)
  local allowed, why = Collision.mayEnter(map, entities, mover, tx, ty, dir)
  if allowed then return true end
  return false, why
end

return Collision
