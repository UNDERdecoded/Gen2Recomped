-- Undo and redo.
--
-- SNAPSHOTS OF SLOTS, NOT OF THE DOCUMENT.  A whole-document copy per stroke
-- would be simple and would also copy every sculpt of every tileset every
-- time somebody nudges one column.  A slot is the unit an edit actually
-- touches: one tileset's entry, or one map's overrides.  Copying that is
-- cheap enough to do on every gesture and complete enough that restoring it
-- puts things back exactly.
--
-- ONE ENTRY PER GESTURE, NOT PER FRAME.  A drag writes into the height field
-- continuously; if each write pushed an entry, undo would walk back a pixel
-- at a time forever.  So the caller records ONCE, before the gesture starts,
-- and the snapshot taken then is the state undo returns to.
--
-- The redo stack is cleared by any new edit, which is what everyone expects
-- and the only behaviour that cannot produce a history that never happened.

local History = {}

History.LIMIT = 100

local function deepcopy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, val in pairs(v) do out[k] = deepcopy(val) end
  return out
end
History.deepcopy = deepcopy

function History.new()
  return { undo = {}, redo = {}, depth = 0 }
end

local function slotOf(doc, kind, id)
  if kind == "tileset" then return doc.tilesets[id] end
  if kind == "map" then return doc.maps[id] end
  return nil
end

local function setSlot(doc, kind, id, value)
  if kind == "tileset" then doc.tilesets[id] = value
  elseif kind == "map" then doc.maps[id] = value end
end

-- Record the state of a slot BEFORE it is changed.
--
-- `coalesce` is for the gesture that arrives as a stream -- a brush dragged
-- across a tile canvas fires per texel, and forty entries for one stroke is
-- forty presses of undo.  Passing the same tag for the whole stroke folds
-- them into the first one.
function History.record(h, doc, kind, id, label, coalesce)
  if not (h and doc and kind and id) then return end
  if coalesce and h.lastTag == coalesce then return end
  h.lastTag = coalesce
  local entry = {
    kind = kind, id = id, label = label or kind,
    before = deepcopy(slotOf(doc, kind, id)),
  }
  h.undo[#h.undo + 1] = entry
  if #h.undo > History.LIMIT then table.remove(h.undo, 1) end
  h.redo = {}
end

-- End a coalescing run, so the next edit of the same kind starts its own
-- entry.  Called when a stroke or drag finishes.
function History.commit(h)
  if h then h.lastTag = nil end
end

local function apply(h, doc, from, to)
  local entry = table.remove(from)
  if not entry then return nil end
  local now = deepcopy(slotOf(doc, entry.kind, entry.id))
  setSlot(doc, entry.kind, entry.id, entry.before)
  to[#to + 1] = { kind = entry.kind, id = entry.id, label = entry.label,
                  before = now }
  h.lastTag = nil
  return entry
end

function History.undoOnce(h, doc)
  return apply(h, doc, h.undo, h.redo)
end

function History.redoOnce(h, doc)
  return apply(h, doc, h.redo, h.undo)
end

function History.canUndo(h) return h and #h.undo > 0 end
function History.canRedo(h) return h and #h.redo > 0 end

function History.peek(h)
  local e = h and h.undo[#h.undo]
  return e and e.label or nil
end

return History
