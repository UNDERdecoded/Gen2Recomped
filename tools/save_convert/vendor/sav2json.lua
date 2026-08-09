#!/usr/bin/env lua
-- sav2json.lua <input.sav> [output.json]
--
-- Converts an international (non-Japanese) Pokemon Red/Blue/Yellow save
-- file into a human-editable JSON file. See README.md for details and
-- limitations, and json2sav.lua for the reverse direction.

local scriptDir = arg[0]:match("^(.*)[/\\]") or "."
local gen1 = dofile(scriptDir .. "/gen1lib.lua")

local input = arg[1]
if not input then
    io.stderr:write("usage: lua sav2json.lua <input.sav> [output.json]\n")
    os.exit(1)
end
local output = arg[2] or (input:gsub("%.[^.]*$", "") .. ".json")

local f, err = io.open(input, "rb")
if not f then
    io.stderr:write("error: could not open '" .. input .. "': " .. tostring(err) .. "\n")
    os.exit(1)
end
local raw = f:read("a")
f:close()

local buf = gen1.string_to_bytes(raw)

local ok, result = pcall(gen1.parse_save, buf)
if not ok then
    io.stderr:write("error: " .. tostring(result) .. "\n")
    os.exit(1)
end

local json = gen1.json_encode(result)

local out, werr = io.open(output, "wb")
if not out then
    io.stderr:write("error: could not write '" .. output .. "': " .. tostring(werr) .. "\n")
    os.exit(1)
end
out:write(json)
out:write("\n")
out:close()

print("wrote " .. output)
