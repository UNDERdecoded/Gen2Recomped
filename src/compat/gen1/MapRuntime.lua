-- Compatibility map observations over one native session. Never loads a map,
-- runs a script/player, or lends native definitions to compatibility writers.
local Identity = require('src.compat.gen1.MapIdentity')
local PairIdentity = require('src.compat.gen1.PairIdentity')
local Views = require('src.compat.gen1.MapViews')
local Version = require('src.core.GameVersion')
local Connections = require('src.core.game3.connections')
local M = {}
local mapTypes = {NONE=0,TOWN=1,CITY=2,ROUTE=3,UNDERGROUND=4,UNDERWATER=5,OCEAN_ROUTE=6,UNKNOWN=7,INDOOR=8,SECRET_BASE=9}
local function numericBoolean(v) if v == nil then return nil end; return (v == true or v == 1) and 1 or 0 end
local function copy(v)
  if type(v) ~= 'table' then return v end
  local out = {}; for k, value in pairs(v) do out[k] = copy(value) end; return out
end
local overworld=require('src.compat.gen1.NativeSession').world
function M.new(getGame, getEdition)
  assert(type(getGame)=='function' and type(getEdition)=='function','native session resolvers required')
  local handle = {}
  local views = Views.new(getGame,getEdition)
  local observing=false
  local owner,data,nativeMaps,edition,binding,pairBinding,epoch
  local maps,known,published,loaded = {},setmetatable({},{__mode='k'}),{},{}
  local ended,allIndexed = false,false
  local function clear()
    if observing or ended then
      views:release();views=not ended and Views.new(getGame,getEdition)or nil;observing=false
    end
    if pairBinding then pairBinding:release() end
    owner,data,nativeMaps,edition,binding,pairBinding,epoch=nil,nil,nil,nil,nil,nil,nil
    maps,known,published,loaded={},setmetatable({},{__mode='k'}),{},{}
    allIndexed=false
  end
  local function session()
    if ended then return nil,'map runtime released' end
    local game,id=getGame(),getEdition()
    local info=Version.info(id)
    if type(game)~='table' or not info or info.generation~=3 or not Identity.lookup(id,0,0)
        or type(game.data)~='table' or type(game.data.maps)~='table' then
      clear();return nil,'no native GBA session'
    end
    if game~=owner or data~=game.data or nativeMaps~=game.data.maps or edition~=id then
      clear();owner,data,nativeMaps,edition=game,game.data,game.data.maps,id
      binding=Identity.bind(nativeMaps,id);epoch={}
      if type(data.tilesets)=='table' and type(data.map_tilesets)=='table' then
        pairBinding=PairIdentity.bind(data.tilesets,data.map_tilesets,id)
      end
    end
    return game
  end
  local function resolve(id)
    local native,def=binding:nativeId(id)
    if not native then
      local canonical=binding:legacyId(id)
      if canonical then native,def=binding:nativeId(canonical) end
    end
    if native then return native,def,binding:legacyId(native) end
    return nil,'map identity unavailable or retired'
  end
  local function destination(id)
    local canonical=binding:legacyId(id)
    if canonical then return canonical end
    if type(id)=='string' then
      local g,n=id:match('^MAP_G(%d+)_N(%d+)$')
      if g then return Identity.lookup(edition,tonumber(g),tonumber(n)) end
      return Identity.lookup(edition,id)
    end
  end
  function handle:definition(id)
    local game,why=session();if not game then return nil,why end
    local native,def,canonical=resolve(id);if not native then return nil,def end
    local prior=maps[canonical]
    if prior then return prior end
    local pair=pairBinding and pairBinding:descriptor(def.tileset)
    if not pair or type(pair.tileset)~='string'then return nil,'source tileset pair identity unavailable' end
    local kind=mapTypes[def.mapType] or tonumber(def.mapType) or 0
    local indoor=kind==4 or kind==8 or kind==9
    local rows={}
    for _,row in ipairs(def.sourceConnections or {})do
      local target=destination(row.map)
      if not target then return nil,'connection identity unavailable' end
      rows[#rows+1]={dir=row.dir,map=target,offset=row.offset}
    end
    if def.connections and next(def.connections) and not def.sourceConnections then
      return nil,'original connection order unavailable'
    end
    local warps={}
    for _,row in ipairs(def.warps or {})do
      local converted=copy(row);converted.nativeDestination=row.destMap;converted.destMap=destination(row.destMap)
      if not converted.destMap and type(row.destMap)=='string' then
        local g,n=row.destMap:match('^MAP_G(%d+)_N(%d+)$')
        converted.mapGroup,converted.mapNum=tonumber(g),tonumber(n)
      end
      warps[#warps+1]=converted
    end
    local cycling,escaping,running=numericBoolean(def.allowCycling),numericBoolean(def.allowEscaping),numericBoolean(def.allowRunning)
    local show=numericBoolean(def.showMapName)or 0
    local flags=tonumber(def.flags)
    if edition=='ruby'or edition=='sapphire'then
      -- RS policies are type-based; byte 26 is the source name-popup value,
      -- not Emerald's permission bit field. Preserve native state separately.
      cycling=(kind~=8 and kind~=9 and kind~=5)and 1 or 0
      local name=canonical:sub(4)
      if name=='ROUTE110_SEASIDE_CYCLING_ROAD_SOUTH_ENTRANCE'or name=='ROUTE110_SEASIDE_CYCLING_ROAD_NORTH_ENTRANCE'then cycling=1 end
      if name=='SEAFLOOR_CAVERN_ROOM9'or name=='CAVE_OF_ORIGIN_B4F'then cycling=0 end
      escaping=kind==4 and 1 or 0;running=kind==8 and 0 or 1
      if flags then show=flags==1 and 1 or 0 end
    elseif flags then
      local shift=(edition=='firered'or edition=='leafgreen')and 4 or 8
      show=math.floor(flags/shift)==1 and 1 or 0
    end
    local view={id=canonical,name=canonical,nativeId=native,nativePair=def.tileset,
      width=def.width,height=def.height,kind=indoor and 'indoor' or (kind==3 and 'route' or 'town'),
      environment=indoor and 'INDOOR' or (kind==3 and 'ROUTE' or 'TOWN'),pair=pair.id,tileset=pair.tileset,
      connections=rows,warps=warps,regionMapSectionId=def.regionMapSection,
      showMapName=show,floorNum=def.floorNum or 0,
      weather=def.weather or 0,mapType=kind,cave=numericBoolean(def.cave),
      allowEscaping=escaping,allowRunning=running,
      bikingAllowed=cycling,battleType=def.battleScene,music=def.music,
      borderWidth=def.sourceBorderWidth,borderHeight=def.sourceBorderHeight,native=true}
    for _,row in ipairs(rows)do
      if row.dir=='dive'or row.dir=='emerge'then view[row.dir]={map=row.map,offset=tonumber(row.offset)or 0}end
    end
    local weak=setmetatable({handle},{__mode='v'});local generation=epoch
    setmetatable(view,{__index=function(_,key)
      local runtime=weak[1]
      if key=='midLayout' and runtime then return runtime:layout(canonical,view,generation) end
    end})
    known[view]=generation;maps[canonical]=view
    return view
  end
  function handle:layout(id,def,generation)
    local game,why=session();if not game then return nil,why end
    if def and (known[def]~=epoch or (generation and generation~=epoch))then
      return nil,'owned map definition retired'
    end
    if not def then def,why=self:definition(id);if not def then return nil,why end end
    observing=true
    local view;view,why=views:map(id);if not view then return nil,why end
    local prior=published[def.id]
    if prior~=view then
      local previous=prior and prior.midLayout
      view.midLayout.pair=def.pair
      view.midLayout._revision=math.max(view.revision,(previous and previous._revision or 0)+1)
      published[def.id]=view
    end
    loaded[def.id]=true
    return view.midLayout
  end
  function handle:definitions()
    local game,why=session();if not game then return nil,why end
    if allIndexed then return maps end
    for key in pairs(nativeMaps)do
      local canonical=binding:legacyId(key)
      if canonical then
        local def,err=self:definition(canonical);if not def then return nil,err end
      end
    end
    allIndexed=true
    return maps
  end
  function handle:current()
    local game,why=session();if not game then return nil,why end
    local ow=overworld(game)
    if not (ow and ow.map and nativeMaps[ow.map.id]==ow.map.def)then
      allIndexed=false;views:current();return nil,'no active native map'
    end
    local def;def,why=self:definition(ow.map.id);if not def then return nil,why end
    local layout;layout,why=self:layout(def.id,def);if not layout then return nil,why end
    return def
  end
  function handle:neighbors(def)
    def=def or self:current()
    if not def or known[def]~=epoch then return {},{} end
    local list,byDir={},{}
    for _,row in ipairs(def.connections or {})do
      local target=self:definition(row.map)
      if target and Connections.cardinal(row.dir) then
        local layout=self:layout(row.map,target)
        if layout then
          local record={dir=row.dir,map=row.map,mapId=row.map,offset=row.offset,def=target}
          list[#list+1]=record;byDir[row.dir]=byDir[row.dir]or record
        end
      end
    end
    return byDir,list
  end
  function handle:loadedCount()
    local n=0;for _ in pairs(loaded)do n=n+1 end;return n
  end
  function handle:invalidate(id)
    local game=session();if not game then return end
    views:invalidate(id)
    if id==nil then clear() end
  end
  function handle:isOwned(def) session();return epoch~=nil and known[def]==epoch end
  function handle:loadedLayouts() session();return loaded end
  function handle:release()
    if ended then return end
    ended=true;clear();getGame,getEdition=nil,nil
  end
  return handle
end
return M
