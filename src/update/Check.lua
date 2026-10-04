-- Async release-check and payload-download for the self-update flow.
--
-- The heavy lifting (curl calls, sha256 verification, the Boot gate) happens
-- on a background love.thread worker (src/update/check_worker.lua); this module
-- is only the thin main-thread state machine the UI polls.  Two channels carry
-- the conversation:
--   "update_check_cmd"   main -> worker: { cmd = "check" | "download" | "quit" }
--   "update_check_state" worker -> main: { status, latest, progress, error }
--
-- Nothing here ever blocks or throws into the game loop: when love.thread is
-- absent (the headless test stub) or the worker cannot run (no curl, Android),
-- state() simply reports "error" and the UI hides itself.  See the shared
-- contract in the task brief for the status vocabulary and the file layout.
--
-- The release-JSON extraction and the sums parsing are exported as pure
-- functions (no love.* calls) so plain-Lua tests can cover them, and so the
-- worker can reuse the exact same code path via love.filesystem.load.

-- src/update/Payload.lua owns the folder, the asset name and the pattern that
-- recognises one.  Zero requires and no love.* calls, so it resolves on the
-- main thread, inside the worker thread, and under plain Lua in a test.
local Payload = require("src.update.Payload")

local Check = {}

-- MUST match `git remote get-url origin`.  This read UNDERdecodedHD/... for
-- a while, which is not a repository that exists: GitHub answered 404, curl
-- exited non-zero with an empty body, and the check reported "release check
-- failed" on every platform.  An updater that points at the wrong repo fails
-- exactly like an updater with no network, so verify this against the remote
-- rather than against how the account name is written down anywhere else.
Check.REPO = "UNDERdecoded/Gen2Recomped"

local CMD = "update_check_cmd"
local STATE = "update_check_state"

-- ---------------------------------------------------------------------------
-- pure helpers (no love.*) -- also used inside the worker
-- ---------------------------------------------------------------------------

-- Find the release asset named exactly `name`, returning its download URL and
-- byte size (or nil when the release has no such asset).
function Check.pickAsset(assets, name)
  if type(assets) ~= "table" then return nil end
  for _, a in ipairs(assets) do
    if type(a) == "table" and a.name == name then
      return { url = a.browser_download_url, size = tonumber(a.size) }
    end
  end
  return nil
end

local function stripV(tag)
  return (tostring(tag):gsub("^[vV]", ""))
end

-- Decode a GitHub "releases/latest" response into just the fields the updater
-- needs.  Returns { version, payloadName, payload, sums } where payload/sums are
-- { url, size } tables (or nil when that asset is missing), or nil, err when the
-- document is not a release with a strict X.Y.Z tag.  Json is injected so the
-- worker can pass a filesystem-loaded codec; on the main thread / in tests it
-- falls back to require.
function Check.parseRelease(jsonText, Json)
  Json = Json or require("src.link.Json")
  local doc = Json.decode(jsonText)
  if type(doc) ~= "table" or not doc.tag_name then
    return nil, "no tag_name in release json"
  end
  local version = stripV(doc.tag_name)
  if not version:match("^%d+%.%d+%.%d+$") then
    return nil, "release tag is not X.Y.Z: " .. tostring(doc.tag_name)
  end
  local payloadName = Payload.name(version)
  return {
    version = version,
    payloadName = payloadName,
    payload = Check.pickAsset(doc.assets, payloadName),
    sums = Check.pickAsset(doc.assets, Payload.SUMS),
  }
end

-- Parse a shasum -a 256 file ("<hex>  <filename>", bare filenames).  With a
-- `target` argument returns just that file's hash (or nil); otherwise returns
-- the whole name -> hash map.  Tolerates the "*" binary marker and "./" prefix.
-- ONE PARSER, in src/update/Payload.lua.  The body used to live here, and the
-- sideload verifier in src/update/Boot.lua runs before this module is loaded,
-- so a copy would have been the ninth instance of the recurring bug.  This
-- stays the public name: the worker and tools/auto_update_check.lua both drive
-- Check.parseSums, and both still exercise the one implementation.
function Check.parseSums(text, target)
  return Payload.parseSums(text, target)
end

-- ---------------------------------------------------------------------------
-- main-thread state machine
-- ---------------------------------------------------------------------------

function Check.releaseUrl()
  return "https://github.com/" .. Check.REPO .. "/releases/latest"
end

-- ---------------------------------------------------------------------------
-- CAN THIS BUILD REPLACE ITS OWN PAYLOAD?  Derived, not listed.
-- ---------------------------------------------------------------------------
--
-- WHAT WAS HERE, AND WHY IT WAS WRONG.  An OS table --
--
--     local NOTIFY_ONLY_OS = { Horizon = true, NX = true, Switch = true }
--     function Check.canSelfUpdate()
--       if _G.POKEPORT_NOTIFY_ONLY_UPDATES then return false end
--       return not NOTIFY_ONLY_OS[(love and love._os) or ""]
--     end
--
-- with a comment arguing that the Switch payload is fused into the NRO and an
-- Xbox UWP package is a signed, read-only app container, so "neither can pick
-- up a downloaded archive".  Three things were measured about that table:
--
--   1. POKEPORT_NOTIFY_ONLY_UPDATES, which the comment said "the console
--      packagers set from their own bootstrap", occurs exactly ONCE in the
--      whole repository -- the read above.  ports/uwp, scripts/xbox-uwp,
--      scripts/build_msix.ps1 and ports/uwp/app/main.cpp set nothing.  So the
--      branch that was supposed to stop Xbox never ran, and on Xbox this
--      function returned TRUE: love._os is "Windows" in a UWP container.
--   2. The read-only-container argument answers a question Boot.run does not
--      ask.  Boot.run never writes inside the package and never replaces the
--      executable: it mounts a .love out of the SAVE DIRECTORY over "/" and
--      chainloads it (src/update/Boot.lua).  The save directory is writable on
--      both consoles -- saves, options and the entire ROM cache already live
--      there.  A payload PUT there by hand runs on the Switch and on Xbox
--      today, which is the opposite of what the comment claimed.
--   3. "Those builds CHECK and REPORT" was not happening either.  With no
--      transport the worker posts status "error", and the launcher banner
--      renders only available / downloading / ready / needs_full -- so NX and
--      UWP showed the player nothing at all, not even a notice.
--
-- THE RULE NOW.  Two orthogonal capabilities, each measured by the thing that
-- owns it, and self-update is their conjunction:
--
--   Platform.canHostPayload()  write a byte into the save directory and read
--                              it back; mount/unmount must exist.
--   HostShell.transport()      curl we actually ran --version on, or the
--                              Android JNI download bridge, or nil + a reason.
--
-- The notify-only FALLBACK is kept for the case that is now named precisely:
-- a shell that can host a payload and cannot fetch one (NX, UWP).  There the
-- player is told, and a payload dropped into the save directory by hand still
-- boots.  POKEPORT_NOTIFY_ONLY_UPDATES survives as an override and is now also
-- readable from the environment, so a packager can actually set it.
local capability

local function announce(cap)
  print(("update: capability host=%s fused=%s host-payload=%s transport=%s"
    .. " -> %s%s"):format(
    cap.host, tostring(cap.fused), tostring(cap.canHostPayload),
    cap.transport or "none", cap.mode,
    cap.reason and (" (" .. cap.reason .. ")") or ""))
end

-- { host, fused, canHostPayload, transport, mode, reason }
-- mode is "self-update" | "notify-only" | "unavailable" | "suppressed".
function Check.capability()
  if capability then return capability end
  local Platform = require("src.core.Platform")
  local HostShell = require("src.core.HostShell")
  -- Only a POSITIVE love.system answer is trusted; a headless run says
  -- "Unknown" and that is what gets logged.
  local host = (love and love.system and love.system.getOS
    and love.system.getOS()) or (love and love._os) or "Unknown"
  local fused = (love and love.filesystem and love.filesystem.isFused
    and love.filesystem.isFused()) and true or false
  local canHost = Platform.canHostPayload()
  local transport, why = HostShell.transport()
  local cap = {
    host = host,
    fused = fused,
    canHostPayload = canHost,
    transport = transport,
  }
  local suppressed = _G.POKEPORT_NOTIFY_ONLY_UPDATES
    or os.getenv("POKEPORT_NOTIFY_ONLY_UPDATES") == "1"
  if suppressed then
    cap.mode, cap.reason = "suppressed", "POKEPORT_NOTIFY_ONLY_UPDATES is set"
  elseif not canHost then
    cap.mode, cap.reason = "unavailable",
      "the save directory did not take a test write, so no payload could be mounted"
  elseif not transport then
    cap.mode, cap.reason = "notify-only", why
  elseif not fused then
    -- A source checkout IS the game; Boot.run no-ops there, so downloading a
    -- payload would be downloading something that can never run.
    cap.mode, cap.reason = "notify-only", "not a fused build"
  else
    cap.mode = "self-update"
  end
  -- WHAT THE PLAYER SHOULD ACTUALLY DO, as an enum rather than a sentence, so
  -- the launcher owns the wording and this file owns the decision.  The banner
  -- used to say "A new version needs a fresh download" with an "Open releases"
  -- button for every refusal, which is wrong on both consoles: a Switch player
  -- updates from ports/switch/ota-launcher, an Xbox player installs a newer
  -- package, and neither has a browser for the button to open.
  --
  --   "download"  self-update works here
  --   "ota"       NX -- the native OTA launcher NRO is the update path
  --   "package"   a packaged container (UWP/MSIX) -- install a newer package
  --   "releases"  no transport, but a desktop that can open a page
  if cap.mode == "self-update" then
    cap.advice = "download"
  elseif host == "NX" then
    cap.advice = "ota"
  elseif Platform.isPackagedContainer() then
    cap.advice = "package"
  else
    cap.advice = "releases"
  end
  capability = cap
  -- A silent three-way branch where the wrong leg does nothing is the whole
  -- shape of this bug, so every build says which leg it took, once.
  pcall(announce, cap)
  return cap
end

function Check.canSelfUpdate()
  return Check.capability().mode == "self-update"
end

-- One of "download" | "ota" | "package" | "releases" -- see Check.capability.
-- The launcher turns this into a sentence and decides whether to draw a button;
-- tools/auto_update_check.lua asserts the launcher handles every value this can
-- return, so a fifth one cannot be added here and ignored there.
Check.ADVICE = { download = true, ota = true, package = true, releases = true }

function Check.advice()
  return Check.capability().advice or "releases"
end

-- True where we can tell the player about a release but not fetch it: the
-- banner is still worth drawing, and a hand-placed payload still boots.
function Check.notifyOnly()
  local mode = Check.capability().mode
  return mode == "notify-only" or mode == "suppressed"
end

-- Tests drive the rule with stub love tables between cases.
function Check._resetCapabilityForTests()
  capability = nil
end

local worker           -- the love.thread, once started
local cmdCh, stateCh   -- the two channels
local workerReady      -- nil = untried, true = running, false = unavailable
local requested        -- a check has been asked for this session
local cache = { status = "idle" } -- newest snapshot from the worker

local function ensureWorker()
  if workerReady ~= nil then return workerReady end
  if not (love and love.thread and love.thread.newThread) then
    workerReady = false
    return false
  end
  local ok, th = pcall(love.thread.newThread, "src/update/check_worker.lua")
  if not ok or not th then
    workerReady = false
    return false
  end
  cmdCh = love.thread.getChannel(CMD)
  stateCh = love.thread.getChannel(STATE)
  if not pcall(function() th:start() end) then
    workerReady = false
    return false
  end
  worker = th
  workerReady = true
  return true
end

-- ---------------------------------------------------------------------------
-- Main-thread transport service (Android)
-- ---------------------------------------------------------------------------
--
-- love.system.httpDownload is a JNI bridge into GameActivity, not part of
-- LOVE.  The worker used to call it directly and the app died the instant the
-- launcher came up, with no Lua error -- a native abort, which is beneath
-- anything pcall or love.threaderror can catch.  See the long note at the top
-- of check_worker.lua's transport section for the three separate things that
-- call got wrong.
--
-- The bridge now only ever runs HERE, on the main thread, through the exact
-- HostShell path the mod index has used on Android since #597.  The worker
-- pushes a request and blocks on the reply channel; we answer from drain(),
-- which the launcher already calls every frame through Check.state().
--
-- Desktop never sees any of this: the worker resolves curl first and never
-- pushes a request, so this finds an empty channel and returns.
local BRIDGE_REQ = "update_bridge_req"
local BRIDGE_RES = "update_bridge_res"

-- A PAYLOAD IS NOT A JSON DOCUMENT.  The release check is a few kilobytes and
-- the bridge returns before the next frame would have drawn; the payload for
-- v0.8.3 is 20,368,165 bytes (measured off the release asset), and the bridge
-- blocks the thread it is called on for the whole transfer.  That thread is
-- the one LOVE drives the frame loop on -- on Android it is SDL's game thread,
-- not Android's UI thread, so this stalls the picture rather than tripping an
-- ANR, but the picture it stalls is whatever was last drawn.
--
-- So a request marked `big` is answered one drain LATE.  The first drain that
-- sees it posts the downloading state and returns, the launcher draws the
-- banner from it, and the NEXT drain runs the transfer -- the player is
-- looking at "Downloading update" while it happens rather than at the
-- untouched launcher.  The worker is blocked on the reply channel either way.
local deferredBig
local function serviceBridgeRequests()
  local reqCh = love.thread.getChannel(BRIDGE_REQ)
  local resCh = love.thread.getChannel(BRIDGE_RES)
  local req = deferredBig or reqCh:pop()
  deferredBig = nil
  while req do
    if type(req) == "table" and req.big and not req.deferred then
      req.deferred = true
      deferredBig = req
      cache = { status = "downloading", latest = req.version, progress = 0 }
      print(("update: fetching %s through the host bridge (%s bytes); the "
        .. "launcher will not redraw until it finishes"):format(
        tostring(req.dest), tostring(req.size or "?")))
      return
    end
    local ok = false
    if type(req) == "table" and type(req.url) == "string"
        and type(req.dest) == "string" and req.dest ~= "" then
      ok = pcall(function()
        local HostShell = require("src.core.HostShell")
        local saveDir = love.filesystem.getSaveDirectory()
        if not saveDir or saveDir == "" then error("no save directory", 0) end
        -- Absolute path and a real User-Agent: the two things the worker's own
        -- call was missing.  HostShell decides curl vs bridge internally.
        local got, why = HostShell.httpDownload(req.url,
          saveDir .. "/" .. req.dest, "Gen2Recomped-updater", req.accept)
        -- The transport used to answer true on the curl path whatever curl
        -- did, so a failed fetch went on to be discovered as a missing file
        -- somewhere later.  It reports now, and the reason travels as far as
        -- this thread can carry it (the result channel is a bare ok/fail).
        if not got then
          error("download failed: " .. tostring(why or "no reason given"), 0)
        end
      end)
    end
    if type(req) == "table" and req.big then
      print("update: bridge payload fetch " .. (ok and "succeeded" or "FAILED"))
    end
    resCh:push({ seq = (type(req) == "table") and req.seq or nil, ok = ok })
    req = reqCh:pop()
  end
end

-- Pull every pending snapshot off the state channel (keeping the newest) and
-- surface a worker crash as a soft error the UI can hide on.
local function drain()
  -- Service first: a worker blocked waiting on us has not posted its result
  -- yet, so answering before we read state makes it visible this frame rather
  -- than the next one.
  if worker then pcall(serviceBridgeRequests) end
  if stateCh then
    local msg = stateCh:pop()
    while msg do
      cache = msg
      msg = stateCh:pop()
    end
  end
  if worker then
    local err = worker:getError()
    if err then
      cache = { status = "error", error = tostring(err) }
    end
  end
end

-- Begin (or, on a prior error, retry) an async check.  Safe to call every frame:
-- once a check is in flight or has reached a terminal state it is a no-op.
function Check.start()
  -- ASK THE CAPABILITY FIRST, so every fused launcher run puts one line in the
  -- log saying what this build can do about updates.  It used to be asked only
  -- by Check.download, which on a host that never draws an Update button is
  -- never called -- so the Switch and Xbox produced no diagnostic at all.
  local cap = Check.capability()
  if not cap.transport then
    -- No HTTPS client reachable from Lua (the Switch, an Xbox UWP container, a
    -- desktop with no curl).  Spinning up the worker only to have it time out
    -- against a network it cannot reach wastes a thread and ten seconds, and
    -- its "error" state draws nothing, so say it here instead and stop.
    --
    -- On the Switch this is not the end of the story: ports/switch/ota-launcher
    -- is a native NRO that does check GitHub and does replace both NROs, and it
    -- is the hbmenu entry.  A payload copied into the save directory by hand
    -- also still boots -- see src/update/Boot.lua and docs/auto-update.md.
    drain()
    -- "notify", not "error".  The launcher banner draws nothing for "error", so
    -- this leg produced no UI at all on NX and UWP -- which is why those two
    -- platforms appeared to have no updater rather than a disabled one.  The
    -- banner has a notify row now, and Check.advice() says what it should read.
    cache = { status = "notify", error = cap.reason or "no network transport" }
    return
  end
  drain()
  if cache.status == "checking" or cache.status == "downloading" then return end
  if requested and cache.status ~= "error" and cache.status ~= "idle" then return end
  if not ensureWorker() then
    cache = { status = "error", error = "background threads unavailable" }
    return
  end
  requested = true
  cache = { status = "checking" }
  cmdCh:push({ cmd = "check" })
end

-- Current snapshot: { status, latest, progress, error, advice }.
--
-- STATUS is one of the nine below, and the four marked (draw) are the ones the
-- launcher banner renders.  "notify" is new: before it, a host that cannot
-- check at all ended on "error", which the banner hides, so the Switch and
-- Xbox showed the player nothing whatsoever.
Check.STATUS = {
  idle = false, checking = false, uptodate = false, error = false,
  available = true,   -- (draw) a payload we can fetch
  downloading = true, -- (draw)
  ready = true,       -- (draw) verified, applies on the next launch
  needs_full = true,  -- (draw) a newer release this build cannot apply in place
  notify = true,      -- (draw) this host cannot check; say what the path is
}
function Check.state()
  drain()
  return {
    status = cache.status or "idle",
    latest = cache.latest,
    progress = cache.progress,
    error = cache.error,
    -- Travels with every snapshot so the banner never has to ask the capability
    -- itself -- one question, one answer, and the launcher cannot drift from
    -- the gate the way it did when it rendered one sentence for every refusal.
    advice = Check.advice(),
  }
end

-- Start downloading the payload announced by an "available" check.  A no-op in
-- any other state (the worker still holds the release info from the check).
function Check.download()
  drain()
  -- Notify-only platforms never start a transfer; the check result stands as
  -- the whole feature there (see Check.capability).  It used to return
  -- silently, which is indistinguishable from a button that is not wired up --
  -- and it used to sit BEHIND the `cmdCh` guard, so on a host with no worker
  -- the refusal never even ran.  The state it leaves must be one the launcher
  -- banner draws, or the player is told nothing; "needs_full" is that state
  -- (tools/auto_update_check.lua checks it against the banner's vocabulary).
  if not Check.canSelfUpdate() then
    local cap = Check.capability()
    print(("update: download refused -- %s (%s)"):format(
      cap.mode, cap.reason or "no reason recorded"))
    cache = { status = "needs_full", latest = cache.latest }
    return
  end
  if not cmdCh then return end
  if cache.status ~= "available" then return end
  cache = { status = "downloading", latest = cache.latest, progress = 0 }
  cmdCh:push({ cmd = "download" })
end

-- End the worker thread.  Its command loop sits in Channel:demand(), which
-- never returns on its own, and LOVE waits for every live love.thread before
-- the process exits (#339).
function Check.shutdown()
  if cmdCh then cmdCh:push({ cmd = "quit" }) end
  -- A worker parked on the bridge reply channel is not watching cmdCh, so
  -- worker:wait() below would hold the process open for that whole demand()
  -- timeout -- the exact shape of #339.  Answer it first (as a failure, so the
  -- fetch gives up) and it comes straight back round to the quit command.
  if worker then
    pcall(function()
      love.thread.getChannel(BRIDGE_RES):push({ ok = false, shutdown = true })
    end)
  end
  if worker then pcall(function() worker:wait() end) end
  worker, cmdCh, stateCh = nil, nil, nil
  workerReady = false
end

return Check
