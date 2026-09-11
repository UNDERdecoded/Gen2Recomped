-- Bake every map's terrain to disk, ahead of anyone walking into it.
--
-- THE PROBLEM. Meshing a route is expensive the first time: Structures has to
-- analyse it and ChunkMesher expands it into hundreds of thousands of
-- vertices. During normal play that cost is paid the moment the map becomes
-- your neighbour, in the few milliseconds a frame the pump can spare -- which
-- on a handheld is slow enough that walking into the next town arrives before
-- the town does, and the world stays flat where you are heading.
--
-- THE FIX. VoxelDiskCache can persist a map's BODY mesh under a key that does
-- not depend on where the player is standing -- only on the map, its tileset,
-- the editor's tile pins and the companion mod's config. So it can all be
-- baked up front, once, and afterwards every arrival is a file read instead
-- of a rebuild.
--
-- This module is the pass that does it: a queue of map ids, drained a slice
-- at a time so a prebake started from a menu never freezes the game, with
-- honest progress so the player can watch it finish. Nothing here touches the
-- GPU -- baking two hundred maps into VRAM would be an expensive way to run
-- out of it -- and nothing here is required: cancel it, or never run it, and
-- the renderer behaves exactly as it did, just meshing on demand.

local V = ...
local ChunkMesher = V.require("ChunkMesher")
local Budget = V.require("BuildBudget")

local Prebake = {}

local clock = (love and love.timer and love.timer.getTime) or os.clock

local state = nil

-- Slots to bake per map. FULL, and only FULL.
--
-- FULL used to be skipped entirely -- its key carried the resident-neighbour
-- rectangles, so a guessed set would bake an entry nothing ever asks for --
-- and BODY was baked instead, because a neighbour drew that one. Since
-- VoxelScene.masksFor both halves of that have turned over: the ring is cut
-- against the map's OWN neighbourhood rather than the player's, so the full
-- key no longer depends on where anyone is standing and bakes like any
-- other; and every map in the frame now draws the full mesh, neighbours
-- included, so nothing asks for the ring-less one at all.
--
-- It is also the expensive slot -- a ringed mesh is about 1.25x the region's
-- body geometry -- which is exactly what a prebake is for: paid once, ahead
-- of anyone walking in, instead of in the slices a frame can spare.
local SLOTS = { "full" }

local function reset()
  state = nil
end

function Prebake.running()
  return state ~= nil and not state.finished
end

-- `ids` is the list to bake; `resolve(id)` returns a live Map for one, or nil
-- plus a reason. The resolver belongs to the host because building a Map from
-- a def needs the tileset adapter, which is the bridge's business, not this
-- module's.
function Prebake.begin(ids, resolve)
  if type(ids) ~= "table" or type(resolve) ~= "function" then
    return false, "prebake needs a map list and a resolver"
  end
  local queue = {}
  for _, id in ipairs(ids) do
    if id ~= nil then queue[#queue + 1] = id end
  end
  if #queue == 0 then return false, "no maps to bake" end
  state = {
    queue = queue,
    at = 1,
    resolve = resolve,
    baked = 0,
    cached = 0,
    failed = 0,
    done = 0,
    total = #queue,
    current = nil,
    lastError = nil,
    started = clock(),
    finished = false,
    co = nil,
  }
  return true
end

function Prebake.cancel()
  if state then state.finished = true end
  reset()
end

function Prebake.progress()
  if not state then
    return { running = false, done = 0, total = 0 }
  end
  return {
    running = not state.finished,
    done = state.done,
    total = state.total,
    baked = state.baked,
    cached = state.cached,
    failed = state.failed,
    current = state.current,
    lastError = state.lastError,
    elapsed = clock() - state.started,
  }
end

-- One map, start to finish, inside a coroutine so ChunkMesher's own budget
-- ticks can suspend it mid-geometry and this pass can hand the frame back.
local function bakeOne(id, resolve)
  local map, err = resolve(id)
  if not map then return "failed", tostring(err or "map unavailable") end
  local outcome, reason
  for _, slot in ipairs(SLOTS) do
    local ok, why = ChunkMesher.bake(map, slot, nil)
    if ok then
      outcome = "baked"
    elseif why == "cached" then
      outcome = outcome or "cached"
    else
      outcome, reason = "failed", why
    end
  end
  return outcome or "failed", reason
end

local function advance(result, reason)
  state.done = state.done + 1
  if result == "baked" then
    state.baked = state.baked + 1
  elseif result == "cached" then
    state.cached = state.cached + 1
  else
    state.failed = state.failed + 1
    state.lastError = reason
  end
  state.at = state.at + 1
  state.co = nil
  state.current = nil
  if state.at > #state.queue then
    state.finished = true
  end
end

-- Drain for at most `seconds`. Call it once a frame with whatever the frame
-- can spare; it always returns, and always leaves a half-built map resumable.
function Prebake.pump(seconds)
  if not Prebake.running() then return false end
  seconds = tonumber(seconds) or 0.004
  local deadline = clock() + seconds
  while Prebake.running() and clock() < deadline do
    local id = state.queue[state.at]
    if id == nil then
      state.finished = true
      break
    end
    state.current = id
    if not state.co then
      local resolve = state.resolve
      state.co = coroutine.create(function() return bakeOne(id, resolve) end)
    end
    Budget.begin(state.co, deadline - clock())
    local ok, a, b = coroutine.resume(state.co)
    Budget.finish()
    if not ok then
      advance("failed", tostring(a))
    elseif coroutine.status(state.co) == "dead" then
      advance(a, b)
    else
      return true    -- slice spent mid-map; resume next frame
    end
  end
  if state and state.finished then
    local summary = Prebake.progress()
    state.summary = summary
  end
  return true
end

-- The last completed pass's numbers, kept after the queue empties so a menu
-- can still say what happened.
function Prebake.summary()
  return state and state.summary or nil
end

return Prebake
