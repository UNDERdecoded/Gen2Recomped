-- Single source of every compatibility-relevant number: engine release,
-- mod API major, link protocol, save format and ROM cache generation.  Zero
-- requires so it loads during love.conf and under plain Lua for tools and
-- tests.

local Version = {
  engine = "0.5.1",       -- game/engine release (semver).  CI restamps this in
                          -- the packed game.love; the working tree carries the
                          -- release it is building towards.
  shell = 1,              -- native-shell contract this build implements
  minShell = 1,           -- lowest shell contract that can RUN this payload.
                          -- Bump only when a payload needs a newer native
                          -- binary (e.g. a LOVE version bump); an older shell
                          -- refuses to chainload a payload whose minShell
                          -- exceeds the shell it provides.
  modApi = 2,             -- mod API major (manifest `api`)
  linkProtocol = 2,       -- link handshake wire version (Handshake.PROTOCOL)
  saveFormat = 4,         -- save.meta.format
  cache = "rom-cache-v5", -- ROM import cache generation (RomImporter marker)
}

-- "gen2recomp v0.5.1" (or the stamped release version in shipped builds)
function Version.title(base)
  return (base or "gen2recomp")
    .. " v" .. Version.engine
end

return Version
