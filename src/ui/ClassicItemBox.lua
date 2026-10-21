-- Independently written overlay for the classic item-list surface. Coordinates
-- follow the Gen1 reference's LIST_MENU_BOX (4,2)-(19,12); host code is not copied.
local B={}
local function sameRows(a,b)
 if #a~=#b then return false end
 for i,row in ipairs(a)do if row~=b[i]then return false end end
 return true
end
function B.attach(list,enabled)
 local V=require('src.core.GameVersion')
 if V.generation()~=1 or list.itemBox or list.__classicItemBox or not(list.kind=='bag'or list.messageBox)then return list end
 enabled=enabled or function()return true end
 local Font=require('src.render.Font');local Strings=require('src.core.Strings');local Theme=require('src.ui.Theme')
 local original={draw=list.draw,update=list.update,rows=list.rows,isOpaque=list.isOpaque,sgbPalettes=list.sgbPalettes}
 local prompt=list.footer;local tick=0
 list.__classicItemBox=true;list.itemBox=true
 local function flags(on)
  if on then list.rows=3;list.isOpaque=false;list.sgbPalettes=false
  else list.rows=original.rows;list.isOpaque=original.isOpaque;list.sgbPalettes=original.sgbPalettes end
 end
 local function rows()
  local view={};local cancel
  for _,row in ipairs(list.items)do view[#view+1]=row;if row.cancel then cancel=row end end
  local owned=not cancel
  if owned then cancel={cancel=true,label=Strings('CANCEL')};view[#view+1]=cancel end
  return view,cancel,owned
 end
 local function fit(text,x,y,budget)
  text=tostring(text or'');local scale=math.min(1,budget/math.max(1,Font.width(text)))
  if scale==1 then return Font.draw(text,x,y)end
  love.graphics.push();love.graphics.translate(x,y);love.graphics.scale(scale,1)
  local ok,result=pcall(Font.draw,text,0,0);love.graphics.pop();if not ok then error(result,0)end;return result
 end
 local function footer()
  local text=list.footer
  if type(text)=='function'then text=text(list,list.items[list.index])end
  Font.drawBox(0,12,20,6);love.graphics.setColor(0,0,0,1)
  if not text then return end
  local flat={};for _,page in ipairs(require('src.render.TextBox').paginate(text))do for _,line in ipairs(page)do flat[#flat+1]=line end end
  for i=math.max(1,#flat-1),#flat do fit(flat[i],8,112+(i-math.max(1,#flat-1))*16,144)end
 end
 list.draw=function(self,...)
  local on=enabled();flags(on);if not on then return original.draw(self,...)end
  local view=rows();local start=math.max(0,math.min(self.scroll or 0,math.max(0,#view-1)))
  love.graphics.push('all')
  local ok,why=pcall(function()
   if self.messageBox and self.footer==prompt then footer()end
   love.graphics.setColor(1,1,1,1);Font.drawBox(4,2,16,11);love.graphics.setColor(0,0,0,1)
   local sawCancel=false
   for i=start+1,math.min(#view,start+4)do
    local row=view[i];local y=32+(i-start-1)*16
    fit(row.label,48,y,104);sawCancel=sawCancel or row.cancel
    if not row.cancel then
     local def=self.game.data.items and self.game.data.items[row.value]
     local key=def and(def.key or row.value)or row.value
     local keyItem=def and def.keyItem or type(key)=='string'and key:match('^HM_')
     local count=row.count or(type(row.right)=='string'and row.right:match('^[x×]%s*(%d+)$'))
     if not keyItem then
      if count then Font.draw('×',112,y+8);local n=tostring(count);fit(n,136-math.min(24,Font.width(n)),y+8,24)
      elseif row.right then fit(row.right,136-math.min(88,Font.width(row.right)),y+8,88)end
     end
    end
    if i==self.index then Font.drawCode((self.hollowIndex==i or self.swapIndex==i)and Theme.cursorHollow or Theme.cursor,40,y)
    elseif self.swapIndex==i then Font.drawCode(Theme.cursorHollow,40,y)end
   end
   if #view-start>=4 and not sawCancel and tick%60<30 then Font.drawCode(Theme.moreArrow,144,88)end
   if self.messageBox and self.footer~=prompt then footer()end
  end)
  love.graphics.pop();if not ok then error(why,0)end
 end
 list.update=function(self,...)
  local on=enabled();flags(on);if not on then return original.update(self,...)end
  tick=tick+1;self.hollowIndex=nil
  local nativeItems=self.items;local view,cancel,owned=rows();local choose,selectKey=self.onChoose,self.onSelectKey
  self.items=view;self.index=math.max(1,math.min(self.index,#view))
  self.onChoose=function(row,...)
   if row==cancel and owned then self:close();if self.onCancel then return self.onCancel()end;return end
   self.hollowIndex=self.index
   if choose then return choose(row,...)end
  end
  if selectKey then self.onSelectKey=function(row,...)if row and not row.cancel then return selectKey(row,...)end end end
  local ok,result=pcall(original.update,self,...)
  self.onChoose,self.onSelectKey=choose,selectKey
  if self.items==view then
   local actual={};for _,row in ipairs(view)do if not owned or row~=cancel then actual[#actual+1]=row end end
   self.items=sameRows(actual,nativeItems)and nativeItems or actual
  end
  if not ok then error(result,0)end;return result
 end
 flags(enabled());return list
end
function B.install(enabled)
 local List=require('src.ui.ListMenu');local state=List.__classicItemBoxFactory
 if state then state.enabled=enabled;return end
 state={enabled=enabled};List.__classicItemBoxFactory=state
 local create=List.new
 List.new=function(...)return B.attach(create(...),function()return state.enabled()end)end
end
return B
