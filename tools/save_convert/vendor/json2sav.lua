#!/usr/bin/env lua
-- json2sav.lua <input.json> [output.sav]
--
-- Converts a JSON file (as produced by sav2json.lua, optionally hand-edited)
-- back into a binary Pokemon Red/Blue/Yellow save file, recomputing the
-- save's checksum. See README.md for details and limitations.

local scriptDir = arg[0]:match("^(.*)[/\\]") or "."
local gen1 = dofile(scriptDir .. "/gen1lib.lua")

local input = arg[1]
if not input then
    io.stderr:write("usage: lua json2sav.lua <input.json> [output.sav]\n")
    os.exit(1)
end
local output = arg[2] or (input:gsub("%.[^.]*$", "") .. ".sav")

local f, err = io.open(input, "rb")
if not f then
    io.stderr:write("error: could not open '" .. input .. "': " .. tostring(err) .. "\n")
    os.exit(1)
end
local text = f:read("a")
f:close()

local ok, data = pcall(gen1.json_decode, text)
if not ok then
    io.stderr:write("error: invalid JSON: " .. tostring(data) .. "\n")
    os.exit(1)
end

local ok2, savBytes = pcall(gen1.build_save, data)
if not ok2 then
    io.stderr:write("error: " .. tostring(savBytes) .. "\n")
    os.exit(1)
end

local out, werr = io.open(output, "wb")
if not out then
    io.stderr:write("error: could not write '" .. output .. "': " .. tostring(werr) .. "\n")
    os.exit(1)
end
out:write(savBytes)
out:close()

print("wrote " .. output .. " (" .. #savBytes .. " bytes)")
