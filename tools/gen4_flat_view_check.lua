-- Run:  texlua tools/gen4_flat_view_check.lua
--
-- THE BLACK BAR ACROSS THE BOTTOM OF THE GEN 4 MAP EDITOR, and the one number
-- that was producing it.
--
-- Reported three times -- "theres a black bar on the map editor in gen4
-- blocking part of the screen", then "still seeing a black bar in the bottom
-- of the viewport", then "its like its an overlay on top of the map viewport".
-- Two fixes missed it. The block-to-cell ratio was genuinely wrong and worth
-- fixing; the camera clamp was genuinely missing and worth adding; neither was
-- what was short, because the shortfall is not in the editor's arithmetic at
-- all -- every rectangle it computes is correct.
--
-- The Gen 4 ground renderer draws with the CARTRIDGE's camera. Every one of
-- the seventeen camera rows is pitched, and a pitched camera compresses ground
-- depth by sin(pitch): 0.858 at the default row's 59.05 degrees. Handed a
-- viewport `vh` pixels tall it fills 0.858*vh of it and leaves the rest
-- showing `GEN4_BACKDROP` -- RGB(24,26,34), which is the black. Gen 1-3 never
-- had the bar because their renderers have no pitch to compress.
--
-- So the editor is not asking a wrong question; it is asking the right
-- question of a renderer aimed at a different projection. `setFlatView` points
-- it straight down -- `Gen4Camera.scales(nil)` already defaults to pitch 90 --
-- and the control below is the half that matters: the OVERWORLD must still get
-- the pitch, because the pitch is the picture the DS draws.
--
-- No cartridge and no cache: the camera table is the cartridge's, transcribed,
-- and `applyCamera` is called for real on a minimal instance.

local PASS, FAIL = 0, 0
local function check(cond, label)
  if cond then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. label) end
end
local function near(a, b, eps)
  return type(a) == 'number' and math.abs(a - (b or 0)) <= (eps or 1e-9)
end

local Cam = require('src.render.Gen4Camera')
local Ground = require('src.render.Gen4Ground')

-- ---------------------------------------------------------------- 1. the flat
-- WHAT "FLAT" IS, asked of the camera module rather than asserted here. The
-- whole fix rests on `scales(nil)` meaning pitch 90, so that is the first
-- thing measured: if the default ever stops being 90 the fix stops working and
-- this says so instead of the bar quietly coming back.
local fg, fh = Cam.scales(nil)
check(near(fg, 1), 'Gen4Camera.scales(nil) must answer ground scale 1 -- the '
      .. 'flat view is built on nil meaning pitch 90, got ' .. tostring(fg))
check(near(fh, 0), 'and height scale 0: at pitch 90 nothing leans, got ' .. tostring(fh))
check(near(Cam.lean(nil), 0), 'and lean 0, which is what keeps a plan view square')

-- ------------------------------------------------------- 2. the bar's own size
-- THE DEFECT, MEASURED. A check that only asserted the fix would pass just as
-- well on a renderer that never had the bug, and would therefore say nothing
-- about why this file exists.
local dg = Cam.scales(Cam.forType(0))
check(dg < 1, 'the DEFAULT camera row must compress ground depth -- if it does '
      .. 'not, there was never a bar and this check has lost its subject')
check(near(dg, 0.857630, 1e-5), 'and by sin(59.05 deg) = 0.85763, so the '
      .. 'unpainted band is 14.24% of the viewport height; got ' .. tostring(dg))

-- EVERY row, not just the one Twinleaf uses. The bar was reported on C01 and on
-- C01FS0101, which are different camera rows, and an invariant over all
-- seventeen is worth more than two examples.
local rows, worst, worstId = 0, 0, nil
for id = 0, 16 do
  local cfg = Cam.forType(id)
  if type(cfg) == 'table' then
    rows = rows + 1
    local g = Cam.scales(cfg)
    check(type(g) == 'number' and g > 0 and g < 1,
          ('camera row %d (%s) must be pitched, not flat -- a row with no '):format(
            id, tostring(cfg.id)) .. 'compression would need no flat view')
    if 1 - g > worst then worst, worstId = 1 - g, cfg.id end
  end
end
check(rows == 17, 'all seventeen cartridge camera rows must be present, got ' .. rows)
check(worst > 0.2, 'and the worst row must lose over a fifth of the viewport -- '
      .. 'the bar is not a rounding error; worst is ' .. tostring(worstId)
      .. ' at ' .. string.format('%.1f%%', worst * 100))

-- ------------------------------------------------- 3. applyCamera, called real
-- The real function on a minimal instance, rather than a transcription of what
-- it does. `applyCamera` derives the canvas size and the projection from these
-- two numbers, so measuring them measures the picture.
local function applied(flat)
  local self_ = setmetatable({ def = {}, chunkPx = 512, half = 256,
                               viewPitch = flat and 90 or nil,
                               baked = {}, order = {}, canopies = {},
                               animated = {}, depthModels = {} },
                             { __index = Ground })
  local ok, err = pcall(Ground.applyCamera, self_)
  return ok and self_ or nil, err
end

local flat = applied(true)
check(flat ~= nil, 'applyCamera must run with flatView set')
check(flat and near(flat.groundScale, 1),
      'flatView must give ground scale 1 -- this is the bar closing, got '
      .. tostring(flat and flat.groundScale))
check(flat and near(flat.lean, 0), 'and lean 0, or props would still shear')
check(flat and flat.canvasPx == 512,
      'and the chunk canvas must be exactly chunkPx tall: at pitch 90 there is '
      .. 'no compressed ground to leave room above, got '
      .. tostring(flat and flat.canvasPx))

-- THE CONTROL, and the one that would catch the wrong fix. Flattening the
-- renderer outright would also remove the bar, and would also delete the
-- cartridge's own projection from the game.
local pitched = applied(false)
check(pitched and near(pitched.groundScale, 0.857630, 1e-5),
      'WITHOUT the flag the renderer must still draw with the cartridge pitch '
      .. '-- the overworld is not a plan view; got '
      .. tostring(pitched and pitched.groundScale))
check(pitched and pitched.lean > 0.5,
      'and must still lean, or Sinnoh is being drawn as a floor plan in play')
check(pitched and pitched.canvasPx > 512,
      'and must still allocate room for what stands on the ground')

-- ------------------------------------------------------------ 4. the flag held
-- A FLAT SCALE ASSIGNED FROM OUTSIDE WOULD NOT SURVIVE. `draw` re-applies the
-- camera whenever `Gen4Camera.generation` ticks, so the flag has to be read
-- INSIDE applyCamera; a caller that set `groundScale = 1` itself would lose it
-- the first time the OPTIONS tilt moved, and the bar would return with no edit
-- to blame. This is that tick.
local held = setmetatable({ def = {}, chunkPx = 512, half = 256,
                            baked = {}, order = {}, canopies = {},
                            animated = {}, depthModels = {} },
                          { __index = Ground })
check(pcall(Ground.setFlatView, held, true), 'setFlatView must run')
check(near(held.groundScale, 1), 'setFlatView must apply at once')
local before = held.tiltGeneration
Cam.generation = (Cam.generation or 0) + 1
pcall(Ground.applyCamera, held)
check(near(held.groundScale, 1),
      'and must SURVIVE a tilt change -- an assignment from the caller would '
      .. 'have been overwritten here, which is the regression this guards')
check(held.tiltGeneration ~= before or before == nil,
      'and the re-apply must have actually happened, or the line above proves '
      .. 'nothing')

-- THE DEFAULT IS THE CARTRIDGE'S OWN ANGLE. A renderer nobody has spoken to
-- must draw Sinnoh the way the DS does; the editor opting into 90 is a choice
-- the user makes, not the state the world starts in.
local untouched = applied(false)
check(untouched and untouched.viewPitch == nil,
      'a renderer with no explicit pitch must keep nil, not adopt one')
check(untouched and near(untouched.groundScale, 0.857630, 1e-5),
      'and must draw at the cartridge pitch, got '
      .. tostring(untouched and untouched.groundScale))

-- An arbitrary angle, which is what the control steps through.
local tilted = setmetatable({ def = {}, chunkPx = 512, half = 256,
                              baked = {}, order = {}, canopies = {},
                              animated = {}, depthModels = {} },
                            { __index = Ground })
check(pcall(Ground.setViewPitch, tilted, 45), 'setViewPitch(45) must run')
check(near(tilted.groundScale, math.sin(math.rad(45)), 1e-6),
      'and 45 degrees must compress the ground by sin(45) = 0.7071, got '
      .. tostring(tilted.groundScale))
check(pcall(Ground.setViewPitch, tilted, nil), 'and nil must be accepted')
check(near(tilted.groundScale, 0.857630, 1e-5),
      'putting the map back on its own camera, got ' .. tostring(tilted.groundScale))
check(pcall(Ground.setViewPitch, tilted, 1000) and tilted.viewPitch == 90,
      'and an out-of-range angle must clamp rather than produce a projection '
      .. 'with no inverse; got ' .. tostring(tilted.viewPitch))

-- Idempotent, and returns the instance: called once a frame from the panel,
-- so a second call must not drop every baked chunk again.
local n = 0
local probe = setmetatable({ def = {}, chunkPx = 512, half = 256,
                             baked = {}, order = {}, canopies = {},
                             animated = {}, depthModels = {},
                             dropBakes = function(s) n = n + 1 end },
                           { __index = Ground })
check(Ground.setFlatView(probe, true) == probe, 'setFlatView must return self')
Ground.setFlatView(probe, true)
Ground.setFlatView(probe, true)
check(n == 1, 'and must drop the bakes only on a CHANGE: it is called every '
      .. 'frame, and re-baking every chunk every frame is not a fix, got ' .. n)
Ground.setFlatView(probe, false)
check(n == 2 and probe.groundScale < 1,
      'and must be reversible, so a map the editor flattened goes back to the '
      .. 'cartridge pitch when the game reloads it')

-- ------------------------------------------------- 5. the panel actually asks
-- A NAME IS NOT A CALL. An earlier check in this editor's suite was satisfied
-- by a function DEFINITION matching its pattern, so this looks for a
-- statement, and for the guard beside it.
local f = assert(io.open('tools/map-editor/panels/Preview.lua', 'rb'))
local code = f:read('*a'); f:close()
local calls = 0
for line in code:gmatch('[^\r\n]+') do
  if line:match('setViewPitch') and line:match('^%s*pcall%s*%(') then
    calls = calls + 1
  end
end
check(calls >= 1, 'nothing in Preview.lua calls setViewPitch as a statement -- '
      .. 'the renderer has an angle and the panel never asks for one')

-- RE-PINNED, AND THE DIRECTION MATTERS. This asserted `setFlatView` while the
-- panel forced a straight-down view; the panel now asks for the USER's angle
-- and defaults to the cartridge's own. Reported: *"add the tilt back and add
-- an option for changing the camera angle above the map view"*. So the thing
-- to guard is no longer "is it flattened" but "can it be, and is it not by
-- default" -- an assertion whose subject is a to-do item has to be turned
-- round once the item is done, or it holds the tree at the old answer.
check(code:match('S%.pvTilt'),
      'the panel must carry a chosen tilt, not a hardcoded one')
check(code:match('pcall%(map%.renderer%.gen4Ground%.setViewPitch,[^\r\n]*\r?\n?[^\r\n]*S%.pvTilt')
      or code:match('setViewPitch,%s*map%.renderer%.gen4Ground,%s*\r?\n?%s*S%.pvTilt'),
      'and must pass it through rather than a literal -- a literal 90 here is '
      .. 'the forced flat view coming back under another name')
check(not code:match('setViewPitch%s*,%s*map%.renderer%.gen4Ground%s*,%s*90'),
      'and must not pin 90')
-- The control itself, which is the half the user asked for.
check(code:match('"TILT"'), 'there must be a TILT control above the map view')
check(code:match('MapKind%.meshGround%(S'),
      'and it must be offered only on a mesh-ground map: Gen 1-3 renderers '
      .. 'have no pitch, so the control would be inert there')
check(code:match('S%.pvTilt = nil'),
      'and there must be a way back to the cartridge angle -- it is a '
      .. 'different KIND of answer from a number and the steppers cannot '
      .. 'reach it')
check(code:match('renderer%.gen4Ground%s+then'),
      'and it must be guarded on gen4Ground: a Gen 1-3 map has no ground '
      .. 'renderer at all and must not be asked for a flat one')

-- AND THE BACKDROP IS STILL WHAT SHOWS. If this ever stops being the fill, the
-- bar described in this file's header would be a different colour and the
-- diagnosis above would be stale.
local t = assert(io.open('src/render/TileRenderer.lua', 'rb'))
local tile = t:read('*a'); t:close()
check(tile:match('GEN4_BACKDROP%s*=%s*{%s*24%s*/%s*255'),
      'GEN4_BACKDROP must still be RGB(24,26,34) -- that is the black that was '
      .. 'reported, and it is what fills the part of the viewport the ground '
      .. 'does not reach')
check(tile:match('g%.rectangle%("fill",%s*0,%s*0,%s*vw%s*or%s*0,%s*vh%s*or%s*0%)'),
      'and it must still be painted over the WHOLE viewport, which is why a '
      .. 'ground that covers 85.8% of it leaves a bar rather than nothing')

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
