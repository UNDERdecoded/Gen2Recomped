local M = {}
function M.run(root, backend, version)
  local native = backend == "gen1"
  local V = require("src.core.GameVersion")
  local oldVersion = V.get()
  V.set(version)
  local runtime, oldSession, Song, oldSelected
  if native then
    runtime = require("src.core.game3.runtime")
    oldSession, runtime.session = runtime.session, { version = version }
    Song = require("src.core.game3.song_ids")
    oldSelected = Song.current
    Song.select(version)
  end
  local module = not native and require("src.core.Gen3SongIds")
  local names = native and Song.forVersion(version) or module.names(version)
  local keys = {}
  for key in pairs(names) do
    if key:match("^MUS_") then
      keys[#keys + 1] = key
    end
  end
  table.sort(keys)
  local rows = {}
  local function resolve(value)
    return native and require("src.core.game3.audio").resolveSong(value) or module.resolve(value, version)
  end
  local function record(input)
    rows[#rows + 1] = { input = input, resolved = resolve(input) }
  end
  for _, name in ipairs(keys) do
    local id = names[name]
    record(name)
    record(name:lower())
    record("  " .. name .. "  ")
    record(id)
    record(tostring(id))
    rows[#rows + 1] =
      { input = id, canonical = native and Song.nameOf(id, version) or module.nameOf(id, version) }
  end
  for _, input in ipairs({ "MOD_SONG", " MOD_SONG ", "unknown", "0x116", 0, 0x7FFF, 0xFFFF }) do
    record(input)
  end
  if native then
    runtime.session = oldSession
    Song.select(oldSelected)
  end
  V.set(oldVersion)
  return rows
end
return M
