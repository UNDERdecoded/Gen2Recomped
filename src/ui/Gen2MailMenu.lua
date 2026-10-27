-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
local Mail=require("src.pokemon.Gen2Mail")
local Menu=require("src.ui.Menu")
local TextBox=require("src.render.TextBox")
local Strings=require("src.core.Strings")
local M={}
function M.read(game,entry)
  local top,bottom=Mail.lines(entry)
  local text=top.."\n"..bottom.."\f"..Strings("FROM:").."\n"..tostring(entry and entry.author or "") -- strings: authored letter data and localized sender heading
  game.stack:push(TextBox.new(game,text))
end
local function partySlot(game,mon)
  for i,member in ipairs(game.save.party or {}) do if member==mon then return i end end
end
function M.new(game,opts)
  opts=opts or {};local mon=opts.mon or game.save.party[opts.slot]
  local function say(text)game.stack:push(TextBox.new(game,Strings(text)))end
  return Menu.new(game,{
    {label=Strings("READ"),keepOpen=true,onSelect=function()
      local slot=partySlot(game,mon)
      if slot then M.read(game,Mail.get(game.save,slot) or Mail.entry(mon.item)) end
    end},
    {label=Strings("TAKE"),onSelect=function()
      game.stack:push(TextBox.new(game,Strings("Send the removed\nMAIL to your PC?"),nil,{
        choice=function(yes)
          local slot=partySlot(game,mon);if not slot then return end
          if yes then
            if Mail.sendToPc(game.save,slot) then say(Strings("The MAIL was sent\nto your PC."))
            else say(Strings("Your PC's MAILBOX\nis full.")) end
          else
            game.stack:push(TextBox.new(game,Strings("The MAIL will lose\nits message. OK?"),nil,{
              defaultNo=true,choice=function(confirm)
                if not confirm then return end
                local current=partySlot(game,mon);if not current then return end
                if Mail.detachToBag(game.save,current,game.data) then say("MAIL detached.")
                else say(Strings("There's no space\nfor removing MAIL.")) end
              end}))
          end
        end}))
    end},
    {label=Strings("QUIT")},
  },{tx=9,ty=10,tw=11,th=8})
end
return M
