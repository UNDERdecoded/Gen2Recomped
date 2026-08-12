-- Registry of hand-ported map scripts.  Map-specific behavior lives HERE,
-- never in engine classes (Critical Engineering Rule #9).
--
-- Each module returns { talk = { [TEXT_CONST] = script }, onEnter = fn,
-- onBoulderMoved = fn } where a script is a list of { "command", args... }
-- rows executed by src/script/ScriptRunner.lua.  Every hand-ported script
-- cites the pokered source it was ported from.
--
-- The modules land in src/script/MapScripts.lua as the engine's base
-- contribution: attachBase keeps the historical merge (talk tables merge
-- per TEXT constant, other hooks are replaced by later files, so
-- different files can each add NPCs to the same map), and mod
-- contributions from the map_scripts registry compose on top of it.

local GameVersion = require("src.core.GameVersion")
local MapScripts = require("src.script.MapScripts")

-- Gen2 ships its scripts as ROM bytecode, disassembled at import time into
-- data/generated/map_scripts.lua.  Attach its object dialogue first so the
-- hand-ported modules below still win per TEXT constant; the scene and
-- coord-event tables are attached last (see the end of this file) so the
-- ROM's own cutscene wiring wins over the hand-ported stand-ins.
local gen2Data = require("src.core.Data")
local gen2VM = gen2Data.map_scripts and require("src.script.Gen2ScriptVM") or nil
if gen2VM then gen2VM.register(gen2Data, "talk") end

-- Maps that Gen2 map_scripts already owns.  Gen1 story hand-ports for the
-- same map ids (CERULEAN_CITY, ROUTE24→ROUTE_24, etc.) must not attach:
-- they override Gen2 talk with pokered rival/Nugget Bridge scripts and
-- leave players fighting CeruleanCityRival with Gen1 text on a Gold/Silver
-- save.
local gen2OwnedMaps = {}
if gen2VM and gen2Data.map_scripts and gen2Data.map_scripts.maps then
  for mapId in pairs(gen2Data.map_scripts.maps) do
    gen2OwnedMaps[mapId] = true
    -- MapScripts.normalizeMapId inserts _ before trailing digits (ROUTE24
    -- → ROUTE_24).  Mark both spellings so story modules keyed either way
    -- are skipped.
    local normalized = mapId:gsub("([A-Z])(%d)", "%1_%2")
    gen2OwnedMaps[normalized] = true
    local compact = mapId:gsub("_(%d+)$", "%1")
    gen2OwnedMaps[compact] = true
  end
end

local function attachBaseUnlessGen2(mapId, mod)
  if gen2OwnedMaps[mapId] then return end
  local compact = type(mapId) == "string" and mapId:gsub("_(%d+)$", "%1") or mapId
  local normalized = type(mapId) == "string" and mapId:gsub("([A-Z])(%d)", "%1_%2") or mapId
  if gen2OwnedMaps[compact] or gen2OwnedMaps[normalized] then return end
  MapScripts.attachBase(mapId, mod)
end

-- OaksLab is a full Yellow rewrite (one Eevee ball + forced Pikachu);
-- Red/Blue keep the three-starter choose flow.  Skip on Gen2.
if not gen2VM then
  local oaksLab = GameVersion.isYellow()
    and "data.scripts.oaks_lab_yellow"
    or "data.scripts.oaks_lab"

  for _, mapEntry in ipairs({
    { "PALLET_TOWN", "data.scripts.pallet_town" },
    { "OAKS_LAB", oaksLab },
    { "REDS_HOUSE_1F", "data.scripts.reds_house" },
    { "CELADON_MANSION_ROOF_HOUSE", "data.scripts.celadon_eevee" },
  }) do
    MapScripts.attachBase(mapEntry[1], require(mapEntry[2]))
  end
end

-- The Gen2 errand chain (player's house, Elm's lab, Mr Pokemon's house) was
-- hand-ported before the ROM bytecode ran; the VM now drives those maps end to
-- end, and mixing the two left the player stuck -- the hand-written Elm
-- dialogue never advanced the scene the ROM's "you can't leave yet" script
-- checks.  They only load when the disassembly is unavailable.
if not gen2VM then
  for _, mapEntry in ipairs({
    { "PLAYERS_HOUSE1_F", "data.scripts.players_house1f" },
    { "MAP_G18_N06",     "data.scripts.players_house1f" },
    { "ELMS_LAB",        "data.scripts.elms_lab" },
  }) do
    MapScripts.attachBase(mapEntry[1], require(mapEntry[2]))
  end
  for mapId, mod in pairs(require("data.scripts.mr_pokemons_house")) do
    if type(mod) == "table" and (mod.talk or mod.onEnter) then
      MapScripts.attachBase(mapId, mod)
    end
  end
end

-- story-critical scripts, one table per map, in the order the old merge
-- loop required them.  On Gen2, skip any map the ROM bytecode already owns
-- (Kanto post-game Cerulean/Route24/25, Kurt, gyms, …).
for _, file in ipairs({ "data.scripts.story", "data.scripts.story2",
                        "data.scripts.story3", "data.scripts.story4",
                        "data.scripts.story5", "data.scripts.story6",
                        "data.scripts.story7",
                        "data.scripts.flavor_all",
                        "data.scripts.safari", "data.scripts.seafoam",
                        "data.scripts.gyms" }) do
  for mapId, mod in pairs(require(file)) do
    attachBaseUnlessGen2(mapId, mod)
  end
end

-- Yellow-only content on top of the shared tables (talk keys merge per
-- TEXT constant): the Kanto-starter gift quests and Jessie & James.
if GameVersion.isYellow() and not gen2VM then
  for _, file in ipairs({ "data.scripts.yellow_gifts",
                          "data.scripts.yellow_jessie_james",
                          "data.scripts.yellow_beach_house",
                          "data.scripts.yellow_viridian_old_man" }) do
    for mapId, mod in pairs(require(file)) do
      MapScripts.attachBase(mapId, mod)
    end
  end
end

if gen2VM then gen2VM.register(gen2Data, "scenes") end

local M = {}

function M.get(mapId)
  return MapScripts.get(mapId)
end

-- script to run when the player talks to an object with this TEXT_ constant
function M.talkScript(mapId, textConst)
  return MapScripts.talkScript(mapId, textConst)
end

-- attribution for that script's run: the owning mod's source, nil for base
function M.talkSource(mapId, textConst)
  return MapScripts.talkSource(mapId, textConst)
end

return M
