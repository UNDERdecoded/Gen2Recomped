-- Background worker for the self-update flow (driven by src/update/Check.lua).
--
-- Runs on a love.thread so no curl call, sha256 pass or archive probe ever
-- touches the render thread.  Talks over two channels:
--   "update_check_cmd"   in:  { cmd = "check" | "download" | "quit" }
--   "update_check_state" out: { status, latest, progress, error }
--
-- Transport is whichever one HostShell.transport() resolves: curl shelled out
-- through HostShell.popen (macOS, Windows 10+, desktop Linux), or the Android
-- JNI download bridge serviced by the main thread.  Everything is wrapped so a
-- missing curl, an HTTP error, or a hung download degrades to an
-- "error"/"needs_full" state rather than blocking or crashing the game.  A
-- host with neither (the Switch, an Xbox UWP container) is the notify-only
-- leg: it reports what the newest release is and cannot fetch it, and says so
-- in the log rather than falling silent.
--
-- Fresh love threads do not carry the "src.*" package searcher, so sibling
-- modules are pulled in with love.filesystem.load exactly like
-- src/core/chip_worker.lua does.  Semver and Boot are authored in parallel; we
-- load them defensively and degrade (a local semver fallback, a permissive
-- gate) if they are not present yet.

require("love.thread")
require("love.filesystem")
require("love.data")
require("love.timer")
require("love.system")

local function loadModule(path)
  local ok, chunk = pcall(love.filesystem.load, path)
  if not ok or type(chunk) ~= "function" then return nil end
  local ok2, mod = pcall(chunk)
  if not ok2 then return nil end
  return mod
end

local Json    = loadModule("src/link/Json.lua")
local Version = loadModule("src/core/Version.lua")
local Semver  = loadModule("src/update/Semver.lua")
local Payload = loadModule("src/update/Payload.lua")
local HostShell = loadModule("src/core/HostShell.lua")
-- Boot's and Check's top-level requires cannot resolve in this thread (no
-- src.* searcher), which would leave them nil -- and a nil Boot leaves the
-- minShell gate permanently permissive.  Seed the loaded table first.
if Semver then package.loaded["src.update.Semver"] = Semver end
if Payload then package.loaded["src.update.Payload"] = Payload end
local Check   = loadModule("src/update/Check.lua")
local Boot    = loadModule("src/update/Boot.lua")

local cmdCh   = love.thread.getChannel("update_check_cmd")
local stateCh = love.thread.getChannel("update_check_state")

-- EVERY TERMINAL STATE SAYS SO IN THE LOG.
--
-- The launcher banner renders four of the eight states (available,
-- downloading, ready, needs_full) and draws nothing for the other four, so
-- "uptodate", "error" and "idle" are invisible by design -- which means a
-- platform that gave up looked exactly like a platform with no updater.  This
-- is the same treatment the audio stack gets ("chip audio: music path = ...").
local announced = {}
local function post(t)
  local status = type(t) == "table" and t.status or "?"
  if status ~= "checking" and status ~= "downloading" and not announced[status] then
    announced[status] = true
    print(("update: %s%s%s"):format(status,
      (type(t) == "table" and t.latest) and (" latest=" .. tostring(t.latest)) or "",
      (type(t) == "table" and t.error) and (" -- " .. tostring(t.error)) or ""))
  end
  stateCh:push(t)
end

local osName    = (love.system and love.system.getOS and love.system.getOS()) or ""
local isWindows = osName == "Windows"
local saveDir   = love.filesystem.getSaveDirectory()

-- DERIVED FROM Check.REPO, which is the one place the repository is named.
-- This line used to spell the slug out a second time, so moving the repo in
-- Check.lua moved the releases page the player is sent to and left the API the
-- check actually calls pointing at the old one -- a check that reports "release
-- check failed" on every platform while the button beside it opens the right
-- page.  The fallback is only for a thread where Check would not load at all.
local REPO = (Check and Check.REPO) or nil
local API_URL = REPO
  and ("https://api.github.com/repos/" .. REPO .. "/releases/latest")
  or nil

-- the release picked by the last "check"; kept between commands so "download"
-- knows the payload url/size/name without re-fetching
local pending = nil

-- ---------------------------------------------------------------------------
-- transport
-- ---------------------------------------------------------------------------
--
-- There are two, and the difference between them is why this file used to kill
-- the app on Android:
--
--   curl        desktop only -- macOS, Windows 10+, desktop Linux.  Shelled
--               out from this thread, which is exactly what this thread is
--               for.  Harmless anywhere it exists.
--   the bridge  love.system.httpDownload.  NOT part of LOVE: it is a JNI call
--               into GameActivity.httpDownload that our vendored liblove
--               exports (#597), and it is Android's only transport.
--
-- This worker used to call the bridge itself, as
-- `love.system.httpDownload(url, "update_fetch_1786.tmp")`.  Three things
-- were wrong with that, and all three are Android-only:
--
--   1. a SAVE-DIRECTORY-RELATIVE path where the bridge documents an ABSOLUTE
--      host path (see HostShell.httpDownload);
--   2. userAgent and accept left nil, where every other caller in the tree
--      passes a defaulted User-Agent -- a JNI wrapper that hands a null
--      straight to NewStringUTF aborts the process rather than raising;
--   3. from a love.thread, which no other bridge call in the tree does.
--
-- The app closed the instant the launcher came up, with no Lua error and no
-- error screen.  That is the signature of a native abort: it is below Lua, so
-- neither the pcall around Check.start nor love.threaderror can see it.
--
-- So this worker no longer touches JNI at all.  It asks the MAIN thread to run
-- the bridge and waits for the answer; Check.lua services those requests in
-- drain() through HostShell.httpDownload -- the same absolute-path,
-- defaulted-agent call the mod index has been making on Android since #597.
-- Desktop never sends one: curl resolves first, and this thread behaves
-- exactly as it always did.

local function shq(s)
  s = tostring(s)
  if isWindows then
    return '"' .. s:gsub('"', '') .. '"'
  end
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

local BRIDGE_REQ = "update_bridge_req"
local BRIDGE_RES = "update_bridge_res"
local bridgeReqCh = love.thread.getChannel(BRIDGE_REQ)
local bridgeResCh = love.thread.getChannel(BRIDGE_RES)

-- WHICH TRANSPORT.  Asked of HostShell, not answered again here.
--
-- This file used to carry its own byte-for-byte copy of haveCurl and its own
-- Android bridge test, so "can this build fetch?" had three answers in the
-- tree -- here, in HostShell.canFetch, and in Platform.canFetchRemote -- and
-- the self-updater was gated on a different one from the mod index.  The curl
-- probe is also a process spawn, and HostShell.popen now refuses outright on a
-- host that cannot spawn (the Switch and a UWP container, where io.popen does
-- not return nil but RAISES), so the console ports no longer pay for a
-- throw-and-catch to learn what the OS name already said.
--
-- "curl" | "bridge" | false, resolved once.  curl wins where both exist so
-- desktop behaviour is bit-for-bit what it was.
local transportAnnounced
local function resolveTransport()
  if not (HostShell and HostShell.transport) then return false end
  local kind, why = HostShell.transport()
  if not transportAnnounced then
    transportAnnounced = true
    print(("update: transport = %s%s"):format(kind or "none",
      (not kind) and (" (" .. tostring(why) .. ")") or ""))
  end
  return kind or false
end

local function canFetch()
  return resolveTransport() ~= false
end

-- Hand one fetch to the main thread and block until it answers.  destRel is
-- save-directory relative; the servicer makes it absolute.
--
-- The wait is bounded because the main thread only services these while the
-- launcher is polling Check.state() -- once the player boots a game nobody is
-- listening, and an unbounded demand() here would hold the process open at
-- quit (#339).  A timeout degrades to "no update offered", which is the
-- failure mode this whole file is designed around.
local bridgeSeq = 0
local function bridgeFetch(url, destRel, accept, timeout, big)
  bridgeSeq = bridgeSeq + 1
  local seq = bridgeSeq
  bridgeResCh:clear() -- strictly synchronous: never more than one in flight
  bridgeReqCh:push({
    seq = seq, url = url, dest = destRel, accept = accept,
    -- `big` makes the main thread post the downloading state and let one frame
    -- draw before it blocks on the transfer (see serviceBridgeRequests); the
    -- version and size ride along only so that log line can name them.
    big = big and true or nil,
    version = big and big.version or nil,
    size = big and big.size or nil,
  })
  local res = bridgeResCh:demand(timeout or 45)
  return type(res) == "table" and res.seq == seq and res.ok == true
end

-- Give me this small text resource, or nil.  Every call site treats it that
-- way; the name is kept so the diff stays readable.
local function curlCapture(url)
  local how = resolveTransport()
  if how == "bridge" then
    local dest = ("update_fetch_%d.tmp"):format(bridgeSeq + 1)
    love.filesystem.remove(dest)
    local ok = bridgeFetch(url, dest, "application/vnd.github+json")
    local body = ok and love.filesystem.read(dest) or nil
    love.filesystem.remove(dest)
    if type(body) ~= "string" or body == "" then return nil end
    return body
  end
  if how ~= "curl" then return nil end
  local cmd = "curl -fsSL --connect-timeout 10 --max-time 40 "
    .. "-H " .. shq("User-Agent: Gen2Recomped-updater") .. " "
    .. "-H " .. shq("Accept: application/vnd.github+json") .. " "
    .. shq(url)
  local pipe = HostShell.popen(cmd)
  if not pipe then return nil end
  local readOk, out = pcall(function() return pipe:read("*a") end)
  pcall(function() pipe:close() end)
  if not readOk or not out or out == "" then return nil end
  return out
end

-- ---------------------------------------------------------------------------
-- version compare (Semver per contract item 5, with a local fallback)
-- ---------------------------------------------------------------------------

local function parseTriple(s)
  s = (tostring(s):gsub("^[vV]", ""))
  local a, b, c = s:match("^(%d+)%.(%d+)%.(%d+)")
  if not a then return nil end
  return { tonumber(a), tonumber(b), tonumber(c) }
end

-- -1 | 0 | 1 for a<b | a==b | a>b
local function compareVersions(a, b)
  if Semver and Semver.compare then
    local ok, r = pcall(Semver.compare, a, b)
    if ok and r ~= nil then return r end
  end
  local pa, pb = parseTriple(a), parseTriple(b)
  if not pa or not pb then return 0 end
  for i = 1, 3 do
    if pa[i] ~= pb[i] then return pa[i] < pb[i] and -1 or 1 end
  end
  return 0
end

-- ---------------------------------------------------------------------------
-- verification and the shell gate
-- ---------------------------------------------------------------------------

local function sha256hex(data)
  local digest = love.data.hash("sha256", data)
  if type(digest) == "userdata" and digest.getString then
    digest = digest:getString()
  end
  return love.data.encode("string", "hex", digest)
end

-- Confirm the save-dir file `rel` hashes to the sum listed for `payloadName`.
local function verifyPayload(rel, payloadName, sumsText)
  local want = Check.parseSums(sumsText, payloadName)
  if not want then return false, "no checksum for " .. payloadName end
  local data = love.filesystem.read(rel)
  if not data then return false, "cannot read downloaded payload" end
  if sha256hex(data):lower() ~= want:lower() then
    return false, "checksum mismatch"
  end
  return true
end

-- true = ok to run, false = payload needs a newer shell (needs_full).  When Boot
-- cannot probe (module missing during parallel dev, or a probe failure) we allow
-- it: Boot.run's crash-guard handles a payload that turns out unrunnable.
local function gatePasses(rel)
  if not (Boot and Boot.probePayload) then return true end
  local info = Boot.probePayload(rel)
  if not info then return true end
  local shell = (Version and Version.shell) or 1
  if info.minShell and info.minShell > shell then return false end
  return true
end

-- ---------------------------------------------------------------------------
-- check
-- ---------------------------------------------------------------------------

local function doCheck()
  post({ status = "checking" })

  if not canFetch() then
    post({ status = "error", error = "no network transport (curl or httpDownload)" })
    return
  end

  if not API_URL then
    post({ status = "error",
      error = "the updater does not know which repository to ask" })
    return
  end

  local body = curlCapture(API_URL)
  if not body then
    post({ status = "error", error = "release check failed" })
    return
  end

  local rel, perr = Check.parseRelease(body, Json)
  if not rel then
    post({ status = "error", error = perr or "bad release json" })
    return
  end
  pending = rel

  -- Unstamped dev build: the working tree always looks "newer", so never
  -- pester the developer with an update (contract item, Check design).
  local currentEngine = (Version and Version.engine) or "0.0.0-dev"
  if currentEngine == "0.0.0-dev" then
    post({ status = "uptodate", latest = rel.version })
    return
  end

  if compareVersions(rel.version, currentEngine) <= 0 then
    post({ status = "uptodate", latest = rel.version })
    return
  end

  -- A newer release, but without the .love payload or its sums we cannot do an
  -- in-place update: send the user to the full installers.
  if not (rel.payload and rel.payload.url and rel.sums and rel.sums.url) then
    post({ status = "needs_full", latest = rel.version })
    return
  end

  -- Already downloaded on a previous run?  Verify and gate it rather than
  -- pulling the bytes again.
  local finalRel = Payload.rel(rel.version)
  if love.filesystem.getInfo(finalRel) then
    local sums = curlCapture(rel.sums.url)
    if sums and verifyPayload(finalRel, rel.payloadName, sums) then
      if gatePasses(finalRel) == false then
        love.filesystem.remove(finalRel)
        post({ status = "needs_full", latest = rel.version })
        return
      end
      post({ status = "ready", latest = rel.version })
      return
    end
    -- stale / corrupt: drop it and offer a fresh download
    love.filesystem.remove(finalRel)
  end

  -- WHAT USED TO BE HERE, AND WHY ANDROID NEVER UPDATED.  A refusal:
  --
  --     if resolveTransport() == "bridge" then
  --       post({ status = "needs_full", latest = rel.version })
  --       return
  --     end
  --
  -- argued on the grounds that launchDownload is curl-only and that "pushing a
  -- ~6 MB transfer through the blocking main-thread bridge would freeze the
  -- launcher for its whole duration".  Android is the only bridge platform, so
  -- that branch WAS the Android update path: every Android release reported
  -- needs_full, the banner drew "Open releases", and the tap opened the GitHub
  -- releases page -- which is exactly the report ("makes them go to github to
  -- get the update").  It was never a failure; it was a policy refusal, which
  -- is why nothing in any log said anything was wrong.
  --
  -- Both premises were out of date.  launchDownload has a bridge branch now
  -- (doDownload below), and the freeze is real but bounded and is now
  -- announced: the main thread posts the downloading state and lets a frame
  -- draw before it blocks, so the player watches a "Downloading update" banner
  -- instead of a dead launcher.  The measured payload is 20,368,165 bytes
  -- (v0.8.3's Gen2Recomped-0.8.3.love), not 6 MB.
  post({ status = "available", latest = rel.version })
end

-- ---------------------------------------------------------------------------
-- download
-- ---------------------------------------------------------------------------

-- Launch curl in the background writing `partAbs`, touching `doneAbs` when it
-- exits.  Returns without waiting so the caller can poll the growing file for
-- progress.  We deliberately do not capture curl's exit code: an incomplete or
-- failed transfer simply fails the checksum below, which is the real gate.
local function launchDownload(url, partAbs, doneAbs)
  if isWindows then
    -- a tiny batch file sidesteps cmd.exe's nested-quote madness
    local batRel = Payload.scriptRel()
    love.filesystem.write(batRel,
      "@echo off\r\n"
      .. "curl -fsSL --connect-timeout 15 --max-time 900 -o \""
      .. partAbs .. "\" \"" .. url .. "\"\r\n"
      .. "type nul > \"" .. doneAbs .. "\"\r\n")
    os.execute('start "" /b ' .. shq(saveDir .. "/" .. batRel))
  else
    -- ( ... ) & backgrounds the whole group so os.execute returns at once
    os.execute("( " .. HostShell.envPrefix() .. "curl -fsSL --connect-timeout 15 --max-time 900 -o "
      .. shq(partAbs) .. " " .. shq(url)
      .. " ; touch " .. shq(doneAbs) .. " ) >/dev/null 2>&1 &")
  end
end

local function doDownload()
  if not (pending and pending.payload and pending.payload.url) then
    post({ status = "error", error = "nothing to download" })
    return
  end
  local how = resolveTransport()
  if how == false then
    -- No transport at all (NX, UWP, a desktop with no curl).  This is the
    -- notify-only leg and it says so rather than leaving a progress bar at 0%.
    local _, why = HostShell and HostShell.transport and HostShell.transport()
    print("update: download impossible -- " .. tostring(why or "no transport"))
    post({ status = "needs_full", latest = pending.version })
    return
  end
  local rel = pending
  post({ status = "downloading", latest = rel.version, progress = 0 })

  love.filesystem.createDirectory(Payload.DIR)
  -- ONE fact for all four spellings of this path.  The part/done/final names
  -- and the folder came from Payload so the file the transport writes and the
  -- file Boot.run later mounts cannot drift apart; they were seven separate
  -- string literals across three files before src/update/Payload.lua existed.
  local partRel  = Payload.partRel(rel.version)
  local doneRel  = Payload.doneRel(rel.version)
  local finalRel = Payload.rel(rel.version)
  love.filesystem.remove(partRel)
  love.filesystem.remove(doneRel)

  local partAbs = saveDir .. "/" .. partRel
  local doneAbs = saveDir .. "/" .. doneRel
  local size    = rel.payload.size or 0

  if how == "bridge" then
    -- THE ANDROID PATH.  One whole-file transfer through the JNI bridge, run
    -- on the MAIN thread because a JNI call from a love.thread is a native
    -- abort (the thread is not attached to the JVM, which is below anything
    -- pcall or love.threaderror can see -- see the transport note above).  The
    -- main thread answers from Check.drain(); `big` makes it draw the
    -- downloading banner first and tells its log what it is fetching.
    --
    -- There is no progress: the bridge deals in whole files and takes no Range
    -- header, so there is nothing to poll.  The banner shows an empty bar and
    -- the state goes straight from downloading to ready or error.  A 20 MB
    -- payload on a slow connection is a long stall; the timeout is 15 minutes,
    -- matching curl's --max-time 900 below so neither transport gives up
    -- sooner than the other.
    local okFetch = bridgeFetch(rel.payload.url, partRel, nil, 900,
      { version = rel.version, size = size })
    if not okFetch then
      love.filesystem.remove(partRel)
      post({ status = "error", error = "the host download bridge refused the transfer" })
      return
    end
  else
    launchDownload(rel.payload.url, partAbs, doneAbs)

    -- poll the .part size for progress until curl drops the done-marker; a
    -- stalled or run-away transfer breaks out and lets verification fail cleanly
    local waited, lastSize, lastChange = 0, -1, 0
    while true do
      if love.filesystem.getInfo(doneRel) then break end
      local pinfo = love.filesystem.getInfo(partRel)
      local cur = (pinfo and pinfo.size) or 0
      if size > 0 then
        local p = cur / size
        if p > 0.999 then p = 0.999 end -- 1.0 is reserved for "ready"
        post({ status = "downloading", latest = rel.version, progress = p })
      else
        post({ status = "downloading", latest = rel.version })
      end
      if cur ~= lastSize then lastSize, lastChange = cur, waited end
      if waited - lastChange > 60 then break end -- 60s with no growth: give up
      if waited > 960 then break end             -- absolute ceiling
      love.timer.sleep(0.25)
      waited = waited + 0.25
    end
    love.filesystem.remove(doneRel)
  end

  local sums = curlCapture(rel.sums and rel.sums.url or "")
  if not sums then
    love.filesystem.remove(partRel)
    post({ status = "error", error = "checksum fetch failed" })
    return
  end

  local ok, verr = verifyPayload(partRel, rel.payloadName, sums)
  if not ok then
    love.filesystem.remove(partRel)
    post({ status = "error", error = verr or "verification failed" })
    return
  end

  if gatePasses(partRel) == false then
    love.filesystem.remove(partRel)
    post({ status = "needs_full", latest = rel.version })
    return
  end

  -- finalize: rename the verified .part to its real name (fall back to a
  -- love.filesystem copy if os.rename is unavailable on this platform)
  if not os.rename(partAbs, saveDir .. "/" .. finalRel) then
    local data = love.filesystem.read(partRel)
    if not data then
      post({ status = "error", error = "finalize failed" })
      return
    end
    love.filesystem.write(finalRel, data)
    love.filesystem.remove(partRel)
  end

  post({ status = "ready", latest = rel.version })
end

-- ---------------------------------------------------------------------------
-- command loop
-- ---------------------------------------------------------------------------

while true do
  local cmd = cmdCh:demand() -- blocks until the main thread pushes work
  if type(cmd) == "table" then
    if cmd.cmd == "quit" then
      break
    elseif cmd.cmd == "check" then
      local ok, err = pcall(doCheck)
      if not ok then post({ status = "error", error = tostring(err) }) end
    elseif cmd.cmd == "download" then
      local ok, err = pcall(doDownload)
      if not ok then post({ status = "error", error = tostring(err) }) end
    end
  end
end
