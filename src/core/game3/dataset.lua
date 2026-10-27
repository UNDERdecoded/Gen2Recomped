-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Read imported artifacts through the native cache filesystem. Hydration,
-- importing and save writes remain with the native data/session owners.
local Native=require('src.compat.gen1.NativeSession')
local Version=require('src.core.GameVersion')
local CacheFs=require('src.import.CacheFs')
local D={}
local records=setmetatable({},{__mode='k'})
local current,currentHandle
local function retire(c)c.retired=true;c.game,c.data,c.root=nil,nil,nil end
local function valid(c)
 local game=Native.game()
 if c.retired then return false end
 if game~=c.game or not game or game.data~=c.data or Version.get()~=c.edition or CacheFs.root()~=c.root then
  retire(c);return false
 end
 return true
end
local function path(value)
 if type(value)~='string'or#value>512 or value:find('[%c\\:]')or value:find('..',1,true)
  or value:find('//',1,true)then return nil end
 if not(value:match('^data/generated/[%w_./%-]+$')or value:match('^assets/generated/[%w_./%-]+$'))then return nil end
 return value
end
function D.cache()
 local game=Native.game();local data=game and game.data;local edition=Version.get();local root=CacheFs.root()
 if current and current.game==game and current.data==data and current.edition==edition and current.root==root and not current.retired then
  return currentHandle
 end
 if current then retire(current)end
 local c={game=game,data=data,edition=edition,root=root,prefix=Version.cachePrefix()}
 local h={};records[h]=c;current,currentHandle=c,h
 function h:read(name)
  local relative=path(name)
  if not relative then return nil,'invalid imported artifact path'end
  if not valid(c)then return nil,'native imported artifact cache retired'end
  local bytes,why=CacheFs.dataFs().read(c.prefix..relative)
  return type(bytes)=='string'and bytes or nil,why
 end
 function h:exists(name)
  local relative=path(name)
  if not relative or not valid(c)then return false end
  local info=CacheFs.dataFs().getInfo(c.prefix..relative,'file')
  return info~=nil and info.type=='file'
 end
 return h
end
D._service={release=function()
 for _,c in pairs(records)do retire(c)end;current,currentHandle=nil,nil
end,poll=function()for _,c in pairs(records)do valid(c)end end}
require('src.core.game3.asset_stream').register(D._service)
return D
