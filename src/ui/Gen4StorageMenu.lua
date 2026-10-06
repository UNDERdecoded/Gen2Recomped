-- The Pokemon Storage System's own menu, for a cache whose common scripts do
-- not compile (OverworldState:openPC's fallback).  On the cartridge this is
-- CommonScript_InitStorageSystemMenu: a field list menu at tile (1, 1)
--
--     InitGlobalTextListMenu 1, 1, 0, VAR_RESULT
--     AddListMenuEntry MenuEntries_Text_PC_DepositPokemon, 0, ..DescriptionDepositPokemon
--     ... WithdrawPokemon, MovePokemon, MoveItems, (ComparePokemon), SeeYa
--
-- in the standard window frame over the field, with the highlighted entry's
-- description in the message box.  Words are bank 361 (65..70 the entries,
-- 74..79 the descriptions); the English below is only for a cache without it.
local Font=require('src.render.Font')
local Screens=require('src.ui.Screens')
local T=require('src.import.Gen4Text')
local Storage={};Storage.__index=Storage;Storage.isOpaque=false
Storage.BANK=361
local ROWS={
 {65,74,'deposit','DEPOSIT POKéMON','Pokémon in your party may be stored\nin the storage system’s Boxes.'},
 {66,75,'withdraw','WITHDRAW POKéMON','Pokémon stored in Boxes may be added\nto your party.'},
 {67,76,'move','MOVE POKéMON','You may sort the Pokémon in Boxes\nand in your party.'},
 {68,77,'items','MOVE ITEMS','You may sort the items held by your\nPokémon in Boxes and in your party.'},
 {70,79,false,'SEE YA!','Log out of the Pokémon Storage\nSystem.'},
}
Storage.ROWS=ROWS
function Storage:uiSize() return 256,192 end
function Storage:wantsFillScale() return true end
function Storage:sgbPalettes() return {require('src.render.PaletteFX').trueColorZone(0,0,31,23)} end
function Storage.new(game,opts) return setmetatable({game=game,opts=opts or {},index=1},Storage) end
function Storage:word(n,fallback)
 local text=T.resolve(self.game.data,Storage.BANK,n,self.game)
 if type(text)~='string' or text=='' then return fallback end
 return (text:gsub('[\v\f]+','\n'))
end
function Storage:close() self.game.stack:pop();if self.opts.onCancel then self.opts.onCancel() end;if self.opts.onDone then self.opts.onDone() end end
function Storage:choose() local row=ROWS[self.index];if not row[3] then return self:close() end;Screens.push(self.game,'BoxMenu',{mode=row[3]}) end
function Storage:update()
 local i=self.game.input
 if i:wasPressed('up') then self.index=(self.index-2)%#ROWS+1 elseif i:wasPressed('down') then self.index=self.index%#ROWS+1
 elseif i:wasPressed('a') then self:choose() elseif i:wasPressed('b') then self:close() end
end
-- the window's content rect in tiles: (1, 1), as wide as its widest entry
-- plus the cursor column, two tiles a row
function Storage:rect()
 local w=0
 for _,row in ipairs(ROWS) do w=math.max(w,Font.width(self:word(row[1],row[4]))) end
 return 1,1,math.ceil((w+12)/8),#ROWS*2
end
function Storage:draw()
 local tx,ty,tw,th=self:rect()
 Font.drawBox(tx-1,ty-1,tw+2,th+2)
 love.graphics.setColor(1,1,1,1)
 for i,row in ipairs(ROWS) do
  local y=(ty*8)+(i-1)*16
  Font.draw(self:word(row[1],row[4]),tx*8+12,y)
  if self.index==i then Font.drawCode(require('src.ui.Theme').cursor,tx*8,y) end
 end
 local row=ROWS[self.index]
 Font.drawDialogueBox(1,18,29,6)   -- the field message window, (2, 19) 27 x 4
 local y=152
 for line in (self:word(row[2],row[5])..'\n'):gmatch('([^\n]*)\n') do
  Font.draw(line,16,y);y=y+16
  if y>168 then break end
 end
end
function Storage:touchpressed(_,px,py)
 local r=require('src.render.Renderer').uiPresentation;if not r then return false end
 local x,y=(px-r.x)/r.scaleX,(py-r.y)/r.scaleY
 local tx,ty,tw=self:rect()
 local i=math.floor((y-ty*8)/16)+1
 if x>=tx*8 and x<(tx+tw)*8 and i>=1 and i<=#ROWS then self.index=i;self:choose();return true end
 return false
end
return Storage
