-- Which Pokemon version this process is running: Red (the historical
-- default), Blue, Yellow, Gold, or Silver.
-- One source of truth for everything that differs by
-- version -- the accepted ROM hash, the import manifest, where the
-- extracted cache lives, and the save-file suffix -- so the importer,
-- cache mount, SaveData, title screen and palette all agree.
--
-- Red keeps every un-suffixed path it always used (save.lua, the root cache),
-- so existing installs are untouched; Blue is namespaced under blue/ and
-- _blue, Yellow under yellow/ and _yellow, Gold under gold/ and _gold,
-- Silver under silver/ and _silver, so versions can be imported and played
-- side by side.
--
-- Zero requires, so it loads during love.conf and under plain Lua for tools
-- and tests.  The active version is a process-global set once at boot from
-- the launcher's column choice (main.lua); it defaults to Red.

local GameVersion = {}

GameVersion.VERSIONS = {
  red = {
    id = "red",
    generation = 1,
    label = "Red",
    displayName = "Pokemon Red",
    launcherName = "Red",       -- game-panel header in the launcher
    sha1 = "ea9bcae617fdf159b045185467ae58b2e4a48b9a",
    manifest = "tools/rom_manifest.json",
    cachePrefix = "",       -- Red owns the cache root (backwards compatible)
    saveSuffix = "",        -- save.lua / save.lua.bak / save.lua.tmp
  },
  blue = {
    id = "blue",
    generation = 1,
    label = "Blue",
    displayName = "Pokemon Blue",
    launcherName = "Blue",
    sha1 = "d7037c83e1ae5b39bde3c30787637ba1d4c48ce2",
    manifest = "tools/rom_manifest_blue.json",
    cachePrefix = "blue/",  -- blue/data/generated, blue/assets/generated
    saveSuffix = "_blue",   -- save_blue.lua / .bak / .tmp
  },
  yellow = {
    id = "yellow",
    generation = 1,
    label = "Yellow",
    displayName = "Pokemon Yellow",
    launcherName = "Yellow (alpha)",
    sha1 = "cc7d03262ebfaf2f06772c1a480c7d9d5f4a38e1",
    manifest = "tools/rom_manifest_yellow.json",
    cachePrefix = "yellow/",  -- yellow/data/generated, yellow/assets/generated
    saveSuffix = "_yellow",   -- save_yellow.lua / .bak / .tmp
  },
  gold = {
    id = "gold",
    generation = 2,
    label = "Gold",
    displayName = "Pokemon Gold",
    launcherName = "Gold (Phase 2B)",
    sha1 = "d8b8a3600a465308c9953dfa04f0081c05bdcb94",
    manifest = "tools/rom_manifest_gold.json",
    cachePrefix = "gold/",
    saveSuffix = "_gold",
  },
  silver = {
    id = "silver",
    generation = 2,
    label = "Silver",
    displayName = "Pokemon Silver",
    launcherName = "Silver (Phase 2B)",
    sha1 = "49b163f7e57702bc939d642a18f591de55d92dae",
    manifest = "tools/rom_manifest_silver.json",
    cachePrefix = "silver/",
    saveSuffix = "_silver",
  },
  -- Crystal is the Rev 1 (v1.1) build, which is what pokecrystal11.sym
  -- describes.  Rev 0 exists but moves three symbols, none of which the
  -- extractor reads -- the hash gate below still pins it to Rev 1 so an
  -- imported ROM can never disagree with the embedded symbol table.
  crystal = {
    id = "crystal",
    generation = 2,
    label = "Crystal",
    displayName = "Pokemon Crystal",
    launcherName = "Crystal (alpha)",
    sha1 = "f2f52230b536214ef7c9924f483392993e226cfb",
    -- Rev 0.  Only three symbols move between the revisions and the extractor
    -- reads none of them, so one manifest and one symbol table serve both --
    -- but the hash still has to be accepted explicitly.
    sha1Alt = { "f4cd194bdee0d04ca4eac29e09b8e4e9d818c133" },
    manifest = "tools/rom_manifest_crystal.json",
    cachePrefix = "crystal/",
    saveSuffix = "_crystal",
  },
}

-- Launcher column order.
GameVersion.ORDER = { "red", "blue", "yellow", "gold", "silver", "crystal" }

GameVersion.current = "red"

function GameVersion.set(id)
  GameVersion.current = GameVersion.VERSIONS[id] and id or "red"
  return GameVersion.current
end

function GameVersion.get()
  return GameVersion.current
end

function GameVersion.generation(id)
  local info = GameVersion.info(id)
  return info and info.generation or 1
end

function GameVersion.isGen1(id)
  return GameVersion.generation(id) == 1
end

function GameVersion.isGen2(id)
  return GameVersion.generation(id) == 2
end

function GameVersion.isBlue()
  return GameVersion.current == "blue"
end

function GameVersion.isYellow()
  return GameVersion.current == "yellow"
end

function GameVersion.isGold()
  return GameVersion.current == "gold"
end

function GameVersion.isSilver()
  return GameVersion.current == "silver"
end

-- Crystal shares the Gen2 engine with Gold/Silver but not its script opcode
-- table, so anything that decodes ROM bytecode has to branch on this.
function GameVersion.isCrystal(id)
  return (id or GameVersion.current) == "crystal"
end

-- Metadata for a version id, defaulting to the active one.
function GameVersion.info(id)
  return GameVersion.VERSIONS[id or GameVersion.current]
end

function GameVersion.saveSuffix(id)
  return GameVersion.info(id).saveSuffix
end

function GameVersion.cachePrefix(id)
  return GameVersion.info(id).cachePrefix
end

-- Does this version accept that ROM hash?  Most versions have exactly one
-- canonical dump; Crystal has two revisions that decode identically here.
function GameVersion.acceptsSha1(id, sha1)
  local info = GameVersion.info(id)
  if not info then return false end
  if info.sha1 == sha1 then return true end
  for _, alt in ipairs(info.sha1Alt or {}) do
    if alt == sha1 then return true end
  end
  return false
end

-- The version a ROM belongs to, by its SHA-1, or nil for an unknown ROM.
function GameVersion.forSha1(sha1)
  for id in pairs(GameVersion.VERSIONS) do
    if GameVersion.acceptsSha1(id, sha1) then return id end
  end
  return nil
end

return GameVersion
