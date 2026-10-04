-- Platform capability detection for console, mobile and desktop builds.
--
-- Ported from gen1recomp, whose Switch build this fork predates.  Nothing in
-- this tree knew the string love-nx reports ("NX"), so the Switch fell
-- through every platform test to the desktop branch and was asked to use a
-- file picker and a shell it does not have.

local HostShell = require("src.core.HostShell")

local Platform = {}

local cached
local payloadHost

local function compute()
  local osName = (love and love.system and love.system.getOS and love.system.getOS())
    or "Unknown"
  local nx = osName == "NX"
  local uwp = osName == "UWP"
  local mobile = osName == "Android" or osName == "iOS"
  local nativePicker = love and love.system
    and type(love.system.pickFile) == "function"
  local nativeHttp = love and love.system
    and type(love.system.httpDownload) == "function"
  return {
    os = osName,
    nx = nx,
    uwp = uwp,
    mobile = mobile,
    console = nx or uwp,
    hasNativePicker = nativePicker,
    -- ONE definition, in src/core/HostShell.lua, beside the io.popen it
    -- describes.  The literal three-OS test used to live here as well, so the
    -- shell that raises on the Switch was guarded by one copy and asked about
    -- through another.
    canSpawnProcess = HostShell.canSpawnProcess(),
    romImportMode = nx and "save-directory"
      or (nativePicker and "native-picker")
      or "desktop",
    networkValidated = not nx and not uwp,
    -- networkValidated is the self-updater's gate and stays a per-platform
    -- policy call: a console package cannot replace itself on disk, so that
    -- answer never depends on whether a transport exists.  Fetching a mod
    -- index or a mod zip is the narrower question, and #876 showed the two
    -- had been conflated, so Xbox lost the mod catalog for the updater's
    -- reason.  Desktop answers it with curl through HostShell; the mobile and
    -- console ports answer it with the native love.system.httpDownload bridge
    -- (#597).  The UWP LOVE backend does not export that bridge yet, so this
    -- still resolves false on Xbox and the launcher still says so, but the
    -- day the backend grows one, nothing here or in RomImporter has to change.
    canFetchRemote = (not nx and not uwp) or nativeHttp,
  }
end

function Platform.detect()
  if not cached then cached = compute() end
  return cached
end

function Platform.isNX()
  return Platform.detect().nx
end

function Platform.isUWP()
  return Platform.detect().uwp
end

function Platform.romImportMode()
  return Platform.detect().romImportMode
end

function Platform.canSpawnProcess()
  return Platform.detect().canSpawnProcess
end

-- ---------------------------------------------------------------------------
-- CAN THIS SHELL HOST A DOWNLOADED PAYLOAD?
-- ---------------------------------------------------------------------------
--
-- The self-updater's real question, and for two years it was answered by an
-- OS table in src/update/Check.lua whose comment said the Switch and an Xbox
-- UWP package "cannot pick up a downloaded archive" because the payload is
-- fused into the NRO and the app container is signed and read-only.
--
-- Both halves of that are true and neither is the question.  src/update/Boot.lua
-- does not replace the executable or write inside the package: it mounts a
-- .love out of the SAVE DIRECTORY over "/" and chainloads it.  Every port has
-- a writable save directory -- it is where the launcher already puts saves,
-- options and the whole ROM cache on the Switch and on Xbox -- so a payload
-- that is PRESENT there is runnable on both.  What the consoles actually lack
-- is a way to FETCH one (HostShell.transport), which is a separate fact with a
-- separate answer and a separate fix.
--
-- So this is measured, not listed.  Three things, each of which can say no:
--   * love.filesystem exists and reports a save directory;
--   * a byte written into Payload.DIR comes back when read;
--   * love.filesystem.mount/unmount are functions (Boot needs both).
-- A new port is right by default and a port whose save directory is read-only
-- is caught by the port, not by a table somebody forgot to add it to.
--
-- Memoized after the first positive answer; a negative is retried, because the
-- save directory can become writable (a Switch microSD remounted rw, an
-- Android volume granted) without the process restarting.
-- IS THIS A PACKAGED APP CONTAINER (an Xbox/UWP package, or an MSIX install)?
--
-- src/update/Check.lua carried, for two years, the claim that this question has
-- no answer: "love._os cannot tell a UWP package apart from a desktop Windows
-- build (both report \"Windows\"), so the console packagers set the global below
-- from their own bootstrap".  The first half is true -- and the global was set
-- by nothing, so the consequence was that Xbox was never recognised at all.
--
-- The shell does tell us, just not through love._os.  A packaged app's writable
-- folder is handed out by the OS under its package identity:
--
--   desktop LOVE on Windows   C:\Users\<u>\AppData\Roaming\LOVE\<identity>
--   UWP / MSIX container      C:\Users\<u>\AppData\Local\Packages\
--                               <PackageFamilyName>\LocalState\...
--
-- so the marker is the `Packages` component, which only appears because the
-- process has package identity.  Measured off love.filesystem.getSaveDirectory()
-- rather than asserted about a platform.
--
-- An MSIX-packaged DESKTOP build (scripts/build_msix.ps1) matches too, and that
-- is correct rather than a false positive: an MSIX build is also updated by
-- installing a newer package, which is the one thing this answer is used for.
-- The only way to be wrong is a user folder with a literal "Packages"
-- component, and the cost of that is a different sentence in the update banner.
function Platform.isPackagedContainer()
  local fs = love and love.filesystem
  if not (fs and type(fs.getSaveDirectory) == "function") then return false end
  local ok, dir = pcall(fs.getSaveDirectory)
  if not ok or type(dir) ~= "string" or dir == "" then return false end
  dir = dir:gsub("\\", "/")
  return dir:lower():find("/packages/", 1, true) ~= nil
end

function Platform.canHostPayload()
  if payloadHost == true then return true end
  local fs = love and love.filesystem
  if not fs then return false end
  for _, name in ipairs({ "write", "read", "remove", "createDirectory",
                          "getSaveDirectory", "mount", "unmount" }) do
    if type(fs[name]) ~= "function" then return false end
  end
  local okDir, dir = pcall(fs.getSaveDirectory)
  if not okDir or type(dir) ~= "string" or dir == "" then return false end
  local Payload = require("src.update.Payload")
  local probe = Payload.DIR .. "/.hostprobe"
  pcall(fs.createDirectory, Payload.DIR)
  -- love.filesystem.write returns false (not an error) when physfs refuses,
  -- so the pcall is only for a port that raises instead; the READ-BACK is what
  -- decides.  A directory that swallows a write and hands back nothing is the
  -- failure this is looking for.
  local okWrite, wrote = pcall(fs.write, probe, "ok")
  local back = false
  if okWrite and wrote ~= false then
    local okRead, data = pcall(fs.read, probe)
    back = okRead and data == "ok"
  end
  pcall(fs.remove, probe)
  payloadHost = back == true
  return payloadHost
end

function Platform.networkValidated()
  return Platform.detect().networkValidated
end

function Platform.canFetchRemote()
  return Platform.detect().canFetchRemote
end

-- Tests may swap love.system between cases.
function Platform._resetForTests()
  cached = nil
  payloadHost = nil
  if HostShell._resetTransportForTests then
    HostShell._resetTransportForTests()
  end
end

return Platform
