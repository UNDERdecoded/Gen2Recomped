-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Source text uses the native imported proportional faces and shaders.
local Font=require('src.render.Font')
local Scope=require('src.render.GraphicsScope')
local F={LINE_PITCH=15,GLYPH_HEIGHT=14}
F.COLOR={NORMAL={fg={98/255,98/255,98/255,1},shadow={213/255,213/255,205/255,1}},
  WHITE={fg={1,1,1,1},shadow={98/255,98/255,98/255,1}}}
local function face(opts,fn)
  local name=opts and(opts.font or opts.small and 'small')
  local pushed=type(name)=='string'and Font.hasFace(name)
  if pushed then Font.pushFace(name)end
  local ok,value=pcall(fn)
  if pushed then Font.popFace()end
  if not ok then error(value,0)end
  return value
end
function F.measure(text,opts)
  return face(opts,function()
    local max=0
    for line in(tostring(text or'')..'\n'):gmatch('(.-)\n')do max=math.max(max,Font.width(line)+math.max(0,#Font.split(line)-1)*(opts and opts.letterSpacing or 0))end
    return max
  end)
end
function F.draw(text,x,y,opts)
  opts=opts or{}
  local ok,value=Scope.call(function()return face(opts,function()
    local colors=opts.colors or F.COLOR.NORMAL
    local toned=Font.beginTwoTone(opts.color or colors.fg or F.COLOR.NORMAL.fg,colors.shadow or F.COLOR.NORMAL.shadow)
    local good,width=pcall(function()
      local max,lineY,count=0,y,0
      for line in(tostring(text or'')..'\n'):gmatch('(.-)\n')do
        local xx=x
        for _,span in ipairs(Font.split(line))do
          if opts.limitChars and count>=opts.limitChars then break end
          local glyph=line:sub(span.from,span.to);local advance=Font.width(glyph)
          if not opts.maxWidth or xx-x+advance<=opts.maxWidth then Font.draw(glyph,xx,lineY)end
          xx=xx+advance+(opts.letterSpacing or 0);count=count+1
        end
        max=math.max(max,xx-x-(#Font.split(line)>0 and(opts.letterSpacing or 0)or 0));lineY=lineY+(opts.linePitch or F.LINE_PITCH)
      end
      return max
    end)
    if toned then Font.endTwoTone()end
    if not good then error(width,0)end
    return width
  end)end)
  if not ok then error(value,0)end
  return value
end
setmetatable(F,{__index=function(_,k)if k=='_spec'then return{nativeLayout=require('src.core.GameVersion').isFRLG()and'frlg'or'rs'}end end})
return F
