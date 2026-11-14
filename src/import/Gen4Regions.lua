-- THE PLATINUM CARTRIDGES THAT ARE NOT THE US ONE, and what the extractor has
-- to know to read them as if they were.
--
-- Three retail dumps import as `platinum` (GameVersion sha1/sha1Alt):
--
--   CPUE rev 1   (USA) Rev 1, what the extractor was written against
--   CPUE rev 10  (Europe), English.  The SAME game code, the same ARM9 and all
--                122 overlays byte for byte; five files differ (the slot
--                machine reels, the opening's legal overlay, one map's
--                collision, one map's scripts, six text banks).  Nothing here
--                applies to it -- the US layout IS its layout.
--   CPUD rev 0   (Germany) "Platin Edition".  Its own ARM9 (+416 bytes) and
--                overlay build (loaded 0x1A0/0x1C0 higher), German text in the
--                same 724-bank message archive under the same bank numbers,
--                and its 32 language-specific archives moved under
--                /resource/ger/<dir>/ with their file names unchanged.
--
-- THE ARCHIVES are the only layout difference the extractor sees: every ARM9
-- and overlay table it reads is FOUND BY CONTENT (a signature, a structural
-- search, a known-first-row), never by address, so a shifted build costs
-- nothing there -- and tools/gen4_region_check.lua proves that by diffing a
-- German import's tables against a US one.  The moved archives are answered
-- at the filesystem: NdsRom:index() asks `Gen4Regions.pathAliases` for the
-- cartridge's game code and lets the US path name the German file, so the
-- two hundred stage modules that open "/graphic/box.narc" keep doing so.
--
-- The table itself is generated (src/import/Gen4RegionMap.lua, by
-- tools/gen4_region_map_gen.py from the US dump and the localized one), so it
-- is regenerated rather than edited.
--
-- Zero requires at load time, like NdsRom: the import worker thread loads it.

local Regions = {}

-- by game code: the language of the cartridge's own text.  `language` is an
-- ISO 639-1 code; the engine's text is whatever the cartridge says, so this
-- is for reports and for the few places that must know (see `isEnglish`).
Regions.BY_CODE = {
  CPUE = { language = "en", label = "English" },
  CPUD = { language = "de", label = "German" },
}

local map
local function regionMap()
  if map == nil then
    local ok, m = pcall(require, "src.import.Gen4RegionMap")
    map = ok and type(m) == "table" and m or false
  end
  return map or nil
end

-- US path -> this cartridge's path, or nil when the cartridge uses US paths.
function Regions.pathAliases(gameCode)
  local m = regionMap()
  local entry = m and gameCode and m[gameCode]
  return entry and entry.paths or nil
end

-- Moved archives whose member count is not the US one ({ us, here }).
function Regions.shortNarcs(gameCode)
  local m = regionMap()
  local entry = m and gameCode and m[gameCode]
  return entry and entry.shortNarcs or {}
end

function Regions.language(gameCode)
  local r = gameCode and Regions.BY_CODE[gameCode]
  return r and r.language or "en"
end

function Regions.isEnglish(gameCode)
  return Regions.language(gameCode) == "en"
end

return Regions
