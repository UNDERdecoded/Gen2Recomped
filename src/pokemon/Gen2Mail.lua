-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- GSC letters belong to party slots; the PC mailbox holds detached letters.
-- Native item IDs are resolved by the imported semantic key, never a label.
local Runtime = require("src.mods.Runtime")
local Mail = {
  MAIL_MSG_LENGTH=32, MAIL_LINE_LENGTH=16, MAILBOX_CAPACITY=10,
  AUTHOR_LENGTH=10, PARTY_LENGTH=6,
  POKEMAIL_WRONG_MAIL=0, POKEMAIL_CORRECT=1, POKEMAIL_REFUSED=2,
  POKEMAIL_NO_MAIL=3, POKEMAIL_LAST_MON=4,
  ITEMS={"FLOWER_MAIL","SURF_MAIL","LITEBLUEMAIL","PORTRAITMAIL","LOVELY_MAIL",
    "EON_MAIL","MORPH_MAIL","BLUESKY_MAIL","MUSIC_MAIL","MIRAGE_MAIL"},
  INDEX={},
}
local named, native, lastRead = {}, {}, nil
for i,id in ipairs(Mail.ITEMS) do named[id]=true;Mail.INDEX[id]=i-1 end
local function slot(n, max)
  return type(n)=="number" and n==math.floor(n) and n>=1 and n<=max
end
function Mail.load(data)
  for id in pairs(native) do Mail.INDEX[id]=nil end
  native={};lastRead=nil
  for i,id in ipairs(Mail.ITEMS) do Mail.INDEX[id]=i-1 end
  for id,def in pairs(data and data.items or {}) do
    if type(def)=="table" and named[def.key] then
      native[id]=def.key;Mail.INDEX[id]=Mail.INDEX[def.key]
    end
  end
end
function Mail.isMail(id) return named[id]==true or native[id]~=nil end
function Mail.monHoldsMail(mon) return type(mon)=="table" and Mail.isMail(mon.item) end
function Mail.anyMonHoldingMail(save)
  for _,mon in ipairs(save and save.party or {}) do if Mail.monHoldsMail(mon) then return true end end
  return false
end
function Mail.state(save)
  if type(save)~="table" then return {party={},box={}} end
  if type(save.mail)~="table" then save.mail={party={},box={}} end
  if type(save.mail.party)~="table" then save.mail.party={} end
  if type(save.mail.box)~="table" then save.mail.box={} end
  return save.mail
end
function Mail.characters(text)
  local out={}
  for ch in tostring(text or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do out[#out+1]=ch end
  return out
end
local function limit(text,n)
  local chars=Mail.characters(text);return table.concat(chars,"",1,math.min(n,#chars))
end
function Mail.trim(text) return limit(text,Mail.MAIL_MSG_LENGTH) end
function Mail.entry(item,message,author,authorId,species)
  return {type=item,message=message or "",author=author or "",authorId=authorId or 0,species=species}
end
function Mail.armRead() lastRead=nil end
function Mail.get(save,n) Mail.armRead();return Mail.state(save).party[n] end
function Mail.set(save,n,entry)
  if not slot(n,Mail.PARTY_LENGTH) then return false end
  Mail.state(save).party[n]=entry;return true
end
function Mail.clear(save,n) if slot(n,Mail.PARTY_LENGTH) then Mail.state(save).party[n]=nil end end
function Mail.removeSlot(save,n)
  if not slot(n,Mail.PARTY_LENGTH) or not (save and save.mail) then return end
  local letters=Mail.state(save).party
  for i=n,Mail.PARTY_LENGTH-1 do letters[i]=letters[i+1] end
  letters[Mail.PARTY_LENGTH]=nil
end
function Mail.swapSlots(save,a,b)
  if not slot(a,6) or not slot(b,6) or not (save and save.mail) then return end
  local letters=Mail.state(save).party;letters[a],letters[b]=letters[b],letters[a]
end
local function written(save,n,mon,item,text,author,id,source)
  if not save or not slot(n,6) or not Mail.isMail(item) then return false end
  local entry=Mail.entry(item,Mail.trim(text),limit(author,10),id,mon and mon.species)
  Mail.set(save,n,entry)
  if Runtime.wants("mail.written") then
    Runtime.emit("mail.written",{entry=entry,slot=n,mon=mon,message=entry.message,author=entry.author,source=source})
  end
  return true
end
function Mail.compose(save,n,text,mon,item)
  local player=save and save.player or {}
  return written(save,n,mon,item,text,player.name or "",player.id or 0,"compose")
end
function Mail.give(save,item,text)
  local party=save and save.party or {};local n=#party;local mon=party[n]
  if not mon or not slot(n,6) or not Mail.isMail(item) then return false end
  mon.item=item
  return written(save,n,mon,item,text,mon.otName or mon.ot or "",mon.otId or 0,"script")
end
function Mail.lines(entry)
  local text=type(entry)=="table" and tostring(entry.message or "") or ""
  local top,bottom=text:match("^(.-)\n(.*)$")
  if not top then
    local chars=Mail.characters(text);top=table.concat(chars,"",1,math.min(16,#chars))
    bottom=#chars>16 and table.concat(chars,"",17) or ""
  end
  if type(entry)=="table" and Runtime.wants("mail.read") and lastRead~=entry then
    lastRead=entry;Runtime.emit("mail.read",{entry=entry,message=entry.message,author=entry.author,top=top,bottom=bottom})
  end
  return top,bottom
end
function Mail.mailbox(save) Mail.armRead();return Mail.state(save).box end
function Mail.mailboxCount(save) return #Mail.state(save).box end
function Mail.mailboxFull(save) return Mail.mailboxCount(save)>=10 end
function Mail.sendToPc(save,n)
  local mon=save and save.party and save.party[n]
  if not Mail.monHoldsMail(mon) or Mail.mailboxFull(save) then return false end
  local state=Mail.state(save)
  state.box[#state.box+1]=state.party[n] or Mail.entry(mon.item,"","",0,mon.species)
  state.party[n]=nil;mon.item=nil;return true
end
function Mail.deleteFromPc(save,n)
  local box=Mail.state(save).box
  if not slot(n,#box) then return nil end
  return table.remove(box,n)
end
function Mail.moveFromPcToParty(save,n,to)
  local mon=save and save.party and save.party[to];local box=Mail.state(save).box
  local letter=slot(n,#box) and box[n]
  if not letter or not slot(to,6) or not mon or mon.item or require("src.pokemon.Party").isEgg(mon) then return false end
  if not Mail.isMail(letter.type) then return false end
  Mail.set(save,to,letter);mon.item=letter.type;table.remove(box,n);return true
end
function Mail.detachToBag(save,n,data)
  local mon=save and save.party and save.party[n]
  if not Mail.monHoldsMail(mon) then return false,"no_mail" end
  if not require("src.inventory.Bag").add(save,mon.item,1,data) then return false,"full" end
  mon.item=nil;Mail.clear(save,n);return true
end
function Mail.attachFromBag(save,n,item,text,data)
  local mon=save and save.party and save.party[n]
  if not mon or not slot(n,6) or require("src.pokemon.Party").isEgg(mon) then return false,"target" end
  if Mail.monHoldsMail(mon) then return false,"mail" end
  if not Mail.isMail(item) or not save.inventory or (save.inventory[item] or 0)<1 then return false,"item" end
  local Bag=require("src.inventory.Bag")
  -- Bag rules are pure store operations. Check the complete exchange before
  -- changing either held state or the live acquisition-ordered inventory.
  local shadow={inventory={}}
  for id,count in pairs(save.inventory)do shadow.inventory[id]=count end
  if save.bagOrder then shadow.bagOrder={};for i,id in ipairs(save.bagOrder)do shadow.bagOrder[i]=id end end
  Bag.remove(shadow,item,1)
  if mon.item and not Bag.add(shadow,mon.item,1,data) then return false,"full" end
  for id in pairs(save.inventory)do save.inventory[id]=nil end
  for id,count in pairs(shadow.inventory)do save.inventory[id]=count end
  if save.bagOrder then
    for i=#save.bagOrder,1,-1 do save.bagOrder[i]=nil end
    for i,id in ipairs(shadow.bagOrder or {})do save.bagOrder[i]=id end
  else save.bagOrder=shadow.bagOrder end
  mon.item=item;Mail.compose(save,n,text,mon,item);return true
end
-- A carrier absent from the loaded dataset cannot keep a live party slot.
-- Retain its detached letter in the existing quarantine until mailbox room
-- is available, rather than attaching it to a later occupant of that slot.
function Mail.reclaimQuarantine(save,report)
  local pending=save and save.orphaned and save.orphaned.mail
  if type(pending)~="table" or #pending==0 then return end
  local box=Mail.state(save).box;local i=1
  while i<=#pending and #box<10 do
    local letter=pending[i]
    if type(letter)=="table" and Mail.isMail(letter.type) then
      box[#box+1]=table.remove(pending,i)
      if report then report.restoredMail=report.restoredMail or {};report.restoredMail[#report.restoredMail+1]={author=letter.author} end
    else i=i+1 end
  end
end
function Mail.checkPokeMail(save,n,expected)
  if n==nil then return Mail.POKEMAIL_REFUSED end
  local mon=save and save.party and save.party[n]
  if not Mail.monHoldsMail(mon) then return Mail.POKEMAIL_NO_MAIL end
  local entry=Mail.get(save,n);local text=entry and entry.message or ""
  if type(expected)~="string" or expected=="" or text:sub(1,#expected)~=expected then return Mail.POKEMAIL_WRONG_MAIL end
  local other=false
  for i,member in ipairs(save.party) do
    if i~=n and (member.hp or 0)>0 and not require("src.pokemon.Party").isEgg(member) then other=true end
  end
  if (mon.hp or 0)>0 and not other then return Mail.POKEMAIL_LAST_MON end
  table.remove(save.party,n);Mail.removeSlot(save,n);return Mail.POKEMAIL_CORRECT
end
function Mail.validate(save,report)
  local lost={};if report then report.lostMail=lost end
  if not save then return lost end
  if save.mail==nil then Mail.reclaimQuarantine(save,report);return lost end
  local raw=save.mail
  local function reject(where,n,why,entry)
    lost[#lost+1]={where=where,slot=n,why=why,entry=entry}
  end
  if type(raw)~="table" then reject("mail",nil,"not a table",raw);save.mail=nil;return lost end
  local function clean(entry,where,n)
    if type(entry)~="table" or not Mail.isMail(entry.type) then reject(where,n,"invalid letter",entry);return end
    local out={};for k,v in pairs(entry) do out[k]=v end
    out.message=Mail.trim(entry.message);out.author=limit(entry.author,10)
    local id=tonumber(entry.authorId) or 0
    out.authorId=slot(id+1,65536) and id or 0
    if out.message~=entry.message or out.author~=entry.author or out.authorId~=entry.authorId then reject(where,n,"letter repaired",entry) end
    return out
  end
  local party,box={},{}
  if type(raw.party)=="table" then
    for key,entry in pairs(raw.party) do
      local n=tonumber(key)
      if not slot(n,6) or not (save.party and save.party[n]) then
        local letter=clean(entry,"party",key)
        reject("party",key,"carrier unavailable",entry)
        if letter then
          save.orphaned=save.orphaned or {mons={},items={}}
          save.orphaned.mail=save.orphaned.mail or {}
          save.orphaned.mail[#save.orphaned.mail+1]=letter
        end
      else party[n]=clean(entry,"party",n) end
    end
  elseif raw.party~=nil then reject("party",nil,"not a table",raw.party) end
  if type(raw.box)=="table" then
    local keys={};for n in pairs(raw.box) do
      if type(n)=="number" and n>=1 and n%1==0 then keys[#keys+1]=n else reject("box",n,"invalid slot",raw.box[n]) end
    end
    table.sort(keys)
    for _,n in ipairs(keys) do
      if #box>=10 then reject("box",n,"MAILBOX full",raw.box[n])
      else local entry=clean(raw.box[n],"box",n);if entry then box[#box+1]=entry end end
    end
  elseif raw.box~=nil then reject("box",nil,"not a table",raw.box) end
  raw.party,raw.box=party,box;Mail.reclaimQuarantine(save,report);return lost
end
return Mail
