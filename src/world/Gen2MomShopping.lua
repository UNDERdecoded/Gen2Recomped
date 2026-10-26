-- Copyright (c) 2026 Roxas2712. See contribution permission:
-- https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md
-- Native accounts, ROM shopping rows and original phone programs share one save.
local Version=require('src.core.GameVersion')
local M={MAX_MONEY=999999}
local function integer(value,lo,hi)
 return type(value)=='number'and value%1==0 and value>=lo and value<=hi and value or nil
end
local function money(value)return integer(value,0,M.MAX_MONEY)or 0 end
function M.stock()
 local v=Version.get();return v=='gold'or v=='silver'or v=='crystal'
end
function M.mode(save)
 local mode=integer(save.g2MomSavingMode,0,3)
 local flag=save.flags and save.flags.ENGINE_MOM_SAVING_MONEY
 if mode==nil then mode=flag~=nil and(flag and 1 or 0)or(save.g2MomSaving and 1 or 0)
 elseif flag~=nil then mode=mode-mode%2+(flag and 1 or 0)end
 return mode
end
function M.prepareBank(save)
 if not M.stock()then return end
 save.flags=save.flags or{}
 local Flags=require('src.script.Flags')
 local active=save.flags.ENGINE_MOM_ACTIVE
 if active==nil and save.g2MomBankOpen==true then Flags.set(save,'ENGINE_MOM_ACTIVE')
 elseif active==true then save.g2MomBankOpen=true
 elseif active==false then save.g2MomBankOpen=nil end
 if save.flags.ENGINE_MOM_SAVING_MONEY==nil and(save.g2MomSaving~=nil or save.g2MomSavingMode~=nil)then
  if M.mode(save)%2==1 then Flags.set(save,'ENGINE_MOM_SAVING_MONEY')else Flags.clear(save,'ENGINE_MOM_SAVING_MONEY')end
 end
 save.g2MomSaving=M.mode(save)~=0
end
function M.setSaving(save,on)
 save.g2MomSaving=on==true
 if not M.stock()then return end
 save.g2MomSavingMode=on and 1 or 0
 save.flags=save.flags or{}
 local Flags=require('src.script.Flags')
 if on then Flags.set(save,'ENGINE_MOM_SAVING_MONEY')else Flags.clear(save,'ENGINE_MOM_SAVING_MONEY')end
end
function M.openBank(save)
 save.g2MomBankOpen=true
 if M.stock()then
  save.flags=save.flags or{};require('src.script.Flags').set(save,'ENGINE_MOM_ACTIVE')
 end
end
-- WinTrainerBattle deals four quarters; near-cap overflow is lost in the
-- selected account, not redirected to the other one.
function M.reward(save,total)
 if not M.stock()or not integer(total,0,0xffffff*4)then return nil end
 M.prepareBank(save)
 local quarter=math.floor(total/4)
 local mode=money(save.g2MomMoney)<M.MAX_MONEY and M.mode(save)or 0
 local quarters=mode==3 and 4 or mode
 local wallet,saved=money(save.money),money(save.g2MomMoney)
 for _=1,quarters do saved=math.min(M.MAX_MONEY,saved+quarter)end
 for _=1,4-quarters do wallet=math.min(M.MAX_MONEY,wallet+quarter)end
 save.money=wallet;save.g2MomMoney=saved
 return{total=quarter*4,mode=mode,quarters=quarters,wallet=wallet,saved=saved}
end
function M.pool(data)return data and data.map_scripts and data.map_scripts.momShopping end
function M.ready(data)
 local p=M.pool(data)
 return M.stock()and type(p)=='table'and p.complete==true and integer(p.step,1,M.MAX_MONEY)~=nil and
  type(p.random)=='table'and #p.random>0 and type(p.ladder)=='table'and #p.ladder>0
end
function M.caller(data)
 local found
 for id,row in pairs(data and data.map_scripts and data.map_scripts.phone or{})do
  if integer(id,1,255)and type(row)=='table'and(row.class==nil or row.class==0)and(row.contactNumber or row.trainer)==1 then
   if found then return nil end;found=id
  end
 end
 return found
end
function M.state(data,save)
 if not M.ready(data)then return nil end
 if save.g2MomShopping==nil then save.g2MomShopping={whichItem=0,whichSet=0,triggerBalance=M.pool(data).step}end
 local state=save.g2MomShopping
 if type(state)~='table'or not integer(state.whichItem,0,255)or not integer(state.triggerBalance,0,M.MAX_MONEY)then return nil end
 return state
end
function M.pick(data,save,random)
 local state=M.state(data,save);if not state then return nil end
 local p=M.pool(data);local saved=money(save.g2MomMoney)
 state.whichSet=0
 local row=p.ladder[state.whichItem+1]
 if row and saved>=row.trigger then return{row=row,set=2}end
 while state.triggerBalance<saved do
  state.triggerBalance=math.min(M.MAX_MONEY,state.triggerBalance+p.step)
 end
 if state.triggerBalance~=saved then return nil end
 state.triggerBalance=math.min(M.MAX_MONEY,state.triggerBalance+p.step)
 local n=random and random(#p.random)or math.random(0,#p.random-1)
 if not integer(n,0,#p.random-1)then return nil end
 state.whichSet=n+1
 return{row=p.random[n+1],set=1}
end
local function itemKey(data,index)
 local preferred=string.format('ITEM_%03d',index)
 local native=data.items and data.items[preferred]
 if type(native)=='table'and native.index==index then return preferred end
 local found
 for id,row in pairs(data.items or{})do
  if type(row)=='table'and row.index==index then
   if found and found~=id then return nil end;found=id
  end
 end
 return found
end
local function receive(data,save,row)
 if row.kind==2 then return require('src.world.Gen2Decorations').give(data,save,row.item)end
 if row.kind~=1 then return false end
 local id=itemKey(data,row.item);if not id then return false end
 local pc=save.pcItems or{};local held=pc[id]or 0
 if not integer(held,0,0xffff)then return false end
 local used=0
 for _,n in pairs(pc)do if not integer(n,0,0xffff)then return false end;used=used+math.ceil(n/99)end
 local cap=data.field and data.field.pcItemCap or 50
 if used+math.ceil((held+1)/99)-math.ceil(held/99)>cap then return false end
 save.pcItems=pc;pc[id]=held+1;return true
end
function M.tryBuy(data,save,opts)
 opts=opts or{}
 if not M.ready(data)or opts.phoneService~=true or opts.queued then return nil end
 local caller=M.caller(data);if not caller then return nil end
 local p=M.pool(data);local VM=require('src.script.Gen2ScriptVM')
 local itemScript=p.programs and VM.compile(data,p.programs.item)
 local dollScript=p.programs and VM.compile(data,p.programs.doll)
 if not(itemScript and dollScript)then return nil end
 local choice=M.pick(data,save,opts.random);if not choice then return nil end
 if not receive(data,save,choice.row)then return nil end
 save.g2MomMoney=math.max(0,money(save.g2MomMoney)-choice.row.cost)
 local state=M.state(data,save)
 if choice.set==2 then state.whichItem=(state.whichItem+1)%256 end
 return{kind=choice.row.kind,item=choice.row.item,cost=choice.row.cost,set=choice.set,
  saved=save.g2MomMoney,caller=caller,script=choice.row.kind==2 and dollScript or itemScript}
end
return M
