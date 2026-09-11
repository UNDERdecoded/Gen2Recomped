-- The fallback voxel-class vocabulary.
--
-- A MIRROR, NOT A SOURCE.  When the mod is installed, every class question
-- is answered by its own TileShape.CLASS_INFO -- so a fork that adds a class
-- gets it here with nothing to update, and a fork that changes a height does
-- not have to be chased.  This table is what the editor offers when no mod
-- is installed at all, and it exists only so the app still opens.
--
-- It mirrors TileShape's FALLBACK_HEIGHTS and ART as of DRAMATIC_SHAPE
-- 1.7.0.  If the two ever disagree, the mod is right.

local Classes = {}

Classes.FALLBACK = {
  ground       = { h = 0,   art = "flat" },
  water        = { h = -2,  art = "flat" },
  void         = { h = 0,   art = "flat" },
  grass        = { h = 0,   art = "grass" },
  flower       = { h = 0,   art = "flower" },
  relief       = { h = 3,   art = "relief" },
  ledge        = { h = 6,   art = "top" },
  bed          = { h = 7,   art = "top" },
  counter      = { h = 8,   art = "upright" },
  stool        = { h = 8,   art = "billboard" },
  can          = { h = 9,   art = "cylinder" },
  fence        = { h = 10,  art = "upright" },
  sign         = { h = 12,  art = "upright" },
  table        = { h = 12,  art = "upright" },
  backrest     = { h = 12,  art = "top" },
  wall         = { h = 16,  art = "upright" },
  tree         = { h = 16,  art = "upright" },
  terrace      = { h = 16,  art = "top" },
  cylinder     = { h = 16,  art = "cylinder" },
  post         = { h = 16,  art = "post" },
  prop         = { h = 16,  art = "billboard" },
  cutout       = { h = 16,  art = "billboard" },
  bike         = { h = 16,  art = "billboard" },
  billboard    = { h = 16,  art = "billboard" },
  signpost     = { h = 16,  art = "billboard" },
  console      = { h = 16,  art = "billboard" },
  stump        = { h = 16,  art = "cylinder" },
  stair_e      = { h = 16,  art = "stair" },
  stair_w      = { h = 16,  art = "stair" },
  stair_down_e = { h = 16,  art = "stair" },
  stair_down_w = { h = 16,  art = "stair" },
  desk         = { h = 24,  art = "upright" },
  roof         = { h = 28,  art = "top" },
  cliff        = { h = 32,  art = "upright" },
  shell        = { h = 32,  art = "upright" },
  waterfall    = { h = 32,  art = "upright" },
  canopy       = { h = 32,  art = "canopy" },
  planter      = { h = 32,  art = "planter" },
  bookcase     = { h = 32,  art = "bookcase" },
  column       = { h = 32,  art = "post" },
}

-- The folds, and what each one MEANS to the mesher.  Shown in the editor
-- because picking between `wall` and `roof` without knowing that the first
-- stands its artwork up and the second lays it on top is guesswork.
Classes.FOLDS = {
  { id = "flat",      label = "flat",            hint = "one quad at the height; side bands show where a neighbour is lower" },
  { id = "top",       label = "art on top",      hint = "box wearing the drawing on its TOP face; side bands crop the art" },
  { id = "upright",   label = "south-face fold", hint = "box whose SOUTH face folds the drawing upright, 8px band by band" },
  { id = "billboard", label = "per-pixel cutout",hint = "a standee: one voxel per lit pixel, holes stay holes" },
  { id = "post",      label = "post",            hint = "per-pixel, per CELL, opaque segmentation -- fences and columns" },
  { id = "cylinder",  label = "round hull",      hint = "voxel hull revolved from the drawing's own half-widths" },
  { id = "canopy",    label = "canopy hull",     hint = "the round hull across a 2x2-cell group" },
  { id = "planter",   label = "planter hull",    hint = "round, two cells of drawing standing on one cell of plot" },
  { id = "relief",    label = "relief",          hint = "drawn from above: flat, with the inside of the outline raised a few voxels" },
  { id = "bookcase",  label = "bookcase",        hint = "ranks collapse onto a one-cell-deep box; the front carries pane relief" },
  { id = "stair",     label = "steps",           hint = "four real treads rising toward the named side" },
  { id = "grass",     label = "grass slab",      hint = "2px-thick upright slab at the middle of its own tile" },
  { id = "flower",    label = "flower card",     hint = "1px thick, every pixel capped -- the silhouette animates in texture space" },
}

-- The heights the editor offers as one click.  Named, because "28" means
-- nothing and "roof" means everything.
Classes.HEIGHT_PRESETS = {
  { h = -2, label = "water (-2)" },
  { h = 0,  label = "ground (0)" },
  { h = 3,  label = "relief (3)" },
  { h = 6,  label = "ledge (6)" },
  { h = 8,  label = "counter (8)" },
  { h = 12, label = "table (12)" },
  { h = 16, label = "wall (16)" },
  { h = 24, label = "desk (24)" },
  { h = 28, label = "roof (28)" },
  { h = 32, label = "cliff (32)" },
  { h = 48, label = "storey (48)" },
}

-- The four Game Boy shades, by the same cutoffs Structures.shadeClass uses.
-- The editor's magic wand selects by these, so a selection made here is the
-- same selection the mesher's background vote would make.
function Classes.shadeClass(v)
  if v <= 0.25 then return "black" end
  if v <= 0.55 then return "dark" end
  if v <= 0.85 then return "light" end
  return "white"
end

Classes.SHADES = { "black", "dark", "light", "white" }

function Classes.sortedNames(info)
  local names = {}
  for name in pairs(info or Classes.FALLBACK) do names[#names + 1] = name end
  table.sort(names, function(a, b)
    local ia, ib = info[a], info[b]
    local ha = (ia and ia.h) or 0
    local hb = (ib and ib.h) or 0
    if ha ~= hb then return ha < hb end
    return a < b
  end)
  return names
end

return Classes
