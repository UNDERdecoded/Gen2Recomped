-- Run:  texlua tools/gen4_scripts_reextract.lua <platinum .nds> <cache dir>
--
-- Re-decodes Platinum's scripts and rewrites ONLY `map_scripts.lua` in an
-- EXISTING cache -- for when Gen4ScriptOps learns a command's real width (as
-- `givepoffin` did) and the decoded scripts behind it need walking again,
-- without a full re-import. Every other stage's output is discarded.

package.path = './?.lua;./?/init.lua;' .. package.path
love = love or {}

local romPath, cacheDir = arg and arg[1], arg and arg[2]
if not (romPath and cacheDir) then
  print('usage: texlua tools/gen4_scripts_reextract.lua <platinum .nds> <cache dir>')
  os.exit(2)
end
cacheDir = cacheDir:gsub('[/\\]$', '')

-- the map stage also encodes images; nothing but the scripts is kept
require('src.import.CacheFs').write = function() return true end
local X = require('src.import.RomExtractorGen4')
local ex = assert(X.new(romPath, 'platinum', {}, function() end))
local LuaWriter = require('src.import.LuaWriter')
ex.write = function(self, name, value)
  self.wrote[#self.wrote + 1] = name
  if name == 'map_scripts' then
    local f = assert(io.open(cacheDir .. '/map_scripts.lua', 'wb'))
    f:write(LuaWriter.encodeSplit(value))
    f:close()
  end
end
ex:extractText()
local headers, names = ex:extractMaps()
local events = ex:extractEvents()
ex:extractScripts()
ex:linkScripts(headers, events, names)
local n = 0
for _ in pairs(ex._scripts or {}) do n = n + 1 end
print(('rewrote %s/map_scripts.lua: %d script blocks'):format(cacheDir, n))
