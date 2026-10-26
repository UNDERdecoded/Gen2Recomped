-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- WHERE THE POKEWALKER'S STEPS COME FROM: the phone's own step counter.
--
-- Android's bridge (love.system.syncHealthSteps -> GameActivity.syncHealthSteps,
-- mobile/ANDROID.md "Step bridge") reads the hardware TYPE_STEP_COUNTER and
-- publishes a cumulative steps_journal.json in the save directory. The counter runs
-- while the app is closed, so a read on opening credits the whole walk.
-- The walker's cursor is saved with its credited steps. Mods retain separate
-- receipts. Legacy native hosts keep their existing pending-file path.
--
-- STEP_DEBUG=n credits n steps once (desktop testing; no sensor there).

local S = {}

S.FILE = "steps_pending.json"
S.EVERY = 60          -- seconds between sensor reads while the app is up

local last = -math.huge
local debugDone = false
local Journal = require('src.core.StepJournal')
local unsaved = setmetatable({}, {__mode='k'})

function S.available()
  return love and love.system and type(love.system.syncHealthSteps) == "function"
end

-- ask the sensor (Android); the reading lands in the file a moment later
function S.request(force)
  local now = love.timer and love.timer.getTime() or os.time()
  if not force and now - last < S.EVERY then return end
  last = now
  if S.available() then pcall(love.system.syncHealthSteps) end
end

-- the staged steps, consumed; 0 when there are none
function S.take(st)
  local n = 0
  if not debugDone and os.getenv and tonumber(os.getenv("STEP_DEBUG") or "") then
    debugDone = true
    n = n + tonumber(os.getenv("STEP_DEBUG"))
  end
  local fs=love and love.filesystem
  if fs and fs.getInfo(Journal.FILE,'file') then
    local snapshot,why=Journal.read(fs)
    if not snapshot then return n,nil,why end
    local delivery,cursor,err=Journal.next(snapshot,st and st.stepsJournal)
    return n+(delivery and delivery.steps or 0),cursor,err
  end
  -- A versioned native producer migrates the legacy file into its first
  -- snapshot before requesting OS consent. Consuming it here could race that
  -- migration and credit the same legacy backlog again through the journal.
  if Journal.available() then return n end
  if fs and fs.getInfo(S.FILE) then
    local body = love.filesystem.read(S.FILE) or ""
    local ok, Json = pcall(require, "src.link.Json")
    local okD, doc = false, nil
    if ok then okD, doc = pcall(Json.decode, body) end
    local steps = okD and type(doc) == "table" and tonumber(doc.steps) or tonumber(body:match('"steps"%s*:%s*(%d+)'))
    if steps and steps > 0 then n = n + math.floor(steps) end
    love.filesystem.remove(S.FILE)
  end
  return n
end

-- one tick: read when due, credit what arrived; returns the steps credited
function S.pump(st, courses, force)
  S.request(force)
  local n,cursor = S.take(st)
  local W = require('src.pokewalker.Walker')
  if n > 0 then
    W.addSteps(st, n, courses)
    if cursor then st.stepsJournal=cursor end
    unsaved[st]=true
  end
  if unsaved[st] then
    local ok=W.save(st)
    if ok then unsaved[st]=nil end
  end
  if n > 0 then
    -- the phone's background check measures from here now
    pcall(require("src.pokewalker.WalkerNotify").watch, st, courses)
  end
  return n
end

return S
