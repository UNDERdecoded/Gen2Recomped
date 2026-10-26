-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
local D={}
function D.mode(menu)
 local features=package.loaded['src.mods.FeatureOptions']
 if not(features and features.enabled('trainingDetails')and menu.page==2 and not menu.moveSelect and not menu.choose)then return 0 end
 return menu._trainingDetailMode or 0
end
function D.input(menu,input)
 local features=package.loaded['src.mods.FeatureOptions']
 if menu.page~=2 or menu.moveSelect or menu.choose or not(features and features.enabled('trainingDetails'))then return false end
 if input:wasPressed('select')then menu._trainingDetailMode=((menu._trainingDetailMode or 0)+1)%3;return true end
 return false
end
function D.stats(menu)
 local mode=D.mode(menu)
 if mode==0 then return nil end
 return mode==1 and menu.mon.ivs or menu.mon.evs
end
function D.title(menu,title)
 local mode=D.mode(menu);return mode==1 and'IV'or mode==2 and'EV'or title
end
return D
