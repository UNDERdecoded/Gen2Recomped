-- Figures: a person drawn INTO furniture, cut out by an authored pixel
-- mask and stood up on top of it (TileShape.figures / Structures.
-- buildFigures).  The Pokemon Center's seated man is the case the feature
-- exists for, so this drives the real profile entry over a hand-built
-- copy of the couch block he is drawn in -- POKECENTER blockset entry $08,
-- as every Center places it:
--
--     y=8   36 37 57 11        36/52 west wall strip, 37/53 the MAN,
--     y=9   52 53 60 27        57/60 floor he overhangs east onto,
--     y=10  38 39 54 11        38/39 cushion, 42/43 the couch's base
--     y=11  42 43 26 27
--
-- No love, no GPU and no pixel access: a figure is authored rather than
-- detected, which is exactly what lets it build headless.
--
--   luajit mods/DramaticShapeVoxelMod/tests/voxel_figure_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")

-- ------- the mod namespace (mirrors main.lua's V, minus the mod loader)

local ROOT = os.getenv("DS_MOD_PATH") or "mods/DramaticShapeVoxelMod"
local V = { path = ROOT }

local function chunkFor(rel)
  local f = assert(io.open(ROOT .. "/" .. rel, "rb"), rel .. " is missing")
  local src = f:read("*a")
  f:close()
  return assert(load(src, "@" .. ROOT .. "/" .. rel))
end

local modules, dataFiles = {}, {}
function V.require(name)
  if modules[name] == nil then
    modules[name] = chunkFor("lib/" .. name .. ".lua")(V)
  end
  return modules[name]
end
function V.data(name)
  if dataFiles[name] == nil then
    dataFiles[name] = chunkFor("data/" .. name .. ".lua")(V)
  end
  return dataFiles[name]
end

local TileShape = V.require("TileShape")
local Structures = V.require("Structures")

-- ------- the authored mask parses

local figs = TileShape.figures("POKECENTER")
T.check(type(figs) == "table" and #figs == 1,
  "POKECENTER carries exactly one figure")

local fig = figs[1]
T.eq(fig.w, 3, "the figure is three tiles across")
T.eq(fig.h, 2, "the figure is two tiles tall")
T.eq(fig.n, 139, "the mask claims 139 pixels of the 384 it spans")
T.check(fig.class == nil,
  "a figure carries no class -- it is always a flat sprite card")

local W = fig.w * 8
local function on(lx, ly) return fig.mask[ly * W + lx] == true end

-- the BACK OF HIS HEAD, in the two rightmost columns of tile 36 (the
-- couch's west arm): rows 0-1 are the arm, row 2 is his hair in column 7
-- only, rows 3-7 are his hair in both
T.check(not on(6, 0) and not on(7, 0) and not on(6, 1) and not on(7, 1),
  "the arm's own top rows stay with the couch")
T.check(not on(6, 2) and on(7, 2), "his hair starts in column 7 at row 2")
for ly = 3, 7 do
  T.check(on(6, ly) and on(7, ly),
    "the back of his head fills both columns at row " .. ly)
end

-- no holes in him: 37/53's column 7 (local 15) is the couch's east rule AND
-- the right side of his face, and masking it out by shade slit his cheek
for ly = 5, 8 do
  T.check(on(15, ly),
    "his cheek is solid at row " .. ly .. " (the column-7 slit)")
end

T.eq(fig.tiles[1], 36, "it starts at the couch's west arm")
T.eq(fig.tiles[2], 37, "then the tile his head is drawn in")
T.eq(fig.under[1], 52, "the arm wears the plain strip once his hair is off")
T.eq(fig.under[2], 39, "his head tile wears the couch's own cushion")
T.eq(fig.under[3], 1, "and the floor tiles wear the clean art (57 -> 1)")
T.eq(fig.under[6], 26, "and (60 -> 26)")

-- the mask is one connected figure: an overhang that floats free of him
-- is the failure this feature exists to avoid
local seen, first = {}, nil
for i in pairs(fig.mask) do first = first or i end
local stack, reached = { first }, 0
seen[first] = true
while #stack > 0 do
  local i = table.remove(stack)
  reached = reached + 1
  local x, y = i % W, math.floor(i / W)
  for dy = -1, 1 do
    for dx = -1, 1 do
      local nx, ny = x + dx, y + dy
      local ni = ny * W + nx
      if (dx ~= 0 or dy ~= 0) and nx >= 0 and nx < W
         and fig.mask[ni] and not seen[ni] then
        seen[ni] = true
        stack[#stack + 1] = ni
      end
    end
  end
end
T.eq(reached, fig.n, "the mask is a single connected figure")

-- ------- the couch block, as the Centers place it

local function keyOf(tx, ty) return (ty + 64) * 4096 + (tx + 64) end

local COUNTER = { class = "counter", h = 8, art = "upright",
                  flat = false, authored = true }
local GROUND = { class = "ground", h = 0, art = "flat",
                 flat = true, authored = false }

local BLOCK = { 36, 37, 57, 11,
                52, 53, 60, 27,
                38, 39, 54, 11,
                42, 43, 26, 27 }
local COUCH = { [36] = true, [37] = true, [38] = true, [39] = true,
                [42] = true, [43] = true, [52] = true, [53] = true }

local function scene()
  local S = { shapeAt = {}, tileAt = {}, figures = {}, skip = {},
              ground = {}, runs = {} }
  for i = 1, 16 do
    local tx, ty = (i - 1) % 4, 8 + math.floor((i - 1) / 4)
    local tile = BLOCK[i]
    S.tileAt[keyOf(tx, ty)] = tile
    S.shapeAt[keyOf(tx, ty)] = COUCH[tile] and COUNTER or GROUND
  end
  return S
end

-- collision is per 16x16 cell: the couch's cell is blocked (he is drawn
-- sitting on it), the floor cell east of it is walkable
local map = {
  tileset = { id = "POKECENTER", tilesPerRow = 16,
              imageWidth = 128, imageHeight = 48 },
  isWalkableCell = function(_, cx) return cx >= 1 end,
}

-- ------- he comes off the couch

local S = scene()
Structures.buildFigures(S, map, 0, 3, 8, 11)

T.eq(#S.figures, 1, "one figure card was built")
local card = S.figures[1]
T.eq(#card.quads, fig.n, "one quad per masked pixel, and nothing else")

T.eq(S.tileAt[keyOf(0, 8)], 52, "the arm wears the plain strip now")
T.eq(S.tileAt[keyOf(1, 8)], 39, "his head tile now wears the cushion")
T.eq(S.tileAt[keyOf(1, 9)], 39, "his body tile too")
T.eq(S.tileAt[keyOf(2, 8)], 1, "the floor he overhung is clean floor again")
T.eq(S.tileAt[keyOf(2, 9)], 26, "both rows of it")
T.eq(S.tileAt[keyOf(1, 10)], 39, "the couch's own cushion row is untouched")
T.eq(S.tileAt[keyOf(1, 11)], 43, "and so is its drawn base")

-- the couch keeps its box: a figure changes ART, never class
T.eq(S.shapeAt[keyOf(1, 8)].class, "counter",
  "his tiles are still the couch's half-cell box")
T.check(S.skip[keyOf(1, 8)] ~= true,
  "and are not skipped -- the couch still renders there")

-- ------- the card is flat, and stands at its feet

local minX, maxX, minY, maxY, minZ, maxZ
for _, q in ipairs(card.quads) do
  for c = 1, 4 do
    local p = q[c]
    minX = math.min(minX or p[1], p[1]); maxX = math.max(maxX or p[1], p[1])
    minY = math.min(minY or p[2], p[2]); maxY = math.max(maxY or p[2], p[2])
    minZ = math.min(minZ or p[3], p[3]); maxZ = math.max(maxZ or p[3], p[3])
  end
end

T.eq(minZ, 0, "the card is a single plane at z = 0 (no thickness)")
T.eq(maxZ, 0, "on both sides -- it is a sprite, not a slab")
T.eq(minY, 0, "local space: his feet are the card's origin")
T.eq(maxY, 16, "and he is his drawn 16px tall")
T.eq(minX, 0, "his west edge is the card's origin too")
T.eq(maxX, 12, "and he is 12px wide -- arm hair to floor overhang")

-- ------- and where VoxelScene stands it

T.eq(card.y, 8, "his feet stand on the couch's top face, not the floor")
T.eq(card.wx, 6, "anchored at the back of his head, in tile 36's column 6")
T.eq(card.wz, 76,
  "and pivoting at the middle of the tile row his feet are drawn in")

-- ------- a map that does not draw him builds nothing

local other = scene()
other.tileAt[keyOf(1, 8)] = 40
Structures.buildFigures(other, map, 0, 3, 8, 11)
T.eq(#other.figures, 0, "no match, no figure")
T.eq(other.tileAt[keyOf(2, 8)], 57, "and nothing repainted")

-- ------- and it never fires twice on the same drawing

local twice = scene()
Structures.buildFigures(twice, map, 0, 3, 8, 11)
Structures.buildFigures(twice, map, 0, 3, 8, 11)
T.eq(#twice.figures, 1,
  "the repaint replaces the pattern, so a rescan cannot match it again")

-- ------- a figure with a DEPTH is an object, not a card
--
-- The Marts' cash register: the same authored-mask escape, but a machine
-- set down on a counter is a box seen from the front rather than a
-- face-on icon, so it builds as a per-pixel solid.  Driven over a
-- synthetic copy of the counter's east arm, as all nine maps on the MART
-- id draw it at cell (1,5):
--
--     y=9    16 41      the work surface north of it
--     y=10   14 15      the register: keypad and receipt curl
--     y=11   30 31
--     y=12   16 41      the work surface it stands on

T.check(TileShape.figures("POKECENTER")[1].depth == nil,
  "the seated man states no depth -- he stays a flat sprite card")

local regs = TileShape.figures("MART")
T.check(type(regs) == "table" and #regs == 1,
  "MART carries exactly one figure")
local reg = regs[1]
T.eq(reg.w, 2, "the register is two tiles across")
T.eq(reg.h, 2, "and two tall")
T.eq(reg.n, 150, "the mask claims 150 pixels of the 256 it spans")
T.eq(reg.depth, 12, "its body is 12 voxels deep -- three quarters of the cell")
T.check(reg.thin and reg.thin.rows == 4 and reg.thin.depth == 2,
  "the four rows above its drawn top edge are 2-voxel paper")
T.check(reg.flat and reg.flat.x0 == 2 and reg.flat.x1 == 8
        and reg.flat.r0 == 4 and reg.flat.r1 == 11,
  "and the keypad is a TOP-VIEW rect, not a face")

local MART_ROWS = { [9] = { 16, 41 }, [10] = { 14, 15 },
                    [11] = { 30, 31 }, [12] = { 16, 41 } }
local martS = { shapeAt = {}, tileAt = {}, figures = {}, skip = {},
                ground = {}, runs = {}, objectQuads = {} }
for ty, row in pairs(MART_ROWS) do
  for i, tile in ipairs(row) do
    martS.tileAt[keyOf(1 + i, ty)] = tile
    martS.shapeAt[keyOf(1 + i, ty)] = COUNTER
  end
end
local martMap = {
  tileset = { id = "MART", tilesPerRow = 16,
              imageWidth = 128, imageHeight = 48 },
  isWalkableCell = function() return false end,
}
Structures.buildFigures(martS, martMap, 2, 3, 9, 12)

T.eq(#martS.figures, 0, "no card was built -- it is a solid")
T.eq(#martS.objectQuads, 351,
  "and it landed in the standee channel as 351 quads")
T.eq(martS.tileAt[keyOf(2, 10)], 16,
  "its tiles wear the plain work surface now")
T.eq(martS.tileAt[keyOf(3, 11)], 41, "all four of them")
T.eq(martS.shapeAt[keyOf(2, 10)].class, "counter",
  "and keep the counter box the machine stands on")

local rx0, rx1, ry0, ry1, rz0, rz1
for _, q in ipairs(martS.objectQuads) do
  for c = 1, 4 do
    local p = q[c]
    rx0 = math.min(rx0 or p[1], p[1]); rx1 = math.max(rx1 or p[1], p[1])
    ry0 = math.min(ry0 or p[2], p[2]); ry1 = math.max(ry1 or p[2], p[2])
    rz0 = math.min(rz0 or p[3], p[3]); rz1 = math.max(rz1 or p[3], p[3])
  end
end
T.eq(ry0, 8, "it stands ON the counter's 8px top plane, not the floor")
T.eq(ry1, 24, "and is its drawn 16px tall")
T.eq(rx0, 18, "west edge at the mask's column 2")
T.eq(rx1, 30, "east edge at column 13, inside its own cell (16..32)")
T.eq(rz1, 96, "its FRONT is the cell's own front edge, where it is drawn")
T.eq(rz0, 84, "and it grows north from there, 4 short of the cell's back")

-- the two thicknesses: the body at 8, the receipt curl at 2, the curl
-- centred in the body's own band rather than flush with its front
local bands = {}
for _, q in ipairs(martS.objectQuads) do
  for c = 1, 4 do bands[q[c][3]] = true end
end
for _, z in ipairs({ 84, 89, 91, 96 }) do
  T.check(bands[z], "the model has a face at z = " .. z)
end
local curl = {}
for _, q in ipairs(martS.objectQuads) do
  local lo = math.min(q[1][2], q[2][2], q[3][2], q[4][2])
  if lo >= 21 then for c = 1, 4 do curl[q[c][3]] = true end end
end
T.check(curl[89] and curl[91] and not curl[84] and not curl[96],
  "clear of the arm's top only the 2-voxel paper band exists")

-- THE L.  The base band (drawn rows 12-15) stands 4 above the counter and
-- the keypad lies on it as a horizontal plate, so the whole machine is
-- exactly three surfaces: a foot, an arm, and a deck in the notch.
local plate, deckTop = {}, 0
for _, q in ipairs(martS.objectQuads) do
  local flatQuad = q[1][2] == q[2][2] and q[2][2] == q[3][2]
                   and q[3][2] == q[4][2]
  if flatQuad and q[1][2] == 13 then
    plate[#plate + 1] = q
  elseif flatQuad and q[1][2] == 12 then
    deckTop = deckTop + 1
  end
end
T.eq(#plate, 83,
  "the keypad lies FLAT: one top quad per masked voxel of the deck")
T.eq(deckTop, 7,
  "on the base band's own top, which is 4 voxels up (drawn rows 12-15)")
local dz0, dz1
for _, q in ipairs(martS.objectQuads) do
  if q[1][2] == 12 and q[3][2] == 12 then
    for c = 1, 4 do
      dz0 = math.min(dz0 or q[c][3], q[c][3])
      dz1 = math.max(dz1 or q[c][3], q[c][3])
    end
  end
end
T.eq(dz0, 84, "and that deck runs the body's whole depth")
T.eq(dz1, 96, "-- plain behind the panel, covered by it in front")

local px0, px1, pz0, pz1
for _, q in ipairs(plate) do
  for c = 1, 4 do
    px0 = math.min(px0 or q[c][1], q[c][1]); px1 = math.max(px1 or q[c][1], q[c][1])
    pz0 = math.min(pz0 or q[c][3], q[c][3]); pz1 = math.max(pz1 or q[c][3], q[c][3])
  end
end
T.eq(px0, 18, "the deck spans the mask's columns 2..8")
T.eq(px1, 25, "-- the keypad panel and its own black rim")
T.eq(pz1, 96, "the deck reaches the body's front edge")
T.eq(pz0, 84, "and its back -- 8 drawn rows STRETCHED over 12 voxels")

-- the stretch is by whole voxels, centre-sampled: 8 drawn rows over 12
-- voxels of deck doubles every second one and blurs nothing
local perRow16, atlasH16 = 16, 48
local depthRow = {}
for _, q in ipairs(plate) do
  local z = math.min(q[1][3], q[2][3], q[3][3], q[4][3])
  depthRow[z] = math.floor(q.v * atlasH16)
end
local seen = {}
for z = 84, 95 do
  T.check(depthRow[z] ~= nil, "deck voxel at z = " .. z .. " wears a texel")
  seen[depthRow[z]] = (seen[depthRow[z]] or 0) + 1
end
T.eq(depthRow[95], 11, "the front voxel wears the keypad's own bottom rim")
T.eq(depthRow[84], 4, "the back one wears its top rim")
local doubled = 0
for _, n in pairs(seen) do
  T.check(n == 1 or n == 2, "no drawn row spreads over more than two voxels")
  if n == 2 then doubled = doubled + 1 end
end
T.eq(doubled, 4, "exactly four of the eight rows double -- 8 into 12")


-- and the arm still stands its drawn 8 rows above that deck, carrying
-- the paper: nothing in the notch reaches higher than the plate
local armTop, notchTop = 0, 0
for _, q in ipairs(martS.objectQuads) do
  for c = 1, 4 do
    if q[c][1] >= 25 then armTop = math.max(armTop, q[c][2])
    elseif q[c][1] <= 24 then notchTop = math.max(notchTop, q[c][2]) end
  end
end
T.eq(armTop, 24, "the arm and its receipt curl reach the drawn 16px")
T.eq(notchTop, 23,
  "and west of it only the keys (13) and the paper overhanging them")

-- ------- prop_bg: the shades a pinned prop treats as background
--
-- The potted plants needed this: their pot's olive base is drawn flush on
-- the bottom of the plant block, so the ordinary vote (shades touching the
-- drawing's own bounding box) read "dark" as background and drained every
-- olive pixel in the plant.

local bgRules = TileShape.propBg("POKECENTER")
T.check(type(bgRules) == "table", "POKECENTER names prop background shades")
for _, tile in ipairs({ 32, 33, 34, 35, 48, 49, 50, 51 }) do
  local set = bgRules and bgRules[tile]
  T.check(type(set) == "table" and set.light and set.white
          and not set.dark and not set.black,
    "plant tile " .. tile .. ": light/white are background, dark is the pot")
end

-- and it is scoped: the healing consoles' screens and the PC keep the
-- ordinary vote, because they want the opposite call on those same shades
for _, tile in ipairs({ 58, 59, 66, 70, 74, 75, 82, 86 }) do
  T.check(bgRules[tile] == nil,
    "tile " .. tile .. " keeps the ordinary background vote")
end

-- a tileset with no prop_bg at all answers nil rather than an empty table,
-- so Structures can skip the lookup entirely
T.check(TileShape.propBg("CAVERN") == nil,
  "a tileset that names none answers nil")

T.finish("DRAMATIC_SHAPE figures")
