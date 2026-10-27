-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Named imported sequences win; the shared cartridge UI constants retain
-- their edition-specific numbering even before an audio cache is mounted.
local S={}
local Version=require('src.core.GameVersion')
function S.resolve(id)
  if type(id)=='number'then return id end
  local Native=require('src.compat.gen1.NativeSession');local g=Native.game()
  if g then
    for _,song in pairs(g.data and g.data.audio and g.data.audio.songs or{})do
      if type(song)=='table'and song.sfxName==id then return song.index end
    end
  end
  return tonumber(id)or S[id]
end
setmetatable(S,{__index=function(_,key)
  if key=='SE_SUCCESS'then return Version.isFRLG()and 25 or 31 end
  if key=='SE_SELECT'then return 5 end
end})
return S
