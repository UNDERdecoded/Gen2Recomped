-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Cartridge windows and native panel drawing share the admitted battle owner.
local Native=require('src.battle.Gen3Battle')
local Battle=require('src.core.game3.battle')
local Boundary=require('src.compat.gen1.ScriptBoundary')
local Call=require('src.compat.gen1.SourceCall')
local Scope=require('src.render.GraphicsScope')
local Version=require('src.core.GameVersion')
local C={WIN={MSG=0,ACTION_PROMPT=1,ACTION_MENU=2,MOVE_NAME_1=3,MOVE_NAME_2=4,MOVE_NAME_3=5,
 MOVE_NAME_4=6,PP=7,DUMMY=8,PP_REMAINING=9,MOVE_TYPE=10,SWITCH_PROMPT=11,YESNO=12,LEVEL_UP_BOX=13,LEVEL_UP_BANNER=14}}
local function owner()
 local screen=Battle._screen();if screen then return screen end
 local g=require('src.compat.gen1.NativeSession').game()
 return g and{game=g,data=g.data}
end
function C.layout()
 local v=Version.get();return(v=='ruby'or v=='sapphire')and'rs'or v=='emerald'and'emerald'or'frlg'
end
function C.isHoenn()return C.layout()~='frlg'end
function C.window(id)
 assert(type(id)=='number'and id%1==0 and id>=0 and id<=14,'invalid battle window')
 local s=owner();if not s then return nil,'no native GBA owner'end
 local c=s.data.constants;local rec=c.gen3BattleWindows
 local row=rec and rec.templates and rec.templates[id+1]
 if not row and rec then
  row=({[0]=rec.message,rec.prompt,rec.action})[id]
  if id>=3 and id<=6 then row=rec.moves and rec.moves[id-2]end
 end
 if not row then return nil,'window not present in imported native templates'end
 local w,h=row.width or row.w,row.height or row.h
 if Battle._screen()==s and id<=6 then
  local windows=Native.windows(s)
  local frame=({[0]=windows.message,windows.prompt,windows.action})[id]
  if id>=3 then frame=windows.moves and windows.moves[id-2]end
  if frame then return{left=frame.textX/8,top=frame.row1/8,w=frame.cols or frame.tw-2,h=frame.th-2,x=frame.textX,y=frame.row1}end
 end
 return{left=row.left,top=row.top%20,w=w,h=h,x=row.left*8,y=(row.top%20)*8}
end
function C.textOrigin(id)
 local w,why=C.window(id);if not w then return nil,why end
 local dx=id==1 and 1 or id==9 and 2 or 0
 return w.x+dx,w.y+1,w.w*8,id>=3 and id<=7 or id==10 or id==11
end
function C.messageOrigin()
 if C.layout()~='emerald'then return 10,122,224 end
 return C.textOrigin(C.WIN.MSG)
end
function C.textboxColors(fg,shadow)
 local s=owner();local a,b;if s then a,b=Native.textColors(s,'message')end
 return a or fg,b or shadow
end
function C.manifest()
 local s=owner();if not s then return nil,'no native GBA owner'end
 local c=s.data.constants;local text=Native.textbox(s)
 local copy=require('src.mods.Merge').deepCopy
 local templates={}
 for id=0,14 do local row=C.window(id);if row then templates[id+1]={left=row.left,top=row.top,w=row.w,h=row.h}end end
 return{layout=C.layout()=='frlg'and'frlg'or'rse',assetLayout=C.layout(),
  windows={normal=templates},
  text=copy(text and text.text or{}),native=true}
end
local modes={none='message',menu='action',moves='moves'}
function C.drawPanel(mode)
 assert(modes[mode],'invalid battle panel mode')
 if Boundary.active('battle.panel')then return Boundary.invoke('battle.panel')end
 local screen=Battle._screen();if not screen then return false,'no native battle'end
 return Native.drawPanel(screen,modes[mode])
end
local basePanel=C.drawPanel
function C._panel(screen,which,body)
 if C.drawPanel==basePanel then return body()end
 local mode=which=='action'and'menu'or which=='moves'and'moves'or'none'
 local ok,result=Scope.call(function()
  Boundary.dispatch('battle.panel',body,function()return Call.call(C,'drawPanel',mode)end)
 end)
 if not ok then error(result,0)end
 -- A presentation wrapper owns the panel even if its painter returns nil.
 return true
end
return C
