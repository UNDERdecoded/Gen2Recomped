-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- The native summary reader already identifies these cartridge controls.
-- Keep a small import-only lookup independent of optional UI/language code.
local icons={[0]='A_BUTTON',[1]='B_BUTTON',[2]='L_BUTTON',[3]='R_BUTTON',
 [4]='START_BUTTON',[5]='SELECT_BUTTON',[6]='DPAD_UP',[7]='DPAD_DOWN',
 [8]='DPAD_LEFT',[9]='DPAD_RIGHT',[10]='DPAD_UPDOWN',[11]='DPAD_LEFTRIGHT',[12]='DPAD_ANY'}
-- Basic extended Latin bank in pret/pokefirered charmap.txt at
-- ce6406d8c2eaf46d543c8a2606de0c3cb1951982. IR keeps the original bank/code
-- so a renderer can draw that native cell rather than a Unicode substitute.
local symbols={[0]='↑',[1]='↓',[2]='←',[3]='→',[4]='+',
 [5]='Lv',[6]='PP',[7]='ID',[8]='№',[9]='_',
 [10]='①',[11]='②',[12]='③',[13]='④',[14]='⑤',[15]='⑥',[16]='⑦',[17]='⑧',[18]='⑨',
 [19]='(',[20]=')',[21]='◎',[22]='△',[23]='✕'}
-- English character facts in pret's pinned GBA charmaps. These punctuation
-- slots are absent from some native manifests; ordinary scan gates stay strict.
local punctuation={[0x5B]='%',[0x5C]='(',[0x5D]=')'}
local M={}
function M.literal(code)return punctuation[code]end
function M.read(kind,id)
 if kind==0xF8 and icons[id]then
  local token='{'..icons[id]..'}';return token,token
 end
 if kind==0xF9 then return symbols[id],symbols[id]end
end
return M
