-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped Map Editor License: you may read,
-- build and privately modify this file; you may not redistribute it or use it
-- commercially. See LICENSE at the repository root. Cartridge-derived data is
-- not covered and is not the copyright holder's to license.

-- Undo and redo for the map editor.
--
-- WHOLE-STATE SNAPSHOTS, NOT AN ACTION LOG, and that is a deliberate trade.
--
-- An action log -- "painted block 5 at 3,4, previous was 2" -- is smaller and
-- lets you undo one thing out of order, and it is also a second description of
-- every operation the editor has: every tool would have to remember to record
-- itself, and the one that forgot would be the one that silently could not be
-- undone. This editor has a dozen tools and gains one most weeks. A snapshot
-- cannot be forgotten by a tool that does not know it exists.
--
-- WHAT A STATE IS. The edit store is most of it -- that is where every patch
-- lives. But two tools also write straight into the LIVE map def, because the
-- next frame draws from that and waiting for a reload would mean painting a
-- block and not seeing it: `setBlock` writes `def.blocks`, and adding an NPC
-- appends to `def.objects`. Restoring the store alone would put the patches
-- back and leave the map still painted -- an undo that half worked, which is
-- worse than one that does not exist. So both come with.
--
-- CAPTURED LAZILY, ONE FRAME BEHIND. Nothing calls "begin an edit"; the tools
-- call `markEdited` after the fact, and threading a pre-edit hook through
-- every one of them is the same forgettable bookkeeping an action log needs.
-- Instead the base state is re-captured at the top of each frame, and when the
-- edit stamp has moved since the last one, the state from BEFORE this frame is
-- what goes on the stack. Two edits in one frame coalesce into one undo step,
-- which for a drag that paints eight cells is what anybody would want anyway.

local History = {}

History.LIMIT = 60          -- states, not actions; see the coalescing note

local function deepCopy(v, seen)
  if type(v) ~= "table" then return v end
  seen = seen or {}
  if seen[v] then return seen[v] end
  local out = {}
  seen[v] = out
  for k, val in pairs(v) do out[deepCopy(k, seen)] = deepCopy(val, seen) end
  return out
end

History.deepCopy = deepCopy

local function liveDef(S)
  return S and S.data and S.data.maps and S.data.maps[S.mapId or ""] or nil
end

-- One state: the store, plus the live def's two mutable arrays for the map
-- that is open. Not every map's -- the editor only ever writes live into the
-- one on screen, and copying a hundred maps' block arrays sixty times a second
-- would be the most expensive thing in the editor by an order of magnitude.
function History.capture(S)
  if not (S and S.mapEdits) then return nil end
  local def = liveDef(S)
  return {
    stamp = S.mapEditsStamp or 0,
    mapId = S.mapId,
    store = deepCopy(S.mapEdits),
    blocks = def and def.blocks and deepCopy(def.blocks) or nil,
    objects = def and def.objects and deepCopy(def.objects) or nil,
  }
end

-- Put a captured state back.
--
-- The store table is replaced wholesale rather than merged: a merge would
-- leave keys the undone edit added, which is the one thing an undo must not
-- do. Everything that reads the store re-reads `S.mapEdits` every frame, and
-- VoxelClasses compares the table's identity when it binds -- so a new table
-- is picked up rather than cached over.
function History.restore(S, snap)
  if not (S and snap) then return false end
  S.mapEdits = snap.store and deepCopy(snap.store) or S.mapEdits
  -- The live arrays go back only if the same map is still open. Undoing across
  -- a map switch restores the store -- which is where the edit really lives --
  -- and leaves the other map's live def alone; it is rebuilt from the store on
  -- the next load anyway.
  if snap.mapId == S.mapId then
    local def = liveDef(S)
    if def then
      if snap.blocks then def.blocks = deepCopy(snap.blocks) end
      if snap.objects then def.objects = deepCopy(snap.objects) end
    end
  end
  -- Every derived thing has to go: the class list, the built mesh, the cached
  -- Map the renderer holds. A stale one of any of them shows the world as it
  -- was before the undo, which reads as the undo not having worked.
  S.mapEditsStamp = (S.mapEditsStamp or 0) + 1
  S.mapEditsDirty = true
  S.voxClasses, S.voxClassesFor = nil, nil
  S.pvClassesFor, S.pv3DKey = nil, nil
  pcall(function()
    require("src.world.MapLoader").evict(S.mapId)
  end)
  pcall(function()
    require("tools.map-editor.ModShapes").invalidate(S.mapId)
  end)
  return true
end

-- Called once a frame, before anything can edit. Pushes the PREVIOUS frame's
-- state when this frame's stamp says an edit happened since.
function History.tick(S)
  if not (S and S.mapEdits) then return end
  local stamp = S.mapEditsStamp or 0
  if not S._histBase then
    S._histBase = History.capture(S)
    return
  end
  -- A restore bumps the stamp too, so `_histSuppress` is how undo and redo
  -- avoid pushing their own result back onto the stack -- without it, one undo
  -- would record itself as an edit and the next would undo the undo.
  if S._histSuppress then
    S._histSuppress = nil
    S._histBase = History.capture(S)
    return
  end
  if stamp ~= S._histBase.stamp then
    S.undoStack = S.undoStack or {}
    S.undoStack[#S.undoStack + 1] = S._histBase
    while #S.undoStack > History.LIMIT do table.remove(S.undoStack, 1) end
    -- A NEW EDIT ENDS THE REDO BRANCH. Keeping it would offer to redo a future
    -- that no longer follows from the present, which is how a "redo" comes to
    -- paste something from a different map.
    S.redoStack = nil
    S._histBase = History.capture(S)
  end
end

function History.canUndo(S) return S and S.undoStack and #S.undoStack > 0 end
function History.canRedo(S) return S and S.redoStack and #S.redoStack > 0 end

function History.undo(S)
  if not History.canUndo(S) then return false end
  local snap = table.remove(S.undoStack)
  S.redoStack = S.redoStack or {}
  S.redoStack[#S.redoStack + 1] = History.capture(S)
  while #S.redoStack > History.LIMIT do table.remove(S.redoStack, 1) end
  History.restore(S, snap)
  S._histSuppress = true
  return true
end

function History.redo(S)
  if not History.canRedo(S) then return false end
  local snap = table.remove(S.redoStack)
  S.undoStack = S.undoStack or {}
  S.undoStack[#S.undoStack + 1] = History.capture(S)
  History.restore(S, snap)
  S._histSuppress = true
  return true
end

-- Both stacks, for a panel that wants to say how far back it can go.
function History.depth(S)
  return (S and S.undoStack and #S.undoStack) or 0,
         (S and S.redoStack and #S.redoStack) or 0
end

return History
