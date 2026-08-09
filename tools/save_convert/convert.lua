#!/usr/bin/env luajit
-- CLI: import a vanilla Gen1 (Red/Blue, international) save -- either a
-- raw 32768-byte .sav file, or a JSON wrapper carrying one as its
-- `raw_base64` field -- into this project's save.lua format, or export a
-- save.lua back out to a raw .sav. Run from the repo root:
--
--   luajit tools/save_convert/convert.lua import <in.json|in.sav> <out.lua>
--   luajit tools/save_convert/convert.lua export <in.lua> <out.sav>
--
-- This is a thin shell: all the actual work (size/checksum validation, the
-- GenSave codec, crosswalk data loading, the merge over new-game defaults)
-- lives in src/save_convert/SaveConvert.lua, shared with the runtime. This
-- file only handles the filesystem + the JSON/base64 input framing. See
-- src/save_convert/GenSave.lua for the codec and its documented scope.

package.path = "./?.lua;" .. package.path

local SaveConvert = require("src.save_convert.SaveConvert")
local SaveSerializer = require("src.core.SaveSerializer")
local Version = require("src.core.Version")

local B64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_LOOKUP = {}
for i = 1, #B64_CHARS do B64_LOOKUP[B64_CHARS:sub(i, i)] = i - 1 end

local function b64decode(s)
  s = s:gsub("[^%w+/=]", "")
  local out = {}
  local i = 1
  while i <= #s do
    local c1, c2, c3, c4 = s:sub(i, i), s:sub(i + 1, i + 1), s:sub(i + 2, i + 2), s:sub(i + 3, i + 3)
    local n1, n2 = B64_LOOKUP[c1], B64_LOOKUP[c2]
    local n3 = c3 ~= "=" and c3 ~= "" and B64_LOOKUP[c3] or nil
    local n4 = c4 ~= "=" and c4 ~= "" and B64_LOOKUP[c4] or nil
    out[#out + 1] = string.char(n1 * 4 + math.floor(n2 / 16))
    if n3 then
      out[#out + 1] = string.char((n2 % 16) * 16 + math.floor(n3 / 4))
      if n4 then out[#out + 1] = string.char((n3 % 4) * 64 + n4) end
    end
    i = i + 4
  end
  return table.concat(out)
end

local function readFile(path, mode)
  local f = assert(io.open(path, mode or "r"), "cannot open " .. path)
  local content = f:read("*a")
  f:close()
  return content
end

local function cmdImport(inPath, outPath)
  local content = readFile(inPath, "rb")
  local bytes
  if #content == SaveConvert.SAVE_SIZE then
    bytes = content
  else
    local b64 = content:match('"raw_base64"%s*:%s*"([^"]+)"')
    assert(b64, "input is neither a 32768-byte .sav nor JSON with a raw_base64 field")
    bytes = b64decode(b64)
    assert(#bytes == SaveConvert.SAVE_SIZE,
          ("decoded raw_base64 is %d bytes, want %d"):format(#bytes, SaveConvert.SAVE_SIZE))
  end

  local save, err = SaveConvert.importSav(bytes, Version.saveFormat)
  assert(save, err)

  local out = assert(io.open(outPath, "w"))
  out:write(SaveSerializer.encode(save))
  out:close()
  print(("wrote %s (party %d, boxed %d, %d flags)"):format(
    outPath, #save.party,
    (function() local n = 0 for _, b in ipairs(save.boxes) do n = n + #b end return n end)(),
    (function() local n = 0 for _ in pairs(save.flags) do n = n + 1 end return n end)()))
end

local function cmdExport(inPath, outPath)
  local content = readFile(inPath)
  local save = assert(SaveSerializer.decode(content))
  local bytes, err = SaveConvert.exportSav(save)
  assert(bytes, err)
  local out = assert(io.open(outPath, "wb"))
  out:write(bytes)
  out:close()
  print(("wrote %s (%d bytes)"):format(outPath, #bytes))
end

local cmd = arg[1]
if cmd == "import" and arg[2] and arg[3] then
  cmdImport(arg[2], arg[3])
elseif cmd == "export" and arg[2] and arg[3] then
  cmdExport(arg[2], arg[3])
else
  io.stderr:write(
    "usage: luajit tools/save_convert/convert.lua import <in.json|in.sav> <out.lua>\n" ..
    "       luajit tools/save_convert/convert.lua export <in.lua> <out.sav>\n")
  os.exit(1)
end
