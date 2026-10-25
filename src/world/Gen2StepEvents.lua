-- Native Gen2 per-footfall state shared by world phases. Save fields remain
-- those consumed by the existing native commands and breeding/poison code.
local Version = require('src.core.GameVersion')
local Flags = require('src.script.Gen2Flags')
local PhoneService = require('src.world.Gen2PhoneService')
local StepEvents = {}
function StepEvents.vanilla()
  local id=Version.get()
  return id=='gold' or id=='silver' or id=='crystal'
end
function StepEvents.matches(visit,world,game)
  return visit and visit.mapId==world.map.id and visit.save==game.save
    and visit.data==game.data and visit.serial==world.cellSerial
end
function StepEvents.visit(world,game)
  return {mapId=world.map.id,save=game.save,data=game.data,serial=world.cellSerial,blocked=false}
end
function StepEvents.bikeStep(save,state,def)
  if not StepEvents.vanilla() or state~='bike' or not PhoneService.available(def) then return false end
  local key=Flags.engineFlag(19) -- same named flag native setflag writes (Crystal raw index 20)
  if not (save.flags and save.flags[key]) then return false end
  save.g2BikeSteps=math.min((save.g2BikeSteps or 0)+1,0xffff)
  if save.g2BikeSteps<1024 or save.g2SpecialCall~=nil then return false end
  save.g2SpecialCall=6 -- SPECIALCALL_BIKESHOP; dispatched through the imported native phone program
  save.flags[key]=nil
  return true -- arming is not CountStep's carry; it rings on the following footfall
end
return StepEvents
