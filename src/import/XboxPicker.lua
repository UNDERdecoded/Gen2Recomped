-- THE XBOX ROM PICKER, on the Lua side.
--
-- The bundled love.dll has a file picker, but its ROM filter is .gb and .gbc
-- only. ports/uwp/app/main.cpp opens one that also offers .gba and .nds, and
-- this file puts it behind the same love.system.pickFile / getPickedFile /
-- getPickError calls the launcher already uses on iOS. The two sides talk through
-- files in LocalState; the protocol is described in main.cpp.
--
-- Mods (.zip) and saves (.sav) stay on the love.dll picker, which handles those.
-- A package older than this code has no gr_picker_ready file, so its ROM picks
-- stay on the love.dll picker as well: Game Boy games only.

local X = {}

local function parentOf(path)
  return (tostring(path):match("^(.*)[/\\][^/\\]+[/\\]?$"))
end

local function fileExists(path)
  local f = io.open(path, "rb")
  if not f then return false end
  f:close()
  return true
end

-- The answer, once it has been written in full: "P...", "C" or "E...".
local function takeResult(root)
  local path = root .. "/gr_pick_result"
  local f = io.open(path, "rb")
  if not f then return nil end
  local text = f:read("*a")
  f:close()
  if not (text and text:sub(-1) == "\n") then return nil end
  os.remove(path)
  return (text:gsub("[\r\n]+$", ""))
end

-- Replaces the three love.system calls. Answers true if it did.
function X.install()
  local sys = love and love.system
  if not (sys and sys.getOS and sys.getOS() == "UWP") then return false end
  if X.installed then return true end
  if type(sys.pickFile) ~= "function" or type(sys.getPickedFile) ~= "function" then
    return false
  end
  local okDir, saveDir = pcall(love.filesystem.getSaveDirectory)
  local root = okDir and parentOf(saveDir)
  if not (root and fileExists(root .. "/gr_picker_ready")) then return false end

  os.remove(root .. "/gr_pick_result")
  local pickFile, getPickedFile = sys.pickFile, sys.getPickedFile
  local getPickError = sys.getPickError
  local waiting, pickError = false, nil

  -- A result only counts while a ROM pick is out. Its error is held for
  -- getPickError, which the launcher asks straight after getPickedFile.
  local function poll()
    if not waiting then return nil end
    local line = takeResult(root)
    if not line then return nil end
    waiting = false
    local kind, rest = line:sub(1, 1), line:sub(2)
    if kind == "P" and rest ~= "" then return rest end
    if kind == "E" then pickError = rest ~= "" and rest or "The file picker failed." end
    return nil
  end

  sys.pickFile = function(kind, ...)
    if kind ~= nil and kind ~= "rom" then return pickFile(kind, ...) end
    if waiting then return true end
    local f = io.open(root .. "/gr_pick_request", "wb")
    if not f then return pickFile(kind, ...) end
    f:write("rom\n")
    f:close()
    waiting = true
    return true
  end

  sys.getPickedFile = function()
    return poll() or getPickedFile()
  end

  sys.getPickError = function()
    if pickError then
      local e = pickError
      pickError = nil
      return e
    end
    return getPickError and getPickError() or nil
  end

  X.installed = true
  return true
end

return X
