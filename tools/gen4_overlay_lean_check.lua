-- Run:  texlua tools/gen4_overlay_lean_check.lua
--
-- THE EDITOR'S OVERLAY AND THE GROUND IT STANDS ON.
--
-- Reported from play, five times in different words, and finally in the one
-- that named it: *"for platinum the npcs and warps arent placed in 3d and are
-- acting as a 2d overlay that doesnt change with the camera tilt"*.
--
-- A Gen 4 map is painted through the cartridge's pitch: `Gen4Ground` states
-- the vertical scale as `groundScale` and paints world row `wy` at view row
-- `(wy - camY) * groundScale`. The editor drew the warps, the NPCs, the cell
-- cursor and the grid at `wy - camY` -- `groundScale` appeared NOWHERE in
-- `tools/`. Two projections for one picture, disagreeing by more the further
-- down the viewport you look.
--
-- The half of this that bites hardest is not the drawing: it is that the HIT
-- TEST has to be the exact inverse. A hit test that disagrees with the picture
-- means clicking paints a cell other than the one under the pointer, which is
-- worse than either being wrong on its own.

package.path = './?.lua;./?/init.lua;./tools/save-editor/?.lua;' .. package.path

local PASS, FAIL = 0, 0
local function check(cond, label)
  if cond then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. label) end
end

local okP, Preview = pcall(require, 'tools.map-editor.panels.Preview')
check(okP, 'the preview panel must load: ' .. tostring(okP and '' or Preview))
if not okP then
  print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
  os.exit(1)
end

local S = {}
local function mapWith(scale)
  return { renderer = { gen4Ground = { groundScale = scale } } }
end

-- ============================================== 1. the scale this port states
--
-- 0.857630 is Jubilife's, from the cartridge's own 59.05-degree camera row. It
-- is asserted here rather than recomputed so that a change to the camera table
-- has to be stated in both places deliberately.
local PLAT = 0.857630
check(math.abs(Preview.groundSin(S, mapWith(PLAT)) - PLAT) < 1e-9,
      'a Gen 4 map must lean by its ground\'s own scale, got '
      .. tostring(Preview.groundSin(S, mapWith(PLAT))))

-- ...AND EVERY OTHER GENERATION IS THE IDENTITY, by construction rather than
-- by a branch somebody has to remember. Gen 1, 2 and 3 have no `gen4Ground`,
-- so they take this path too and must come out untouched -- *"Make sure your
-- additions dont break crystal, gold silver or prism"*.
check(Preview.groundSin(S, nil) == 1, 'no map must lean by 1')
check(Preview.groundSin(S, { renderer = {} }) == 1,
      'a map with no gen4 ground must lean by 1')
check(Preview.groundSin(S, { renderer = { gen4Ground = {} } }) == 1,
      'a gen4 ground that states no scale must lean by 1, not by nil')
for _, y in ipairs({ 0, 1, 16, 199, 1024, -16 }) do
  check(Preview.groundY(S, y, nil) == y,
        'and must move nothing on a non-Gen-4 map: ' .. y .. ' -> '
        .. tostring(Preview.groundY(S, y, nil)))
  check(Preview.groundUn(S, y, nil) == y, 'in both directions')
end

-- ===================================== 2. the drawing and the hit test invert
--
-- THE PROPERTY, not a list of values: for every lean and every row, going down
-- and back up must return where it started. A one-sided change -- applying the
-- lean to the drawing and forgetting the hit test, which is exactly the shape
-- of this bug -- fails here on the first row that is not zero.
local LEANS = { 1, PLAT, 0.5, 0.9999, 0.0501 }
local worst = 0
for _, lean in ipairs(LEANS) do
  local m = mapWith(lean)
  for _, y in ipairs({ 0, 1, 7, 16, 100, 199, 512, 1024, 3584, -1, -97 }) do
    local back = Preview.groundUn(S, Preview.groundY(S, y, m), m)
    worst = math.max(worst, math.abs(back - y))
  end
end
check(worst < 1e-9,
      'the lean and its inverse must round-trip for every lean and row -- a '
      .. 'hit test that does not invert the drawing paints a cell other than '
      .. 'the one under the pointer; worst error ' .. tostring(worst))

-- A LEANED ROW IS HIGHER UP THE SCREEN, and further up the further down the
-- map it is. This is the direction check: an inverse applied the wrong way
-- round still round-trips perfectly and moves everything the wrong way.
local m = mapWith(PLAT)
check(Preview.groundY(S, 100, m) < 100,
      'a leaned row must move UP the view, got ' .. Preview.groundY(S, 100, m))
check(Preview.groundY(S, 0, m) == 0, 'and the camera row must not move at all')
local near0, far = Preview.groundY(S, 50, m), Preview.groundY(S, 200, m)
check((50 - near0) < (200 - far),
      'with the gap growing further down the viewport -- that is what puts a '
      .. 'sprite outside the viewport rather than merely near its edge')

-- THE DEGENERATE SCALE. A lean of zero would divide the inverse by nothing and
-- throw the hit test off the end of the map; a lean above 1 would stretch the
-- picture past the viewport. Both must fall back rather than propagate.
for _, bad in ipairs({ 0, -0.5, 1.5, 0.01 }) do
  check(Preview.groundSin(S, mapWith(bad)) == 1,
        'a lean of ' .. bad .. ' must fall back to 1, got '
        .. tostring(Preview.groundSin(S, mapWith(bad))))
end
-- RE-PINNED: `tonumber('0.8')` IS 0.8, so a numeric string is a number by
-- the same rule every other reader in this tree uses, and rejecting it would
-- be this check inventing a stricter contract than the code's. What must not
-- get through is a value that is not a number at all.
for _, junk in ipairs({ 'abc', true, {} }) do
  check(Preview.groundSin(S, mapWith(junk)) == 1,
        'a non-numeric scale must fall back to 1, got '
        .. tostring(Preview.groundSin(S, mapWith(junk))))
end

-- ================================== 3. one source of the arithmetic, in use
local src = io.open('tools/map-editor/panels/Preview.lua'):read('a')
check(src:match('function Preview%.groundSin'), 'the lean must be one function')
check(src:match('function Preview%.groundY') and src:match('function Preview%.groundUn'),
      'with one function each way')
-- THE OVERLAY'S SINGLE RECT. Every overlay in `drawOverlays` -- warps, NPCs,
-- cursor, collision wash -- is placed by it, which is why the lean belongs
-- there rather than at a dozen call sites that can each be forgotten.
check(src:match('local lean = Preview%.groundSin%(S, map%)'),
      'the overlay rect must take the lean')
check(src:match('%(cy %* CELL %- %(S%.pvCamY or 0%)%) %* lean'),
      'and apply it to the row')
check(src:match('CELL %* lean'),
      'and to the cell\'s HEIGHT -- a full-height cell on leaned ground '
      .. 'overhangs the one below it, which reads as selecting two cells')
check(src:match('Preview%.groundUn%(S, worldY%)'),
      'and the hit test must come back up through the inverse')
-- NO SECOND COPY. These two were the other places that did the arithmetic by
-- hand, and a fix that left them behind would move the sprites and leave the
-- grid and the warp numbers where they were.
local raw = select(2, src:gsub('%* CELL %- %(S%.pvCamY or 0%)[^%)]*%), CELL', ''))
check(raw == 0,
      'no overlay may still place a row by hand -- found ' .. raw)
check(src:match('S%._pvMap%)') and not src:match('_pvMapForLean'),
      'and the map must be read from the field the viewport already keeps, '
      .. 'not a second one meaning the same thing')

-- ============================ 4. the hover preview dies with the list it owns
--
-- Reported: *"after selecting a model the square for the preview is still
-- there when i close out the model selection menu"*. `_mpHover` was cleared
-- only by the row loop, which runs inside the picker's scroll region -- so
-- closing the picker stopped the one thing that could clear it.
local models = io.open('tools/map-editor/panels/Models.lua'):read('a')
check(models:match('if not picker then S%._mpHover, S%.modelZoom = nil, nil end'),
      'closing the model picker must drop BOTH the hover and the eye popup '
      .. 'it owned -- selecting a model closes the picker, and either one '
      .. 'left behind is a panel floating over a list that is gone')
check(models:match('if hv and S%.modelPickerOpen and S%.modelZoom == nil'),
      'and the deferred layer must refuse to paint one with no list open')

-- ===================== 5. the ground says whether it covered what it painted
--
-- The band under a Gen 4 map has survived five fixes, and the reason is that
-- the one deciding number was never measured: whether the ground COVERS the
-- canvas it paints into. Every reading of `Gen4Ground` says it does -- `y1` is
-- derived from `vh / sinP` precisely so that it should -- and a reading has
-- now been wrong five times running.
--
-- It also has to be measured on the path that RUNS. The earlier paint
-- reporting went into the baked loop; the editor's log says `drew LIVE`, so
-- that instrumentation has never once executed in the session it was written
-- for. That is its own lesson: instrument the branch the report came from.
local ground = io.open('src/render/Gen4Ground.lua'):read('a')
check(ground:match('self%.liveReach = '),
      'the LIVE pass must record how far down the canvas it reached')
check(ground:match('self%.liveWant = vh'), 'and what it was asked to cover')
check(ground:match('UNPAINTED BAND OF'),
      'and must say so in plain words when it falls short, rather than '
      .. 'leaving the reader to subtract two numbers')
check(ground:match('live coverage'), 'under a findable name')
-- The latch must include the reach, or a frame whose coverage CHANGES is
-- hidden by a key that only counts chunks.
check(ground:match('"live/%%d/%%.6f/%%d/%%d"'),
      'and the once-per-change latch must key on the reach too')

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
