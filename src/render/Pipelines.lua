-- Rendering pipelines: the engine side of the render_pipelines registry.
--
-- A pipeline is a display mode a mod owns.  It may replace the overworld's
-- world pass with geometry of its own (drawWorld) and/or post-process the
-- finished composite (present).  Everything else about being a display mode
-- -- the OFF/1/2/3 ladder, the options row, the hotkey, persistence, the
-- free-roam gate, and never letting a mod's error take the frame down -- is
-- engine plumbing and lives here, so a renderer mod writes the two draw
-- functions and declares the rest.
--
-- The two halves compose independently and in priority order: the highest
-- priority eligible drawWorld renders the world, then every eligible
-- present folds over whatever came out (the world pipeline's canvas, or the
-- vanilla flat/tilt composite when none ran).  A present that is switched
-- off returns its input, so a full ladder of them costs nothing at level 0.
--
-- Nothing here reaches collision, movement, triggers or scripts: like
-- survey zoom and tilt, a pipeline is purely presentational, which is why
-- its level rides in save.options rather than the save proper.
--
-- Spec: docs/modding.md (rendering pipelines)

local Data = require("src.core.Data")
local Logger = require("src.core.Logger")
local Runtime = require("src.mods.Runtime")
local Zoom = require("src.render.Zoom")

local Pipelines = {}

-- id -> level.  Levels live here rather than on the records because the
-- records are merged content: frozen after load, and shared with whatever
-- else reads Data.
local levels = {}

-- ids whose callbacks have already thrown, so a pipeline that fails every
-- frame reports once instead of filling the log at 60Hz
local broken = {}

-- id -> consecutive failures.  A pipeline is not retired on its FIRST throw
-- any more.  A 3D renderer misses a frame for reasons that have nothing to do
-- with the mod being wrong -- a canvas that is not resident yet on the frame a
-- map loads, a model still streaming in, a device that lost its context on a
-- resize -- and retiring for the whole session on one of those took the
-- feature away until the player restarted.  Worse, when the retired pipeline
-- was an UPDATE tick the world quietly half-worked: the Stadium mod's wild
-- Pokemon kept their sprites but never finished spawning, so they stood there
-- unbattleable, because the tick that sets `canTriggerBattle` had been
-- switched off two hundred frames earlier.
--
-- Ten in a row is a mod that is actually broken; one is a hiccup.  A run of
-- good frames clears the count.
local failures = {}
local MAX_FAILURES = 10

Pipelines.DEFAULT_LEVELS = { "OFF", "ON" }

-- The merged dataset the records live in.  The boot singleton is the
-- default -- Game.data is that very table -- and install() lets a headless
-- caller (the SDK harness, a tool) point this at a dataset of its own.
local source = Data

function Pipelines.install(data)
  source = data or Data
  Pipelines.reset()
end

-- ------- catalog

-- Every registered pipeline as { id = ..., def = ... }, ordered by priority
-- (descending, ties by id) so selection, the options rows and the present
-- fold all walk the same sequence.
--
-- Memoized on the namespace table's identity.  Content freezes at the merge
-- boundary, so the answer cannot change for a given table -- and this is
-- read several times per frame by update(), worldPipeline() and the
-- endFrame present check, which is no place to allocate and sort.  An empty
-- list is cached too, so a mod-free boot pays one table for the process.
local listCache, listSource = nil, nil

function Pipelines.list()
  local defs = source and source.render_pipelines
  if defs == listSource and listCache then return listCache end
  local out = {}
  if type(defs) == "table" then
    for id, def in pairs(defs) do
      -- the merge writes provenance under _owners; skip the bookkeeping
      -- keys rather than treating them as pipelines
      if type(id) == "string" and id:sub(1, 1) ~= "_" and type(def) == "table" then
        out[#out + 1] = { id = id, def = def }
      end
    end
    table.sort(out, function(a, b)
      local pa, pb = a.def.priority or 0, b.def.priority or 0
      if pa ~= pb then return pa > pb end
      return a.id < b.id
    end)
  end
  listCache, listSource = out, defs
  return out
end

function Pipelines.get(id)
  local defs = source and source.render_pipelines
  local def = type(defs) == "table" and defs[id] or nil
  return type(def) == "table" and def or nil
end

-- A DRIVER, not a display mode: registered only to get a per-frame callback,
-- with no options row and no persisted level.  See Schemas.render_pipelines
-- for why the persistence half matters more than the row.
function Pipelines.isInternal(id)
  local def = Pipelines.get(id)
  return (def and def.internal) == true
end

-- the mod that registered a pipeline, so a runtime failure lands in the
-- feed the mod manager shows instead of only in the console
local function ownerOf(id)
  local defs = source and source.render_pipelines
  local owners = type(defs) == "table" and defs._owners or nil
  return owners and owners[id] or nil
end

-- Run one of a pipeline's callbacks under pcall.  A mod that throws mid-
-- frame must not take the frame with it: the pipeline is marked broken,
-- attributed once, and treated as absent from then on -- which degrades to
-- the vanilla 2D path rather than a black screen.
-- Retire a pipeline for the rest of the session, once, with a reason.
local function retire(id, reason)
  if broken[id] then return end
  broken[id] = true
  Logger.error("render pipeline %s: %s -- disabled for this session",
               id, tostring(reason))
  Runtime.reportError(ownerOf(id), "render pipeline disabled: " .. tostring(reason))
end
Pipelines.retire = retire

local function guard(id, fn, ...)
  if broken[id] then return nil end
  local ok, result = pcall(fn, ...)
  if ok then
    failures[id] = nil
    return result
  end
  local n = (failures[id] or 0) + 1
  failures[id] = n
  if n == 1 then
    -- the first one is worth seeing even when the pipeline recovers, because
    -- it is the line that names the file and the line number
    Logger.warn("render pipeline %s failed: %s", id, tostring(result))
  end
  if n >= MAX_FAILURES then
    retire(id, ("failed %d frames running (last: %s)"):format(n, tostring(result)))
  end
  return nil
end

-- Whether a callback's return is a real Canvas we can composite.  A mod that
-- forgets a return, or hands back a shade string / flag / number, must be
-- ignored rather than trusted -- draw() on a non-canvas takes the frame down.
-- Real LOVE canvases are userdata answering typeOf("Canvas"); the headless
-- test stub (tests/love_stub) fakes them as tables carrying the Canvas method
-- shape (love.graphics.newCanvas), so accept either and nothing else.
local function isCanvas(v)
  if type(v) == "userdata" then
    return type(v.getWidth) == "function" and type(v.getHeight) == "function"
  end
  if type(v) == "table" then
    return type(v.getWidth) == "function" and type(v.getHeight) == "function"
  end
  return false
end

-- Dispatch a mod render callback with its GPU state fenced off: push("all")
-- before and pop() after, so a callback that returns cleanly but leaves a
-- shader bound, the canvas redirected, or blend/colour changed cannot corrupt
-- the engine composite that follows.  guard() catches a callback that throws;
-- this catches one that dirties state.  A pipeline already retired skips the
-- push/pop entirely, so the stack stays balanced.
--
-- IT ALSO HAS TO SURVIVE A CALLBACK THAT LEAKS PUSHES, which is a different
-- failure and a nastier one.  LOVE's graphics stack is a small fixed depth, so
-- a callback that pushes without popping does not fail on the frame it leaks:
-- it leaves the stack one deeper, and sixty-odd frames later the ENGINE's own
-- `push("all")` on the line below throws "Maximum stack depth reached (more
-- pushes than pops?)".  That throw is OUTSIDE any pcall, so it ends the frame,
-- the handler, and the process:
--
--     Error: src/render/Pipelines.lua:139: Maximum stack depth reached
--     ...
--     error: the game failed to start
--
-- and the traceback names this file rather than whoever leaked, which is a
-- miserable thing to debug.  Two guards, both of them cheap:
--
--   * our own push is pcall'd, so a stack that is ALREADY full retires this
--     pipeline instead of taking the frame down;
--   * the callback's own pushes are COUNTED for the duration of the call, and
--     anything it forgot to pop is popped here -- so one leaky frame cannot
--     compound into a crash a second later, and the log names the pipeline
--     that did it.
--
-- The counter shims love.graphics.push/pop for exactly the length of the call.
-- A callback that cached those two functions in locals beforehand slips past
-- it; the pcall on our own push is the backstop for that case.
local function guardRender(id, fn, ...)
  if broken[id] then return nil end
  local g = love.graphics
  if not pcall(g.push, "all") then
    retire(id, "the graphics stack was already full when this pipeline ran "
             .. "(some callback is pushing without popping)")
    return nil
  end

  local depth = 0
  local realPush, realPop = g.push, g.pop
  g.push = function(...) depth = depth + 1 return realPush(...) end
  g.pop = function(...) depth = depth - 1 return realPop(...) end
  local out = guard(id, fn, ...)
  g.push, g.pop = realPush, realPop

  if depth > 0 then
    -- unbalanced in our favour: unwind the callback's surplus back down to the
    -- snapshot we took above, then pop that snapshot as usual
    for _ = 1, depth do
      if not pcall(realPop) then break end
    end
    retire(id, ("left %d graphics push(es) unpopped"):format(depth))
  elseif depth < 0 then
    -- it popped past its own pushes and ate OURS, so the engine's state is
    -- already whatever the callback left behind and there is no snapshot of
    -- ours left to pop -- doing it anyway would eat the CALLER's.  Stop here
    -- rather than making it worse.
    retire(id, ("popped %d more graphics state(s) than it pushed"):format(-depth))
    return out
  end
  realPop()
  return out
end

-- ------- levels

function Pipelines.levelLabels(id)
  local def = Pipelines.get(id)
  local labels = def and def.levels
  if type(labels) ~= "table" or labels[1] == nil then
    return Pipelines.DEFAULT_LEVELS
  end
  return labels
end

-- highest selectable level: one less than the label count, so a two-label
-- ladder is a plain OFF/ON toggle
function Pipelines.maxLevel(id)
  return #Pipelines.levelLabels(id) - 1
end

function Pipelines.level(id)
  return levels[id] or 0
end

function Pipelines.levelLabel(id, level)
  local labels = Pipelines.levelLabels(id)
  return labels[(level or Pipelines.level(id)) + 1] or labels[1] or "OFF"
end

-- A world pipeline and the engine's own tilt mode are two answers to the
-- same question, so switching one on switches the other off -- the rule
-- tilt and survey zoom already follow between themselves.  Present-only
-- pipelines (post-processes) compose with tilt and are left alone.
local function excludeTilt(id, level)
  local def = Pipelines.get(id)
  if not (def and def.drawWorld) or level <= 0 then return end
  local Tilt = require("src.render.Tilt")
  if Tilt.level > 0 then Tilt.setLevel(0) end
  -- ONE WORLD PIPELINE AT A TIME, for the same reason.
  --
  -- And SAY SO.  Two mods that each render the world -- DRAMATIC_SHAPE's
  -- `voxel` and STADIUM2_OVERWORLD_MODELS' `stadium2_gold_voxel` -- both ask
  -- for this slot, and the loser is switched off here with nothing on screen
  -- and nothing in the log to say it happened.  What the player sees is the
  -- WINNER's world with the loser's features missing: 3D terrain drawn by one
  -- mod, and the other mod's Stadium models simply absent, while both mods'
  -- own options still read ON because neither of them turned anything off.
  -- That is unfalsifiable from inside the game, so it is logged.
  for _, entry in ipairs(Pipelines.list()) do
    if entry.id ~= id and entry.def.drawWorld and Pipelines.level(entry.id) > 0 then
      levels[entry.id] = 0
      Logger.warn("render pipeline %s took the world pass; %s switched off "
        .. "(only one may draw the world). Anything %s draws INTO the world "
        .. "-- models, entities, terrain -- will not appear.",
        id, entry.id, entry.id)
    end
  end
end

function Pipelines.setLevel(id, level)
  if not Pipelines.get(id) then return 0 end
  -- a driver has no ladder: it runs whenever `available` says yes
  if Pipelines.isInternal(id) then
    levels[id] = 1
    return 1
  end
  level = math.floor(tonumber(level) or 0)
  if level < 0 then level = 0 end
  local max = Pipelines.maxLevel(id)
  if level > max then level = max end
  levels[id] = level
  excludeTilt(id, level)
  return level
end

-- Advance the ladder and wrap to OFF, the shape every display hotkey walks.
function Pipelines.cycle(id, dir)
  local max = Pipelines.maxLevel(id)
  if max < 1 then return 0 end
  local span = max + 1
  local target = (Pipelines.level(id) + (dir or 1)) % span
  if target < 0 then target = target + span end
  return Pipelines.setLevel(id, target)
end

-- Turning a world pipeline on must switch tilt off in the save too, not
-- just in the live module, or the next boot restores both.  Call sites hand
-- over the options table so this stays the one place that rule lives.
function Pipelines.syncOptions(opts)
  if type(opts) ~= "table" then return end
  local bucket = opts.pipelines
  if type(bucket) ~= "table" then
    bucket = {}
    opts.pipelines = bucket
  end
  for _, entry in ipairs(Pipelines.list()) do
    -- A driver is never written to the save.  Persisting one is a trap with a
    -- long fuse: a single stored 0 outranks the level the mod sets for itself
    -- at registration for the rest of that save's life, and the player has no
    -- row to turn it back on with.
    if entry.def.internal then
      bucket[entry.id] = nil
    else
      bucket[entry.id] = Pipelines.level(entry.id)
      if entry.def.drawWorld and Pipelines.level(entry.id) > 0 then
        opts.tilt = 0
      end
    end
  end
end

-- Restore levels from a loaded options table.  A pipeline whose mod is gone
-- keeps its stored level untouched in the bucket (so re-enabling the mod
-- restores the mode) but contributes nothing while absent.
--
-- NO STORED PREFERENCE IS NOT "OFF".
--
-- This wiped `levels` and read every id out of the bucket with `or 0`, so a
-- pipeline the player has never touched was forced off -- including one a mod
-- had just switched ON for itself at registration, which is the only way a
-- mod can ship a pipeline that is enabled by default.  The first applyOptions
-- after load silently undid it.
--
-- That is not a display nicety: a mod may put real per-frame work in a
-- pipeline callback (STADIUM2_OVERWORLD_MODELS drives its entire wild-Pokemon
-- AI from one), and `present` only runs while the level is above zero.  So
-- the Pokemon spawned, never ticked, never moved, never made contact and
-- never started a battle -- "the wild Pokemon do nothing" -- with nothing in
-- any log to say why, because nothing had failed.
--
-- A stored value still wins outright; absence now means "leave it as it is".
function Pipelines.applyOptions(opts)
  local bucket = type(opts) == "table" and opts.pipelines or nil
  local live = levels
  levels = {}
  broken = {}
  local world = nil
  for _, entry in ipairs(Pipelines.list()) do
    if entry.def.internal then
      -- a driver is on, always: it has no ladder, and a stale 0 left in an old
      -- save must not be able to switch it off for the life of that save
      levels[entry.id] = 1
      if type(bucket) == "table" then bucket[entry.id] = nil end
    else
      local stored = type(bucket) == "table" and bucket[entry.id] or nil
      if stored == nil then stored = live[entry.id] end
      local level = math.floor(tonumber(stored) or 0)
      if level < 0 then level = 0 end
      local max = Pipelines.maxLevel(entry.id)
      if level > max then level = max end
      -- list() is priority order, so the first world pipeline with a stored
      -- level is the one that wins; the rest restore to OFF rather than
      -- sitting on a level that can never render
      if entry.def.drawWorld and level > 0 then
        if world then level = 0 else world = entry.id end
      end
      levels[entry.id] = level
    end
  end
  -- a restored world pipeline and tilt are two answers to the same
  -- question; the pipeline wins, as it does at every place that sets one
  if world then require("src.render.Tilt").setLevel(0) end
end

function Pipelines.reset()
  levels = {}
  broken = {}
  failures = {}
end

-- ------- per-frame

-- Presentational tweens run on real frame time, like Tilt's.  Every
-- pipeline ticks, not just the active ones: a mode easing back OUT still
-- has an angle to retire.
function Pipelines.update(dt)
  for _, entry in ipairs(Pipelines.list()) do
    if entry.def.update then
      guardRender(entry.id, entry.def.update, dt, Pipelines.level(entry.id))
    end
  end
end

-- A pipeline may run this frame when it is switched on, has not thrown, and
-- its hardware gate says yes.  `available` is consulted every frame rather
-- than cached: a driver that loses its depth canvas on a resize has to be
-- able to change its mind.
--
-- Deliberately NOT gated on the state stack.  `gate` governs whether the
-- player may CHANGE the mode, never whether it draws -- a display mode that
-- stopped rendering during a warp, a scripted cutscene or an open menu
-- would flash the flat 2D world for those frames every time the player
-- walked through a door.  Once a mode is on it renders until it is off.
function Pipelines.eligible(id)
  local def = Pipelines.get(id)
  if not def or broken[id] then return false end
  if Pipelines.level(id) <= 0 then return false end
  if def.available and guard(id, def.available) ~= true then return false end
  return true
end

-- Whether the player may cycle this mode right now: the free-roam gate,
-- which keeps a hotkey press from switching modes mid-warp or mid-cutscene.
-- Input only -- see eligible() for why the draw path does not consult it.
function Pipelines.canToggle(id, top, overworld)
  local def = Pipelines.get(id)
  if not def then return false end
  local gate = def.gate or Zoom.gateOK
  return guard(id, gate, top, overworld) == true
end

-- The pipeline that owns the world pass right now, or nil for the vanilla
-- flat/tilt draw.  Highest priority wins; the exclusion rules above mean
-- there is normally only one candidate anyway.
-- WHO OWNS THE WORLD, AND WHY NOT THE OTHERS.
--
-- A world pipeline that does not run leaves NOTHING on screen or in the log to
-- say so: the frame simply falls back to the flat draw, which is a perfectly
-- good frame.  Three separate things silence it -- level 0, an `available`
-- gate answering no, and retirement after repeated throws -- and from inside a
-- running game they are indistinguishable from each other and from a mod that
-- chose to be off.  Every one of them has cost a real debugging session.
--
-- So the decision is reported whenever it CHANGES, with each candidate's level,
-- retirement and `available` answer.  Only on a change: the report calls
-- `available` a second time, and this runs every frame.
local lastWorldReport = nil

local function reportWorldPass(chosen)
  local parts = {}
  for _, entry in ipairs(Pipelines.list()) do
    if entry.def.drawWorld then
      local id = entry.id
      local avail = "n/a"
      if entry.def.available then
        avail = tostring(guard(id, entry.def.available) == true)
      end
      parts[#parts + 1] = ("%s(level=%d available=%s%s)"):format(
        id, Pipelines.level(id), avail, broken[id] and " RETIRED" or "")
    end
  end
  if not parts[1] then return end
  Logger.warn("world pass: %s -- candidates: %s",
    chosen or "NOBODY (flat/tilt draw)", table.concat(parts, " "))
end

function Pipelines.worldPipeline()
  local chosen, chosenDef
  for _, entry in ipairs(Pipelines.list()) do
    if entry.def.drawWorld and Pipelines.eligible(entry.id) then
      chosen, chosenDef = entry.id, entry.def
      break
    end
  end
  -- keyed on the OUTCOME, so a steady state reports once and a flap reports
  -- each way exactly once per swing
  local key = chosen or "\0none"
  if key ~= lastWorldReport then
    lastWorldReport = key
    reportWorldPass(chosen)
  end
  return chosen, chosenDef
end

-- Render the world through `id`.  Returns the canvas to composite, or nil
-- when the pipeline declined this frame (nothing to draw, a transient
-- failure), which the caller treats as "fall back to the 2D path".
function Pipelines.drawWorld(id, ctx)
  local def = Pipelines.get(id)
  if not (def and def.drawWorld) then return nil end
  return guardRender(id, def.drawWorld, ctx)
end

-- Fold every eligible world post-process over a pipeline's world image,
-- before the UI composites on top.  This is where a depth-of-field or a
-- colour grade belongs when it must leave the dialog boxes and menus crisp;
-- `present` below is the whole-frame counterpart.  Only reachable once some
-- pipeline rendered the world, so it is gated on the overworld state the
-- same way drawWorld is.
function Pipelines.worldPresent(canvas, ctx)
  if canvas == nil then return nil end
  for _, entry in ipairs(Pipelines.list()) do
    if entry.def.worldPresent and Pipelines.eligible(entry.id) then
      local out = guardRender(entry.id, entry.def.worldPresent, canvas, ctx)
      -- accept only a real Canvas: a pass that returns a non-canvas (a
      -- forgotten return, a shade string) is ignored, not folded in
      if isCanvas(out) then canvas = out end
    end
  end
  return canvas
end

-- Fold every eligible post-process over the finished frame.  Present
-- pipelines are not gated on the overworld state -- a CRT curve or a colour
-- grade applies to menus and battles too -- so eligibility here is just
-- "switched on and available".  A pass that returns a non-canvas is
-- ignored rather than trusted, so a mod cannot blank the screen by
-- forgetting a return.
function Pipelines.present(canvas, ctx)
  if canvas == nil then return nil end
  for _, entry in ipairs(Pipelines.list()) do
    if entry.def.present and Pipelines.eligible(entry.id) then
      local out = guardRender(entry.id, entry.def.present, canvas, ctx)
      -- accept only a real Canvas: a pass that returns a non-canvas is
      -- ignored (docstring above), so a mod cannot blank or crash the frame
      -- by forgetting a return or handing back a truthy non-canvas
      if isCanvas(out) then canvas = out end
    end
  end
  return canvas
end

-- true when any present-only pass wants to run, so the composite path can
-- skip allocating a target it would not use
function Pipelines.wantsPresent()
  for _, entry in ipairs(Pipelines.list()) do
    if entry.def.present and Pipelines.eligible(entry.id) then return true end
  end
  return false
end

-- ------- input and UI

-- Cycle whichever pipeline claims `key`.  Returns the id when one did, so
-- the caller knows the key was consumed.  Checked after the engine's own
-- display hotkeys, so a mod can never shadow one.
function Pipelines.hotkey(key, top, overworld)
  for _, entry in ipairs(Pipelines.list()) do
    if entry.def.hotkey == key and not entry.def.internal then
      -- the gate belongs here and nowhere else: it stops the player
      -- flipping modes mid-warp or mid-cutscene, and has no say over
      -- whether an already-on mode draws
      if Pipelines.canToggle(entry.id, top, overworld) then
        Pipelines.cycle(entry.id)
        return entry.id
      end
      return nil
    end
  end
  return nil
end

-- Options rows for every registered pipeline, in the same priority order,
-- in the descriptor shape src/ui/OptionRows.lua renders.
function Pipelines.rows(game)
  local rows = {}
  for _, entry in ipairs(Pipelines.list()) do
    -- a driver has no ladder to show; the mod that registered it owns the
    -- toggle, wherever it chose to put it
    if not entry.def.internal then
      local id = entry.id
      rows[#rows + 1] = {
        id = "pipeline:" .. id,
        label = entry.def.label or id:upper(),
        value = function() return Pipelines.levelLabel(id) end,
        step = function(g, dir)
          Pipelines.cycle(id, dir)
          local opts = g and g.save and g.save.options
          if opts then
            Pipelines.syncOptions(opts)
            -- the exclusion above may have switched tilt off; keep the live
            -- module in step with the option it just wrote
            require("src.render.Tilt").setLevel(opts.tilt or 0)
          end
          return true
        end,
      }
    end
  end
  return rows
end

-- Drop every pipeline's GPU objects (window resize, hot reload).
function Pipelines.invalidate()
  for _, entry in ipairs(Pipelines.list()) do
    if entry.def.invalidate then guardRender(entry.id, entry.def.invalidate) end
  end
end

return Pipelines
