-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Read the current native cache. Returned IR is detached; no game, ROM reader,
-- translation catalogue or retired dataset is retained by this module.
local Native=require('src.compat.gen1.NativeSession')
local Version=require('src.core.GameVersion')
local Copy=require('src.mods.Merge').deepCopy
local M={}
local function readNative(key)
 local game=Native.game();local data=game and game.data
 if not data or type(key)~='string'then return nil end
 local catalog=data.text_pointers and data.text_pointers.namedIR
 if catalog and(type(catalog)~='table'or catalog.schema~=1
   or type(catalog.named)~='table'or type(catalog.records)~='table'or catalog.edition~=Version.get()
   or catalog.romSha1~=Version.info().sha1)then return nil,nil,game,true end
 local prose=data._romTextGeneration==3 and data.romText
 if prose and(prose[key]~=nil or data._romTextTouched and data._romTextTouched[key])then
  return prose[key],nil,game,prose[key]==nil
 end
 local id=catalog and catalog.named[key]or key
 local row=catalog and catalog.records[id]
 local text=data.text or{}
 local value=text[key]
 if key~=id and value~=nil then return value,nil,game end
 value=text[id]
 if row then
  if value~=row.nativePlain then return value,nil,game,value==nil end
  if key=='gText_SafariZoneMenu'or key=='BattleText_MenuOptionsSafari'then
   -- The native Safari owner preserves compound glyph tags which older
   -- generic catalogs flattened into Latin letters. Borrow its actual IR;
   -- explicit canonical/offset/prose edits have already won above.
   local plain,nodes=require('src.battle.Gen3SafariText').read(data,Version.get(),'native.safari.menu')
   if plain then return plain,nodes,game,nil,true end
  end
  return row.plain,row.ir,game,nil,true
 end
 if value==nil and key:sub(1,14)=='native.safari.'then
  local plain,nodes=require('src.battle.Gen3SafariText').read(data,Version.get(),key)
  return plain,nodes,game
 end
 return value,nil,game
end
-- Semantic RS names refer to the cartridge's own records. PP and TYPE share
-- a record but are separate labels to callers; keep leading IR controls on
-- both lines. The ordinary command uses the active-mon prompt, whereas the
-- separate Safari prompt really names the player. Never rewrite placeholder
-- bytes globally to compensate for selecting the wrong record.
local rsLabels={gText_MoveInterfacePP={'BattleText_PP',1},gText_MoveInterfaceType={'BattleText_PP',2},
 gText_BattleSwitchWhich={'BattleText_SwitchWhich'},gText_WhatWillPkmnDo={'BattleText_OtherMenu'},
 gText_WhatWillWallyDo={'BattleText_WallyMenu'},gText_SafariZoneMenu={'BattleText_MenuOptionsSafari'},
 gText_SafariBalls={'BattleText_SafariBalls'}}
local function line(value,nodes,wanted)
 if type(value)~='string'then return value,nodes end
 local at=1
 for _=2,wanted do local p=value:find('\n',at,true);if not p then return end;at=p+1 end
 local p=value:find('\n',at,true);value=value:sub(at,p and p-1 or #value)
 if not nodes then return value end
 local out,header,row,leading={},{},1,true
 for _,node in ipairs(nodes)do
  if leading and node.t=='ext'then header[#header+1]=node else leading=false end
  if node.t=='nl'then
   row=row+1
   if row==wanted then for _,control in ipairs(header)do out[#out+1]=control end end
  elseif row==wanted and node.t~='eos'then out[#out+1]=node end
 end
 out[#out+1]={t='eos'};return value,out
end
local function read(key)
 local value,nodes,game,removed,nativeRecord=readNative(key)
 local edition=Version.get()
 local alias=rsLabels[key]
 if not removed and (value==nil or nativeRecord)and (edition=='ruby'or edition=='sapphire')and alias then
  local v,ir,owner,gone=readNative(alias[1])
  if alias[2]then v,ir=line(v,ir,alias[2])end
  return v,ir,owner,gone
 end
 return value,nodes,game,removed
end
local function translated(value,game)
 if type(value)~='string'then return nil end
 local direct=game.data.strings and game.data.strings[value]
 if type(direct)=='string'then return direct end
 local service=package.loaded['src.translation.Service']
 return service and service.lookup(value)or value
end
-- Registry edits have string semantics. Recover their explicit line/page/tag
-- structure without inventing absent cartridge formatting operands.
local lineKinds={['\n']='nl',['\v']='scroll',['\f']='para'}
local function stringIR(value)
 local out,pending={},{}
 local function flush()
  if #pending>0 then out[#out+1]={t='text',s=table.concat(pending)};pending={}end
 end
 local at=1
 while at<=#value do
  local c=value:sub(at,at);local kind=lineKinds[c]
  if kind then flush();out[#out+1]={t=kind};at=at+1
  elseif c=='{'then
   local token=value:match('^%b{}',at)
   if token then flush();out[#out+1]={t='tag',tag=token};at=at+#token
   else pending[#pending+1]=c;at=at+1 end
  else pending[#pending+1]=c;at=at+1 end
 end
 flush();out[#out+1]={t='eos'};return out
end
local function currentMenu(game)
 local menu=game and game.data.constants and game.data.constants.gen3BattleMenu
 if not(menu and menu.rows and menu.rows[1]and menu.rows[2]and menu.columnX)then return end
 for y=1,2 do for x=1,2 do if type(menu.rows[y][x])~='string'then return end end end
 return menu
end
local function menuIR(game)
 local menu=currentMenu(game);if not menu then return end
 local out={}
 for y=1,2 do
  for x=1,2 do
   out[#out+1]={t='text',s=menu.rows[y][x]}
   if x==1 then out[#out+1]={t='ext',cmd=19,args={menu.columnX}}end
  end
  if y==1 then out[#out+1]={t='nl'}end
 end
 out[#out+1]={t='eos'};return out
end
local function adaptMenu(game,nodes)
 local menu=currentMenu(game);if not menu then return Copy(nodes)end
 local cells={{'',''},{'',''}};local row,col,gap=1,1
 for _,node in ipairs(nodes)do
  if node.t=='nl'then row=row+1;col=1
  elseif node.t=='ext'and node.cmd==19 then
   col=col+1
   if gap and gap~=node.args[1]then return Copy(nodes)end
   gap=node.args[1]
  elseif node.t=='text'or node.t=='tag'then
   if not(cells[row]and cells[row][col])then return Copy(nodes)end
   cells[row][col]=cells[row][col]..(node.s or node.tag)
  end
 end
 if row~=2 or col~=2 or not gap then return Copy(nodes)end
 local changed=gap~=menu.columnX
 for y=1,2 do for x=1,2 do
  if cells[y][x]==''then return Copy(nodes)end
  changed=changed or cells[y][x]~=menu.rows[y][x]
 end end
 if not changed then return Copy(nodes)end
 -- Replace only cell lettering and column positions. Preserve cartridge
 -- colour/font/pause controls around those cells in their original order.
 local out,written={},false;row,col=1,1
 for _,node in ipairs(nodes)do
  if node.t=='text'or node.t=='tag'then
   if not written then out[#out+1]={t='text',s=menu.rows[row][col]};written=true end
  else
   local value=Copy(node)
   if node.t=='nl'then row=row+1;col=1;written=false
   elseif node.t=='ext'and node.cmd==19 then
    col=col+1;written=false;value.args[1]=menu.columnX
   end
   out[#out+1]=value
  end
 end
 return out
end
function M.has(key)
 local text,_,_,removed=read(key)
 if removed then return false end
 if text~=nil then return type(text)=='string'end
 local game=Native.game()
 return key=='gText_BattleMenu'and menuIR(game)~=nil or false
end
function M.ir(key)
 local value,nodes,game,removed=read(key)
 if key=='gText_BattleMenu'and game and not removed then
  if nodes then return adaptMenu(game,nodes)end
  if value==nil then local menu=menuIR(game);if menu then return menu end end
 end
 assert(type(value)=='string','native ROM text is unavailable: '..tostring(key))
 local current=translated(value,game)
 if nodes and current==value then return Copy(nodes)end
 return stringIR(current)
end
local function expand(value,game,fill)
 fill=fill or{};assert(type(fill)=='table','native text fill must be a table')
 local player=game.save and game.save.player or{}
 return(value:gsub('%b{}',function(token)
  local key=token:sub(2,-2)
  local found=fill[key]
  if found==nil then found=fill[token]end
  if found==nil and key=='PLAYER'then found=fill.playerName or player.name end
  if found==nil and key=='RIVAL'then found=fill.rivalName or player.rival end
  local slot=key:match('^VAR([123])$')
  if found==nil and slot and fill.stringVars then found=fill.stringVars[tonumber(slot)]end
  return found==nil and token or tostring(found)
 end))
end
function M._expand(value,fill)
 local game=assert(Native.game(),'native text expansion requires a current session')
 assert(type(value)=='string','native text expansion requires a string')
 return expand(value,game,fill)
end
function M.plain(key,fill)
 local value,_,game=read(key)
 assert(type(value)=='string','native ROM text is unavailable: '..tostring(key))
 return expand(translated(value,game),game,fill)
end
function M.key(label,index)
 assert(type(label)=='string'and type(index)=='number'and index>=0 and index%1==0,'invalid native text table index')
 return label..'['..index..']'
end
function M.at(label,index,fill)return M.plain(M.key(label,index),fill)end
M.box=M.plain
return M
