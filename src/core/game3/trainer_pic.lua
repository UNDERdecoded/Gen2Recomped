-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Trainer artwork is resolved from native imported records, with owned images.
local Native=require('src.compat.gen1.NativeSession')
local Assets=require('src.render.Assets')
local Version=require('src.core.GameVersion')
local P={}
local current,cache,users
local function release()
 for _,row in pairs(cache or{})do if row.image and row.image.release then row.image:release()end end
 current,cache,users=nil,{},{}
end
release()
local function context()
 local g=Native.game();if not g then release();return end
 if not current or current.game~=g or current.data~=g.data or current.loader~=g.mods or current.edition~=Version.get()then
  release();current={game=g,data=g.data,loader=g.mods,edition=Version.get()}
 end
 local host=package.loaded['src.mods.Runtime'];local facade=package.loaded['src.core.Game3']
 local who=host and host.currentMod or facade and facade._callbackOwner();if who then users[who]=true end
 return g
end
local function image(path)
 if type(path)~='string'then return nil,'native trainer picture unavailable'end
 if cache[path]then return cache[path]end
 local ok,img=pcall(love.graphics.newImage,Assets.resolve(path))
 if not ok then return nil,tostring(img)end
 local w,h=img:getDimensions();local row={image=img,w=w,h=h,frames=math.max(1,math.floor(h/64))}
 cache[path]=row;return row
end
function P.front(id)
 local g=context();if not g then return nil,'no native GBA owner'end
 assert(type(id)=='number'and id%1==0 and id>=0,'invalid trainer picture id')
 local c=g.data.constants;local path=c.gen3TrainerFront and c.gen3TrainerFront[id]
 if not path then
  for _,r in pairs(g.data.trainers or{})do if r.picIndex==id and type(r.pic)=='string'then
   assert(path==nil or path==r.pic,'ambiguous native trainer picture');path=r.pic
  end end
  for _,r in pairs(g.data.field and g.data.field.playerForms or{})do if r.picIndex==id then path=r.intro or r.card or path end end
 end
 return image(path)
end
function P.back(gender)
 local g=context();if not g then return nil,'no native GBA owner'end
 assert(gender==0 or gender==1,'invalid player gender')
 local record=g.data.constants.gen3TrainerBack;local who=gender==1 and'girl'or'boy'
 local index=record and record.player and record.player[who]
 return image(record and record.images and record.images[index])
end
function P.backAnims(gender)
 local g=context();if not g then return nil,'no native GBA owner'end
 assert(gender==0 or gender==1,'invalid player gender')
 local r=g.data.constants.gen3TrainerBack;local id=r and r.player and r.player[gender==1 and'girl'or'boy']
 local row=r and r.anims and r.anims[id]
 return row and require('src.mods.Merge').deepCopy(row)
end
local service={release=release,poll=function()if current then context()end end,
 releaseOwner=function(_,who)if users[who]then users[who]=nil;if not next(users)then release()end end end}
P._service=service
require('src.core.game3.asset_stream').register(service);Assets.register(release)
return P
