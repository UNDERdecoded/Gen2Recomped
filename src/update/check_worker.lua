-- Background worker for the self-update flow (driven by src/update/Check.lua).
--
-- Runs on a love.thread so no curl call, sha256 pass or archive probe ever
-- touches the render thread.  Talks over two channels:
--   "update_check_cmd"   in:  { cmd = "check" | "download" | "quit" }
--   "update_check_state" out: { status, latest, progress, error }
--
-- Transport is curl shelled out via io.popen (curl ships on macOS, Windows 10+
-- and desktop Linux).  Everything is wrapped so a missing curl, an HTTP error,
-- or a hung download degrades to a "error"/"needs_full" state rather than
-- blocking or crashing the game.  On Android curl is absent and the check
-- soft-fails to "error", which the UI hides.
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
local Check   = loadModule("src/update/Check.lua")
local Version = loadModule("src/core/Version.lua")
local Semver  = loadModule("src/update/Semver.lua")
local HostShell = loadModule("src/core/HostShell.lua")
-- Boot's top-level require("src.update.Semver") cannot resolve in this thread
-- (no src.* searcher), which would leave Boot nil and the minShell gate
-- permanently permissive.  Seed the loaded table first so it resolves.
if Semver then package.loaded["src.update.Semver"] = Semver end
local Boot    = loadModule("src/update/Boot.lua")

local cmdCh   = love.thread.getChannel("update_check_cmd")
local stateCh = love.thread.getChannel("update_check_state")

local function post(t) stateCh:push(t) end

local osName    = (love.system and love.system.getOS and love.system.getOS()) or ""
local isWindows = osName == "Windows"
local saveDir   = love.filesystem.getSaveDirectory()

local API_URL = "https://api.github.com/repos/bryanthaboi/gen1recomp/releases/latest"

-- the release picked by the last "check"; kept between commands so "download"
-- knows the payload url/size/name without re-fetching
local pending = nil

-- ---------------------------------------------------------------------------
-- shell / curl
-- ---------------------------------------------------------------------------

local function shq(s)
  s = tostring(s)
  if isWindows then
    return '"' .. s:gsub('"', '') .. '"'
  end
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

-- run curl and return its response body (text), or nil on any failure.  Used
-- for the small text resources (release JSON, sums file); -f makes curl exit
-- non-zero and emit nothing on an HTTP error, so an empty read is a failure.
local function curlCapture(url)
  local cmd = "curl -fsSL --connect-timeout 10 --max-time 40 "
    .. "-H " .. shq("User-Agent: gen1recomp-updater") .. " "
    .. "-H " .. shq("Accept: application/vnd.github+json") .. " "
    .. shq(url)
  local pipe = HostShell.popen(cmd)
  if not pipe then return nil end
  local out = pipe:read("*a")
  pipe:close()
  if not out or out == "" then return nil end
  return out
end

local function haveCurl()
  local pipe = HostShell.popen("curl --version")
  if not pipe then return false end
  local out = pipe:read("*a")
  pipe:close()
  return out ~= nil and out:find("curl", 1, true) ~= nil
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

  if not haveCurl() then
    post({ status = "error", error = "curl not available" })
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
  local finalRel = "updates/" .. rel.payloadName
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
    local batRel = "updates/dl.bat"
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
  local rel = pending
  post({ status = "downloading", latest = rel.version, progress = 0 })

  love.filesystem.createDirectory("updates")
  local partRel  = "updates/" .. rel.payloadName .. ".part"
  local doneRel  = "updates/" .. rel.payloadName .. ".done"
  local finalRel = "updates/" .. rel.payloadName
  love.filesystem.remove(partRel)
  love.filesystem.remove(doneRel)

  local partAbs = saveDir .. "/updates/" .. rel.payloadName .. ".part"
  local doneAbs = saveDir .. "/updates/" .. rel.payloadName .. ".done"
  local size    = rel.payload.size or 0

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
  if not os.rename(partAbs, saveDir .. "/updates/" .. rel.payloadName) then
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
