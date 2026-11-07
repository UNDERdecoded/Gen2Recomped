-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- BLACK / WHITE'S ARRIVAL SCRIPTS: script op 0x021 <entry> queues entry n of
-- whatever zone the next warp lands in (Gen5ScriptLink's note on 0x021).
-- Run here once the map has changed and the script that warped has ended --
-- the order the field gives them, the warping script's `releaseall; end`
-- first, the destination's scene after.

local M = {}

local function Game() return package.loaded["src.core.Game"] end

local function busy(ow)
  return (ow.runner and ow.runner.isRunning and ow.runner:isRunning())
      or (ow.pendingScripts and #ow.pendingScripts > 0)
      or ow.warping or ow.transition
end

function M.update(ow)
  -- the Musical's backstage: back to the lobby once its review has run
  -- (src/script/Gen5MusicalBackstage.lua)
  if Game() and Game().gen5Musical then pcall(require("src.script.Gen5MusicalBackstage").tick, ow) end
  -- a field return lasts as long as the script that asked for it
  if ow.gen5FieldReturn and not busy(ow) and not ow.gen5QueuedEntry then ow.gen5FieldReturn = nil end
  local q = ow.gen5QueuedEntry
  if not q then return end
  if q.sameMap then ow.gen5FieldReturn = nil end
  local mapId = ow.map and ow.map.id
  if mapId == q.from and not q.sameMap then return end
  if busy(ow) then return end
  ow.gen5QueuedEntry = nil
  local G = Game()
  local ms = G and G.data and G.data.map_scripts
  local rec = ms and ((ms.maps and ms.maps[mapId]) or ms[mapId])
  local label = rec and rec.entries and rec.entries[q.entry]
  if not label then
    require("src.core.Logger").warn("gen5 queued entry %d: %s has no such script (re-import Black/White's scripts)",
      q.entry, tostring(mapId))
    return
  end
  local rows = require("src.script.Gen4ScriptVM").compile(G.data, label)
  if not rows then return end
  require("src.core.Logger").info("gen5 queued entry %d on %s: %s", q.entry, tostring(mapId), label)
  ow.runner:run(rows, { mapId = mapId })
end

return M
