-- Platform capability detection for console, mobile, handheld and desktop builds.

local Platform = {}

local cached

local function compute()
  local osName = (love and love.system and love.system.getOS and love.system.getOS())
    or "Unknown"
  local nx = osName == "NX"
  local uwp = osName == "UWP"
  local mobile = osName == "Android" or osName == "iOS"
  
  -- PortMaster environment detection for R36S / ArkOS and similar handhelds
  local isPortMaster = os.getenv("PORTMASTER") ~= nil 
    or os.getenv("DEVICE_NAME") ~= nil 
    or love.filesystem.getInfo("portmaster") ~= nil

  local nativePicker = love and love.system
    and type(love.system.pickFile) == "function"
  local nativeHttp = love and love.system
    and type(love.system.httpDownload) == "function"

  return {
    os = osName,
    nx = nx,
    uwp = uwp,
    mobile = mobile,
    portmaster = isPortMaster,
    console = nx or uwp or isPortMaster,
    hasNativePicker = nativePicker and not isPortMaster,
    canSpawnProcess = (osName == "OS X" or osName == "Windows" or osName == "Linux") and not isPortMaster,
    romImportMode = (nx or isPortMaster) and "save-directory"
      or (nativePicker and "native-picker")
      or "desktop",
    networkValidated = not nx and not uwp,
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

function Platform.isPortMaster()
  return Platform.detect().portmaster
end

function Platform.romImportMode()
  return Platform.detect().romImportMode
end

function Platform.canSpawnProcess()
  return Platform.detect().canSpawnProcess
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
end

return Platform
