-- Reading files that are not ours.
--
-- WHY THIS IS `io` AND NOT `love.filesystem`.  A LOVE app can only see two
-- directories: its own source and its own save directory.  Everything this
-- editor reads lives in a THIRD place -- the game's save directory, where
-- the ROM extractor wrote the cache, and the mods folder beside it -- and
-- love.filesystem.mount refuses an external folder (the engine's own
-- src/import/CacheFs.lua says so in as many words and reaches for FFI and
-- PHYSFS_mount to get around it).
--
-- FFI is not needed here.  LuaJIT's `io` opens an absolute path perfectly
-- well, and an image can be handed to love.image as bytes rather than as a
-- path.  So: every external read goes through this file, as bytes, and the
-- only thing love.filesystem is used for is the editor's OWN settings.
--
-- Nothing here writes outside a path the caller states.

local Fs = {}

Fs.sep = (package and package.config and package.config:sub(1, 1)) or "/"
Fs.windows = Fs.sep == "\\"

-- Always build paths with forward slashes.  Windows accepts them at every
-- API this uses, and a path that is one thing on one platform is a bug
-- waiting for the other one.
function Fs.join(...)
  local parts = { ... }
  local out = {}
  for _, p in ipairs(parts) do
    if p and p ~= "" then
      p = tostring(p):gsub("\\", "/"):gsub("/+$", "")
      out[#out + 1] = p
    end
  end
  return (table.concat(out, "/"):gsub("//+", "/"))
end

function Fs.dirname(path)
  return (tostring(path):gsub("\\", "/"):gsub("/[^/]*$", ""))
end

function Fs.basename(path)
  return (tostring(path):gsub("\\", "/"):match("([^/]*)$"))
end

-- Read a whole file as a string, or nil plus a reason.  Binary mode always:
-- a PNG read in text mode on Windows loses every 0x1A.
function Fs.read(path)
  local f, err = io.open(path, "rb")
  if not f then return nil, err or ("cannot open " .. tostring(path)) end
  local data = f:read("*a")
  f:close()
  if not data then return nil, "empty read: " .. tostring(path) end
  return data
end

function Fs.exists(path)
  local f = io.open(path, "rb")
  if f then f:close() return true end
  return false
end

function Fs.isDir(path)
  -- No stat without FFI, so ask the only question that matters: can we
  -- open something inside it?  A directory opens as a file on some
  -- platforms and fails to READ on all of them, which is the test.
  local f = io.open(path, "rb")
  if not f then
    -- try it as a directory by opening a name under it that cannot exist
    return false
  end
  local ok = f:read(1)
  f:close()
  if ok == nil then return true end
  return false
end

function Fs.write(path, data)
  local f, err = io.open(path, "wb")
  if not f then return nil, err or ("cannot write " .. tostring(path)) end
  f:write(data)
  f:close()
  return true
end

-- Create a directory and its parents.  There is no portable mkdir in plain
-- Lua; this shells out, quietly, and the caller checks the result by trying
-- to write.  Kept here so exactly one place in the editor knows the two
-- spellings.
function Fs.mkdirp(path)
  path = Fs.join(path)
  if Fs.exists(Fs.join(path, ".")) then return true end
  local cmd
  if Fs.windows then
    cmd = 'mkdir "' .. path:gsub("/", "\\") .. '" 2>NUL'
  else
    cmd = 'mkdir -p "' .. path .. '" 2>/dev/null'
  end
  os.execute(cmd)
  return true
end

-- Load a Lua data file from an absolute path and call it with `...`.
-- Returns value, or nil + error.  Never raises: a broken data file must
-- leave the editor open with a message, not take it down.
function Fs.loadLua(path, ...)
  local src, err = Fs.read(path)
  if not src then return nil, err end
  -- strip a UTF-8 BOM: the extractor does not write one, a text editor might
  if src:sub(1, 3) == "\239\187\191" then src = src:sub(4) end
  local chunk, cerr
  if _VERSION == "Lua 5.1" then
    chunk, cerr = loadstring(src, "@" .. path)
  else
    chunk, cerr = load(src, "@" .. path)
  end
  if not chunk then return nil, cerr end
  local ok, value = pcall(chunk, ...)
  if not ok then return nil, tostring(value) end
  return value
end

return Fs
