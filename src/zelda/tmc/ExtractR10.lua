-- Round 10: small tables read from the player's ROM at import time
-- (manifest.r10).  Nothing here is shipped: each entry names the ROM
-- address it is read from.
local ExtractR10 = {}

function ExtractR10.run(rom, manifest)
  local t = {}
  -- cutsceneMiscObject.c gUnk_08122AF8: s8 x, y per animationState; the
  -- Type19 Octoroks index it with states 0..7 (8 pairs)
  t.rockOffsets = {}
  for i = 0, 7 do t.rockOffsets[i] = { rom:s8(0x08122AF8 + i * 2), rom:s8(0x08122AF8 + i * 2 + 1) } end
  -- npc4E.c gUnk_081141F4: tile positions (x + y * 64), 0-terminated
  t.fightTiles = {}
  for i = 0, 31 do
    local v = rom:u16(0x081141F4 + i * 2)
    if v == 0 then break end
    t.fightTiles[#t.fightTiles + 1] = v
  end
  -- NPCs whose C init starts a script from a table by type2 (no script in
  -- their EntityData): forestMinish.c gUnk_08109D18 (44 entries)
  t.npcScriptTables = { [0x03] = {} }
  for i = 0, 43 do t.npcScriptTables[0x03][i] = rom:u32(0x08109D18 + i * 4) end
  if ExtractR10.more then ExtractR10.more(rom, t) end
  manifest.r10 = t
end

return ExtractR10
