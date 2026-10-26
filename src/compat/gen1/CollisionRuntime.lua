-- Source observations and native permission queries have different alphabets:
-- classified COLL bytes are views; actual entry permission stays native.
local Session=require('src.compat.gen1.NativeSession')
local Map=require('src.core.game3.map')
local Tiles=require('src.render.Gen3Tiles')
local Behavior=require('src.compat.gen1.MetatileBehavior')
local Version=require('src.core.GameVersion')
local Native=require('src.world.Collision')
local M={}
local function integer(v)return type(v)=='number'and v==v and math.abs(v)<math.huge and v%1==0 end
local directions={up=true,down=true,left=true,right=true}
function M.new()
  local readers=setmetatable({},{__mode='k'})
  local grids=setmetatable({},{__mode='k'})
  local runtime={}
  local function context(game)
    local g,w,p=Session.resolve(game);if not g then return nil,w end
    local maps,why=Map._context(g);if not maps then return nil,why end
    return g,w,p,maps
  end
  function runtime:current(game)
    local g,_,_,maps=context(game);if not g then return nil end
    return maps:current()
  end
  function runtime:behaviorMid(def,mid,game)
    if not(integer(mid)and mid>=0 and mid<1024)then return nil end
    local g,_,_,maps=context(game);if not g or not maps:isOwned(def)then return nil end
    local native=g.data.maps[def.nativeId]
    local pair=native and g.data.tilesets[native.tileset]
    local sets=g.data.map_tilesets
    local a=pair and sets and sets[pair.primaryKey]
    local b=pair and sets and sets[pair.secondaryKey]
    local geometry=g.data.constants and g.data.constants.gen3Layout
    if not(a and b and geometry)then return nil end
    local cached=readers[pair]
    if not cached or cached.primary~=a or cached.secondary~=b or cached.geometry~=geometry
        or cached.split~=geometry.metatilesInPrimary then
      cached={primary=a,secondary=b,geometry=geometry,split=geometry.metatilesInPrimary,
        reader=Tiles.new({primary=a,secondary=b},geometry)}
      readers[pair]=cached
    end
    local raw=cached.reader:sourceBehavior(mid)
    return raw~=nil and Behavior.fromRaw(Version.get(),raw)or nil
  end
  function runtime:behavior(def,x,y,game)
    if not(integer(x)and integer(y))then return nil end
    local layout=def and def.midLayout
    if not layout or x<0 or y<0 or x>=layout.width or y>=layout.height then return nil end
    return self:behaviorMid(def,layout:midAt(x,y),game)
  end
  function runtime:grid(game)
    local def=self:current(game);local layout=def and def.midLayout
    if not layout then return nil end
    local cached=grids[layout]
    if not cached or cached.revision~=layout._revision then
      cached={revision=layout._revision,cells=layout:collArray()};grids[layout]=cached
    end
    return cached.cells
  end
  function runtime:canEnter(game,x,y,opts)
    if not(integer(x)and integer(y))then return false,'bounds'end
    local g,w,p=Session.resolve(game);if not g then return false,'bounds'end
    opts=opts or {}
    local fx,fy=opts.fromX or p.cellX,opts.fromY or p.cellY
    if not(integer(fx)and integer(fy))then return false,'bounds'end
    local direction=opts.dir
    if direction~=nil and not directions[direction]then return false,'direction'end
    if not direction then
      if fx==x and fy~=y then direction=y>fy and'down'or'up'
      elseif fy==y and fx~=x then direction=x>fx and'right'or'left'end
    end
    local elevation=opts.elevation
    if elevation==nil then elevation=p.elevation end
    local surfing=opts.surfing
    if surfing==nil then surfing=p.surfing end
    local cast=w.cast or w.entities or {}
    local mover=p
    if fx~=p.cellX or fy~=p.cellY or elevation~=p.elevation or surfing~=p.surfing then
      mover={};for k,v in pairs(p)do mover[k]=v end
      mover.cellX,mover.cellY,mover.elevation,mover.surfing=fx,fy,elevation,surfing
      local filtered={}
      for _,entity in ipairs(cast)do
        if entity~=p and entity.of~=p then filtered[#filtered+1]=entity end
      end
      cast=filtered
    end
    return Native.mayEnter(w.map,cast,mover,x,y,direction)
  end
  function runtime:release()
    readers=setmetatable({},{__mode='k'});grids=setmetatable({},{__mode='k'})
  end
  return runtime
end
return M
