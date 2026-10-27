-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Uses the native keyboard with two 16-character rows. Accepting commits
-- the stationery exchange and letter together; cancelling changes neither.
local Mail=require("src.pokemon.Gen2Mail")
local Strings=require("src.core.Strings")
local M={}
function M.new(game,opts)
  opts=opts or {}
  local screen
  local function close()
    if game.stack:top()==screen then game.stack:pop() end
  end
  screen=require("src.ui.Gen2NamingScreen").new(game,{
    type="box",maxLength=32,prompt=require("src.core.Strings")("MAIL  SELECT:QUIT"),initial="",
    onDone=function(text)
      local slot
      for i,mon in ipairs(game.save.party or {})do if mon==opts.mon then slot=i;break end end
      local ok,why=Mail.attachFromBag(game.save,slot,opts.item,text,game.data)
      if not ok then
        local message=why=="full" and Strings("The PACK is full.") or Strings("The MAIL couldn't\nbe attached.")
        game.stack:push(require("src.render.TextBox").new(game,message));return
      end
      close();if opts.onDone then opts.onDone(true) end
    end,
  })
  screen.mailMode=true
  local update=screen.update
  function screen:update(dt)
    local input=game.input
    if input:wasPressed("select") or (input:wasPressed("b") and #self.glyphs==0) then
      close();if opts.onCancel then opts.onCancel() end;return
    end
    return update(self,dt)
  end
  return screen
end
return M
