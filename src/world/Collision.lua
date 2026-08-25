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
local function entityBlocks(e, cx, cy)
  local x, y = e.cellX, e.cellY
  if not (x and y) then return false end
  local big = e.big or (e.sprite and e.sprite.big)
    or (e.def and e.def.big)
    or (e.def and (e.def.sprite == "SPRITE_BIG_SNORLAX"
                   or e.def.sprite == "SPRITE_BIG_LAPRAS"))
  if big then
    -- Origin cell is the top-left of the 2x2 (pret big object_event)
    return cx >= x and cx <= x + 1 and cy >= y and cy <= y + 1
  end
  if x == cx and y == cy then return true end
  if e.targetX == cx and e.targetY == cy then return true end
  return false
end

function Collision.occupied(entities, cx, cy, ignore)
  for _, e in ipairs(entities) do
    if e ~= ignore and not e.passable then
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
  if not map:isWalkableCell(tx, ty) then
    if not (mover.surfing and map:isWaterCell(tx, ty)) then
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

-- the movement.collision chain sees the boolean; a wrapper that flips it
-- rewrites ctx.reason to say why (the engine's own reasons are bounds /
-- tile / entity), so the hook stays a single-value middleware
local function passthrough(allowed) return allowed end

-- Returns true when the mover may step from (cx,cy) toward dir.
-- Out-of-bounds is blocked here; the OverworldController handles map
-- connections and edge warps before asking.  Per-step hot path: with an
-- empty chain this costs one table lookup and no ctx allocation.
function Collision.canMove(map, entities, mover, dir)
  local tx, ty = Collision.target(mover.cellX, mover.cellY, dir)
  local allowed, why = verdict(map, entities, mover, dir, tx, ty)
  if Runtime.wantsHook("movement.collision") then
    local ctx = { map = map, mover = mover, dir = dir,
                  fromX = mover.cellX, fromY = mover.cellY,
                  toX = tx, toY = ty, reason = why }
    allowed = Runtime.call("movement.collision", passthrough, allowed, ctx)
    why = ctx.reason
  end
  if allowed then return true end
  return false, why
end

return Collision
