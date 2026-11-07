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

-- POKEPORT_SIMULATE_SWITCH=1 on a desktop build: take the read path the
-- Switch is left with -- no FFI PHYSFS mounts (love-nx is statically linked,
-- no dlopen) and therefore CacheFs's prefix shim as the only way into a
-- version's cache.  Deliberately NOT folded into isNX(): the UI, input and
-- import paths keep behaving as desktop so a harness can still drive them.
-- docs/switch.md.
function Platform.simulatesSwitch()
  local v = os.getenv and os.getenv("POKEPORT_SIMULATE_SWITCH")
  return v ~= nil and v ~= "" and v ~= "0"
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

-- ---------------------------------------------------------------------------
-- CAN THIS BUILD GO ONLINE?  (docs/online-design.md 2.10, workstream WS10)
-- ---------------------------------------------------------------------------
--
-- Measured, like canHostPayload: the answer is whether `require("enet")` and
-- `require("socket")` work in THIS binary, not a list of platforms.  The OS
-- only adds what a library cannot tell us:
--
--   * Web (love.js): no UDP at all, whatever the module table says.
--   * iOS: sending to a multicast or broadcast address needs Apple's
--     com.apple.developer.networking.multicast entitlement, which the
--     sideload builds do not carry -- so no UPnP (SSDP M-SEARCH) and no LAN
--     beacon.  NAT-PMP/PCP are unicast to the gateway and still work, so
--     port mapping stays on.  LAN traffic needs NSLocalNetworkUsageDescription
--     (mobile/ios/overlays/love-ios.plist), which iOS asks about once.
--   * Android: receiving broadcasts needs a held WifiManager.MulticastLock
--     (permission CHANGE_WIFI_MULTICAST_STATE, in the manifest).  The APK's
--     love.system.acquireMulticastLock bridge takes it (GameActivity.java,
--     LanBeacon holds it while a listener is open); a build without the bridge
--     reports the beacon off.
--   * Xbox (UWP): the bundled love.dll (ports/uwp/third_party/love) carries
--     lua-enet and LuaSocket 3.0-rc1; the package declares internetClient,
--     internetClientServer and privateNetworkClientServer.  Not yet tried on
--     a console, so `validated` is false.  UWP blocks loopback between apps.
--   * Switch (love-nx): whether this homebrew runtime was built with enet and
--     luasocket is decided by the probe; `consent` asks the player to accept
--     the ban risk before going online (OnlineGate).
--
-- Returns (memoized; _resetForTests clears it):
--   { available, reason, canHost, canPortMap, canBroadcast,
--     hasEnet, hasSocket, relayOnly, validated, consent, os }
-- `available` is "direct codes and worlds work" (both need lua-enet).
-- `relayOnly` is the narrower case of LuaSocket without enet: short codes
-- and tournaments over the relay (plain TCP) still work.  `reason` is a
-- sentence for the player, nil when there is nothing to say.

local onlineCached

-- swapped by tests: name -> module | nil
Platform.requireProbe = function(name)
  local ok, mod = pcall(require, name)
  if ok and mod then return mod end
  return nil
end

local function computeOnline()
  local d = Platform.detect()
  local osName = d.os
  local hasEnet = Platform.requireProbe("enet") ~= nil
  local hasSocket = Platform.requireProbe("socket") ~= nil
  local r = {
    os = osName, hasEnet = hasEnet, hasSocket = hasSocket,
    available = false, relayOnly = false, canHost = false,
    canPortMap = false, canBroadcast = false,
    validated = not d.nx and not d.uwp,
    consent = d.nx and "homebrew" or nil,
  }
  if osName == "Web" then
    r.hasEnet, r.hasSocket = false, false
    r.reason = "The web version cannot use the network. Play the desktop or phone version to link."
    return r
  end
  if not hasEnet and not hasSocket then
    r.reason = "This build has no network library (lua-enet and LuaSocket are missing), so online play is off."
    return r
  end
  if not hasEnet then
    r.relayOnly = true
    r.reason = "This build has no lua-enet. Direct codes and worlds are off; short codes and tournaments over the relay still work."
    return r
  end
  r.available = true
  r.canHost = true
  -- port mapping and the beacon are luasocket UDP (src/online/net)
  r.canPortMap = hasSocket
  r.canBroadcast = hasSocket and osName ~= "iOS"
  if osName == "Android" then
    local sys = love and love.system
    r.canBroadcast = hasSocket and sys ~= nil
      and type(sys.acquireMulticastLock) == "function"
  end
  if not hasSocket then
    r.reason = "This build has no LuaSocket: codes work on the same network only, and the router cannot be asked to open a port."
  elseif d.nx then
    r.reason = "Online play on the Switch is untested. Going online with homebrew can get a console banned by Nintendo."
  elseif d.uwp then
    r.reason = "Online play on Xbox is untested on hardware. Two apps on one console cannot link to each other."
  end
  return r
end

function Platform.online()
  if not onlineCached then onlineCached = computeOnline() end
  return onlineCached
end

-- the two questions docs/online-design.md 2.10 and WS10 name
function Platform.canHostOnline()
  return Platform.online().canHost
end

function Platform.canPortMap()
  return Platform.online().canPortMap
end

-- Tests may swap love.system between cases.
function Platform._resetForTests()
  cached = nil
  onlineCached = nil
  payloadHost = nil
  if HostShell._resetTransportForTests then
    HostShell._resetTransportForTests()
  end
end

return Platform
