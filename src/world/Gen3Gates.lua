-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE ROTATING GATES, which were read out of the cartridge and then read by
-- nothing at all.
--
-- `constants.gen3RotatingGates` has been in the cache for a while -- nineteen
-- gates over two puzzles, eight shapes, their arm tables, their pictures,
-- four rotation grids and two sweep tables -- and not one line of the port
-- ever looked at it.  That is the dominant shape of this project's Gen 3
-- bugs: not "extracted wrong" but "extracted correctly and read by nothing".
-- Fortree Gym is the visible half of it -- its whole puzzle is these gates,
-- and with none of them there the room is an empty hall you stroll across --
-- and the Trick House's eighth puzzle is the other.
--
-- WHAT A GATE IS, and every part of it is the cartridge's:
--
--   * a PIVOT, which is a CORNER rather than a cell.  The collision test
--     (080FBEF0) takes the four-by-four block from (x-2, y-2) to (x+1, y+1),
--     so the middle of a gate is the corner where those four middle cells
--     meet -- world pixel (x*16, y*16).
--   * a SHAPE, which is up to three arms of one or two cells, and the arms
--     lie on the LINES between cells rather than in them.  The two vertical
--     arms are the boundary at the pivot's x, the two horizontal ones the
--     boundary at its y.  That is what makes walking up into row 1 and
--     walking down into row 2 answer the same pair of arms: it is one fence,
--     crossed from either side.
--   * an ORIENTATION, 0..3, and it lives in the cartridge's own place: bytes
--     of the var block from VAR $4000, one a gate (080FB854 reads it, and
--     080FB870 is the only thing that ever writes it).  The map's entry
--     copies each gate's default orientation in (080FB818), which is why the
--     puzzle is back to its starting position every time you walk in.
--
-- AND WHICH WAY IT TURNS, which is the part with no room to guess.  The
-- shape's own arm slot `i` points in world direction (i + orientation) mod 4,
-- counted up -> right -> down -> left; so orientation + 1 moves every arm one
-- step CLOCKWISE.  The grids agree: pushing the left arm north answers
-- rotation 2, rotation 2 adds one, and left -> up is one step clockwise.
-- Nothing here is named after a guess -- the two sweep tables are keyed by
-- the rotation NUMBER that selects them, because their names are this port's
-- and the number is the cartridge's.

local Gen3Gates = {}

local WINDOW_BACK = 2          -- the fallback shape of the collision window,
local WINDOW_SIDE = 4          -- for a dataset imported before it was read

function Gen3Gates.record(data)
  local r = (data and data.constants or {}).gen3RotatingGates
  if type(r) == "table" and type(r.puzzles) == "table" then return r end
  return nil
end

-- WHICH PUZZLE a map is, or nil for the five hundred and sixteen that are not
-- one.  Two maps in Hoenn have gates and the record names both.
function Gen3Gates.puzzleFor(record, mapId)
  if not (record and type(mapId) == "string") then return nil end
  for _, puzzle in ipairs(record.puzzles) do
    if puzzle.map == mapId and type(puzzle.gates) == "table"
       and #puzzle.gates > 0 then
      return puzzle
    end
  end
  return nil
end

-- ------- the orientation bytes
--
-- The cartridge keeps one BYTE a gate in the var block from $4000, so two
-- gates share a var and eleven gates take six of them.  Keeping them here
-- rather than in a table of this port's own is not tidiness: they are
-- TEMPORARY vars, which a map change clears, and anything else that reads
-- $4000 on those two maps is reading the same bytes the gates do.

local function varOf(record, index)
  local base = math.floor(tonumber(record and record.orientationVar) or 0x4000)
  return base + math.floor(index / 2), (index % 2 == 1)
end

function Gen3Gates.orientation(save, record, index)
  local G3 = require("src.script.Gen3Commands")
  local var, high = varOf(record, index)
  local word = math.floor(tonumber(G3.getVar(save, var)) or 0)
  local byte = high and math.floor(word / 256) % 256 or word % 256
  return byte % 4
end

function Gen3Gates.setOrientation(save, record, index, value)
  local G3 = require("src.script.Gen3Commands")
  local var, high = varOf(record, index)
  local word = math.floor(tonumber(G3.getVar(save, var)) or 0)
  local low, hi = word % 256, math.floor(word / 256) % 256
  value = math.floor(tonumber(value) or 0) % 4
  if high then hi = value else low = value end
  G3.setVar(save, var, hi * 256 + low)
  return value
end

-- Walking in puts every gate back where the puzzle starts.  This is the whole
-- of the cartridge's RotatingGate_ResetAllGateOrientations (080FB818): copy
-- byte 5 of each config row into byte i of the var block.
function Gen3Gates.reset(save, record, puzzle)
  if not (save and record and puzzle) then return end
  for index, gate in ipairs(puzzle.gates) do
    Gen3Gates.setOrientation(save, record, index - 1, gate.orientation or 0)
  end
end

-- ------- the shape

function Gen3Gates.shapeOf(record, gate)
  local shapes = record and record.shapes
  local shape = gate and tonumber(gate.shape)
  if type(shapes) ~= "table" or not shape then return nil end
  return shapes[shape + 1]
end

-- Does this gate, turned this far, have the arm the grid named?  The arm
-- index is in WORLD terms -- direction * 2 + segment, counted up, right,
-- down, left -- and the shape's own slot is that minus the orientation
-- (080FBDB4 does exactly this subtraction).
function Gen3Gates.hasArm(record, gate, orientation, armIndex)
  local shape = Gen3Gates.shapeOf(record, gate)
  if not shape then return false end
  armIndex = math.floor(tonumber(armIndex) or 0)
  local segment = armIndex % 2
  local slot = (math.floor(armIndex / 2) - (tonumber(orientation) or 0)) % 4
  return (tonumber(shape.arms[slot + 1]) or 0) > segment
end

-- IS THERE ROOM TO TURN?  Every arm the gate actually has sweeps through one
-- cell, and if any of those is impassable the gate refuses -- which is what
-- makes a gate against a wall a wall (080FBCDC).  `passable` is the
-- overworld's own answer for a cell; the cartridge asks
-- MapGridIsImpassableAt and nothing else, so neither does this.
function Gen3Gates.canRotate(record, gate, orientation, code, passable)
  local shape = Gen3Gates.shapeOf(record, gate)
  local sweep = record and record.sweepByCode and record.sweepByCode[code]
  if not (shape and type(sweep) == "table" and passable) then return false end
  for slot = 0, 3 do
    local reach = tonumber(shape.arms[slot + 1]) or 0
    for segment = 0, 1 do
      if reach > segment then
        local armIndex = ((orientation + slot) % 4) * 2 + segment
        local off = sweep[armIndex + 1]
        if not off then return false end
        if not passable(gate.x + off[1], gate.y + off[2]) then return false end
      end
    end
  end
  return true
end

-- ------- the step
--
-- Answers what a step into (x, y) walking `dir` does, and it is one of three
-- things: nothing at all (no gate, or no arm across that line), "rotated"
-- (the gate turns and the step goes through -- the cartridge returns "no
-- collision" here, so you DO walk on), or "blocked" (an arm is across the
-- line and the gate has nowhere to turn).
function Gen3Gates.step(record, save, puzzle, dir, x, y, passable)
  if not (record and puzzle and save) then return nil end
  local dirs = record.directions or {}
  local dirIndex = tonumber(dirs[dir]) or tonumber(dir)
  local grid = dirIndex and record.anims and record.anims[dirIndex]
  if type(grid) ~= "table" then return nil end
  local back = math.floor(tonumber(record.window and record.window.back)
                          or WINDOW_BACK)
  local side = math.floor(tonumber(record.window and record.window.side)
                          or WINDOW_SIDE)
  for index, gate in ipairs(puzzle.gates) do
    local col = x - gate.x + back
    local row = y - gate.y + back
    if col >= 0 and col < side and row >= 0 and row < side then
      local entry = grid[row + 1] and grid[row + 1][col + 1]
      if type(entry) == "table" then
        local orientation = Gen3Gates.orientation(save, record, index - 1)
        if Gen3Gates.hasArm(record, gate, orientation, entry.arm) then
          local code = entry.rotation
          if Gen3Gates.canRotate(record, gate, orientation, code, passable) then
            local step = tonumber((record.turn or {})[code]) or 0
            local turned = (orientation + step) % 4
            Gen3Gates.setOrientation(save, record, index - 1, turned)
            return "rotated", index, turned
          end
          return "blocked", index, orientation
        end
      end
    end
  end
  return nil
end

return Gen3Gates
