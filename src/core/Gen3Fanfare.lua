-- Native fanfare metadata remains independent of rendered PCM duration.
local Songs = require("src.core.Gen3SongIds")
local Fanfare = {}
local function entry(data, id)
  local metadata = data and data.constants and data.constants.gen3Fanfares
  local rows = metadata and metadata.fanfares
  if type(rows) ~= "table" then
    return nil, false
  end
  for _, row in pairs(rows) do
    if type(row) == "table" and tonumber(row.index) == id then
      return row, true
    end
  end
  return nil, true
end
function Fanfare.resolve(value)
  if type(value) == "string" then
    local hex = value:match("^SONG_(%x+)$")
    if hex then
      return tonumber(hex, 16)
    end
  end
  return Songs.resolve(value)
end
function Fanfare.info(data, value)
  local id = Fanfare.resolve(value)
  if type(id) ~= "number" then
    return nil
  end
  local row, haveTable = entry(data, id)
  if haveTable and not row then
    id = Songs.resolve("MUS_LEVEL_UP")
    row = entry(data, id)
  end
  local songs = data and data.audio and data.audio.songs
  local song = songs and songs[("SONG_%03X"):format(id)] or {}
  if type(song) ~= "table" then
    song = {}
  end
  return {
    id = id,
    frames = song.fanfareFrames or row and row.frames or 160,
    player = tonumber(song.player) or 2,
  }
end
function Fanfare.isSong(data, id)
  local songs = data and data.audio and data.audio.songs or {}
  local name = type(id) == "number" and Songs.nameOf(id) or id
  if name and songs[name] ~= nil then
    return false
  end
  local song = type(id) == "number" and songs[("SONG_%03X"):format(id)]
  return song and song.kind == "fanfare" or entry(data, id) ~= nil
end
return Fanfare
