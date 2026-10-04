-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- A SPINNING PICTURE OF ONE BUILD MODEL, for the picker's rows.
--
-- Asked for: *"a list of all models with their previews next to them spinning
-- ... make the list have medium sized entries so the user can actually see the
-- model, and only spin when the player hovers over the list item and make the
-- model image bigger when hovered over as well"*.
--
-- WHY "ONLY WHEN HOVERED" IS THE DESIGN AND NOT A CONCESSION.
--
-- There are 590 build models. A row that animates is a model built, a depth
-- target allocated and a draw submitted EVERY FRAME; doing that for every
-- visible row would be dozens of 3D passes per frame to animate pictures
-- nobody is looking at, and this editor already has a note about costs that
-- "show up later as the editor feels heavy". One row spins -- the one under
-- the pointer -- and that is also the one the reader is actually reading.
--
-- WHAT THIS FILE OWNS AND WHAT IT DOES NOT. It owns the clock, the hover rule,
-- the sizes, the cache and its bound, and the failure latch -- all of which are
-- plain arithmetic and bookkeeping, and all of which are checked headlessly.
-- It does NOT own a second 3D renderer: the picture comes from `Gen4Model`,
-- which already has `new`, `framing`, `orbit`, `perspective`, `newTarget` and
-- `draw`. This tree's note on the 3D viewport is worth repeating -- it
-- "shipped four times without ever drawing a frame, and every one of those
-- times the tests passed" -- so the parts a test CAN see are separated from
-- the one part it cannot, and the one part it cannot is a handful of calls
-- into a module that is already drawn with every day.

local ModelPreview = {}

-- The row thumbnail, and the enlarged one under the pointer. A CHOICE, not a
-- measurement: 48px is about the smallest a Sinnoh building reads at, and
-- doubling is the smallest change that is unmistakably a change. Named here so
-- the row layout and the render agree on one number rather than two.
ModelPreview.SIZE = 48
ModelPreview.HOVER_SIZE = 96

-- A full turn in seconds. Slow enough to read the shape, fast enough that a
-- hover shows you the back of the model before you lose patience.
ModelPreview.TURN_SECONDS = 4

-- How many built models and targets to hold. 590 is far too many -- each is
-- geometry plus two canvases -- and the picker shows a page at a time, so the
-- working set is the page plus whatever the pointer has visited.
ModelPreview.CACHE_LIMIT = 24

-- The key for one model in one building set. The SET is in it because a mod
-- with its own models reuses the same member numbers for different things; a
-- key that forgot it would show the previous set's picture under the new set's
-- name, which is the same class of bug as the catalogue's own cache.
function ModelPreview.key(setId, member)
  return tostring(setId or "?") .. "#" .. tostring(member)
end

-- THE CLOCK. Advances ONE entry -- the hovered one -- and leaves every other
-- angle exactly where it was, so a row keeps the pose it was last seen at
-- rather than snapping back to front-on when the pointer leaves.
--
-- `dt` is seconds. Wrapped into [0, 2pi) so the number cannot grow without
-- bound across a long session.
function ModelPreview.tick(S, dt, hoveredKey)
  S.mpAngles = S.mpAngles or {}
  if hoveredKey == nil then return nil end
  local two = math.pi * 2
  local step = (tonumber(dt) or 0) / ModelPreview.TURN_SECONDS * two
  local at = (S.mpAngles[hoveredKey] or 0) + step
  -- `%` rather than a while-loop: a frame after a long stall can be seconds
  -- long, and a loop would run thousands of times for one frame.
  S.mpAngles[hoveredKey] = at % two
  return S.mpAngles[hoveredKey]
end

function ModelPreview.angleOf(S, key)
  return (S and S.mpAngles and S.mpAngles[key]) or 0
end

function ModelPreview.sizeFor(hovered)
  return hovered and ModelPreview.HOVER_SIZE or ModelPreview.SIZE
end

-- THE FAILURE LATCH. A model whose geometry will not build, or a size this
-- driver will not give a depth target for, fails the same way on every frame.
-- Retrying it sixty times a second is a stall that looks like the editor
-- hanging; `Gen4Ground` latches its live pass the same way for the same
-- reason.
function ModelPreview.failed(S, key)
  return not not (S and S.mpFailed and S.mpFailed[key])
end

function ModelPreview.markFailed(S, key, why)
  S.mpFailed = S.mpFailed or {}
  S.mpFailed[key] = why or true
  return false
end

-- The built model for a key, building it on first use and evicting the least
-- recently used when the cache is full.
--
-- Eviction RELEASES, because a target is two canvases of GPU memory and
-- dropping the reference is not the same as giving it back.
-- `failKey` is the key the FAILURE is remembered under, which is not always
-- the key the entry is cached under. The cache is per (model, size); a model
-- that cannot be built fails at every size, so latching on the size-qualified
-- key would retry it once per size -- and the hover preview asks for a second
-- size, so "once" quietly became "twice, for ever".
function ModelPreview.entryFor(S, key, build, failKey)
  failKey = failKey or key
  S.mpCache = S.mpCache or {}
  S.mpOrder = S.mpOrder or {}
  local hit = S.mpCache[key]
  if hit then
    -- Touch: move to the end of the order so it is the last to be evicted.
    for i, k in ipairs(S.mpOrder) do
      if k == key then table.remove(S.mpOrder, i); break end
    end
    S.mpOrder[#S.mpOrder + 1] = key
    return hit
  end
  if ModelPreview.failed(S, failKey) then return nil end
  local entry = build and build() or nil
  if not entry then
    return ModelPreview.markFailed(S, failKey, "could not build")
  end
  S.mpCache[key] = entry
  S.mpOrder[#S.mpOrder + 1] = key
  while #S.mpOrder > ModelPreview.CACHE_LIMIT do
    local oldest = table.remove(S.mpOrder, 1)
    local dropped = S.mpCache[oldest]
    S.mpCache[oldest] = nil
    if type(dropped) == "table" then
      for _, field in ipairs({ "colour", "depth" }) do
        local c = dropped[field]
        if c and c.release then pcall(c.release, c) end
      end
    end
  end
  return entry
end

-- Drop everything. Called when the building set changes under us -- a mod
-- loaded, a re-import -- because every cached picture is then of the previous
-- cartridge's models.
function ModelPreview.forget(S)
  for _, entry in pairs((S and S.mpCache) or {}) do
    if type(entry) == "table" then
      for _, field in ipairs({ "colour", "depth" }) do
        local c = entry[field]
        if c and c.release then pcall(c.release, c) end
      end
    end
  end
  if S then
    S.mpCache, S.mpOrder, S.mpFailed, S.mpAngles = nil, nil, nil, nil
  end
end

-- ---------------------------------------------------------------- the picture
--
-- The only part a headless check cannot see. Everything it needs has been
-- decided above; this is the handful of calls into `Gen4Model`.
--
-- Guarded at every step rather than assumed: a driver with no depth format
-- gives no target, and a record whose geometry will not parse raises. Either
-- one latches as a failure and the row falls back to its name and footprint,
-- which is what the row showed before previews existed and is still useful.
function ModelPreview.render(S, record, key, size, angle)
  if type(record) ~= "table" then return nil end
  if ModelPreview.failed(S, key) then return nil end
  local okMod, Gen4Model = pcall(require, "src.render.Gen4Model")
  if not (okMod and type(Gen4Model) == "table" and Gen4Model.new) then
    return ModelPreview.markFailed(S, key, "Gen4Model unavailable") and nil
  end
  -- CACHED PER (MODEL, SIZE), not per model.
  --
  -- The row draws at the thumbnail size and the hover preview at twice it, and
  -- with one entry per model those two sizes fought over the same target: every
  -- frame the pointer sat on a row, the entry was released and reallocated at
  -- the other size. Two canvases is cheaper than two allocations a frame, and
  -- the failure latch stays on the MODEL key so a model that cannot be built is
  -- not retried once per size.
  local cacheKey = key .. "@" .. tostring(size)
  local entry = ModelPreview.entryFor(S, cacheKey, function()
    local okNew, model = pcall(Gen4Model.new, record)
    if not (okNew and model) then return nil end
    local colour, depth = Gen4Model.newTarget(size, size)
    if not colour then return nil end
    return { model = model, colour = colour, depth = depth, size = size }
  end, key)
  if not entry then return nil end

  -- DO NOT REDRAW A PICTURE THAT HAS NOT CHANGED.
  --
  -- Reported: *"its really laggy when loading the list, and when i click the
  -- eyeball"*. The first version re-rendered on every call, so a list of 590
  -- rows submitted 590 model draws a frame -- and the hover rule, which only
  -- stops the ANGLE advancing, did nothing about that at all. Keeping the
  -- angle still was never the same as keeping the picture still.
  --
  -- A canvas is only redrawn when its angle actually moved (the hovered row,
  -- and the eye popup) or when it has never been drawn. Everything else hands
  -- back the canvas it already has, which is a texture bind and nothing else.
  if entry.drawnAngle ~= nil and entry.drawnAngle == angle
     and entry.drawnSize == size then
    return entry.colour
  end

  local okDraw = pcall(function()
    local pose = entry.model:restPose()
    local centre, distance = entry.model:framing(pose)
    -- Pitched down a little rather than side-on: a roof is most of what
    -- identifies a Sinnoh building, and a dead-level camera hides it.
    local view = Gen4Model.orbit(centre, distance, angle or 0, math.rad(25))
    local proj = Gen4Model.perspective(math.rad(40), 1, distance / 16,
                                       distance * 4)
    local g = love.graphics
    g.push("all")
    g.setCanvas({ entry.colour, depthstencil = entry.depth })
    g.clear(0, 0, 0, 0, true, true)
    g.origin()
    -- `multiply`, which is the name this module actually exports -- and NOT a
    -- fallback that passes `{ proj, view }` when it is missing. A guess like
    -- that is how a 3D path ships "working": the call succeeds, the shader is
    -- handed a table that is not a matrix, and nothing is ever drawn. If the
    -- composer is gone this must raise and latch as a failure.
    entry.model:draw(Gen4Model.multiply(proj, view), pose, nil, nil, nil,
                     "lequal")
    g.pop()
  end)
  if not okDraw then
    return ModelPreview.markFailed(S, key, "draw raised") and nil
  end
  entry.drawnAngle, entry.drawnSize = angle, size
  return entry.colour
end

-- THE CANVAS FOR A KEY, WITHOUT RENDERING ANYTHING.
--
-- `render` switches the render target, and a render-target switch in the
-- middle of a clipped list is unrecoverable: `Kit.pushClip` sets a scissor and
-- nothing re-applies it, so everything drawn after the switch is unclipped --
-- rows landing over the panel header at one scroll position and vanishing at
-- another, which is exactly what was reported.
--
-- So the two halves are separated. `render` is called BEFORE the clip goes up,
-- for the rows that will be visible; this hands back what it produced, and is
-- safe to call anywhere because it touches no graphics state at all.
function ModelPreview.canvasFor(S, key, size)
  local entry = S and S.mpCache and S.mpCache[key .. "@" .. tostring(size)]
  if type(entry) ~= "table" then return nil end
  -- `drawnAngle` nil means the entry was built but never drawn into, so its
  -- canvas holds whatever the driver left there -- usually garbage.
  if entry.drawnAngle == nil then return nil end
  return entry.colour
end

-- DRAW A FINISHED PREVIEW, THE RIGHT WAY UP.
--
-- Reported: *"its rendering all models upside down"*. A canvas in LOVE has its
-- origin at the top-left and Y growing DOWN, while the projection that drew
-- into it has Y growing UP -- so the picture lands mirrored vertically. The
-- flip belongs at the draw rather than in the matrix: the geometry inside the
-- canvas is correct, it is the two conventions meeting that is not, and
-- negating the projection's Y would put the model's own winding inside out and
-- turn the depth test against it.
--
-- One function, used by both the rows and the eye popup, so the two cannot end
-- up disagreeing about which way up a model goes.
function ModelPreview.paint(canvas, x, y, size)
  if not (canvas and love and love.graphics) then return false end
  love.graphics.setColor(1, 1, 1, 1)
  -- Drawn from the BOTTOM edge with a negative Y scale: the image occupies the
  -- same rectangle, upside down relative to the canvas, which is the right way
  -- up relative to the screen.
  love.graphics.draw(canvas, x, y + size, 0, 1, -1)
  return true
end

return ModelPreview
