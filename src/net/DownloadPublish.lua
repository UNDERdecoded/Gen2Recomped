-- Worker-only atomic replacement. The caller owns the publication claim;
-- slow filesystem/antivirus operations never run in the game's poll path.
return function(source, target)
  if love.system.getOS() ~= "Windows" then return os.rename(source, target) end
  -- Windows rename cannot overwrite an existing file. Never delete the old
  -- destination first: MoveFileExW replaces it in one filesystem operation.
  local ffi = require("ffi")
  ffi.cdef[[
    int MultiByteToWideChar(unsigned int, unsigned long, const char *, int, unsigned short *, int);
    int MoveFileExW(const unsigned short *, const unsigned short *, unsigned long);
    unsigned long GetLastError(void);
  ]]
  local function wide(s)
    local n = ffi.C.MultiByteToWideChar(65001, 8, s, #s, nil, 0)
    if n == 0 then error("invalid UTF-8 download path") end
    local out = ffi.new("unsigned short[?]", n + 1)
    if ffi.C.MultiByteToWideChar(65001, 8, s, #s, out, n) ~= n then error("download path conversion failed") end
    return out
  end
  if ffi.C.MoveFileExW(wide(source), wide(target), 1) == 0 then
    return nil, "download publish failed (Windows " .. tonumber(ffi.C.GetLastError()) .. ")"
  end
  return true
end

