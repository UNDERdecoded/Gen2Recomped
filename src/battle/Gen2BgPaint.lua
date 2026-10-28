-- Gen1Recomp-derived BG paper/clip drawing. GPLv3 plus Additional Terms:
-- compat/gen1-gsc/LICENSE.MD and provenance.json. Uses native indexed colour.
local Palette=require('src.render.Gen2PaletteDraw')
local M={}
-- The GSC battle/menu paper palette from the pinned Gen1 Chrome owner.
local BOX={{255,255,255},{255,255,255},{255,255,255},{0,0,0}}
function M.paletteFill(x,y,w,h)
  local g=love.graphics
  local previous=g.getShader and g.getShader()
  g.setColor(1,1,1,1)
  if Palette.available()then Palette.use(BOX)end
  g.rectangle('fill',x,y,w,h)
  g.setShader(previous)
  g.setColor(0,0,0,1)
end
function M.clipTo(x,y,w,h)
  local g=love.graphics
  if g.transformPoint then
    local x1,y1=g.transformPoint(x,y)
    local x2,y2=g.transformPoint(x+w,y+h)
    x,y=math.floor(math.min(x1,x2)),math.floor(math.min(y1,y2))
    w,h=math.ceil(math.abs(x2-x1)),math.ceil(math.abs(y2-y1))
  end
  if g.intersectScissor then g.intersectScissor(x,y,w,h)
  else g.setScissor(x,y,w,h)end
end
return M
