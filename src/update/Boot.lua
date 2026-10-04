-- The boot shell: the heart of the self-updater.  A fused build, before it
-- runs the game bundled inside it, looks in its save directory for a newer
-- payload (a downloaded Gen2Recomped-X.Y.Z.love), and if one is present and
-- runnable, mounts it over the bundled source and chainloads it -- so the
-- binary shipped once can keep updating the Lua it runs without a reinstall.
--
-- Only a fused build self-updates.  A dev / source checkout IS the game, so
-- Boot.run is a no-op there.
--
-- Three pieces, deliberately layered so the risky part is small and the
-- decision part is testable:
--   * Boot.select     -- pure: given probed candidates + the bundled version,
--                        decide what to run and what to delete.  No love.*.
--   * Boot.probePayload-- read one archive's advertised version, isolated.
--   * Boot.run        -- orchestrates: crash-guard, enumerate, select, and
--                        (if a payload wins) mount + chainload with full
--                        rollback on any failure so the bundled game always
--                        boots.
--
-- Known limitation: the bundled love.run keeps driving the frame loop after a
-- handoff (it has already returned its stepper to LÖVE; redefining the global
-- love.run does nothing to the running one).  A payload that must change
-- love.run itself therefore requires a minShell bump so an older shell refuses
-- to chainload it.

local Semver = require("src.update.Semver")
-- The folder, the asset name and the pattern that recognises one all come from
-- here.  They were three literals in this file and four more in
-- src/update/check_worker.lua, so the downloader and the boot shell each had
-- their own copy of where a payload lives -- the recurring fault in this tree.
local Payload = require("src.update.Payload")
-- The sideload verdict: a payload that arrived by hand (the only update path
-- the Switch and Xbox have outside the native OTA launcher) used to be mounted
-- with no integrity check at all, while every other arrival route refused a bad
-- hash.  src/update/Sideload.lua owns the decision and the wording; this file
-- owns the hashing and the mount.
local Sideload = require("src.update.Sideload")

local Boot = {}

-- Save-directory layout (identity "pokemon-love2d"), per the shared contract.
local PAYLOAD_DIR = Payload.DIR
local PENDING = Payload.PENDING

-- Isolated mountpoint used only to peek at a candidate's Version.lua, so its
-- copy never collides with the running source's copy at "/".
local PROBE_MOUNT = "__pokeport_probe"

-- Downloaded payloads are named Gen2Recomped-<X.Y.Z>.love.
local isPayloadName = Payload.isName

-- The love callbacks the payload's main.lua chunk may redefine when it runs.
-- We snapshot these before a handoff and restore them if the handoff fails, so
-- the exact bundled closures (with their intact upvalues) drive the game
-- again.  love.run is included: harmless to restore, and it is one of the
-- globals a payload main.lua reassigns.
local CALLBACK_NAMES = {
  "load", "update", "draw", "quit", "run",
  "keypressed", "keyreleased", "textinput",
  "mousepressed", "mousereleased", "mousemoved", "wheelmoved",
  "touchpressed", "touchmoved", "touchreleased",
  "gamepadpressed", "gamepadreleased", "gamepadaxis",
  "joystickpressed", "joystickreleased", "joystickaxis", "joystickhat",
  "joystickremoved",
  "focus", "visible", "resize", "filedropped", "directorydropped",
  "errorhandler", "threaderror", "lowmemory",
}

local function snapshotCallbacks()
  local snap = {}
  for _, k in ipairs(CALLBACK_NAMES) do snap[k] = love[k] end
  return snap
end

local function restoreCallbacks(snap)
  for _, k in ipairs(CALLBACK_NAMES) do love[k] = snap[k] end
end

-- Drop every bundled Lua module the payload must be allowed to re-resolve: all
-- src.* modules plus the main/conf chunks.  conf.lua cached the bundled
-- Version into package.loaded["src.core.Version"]; without this purge the next
-- require would hand back the bundled copy instead of the payload's.  Setting
-- existing fields to nil during a pairs traversal is explicitly permitted.
local function purgeBundledModules()
  for key in pairs(package.loaded) do
    if key:match("^src%.") or key == "main" or key == "conf" then
      package.loaded[key] = nil
    end
  end
end

-- Boot.probePayload(rel) -> { engine = string, minShell = number } | nil, err
--
-- Mount the archive at rel (a save-directory-relative path) on an isolated
-- mountpoint, read its src/core/Version.lua by executing the source with
-- loadstring (NEVER require -- we must not cache or run it as a module), then
-- unmount.  Version.lua is zero-require, so running its chunk is safe.
function Boot.probePayload(rel)
  if not love.filesystem.mount(rel, PROBE_MOUNT) then
    return nil, "could not mount " .. tostring(rel)
  end
  local chunkPath = PROBE_MOUNT .. "/src/core/Version.lua"
  local ok, result = pcall(function()
    local src = love.filesystem.read(chunkPath)
    if not src then error("Version.lua missing", 0) end
    local chunk = loadstring(src, "@" .. chunkPath)
    if not chunk then error("Version.lua would not compile", 0) end
    return chunk()
  end)
  love.filesystem.unmount(rel)
  if not ok then return nil, tostring(result) end
  local v = result
  if type(v) ~= "table" or type(v.engine) ~= "string" then
    return nil, "payload has no usable Version table"
  end
  return { engine = v.engine, minShell = tonumber(v.minShell) or 1 }
end

-- Boot.sha256hex(rel) -> lowercase hex | nil, err
--
-- love.data is a core module and conf.lua disables only physics, so hash() is
-- there on every host including NX and UWP.  No incremental form exists in
-- LOVE 11.x, so the payload is read whole -- which is why this is reached only
-- when the player has actually placed a manifest (see Boot.sideloadCheck).
function Boot.sha256hex(rel)
  if not (love.data and love.data.hash and love.data.encode) then
    return nil, "love.data is not available to hash with"
  end
  local data = love.filesystem.read(rel)
  if not data then return nil, "could not read " .. tostring(rel) end
  local ok, digest = pcall(love.data.hash, "sha256", data)
  if not ok or not digest then return nil, "sha256 failed" end
  if type(digest) == "userdata" and digest.getString then
    digest = digest:getString()
  end
  local okHex, hex = pcall(love.data.encode, "string", "hex", digest)
  if not okHex or type(hex) ~= "string" then return nil, "hex encode failed" end
  return hex:lower()
end

-- Boot.sideloadCheck(name, sumsText) -> verdict, expected, actual
--
-- Split out so the expensive half (reading and hashing the archive) is skipped
-- entirely when there is no manifest to compare against, and so the cheap half
-- stays a pure decision in src/update/Sideload.lua.
function Boot.sideloadCheck(name, sumsText)
  if type(sumsText) ~= "string" then
    return Sideload.verdict(name, nil, nil)
  end
  -- An unlisted payload is refused without hashing it: the manifest already
  -- settles the question and 20 MB of sha256 would change nothing.
  if not Payload.parseSums(sumsText, name) then
    return Sideload.verdict(name, sumsText, nil)
  end
  local actual, err = Boot.sha256hex(PAYLOAD_DIR .. "/" .. name)
  if not actual then
    -- Could not hash a payload whose sum IS listed.  Refusing is the only safe
    -- answer: the alternative is mounting an archive we were asked to verify
    -- and could not, which is the silent accept this whole module exists to
    -- remove.  The reason travels in place of the hash so the line says it.
    return Sideload.MISMATCH, Payload.parseSums(sumsText, name),
      "unreadable (" .. tostring(err) .. ")"
  end
  return Sideload.verdict(name, sumsText, actual)
end

-- Boot.select(candidates, bundledEngine, bundledShell) -> chosen | nil, toDelete
--
-- Pure (no love.*): decide which payload to run and which to delete.
-- candidates is a list of { name = , engine = , minShell = }.
--   * chosen: the highest engine that is STRICTLY newer than bundledEngine and
--     whose minShell <= bundledShell (a payload the running shell can host).
--   * toDelete: stale payloads -- engine <= bundled (old or the same as what we
--     already ship), or superseded by the chosen one (not newer than chosen).
--     A payload newer than the chosen one but unrunnable here (minShell too
--     high) is kept: a future shell upgrade may be able to run it.
function Boot.select(candidates, bundledEngine, bundledShell)
  local chosen
  for _, c in ipairs(candidates) do
    local newer = Semver.compare(c.engine, bundledEngine) > 0
    local runnable = (c.minShell or 1) <= bundledShell
    if newer and runnable then
      if not chosen or Semver.compare(c.engine, chosen.engine) > 0 then
        chosen = c
      end
    end
  end

  local toDelete = {}
  for _, c in ipairs(candidates) do
    if not (chosen and c.name == chosen.name) then
      local stale = Semver.compare(c.engine, bundledEngine) <= 0
      if chosen and Semver.compare(c.engine, chosen.engine) <= 0 then
        stale = true
      end
      if stale then toDelete[#toDelete + 1] = c.name end
    end
  end

  return chosen and chosen.name or nil, toDelete
end

-- Mount the chosen payload and hand control to it.  Returns true when the
-- payload is live and has completed its own love.load; false (with full
-- rollback) on any failure, so the caller runs the bundled game instead.
local function chainload(name, args)
  local rel = PAYLOAD_DIR .. "/" .. name

  -- Crash marker: if we die between here and clearing it, the next boot's
  -- crash guard distrusts this payload and deletes it.
  love.filesystem.write(PENDING, name)

  -- Prepend-mount the payload at "/" (appendToPath = false) so its files win
  -- over the fused source for every subsequent require / love.filesystem read.
  if not love.filesystem.mount(rel, "/", false) then
    love.filesystem.remove(PENDING)
    return false
  end

  local snapshot = snapshotCallbacks()
  purgeBundledModules()
  _G.POKEPORT_PAYLOAD_MOUNTED = true

  -- Chainload: run the payload's main.lua (redefines the love callbacks from
  -- the NEW code), then call its love.load.  The new love.load calls Boot.run
  -- again, which no-ops via the flag set above.
  local ok, err = pcall(function()
    local chunk = assert(love.filesystem.load("main.lua"))
    chunk()
    love.load(args)
  end)

  if not ok then
    -- Handoff failed after mounting.  Unwind everything so the bundled game
    -- boots cleanly: clear the flag, unmount the payload, purge any payload
    -- modules it cached (so bundled requires reload from source), restore the
    -- bundled love callbacks with their intact upvalues, and drop the marker.
    -- Delete the payload too: it failed deterministically once, so leaving it
    -- would re-select and re-fail it on every boot forever.
    print("update: payload handoff failed, reverting to bundled: " .. tostring(err))
    _G.POKEPORT_PAYLOAD_MOUNTED = nil
    pcall(love.filesystem.unmount, rel)
    purgeBundledModules()
    restoreCallbacks(snapshot)
    love.filesystem.remove(rel)
    love.filesystem.remove(PENDING)
    return false
  end

  -- Success: the payload owns the game now.  Drop the marker and tell the
  -- caller to stop so the bundled love.load does not run on top of it.
  love.filesystem.remove(PENDING)
  return true
end

-- Everything after the fused / flag guards, wrapped so an unexpected error in
-- enumeration or selection can never crash the boot.
local function runInner(args)
  -- Crash guard first: a pending.txt naming a payload means a previous boot
  -- crashed mid-handoff.  Distrust that payload -- delete it and the marker --
  -- then continue (we may still pick an older valid payload, or fall through
  -- to the bundled game).
  local pending = love.filesystem.read(PENDING)
  if pending then
    pending = pending:gsub("%s+$", "")
    if pending ~= "" then
      love.filesystem.remove(PAYLOAD_DIR .. "/" .. pending)
    end
    love.filesystem.remove(PENDING)
  end

  -- Enumerate and probe every payload in the payload folder.
  --
  -- The checksum manifest is read ONCE for the whole sweep, not per candidate:
  -- one release's manifest covers every payload the player placed, and reading
  -- it per file would make the cost scale with the folder.
  local sumsText = love.filesystem.read(Payload.sumsRel())
  local candidates = {}
  if love.filesystem.getInfo(PAYLOAD_DIR, "directory") then
    for _, entry in ipairs(love.filesystem.getDirectoryItems(PAYLOAD_DIR)) do
      if isPayloadName(entry) then
        local info = Boot.probePayload(PAYLOAD_DIR .. "/" .. entry)
        if info then
          -- VERIFY BEFORE TRUSTING, and say which of the four it was.  A
          -- refused payload is dropped from the candidate list rather than
          -- deleted: the player put it there by hand and a second copy attempt
          -- is the fix, so destroying it would take the diagnosis away with it.
          local verdict, expected, actual = Boot.sideloadCheck(entry, sumsText)
          print("update: " .. Sideload.sentence(entry, verdict, expected, actual))
          if Sideload.mayMount(verdict) then
            candidates[#candidates + 1] = {
              name = entry,
              engine = info.engine,
              minShell = info.minShell,
              verdict = verdict,
            }
          end
        end
      end
    end
  end

  local Version = require("src.core.Version")
  local chosen, toDelete = Boot.select(candidates, Version.engine, Version.shell)

  for _, victim in ipairs(toDelete) do
    love.filesystem.remove(PAYLOAD_DIR .. "/" .. victim)
  end

  if not chosen then
    -- A PAYLOAD THAT IS PRESENT AND NOT CHOSEN USED TO BE SILENT, and the two
    -- reasons it can happen look identical from the outside and completely
    -- different from the inside: an older payload (nothing to do) and a
    -- payload whose minShell exceeds this shell (the player needs a new native
    -- build, and no amount of re-downloading will help).  "Auto-update does
    -- nothing" is what both reported.  Now each candidate says which it was.
    for _, c in ipairs(candidates) do
      local why
      if (c.minShell or 1) > Version.shell then
        why = ("needs shell %d, this build provides %d -- install a full "
          .. "release, a payload cannot upgrade the native shell")
          :format(c.minShell or 1, Version.shell)
      elseif Semver.compare(c.engine, Version.engine) <= 0 then
        why = ("is %s, not newer than the bundled %s"):format(
          tostring(c.engine), tostring(Version.engine))
      else
        why = "was not selected"
      end
      print(("update: payload %s %s"):format(c.name, why))
    end
    return false
  end
  -- THIS PRINTED THE BUNDLED VERSION, NOT THE PAYLOAD'S.  It read
  -- `(engine %s)` with Version.engine, which is the version being REPLACED --
  -- so the one line that was supposed to say what the player is about to run
  -- reported the thing they were trying to move off, and a payload that
  -- advertised the wrong version was indistinguishable in the log from one
  -- that advertised the right one.  Both versions and the integrity verdict,
  -- in the one line.
  local info
  for _, c in ipairs(candidates) do
    if c.name == chosen then info = c end
  end
  print(("update: chainloading %s (engine %s over bundled %s, %s)"):format(
    chosen, tostring(info and info.engine), tostring(Version.engine),
    tostring(info and info.verdict)))
  return chainload(chosen, args)
end

-- Boot.run(args) -> boolean
--
-- The first line of love.load.  True means a payload was mounted and
-- chainloaded and the caller must return immediately; false means boot the
-- bundled game as normal.
function Boot.run(args)
  -- Dev / source checkouts never self-update.
  if not (love.filesystem.isFused and love.filesystem.isFused()) then
    -- Silent on a plain working tree, which is the normal case and must not
    -- spam the console.  Loud when a payload is actually sitting there being
    -- ignored: that is the shape of "I copied the .love across and nothing
    -- happened", and on the console ports (where a hand-placed payload in the
    -- save directory is the whole update story) it is the first thing to check.
    local ok, items = pcall(love.filesystem.getDirectoryItems, PAYLOAD_DIR)
    if ok and type(items) == "table" then
      local n = 0
      for _, entry in ipairs(items) do
        if isPayloadName(entry) then n = n + 1 end
      end
      if n > 0 then
        print(("update: %d payload(s) in %s/ ignored -- this build is not "
          .. "fused, so it IS the game and runs itself"):format(n, PAYLOAD_DIR))
      end
    end
    return false
  end
  -- The chainloaded love.load calls Boot.run again; the flag makes it a no-op.
  if _G.POKEPORT_PAYLOAD_MOUNTED then return false end

  local ok, result = pcall(runInner, args)
  if not ok then
    -- An error escaped before any handoff mount (chainload cleans up after
    -- itself), so state is still clean.  Never crash the boot.
    return false
  end
  return result
end

return Boot
