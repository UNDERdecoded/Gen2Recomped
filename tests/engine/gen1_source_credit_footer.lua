-- Native launcher draw and scroll owners; only the graphics device is stubbed.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local run=T.sdk.loadNone({data=T.fixtures.fresh(),fs=T.sdk.memfs({})})
love.system=love.system or {}
love.system.getOS=function()return 'Unknown'end
local Importer=require('src.import.RomImporter')
local g=love.graphics
local dimensions,printf,setFont=g.getDimensions,g.printf,g.setFont
local widthFn,heightFn,safeArea=g.getWidth,g.getHeight,love.window.getSafeArea
local mesh,shader,image,newFont=g.newMesh,g.newShader,g.newImage,g.newFont
local oldImage=love.image
local mouseDown=love.mouse.isDown
love.mouse.isDown=function()return false end
local function noop()end
local ellipse,arc,polygon=g.ellipse,g.arc,g.polygon
g.ellipse,g.arc,g.polygon=noop,noop,noop
local stencil,stencilTest=g.stencil,g.setStencilTest
g.stencil=function(fn)fn()end
g.setStencilTest=noop
g.newMesh=function()return {release=noop,setVertices=noop}end
g.newShader=function()return {send=noop,release=noop}end
love.image={newImageData=function(w,h)return {w=w,h=h,setPixel=noop}end}
g.newImage=function(source)
  local obj=type(source)=='table'and {w=source.w,h=source.h}or image(source)
  obj.setWrap,obj.setFilter,obj.setMipmapFilter=noop,noop,noop
  obj.getDimensions=function(self)return self.w,self.h end
  return obj
end
g.newFont=function(a,b)
  local font=newFont(type(a)=='number'and a or b)
  function font:getWrap(text,limit)
    local lines={}
    for line in (tostring(text)..'\n'):gmatch('(.-)\n')do
      local current=''
      for word in line:gmatch('%S+')do
        local nextLine=current==''and word or current..' '..word
        if current~=''and self:getWidth(nextLine)>limit then lines[#lines+1]=current;current=word
        else current=nextLine end
      end
      lines[#lines+1]=current
    end
    return limit,lines
  end
  return font
end
local width,height=960,720
g.getDimensions=function()return width,height end
g.getWidth=function()return width end
g.getHeight=function()return height end
love.window.getSafeArea=function()return 0,0,width,height end
local printed,currentFont={},nil
g.setFont=function(font)currentFont=font;return setFont(font)end
g.printf=function(text,x,y,w,...)
  if type(text)=='string'and text:find('Based on the Pokemon Gen 1',1,true)then
    printed[#printed+1]={text=text,x=x,y=y,width=w,font=currentFont}
  end
  return printf(text,x,y,w,...)
end
local ui=Importer.new(function()end)
for _,size in ipairs({{960,720},{480,360},{1280,960}})do
  width,height=size[1],size[2]
  for _,tab in ipairs({'red','gold','crystal','emerald'})do
    ui.tab=tab;printed={}
    local ok,why=pcall(ui.draw,ui)
    T.check(ok,'actual native launcher still draws with wrapped attribution: '..tostring(why))
    local line=printed[#printed]
    T.check(line~=nil,'native launcher renders the original project credit')
    if line then
      T.check(line.text:find('by BOIS CLUB GAMES, LLC',1,true)~=nil,'credit retains original rights holder')
      T.check(line.text:find('https://github.com/bryanthaboi/gen1recomp',1,true)~=nil,'credit retains source project link')
      local _,lines=line.font:getWrap(line.text,line.width)
      local bottom=line.y+math.max(1,#lines)*line.font:getHeight()
      for _,button in ipairs(ui.donateButtons or {})do
        if not button.pinned then
          T.check(button.y>=bottom,'native footer reserves the full wrapped credit before its donation controls')
        end
      end
    end
  end
end
g.getDimensions,g.printf,g.setFont=dimensions,printf,setFont
g.getWidth,g.getHeight,love.window.getSafeArea=widthFn,heightFn,safeArea
g.newMesh,g.newShader,g.newImage,g.newFont=mesh,shader,image,newFont
love.image=oldImage
love.mouse.isDown=mouseDown
g.stencil,g.setStencilTest=stencil,stencilTest
g.ellipse,g.arc,g.polygon=ellipse,arc,polygon
run.release()
T.finish('Gen1 source attribution through native launcher footer')
