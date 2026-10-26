-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
local Features=require('src.mods.FeatureOptions')
local E={attach=Features.attach,enabled=Features.enabled}
function E.text(en,de)
 local p=Features.provider('quickBall')or Features.provider('repelPrompt')or Features.provider('trainingDetails')or Features.provider('timedEncounters')
 return p and Features.call(p,'language')=='de'and de or en
end
function E.encounterTable(mapId,source)
 local g=require('src.compat.gen1.NativeSession').game();if not g then return source end
 local maps=require('src.core.game3.map')._context(g);local def=maps and maps:definition(mapId)
 if not def then return source end
 local native=g.data.maps[def.nativeId]
 if source and source.grass then return require('src.world.EncounterActivity').forMap(g.data,g.save,native,def.nativeId,source)end
 local p=Features.provider('timedEncounters')
 if not(p and source and source.land and Features.call(p,'outdoors',mapId)==true)then return source end
 local out={};for k,v in pairs(source)do out[k]=v end
 out.land=require('src.world.EncounterActivity').reweight(source.land,require('src.world.EncounterActivity').phase(Features.call(p,'time')),
  require('src.core.game3.pokemon').national,g.data.constants.encounterActivity)
 return out
end
return E
