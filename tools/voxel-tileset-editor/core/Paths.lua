-- Finding the game, its ROM cache, and the voxel mod that actually runs.
--
-- THE SAVE-DIRECTORY COPY SHADOWS THE GAME FOLDER, FILE BY FILE.  This is
-- the single most expensive fact about this project and it is why this file
-- exists: an installed mod lives in the player's save directory, the repo
-- copy lives in the game folder, PhysFS searches the save directory first,
-- and so `lib/ChunkMesher.lua` can come from one tree while
-- `lib/TileShape.lua` comes from the other.  An editor that reads only the
-- repo copy previews a mod nobody is running.
--
-- So `Paths.modFile(root, rel)` resolves ONE FILE at a time against an
-- ordered list of roots, exactly as PhysFS does, and reports which root
-- answered.  The overlay is visible in the UI for the same reason.

local Fs = require("core.Fs")

local Paths = {}

Paths.GAME_IDENTITY = "Gen2Recomp"

-- The LOVE appdata root for the HOST game, not for this editor.  love.filesystem
-- .getAppdataDirectory() is the platform's app-data root; the game's save
-- directory is <that>/LOVE/<identity> on Windows and Linux, and
-- <home>/Library/Application Support/LOVE/<identity> on macOS.
function Paths.candidateSaveDirs(identity)
  identity = identity or Paths.GAME_IDENTITY
  local out = {}
  local function add(p) if p and p ~= "" then out[#out + 1] = Fs.join(p) end end

  if love and love.filesystem and love.filesystem.getAppdataDirectory then
    local appdata = love.filesystem.getAppdataDirectory()
    add(Fs.join(appdata, "LOVE", identity))
    add(Fs.join(appdata, identity))
  end
  local env = os.getenv("APPDATA")
  if env then add(Fs.join(env, "LOVE", identity)) end
  local home = os.getenv("HOME")
  if home then
    add(Fs.join(home, ".local/share/love", identity))
    add(Fs.join(home, "Library/Application Support/LOVE", identity))
    add(Fs.join(home, ".love", identity))
  end
  return out
end

-- A cache root is a directory holding data/generated/tilesets.lua.  There
-- can be several: the un-prefixed one at the save root is the ACTIVE
-- cartridge, and each <version>/ subtree beside it is one the player has
-- extracted before (crystal/, gold/, emerald/ ...).  All of them are
-- offered, because a tileset only exists in the cache of the cartridge it
-- came from and an editor that shows one is an editor for one game.
Paths.VERSION_DIRS = {
  "", "crystal", "gold", "silver", "prism", "polishedcrystal", "emerald",
  "red", "blue", "yellow",
}

function Paths.cacheRoots(saveDir)
  local out = {}
  for _, v in ipairs(Paths.VERSION_DIRS) do
    local root = v == "" and saveDir or Fs.join(saveDir, v)
    if Fs.exists(Fs.join(root, "data/generated/tilesets.lua")) then
      out[#out + 1] = { root = root, version = v == "" and "active" or v }
    end
  end
  return out
end

-- Every place a mod called `id` might be, most authoritative first.  The
-- save directory beats the game folder because PhysFS mounts it first --
-- that is the shadowing rule, and getting it backwards is how an editor
-- shows the wrong shapes with total confidence.
function Paths.modRoots(saveDir, gameDir, id)
  local roots = {}
  if saveDir then roots[#roots + 1] = Fs.join(saveDir, "mods", id) end
  if gameDir then roots[#roots + 1] = Fs.join(gameDir, "mods", id) end
  return roots
end

-- Resolve one file across the overlay.  Returns absolute path, root index.
function Paths.overlayFile(roots, rel)
  for i, root in ipairs(roots) do
    local p = Fs.join(root, rel)
    if Fs.exists(p) then return p, i, root end
  end
  return nil
end

-- Walk up from a starting directory looking for the game checkout: the
-- folder holding both `conf.lua` and `mods/`.  The editor normally lives in
-- <game>/tools/voxel-tileset-editor, so two levels up is the usual answer,
-- but it must work when someone copies it elsewhere too.
function Paths.findGameDir(start)
  local dir = Fs.join(start or ".")
  for _ = 1, 6 do
    if Fs.exists(Fs.join(dir, "conf.lua"))
       and Fs.exists(Fs.join(dir, "mods/DRAMATIC_SHAPE/manifest.json")) then
      return dir
    end
    local up = Fs.dirname(dir)
    if up == dir or up == "" then break end
    dir = up
  end
  return nil
end

-- Everything the editor needs to know about where things are, resolved
-- once and reported as data so the UI can show it and a settings file can
-- override any part of it.
function Paths.discover(overrides)
  overrides = overrides or {}
  local out = {
    saveDir = overrides.saveDir,
    gameDir = overrides.gameDir,
    modId = overrides.modId or "DRAMATIC_SHAPE",
    notes = {},
  }

  if not out.saveDir then
    for _, d in ipairs(Paths.candidateSaveDirs(overrides.identity)) do
      if Fs.exists(Fs.join(d, "options.lua"))
         or Fs.exists(Fs.join(d, "data/generated/tilesets.lua"))
         or Fs.exists(Fs.join(d, "mods")) then
        out.saveDir = d
        break
      end
    end
  end

  if not out.gameDir then
    local here = love and love.filesystem and love.filesystem.getSource
        and love.filesystem.getSource() or "."
    out.gameDir = Paths.findGameDir(here)
        or Paths.findGameDir(Fs.dirname(Fs.dirname(here)))
  end

  out.cacheRoots = out.saveDir and Paths.cacheRoots(out.saveDir) or {}
  if out.gameDir and #out.cacheRoots == 0 then
    -- a portable install keeps the cache in the game folder itself
    if Fs.exists(Fs.join(out.gameDir, "data/generated/tilesets.lua")) then
      out.cacheRoots[1] = { root = out.gameDir, version = "portable" }
    end
  end

  out.modRoots = Paths.modRoots(out.saveDir, out.gameDir, out.modId)
  local present = {}
  for _, r in ipairs(out.modRoots) do
    if Fs.exists(Fs.join(r, "main.lua")) or Fs.exists(Fs.join(r, "lib")) then
      present[#present + 1] = r
    end
  end
  out.modRoots = present

  if #out.cacheRoots == 0 then
    out.notes[#out.notes + 1] =
      "no ROM cache found -- run the game once so it extracts a cartridge"
  end
  if #out.modRoots == 0 then
    out.notes[#out.notes + 1] =
      "no " .. out.modId .. " install found -- shapes fall back to the built-in table"
  end
  return out
end

return Paths
