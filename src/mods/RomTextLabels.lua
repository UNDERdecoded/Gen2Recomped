-- Exact import-symbol facts are loaded only when a native prose consumer or
-- registry needs them. Never identify a label by matching its rendered words.
local Labels = {}
local cache = {}
local supported = { gold = true, silver = true, crystal = true }
function Labels.forVersion(version)
  if not supported[version] then
    return nil
  end
  if not cache[version] then
    cache[version] = require("src.mods.rom_text_labels." .. version)
  end
  return cache[version]
end
return Labels
