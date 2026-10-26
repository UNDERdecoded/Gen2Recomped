-- RS class ordinals differ from Emerald. Older relocated caches retained
-- Emerald's default pair; resolve only that known inherited profile, leaving
-- explicitly authored class profiles alone.
local M={}
function M.classes(edition,classes)
  classes=classes or{}
  if(edition=='ruby'or edition=='sapphire')and classes.eliteFour==31 and classes.champion==38 then
    return{eliteFour=24,champion=32,magma={},aqua={}}
  end
  return classes
end
return M
