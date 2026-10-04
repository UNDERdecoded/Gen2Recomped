-- Run:  texlua tools/model_preview_check.lua
--
-- THE SPINNING MODEL PREVIEWS in the map editor's model picker -- everything
-- about them that is not the picture.
--
-- Asked for: *"a list of all models with their previews next to them spinning
-- ... only spin when the player hovers over the list item and make the model
-- image bigger when hovered over as well"*.
--
-- WHY THIS FILE EXISTS IN THIS SHAPE. The 3D viewport in this tree "shipped
-- four times without ever drawing a frame, and every one of those times the
-- tests passed" -- so a check that claimed to test a preview by asserting the
-- draw function was called would be the fifth. The picture cannot be seen
-- here. Everything AROUND it can: which row's angle moves, what happens to the
-- others, the size change, the cache bound, whether a release happened, and
-- whether a failure is retried sixty times a second. Those are the parts that
-- were going to be wrong, and they are all plain bookkeeping.

local PASS, FAIL = 0, 0
local function check(cond, label)
  if cond then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. label) end
end

local MP = require('tools.map-editor.ModelPreview')

-- ================================================================= 1. the clock
--
-- ONLY THE HOVERED ROW MOVES. This is the whole performance argument: 590
-- models, and a row that animates is a model built, a depth target allocated
-- and a draw submitted every frame.
local S = {}
MP.tick(S, 0.5, 'set#1')
local a1 = MP.angleOf(S, 'set#1')
check(a1 > 0, 'the hovered row must turn, got ' .. tostring(a1))
check(MP.angleOf(S, 'set#2') == 0, 'and no other row may turn')

-- Half a turn period is half a turn.
local S2 = {}
MP.tick(S2, MP.TURN_SECONDS / 2, 'k')
check(math.abs(MP.angleOf(S2, 'k') - math.pi) < 1e-9,
      'half the turn period must be half a turn, got ' .. MP.angleOf(S2, 'k'))

-- A row KEEPS its pose when the pointer leaves, rather than snapping back
-- front-on -- the list should not flicker as the pointer crosses it.
MP.tick(S, 0.1, 'set#2')
check(math.abs(MP.angleOf(S, 'set#1') - a1) < 1e-12,
      'a row the pointer has left must hold its angle, got '
      .. MP.angleOf(S, 'set#1') .. ' was ' .. a1)

-- NOTHING hovered means NO row moves -- and this snapshots EVERY angle rather
-- than one chosen row.
--
-- The first version checked `set#2` alone, and a planted fault that made the
-- hover default to `set#1` sailed straight through it: the row it moved was
-- not the row being watched. An assertion about "no row" has to look at every
-- row, or it is an assertion about one row wearing a general name.
local snapshot = {}
for k, v in pairs(S.mpAngles or {}) do snapshot[k] = v end
MP.tick(S, 1.0, nil)
local moved = nil
for k, v in pairs(S.mpAngles or {}) do
  if snapshot[k] ~= v then moved = k end
end
check(moved == nil,
      'with nothing hovered NO row may turn -- ' .. tostring(moved)
      .. ' moved, so something is animating rows the pointer is not on, which '
      .. 'is 590 models of work per frame')

-- WRAPPED, and not with a loop. A frame after a long stall can be seconds
-- long; a `while angle > 2pi` would run thousands of times for one frame.
local S3 = {}
MP.tick(S3, MP.TURN_SECONDS * 1000, 'k')
local big = MP.angleOf(S3, 'k')
check(big >= 0 and big < math.pi * 2 + 1e-9,
      'the angle must stay inside one turn however long the frame was, got '
      .. big)

-- ================================================================== 2. the size
check(MP.sizeFor(false) == MP.SIZE, 'an ordinary row is the thumbnail size')
check(MP.sizeFor(true) == MP.HOVER_SIZE, 'and a hovered row is the large one')
check(MP.HOVER_SIZE > MP.SIZE,
      'the hovered picture must actually be BIGGER -- "make the model image '
      .. 'bigger when hovered" is the request, and equal sizes would satisfy '
      .. 'every other assertion here')
check(MP.SIZE >= 40, 'and the ordinary size must be big enough to read a '
      .. 'building at -- "medium sized entries so the user can actually see '
      .. 'the model"; got ' .. MP.SIZE)

-- ================================================================= 3. the key
check(MP.key('a', 1) ~= MP.key('b', 1),
      'the key must include the building set: a mod reuses member numbers, and '
      .. 'a key that forgot the set would show the previous set\'s picture '
      .. 'under the new set\'s name')
check(MP.key('a', 1) == MP.key('a', 1), 'and be stable')
check(MP.key('a', 1) ~= MP.key('a', 2), 'and separate members')

-- ======================================================= 4. the cache and bound
local S4 = {}
local built, released = 0, 0
local function fakeEntry()
  built = built + 1
  local function rel() released = released + 1 end
  return { model = {}, colour = { release = rel }, depth = { release = rel },
           size = MP.SIZE }
end
for i = 1, MP.CACHE_LIMIT do
  MP.entryFor(S4, MP.key('s', i), fakeEntry)
end
check(built == MP.CACHE_LIMIT, 'each new model must be built once, got ' .. built)
check(released == 0, 'and nothing evicted while inside the bound')
MP.entryFor(S4, MP.key('s', 1), fakeEntry)
check(built == MP.CACHE_LIMIT,
      'a cache HIT must not rebuild -- rebuilding on every frame is the stall '
      .. 'this cache exists to prevent; got ' .. built)

-- One past the bound evicts, and evicting RELEASES: a target is two canvases
-- of GPU memory and dropping the reference is not giving it back.
MP.entryFor(S4, MP.key('s', MP.CACHE_LIMIT + 1), fakeEntry)
check(built == MP.CACHE_LIMIT + 1, 'the new one is built')
check(released == 2, 'and the evicted one releases BOTH its canvases, got '
      .. released)
local held = 0
for _ in pairs(S4.mpCache) do held = held + 1 end
check(held == MP.CACHE_LIMIT, 'and the cache stays at its bound, got ' .. held)

-- LEAST RECENTLY USED, not least recently created. `s1` was touched after it
-- was built, so `s2` is the one that should have gone.
check(S4.mpCache[MP.key('s', 1)] ~= nil,
      'the entry touched most recently must survive eviction')
check(S4.mpCache[MP.key('s', 2)] == nil,
      'and the least recently used must be the one dropped')

-- ============================================================ 5. the failure latch
local S5 = {}
local attempts = 0
local function neverBuilds() attempts = attempts + 1; return nil end
for _ = 1, 10 do MP.entryFor(S5, 'bad', neverBuilds) end
check(attempts == 1,
      'a model that cannot be built must be tried ONCE and remembered -- '
      .. 'retrying sixty times a second is a stall that reads as the editor '
      .. 'hanging; got ' .. attempts .. ' attempts')
check(MP.failed(S5, 'bad'), 'and the failure must be recorded')
check(not MP.failed(S5, 'other'), 'without condemning anything else')

-- ================================================================ 6. forgetting
local S6 = {}
local freed = 0
S6.mpCache = { k = { colour = { release = function() freed = freed + 1 end },
                     depth = { release = function() freed = freed + 1 end } } }
S6.mpOrder = { 'k' }
S6.mpAngles = { k = 1 }
S6.mpFailed = { z = true }
MP.forget(S6)
check(freed == 2, 'forgetting must release every held canvas, got ' .. freed)
check(S6.mpCache == nil and S6.mpAngles == nil and S6.mpFailed == nil,
      'and clear the bookkeeping, or a re-import shows the previous '
      .. 'cartridge\'s models')

-- ============================================ 7. the picture is not faked here
--
-- `render` needs love.graphics. In this harness there is none, so it must fail
-- QUIETLY and latch -- not raise, and not report success. A preview that
-- claimed to have drawn without a GPU is precisely the lie this file's header
-- is about.
local S7 = {}
local okR, got = pcall(MP.render, S7, { shapes = {} }, 'k', MP.SIZE, 0)
check(okR, 'render must not raise with no graphics available: ' .. tostring(got))
check(got == nil, 'and must answer nil rather than a canvas it did not make')
check(MP.failed(S7, 'k'), 'and must latch so it is not retried every frame')

-- ============================================== 8. the previews are actually wired
local function slurp(path)
  local f = io.open(path, 'rb'); if not f then return '' end
  local s = f:read('*a'); f:close(); return s
end
local models = slurp('tools/map-editor/panels/Models.lua')
local app = slurp('tools/save-editor/App.lua')
local mp = slurp('tools/map-editor/ModelPreview.lua')
check(models:match('ModelPreview%.render'),
      'the picker rows must draw a preview, or the list is still names only')
check(models:match('ModelPreview%.tick%(S, dt, hoveredKey%)'),
      'and must tick exactly the hovered key -- ticking per row would animate '
      .. 'every model in the list')
-- RETIRED: the row used to size its picture by hover, and that was the bug --
-- see section 10, which now asserts the opposite. `sizeFor` is still the one
-- place that knows the two sizes; it is the floating panel that calls it.
check(mp:match('function ModelPreview%.sizeFor'),
      'sizeFor must remain the one place that knows the two sizes')
check(models:match('Kit%.hover'), 'and must detect the hover at all')
check(models:match('S%.modelZoom = e%.member'),
      'the eye must open a model, or there is no "proper look"')
check(models:match('function M%.drawDeferred'),
      'and the popup must be DEFERRED -- Kit has no z-order, so a popup drawn '
      .. 'inside the picker leaves every row under it still taking clicks')
-- `Kit.blockClicks` IS A BOOLEAN, so the popup must not call it -- and must
-- instead join App's modal predicate, which is where every other deferred
-- layer in this editor shields from.
check(not models:match('Kit%.blockClicks%('),
      'the popup must not CALL Kit.blockClicks -- it is a flag App sets, not a '
      .. 'shield function, and calling it calls a boolean')
check(app:match('S%.modelZoom ~= nil%) or false'),
      'and App must shield the frame while the eye popup is open, or the '
      .. 'picker rows under it still take clicks -- a panel drawn over live '
      .. 'hit targets is worse than one not drawn at all')

check(app:match('PANELS%.models%.drawDeferred'),
      'App must call the models panel\'s deferred layer, or the eye popup is '
      .. 'written and never drawn')

-- The row height the picker scrolls by must come from the same constant the
-- draw uses, or the list scrolls by one number and paints by another.
check(models:match('ModelPreview%.SIZE %* s %+ 10 %* s'),
      'the measured row height must be derived from ModelPreview.SIZE')

-- ================================== 9. the lag, the flip, and the honest message
--
-- Reported after the first cut shipped: *"its really laggy when loading the
-- list, and when i click the eyeball, as well as its rendering all models
-- upside down"*.
check(models:match('if ry %+ prow >= top and ry <= bottom then'),
      'the row loop must skip rows far outside the visible band -- the scroll '
      .. 'region CLIPS the pixels but the loop still asked all 590 rows for a '
      .. 'preview, which is the lag')
-- ...AND THE BAND MUST BE GENEROUS. An exact cull emptied the list below the
-- hovered row: `BodyFill` paints at `y - at`, so a row's position depends on
-- the scroll offset, and a one-row disagreement between that and this band
-- skips rows that are on screen. Skipped is not drawn, not merely clipped.
-- Culling too little costs a few throwaway draws; culling too much deletes the
-- list in front of the reader.
check(models:match('local top = bodyY %- bodyH')
      and models:match('local bottom = bodyY %+ bodyH %* 2'),
      'the cull band must carry a full body height of slack on each side, so '
      .. 'no plausible disagreement about where the band sits can hide a row')
-- A STATEMENT, NOT THE WORD. This asserted `not models:match('goto ')` and
-- failed on the COMMENT that explains why `goto` is not used -- shape 3e, a
-- prose scan defeated by prose about its own subject, which is already written
-- up in this tree's check-design lessons and caught me anyway. Comment lines
-- are skipped and the keyword must start a statement.
local gotos = 0
for line in models:gmatch('[^\r\n]+') do
  if not line:match('^%s*%-%-') and line:match('^%s*goto%s') then
    gotos = gotos + 1
  end
end
check(gotos == 0,
      'the panel must not USE `goto`, which is Lua 5.2 -- this tree targets '
      .. '5.1/LuaJIT; found ' .. gotos .. ' statement(s)')

check(mp:match('entry%.drawnAngle == angle'),
      'a preview whose angle has not moved must NOT be redrawn -- keeping the '
      .. 'angle still was never the same as keeping the picture still, and the '
      .. 'first version re-rendered every row every frame')
check(mp:match('function ModelPreview%.paint'),
      'there must be one place that draws a finished preview')
check(mp:match('love%.graphics%.draw%(canvas, x, y %+ size, 0, 1, %-1%)'),
      'and it must flip Y -- a canvas has Y growing down and the projection '
      .. 'has it growing up, which is why every model came out upside down')
check(not models:match('love%.graphics%.draw%(canvas'),
      'and the panel must not draw a canvas itself, or the rows and the eye '
      .. 'popup can disagree about which way up a model goes')

-- The "no chunk" message must name the real reason. A created map is not on
-- the Sinnoh chunk grid and never will be; telling its author to pick a cell
-- is sending them to do something that cannot work.
check(models:match('not on Sinnoh'),
      'the 3D PROPS panel must say that a created map has no chunk, rather '
      .. 'than "select a cell on a rendered Platinum map"')
check(models:match('Click a cell on the map'),
      'and must still say "click a cell" for the case where that IS the answer')

-- ======================= 10. the hover preview must not grow inside the row
--
-- Reported: *"when i hover over a listing that isnt at the top it makes the
-- title disappear and cant click the eye button for it"*. The row drew the
-- ENLARGED picture in place: a 48-wide slot, a title starting at 66, and a
-- 96-wide picture painted straight over it -- and overflowing the row's height
-- in both directions on top of that.
check(models:match('local size = ModelPreview%.SIZE %* s'),
      'the ROW must draw at the thumbnail size -- growing a cell inside a list '
      .. 'laid out by a fixed row height paints over its neighbours')
check(not models:match('ModelPreview%.sizeFor%(hot%)'),
      'and must not size the row picture by hover any more')
check(models:match('S%._mpHover = %{'),
      'the hovered row must be recorded for the floating preview')
check(models:match('ModelPreview%.HOVER_SIZE %* s'),
      'which draws at the large size, so "bigger when hovered" still happens')
check(models:match('if not hoveredKey then S%._mpHover = nil end'),
      'and must be cleared when nothing is hovered, or the panel sticks')

-- The cache must key on SIZE as well as model, or the row and the floating
-- preview release and reallocate one target against each other every frame.
check(mp:match('local cacheKey = key %.%. "@" %.%. tostring%(size%)'),
      'ModelPreview must cache per (model, size)')
check(not mp:match('if entry%.size ~= size then'),
      'and must not still carry the release-and-reallocate path that replaced')

-- `render` rejects a nil record on its first line, so the floating preview has
-- to pass a real one -- an earlier draft passed nil and drew nothing at all.
-- RE-PINNED. The floating preview no longer renders at all -- the panel
-- pre-renders the hovered key and this only paints -- so "must pass a real
-- record" is no longer the thing to guard. What matters now is the
-- separation: rendering switches the render target, painting does not.
check(models:match('ModelPreview%.canvasFor%(S, hv%.key'),
      'the floating preview must PAINT a pre-rendered canvas, not render one')
check(models:match('pcall%(ModelPreview%.render, S, M%.modelRecord%(ground, hv%.member%), hv%.key'),
      'and the panel must pre-render the hovered key with a real record')

-- ============ 13. no render-target switch inside the clipped row loop
--
-- Reported twice and they are the same bug: *"when i hover over an option all
-- options below it disappear"*, and *"when i scroll ... it acts like im
-- hovering over the list still, showing over my buttons in the UI"*.
--
-- `Kit.pushClip` sets a scissor and NOTHING re-applies it. `ModelPreview.render`
-- switches the render target, and a render-target switch clears the scissor --
-- so every row drawn after the first preview in a frame is unclipped. At one
-- scroll position that hides rows; at another it paints them over the panel's
-- own header. The fix is not a better clip, it is to do no rendering while the
-- clip is up.
check(models:match('local canvas = ModelPreview%.canvasFor%(S, key'),
      'the row loop must PAINT a pre-rendered canvas')
local loopStart = models:find('for _, e in ipairs%(picker%) do')
local loopEnd = models:find('ONE tick, for ONE key')
check(loopStart and loopEnd and loopEnd > loopStart, 'the row loop must be findable')
if loopStart and loopEnd then
  local body = models:sub(loopStart, loopEnd)
  check(not body:find('ModelPreview.render', 1, true),
        'and must not call ModelPreview.render ANYWHERE inside itself -- that '
        .. 'is the render-target switch that takes the clip with it')
end
check(models:match('EVERY PREVIEW IS RENDERED HERE, BEFORE THE CLIP GOES UP'),
      'and there must be a pre-render pass outside the clip')
check(models:match('BodyFill%.scrollOf%(S, "models"%)'),
      'which works out the visible rows from the same scroll offset the region '
      .. 'uses, rather than by drawing and finding out')

-- `canvasFor` must touch no graphics state at all, or the separation is
-- cosmetic.
check(not mp:match('function ModelPreview%.canvasFor[^\n]*\n[^\n]*setCanvas'),
      'canvasFor must not switch the render target')
check(mp:match('function ModelPreview%.canvasFor'), 'and must exist')
-- An entry that was built but never drawn into holds whatever the driver left
-- there; handing that back would paint garbage.
check(mp:match('if entry%.drawnAngle == nil then return nil end'),
      'and must refuse a canvas that has never been drawn into')

local ground = slurp('src/render/Gen4Ground.lua')
check(ground:find('painted %.0f..%.0f of a', 1, true) ~= nil,
      'the ground pass must LOG what it painted -- a footer only helps if the '
      .. 'screenshot includes the bottom of the window, and the ones that come '
      .. 'back are cropped above it')
check(ground:match('self%.saidPaint ~= key'),
      'and must say it once per distinct answer rather than per frame')

-- ================ 11. a map id that is not in this dataset must not crash
--
-- Reported as a crash on opening the Platinum map editor:
--
--   src/world/MapLoader.lua:120: unknown map: REDS_HOUSE_2F
--     tools/map-editor/panels/Models.lua:101: in function 'context'
--     tools/map-editor/panels/Models.lua:878: in function 'drawDeferred'
--
-- `MapLoader.load` ASSERTS on an id it does not know, and `context` called it
-- bare while every sibling panel calls it through `pcall`. `S.mapId` is not
-- guaranteed to belong to the loaded dataset -- the editor's own startup log
-- says "reading as 'platinum'; store holds crystal(13 map/16 added)" -- so a
-- foreign id is an ordinary thing to find, and a draw path that can assert on
-- one is a draw path that can kill the editor.
--
-- Driven through EVERY entry point that reaches `context`, not just the one
-- the traceback named: the same assert was reachable from the prop pick and
-- the placement, which run while the pointer is moving.
local Panel = require('tools.map-editor.panels.Models')
local function foreign()
  return { mapId = 'REDS_HOUSE_2F', version = 'platinum', mapEdits = {},
           data = { maps = {}, tilesets = {}, constants = {} } }
end

local okA, errA = pcall(Panel.propsInCell, foreign(), 0, 0)
check(okA, 'propsInCell must survive a map id this dataset does not have: '
      .. tostring(errA))
local okB = pcall(Panel.pickAt, foreign(), 0, 0)
check(okB, 'and so must pickAt, which runs on every click')
-- ARMED FIRST. `placeAt` returns before it touches `context` when nothing is
-- held, so an unarmed call passed under the planted fault and proved nothing.
local armed = foreign(); armed.modelPlacing = 1
local okC = pcall(Panel.placeAt, armed, 0, 0)
check(okC, 'and placeAt, with a model actually held')
local okD = pcall(Panel.ghostCells, foreign(), 1)
check(okD, 'and ghostCells, which runs every frame while a model is held')

-- The one from the traceback. `modelZoom` set is what makes it resolve the
-- ground rather than returning early.
local K = { scale = 1 }
K.textHeight = function() return 12 end
K.text = function() end
K.caption = function() end
K.card = function() end
K.row = function() end
K.press = function() return false end
K.button = function() return false end
K.stepper = function() return false end
K.hover = function() return false end
-- `emptyBox` is what the panel draws when it has no map, which is exactly
-- the path this section drives it down. Left out of the fake Kit at first,
-- and the resulting "attempt to call a nil value" read like the product
-- crash this section is about -- it was the harness.
K.emptyBox = function() end
local S11 = foreign(); S11.modelZoom = 3
local okE, errE = pcall(Panel.drawDeferred, S11, K)
check(okE, 'and drawDeferred, which is where it actually crashed: ' .. tostring(errE))

-- ...and the panel's own draw, for completeness.
local okF = pcall(Panel.draw, foreign(), K, 0, 0, 300, 600)
check(okF, 'and the panel draw itself')

-- The fix must be the PCALL, not a guard that happens to avoid the call: the
-- assert is reachable from six places and only one of them was in the
-- traceback.
check(models:match('pcall%(Loader%.load, S%.data, S%.mapId%)'),
      'context must call the loader through pcall -- guarding one call site '
      .. 'leaves the other five able to assert')
check(not models:match('\n  local map = Loader%.load%(S%.data, S%.mapId%)'),
      'and must not still call it bare')

-- The deferred layer must not resolve a map when it has nothing to draw --
-- that is most frames, and it was paying for a map lookup on every one.
check(models:match('local function groundOnce'),
      'drawDeferred must resolve the ground lazily rather than on every frame')

-- ============ 12. the cull can never hide a row that is actually on screen
--
-- The arithmetic, exercised over every scroll position rather than argued
-- about. For each offset, every row that OVERLAPS the visible body must fall
-- inside the cull band -- and the band must still reject the great majority of
-- 590 rows, or it is not a cull.
do
  local bodyY, bodyH, prow, pitch = 300, 420, 58, 61
  local top, bottom = bodyY - bodyH, bodyY + bodyH * 2
  local hidden, worstKept = 0, 0
  for at = 0, 590 * pitch, 37 do
    local kept = 0
    for n = 0, 589 do
      local ry = (bodyY - at) + 5 + n * pitch
      local onScreen = (ry + prow >= bodyY) and (ry <= bodyY + bodyH)
      local inBand = (ry + prow >= top) and (ry <= bottom)
      if onScreen and not inBand then hidden = hidden + 1 end
      if inBand then kept = kept + 1 end
    end
    if kept > worstKept then worstKept = kept end
  end
  check(hidden == 0,
        hidden .. ' row(s) that overlap the visible body fall outside the cull '
        .. 'band -- those rows are not drawn at all, which is the list going '
        .. 'empty')
  check(worstKept < 60,
        'and the band must still reject most of the 590 rows or it is not a '
        .. 'cull -- worst case kept ' .. worstKept)
end

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
