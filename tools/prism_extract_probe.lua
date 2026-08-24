-- What actually blocks a Prism import?  Drives the real extractor end to end
-- with every write captured in memory, and reports per-stage what came out.
-- Guessing from the missing-symbol list overstates the problem: most readers
-- are pcall'd with a scaffold fallback, so a missing symbol costs a feature,
-- not the import.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local version = arg[1] or "prism"
local romPath = arg[2] or "pokeprism.gbc"
local manifestPath = arg[3] or "tools/rom_manifest_prism.json"

local function rd(p)
  local f = io.open(p, "rb"); if not f then return nil end
  local d = f:read("*a"); f:close(); return d
end

local rom = assert(rd(romPath), "rom missing: " .. romPath)
local manifest = assert(require("src.link.Json").decode(assert(rd(manifestPath))))

-- capture instead of writing into the checkout
local LuaWriter = require("src.import.LuaWriter")
local written = {}
LuaWriter.write = function(path, value) written[path] = value end
local okImg, ImageWriter = pcall(require, "src.import.ImageWriter")
local images = 0
if okImg then ImageWriter.save = function() images = images + 1 end end

local E = require("src.import.RomExtractorGen2")
local x = E.new(rom, version, manifest)
-- Seed from the Python scaffold on real disk (love_stub's filesystem is
-- in-memory, so the extractor's own love.filesystem.load finds nothing).
local sourceDir = arg[4]
x.readSourceTable = function(_, name)
  if sourceDir then
    local chunk = loadfile(sourceDir .. "/" .. name .. ".lua")
    if chunk then
      local ok, value = pcall(chunk)
      if ok and type(value) == "table" then return value end
    end
  end
  if name == "constants" then
    local c = {}
    for k, v in pairs(manifest.constants or {}) do c[k] = v end
    return c
  end
  return {}
end
x.saveImage = function() images = images + 1 end

local stages = {
  "extractScaffoldCore", "extractMoves", "extractMapsFromRom",
  "extractMapScripts", "extractTextFromRom", "extractPokemon",
  "extractPalettes", "extractIcons", "extractEncounters", "extractField",
  "extractRuntimeScaffolds", "extractIntroAssetsFromRom", "extractAudio",
  "extractAssets",
}

print(("=== %s: %d stages ==="):format(version, #stages))
local failed = 0
for _, stage in ipairs(stages) do
  local before = 0
  for _ in pairs(written) do before = before + 1 end
  local ok, err = pcall(function() return x[stage](x) end)
  local after = 0
  for _ in pairs(written) do after = after + 1 end
  if ok then
    print(("  ok    %-26s +%d file(s)"):format(stage, after - before))
  else
    failed = failed + 1
    print(("  FAIL  %-26s %s"):format(stage, tostring(err):gsub("%s+", " "):sub(1, 150)))
  end
end

print(("\n%d/%d stages ran, %d file(s) produced, %d image(s)")
  :format(#stages - failed, #stages, (function() local n=0 for _ in pairs(written) do n=n+1 end return n end)(), images))

-- size of the things that decide whether the game is playable
local function count(t) local n = 0; if type(t)=="table" then for _ in pairs(t) do n = n + 1 end end return n end
print("\n--- payload ---")
for _, name in ipairs{"constants","moves","items","maps","pokemon","encounters",
                      "trainers","type_chart","text","tilesets","field","map_scripts"} do
  local v = written["data/generated/" .. name .. ".lua"]
  if v == nil then print(("  %-14s (not written)"):format(name))
  else print(("  %-14s %d entr%s"):format(name, count(v), count(v)==1 and "y" or "ies")) end
end
local maps = written["data/generated/maps.lua"]
if type(maps) == "table" then
  local shown = 0
  for id, m in pairs(maps) do
    if shown < 5 then
      print(("     map %-22s %sx%s"):format(tostring(id),
        tostring(type(m)=="table" and m.width), tostring(type(m)=="table" and m.height)))
      shown = shown + 1
    end
  end
end
