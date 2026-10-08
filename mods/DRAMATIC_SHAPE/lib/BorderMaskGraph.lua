-- Reciprocal drawing masks use the engine's actual placements, including
-- bodies reached through a one-way link or a detour outside the ring reach.
local Graph={}
function Graph.build(maps,compute)
  local out={}
  local function add(id,def,x,y)
    out[id]=out[id] or {}
    local px=tonumber(def.blockPx) or 32
    local rect={x,y,x+def.width*px,y+def.height*px}
    for _,r in ipairs(out[id])do
      if r[1]==rect[1] and r[2]==rect[2] and r[3]==rect[3] and r[4]==rect[4]then return end
    end
    out[id][#out[id]+1]=rect
  end
  for id,def in pairs(maps)do
    if type(def)=="table" and def.width and def.height then
      out[id]=out[id] or {}
      for _,n in ipairs(compute(maps,id,2,96,96))do
        local dest=maps[n.id]
        if dest and dest.width and dest.height then
          add(id,dest,n.ox,n.oy)
          add(n.id,def,-n.ox,-n.oy)
        end
      end
    end
  end
  for _,list in pairs(out)do
    table.sort(list,function(a,b)
      for i=1,4 do if a[i]~=b[i] then return a[i]<b[i] end end
      return false
    end)
  end
  return out
end
return Graph
