-- Imported field artwork, without allocating images or observing an actor.
-- Names describe identified native records; unavailable effects stay absent.
local M={}
local function integer(n,lo,hi)
  return type(n)=='number'and n==n and n%1==0 and n>=lo and n<=hi
end
function M.record(row)
  if type(row)~='table'then return nil end
  local path=row.image or row.path
  local w,h,n=row.frameWidth,row.frameHeight,row.frames
  if type(path)~='string'or#path==0 or#path>1024 or not integer(w,8,128)
      or not integer(h,8,128)or not integer(n,1,256)or w*h*n>1048576 then return nil end
  return {path=path,fw=w,fh=h,frames=n}
end
function M.records(data)
  local c=type(data)=='table'and data.constants or{};local out={}
  for name,key in pairs({tall_grass='gen3TallGrass',surf_blob='gen3SurfBlob',fly_bird='gen3FRLGFlyBird'})do
    out[name]=M.record(c[key])
  end
  for name,key in pairs({ripple='gen3Ripple',sparkle='gen3Sparkle'})do
    local set=c[key];local row=set and data.sprites and data.sprites[set.key]
    if row and row.trueColor==true and not row.big and not row.monIcon then out[name]=M.record(row)end
  end
  -- Native emote strips have independent geometry/order. Do not concatenate
  -- them into an assumed fifteen-frame source strip.
  for _,name in ipairs({'exclamation','question','heart'})do
    local row=c.gen3Emotes and c.gen3Emotes[name]
    if row then out['emote_'..name]=M.record({image=row.image,frameWidth=row.width,
      frameHeight=row.height,frames=row.frames})end
  end
  return out
end
return M
